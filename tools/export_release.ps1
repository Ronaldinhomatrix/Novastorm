# ============================================================================
# export_release.ps1 - Exporta o jogo (Windows / Android) sem abrir o editor
# ----------------------------------------------------------------------------
# USO:
#   .\tools\export_release.ps1 -Preset "Windows Desktop"  # build\windows\Novastorm.exe + .pck
#   .\tools\export_release.ps1 -Preset "Android"          # build\android\Novastorm.apk
#   .\tools\export_release.ps1 -Out meu_build.exe         # nome customizado
#   .\tools\export_release.ps1 -Debug                     # build de debug
# ============================================================================
param(
	[string]$Preset = 'Windows Desktop',
	[string]$Out = '',
	[switch]$Debug,
	[string]$GodotExe = 'C:\Users\ronal\.ziva\engines\godot\4.7.1\Godot.exe'
)

$ErrorActionPreference = 'Stop'
$projRoot = Split-Path $PSScriptRoot -Parent

if (-not (Test-Path $GodotExe)) { Write-Error "Godot nao encontrado: $GodotExe (ajuste -GodotExe)" }

$targetFile = if ($Out -ne '') {
	$Out
} elseif ($Preset -eq 'Android') {
	if ($Debug) { 'build\android\Novastorm-debug.apk' } else { 'build\android\Novastorm.apk' }
} else {
	if ($Debug) { 'build\windows\Novastorm-debug.exe' } else { 'build\windows\Novastorm.exe' }
}

$mode = if ($Debug) { '--export-debug' } else { '--export-release' }
$outDir = Split-Path (Join-Path $projRoot $targetFile)
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Output "Exportando ($mode) $Preset -> $targetFile ..."
$outLog = Join-Path $env:TEMP 'novastorm_export_out.log'
$errLog = Join-Path $env:TEMP 'novastorm_export_err.log'
$p = Start-Process -FilePath $GodotExe -ArgumentList @('--headless', $mode, "`"$Preset`"", $targetFile) -WorkingDirectory $projRoot -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outLog -RedirectStandardError $errLog

Get-Content $errLog | Where-Object { $_ -match 'ERROR|WARNING' } | Select-Object -First 10
if ($p.ExitCode -ne 0) {
	Get-Content $outLog -Tail 20
	Write-Error "Export falhou (exit code $($p.ExitCode)). Veja $outLog"
}
$fullPath = Join-Path $projRoot $targetFile
Write-Output ("Build gerado com sucesso: " + $fullPath + " | " + [math]::Round((Get-Item $fullPath).Length/1MB,1) + " MB")
