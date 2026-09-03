class_name EnemyBomber
extends "res://scripts/enemies/enemy_base.gd"

## Inimigo Bombardeiro Pesado (Enemy Bomber).
##
## Aparece no Ponto 25 realizando um rasante supersônico vindo de trás da câmera
## (idêntico ao estilo das primeiras naves inimigas das Waves 1 e 2).
##
## Ao ultrapassar o jogador e assumir a vanguarda, executa uma varredura lateral
## no cânion deixando uma fileira de minas/bombas flutuantes estacionárias no ar.
## O jogador deve manobrar para desviar entre as minas ou destruí-las com lasers.
##
## Este inimigo NÃO dispara lasers convencionais.

enum Phase { ENTER, BOMB_RUN, EXIT }

const BombScene := preload("res://scenes/enemies/enemy_bomb.tscn")
const BombDropSound := preload("res://assets/audio/mothership1_torpedo.ogg")
const EnemyBombScript := preload("res://scripts/enemies/enemy_bomb.gd")

@export_category("Comportamento do Bomber")
@export var enter_duration: float = 2.2
@export var bomb_run_duration: float = 6.0
@export var exit_duration: float = 2.5

@export var combat_distance_ahead: float = 85.0   ## Distância à frente do jogador durante o lançamento
@export var lateral_span: float = 14.0            ## Amplitude de varredura lateral (±14m)
@export var base_height: float = 6.0              ## Altura de voo no cânion
@export var total_bombs: int = 8                  ## Quantidade de bombas na fileira
@export var drop_interval: float = 0.6            ## Intervalo em segundos entre cada bomba

var _phase: Phase = Phase.ENTER
var _phase_timer: float = 0.0
var _current_distance: float = -178.0
var _current_lateral: float = 0.0
var _current_vertical: float = 4.0

var _bombs_dropped: int = 0
var _drop_timer: float = 0.0
var _side: float = 1.0


func _ready() -> void:
	max_hp = 5
	current_hp = 5
	score_value = 600
	enable_engine_sound = true
	super._ready()


func setup_bomber(_start_pos: Vector3, _dir: Vector3, side: float = 1.0) -> void:
	_side = 1.0 if side >= 0.0 else -1.0
	_phase = Phase.ENTER
	_phase_timer = 0.0
	_bombs_dropped = 0
	_drop_timer = 0.4  ## Pequeno delay antes de soltar a primeira bomba após o rasante

	# Nasce 178m atrás da câmera para fazer o rasante perfeito
	_current_distance = -178.0
	_current_lateral = _side * 3.5
	_current_vertical = 3.5

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]
	_orient_ship(frame["forward"], frame["up"], -_side * 0.3, true)


func force_exit() -> void:
	if _phase != Phase.EXIT:
		_phase = Phase.EXIT
		_phase_timer = 0.0


func _physics_process(delta: float) -> void:
	_phase_timer += delta

	match _phase:
		Phase.ENTER:
			_process_enter(delta)
		Phase.BOMB_RUN:
			_process_bomb_run(delta)
		Phase.EXIT:
			_process_exit(delta)

	# Se ficou muito para trás por qualquer motivo fora da entrada, descarta
	if _current_distance < -190.0 and _phase != Phase.ENTER:
		queue_free()


# ---------------------------------------------------------------------------
# Fase 1: Rasante Supersônico vindo de trás do jogador (-178m para +85m)
# ---------------------------------------------------------------------------

