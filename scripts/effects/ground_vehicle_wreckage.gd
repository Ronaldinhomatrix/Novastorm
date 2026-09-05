class_name GroundVehicleWreckage
extends Node3D

## Sistema de destruição realista de veículos terrestres (Tanques e Caminhões).
##
## Sequência temporal de detonação em 4 fases:
##   Fase 0 (t=0.00s) — FLASH: Pulso branco-amarelo cegante instantâneo + onda de choque.
##   Fase 1 (t=0.05s) — FIREBALL: Bola de fogo volumétrica expandindo com convecção.
##   Fase 2 (t=0.10s) — DEBRIS: Estilhaços incandescentes em arco balístico com gravidade.
##   Fase 3 (t=0.30s) — AFTERMATH: Carcaça carbonizada + chamas residuais + coluna de fumaça.
##
## Para o Tank1, a torreta é ejetada com física balística real (Turret Pop).

const ExplosionSounds := [
	preload("res://assets/audio/explosion1.ogg"),
	preload("res://assets/audio/explosion2.ogg"),
]

var _lifetime: float = 12.0
var _age: float = 0.0
var _flash_light: OmniLight3D = null
var _fireball_light: OmniLight3D = null
var _flicker_light: OmniLight3D = null
var _fire_particles: CPUParticles3D = null
var _smoke_particles: CPUParticles3D = null
var _wreck_root: Node3D = null
var _fading: bool = false


# ---------------------------------------------------------------------------
# Construtores Estáticos
# ---------------------------------------------------------------------------

static func spawn_for_tank(tank: Node3D) -> GroundVehicleWreckage:
	if not tank or not is_instance_valid(tank):
		return null
	var parent := _get_scene_parent(tank)
	if not parent:
		return null
	var w := GroundVehicleWreckage.new()
	parent.add_child(w)
	w.global_transform = tank.global_transform
	w._build_tank_wreckage(tank)
	return w


static func spawn_for_truck(truck: Node3D) -> GroundVehicleWreckage:
	if not truck or not is_instance_valid(truck):
		return null
	var parent := _get_scene_parent(truck)
	if not parent:
		return null
	var w := GroundVehicleWreckage.new()
	parent.add_child(w)
	w.global_transform = truck.global_transform
	w._build_truck_wreckage(truck)
	return w


static func _get_scene_parent(node: Node) -> Node:
	if node.get_tree() and node.get_tree().current_scene:
		return node.get_tree().current_scene
	if node.get_parent():
		return node.get_parent()
	return node.get_tree().root if node.get_tree() else null


# ---------------------------------------------------------------------------
# Montagem — Tanque
# ---------------------------------------------------------------------------

func _build_tank_wreckage(tank: Node3D) -> void:
	# ---- Fase 0: Flash + Shockwave ----
	_build_flash_pulse(2.0)
	_build_shockwave_ring()

	# ---- Fase 1: Fireball ----
	_build_fireball(Vector3(0, 3.0, 0), 1.8)

	# ---- Fase 2: Debris balístico ----
	_build_hot_debris(Vector3(0, 3.0, 0), 30)

	# ---- Fase 3: Carcaça + Fumaça ----
	var tank_model := tank.find_child("TankModel", true, false) as Node3D
	var original_turret := tank.find_child("Turret", true, false) as Node3D

	if tank_model:
		var wreck := tank_model.duplicate() as Node3D
		add_child(wreck)
		wreck.position = Vector3.ZERO
		wreck.rotation = Vector3.ZERO
		_wreck_root = wreck
		var wreck_turret := wreck.find_child("Turret", true, false)
		if wreck_turret:
			wreck_turret.queue_free()
		_apply_charred_material(wreck)

	# Turret Pop
	if original_turret and is_instance_valid(original_turret):
		_spawn_flying_turret(original_turret, tank.global_position.y)

	_build_aftermath_fire(Vector3(0, 2.5, 0))
	_build_aftermath_smoke(Vector3(0, 3.0, 0))
	_play_heavy_explosion_sound()


