class_name EnemyFighter
extends "res://scripts/enemies/enemy_base.gd"

## Inimigo Caça Tático / Fighter (Starship.v2)
## Entra em alta velocidade, estabiliza em distância de combate, realiza manobras
## de rolamento evasivo (barrel roll) e dispara rajadas duplas de laser.

enum State { ENTERING, COMBAT, DIVE_AWAY }

@export var enter_speed: float = 140.0
@export var combat_z: float = -95.0
@export var combat_duration: float = 7.5
@export var fire_interval: float = 2.2
@export var strafe_speed: float = 1.6
@export var strafe_width: float = 22.0

var _state: State = State.ENTERING
var _time_in_state: float = 0.0
var _fire_timer: float = 0.8
var _barrel_roll_timer: float = 3.0
var _is_barrel_rolling: bool = false
var _roll_progress: float = 0.0
var _wing_offset: float = 3.5


func _ready() -> void:
	max_hp = 1
	score_value = 300
	super._ready()


func _physics_process(delta: float) -> void:
	_time_in_state += delta

	match _state:
		State.ENTERING:
			_process_entering(delta)
		State.COMBAT:
			_process_combat(delta)
		State.DIVE_AWAY:
			_process_dive_away(delta)


func _process_entering(delta: float) -> void:
	position.z = move_toward(position.z, combat_z, enter_speed * delta)
	rotation.z = lerpf(rotation.z, 0.0, 6.0 * delta)

	if absf(position.z - combat_z) < 2.0:
		_state = State.COMBAT
		_time_in_state = 0.0


func _process_combat(delta: float) -> void:
	# Movimento de strafe lateral
	var strafe_x := sin(_time_in_state * strafe_speed) * strafe_width
	var target_y := 6.0 + cos(_time_in_state * strafe_speed * 1.4) * 4.0

	position.x = lerpf(position.x, strafe_x, 4.0 * delta)
	position.y = lerpf(position.y, target_y, 4.0 * delta)

	# Manobra de Barrel Roll evasivo
	_barrel_roll_timer -= delta
	if _barrel_roll_timer <= 0.0 and not _is_barrel_rolling:
		_is_barrel_rolling = true
		_roll_progress = 0.0
		_barrel_roll_timer = randf_range(3.5, 5.5)

	if _is_barrel_rolling:
		_roll_progress += delta * 4.5
		rotation.z = _roll_progress * TAU
		if _roll_progress >= 1.0:
			_is_barrel_rolling = false
			rotation.z = 0.0
	else:
		var bank := -cos(_time_in_state * strafe_speed) * 0.35
		rotation.z = lerpf(rotation.z, bank, 8.0 * delta)

	# Ciclo de disparo duplo
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = fire_interval
		_shoot_twin_lasers()

	if _time_in_state >= combat_duration:
		_state = State.DIVE_AWAY
		_time_in_state = 0.0


func _process_dive_away(delta: float) -> void:
	# Acelera passando em mergulho pelo jogador
	position.z += 180.0 * delta
	position.y -= 15.0 * delta
	rotation.x = lerpf(rotation.x, 0.3, 5.0 * delta)

	if position.z > 45.0:
		queue_free()


func _shoot_twin_lasers() -> void:
	var left_pos := global_position + (global_basis.x * -_wing_offset) + (-global_basis.z * 1.5)
	var right_pos := global_position + (global_basis.x * _wing_offset) + (-global_basis.z * 1.5)

	fire_towards_player(left_pos, 0.75)
	fire_towards_player(right_pos, 0.75)
