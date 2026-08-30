extends Node3D

## Efeito de impacto/atrito BEM VISÍVEL e 100% procedural (sem assets).
##
## Combina três camadas para chamar atenção:
##   1. Onda de choque: uma esfera emissiva que se expande rapidamente e
##      desvanece (anel de energia bem perceptível).
##   2. Flash de luz omnidirecional forte que decai quase instantaneamente.
##   3. Partículas grandes de fogo/estilhaços que jorram ao longo da normal.
##
## Uso:
##   var s = preload("res://scripts/effects/spark.gd").new()
##   get_tree().current_scene.add_child(s)
##   s.global_position = ponto_de_contato
##   s.setup(normal_da_superficie)
##
## O nó se remove da árvore automaticamente ao fim da vida.


@export var size_scale: float = 1.0

const MAX_LIFETIME: float = 0.9
const FLASH_DECAY: float = 0.15
const SHOCKWAVE_MAX_RADIUS: float = 7.0

var _age: float = 0.0
var _flash_light: OmniLight3D = null


func _ready() -> void:
	scale = Vector3.ONE * size_scale
	_build_particles()
	_build_flash()


func _process(delta: float) -> void:
	_age += delta

	# Decai o flash de luz rapidamente.
	if _flash_light:
		_flash_light.light_energy = lerpf(
			50.0 * size_scale,
			0.0,
			clampf(_age / FLASH_DECAY, 0.0, 1.0)
		)

	if _age >= MAX_LIFETIME:
		queue_free()


## Orienta o nó para que o eixo LOCAL -Z fique alinhado à normal. As
## partículas são emitidas ao longo de -Z, jorrando "para fora" da superfície.
func setup(normal: Vector3) -> void:
	var n := normal.normalized()
	if n.length_squared() < 0.0001:
		return

	var up := Vector3.UP
	if absf(n.dot(up)) > 0.99:
		up = Vector3.RIGHT

	var right := n.cross(up).normalized()
	var true_up := right.cross(n).normalized()

	basis = Basis(right, true_up, -n).orthonormalized()


# ---------------------------------------------------------------------------
# 1. Partículas grandes de fogo/estilhaço
# ---------------------------------------------------------------------------

func _build_particles() -> void:
	var p := CPUParticles3D.new()
	p.name = "Sparks"
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 40
	p.lifetime = 0.6
	p.spread = 60.0
	p.direction = Vector3(0.0, 0.0, -1.0)  # jorra ao longo da normal (-Z)
	p.gravity = Vector3(0.0, -6.0, 0.0)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 24.0
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 4.0
	p.color = Color(1.0, 1.0, 1.0, 1.0)

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 1.0, 0.85, 1.0),
		Color(1.0, 0.6, 0.15, 0.95),
		Color(1.0, 0.3, 0.05, 0.0)
	])
	p.color_ramp = ramp

	p.mesh = _make_sphere(0.5)
	p.material_override = _make_material(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(p)


# ---------------------------------------------------------------------------
# 2. Flash de luz
# ---------------------------------------------------------------------------

func _build_flash() -> void:
	var l := OmniLight3D.new()
	l.name = "Flash"
	l.light_color = Color(1.0, 0.7, 0.3)
	l.light_energy = 50.0 * size_scale
	l.omni_range = 24.0 * size_scale
	add_child(l)
	_flash_light = l


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 6
	m.rings = 3
	return m


func _make_material(blend_mode: StandardMaterial3D.BlendMode) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = blend_mode
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat