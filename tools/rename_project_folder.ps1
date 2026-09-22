<#
.SYNOPSIS
    Renomeia o diretório raiz do projeto de C:\Novastorm para C:\Pterodon.

.DESCRIPTION
    Execute este script a partir do PowerShell externo (fora da pasta C:\Novastorm)
    após fechar o Godot Editor e o Antigravity IDE.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Novastorm\tools\rename_project_folder.ps1
#>

$oldPath = "C:\Novastorm"
$newPath = "C:\Pterodon"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  PTERODON - Script de Renomeacao de Pasta Raiz" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (-not (Test-Path $oldPath)) {
    if (Test-Path $newPath) {
        Write-Host "[OK] A pasta já foi renomeada para: $newPath" -ForegroundColor Green
        exit 0
    } else {
        Write-Error "Pasta de origem $oldPath não encontrada!"
        exit 1
    }
}

# Verifica se o Godot ainda está em execução
$godotProc = Get-Process -Name godot* -ErrorAction SilentlyContinue
if ($godotProc) {
    Write-Warning "ATENÇÃO: O Godot Editor ainda está em execução!"
    Write-Warning "Por favor, feche o Godot antes de prosseguir."
    $confirm = Read-Host "Deseja encerrar o processo do Godot automaticamente agora? (S/N)"
    if ($confirm -eq 'S' -or $confirm -eq 's') {
        Stop-Process -Name godot* -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } else {
        Write-Host "Operação cancelada pelo usuário. Feche o Godot e tente novamente." -ForegroundColor Yellow
        exit 1
    }
}

try {
    Write-Host "Renomeando '$oldPath' para '$newPath'..." -ForegroundColor Yellow
    Rename-Item -Path $oldPath -NewName "Pterodon" -ErrorAction Stop
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "[SUCESSO] Projeto renomeado com sucesso para:" -ForegroundColor Green
    Write-Host "  $newPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "Passos seguintes:" -ForegroundColor Cyan
    Write-Host "1. Abra o Godot Editor e importe/abra o projeto em $newPath" -ForegroundColor White
    Write-Host "2. Abra o Antigravity IDE apontando para a nova pasta $newPath" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Green
} catch {
    Write-Error "Falha ao renomear: $($_.Exception.Message)"
    Write-Host "Certifique-se de que nenhum terminal ou IDE esteja com o diretório '$oldPath' aberto." -ForegroundColor Yellow
    exit 1
}
