class_name PlayerMissile
extends Area3D

## Míssil teleguiado com sistema de mira lock-on estilo After Burner II.
## Persegue suavemente o alvo travado com aceleração gradual e curva aerodinâmica.
## Gera esteira densa e volumosa de fumaça suspensa no ar (world coords).

@export_category("Desempenho e Voo")
@export var initial_relative_speed: float = 1.0   ## Velocidade inicial relativa à nave (m/s)
@export var max_speed: float = 380.0             ## Velocidade máxima em relação ao mundo
@export var acceleration: float = 320.0          ## Aceleração linear rápida (m/s²)
@export var turn_rate: float = 12.0              ## Velocidade angular base de perseguição (rad/s)
@export var homing_delay: float = 0.25           ## Tempo máximo em linha reta antes de iniciar perseguição (s)
@export var max_lifetime: float = 7.5
@export var damage: int = 3

const WORLD_LAYER_MASK: int = 1 << 3  ## Layer 4: "World" (terreno/paredes)
const ExplosionScript := preload("res://scripts/effects/explosion.gd")

var _target: Node3D = null
var _current_speed: float = 0.0
var _velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _is_exploding: bool = false
var _smoke_particles: CPUParticles3D = null
var _ray: RayCast3D = null
var _has_hit: bool = false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 2 | WORLD_LAYER_MASK
	monitoring = true
	monitorable = true

	add_to_group("player_bullets")
	add_to_group("player_missiles")

	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

	_current_speed = initial_relative_speed
	_velocity = -global_transform.basis.z.normalized() * _current_speed

	# Raycast para colisão contínua sem tunelamento com malha de terreno
	_ray = RayCast3D.new()
	_ray.enabled = true
	_ray.collision_mask = WORLD_LAYER_MASK
	_ray.collide_with_bodies = true
	_ray.collide_with_areas = false
	add_child(_ray)

	_smoke_particles = get_node_or_null("SmokeTrail") as CPUParticles3D


## Inicializa o míssil com o alvo travado, direção de ejeção inicial e velocidade base da nave
func setup(target: Node3D, initial_dir: Vector3, base_ship_speed: float = 65.0) -> void:
	_target = target
	# Velocidade inicial real = velocidade que a nave já tem + velocidade de ejeção relativa (10 m/s)
	_current_speed = base_ship_speed + initial_relative_speed
	var forward := initial_dir.normalized()
	if forward.length_squared() > 0.001:
		_velocity = forward * _current_speed
		look_at(global_position + forward, Vector3.UP)


func _physics_process(delta: float) -> void:
	if _has_hit or _is_exploding:
		return

	_age += delta
	if _age >= max_lifetime:
		_explode()
		return

	# Aceleração progressiva e linear em direção à velocidade máxima
	_current_speed = move_toward(_current_speed, max_speed, acceleration * delta)

	var forward := _velocity.normalized()
	var desired_dir := forward

	if is_instance_valid(_target) and not _target.is_queued_for_deletion():
		# Pega a posição central do alvo
		var target_pos := _target.global_position
		var model: Node3D = _target.get_node_or_null("ShipModel") as Node3D
		if model:
			target_pos = model.global_position

		var to_target_vec := target_pos - global_position
		var dist_to_target := to_target_vec.length()

		# Lógica simples de 2 situações:
		# Se o alvo está perto (< 100m): teleguia imediatamente (sem delay) e com curva mais fechada.
		# Se o alvo está longe (>= 100m): comportamento normal de ejeção em linha reta por homing_delay.
		var current_homing_delay := 0.0 if dist_to_target < 100.0 else homing_delay
		var current_turn_rate := (turn_rate * 1.8) if dist_to_target < 100.0 else turn_rate

		if _age >= current_homing_delay:
			var to_target := to_target_vec.normalized()
			var angle_diff := forward.angle_to(to_target)
			if angle_diff > 0.001:
				var max_angle_step := current_turn_rate * delta
				var rot_factor := clampf(max_angle_step / angle_diff, 0.0, 1.0)
				desired_dir = forward.slerp(to_target, rot_factor).normalized()
			else:
				desired_dir = to_target
	else:
		_target = null  # Alvo perdido, segue trajetória reta balística

	_velocity = desired_dir * _current_speed

	# Alinha visual do míssil na direção do movimento
	if _velocity.length_squared() > 0.1:
		look_at(global_position + _velocity, Vector3.UP)

	# Verificação de raycast preventivo contra paredes e chão
	var step := _velocity * delta
	if _ray:
		_ray.target_position = _ray.to_local(global_position + step * 1.3)
		_ray.force_raycast_update()
		if _ray.is_colliding():
			global_position = _ray.get_collision_point()
			_explode()
			return

	global_position += step


func _on_area_entered(area: Area3D) -> void:
	if _has_hit or _is_exploding:
		return
	if area.is_in_group("player") or area.is_in_group("player_bullets"):
		return
	_apply_damage_and_explode(area)


func _on_body_entered(body: Node3D) -> void:
	if _has_hit or _is_exploding:
		return
	if body.is_in_group("player") or body.is_in_group("player_bullets"):
		return
	_apply_damage_and_explode(body)


func _apply_damage_and_explode(target_node: Node) -> void:
	_has_hit = true
	if is_instance_valid(target_node):
		if target_node.has_method("take_damage"):
			target_node.call("take_damage", damage)
		elif target_node.get_parent() and target_node.get_parent().has_method("take_damage"):
			target_node.get_parent().call("take_damage", damage)

	_explode()


func _explode() -> void:
	if _is_exploding:
		return
	_is_exploding = true
	_has_hit = true

	# Desativa colisões e visuais do corpo do míssil
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	var mesh_body := get_node_or_null("MissileBody") as Node3D
	if mesh_body:
		mesh_body.visible = false

	# Detona explosão procedural
	if ExplosionScript:
		var scene_root := get_tree().current_scene
		if not scene_root:
			scene_root = get_parent()
		var explosion: Node3D = ExplosionScript.new()
		scene_root.add_child(explosion)
		explosion.global_position = global_position
		if explosion.has_method("set"):
			explosion.set("size_scale", 1.4)

	# Áudio de impacto / explosão
	if has_node("/root/SoundManager"):
		get_node("/root/SoundManager").play_heavy_explosion(-1.0)

	# Deixa a fumaça suspensa dissipar antes de remover o nó
	if _smoke_particles:
		_smoke_particles.emitting = false

	var tree := get_tree()
	if tree:
		await tree.create_timer(1.2).timeout
	if is_instance_valid(self):
		queue_free()
