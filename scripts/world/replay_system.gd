class_name ReplaySystem
extends Node

## Sistema de gravação e gerenciamento de Replay 3D.
## Grava automaticamente o estado da partida a cada frame (60Hz) em buffer circular de 3 minutos.
## Pressione F4 a qualquer momento para abrir o Replay 3D interativo com Câmera Livre e Linha do Tempo.

const MAX_RECORD_SECONDS: float = 180.0
const TARGET_FPS: float = 60.0
const MAX_FRAMES: int = int(MAX_RECORD_SECONDS * TARGET_FPS)

var _recorded_frames: Array[Dictionary] = []
var _is_recording: bool = true
var _replay_active: bool = false
var _replay_viewer: ReplayViewer = null
var _game_elapsed_time: float = 0.0

var _game_controller: GameController = null
var _player_node: Node3D = null
var _camera_node: Camera3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_find_references()


func _find_references() -> void:
	_game_controller = get_parent() as GameController
	if not _game_controller and get_tree() and get_tree().current_scene:
		_game_controller = get_tree().current_scene as GameController


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F4:
			toggle_replay()


func _physics_process(delta: float) -> void:
	if not _is_recording or _replay_active:
		return

	_game_elapsed_time += delta
	_record_current_frame()


func _record_current_frame() -> void:
	# Busca referências caso ainda não estejam prontas
	if not _player_node or not is_instance_valid(_player_node):
		_player_node = get_tree().get_first_node_in_group("player") as Node3D
		if not _player_node:
			_player_node = get_node_or_null("/root/Game/FlightPath/PathFollower/Player")

	if not _camera_node or not is_instance_valid(_camera_node):
		var vp := get_viewport()
		if vp:
			_camera_node = vp.get_camera_3d()

	var frame: Dictionary = {}
	frame["time"] = _game_elapsed_time

	# Câmera
	if _camera_node and is_instance_valid(_camera_node):
		frame["camera_transform"] = _camera_node.global_transform
		frame["camera_pos"] = _camera_node.global_position
		frame["camera_yaw"] = _camera_node.global_rotation.y
		frame["camera_pitch"] = _camera_node.global_rotation.x

	# Player
	if _player_node and is_instance_valid(_player_node):
		frame["player_transform"] = _player_node.global_transform
		frame["player_visible"] = _player_node.is_visible_in_tree()

	# Inimigos
	var enemies_data: Array[Dictionary] = []
	var enemies := get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if is_instance_valid(e) and e is Node3D and not e.is_queued_for_deletion():
			var e_node: Node3D = e as Node3D
			var e_dict: Dictionary = {
				"id": e_node.get_instance_id(),
				"name": e_node.name,
				"transform": e_node.global_transform,
				"type": e_node.get_script().get_global_name() if e_node.get_script() else e_node.name
			}
			
			# Hitbox size
			if e_node is EnemyScout or e_node.name.contains("Scout"):
				e_dict["hitbox_size"] = Vector3(21, 9, 18)
			elif e_node is EnemyFighter or e_node.name.contains("Fighter"):
				e_dict["hitbox_size"] = Vector3(27, 11, 21)
			elif e_node is EnemyHeavy or e_node.name.contains("Heavy"):
				e_dict["hitbox_size"] = Vector3(39, 15, 30)
			elif e_node.name.contains("Bomber"):
				e_dict["hitbox_size"] = Vector3(34, 10, 22)
			else:
				e_dict["hitbox_size"] = Vector3(15, 8, 15)

			enemies_data.append(e_dict)

	frame["enemies"] = enemies_data

	# Balas / Projéteis
	var bullets_data: Array[Dictionary] = []
	var p_bullets := get_tree().get_nodes_in_group("player_bullets")
	for b in p_bullets:
		if is_instance_valid(b) and b is Node3D and not b.is_queued_for_deletion():
			bullets_data.append({
				"id": (b as Node3D).get_instance_id(),
				"transform": (b as Node3D).global_transform,
				"is_enemy": false
			})

	var e_bullets := get_tree().get_nodes_in_group("enemy_bullets")
	for b in e_bullets:
		if is_instance_valid(b) and b is Node3D and not b.is_queued_for_deletion():
			bullets_data.append({
				"id": (b as Node3D).get_instance_id(),
				"transform": (b as Node3D).global_transform,
				"is_enemy": true
			})

	frame["bullets"] = bullets_data

	# Adiciona frame ao buffer
	_recorded_frames.append(frame)
	if _recorded_frames.size() > MAX_FRAMES:
		_recorded_frames.pop_front()


var _hidden_nodes: Array[Node3D] = []


func toggle_replay() -> void:
	if _replay_active:
		close_replay()
	else:
		open_replay()


func open_replay() -> void:
	if _replay_active or _recorded_frames.is_empty():
		return

	_replay_active = true
	_is_recording = false

	# Pausa a árvore do jogo para congelar tudo
	get_tree().paused = true

	# Oculta entidades reais vivas para que não sobreponham os clones do replay
	_hide_live_entities()

	# Instancia o visualizador de replay
	_replay_viewer = ReplayViewer.new()
	_replay_viewer.name = "ReplayViewerInstance"
	_replay_viewer.frames = _recorded_frames.duplicate()
	_replay_viewer.replay_closed.connect(_on_replay_viewer_closed)

	get_tree().current_scene.add_child(_replay_viewer)


func close_replay() -> void:
	if not _replay_active:
		return

	if _replay_viewer and is_instance_valid(_replay_viewer):
		_replay_viewer.queue_free()
		_replay_viewer = null

	_restore_live_entities()

	_replay_active = false
	_is_recording = true
	get_tree().paused = false


func _hide_live_entities() -> void:
	_hidden_nodes.clear()
	
	if _player_node and is_instance_valid(_player_node) and _player_node.visible:
		_player_node.visible = false
		_hidden_nodes.append(_player_node)

	var enemies := get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if is_instance_valid(e) and e is Node3D and (e as Node3D).visible:
			(e as Node3D).visible = false
			_hidden_nodes.append(e as Node3D)

	var p_bullets := get_tree().get_nodes_in_group("player_bullets")
	for b in p_bullets:
		if is_instance_valid(b) and b is Node3D and (b as Node3D).visible:
			(b as Node3D).visible = false
			_hidden_nodes.append(b as Node3D)

	var e_bullets := get_tree().get_nodes_in_group("enemy_bullets")
	for b in e_bullets:
		if is_instance_valid(b) and b is Node3D and (b as Node3D).visible:
			(b as Node3D).visible = false
			_hidden_nodes.append(b as Node3D)


func _restore_live_entities() -> void:
	for node in _hidden_nodes:
		if is_instance_valid(node):
			node.visible = true
	_hidden_nodes.clear()


func _on_replay_viewer_closed() -> void:
	close_replay()
