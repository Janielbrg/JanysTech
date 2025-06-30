<#
.SYNOPSIS
Script de atualização automática com tratamento robusto de erros e barra de progresso

.DESCRIPTION
Versão completamente revisada com proteção contra valores nulos em todas as operações
e interface de progresso durante o download
#>

param(
    [string]$CurrentVersion,
    [string]$InstallerPath,
    [string]$TempFolder = "$env:ProgramData\QualityTemp"
)

# Carrega os assemblies necessários para a interface gráfica
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Habilita estilos visuais para a aplicação
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetHighDpiMode([System.Windows.Forms.HighDpiMode]::PerMonitorV2)

$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

if ([Environment]::OSVersion.Version -ge [Version]"6.2") {
    [System.Windows.Forms.Application]::SetHighDpiMode([System.Windows.Forms.HighDpiMode]::PerMonitorV2)
}

# Função auxiliar para verificação segura de objetos
function Test-NotNull {
    param($Object)
    return ($null -ne $Object) -and ($Object -isnot [System.DBNull])
}

# Função para validação de versão
function Get-ValidVersion {
    param([string]$VersionString)
    try {
        if ([string]::IsNullOrWhiteSpace($VersionString)) { return $null }
        
        $cleanVersion = $VersionString.Trim() -replace '[^\d.]', ''
        if ($cleanVersion -match '^\d+(\.\d+){1,3}$') {
            return [Version]$cleanVersion
        }
        return $null
    } catch {
        return $null
    }
}

# Configuração inicial
$ErrorActionPreference = 'Stop'
$LogPath = "$TempFolder\QualityUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:downloadCancelled = $false
$global:webClient = $null
$global:progressForm = $null

# Função de log segura
function Write-Log {
    param([string]$message)
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $message" | Out-File -FilePath $LogPath -Append -Encoding UTF8
    } catch {
        # Fallback silencioso se não puder escrever no log
    }
}

# Carregar assemblies com verificação
function Safe-LoadAssembly {
    param([string]$AssemblyName)
    try {
        if (-not [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -like "$AssemblyName,*" }) {
            Add-Type -AssemblyName $AssemblyName -ErrorAction Stop
        }
        return $true
    } catch {
        Write-Log "FALHA AO CARREGAR ASSEMBLY $AssemblyName : $($_.Exception.Message)"
        return $false
    }
}

