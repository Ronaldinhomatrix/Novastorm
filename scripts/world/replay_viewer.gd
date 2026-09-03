class_name ReplayViewer
extends Node3D

## Visualizador e reprodutor 3D de replays gravados.
## Permite pausar, avançar/rebobinar na linha do tempo, voar livremente com uma câmera 3D
## e inspecionar os disparos e as caixas de colisão (hitboxes) dos inimigos de qualquer ângulo.

signal replay_closed

var frames: Array = []
var current_frame_index: int = 0
var is_playing: bool = false
var playback_speed: float = 1.0
var show_hitboxes: bool = true
var is_freecam: bool = true

# Nós internos
var _replay_cam: Camera3D = null
var _entities_container: Node3D = null
var _ui_canvas: CanvasLayer = null

# UI
var _slider: HSlider = null
var _time_label: Label = null
var _play_btn: Button = null
var _cam_mode_label: Button = null
var _hitbox_btn: Button = null

# FreeCam state
var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.0
var _rmb_held: bool = false
var _cam_speed: float = 60.0

# Assets pré-carregados para visualização
const ENEMY_GLB := preload("res://assets/models/Enemys/3_enemy_red_starships.glb")
const BOMBER_GLB := preload("res://assets/models/levels/enemy_bomber.glb")
const PLAYER_GLTF := preload("res://assets/models/Player_ship_1/scene.gltf")

# Materiais
var _player_laser_mat: StandardMaterial3D = null
var _enemy_laser_mat: StandardMaterial3D = null
var _hitbox_mat: StandardMaterial3D = null

# Cache de nós visuais
var _vis_player: Node3D = null
var _vis_enemies: Dictionary = {}  # enemy_id -> Node3D
var _vis_bullets: Dictionary = {}  # bullet_id -> MeshInstance3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_materials()
	_setup_scene()
	_setup_ui()

	if frames.size() > 0:
		current_frame_index = 0
		_slider.max_value = maxf(float(frames.size() - 1), 1.0)
		_slider.value = 0
		_render_frame(0)
		_init_freecam_position()


func _setup_materials() -> void:
	_player_laser_mat = StandardMaterial3D.new()
	_player_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_player_laser_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_player_laser_mat.albedo_color = Color(0.2, 1.0, 1.0, 1.0)

	_enemy_laser_mat = StandardMaterial3D.new()
	_enemy_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_enemy_laser_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_enemy_laser_mat.albedo_color = Color(1.0, 0.2, 0.1, 1.0)

	_hitbox_mat = StandardMaterial3D.new()
	_hitbox_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hitbox_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hitbox_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hitbox_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	_hitbox_mat.albedo_color = Color(1.0, 0.9, 0.1, 0.28)


func _setup_scene() -> void:
	_entities_container = Node3D.new()
	_entities_container.name = "ReplayEntities"
	add_child(_entities_container)

	_replay_cam = Camera3D.new()
	_replay_cam.name = "ReplayCamera3D"
	_replay_cam.current = true
	_replay_cam.fov = 65.0
	_replay_cam.far = 4000.0
	add_child(_replay_cam)


func _init_freecam_position() -> void:
	if frames.is_empty():
		return
	var f: Dictionary = frames[0]
	if f.has("camera_pos"):
		_replay_cam.global_position = f["camera_pos"] + Vector3(0, 4, 3)
		_cam_yaw = f.get("camera_yaw", 0.0)
		_cam_pitch = f.get("camera_pitch", -0.05)
		_update_camera_rotation()


