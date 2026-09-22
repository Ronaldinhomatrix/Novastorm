class_name TutorialOverlay
extends Control

## Overlay do Tutorial Tático estilo AAA para Pterodon.
## Apresenta tipografia grossa/impactante, animação elástica (pop-in com overshoot/bounce)
## e ambientação cinematográfica sem caixas restritivas ao redor dos textos.

var _banner_container: Control = null
var _tag_label: Label = null
var _message_label: Label = null
var _sub_message_label: Label = null
var _line_top: ColorRect = null
var _line_bottom: ColorRect = null
var _bg_glow: TextureRect = null

var _dim_overlay: ColorRect = null
var _is_pulsing_mobile: bool = false
var _pulse_timer: float = 0.0

var _target_alpha: float = 0.0
var _current_alpha: float = 0.0
var _elastic_time: float = 2.0
var _elastic_duration: float = 2.0  # Duração estendida para a animação rodar a 30% da velocidade anterior
var _idle_time: float = 0.0

var _prompt_panel_ref: Control = null
var _prompt_arrow_color: Color = Color(1.5, 1.1, 0.2, 1.0)
var _current_accent_color: Color = Color(0.2, 0.9, 1.0)

# Brilho ao redor do botão apontado (o corpo do botão NUNCA pulsa/escala)
var _prompt_panel_sb: StyleBoxFlat = null
var _prompt_panel_glow_backup: Dictionary = {}

