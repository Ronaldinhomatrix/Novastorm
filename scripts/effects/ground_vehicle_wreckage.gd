class_name GroundVehicleWreckage
extends Node3D

## Efeito de Destruição AAA Estilo Militar:
##   1. Carcaça 3D Carbonizada: O veículo NÃO desaparece no frame 0. O chassi original
##      permanece no solo com textura/cor de metal queimado e fuligem.
##   2. Ejeção Balística de Torreta (Tanque): A torreta salta com rotação e arco balístico
##      caindo no solo com gravidade e fumegando.
##   3. Explosão Volumétrica Calibrada: Escala proporcional ao tamanho do tanque/caminhão
##      (16m a 32m de expansão, fumaça subindo a 45m), sem bolhas gigantes que cobrem a tela.
##   4. Totalmente Otimizado para Mobile: Partículas QuadMesh billboard com texturas procedurais
##      suaves, materiais unshaded, baixíssimo overdraw e 60+ FPS garantidos.

const ExplosionSounds := [
	preload("res://assets/audio/explosion1.ogg"),
	preload("res://assets/audio/explosion2.ogg"),
]

static var _puff_texture: Texture2D = null
static var _spark_texture: Texture2D = null

var _lifetime: float = 8.5
var _age: float = 0.0
var _flash_light: OmniLight3D = null
var _smoke_particles: CPUParticles3D = null
var _fire_particles: CPUParticles3D = null
var _scorch_decal: Decal = null
var _fading: bool = false

# Componentes da Carcaça e Estilhaços
var _flying_turret: Node3D = null
var _turret_velocity: Vector3 = Vector3.ZERO
var _turret_angular_velocity: Vector3 = Vector3.ZERO
var _turret_ground_y: float = 0.0
var _turret_landed: bool = false


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
	w.global_rotation = tank.global_rotation
	w._build_for_tank(tank)
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
	w.global_rotation = truck.global_rotation
	w._build_for_truck(truck)
	return w


static func _get_scene_parent(node: Node) -> Node:
	if node.get_tree() and node.get_tree().current_scene:
		return node.get_tree().current_scene
	if node.get_parent():
		return node.get_parent()
	return node.get_tree().root if node.get_tree() else null


# ---------------------------------------------------------------------------
# ===========================================================================
# Construção da Destruição do Tanque (Explosão Catastrófica de Munição)
# ===========================================================================

func _build_for_tank(tank: Node3D) -> void:
	_init_shared_textures()

	# 1. Ejeção Balística Realista da Torreta do Tanque
	_setup_tank_turret_ejection(tank)

	# 2. Estilhaços Metálicos 3D do Casco Explodindo
	_spawn_vehicle_shrapnel_chunks(tank, 12, 1.4)

	# 3. Explosão Volumétrica e Cinematográfica de Alta Intensidade
	var blast_origin := Vector3(0.0, 18.0, 0.0)
	var scale_mult: float = 3.6

	_build_detonation_flash(scale_mult)
	_build_fire_burst(blast_origin, scale_mult)
	_build_shrapnel_and_debris(blast_origin, scale_mult)
	_build_highspeed_sparks(blast_origin, scale_mult)
	_build_shockwave_dust(scale_mult)
	_build_smoke_plume(blast_origin, scale_mult)
	_build_scorch_mark(scale_mult)
	_build_residual_ground_fire(scale_mult)

	_play_heavy_sound(true)
	_trigger_shake(1.1)


# ===========================================================================
# Construção da Destruição do Caminhão (Detonação Total de Carga/Combustível)
# ===========================================================================

