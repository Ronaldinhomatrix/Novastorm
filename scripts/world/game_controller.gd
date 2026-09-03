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

@export_category("Áudio")
## Volume da música de fundo em dB. 0 = 100%, -6 ≈ 50%, -12 ≈ 25%.
## Ajuste direto no Inspector para regular o volume da trilha do nível.
@export_range(-40.0, 0.0, 0.5) var music_volume_db: float = -9.7

@export_category("Componentes")
@export var path_follower: PathFollower = null
@export var player: Node3D = null
@export var camera: Camera3D = null
@export var player_scene: PackedScene = preload("res://scenes/player.tscn")
@export var mothership: Node3D = null

@export_category("Mothership Animation")
@export var mothership_start_point: int = 22
@export var mothership_end_point: int = 29
@export var mothership_rotation_deg: float = 20.0
## Ponto do Path3D onde fica a origem do som da Mothership.
@export var mothership_sound_point: int = 27
## Pontos do Path3D onde a Mothership dispara seus 2 torpedos de energia.
@export var mothership_fire_point_1: int = 25
@export var mothership_fire_point_2: int = 27
## Volume do som da Mothership em dB (+3.0 dB ≈ +40% de volume).
@export_range(-20.0, 10.0, 0.5) var mothership_sound_volume_db: float = 3.0

@export_category("Comboio Terrestre (SmallBridgeConvoy)")
@export var convoy_node_path: NodePath = "SmallBridgeConvoy"
@export var convoy_move_start_point: int = 16  ## Ponto onde o comboio começa a se mover lentamente
@export var convoy_tank_fire_start_point: int = 17  ## Ponto inicial da janela de disparo dos tanques
@export var convoy_tank_fire_end_point: int = 18    ## Ponto final da janela de disparo dos tanques

@export_category("Intro Cinematica")
@export var enable_cinematic_intro: bool = false
@export var intro_duration: float = 5.0
@export var intro_start_azimuth_deg: float = 135.0  ## Ângulo horizontal inicial em graus (135 = diagonal lateral frontal)
@export var intro_start_elevation_deg: float = -20.0  ## Ângulo vertical inicial em graus (negativo = abaixo da nave)
@export_range(0.05, 1.0) var intro_start_distance_fraction: float = 0.25  ## Distância inicial como fração da distância padrão (0.25 = 25%)

@export_category("Cenario")
@export var enable_cloud_sky: bool = true  ## Gera nuvens estáticas no céu do nível
@export var terrain_detail_material: Material = preload("res://assets/materials/terrain_detailed.tres")
@export var custom_camera_far_pc: float = 4000.0  ## Alcance da câmera no PC em metros (6000m no Nível 1)
@export var custom_camera_far_mobile: float = 3500.0  ## Alcance da câmera no Mobile em metros (5000m no Nível 1)
@export var enable_depth_fog: bool = true  ## Névoa de profundidade automática (sem pop-in)

@export_category("Progressão de Nível")
@export var level_complete_scene: PackedScene = preload("res://scenes/level_complete.tscn")
@export var next_level_path: String = ""  ## Caminho para próximo nível (vazio = não transiciona)
@export var show_level_complete: bool = true  ## Mostrar tela ao terminar o nível

@export_category("Inimigos e Ondas")
@export var wave_manager: WaveManager = null
@export var enable_enemy_waves: bool = true

@export_category("HUD de Combate")
@export var hud_scene: PackedScene = preload("res://scenes/ui/hud.tscn")
@export var hud: CombatHUD = null

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
var _convoy_move_dist: float = 0.0
var _convoy_fire_start_dist: float = 0.0
var _convoy_fire_end_dist: float = 0.0
var _convoy_started_moving: bool = false
var _convoy_node: Node3D = null

# Sistema de tremor de câmera (Screen Shake)
var _shake_time: float = 0.0
var _shake_duration: float = 0.0
var _shake_intensity: float = 0.0

