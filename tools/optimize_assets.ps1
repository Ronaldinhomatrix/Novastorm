# ============================================================================
# optimize_assets.ps1 - Otimizacao automatica de assets do Astro Striker
# ----------------------------------------------------------------------------
# USO:
#   .\tools\optimize_assets.ps1                    # otimiza tudo acima do limite
#   .\tools\optimize_assets.ps1 -MaxDim 1024       # limite diferente
#   .\tools\optimize_assets.ps1 -DryRun            # so mostra o que faria
#   .\tools\optimize_assets.ps1 -Reimport          # roda o import headless depois
#
# O que faz (com backup automatico fora do projeto):
#   1. Imagens acima de $MaxDim (default 2048) -> redimensiona mantendo proporcao
#   2. Lista GLBs acima de $MeshWarnMB (10 MB) como candidatos a decimacao
#      no Blender (decimacao automatica de malha NAO e segura sem revisao)
#   3. Com -ConvertAudio e ffmpeg instalado: converte MP3/WAV -> OGG (menor)
#
# IMPORTANTE: apos rodar, abra o Godot para ele reimportar as texturas
# (ou use -Reimport, que roda o import sem abrir o editor).
# ============================================================================
param(
	[int]$MaxDim = 2048,
	[int]$JpegQuality = 92,
	[int]$MeshWarnMB = 10,
	[string]$BackupRoot = 'C:\AstroStriker-Backup-Auto',
	[switch]$DryRun,
	[switch]$ConvertAudio,
	[switch]$Reimport,
	[string]$GodotExe = 'C:\Users\ronal\.ziva\engines\godot\4.7.1\Godot.exe',
	[string]$FfmpegExe = 'ffmpeg'
)

$ErrorActionPreference = 'Stop'
$projRoot = Split-Path $PSScriptRoot -Parent
$assetsRoot = Join-Path $projRoot 'assets'
if (-not (Test-Path $assetsRoot)) { Write-Error "Pasta de assets nao encontrada: $assetsRoot" }

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$backupDir = Join-Path $BackupRoot $stamp
$imgs = Get-ChildItem -Path $assetsRoot -Recurse -File -Include '*.png','*.jpg','*.jpeg'

Add-Type -AssemblyName System.Drawing
$jpgCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }

$processed = 0
$savedBytes = 0
foreach ($f in $imgs) {
	$img = [System.Drawing.Image]::FromFile($f.FullName)
	$w = $img.Width; $h = $img.Height
	if ($w -le $MaxDim -and $h -le $MaxDim) { $img.Dispose(); continue }

	# preserva proporcao; arredonda para multiplo de 4 (bom para compressao ETC2/s3tc)
	$scale = [Math]::Min($MaxDim / $w, $MaxDim / $h)
	$nw = [int]([Math]::Round($w * $scale / 4) * 4)
	$nh = [int]([Math]::Round($h * $scale / 4) * 4)
	if ($nw -lt 4) { $nw = 4 }; if ($nh -lt 4) { $nh = 4 }

	$rel = $f.FullName.Substring($assetsRoot.Length + 1)
	if ($DryRun) {
		Write-Output ("[DRY] {0}: {1}x{2} -> {3}x{4}" -f $rel, $w, $h, $nw, $nh)
		$img.Dispose(); $processed++
		continue
	}

	# backup espelhando a estrutura da pasta assets
	$bk = Join-Path $backupDir $rel
	New-Item -ItemType Directory -Force -Path (Split-Path $bk) | Out-Null
	Copy-Item $f.FullName $bk -Force

	$bmp = New-Object System.Drawing.Bitmap($nw, $nh)
	$bmp.SetResolution(72, 72)
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
	$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
	$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
	if ($f.Extension -match '(?i)\.jpe?g$') { $g.Clear([System.Drawing.Color]::White) }
	$g.DrawImage($img, 0, 0, $nw, $nh)

	$tmp = $f.FullName + '.tmp'
	if ($f.Extension -match '(?i)\.png$') {
		$bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
	} else {
		$ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
		$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [int64]$JpegQuality)
		$bmp.Save($tmp, $jpgCodec, $ep)
	}
	$g.Dispose(); $bmp.Dispose(); $img.Dispose()
	[System.GC]::Collect()
	Move-Item -Force $tmp $f.FullName

	$newLen = (Get-Item $f.FullName).Length
	$savedBytes += $f.Length - $newLen
	$processed++
	Write-Output ("OK {0}: {1}x{2} -> {3}x{4} | {5:N2} MB -> {6:N2} MB" -f $rel, $w, $h, $nw, $nh, ($f.Length/1MB), ($newLen/1MB))
}
# meshes grandes: candidatos a decimacao manual no Blender
$bigMeshes = Get-ChildItem -Path $assetsRoot -Recurse -File -Include '*.glb','*.gltf','*.fbx' | Where-Object { $_.Length -gt ($MeshWarnMB * 1MB) }
if ($bigMeshes) {
	Write-Output ''
	Write-Output "ATENCAO - malhas acima de ${MeshWarnMB} MB (decime manualmente no Blender):"
	$bigMeshes | ForEach-Object { Write-Output ("   {0} ({1:N1} MB)" -f $_.FullName.Substring($assetsRoot.Length + 1), ($_.Length/1MB)) }
}

# audio: conversao opcional MP3/WAV -> OGG (requer ffmpeg no PATH)
if ($ConvertAudio) {
	$hasFfmpeg = $null -ne (Get-Command $FfmpegExe -ErrorAction SilentlyContinue)
	if ($hasFfmpeg) {
		$audios = Get-ChildItem -Path $assetsRoot -Recurse -File -Include '*.mp3','*.wav'
		foreach ($a in $audios) {
			$rel = $a.FullName.Substring($assetsRoot.Length + 1)
			$bk = Join-Path $backupDir $rel
			New-Item -ItemType Directory -Force -Path (Split-Path $bk) | Out-Null
			Copy-Item $a.FullName $bk -Force
			$ogg = [System.IO.Path]::ChangeExtension($a.FullName, '.ogg')
			& $FfmpegExe -y -i $a.FullName -c:a libvorbis -q:a 5 $ogg 2>$null
			if (Test-Path $ogg) {
				Write-Output ("OK audio {0}: {1:N2} MB -> {2:N2} MB (OGG)" -f $rel, ($a.Length/1MB), ((Get-Item $ogg).Length/1MB))
				Write-Output "   -> atualize as referencias no codigo (.mp3/.wav -> .ogg) e apague o original"
			}
		}
	} else {
		Write-Output 'AVISO: -ConvertAudio sem ffmpeg instalado; etapa ignorada.'
	}
}

Write-Output ''
if (-not $DryRun) {
	Write-Output ("Resumo: {0} imagens processadas | economia de fonte em disco: {1:N2} MB" -f $processed, ($savedBytes/1MB))
	if ($processed -gt 0) {
		Write-Output ("Backup salvo em: " + $backupDir)
		if ($Reimport -and (Test-Path $GodotExe)) {
			Write-Output 'Rodando import headless (sem abrir o editor)...'
			$rp = Start-Process -FilePath $GodotExe -ArgumentList @('--headless','--import') -WorkingDirectory $projRoot -Wait -PassThru -NoNewWindow
			Write-Output ("import exitcode=" + $rp.ExitCode)
		} else {
			Write-Output 'Lembrete: abra o editor do Godot para reimportar as texturas (ou use -Reimport).'
		}
	}
} else {
	Write-Output ("Resumo DRY-RUN: {0} imagens seriam processadas." -f $processed)
}

