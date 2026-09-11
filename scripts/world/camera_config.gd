class_name CameraConfig
extends Node

## Configurações globais e padronizadas da câmera, visão e névoa.
## Define o enquadramento oficial baseado no Nível 1 para ser aplicado
## em todas as fases do jogo, prevenindo desalinhamentos futuros.

# ---------------------------------------------------------------------------
# Constantes do Padrão Oficial (Nível 1)
# ---------------------------------------------------------------------------

## Posição padrão da câmera relativa ao PathFollower (18m atrás)
const DEFAULT_CAMERA_POSITION := Vector3(-0.0112, 0.0, 18.0)

## Rotação padrão da câmera
const DEFAULT_CAMERA_ROTATION := Vector3.ZERO

## Campo de visão (FOV) padrão em graus
const DEFAULT_CAMERA_FOV := 56.25

## Posição padrão da nave do jogador relativa ao PathFollower (40m à frente da origem do follower)
const DEFAULT_PLAYER_POSITION := Vector3(0.0, 0.0, -40.0)

## Alcances padrão de renderização (camera.far)
const DEFAULT_CAMERA_FAR_PC := 4000.0
const LEVEL1_CAMERA_FAR_PC := 6000.0
const DEFAULT_CAMERA_FAR_MOBILE := 3500.0
const LEVEL1_CAMERA_FAR_MOBILE := 5000.0


# ---------------------------------------------------------------------------
# Presets de Câmera para Teste em Tempo Real
# ---------------------------------------------------------------------------

## Definição de presets de câmera com distâncias progressivamente mais próximas da nave
const PRESETS: Array[Dictionary] = [
	{
		"name": "Preset 1: Padrão Atual (58m)",
		"position": Vector3(-0.0112, 0.0, 18.0),
		"rotation_deg": Vector3(0.0, 0.0, 0.0),
		"fov": 56.25,
		"distance": 58.0
	},
	{
		"name": "Preset 2: Chase Médio (38m)",
		"position": Vector3(0.0, 2.0, -2.0),
		"rotation_deg": Vector3(-2.5, 0.0, 0.0),
		"fov": 58.0,
		"distance": 38.0
	},
	{
		"name": "Preset 3: Chase Próximo (25m)",
		"position": Vector3(0.0, 3.5, -15.0),
		"rotation_deg": Vector3(-4.0, 0.0, 0.0),
		"fov": 60.0,
		"distance": 25.0
	},
	{
		"name": "Preset 4: Super Próxima (16m - Arcade)",
		"position": Vector3(0.0, 4.2, -24.0),
		"rotation_deg": Vector3(-5.5, 0.0, 0.0),
		"fov": 64.0,
		"distance": 16.0
	}
]

static func get_preset_count() -> int:
	return PRESETS.size()

static func get_preset(index: int) -> Dictionary:
	if PRESETS.is_empty():
		return {}
	var safe_idx: int = posmod(index, PRESETS.size())
	return PRESETS[safe_idx]

## Aplica um preset específico à Câmera com interpolação suave (Tween)
static func apply_preset(index: int, camera: Camera3D, duration: float = 0.5) -> Tween:
	var preset := get_preset(index)
	if preset.is_empty() or camera == null:
		return null
	
	var target_pos: Vector3 = preset["position"]
	var target_rot: Vector3 = Vector3(
		deg_to_rad(preset["rotation_deg"].x),
		deg_to_rad(preset["rotation_deg"].y),
		deg_to_rad(preset["rotation_deg"].z)
	)
	var target_fov: float = preset["fov"]
	
	if duration <= 0.0 or not camera.is_inside_tree():
		camera.position = target_pos
		camera.rotation = target_rot
		camera.fov = target_fov
		return null
	
	var tree := camera.get_tree()
	if tree == null:
		camera.position = target_pos
		camera.rotation = target_rot
		camera.fov = target_fov
		return null

	var tween := tree.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "position", target_pos, duration)
	tween.tween_property(camera, "rotation", target_rot, duration)
	tween.tween_property(camera, "fov", target_fov, duration)
	return tween

# ---------------------------------------------------------------------------
# Funções de Aplicação
# ---------------------------------------------------------------------------

## Aplica o enquadramento e posição padronizados à Câmera e ao Player fornecidos.
static func apply_standard_setup(camera: Camera3D, player: Node3D = null) -> void:
	if camera:
		camera.position = DEFAULT_CAMERA_POSITION
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
	env.fog_light_energy = 1.0
	env.fog_depth_begin = maxf(target_far * 0.25, 400.0)  # Névoa sutil começa a 25% do horizonte
	env.fog_depth_end = target_far * 0.95  # 100% de opacidade no limite do horizonte para transição invisível
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 0.8
