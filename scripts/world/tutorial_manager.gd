class_name TutorialManager
extends Node

## Gerenciador Central do Tutorial Interativo para Novastorm.
##
## Controla o fluxo de 2 etapas:
## Etapa 1: Disparo Primário (Laser)
##   - 2 naves surgem à frente.
##   - Câmera lenta (Engine.time_scale = 0.2).
##   - Texto: "Clique com o mouse para disparar" (PC) / "Use o dedo para controlar e disparar" (Mobile).
##   - Sai da câmera lenta assim que o jogador começar a disparar.
##   - Destruição das 2 naves.
##
## Etapa 2: Disparo Secundário (Lock-On & Mísseis)
##   - Entram mais 2 naves (imunes a laser até o disparo do míssil).
##   - Câmera lenta (Engine.time_scale = 0.25).
##   - Texto: "Aponte para os inimigos para travar no alvo".
##   - Ao travar: "Use o botão direito para disparar mísseis" (PC) /
##     Botão de mísseis pisca + "Use este botão para disparar mísseis" (Mobile).
##   - Ao disparar o primeiro míssil: sai da câmera lenta.
##   - Míssil destrói o alvo. Tutorial concluído!

signal tutorial_started
signal tutorial_step_changed(step_index: int)
signal tutorial_completed

enum State {
	INACTIVE,
	WAITING_START,
	STEP1_PRESENTING,     # Naves entrando, câmera lenta, aguardando tiro
	STEP1_ENGAGING,       # Jogador atirando, tempo normal, aguardando destruição
	STEP1_CLEARED,        # Intervalo entre etapas
	STEP2_PRESENTING,     # Novas naves entrando, câmera lenta, aguardando lock-on
	STEP2_LOCKED,         # Alvo travado, orienta disparo de míssil
	STEP2_MISSILE_FIRED,  # Míssil lançado, tempo normal restaurado
	COMPLETED
}

const TutorialEnemyScene := preload("res://scenes/enemies/tutorial_enemy.tscn")
const ChimeSound := preload("res://assets/audio/maneuver2_short.ogg")

@export var enabled: bool = true
@export var limit_point: int = 7
@export var path_follower: PathFollower = null
@export var player: Player = null
@export var hud: CombatHUD = null

var _state: State = State.INACTIVE
var _step1_enemies: Array[Node] = []
var _step2_enemies: Array[Node] = []
var _state_timer: float = 0.0
var _limit_offset: float = -1.0
var _overlay: TutorialOverlay = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if path_follower and path_follower.has_method("set_speed_multiplier"):
		path_follower.set_speed_multiplier(1.0)
	if hud and hud.has_method("stop_tutorial_missile_blink"):
		hud.stop_tutorial_missile_blink()


func setup(p_follower: PathFollower, p_player: Player, p_hud: CombatHUD) -> void:
	path_follower = p_follower
	player = p_player
	hud = p_hud

	if hud and hud.has_method("get_tutorial_overlay"):
		_overlay = hud.get_tutorial_overlay()

	if player:
		if not player.primary_fire_started.is_connected(_on_player_primary_fire_started):
			player.primary_fire_started.connect(_on_player_primary_fire_started)
		if not player.missile_targets_changed.is_connected(_on_player_missile_targets_changed):
			player.missile_targets_changed.connect(_on_player_missile_targets_changed)
		if not player.missile_fired.is_connected(_on_player_missile_fired):
			player.missile_fired.connect(_on_player_missile_fired)

	_calculate_limit_offset()


func _calculate_limit_offset() -> void:
	if not path_follower:
		return
	var parent_path := path_follower.get_parent() as Path3D
	var c: Curve3D = parent_path.curve if parent_path else null
	if c and limit_point >= 0 and limit_point < c.point_count:
		_limit_offset = c.get_closest_offset(c.get_point_position(limit_point))


func start_tutorial() -> void:
	if not enabled or _state != State.INACTIVE:
		return

	if _limit_offset < 0.0:
		_calculate_limit_offset()

	if path_follower and path_follower.has_method("set_speed_multiplier"):
		path_follower.set_speed_multiplier(0.5)

	_state = State.WAITING_START
	_state_timer = 0.8
	tutorial_started.emit()


