class_name GameConfigClass
extends Node

## Fonte única de verdade da configuração de plataforma (PC Ultra vs Mobile 60 FPS).
## Autoload "GameConfig" — acessível globalmente como GameConfig.is_mobile / .is_pc.
##
## A detecção roda UMA vez no _ready (antes das cenas do jogo), substituindo os
## OS.has_feature(...) que estavam espalhados e inconsistentes pelo projeto.

## true em Android/iOS (e web mobile); false em desktop.
var is_mobile: bool = false

## true em desktop (caminho PC/Ultra); false em mobile.
var is_pc: bool = false

## true em navegador (HTML5), independente de ser mobile ou desktop.
var is_web: bool = false


# ---------------------------------------------------------------------------
# Constantes de qualidade (PC Ultra vs Mobile 60 FPS)
# ---------------------------------------------------------------------------
# Fonte única de verdade dos números de performance/qualidade do guideline.
# O far de câmera pode ser sobrescrito por nível (ver game_controller.gd).

const CAMERA_FAR_PC := 4000.0
const CAMERA_FAR_MOBILE := 3500.0
const MAX_FPS_PC := 0
const MAX_FPS_MOBILE := 60
const RENDER_SCALE_PC := 1.0
const RENDER_SCALE_MOBILE := 0.75
const FSR_SHARPNESS_MOBILE := 0.3
const SHADOW_MAX_DISTANCE_PC := 1200.0
const SHADOW_MAX_DISTANCE_MOBILE := 100.0

# Defaults dos toggles gráficos do usuário (usados pelo UserSettings quando o
# jogador ainda não escolheu). O menu de opções é o MESMO nas duas plataformas.
const SHADOWS_DEFAULT_PC := true
const SHADOWS_DEFAULT_MOBILE := true
const GLOW_DEFAULT_PC := true
const GLOW_DEFAULT_MOBILE := true

# Glow (bloom) mais leve no mobile: menos intensidade e menos bloom para
# preservar o brilho do projétil sem estourar o pós-processamento.
const GLOW_INTENSITY_MOBILE := 0.5
const GLOW_BLOOM_MOBILE := 0.06
const SSAO_DEFAULT_PC := true
const SSAO_DEFAULT_MOBILE := false
const SSIL_DEFAULT_PC := true
const SSIL_DEFAULT_MOBILE := false


func _ready() -> void:
	is_web = OS.has_feature("web")
	# "mobile" é o feature tag embutido do Godot (true em Android/iOS).
	# Mantemos também "android"/"ios" explícitos por clareza e alinhamento
	# com o padrão já adotado nas DEVELOPMENT_GUIDELINES do projeto.
	is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	is_pc = not is_mobile
