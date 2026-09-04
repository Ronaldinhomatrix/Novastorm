class_name GroundVehicleWreckage
extends Node3D

## Sistema especializado de destruição e explosão de veículos terrestres (Tanques e Caminhões).
## Substitui o desmonte aéreo espacial por:
##   1. Carcaça carbonizada (Hull/Chassi) mantida firmemente no solo/ponte.
##   2. Pluma contínua e volumétrica de chamas e fumaça negra densa subindo aos céus.
##   3. Para tanques: Ejeção balística da torreta com impulso vertical, rotação e gravidade real.
##   4. Estilhaços metálicos e centelhas arremessados em arco balístico com gravidade pesada.
##   5. Flash, onda de choque e som de explosão de artilharia pesada.

const ExplosionScript := preload("res://scripts/effects/explosion.gd")
const ExplosionSounds := [
	preload("res://assets/audio/explosion1.ogg"),
	preload("res://assets/audio/explosion2.ogg"),
]

var _lifetime: float = 14.0
var _age: float = 0.0
var _flicker_light: OmniLight3D = null
var _smoke_particles: CPUParticles3D = null
var _fire_particles: CPUParticles3D = null
var _wreck_root: Node3D = null
var _fading: bool = false


# ---------------------------------------------------------------------------
# Construtores Estáticos (Spawners)
# ---------------------------------------------------------------------------

## Dispara a destruição cinematográfica de um tanque de guerra
static func spawn_for_tank(tank: Node3D) -> GroundVehicleWreckage:
	if not tank or not is_instance_valid(tank):
		return null
		
	var parent := _get_scene_parent(tank)
	if not parent:
		return null

	var wreckage := GroundVehicleWreckage.new()
	parent.add_child(wreckage)
	wreckage.global_transform = tank.global_transform
	wreckage._build_tank_wreckage(tank)
	return wreckage


## Dispara a destruição cinematográfica de um caminhão militar
static func spawn_for_truck(truck: Node3D) -> GroundVehicleWreckage:
	if not truck or not is_instance_valid(truck):
		return null
		
	var parent := _get_scene_parent(truck)
	if not parent:
		return null

	var wreckage := GroundVehicleWreckage.new()
	parent.add_child(wreckage)
	wreckage.global_transform = truck.global_transform
	wreckage._build_truck_wreckage(truck)
	return wreckage


static func _get_scene_parent(node: Node) -> Node:
	if node.get_tree() and node.get_tree().current_scene:
		return node.get_tree().current_scene
	if node.get_parent():
		return node.get_parent()
	return node.get_tree().root if node.get_tree() else null


# ---------------------------------------------------------------------------
# Montagem do Destroço do Tanque
# ---------------------------------------------------------------------------

func _build_tank_wreckage(tank: Node3D) -> void:
	# 1. Detonação inicial com onda de choque e flash terrestre
	_spawn_blast(1.9)

	# 2. Clona o modelo do tanque para servir de carcaça carbonizada
	var tank_model := tank.find_child("TankModel", true, false) as Node3D
	var original_turret := tank.find_child("Turret", true, false) as Node3D
	
	if tank_model:
		var wreck_model := tank_model.duplicate() as Node3D
		add_child(wreck_model)
		wreck_model.position = Vector3.ZERO
		wreck_model.rotation = Vector3.ZERO
		_wreck_root = wreck_model
		
		# No casco destruído, remove a torreta original (pois ela voa pelos ares)
		var wreck_turret := wreck_model.find_child("Turret", true, false)
		if wreck_turret:
			wreck_turret.queue_free()
			
		_apply_charred_material(wreck_model)

	# 3. Ejeção Balística da Torreta (Turret Pop) com gravidade e rotação
	if original_turret and is_instance_valid(original_turret):
		_spawn_flying_turret(original_turret, tank.global_position.y)

	# 4. Adiciona plumas contínuas de fogo e fumaça densa saindo do anel da torreta
	_create_hull_fire_and_smoke(Vector3(0, 2.5, 0))

	# 5. Estilhaços metálicos em arco com gravidade pesada
	_spawn_ballistic_shrapnel(Vector3(0, 2.0, 0), 22)