func _process(delta: float) -> void:
	if _state == State.INACTIVE or _state == State.COMPLETED:
		return

	# Checagem de limite no Path3D: se o jogador atingir o ponto 7 sem concluir, encerra o tutorial imediatamente
	if _limit_offset > 0.0 and path_follower and path_follower.progress >= _limit_offset:
		_abort_tutorial_at_limit()
		return

	# Como time_scale pode estar reduzido (0.2), usamos delta de tempo real
	var real_delta: float = (delta / maxf(Engine.time_scale, 0.05)) if Engine.time_scale < 0.9 else delta

	match _state:
		State.WAITING_START:
			_state_timer -= real_delta
			if _state_timer <= 0.0:
				_start_step_1()

		State.STEP1_ENGAGING:
			# Verifica se ambas as naves da etapa 1 foram destruídas
			_clean_dead_enemies(_step1_enemies)
			if _step1_enemies.is_empty():
				_on_step1_cleared()

		State.STEP1_CLEARED:
			_state_timer -= real_delta
			if _state_timer <= 0.0:
				_start_step_2()

		State.STEP2_MISSILE_FIRED:
			_clean_dead_enemies(_step2_enemies)
			if _step2_enemies.is_empty():
				_on_step2_cleared()


# ---------------------------------------------------------------------------
# ETAPA 1: Disparo Primário (Laser)
# ---------------------------------------------------------------------------

func _start_step_1() -> void:
	_state = State.STEP1_PRESENTING
	tutorial_step_changed.emit(1)

	# 1. Spawn de duas naves inimigas na frente
	_spawn_step1_pair()

	# 2. Ativa câmera lenta
	Engine.time_scale = 0.20

	# 3. Toca som de aviso tático
	_play_chime()

	# 4. Exibe texto instrutivo contextualizado por plataforma
	if _overlay:
		if GameConfig.is_mobile:
			_overlay.show_instruction("USE O DEDO PARA CONTROLAR E DISPARAR", "// TUTORIAL // CONTROLE E TIRO PRIMÁRIO")
		else:
			_overlay.show_instruction("CLIQUE COM O MOUSE PARA DISPARAR", "// TUTORIAL // CONTROLE E TIRO PRIMÁRIO")


func _spawn_step1_pair() -> void:
	_step1_enemies.clear()
	# Nave 1: lateral esquerda (-6.5m), distância 62m
	var e1 := _create_tutorial_enemy(-6.5, 62.0, 4.0, false)
	# Nave 2: lateral direita (+6.5m), distância 62m
	var e2 := _create_tutorial_enemy(6.5, 62.0, 4.0, false)

	if e1:
		_step1_enemies.append(e1)
	if e2:
		_step1_enemies.append(e2)


func _on_player_primary_fire_started() -> void:
	if _state == State.STEP1_PRESENTING:
		# Jogador começou a disparar: SAI DA CÂMERA LENTA!
		_state = State.STEP1_ENGAGING
		Engine.time_scale = 1.0


func _on_step1_cleared() -> void:
	_state = State.STEP1_CLEARED
	_state_timer = 1.2
	if _overlay:
		_overlay.hide_instruction()


# ---------------------------------------------------------------------------
# ETAPA 2: Disparo Secundário (Lock-On & Mísseis)
# ---------------------------------------------------------------------------

func _start_step_2() -> void:
	_state = State.STEP2_PRESENTING
	tutorial_step_changed.emit(2)

	# 1. Entram mais duas naves inimigas (imunes a laser até o disparo do míssil)
	_spawn_step2_pair()

	# 2. Ativa câmera lenta novamente
	Engine.time_scale = 0.25

	# 3. Toca som de aviso tático
	_play_chime()

	# 4. Exibe instrução de mirar para travar no alvo
	if _overlay:
		_overlay.show_instruction(
			"APONTE PARA OS INIMIGOS PARA TRAVAR NO ALVO",
			"// TUTORIAL // MIRA TÁTICA LOCK-ON",
			Color(1.2, 0.75, 0.15, 1.0) # Âmbar/Dourado Neon
		)


func _spawn_step2_pair() -> void:
	_step2_enemies.clear()
	# Nave 1: lateral esquerda (-7.5m), distância 64m (imune a laser)
	var e1 := _create_tutorial_enemy(-7.5, 64.0, 4.2, true)
	# Nave 2: lateral direita (+7.5m), distância 64m (imune a laser)
	var e2 := _create_tutorial_enemy(7.5, 64.0, 4.2, true)

	if e1:
		_step2_enemies.append(e1)
	if e2:
		_step2_enemies.append(e2)


