@tool
extends EditorPlugin

## Plugin de Editor para Path3D:
## Desenha numeros 3D flutuantes (#0, #1, #2, etc.) sobre cada ponto da curva no Viewport 3D
## Mantém os rótulos SEMPRE VISÍVEIS na cena atual, com botão de Liga/Desliga na barra superior.

var _labels_root: Node3D = null
var _current_path: Path3D = null
var _toggle_btn: Button = null
var _show_numbers: bool = true


func _enter_tree() -> void:
	_toggle_btn = Button.new()
	_toggle_btn.text = "🔢 Números Path: ON"
	_toggle_btn.tooltip_text = "Alterna a visibilidade contínua dos números dos pontos do Path3D na cena"
	_toggle_btn.toggle_mode = true
	_toggle_btn.button_pressed = true
	_toggle_btn.toggled.connect(_on_toggle_pressed)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _toggle_btn)


func _exit_tree() -> void:
	if _toggle_btn:
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _toggle_btn)
		_toggle_btn.queue_free()
		_toggle_btn = null
	_clear_labels()


func _on_toggle_pressed(pressed: bool) -> void:
	_show_numbers = pressed
	if _toggle_btn:
		_toggle_btn.text = "🔢 Números Path: ON" if pressed else "🔢 Números Path: OFF"
	if not _show_numbers:
		_clear_labels()
	else:
		_refresh_active_scene_path()


func _process(_delta: float) -> void:
	if not _show_numbers:
		return

	var path := _get_scene_path()
	if path != _current_path or (_labels_root == null or not is_instance_valid(_labels_root)):
		_current_path = path
		_update_labels()
	elif _current_path and is_instance_valid(_current_path) and _current_path.curve:
		var expected_count := _current_path.curve.point_count
		var current_count := 0
		if _labels_root and is_instance_valid(_labels_root):
			current_count = _labels_root.get_child_count()
		if expected_count != current_count:
			_update_labels()


func _get_scene_path() -> Path3D:
	var editor := get_editor_interface()
	if not editor:
		return null
	var scene := editor.get_edited_scene_root()
	if not scene:
		return null

	# 1. Procura nó com nome FlightPath
	var p := scene.find_child("FlightPath", true, false) as Path3D
	if p:
		return p

	# 2. Se não achar, procura qualquer Path3D na cena
	return scene.find_child("*", true, false) as Path3D if scene is Path3D else _find_any_path3d(scene)


func _find_any_path3d(node: Node) -> Path3D:
	if node is Path3D:
		return node as Path3D
	for child in node.get_children():
		var res := _find_any_path3d(child)
		if res:
			return res
	return null


func _refresh_active_scene_path() -> void:
	_current_path = _get_scene_path()
	_update_labels()


func _clear_labels() -> void:
	if _labels_root and is_instance_valid(_labels_root):
		_labels_root.queue_free()
		_labels_root = null


func _update_labels() -> void:
	_clear_labels()
	if not _show_numbers or not _current_path or not is_instance_valid(_current_path) or not _current_path.curve:
		return

	var curve := _current_path.curve
	_labels_root = Node3D.new()
	_labels_root.name = "_PathPointLabels"
	_current_path.add_child(_labels_root)

	for i in range(curve.point_count):
		var pos := curve.get_point_position(i)
		var lbl := Label3D.new()
		lbl.text = " #%d " % i
		lbl.font_size = 54
		lbl.pixel_size = 0.08
		lbl.modulate = Color(1.0, 0.9, 0.1, 1.0)
		lbl.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
		lbl.outline_size = 18
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.double_sided = true
		lbl.render_priority = 120
		lbl.position = pos + Vector3(0, 25, 0)
		_labels_root.add_child(lbl)