# ---------------------------------------------------------------------------
# Montagem do Destroço do Caminhão
# ---------------------------------------------------------------------------

func _build_truck_wreckage(truck: Node3D) -> void:
	# 1. Detonação inicial
	_spawn_blast(1.7)

	# 2. Clona o modelo do caminhão para a carcaça
	var truck_model := truck.find_child("TruckModel", true, false) as Node3D
	if truck_model:
		var wreck_model := truck_model.duplicate() as Node3D
		add_child(wreck_model)
		wreck_model.position = Vector3.ZERO
		# Leve inclinação de suspensão quebrada pelo impacto
		wreck_model.rotation_degrees = Vector3(randf_range(-4, 4), 0, randf_range(-6, 6))
		_wreck_root = wreck_model
		_apply_charred_material(wreck_model)

	# 3. Adiciona plumas de fogo e fumaça saindo do motor e carroceria
	_create_hull_fire_and_smoke(Vector3(0, 3.0, 0))

	# 4. Estilhaços metálicos com gravidade pesada
	_spawn_ballistic_shrapnel(Vector3(0, 2.5, 0), 18)


# ---------------------------------------------------------------------------
# Torreta Voadora (Turret Pop com Física e Gravidade Real)
# ---------------------------------------------------------------------------

func _spawn_flying_turret(source_turret: Node3D, ground_y: float) -> void:
	var turret_clone := source_turret.duplicate() as Node3D
	var scene_parent := get_parent()
	if not scene_parent:
		return
		
	var debris_container := Node3D.new()
	scene_parent.add_child(debris_container)
	debris_container.global_transform = source_turret.global_transform
	
	turret_clone.position = Vector3.ZERO
	turret_clone.rotation = Vector3.ZERO
	debris_container.add_child(turret_clone)
	_apply_charred_material(turret_clone)

	# Script leve dinâmico para simular o vôo e queda balística da torreta
	var debris_sim := TurretFlightPhysics.new()
	debris_sim.ground_y = ground_y
	debris_sim.velocity = Vector3(
		randf_range(-6.0, 6.0),
		randf_range(18.0, 27.0),  # Forte impulso para o alto
		randf_range(-6.0, 6.0)
	)
	debris_sim.angular_velocity = Vector3(
		randf_range(-4.0, 4.0),
		randf_range(-2.5, 2.5),
		randf_range(-4.0, 4.0)
	)
	debris_container.add_child(debris_sim)


# ---------------------------------------------------------------------------
# Efeitos de Fogo, Fumaça e Estilhaços
# ---------------------------------------------------------------------------

