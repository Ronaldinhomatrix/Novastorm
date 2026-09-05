class_name GroundVehicleWreckage
extends Node3D

## Explosão Cinematográfica Especializada para Veículos Terrestres (Tanques e Caminhões).
##
## Efeito 100% novo construído do zero, sem corte de peças ou herança das naves:
##   1. Detonação instantânea: Flash cegante + onda de choque no solo + core de plasma.
##   2. Bola de fogo em dois estágios: Burst inicial violento + convecção em cogumelo (combustível/munição).
##   3. Chuveiro de faíscas incandescentes em arco balístico com gravidade pesada.
##   4. Decalque de solo carbonizado (Scorch Mark) projetado diretamente na pista/ponte.
##   5. Chamas residuais no ponto de impacto + coluna volumétrica de fumaça preta subindo aos céus.
##   6. Impacto sonoro de artilharia pesada (grave com punch) + camera shake integrado.

const ExplosionSounds := [
	preload("res://assets/audio/explosion1.ogg"),
	preload("res://assets/audio/explosion2.ogg"),
]

var _lifetime: float = 6.0
var _age: float = 0.0
var _flash_light: OmniLight3D = null
var _fireball_light: OmniLight3D = null
var _flicker_light: OmniLight3D = null
var _fire_particles: CPUParticles3D = null
var _smoke_particles: CPUParticles3D = null
var _scorch_decal: Decal = null
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
	w.global_position = tank.global_position
	w.global_rotation = Vector3.ZERO
	w._build_explosion(true)
	return w


static func spawn_for_truck(truck: Node3D) -> GroundVehicleWreckage:
	if not truck or not is_instance_valid(truck):
		return null
	var parent := _get_scene_parent(truck)
	if not parent:
		return null
	var w := GroundVehicleWreckage.new()
	parent.add_child(w)
	w.global_position = truck.global_position
	w.global_rotation = Vector3.ZERO
	w._build_explosion(false)
	return w


static func _get_scene_parent(node: Node) -> Node:
	if node.get_tree() and node.get_tree().current_scene:
		return node.get_tree().current_scene
	if node.get_parent():
		return node.get_parent()
	return node.get_tree().root if node.get_tree() else null


# ---------------------------------------------------------------------------
# Construção Principal da Explosão
# ---------------------------------------------------------------------------

func _build_explosion(is_tank: bool) -> void:
	var intensity: float = 1.35 if is_tank else 1.15
	var blast_origin := Vector3(0.0, 1.8, 0.0)

	# 1. Flash de luz instantâneo e ultra-brilhante
	_build_detonation_flash(intensity)

	# 2. Onda de choque rente ao solo / pista
	_build_ground_shockwave(intensity)

	# 3. Núcleo de plasma / burst de fogo violento primário
	_build_primary_fireball(blast_origin, intensity)

	# 4. Segundo estágio: Bola de fogo de convecção térmica (combustível/munição subindo)
	_build_convection_fireball(blast_origin, intensity)

	# 5. Chuveiro de faíscas incandescentes em arco balístico com gravidade
	_build_spark_shower(blast_origin, 55 if is_tank else 45)

	# 6. Poeira e onda de pressão varrendo a pista horizontalmente
	_build_road_dust(intensity)

	# 7. Decalque de marca de queimado carbonizada no chão da ponte/estrada
	_build_scorch_mark(intensity)

	# 8. Fogo residual no solo + coluna densa de fumaça preta subindo
	_build_aftermath_effects(blast_origin, intensity)

	# 9. Som pesado de artilharia grave
	_play_heavy_sound(is_tank)

	# 10. Camera Shake para impacto físico visceral
	_trigger_shake(0.65 if is_tank else 0.50)


# ===========================================================================
# 1. Flash Cegante de Detonação
# ===========================================================================

func _build_detonation_flash(mult: float) -> void:
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.96, 0.85)
	_flash_light.light_energy = 160.0 * mult
	_flash_light.omni_range = 55.0 * mult
	_flash_light.omni_attenuation = 0.5
	_flash_light.position = Vector3(0, 2.5, 0)
	add_child(_flash_light)

	# Esfera de plasma branco instantânea no ponto zero
	var core := CPUParticles3D.new()
	core.name = "PlasmaCore"
	core.emitting = true
	core.one_shot = true
	core.explosiveness = 1.0
	core.amount = 1
	core.lifetime = 0.15
	core.position = Vector3(0, 2.5, 0)
	core.gravity = Vector3.ZERO
	core.scale_amount_min = 14.0 * mult
	core.scale_amount_max = 18.0 * mult

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray([
		Color(5.0, 4.5, 3.0, 1.0),
		Color(3.0, 1.8, 0.4, 0.9),
		Color(1.0, 0.2, 0.0, 0.0)
	])
	core.color_ramp = ramp
	core.mesh = _make_sphere(0.5)
	core.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(core)


