class_name EnemyFighter
extends "res://scripts/enemies/enemy_base.gd"

## Inimigo Caça Tático / Fighter (Starship.v2) no Mundo 3D Real.
## Voa à frente do jogador ao longo do cânion, realizando manobra evasiva
## de barrel roll 360°, disparos de lasers e quebra de asa na passagem do jogador.

enum State { PATROL, COMBAT_ROLL, BREAKAWAY }

@export var patrol_speed: float = 245.0  ## Velocidade à frente do jogador (m/s)
@export var breakaway_speed: float = 340.0  ## Velocidade de fuga após o jogador passar (m/s)
@export var breakaway_type: int = 0  ## 0 = Sobe pelo topo do cânion, 1 = Quebra para a esquerda, 2 = Quebra para a direita

var flight_direction: Vector3 = Vector3.FORWARD
var _state: State = State.PATROL
var _time_in_state: float = 0.0
var _fire_timer: float = 0.4
var _barrel_roll_progress: float = 0.0
var _is_rolling: bool = false
var _wing_offset: float = 4.0
var _up_vec: Vector3 = Vector3.UP
var _right_vec: Vector3 = Vector3.RIGHT


func _ready() -> void:
	max_hp = 1
	score_value = 300
	super._ready()

	if flight_direction.length_squared() < 0.001:
		flight_direction = -global_basis.z.normalized()
	else:
		flight_direction = flight_direction.normalized()

	_right_vec = flight_direction.cross(Vector3.UP).normalized()
	if _right_vec.length_squared() < 0.001:
		_right_vec = Vector3.RIGHT
	_up_vec = _right_vec.cross(flight_direction).normalized()


func setup_fighter(start_pos: Vector3, dir: Vector3, b_type: int = 0) -> void:
	global_position = start_pos
	flight_direction = dir.normalized()
	breakaway_type = b_type

	_right_vec = flight_direction.cross(Vector3.UP).normalized()
	if _right_vec.length_squared() < 0.001:
		_right_vec = Vector3.RIGHT
	_up_vec = _right_vec.cross(flight_direction).normalized()

	look_at(global_position + flight_direction, _up_vec)


func _physics_process(delta: float) -> void:
	_time_in_state += delta

	match _state:
		State.PATROL:
			_process_patrol(delta)
		State.COMBAT_ROLL:
			_process_combat_roll(delta)
		State.BREAKAWAY:
			_process_breakaway(delta)


func _process_patrol(delta: float) -> void:
	# Voo suave à frente do jogador ao longo do desfiladeiro
	global_position += flight_direction * patrol_speed * delta

	var weave: Vector3 = _right_vec * sin(_time_in_state * 2.2) * 12.0 * delta
	global_position += weave

	look_at(global_position + flight_direction, _up_vec)

	var player: Node3D = _get_player_node()
	if player:
		var dist: float = global_position.distance_to(player.global_position)
		var to_fighter: Vector3 = global_position - player.global_position

		# Inicia a manobra de combate ao se aproximar
		if dist <= 240.0 and to_fighter.dot(flight_direction) > 0.0:
			_state = State.COMBAT_ROLL
			_time_in_state = 0.0
			_is_rolling = true
			_barrel_roll_progress = 0.0

		# Se o jogador já ultrapassou, entra imediatamente em breakaway (sem perseguição)
		if to_fighter.dot(flight_direction) < -20.0:
			_state = State.BREAKAWAY
			_time_in_state = 0.0


func _process_combat_roll(delta: float) -> void:
	global_position += flight_direction * patrol_speed * delta

	# Movimento lateral evasivo durante o roll
	var side_dir: float = 1.0 if breakaway_type == 2 else (-1.0 if breakaway_type == 1 else sin(_time_in_state * 3.0))
	global_position += _right_vec * side_dir * 18.0 * delta

	look_at(global_position + flight_direction, Vector3.UP)

	# Manobra de Barrel Roll 360° em voo
	if _is_rolling:
		_barrel_roll_progress += delta * 3.2
		rotate_object_local(Vector3(0, 0, 1), _barrel_roll_progress * TAU)
		if _barrel_roll_progress >= 1.0:
			_is_rolling = false

	# Disparo de lasers duplos em direção ao jogador
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = 1.0
		_shoot_twin_lasers()

	var player: Node3D = _get_player_node()
	if player:
		var to_fighter: Vector3 = global_position - player.global_position
		# Quando o jogador passa pela nave, quebra a formação
		if to_fighter.dot(flight_direction) < -20.0 or _time_in_state > 4.5:
			_state = State.BREAKAWAY
			_time_in_state = 0.0


func _process_breakaway(delta: float) -> void:
	# Direção de fuga no espaço 3D (para fora do campo de visão)
	var break_vector: Vector3 = flight_direction
	match breakaway_type:
		0:  # Sobe pelo cânion
			break_vector = (flight_direction + Vector3.UP * 0.9).normalized()
		1:  # Quebra para a esquerda
			break_vector = (flight_direction - _right_vec * 0.8 + Vector3.UP * 0.2).normalized()
		2:  # Quebra para a direita
			break_vector = (flight_direction + _right_vec * 0.8 + Vector3.UP * 0.2).normalized()

	flight_direction = flight_direction.slerp(break_vector, 3.5 * delta).normalized()
	global_position += flight_direction * breakaway_speed * delta

	look_at(global_position + flight_direction, Vector3.UP)

	var bank_dir: float = 0.9 if breakaway_type == 2 else (-0.9 if breakaway_type == 1 else 0.0)
	rotate_object_local(Vector3(0, 0, 1), bank_dir)

	# Auto-remoção rápida após sair do campo visual
	if _time_in_state > 3.0:
		queue_free()


func _shoot_twin_lasers() -> void:
	var left_pos: Vector3 = global_position + (global_basis.x * -_wing_offset) + (-global_basis.z * 1.5)
	var right_pos: Vector3 = global_position + (global_basis.x * _wing_offset) + (-global_basis.z * 1.5)

	var player: Node3D = _get_player_node()
	var dir_to_player: Vector3 = -flight_direction
	if player:
		dir_to_player = (player.global_position - global_position).normalized()

	fire_bullet(left_pos, dir_to_player)
	fire_bullet(right_pos, dir_to_player)
