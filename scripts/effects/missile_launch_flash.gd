class_name MissileLaunchFlash
extends Node3D

## Clarão de ignição do míssil: flash de ILUMINAÇÃO real acoplado à asa da nave.
##
## Substitui o antigo "flare esférico" (mesh de brilho aditivo) que aparecia como
## uma bola de luz presa na fuselagem. Agora o efeito é feito apenas com luz:
## - Núcleo OmniLight3D quente (branco-dourado) com ataque quase instantâneo e
##   decaimento quadrático, banhando a própria fuselagem no instante do disparo.
## - Segundo OmniLight3D laranja, mais aberto, que espalha o clarão pelo cenário
##   ao redor (sensação de "flash" real iluminando o ambiente).
## - Jato curto de faíscas de ignição no tubo ejetor (mundo, não presas à nave),
##   deixando um rastro para trás.
## Sem nenhum mesh esférico visível.

## Duração total do clarão (segundos)
const DURATION: float = 0.34
## Tempo de subida do flash (ataque quase instantâneo)
const ATTACK: float = 0.045

# --- Núcleo: ilumina a fuselagem da nave ---
const CORE_COLOR: Color = Color(1.0, 0.9, 0.66)
const CORE_ENERGY: float = 420.0
const CORE_RANGE: float = 36.0
const CORE_ATTENUATION: float = 1.1

# --- Spill: propaga o clarão pelo ambiente ao redor ---
const SPILL_COLOR: Color = Color(1.0, 0.55, 0.18)
const SPILL_ENERGY: float = 170.0
const SPILL_RANGE: float = 95.0
const SPILL_ATTENUATION: float = 0.7

var _core_light: OmniLight3D = null
var _spill_light: OmniLight3D = null
var _particles: CPUParticles3D = null
var _age: float = 0.0

static var _shared_spark_mesh: SphereMesh = null
static var _shared_spark_mat: StandardMaterial3D = null
static var _shared_spark_ramp: Gradient = null


func _ready() -> void:
	_setup_visuals()


func _setup_visuals() -> void:
	# 1. Luz de núcleo: o clarão que realmente ilumina a fuselagem da asa e o cockpit.
	_core_light = OmniLight3D.new()
	_core_light.name = "CoreFlashLight"
	_core_light.light_color = CORE_COLOR
	_core_light.light_energy = CORE_ENERGY
	_core_light.omni_range = CORE_RANGE
	_core_light.omni_attenuation = CORE_ATTENUATION
	add_child(_core_light)

	# 2. Luz de spill: alcance maior para o clarão vazar no cenário em volta.
	_spill_light = OmniLight3D.new()
	_spill_light.name = "SpillFlashLight"
	_spill_light.light_color = SPILL_COLOR
	_spill_light.light_energy = SPILL_ENERGY
	_spill_light.omni_range = SPILL_RANGE
	_spill_light.omni_attenuation = SPILL_ATTENUATION
	add_child(_spill_light)

	# 3. Faíscas de ignição ejetadas para trás (curtas, rápidas e pequenas:
	#    leem como jato de fagulhas, não como bola de glow).
	if not _shared_spark_ramp:
		_shared_spark_ramp = Gradient.new()
		_shared_spark_ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		_shared_spark_ramp.colors = PackedColorArray([
			Color(3.2, 2.6, 1.6, 1.0),
			Color(1.8, 0.8, 0.15, 0.85),
			Color(0.6, 0.15, 0.02, 0.0)
		])
	if not _shared_spark_mesh:
		_shared_spark_mesh = SphereMesh.new()
		_shared_spark_mesh.radius = 0.11
		_shared_spark_mesh.height = 0.22
		_shared_spark_mesh.radial_segments = 6
		_shared_spark_mesh.rings = 3
	if not _shared_spark_mat:
		_shared_spark_mat = StandardMaterial3D.new()
		_shared_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_shared_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shared_spark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shared_spark_mat.vertex_color_use_as_albedo = true
		_shared_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES

	_particles = CPUParticles3D.new()
	_particles.name = "IgnitionSparks"
	_particles.emitting = true
	_particles.one_shot = true
	_particles.explosiveness = 1.0
	_particles.amount = 20 if GameConfig.is_mobile else 38
	_particles.lifetime = 0.26
	_particles.spread = 38.0
	_particles.direction = Vector3(0.0, -0.15, 1.0)  # Jorra para trás do tubo ejetor
	_particles.gravity = Vector3(0.0, -5.0, 0.0)
	_particles.initial_velocity_min = 14.0
	_particles.initial_velocity_max = 34.0
	_particles.scale_amount_min = 0.35
	_particles.scale_amount_max = 0.95
	# Faíscas soltas no mundo: a nave a 65 m/s deixa o rastro para trás.
	_particles.local_coords = false
	_particles.mesh = _shared_spark_mesh
	_particles.material_override = _shared_spark_mat
	_particles.color_ramp = _shared_spark_ramp
	add_child(_particles)


func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return

	# Envelope: ataque quase instantâneo + decaimento quadrático (clarão de descarga).
	var rise := clampf(_age / ATTACK, 0.0, 1.0)
	var fall := 1.0 - clampf((_age - ATTACK) / maxf(0.001, DURATION - ATTACK), 0.0, 1.0)
	var envelope := rise * fall * fall

	# Leve tremulação no início, como uma descarga elétrica real.
	if rise >= 1.0 and envelope > 0.1:
		envelope *= randf_range(0.9, 1.06)

	if _core_light:
		_core_light.light_energy = CORE_ENERGY * envelope
	if _spill_light:
		_spill_light.light_energy = SPILL_ENERGY * envelope
