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

@export var start_distance_ahead: float = 135.0   ## Distância de spawn à frente da curva (95m à frente da nave)
@export var combat_distance_ahead: float = 100.0  ## Distância durante o combate (60m à frente da nave)
@export var lateral_span: float = 18.0           ## Extensão lateral de travessia calibrada para o canyon (±18m)
@export var base_height: float = 6.0             ## Altura média de voo

@export var is_cinematic_entrance: bool = false ## Se true, faz um rasante dramático na entrada
@export var cinematic_lane: int = 0          ## 0: Direita (+2.8m), 1: Esquerda (-2.8m), 2: Cima (+3.4m)

var flight_direction: Vector3 = Vector3.FORWARD
var _phase: Phase = Phase.ENTER
var _phase_timer: float = 0.0
var _shots_fired: int = 0
var _side: float = 1.0
var _current_distance: float = 135.0
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


func setup_flight(_start_pos: Vector3, dir: Vector3, side: float = 1.0, _speed: float = 60.0, lane: int = 0) -> void:
	flight_direction = dir.normalized()
	_side = 1.0 if side >= 0.0 else -1.0
	cinematic_lane = lane

	if is_cinematic_entrance:
		# Nasce 160m ATRÁS da câmera (-18m - 160m = -178m) iniciando no silêncio com crescendo sonoro perfeito
		_current_distance = -178.0
		if cinematic_lane == 0:
			_current_lateral = 2.8
			_current_vertical = 1.4
		elif cinematic_lane == 1:
			_current_lateral = -2.8
			_current_vertical = 1.4
		else:
			_current_lateral = 0.0
			_current_vertical = 3.4
	else:
		# Entrada pela lateral fora da tela (65m de offset lateral)
		_current_distance = 110.0
		_current_lateral = -_side * 65.0
		_current_vertical = base_height + 6.0

	_phase = Phase.ENTER
	_phase_timer = 0.0
	_shots_fired = 0

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]
	var initial_bank := 0.0
	if is_cinematic_entrance:
		initial_bank = -0.5 if cinematic_lane == 0 else (0.5 if cinematic_lane == 1 else 0.0)
	else:
		initial_bank = -_side * 0.4
	_orient_ship(frame["forward"], frame["up"], initial_bank, true)


func force_exit() -> void:
	if _phase != Phase.EXIT:
		_phase = Phase.EXIT
		_phase_timer = 0.0


func _physics_process(delta: float) -> void:
	_phase_timer += delta

	match _phase:
		Phase.ENTER:
			_process_enter(delta)
		Phase.ENGAGE:
			_process_engage(delta)
		Phase.EXIT:
			_process_exit(delta)

	# Se a nave ficou para trás do jogador durante combate normal, descarta
	if _current_distance < -190.0 and _phase != Phase.ENTER:
		queue_free()


