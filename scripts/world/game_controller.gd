class_name GameController
extends Node3D

## Controlador central do jogo.
## Gerencia HUD, pontuação e referências aos componentes principais.
## O movimento ao longo do Path3D é controlado por PathFollower.
## Detecta fim do nível e exibe tela de LEVEL COMPLETE.
## Inclui fase de pré-carregamento/aquecimento com cortina preta (warmup) para garantir
## que colisões, texturas e shaders estejam 100% prontos na VRAM antes do jogo aparecer.

# ---------------------------------------------------------------------------
# Exportações e Configurações
# ---------------------------------------------------------------------------

# Trilha sonora do nível 1.
const MUSIC_LEVEL_1 := preload("res://assets/audio/music_1_Aphelion.ogg")

# Som da nave mãe (Mothership) - efeito posicional tocado ao se aproximar dela.
const MOTHERSHIP_SOUND := preload("res://assets/audio/mothership1.ogg")

# Som de disparo do torpedo da Mothership.
const MOTHERSHIP_TORPEDO_SOUND := preload("res://assets/audio/mothership1_torpedo.ogg")

# Script do retículo de mira (crosshair) desenhado na tela como overlay UI.
const CrosshairScript := preload("res://scripts/ui/crosshair.gd")

# Efeito cinematográfico de clarão de disparo da Mothership.
const MothershipMuzzleFlashScript := preload("res://scripts/effects/mothership_muzzle_flash.gd")

var _crosshair: Control = null  ## Instância do crosshair UI

@export_category("Áudio e Música")
## Trilha sonora do nível.
@export var background_music: AudioStream = preload("res://assets/audio/music_1_Aphelion.ogg")
## Volume da música de fundo em dB. 0 = 100%, -6 ≈ 50%, -12 ≈ 25%.
@export_range(-40.0, 0.0, 0.5) var music_volume_db: float = -9.7

@export_category("Aviso Cinematográfico de Inimigos (HUD)")
## Ativa o aviso cinematográfico de proximidade hostil no HUD
@export var enable_cinematic_warning: bool = false
## Ponto do Path3D onde o aviso de inimigos é exibido (-1 = desativado)
@export var cinematic_warning_point: int = -1
@export var cinematic_warning_title: String = "WARNING // INCOMING ENEMIES"
@export var cinematic_warning_subtitle: String = "RADAR PROXIMITY ALERT // HOSTILE SQUADRONS DETECTED"
@export var cinematic_warning_duration: float = 5.5

@export_category("Sons de Manobra de Câmera")
## Ativa sons de manobra em pontos específicos da pista
@export var enable_maneuver_sounds: bool = false
@export var maneuver_sound_p19_point: int = -1
@export var maneuver_sound_p22_point: int = -1

@export_category("Componentes")
@export var path_follower: PathFollower = null
@export var player: Node3D = null
@export var camera: Camera3D = null
@export var player_scene: PackedScene = preload("res://scenes/player.tscn")
@export var mothership: Node3D = null

@export_category("Mothership Animation")
@export var mothership_start_point: int = -1
@export var mothership_end_point: int = -1
@export var mothership_rotation_deg: float = 30.0
## Ponto do Path3D onde fica a origem do som da Mothership (-1 = desativado).
@export var mothership_sound_point: int = -1
## Pontos do Path3D onde a Mothership dispara seus 2 torpedos de energia (-1 = desativado).
@export var mothership_fire_point_1: int = -1
@export var mothership_fire_point_2: int = -1
## Volume do som da Mothership em dB (+3.0 dB ≈ +40% de volume).
@export_range(-20.0, 10.0, 0.5) var mothership_sound_volume_db: float = 3.0

@export_category("Comboio Terrestre")
@export var convoy_node_path: NodePath = ""
@export var convoy_move_start_point: int = -1  ## Ponto onde o comboio começa a se mover e os tanques padrão disparam (-1 = desativado)
@export var convoy_move_end_point: int = -1    ## Ponto onde o comboio interrompe o movimento e os tanques padrão cessam fogo (-1 = desativado)
@export var bridge_tanks_start_point: int = 44 ## Ponto onde os tanques da ponte (Tank1_Bridge_*) começam a disparar
@export var bridge_tanks_end_point: int = 46   ## Ponto onde os tanques da ponte (Tank1_Bridge_*) cessam fogo

@export_category("Intro Cinematica")
@export var enable_cinematic_intro: bool = false
@export var intro_duration: float = 5.0
@export var intro_start_azimuth_deg: float = 135.0  ## Ângulo horizontal inicial em graus (135 = diagonal lateral frontal)
@export var intro_start_elevation_deg: float = -20.0  ## Ângulo vertical inicial em graus (negativo = abaixo da nave)
@export_range(0.05, 1.0) var intro_start_distance_fraction: float = 0.25  ## Distância inicial como fração da distância padrão (0.25 = 25%)

@export_category("Cenario")
@export var enable_cloud_sky: bool = true  ## Gera nuvens estáticas no céu do nível
@export var terrain_detail_material: Material  # PC: sobrescrito por nível; carregado sob demanda se vazio
@export var custom_camera_far_pc: float = GameConfig.CAMERA_FAR_PC  ## Alcance da câmera no PC em metros (sobrescrito por nível)
@export var custom_camera_far_mobile: float = GameConfig.CAMERA_FAR_MOBILE  ## Alcance da câmera no Mobile em metros (sobrescrito por nível)
@export var enable_depth_fog: bool = true  ## Névoa de profundidade automática (sem pop-in)
@export var mothership_cast_shadow: bool = true  ## Define se a Mothership projeta sombra no cenário (desativar em fases de órbita)

@export_category("Progressão de Nível")
@export var level_complete_scene: PackedScene = preload("res://scenes/level_complete.tscn")
@export var next_level_path: String = ""  ## Caminho para próximo nível (vazio = não transiciona)
@export var show_level_complete: bool = true  ## Mostrar tela ao terminar o nível

