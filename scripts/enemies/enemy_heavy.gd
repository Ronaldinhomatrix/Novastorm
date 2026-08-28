class_name EnemyHeavy
extends "res://scripts/enemies/enemy_base.gd"

## Inimigo Cruzador Pesado / Mini-Boss (Starship.v3) no Mundo 3D Real.
## Navega à frente do jogador pelo céu da bacia do cânion com movimentação
## imponente em figura-8, disparando leques triplos e salvas de canhão.

@export var forward_speed: float = 230.0  ## Velocidade de avanço pelo cânion (m/s)
@export var width_amplitude: float = 45.0  ## Amplitude lateral na bacia
@export var height_amplitude: float = 14.0  ## Amplitude vertical
@export var wave_frequency: float = 0.8  ## Frequência do padrão de voo

var flight_direction: Vector3 = Vector3.FORWARD
var _time_alive: float = 0.0
var _attack_timer: float = 1.6
var _attack_pattern_index: int = 0
var _dying_sequence: bool = false
var _initial_pos: Vector3 = Vector3.ZERO
var _right_vec: Vector3 = Vector3.RIGHT
var _up_vec: Vector3 = Vector3.UP


func _ready() -> void:
	max_hp = 1
	score_value = 1000
	super._ready()
	_initial_pos = global_position

	if flight_direction.length_squared() < 0.001:
		flight_direction = -global_basis.z.normalized()
	else:
		flight_direction = flight_direction.normalized()

	_right_vec = flight_direction.cross(Vector3.UP).normalized()
	if _right_vec.length_squared() < 0.001:
		_right_vec = Vector3.RIGHT
	_up_vec = _right_vec.cross(flight_direction).normalized()


func setup_heavy(start_pos: Vector3, dir: Vector3) -> void:
	global_position = start_pos
	_initial_pos = start_pos
	flight_direction = dir.normalized()

	_right_vec = flight_direction.cross(Vector3.UP).normalized()
	if _right_vec.length_squared() < 0.001:
		_right_vec = Vector3.RIGHT
	_up_vec = _right_vec.cross(flight_direction).normalized()

	look_at(global_position + flight_direction, _up_vec)


func _physics_process(delta: float) -> void:
	if _dying_sequence:
		return

	_time_alive += delta

	# Movimento para frente ao longo do cânion + padrão figura-8 (lemniscata)
	var forward_travel: Vector3 = flight_direction * (forward_speed * _time_alive)
	var t: float = _time_alive * wave_frequency
	var lateral_offset: Vector3 = _right_vec * (sin(t) * width_amplitude)
	var vertical_offset: Vector3 = _up_vec * (sin(t * 2.0) * height_amplitude)

	global_position = _initial_pos + forward_travel + lateral_offset + vertical_offset

	# Direção de voo com look-at suave
	look_at(global_position + flight_direction, Vector3.UP)
	var bank: float = -cos(t) * 0.25
	rotate_object_local(Vector3(0, 0, 1), bank)

	# Gerenciador de ataques em direção ao jogador
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = 2.0
		_execute_attack()

	# Despawn gracioso quando o jogador ultrapassa a nave (sem perseguição)
	var player: Node3D = _get_player_node()
	if player:
		var to_heavy: Vector3 = global_position - player.global_position
		if to_heavy.dot(flight_direction) < -50.0 or _time_alive > 16.0:
			queue_free()
	elif _time_alive > 18.0:
		queue_free()


func _execute_attack() -> void:
	_attack_pattern_index = (_attack_pattern_index + 1) % 2

	if _attack_pattern_index == 0:
		_shoot_triple_spread()
	else:
		_shoot_twin_heavy_burst()


func _shoot_triple_spread() -> void:
	var center_pos: Vector3 = global_position + (-flight_direction * 4.0)
	var left_pos: Vector3 = global_position + (-_right_vec * 6.0) + (-flight_direction * 3.0)
	var right_pos: Vector3 = global_position + (_right_vec * 6.0) + (-flight_direction * 3.0)

	var player: Node3D = _get_player_node()
	var base_dir: Vector3 = -flight_direction
	if player:
		base_dir = (player.global_position - global_position).normalized()

	var left_dir: Vector3 = (base_dir - _right_vec * 0.18).normalized()
	var right_dir: Vector3 = (base_dir + _right_vec * 0.18).normalized()

	fire_bullet(left_pos, left_dir)
	fire_bullet(center_pos, base_dir)
	fire_bullet(right_pos, right_dir)


func _shoot_twin_heavy_burst() -> void:
	var left_pos: Vector3 = global_position + (-_right_vec * 4.5) + (-flight_direction * 3.0)
	var right_pos: Vector3 = global_position + (_right_vec * 4.5) + (-flight_direction * 3.0)

	var player: Node3D = _get_player_node()
	var dir_to_player: Vector3 = -flight_direction
	if player:
		dir_to_player = (player.global_position - global_position).normalized()

	fire_bullet(left_pos, dir_to_player)
	fire_bullet(right_pos, dir_to_player)


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
