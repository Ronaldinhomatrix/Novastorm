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
var _default_camera_pos: Vector3 = Vector3(-0.0112, 0.0, 33.85669)
var _default_camera_rot: Vector3 = Vector3.ZERO

# Parâmetros de distância para a rotação da Mothership
var _start_dist: float = 0.0
var _end_dist: float = 0.0
var _initial_mothership_rot_y: float = 0.0

# ---------------------------------------------------------------------------
# Ciclo de Vida
# ---------------------------------------------------------------------------

func _ready() -> void:
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

	_apply_terrain_detail_material()

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
	# Detectar fim do nível
	if not _level_completed and show_level_complete and path_follower:
		if path_follower.progress >= _path_length - 1.0:
			_on_level_finished()
	
	# Animação de rotação da Mothership entre os pontos do Path3D
	_update_mothership_rotation()


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
	
	# Pausar o movimento
	if path_follower:
		path_follower.set_paused(true)
	
	# Mostrar tela de level complete
	if level_complete_scene and next_level_path != "":
		var ui := level_complete_scene.instantiate() as LevelComplete
		if ui:
			add_child(ui)
			ui.next_level_path = next_level_path


func _get_terrain_node() -> Node:
	var node := get_node_or_null("GrandCanyon")
	if node:
		return node
	node = get_node_or_null("Mountains1")
	if node:
		return node
	return get_node_or_null("Terrain")


func _apply_terrain_detail_material() -> void:
	if terrain_detail_material == null:
		return
	var mountains := _get_terrain_node()
	if not mountains:
		return
	var stack: Array = [mountains]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			(node as MeshInstance3D).material_override = terrain_detail_material
		for child in node.get_children():
			stack.append(child)


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