@export_category("Cutscene de Fim de Nível")
## Ativa a cutscene cinematográfica ao final do nível (câmera externa + nave subindo).
@export var enable_level_end_cutscene: bool = true
## Posição GLOBAL da câmera externa da cutscene (calculada para 780m a 260 u/s aos 3.0s).
@export var cutscene_camera_position := Vector3(10143.0, 1242.0, -546.0)
## Rotação inicial em graus da câmera externa.
@export var cutscene_camera_rotation_deg := Vector3(-58.8, 79.9, 0.0)
## Se true, a câmera acompanha a nave suavemente (look_at).
@export var cutscene_camera_tracks_ship: bool = true
## Suavização do tracking da câmera (valores maiores = tracking mais rápido, menor atraso sem perder a nave de vista).
@export var cutscene_camera_tracking_smoothing: float = 11.0
## Velocidade constante de subida da nave (unidades/segundo).
@export var cutscene_climb_speed: float = 260.0
## Tempo exato em segundos para a nave alcançar e passar ao lado da câmera.
@export var cutscene_flyby_target_time: float = 3.0
## Deslocamento em relação à câmera no ponto de maior aproximação (efeito rasante).
@export var cutscene_flyby_offset := Vector3(-20.0, -45.0, 18.0)
## Ativa o efeito de Zoom contínuo durante toda a cutscene.
@export var cutscene_enable_zoom: bool = true
## FOV inicial da câmera (graus).
@export var cutscene_initial_fov: float = 56.25
## FOV final após o zoom (graus).
@export var cutscene_target_zoom_fov: float = 36.0
## Duração total da cutscene em segundos (3s até o rasante + 2s vivo + 1.2s fade).
@export var cutscene_duration: float = 6.2
## Fração da duração onde o fade-out para preto começa (aos ~5.0s).
@export_range(0.3, 0.95, 0.05) var cutscene_fade_start: float = 0.8
## Caminho da cena do boss para transicionar ao fim da cutscene.
@export var cutscene_next_scene: String = "res://scenes/stages/level_1_boss.tscn"

@export_category("Inimigos e Ondas")
@export var wave_manager: WaveManager = null
@export var enable_enemy_waves: bool = true

@export_category("Tutorial")
## Ativa o tutorial interativo de tiro e lock-on no início da fase
@export var enable_tutorial: bool = true

@export_category("HUD de Combate")
@export var hud_scene: PackedScene = preload("res://scenes/ui/hud.tscn")
@export var hud: CombatHUD = null

@export_category("Debug e Teste de Trechos")
## Ponto do Path3D onde o percurso deve iniciar ao dar Play (0 = início padrão, 15 = pula direto pro ponto 15, etc.).
@export var debug_start_point: int = 0
## Inicia a partir de uma porcentagem da pista (0.0 a 1.0). Se > 0.0, tem prioridade sobre debug_start_point.
@export_range(0.0, 1.0) var debug_start_ratio: float = 0.0
## Ponto final para loop de teste (se > debug_start_point, repete apenas o trecho selecionado continuamente).
@export var debug_loop_point_end: int = -1

# ---------------------------------------------------------------------------
# Estado Interno
# ---------------------------------------------------------------------------

var _collision_generated: bool = false
var _level_completed: bool = false
var _path_length: float = 0.0
var _initial_warning_shown: bool = false
var _initial_warning_dist: float = 0.0

var _intro_active: bool = false
var _intro_timer: float = 0.0
var _default_camera_pos: Vector3 = Vector3(-0.0112, 0.0, 18.0)
var _default_camera_rot: Vector3 = Vector3.ZERO

# Sons de manobra tocados quando a câmera chega aos pontos 19 e 22.
const MANEUVER_2_SOUND := preload("res://assets/audio/maneuver2.ogg")
const MANEUVER_2_SHORT_SOUND := preload("res://assets/audio/maneuver2_short.ogg")

# Efeito sonoro da manobra 2 (pontos 19 e 22)
var _maneuver2_player: AudioStreamPlayer = null
var _maneuver2_short_player: AudioStreamPlayer = null
var _maneuver2_p19_played: bool = false
var _maneuver2_p22_played: bool = false
var _maneuver2_p19_offset: float = 0.0
var _maneuver2_p22_offset: float = 0.0

# Parâmetros de distância para a rotação da Mothership
var _start_dist: float = 0.0
var _end_dist: float = 0.0
var _initial_mothership_rot_y: float = 0.0

# Player de áudio simplificado da Mothership (2D, sem posição/distância).
var _mothership_sound_player: AudioStreamPlayer = null
var _mothership_sound_played: bool = false
var _mothership_sound_offset: float = 0.0  # offset ao longo do path para o ponto 27
# Torpedo (energy ball) firing state
var _fire_dist_1: float = 0.0
var _fire_dist_2: float = 0.0
var _fire_shot_1_done: bool = false
var _fire_shot_2_done: bool = false
var _energy_ball_scene: PackedScene = preload("res://scenes/projectiles/energy_ball.tscn")

# Convoy state & offsets
var _convoy_move_start_dist: float = -1.0
var _convoy_move_end_dist: float = -1.0
var _bridge_tanks_start_dist: float = -1.0
var _bridge_tanks_end_dist: float = -1.0
var _convoy_node: Node3D = null

# Sistema de tremor de câmera (Screen Shake)
var _shake_time: float = 0.0
var _shake_duration: float = 0.0
var _shake_intensity: float = 0.0

# Reproduz a trilha sonora do nível.
var _music_player: AudioStreamPlayer = null
var _dev_layer: CanvasLayer = null

const TutorialManagerScript := preload("res://scripts/world/tutorial_manager.gd")
var _tutorial_manager: Node = null

# ---------------------------------------------------------------------------
# Ciclo de Vida
# ---------------------------------------------------------------------------

