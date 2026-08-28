class_name EnemyHeavy
extends "res://scripts/enemies/enemy_base.gd"

## Inimigo Cruzador Pesado / Mini-Boss (Starship.v3) no Mundo 3D Real.
## Navega em órbita tática pelo céu da bacia do cânion, virando a proa para mirar
## continuamente no jogador e disparando leques triplos e salvas de canhão pesado.

@export var orbit_radius_x: float = 75.0  ## Raio horizontal da órbita de combate
@export var orbit_radius_z: float = 55.0  ## Raio de profundidade da órbita
@export var orbit_speed: float = 0.45  ## Velocidade de rotação orbital (rad/s)
@export var altitude_wave: float = 12.0  ## Variação de altitude durante o voo

var orbit_center: Vector3 = Vector3.ZERO
var _time_alive: float = 0.0
var _attack_timer: float = 1.8
var _attack_pattern_index: int = 0
var _dying_sequence: bool = false


func _ready() -> void:
	max_hp = 1
	score_value = 1000
	super._ready()
	if orbit_center.length_squared() < 0.001:
		orbit_center = global_position


func setup_heavy(center: Vector3) -> void:
	orbit_center = center
	global_position = center + Vector3(orbit_radius_x, altitude_wave, 0.0)


func _physics_process(delta: float) -> void:
	if _dying_sequence:
		return

	_time_alive += delta

	# Movimento contínuo em órbita elíptica no céu do cânion
	var angle: float = _time_alive * orbit_speed
	var target_x: float = cos(angle) * orbit_radius_x
	var target_z: float = sin(angle) * orbit_radius_z
	var target_y: float = sin(angle * 1.5) * altitude_wave

	var new_pos: Vector3 = orbit_center + Vector3(target_x, target_y, target_z)
	global_position = global_position.lerp(new_pos, 4.0 * delta)

	# Vira a proa suavemente para manter os canhões apontados para a posição 3D do jogador
	var player: Node3D = _get_player_node()
	if player:
		var target_look: Vector3 = player.global_position
		var dir_to_player: Vector3 = (target_look - global_position).normalized()
		if dir_to_player.length_squared() > 0.001:
			var target_transform: Transform3D = global_transform.looking_at(target_look, Vector3.UP)
			global_transform.basis = global_transform.basis.slerp(target_transform.basis, 3.0 * delta)

	# Gerenciador de ataques em movimento
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = 2.2
		_execute_attack()


func _execute_attack() -> void:
	_attack_pattern_index = (_attack_pattern_index + 1) % 2

	if _attack_pattern_index == 0:
		_shoot_triple_spread()
	else:
		_shoot_twin_heavy_burst()


func _shoot_triple_spread() -> void:
	var center_pos: Vector3 = global_position + (-global_basis.z * 5.0)
	var left_pos: Vector3 = global_position + (-global_basis.x * 6.0) + (-global_basis.z * 3.0)
	var right_pos: Vector3 = global_position + (global_basis.x * 6.0) + (-global_basis.z * 3.0)

	var target_center: Vector3 = _get_player_position()
	var base_dir: Vector3 = (target_center - global_position).normalized()

	var left_dir: Vector3 = (base_dir + -global_basis.x * 0.18).normalized()
	var right_dir: Vector3 = (base_dir + global_basis.x * 0.18).normalized()

	fire_bullet(left_pos, left_dir)
	fire_bullet(center_pos, base_dir)
	fire_bullet(right_pos, right_dir)


func _shoot_twin_heavy_burst() -> void:
	var left_pos: Vector3 = global_position + (-global_basis.x * 4.5) + (-global_basis.z * 4.0)
	var right_pos: Vector3 = global_position + (global_basis.x * 4.5) + (-global_basis.z * 4.0)

	fire_towards_player(left_pos, 0.9)
	fire_towards_player(right_pos, 0.9)


func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_dying_sequence = true
	is_invulnerable = true

	_run_death_sequence()


func _run_death_sequence() -> void:
	for i: int in range(4):
		var offset: Vector3 = Vector3(
			randf_range(-5.0, 5.0),
			randf_range(-3.0, 3.0),
			randf_range(-4.0, 4.0)
		)
		var exp_small: Node3D = ExplosionScript.new()
		get_tree().current_scene.add_child(exp_small)
		exp_small.global_position = global_position + offset
		if exp_small.has_method("set"):
			exp_small.set("size_scale", 1.2)
		await get_tree().create_timer(0.15).timeout

	var exp_big: Node3D = ExplosionScript.new()
	get_tree().current_scene.add_child(exp_big)
	exp_big.global_position = global_position
	if exp_big.has_method("set"):
		exp_big.set("size_scale", 3.5)

	enemy_destroyed.emit(self, score_value)
	queue_free()
