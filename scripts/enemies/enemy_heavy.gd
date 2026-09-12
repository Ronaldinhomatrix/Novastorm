class_name EnemyHeavy
extends "res://scripts/enemies/enemy_base.gd"

## Inimigo Cruzador Pesado / Mini-Boss (Starship.v3).
##
## Padrão de Voo Rail-Shooter:
## - 1 HP (morre com 1 tiro).
## - Permanece na frente do jogador durante 14.0s em uma deriva horizontal imponente.
## - Se o jogador ultrapassar ou a nave fugir, é liberada imediatamente.

enum Phase { ENTER, ENGAGE, EXIT }

@export_category("Padrão de Voo")
@export var enter_duration: float = 2.0
@export var engage_duration: float = 14.0
@export var exit_duration: float = 3.0

@export var start_distance_ahead: float = 160.0  ## Distância de spawn à frente da curva (120m à frente da nave)
@export var combat_distance_ahead: float = 120.0 ## Distância durante o combate (80m à frente da nave)
@export var width_amplitude: float = 18.0        ## Amplitude horizontal calibrada para o canyon (±18m)
@export var height_amplitude: float = 5.0        ## Amplitude vertical (±5.0m)

var flight_direction: Vector3 = Vector3.FORWARD
var _phase: Phase = Phase.ENTER
var _phase_timer: float = 0.0
var _attack_timer: float = 1.8
var _attack_pattern_index: int = 0
var _shots_fired: int = 0
var _side: float = 1.0
var _current_distance: float = 115.0
var _current_lateral: float = 0.0
var _current_vertical: float = 15.0

var _rnd_lat: float = 1.0
var _rnd_vert: float = 0.0
var _rnd_dist: float = 0.0
var _th_1: float = 0.20
var _th_2: float = 0.50
var _th_3: float = 0.80

var _bob_speed: float = 1.0
var _bob_phase: float = 0.0

var is_curve_driven: bool = false
var _r_trigger: float = 0.0
var _r_spawn: float = 0.0
var _r_meet: float = 0.0
var _r_exit: float = 0.0
var _curve_len: float = 0.0
var _target_lateral: float = 0.0

func _ready() -> void:
	max_hp = 50
	current_hp = 50
	score_value = 800
	
	_rnd_lat = randf_range(0.85, 1.15)
	_rnd_vert = randf_range(-1.5, 2.0)
	_rnd_dist = randf_range(-10.0, 10.0)
	
	_th_1 = randf_range(0.15, 0.25)
	_th_2 = _th_1 + randf_range(0.25, 0.35)
	_th_3 = randf_range(0.75, 0.85)

	_bob_speed = randf_range(0.5, 1.5)
	_bob_phase = randf_range(0.0, TAU)
	
	super._ready()

	if flight_direction.length_squared() < 0.001:
		flight_direction = -global_basis.z.normalized()
	else:
		flight_direction = flight_direction.normalized()


func setup_heavy(_start_pos: Vector3, dir: Vector3, side: float = 1.0) -> void:
	flight_direction = dir.normalized()
	_side = 1.0 if side >= 0.0 else -1.0

	# Entrada vindo da lateral fora da tela
	_current_distance = 180.0
	_current_lateral = -_side * 150.0
	_current_vertical = 35.0

	_phase = Phase.ENTER
	_phase_timer = 0.0
	_attack_timer = 2.0
	_attack_pattern_index = 0

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]
	_orient_ship(frame["forward"], frame["up"], -_side * 0.35, true)


func setup_heavy_curve_driven(dir: Vector3, side: float, r_trigger: float, r_spawn: float, r_meet: float, r_exit: float, c_len: float) -> void:
	is_curve_driven = true
	flight_direction = dir.normalized()
	_side = 1.0 if side >= 0.0 else -1.0
	
	_r_trigger = r_trigger
	_r_spawn = r_spawn
	_r_meet = r_meet
	_r_exit = r_exit
	_curve_len = c_len
	
	_target_lateral = _side * 18.0 * randf_range(0.3, 0.9)
	
	_phase = Phase.ENGAGE
	_phase_timer = 0.0
	_attack_timer = 2.0
	_attack_pattern_index = 0
	
	var c_prog = _get_player_progress()
	_current_distance = (r_spawn * c_len) - c_prog
	_current_lateral = -_side * 150.0
	_current_vertical = 35.0
	
	_curve_offset = c_prog + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]
	_orient_ship(frame["forward"], frame["up"], -_side * 0.35, true)


func force_exit() -> void:
	if _phase != Phase.EXIT:
		_phase = Phase.EXIT
		_phase_timer = 0.0