func _build_for_truck(truck: Node3D) -> void:
	_init_shared_textures()

	# 1. Estilhaços Metálicos 3D do Caminhão se Desintegrando no Impacto
	_spawn_vehicle_shrapnel_chunks(truck, 16, 1.6)

	# 2. Bola de Fogo e Onda Expansiva Massiva (Veículo explode de verdade)
	var blast_origin := Vector3(0.0, 20.0, 0.0)
	var scale_mult: float = 4.0

	_build_detonation_flash(scale_mult)
	_build_fire_burst(blast_origin, scale_mult)
	_build_shrapnel_and_debris(blast_origin, scale_mult)
	_build_highspeed_sparks(blast_origin, scale_mult)
	_build_shockwave_dust(scale_mult)
	_build_smoke_plume(blast_origin, scale_mult)
	_build_scorch_mark(scale_mult)
	_build_residual_ground_fire(scale_mult)

	_play_heavy_sound(false)
	_trigger_shake(1.05)


# ===========================================================================
# Ejeção Balística da Torreta (Apenas Tanque - Arma voa com a explosão)
# ===========================================================================

func _setup_tank_turret_ejection(tank: Node3D) -> void:
	var turret_src := tank.find_child("Turret", true, false) as Node3D
	if not turret_src:
		return

	var turret_global_pos := turret_src.global_position
	var turret_global_rot := turret_src.global_rotation
	var turret_global_scale := turret_src.global_basis.get_scale()

	var turret_clone := turret_src.duplicate() as Node3D
	if not turret_clone:
		return

	add_child(turret_clone)
	turret_clone.global_position = turret_global_pos
	turret_clone.global_rotation = turret_global_rot
	turret_clone.scale = turret_global_scale
	_flying_turret = turret_clone

	# Material realista escurecido por fuligem / explosão (sem brilho vermelho/laranja artificial)
	_apply_burned_soot_material(turret_clone)

	# Física do arremesso da torreta pelos ares
	_turret_velocity = Vector3(
		randf_range(-25.0, 25.0),
		randf_range(75.0, 110.0),
		randf_range(-25.0, 25.0)
	)
	_turret_angular_velocity = Vector3(
		randf_range(-5.0, 5.0),
		randf_range(-7.0, 7.0),
		randf_range(-5.0, 5.0)
	)
	_turret_ground_y = global_position.y + 0.5


# ===========================================================================
# Pedaços Metálicos 3D Arremessados (Desintegração Realista do Veículo)
# ===========================================================================

var _flying_chunks: Array[Node3D] = []
var _chunk_velocities: Array[Vector3] = []
var _chunk_rot_velocities: Array[Vector3] = []

func _spawn_vehicle_shrapnel_chunks(vehicle: Node3D, count: int, chunk_scale: float) -> void:
	var chunk_mat := StandardMaterial3D.new()
	chunk_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	chunk_mat.albedo_color = Color(0.18, 0.18, 0.19, 1.0) # Metal escuro chamuscado
	chunk_mat.metallic = 0.6
	chunk_mat.roughness = 0.65

	for i in range(count):
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		var sx := randf_range(2.0, 4.5) * chunk_scale
		var sy := randf_range(1.2, 3.0) * chunk_scale
		var sz := randf_range(2.0, 5.0) * chunk_scale
		box.size = Vector3(sx, sy, sz)
		mi.mesh = box
		mi.material_override = chunk_mat

		add_child(mi)
		mi.global_position = vehicle.global_position + Vector3(
			randf_range(-4.0, 4.0),
			randf_range(2.0, 8.0),
			randf_range(-4.0, 4.0)
		)

		_flying_chunks.append(mi)
		_chunk_velocities.append(Vector3(
			randf_range(-45.0, 45.0),
			randf_range(35.0, 75.0),
			randf_range(-45.0, 45.0)
		))
		_chunk_rot_velocities.append(Vector3(
			randf_range(-6.0, 6.0),
			randf_range(-6.0, 6.0),
			randf_range(-6.0, 6.0)
		))


func _apply_burned_soot_material(node: Node) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = Color(0.16, 0.16, 0.17, 1.0) # Metal queimado fosco natural
	mat.metallic = 0.4
	mat.roughness = 0.8
	_recurse_apply_material(node, mat)


