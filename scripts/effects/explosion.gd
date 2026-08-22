extends Node3D

## Explosão de impacto 100% procedural (NENHUM asset externo necessário).
##
## Combina camadas de efeito:
##   1. Flash de luz omnidirecional forte que decai rapidamente.
##   2. Onda de choque expansiva (esfera emissiva que cresce e desvanece) —
##      o mesmo "anel de energia" visível do efeito de faísca.
##   3. Partículas GRANDES de fogo (burst laranja/branco).
##   4. Partículas de fumaça (cinza, que se expandem e sobem).
##
## O nó se remove da árvore automaticamente ao fim da vida.
##
## Uso:
##   var e = preload("res://scripts/effects/explosion.gd").new()
##   get_tree().current_scene.add_child(e)
##   e.global_position = ponto_de_impacto


@export var size_scale: float = 1.0

const MAX_LIFETIME: float = 1.6
const FLASH_DECAY: float = 0.35
const SHOCKWAVE_MAX_RADIUS: float = 9.0

var _age: float = 0.0
var _flash_light: OmniLight3D = null
var _shockwave: MeshInstance3D = null
var _shockwave_mat: StandardMaterial3D = null


func _ready() -> void:
	scale = Vector3.ONE * size_scale
	_build_fire()
	_build_smoke()
	_build_flash()
	_build_shockwave()


func _process(delta: float) -> void:
	_age += delta

	# Decai a energia do flash até apagar.
	if _flash_light:
		_flash_light.light_energy = lerpf(
			50.0 * size_scale,
			0.0,
			clampf(_age / FLASH_DECAY, 0.0, 1.0)
		)

	# Expande a onda de choque e desvanece.
	if _shockwave:
		var t := clampf(_age / MAX_LIFETIME, 0.0, 1.0)
		_shockwave.scale = Vector3.ONE * (0.5 + t * SHOCKWAVE_MAX_RADIUS) * size_scale
		if _shockwave_mat:
			_shockwave_mat.albedo_color.a = lerpf(0.95, 0.0, t)

	if _age >= MAX_LIFETIME:
		queue_free()


# ---------------------------------------------------------------------------
# Fire (burst central)
# ---------------------------------------------------------------------------

func _build_fire() -> void:
	var p := CPUParticles3D.new()
	p.name = "Fire"
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 40
	p.lifetime = 0.5
	p.spread = 180.0
	p.direction = Vector3.UP
	p.gravity = Vector3(0.0, -1.0, 0.0)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 14.0
	p.angular_velocity_min = -90.0
	p.angular_velocity_max = 90.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 7.0
	p.color = Color(1.0, 1.0, 1.0, 1.0)

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 1.0, 0.92, 1.0),
		Color(1.0, 0.55, 0.1, 0.9),
		Color(1.0, 0.2, 0.05, 0.0)
	])
	p.color_ramp = ramp

	p.mesh = _make_sphere(0.5)
	p.material_override = _make_material(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(p)


# ---------------------------------------------------------------------------
# Smoke (se expande e sobe)
# ---------------------------------------------------------------------------

func _build_smoke() -> void:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.6
	p.amount = 18
	p.lifetime = 1.2
	p.spread = 160.0
	p.direction = Vector3.UP
	p.gravity = Vector3(0.0, 2.0, 0.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.angular_velocity_min = -60.0
	p.angular_velocity_max = 60.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 9.0
	p.color = Color(0.3, 0.3, 0.32, 1.0)

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.4, 0.4, 0.42, 0.5),
		Color(0.25, 0.25, 0.27, 0.35),
		Color(0.1, 0.1, 0.12, 0.0)
	])
	p.color_ramp = ramp

	p.mesh = _make_sphere(0.4)
	p.material_override = _make_material(BaseMaterial3D.BLEND_MODE_MIX)
	add_child(p)


# ---------------------------------------------------------------------------
# Flash de luz
# ---------------------------------------------------------------------------

func _build_flash() -> void:
	var l := OmniLight3D.new()
	l.name = "Flash"
	l.light_color = Color(1.0, 0.65, 0.25)
	l.light_energy = 50.0 * size_scale
	l.omni_range = 24.0 * size_scale
	add_child(l)
	_flash_light = l


# ---------------------------------------------------------------------------
# Onda de choque (esfera emissiva que se expande)
# ---------------------------------------------------------------------------

func _build_shockwave() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.8, 0.35, 0.95)
	_shockwave_mat = mat

	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 12

	var mi := MeshInstance3D.new()
	mi.name = "Shockwave"
	mi.mesh = mesh
	mi.material_override = mat
	mi.scale = Vector3.ONE * 0.5
	add_child(mi)
	_shockwave = mi


# ---------------------------------------------------------------------------
# Helpers de construção
# ---------------------------------------------------------------------------

func _make_sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m


func _make_material(blend_mode: StandardMaterial3D.BlendMode) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = blend_mode
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat