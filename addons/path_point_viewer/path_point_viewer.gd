@tool
extends EditorPlugin

## Plugin de Editor para Path3D:
## Desenha numeros 3D flutuantes (#0, #1, #2, etc.) sobre cada ponto da curva no Viewport 3D

var _labels_root: Node3D = null
var _current_path: Path3D = null


func _handles(object: Object) -> bool:
	return object is Path3D


func _edit(object: Object) -> void:
	if object is Path3D:
		_current_path = object as Path3D
		_update_labels()
	else:
		_clear_labels()
		_current_path = null


func _make_visible(visible: bool) -> void:
	if not visible:
		_clear_labels()
		_current_path = null


func _process(_delta: float) -> void:
	if _current_path and is_instance_valid(_current_path):
		if _current_path.curve:
			var expected_count := _current_path.curve.point_count
			var current_count := 0
			if _labels_root and is_instance_valid(_labels_root):
				current_count = _labels_root.get_child_count()
			if expected_count != current_count:
				_update_labels()


func _clear_labels() -> void:
	if _labels_root and is_instance_valid(_labels_root):
		_labels_root.queue_free()
		_labels_root = null


func _update_labels() -> void:
	_clear_labels()
	if not _current_path or not is_instance_valid(_current_path) or not _current_path.curve:
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