# Carregar assemblies necessários
if (-not (Safe-LoadAssembly "System.Windows.Forms") -or -not (Safe-LoadAssembly "System.Drawing")) {
    [System.Windows.Forms.MessageBox]::Show("Falha ao carregar componentes necessários", "Erro Crítico", "OK", "Error")
    exit 1
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# Interface de progresso com verificação completa
function Show-ProgressDialog {
    try {
        # Criação do formulário principal otimizado
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Atualizando QualitySetup2025"
        $form.Size = New-Object System.Drawing.Size(480, 250)  # Tamanho um pouco menor
        $form.StartPosition = "CenterScreen"
        $form.FormBorderStyle = "FixedDialog"
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.ControlBox = $false
        $form.BackColor = [System.Drawing.Color]::White  # Fundo branco puro para melhor performance
        $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)  # Fonte padrão menor

        # Cabeçalho simplificado (sem gradiente para melhor performance)
        $headerPanel = New-Object System.Windows.Forms.Panel
        $headerPanel.Location = New-Object System.Drawing.Point(0, 0)
        $headerPanel.Size = New-Object System.Drawing.Size($form.Width, 50)  # Mais compacto
        $headerPanel.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)  # Azul mais vibrante
        $form.Controls.Add($headerPanel)

        # Título moderno
        $labelTitle = New-Object System.Windows.Forms.Label
        $labelTitle.Location = New-Object System.Drawing.Point(15, 15)
        $labelTitle.Size = New-Object System.Drawing.Size(450, 25)
        $labelTitle.Text = "ATUALIZAÇÃO QUALITY-SETUP-2025"
        $labelTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $labelTitle.ForeColor = [System.Drawing.Color]::White
        $headerPanel.Controls.Add($labelTitle)

        # Barra de progresso otimizada
        $progressBar = New-Object System.Windows.Forms.ProgressBar
        $progressBar.Location = New-Object System.Drawing.Point(20, 70)
        $progressBar.Size = New-Object System.Drawing.Size(440, 23)  # Largura maior
        $progressBar.Style = "Continuous"
        $progressBar.ForeColor = [System.Drawing.Color]::FromArgb(0, 150, 215)
        $form.Controls.Add($progressBar)

        # Status do download com melhor contraste
        $statusLabel = New-Object System.Windows.Forms.Label
        $statusLabel.Location = New-Object System.Drawing.Point(20, 100)
        $statusLabel.Size = New-Object System.Drawing.Size(440, 20)
        $statusLabel.Text = "Preparando download..."
        $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(50, 50, 50)  # Mais escuro
        $form.Controls.Add($statusLabel)

        # Mensagem de status adicional (mais visível)
        $detailsLabel = New-Object System.Windows.Forms.Label
        $detailsLabel.Location = New-Object System.Drawing.Point(20, 125)
        $detailsLabel.Size = New-Object System.Drawing.Size(440, 40)
        $detailsLabel.Text = "Por favor, aguarde enquanto a nova versão é baixada."
        $detailsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
        $detailsLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)  # Contraste melhorado
        $form.Controls.Add($detailsLabel)

        # Botão Cancelar otimizado
        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Location = New-Object System.Drawing.Point(180, 170)  # Posição ajustada
        $cancelButton.Size = New-Object System.Drawing.Size(120, 35)  # Mais compacto
        $cancelButton.Text = "Cancelar"
        $cancelButton.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
        $cancelButton.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
        $cancelButton.FlatStyle = "Standard"  # Melhor performance que Flat
        $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $cancelButton.Cursor = [System.Windows.Forms.Cursors]::Hand

        # Configuração do evento de clique do botão (mantido igual)
        $cancelButton.Add_Click({
            $script:downloadCancelled = $true
            
            try {
                if ($global:webClient -ne $null -and $global:webClient.IsBusy) {
                    $global:webClient.CancelAsync()
                    Write-Log "Download cancelado a pedido do usuário"
                }
            } catch {
                Write-Log "ERRO AO CANCELAR: $($_.Exception.Message)"
            }
            
            try {
                if ($this.Parent -ne $null -and $this.Parent.IsHandleCreated) {
                    $this.Parent.Close()
                }
            } catch {
                Write-Log "ERRO AO FECHAR FORMULÁRIO: $($_.Exception.Message)"
            }
        })

        $form.Controls.Add($cancelButton)
        
        # Otimização de performance
        $form.SuspendLayout()
        $form.ResumeLayout($false)
        $form.PerformLayout()

        $form.Topmost = $true
        $form.Add_Shown({ $this.Activate() })

        return @{
            Form = $form
            ProgressBar = $progressBar
            StatusLabel = $statusLabel
        }
    } catch {
        Write-Log "ERRO AO CRIAR DIÁLOGO: $($_.Exception.Message)"
        return $null
    }
}

# Função principal de download
function Download-FileWithProgress {
    param(
        [string]$url,
        [string]$outputFile,
        [System.Windows.Forms.ProgressBar]$progressBar,
        [System.Windows.Forms.Label]$statusLabel
    )
    
    $global:webClient = $null
    $script:downloadCancelled = $false

    try {
        $global:webClient = New-Object System.Net.WebClient
        # Garantir que o formulário está visível
        if (-not $global:progressForm.Visible) {
            $global:progressForm.Show()
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 300
        }

        # Limpar arquivo existente
        if (Test-Path $outputFile) {
            Remove-Item $outputFile -Force -ErrorAction Stop
        }

        # Obter tamanho do arquivo
        $request = [System.Net.HttpWebRequest]::Create($url)
        $request.Timeout = 30000 # 30 segundos
        $response = $request.GetResponse()
        $totalBytes = $response.ContentLength
        $response.Close()

        if ($totalBytes -eq -1) {
            throw "Não foi possível obter o tamanho do arquivo"
        }

        # Configurar a requisição de download
        $request = [System.Net.HttpWebRequest]::Create($url)
        $request.Timeout = [System.Threading.Timeout]::Infinite # Sem timeout

        # Obter a resposta
        $response = $request.GetResponse()
        $responseStream = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create($outputFile)

        # Buffer de download
        $buffer = New-Object byte[] 16KB
        $totalRead = 0
        $lastUpdate = [DateTime]::Now
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        # Loop de download
        while ($true) {
            # Verificar cancelamento
            if ($script:downloadCancelled) {
                throw "Download cancelado pelo usuário"
            }

            # Ler dados
            $read = $responseStream.Read($buffer, 0, $buffer.Length)
            if ($read -eq 0) { break }

            # Escrever no arquivo
            $fileStream.Write($buffer, 0, $read)
            $totalRead += $read

            # Atualizar progresso (não mais que 10 vezes por segundo)
            if (([DateTime]::Now - $lastUpdate).TotalMilliseconds -gt 100) {
                $percent = [math]::Round(($totalRead / $totalBytes) * 100)
                $global:progressForm.Invoke([action]{
                    $progressBar.Value = $percent
                    $statusLabel.Text = "Baixando: $percent% ($([math]::Round($totalRead/1MB, 2))MB/$([math]::Round($totalBytes/1MB, 2))MB)"
                })
                $lastUpdate = [DateTime]::Now
            }

            [System.Windows.Forms.Application]::DoEvents()
        }

        # Finalização
        $fileStream.Close()
        $responseStream.Close()
        $response.Close()

        return $true
    } catch {
        Write-Log "ERRO NO DOWNLOAD: $($_.Exception.Message)"
        if ($fileStream) { $fileStream.Close() }
        if ($responseStream) { $responseStream.Close() }
        if ($response) { $response.Close() }
        if (Test-Path $outputFile) { Remove-Item $outputFile -Force }
        throw $_
    }
}

