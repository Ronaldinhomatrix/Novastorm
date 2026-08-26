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
const MUSIC_LEVEL_1 := preload("res://assets/audio/music_1_Aphelion.mp3")

# Som da nave mãe (Mothership) - efeito posicional tocado ao se aproximar dela.
const MOTHERSHIP_SOUND := preload("res://assets/audio/mothership1.ogg")

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

@export_category("Intro Cinematica")
@export var enable_cinematic_intro: bool = false
@export var intro_duration: float = 5.0
@export var intro_start_azimuth_deg: float = 135.0  ## Ângulo horizontal inicial em graus (135 = diagonal lateral frontal)
@export var intro_start_elevation_deg: float = -20.0  ## Ângulo vertical inicial em graus (negativo = abaixo da nave)
@export_range(0.05, 1.0) var intro_start_distance_fraction: float = 0.25  ## Distância inicial como fração da distância padrão (0.25 = 25%)

@export_category("Cenario")
@export var enable_cloud_sky: bool = true  ## Gera nuvens estáticas no céu do nível
@export var terrain_detail_material: Material = preload("res://assets/materials/terrain_detailed.tres")

@export_category("Progressão de Nível")
@export var level_complete_scene: PackedScene = preload("res://scenes/level_complete.tscn")
@export var next_level_path: String = ""  ## Caminho para próximo nível (vazio = não transiciona)
@export var show_level_complete: bool = true  ## Mostrar tela ao terminar o nível

# ---------------------------------------------------------------------------
# Estado Interno
# ---------------------------------------------------------------------------

var _collision_generated: bool = false
var _level_completed: bool = false
var _path_length: float = 0.0

var _intro_active: bool = false
var _intro_timer: float = 0.0
var _default_camera_pos: Vector3 = Vector3(-0.0112, 0.0, 18.0)
var _default_camera_rot: Vector3 = Vector3.ZERO

# Parâmetros de distância para a rotação da Mothership
var _start_dist: float = 0.0
var _end_dist: float = 0.0
var _initial_mothership_rot_y: float = 0.0

# Player de áudio posicional ancorado na Mothership.
var _mothership_sound_player: AudioStreamPlayer3D = null

# Reproduz a trilha sonora do nível.
var _music_player: AudioStreamPlayer = null

# ---------------------------------------------------------------------------
# Ciclo de Vida
# ---------------------------------------------------------------------------

func _ready() -> void:
	_start_background_music()

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

	# Configura o ouvinte de áudio 3D na câmera e o som da Mothership.
	_setup_audio_listener()
	_setup_mothership_sound()

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

	# Configuração gráfica dinâmica: PC Ultra vs Mobile Otimizado
	_apply_platform_graphics_settings()

	if enable_cloud_sky and not get_node_or_null("ProceduralCloudSky"):
		var cloud_sky := ProceduralCloudSky.new()
		cloud_sky.name = "ProceduralCloudSky"
		add_child(cloud_sky)

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

	# Dispara o pré-carregamento e aquecimento de shaders/colisões
	_run_preload_and_warmup(canvas_layer, curtain, intro)


