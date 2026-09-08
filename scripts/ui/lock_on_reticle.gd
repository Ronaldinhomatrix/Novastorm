class_name LockOnReticle
extends Control

## Retículo computadorizado de Lock-On no estilo After Burner II.
## Desenha caixas de mira tática sobre até 3 inimigos travados,
## com cantoneiras animadas, indicador de LOCK e tracking em tempo real.

@export var color_locked: Color = Color(1.0, 0.28, 0.1, 0.92)      # Laranja/Vermelho Alerta
@export var color_tracking: Color = Color(1.0, 0.85, 0.15, 0.88)   # Amarelo Radar
@export var reticle_size: float = 64.0
@export var corner_size: float = 14.0
@export var line_thickness: float = 2.5

var _camera: Camera3D = null
var _targets: Array[Node3D] = []
var _target_screen_positions: Dictionary = {}  # target -> Vector2
var _anim_time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_camera(cam: Camera3D) -> void:
	_camera = cam


func update_targets(targets: Array[Node3D]) -> void:
	_targets.clear()
	for t in targets:
		if is_instance_valid(t) and not t.is_queued_for_deletion():
			_targets.append(t)
	queue_redraw()


func _process(delta: float) -> void:
	_anim_time += delta * 6.0
	if not _targets.is_empty():
		queue_redraw()


func _draw() -> void:
	if not _camera or _targets.is_empty():
		return

	var vp_rect := get_viewport_rect()
	var default_font := ThemeDB.fallback_font
	var default_font_size: int = 12

	for i in range(_targets.size()):
		var target := _targets[i]
		if not is_instance_valid(target) or target.is_queued_for_deletion():
			continue

		var target_pos := target.global_position
		var model: Node3D = target.get_node_or_null("ShipModel") as Node3D
		if model:
			target_pos = model.global_position

		# Ignora se estiver atrás da câmera
		if _camera.is_position_behind(target_pos):
			continue

		var screen_pos := _camera.unproject_position(target_pos)

		# Verifica se está dentro dos limites da tela
		if not vp_rect.has_point(screen_pos):
			continue

		# Animação de pulso sutil da caixa
		var pulse := sin(_anim_time + float(i) * 1.5) * 3.0
		var current_size := reticle_size + pulse
		var half_size := current_size * 0.5
		var rect := Rect2(screen_pos.x - half_size, screen_pos.y - half_size, current_size, current_size)

		_draw_tactical_brackets(rect, color_locked)

		# Desenha ponto central / diamante
		var diamond_r := 3.5
		var diamond_pts: PackedVector2Array = [
			screen_pos + Vector2(0, -diamond_r),
			screen_pos + Vector2(diamond_r, 0),
			screen_pos + Vector2(0, diamond_r),
			screen_pos + Vector2(-diamond_r, 0)
		]
		draw_colored_polygon(diamond_pts, color_locked)

		# Rótulo de Lock "LOCK // T-1", "LOCK // T-2"
		var label_text := "LOCK // T-%d" % (i + 1)
		var text_pos := Vector2(rect.position.x, rect.end.y + 14.0)
		if default_font:
			draw_string(default_font, text_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, default_font_size, color_locked)


func _draw_tactical_brackets(rect: Rect2, color: Color) -> void:
	var c_len := corner_size
	var t := line_thickness
	var p1 := rect.position
	var p2 := rect.end

	# Canto Superior Esquerdo
	draw_line(Vector2(p1.x, p1.y), Vector2(p1.x + c_len, p1.y), color, t)
	draw_line(Vector2(p1.x, p1.y), Vector2(p1.x, p1.y + c_len), color, t)

	# Canto Superior Direito
	draw_line(Vector2(p2.x, p1.y), Vector2(p2.x - c_len, p1.y), color, t)
	draw_line(Vector2(p2.x, p1.y), Vector2(p2.x, p1.y + c_len), color, t)

	# Canto Inferior Esquerdo
	draw_line(Vector2(p1.x, p2.y), Vector2(p1.x + c_len, p2.y), color, t)
	draw_line(Vector2(p1.x, p2.y), Vector2(p1.x, p2.y - c_len), color, t)

	# Canto Inferior Direito
	draw_line(Vector2(p2.x, p2.y), Vector2(p2.x - c_len, p2.y), color, t)
	draw_line(Vector2(p2.x, p2.y), Vector2(p2.x, p2.y - c_len), color, t)
