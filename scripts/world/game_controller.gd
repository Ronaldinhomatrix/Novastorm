class_name GameController
extends Node3D

## Controlador central do jogo.
## Gerencia HUD, pontuação e referências aos componentes principais.
## O movimento ao longo do Path3D é controlado por PathFollower.
## Detecta fim do nível e exibe tela de LEVEL COMPLETE.

# ---------------------------------------------------------------------------
# Exportações e Configurações
# ---------------------------------------------------------------------------

@export_category("Componentes")
@export var path_follower: PathFollower = null
@export var player: Node3D = null
@export var camera: Camera3D = null
@export var player_scene: PackedScene = preload("res://scenes/player.tscn")

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

## Fila de MeshInstance3D aguardando geração de colisão (processado 1 por frame)
var _collision_queue: Array[MeshInstance3D] = []
## Delay em frames antes de iniciar a geração (permite primeiros frames renderizarem limpos)
var _collision_delay_frames: int = 10

# ---------------------------------------------------------------------------
# Ciclo de Vida
# ---------------------------------------------------------------------------

func _ready() -> void:
	if not path_follower:
		path_follower = get_node_or_null("FlightPath/PathFollower") as PathFollower
	
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

	# Calcular comprimento do path
	var flight_path := get_node_or_null("FlightPath") as Path3D
	if flight_path and flight_path.curve:
		_path_length = flight_path.curve.get_baked_length()

	_apply_terrain_detail_material()
	# Colisão é adiada — enfileira meshes e processa gradualmente no _process()
	_enqueue_world_collision()

	if enable_cloud_sky and not get_node_or_null("ProceduralCloudSky"):
		var cloud_sky := ProceduralCloudSky.new()
		cloud_sky.name = "ProceduralCloudSky"
		add_child(cloud_sky)

	if enable_cinematic_intro:
		var intro := CinematicIntro.new()
		intro.path_follower = path_follower
		intro.player = player
		intro.camera = camera
		intro.duration = intro_duration
		intro.start_azimuth_deg = intro_start_azimuth_deg
		intro.start_elevation_deg = intro_start_elevation_deg
		intro.start_distance_fraction = intro_start_distance_fraction
		add_child(intro)


func _process(_delta: float) -> void:
	# Geração incremental de colisão: 1 mesh por frame após delay inicial
	if _collision_delay_frames > 0:
		_collision_delay_frames -= 1
	elif _collision_queue.size() > 0:
		_process_one_collision()

	# Detectar fim do nível
	if not _level_completed and show_level_complete and path_follower:
		if path_follower.progress >= _path_length - 1.0:
			_on_level_finished()


func _on_level_finished() -> void:
	_level_completed = true
	
	# Finalizar qualquer colisão pendente imediatamente
	while _collision_queue.size() > 0:
		_process_one_collision()
	
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
	# O terreno é uma instância GLTF; aplica o material de detalhe em runtime
	# em todos os MeshInstance3D aninhados, pois o override não persiste no .tscn.
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
# Geração Incremental de Colisão (sem bloquear a thread principal)
# ---------------------------------------------------------------------------

func _enqueue_world_collision() -> void:
	## Coleta todos os MeshInstance3D que precisam de colisão e enfileira para processamento gradual.
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

			# Se já possui colisão pré-salva no modelo, apenas valida a camada
			var existing_body := mesh_instance.get_node_or_null("StaticBody3D") as StaticBody3D
			if existing_body:
				existing_body.collision_layer = 1 << 3  # layer 4 ("world")
				existing_body.collision_mask = 0
				continue

			# Enfileira para processamento gradual
			_collision_queue.append(mesh_instance)


func _process_one_collision() -> void:
	## Processa exatamente 1 MeshInstance3D da fila de colisão por frame.
	if _collision_queue.is_empty():
		_collision_generated = true
		return

	var mesh_instance: MeshInstance3D = _collision_queue.pop_front()
	if not is_instance_valid(mesh_instance) or not mesh_instance.mesh:
		return

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

	if _collision_queue.is_empty():
		_collision_generated = true
