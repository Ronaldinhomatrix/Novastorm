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

@export var start_distance_ahead: float = 145.0  ## Distância de spawn à frente da curva (105m à frente da nave)
@export var combat_distance_ahead: float = 105.0 ## Distância durante o combate (65m à frente da nave)
@export var lateral_span: float = 28.0          ## Extensão lateral da travessia ampliada (±28m)
@export var base_height: float = 8.0            ## Altura média de combate
@export var roll_duration: float = 1.0          ## Duração do giro 360°

@export var is_cinematic_entrance: bool = false ## Se true, faz um rasante de entrada nascendo 160m atrás da câmera
@export var cinematic_lane: int = 0          ## 0: Direita (+2.8m), 1: Esquerda (-2.8m), 2: Cima (+3.4m)
@export var is_cinematic_exit: bool = false ## Se true, faz um rasante dramático passando rente ao jogador na saída

var _phase: Phase = Phase.ENTER
var _phase_timer: float = 0.0
var _fire_timer: float = 1.2
var _side: float = 1.0

var _is_rolling: bool = false
var _roll_timer: float = 0.0
var _roll_done: bool = false
var _wing_offset: float = 4.0

var _current_distance: float = 145.0
var _current_lateral: float = 0.0
var _current_vertical: float = 18.0


func _ready() -> void:
	max_hp = 1
	current_hp = 1
	score_value = 300
	super._ready()


var _b_type: int = 0


func setup_fighter(_start_pos: Vector3, _dir: Vector3, b_type: int = 0, lane: int = 0) -> void:
	_b_type = b_type
	_side = 1.0 if b_type == 2 else (-1.0 if b_type == 1 else 1.0)
	cinematic_lane = lane

	if is_cinematic_entrance:
		# Nasce 160m ATRÁS da câmera (-18m - 160m = -178m) com rasante mais aberto e afastado da câmera
		_current_distance = -178.0
		if cinematic_lane == 0:
			_current_lateral = 7.5
			_current_vertical = 3.2
		elif cinematic_lane == 1:
			_current_lateral = -7.5
			_current_vertical = 3.2
		else:
			_current_lateral = 0.0
			_current_vertical = 6.5
	elif _b_type == 0:
		# Tipo 0: Mergulho frontal vindo do horizonte distante (230m) e alta altitude (45m)
		_current_distance = 230.0
		_current_lateral = 0.0
		_current_vertical = 45.0
	else:
		# Tipos 1 e 2: Entram pelas laterais fora da visão (85m de deslocamento)
		_current_distance = 115.0
		_current_lateral = -_side * 85.0
		_current_vertical = 24.0

	_phase = Phase.ENTER
	_phase_timer = 0.0
	_fire_timer = 1.2
	_roll_done = false
	_is_rolling = false

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]
	var initial_bank := 0.0
	if is_cinematic_entrance:
		initial_bank = -0.35 if cinematic_lane == 0 else (0.35 if cinematic_lane == 1 else 0.0)
	else:
		initial_bank = -_side * (0.45 if _b_type != 0 else 0.0)
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
				# 0: Rasante aberto pela Direita (+7.5m -> +12.0m)
				_current_lateral = lerpf(7.5, 12.0, surge_t)
				_current_vertical = lerpf(3.2, 5.5, surge_t)
				var bank := -lerpf(0.25, 0.55, surge_t)
				_curve_offset = _get_player_progress() + _current_distance
				var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
				global_position = frame["position"]
				_orient_ship(frame["forward"], frame["up"], bank)
			elif cinematic_lane == 1:
				# 1: Rasante aberto pela Esquerda (-7.5m -> -12.0m)
				_current_lateral = lerpf(-7.5, -12.0, surge_t)
				_current_vertical = lerpf(3.2, 5.5, surge_t)
				var bank := lerpf(0.25, 0.55, surge_t)
				_curve_offset = _get_player_progress() + _current_distance
				var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
				global_position = frame["position"]
				_orient_ship(frame["forward"], frame["up"], bank)
			else:
				# 2: Rasante alto por Cima (+6.5m -> +9.0m)
				_current_lateral = lerpf(0.0, 0.0, surge_t)
				_current_vertical = lerpf(6.5, 9.0, surge_t)
				var pitch_dip := -lerpf(0.08, 0.0, surge_t)
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
				_current_lateral = lerpf(12.0, -lateral_span * 0.6, eased_settle)
				_current_vertical = lerpf(5.5, base_height, eased_settle)
				var bank := -lerpf(0.55, 0.20, eased_settle)
				_curve_offset = _get_player_progress() + _current_distance
				var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
				global_position = frame["position"]
				_orient_ship(frame["forward"], frame["up"], bank)
			elif cinematic_lane == 1:
				_current_lateral = lerpf(-12.0, lateral_span * 0.6, eased_settle)
				_current_vertical = lerpf(5.5, base_height, eased_settle)
				var bank := lerpf(0.55, 0.20, eased_settle)
				_curve_offset = _get_player_progress() + _current_distance
				var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
				global_position = frame["position"]
				_orient_ship(frame["forward"], frame["up"], bank)
			else:
				_current_lateral = lerpf(0.0, 0.0, eased_settle)
				_current_vertical = lerpf(9.0, base_height + 2.0, eased_settle)
				_curve_offset = _get_player_progress() + _current_distance
				var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
				global_position = frame["position"]
				_orient_ship(frame["forward"], frame["up"], 0.0)

			# Queda suave de pitch para o tom normal de voo (1.0)
			set_engine_pitch(lerpf(1.22, 1.0, eased_settle))
	elif _b_type == 0:
		var eased := t * t * (3.0 - 2.0 * t)
		# Mergulho suave vindo da frente/cima
		_current_lateral = lerpf(0.0, -lateral_span * 0.5, eased)
		_current_distance = lerpf(230.0, combat_distance_ahead, eased)
		_current_vertical = lerpf(45.0, base_height, eased)

		_curve_offset = _get_player_progress() + _current_distance
		var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
		global_position = frame["position"]

		var pitch_down := -lerpf(0.25, 0.0, eased)
		_orient_ship(frame["forward"] + Vector3(0, pitch_down, 0), frame["up"], 0.0)
	else:
		var eased := t * t * (3.0 - 2.0 * t)
		# Entrada lateral curva vindo de fora da tela (±85m)
		var start_lat := -_side * 85.0
		var target_lat := -lateral_span * _side
		_current_lateral = lerpf(start_lat, target_lat, eased)
		_current_distance = lerpf(115.0, combat_distance_ahead, eased)
		_current_vertical = lerpf(24.0, base_height, eased)

		_curve_offset = _get_player_progress() + _current_distance
		var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
		global_position = frame["position"]

		var bank := -_side * lerpf(0.55, 0.15, eased)
		_orient_ship(frame["forward"], frame["up"], bank)

	if t >= 1.0:
		_phase = Phase.ENGAGE
		_phase_timer = 0.0