func _physics_process(delta: float) -> void:
	if is_curve_driven:
		_process_curve_driven(delta)
		return
		
	_phase_timer += delta

	match _phase:
		Phase.ENTER:
			_process_enter(delta)
		Phase.ENGAGE:
			_process_engage(delta)
		Phase.EXIT:
			_process_exit(delta)

	if _current_distance < -25.0:
		queue_free()


func _process_curve_driven(delta: float) -> void:
	_phase_timer += delta
	_attack_timer -= delta
	
	var c_prog = _get_player_progress()
	var c_ratio = c_prog / maxf(_curve_len, 1.0)
	
	if c_ratio >= _r_exit:
		queue_free()
		return
		
	var t_dist := 0.0
	var t_lat := 0.0
	var t_vert := 15.0
	var t_bank := 0.0
	var t_pitch := 0.0
	
	var bob := sin(_phase_timer * _bob_speed + _bob_phase) * 1.5
	
	if c_ratio < _r_meet:
		var meet_len = maxf(0.001, _r_meet - _r_trigger)
		var t = clampf((c_ratio - _r_trigger) / meet_len, 0.0, 1.0)
		var ease_t = t * t * (3.0 - 2.0 * t)
		
		var spawn_dist = (_r_spawn - _r_trigger) * _curve_len
		t_dist = lerpf(spawn_dist, 0.0, ease_t)
		t_lat = lerpf(-_side * 150.0, _target_lateral, ease_t)
		t_vert = lerpf(40.0, 15.0 + bob, ease_t)
		t_bank = -_side * 0.2 * sin(ease_t * PI)
		
		if t > 0.3 and t < 0.9 and _attack_timer <= 0.0:
			_attack_timer = 2.0
			_execute_attack()
	else:
		var exit_len = maxf(0.001, _r_exit - _r_meet)
		var t = clampf((c_ratio - _r_meet) / exit_len, 0.0, 1.0)
		var ease_t = t * t * (3.0 - 2.0 * t)
		
		t_dist = lerpf(0.0, -150.0, ease_t)
		t_lat = lerpf(_target_lateral, _side * 150.0, ease_t)
		t_vert = lerpf(15.0 + bob, 45.0, ease_t)
		t_bank = _side * lerpf(0.0, 0.45, ease_t)
		t_pitch = lerpf(0.0, 0.35, ease_t)
		
	var lerp_weight := 1.0 - exp(-3.0 * delta)
	_current_lateral = lerpf(_current_lateral, t_lat, lerp_weight)
	_current_vertical = lerpf(_current_vertical, t_vert, lerp_weight)
	_current_distance = lerpf(_current_distance, t_dist, lerp_weight)
	
	_curve_offset = c_prog + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]
	_orient_ship(frame["forward"] + Vector3(0, t_pitch, 0), frame["up"], t_bank)


func _process_enter(delta: float) -> void:
	var t := clampf(_phase_timer / maxf(enter_duration, 0.01), 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)

	var start_lat := -_side * 65.0
	var target_lat := 0.0
	_current_lateral = lerpf(start_lat, target_lat, eased)
	_current_distance = lerpf(135.0, combat_distance_ahead, eased)
	_current_vertical = lerpf(30.0, 14.0 + height_amplitude, eased)

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	var bank := -_side * lerpf(0.35, 0.25, eased)
	_orient_ship(frame["forward"], frame["up"], bank)

	if t >= 1.0:
		_phase = Phase.ENGAGE
		_phase_timer = 0.0