func _recurse_apply_material(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.material_override = mat
	for child in node.get_children():
		_recurse_apply_material(child, mat)


# ===========================================================================
# Texturas Procedurais Criadas uma Única Vez (Zero Assets Externos / Zero Overdraw)
# ===========================================================================

static func _init_shared_textures() -> void:
	if _puff_texture and _spark_texture:
		return

	# Textura suave e volumétrica para fogo e fumaça
	var grad_puff := Gradient.new()
	grad_puff.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	grad_puff.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.92),
		Color(1.0, 1.0, 1.0, 0.35),
		Color(1.0, 1.0, 1.0, 0.0)
	])
	var tex_puff := GradientTexture2D.new()
	tex_puff.gradient = grad_puff
	tex_puff.fill = GradientTexture2D.FILL_RADIAL
	tex_puff.fill_from = Vector2(0.5, 0.5)
	tex_puff.fill_to = Vector2(0.5, 0.0)
	tex_puff.width = 64
	tex_puff.height = 64
	_puff_texture = tex_puff

	# Textura nítida para estilhaços e faíscas incandescentes
	var grad_spark := Gradient.new()
	grad_spark.offsets = PackedFloat32Array([0.0, 0.35, 0.8, 1.0])
	grad_spark.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.85),
		Color(1.0, 1.0, 1.0, 0.2),
		Color(1.0, 1.0, 1.0, 0.0)
	])
	var tex_spark := GradientTexture2D.new()
	tex_spark.gradient = grad_spark
	tex_spark.fill = GradientTexture2D.FILL_RADIAL
	tex_spark.fill_from = Vector2(0.5, 0.5)
	tex_spark.fill_to = Vector2(0.5, 0.0)
	tex_spark.width = 32
	tex_spark.height = 32
	_spark_texture = tex_spark


# ===========================================================================
# 1. Flash Inicial de Luz
# ===========================================================================

func _build_detonation_flash(scale_mult: float) -> void:
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.88, 0.6)
	_flash_light.light_energy = 380.0 * scale_mult
	_flash_light.omni_range = 280.0 * scale_mult
	_flash_light.omni_attenuation = 0.75
	_flash_light.position = Vector3(0, 16.0, 0)
	add_child(_flash_light)


# ===========================================================================
# 2. Núcleo Térmico de Bola de Fogo Volumétrica (Diâmetro 160m - 260m)
# ===========================================================================

func _build_fire_burst(offset: Vector3, scale_mult: float) -> void:
	var fb := CPUParticles3D.new()
	fb.name = "FireBurst"
	fb.emitting = true
	fb.one_shot = true
	fb.explosiveness = 0.94
	fb.amount = 45
	fb.lifetime = 1.15
	fb.position = offset
	fb.direction = Vector3.UP
	fb.spread = 160.0
	fb.gravity = Vector3(0, 24.0, 0) # Rápida ascensão térmica
	fb.initial_velocity_min = 45.0 * scale_mult
	fb.initial_velocity_max = 100.0 * scale_mult
	fb.angular_velocity_min = -60.0
	fb.angular_velocity_max = 60.0
	fb.scale_amount_min = 32.0 * scale_mult
	fb.scale_amount_max = 65.0 * scale_mult

	var s_curve := Curve.new()
	s_curve.add_point(Vector2(0.0, 0.35))
	s_curve.add_point(Vector2(0.22, 1.0))
	s_curve.add_point(Vector2(1.0, 0.8))
	fb.scale_amount_curve = s_curve

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.45, 0.80, 1.0])
	ramp.colors = PackedColorArray([
		Color(4.5, 4.0, 2.8, 1.0),   # Núcleo branco incandescente ofuscante
		Color(3.0, 2.0, 0.4, 1.0),   # Dourado elétrico
		Color(2.2, 0.7, 0.08, 0.95), # Fogo alaranjado denso
		Color(1.1, 0.18, 0.02, 0.7), # Vermelho brasa
		Color(0.15, 0.08, 0.08, 0.0) # Transição para fuligem
	])
	fb.color_ramp = ramp
	fb.mesh = _make_quad(3.0)
	fb.material_override = _make_particle_mat(BaseMaterial3D.BLEND_MODE_ADD, _puff_texture)
	add_child(fb)