var _prompt_arrow_container: Control = null
var _prompt_arrow_label: Label = null
var _prompt_arrow_text: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func _build_ui() -> void:
	# Fonte principal: ultra-bold/impactante estilo arcade espacial AAA
	var font_impact := SystemFont.new()
	font_impact.font_names = PackedStringArray(["Impact", "Arial Black", "Trebuchet MS", "Consolas", "Monospace"])
	font_impact.font_weight = 900
	font_impact.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED

	var font_mono := SystemFont.new()
	font_mono.font_names = PackedStringArray(["Consolas", "Cascadia Code", "Courier New", "Lucida Console", "Monospace"])
	font_mono.font_weight = 800
	font_mono.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED

	# Fundo escurecedor para destaque do tutorial (Dim Layer)
	_dim_overlay = ColorRect.new()
	_dim_overlay.name = "DimOverlay"
	_dim_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_overlay.color = Color(0.0, 0.0, 0.0, 0.70)
	_dim_overlay.modulate.a = 0.0
	_dim_overlay.visible = false
	add_child(_dim_overlay)

	# 1. Container Central Flutuante para os Textos (Sem caixa fechada)
	_banner_container = Control.new()
	_banner_container.name = "BannerContainer"
	_banner_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_container.anchor_left = 0.5
	_banner_container.anchor_right = 0.5
	_banner_container.offset_left = -780.0
	_banner_container.offset_right = 780.0
	_banner_container.offset_top = 130.0
	_banner_container.offset_bottom = 350.0
	# Pivot exatamente no centro para o efeito elástico de escala
	_banner_container.pivot_offset = Vector2(780.0, 110.0)
	_banner_container.scale = Vector2.ZERO
	_banner_container.modulate.a = 0.0
	add_child(_banner_container)

	# Fundo cinematográfico sutil: gradiente horizontal que some nas bordas (sem parecer caixa)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	grad.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.01, 0.03, 0.08, 0.45),
		Color(0.01, 0.04, 0.10, 0.65),
		Color(0.01, 0.03, 0.08, 0.45),
		Color(0.0, 0.0, 0.0, 0.0)
	])
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0.0, 0.5)
	grad_tex.fill_to = Vector2(1.0, 0.5)
	grad_tex.width = 512
	grad_tex.height = 64

	_bg_glow = TextureRect.new()
	_bg_glow.texture = grad_tex
	_bg_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner_container.add_child(_bg_glow)

	# Linhas holográficas sutis (topo e base) estilo HUD de nave de caça
	_line_top = ColorRect.new()
	_line_top.custom_minimum_size = Vector2(0.0, 2.0)
	_line_top.anchor_left = 0.1
	_line_top.anchor_right = 0.9
	_line_top.offset_top = 4.0
	_line_top.offset_bottom = 6.0
	_line_top.color = Color(0.0, 0.85, 1.0, 0.55)
	_banner_container.add_child(_line_top)

	_line_bottom = ColorRect.new()
	_line_bottom.custom_minimum_size = Vector2(0.0, 2.0)
	_line_bottom.anchor_left = 0.1
	_line_bottom.anchor_right = 0.9
	_line_bottom.anchor_top = 1.0
	_line_bottom.anchor_bottom = 1.0
	_line_bottom.offset_top = -6.0
	_line_bottom.offset_bottom = -4.0
	_line_bottom.color = Color(0.0, 0.85, 1.0, 0.55)
	_banner_container.add_child(_line_bottom)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	_banner_container.add_child(vbox)

	# Tag / Categoria acima da mensagem principal
	_tag_label = Label.new()
	_tag_label.text = tr("TUTORIAL_TAG")
	_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag_label.add_theme_font_override("font", font_mono)
	_tag_label.add_theme_font_size_override("font_size", 16)
	_tag_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0, 0.9))
	_tag_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.5, 0.8, 0.6))
	_tag_label.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(_tag_label)

	# Linha 1 - Mensagem Principal: LETRA GROSSA, GRANDE, ALTO IMPACTO
	_message_label = Label.new()
	_message_label.text = ""
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_override("font", font_impact)
	_message_label.add_theme_font_size_override("font_size", 50)
	_message_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_message_label.add_theme_color_override("font_outline_color", Color(0.0, 0.35, 0.65, 0.95))
	_message_label.add_theme_constant_override("outline_size", 12)
	_message_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.8, 1.0, 0.85))
	_message_label.add_theme_constant_override("shadow_offset_y", 4)
	_message_label.add_theme_constant_override("shadow_outline_size", 10)
	vbox.add_child(_message_label)

	# Linha 2 - Sub-mensagem / Linha de Baixo: MESMO TAMANHO DA PRIMEIRA LINHA, COM COR DIFERENTE
	_sub_message_label = Label.new()
	_sub_message_label.text = ""
	_sub_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub_message_label.add_theme_font_override("font", font_impact)
	_sub_message_label.add_theme_font_size_override("font_size", 50)
	_sub_message_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4, 1.0))
	_sub_message_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_sub_message_label.add_theme_constant_override("outline_size", 12)
	_sub_message_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.8, 1.0, 0.85))
	_sub_message_label.add_theme_constant_override("shadow_offset_y", 4)
	_sub_message_label.add_theme_constant_override("shadow_outline_size", 10)
	_sub_message_label.visible = false
	vbox.add_child(_sub_message_label)

	# Container da flecha pulsante flutuante apontada para o botão (Mobile e PC)
	_prompt_arrow_container = Control.new()
	_prompt_arrow_container.name = "PromptArrowContainer"
	_prompt_arrow_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_arrow_container.visible = false
	add_child(_prompt_arrow_container)

	var arrow_vbox := VBoxContainer.new()
	arrow_vbox.name = "ArrowVBox"
	arrow_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	arrow_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arrow_vbox.add_theme_constant_override("separation", -4)
	_prompt_arrow_container.add_child(arrow_vbox)

	_prompt_arrow_text = Label.new()
	_prompt_arrow_text.text = ""
	_prompt_arrow_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_arrow_text.add_theme_font_override("font", font_impact)
	_prompt_arrow_text.add_theme_font_size_override("font_size", 30)
	_prompt_arrow_text.add_theme_color_override("font_color", Color(1.5, 1.1, 0.2, 1.0))
	_prompt_arrow_text.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_prompt_arrow_text.add_theme_constant_override("outline_size", 10)
	_prompt_arrow_text.add_theme_color_override("font_shadow_color", Color(1.0, 0.5, 0.0, 0.9))
	_prompt_arrow_text.add_theme_constant_override("shadow_offset_y", 3)
	_prompt_arrow_text.add_theme_constant_override("line_spacing", -4)
	arrow_vbox.add_child(_prompt_arrow_text)

	_prompt_arrow_label = Label.new()
	_prompt_arrow_label.text = "▼"
	_prompt_arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_arrow_label.add_theme_font_override("font", font_impact)
	_prompt_arrow_label.add_theme_font_size_override("font_size", 70)
	_prompt_arrow_label.add_theme_color_override("font_color", Color(1.5, 1.1, 0.2, 1.0))
	_prompt_arrow_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_prompt_arrow_label.add_theme_constant_override("outline_size", 14)
	_prompt_arrow_label.add_theme_color_override("font_shadow_color", Color(1.0, 0.4, 0.0, 0.9))
	_prompt_arrow_label.add_theme_constant_override("shadow_offset_y", 5)
	arrow_vbox.add_child(_prompt_arrow_label)