func _process_engage(delta: float) -> void:
	var u := clampf(_phase_timer / maxf(engage_duration, 0.01), 0.0, 1.0)

	var t_lat := _current_lateral
	var t_vert := 14.0 + _rnd_vert
	var t_dist := combat_distance_ahead + _rnd_dist
	var t_bank := 0.0
	var t_pitch := 0.0
	
	var width_amp := width_amplitude * _rnd_lat
	
	var independent_bob := sin(_phase_timer * _bob_speed + _bob_phase) * 1.5
	t_vert += independent_bob

	# Padrão pesado orgânico
	if u < _th_1:
		var t := u / _th_1
		var ease_t := t * t * (3.0 - 2.0 * t)
		t_lat = lerpf(-width_amp * _side * 0.5, 0.0, ease_t)
		t_bank = -_side * 0.15 * sin(ease_t * PI)
	elif u < _th_2:
		var len_th := maxf(0.01, _th_2 - _th_1)
		var t := (u - _th_1) / len_th
		t_lat = lerpf(0.0, width_amp * _side * 0.3, t)
		t_bank = -_side * 0.05 * sin(t * PI)
	elif u < _th_3:
		var len_th := maxf(0.01, _th_3 - _th_2)
		var t := (u - _th_2) / len_th
		var ease_t := t * t * (3.0 - 2.0 * t)
		t_lat = lerpf(width_amp * _side * 0.3, width_amp * _side * 0.8, ease_t)
		t_dist += sin(ease_t * PI) * 12.0
		t_bank = -_side * 0.3 * sin(ease_t * PI)
	elif u < 0.90:
		var len_th := maxf(0.01, 0.90 - _th_3)
		var t := (u - _th_3) / len_th
		t_lat = lerpf(width_amp * _side * 0.8, width_amp * _side * 0.5, t)
		t_bank = _side * 0.05 * sin(t * PI)
	else:
		var len_th := maxf(0.01, 0.10)
		var t := (u - 0.90) / len_th
		var ease_t := t * t * (3.0 - 2.0 * t)
		t_lat = lerpf(width_amp * _side * 0.5, width_amp * _side, ease_t)
		t_vert = lerpf(12.0 + _rnd_vert, 25.0 + _rnd_vert, ease_t)
		t_pitch = lerpf(0.0, 0.25, ease_t)

	var lerp_weight := 1.0 - exp(-2.0 * delta)
	_current_lateral = lerpf(_current_lateral, t_lat, lerp_weight)
	_current_vertical = lerpf(_current_vertical, t_vert, lerp_weight)
	_current_distance = lerpf(_current_distance, t_dist, lerp_weight)

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	_orient_ship(frame["forward"] + Vector3(0, t_pitch, 0), frame["up"], t_bank)

	# Sistema de ataques contínuos
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = 2.0 
		_execute_attack()

	if u >= 1.0:
		_phase = Phase.EXIT
		_phase_timer = 0.0


func _process_exit(delta: float) -> void:
	var t := clampf(_phase_timer / maxf(exit_duration, 0.01), 0.0, 1.0)

	_current_vertical += (20.0 + _phase_timer * 25.0) * delta
	_current_distance += (60.0 + _phase_timer * 90.0) * delta

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	var bank := _side * lerpf(0.1, 0.5, t)
	_orient_ship(frame["forward"], frame["up"], bank)

	if t >= 1.0:
		queue_free()


func _execute_attack() -> void:
	if _is_dead:
		return
	_attack_pattern_index = (_attack_pattern_index + 1) % 2
	if _attack_pattern_index == 0:
		_shoot_triple_spread()
	else:
		_shoot_twin_heavy_burst()


func _shoot_triple_spread() -> void:
	var right_vec := global_basis.x
	var player: Node3D = _get_player_node()
	var base_dir := -global_basis.z
	if player:
		base_dir = (player.global_position - global_position).normalized()

	var left_dir := (base_dir - right_vec * 0.18).normalized()
	var right_dir := (base_dir + right_vec * 0.18).normalized()

	var center_pos := global_position + (base_dir * 18.0)
	var left_pos := global_position + (-right_vec * 8.0) + (left_dir * 18.0)
	var right_pos := global_position + (right_vec * 8.0) + (right_dir * 18.0)

	fire_bullet(left_pos, left_dir)
	fire_bullet(center_pos, base_dir)
	fire_bullet(right_pos, right_dir)


func _shoot_twin_heavy_burst() -> void:
	var right_vec := global_basis.x
	var player: Node3D = _get_player_node()
	var dir_to_player := -global_basis.z
	if player:
		dir_to_player = (player.global_position - global_position).normalized()

	var left_pos := global_position + (-right_vec * 6.0) + (dir_to_player * 18.0)
	var right_pos := global_position + (right_vec * 6.0) + (dir_to_player * 18.0)

	fire_bullet(left_pos, dir_to_player)
	fire_bullet(right_pos, dir_to_player)


func die() -> void:
	if _is_dead:
		return
	_is_dead = true

	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	if _engine_audio_player and is_instance_valid(_engine_audio_player):
		if _engine_audio_player.finished.is_connected(_on_engine_sound_finished):
			_engine_audio_player.finished.disconnect(_on_engine_sound_finished)
		_engine_audio_player.stop()

	# Desmonte do asset 3D em 3 partes com proporção e força aumentadas mantendo o movimento
	var vel := get_linear_velocity()
	EnemyWreckageScript.spawn_from_enemy(self, 1.6, vel)

	# Efeito de grande explosão de cruzador
	var exp_big: Node3D = ExplosionScript.new()
	var spawn_parent: Node = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if spawn_parent:
		spawn_parent.add_child(exp_big)
	exp_big.global_position = global_position
	if _cached_sound_manager and _cached_sound_manager.has_method("play_heavy_explosion"):
		_cached_sound_manager.play_heavy_explosion(explosion_volume_db + 1.0)
	else:
		_play_explosion_sound()

	enemy_destroyed.emit(self, score_value)
	queue_free()
