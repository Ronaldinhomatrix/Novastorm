class_name MuzzleFlashEffect
extends Node3D

## Efeito de flash / brilho da nave no momento do disparo laser:
## - Luz dinâmica omnidirecional azul/ciano neon de decaimento rápido (ilumina a própria nave e o ambiente imediato).
## - Flares / estrelas de plasma nos canhões ou no centro do canhão de tiro.
## - Duração ultracurta e alta intensidade para máximo feedback e "juice".

var _light: OmniLight3D = null
var _glow_mesh: MeshInstance3D = null
var _glow_mat: StandardMaterial3D = null
var _timer: float = 0.0
const FLASH_DURATION: float = 0.09


func _ready() -> void:
	_setup_effect()


func _setup_effect() -> void:
	# Luz dinâmica de disparo
	_light = OmniLight3D.new()
	_light.light_color = Color(0.15, 0.85, 1.0)
	_light.light_energy = 0.0
	_light.omni_range = 14.0
	_light.omni_attenuation = 1.6
	_light.position = Vector3(0.0, -0.2, -6.0)
	add_child(_light)

	# Mesh emissivo do flare de plasma
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_mat.albedo_color = Color(0.6, 0.95, 1.0, 0.0)

	var sphere := SphereMesh.new()
	sphere.radius = 0.85
	sphere.height = 1.7
	sphere.radial_segments = 8
	sphere.rings = 4

	_glow_mesh = MeshInstance3D.new()
	_glow_mesh.mesh = sphere
	_glow_mesh.material_override = _glow_mat
	_glow_mesh.position = Vector3(0.0, -0.2, -5.8)
	_glow_mesh.scale = Vector3(1.8, 0.7, 1.2)
	add_child(_glow_mesh)


func trigger() -> void:
	_timer = FLASH_DURATION
	if _light:
		_light.light_energy = 16.0
	if _glow_mat:
		_glow_mat.albedo_color.a = 0.95
	if _glow_mesh:
		_glow_mesh.scale = Vector3(randf_range(1.6, 2.1), randf_range(0.7, 1.0), randf_range(1.1, 1.5))


func _process(delta: float) -> void:
	if _timer > 0.0:
		_timer = maxf(0.0, _timer - delta)
		var t := _timer / FLASH_DURATION
		if _light:
			_light.light_energy = 16.0 * (t * t)
		if _glow_mat:
			_glow_mat.albedo_color.a = 0.95 * t
	else:
		if _light and _light.light_energy > 0.0:
			_light.light_energy = 0.0
		if _glow_mat and _glow_mat.albedo_color.a > 0.0:
			_glow_mat.albedo_color.a = 0.0