# ===========================================================================
# 2. Onda de Choque Rente ao Solo
# ===========================================================================

func _build_ground_shockwave(mult: float) -> void:
	var wave := CPUParticles3D.new()
	wave.name = "Shockwave"
	wave.emitting = true
	wave.one_shot = true
	wave.explosiveness = 1.0
	wave.amount = 45
	wave.lifetime = 0.42
	wave.position = Vector3(0, 0.4, 0)
	wave.direction = Vector3.UP
	wave.spread = 90.0
	wave.flatness = 0.96  # Quase 100% horizontal
	wave.gravity = Vector3.ZERO
	wave.initial_velocity_min = 45.0 * mult
	wave.initial_velocity_max = 75.0 * mult
	wave.scale_amount_min = 2.0
	wave.scale_amount_max = 5.0 * mult

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	ramp.colors = PackedColorArray([
		Color(2.5, 2.0, 1.2, 0.9),
		Color(1.5, 0.8, 0.2, 0.5),
		Color(0.4, 0.15, 0.05, 0.0)
	])
	wave.color_ramp = ramp
	wave.mesh = _make_sphere(0.4)
	wave.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(wave)


# ===========================================================================
# 3. Bola de Fogo Primária (Violenta & Volumétrica)
# ===========================================================================

func _build_primary_fireball(offset: Vector3, mult: float) -> void:
	var fb := CPUParticles3D.new()
	fb.name = "PrimaryFireball"
	fb.emitting = true
	fb.one_shot = true
	fb.explosiveness = 0.94
	fb.amount = 48
	fb.lifetime = 0.65
	fb.position = offset
	fb.direction = Vector3.UP
	fb.spread = 65.0
	fb.gravity = Vector3(0, 6.0, 0)
	fb.initial_velocity_min = 10.0 * mult
	fb.initial_velocity_max = 28.0 * mult
	fb.angular_velocity_min = -150.0
	fb.angular_velocity_max = 150.0
	fb.scale_amount_min = 4.0 * mult
	fb.scale_amount_max = 10.5 * mult

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.40, 0.70, 1.0])
	ramp.colors = PackedColorArray([
		Color(4.5, 4.0, 2.0, 1.0),   # Branco-amarelo nuclear
		Color(2.8, 1.4, 0.2, 1.0),   # Dourado elétrico
		Color(1.8, 0.45, 0.03, 0.9), # Laranja fogo vívido
		Color(0.7, 0.1, 0.01, 0.5),  # Vermelho escurecendo
		Color(0.12, 0.02, 0.0, 0.0)  # Fade para cinzas
	])
	fb.color_ramp = ramp
	fb.mesh = _make_sphere(0.6)
	fb.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(fb)

	# Luz laranja acompanhando a bola de fogo
	_fireball_light = OmniLight3D.new()
	_fireball_light.position = offset + Vector3.UP * 2.0
	_fireball_light.light_color = Color(1.0, 0.6, 0.12)
	_fireball_light.light_energy = 55.0 * mult
	_fireball_light.omni_range = 38.0 * mult
	_fireball_light.omni_attenuation = 1.0
	add_child(_fireball_light)


# ===========================================================================
# 4. Segundo Estágio: Bola de Fogo de Convecção Térmica (Updraft)
# ===========================================================================

func _build_convection_fireball(offset: Vector3, mult: float) -> void:
	# Simula o efeito cogumelo de combustível pesado explodindo e subindo
	var col := CPUParticles3D.new()
	col.name = "MushroomFire"
	col.emitting = true
	col.one_shot = true
	col.explosiveness = 0.88
	col.amount = 36
	col.lifetime = 1.1
	col.position = offset + Vector3.UP * 1.0
	col.direction = Vector3.UP
	col.spread = 35.0
	col.gravity = Vector3(0, 14.0, 0) # Forte impulso térmico para cima
	col.initial_velocity_min = 6.0 * mult
	col.initial_velocity_max = 18.0 * mult
	col.angular_velocity_min = -80.0
	col.angular_velocity_max = 80.0
	col.scale_amount_min = 5.0 * mult
	col.scale_amount_max = 13.0 * mult

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.55, 0.85, 1.0])
	ramp.colors = PackedColorArray([
		Color(2.5, 1.5, 0.3, 1.0),
		Color(1.8, 0.6, 0.08, 0.95),
		Color(0.8, 0.15, 0.02, 0.7),
		Color(0.25, 0.18, 0.16, 0.5), # Vira fumaça grossa
		Color(0.08, 0.08, 0.08, 0.0)
	])
	col.color_ramp = ramp
	col.mesh = _make_sphere(0.65)
	col.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(col)


# ===========================================================================
# 5. Chuveiro de Faíscas Incandescentes em Arco Balístico
# ===========================================================================