func _process(delta: float) -> void:
	# Como o jogo entra em slow motion (time_scale = 0.25), computamos delta real
	# para que o efeito elástico e as letras cresçam com dinamismo fluido
	var real_delta: float = (delta / maxf(Engine.time_scale, 0.05)) if Engine.time_scale < 0.9 else delta

	# Fade de transparência (30% da velocidade anterior)
	if _banner_container:
		_current_alpha = move_toward(_current_alpha, _target_alpha, 1.8 * real_delta)
		_banner_container.modulate.a = _current_alpha
		_banner_container.visible = (_current_alpha > 0.01)

		# Animação Elástica (Cresce com Overshoot / Efeito Mola)
		if _elastic_time < _elastic_duration:
			_elastic_time += real_delta
			var t := clampf(_elastic_time / _elastic_duration, 0.0, 1.0)
			var scale_factor := _ease_elastic_out(t)
			_banner_container.scale = Vector2(scale_factor, scale_factor)
		elif _target_alpha > 0.0:
			# Pulsação suave contínua ("respiração viva") enquanto a instrução está na tela
			_idle_time += real_delta
			var breathe := 1.0 + sin(_idle_time * 3.6) * 0.028
			_banner_container.scale = Vector2(breathe, breathe)

	# Efeito da flecha apontando para o botão (Flecha grande pulsando + contorno neon)
	if _is_pulsing_mobile:
		_pulse_timer += real_delta * 9.0
		var wave := (sin(_pulse_timer) + 1.0) * 0.5 # 0.0 a 1.0

		if _dim_overlay:
			_dim_overlay.visible = true
			_dim_overlay.modulate.a = move_toward(_dim_overlay.modulate.a, 1.0, 4.0 * real_delta)

		if _prompt_panel_ref and is_instance_valid(_prompt_panel_ref):
			_prompt_panel_ref.pivot_offset = _prompt_panel_ref.size * 0.5
			# Mantém o botão em destaque total e ligeiramente mais brilhante contra o fundo escuro
			_prompt_panel_ref.modulate = Color(1.25, 1.25, 1.25, 1.0)
			_prompt_panel_ref.scale = Vector2.ONE
			_pulse_panel_glow(_prompt_panel_ref, wave)

			# Anima a Flecha Grande Pulsando sobre o botão apontado
			if _prompt_arrow_container:
				_prompt_arrow_container.visible = true
				var p_rect := _prompt_panel_ref.get_global_rect()
				var w := 440.0
				var has_text := _prompt_arrow_text and not _prompt_arrow_text.text.is_empty()
				var is_multiline := has_text and _prompt_arrow_text.text.contains("\n")
				var h := 160.0 if is_multiline else (120.0 if has_text else 80.0)

				_prompt_arrow_container.size = Vector2(w, h)
				# Pivot no centro inferior (apontador da seta) para a pulsação ser puramente vertical/escala
				_prompt_arrow_container.pivot_offset = Vector2(w * 0.5, h)

				# Fixa a coordenada X perfeitamente no centro do botão (sem oscilação lateral)
				var center_x := p_rect.position.x + p_rect.size.x * 0.5
				var target_x := center_x - w * 0.5

				# Quique exclusivamente vertical (subindo e descendo suavemente em direção ao botão)
				var bounce := sin(_pulse_timer * 0.75) * 8.0
				var target_y := p_rect.position.y - h - 14.0 + bounce

				_prompt_arrow_container.global_position = Vector2(target_x, target_y)

				# Efeito de pulsação suave em escala (1.0 a 1.25x)
				var pulse_scale := lerpf(1.0, 1.25, wave)
				_prompt_arrow_container.scale = Vector2(pulse_scale, pulse_scale)

				# Ajusta as cores neon da seta e texto para combinarem com a cor do prompt
				if _prompt_arrow_text:
					_prompt_arrow_text.add_theme_color_override("font_color", _prompt_arrow_color)
					_prompt_arrow_text.add_theme_color_override("font_shadow_color", Color(_prompt_arrow_color.r * 0.6, _prompt_arrow_color.g * 0.6, _prompt_arrow_color.b * 0.6, 0.9))

				if _prompt_arrow_label:
					_prompt_arrow_label.add_theme_color_override("font_color", _prompt_arrow_color)
					_prompt_arrow_label.add_theme_color_override("font_shadow_color", Color(_prompt_arrow_color.r * 0.6, _prompt_arrow_color.g * 0.6, _prompt_arrow_color.b * 0.6, 0.9))
	else:
		if _dim_overlay and _dim_overlay.visible:
			_dim_overlay.modulate.a = move_toward(_dim_overlay.modulate.a, 0.0, 4.0 * real_delta)
			if _dim_overlay.modulate.a <= 0.01:
				_dim_overlay.visible = false

		if _prompt_arrow_container and _prompt_arrow_container.visible:
			_prompt_arrow_container.visible = false

		if _prompt_panel_ref and is_instance_valid(_prompt_panel_ref):
			_prompt_panel_ref.modulate = Color.WHITE
			if _prompt_panel_ref.scale != Vector2.ONE:
				_prompt_panel_ref.scale = Vector2.ONE