func _ready():
	_start_background_music()

	if not get_node_or_null("ReplaySystem"):
		var replay_sys := ReplaySystem.new()
		replay_sys.name = "ReplaySystem"
		add_child(replay_sys)

	if not path_follower:
		path_follower = get_node_or_null("FlightPath/PathFollower") as PathFollower
	
	if not mothership:
		mothership = get_node_or_null("Mothership")
	
	if mothership:
		_initial_mothership_rot_y = mothership.rotation_degrees.y

	if not player:
		player = get_node_or_null("FlightPath/PathFollower/Player")
		if not player and path_follower:
			var p_instance := player_scene.instantiate() as Node3D
			path_follower.add_child(p_instance)
			p_instance.name = "Player"
			p_instance.position = Vector3(0.0, 0.0, -40.0)
			player = p_instance

	if not camera and path_follower:
		camera = path_follower.get_node_or_null("Camera3D") as Camera3D

	# Aplica o padrão oficial global de enquadramento de câmera e posição do player
	CameraConfig.apply_standard_setup(camera, player)

	# Configura o ouvinte de áudio 3D na câmera.
	_setup_audio_listener()
	
	# Player de áudio da Mothership (apenas se configurado e presente)
	if mothership and mothership_sound_point >= 0:
		_mothership_sound_player = AudioStreamPlayer.new()
		_mothership_sound_player.stream = MOTHERSHIP_SOUND
		_mothership_sound_player.bus = "Master"
		_mothership_sound_player.volume_db = mothership_sound_volume_db
		add_child(_mothership_sound_player)
	_mothership_sound_played = false

	# Pausa o movimento imediatamente durante a fase de pré-carregamento
	if path_follower:
		path_follower.set_paused(true)

	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(false)

	# Calcular comprimento do path e distâncias de eventos configurados no nível
	var flight_path := get_node_or_null("FlightPath") as Path3D
	if flight_path and flight_path.curve:
		var curve := flight_path.curve
		_path_length = curve.get_baked_length()
		var point_count := curve.point_count

		if point_count > 0:
			if mothership and mothership_start_point >= 0 and mothership_end_point >= 0:
				var clamped_start := clampi(mothership_start_point, 0, point_count - 1)
				var clamped_end := clampi(mothership_end_point, 0, point_count - 1)
				_start_dist = curve.get_closest_offset(curve.get_point_position(clamped_start))
				_end_dist = curve.get_closest_offset(curve.get_point_position(clamped_end))

			if mothership and mothership_fire_point_1 >= 0:
				var fire_idx_1 := clampi(mothership_fire_point_1, 0, point_count - 1)
				_fire_dist_1 = curve.get_closest_offset(curve.get_point_position(fire_idx_1))
			if mothership and mothership_fire_point_2 >= 0:
				var fire_idx_2 := clampi(mothership_fire_point_2, 0, point_count - 1)
				_fire_dist_2 = curve.get_closest_offset(curve.get_point_position(fire_idx_2))

			if mothership and mothership_sound_point >= 0:
				var sound_idx := clampi(mothership_sound_point, 0, point_count - 1)
				_mothership_sound_offset = curve.get_closest_offset(curve.get_point_position(sound_idx))

			if enable_maneuver_sounds:
				if maneuver_sound_p19_point >= 0:
					var m2_p19_idx := clampi(maneuver_sound_p19_point, 0, point_count - 1)
					_maneuver2_p19_offset = curve.get_closest_offset(curve.get_point_position(m2_p19_idx))
				if maneuver_sound_p22_point >= 0:
					var m2_p22_idx := clampi(maneuver_sound_p22_point, 0, point_count - 1)
					_maneuver2_p22_offset = curve.get_closest_offset(curve.get_point_position(m2_p22_idx))

			if enable_cinematic_warning and cinematic_warning_point >= 0:
				var warning_point_idx := clampi(cinematic_warning_point, 0, point_count - 1)
				_initial_warning_dist = curve.get_closest_offset(curve.get_point_position(warning_point_idx))

			if convoy_node_path != ^"" and convoy_move_start_point >= 0 and convoy_move_end_point >= 0:
				var c_move_start_idx := clampi(convoy_move_start_point, 0, point_count - 1)
				var c_move_end_idx := clampi(convoy_move_end_point, 0, point_count - 1)
				_convoy_move_start_dist = curve.get_closest_offset(curve.get_point_position(c_move_start_idx))
				_convoy_move_end_dist = curve.get_closest_offset(curve.get_point_position(c_move_end_idx))

			# Janela de disparo dos tanques da ponte (Tank1_Bridge_*)
			if bridge_tanks_start_point >= 0 and bridge_tanks_end_point >= 0 and point_count > bridge_tanks_start_point:
				var b_start_idx := clampi(bridge_tanks_start_point, 0, point_count - 1)
				var b_end_idx := clampi(bridge_tanks_end_point, 0, point_count - 1)
				_bridge_tanks_start_dist = curve.get_closest_offset(curve.get_point_position(b_start_idx))
				_bridge_tanks_end_dist = curve.get_closest_offset(curve.get_point_position(b_end_idx))

	if convoy_node_path != ^"":
		_convoy_node = get_node_or_null(convoy_node_path) as Node3D

	# Configuração gráfica dinâmica: PC Ultra vs Mobile Otimizado + escolhas do usuário.
	_apply_graphics_settings()
	# Re-aplica os gráficos na hora quando o usuário muda uma opção no menu.
	UserSettings.settings_changed.connect(_apply_graphics_settings)

	if enable_cloud_sky and not get_node_or_null("ProceduralCloudSky"):
		var cloud_sky := ProceduralCloudSky.new()
		cloud_sky.name = "ProceduralCloudSky"
		add_child(cloud_sky)

	# Configura o gerenciador de ondas de inimigos (Waves) SE existir no nível
	if enable_enemy_waves:
		if not wave_manager:
			wave_manager = get_node_or_null("WaveManager") as WaveManager
		if wave_manager and not wave_manager.path_follower:
			wave_manager.path_follower = path_follower

	# Cria a cortina preta de pré-carregamento
	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 100
	add_child(canvas_layer)

	var curtain := ColorRect.new()
	curtain.color = Color.BLACK
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(curtain)

	# Cria a instância da intro cinematográfica se habilitada
	var intro: CinematicIntro = null
	if enable_cinematic_intro:
		intro = CinematicIntro.new()
		intro.enabled = false  # Só inicia após o aquecimento
		intro.path_follower = path_follower
		intro.player = player
		intro.camera = camera
		intro.duration = intro_duration
		intro.start_azimuth_deg = intro_start_azimuth_deg
		intro.start_elevation_deg = intro_start_elevation_deg
		intro.start_distance_fraction = intro_start_distance_fraction
		add_child(intro)

	# Cria o retículo de mira (crosshair) como overlay UI.
	# NOTA: crosshair desabilitado — em rail shooter a nave é a referência
	# de tiro (nave segue o mouse, tiro vai pra frente). O crosshair era
	# redundante. Código mantido para reativação futura se necessário.
	# _setup_crosshair()

	_setup_dev_ui()
	_setup_hud()

	# Dispara o pré-carregamento e aquecimento de shaders/colisões
	_run_preload_and_warmup(canvas_layer, curtain, intro)



