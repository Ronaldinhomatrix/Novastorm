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


func _draw_bordered_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, point_count: int, color: Color, width: float) -> void:
	# Contorno escuro sólido para garantir 100% de contraste sobre qualquer cenário
	draw_arc(center, radius, start_angle, end_angle, point_count, Color(0.0, 0.0, 0.0, 0.95 * color.a), width + 3.0, true)
	draw_arc(center, radius, start_angle, end_angle, point_count, color, width, true)


func _draw_bordered_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	draw_line(from, to, Color(0.0, 0.0, 0.0, 0.95 * color.a), width + 3.0)
	draw_line(from, to, color, width)


func _draw_bordered_circle(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius + 1.8, Color(0.0, 0.0, 0.0, 0.95 * color.a))
	draw_circle(center, radius, color)


func _draw() -> void:
	if not _camera:
		return
	if _targets.is_empty() and _acquiring.is_empty():
		return

	var vp_rect := get_viewport_rect()
	var default_font := ThemeDB.fallback_font
	var is_mobile := GameConfig.is_mobile

	# Calibração de tamanho: no Mobile o retículo é bem maior e mais espesso para ser imediatamente visível
	var r_base := 48.0 if is_mobile else 32.0
	var t_width := 4.0 if is_mobile else 2.5
	var cross_len := 24.0 if is_mobile else 18.0
	var cross_g := 9.0 if is_mobile else 6.0
	var corner_l := 16.0 if is_mobile else 10.0
	var tick_l := 8.0 if is_mobile else 5.0
	var font_sz := 16 if is_mobile else 12

	# Efeito de piscar luminoso contínuo (Blink): nunca fica invisível (oscila entre 0.72 e 1.0)
	var blink_cycle := sin(_anim_time)
	var is_blink_on := blink_cycle > -0.2
	var blink_alpha := 1.0 if is_blink_on else 0.72
	var outer_pulse := (blink_cycle + 1.0) * 0.5 * (6.0 if is_mobile else 4.0)

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

		# Cores de alta emissividade com pulso
		var c_ring := Color(1.2, 0.28, 0.15, blink_alpha)
		var c_cross := Color(1.2, 1.0, 0.25, blink_alpha)

		var r := r_base + (outer_pulse if is_blink_on else 0.0)

		# 0. Disco de mira semi-transparente escurecido para isolar o alvo do fundo desértico
		draw_circle(screen_pos, r, Color(0.01, 0.03, 0.06, 0.32 * blink_alpha))

		# 1. Círculo principal da mira com contorno escuro nítido
		_draw_bordered_arc(screen_pos, r, 0.0, TAU, 40, c_ring, t_width)

		# 2. Círculo interno tático
		_draw_bordered_arc(screen_pos, r * 0.52, 0.0, TAU, 28, Color(c_ring.r, c_ring.g, c_ring.b, c_ring.a * 0.75), t_width * 0.6)

		# 3. Ponto central
		_draw_bordered_circle(screen_pos, 4.0 if is_mobile else 2.8, c_cross)

		# 4. Cruz da mira com contorno
		var t := t_width
		var g := cross_g
		var l := cross_len

		# Linha de Cima
		_draw_bordered_line(screen_pos + Vector2(0, -g), screen_pos + Vector2(0, -g - l), c_cross, t)
		# Linha de Baixo
		_draw_bordered_line(screen_pos + Vector2(0, g), screen_pos + Vector2(0, g + l), c_cross, t)
		# Linha da Esquerda
		_draw_bordered_line(screen_pos + Vector2(-g, 0), screen_pos + Vector2(-g - l, 0), c_cross, t)
		# Linha da Direita
		_draw_bordered_line(screen_pos + Vector2(g, 0), screen_pos + Vector2(g + l, 0), c_cross, t)

		# 5. Marcadores angulares militares
		_draw_bordered_line(screen_pos + Vector2(0, -r), screen_pos + Vector2(0, -r + tick_l), c_cross, t)
		_draw_bordered_line(screen_pos + Vector2(0, r), screen_pos + Vector2(0, r - tick_l), c_cross, t)
		_draw_bordered_line(screen_pos + Vector2(-r, 0), screen_pos + Vector2(-r + tick_l, 0), c_cross, t)
		_draw_bordered_line(screen_pos + Vector2(r, 0), screen_pos + Vector2(r - tick_l, 0), c_cross, t)

		# 6. Rótulo de travamento com contorno escuro grosso
		var label_text := "LOCK // T-%d" % (i + 1)
		var text_pos := Vector2(screen_pos.x - 60.0, screen_pos.y + r + (20.0 if is_mobile else 15.0))
		if default_font:
			draw_string_outline(default_font, text_pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, 120, font_sz, 5, Color(0.0, 0.0, 0.0, 0.95))
			draw_string(default_font, text_pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, 120, font_sz, c_cross)

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
		# Ciano elétrico com alto contraste em relação ao canyon desértico
		var c_col := Color(0.2, 0.95, 1.2, 0.95)
		var ar := r_base * lerpf(1.4, 1.0, progress)

		# 4 cantos de mira quadrada em aproximação com contorno escuro
		# Canto Superior Esquerdo
		_draw_bordered_line(a_screen + Vector2(-ar, -ar), a_screen + Vector2(-ar + corner_l, -ar), c_col, t_width)
		_draw_bordered_line(a_screen + Vector2(-ar, -ar), a_screen + Vector2(-ar, -ar + corner_l), c_col, t_width)

		# Canto Superior Direito
		_draw_bordered_line(a_screen + Vector2(ar, -ar), a_screen + Vector2(ar - corner_l, -ar), c_col, t_width)
		_draw_bordered_line(a_screen + Vector2(ar, -ar), a_screen + Vector2(ar, -ar + corner_l), c_col, t_width)

		# Canto Inferior Esquerdo
		_draw_bordered_line(a_screen + Vector2(-ar, ar), a_screen + Vector2(-ar + corner_l, ar), c_col, t_width)
		_draw_bordered_line(a_screen + Vector2(-ar, ar), a_screen + Vector2(-ar, ar - corner_l), c_col, t_width)

		# Canto Inferior Direito
		_draw_bordered_line(a_screen + Vector2(ar, ar), a_screen + Vector2(ar - corner_l, ar), c_col, t_width)
		_draw_bordered_line(a_screen + Vector2(ar, ar), a_screen + Vector2(ar, ar - corner_l), c_col, t_width)

		# Arco circular de progresso (carregando até travar)
		_draw_bordered_arc(a_screen, ar * 0.72, -PI * 0.5, -PI * 0.5 + (TAU * progress), 32, c_col, t_width * 0.75)

		# Ponto central
		_draw_bordered_circle(a_screen, 3.5 if is_mobile else 2.2, c_col)

		# Rótulo de aquisição com contorno
		var acq_label := "TRACKING (%.0f%%)" % (progress * 100.0)
		var acq_text_pos := Vector2(a_screen.x - 60.0, a_screen.y + ar + (18.0 if is_mobile else 14.0))
		if default_font:
			draw_string_outline(default_font, acq_text_pos, acq_label, HORIZONTAL_ALIGNMENT_CENTER, 120, font_sz - 2, 4, Color(0.0, 0.0, 0.0, 0.95))
			draw_string(default_font, acq_text_pos, acq_label, HORIZONTAL_ALIGNMENT_CENTER, 120, font_sz - 2, c_col)