## Faz o brilho ao redor do painel e o fundo StyleBox destacarem-se vivamente
func _pulse_panel_glow(panel: Control, wave: float) -> void:
	var sb := panel.get_theme_stylebox("panel")
	if not (sb is StyleBoxFlat):
		return
	var sb_flat := sb as StyleBoxFlat
	if _prompt_panel_sb != sb_flat:
		# O HUD recriou o StyleBox (mudança de estado): restaura o antigo e
		# passa a guardar os valores base do novo contorno.
		_restore_prompt_panel_glow()
		_prompt_panel_sb = sb_flat
		_store_prompt_panel_glow_backup(sb_flat)

	var glow := lerpf(1.1, 2.0, wave)
	sb_flat.border_color = Color(
		_prompt_arrow_color.r * glow,
		_prompt_arrow_color.g * glow,
		_prompt_arrow_color.b * glow,
		1.0
	)
	sb_flat.shadow_color = Color(
		_prompt_arrow_color.r,
		_prompt_arrow_color.g,
		_prompt_arrow_color.b,
		lerpf(0.55, 1.0, wave)
	)
	sb_flat.shadow_size = int(lerpf(14.0, 32.0, wave))
	# Fundo do botão com leve brilho da cor do botão para se destacar na escuridão
	sb_flat.bg_color = Color(
		lerpf(0.04, 0.04 + _prompt_arrow_color.r * 0.08, wave),
		lerpf(0.06, 0.06 + _prompt_arrow_color.g * 0.08, wave),
		lerpf(0.10, 0.10 + _prompt_arrow_color.b * 0.08, wave),
		0.96
	)


## Guarda os valores base do contorno/brilho do painel apontado
func _store_prompt_panel_glow_backup(sb_flat: StyleBoxFlat) -> void:
	_prompt_panel_glow_backup = {
		"border": sb_flat.border_color,
		"shadow": sb_flat.shadow_color,
		"shadow_size": sb_flat.shadow_size,
		"bg_color": sb_flat.bg_color,
	}


## Guarda os valores originais do contorno/brilho do painel apontado
func _backup_prompt_panel_glow(panel: Control) -> void:
	var sb := panel.get_theme_stylebox("panel")
	if not (sb is StyleBoxFlat):
		return
	var sb_flat := sb as StyleBoxFlat
	if _prompt_panel_sb == sb_flat and not _prompt_panel_glow_backup.is_empty():
		return
	_restore_prompt_panel_glow()
	_prompt_panel_sb = sb_flat
	_store_prompt_panel_glow_backup(sb_flat)


## Devolve o contorno/brilho originais ao painel apontado
func _restore_prompt_panel_glow() -> void:
	if _prompt_panel_sb and is_instance_valid(_prompt_panel_sb) and not _prompt_panel_glow_backup.is_empty():
		_prompt_panel_sb.border_color = _prompt_panel_glow_backup["border"]
		_prompt_panel_sb.shadow_color = _prompt_panel_glow_backup["shadow"]
		_prompt_panel_sb.shadow_size = int(_prompt_panel_glow_backup["shadow_size"])
		if _prompt_panel_glow_backup.has("bg_color"):
			_prompt_panel_sb.bg_color = _prompt_panel_glow_backup["bg_color"]
	_prompt_panel_sb = null
	_prompt_panel_glow_backup.clear()


## Informa se o overlay está destacando algum botão do HUD no momento
func is_prompting() -> bool:
	return _is_pulsing_mobile