func _setup_dev_ui() -> void:
	_dev_layer = CanvasLayer.new()
	_dev_layer.layer = 50
	add_child(_dev_layer)

	var dev_btn := Button.new()
	dev_btn.text = "🔄 DEV: Olhar para Trás (F / B)"
	dev_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	dev_btn.position = Vector2(20, 20)
	dev_btn.focus_mode = Control.FOCUS_NONE
	
	# Estilização sutil do botão Dev
	var override_style := StyleBoxFlat.new()
	override_style.bg_color = Color(0.1, 0.1, 0.15, 0.75)
	override_style.corner_radius_top_left = 6
	override_style.corner_radius_top_right = 6
	override_style.corner_radius_bottom_left = 6
	override_style.corner_radius_bottom_right = 6
	override_style.content_margin_left = 12
	override_style.content_margin_top = 8
	override_style.content_margin_right = 12
	override_style.content_margin_bottom = 8
	dev_btn.add_theme_stylebox_override("normal", override_style)

	dev_btn.pressed.connect(func():
		if player and player.has_method("toggle_look_back"):
			player.toggle_look_back()
	)

	_dev_layer.add_child(dev_btn)


func _setup_hud() -> void:
	if not hud:
		hud = get_node_or_null("HUD") as CombatHUD
	if not hud and hud_scene:
		hud = hud_scene.instantiate() as CombatHUD
		hud.name = "HUD"
		add_child(hud)

	if hud and player:
		hud.attach_player(player)


func _process(delta: float) -> void:
	# Detectar fim do nível (baseado em ratio >= 0.99 ou progresso a menos de 5 unidades do fim)
	if not _level_completed and show_level_complete and path_follower:
		if path_follower.progress_ratio >= 0.99 or path_follower.progress >= _path_length - 5.0:
			_on_level_finished()
	
	# Animação de rotação da Mothership entre os pontos do Path3D (se existir)
	if mothership and _end_dist > _start_dist:
		_update_mothership_rotation()

	# Alerta Cinematográfico único antes da primeira onda de inimigos
	if enable_cinematic_warning and not _initial_warning_shown and _initial_warning_dist > 0.0 and path_follower:
		if path_follower.progress >= _initial_warning_dist:
			_initial_warning_shown = true
			if hud:
				hud.show_cinematic_warning(cinematic_warning_title, cinematic_warning_subtitle, cinematic_warning_duration)

	# Toca o som da Mothership e manobra 2 ao cruzar os pontos definidos.
	if mothership and _mothership_sound_offset > 0.0:
		_trigger_mothership_sound()
	if enable_maneuver_sounds:
		_trigger_maneuver2_sound()
	if mothership and (_fire_dist_1 > 0.0 or _fire_dist_2 > 0.0):
		_handle_mothership_firing()

	# Gerencia o movimento lento e a janela de disparos do comboio terrestre
	if _convoy_node and (_convoy_move_start_dist > 0.0 or _convoy_move_end_dist > 0.0):
		_handle_convoy_logic()

	# Processa tremor de câmera ativo
	_process_camera_shake(delta)


func _handle_mothership_firing() -> void:
	if not path_follower or not mothership or not _energy_ball_scene:
		return

	# Garantia de inicialização das distâncias caso não tenham sido calculadas em _ready()
	if _fire_dist_1 <= 0.0 or _fire_dist_2 <= 0.0:
		var flight_path := get_node_or_null("FlightPath") as Path3D
		if flight_path and flight_path.curve and flight_path.curve.point_count > 0:
			var idx1 := clampi(mothership_fire_point_1, 0, flight_path.curve.point_count - 1)
			var idx2 := clampi(mothership_fire_point_2, 0, flight_path.curve.point_count - 1)
			_fire_dist_1 = flight_path.curve.get_closest_offset(flight_path.curve.get_point_position(idx1))
			_fire_dist_2 = flight_path.curve.get_closest_offset(flight_path.curve.get_point_position(idx2))

	var prog: float = path_follower.progress

	# 1º Torpedo: inicia sequência de disparo no ponto 25
	if not _fire_shot_1_done and _fire_dist_1 > 0.0 and prog >= _fire_dist_1:
		_fire_shot_1_done = true
		_trigger_mothership_torpedo_sequence()

	# 2º Torpedo: inicia sequência de disparo no ponto 27
	if not _fire_shot_2_done and _fire_dist_2 > 0.0 and prog >= _fire_dist_2:
		_fire_shot_2_done = true
		_trigger_mothership_torpedo_sequence()


func _trigger_mothership_torpedo_sequence() -> void:
	# 1. Toca imediatamente o som do torpedo da Mothership
	_play_torpedo_sound()

	# 2. Aguarda exatamente 1 segundo antes de disparar o torpedo e o clarão
	await get_tree().create_timer(1.0).timeout

	# 3. Lança o torpedo e o clarão com mira recalculada em tempo real
	_spawn_mothership_torpedo()


func _play_torpedo_sound() -> void:
	if MOTHERSHIP_TORPEDO_SOUND:
		var audio_player := AudioStreamPlayer.new()
		audio_player.stream = MOTHERSHIP_TORPEDO_SOUND
		audio_player.bus = "Master"
		add_child(audio_player)
		audio_player.play()
		audio_player.finished.connect(audio_player.queue_free)


func _get_mothership_muzzle_position() -> Vector3:
	if mothership:
		var muzzle := mothership.get_node_or_null("TorpedoMuzzle") as Node3D
		if muzzle:
			return muzzle.global_position
		# Offset local preciso derivado da câmera do editor 3D na frente da nave
		return mothership.to_global(Vector3(0.4126, -1.8468, 12.2879))
	return Vector3(3571.202, 632.072, -2145.927)


