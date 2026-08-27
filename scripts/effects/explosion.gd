extends Node3D

## Explosão de impacto 100% procedural com múltiplas camadas cinematográficas:
##   1. Flash de luz dinâmico ultrabrilhante de decaimento rápido.
##   2. Onda de choque expansiva (Shockwave Ring) com brilho aditivo.
##   3. Burst central de plasma e fogo volumétrico (núcleo branco-dourado).
##   4. Estilhaços metálicos incandescentes (Debris / Shrapnel) com rotação e velocidade variada.
##   5. Faíscas de alta velocidade radiando para fora.
##   6. Nuvem volumétrica de fumaça cinza escura expansiva.
##
## 100% autossuficiente (sem assets externos necessários) e otimizado para 60 FPS.

@export var size_scale: float = 1.0

const MAX_LIFETIME: float = 1.6
const FLASH_DECAY: float = 0.3
const SHOCKWAVE_MAX_RADIUS: float = 12.0

var _age: float = 0.0
var _flash_light: OmniLight3D = null
var _shockwave: MeshInstance3D = null
var _shockwave_mat: StandardMaterial3D = null


func _ready() -> void:
	scale = Vector3.ONE * size_scale
	_build_fire_core()
	_build_debris()
	_build_sparks()
	_build_smoke()
	_build_flash()
	_build_shockwave()


func _process(delta: float) -> void:
	_age += delta

	# Decaimento rápido e suave do flash de luz
	if _flash_light:
		var flash_t := clampf(_age / FLASH_DECAY, 0.0, 1.0)
		_flash_light.light_energy = lerpf(70.0 * size_scale, 0.0, flash_t * flash_t)

	# Expansão e fade-out da onda de choque
	if _shockwave:
		var t := clampf(_age / (MAX_LIFETIME * 0.7), 0.0, 1.0)
		_shockwave.scale = Vector3.ONE * (0.8 + t * SHOCKWAVE_MAX_RADIUS) * size_scale
		if _shockwave_mat:
			_shockwave_mat.albedo_color.a = lerpf(0.9, 0.0, t * t)

	if _age >= MAX_LIFETIME:
		queue_free()


# ---------------------------------------------------------------------------
# 1. Fire Core (Plasma e Fogo Volumétrico Central)
# ---------------------------------------------------------------------------

func _build_fire_core() -> void:
	var p := CPUParticles3D.new()
	p.name = "FireCore"
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 45
	p.lifetime = 0.55
	p.spread = 180.0
	p.direction = Vector3.UP
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 22.0
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.scale_amount_min = 2.5
	p.scale_amount_max = 8.5

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.5, 1.0])
	ramp.colors = PackedColorArray([
		Color(2.0, 2.0, 1.8, 1.0),   # Núcleo branco incandescente
		Color(1.0, 0.85, 0.2, 1.0),  # Dourado elétrico
		Color(1.0, 0.35, 0.05, 0.85), # Laranja fogo
		Color(0.6, 0.08, 0.02, 0.0)   # Vermelho brasa fade
	])
	p.color_ramp = ramp

	p.mesh = _make_sphere(0.6)
	p.material_override = _make_material(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(p)


# ---------------------------------------------------------------------------
# 2. Debris & Shrapnel (Estilhaços de Metal Incandescente Voando)
# ---------------------------------------------------------------------------

func _build_debris() -> void:
	var p := CPUParticles3D.new()
	p.name = "Debris"
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 32
	p.lifetime = 1.1
	p.spread = 180.0
	p.direction = Vector3.UP
	p.gravity = Vector3(0.0, -15.0, 0.0)
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 65.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.2

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.5, 0.9, 0.3, 1.0),
		Color(1.0, 0.3, 0.05, 0.9),
		Color(0.2, 0.05, 0.02, 0.0)
	])
	p.color_ramp = ramp

	# Fragmentos de caixa / estilhaço
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.4, 0.9)
	p.mesh = box
	p.material_override = _make_material(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(p)


# ---------------------------------------------------------------------------
# 3. Golden Sparks (Faíscas Rápidas e Finas)
# ---------------------------------------------------------------------------

func _build_sparks() -> void:
	var p := CPUParticles3D.new()
	p.name = "Sparks"
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 35
	p.lifetime = 0.65
	p.spread = 180.0
	p.direction = Vector3.UP
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 35.0
	p.initial_velocity_max = 80.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 1.0

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray([
		Color(2.0, 1.6, 0.8, 1.0),
		Color(1.0, 0.6, 0.1, 0.8),
		Color(1.0, 0.1, 0.0, 0.0)
	])
	p.color_ramp = ramp

	p.mesh = _make_sphere(0.25)
	p.material_override = _make_material(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(p)


# ---------------------------------------------------------------------------
# 4. Smoke Clouds (Fumaça Escura Expansiva)
# ---------------------------------------------------------------------------

func _build_smoke() -> void:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.7
	p.amount = 22
	p.lifetime = 1.4
	p.spread = 180.0
	p.direction = Vector3.UP
	p.gravity = Vector3(0.0, 2.5, 0.0)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 10.0
	p.angular_velocity_min = -70.0
	p.angular_velocity_max = 70.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 11.0

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.5, 0.45, 0.4, 0.6),
		Color(0.3, 0.28, 0.26, 0.5),
		Color(0.18, 0.16, 0.16, 0.3),
		Color(0.08, 0.08, 0.08, 0.0)
	])
	p.color_ramp = ramp

	p.mesh = _make_sphere(0.5)
	p.material_override = _make_material(BaseMaterial3D.BLEND_MODE_MIX)
	add_child(p)


# ---------------------------------------------------------------------------
# 5. Flash de Luz
# ---------------------------------------------------------------------------

func _build_flash() -> void:
	var l := OmniLight3D.new()
	l.name = "Flash"
	l.light_color = Color(1.0, 0.75, 0.35)
	l.light_energy = 70.0 * size_scale
	l.omni_range = 35.0 * size_scale
	add_child(l)
	_flash_light = l


# ---------------------------------------------------------------------------
# 6. Onda de Choque (Shockwave)
# ---------------------------------------------------------------------------

func _build_shockwave() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.85, 0.4, 0.9)
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
# Helpers de Construção
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