# Função para encerrar processos do instalador
function Kill-InstallerProcesses {
    param([string]$installerPath)
    
    try {
        if (-not (Test-Path $installerPath)) {
            Write-Log "Arquivo do instalador não encontrado: $installerPath"
            return $false
        }

        $processName = [System.IO.Path]::GetFileNameWithoutExtension($installerPath)
        $maxAttempts = 3
        $attempt = 1
        $success = $false
        
        # --------------------------------------------
        # MÉTODO PRINCIPAL (sua solução que funcionou)
        # --------------------------------------------
        while ($attempt -le $maxAttempts -and -not $success) {
            Write-Log "Tentativa $attempt (Método WMI + API Windows)..."
            
            try {
                # 1. Encerramento via WMI (o mais robusto)
                Get-WmiObject Win32_Process | Where-Object { 
                    $_.Name -like "*$processName*" -or 
                    $_.ExecutablePath -like "*$processName*"
                } | ForEach-Object {
                    $_.Terminate()
                    Write-Log "Processo $($_.ProcessId) encerrado via WMI"
                }

                # 2. Liberação via API do Windows
                Add-Type @"
                using System;
                using System.Runtime.InteropServices;
                public class FileUnlocker {
                    [DllImport("kernel32.dll")] 
                    public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);
                }
"@
                [FileUnlocker]::MoveFileEx($installerPath, $null, 4) # MOVEFILE_DELAY_UNTIL_REBOOT

                # Verificação
                $fileStream = [System.IO.File]::Open($installerPath, 'Open', 'Read', 'None')
                $fileStream.Close()
                $success = $true
                Write-Log "Arquivo desbloqueado com sucesso (Método Principal)"
                
            } catch {
                Write-Log "Falha no método principal: $($_.Exception.Message)"
                $attempt++
                Start-Sleep -Seconds 2
            }
        }

        # --------------------------------------------
        # FALLBACK 1: Métodos tradicionais (nome + caminho)
        # --------------------------------------------
        if (-not $success) {
            Write-Log "Iniciando fallback: métodos tradicionais..."
            try {
                # 1. Por nome do processo
                $processesByName = Get-Process -Name $processName -ErrorAction SilentlyContinue
                if ($processesByName) {
                    $processesByName | Stop-Process -Force
                    Write-Log "Encerrados $($processesByName.Count) processos por nome"
                }

                # 2. Por caminho do executável
                Get-Process | Where-Object { 
                    $_.Path -and $_.Path -like "*$processName*" -and $_.Path -ne $installerPath
                } | Stop-Process -Force

                # Verificação
                $fileStream = [System.IO.File]::Open($installerPath, 'Open', 'Read', 'None')
                $fileStream.Close()
                $success = $true
                Write-Log "Arquivo desbloqueado via fallback tradicional"
                
            } catch {
                Write-Log "Falha no fallback tradicional: $($_.Exception.Message)"
            }
        }

        # --------------------------------------------
        # FALLBACK 2: Taskkill (como último recurso)
        # --------------------------------------------
        if (-not $success) {
            Write-Log "Iniciando fallback final: taskkill..."
            try {
                $currentPID = $PID
                & taskkill /F /IM "$processName.exe" /T /FI "PID ne $currentPID" 2>&1 | Out-Null
                Write-Log "Comando taskkill executado"

                # Verificação final
                $fileStream = [System.IO.File]::Open($installerPath, 'Open', 'Read', 'None')
                $fileStream.Close()
                $success = $true
                Write-Log "Arquivo desbloqueado via taskkill"
                
            } catch {
                Write-Log "Falha no taskkill: $($_.Exception.Message)"
            }
        }

        return $true
        
    } catch {
        Write-Log "ERRO GERAL: $($_.Exception.Message)"
        return $false
    }
}