func _spawn_mothership_torpedo() -> void:
	var instance := _energy_ball_scene.instantiate() as Area3D
	if not instance:
		return

	var spawn_pos := _get_mothership_muzzle_position()
	var flight_path: Path3D = (path_follower.get_parent() as Path3D) if path_follower else (get_node_or_null("FlightPath") as Path3D)
	var torpedo_speed: float = 420.0
	if instance.get("speed") != null and float(instance.get("speed")) > 0.0:
		torpedo_speed = float(instance.get("speed"))

	var target_pos: Vector3 = Vector3.ZERO

	# Estima a posição futura do jogador considerando o trajeto e curvas reais do Path3D a partir do canhão
	if flight_path and flight_path.curve and path_follower:
		var curve: Curve3D = flight_path.curve
		var current_prog: float = path_follower.progress
		var fwd_speed: float = path_follower.forward_speed

		# 1ª estimativa de tempo com base na distância do canhão até o player
		var cur_player_pos: Vector3 = player.global_position if player else path_follower.global_position
		var t: float = spawn_pos.distance_to(cur_player_pos) / torpedo_speed

		# Refinamento iterativo ao longo do Path3D (amostragem da curva futura)
		for _i in range(3):
			var future_prog: float = clampf(current_prog + fwd_speed * t, 0.0, curve.get_baked_length())
			var local_curve_pos: Vector3 = curve.sample_baked(future_prog)
			var future_path_pos: Vector3 = flight_path.global_transform * local_curve_pos
			t = spawn_pos.distance_to(future_path_pos) / torpedo_speed
			target_pos = future_path_pos

		# Ajusta para a altura/posição do player em relação ao trilho
		if player:
			target_pos.y += player.position.y
	else:
		target_pos = player.global_position if player else (spawn_pos + Vector3(0.0, -100.0, 500.0))

	var fire_dir: Vector3 = (target_pos - spawn_pos).normalized()
	if fire_dir.length_squared() < 0.001:
		fire_dir = -mothership.global_transform.basis.z.normalized() if mothership else Vector3.FORWARD

	# Clarão cinematográfico exatamente no canhão frontal da Mothership
	if MothershipMuzzleFlashScript:
		var flash: Node3D = MothershipMuzzleFlashScript.new()
		add_child(flash)
		flash.global_position = spawn_pos
		if flash.has_method("setup"):
			flash.setup(fire_dir)

	add_child(instance)
	instance.global_position = spawn_pos

	if instance.has_method("setup"):
		instance.setup(fire_dir)

	# Tremor de tela no momento do disparo do torpedo da Mothership
	trigger_camera_shake(0.75, 0.48)


## Dispara um tremor na câmera com intensidade e duração configuráveis
func trigger_camera_shake(intensity: float = 0.75, duration: float = 0.48) -> void:
	_shake_intensity = intensity
	_shake_duration = maxf(duration, 0.01)
	_shake_time = _shake_duration


func _process_camera_shake(delta: float) -> void:
	if not camera:
		return

	if _shake_time > 0.0:
		_shake_time -= delta
		if _shake_time <= 0.0:
			_shake_time = 0.0
			camera.h_offset = 0.0
			camera.v_offset = 0.0
			camera.rotation.z = _default_camera_rot.z
		else:
			var progress := _shake_time / _shake_duration
			var current_power := _shake_intensity * progress * progress
			camera.h_offset = randf_range(-1.0, 1.0) * current_power
			camera.v_offset = randf_range(-1.0, 1.0) * (current_power * 0.85)
			camera.rotation.z = _default_camera_rot.z + deg_to_rad(randf_range(-1.0, 1.0) * current_power * 2.4)











func _handle_convoy_logic() -> void:
	if not path_follower:
		return

	if not _convoy_node or not is_instance_valid(_convoy_node):
		if convoy_node_path != ^"":
			_convoy_node = get_node_or_null(convoy_node_path) as Node3D
		if not _convoy_node:
			return

	var current_prog: float = path_follower.progress
	var min_dist := minf(_convoy_move_start_dist, _convoy_move_end_dist)
	var max_dist := maxf(_convoy_move_start_dist, _convoy_move_end_dist)
	var in_convoy_window: bool = (current_prog >= min_dist and current_prog <= max_dist)

	var in_bridge_window: bool = false
	if _bridge_tanks_start_dist >= 0.0 and _bridge_tanks_end_dist >= 0.0:
		var min_b_dist := minf(_bridge_tanks_start_dist, _bridge_tanks_end_dist)
		var max_b_dist := maxf(_bridge_tanks_start_dist, _bridge_tanks_end_dist)
		in_bridge_window = (current_prog >= min_b_dist and current_prog <= max_b_dist)

	for child in _convoy_node.get_children():
		if not is_instance_valid(child):
			continue
		var is_bridge_tank: bool = child.name.begins_with("Tank1_Bridge")
		var should_shoot: bool = in_bridge_window if is_bridge_tank else in_convoy_window
		if "active_move" in child:
			child.set("active_move", false if is_bridge_tank else in_convoy_window)
		if "can_shoot" in child:
			child.set("can_shoot", should_shoot)


func _update_mothership_rotation() -> void:
	if not mothership or not path_follower or _end_dist <= _start_dist:
		return
	
	var current_prog: float = path_follower.progress
	if current_prog <= _start_dist:
		mothership.rotation_degrees.y = _initial_mothership_rot_y
	elif current_prog >= _end_dist:
		mothership.rotation_degrees.y = _initial_mothership_rot_y + mothership_rotation_deg
	else:
		var t := (current_prog - _start_dist) / (_end_dist - _start_dist)
		mothership.rotation_degrees.y = _initial_mothership_rot_y + lerp(0.0, mothership_rotation_deg, t)


func _on_level_finished() -> void:
	_level_completed = true

	# --- Cutscene cinematográfica de fim de nível (câmera externa + nave subindo) ---
	if enable_level_end_cutscene:
		_start_level_end_cutscene()
		return

	# --- Fluxo padrão: tela de Level Complete ---
	# Pausar o movimento permanentemente no fim do percurso
	if path_follower:
		path_follower.set_paused(true)

	# Mostrar tela de level complete
	if level_complete_scene:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var target_next_level := next_level_path
		if target_next_level == "":
			target_next_level = "res://scenes/stages/level_2.tscn"

		var ui := level_complete_scene.instantiate() as LevelComplete
		if ui:
			add_child(ui)
			ui.next_level_path = target_next_level