# ---------------------------------------------------------------------------
# Montagem — Caminhão
# ---------------------------------------------------------------------------

func _build_truck_wreckage(truck: Node3D) -> void:
	_build_flash_pulse(1.6)
	_build_shockwave_ring()
	_build_fireball(Vector3(0, 3.5, 0), 1.5)
	_build_hot_debris(Vector3(0, 3.0, 0), 22)

	var truck_model := truck.find_child("TruckModel", true, false) as Node3D
	if truck_model:
		var wreck := truck_model.duplicate() as Node3D
		add_child(wreck)
		wreck.position = Vector3.ZERO
		wreck.rotation_degrees = Vector3(randf_range(-3, 3), 0, randf_range(-5, 5))
		_wreck_root = wreck
		_apply_charred_material(wreck)

	_build_aftermath_fire(Vector3(0, 3.0, 0))
	_build_aftermath_smoke(Vector3(0, 3.5, 0))
	_play_heavy_explosion_sound()


# ===========================================================================
#  FASE 0 — FLASH PULSE + SHOCKWAVE
# ===========================================================================

func _build_flash_pulse(intensity: float) -> void:
	# Luz branca ultra-intensa de decaimento instantâneo (0.15s)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.95, 0.8)
	_flash_light.light_energy = 120.0 * intensity
	_flash_light.omni_range = 50.0
	_flash_light.omni_attenuation = 0.6
	_flash_light.position = Vector3.UP * 3.0
	add_child(_flash_light)

	# Brilho core branco-amarelo (esfera emissiva que encolhe rapidamente)
	var core := CPUParticles3D.new()
	core.name = "FlashCore"
	core.emitting = true
	core.one_shot = true
	core.explosiveness = 1.0
	core.amount = 1
	core.lifetime = 0.18
	core.position = Vector3.UP * 3.0
	core.direction = Vector3.UP
	core.spread = 0.0
	core.gravity = Vector3.ZERO
	core.initial_velocity_min = 0.0
	core.initial_velocity_max = 0.0
	core.scale_amount_min = 12.0
	core.scale_amount_max = 14.0

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	ramp.colors = PackedColorArray([
		Color(4.0, 3.5, 2.0, 1.0),
		Color(3.0, 1.5, 0.3, 0.8),
		Color(1.0, 0.2, 0.0, 0.0)
	])
	core.color_ramp = ramp
	core.mesh = _make_sphere(0.5)
	core.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(core)


func _build_shockwave_ring() -> void:
	# Anel horizontal de poeira/compressão radiando para fora
	var ring := CPUParticles3D.new()
	ring.name = "Shockwave"
	ring.emitting = true
	ring.one_shot = true
	ring.explosiveness = 1.0
	ring.amount = 50
	ring.lifetime = 0.45
	ring.position = Vector3.UP * 0.5
	ring.direction = Vector3.UP
	ring.spread = 90.0
	ring.flatness = 0.95  # Forçar partículas no plano horizontal
	ring.gravity = Vector3.ZERO
	ring.initial_velocity_min = 40.0
	ring.initial_velocity_max = 70.0
	ring.scale_amount_min = 1.5
	ring.scale_amount_max = 4.0

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.5, 1.2, 0.8, 0.7),
		Color(0.6, 0.5, 0.4, 0.4),
		Color(0.3, 0.25, 0.2, 0.0)
	])
	ring.color_ramp = ramp
	ring.mesh = _make_sphere(0.3)
	ring.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(ring)


# ===========================================================================
#  FASE 1 — FIREBALL (Bola de Fogo Volumétrica)
# ===========================================================================