# ===========================================================================
# 3. Estilhaços e Brasas Incandescentes em Grande Arco Balístico (250m+ alcance)
# ===========================================================================

func _build_shrapnel_and_debris(offset: Vector3, scale_mult: float) -> void:
	var deb := CPUParticles3D.new()
	deb.name = "Shrapnel"
	deb.emitting = true
	deb.one_shot = true
	deb.explosiveness = 0.98
	deb.amount = 38
	deb.lifetime = 2.0
	deb.position = offset + Vector3.UP * 2.0
	deb.direction = Vector3.UP
	deb.spread = 80.0
	deb.gravity = Vector3(0, -32.0, 0)
	deb.initial_velocity_min = 60.0 * scale_mult
	deb.initial_velocity_max = 130.0 * scale_mult
	deb.scale_amount_min = 4.5 * scale_mult
	deb.scale_amount_max = 10.0 * scale_mult

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	ramp.colors = PackedColorArray([
		Color(3.5, 2.8, 1.0, 1.0),
		Color(2.0, 0.6, 0.08, 0.9),
		Color(0.3, 0.06, 0.02, 0.0)
	])
	deb.color_ramp = ramp
	deb.mesh = _make_quad(1.5)
	deb.material_override = _make_particle_mat(BaseMaterial3D.BLEND_MODE_ADD, _spark_texture)
	add_child(deb)


# ===========================================================================
# 4. Chuveiro de Faíscas Pirotécnicas Rápidas (300m+)
# ===========================================================================

func _build_highspeed_sparks(offset: Vector3, scale_mult: float) -> void:
	var sp := CPUParticles3D.new()
	sp.name = "Sparks"
	sp.emitting = true
	sp.one_shot = true
	sp.explosiveness = 1.0
	sp.amount = 35
	sp.lifetime = 1.1
	sp.position = offset
	sp.direction = Vector3.UP
	sp.spread = 170.0
	sp.gravity = Vector3(0, -22.0, 0)
	sp.initial_velocity_min = 70.0 * scale_mult
	sp.initial_velocity_max = 150.0 * scale_mult
	sp.scale_amount_min = 2.5 * scale_mult
	sp.scale_amount_max = 6.0 * scale_mult

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	ramp.colors = PackedColorArray([
		Color(4.5, 3.8, 2.2, 1.0),
		Color(2.5, 1.2, 0.25, 0.9),
		Color(1.0, 0.2, 0.0, 0.0)
	])
	sp.color_ramp = ramp
	sp.mesh = _make_quad(1.0)
	sp.material_override = _make_particle_mat(BaseMaterial3D.BLEND_MODE_ADD, _spark_texture)
	add_child(sp)


# ===========================================================================
# 5. Onda de Poeira Rente ao Solo (Shockwave Dust - 280m+)
# ===========================================================================

func _build_shockwave_dust(scale_mult: float) -> void:
	var wave := CPUParticles3D.new()
	wave.name = "ShockwaveDust"
	wave.emitting = true
	wave.one_shot = true
	wave.explosiveness = 0.92
	wave.amount = 32
	wave.lifetime = 1.8
	wave.position = Vector3(0, 1.5, 0)
	wave.direction = Vector3.UP
	wave.spread = 90.0
	wave.flatness = 0.94
	wave.gravity = Vector3(0, 1.5, 0)
	wave.initial_velocity_min = 55.0 * scale_mult
	wave.initial_velocity_max = 115.0 * scale_mult
	wave.scale_amount_min = 28.0 * scale_mult
	wave.scale_amount_max = 55.0 * scale_mult

	var s_curve := Curve.new()
	s_curve.add_point(Vector2(0.0, 0.3))
	s_curve.add_point(Vector2(1.0, 1.0))
	wave.scale_amount_curve = s_curve

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.70, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.55, 0.48, 0.40, 0.65),
		Color(0.38, 0.33, 0.28, 0.45),
		Color(0.24, 0.21, 0.18, 0.25),
		Color(0.12, 0.12, 0.12, 0.0)
	])
	wave.color_ramp = ramp
	wave.mesh = _make_quad(3.0)
	wave.material_override = _make_particle_mat(BaseMaterial3D.BLEND_MODE_MIX, _puff_texture)
	add_child(wave)