func _process_engage(delta: float) -> void:
	var u := clampf(_phase_timer / maxf(engage_duration, 0.01), 0.0, 1.0)

	# Travessia lateral agressiva com manobras de avanço e recuo tático (±28m lateral, ±35m profundidade)
	var smooth_u := u * u * (3.0 - 2.0 * u)
	_current_lateral = lerpf(-lateral_span * _side, lateral_span * _side, smooth_u)
	_current_vertical = base_height + sin(u * TAU) * 6.5

	# O caça avança agressivamente se aproximando do jogador (~70m) e recua (~140m)
	var depth_wave := sin(u * 2.5 * PI) * 35.0
	_current_distance = combat_distance_ahead + depth_wave

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	var base_bank := -_side * 0.45
	var pitch_adj := -cos(u * 2.5 * PI) * 0.22

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

	_orient_ship(frame["forward"] + Vector3(0, pitch_adj, 0), frame["up"], base_bank + extra_roll)

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

	if is_cinematic_exit:
		# Rasante cinematográfico de alta velocidade passando a ~3.2m da câmera
		_current_distance -= (85.0 + _phase_timer * 115.0) * delta
		_current_lateral = lerpf(_current_lateral, 3.2 * _side, clampf(_phase_timer / 0.45, 0.0, 1.0))
		_current_vertical = lerpf(_current_vertical, 1.8, clampf(_phase_timer / 0.45, 0.0, 1.0))
		var bank := _side * (0.6 + t * 4.5)

		_curve_offset = _get_player_progress() + _current_distance
		var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
		global_position = frame["position"]
		_orient_ship(frame["forward"], frame["up"], bank)

		if _current_distance < -55.0:
			queue_free()
	else:
		_current_lateral += (_side * 30.0) * delta
		_current_vertical += (20.0 + _phase_timer * 30.0) * delta
		_current_distance += (80.0 + _phase_timer * 120.0) * delta

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
	var player: Node3D = _get_player_node()
	var dir_to_player := -global_basis.z
	if player:
		dir_to_player = (player.global_position - global_position).normalized()

	var left_pos := global_position + (global_basis.x * -_wing_offset) + (dir_to_player * 14.0)
	var right_pos := global_position + (global_basis.x * _wing_offset) + (dir_to_player * 14.0)

	fire_bullet(left_pos, dir_to_player)
	fire_bullet(right_pos, dir_to_player)