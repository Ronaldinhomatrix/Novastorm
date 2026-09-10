class_name TutorialOverlay
extends Control

## Overlay do Tutorial Tático estilo AAA para Novastorm.
## Apresenta tipografia grossa/impactante, animação elástica (pop-in com overshoot/bounce)
## e ambientação cinematográfica sem caixas restritivas ao redor dos textos.

var _banner_container: Control = null
var _tag_label: Label = null
var _message_label: Label = null
var _line_top: ColorRect = null
var _line_bottom: ColorRect = null
var _bg_glow: TextureRect = null

var _mobile_hint: PanelContainer = null
var _mobile_hint_label: Label = null
var _is_pulsing_mobile: bool = false
var _pulse_timer: float = 0.0

var _target_alpha: float = 0.0
var _current_alpha: float = 0.0
var _elastic_time: float = 1.0
var _elastic_duration: float = 0.60
var _idle_time: float = 0.0

var _missile_panel_ref: Control = null
var _current_accent_color: Color = Color(0.2, 0.9, 1.0)


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

	# 1. Container Central Flutuante para os Textos (Sem caixa fechada)
	_banner_container = Control.new()
	_banner_container.name = "BannerContainer"
	_banner_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_container.anchor_left = 0.5
	_banner_container.anchor_right = 0.5
	_banner_container.offset_left = -700.0
	_banner_container.offset_right = 700.0
	_banner_container.offset_top = 160.0
	_banner_container.offset_bottom = 290.0
	# Pivot exatamente no centro para o efeito elástico de escala
	_banner_container.pivot_offset = Vector2(700.0, 65.0)
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
	vbox.add_theme_constant_override("separation", 8)
	_banner_container.add_child(vbox)

	# Tag / Categoria acima da mensagem principal
	_tag_label = Label.new()
	_tag_label.text = "// PROTOCOLO DE COMBATE // TUTORIAL"
	_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag_label.add_theme_font_override("font", font_mono)
	_tag_label.add_theme_font_size_override("font_size", 14)
	_tag_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0, 0.9))
	_tag_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.5, 0.8, 0.6))
	_tag_label.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(_tag_label)

	# Mensagem Principal: LETRA GROSSA, GRANDE, ALTO IMPACTO
	_message_label = Label.new()
	_message_label.text = ""
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_override("font", font_impact)
	_message_label.add_theme_font_size_override("font_size", 46)
	_message_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_message_label.add_theme_color_override("font_outline_color", Color(0.0, 0.35, 0.65, 0.95))
	_message_label.add_theme_constant_override("outline_size", 12)
	_message_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.8, 1.0, 0.85))
	_message_label.add_theme_constant_override("shadow_offset_y", 4)
	_message_label.add_theme_constant_override("shadow_outline_size", 10)
	vbox.add_child(_message_label)

	# 2. Balão de chamada (Hint) apontando para o botão de míssil no Mobile com letra grossa
	_mobile_hint = PanelContainer.new()
	_mobile_hint.name = "MobileMissileHint"
	_mobile_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_hint.anchor_top = 1.0
	_mobile_hint.anchor_bottom = 1.0
	_mobile_hint.offset_left = 270.0
	_mobile_hint.offset_right = 720.0
	_mobile_hint.offset_top = -84.0
	_mobile_hint.offset_bottom = -16.0
	_mobile_hint.pivot_offset = Vector2(0.0, 34.0)
	_mobile_hint.visible = false

	var hint_sb := StyleBoxFlat.new()
	hint_sb.bg_color = Color(0.02, 0.04, 0.08, 0.94)
	hint_sb.border_color = Color(1.3, 0.85, 0.1, 1.0) # Dourado Neon
	hint_sb.set_border_width_all(3)
	hint_sb.corner_radius_top_left = 8
	hint_sb.corner_radius_top_right = 8
	hint_sb.corner_radius_bottom_left = 8
	hint_sb.corner_radius_bottom_right = 8
	hint_sb.shadow_color = Color(1.0, 0.6, 0.05, 0.6)
	hint_sb.shadow_size = 14
	hint_sb.set_content_margin_all(10)
	_mobile_hint.add_theme_stylebox_override("panel", hint_sb)
	add_child(_mobile_hint)

	_mobile_hint_label = Label.new()
	_mobile_hint_label.text = "◄ USE ESTE BOTÃO PARA DISPARAR MÍSSEIS"
	_mobile_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mobile_hint_label.add_theme_font_override("font", font_impact)
	_mobile_hint_label.add_theme_font_size_override("font_size", 20)
	_mobile_hint_label.add_theme_color_override("font_color", Color(1.4, 0.95, 0.3, 1.0))
	_mobile_hint_label.add_theme_color_override("font_outline_color", Color(0.4, 0.15, 0.0, 0.9))
	_mobile_hint_label.add_theme_constant_override("outline_size", 6)
	_mobile_hint.add_child(_mobile_hint_label)


