# ============================================================================
# export_release.ps1 - Exporta o APK de release assinado sem abrir o editor
# ----------------------------------------------------------------------------
# USO:
#   .\tools\export_release.ps1                          # build\android\AstroStriker-release.apk
#   .\tools\export_release.ps1 -Out meu_build.apk       # nome customizado
#   .\tools\export_release.ps1 -Debug                   # build de debug (bybpassa keystore release)
#
# Pre-requisitos (ja configurados neste projeto):
#   - Keystore: C:\AstroStrikerKeystore\release.keystore (senha em INFO-KEYSTORE.txt)
#   - export/android/java_sdk_path no Editor Settings do Godot
#   - Templates de exportacao Android instalados no Godot
# ============================================================================
param(
	[string]$Preset = 'Android',
	[string]$Out = '',
	[switch]$Debug,
	[string]$GodotExe = 'C:\Users\ronal\.ziva\engines\godot\4.7.1\Godot.exe'
)

$ErrorActionPreference = 'Stop'
$projRoot = Split-Path $PSScriptRoot -Parent

if (-not (Test-Path $GodotExe)) { Write-Error "Godot nao encontrado: $GodotExe (ajuste -GodotExe)" }
$apkName = if ($Out -ne '') { $Out } elseif ($Debug) { 'build\android\AstroStriker-debug.apk' } else { 'build\android\AstroStriker-release.apk' }
$mode = if ($Debug) { '--export-debug' } else { '--export-release' }
$outDir = Split-Path (Join-Path $projRoot $apkName)
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Output "Exportando ($mode) $Preset -> $apkName ..."
$outLog = Join-Path $env:TEMP 'astro_export_out.log'
$errLog = Join-Path $env:TEMP 'astro_export_err.log'
$p = Start-Process -FilePath $GodotExe -ArgumentList @('--headless', $mode, $Preset, $apkName) -WorkingDirectory $projRoot -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outLog -RedirectStandardError $errLog

Get-Content $errLog | Where-Object { $_ -match 'ERROR|WARNING' } | Select-Object -First 10
if ($p.ExitCode -ne 0) {
	Get-Content $outLog -Tail 20
	Write-Error "Export falhou (exit code $($p.ExitCode)). Veja $outLog"
}
$apkPath = Join-Path $projRoot $apkName
Write-Output ("APK gerado: " + $apkPath + " | " + [math]::Round((Get-Item $apkPath).Length/1MB,1) + " MB")