func _build_fireball(offset: Vector3, scale_mult: float) -> void:
	# Bola de fogo que expande, sobe e se dissipa (tipo cogumelo)
	var fb := CPUParticles3D.new()
	fb.name = "Fireball"
	fb.emitting = true
	fb.one_shot = true
	fb.explosiveness = 0.92
	fb.amount = 55
	fb.lifetime = 0.7
	fb.position = offset
	fb.direction = Vector3.UP
	fb.spread = 55.0
	fb.gravity = Vector3(0, 8.0, 0)  # Convecção térmica puxa para cima
	fb.initial_velocity_min = 8.0 * scale_mult
	fb.initial_velocity_max = 22.0 * scale_mult
	fb.angular_velocity_min = -120.0
	fb.angular_velocity_max = 120.0
	fb.scale_amount_min = 3.5 * scale_mult
	fb.scale_amount_max = 9.0 * scale_mult

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.35, 0.65, 1.0])
	ramp.colors = PackedColorArray([
		Color(4.0, 3.5, 1.5, 1.0),   # Núcleo branco incandescente
		Color(2.5, 1.2, 0.15, 1.0),  # Dourado elétrico
		Color(1.5, 0.4, 0.02, 0.9),  # Laranja intenso
		Color(0.6, 0.08, 0.01, 0.6), # Vermelho brasa
		Color(0.15, 0.02, 0.0, 0.0)  # Fade escuro
	])
	fb.color_ramp = ramp
	fb.mesh = _make_sphere(0.6)
	fb.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(fb)

	# Fumaça escura que acompanha a bola de fogo (contorno orgânico)
	var fb_smoke := CPUParticles3D.new()
	fb_smoke.name = "FireballSmoke"
	fb_smoke.emitting = true
	fb_smoke.one_shot = true
	fb_smoke.explosiveness = 0.85
	fb_smoke.amount = 35
	fb_smoke.lifetime = 1.2
	fb_smoke.position = offset
	fb_smoke.direction = Vector3.UP
	fb_smoke.spread = 60.0
	fb_smoke.gravity = Vector3(0, 5.0, 0)
	fb_smoke.initial_velocity_min = 5.0 * scale_mult
	fb_smoke.initial_velocity_max = 16.0 * scale_mult
	fb_smoke.angular_velocity_min = -60.0
	fb_smoke.angular_velocity_max = 60.0
	fb_smoke.scale_amount_min = 4.0 * scale_mult
	fb_smoke.scale_amount_max = 12.0 * scale_mult

	var smoke_ramp := Gradient.new()
	smoke_ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.6, 1.0])
	smoke_ramp.colors = PackedColorArray([
		Color(0.35, 0.25, 0.15, 0.85),
		Color(0.2, 0.18, 0.15, 0.7),
		Color(0.12, 0.1, 0.1, 0.4),
		Color(0.06, 0.06, 0.06, 0.0)
	])
	fb_smoke.color_ramp = smoke_ramp
	fb_smoke.mesh = _make_sphere(0.5)
	fb_smoke.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_MIX)
	add_child(fb_smoke)

	# Luz alaranjada intensa que acompanha a bola de fogo
	_fireball_light = OmniLight3D.new()
	_fireball_light.position = offset + Vector3.UP * 2.0
	_fireball_light.light_color = Color(1.0, 0.55, 0.1)
	_fireball_light.light_energy = 45.0 * scale_mult
	_fireball_light.omni_range = 35.0
	_fireball_light.omni_attenuation = 1.2
	add_child(_fireball_light)


# ===========================================================================
#  FASE 2 — HOT DEBRIS (Estilhaços Incandescentes com Gravidade)
# ===========================================================================