func _setup_ui() -> void:
	_ui_canvas = CanvasLayer.new()
	_ui_canvas.name = "ReplayHUD"
	_ui_canvas.layer = 125
	add_child(_ui_canvas)

	# --- PAINEL SUPERIOR ---
	var top_panel := PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.offset_left = 16.0
	top_panel.offset_top = 12.0
	top_panel.offset_right = -16.0
	top_panel.offset_bottom = 58.0

	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.03, 0.05, 0.09, 0.88)
	top_style.border_color = Color(0.0, 0.8, 1.0, 0.7)
	top_style.border_width_bottom = 2
	top_style.corner_radius_top_left = 6
	top_style.corner_radius_top_right = 6
	top_style.corner_radius_bottom_left = 6
	top_style.corner_radius_bottom_right = 6
	top_style.content_margin_left = 14.0
	top_style.content_margin_right = 14.0
	top_panel.add_theme_stylebox_override("panel", top_style)
	_ui_canvas.add_child(top_panel)

	var top_hbox := HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_hbox.add_theme_constant_override("separation", 24)
	top_panel.add_child(top_hbox)

	var title := Label.new()
	title.text = "🎥 REPLAY 3D"
	title.add_theme_color_override("font_color", Color(0.0, 1.0, 0.9))
	title.add_theme_font_size_override("font_size", 15)
	top_hbox.add_child(title)

	var hints := Label.new()
	hints.text = "[ESPAÇO]: Play/Pause | [◀ / ▶]: Frame a Frame | [C]: Câmera | [H]: Hitboxes | Botão Dir. Mouse + WASD: Voo Livre"
	hints.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	hints.add_theme_font_size_override("font_size", 12)
	top_hbox.add_child(hints)

	var btn_exit := Button.new()
	btn_exit.text = "✕ Voltar ao Jogo (F4)"
	btn_exit.pressed.connect(_on_close_replay)
	top_hbox.add_child(btn_exit)

	# --- PAINEL INFERIOR ---
	var bot_panel := PanelContainer.new()
	bot_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot_panel.offset_left = 20.0
	bot_panel.offset_top = -120.0
	bot_panel.offset_right = -20.0
	bot_panel.offset_bottom = -25.0

	var bot_style := StyleBoxFlat.new()
	bot_style.bg_color = Color(0.03, 0.05, 0.09, 0.92)
	bot_style.border_color = Color(0.0, 0.8, 1.0, 0.7)
	bot_style.border_width_top = 2
	bot_style.border_width_left = 1
	bot_style.border_width_right = 1
	bot_style.border_width_bottom = 1
	bot_style.corner_radius_top_left = 8
	bot_style.corner_radius_top_right = 8
	bot_style.corner_radius_bottom_left = 8
	bot_style.corner_radius_bottom_right = 8
	bot_style.content_margin_left = 16.0
	bot_style.content_margin_right = 16.0
	bot_style.content_margin_top = 10.0
	bot_style.content_margin_bottom = 10.0
	bot_panel.add_theme_stylebox_override("panel", bot_style)
	_ui_canvas.add_child(bot_panel)

	var bot_vbox := VBoxContainer.new()
	bot_vbox.add_theme_constant_override("separation", 8)
	bot_panel.add_child(bot_vbox)

	# Slider da linha do tempo
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = maxf(float(frames.size() - 1), 1.0)
	_slider.step = 1.0
	_slider.value_changed.connect(_on_slider_value_changed)
	bot_vbox.add_child(_slider)

	var bot_controls := HBoxContainer.new()
	bot_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_controls.add_theme_constant_override("separation", 14)
	bot_vbox.add_child(bot_controls)

	var btn_step_back := Button.new()
	btn_step_back.text = "◀ Quadro"
	btn_step_back.pressed.connect(func(): _step_frame(-1))
	bot_controls.add_child(btn_step_back)

	_play_btn = Button.new()
	_play_btn.text = "▶ Reproduzir"
	_play_btn.pressed.connect(_toggle_playback)
	bot_controls.add_child(_play_btn)

	var btn_step_fwd := Button.new()
	btn_step_fwd.text = "Quadro ▶"
	btn_step_fwd.pressed.connect(func(): _step_frame(1))
	bot_controls.add_child(btn_step_fwd)

	_time_label = Label.new()
	_time_label.text = "Quadro: 0 / 0 | Tempo: 0.0s"
	_time_label.add_theme_font_size_override("font_size", 12)
	bot_controls.add_child(_time_label)

	# Velocidades
	var spd_menu := MenuButton.new()
	spd_menu.text = "Velocidade: 1.0x"
	var popup := spd_menu.get_popup()
	popup.add_item("0.05x (Super Slow)", 0)
	popup.add_item("0.25x (Lento)", 1)
	popup.add_item("0.5x (Meia Vel.)", 2)
	popup.add_item("1.0x (Normal)", 3)
	popup.add_item("2.0x (Rápido)", 4)
	popup.id_pressed.connect(func(id: int):
		match id:
			0: playback_speed = 0.05
			1: playback_speed = 0.25
			2: playback_speed = 0.5
			3: playback_speed = 1.0
			4: playback_speed = 2.0
		spd_menu.text = "Velocidade: %.2fx" % playback_speed
	)
	bot_controls.add_child(spd_menu)

	# Botão Câmera
	var btn_cam := Button.new()
	btn_cam.text = "📷 Câmera: Livre (C)"
	btn_cam.pressed.connect(_toggle_camera_mode)
	bot_controls.add_child(btn_cam)
	_cam_mode_label = btn_cam

	# Botão Hitboxes
	_hitbox_btn = Button.new()
	_hitbox_btn.text = "📦 Hitboxes 3D: LIGADAS (H)"
	_hitbox_btn.pressed.connect(_toggle_hitboxes)
	bot_controls.add_child(_hitbox_btn)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F4, KEY_ESCAPE:
				_on_close_replay()
			KEY_SPACE:
				_toggle_playback()
			KEY_LEFT:
				_step_frame(-1)
			KEY_RIGHT:
				_step_frame(1)
			KEY_C:
				_toggle_camera_mode()
			KEY_H:
				_toggle_hitboxes()

	# FreeCam mouse rotation
	if is_freecam:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_rmb_held = event.pressed
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _rmb_held else Input.MOUSE_MODE_VISIBLE
		elif event is InputEventMouseMotion and _rmb_held:
			_cam_yaw -= event.relative.x * 0.003
			_cam_pitch = clampf(_cam_pitch - event.relative.y * 0.003, -1.4, 1.4)
			_update_camera_rotation()