func _start_level_end_cutscene() -> void:
	var cutscene := CinematicLevelEnd.new()
	cutscene.name = "CinematicLevelEnd"

	# Configura os parâmetros da cutscene a partir dos exports do GameController
	cutscene.cutscene_camera_position = cutscene_camera_position
	cutscene.cutscene_camera_rotation_deg = cutscene_camera_rotation_deg
	cutscene.camera_tracks_ship = cutscene_camera_tracks_ship
	cutscene.camera_tracking_smoothing = cutscene_camera_tracking_smoothing
	cutscene.climb_speed = cutscene_climb_speed
	cutscene.flyby_target_time = cutscene_flyby_target_time
	cutscene.flyby_offset = cutscene_flyby_offset
	cutscene.enable_cinematic_zoom = cutscene_enable_zoom
	cutscene.initial_fov = cutscene_initial_fov
	cutscene.target_zoom_fov = cutscene_target_zoom_fov
	cutscene.duration = cutscene_duration
	cutscene.fade_start_ratio = cutscene_fade_start

	# Determina a cena de destino (boss)
	if cutscene_next_scene != "":
		cutscene.next_scene_path = cutscene_next_scene
	elif next_level_path != "":
		cutscene.next_scene_path = next_level_path
	else:
		cutscene.next_scene_path = "res://scenes/stages/level_1_boss.tscn"

	# Referências aos componentes
	cutscene.path_follower = path_follower
	cutscene.player = player
	cutscene.camera = camera
	cutscene.hud = hud

	# Oculta UI de desenvolvimento e HUD durante a cutscene cinematográfica
	if _dev_layer:
		_dev_layer.visible = false

	add_child(cutscene)
	cutscene.start()


func _get_terrain_node() -> Node:
	var node := get_node_or_null("GrandCanyon")
	if node:
		return node
	node = get_node_or_null("Mountains1")
	if node:
		return node
	return get_node_or_null("Terrain")


const TERRAIN_PC_PATH := "res://assets/materials/terrain_detailed_pc.tres"
const TERRAIN_MOBILE_PATH := "res://assets/materials/terrain_detailed_mobile.tres"
const SettingsMenuScript := preload("res://scripts/ui/settings_menu.gd")

var _settings_menu: CanvasLayer = null

func _apply_graphics_settings() -> void:
	var is_mobile := GameConfig.is_mobile
	var sun := get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	
	var target_far := custom_camera_far_mobile if is_mobile else custom_camera_far_pc
	if camera:
		camera.far = target_far

	# FPS e escala de render: baseline por plataforma (não exposto ao usuário por ora).
	Engine.max_fps = GameConfig.MAX_FPS_MOBILE if is_mobile else GameConfig.MAX_FPS_PC
	if is_mobile:
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		get_viewport().scaling_3d_scale = GameConfig.RENDER_SCALE_MOBILE
		get_viewport().fsr_sharpness = GameConfig.FSR_SHARPNESS_MOBILE
	else:
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = GameConfig.RENDER_SCALE_PC

	# Sombras: qualidade por plataforma, mas ligar/desligar é escolha do usuário.
	var shadows_on := UserSettings.get_shadows()
	if sun:
		sun.shadow_enabled = shadows_on
		if shadows_on:
			if is_mobile:
				# Sombra focal de 100m na nave (leve e nítida)
				sun.directional_shadow_max_distance = GameConfig.SHADOW_MAX_DISTANCE_MOBILE
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
				sun.directional_shadow_blend_splits = false
			else:
				# 1200m de alcance, 4 divisões, sombras nítidas
				sun.directional_shadow_max_distance = GameConfig.SHADOW_MAX_DISTANCE_PC
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
				sun.directional_shadow_blend_splits = true
			sun.shadow_blur = 1.0

	# Terreno: material por plataforma. Mobile nunca projeta sombra no cenário
	# (otimização); PC projeta apenas se o usuário deixou sombras ligadas.
	var terrain_cast := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (shadows_on and not is_mobile) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if is_mobile:
		_apply_scenery_materials_and_shadows(load(TERRAIN_MOBILE_PATH), terrain_cast)
	else:
		_apply_scenery_materials_and_shadows(terrain_detail_material if terrain_detail_material else load(TERRAIN_PC_PATH), terrain_cast)

	# Pós-processamento (Glow / SSAO / SSIL): escolha do usuário, default por plataforma.
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		if enable_depth_fog:
			CameraConfig.apply_depth_fog(world_env.environment, target_far)
		world_env.environment.glow_enabled = UserSettings.get_glow()
		if UserSettings.get_glow() and is_mobile:
			# Glow mais leve no mobile (menos intensidade/bloom), preservando o
			# brilho do projétil sem pesar o pós-processamento.
			world_env.environment.glow_intensity = GameConfig.GLOW_INTENSITY_MOBILE
			world_env.environment.glow_bloom = GameConfig.GLOW_BLOOM_MOBILE
		world_env.environment.ssao_enabled = UserSettings.get_ssao()
		world_env.environment.ssil_enabled = UserSettings.get_ssil()
		if UserSettings.get_ssao():
			world_env.environment.ssao_radius = 2.0
			world_env.environment.ssao_intensity = 2.2
			world_env.environment.ssao_power = 1.5
			world_env.environment.ssao_detail = 0.5
			world_env.environment.ssao_horizon = 0.06
		if UserSettings.get_ssil():
			world_env.environment.ssil_radius = 4.0
			world_env.environment.ssil_intensity = 1.0


