class_name EnemyFighter
extends "res://scripts/enemies/enemy_base.gd"

## Inimigo Caça Tático / Fighter (Starship.v2).
##
## Padrão de Voo Rail-Shooter:
## - 1 HP (morre com 1 tiro).
## - Permanece na frente do jogador durante 8.0s em uma travessia suave com barrel roll na metade.
## - Se o jogador ultrapassar ou a nave fugir, é liberada imediatamente.

enum Phase { ENTER, ENGAGE, EXIT }

@export_category("Padrão de Voo")
@export var enter_duration: float = 1.8
@export var engage_duration: float = 8.0
@export var exit_duration: float = 2.5

@export var start_distance_ahead: float = 95.0   ## Distância de spawn à frente
@export var combat_distance_ahead: float = 68.0  ## Distância média de combate
@export var lateral_span: float = 32.0           ## Extensão lateral da travessia (±32m)
@export var base_height: float = 8.0             ## Altura média de combate
@export var roll_duration: float = 1.0           ## Duração do giro 360°

var _phase: Phase = Phase.ENTER
var _phase_timer: float = 0.0
var _fire_timer: float = 1.2
var _side: float = 1.0

var _is_rolling: bool = false
var _roll_timer: float = 0.0
var _roll_done: bool = false
var _wing_offset: float = 4.0

var _current_distance: float = 95.0
var _current_lateral: float = 0.0
var _current_vertical: float = 18.0


func _ready() -> void:
	max_hp = 1
	current_hp = 1
	score_value = 300
	super._ready()


func setup_fighter(_start_pos: Vector3, _dir: Vector3, b_type: int = 0) -> void:
	_side = 1.0 if b_type == 2 else -1.0
	_current_distance = start_distance_ahead
	_current_lateral = -40.0 * _side
	_current_vertical = 20.0

	_phase = Phase.ENTER
	_phase_timer = 0.0
	_fire_timer = 1.2
	_roll_done = false
	_is_rolling = false

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]
	_orient_ship(frame["forward"], frame["up"], -_side * 0.25, true)


func _physics_process(delta: float) -> void:
	_phase_timer += delta

	match _phase:
		Phase.ENTER:
			_process_enter(delta)
		Phase.ENGAGE:
			_process_engage(delta)
		Phase.EXIT:
			_process_exit(delta)

	if _current_distance < -15.0:
		queue_free()


func _process_enter(_delta: float) -> void:
	var t := clampf(_phase_timer / maxf(enter_duration, 0.01), 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)

	var start_lat := -40.0 * _side
	var target_lat := -lateral_span * _side
	_current_lateral = lerpf(start_lat, target_lat, eased)
	_current_distance = lerpf(start_distance_ahead, combat_distance_ahead, eased)
	_current_vertical = lerpf(20.0, base_height, eased)

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	var bank := -_side * lerpf(0.35, 0.15, eased)
	_orient_ship(frame["forward"], frame["up"], bank)

	if t >= 1.0:
		_phase = Phase.ENGAGE
		_phase_timer = 0.0


func _process_engage(delta: float) -> void:
	var u := clampf(_phase_timer / maxf(engage_duration, 0.01), 0.0, 1.0)

	# Travessia lateral suave de um lado ao outro da tela ao longo de 8 segundos
	var smooth_u := u * u * (3.0 - 2.0 * u)
	_current_lateral = lerpf(-lateral_span * _side, lateral_span * _side, smooth_u)
	_current_vertical = base_height + sin(u * PI) * 3.0
	_current_distance = lerpf(combat_distance_ahead, combat_distance_ahead - 14.0, u)

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	var base_bank := -_side * 0.25

	# Único Barrel Roll pontual aos 45% da travessia (na metade do voo)
	if not _roll_done and u >= 0.45:
		_is_rolling = true
		_roll_timer = 0.0
		_roll_done = true

	var extra_roll := 0.0
	if _is_rolling:
		_roll_timer += delta
		var roll_t := clampf(_roll_timer / maxf(roll_duration, 0.01), 0.0, 1.0)
		var smooth_roll := roll_t * roll_t * (3.0 - 2.0 * roll_t)
		extra_roll = smooth_roll * TAU * -_side
		if roll_t >= 1.0:
			_is_rolling = false

	_orient_ship(frame["forward"], frame["up"], base_bank + extra_roll)

	# Disparo periódico de lasers duplos a cada 2.0s
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = 2.0
		_shoot_twin_lasers()

	if u >= 1.0:
		_phase = Phase.EXIT
		_phase_timer = 0.0


func _process_exit(delta: float) -> void:
	var t := clampf(_phase_timer / maxf(exit_duration, 0.01), 0.0, 1.0)

	_current_lateral += (_side * 25.0) * delta
	_current_vertical += (20.0 + _phase_timer * 30.0) * delta
	_current_distance += (70.0 + _phase_timer * 110.0) * delta

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	var bank := _side * lerpf(0.3, 0.7, t)
	_orient_ship(frame["forward"], frame["up"], bank)

	if t >= 1.0:
		queue_free()


func _shoot_twin_lasers() -> void:
	if _is_dead:
		return
	var left_pos := global_position + (global_basis.x * -_wing_offset) + (-global_basis.z * 1.5)
	var right_pos := global_position + (global_basis.x * _wing_offset) + (-global_basis.z * 1.5)

	var player: Node3D = _get_player_node()
	var dir_to_player := -global_basis.z
	if player:
		dir_to_player = (player.global_position - global_position).normalized()

	fire_bullet(left_pos, dir_to_player)
	fire_bullet(right_pos, dir_to_player)