func _build_spark_shower(offset: Vector3, count: int) -> void:
	var sp := CPUParticles3D.new()
	sp.name = "SparkShower"
	sp.emitting = true
	sp.one_shot = true
	sp.explosiveness = 0.98
	sp.amount = count
	sp.lifetime = 1.2
	sp.position = offset
	sp.direction = Vector3.UP
	sp.spread = 75.0
	sp.gravity = Vector3(0, -26.0, 0) # Gravidade real forte
	sp.initial_velocity_min = 22.0
	sp.initial_velocity_max = 50.0
	sp.scale_amount_min = 0.25
	sp.scale_amount_max = 0.7

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 0.8, 1.0])
	ramp.colors = PackedColorArray([
		Color(4.0, 3.2, 1.5, 1.0),
		Color(2.2, 1.0, 0.15, 0.9),
		Color(1.0, 0.3, 0.02, 0.7),
		Color(0.5, 0.05, 0.0, 0.0)
	])
	sp.color_ramp = ramp
	sp.mesh = _make_sphere(0.18)
	sp.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(sp)


# ===========================================================================
# 6. Poeira da Estrada
# ===========================================================================

func _build_road_dust(mult: float) -> void:
	var dust := CPUParticles3D.new()
	dust.name = "RoadDust"
	dust.emitting = true
	dust.one_shot = true
	dust.explosiveness = 0.92
	dust.amount = 28
	dust.lifetime = 1.4
	dust.position = Vector3(0, 0.5, 0)
	dust.direction = Vector3.UP
	dust.spread = 85.0
	dust.flatness = 0.8
	dust.gravity = Vector3(0, 1.0, 0)
	dust.initial_velocity_min = 12.0 * mult
	dust.initial_velocity_max = 30.0 * mult
	dust.scale_amount_min = 3.5 * mult
	dust.scale_amount_max = 9.0 * mult

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.45, 0.38, 0.3, 0.7),
		Color(0.35, 0.3, 0.25, 0.55),
		Color(0.25, 0.22, 0.2, 0.3),
		Color(0.15, 0.15, 0.15, 0.0)
	])
	dust.color_ramp = ramp
	dust.mesh = _make_sphere(0.5)
	dust.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_MIX)
	add_child(dust)


# ===========================================================================
# 7. Decalque de Solo Carbonizado (Scorch Mark)
# ===========================================================================

func _build_scorch_mark(mult: float) -> void:
	_scorch_decal = Decal.new()
	_scorch_decal.name = "ScorchDecal"
	_scorch_decal.size = Vector3(14.0 * mult, 6.0, 14.0 * mult)
	_scorch_decal.position = Vector3(0, 0.5, 0)

	# Cria textura radial de queimadura escura procedural
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
	grad.colors = PackedColorArray([
		Color(0.04, 0.04, 0.04, 0.95), # Centro preto carvão
		Color(0.08, 0.07, 0.06, 0.85),
		Color(0.12, 0.09, 0.06, 0.45),
		Color(0.0, 0.0, 0.0, 0.0)      # Borda suave
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128

	_scorch_decal.texture_albedo = tex
	add_child(_scorch_decal)


# ===========================================================================
# 8. Efeitos Residuais: Fogo no Solo + Coluna de Fumaça Densa
# ===========================================================================

func _build_aftermath_effects(offset: Vector3, mult: float) -> void:
	# Fogo residual lambendo o solo onde o veículo explodiu
	_fire_particles = CPUParticles3D.new()
	_fire_particles.name = "GroundFire"
	_fire_particles.emitting = true
	_fire_particles.amount = 22
	_fire_particles.lifetime = 0.7
	_fire_particles.position = Vector3(0, 0.8, 0)
	_fire_particles.direction = Vector3.UP
	_fire_particles.spread = 40.0
	_fire_particles.gravity = Vector3(0, 4.5, 0)
	_fire_particles.initial_velocity_min = 1.8
	_fire_particles.initial_velocity_max = 5.0
	_fire_particles.scale_amount_min = 1.2 * mult
	_fire_particles.scale_amount_max = 3.2 * mult

	var fire_ramp := Gradient.new()
	fire_ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	fire_ramp.colors = PackedColorArray([
		Color(2.2, 1.6, 0.3, 1.0),
		Color(1.5, 0.5, 0.05, 0.9),
		Color(0.8, 0.15, 0.02, 0.7),
		Color(0.15, 0.02, 0.0, 0.0)
	])
	_fire_particles.color_ramp = fire_ramp
	_fire_particles.mesh = _make_sphere(0.4)
	_fire_particles.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(_fire_particles)

	# Luz trêmula do fogo no chão
	_flicker_light = OmniLight3D.new()
	_flicker_light.name = "GroundFireLight"
	_flicker_light.position = Vector3(0, 1.5, 0)
	_flicker_light.light_color = Color(1.0, 0.5, 0.08)
	_flicker_light.light_energy = 6.0
	_flicker_light.omni_range = 20.0
	_flicker_light.omni_attenuation = 1.5
	add_child(_flicker_light)

	# Coluna monumental de fumaça preta densa subindo aos céus
	_smoke_particles = CPUParticles3D.new()
	_smoke_particles.name = "SmokeColumn"
	_smoke_particles.emitting = true
	_smoke_particles.amount = 36
	_smoke_particles.lifetime = 3.2
	_smoke_particles.position = Vector3(0, 1.2, 0)
	_smoke_particles.direction = Vector3(0.06, 1.0, 0.03).normalized()
	_smoke_particles.spread = 16.0
	_smoke_particles.gravity = Vector3(0, 3.5, 0) # Flutuabilidade térmica
	_smoke_particles.initial_velocity_min = 3.5
	_smoke_particles.initial_velocity_max = 8.5
	_smoke_particles.angular_velocity_min = -35.0
	_smoke_particles.angular_velocity_max = 35.0
	_smoke_particles.scale_amount_min = 2.5 * mult
	_smoke_particles.scale_amount_max = 8.5 * mult

	var smoke_ramp := Gradient.new()
	smoke_ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.55, 1.0])
	smoke_ramp.colors = PackedColorArray([
		Color(0.2, 0.18, 0.16, 0.9),
		Color(0.13, 0.12, 0.11, 0.8),
		Color(0.08, 0.07, 0.07, 0.45),
		Color(0.04, 0.04, 0.04, 0.0)
	])
	_smoke_particles.color_ramp = smoke_ramp
	_smoke_particles.mesh = _make_sphere(0.6)
	_smoke_particles.material_override = _make_mat(BaseMaterial3D.BLEND_MODE_MIX)
	add_child(_smoke_particles)