func _apply_scenery_materials_and_shadows(mat: Material, shadow_setting: GeometryInstance3D.ShadowCastingSetting) -> void:
	var mountains := _get_terrain_node()
	if mountains:
		var stack: Array = [mountains]
		while stack.size() > 0:
			var node: Node = stack.pop_back()
			if node is MeshInstance3D:
				var mi := node as MeshInstance3D
				if mat:
					mi.material_override = mat
				mi.cast_shadow = shadow_setting
			for child in node.get_children():
				stack.append(child)
	
	# Ajusta projeção de sombra em outros objetos estáticos do cenário
	var static_scenery := ["HighBridge", "SmallBridge", "SmallBridge2", "Castle", "Mothership"]
	for sc_name in static_scenery:
		var sc_node := get_node_or_null(sc_name)
		if sc_node:
			var effective_shadow := shadow_setting
			if sc_name == "Mothership" and not mothership_cast_shadow:
				effective_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for child in sc_node.find_children("*", "MeshInstance3D", true, false):
				var mi := child as MeshInstance3D
				if mi:
					mi.cast_shadow = effective_shadow


# ---------------------------------------------------------------------------
# Pré-carregamento Síncrono e Aquecimento de Shaders/VRAM (Warmup)
# ---------------------------------------------------------------------------

func _run_preload_and_warmup(canvas_layer: CanvasLayer, curtain: ColorRect, intro: CinematicIntro) -> void:
	# 1. Gera e conecta todas as colisões físicas de forma síncrona atrás da cortina preta
	_generate_all_world_collision_sync()

	# 2. Aguarda 2 quadros de renderização para a GPU compilar todos os shaders,
	# carregar texturas na VRAM e estabilizar os buffers
	await get_tree().process_frame
	await get_tree().process_frame

	# 3. Aplica pontos de teste e reinicia o progresso no ponto desejado
	if path_follower:
		if debug_start_ratio > 0.0:
			path_follower.debug_start_ratio = debug_start_ratio
		elif debug_start_point > 0:
			path_follower.debug_start_point = debug_start_point
		if debug_loop_point_end > 0:
			path_follower.debug_loop_point_end = debug_loop_point_end
		path_follower.reset_progress()
		var start_offset: float = path_follower.progress
		if start_offset > 1.0:
			if _initial_warning_dist > 0.0 and start_offset >= _initial_warning_dist:
				_initial_warning_shown = true
			if _mothership_sound_offset > 0.0 and start_offset >= _mothership_sound_offset:
				_mothership_sound_played = true
			if _maneuver2_p19_offset > 0.0 and start_offset >= _maneuver2_p19_offset:
				_maneuver2_p19_played = true
			if _maneuver2_p22_offset > 0.0 and start_offset >= _maneuver2_p22_offset:
				_maneuver2_p22_played = true
			if _fire_dist_1 > 0.0 and start_offset >= _fire_dist_1:
				_fire_shot_1_done = true
			if _fire_dist_2 > 0.0 and start_offset >= _fire_dist_2:
				_fire_shot_2_done = true
		if wave_manager and wave_manager.has_method("_update_target_ratios"):
			wave_manager._update_target_ratios()

	# 4. Inicializa o Tutorial Interativo (apenas se habilitado e fora de testes de trechos)
	var is_testing_section := (path_follower and (path_follower.debug_start_point > 0 or path_follower.debug_start_ratio > 0.0))
	if enable_tutorial and not is_testing_section:
		_tutorial_manager = TutorialManagerScript.new()
		_tutorial_manager.name = "TutorialManager"
		add_child(_tutorial_manager)
		_tutorial_manager.setup(path_follower, player as Player, hud)

	# 5. Despausa o jogo / inicia a introdução cinematográfica (pula intro se estiver testando trecho específico)
	if intro and not is_testing_section:
		intro.enabled = true
		intro.start()
		# A mira só aparece quando a intro terminar.
		if _crosshair and intro.has_signal("intro_completed"):
			if not intro.intro_completed.is_connected(_show_crosshair):
				intro.intro_completed.connect(_show_crosshair)
		if _tutorial_manager:
			intro.intro_completed.connect(func():
				_tutorial_manager.start_tutorial()
			)
	else:
		if path_follower:
			path_follower.set_paused(false)
		if player and player.has_method("set_controls_enabled"):
			player.set_controls_enabled(true)
		# Sem intro → oculta o cursor imediatamente durante gameplay no PC
		var is_mobile := GameConfig.is_mobile
		if not is_mobile:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		if _crosshair:
			_crosshair.visible = true
		if _tutorial_manager:
			_tutorial_manager.start_tutorial()

	# 5. Transição suave (fade-out) da cortina preta para revelar o jogo rodando 100% fluido
	var tween := create_tween()
	tween.tween_property(curtain, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished

	if is_instance_valid(canvas_layer):
		canvas_layer.queue_free()


func _generate_all_world_collision_sync() -> void:
	if _collision_generated:
		return

	var targets: Array[Node] = []
	var terrain := _get_terrain_node()
	if terrain:
		targets.append(terrain)
	
	var high_bridge := get_node_or_null("HighBridge")
	if high_bridge:
		targets.append(high_bridge)

	var small_bridge := get_node_or_null("SmallBridge")
	if small_bridge:
		targets.append(small_bridge)

	var small_bridge2 := get_node_or_null("SmallBridge2")
	if small_bridge2:
		targets.append(small_bridge2)

	for target in targets:
		for child in target.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := child as MeshInstance3D
			if not mesh_instance or not mesh_instance.mesh:
				continue

			var existing_body := mesh_instance.get_node_or_null("StaticBody3D") as StaticBody3D
			if existing_body:
				existing_body.collision_layer = 1 << 3  # layer 4 ("world")
				existing_body.collision_mask = 0
				continue

			# Cria colisão simplificada/trimesh com camada 4 isolada
			mesh_instance.create_trimesh_collision()
			var body := mesh_instance.get_node_or_null("StaticBody3D") as StaticBody3D
			if not body:
				for c in mesh_instance.get_children():
					if c is StaticBody3D:
						body = c as StaticBody3D
						break
			if body:
				body.collision_layer = 1 << 3  # layer 4 ("world")
				body.collision_mask = 0
				for col in body.find_children("*", "CollisionShape3D", false, false):
					var cs := col as CollisionShape3D
					if cs and cs.shape is ConcavePolygonShape3D:
						(cs.shape as ConcavePolygonShape3D).backface_collision = true

	_collision_generated = true



# ---------------------------------------------------------------------------
# Áudio (Trilha Sonora)
# ---------------------------------------------------------------------------

func _start_background_music() -> void:
	if background_music == null:
		return
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = background_music
	_music_player.bus = "Master"
	_music_player.volume_db = music_volume_db  # regulável no Inspector (nome: Music Volume Db)
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)
	_music_player.play()


