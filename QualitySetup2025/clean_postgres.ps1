<#
.SYNOPSIS
    Remove COMPLETAMENTE o PostgreSQL 12 com exclusão direta do registro
#>

$ErrorActionPreference = "Stop"
$logPath = Join-Path $env:TEMP "PostgreSQL_Removal.log"

function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $message" | Out-File -FilePath $logPath -Append
}

try {
    Write-Log "Iniciando remoção completa do PostgreSQL 12"

    # 1. Remoção do serviço
    Write-Log "=== ETAPA 1: REMOÇÃO DO SERVIÇO ==="
    $serviceName = "postgresql-x64-12"
    
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        Write-Log "Parando serviço..."
        Stop-Service -Name $serviceName -Force
        Write-Log "Removendo serviço..."
        sc.exe delete $serviceName | Out-Null
        Start-Sleep -Seconds 2
    }

    # 2. Remoção de registros com abordagem direta
    Write-Log "=== ETAPA 2: REMOÇÃO DE REGISTROS (MÉTODO DIRETO) ==="
    
    # Lista de chaves a serem removidas
    $registryKeys = @(
        "HKLM:\SOFTWARE\PostgreSQL",
        "HKLM:\SOFTWARE\Wow6432Node\PostgreSQL",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PostgreSQL 12",
        "HKLM:\SYSTEM\CurrentControlSet\Services\postgresql-x64-12"
    )
    
    foreach ($key in $registryKeys) {
        Write-Log "Processando chave: $key"
        
        # Método direto usando .NET para evitar redirecionamento
        try {
            $regView = [Microsoft.Win32.RegistryView]::Registry64
            $regHive = [Microsoft.Win32.RegistryHive]::LocalMachine
            $regKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($regHive, $regView)
            
            $relativePath = $key -replace "HKLM:\\", ""
            $parentPath = Split-Path $relativePath -Parent
            $keyName = Split-Path $relativePath -Leaf
            
            $parentKey = $regKey.OpenSubKey($parentPath, $true)
            if ($parentKey) {
                Write-Log "Removendo chave diretamente: $keyName"
                $parentKey.DeleteSubKeyTree($keyName, $false)
                $parentKey.Close()
            }
        }
        catch {
            Write-Log "Erro no método direto: $($_.Exception.Message)"
            
            # Fallback com reg.exe
            Write-Log "Tentando com reg.exe..."
            $regPath = $key -replace "HKLM:\\", "HKLM\"
            $output = cmd /c "reg delete `"$regPath`" /f 2>&1"
            if ($LASTEXITCODE -ne 0) {
                Write-Log "Falha ao remover com reg.exe: $output"
            }
        }
    }

    # 3. Remoção de arquivos
    Write-Log "=== ETAPA 3: REMOÇÃO DE ARQUIVOS ==="
    $folders = @(
        "C:\Program Files\PostgreSQL\12",
        "C:\Program Files (x86)\PostgreSQL\12",
        "$env:ProgramData\PostgreSQL",
        "$env:APPDATA\postgresql"
    )
    
    foreach ($folder in $folders) {
        if (Test-Path $folder) {
            Write-Log "Removendo pasta: $folder"
            Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Verificação final
    Write-Log "=== VERIFICAÇÃO FINAL ==="
    $remaining = @()
    
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        $remaining += "Serviço ainda existe"
    }
    
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PostgreSQL 12") {
        $remaining += "Chave de registro ainda existe"
    }
    
    if ($remaining.Count -gt 0) {
        $remaining | ForEach-Object { Write-Log "AVISO: $_" }
        throw "Remoção incompleta. Itens remanescentes: " + ($remaining -join ", ")
    }
    
    Write-Log "[SUCESSO] PostgreSQL 12 foi completamente removido!"
    exit 0
}
catch {
    Write-Log "[ERRO CRÍTICO] $($_.Exception.Message)"
    exit 1
}