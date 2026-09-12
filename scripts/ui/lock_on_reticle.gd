class_name LockOnReticle
extends Control

## Retículo computadorizado de Lock-On estilo arcade militar.
## Desenha um círculo com cruz central sobre cada inimigo travado,
## com efeito estroboscópico/piscante (blink) pulsante em tempo real.

@export var color_locked: Color = Color(1.0, 0.22, 0.1, 0.95)       # Vermelho/Laranja Neon Alerta
@export var color_cross: Color = Color(1.0, 0.9, 0.2, 0.95)         # Amarelo Radiante
@export var color_acquiring: Color = Color(1.0, 0.85, 0.2, 0.85)    # Amarelo/Dourado em aquisição
@export var reticle_radius: float = 28.0
@export var line_thickness: float = 2.0
@export var cross_length: float = 16.0
@export var cross_gap: float = 6.0
@export var blink_speed: float = 14.0                               # Velocidade do piscar

var _camera: Camera3D = null
var _targets: Array[Node3D] = []
var _acquiring: Dictionary = {}  ## Node3D -> float (tempo decorrido)
var _anim_time: float = 0.0
var _model_cache: Dictionary = {}  ## Node3D -> Node3D (target -> ShipModel)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_camera(cam: Camera3D) -> void:
	_camera = cam


func _get_target_pos(target: Node3D) -> Vector3:
	## Retorna a posição do ShipModel se existir, senão a posição global do alvo.
	if _model_cache.has(target):
		var model: Node3D = _model_cache[target]
		if is_instance_valid(model):
			return model.global_position
		else:
			_model_cache.erase(target)
	var model: Node3D = target.get_node_or_null("ShipModel") as Node3D
	if model:
		_model_cache[target] = model
		return model.global_position
	return target.global_position


func update_targets(targets: Array[Node3D]) -> void:
	_targets.clear()
	for t in targets:
		if is_instance_valid(t) and not t.is_queued_for_deletion():
			_targets.append(t)
	queue_redraw()
	
	# Limpa cache de modelos para alvos que não existem mais
	for key in _model_cache.keys():
		if not is_instance_valid(key):
			_model_cache.erase(key)


func update_targeting_state(locked: Array[Node3D], acquiring: Dictionary) -> void:
	_targets.clear()
	for t in locked:
		if is_instance_valid(t) and not t.is_queued_for_deletion():
			_targets.append(t)

	_acquiring.clear()
	for a in acquiring.keys():
		if is_instance_valid(a) and not a.is_queued_for_deletion() and not _targets.has(a):
			_acquiring[a] = acquiring[a]

	queue_redraw()
	
	# Limpa cache de modelos para alvos que não existem mais
	for key in _model_cache.keys():
		if not is_instance_valid(key):
			_model_cache.erase(key)


func _process(delta: float) -> void:
	_anim_time += delta * blink_speed
	if not _targets.is_empty() or not _acquiring.is_empty():
		queue_redraw()


func _draw() -> void:
	if not _camera:
		return
	if _targets.is_empty() and _acquiring.is_empty():
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

		var target_pos := _get_target_pos(target)

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

	# Desenha alvos em processo de aquisição (Marcados / Tagged - Aguardando confirmação)
	for a_target in _acquiring.keys():
		if not is_instance_valid(a_target) or a_target.is_queued_for_deletion():
			continue

		var a_pos: Vector3 = _get_target_pos(a_target)

		if _camera.is_position_behind(a_pos):
			continue

		var a_screen := _camera.unproject_position(a_pos)
		if not vp_rect.has_point(a_screen):
			continue

		var progress: float = clampf(_acquiring[a_target] / 1.0, 0.0, 1.0)
		var c_acq := color_acquiring
		# Efeito de mira fechando/focando conforme aproxima de 1.0s
		var ar := reticle_radius * lerpf(1.35, 1.0, progress)

		# 4 cantos de mira quadrada em aproximação (Target Acquired/Tracking)
		var corner_len := 9.0
		var c_col := Color(c_acq.r, c_acq.g, c_acq.b, 0.85)

		# Canto Superior Esquerdo
		draw_line(a_screen + Vector2(-ar, -ar), a_screen + Vector2(-ar + corner_len, -ar), c_col, 2.0)
		draw_line(a_screen + Vector2(-ar, -ar), a_screen + Vector2(-ar, -ar + corner_len), c_col, 2.0)

		# Canto Superior Direito
		draw_line(a_screen + Vector2(ar, -ar), a_screen + Vector2(ar - corner_len, -ar), c_col, 2.0)
		draw_line(a_screen + Vector2(ar, -ar), a_screen + Vector2(ar, -ar + corner_len), c_col, 2.0)

		# Canto Inferior Esquerdo
		draw_line(a_screen + Vector2(-ar, ar), a_screen + Vector2(-ar + corner_len, ar), c_col, 2.0)
		draw_line(a_screen + Vector2(-ar, ar), a_screen + Vector2(-ar, ar - corner_len), c_col, 2.0)

		# Canto Inferior Direito
		draw_line(a_screen + Vector2(ar, ar), a_screen + Vector2(ar - corner_len, ar), c_col, 2.0)
		draw_line(a_screen + Vector2(ar, ar), a_screen + Vector2(ar, ar - corner_len), c_col, 2.0)

		# Arco circular de progresso (carregando até fechar o círculo e travar)
		draw_arc(a_screen, ar * 0.75, -PI * 0.5, -PI * 0.5 + (TAU * progress), 28, c_col, 1.5, true)

		# Ponto central
		draw_circle(a_screen, 2.0, c_col)

		# Rótulo de aquisição
		var acq_label := "TRACKING"
		var acq_text_pos := Vector2(a_screen.x - 30.0, a_screen.y + ar + 14.0)
		if default_font:
			draw_string(default_font, acq_text_pos, acq_label, HORIZONTAL_ALIGNMENT_CENTER, 60, 10, c_col)