func _process_enter(_delta: float) -> void:
	var total_dur := 2.2 if is_cinematic_entrance else enter_duration
	var t := clampf(_phase_timer / maxf(total_dur, 0.01), 0.0, 1.0)

	if is_cinematic_entrance:
		if t < 0.60:
			var surge_t := t / 0.60
			_current_distance = lerpf(-178.0, 65.0, surge_t)

			if cinematic_lane == 0:
				# 0: Rasante pela Direita
				_current_lateral = lerpf(2.8, 4.5, surge_t)
				_current_vertical = lerpf(1.4, 3.8, surge_t)
				var bank := -lerpf(0.35, 0.65, surge_t)
				_curve_offset = _get_player_progress() + _current_distance
				var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
				global_position = frame["position"]
				_orient_ship(frame["forward"], frame["up"], bank)
			elif cinematic_lane == 1:
				# 1: Rasante pela Esquerda
				_current_lateral = lerpf(-2.8, -4.5, surge_t)
				_current_vertical = lerpf(1.4, 3.8, surge_t)
				var bank := lerpf(0.35, 0.65, surge_t)
				_curve_offset = _get_player_progress() + _current_distance
				var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
				global_position = frame["position"]
				_orient_ship(frame["forward"], frame["up"], bank)
			else:
				# 2: Rasante por Cima (topo da tela)
				_current_lateral = lerpf(0.0, 0.0, surge_t)
				_current_vertical = lerpf(3.4, 5.0, surge_t)
				var pitch_dip := -lerpf(0.10, 0.0, surge_t)
				_curve_offset = _get_player_progress() + _current_distance
				var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
				global_position = frame["position"]
				_orient_ship(frame["forward"] + Vector3(0, pitch_dip, 0), frame["up"], 0.0)

			# Efeito Doppler de aproximação supersônica
			set_engine_pitch(lerpf(1.12, 1.22, surge_t))
		else:
			var settle_t := (t - 0.60) / 0.40
			var eased_settle := settle_t * (2.0 - settle_t)
			_current_distance = lerpf(65.0, combat_distance_ahead, eased_settle)

			if cinematic_lane == 0:
				_current_lateral = lerpf(4.5, -lateral_span, eased_settle)
				_current_vertical = lerpf(3.8, base_height, eased_settle)
				var bank := -lerpf(0.65, 0.2, eased_settle)
				_curve_offset = _get_player_progress() + _current_distance
				var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
				global_position = frame["position"]
				_orient_ship(frame["forward"], frame["up"], bank)
			elif cinematic_lane == 1:
				_current_lateral = lerpf(-4.5, lateral_span, eased_settle)
				_current_vertical = lerpf(3.8, base_height, eased_settle)
				var bank := lerpf(0.65, 0.2, eased_settle)
				_curve_offset = _get_player_progress() + _current_distance
				var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
				global_position = frame["position"]
				_orient_ship(frame["forward"], frame["up"], bank)
			else:
				_current_lateral = lerpf(0.0, -lateral_span * _side, eased_settle)
				_current_vertical = lerpf(5.0, base_height, eased_settle)
				_curve_offset = _get_player_progress() + _current_distance
				var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
				global_position = frame["position"]
				_orient_ship(frame["forward"], frame["up"], 0.0)

			# Queda suave de pitch para o tom normal de voo (1.0)
			set_engine_pitch(lerpf(1.22, 1.0, eased_settle))
	else:
		# Entrada lateral suave: surge de fora da visão lateral (-65m) e faz curva em direção ao centro do combate
		var eased := t * t * (3.0 - 2.0 * t)
		var start_lat := -_side * 65.0
		var target_lat := -lateral_span * _side
		_current_lateral = lerpf(start_lat, target_lat, eased)
		_current_distance = lerpf(110.0, combat_distance_ahead, eased)
		_current_vertical = lerpf(base_height + 6.0, base_height, eased)

		_curve_offset = _get_player_progress() + _current_distance
		var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
		global_position = frame["position"]

		var bank := -_side * lerpf(0.45, 0.15, eased)
		_orient_ship(frame["forward"], frame["up"], bank)

	if t >= 1.0:
		_phase = Phase.ENGAGE
		_phase_timer = 0.0
		if is_cinematic_entrance and cinematic_lane == 1:
			_side = -1.0
		else:
			_side = 1.0 if _current_lateral < 0.0 else -1.0


func _process_engage(_delta: float) -> void:
	var u := clampf(_phase_timer / maxf(engage_duration, 0.01), 0.0, 1.0)

	# Travessia contínua e suave em S
	var angle := (u * 2.0 - 0.5) * PI
	_current_lateral = sin(angle) * lateral_span * _side
	_current_vertical = base_height + sin(u * 2.0 * PI) * 4.5

	# Oscilação suave de profundidade
	var depth_osc := sin(u * 2.0 * PI) * 20.0
	_current_distance = combat_distance_ahead + depth_osc

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	var lateral_dir := cos(angle) * _side
	var pitch_adj := -cos(u * 2.0 * PI) * 0.15
	var bank := -clampf(lateral_dir * 0.45, -0.55, 0.55)
	_orient_ship(frame["forward"] + Vector3(0, pitch_adj, 0), frame["up"], bank)

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

	_current_lateral += (_side * 12.0) * delta
	_current_vertical += (12.0 + _phase_timer * 20.0) * delta
	_current_distance += (70.0 + _phase_timer * 100.0) * delta

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	var bank := _side * lerpf(0.2, 0.5, t)
	_orient_ship(frame["forward"], frame["up"], bank)

	if t >= 1.0:
		queue_free()


func _shoot() -> void:
	if _is_dead:
		return
	var player: Node3D = _get_player_node()
	var dir_to_player := -global_basis.z
	if player:
		dir_to_player = (player.global_position - global_position).normalized()
	var shoot_pos := global_position + dir_to_player * 12.0
	fire_bullet(shoot_pos, dir_to_player)
