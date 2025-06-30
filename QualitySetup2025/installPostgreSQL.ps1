<#
.SYNOPSIS
    Script de instalação do PostgreSQL com download automático e verificação de integridade
.DESCRIPTION
    Instala o PostgreSQL 12, cria banco de dados, restaura backup e insere dados na tabela empresa
.VERSION
    2.3
.AUTHOR
    © Janiel Borges
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$Porta,        # Porta do PostgreSQL
    
    [Parameter(Mandatory=$true)]
    [string]$CNPJ,         # CNPJ da empresa
    
    [Parameter(Mandatory=$true)]
    [string]$IDQ,          # IDQ
    
    [Parameter(Mandatory=$true)]
    [string]$NomeBanco,    # Nome do banco de dados

    [Parameter(Mandatory=$true)]
    [string]$Senha,        # Senha do postgreSQL
    
    [switch]$SkipHashCheck # Pular verificação de hash
)

# Alterar a política de execução para permitir a execução do script
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# =============================================
# VARIÁVEIS GLOBAIS
# =============================================
$dataDir = "C:\Program Files\PostgreSQL\12\data"
$installDir = "C:\Program Files\PostgreSQL\12"
$backupDir = "C:\Quality\instala"
$defaultBackup = "banco_limpo.sql"
$customBackupNames = @("banco.sql", "banco.backup")

# =============================================
# FUNÇÃO DE DOWNLOAD COM VERIFICAÇÃO DE HASH
# =============================================
function Download-PostgreSQL {
    param (
        [string]$DownloadPath = "$env:ProgramData\QualityTemp\instala",
        [switch]$SkipHashCheck
    )

    $installerName = "postgresql-12-windows-x64.exe"
    $installerPath = Join-Path -Path $DownloadPath -ChildPath $installerName
    $expectedHash = "0F7F6EDA581552AA697DD8FCA1D370F9B157DF501B229BD73AA42D08E36FC33E"
    $downloadUrl = "https://direct.janystech.com.br/postgres12.exe"

    # Verificar/Criar diretório
    if (-not (Test-Path -Path $DownloadPath)) {
        New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
        attrib +h +s "$DownloadPath"
    }

    Write-Host "`n-----------------------------------------------" -ForegroundColor Cyan
    Write-Host "          DOWNLOAD DO INSTALADOR POSTGRESQL      " -ForegroundColor Yellow
    Write-Host "-----------------------------------------------" -ForegroundColor Cyan
    Write-Host "• Tamanho estimado: ~330MB" -ForegroundColor Gray
    Write-Host "• Tempo estimado: 2-4 minutos (depende da conexão)" -ForegroundColor Gray
    Write-Host ""

    # Verificar se arquivo já existe e é válido
    if (Test-Path -Path $installerPath) {
        Write-Host "🔍 Arquivo local encontrado. Verificando integridade..." -ForegroundColor Cyan
        
        if (-not $SkipHashCheck) {
            try {
                $fileHash = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash
                if ($fileHash -eq $expectedHash) {
                    Write-Host "✔ Arquivo local é válido! Usando versão existente." -ForegroundColor Green
                    Write-Host "  Hash SHA256: $fileHash" -ForegroundColor DarkGray
                    return $installerPath
                } else {
                    Write-Host "⚠ Arquivo local corrompido. Baixando nova versão..." -ForegroundColor Yellow
                }
            } catch {
                Write-Host "⚠ Erro na verificação. Baixando nova versão..." -ForegroundColor Yellow
            }
        } else {
            Write-Host "⚠ Verificação de hash desativada. Usando arquivo existente." -ForegroundColor Yellow
            return $installerPath
        }
    }

    # Se chegou aqui, precisa baixar
    try {
        Write-Host "🌐 Conectando ao servidor..." -ForegroundColor Cyan
        
        # Configurações para o download
        $ProgressPreference = 'SilentlyContinue'
        $startTime = Get-Date
        $totalBytes = 330MB # Valor estimado

        # Barra de progresso manual
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFileAsync([Uri]$downloadUrl, $installerPath)

        while ($webClient.IsBusy) {
            $bytesReceived = (Get-Item $installerPath -ErrorAction SilentlyContinue).Length
            if ($bytesReceived -gt 0) {
                $percent = [math]::Min(100, [math]::Round(($bytesReceived / $totalBytes) * 100, 2))
                $filled = [math]::Round(25 * ($percent / 100))
                $bar = ("█" * $filled).PadRight(25, '░')
                Write-Host "`rProgresso: [$bar] $percent% " -NoNewline -ForegroundColor Cyan
            }
            Start-Sleep -Milliseconds 500
        }

        Write-Host "`r✅ Download concluído! [█████████████████████████] 100%" -ForegroundColor Green
        Write-Host "  ⏱️ Tempo total: $(([datetime]::Now - $startTime).ToString('mm\:ss'))" -ForegroundColor Gray

        # Verificação de hash pós-download
        if (-not $SkipHashCheck) {
            Verify-FileHash -FilePath $installerPath -ExpectedHash $expectedHash
        }

        return $installerPath

    } catch {
        Write-Host "`n❌ Erro no download: $($_.Exception.Message)" -ForegroundColor Red
        if (Test-Path $installerPath) { Remove-Item -Path $installerPath -Force }
        exit 5
    } finally {
        if ($webClient) { $webClient.Dispose() }
    }
}