# EXECUÇÃO PRINCIPAL
try {
    Write-Log "=== INÍCIO DO PROCESSO ==="
    Write-Log "Versão atual: $CurrentVersion"
    Write-Log "Caminho do instalador: $InstallerPath"

    # Validar versão atual
    $currentVer = Get-ValidVersion $CurrentVersion
    if (-not $currentVer) {
        [System.Windows.Forms.MessageBox]::Show(
            "Versão atual no formato inválido. Use o formato X.Y.Z ou X.Y.Z.W",
            "Erro de Versão",
            "OK",
            "Error"
        )
        exit 1
    }

    if (-not (Test-Path $TempFolder)) {
        New-Item -Path $TempFolder -ItemType Directory -Force | Out-Null
        attrib +h +s "$TempFolder"
    }

    # Obter versão do servidor
    $VersionURL = "https://direct.janystech.com.br/version.txt"
    try {
        $response = Invoke-WebRequest -Uri $VersionURL -UseBasicParsing -ErrorAction Stop
        $rawContent = $response.Content.Trim()
        Write-Log "Resposta bruta do servidor: '$rawContent'"
        
        $latestVer = Get-ValidVersion $rawContent
        if (-not $latestVer) {
            throw "Formato de versão inválido recebido do servidor: '$rawContent'"
        }
        
        Write-Log "Versão do servidor validada: $($latestVer.ToString())"
    } catch {
        Write-Log "ERRO AO OBTER VERSÃO: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
        "Não foi possível verificar atualizações`n`n" +
        "Verifique:`n" +
        "✓ Sua conexão com a internet`n" +
        "✓ A disponibilidade do servidor de atualizações`n`n" +
        "Código do erro: UPD-0042`n`n" +
        "Entre em contato com o suporte técnico caso o problema persista.",
        "Erro de Atualização",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
        exit 2
    }

    # Comparar versões
    if ($latestVer -gt $currentVer) {
    Write-Log "Atualização disponível: $currentVer -> $latestVer"

    

    # Verificação final do conteúdo (para debug)
    Write-Output "[DEBUG] Conteúdo da mensagem:`n$updateMessage"

    # Código original (não alterado)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Configuração segura do formulário principal
$updateForm = New-Object System.Windows.Forms.Form
$updateForm.Text = "Atualização QualitySetup2025"
$updateForm.ClientSize = New-Object System.Drawing.Size(450, 300)  # Tamanho fixo sem cálculos
$updateForm.StartPosition = "CenterScreen"
$updateForm.BackColor = [System.Drawing.Color]::White
$updateForm.FormBorderStyle = "FixedDialog"

# Cabeçalho moderno simplificado
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Size = New-Object System.Drawing.Size($updateForm.Width, 60)
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)  # Azul sólido
$headerPanel.Dock = [System.Windows.Forms.DockStyle]::Top

# Título principal
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "ATUALIZAÇÃO DISPONÍVEL"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.Location = New-Object System.Drawing.Point(20, 15)
$titleLabel.AutoSize = $true
$headerPanel.Controls.Add($titleLabel)

# Conteúdo principal - versões (sem operações matemáticas)
$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Text = "Versão atual: $($currentVer.ToString())`nNova versão: $($latestVer.ToString())"
$versionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$versionLabel.Location = New-Object System.Drawing.Point(20, 70)
$versionLabel.AutoSize = $true
$updateForm.Controls.Add($versionLabel)

# Melhorias
$improvementsLabel = New-Object System.Windows.Forms.Label
$improvementsLabel.Text = "Melhorias:`n• Melhor desempenho`n• Novos recursos"
$improvementsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$improvementsLabel.Location = New-Object System.Drawing.Point(20, 120)
$improvementsLabel.AutoSize = $true
$updateForm.Controls.Add($improvementsLabel)

# Contador regressivo
$countdownLabel = New-Object System.Windows.Forms.Label
$countdownLabel.Text = "A atualização começará em 7 segundos..."
$countdownLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$countdownLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 150, 215)
$countdownLabel.Location = New-Object System.Drawing.Point(20, 180)
$countdownLabel.AutoSize = $true
$updateForm.Controls.Add($countdownLabel)