func _process(_delta: float) -> void:
	# Detectar fim do nível (baseado em ratio >= 0.99 ou progresso a menos de 5 unidades do fim)
	if not _level_completed and show_level_complete and path_follower:
		if path_follower.progress_ratio >= 0.99 or path_follower.progress >= _path_length - 5.0:
			_on_level_finished()
	
	# Animação de rotação da Mothership entre os pontos do Path3D
	_update_mothership_rotation()

	# Aciona/para o som da Mothership conforme a proximidade do jogador
	_update_mothership_sound()


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
	
	if is_mobile:
		# --- CONFIGURAÇÃO MOBILE (Alta Performance - 60 FPS) ---
		Engine.max_fps = 60
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		get_viewport().scaling_3d_scale = 0.75
		get_viewport().fsr_sharpness = 0.3
		
		# Câmera no Mobile: alcance amplo até o horizonte (3500m)
		if camera:
			camera.far = 3500.0
		
		# Sol e Sombras no Mobile: sombra focal de 100m focada na nave (leve e ultra nítida)
		if sun:
			sun.directional_shadow_max_distance = 100.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_blend_splits = false
		
		# Terreno no Mobile: material leve sem triplanar e sem projeção de sombras no cenário
		_apply_scenery_materials_and_shadows(TerrainMobileMaterial, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	else:
		# --- CONFIGURAÇÃO PC / DESKTOP (Ultra Visuals - 144Hz+) ---
		Engine.max_fps = 0
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = 1.0
		
		# Câmera: alcance total até o horizonte (4000m)
		if camera:
			camera.far = 4000.0
		
		# Sol e Sombras no PC: 800m de alcance, 4 divisões ultra suaves
		if sun:
			sun.directional_shadow_max_distance = 800.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_blend_splits = true
		
		# Terreno no PC: material ultra detalhado com Triplanar e sombras ativas
		_apply_scenery_materials_and_shadows(terrain_detail_material, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


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
	var static_scenery := ["HighBridge", "SmallBridge", "Castle", "Mothership"]
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
	else:
		if path_follower:
			path_follower.set_paused(false)
		if player and player.has_method("set_controls_enabled"):
			player.set_controls_enabled(true)

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
	_music_player.volume_db = -12.0  # Música um pouco abaixo dos efeitos sonoros
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)
	_music_player.play()


func _on_music_finished() -> void:
	# Faz a música tocar em loop contínuo durante o nível.
	if _music_player:
		_music_player.play()


# ---------------------------------------------------------------------------
# Áudio 3D (Ouvinte + Nave Mãe)
# ---------------------------------------------------------------------------

## Garante que a câmera tenha um AudioListener3D (o "ouvido" do jogo).
## Sem ele, o áudio posicional 3D não tem ponto de escuta e não atenua por
## distância — essencial para que o som da Mothership se comporte.
func _setup_audio_listener() -> void:
	if not camera:
		return
	if camera.get_node_or_null("AudioListener3D") == null:
		var listener := AudioListener3D.new()
		listener.name = "AudioListener3D"
		camera.add_child(listener)


## Cria o player de áudio posicional ancorado na Mothership.
## O som toca em loop enquanto a nave do jogador estiver perto dela e a
## distância é calculada automaticamente pelo motor (com atenuação por unit_size).
func _setup_mothership_sound() -> void:
	if _mothership_sound_player or not mothership or MOTHERSHIP_SOUND == null:
		return
	_mothership_sound_player = AudioStreamPlayer3D.new()
	_mothership_sound_player.name = "MothershipSound"
	_mothership_sound_player.stream = MOTHERSHIP_SOUND
	if _mothership_sound_player.stream and "loop" in _mothership_sound_player.stream:
		_mothership_sound_player.stream.loop = true
	_mothership_sound_player.bus = "Master"
	# Modelo logarítmico: no afastamento o volume decai bem mais devagar que
	# o padrão (INVERSE_DISTANCE), evitando que o som "suma" cedo demais.
	_mothership_sound_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
	_mothership_sound_player.unit_size = 900.0   # Volume pleno até ~900 unid.
	_mothership_sound_player.max_distance = 5200.0  # Borda real de audibilidade (fade até aqui)
	_mothership_sound_player.volume_db = 0.0
	mothership.add_child(_mothership_sound_player)
	# Começa silencioso; só dispara quando o jogador se aproxima.
	_mothership_sound_player.playing = false


## Liga/desliga a reprodução conforme a distância do jogador à Mothership.
## Combina o gatilho (play/stop por proximidade) com a atenuação automática
## por distância que o AudioStreamPlayer3D já aplica.
func _update_mothership_sound() -> void:
	if _mothership_sound_player == null or not mothership:
		return

	# Ponto de escuta: usa a nave do jogador se disponível, senão a câmera.
	var listener_pos := _mothership_listener_pos()

	var dist := listener_pos.distance_to(mothership.global_position)
	var activation_radius := 3600.0  # A partir de qual distância começa a tocar (aproximação)
	# No afastamento, só para na borda real do fade (max_distance) para não
	# cortar o som antes do esperado (histérese: evita liga/desliga perto da borda).
	var stop_radius := _mothership_sound_player.max_distance

	if dist <= activation_radius and not _mothership_sound_player.playing:
		_mothership_sound_player.play()
	elif dist > stop_radius and _mothership_sound_player.playing:
		_mothership_sound_player.stop()


func _mothership_listener_pos() -> Vector3:
	# Prefere a posição do jogador (a nave que percorre o caminho).
	var ref: Node3D = player if player else camera
	if ref:
		return ref.global_position
	return mothership.global_position if mothership else Vector3.ZERO
