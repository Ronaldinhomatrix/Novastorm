class_name MissileLaunchFlash
extends Node3D

## Efeito visual de flash/brilho no momento do disparo do missil pela nave:
## - Glow de plasma alaranjado/dourado na asa de ejecao.
## - Flash rapido de luz com decaimento suave.
## - Auto-destroi apos a conclusao do efeito.

const DURATION: float = 0.22

var _glow_mesh: MeshInstance3D = null
var _glow_mat: StandardMaterial3D = null
var _light: OmniLight3D = null
var _timer: float = 0.0


func _ready() -> void:
	_setup_visuals()
	_timer = DURATION


func _setup_visuals() -> void:
	# Material emissivo aditivo alaranjado/dourado brilhante
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_mat.albedo_color = Color(1.0, 0.65, 0.2, 0.95)

	var sphere := SphereMesh.new()
	sphere.radius = 0.9
	sphere.height = 1.8
	sphere.radial_segments = 8
	sphere.rings = 4

	_glow_mesh = MeshInstance3D.new()
	_glow_mesh.mesh = sphere
	_glow_mesh.material_override = _glow_mat
	_glow_mesh.scale = Vector3(1.4, 1.1, 2.2)
	add_child(_glow_mesh)

	# Luz omnidirecional curta e rapida
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.15)
	_light.light_energy = 14.0
	_light.omni_range = 16.0
	_light.omni_attenuation = 1.5
	add_child(_light)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		queue_free()
		return

	var progress := _timer / DURATION
	# Expande o mesh ligeiramente enquanto desaparece
	if _glow_mesh:
		var expand := (1.0 - progress) * 1.5
		_glow_mesh.scale = Vector3(1.4 + expand, 1.1 + expand, 2.2 + expand * 1.8)
	if _glow_mat:
		_glow_mat.albedo_color.a = 0.95 * (progress * progress)
	if _light:
		_light.light_energy = 14.0 * progress