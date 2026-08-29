class_name EnemyScout
extends "res://scripts/enemies/enemy_base.gd"

## Inimigo Caça Leve / Reconhecimento (Starship.002).
##
## Padrão de Voo Rail-Shooter:
## - 1 HP (morre com 1 tiro).
## - Permanece na frente do jogador durante 7.0s em uma travessia suave de ponta a ponta.
## - Se o jogador ultrapassar ou a nave fugir, é liberada imediatamente.

enum Phase { ENTER, ENGAGE, EXIT }

@export_category("Padrão de Voo")
@export var enter_duration: float = 1.5
@export var engage_duration: float = 7.0
@export var exit_duration: float = 2.0

@export var start_distance_ahead: float = 90.0   ## Distância de spawn à frente da câmera
@export var combat_distance_ahead: float = 65.0  ## Distância durante o combate
@export var lateral_span: float = 30.0           ## Extensão lateral da travessia (±30m)
@export var base_height: float = 6.0             ## Altura média de voo

var flight_direction: Vector3 = Vector3.FORWARD
var _phase: Phase = Phase.ENTER
var _phase_timer: float = 0.0
var _shots_fired: int = 0
var _side: float = 1.0
var _current_distance: float = 90.0
var _current_lateral: float = 0.0
var _current_vertical: float = 6.0


func _ready() -> void:
	max_hp = 1
	current_hp = 1
	score_value = 100
	super._ready()

	if flight_direction.length_squared() < 0.001:
		flight_direction = -global_basis.z.normalized()
	else:
		flight_direction = flight_direction.normalized()


func setup_flight(_start_pos: Vector3, dir: Vector3, side: float = 1.0, _speed: float = 60.0) -> void:
	flight_direction = dir.normalized()
	_side = 1.0 if side >= 0.0 else -1.0
	_current_distance = start_distance_ahead
	_current_lateral = -42.0 * _side
	_current_vertical = base_height + 4.0

	_phase = Phase.ENTER
	_phase_timer = 0.0
	_shots_fired = 0

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]
	_orient_ship(frame["forward"], frame["up"], -_side * 0.3, true)


func _physics_process(delta: float) -> void:
	_phase_timer += delta

	match _phase:
		Phase.ENTER:
			_process_enter(delta)
		Phase.ENGAGE:
			_process_engage(delta)
		Phase.EXIT:
			_process_exit(delta)

	# Se a nave ficou para trás do jogador, descarta imediatamente
	if _current_distance < -15.0:
		queue_free()


func _process_enter(_delta: float) -> void:
	var t := clampf(_phase_timer / maxf(enter_duration, 0.01), 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)

	var start_lat := -42.0 * _side
	var target_lat := -lateral_span * _side
	_current_lateral = lerpf(start_lat, target_lat, eased)
	_current_distance = lerpf(start_distance_ahead, combat_distance_ahead, eased)
	_current_vertical = lerpf(base_height + 4.0, base_height, eased)

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	var bank := -_side * lerpf(0.4, 0.2, eased)
	_orient_ship(frame["forward"], frame["up"], bank)

	if t >= 1.0:
		_phase = Phase.ENGAGE
		_phase_timer = 0.0


func _process_engage(_delta: float) -> void:
	var u := clampf(_phase_timer / maxf(engage_duration, 0.01), 0.0, 1.0)

	# Travessia suave em arco único de um lado ao outro da tela (sem círculos)
	var angle := (u * 1.5 - 0.5) * PI
	_current_lateral = sin(angle) * lateral_span * _side
	_current_vertical = base_height + sin(u * PI) * 2.5
	_current_distance = lerpf(combat_distance_ahead, combat_distance_ahead - 10.0, u)

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	var lateral_dir := cos(angle) * _side
	var bank := -clampf(lateral_dir * 0.35, -0.4, 0.4)
	_orient_ship(frame["forward"], frame["up"], bank)

	# Disparos pontuais aos 30% e 70% da travessia
	if _shots_fired == 0 and u >= 0.30:
		_shots_fired += 1
		_shoot()
	elif _shots_fired == 1 and u >= 0.70:
		_shots_fired += 1
		_shoot()

	if u >= 1.0:
		_phase = Phase.EXIT
		_phase_timer = 0.0


func _process_exit(delta: float) -> void:
	var t := clampf(_phase_timer / maxf(exit_duration, 0.01), 0.0, 1.0)

	_current_lateral += (_side * 20.0) * delta
	_current_vertical += (15.0 + _phase_timer * 25.0) * delta
	_current_distance += (60.0 + _phase_timer * 100.0) * delta

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	var bank := _side * lerpf(0.2, 0.6, t)
	_orient_ship(frame["forward"], frame["up"], bank)

	if t >= 1.0:
		queue_free()


func _shoot() -> void:
	if _is_dead:
		return
	var shoot_pos := global_position + (-global_basis.z * 2.0)
	var player: Node3D = _get_player_node()
	var dir_to_player := -global_basis.z
	if player:
		dir_to_player = (player.global_position - global_position).normalized()
	fire_bullet(shoot_pos, dir_to_player)