func _on_music_finished() -> void:
	# Faz a música tocar em loop contínuo durante o nível.
	if _music_player:
		_music_player.play()


# ---------------------------------------------------------------------------
# Áudio 3D (Ouvinte) + Som simplificado da Mothership
# ---------------------------------------------------------------------------

## Garante que a câmera tenha um AudioListener3D (o "ouvido" do jogo).
func _setup_audio_listener() -> void:
	if not camera:
		return
	if camera.get_node_or_null("AudioListener3D") == null:
		var listener := AudioListener3D.new()
		listener.name = "AudioListener3D"
		listener.current = true  # Ativa este ouvinte 3D como referência do AudioServer
		camera.add_child(listener)


## Toca o som da Mothership uma única vez quando o progresso cruza o ponto definido
func _trigger_mothership_sound() -> void:
	if _mothership_sound_player == null or _mothership_sound_played or not path_follower or mothership_sound_point < 0:
		return

	if _mothership_sound_offset <= 0.0:
		var flight_path := get_node_or_null("FlightPath") as Path3D
		if flight_path and flight_path.curve and flight_path.curve.point_count > 0:
			var sound_idx := clampi(mothership_sound_point, 0, flight_path.curve.point_count - 1)
			_mothership_sound_offset = flight_path.curve.get_closest_offset(flight_path.curve.get_point_position(sound_idx))

	if _mothership_sound_offset > 0.0 and path_follower.progress >= _mothership_sound_offset:
		if has_node("/root/SoundManager"):
			get_node("/root/SoundManager").play_voice(MOTHERSHIP_SOUND, mothership_sound_volume_db)
		else:
			_mothership_sound_player.play()
		_mothership_sound_played = true


## Toca os sons de manobra nos pontos específicos configurados para o nível
func _trigger_maneuver2_sound() -> void:
	if not enable_maneuver_sounds or not path_follower:
		return
	if _maneuver2_p19_played and _maneuver2_p22_played:
		return

	if _maneuver2_player == null:
		_maneuver2_player = AudioStreamPlayer.new()
		_maneuver2_player.stream = MANEUVER_2_SOUND
		_maneuver2_player.bus = "Master"
		_maneuver2_player.volume_db = 0.0
		add_child(_maneuver2_player)

	if _maneuver2_short_player == null:
		_maneuver2_short_player = AudioStreamPlayer.new()
		_maneuver2_short_player.stream = MANEUVER_2_SHORT_SOUND
		_maneuver2_short_player.bus = "Master"
		_maneuver2_short_player.volume_db = 0.0
		add_child(_maneuver2_short_player)

	if _maneuver2_p19_offset <= 0.0 and maneuver_sound_p19_point >= 0:
		var flight_path := get_node_or_null("FlightPath") as Path3D
		if flight_path and flight_path.curve and flight_path.curve.point_count > 0:
			var m2_p19_idx := clampi(maneuver_sound_p19_point, 0, flight_path.curve.point_count - 1)
			_maneuver2_p19_offset = flight_path.curve.get_closest_offset(flight_path.curve.get_point_position(m2_p19_idx))

	if _maneuver2_p22_offset <= 0.0 and maneuver_sound_p22_point >= 0:
		var flight_path := get_node_or_null("FlightPath") as Path3D
		if flight_path and flight_path.curve and flight_path.curve.point_count > 0:
			var m2_p22_idx := clampi(maneuver_sound_p22_point, 0, flight_path.curve.point_count - 1)
			_maneuver2_p22_offset = flight_path.curve.get_closest_offset(flight_path.curve.get_point_position(m2_p22_idx))

	var prog := path_follower.progress

	# Ponto 19 (maneuver2.ogg)
	if not _maneuver2_p19_played and _maneuver2_p19_offset > 0.0 and prog >= _maneuver2_p19_offset:
		if has_node("/root/SoundManager"):
			get_node("/root/SoundManager").play_voice(MANEUVER_2_SOUND, 0.0, randf_range(0.97, 1.03))
		else:
			_maneuver2_player.pitch_scale = randf_range(0.97, 1.03)
			_maneuver2_player.play()
		_maneuver2_p19_played = true

	# Ponto 22 (maneuver2_short.ogg)
	if not _maneuver2_p22_played and _maneuver2_p22_offset > 0.0 and prog >= _maneuver2_p22_offset:
		if has_node("/root/SoundManager"):
			get_node("/root/SoundManager").play_voice(MANEUVER_2_SHORT_SOUND, 0.0, randf_range(0.97, 1.03))
		else:
			_maneuver2_short_player.pitch_scale = randf_range(0.97, 1.03)
			_maneuver2_short_player.play()
		_maneuver2_p22_played = true


# ---------------------------------------------------------------------------
# Crosshair (Retículo de Mira)
# ---------------------------------------------------------------------------

## Cria e posiciona o retículo procedural como overlay UI na tela,
## acoplado ao mouse. A própria classe Crosshair detecta inimigos.
## O crosshair começa OCULTO e só é revelado quando a intro termina
## (ou imediatamente se não houver intro).
func _setup_crosshair() -> void:
	if not CrosshairScript:
		return
	var cl := CanvasLayer.new()
	cl.name = "CrosshairLayer"
	cl.layer = 90
	add_child(cl)

	_crosshair = CrosshairScript.new()
	_crosshair.name = "Crosshair"
	var is_mobile := GameConfig.is_mobile
	if _crosshair.has_method("set_mobile_mode"):
		_crosshair.set_mobile_mode(is_mobile)
	if _crosshair.has_method("set_camera"):
		_crosshair.set_camera(camera)
	# No mobile a mira é desnecessária — a nave serve como referência visual.
	# Em ambos os casos começa oculta; no desktop aparece ao fim da intro.
	_crosshair.visible = false
	cl.add_child(_crosshair)
## Revela a mira (crosshair) ao fim da introdução cinemática.
## No mobile a mira nunca aparece — a nave é a referência de tiro.
func _show_crosshair() -> void:
	if _crosshair:
		var is_mobile := GameConfig.is_mobile
		_crosshair.visible = not is_mobile