# Botão Cancelar com posição fixa (sem cálculos de divisão)
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "Cancelar"
$cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$cancelButton.ForeColor = [System.Drawing.Color]::White
$cancelButton.BackColor = [System.Drawing.Color]::FromArgb(220, 80, 80)
$cancelButton.Size = New-Object System.Drawing.Size(120, 35)
$cancelButton.Location = New-Object System.Drawing.Point(165, 230)  # Posição fixa centralizada
$cancelButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cancelButton.FlatAppearance.BorderSize = 0
$updateForm.Controls.Add($cancelButton)

# Adicionar cabeçalho ao formulário
$updateForm.Controls.Add($headerPanel)

# Lógica de funcionamento
$script:countdownCanceled = $false

$cancelButton.Add_Click({
    $script:countdownCanceled = $true
    Write-Log "Atualização cancelada pelo usuário"
    
    try {
        # Fecha o formulário de forma segura
        if ($updateForm -ne $null -and $updateForm.Visible) {
            $updateForm.Close()
            $updateForm.Dispose()
        }
    } catch {
        Write-Log "Erro ao fechar formulário: $($_.Exception.Message)"
    }
    
    # Encerra o script imediatamente sem exceções
    [System.Environment]::Exit(3)  # Força saída limpa (sem erros do .NET)
})

# SEÇÃO FINAL SEGURA (sem operações matemáticas)
$updateForm.Add_Shown({ $updateForm.Activate() })
$updateForm.Show()

$secondsLeft = 10
while ($secondsLeft -gt 0 -and -not $script:countdownCanceled) {
    $countdownLabel.Text = "A atualização começará em $secondsLeft segundos..."
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Seconds 1
    $secondsLeft--
}

$updateForm.Close()

if (-not $script:countdownCanceled) {
    Write-Host "Contagem regressiva concluída - iniciando atualização..."
    # Seu código de atualização aqui
    
            
            # Encerrar processos do instalador
            if (-not (Kill-InstallerProcesses $InstallerPath)) {
                # Mensagem no console (para logs visíveis em execução manual)
                Write-Host "ERRO: Não foi possível encerrar os processos do instalador em $InstallerPath." -ForegroundColor Red
                Write-Host "Ação necessária: Feche manualmente o QualitySetup2025.exe e execute o script novamente." -ForegroundColor Yellow

                # Caixa de diálogo gráfica (para usuários com interface)
                [System.Windows.Forms.MessageBox]::Show(
                    "Não foi possível liberar o arquivo do instalador.`n`nFeche manualmente o 'QualitySetup2025.exe' no Gerenciador de Tarefas e tente novamente.",
                    "Erro - Atualização Interrompida",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                exit 1
            }

            # Configurar interface de progresso
            $progressUI = Show-ProgressDialog
            if (-not $progressUI) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Falha ao criar janela de progresso.",
                    "Erro",
                    "OK",
                    "Error"
                )
                exit 1
            }

            $global:progressForm = $progressUI.Form
            $progressBar = $progressUI.ProgressBar
            $statusLabel = $progressUI.StatusLabel

        # Download da nova versão
$TempInstaller = "$TempFolder\QualitySetup2025_$($latestVer.ToString()).exe"
$downloadURL = "https://direct.janystech.com.br/QualitySetup2025.exe"