func _process_enter(_delta: float) -> void:
	var total_dur := maxf(enter_duration, 0.01)
	var t := clampf(_phase_timer / total_dur, 0.0, 1.0)

	if t < 0.60:
		# Rasante acelerando e cruzando a câmera em alta velocidade
		var surge_t := t / 0.60
		_current_distance = lerpf(-178.0, 55.0, surge_t)
		_current_lateral = lerpf(_side * 3.5, _side * 6.0, surge_t)
		_current_vertical = lerpf(3.5, 4.8, surge_t)

		var bank := -_side * lerpf(0.25, 0.50, surge_t)
		_curve_offset = _get_player_progress() + _current_distance
		var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
		global_position = frame["position"]
		_orient_ship(frame["forward"], frame["up"], bank)

		# Efeito Doppler do motor subindo
		set_engine_pitch(lerpf(1.10, 1.30, surge_t))
	else:
		# Desacelera para a distância de engajamento e estabiliza à frente
		var settle_t := (t - 0.60) / 0.40
		var eased := settle_t * (2.0 - settle_t)
		_current_distance = lerpf(55.0, combat_distance_ahead, eased)
		_current_lateral = lerpf(_side * 6.0, -_side * 2.0, eased)
		_current_vertical = lerpf(4.8, base_height, eased)

		var bank := -_side * lerpf(0.50, 0.1, eased)
		_curve_offset = _get_player_progress() + _current_distance
		var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
		global_position = frame["position"]
		_orient_ship(frame["forward"], frame["up"], bank)

		set_engine_pitch(lerpf(1.30, 1.0, eased))

	if t >= 1.0:
		_phase = Phase.BOMB_RUN
		_phase_timer = 0.0
		_drop_timer = 0.3


# ---------------------------------------------------------------------------
# Fase 2: Bombing Run - Varredura em ziguezague soltando fileira de bombas
# ---------------------------------------------------------------------------

func _process_bomb_run(delta: float) -> void:
	var u := clampf(_phase_timer / maxf(bomb_run_duration, 0.01), 0.0, 1.0)

	# Trajetória senoidal contínua cortando o cânion de um lado ao outro (onda em S)
	var sweep_angle := u * PI * 2.5
	var target_lat := sin(sweep_angle) * lateral_span * _side
	var target_vert := base_height + cos(sweep_angle * 0.8) * 1.8
	var target_dist := combat_distance_ahead + sin(u * PI) * 8.0
	var target_bank := -cos(sweep_angle) * 0.45 * _side

	var lerp_w := 1.0 - exp(-6.0 * delta)
	_current_lateral = lerpf(_current_lateral, target_lat, lerp_w)
	_current_vertical = lerpf(_current_vertical, target_vert, lerp_w)
	_current_distance = lerpf(_current_distance, target_dist, lerp_w)

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]
	_orient_ship(frame["forward"], frame["up"], target_bank)

	# Lançamento de bombas a intervalos regulares
	if _bombs_dropped < total_bombs:
		_drop_timer -= delta
		if _drop_timer <= 0.0:
			_drop_timer = drop_interval
			_drop_bomb()

	if u >= 1.0:
		_phase = Phase.EXIT
		_phase_timer = 0.0


func _drop_bomb() -> void:
	if _is_dead or not is_inside_tree():
		return

	_bombs_dropped += 1
	var bomb: Node3D = BombScene.instantiate() as Node3D
	if not bomb:
		return

	# Solta a bomba logo atrás da cauda do Bomber
	var drop_pos := global_position + global_basis.z * 4.5 - global_basis.y * 0.8
	bomb.global_position = drop_pos

	# Adiciona no container de mundo ou cena
	var container: Node = get_parent()
	if container:
		container.add_child(bomb)
	else:
		get_tree().current_scene.add_child(bomb)

	# Som sutil de lançamento de mina/bomba
	_play_drop_sound()


func _play_drop_sound() -> void:
	if not BombDropSound:
		return
	var audio := AudioStreamPlayer3D.new()
	audio.stream = BombDropSound
	audio.bus = "Master"
	audio.volume_db = -8.0
	audio.pitch_scale = randf_range(1.2, 1.4)
	audio.unit_size = 10.0
	audio.max_distance = 180.0
	audio.finished.connect(audio.queue_free)
	get_tree().current_scene.add_child(audio)
	audio.global_position = global_position
	audio.play()


# ---------------------------------------------------------------------------
# Fase 3: Saída - Pós-combustor subindo íngreme em direção ao topo do cânion
# ---------------------------------------------------------------------------

func _process_exit(delta: float) -> void:
	var t := clampf(_phase_timer / maxf(exit_duration, 0.01), 0.0, 1.0)

	_current_lateral += (_side * 6.0) * delta
	_current_vertical += (15.0 + _phase_timer * 30.0) * delta
	_current_distance += (90.0 + _phase_timer * 120.0) * delta

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	var pitch_up := lerpf(0.0, 0.5, t)
	_orient_ship(frame["forward"] + Vector3(0, pitch_up, 0), frame["up"], _side * 0.2)

	if t >= 1.0:
		queue_free()