# Reproduz a trilha sonora do nível.
var _music_player: AudioStreamPlayer = null

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
	
	# Player de áudio da Mothership: som 2D simples (+40% volume padrão).
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

	# Calcular comprimento do path e distâncias dos pontos 22 a 29
	var flight_path := get_node_or_null("FlightPath") as Path3D
	if flight_path and flight_path.curve:
		var curve := flight_path.curve
		_path_length = curve.get_baked_length()
		
		# Calcula a distância exata ao longo da curva dos pontos especificados
		var point_count := curve.point_count
		if point_count > 0:
			var clamped_start := clampi(mothership_start_point, 0, point_count - 1)
			var clamped_end := clampi(mothership_end_point, 0, point_count - 1)
			_start_dist = curve.get_closest_offset(curve.get_point_position(clamped_start))
			_end_dist = curve.get_closest_offset(curve.get_point_position(clamped_end))

			# Offsets exatos de disparo dos 2 torpedos da Mothership (pontos 25 e 27)
			var fire_idx_1 := clampi(mothership_fire_point_1, 0, point_count - 1)
			var fire_idx_2 := clampi(mothership_fire_point_2, 0, point_count - 1)
			_fire_dist_1 = curve.get_closest_offset(curve.get_point_position(fire_idx_1))
			_fire_dist_2 = curve.get_closest_offset(curve.get_point_position(fire_idx_2))

			# Offset do ponto de som da Mothership.
			var sound_idx := clampi(mothership_sound_point, 0, point_count - 1)
			_mothership_sound_offset = curve.get_closest_offset(curve.get_point_position(sound_idx))

			# Ponto 6 (pouco antes da Wave 1 no ponto 8) para o alerta cinematográfico único
			var warning_point_idx := clampi(6, 0, point_count - 1)
			_initial_warning_dist = curve.get_closest_offset(curve.get_point_position(warning_point_idx))

			# Offsets do Comboio Terrestre (Movimento no ponto 16, disparos dos tanques entre 17 e 18)
			var c_move_idx := clampi(convoy_move_start_point, 0, point_count - 1)
			var c_fstart_idx := clampi(convoy_tank_fire_start_point, 0, point_count - 1)
			var c_fend_idx := clampi(convoy_tank_fire_end_point, 0, point_count - 1)
			_convoy_move_dist = curve.get_closest_offset(curve.get_point_position(c_move_idx))
			_convoy_fire_start_dist = curve.get_closest_offset(curve.get_point_position(c_fstart_idx))
			_convoy_fire_end_dist = curve.get_closest_offset(curve.get_point_position(c_fend_idx))

	if convoy_node_path != ^"":
		_convoy_node = get_node_or_null(convoy_node_path) as Node3D

	# Configuração gráfica dinâmica: PC Ultra vs Mobile Otimizado
	_apply_platform_graphics_settings()

	if enable_cloud_sky and not get_node_or_null("ProceduralCloudSky"):
		var cloud_sky := ProceduralCloudSky.new()
		cloud_sky.name = "ProceduralCloudSky"
		add_child(cloud_sky)

	# Configura e inicializa o gerenciador de ondas de inimigos (Waves)
	if enable_enemy_waves:
		if not wave_manager:
			wave_manager = get_node_or_null("WaveManager") as WaveManager
		if not wave_manager:
			wave_manager = WaveManager.new()
			wave_manager.name = "WaveManager"
			wave_manager.path_follower = path_follower
			add_child(wave_manager)
		elif not wave_manager.path_follower:
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
	var dev_layer := CanvasLayer.new()
	dev_layer.layer = 50
	add_child(dev_layer)

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

	dev_layer.add_child(dev_btn)


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
	
	# Animação de rotação da Mothership entre os pontos do Path3D
	_update_mothership_rotation()

	# Alerta Cinematográfico único antes da primeira onda de inimigos
	if not _initial_warning_shown and _initial_warning_dist > 0.0 and path_follower:
		if path_follower.progress >= _initial_warning_dist:
			_initial_warning_shown = true
			if hud:
				hud.show_cinematic_warning("WARNING // INCOMING ENEMYS", "RADAR PROXIMITY ALERT // HOSTILE SQUADRONS DETECTED", 3.5)

	# Toca o som da Mothership ao cruzar o ponto definido.
	_trigger_mothership_sound()
	_handle_mothership_firing()

	# Gerencia o movimento lento e a janela de disparos do comboio terrestre
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


func _get_terrain_node() -> Node:
	var node := get_node_or_null("GrandCanyon")
	if node:
		return node
	node = get_node_or_null("Mountains1")
	if node:
		return node
	return get_node_or_null("Terrain")


const TerrainMobileMaterial := preload("res://assets/materials/terrain_detailed_mobile.tres")