func _create_hull_fire_and_smoke(offset: Vector3) -> void:
	# Fogo contínuo lambendo a carcaça
	_fire_particles = CPUParticles3D.new()
	_fire_particles.name = "WreckFire"
	_fire_particles.emitting = true
	_fire_particles.amount = 28
	_fire_particles.lifetime = 0.75
	_fire_particles.position = offset
	_fire_particles.direction = Vector3.UP
	_fire_particles.spread = 35.0
	_fire_particles.gravity = Vector3(0, 3.0, 0)
	_fire_particles.initial_velocity_min = 2.0
	_fire_particles.initial_velocity_max = 5.5
	_fire_particles.scale_amount_min = 1.2
	_fire_particles.scale_amount_max = 3.2
	
	var fire_ramp := Gradient.new()
	fire_ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.6, 1.0])
	fire_ramp.colors = PackedColorArray([
		Color(2.2, 1.8, 0.4, 1.0),
		Color(1.6, 0.6, 0.05, 0.95),
		Color(0.8, 0.15, 0.02, 0.8),
		Color(0.2, 0.02, 0.0, 0.0)
	])
	_fire_particles.color_ramp = fire_ramp
	_fire_particles.mesh = _create_sphere_mesh(0.45)
	_fire_particles.material_override = _create_particle_material(BaseMaterial3D.BLEND_MODE_ADD)
	add_child(_fire_particles)

	# Coluna volumétrica de fumaça negra subindo aos céus
	_smoke_particles = CPUParticles3D.new()
	_smoke_particles.name = "WreckSmoke"
	_smoke_particles.emitting = true
	_smoke_particles.amount = 40
	_smoke_particles.lifetime = 3.0
	_smoke_particles.position = offset + Vector3.UP * 0.5
	_smoke_particles.direction = Vector3(0.08, 1.0, 0.04).normalized()
	_smoke_particles.spread = 22.0
	_smoke_particles.gravity = Vector3(0, 2.5, 0)
	_smoke_particles.initial_velocity_min = 3.5
	_smoke_particles.initial_velocity_max = 8.5
	_smoke_particles.scale_amount_min = 2.5
	_smoke_particles.scale_amount_max = 8.0
	
	var smoke_ramp := Gradient.new()
	smoke_ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	smoke_ramp.colors = PackedColorArray([
		Color(0.18, 0.18, 0.18, 0.9),
		Color(0.12, 0.12, 0.12, 0.85),
		Color(0.08, 0.08, 0.08, 0.5),
		Color(0.05, 0.05, 0.05, 0.0)
	])
	_smoke_particles.color_ramp = smoke_ramp
	_smoke_particles.mesh = _create_sphere_mesh(0.7)
	_smoke_particles.material_override = _create_particle_material(BaseMaterial3D.BLEND_MODE_MIX)
	add_child(_smoke_particles)

	# Luz trêmula de fogo iluminando a carcaça e o chão
	_flicker_light = OmniLight3D.new()
	_flicker_light.name = "FireLight"
	_flicker_light.position = offset + Vector3.UP * 1.5
	_flicker_light.light_color = Color(1.0, 0.5, 0.12)
	_flicker_light.light_energy = 8.0
	_flicker_light.omni_range = 22.0
	_flicker_light.omni_attenuation = 1.4
	add_child(_flicker_light)


func _spawn_ballistic_shrapnel(offset: Vector3, count: int) -> void:
	var p := CPUParticles3D.new()
	p.name = "BallisticShrapnel"
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.98
	p.amount = count
	p.lifetime = 2.2
	p.position = offset
	p.direction = Vector3.UP
	p.spread = 65.0
	p.gravity = Vector3(0, -32.0, 0) # Gravidade pesada real
	p.initial_velocity_min = 16.0
	p.initial_velocity_max = 34.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.6
	
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 0.8, 1.0])
	ramp.colors = PackedColorArray([
		Color(2.0, 1.5, 0.5, 1.0),
		Color(1.0, 0.4, 0.1, 1.0),
		Color(0.2, 0.15, 0.15, 0.9),
		Color(0.08, 0.08, 0.08, 0.0)
	])
	p.color_ramp = ramp
	
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.3, 0.6)
	p.mesh = box
	p.material_override = _create_particle_material(BaseMaterial3D.BLEND_MODE_MIX)
	add_child(p)


func _spawn_blast(size: float) -> void:
	var exp_node: Node3D = ExplosionScript.new()
	add_child(exp_node)
	exp_node.global_position = global_position + Vector3.UP * 1.5
	if exp_node.has_method("set"):
		exp_node.set("size_scale", size)
		
	# Som de explosão pesado
	_play_heavy_explosion_sound()


func _play_heavy_explosion_sound() -> void:
	if has_node("/root/SoundManager"):
		get_node("/root/SoundManager").play_explosion(-0.5)
		return
	if ExplosionSounds.is_empty():
		return
	var p := AudioStreamPlayer.new()
	p.stream = ExplosionSounds.pick_random()
	p.bus = "Master"
	p.volume_db = 1.0
	p.pitch_scale = randf_range(0.85, 0.95) # Tom mais grave para artilharia
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ---------------------------------------------------------------------------
# Material Carbonizado e Helpers
# ---------------------------------------------------------------------------

