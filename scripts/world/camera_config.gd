class_name CameraConfig
extends Node

## Configurações globais e padronizadas da câmera, visão e névoa.
## Define o enquadramento oficial baseado no Nível 1 para ser aplicado
## em todas as fases do jogo, prevenindo desalinhamentos futuros.

# ---------------------------------------------------------------------------
# Constantes do Padrão Oficial (Nível 1)
# ---------------------------------------------------------------------------

## Posição padrão da câmera relativa ao PathFollower no PC (5m atrás do follower, totalizando 45m de distância até o Player em Z=-40)
const DEFAULT_CAMERA_POSITION_PC := Vector3(0.0, 1.3, 5.0)

## Posição padrão da câmera relativa ao PathFollower no Mobile (8m à frente do follower, totalizando 32m de distância até o Player em Z=-40)
const DEFAULT_CAMERA_POSITION_MOBILE := Vector3(0.0, 1.3, -8.0)

## Manter compatibilidade com código existente
const DEFAULT_CAMERA_POSITION := DEFAULT_CAMERA_POSITION_PC

## Rotação padrão da câmera (leve inclinação de -1.6° para visão desimpedida sobre o caça)
const DEFAULT_CAMERA_ROTATION := Vector3(-0.027925, 0.0, 0.0)

## Campo de visão (FOV) padrão em graus
const DEFAULT_CAMERA_FOV := 57.0

## Posição padrão da nave do jogador relativa ao PathFollower (40m à frente da origem do follower)
const DEFAULT_PLAYER_POSITION := Vector3(0.0, 0.0, -40.0)

## Distância base nominal da câmera dinâmica
const DYNAMIC_CAMERA_BASE_DISTANCE_PC := 45.0
const DYNAMIC_CAMERA_BASE_DISTANCE_MOBILE := 32.0

## Alcances padrão de renderização (camera.far)
const DEFAULT_CAMERA_FAR_PC := 4000.0
const LEVEL1_CAMERA_FAR_PC := 6000.0
const DEFAULT_CAMERA_FAR_MOBILE := 3500.0
const LEVEL1_CAMERA_FAR_MOBILE := 5000.0


# ---------------------------------------------------------------------------
# Funções de Aplicação
# ---------------------------------------------------------------------------

## Aplica o enquadramento e posição padronizados à Câmera e ao Player fornecidos.
static func apply_standard_setup(camera: Camera3D, player: Node3D = null) -> void:
	if camera:
		camera.position = DEFAULT_CAMERA_POSITION_MOBILE if GameConfig.is_mobile else DEFAULT_CAMERA_POSITION_PC
		camera.rotation = DEFAULT_CAMERA_ROTATION
		camera.fov = DEFAULT_CAMERA_FOV
	
	if player:
		player.position = DEFAULT_PLAYER_POSITION


## Aplica névoa suave de profundidade (Depth Fog) no WorldEnvironment para evitar surgimento brusco (pop-in)
static func apply_depth_fog(env: Environment, target_far: float) -> void:
	if env == null:
		return
	
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	
	# Obtém a cor do horizonte do ProceduralSkyMaterial ou dos metadados gravados do céu
	var fog_color := Color(0.7, 0.8, 0.95, 1.0)
	if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
		fog_color = sky_mat.sky_horizon_color
	elif env.has_meta("original_sky_horizon_color"):
		fog_color = env.get_meta("original_sky_horizon_color") as Color
	
	env.fog_light_color = fog_color
	if GameConfig.is_mobile:
		env.fog_light_energy = 0.85
		# No mobile, a névoa começa mais longe (45% da distância) para manter cânions e inimigos nítidos
		env.fog_depth_begin = maxf(target_far * 0.45, 1200.0)
		env.fog_depth_end = target_far * 0.98
		env.fog_depth_curve = 1.4
		env.fog_sky_affect = 0.5
	else:
		# No PC: preserva 100% os valores originais
		env.fog_light_energy = 1.0
		env.fog_depth_begin = maxf(target_far * 0.25, 400.0)
		env.fog_depth_end = target_far * 0.95
		env.fog_depth_curve = 1.0
		env.fog_sky_affect = 0.8