func _on_player_missile_targets_changed(targets: Array[Node3D]) -> void:
	if _state == State.STEP2_PRESENTING and not targets.is_empty():
		# O alvo foi travado com sucesso!
		_state = State.STEP2_LOCKED
		_play_chime()

		if _overlay:
			if GameConfig.is_mobile:
				_overlay.show_instruction(
					"USE ESTE BOTÃO PARA DISPARAR MÍSSEIS",
					"// ALVO TRAVADO // ARMA SECUNDÁRIA",
					Color(0.1, 1.4, 0.45, 1.0)
				)
				# Faz o botão de mísseis piscar no mobile
				if hud and hud.has_method("start_tutorial_missile_blink"):
					hud.start_tutorial_missile_blink()
			else:
				_overlay.show_instruction(
					"USE O BOTÃO DIREITO PARA DISPARAR MÍSSEIS",
					"// ALVO TRAVADO // ARMA SECUNDÁRIA",
					Color(0.1, 1.4, 0.45, 1.0)
				)


func _on_player_missile_fired(_remaining: int, _max_val: int) -> void:
	if _state == State.STEP2_LOCKED or _state == State.STEP2_PRESENTING:
		# Jogador disparou o primeiro míssil: SAI DA CÂMERA LENTA!
		_state = State.STEP2_MISSILE_FIRED
		Engine.time_scale = 1.0

		# Permite que quaisquer naves restantes da etapa 2 também sejam vulneráveis a laser
		for enemy in _step2_enemies:
			if is_instance_valid(enemy):
				enemy.immune_to_lasers = false

		# Interrompe o piscar do botão no Mobile
		if hud and hud.has_method("stop_tutorial_missile_blink"):
			hud.stop_tutorial_missile_blink()


func _on_step2_cleared() -> void:
	_state = State.COMPLETED
	Engine.time_scale = 1.0
	if path_follower and path_follower.has_method("set_speed_multiplier"):
		path_follower.set_speed_multiplier(1.0)

	if _overlay:
		_overlay.flash_completion("MÍSSEIS DISPARADOS // SISTEMAS DE COMBATE OPERACIONAIS")

	tutorial_completed.emit()


## Encerramento forçado caso o jogador atinja o ponto 7 do Path3D sem ter executado os passos do tutorial
func _abort_tutorial_at_limit() -> void:
	_state = State.COMPLETED
	Engine.time_scale = 1.0

	if path_follower and path_follower.has_method("set_speed_multiplier"):
		path_follower.set_speed_multiplier(1.0)

	if hud and hud.has_method("stop_tutorial_missile_blink"):
		hud.stop_tutorial_missile_blink()

	if _overlay:
		_overlay.hide_instruction()

	# Remove naves do tutorial que possam ter restado na pista
	for e in _step1_enemies:
		if is_instance_valid(e):
			e.queue_free()
	_step1_enemies.clear()

	for e in _step2_enemies:
		if is_instance_valid(e):
			e.queue_free()
	_step2_enemies.clear()

	tutorial_completed.emit()


# ---------------------------------------------------------------------------
# Utilitários de Criação e Limpeza
# ---------------------------------------------------------------------------

func _create_tutorial_enemy(lat: float, dist: float, vert: float, laser_immune: bool) -> Node:
	var enemy := TutorialEnemyScene.instantiate()
	if not enemy:
		return null

	var scene_root: Node = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if scene_root:
		scene_root.add_child(enemy)
	else:
		add_child(enemy)

	if enemy.has_method("setup_tutorial_formation"):
		enemy.setup_tutorial_formation(lat, dist, vert, laser_immune)
	return enemy


func _clean_dead_enemies(arr: Array[Node]) -> void:
	var i := arr.size() - 1
	while i >= 0:
		var e := arr[i]
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			arr.remove_at(i)
		elif "current_hp" in e and e.current_hp <= 0:
			arr.remove_at(i)
		elif "_is_dead" in e and e._is_dead:
			arr.remove_at(i)
		i -= 1


func _play_chime() -> void:
	if ChimeSound:
		if has_node("/root/SoundManager"):
			get_node("/root/SoundManager").play_sfx(ChimeSound, -2.0, 1.05)
		else:
			var p := AudioStreamPlayer.new()
			p.stream = ChimeSound
			p.volume_db = -2.0
			p.pitch_scale = 1.05
			add_child(p)
			p.finished.connect(p.queue_free)
			p.play()