func _apply_charred_material(root: Node) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.11, 0.11, 0.12, 1.0) # Metal preto chamuscado
	mat.roughness = 0.9
	mat.metallic = 0.15
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.25, 0.03, 1.0) # Brasas residuais
	mat.emission_energy_multiplier = 0.35

	_apply_material_recursive(root, mat)


func _apply_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_apply_material_recursive(child, mat)


func _create_sphere_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 5
	return mesh


func _create_particle_material(blend_mode: BaseMaterial3D.BlendMode) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = blend_mode
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


# ---------------------------------------------------------------------------
# Ciclo de Vida e Fade Out
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_age += delta
	
	# Efeito de oscilação natural da luz da chama
	if _flicker_light and is_instance_valid(_flicker_light):
		var noise := sin(_age * 18.0) * 0.3 + cos(_age * 31.0) * 0.2
		_flicker_light.light_energy = clampf(7.5 + noise * 3.5, 2.0, 12.0)

	# Inicia o fade suave nos últimos 3 segundos
	if _age >= _lifetime - 3.0 and not _fading:
		_fading = true
		if _fire_particles:
			_fire_particles.emitting = false
		if _flicker_light:
			var tween := create_tween()
			tween.tween_property(_flicker_light, "light_energy", 0.0, 2.5)

	if _age >= _lifetime:
		queue_free()


# ===========================================================================
# Classe Interna: Física Balística da Torreta com Gravidade
# ===========================================================================

class TurretFlightPhysics extends Node:
	var ground_y: float = 0.0
	var velocity: Vector3 = Vector3.ZERO
	var angular_velocity: Vector3 = Vector3.ZERO
	var gravity: float = 28.0
	var bounces: int = 0
	var parent_node: Node3D = null
	var smoke_trail: CPUParticles3D = null

	func _ready() -> void:
		parent_node = get_parent() as Node3D
		if parent_node:
			_create_trail()

	func _create_trail() -> void:
		smoke_trail = CPUParticles3D.new()
		smoke_trail.emitting = true
		smoke_trail.amount = 20
		smoke_trail.lifetime = 1.0
		smoke_trail.direction = Vector3.DOWN
		smoke_trail.spread = 15.0
		smoke_trail.gravity = Vector3(0, 2.0, 0)
		smoke_trail.initial_velocity_min = 1.0
		smoke_trail.initial_velocity_max = 3.0
		smoke_trail.scale_amount_min = 0.8
		smoke_trail.scale_amount_max = 2.4
		
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		ramp.colors = PackedColorArray([
			Color(1.0, 0.4, 0.1, 0.8),
			Color(0.2, 0.2, 0.2, 0.7),
			Color(0.1, 0.1, 0.1, 0.0)
		])
		smoke_trail.color_ramp = ramp
		
		var sphere := SphereMesh.new()
		sphere.radius = 0.4
		sphere.height = 0.8
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

		# Aplicação de Gravidade Real
		velocity.y -= gravity * delta
		parent_node.global_position += velocity * delta
		
		parent_node.rotate_x(angular_velocity.x * delta)
		parent_node.rotate_y(angular_velocity.y * delta)
		parent_node.rotate_z(angular_velocity.z * delta)

		# Colisão com o solo/piso da ponte
		if parent_node.global_position.y <= ground_y:
			if bounces < 2 and absf(velocity.y) > 4.0:
				bounces += 1
				parent_node.global_position.y = ground_y
				velocity.y = -velocity.y * 0.35 # Quique amortecido
				velocity.x *= 0.55
				velocity.z *= 0.55
				angular_velocity *= 0.5
			else:
				# A torreta repousa no chão
				parent_node.global_position.y = ground_y
				velocity = Vector3.ZERO
				angular_velocity = Vector3.ZERO
				if smoke_trail:
					smoke_trail.emitting = false
				set_physics_process(false)