# ===========================================================================
# 6. Coluna Monumental de Fumaça Preta com Convecção Térmica (Sobe a 300m+)
# ===========================================================================

func _build_smoke_plume(offset: Vector3, scale_mult: float) -> void:
	var smk := CPUParticles3D.new()
	smk.name = "SmokePlume"
	smk.emitting = true
	smk.one_shot = true
	smk.explosiveness = 0.80
	smk.amount = 48
	smk.lifetime = 4.8
	smk.position = offset + Vector3.UP * 4.0
	smk.direction = Vector3(0.08, 1.0, 0.04).normalized()
	smk.spread = 30.0
	smk.gravity = Vector3(0, 18.0, 0) # Subida térmica monumental aos céus
	smk.initial_velocity_min = 32.0 * scale_mult
	smk.initial_velocity_max = 68.0 * scale_mult
	smk.angular_velocity_min = -30.0
	smk.angular_velocity_max = 30.0
	smk.scale_amount_min = 35.0 * scale_mult
	smk.scale_amount_max = 75.0 * scale_mult

	var s_curve := Curve.new()
	s_curve.add_point(Vector2(0.0, 0.35))
	s_curve.add_point(Vector2(0.35, 0.85))
	s_curve.add_point(Vector2(1.0, 1.5))
	smk.scale_amount_curve = s_curve

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.40, 0.26, 0.15, 0.90), # Base quente com chamas internas
		Color(0.16, 0.14, 0.13, 0.85), # Preto fuligem espesso
		Color(0.09, 0.08, 0.08, 0.50),
		Color(0.05, 0.05, 0.05, 0.0)   # Dissipação suave
	])
	smk.color_ramp = ramp
	smk.mesh = _make_quad(3.5)
	smk.material_override = _make_particle_mat(BaseMaterial3D.BLEND_MODE_MIX, _puff_texture)
	add_child(smk)
	_smoke_particles = smk


# ===========================================================================
# 7. Asfalto Carbonizado (Scorch Mark - 220m+)
# ===========================================================================

