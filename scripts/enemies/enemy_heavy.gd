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
@export var width_amplitude: float = 32.0        ## Amplitude horizontal ampliada (±32m)
@export var height_amplitude: float = 6.5        ## Amplitude vertical ampliada (±6.5m)

var flight_direction: Vector3 = Vector3.FORWARD
var _phase: Phase = Phase.ENTER
var _phase_timer: float = 0.0
var _attack_timer: float = 1.8
var _attack_pattern_index: int = 0
var _side: float = 1.0

var _current_distance: float = 160.0
var _current_lateral: float = 0.0
var _current_vertical: float = 24.0


func _ready() -> void:
	max_hp = 1
	current_hp = 1
	score_value = 500
	super._ready()

	if flight_direction.length_squared() < 0.001:
		flight_direction = -global_basis.z.normalized()
	else:
		flight_direction = flight_direction.normalized()


func setup_heavy(_start_pos: Vector3, dir: Vector3, side: float = 1.0) -> void:
	flight_direction = dir.normalized()
	_side = 1.0 if side >= 0.0 else -1.0

	# Entrada vindo da lateral fora da tela (80m de deslocamento) e altitude superior (38m)
	_current_distance = 135.0
	_current_lateral = -_side * 80.0
	_current_vertical = 38.0

	_phase = Phase.ENTER
	_phase_timer = 0.0
	_attack_timer = 2.0
	_attack_pattern_index = 0

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]
	_orient_ship(frame["forward"], frame["up"], -_side * 0.35, true)


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

	if _current_distance < -25.0:
		queue_free()


func _process_enter(_delta: float) -> void:
	var t := clampf(_phase_timer / maxf(enter_duration, 0.01), 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)

	var start_lat := -_side * 80.0
	var target_lat := -_side * 14.0
	_current_lateral = lerpf(start_lat, target_lat, eased)
	_current_distance = lerpf(135.0, combat_distance_ahead, eased)
	_current_vertical = lerpf(38.0, 12.0, eased)

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	var bank := -_side * lerpf(0.35, 0.05, eased)
	_orient_ship(frame["forward"], frame["up"], bank)

	if t >= 1.0:
		_phase = Phase.ENGAGE
		_phase_timer = 0.0


func _process_engage(delta: float) -> void:
	var u := clampf(_phase_timer / maxf(engage_duration, 0.01), 0.0, 1.0)

	# Deriva horizontal lenta e imponente com ampla oscilação de aproximação/recuo
	var angle := u * TAU
	_current_lateral = sin(angle) * width_amplitude * _side
	_current_vertical = 14.0 + cos(angle) * height_amplitude

	# Oscilação imponente de profundidade do cruzador (aproxima-se até ~92m e recua até ~148m)
	var depth_surge := sin(angle) * 28.0
	_current_distance = combat_distance_ahead + depth_surge

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	# Banking suave e pesado de cruzador espacial (~16 graus)
	var bank := -cos(angle) * 0.28 * _side
	var pitch_adj := -cos(angle) * 0.14
	_orient_ship(frame["forward"] + Vector3(0, pitch_adj, 0), frame["up"], bank)

	# Sistema de ataques alternados
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = 2.4
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
	if has_node("/root/SoundManager"):
		get_node("/root/SoundManager").play_heavy_explosion(explosion_volume_db + 1.0)
	else:
		_play_explosion_sound()

	enemy_destroyed.emit(self, score_value)
	queue_free()