function Verify-FileHash {
    param (
        [string]$FilePath,
        [string]$ExpectedHash
    )
    
    try {
        try {
            Write-Host "`n🔍 Verificando integridade do arquivo..." -ForegroundColor Cyan
        } catch {
            Write-Host "`n[VERIFICACAO] Verificando arquivo..." -ForegroundColor Cyan
        }
        
        $fileHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
        
        if ($fileHash -ne $ExpectedHash) {
            try {
                Write-Host "❌ Arquivo corrompido!" -ForegroundColor Red
            } catch {
                Write-Host "[ERRO] Arquivo corrompido!" -ForegroundColor Red
            }
            Write-Host "  Hash esperado: $ExpectedHash" -ForegroundColor Yellow
            Write-Host "  Hash obtido:  $fileHash" -ForegroundColor Yellow
            Remove-Item -Path $FilePath -Force
            exit 1
        }
        
        try {
            Write-Host "✔ Verificação concluída - Arquivo válido!" -ForegroundColor Green
        } catch {
            Write-Host "[SUCESSO] Arquivo válido!" -ForegroundColor Green
        }
        Write-Host "  Hash SHA256: $fileHash" -ForegroundColor DarkGray
        
    } catch {
        try {
            Write-Host "❌ Falha na verificação: $($_.Exception.Message)" -ForegroundColor Red
        } catch {
            Write-Host "[ERRO] Falha na verificacao: $($_.Exception.Message)" -ForegroundColor Red
        }
        exit 1
    }
}
# =============================================
# CONFIGURAÇÕES PRINCIPAIS
# =============================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
[System.Net.ServicePointManager]::DefaultConnectionLimit = 10

# =============================================
# CABEÇALHO DO SCRIPT
# =============================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       INSTALADOR POSTGRESQL ONLINE       " -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "CONFIGURAÇÕES DA INSTALAÇÃO:" -ForegroundColor Green
Write-Host ("• Porta PostgreSQL: " + $Porta) -ForegroundColor White
Write-Host ("• CNPJ: " + $CNPJ) -ForegroundColor White
Write-Host ("• IDQ: " + $IDQ) -ForegroundColor White
Write-Host ("• Banco de Dados: " + $NomeBanco) -ForegroundColor White
Write-Host ("• Senha PostgreSQL: " + $Senha) -ForegroundColor White
Write-Host ""