# ===========================================================================
# 9. Áudio Pesado de Artilharia
# ===========================================================================

func _play_heavy_sound(is_tank: bool) -> void:
	if has_node("/root/SoundManager"):
		get_node("/root/SoundManager").play_explosion(1.0 if is_tank else 0.5)
		return
	if ExplosionSounds.is_empty():
		return
	var p := AudioStreamPlayer.new()
	p.stream = ExplosionSounds.pick_random()
	p.bus = "Master"
	p.volume_db = 2.5
	p.pitch_scale = randf_range(0.75, 0.88) if is_tank else randf_range(0.85, 0.95)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ===========================================================================
# 10. Camera Shake
# ===========================================================================

func _trigger_shake(intensity: float) -> void:
	var tree := get_tree()
	if not tree:
		return
	var controller := tree.root.find_child("GameController", true, false)
	if controller and controller.has_method("trigger_camera_shake"):
		controller.trigger_camera_shake(intensity, 0.38)


# ===========================================================================
# Helpers de Malhas e Materiais
# ===========================================================================

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


# ===========================================================================
# Ciclo de Vida e Fade Out
# ===========================================================================

func _process(delta: float) -> void:
	_age += delta

	# Decaimento rápido do flash de luz (0 → 0.22s)
	if _flash_light and is_instance_valid(_flash_light):
		var ft := clampf(_age / 0.22, 0.0, 1.0)
		_flash_light.light_energy = lerpf(_flash_light.light_energy, 0.0, ft * ft)
		if ft >= 1.0:
			_flash_light.queue_free()
			_flash_light = null

	# Decaimento da luz da bola de fogo (0 → 0.75s)
	if _fireball_light and is_instance_valid(_fireball_light):
		var fbt := clampf(_age / 0.75, 0.0, 1.0)
		_fireball_light.light_energy = lerpf(_fireball_light.light_energy, 0.0, fbt)
		if fbt >= 1.0:
			_fireball_light.queue_free()
			_fireball_light = null

	# Oscilação do fogo no chão
	if _flicker_light and is_instance_valid(_flicker_light):
		var noise := sin(_age * 20.0) * 0.35 + cos(_age * 33.0) * 0.2
		_flicker_light.light_energy = clampf(5.5 + noise * 3.0, 1.0, 8.5)

	# Fade suave no final da vida do efeito (últimos 2.2 segundos)
	if _age >= _lifetime - 2.2 and not _fading:
		_fading = true
		if _fire_particles:
			_fire_particles.emitting = false
		if _smoke_particles:
			_smoke_particles.emitting = false
		if _flicker_light:
			var tw := create_tween()
			tw.tween_property(_flicker_light, "light_energy", 0.0, 1.8)
		if _scorch_decal:
			var tw2 := create_tween()
			tw2.tween_property(_scorch_decal, "modulate:a", 0.0, 2.0)

	if _age >= _lifetime:
		queue_free()
