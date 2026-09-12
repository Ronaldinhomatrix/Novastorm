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
	STEP2_READING,        # Câmera lenta e texto de mirar exibido; delay de 1s antes dos inimigos surgirem
	STEP2_PRESENTING,     # Novas naves entrando, câmera lenta, aguardando lock-on
	STEP2_LOCKED,         # Alvo travado, orienta disparo de míssil
	STEP2_MISSILE_FIRED,  # Míssil lançado, tempo normal restaurado
	STEP2_RELOADING,      # Exibe flecha apontando para o botão: "Mísseis carregando" por ~3s
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
	if player and "missiles_enabled" in player:
		player.missiles_enabled = true
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

		State.STEP2_READING:
			_state_timer -= real_delta
			if _state_timer <= 0.0:
				_spawn_step2_enemies()

		State.STEP2_MISSILE_FIRED:
			_clean_dead_enemies(_step2_enemies)
			if _step2_enemies.is_empty():
				_on_step2_cleared()

		State.STEP2_RELOADING:
			_state_timer -= real_delta
			if _state_timer <= 0.0:
				_finish_tutorial()


# ---------------------------------------------------------------------------
# ETAPA 1: Disparo Primário (Laser)
# ---------------------------------------------------------------------------

func _start_step_1() -> void:
	_state = State.STEP1_PRESENTING
	tutorial_step_changed.emit(1)

	# 0. Bloqueia os mísseis durante o treinamento de disparo primário (laser)
	if player and "missiles_enabled" in player:
		player.missiles_enabled = false

	# 1. Spawn de duas naves inimigas na frente
	_spawn_step1_pair()

	# 2. Ativa câmera lenta
	Engine.time_scale = 0.20

	# 3. Toca som de aviso tático
	_play_chime()

	# 4. Exibe texto instrutivo contextualizado por plataforma
	if _overlay:
		if GameConfig.is_mobile:
			_overlay.show_instruction("USE O DEDO PARA CONTROLAR E DISPARAR")
		else:
			_overlay.show_instruction("CLIQUE COM O MOUSE PARA DISPARAR")


func _spawn_step1_pair() -> void:
	_step1_enemies.clear()
	# Nave 1: lateral esquerda (-7.5m), distância 135m (espaçamento confortável à frente da nave)
	var e1 := _create_tutorial_enemy(-7.5, 135.0, 4.0, false)
	# Nave 2: lateral direita (+7.5m), distância 135m (espaçamento confortável à frente da nave)
	var e2 := _create_tutorial_enemy(7.5, 135.0, 4.0, false)

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
	_state = State.STEP2_READING
	_state_timer = 3.5  # 3.5s em tempo real para o jogador ler com total tranquilidade
	tutorial_step_changed.emit(2)

	# 0. Reabilita os mísseis para a etapa de lock-on e mísseis
	if player and "missiles_enabled" in player:
		player.missiles_enabled = true

	# 1. Ativa câmera super lenta no exato instante em que a instrução surge na tela
	Engine.time_scale = 0.08

	# 2. Toca som de aviso tático
	_play_chime()

	# 3. Exibe instrução de mirar para travar as 3 no alvo (pista livre enquanto o jogador lê)
	if _overlay:
		_overlay.show_instruction(
			"MIRE NAS TRÊS NAVES INIMIGAS",
			"TRAVE AS 3 NO ALVO",
			"",
			Color(1.2, 0.75, 0.15, 1.0)
		)


func _spawn_step2_enemies() -> void:
	_state = State.STEP2_PRESENTING
	# As naves surgem em posições bem separadas e NÃO convergem para o centro
	_spawn_step2_trio()


