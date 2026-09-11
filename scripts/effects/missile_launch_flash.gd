class_name MissileLaunchFlash
extends Node3D

## Efeito visual cinematográfico de flash/clarão no momento do disparo do míssil pela nave:
## - Acoplado à asa da nave que disparou o míssil (acompanha a nave e o movimento do caça).
## - Clarão omnidirecional quente de alta intensidade que banha a fuselagem da asa e o cockpit.
## - Flare esférico de plasma alaranjado/dourado aditivo de grande porte visível da câmera em 3ª pessoa.
## - Burst instantâneo de partículas de ignição/plasma.
## - Auto-destrói após a conclusão do efeito.

const DURATION: float = 0.35

var _glow_mesh: MeshInstance3D = null
var _glow_mat: StandardMaterial3D = null
var _light: OmniLight3D = null
var _particles: CPUParticles3D = null
var _timer: float = 0.0


func _ready() -> void:
	_setup_visuals()
	_timer = DURATION


func _setup_visuals() -> void:
	# 1. Material emissivo aditivo brilhante (estilo Afterburner ignição)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_mat.albedo_color = Color(1.8, 1.2, 0.4, 1.0)

	var sphere := SphereMesh.new()
	sphere.radius = 1.6
	sphere.height = 3.2
	sphere.radial_segments = 10
	sphere.rings = 6

	_glow_mesh = MeshInstance3D.new()
	_glow_mesh.mesh = sphere
	_glow_mesh.material_override = _glow_mat
	_glow_mesh.scale = Vector3(1.8, 1.5, 2.5)
	add_child(_glow_mesh)

	# 2. Luz omnidirecional de alta intensidade iluminando a fuselagem da nave
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.65, 0.2)
	_light.light_energy = 38.0
	_light.omni_range = 28.0
	_light.omni_attenuation = 1.2
	add_child(_light)

	# 3. Pequeno burst de plasma/fagulhas de ignição no tubo ejetor
	_particles = CPUParticles3D.new()
	_particles.emitting = true
	_particles.one_shot = true
	_particles.explosiveness = 0.95
	_particles.amount = 24
	_particles.lifetime = 0.28
	_particles.spread = 45.0
	_particles.direction = Vector3(0.0, -0.2, 1.0)  # Sopra ligeiramente para trás
	_particles.initial_velocity_min = 6.0
	_particles.initial_velocity_max = 16.0
	_particles.scale_amount_min = 0.6
	_particles.scale_amount_max = 1.8

	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.3
	p_mesh.height = 0.6
	_particles.mesh = p_mesh

	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	p_mat.vertex_color_use_as_albedo = true
	_particles.material_override = p_mat

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray([
		Color(2.0, 1.6, 0.8, 1.0),
		Color(1.5, 0.6, 0.1, 0.9),
		Color(0.8, 0.2, 0.05, 0.0)
	])
	_particles.color_ramp = ramp
	add_child(_particles)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		queue_free()
		return

	var progress := _timer / DURATION  # 1.0 -> 0.0
	var expand := (1.0 - progress) * 2.8

	if _glow_mesh:
		_glow_mesh.scale = Vector3(1.8 + expand * 1.5, 1.5 + expand * 1.2, 2.5 + expand * 2.2)
	if _glow_mat:
		_glow_mat.albedo_color = Color(1.8 * progress, 1.2 * progress, 0.4 * progress, progress * progress)
	if _light:
		_light.light_energy = 38.0 * (progress * progress)