## Efeito matemático padrão de Ease Elastic Out (Cresce, ultrapassa 1.0 e oscila como mola)
func _ease_elastic_out(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	var p := 0.38
	return pow(2.0, -10.0 * t) * sin((t - p / 4.0) * (TAU / p)) + 1.0


## Exibe uma instrução com o efeito elástico pop-in (suporta linha principal e linha de baixo)
func show_instruction(text: String, sub_text: String = "", tag: String = "", accent_color: Color = Color(0.0, 0.85, 1.0, 0.95)) -> void:
	if _message_label:
		_message_label.text = text
	if _sub_message_label:
		_sub_message_label.text = sub_text
		_sub_message_label.visible = not sub_text.is_empty()
	if _tag_label:
		_tag_label.text = tag
		_tag_label.visible = not tag.is_empty()

	_current_accent_color = accent_color

	# Ajusta as cores neon de outline, sombra e linhas decorativas
	var outline_col := Color(accent_color.r * 0.35, accent_color.g * 0.35, accent_color.b * 0.35, 0.95)
	if _message_label:
		# Linha 1: Branco cristal puro com sombra neon do accent_color
		_message_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		_message_label.add_theme_color_override("font_outline_color", outline_col)
		_message_label.add_theme_color_override("font_shadow_color", accent_color)

	if _sub_message_label:
		# Linha 2: Mesmo tamanho, com cor diferente (tonalidade vibrante do accent_color)
		_sub_message_label.add_theme_color_override("font_color", accent_color)
		_sub_message_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
		_sub_message_label.add_theme_color_override("font_shadow_color", Color(accent_color.r * 0.6, accent_color.g * 0.6, accent_color.b * 0.6, 0.85))

	if _tag_label and not tag.is_empty():
		_tag_label.add_theme_color_override("font_color", accent_color)

	if _line_top and _line_bottom:
		var line_col := Color(accent_color.r, accent_color.g, accent_color.b, 0.65)
		_line_top.color = line_col
		_line_bottom.color = line_col

	# Dispara o efeito elástico de crescimento a partir do zero
	_elastic_time = 0.0
	_idle_time = 0.0
	_target_alpha = 1.0


## Oculta o banner de instrução
func hide_instruction() -> void:
	_target_alpha = 0.0


## Inicia o piscar da flecha e do brilho ao redor de um painel específico
func start_mobile_button_prompt(target_panel: Control, arrow_text: String = "DISPARAR", arrow_color: Color = Color(1.5, 1.1, 0.2, 1.0)) -> void:
	# Restaura painel anterior se estivesse ativo
	if _prompt_panel_ref and is_instance_valid(_prompt_panel_ref) and _prompt_panel_ref != target_panel:
		_prompt_panel_ref.modulate = Color.WHITE
		_prompt_panel_ref.scale = Vector2.ONE
		_restore_prompt_panel_glow()

	_prompt_panel_ref = target_panel
	_prompt_arrow_color = arrow_color
	_is_pulsing_mobile = true
	_pulse_timer = 0.0
	if _prompt_arrow_text:
		_prompt_arrow_text.text = arrow_text
	_backup_prompt_panel_glow(target_panel)


## Inicia o piscar da flecha e do botão de mísseis apontando para o painel (compatibilidade retroativa)
func start_mobile_missile_prompt(missile_panel: Control, arrow_text: String = "DISPARAR") -> void:
	start_mobile_button_prompt(missile_panel, arrow_text, Color(1.5, 1.1, 0.2, 1.0))


## Interrompe o piscar do brilho e da flecha apontando para o botão
func stop_mobile_button_prompt() -> void:
	_is_pulsing_mobile = false
	if _prompt_arrow_container:
		_prompt_arrow_container.visible = false
	if _prompt_panel_ref and is_instance_valid(_prompt_panel_ref):
		_prompt_panel_ref.modulate = Color.WHITE
		_prompt_panel_ref.scale = Vector2.ONE
	_restore_prompt_panel_glow()
	_prompt_panel_ref = null


## Interrompe o piscar do botão e flecha de mísseis (compatibilidade retroativa)
func stop_mobile_missile_prompt() -> void:
	stop_mobile_button_prompt()


## Mostra mensagem de sucesso temporária com efeito elástico
func flash_completion(msg: String = "") -> void:
	if msg.is_empty():
		hide_instruction()
		return
	show_instruction(msg, "", "", Color(0.1, 1.4, 0.45, 1.0))
	var tree := get_tree()
	if tree:
		await tree.create_timer(2.0).timeout
	hide_instruction()