func _spawn_step2_trio() -> void:
	_step2_enemies.clear()
	# As 3 naves ocupam posições bem espaçadas dentro do cânion e NÃO convergem para o centro:
	# Nave 1: lateral esquerda (-20.0m), voa rente à parede esquerda do cânion sem atravessá-la
	var e1 := _create_tutorial_enemy(-20.0, 160.0, 5.5, true, -20.0, 5.5)
	# Nave 2: lateral direita (+20.0m), voa rente à parede direita do cânion sem atravessá-la
	var e2 := _create_tutorial_enemy(20.0, 160.0, 5.5, true, 20.0, 5.5)
	# Nave 3: topo elevado (+24.0m), no céu aberto do cânion sem mergulhar
	var e3 := _create_tutorial_enemy(0.0, 165.0, 24.0, true, 0.0, 24.0)

	if e1:
		_step2_enemies.append(e1)
	if e2:
		_step2_enemies.append(e2)
	if e3:
		_step2_enemies.append(e3)


func _on_player_missile_targets_changed(targets: Array[Node3D]) -> void:
	if _state == State.STEP2_PRESENTING:
		var required_locks := mini(3, _step2_enemies.size())
		if targets.size() >= required_locks and not targets.is_empty():
			# Todos os 3 alvos foram travados com sucesso!
			_state = State.STEP2_LOCKED
			_play_chime()

			if _overlay:
				if GameConfig.is_mobile:
					_overlay.show_instruction(
						"DISPARE 3 MÍSSEIS",
						"TOQUE NO BOTÃO DO MÍSSIL",
						"",
						Color(0.1, 1.4, 0.45, 1.0)
					)
					# Faz o botão de mísseis piscar no mobile
					if hud and hud.has_method("start_tutorial_missile_blink"):
						hud.start_tutorial_missile_blink()
				else:
					_overlay.show_instruction(
						"DISPARE 3 MÍSSEIS",
						"BOTÃO DIREITO DO MOUSE",
						"",
						Color(0.1, 1.4, 0.45, 1.0)
					)
	elif _state == State.STEP2_LOCKED:
		var required_locks := mini(3, _step2_enemies.size())
		if targets.size() < required_locks:
			# O jogador perdeu a mira de algum alvo antes de atirar; volta para o estado de mira
			_state = State.STEP2_PRESENTING
			if hud and hud.has_method("stop_tutorial_missile_blink"):
				hud.stop_tutorial_missile_blink()
			if _overlay:
				_overlay.show_instruction(
					"MIRE NAS TRÊS NAVES INIMIGAS",
					"TRAVE AS 3 NO ALVO",
					"",
					Color(1.2, 0.75, 0.15, 1.0)
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
	# Terceiro inimigo destruído! Inicia a parte 3: flecha apontando para o botão dos mísseis com "Mísseis carregando" por 3s
	_state = State.STEP2_RELOADING
	_state_timer = 3.0
	Engine.time_scale = 1.0

	if _overlay:
		_overlay.hide_instruction()

	if hud and hud.has_method("start_tutorial_missile_blink"):
		hud.start_tutorial_missile_blink("Mísseis carregando")


func _finish_tutorial() -> void:
	_state = State.COMPLETED
	Engine.time_scale = 1.0
	if player and "missiles_enabled" in player:
		player.missiles_enabled = true
	if path_follower and path_follower.has_method("set_speed_multiplier"):
		path_follower.set_speed_multiplier(1.0)

	if hud and hud.has_method("stop_tutorial_missile_blink"):
		hud.stop_tutorial_missile_blink()

	if _overlay:
		_overlay.flash_completion()

	tutorial_completed.emit()


## Encerramento forçado caso o jogador atinja o ponto 7 do Path3D sem ter executado os passos do tutorial
func _abort_tutorial_at_limit() -> void:
	_state = State.COMPLETED
	Engine.time_scale = 1.0

	if player and "missiles_enabled" in player:
		player.missiles_enabled = true

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

func _create_tutorial_enemy(lat: float, dist: float, vert: float, laser_immune: bool, start_lat: float = NAN, start_vert: float = NAN) -> Node:
	var enemy := TutorialEnemyScene.instantiate()
	if not enemy:
		return null

	var scene_root: Node = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if scene_root:
		scene_root.add_child(enemy)
	else:
		add_child(enemy)

	if enemy.has_method("setup_tutorial_formation"):
		enemy.setup_tutorial_formation(lat, dist, vert, laser_immune, start_lat, start_vert)
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