func _build_hot_debris(offset: Vector3, count: int) -> void:
	# Estilhaços metálicos pesados: arremessados para cima e caem com gravidade
	var debris := CPUParticles3D.new()
	debris.name = "HotDebris"
	debris.emitting = true
	debris.one_shot = true
	debris.explosiveness = 0.96
	debris.amount = count
	debris.lifetime = 2.0
	debris.position = offset
	debris.direction = Vector3.UP
	debris.spread = 70.0
	debris.gravity = Vector3(0, -28.0, 0)  # Gravidade real
	debris.initial_velocity_min = 18.0
	debris.initial_velocity_max = 40.0
	debris.angular_velocity_min = -400.0
	debris.angular_velocity_max = 400.0
	debris.scale_amount_min = 0.3
	debris.scale_amount_max = 1.4

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	ramp.colors = PackedColorArray([
		Color(2.5, 1.8, 0.6, 1.0),   # Metal incandescente
		Color(1.2, 0.5, 0.1, 1.0),   # Alaranjado
		Color(0.3, 0.2, 0.18, 0.9),  # Metal escurecendo
		Color(0.1, 0.1, 0.1, 0.0)    # Apagando
	])
	debris.color_ramp = ramp

	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.25, 0.6)
	debris.mesh = box
	debris.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_MIX)
	add_child(debris)

	# Faíscas rápidas radiando para fora
	var sparks := CPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.emitting = true
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = 45
	sparks.lifetime = 0.6
	sparks.position = offset
	sparks.direction = Vector3.UP
	sparks.spread = 80.0
	sparks.gravity = Vector3(0, -18.0, 0)
	sparks.initial_velocity_min = 30.0
	sparks.initial_velocity_max = 75.0
	sparks.scale_amount_min = 0.15
	sparks.scale_amount_max = 0.5

	var spark_ramp := Gradient.new()
	spark_ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	spark_ramp.colors = PackedColorArray([
		Color(3.0, 2.5, 1.2, 1.0),
		Color(1.5, 0.6, 0.1, 0.8),
		Color(0.8, 0.1, 0.0, 0.0)
	])
	sparks.color_ramp = spark_ramp
	sparks.mesh = _make_sphere(0.12)
	sparks.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(sparks)


# ===========================================================================
#  FASE 3 — AFTERMATH (Chamas Residuais + Fumaça Densa Contínua)
# ===========================================================================

func _build_aftermath_fire(offset: Vector3) -> void:
	_fire_particles = CPUParticles3D.new()
	_fire_particles.name = "AftermathFire"
	_fire_particles.emitting = true
	_fire_particles.amount = 22
	_fire_particles.lifetime = 0.65
	_fire_particles.position = offset
	_fire_particles.direction = Vector3.UP
	_fire_particles.spread = 30.0
	_fire_particles.gravity = Vector3(0, 4.0, 0)
	_fire_particles.initial_velocity_min = 1.5
	_fire_particles.initial_velocity_max = 4.5
	_fire_particles.scale_amount_min = 1.0
	_fire_particles.scale_amount_max = 2.8

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	ramp.colors = PackedColorArray([
		Color(2.0, 1.5, 0.3, 1.0),
		Color(1.4, 0.5, 0.04, 0.9),
		Color(0.7, 0.12, 0.02, 0.7),
		Color(0.15, 0.02, 0.0, 0.0)
	])
	_fire_particles.color_ramp = ramp
	_fire_particles.mesh = _make_sphere(0.4)
	_fire_particles.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(_fire_particles)

	# Luz trêmula alaranjada
	_flicker_light = OmniLight3D.new()
	_flicker_light.name = "FireLight"
	_flicker_light.position = offset + Vector3.UP * 1.5
	_flicker_light.light_color = Color(1.0, 0.5, 0.1)
	_flicker_light.light_energy = 6.0
	_flicker_light.omni_range = 18.0
	_flicker_light.omni_attenuation = 1.4
	add_child(_flicker_light)


