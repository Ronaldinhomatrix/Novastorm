class_name EnemyFighter
extends "res://scripts/enemies/enemy_base.gd"

## Inimigo Caça Tático / Fighter (Starship.v2) no Mundo 3D Real.
## Voa pelo espaço aéreo do cânion realizando patrulha, mergulho de combate
## com barrel roll 360°, rajadas duplas de laser e manobra de quebra de asa.

enum State { PATROL, DIVE_ATTACK, BREAKAWAY }

@export var patrol_speed: float = 120.0  ## Velocidade de aproximação no mundo (m/s)
@export var dive_speed: float = 160.0  ## Velocidade no mergulho de ataque (m/s)
@export var breakaway_speed: float = 200.0  ## Velocidade de saída após o rasante (m/s)
@export var breakaway_type: int = 0  ## 0 = Sobe pelo topo do cânion, 1 = Quebra para a esquerda, 2 = Quebra para a direita

var flight_direction: Vector3 = Vector3.FORWARD
var _state: State = State.PATROL
var _time_in_state: float = 0.0
var _fire_timer: float = 0.3
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
		State.DIVE_ATTACK:
			_process_dive_attack(delta)
		State.BREAKAWAY:
			_process_breakaway(delta)


func _process_patrol(delta: float) -> void:
	# Voo contínuo em direção à área de interceptação
	global_position += flight_direction * patrol_speed * delta

	# Suave oscilação de patrulha
	var weave: Vector3 = _right_vec * sin(_time_in_state * 2.0) * 8.0 * delta
	global_position += weave

	look_at(global_position + flight_direction, _up_vec)

	var player: Node3D = _get_player_node()
	if player:
		var dist: float = global_position.distance_to(player.global_position)
		if dist <= 380.0:
			_state = State.DIVE_ATTACK
			_time_in_state = 0.0
			_is_rolling = true
			_barrel_roll_progress = 0.0


func _process_dive_attack(delta: float) -> void:
	var player: Node3D = _get_player_node()
	var target_dir: Vector3 = flight_direction
	if player:
		target_dir = (player.global_position - global_position).normalized()

	# Interpolação vetorial em direção à nave do jogador
	flight_direction = flight_direction.slerp(target_dir, 3.5 * delta).normalized()
	global_position += flight_direction * dive_speed * delta

	# Look-at na direção de ataque
	look_at(global_position + flight_direction, Vector3.UP)

	# Manobra de Barrel Roll 360° durante o mergulho
	if _is_rolling:
		_barrel_roll_progress += delta * 4.0
		rotate_object_local(Vector3(0, 0, 1), _barrel_roll_progress * TAU)
		if _barrel_roll_progress >= 1.0:
			_is_rolling = false

	# Disparo de lasers duplos
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = 0.8
		_shoot_twin_lasers()

	if player:
		var dist: float = global_position.distance_to(player.global_position)
		var to_fighter: Vector3 = global_position - player.global_position
		# Se cruzou o jogador ou chegou a menos de 50m, faz a quebra de asa
		if dist < 50.0 or to_fighter.dot(flight_direction) > 20.0:
			_state = State.BREAKAWAY
			_time_in_state = 0.0


func _process_breakaway(delta: float) -> void:
	# Direção de fuga baseada no tipo de caça
	var break_vector: Vector3 = flight_direction
	match breakaway_type:
		0:  # Sobe pelo cânion
			break_vector = (flight_direction + Vector3.UP * 0.8).normalized()
		1:  # Quebra para a esquerda
			break_vector = (flight_direction - _right_vec * 0.7 + Vector3.UP * 0.3).normalized()
		2:  # Quebra para a direita
			break_vector = (flight_direction + _right_vec * 0.7 + Vector3.UP * 0.3).normalized()

	flight_direction = flight_direction.slerp(break_vector, 4.0 * delta).normalized()
	global_position += flight_direction * breakaway_speed * delta

	look_at(global_position + flight_direction, Vector3.UP)

	# Inclinação dramática na saída
	var bank_dir: float = 0.8 if breakaway_type == 2 else (-0.8 if breakaway_type == 1 else 0.0)
	rotate_object_local(Vector3(0, 0, 1), bank_dir)

	if _time_in_state > 5.0:
		queue_free()


func _shoot_twin_lasers() -> void:
	var left_pos: Vector3 = global_position + (global_basis.x * -_wing_offset) + (-global_basis.z * 1.5)
	var right_pos: Vector3 = global_position + (global_basis.x * _wing_offset) + (-global_basis.z * 1.5)

	fire_towards_player(left_pos, 0.8)
	fire_towards_player(right_pos, 0.8)