func _update_camera_rotation() -> void:
	_replay_cam.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)


func _process(delta: float) -> void:
	if is_freecam:
		_process_freecam_move(delta)

	if is_playing and frames.size() > 0:
		var frame_advance: float = 60.0 * playback_speed * delta
		var next_idx: int = current_frame_index + int(round(frame_advance))
		if next_idx >= frames.size():
			current_frame_index = frames.size() - 1
			is_playing = false
			_update_play_button_text()
		else:
			current_frame_index = next_idx
		_slider.value = current_frame_index
		_render_frame(current_frame_index)


func _process_freecam_move(delta: float) -> void:
	var move_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move_dir -= _replay_cam.global_basis.z
	if Input.is_key_pressed(KEY_S):
		move_dir += _replay_cam.global_basis.z
	if Input.is_key_pressed(KEY_A):
		move_dir -= _replay_cam.global_basis.x
	if Input.is_key_pressed(KEY_D):
		move_dir += _replay_cam.global_basis.x
	if Input.is_key_pressed(KEY_E):
		move_dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move_dir -= Vector3.UP

	if move_dir.length_squared() > 0.0001:
		var speed := _cam_speed * (2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		_replay_cam.global_position += move_dir.normalized() * speed * delta


func _toggle_playback() -> void:
	is_playing = not is_playing
	_update_play_button_text()


func _update_play_button_text() -> void:
	if _play_btn:
		_play_btn.text = "⏸ Pausar" if is_playing else "▶ Reproduzir"


func _step_frame(direction: int) -> void:
	is_playing = false
	_update_play_button_text()
	current_frame_index = clampi(current_frame_index + direction, 0, frames.size() - 1)
	_slider.value = current_frame_index
	_render_frame(current_frame_index)


func _on_slider_value_changed(val: float) -> void:
	current_frame_index = clampi(int(val), 0, frames.size() - 1)
	_render_frame(current_frame_index)


func _toggle_camera_mode() -> void:
	is_freecam = not is_freecam
	if _cam_mode_label:
		_cam_mode_label.text = "📷 Câmera: Livre (C)" if is_freecam else "📷 Câmera: Gravada (C)"
	if not is_freecam and frames.size() > 0:
		var f: Dictionary = frames[current_frame_index]
		if f.has("camera_transform"):
			_replay_cam.global_transform = f["camera_transform"]


func _toggle_hitboxes() -> void:
	show_hitboxes = not show_hitboxes
	if _hitbox_btn:
		_hitbox_btn.text = "📦 Hitboxes 3D: LIGADAS (H)" if show_hitboxes else "📦 Hitboxes 3D: DESLIGADAS (H)"
	_render_frame(current_frame_index)


func _render_frame(idx: int) -> void:
	if idx < 0 or idx >= frames.size():
		return

	var f: Dictionary = frames[idx]

	if _time_label:
		var cur_t: float = f.get("time", 0.0)
		var max_t: float = frames.back().get("time", 0.0) if not frames.is_empty() else 0.0
		_time_label.text = "Quadro: %d / %d | Tempo: %.2fs / %.2fs" % [
			idx + 1, frames.size(), cur_t, max_t
		]

	if not is_freecam and f.has("camera_transform"):
		_replay_cam.global_transform = f["camera_transform"]

	_render_player(f)
	_render_enemies(f)
	_render_bullets(f)


func _render_player(f: Dictionary) -> void:
	if not _vis_player:
		_vis_player = Node3D.new()
		_vis_player.name = "ReplayPlayerVisual"
		if PLAYER_GLTF:
			var ship_model := Node3D.new()
			ship_model.name = "ShipModel"
			ship_model.scale = Vector3(1.5, 1.5, 1.5)
			var ship_gltf := PLAYER_GLTF.instantiate() as Node3D
			# Rotação e escala idênticas a player.tscn (aponta para frente!)
			ship_gltf.transform = Transform3D(Basis(Vector3(-0.5, 0, 1.26759e-06), Vector3(0, 0.5, 0), Vector3(-1.26759e-06, 0, -0.5)), Vector3.ZERO)
			ship_model.add_child(ship_gltf)
			_vis_player.add_child(ship_model)
		_entities_container.add_child(_vis_player)

	if f.has("player_transform"):
		_vis_player.global_transform = f["player_transform"]
		_vis_player.visible = f.get("player_visible", true)


func _render_enemies(f: Dictionary) -> void:
	var enemy_data: Array = f.get("enemies", [])
	var active_ids: Dictionary = {}

	for e_info: Dictionary in enemy_data:
		var e_id: int = e_info.get("id", 0)
		active_ids[e_id] = true

		var vis_node: Node3D = _vis_enemies.get(e_id, null)
		if not vis_node:
			vis_node = _create_enemy_visual(e_info)
			_vis_enemies[e_id] = vis_node
			_entities_container.add_child(vis_node)

		vis_node.visible = true
		vis_node.global_transform = e_info.get("transform", Transform3D())

		var hitbox: MeshInstance3D = vis_node.get_node_or_null("HitboxMesh") as MeshInstance3D
		if hitbox:
			hitbox.visible = show_hitboxes

	for stored_id: int in _vis_enemies.keys():
		if not active_ids.has(stored_id):
			_vis_enemies[stored_id].visible = false


func _create_enemy_visual(e_info: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "EnemyVisual_%d" % e_info.get("id", 0)

	var e_type: String = e_info.get("type", "Scout")

	if e_type.contains("Bomber") and BOMBER_GLB:
		var ship_model := Node3D.new()
		ship_model.name = "ShipModel"
		root.add_child(ship_model)

		var bomber_glb := BOMBER_GLB.instantiate() as Node3D
		ship_model.add_child(bomber_glb)
		bomber_glb.transform = Transform3D(Basis(Vector3(-4, 0, 0), Vector3(0, 4, 0), Vector3(0, 0, -4)), Vector3(-0.266, -0.905, 3.506))
	elif ENEMY_GLB:
		var ship_model := Node3D.new()
		ship_model.name = "ShipModel"
		root.add_child(ship_model)

		var glb := ENEMY_GLB.instantiate() as Node3D
		ship_model.add_child(glb)

		var target_ship := "Starship.002"
		if e_type.contains("Fighter"):
			target_ship = "Starship.v2"
			ship_model.scale = Vector3(1.5, 1.5, 1.5)
			glb.transform = Transform3D(Basis(Vector3(-5, 0, 7.54979e-07), Vector3(0, 5, 0), Vector3(-7.54979e-07, 0, -5)), Vector3(9.99, 0, 2.401))
		elif e_type.contains("Heavy"):
			target_ship = "Starship.v3"
			ship_model.scale = Vector3(1.5, 1.5, 1.5)
			glb.transform = Transform3D(Basis(Vector3(-4.5, 0, 3.93403e-07), Vector3(0, 4.5, 0), Vector3(-3.93403e-07, 0, -4.5)), Vector3(0, 0, -1.874))
		else:  # Scout
			target_ship = "Starship.002"
			ship_model.scale = Vector3(3.0, 3.0, 3.0)
			glb.transform = Transform3D(Basis(Vector3(-4, 0, 3.49691e-07), Vector3(0, 4, 0), Vector3(-3.49691e-07, 0, -4)), Vector3(-6.753, 0.297, 0.754))

		var known_ships: Array[String] = ["Starship.002", "Starship.v2", "Starship.v3", "Starship_002", "Starship_v2", "Starship_v3"]
		for s_name in known_ships:
			var node := glb.find_child(s_name, true, false)
			if node and node is Node3D:
				var m_clean := String(s_name).replace("_", ".")
				(node as Node3D).visible = (m_clean == target_ship)

	# Hitbox 3D Amarela Translúcida
	var hitbox_size: Vector3 = e_info.get("hitbox_size", Vector3(21, 9, 18))
	var box_mesh := BoxMesh.new()
	box_mesh.size = hitbox_size
	box_mesh.material = _hitbox_mat

	var hitbox_inst := MeshInstance3D.new()
	hitbox_inst.name = "HitboxMesh"
	hitbox_inst.mesh = box_mesh
	hitbox_inst.visible = show_hitboxes
	root.add_child(hitbox_inst)

	return root


func _render_bullets(f: Dictionary) -> void:
	var bullet_data: Array = f.get("bullets", [])
	var active_bullet_ids: Dictionary = {}

	for b_info: Dictionary in bullet_data:
		var b_id: int = b_info.get("id", 0)
		active_bullet_ids[b_id] = true

		var b_vis: MeshInstance3D = _vis_bullets.get(b_id, null)
		if not b_vis:
			b_vis = MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.7
			cap.height = 12.0
			b_vis.mesh = cap
			_entities_container.add_child(b_vis)
			_vis_bullets[b_id] = b_vis

		b_vis.visible = true
		b_vis.global_transform = b_info.get("transform", Transform3D())
		var is_enemy: bool = b_info.get("is_enemy", false)
		b_vis.material_override = _enemy_laser_mat if is_enemy else _player_laser_mat

	# Oculta projéteis que já atingiram o alvo ou expiraram
	for stored_id: int in _vis_bullets.keys():
		if not active_bullet_ids.has(stored_id):
			_vis_bullets[stored_id].visible = false


func _on_close_replay() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	replay_closed.emit()
	queue_free()