func _build_aftermath_smoke(offset: Vector3) -> void:
	_smoke_particles = CPUParticles3D.new()
	_smoke_particles.name = "AftermathSmoke"
	_smoke_particles.emitting = true
	_smoke_particles.amount = 30
	_smoke_particles.lifetime = 3.5
	_smoke_particles.position = offset
	_smoke_particles.direction = Vector3(0.05, 1.0, 0.03).normalized()
	_smoke_particles.spread = 18.0
	_smoke_particles.gravity = Vector3(0, 3.0, 0)
	_smoke_particles.initial_velocity_min = 2.5
	_smoke_particles.initial_velocity_max = 7.0
	_smoke_particles.angular_velocity_min = -40.0
	_smoke_particles.angular_velocity_max = 40.0
	_smoke_particles.scale_amount_min = 2.0
	_smoke_particles.scale_amount_max = 7.0

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.5, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.22, 0.2, 0.18, 0.85),
		Color(0.15, 0.14, 0.13, 0.75),
		Color(0.09, 0.09, 0.09, 0.4),
		Color(0.04, 0.04, 0.04, 0.0)
	])
	_smoke_particles.color_ramp = ramp
	_smoke_particles.mesh = _make_sphere(0.6)
	_smoke_particles.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_MIX)
	add_child(_smoke_particles)


# ===========================================================================
#  TURRET POP (Ejeção Balística da Torreta)
# ===========================================================================

func _spawn_flying_turret(source_turret: Node3D, ground_y: float) -> void:
	var turret_clone := source_turret.duplicate() as Node3D
	var scene_parent := get_parent()
	if not scene_parent:
		return

	var container := Node3D.new()
	scene_parent.add_child(container)
	container.global_transform = source_turret.global_transform
	turret_clone.position = Vector3.ZERO
	turret_clone.rotation = Vector3.ZERO
	container.add_child(turret_clone)
	_apply_charred_material(turret_clone)

	var sim := TurretFlightPhysics.new()
	sim.ground_y = ground_y
	sim.velocity = Vector3(
		randf_range(-5.0, 5.0),
		randf_range(20.0, 30.0),
		randf_range(-5.0, 5.0)
	)
	sim.angular_velocity = Vector3(
		randf_range(-3.5, 3.5),
		randf_range(-2.0, 2.0),
		randf_range(-3.5, 3.5)
	)
	container.add_child(sim)


# ===========================================================================
#  HELPERS
# ===========================================================================

func _apply_charred_material(root: Node) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.09, 0.1)
	mat.roughness = 0.92
	mat.metallic = 0.12
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.2, 0.03)
	mat.emission_energy_multiplier = 0.3
	_apply_mat_recursive(root, mat)


func _apply_mat_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_apply_mat_recursive(child, mat)


func _make_sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 8
	m.rings = 5
	return m


func _make_mat(blend: BaseMaterial3D.BlendMode) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = blend
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _play_heavy_explosion_sound() -> void:
	if has_node("/root/SoundManager"):
		get_node("/root/SoundManager").play_explosion(-0.5)
		return
	if ExplosionSounds.is_empty():
		return
	var p := AudioStreamPlayer.new()
	p.stream = ExplosionSounds.pick_random()
	p.bus = "Master"
	p.volume_db = 1.5
	p.pitch_scale = randf_range(0.78, 0.92)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ===========================================================================
#  CICLO DE VIDA
# ===========================================================================

