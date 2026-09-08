class_name LockOnReticle
extends Control

## Retículo computadorizado de Lock-On estilo arcade militar.
## Desenha um círculo com cruz central sobre cada inimigo travado,
## com efeito estroboscópico/piscante (blink) pulsante em tempo real.

@export var color_locked: Color = Color(1.0, 0.22, 0.1, 0.95)       # Vermelho/Laranja Neon Alerta
@export var color_cross: Color = Color(1.0, 0.9, 0.2, 0.95)         # Amarelo Radiante
@export var reticle_radius: float = 28.0
@export var line_thickness: float = 2.0
@export var cross_length: float = 16.0
@export var cross_gap: float = 6.0
@export var blink_speed: float = 14.0                               # Velocidade do piscar

var _camera: Camera3D = null
var _targets: Array[Node3D] = []
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
	_anim_time += delta * blink_speed
	if not _targets.is_empty():
		queue_redraw()


func _draw() -> void:
	if not _camera or _targets.is_empty():
		return

	var vp_rect := get_viewport_rect()
	var default_font := ThemeDB.fallback_font
	var default_font_size: int = 12

	# Efeito de piscar contínuo (Blink): modula transparência e intensidade luminosa
	# Gera alternância rápida entre foco brilhante e semi-transparência
	var blink_cycle := sin(_anim_time)
	var is_blink_on := blink_cycle > -0.2
	var blink_alpha := 1.0 if is_blink_on else 0.35
	var outer_pulse := (blink_cycle + 1.0) * 0.5 * 4.0

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

		# Ignora se estiver fora da tela
		if not vp_rect.has_point(screen_pos):
			continue

		var c_ring := color_locked
		c_ring.a *= blink_alpha
		var c_cross := color_cross
		c_cross.a *= blink_alpha

		var r := reticle_radius + (outer_pulse if is_blink_on else 0.0)

		# 1. Círculo principal da mira
		draw_arc(screen_pos, r, 0.0, TAU, 36, c_ring, line_thickness, true)

		# 2. Círculo interno tático (anel secundário pontilhado ou menor)
		draw_arc(screen_pos, r * 0.45, 0.0, TAU, 24, Color(c_ring.r, c_ring.g, c_ring.b, c_ring.a * 0.6), 1.2, true)

		# 3. Ponto central
		draw_circle(screen_pos, 2.5, c_cross)

		# 4. Cruz da mira (4 segmentos saindo a partir de cross_gap até cross_length)
		var t := line_thickness
		var g := cross_gap
		var l := cross_length

		# Linha de Cima
		draw_line(screen_pos + Vector2(0, -g), screen_pos + Vector2(0, -g - l), c_cross, t)
		# Linha de Baixo
		draw_line(screen_pos + Vector2(0, g), screen_pos + Vector2(0, g + l), c_cross, t)
		# Linha da Esquerda
		draw_line(screen_pos + Vector2(-g, 0), screen_pos + Vector2(-g - l, 0), c_cross, t)
		# Linha da Direita
		draw_line(screen_pos + Vector2(g, 0), screen_pos + Vector2(g + l, 0), c_cross, t)

		# 5. Marcadores angulares nos 4 cantos do círculo (marcações táticas militares)
		var tick_len := 4.5
		draw_line(screen_pos + Vector2(0, -r), screen_pos + Vector2(0, -r + tick_len), c_cross, t)
		draw_line(screen_pos + Vector2(0, r), screen_pos + Vector2(0, r - tick_len), c_cross, t)
		draw_line(screen_pos + Vector2(-r, 0), screen_pos + Vector2(-r + tick_len, 0), c_cross, t)
		draw_line(screen_pos + Vector2(r, 0), screen_pos + Vector2(r - tick_len, 0), c_cross, t)

		# 6. Rótulo de travamento com ordem de disparo (T-1, T-2, T-3)
		if is_blink_on:
			var label_text := "LOCK // T-%d" % (i + 1)
			var text_pos := Vector2(screen_pos.x - 30.0, screen_pos.y + r + 16.0)
			if default_font:
				draw_string(default_font, text_pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, 60, default_font_size, c_ring)
