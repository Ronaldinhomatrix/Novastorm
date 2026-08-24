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

## Thread de background para geração de colisão sem bloquear renderização
var _collision_thread: Thread = null
## Dados das faces extraídos na thread principal para processamento na thread de background
var _collision_face_data: Array = []
## Resultados prontos gerados pela thread de background
var _collision_results: Array = []

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
	# Colisão é gerada em thread de background — zero impacto nos primeiros frames
	_start_collision_thread()

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
	# Detectar fim do nível
	if not _level_completed and show_level_complete and path_follower:
		if path_follower.progress >= _path_length - 1.0:
			_on_level_finished()


func _exit_tree() -> void:
	# Garante que a thread seja finalizada ao sair da cena
	if _collision_thread and _collision_thread.is_started():
		_collision_thread.wait_to_finish()
		_collision_thread = null


func _on_level_finished() -> void:
	_level_completed = true
	
	# Aguarda a thread terminar se ainda estiver rodando
	if _collision_thread and _collision_thread.is_started():
		_collision_thread.wait_to_finish()
		_collision_thread = null
	
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
# Geração de Colisão em Thread de Background (zero bloqueio na renderização)
# ---------------------------------------------------------------------------

func _start_collision_thread() -> void:
	## Coleta as faces de cada mesh na thread principal e dispara a thread de
	## background para construir os ConcavePolygonShape3D sem travar o jogo.
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

	_collision_face_data.clear()

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

			# Extrai as faces na thread principal (rápido — apenas copia referência de dados)
			var faces: PackedVector3Array = mesh_instance.mesh.get_faces()
			if faces.size() > 0:
				_collision_face_data.append({
					"mesh_instance": mesh_instance,
					"faces": faces
				})

	if _collision_face_data.is_empty():
		_collision_generated = true
		return

	# Dispara thread de background para construir as collision shapes
	_collision_thread = Thread.new()
	_collision_thread.start(_build_collision_shapes_threaded)


func _build_collision_shapes_threaded() -> void:
	## Executa na thread de background — constroi ConcavePolygonShape3D para cada mesh.
	## O cálculo pesado (BVH de milhões de faces) acontece aqui sem bloquear a renderização.
	var results: Array = []
	for data: Dictionary in _collision_face_data:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(data["faces"])
		results.append({
			"mesh_instance": data["mesh_instance"],
			"shape": shape
		})
	_collision_results = results
	# Agenda a aplicação dos resultados na thread principal
	call_deferred("_apply_collision_results")


func _apply_collision_results() -> void:
	## Executa na thread principal — adiciona os nós de colisão à árvore de cena.
	## Esta operação é instantânea pois as shapes já estão prontas.
	if _collision_thread and _collision_thread.is_started():
		_collision_thread.wait_to_finish()
		_collision_thread = null

	for result: Dictionary in _collision_results:
		var mi: MeshInstance3D = result["mesh_instance"]
		if not is_instance_valid(mi):
			continue
		var body := StaticBody3D.new()
		body.collision_layer = 1 << 3  # layer 4 ("world")
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		col.shape = result["shape"]
		body.add_child(col)
		mi.add_child(body)

	_collision_results.clear()
	_collision_face_data.clear()
	_collision_generated = true