func _process(delta: float) -> void:
	_age += delta

	# Decaimento rápido do flash (0 → 0.15s)
	if _flash_light and is_instance_valid(_flash_light):
		var flash_t := clampf(_age / 0.15, 0.0, 1.0)
		_flash_light.light_energy = lerpf(_flash_light.light_energy, 0.0, flash_t * flash_t * flash_t)
		if flash_t >= 1.0:
			_flash_light.queue_free()
			_flash_light = null

	# Decaimento da luz da bola de fogo (0 → 0.8s)
	if _fireball_light and is_instance_valid(_fireball_light):
		var fb_t := clampf(_age / 0.8, 0.0, 1.0)
		var fb_decay := 1.0 - (fb_t * fb_t)
		_fireball_light.light_energy *= fb_decay + 0.01
		if fb_t >= 1.0:
			_fireball_light.queue_free()
			_fireball_light = null

	# Oscilação natural da chama residual
	if _flicker_light and is_instance_valid(_flicker_light):
		var noise := sin(_age * 18.0) * 0.3 + cos(_age * 31.0) * 0.2
		_flicker_light.light_energy = clampf(5.5 + noise * 3.0, 1.5, 9.0)

	# Fade suave nos últimos 3 segundos
	if _age >= _lifetime - 3.0 and not _fading:
		_fading = true
		if _fire_particles:
			_fire_particles.emitting = false
		if _smoke_particles:
			# Reduz suavemente a emissão da fumaça
			var tween := create_tween()
			tween.tween_property(_smoke_particles, "amount", 5, 2.0)
		if _flicker_light:
			var tween2 := create_tween()
			tween2.tween_property(_flicker_light, "light_energy", 0.0, 2.5)

	if _age >= _lifetime:
		queue_free()


# ===========================================================================
#  CLASSE INTERNA — Física Balística da Torreta
# ===========================================================================

class TurretFlightPhysics extends Node:
	var ground_y: float = 0.0
	var velocity: Vector3 = Vector3.ZERO
	var angular_velocity: Vector3 = Vector3.ZERO
	var gravity: float = 28.0
	var bounces: int = 0
	var parent_node: Node3D = null
	var smoke_trail: CPUParticles3D = null
	var _trail_lifetime: float = 8.0
	var _trail_age: float = 0.0

	func _ready() -> void:
		parent_node = get_parent() as Node3D
		if parent_node:
			_create_trail()

	func _create_trail() -> void:
		smoke_trail = CPUParticles3D.new()
		smoke_trail.emitting = true
		smoke_trail.amount = 16
		smoke_trail.lifetime = 0.9
		smoke_trail.direction = Vector3.DOWN
		smoke_trail.spread = 12.0
		smoke_trail.gravity = Vector3(0, 3.0, 0)
		smoke_trail.initial_velocity_min = 0.8
		smoke_trail.initial_velocity_max = 2.5
		smoke_trail.scale_amount_min = 0.6
		smoke_trail.scale_amount_max = 2.0

		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		ramp.colors = PackedColorArray([
			Color(1.0, 0.45, 0.08, 0.75),
			Color(0.25, 0.22, 0.2, 0.6),
			Color(0.1, 0.1, 0.1, 0.0)
		])
		smoke_trail.color_ramp = ramp

		var sphere := SphereMesh.new()
		sphere.radius = 0.35
		sphere.height = 0.7
		smoke_trail.mesh = sphere

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		smoke_trail.material_override = mat
		parent_node.add_child(smoke_trail)

	func _physics_process(delta: float) -> void:
		if not parent_node:
			return

		_trail_age += delta

		velocity.y -= gravity * delta
		parent_node.global_position += velocity * delta

		parent_node.rotate_x(angular_velocity.x * delta)
		parent_node.rotate_y(angular_velocity.y * delta)
		parent_node.rotate_z(angular_velocity.z * delta)

		if parent_node.global_position.y <= ground_y:
			if bounces < 2 and absf(velocity.y) > 4.0:
				bounces += 1
				parent_node.global_position.y = ground_y
				velocity.y = -velocity.y * 0.3
				velocity.x *= 0.5
				velocity.z *= 0.5
				angular_velocity *= 0.4
			else:
				parent_node.global_position.y = ground_y
				velocity = Vector3.ZERO
				angular_velocity = Vector3.ZERO
				if smoke_trail:
					smoke_trail.emitting = false
				set_physics_process(false)

		# Limpa a torreta após timeout
		if _trail_age >= _trail_lifetime:
			if parent_node and is_instance_valid(parent_node):
				parent_node.queue_free()
			queue_free()