func _process(delta: float) -> void:
	# Como o jogo entra em slow motion (time_scale = 0.2), computamos delta real
	# para que o efeito elástico e as letras cresçam com vigor e dinamismo 100% fluidos!
	var real_delta: float = (delta / maxf(Engine.time_scale, 0.05)) if Engine.time_scale < 0.9 else delta

	# Fade de transparência
	if _banner_container:
		_current_alpha = move_toward(_current_alpha, _target_alpha, 6.0 * real_delta)
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

	# Efeito pulsante de piscar do botão no Mobile
	if _is_pulsing_mobile:
		_pulse_timer += real_delta * 8.0
		var wave := (sin(_pulse_timer) + 1.0) * 0.5 # 0.0 a 1.0
		if _mobile_hint:
			_mobile_hint.visible = true
			var hint_scale := 1.0 + wave * 0.06
			_mobile_hint.scale = Vector2(hint_scale, hint_scale)
			_mobile_hint.modulate = Color(1.0 + wave * 0.3, 1.0 + wave * 0.2, 0.8 + wave * 0.4, 0.9 + wave * 0.1)
		if _missile_panel_ref and is_instance_valid(_missile_panel_ref):
			_missile_panel_ref.modulate = Color(1.0 + wave * 0.7, 1.0 + wave * 0.5, 0.5 + wave * 0.5, 1.0)
			_missile_panel_ref.scale = Vector2.ONE * (1.0 + wave * 0.08)
	else:
		if _mobile_hint and _mobile_hint.visible:
			_mobile_hint.visible = false
		if _missile_panel_ref and is_instance_valid(_missile_panel_ref):
			if _missile_panel_ref.scale != Vector2.ONE:
				_missile_panel_ref.scale = Vector2.ONE


## Efeito matemático padrão de Ease Elastic Out (Cresce, ultrapassa 1.0 e oscila como mola)
func _ease_elastic_out(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	var p := 0.38
	return pow(2.0, -10.0 * t) * sin((t - p / 4.0) * (TAU / p)) + 1.0


## Exibe uma instrução tática com o efeito elástico pop-in
func show_instruction(text: String, tag: String = "// PROTOCOLO DE COMBATE // TUTORIAL", accent_color: Color = Color(0.0, 0.85, 1.0, 0.95)) -> void:
	if _message_label:
		_message_label.text = text
	if _tag_label:
		_tag_label.text = tag

	_current_accent_color = accent_color

	# Ajusta as cores neon de outline, sombra e linhas decorativas
	if _message_label:
		var outline_col := Color(accent_color.r * 0.4, accent_color.g * 0.4, accent_color.b * 0.4, 0.95)
		_message_label.add_theme_color_override("font_outline_color", outline_col)
		_message_label.add_theme_color_override("font_shadow_color", accent_color)

	if _tag_label:
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


## Inicia o piscar do botão de disparo de mísseis no Mobile
func start_mobile_missile_prompt(missile_panel: Control) -> void:
	_missile_panel_ref = missile_panel
	_is_pulsing_mobile = true
	_pulse_timer = 0.0


## Interrompe o piscar do botão de mísseis
func stop_mobile_missile_prompt() -> void:
	_is_pulsing_mobile = false
	if _mobile_hint:
		_mobile_hint.visible = false
	if _missile_panel_ref and is_instance_valid(_missile_panel_ref):
		_missile_panel_ref.modulate = Color.WHITE
		_missile_panel_ref.scale = Vector2.ONE


## Mostra mensagem de sucesso temporária com efeito elástico
func flash_completion(msg: String = "MÍSSEIS DISPARADOS // SISTEMAS DE COMBATE OPERACIONAIS") -> void:
	show_instruction(msg, "// TREINAMENTO CONCLUÍDO // BOA SORTE, PILOTO", Color(0.1, 1.4, 0.45, 1.0))
	var tree := get_tree()
	if tree:
		await tree.create_timer(2.4).timeout
	hide_instruction()