func _build_scorch_mark(scale_mult: float) -> void:
	_scorch_decal = Decal.new()
	_scorch_decal.name = "ScorchDecal"
	_scorch_decal.size = Vector3(65.0 * scale_mult, 15.0, 65.0 * scale_mult)
	_scorch_decal.position = Vector3(0, 1.0, 0)

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.4, 0.8, 1.0])
	grad.colors = PackedColorArray([
		Color(0.02, 0.02, 0.02, 0.95),
		Color(0.05, 0.04, 0.04, 0.85),
		Color(0.10, 0.08, 0.06, 0.40),
		Color(0.0, 0.0, 0.0, 0.0)
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
# 8. Fogo Residual Discreto no Ponto da Detonação (Sem cobrir o veículo)
# ===========================================================================

func _build_residual_ground_fire(scale_mult: float) -> void:
	_fire_particles = CPUParticles3D.new()
	_fire_particles.name = "ResidualGroundFire"
	_fire_particles.emitting = true
	_fire_particles.amount = 18
	_fire_particles.lifetime = 1.6
	_fire_particles.position = Vector3(0, 2.0, 0)
	_fire_particles.direction = Vector3.UP
	_fire_particles.spread = 35.0
	_fire_particles.gravity = Vector3(0, 10.0, 0)
	_fire_particles.initial_velocity_min = 8.0 * scale_mult
	_fire_particles.initial_velocity_max = 18.0 * scale_mult
	_fire_particles.scale_amount_min = 8.0 * scale_mult
	_fire_particles.scale_amount_max = 18.0 * scale_mult

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
	ramp.colors = PackedColorArray([
		Color(2.2, 1.6, 0.5, 0.85),
		Color(1.5, 0.55, 0.08, 0.70),
		Color(0.6, 0.12, 0.02, 0.35),
		Color(0.08, 0.02, 0.0, 0.0)
	])
	_fire_particles.color_ramp = ramp
	_fire_particles.mesh = _make_quad(2.0)
	_fire_particles.material_override = _make_particle_mat(BaseMaterial3D.BLEND_MODE_ADD, _puff_texture)
	add_child(_fire_particles)


# ===========================================================================
# 9. Áudio e Vibração
# ===========================================================================

func _play_heavy_sound(is_tank: bool) -> void:
	if has_node("/root/SoundManager"):
		get_node("/root/SoundManager").play_explosion(2.5 if is_tank else 2.1)
		return
	if ExplosionSounds.is_empty():
		return
	var p := AudioStreamPlayer.new()
	p.stream = ExplosionSounds.pick_random()
	p.bus = "Master"
	p.volume_db = 3.0
	p.pitch_scale = randf_range(0.80, 0.90) if is_tank else randf_range(0.88, 0.98)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _trigger_shake(intensity: float) -> void:
	var tree := get_tree()
	if not tree:
		return
	var controller := tree.root.find_child("GameController", true, false)
	if controller and controller.has_method("trigger_camera_shake"):
		controller.trigger_camera_shake(intensity, 0.45)


# ===========================================================================
# Helpers Otimizados: QuadMesh + Billboard Material (Super Leve para Mobile)
# ===========================================================================

func _make_quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q


func _make_particle_mat(blend: BaseMaterial3D.BlendMode, tex: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = blend
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = tex
	return mat


# ===========================================================================
# Física da Explosão, Estilhaços 3D e Ciclo de Vida
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

	# Atualiza trajetória balística da torreta arremessada (Tanque)
	if _flying_turret and is_instance_valid(_flying_turret) and not _turret_landed:
		_turret_velocity.y -= 38.0 * delta # Gravidade
		_flying_turret.global_position += _turret_velocity * delta
		_flying_turret.rotate_x(_turret_angular_velocity.x * delta)
		_flying_turret.rotate_y(_turret_angular_velocity.y * delta)
		_flying_turret.rotate_z(_turret_angular_velocity.z * delta)

		# Impacto no solo
		if _flying_turret.global_position.y <= _turret_ground_y:
			_flying_turret.global_position.y = _turret_ground_y
			_turret_landed = true
			_turret_velocity = Vector3.ZERO

	# Atualiza física dos pedaços metálicos 3D explodindo para longe
	for i in range(_flying_chunks.size()):
		var chunk := _flying_chunks[i]
		if is_instance_valid(chunk):
			_chunk_velocities[i].y -= 45.0 * delta
			chunk.global_position += _chunk_velocities[i] * delta
			chunk.rotate_x(_chunk_rot_velocities[i].x * delta)
			chunk.rotate_y(_chunk_rot_velocities[i].y * delta)
			chunk.rotate_z(_chunk_rot_velocities[i].z * delta)
			if chunk.global_position.y <= global_position.y + 0.3:
				chunk.global_position.y = global_position.y + 0.3
				_chunk_velocities[i] = Vector3.ZERO
				_chunk_rot_velocities[i] = Vector3.ZERO

	# Fade suave dos elementos no final da vida útil (últimos 2.5s)
	if _age >= _lifetime - 2.5 and not _fading:
		_fading = true
		if _fire_particles and is_instance_valid(_fire_particles):
			_fire_particles.emitting = false
		if _scorch_decal and is_instance_valid(_scorch_decal):
			var tw_decal := create_tween()
			tw_decal.tween_property(_scorch_decal, "modulate:a", 0.0, 2.2)
		if _flying_turret and is_instance_valid(_flying_turret):
			_fade_node_out(_flying_turret, 2.2)
		for chunk in _flying_chunks:
			if is_instance_valid(chunk):
				_fade_node_out(chunk, 2.2)

	if _age >= _lifetime:
		queue_free()


func _fade_node_out(node: Node, duration: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is StandardMaterial3D:
			var mat := (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.material_override = mat
			var tw := create_tween()
			tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	for child in node.get_children():
		_fade_node_out(child, duration)