func _apply_platform_graphics_settings() -> void:
	var is_mobile := OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	var sun := get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	
	var target_far := custom_camera_far_mobile if is_mobile else custom_camera_far_pc
	if camera:
		camera.far = target_far

	if is_mobile:
		# --- CONFIGURAÇÃO MOBILE (Alta Performance - 60 FPS) ---
		Engine.max_fps = 60
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		get_viewport().scaling_3d_scale = 0.75
		get_viewport().fsr_sharpness = 0.3
		
		# Sol e Sombras no Mobile: sombra focal de 100m focada na nave (leve e ultra nítida)
		if sun:
			sun.directional_shadow_max_distance = 100.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_blend_splits = false
			sun.shadow_blur = 1.0
		
		# Terreno no Mobile: material leve sem triplanar e sem projeção de sombras no cenário
		_apply_scenery_materials_and_shadows(TerrainMobileMaterial, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	else:
		# --- CONFIGURAÇÃO PC / DESKTOP (Ultra Visuals - 144Hz+) ---
		Engine.max_fps = 0
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = 1.0
		
		# Sol e Sombras no PC: 800m de alcance, 4 divisões ultra suaves
		if sun:
			sun.directional_shadow_max_distance = 800.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_blend_splits = true
			sun.shadow_blur = 1.8
			sun.directional_shadow_split_1 = 0.05
			sun.directional_shadow_split_2 = 0.15
			sun.directional_shadow_split_3 = 0.35
		
		# Terreno no PC: material ultra detalhado com Triplanar e sombras ativas
		_apply_scenery_materials_and_shadows(terrain_detail_material, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)

	# Aplica a névoa suave de profundidade automática e perfil de Glow / SSAO / SSIL no WorldEnvironment
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		if enable_depth_fog:
			CameraConfig.apply_depth_fog(world_env.environment, target_far)
		# No Mobile: desativa pós-processamento pesado para economizar bateria e garantir 60 FPS
		# No PC: ativa Glow, SSAO e SSIL com máxima fidelidade
		world_env.environment.glow_enabled = not is_mobile
		world_env.environment.ssao_enabled = not is_mobile
		if not is_mobile:
			world_env.environment.ssao_radius = 2.0
			world_env.environment.ssao_intensity = 2.2
			world_env.environment.ssao_power = 1.5
			world_env.environment.ssao_detail = 0.5
			world_env.environment.ssao_horizon = 0.06
		world_env.environment.ssil_enabled = not is_mobile
		if not is_mobile:
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
			for child in sc_node.find_children("*", "MeshInstance3D", true, false):
				var mi := child as MeshInstance3D
				if mi:
					mi.cast_shadow = shadow_setting


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

	# 3. Reinicia o progresso para garantir início no ponto zero exato
	if path_follower:
		path_follower.reset_progress()

	# 4. Despausa o jogo / inicia a introdução cinematográfica
	if intro:
		intro.enabled = true
		intro.start()
		# A mira só aparece quando a intro terminar.
		if _crosshair and intro.has_signal("intro_completed"):
			# Conecta apenas uma vez para evitar leaks.
			if not intro.intro_completed.is_connected(_show_crosshair):
				intro.intro_completed.connect(_show_crosshair)
	else:
		if path_follower:
			path_follower.set_paused(false)
		if player and player.has_method("set_controls_enabled"):
			player.set_controls_enabled(true)
		# Sem intro → oculta o cursor imediatamente durante gameplay no PC
		var is_mobile := OS.has_feature("android") or OS.has_feature("ios")
		if not is_mobile:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		if _crosshair:
			_crosshair.visible = true

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
	if _music_player or MUSIC_LEVEL_1 == null:
		return
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = MUSIC_LEVEL_1
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


## Toca o som da Mothership uma única vez quando o progresso cruza o ponto
## definido (mothership_sound_point, padrão = 32).
func _trigger_mothership_sound() -> void:
	if _mothership_sound_player == null or _mothership_sound_played or not path_follower:
		return

	if _mothership_sound_offset <= 0.0:
		var flight_path := get_node_or_null("FlightPath") as Path3D
		if flight_path and flight_path.curve and flight_path.curve.point_count > 0:
			var sound_idx := clampi(mothership_sound_point, 0, flight_path.curve.point_count - 1)
			_mothership_sound_offset = flight_path.curve.get_closest_offset(flight_path.curve.get_point_position(sound_idx))

	if _mothership_sound_offset > 0.0 and path_follower.progress >= _mothership_sound_offset:
		_mothership_sound_player.play()
		_mothership_sound_played = true


# ---------------------------------------------------------------------------
# Comboio Terrestre (SmallBridgeConvoy)
# ---------------------------------------------------------------------------

## Controla a ativação de movimento lento do comboio no ponto 16
## e a janela restrita de tiro dos tanques (entre os pontos 17 e 18).
func _handle_convoy_logic() -> void:
	if not path_follower:
		return

	if not _convoy_node:
		_convoy_node = get_node_or_null(convoy_node_path) as Node3D
		if not _convoy_node:
			return

	var current_prog: float = path_follower.progress

	# 1. Ativa movimentação lenta (active_move = true) ao atingir o ponto 16
	if not _convoy_started_moving and _convoy_move_dist > 0.0:
		if current_prog >= _convoy_move_dist:
			_convoy_started_moving = true
			for child in _convoy_node.get_children():
				if "active_move" in child:
					child.active_move = true

	# 2. Controla a permissão de disparo dos tanques (can_shoot = true apenas entre ponto 17 e 18)
	if _convoy_fire_start_dist > 0.0 and _convoy_fire_end_dist > _convoy_fire_start_dist:
		var in_firing_window := (current_prog >= _convoy_fire_start_dist and current_prog <= _convoy_fire_end_dist)
		for child in _convoy_node.get_children():
			if child is EnemyTank or "can_shoot" in child:
				child.can_shoot = in_firing_window


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
	var is_mobile := OS.has_feature("android") or OS.has_feature("ios")
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
		var is_mobile := OS.has_feature("android") or OS.has_feature("ios")
		_crosshair.visible = not is_mobile