# =============================================
# EXECUÇÃO PRINCIPAL
# =============================================
try {
    # 1. Baixar ou verificar instalador
    $installerPath = Download-PostgreSQL -SkipHashCheck:$SkipHashCheck
    
    # 2. Instalar PostgreSQL
    Write-Host "🛠️ Instalando PostgreSQL..." -ForegroundColor Magenta
    Start-Process -FilePath $installerPath -ArgumentList @(
        "--mode unattended",
        "--prefix `"C:\Program Files\PostgreSQL\12`"",
        "--datadir `"C:\Program Files\PostgreSQL\12\data`"",
        "--superpassword $Senha",
        "--servicename postgresql-x64-12",
        "--serverport $Porta"
    ) -Wait

    # Verificar se o serviço está rodando
    Write-Host ""
    Write-Host "🔍 Verificando o status do serviço..." -ForegroundColor Cyan
    $service = Get-Service -Name "postgresql-x64-12" -ErrorAction SilentlyContinue

    if ($service -and $service.Status -eq "Running") {
        Write-Host "✔ Serviço do PostgreSQL está rodando com sucesso!" -ForegroundColor Green
    } else {
        Write-Host "❌ Erro: O serviço do PostgreSQL não está rodando." -ForegroundColor Red
        exit 1
    }

    Write-Host "🔄 Reiniciando o serviço do PostgreSQL..." -ForegroundColor Cyan
    Restart-Service -Name "postgresql-x64-12"

    $env:PGPASSWORD = $Senha

    # Verificar conexão com o PostgreSQL
    Write-Host ""
    Write-Host "🔍 Verificando conexão com o PostgreSQL..." -ForegroundColor Cyan
    try {
        & "$installDir\bin\psql.exe" -U postgres -h localhost -p $Porta -c "SELECT 1 AS connection_test;"
        if ($LASTEXITCODE -ne 0) {
            throw "Não foi possível conectar ao PostgreSQL"
        }
        Write-Host "✔ Conexão bem-sucedida!" -ForegroundColor Green
    } catch {
        Write-Host "❌ Falha na conexão com o PostgreSQL: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Verifique:" -ForegroundColor Yellow
        Write-Host "• O serviço está rodando" -ForegroundColor Yellow
        Write-Host "• A senha está correta" -ForegroundColor Yellow
        Write-Host "• A porta $Porta está configurada corretamente" -ForegroundColor Yellow
        exit 1
    }

    # Criar o banco de dados
    Write-Host ""
    Write-Host "🆕 Criando banco de dados $NomeBanco..." -ForegroundColor Cyan
    try {
        & "$installDir\bin\psql.exe" -U postgres -h localhost -p $Porta -c "CREATE DATABASE $NomeBanco;"
        if ($LASTEXITCODE -ne 0) {
            throw "Falha ao criar o banco de dados. Código de erro: $LASTEXITCODE"
        }
        Write-Host "✔ Banco de dados criado com sucesso!" -ForegroundColor Green
    } catch {
        Write-Host "❌ Erro ao criar o banco de dados: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Verifique:" -ForegroundColor Yellow
        Write-Host "• O serviço PostgreSQL está rodando" -ForegroundColor Yellow
        Write-Host "• A senha está correta" -ForegroundColor Yellow
        Write-Host "• A porta $Porta está acessível" -ForegroundColor Yellow
        exit 1
    }

    # Criar a role "suporte"
    Write-Host ""
    Write-Host "👤 Criando o usuário 'suporte'..." -ForegroundColor Cyan
    try {
        & "$installDir\bin\psql.exe" -U postgres -h localhost -p $Porta -c @"
CREATE ROLE suporte WITH
    NOSUPERUSER
    CREATEDB
    NOCREATEROLE
    INHERIT
    LOGIN
    NOREPLICATION
    NOBYPASSRLS
    CONNECTION LIMIT 10
    PASSWORD '$Senha'
    VALID UNTIL '2025-03-25 15:30:59-03';
"@
        if ($LASTEXITCODE -ne 0) {
            throw "Falha ao criar a role suporte. Código de erro: $LASTEXITCODE"
        }
        Write-Host "✔ Usuário 'suporte' criado com sucesso!" -ForegroundColor Green
    } catch {
        Write-Host "❌ Erro ao criar o usuário 'suporte': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    # ==================== SEÇÃO DE RESTAURAÇÃO ====================
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           OPÇÕES DE RESTAURAÇÃO              ║" -ForegroundColor Yellow
    Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "┌──────────────────────────────────────────────┐" -ForegroundColor Blue
    Write-Host "│  🔵 1 - BANCO NOVO (PADRÃO)                  │" -ForegroundColor Blue
    Write-Host "│                                              │" -ForegroundColor Blue
    Write-Host "│  • Instala um banco limpo (banco_limpo.sql)  │" -ForegroundColor White
    Write-Host "│  • Inclui dados iniciais da empresa          │" -ForegroundColor White
    Write-Host "│                                              │" -ForegroundColor Blue
    Write-Host "│  🟢 2 - RESTAURAR BACKUP EXISTENTE           │" -ForegroundColor Green
    Write-Host "│                                              │" -ForegroundColor Green
    Write-Host "│  • Usa seu próprio arquivo de backup         │" -ForegroundColor White
    Write-Host "│  • Não altera dados existentes               │" -ForegroundColor White
    Write-Host "└──────────────────────────────────────────────┘" -ForegroundColor Blue
    Write-Host ""

    Write-Host "📝 INSTRUÇÕES PARA BACKUP PERSONALIZADO:" -ForegroundColor Magenta
    Write-Host " 1. Coloque seu arquivo em: C:\Quality\instala\" -ForegroundColor Gray
    Write-Host " 2. Nomeie como: " -NoNewline
    Write-Host "banco.sql" -ForegroundColor Yellow -NoNewline
    Write-Host " ou " -NoNewline
    Write-Host "banco.backup" -ForegroundColor Yellow
    Write-Host " 3. Certifique-se que é um backup PostgreSQL válido" -ForegroundColor Gray
    Write-Host ""

    do {
        $opcao = Read-Host "👉 Digite sua escolha (1 ou 2)"
        if ($opcao -notin @('1','2')) {
            Write-Host "❌ Opção inválida! Por favor, digite 1 ou 2" -ForegroundColor Red
        }
    } while ($opcao -notin @('1','2'))

    $usandoBackupPersonalizado = $opcao -eq "2"

    if ($usandoBackupPersonalizado) {
        Write-Host ""
        Write-Host "🔍 Procurando arquivo de backup personalizado..." -ForegroundColor Cyan
    }

    if ($usandoBackupPersonalizado) {
    $backupFile = $null
    foreach ($name in $customBackupNames) {
        $path = Join-Path -Path $backupDir -ChildPath $name
        if (Test-Path -Path $path) {
            $backupFile = $path
            break
        }
    }

    if (-not $backupFile) {
        Write-Host "❌ Nenhum arquivo personalizado encontrado em $backupDir" -ForegroundColor Red
        Write-Host "⚠ Usando o banco padrão ($defaultBackup) como fallback." -ForegroundColor Yellow
        $backupFile = Join-Path -Path $backupDir -ChildPath $defaultBackup
        $usandoBackupPersonalizado = $false
    }
} else {
    $backupFile = Join-Path -Path $backupDir -ChildPath $defaultBackup
}

# Verifica se o arquivo de backup existe
if (-not (Test-Path -Path $backupFile)) {
    Write-Host "❌ Erro: Arquivo de backup não encontrado em $backupFile" -ForegroundColor Red
    exit 1
}

# Lê os primeiros bytes para identificar o formato REAL
$stream = [System.IO.File]::OpenRead($backupFile)
try {
    $header = New-Object byte[] 5
    $bytesRead = $stream.Read($header, 0, 5)
    $headerStr = -join ($header | ForEach-Object { [char]$_ })
    $isBinaryBackup = $headerStr -match 'PGDMP'
}
finally {
    $stream.Close()
}

Write-Host ""
Write-Host "🔄 Restaurando o banco de dados $NomeBanco a partir de $backupFile..." -ForegroundColor Cyan

try {
    if ($isBinaryBackup) {
        Write-Host "🔍 Formato detectado: BINÁRIO (usando pg_restore)" -ForegroundColor Blue
    } else {
        Write-Host "🔍 Formato detectado: TEXTO (usando psql)" -ForegroundColor Blue
    }

    $backupSizeBytes = (Get-Item $backupFile).Length
    $backupSizeMB = $backupSizeBytes / 1MB

    if ($backupSizeMB -ge 1024) {
        $backupSizeDisplay = "$([math]::Round($backupSizeMB / 1024, 2)) GB ($([math]::Round($backupSizeMB)) MB)"
    } else {
        $backupSizeDisplay = "$([math]::Round($backupSizeMB, 2)) MB"
    }
    $estimatedTime = [TimeSpan]::FromMinutes($backupSizeMB / $(if ($isBinaryBackup) { 40 } else { 20 }))

    Write-Host "🔄 Restaurando backup ($backupSizeDisplay - Tempo estimado: $($estimatedTime.ToString('mm\:ss')))" -ForegroundColor Cyan
    
    # Barra de progresso otimizada
    $progressTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $lastUpdate = [System.Diagnostics.Stopwatch]::StartNew()
    $lastPercent = 0
    
    # Executar o restore em um job
    $restoreJob = Start-Job -ScriptBlock {
        param($installDir, $Porta, $NomeBanco, $backupFile, $isBinaryBackup)
        
        if ($isBinaryBackup) {
            & "$installDir\bin\pg_restore.exe" -U postgres -h localhost -p $Porta -d $NomeBanco -F c "$backupFile" 2>&1
        } else {
            & "$installDir\bin\psql.exe" -U postgres -h localhost -p $Porta -d $NomeBanco -f "$backupFile" 2>&1
        }
    } -ArgumentList $installDir, $Porta, $NomeBanco, $backupFile, $isBinaryBackup
    
    # Mostrar progresso
    while ($restoreJob.State -eq 'Running') {
        $elapsedRatio = $progressTimer.Elapsed.TotalMilliseconds / $estimatedTime.TotalMilliseconds
        $currentPercent = [math]::Min(99, [int]($elapsedRatio * 100))
        
        if ($lastUpdate.ElapsedMilliseconds -ge 500 -or $currentPercent -gt $lastPercent) {
            $remainingTime = $estimatedTime - $progressTimer.Elapsed
            $bar = ("█" * ($currentPercent / 2)).PadRight(50, '░')
            Write-Host "`r[$bar] $currentPercent% (Restante: $($remainingTime.ToString('mm\:ss')))" -NoNewline -ForegroundColor Cyan
            $lastPercent = $currentPercent
            $lastUpdate.Restart()
        }
        Start-Sleep -Milliseconds 100
    }
    
    # Finalização
    $realTime = $progressTimer.Elapsed
    $realSpeed = [math]::Round($backupSizeMB / $realTime.TotalMinutes, 1)
    Write-Host "`r[██████████████████████████████████████████████████] 100% (Concluído em $($realTime.ToString('mm\:ss')) - $realSpeed MB/min)" -ForegroundColor Green
    
    # Capturar erros
    $errorLog = Receive-Job $restoreJob
    $errorLog | Where-Object { $_ -match "error|warning|falha|aviso|failed" -and $_ -notmatch "already exists|já existe" } | ForEach-Object {
        Write-Host "⚠️ AVISO: $_" -ForegroundColor Yellow
    }
    
    Remove-Job $restoreJob
    $LASTEXITCODE = 0

    # Verificação do resultado
    if ($usandoBackupPersonalizado) {
        Write-Host "✅ Restauração personalizada concluída" -ForegroundColor Green
    } elseif ($LASTEXITCODE -ne 0) {
        throw "Falha na restauração do backup padrão"
    } else {
        Write-Host "✅ Banco de dados restaurado com sucesso!" -ForegroundColor Green
    }
}
catch {
    if ($usandoBackupPersonalizado) {
        Write-Host "⚠️ AVISO: $($_.Exception.Message)" -ForegroundColor Yellow
    } else {
        Write-Host "❌ ERRO: Falha na restauração:" -ForegroundColor Red
        Write-Host "$($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Verifique:" -ForegroundColor White
        Write-Host "• O arquivo de backup" -ForegroundColor Yellow
        Write-Host "• A conexão com o PostgreSQL" -ForegroundColor Yellow
        Write-Host "• As permissões do usuário" -ForegroundColor Yellow
        exit 1
    }
}

# Inserção na tabela empresa (apenas para backup padrão)
if (-not $usandoBackupPersonalizado) {
    Write-Host ""
    Write-Host "📝 Configurando dados da empresa..." -ForegroundColor Cyan
    & "$installDir\bin\psql.exe" -U postgres -h localhost -p $Porta -d $NomeBanco -c @"
INSERT INTO empresa (CNPJ, IDQ, IDEMPRESA) VALUES ('$CNPJ', '$IDQ', '1');
"@
} else {
    Write-Host ""
    Write-Host "⏭ Dados da tabela empresa preservados (backup personalizado selecionado)" -ForegroundColor Yellow
}

    # Mensagem final
    if ($LASTEXITCODE -eq 0 -and ($service.Status -eq 'Running')) {
        Write-Host ""
        Write-Host "====================================================" -ForegroundColor Green
        Write-Host "✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!" -ForegroundColor Green
        Write-Host "====================================================" -ForegroundColor Green
        exit 0
    }
    elseif ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "====================================================" -ForegroundColor Red
        Write-Host "⚠️ INSTALAÇÃO CONCLUÍDA COM AVISOS" -ForegroundColor Yellow
        Write-Host "====================================================" -ForegroundColor Red
        Write-Host "O PostgreSQL foi instalado corretamente, mas ocorreram" -ForegroundColor White
        Write-Host "problemas na restauração do backup padrão." -ForegroundColor White
        Write-Host "Verifique o banco de dados manualmente se necessário." -ForegroundColor White
        exit 0
    }
    else {
        exit 1
    }
}
catch {
    Write-Host "❌ ERRO CRÍTICO: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}