try {
    # Mostrar o formulário primeiro
    $global:progressForm.Show()
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 300

    # Chamada da função de download
    $downloadSuccess = $false
    $downloadSuccess = Download-FileWithProgress -url $downloadURL -outputFile $TempInstaller -progressBar $progressBar -statusLabel $statusLabel
    
    if (-not $downloadSuccess) {
        if ($script:downloadCancelled) {
            [System.Windows.Forms.MessageBox]::Show(
                "Atualização cancelada pelo usuário.",
                "Atualização Cancelada",
                "OK",
                "Information"
            )
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Falha no download da atualização. Verifique sua conexão e tente novamente.",
                "Erro de Download",
                "OK",
                "Error"
            )
        }
        exit 1
    }

        # Substituir instalador com limpeza do arquivo .old
        try {
            $oldInstaller = "$InstallerPath.old"
            
            # 1. Tentar remover arquivo .old existente (se houver)
            if (Test-Path $oldInstaller) {
                try {
                    Remove-Item $oldInstaller -Force -ErrorAction Stop
                    Write-Log "Arquivo .old anterior removido: $oldInstaller"
                } catch {
                    Write-Log "AVISO: Não foi possível remover arquivo .old existente: $($_.Exception.Message)"
                }
            }

            # 2. Renomear instalador atual para .old
            Rename-Item -Path $InstallerPath -NewName "$([System.IO.Path]::GetFileName($InstallerPath)).old" -Force -ErrorAction Stop
            Write-Log "Instalador atual renomeado para: $InstallerPath.old"

            # 3. Mover novo instalador para o local correto
            Move-Item -Path $TempInstaller -Destination $InstallerPath -Force -ErrorAction Stop
            Write-Log "Novo instalador movido para: $InstallerPath"

            # 4. Fechar a janela de progresso antes de iniciar o instalador
            try {
                if (Test-NotNull $global:progressForm) {
                    $global:progressForm.Close()
                    $global:progressForm.Dispose()
                    $global:progressForm = $null
                }
            } catch {
                Write-Log "ERRO AO FECHAR FORMULÁRIO: $($_.Exception.Message)"
            }

            # 5. Iniciar novo instalador e aguardar
            $installProcess = Start-Process -FilePath $InstallerPath -PassThru
            Write-Log "Novo instalador iniciado (PID: $($installProcess.Id))"
            
            # 6. Aguardar processo terminar e então limpar o .old
            try {
                $installProcess | Wait-Process -ErrorAction Stop
                Write-Log "Instalação concluída com sucesso"
                
                # Tentar remover o .old após instalação
                Start-Sleep -Seconds 2  # Espera para garantir que o sistema liberou o arquivo
                if (Test-Path $oldInstaller) {
                    Remove-Item $oldInstaller -Force -ErrorAction Stop
                    Write-Log "Arquivo .old removido com sucesso: $oldInstaller"
                }
            } catch {
                Write-Log "AVISO: Não foi possível aguardar término do instalador: $($_.Exception.Message)"
            }

            exit 0
        } catch {
            Write-Log "ERRO NA SUBSTITUIÇÃO: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show(
                "Falha ao substituir o instalador. Tente executar como administrador.",
                "Erro de Instalação",
                "OK",
                "Error"
            )
            exit 1
        }
        
    } finally {
        try {
            if (Test-NotNull $global:progressForm) {
                $global:progressForm.Close()
                $global:progressForm.Dispose()
                $global:progressForm = $null
            }
        } catch {
            Write-Log "ERRO AO FECHAR FORMULÁRIO: $($_.Exception.Message)"
        }
    }
} else {
    Write-Log "Atualização recusada pelo usuário"
    exit 2
}

# ESTA PARTE É ESSENCIAL - NÃO REMOVER!
} else {
    Write-Log "Nenhuma atualização necessária"
    exit 0
}
} catch {
    Write-Log "ERRO CRÍTICO: $($_.Exception.Message)"
    Write-Log "STACK TRACE: $($_.ScriptStackTrace)"
    [System.Windows.Forms.MessageBox]::Show(
        "Erro crítico durante a atualização: $($_.Exception.Message)",
        "Erro",
        "OK",
        "Error"
    )
    exit 1
} finally {
    try {
        if (Test-NotNull $global:progressForm) {
            $global:progressForm.Dispose()
        }
        if (Test-NotNull $global:webClient) {
            $global:webClient.Dispose()
        }
    } catch {
        Write-Log "ERRO AO LIBERAR RECURSOS: $($_.Exception.Message)"
    }
}

Write-Log "=== FIM DO PROCESSO ==="
exit 0