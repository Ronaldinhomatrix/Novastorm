class_name TutorialOverlay
extends Control

## Overlay do Tutorial Tático estilo AAA para Novastorm.
## Exibe banners holográficos com instruções contextuais (PC / Mobile)
## e gerencia o indicador pulsante no botão de mísseis mobile.

var _banner_container: Control = null
var _panel: PanelContainer = null
var _tag_label: Label = null
var _message_label: Label = null

var _mobile_hint: PanelContainer = null
var _mobile_hint_label: Label = null
var _is_pulsing_mobile: bool = false
var _pulse_timer: float = 0.0

var _target_alpha: float = 0.0
var _current_alpha: float = 0.0
var _hud_ref: Node = null
var _missile_panel_ref: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func _build_ui() -> void:
	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray(["Consolas", "Cascadia Code", "Courier New", "Lucida Console", "Monospace"])
	sys_font.font_weight = 800
	sys_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED

	# 1. Container Central Superior para o Banner de Instrução
	_banner_container = Control.new()
	_banner_container.name = "BannerContainer"
	_banner_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_container.anchor_left = 0.5
	_banner_container.anchor_right = 0.5
	_banner_container.offset_left = -380.0
	_banner_container.offset_right = 380.0
	_banner_container.offset_top = 180.0
	_banner_container.offset_bottom = 275.0
	_banner_container.modulate.a = 0.0
	add_child(_banner_container)

	_panel = PanelContainer.new()
	_panel.name = "TacticalPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.08, 0.90)
	sb.border_color = Color(0.0, 0.85, 1.0, 0.95)
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.shadow_color = Color(0.0, 0.6, 1.0, 0.45)
	sb.shadow_size = 14
	sb.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	_banner_container.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	_tag_label = Label.new()
	_tag_label.text = "// SISTEMA DE TREINAMENTO // CONTROLE TÁTICO"
	_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag_label.add_theme_font_override("font", sys_font)
	_tag_label.add_theme_font_size_override("font_size", 12)
	_tag_label.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0, 0.95))
	vbox.add_child(_tag_label)

	_message_label = Label.new()
	_message_label.text = ""
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_override("font", sys_font)
	_message_label.add_theme_font_size_override("font_size", 22)
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.92, 1.0))
	_message_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.7, 1.0, 0.8))
	_message_label.add_theme_constant_override("shadow_offset_y", 2)
	_message_label.add_theme_constant_override("shadow_outline_size", 4)
	vbox.add_child(_message_label)

	# 2. Balão de chamada (Hint) apontando para o botão de míssil no Mobile
	_mobile_hint = PanelContainer.new()
	_mobile_hint.name = "MobileMissileHint"
	_mobile_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_hint.anchor_top = 1.0
	_mobile_hint.anchor_bottom = 1.0
	_mobile_hint.offset_left = 265.0
	_mobile_hint.offset_right = 650.0
	_mobile_hint.offset_top = -78.0
	_mobile_hint.offset_bottom = -22.0
	_mobile_hint.visible = false

	var hint_sb := StyleBoxFlat.new()
	hint_sb.bg_color = Color(0.03, 0.04, 0.07, 0.92)
	hint_sb.border_color = Color(1.2, 0.8, 0.1, 1.0) # Âmbar/Dourado Neon
	hint_sb.set_border_width_all(2)
	hint_sb.corner_radius_top_left = 6
	hint_sb.corner_radius_top_right = 6
	hint_sb.corner_radius_bottom_left = 6
	hint_sb.corner_radius_bottom_right = 6
	hint_sb.shadow_color = Color(1.0, 0.6, 0.05, 0.5)
	hint_sb.shadow_size = 12
	hint_sb.set_content_margin_all(10)
	_mobile_hint.add_theme_stylebox_override("panel", hint_sb)
	add_child(_mobile_hint)

	_mobile_hint_label = Label.new()
	_mobile_hint_label.text = "◄ USE ESTE BOTÃO PARA DISPARAR MÍSSEIS"
	_mobile_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mobile_hint_label.add_theme_font_override("font", sys_font)
	_mobile_hint_label.add_theme_font_size_override("font_size", 14)
	_mobile_hint_label.add_theme_color_override("font_color", Color(1.3, 0.95, 0.3, 1.0))
	_mobile_hint.add_child(_mobile_hint_label)


func _process(delta: float) -> void:
	# Como o jogo pode estar em time_scale reduzido (0.2), computamos delta real
	var real_delta: float = (delta / maxf(Engine.time_scale, 0.05)) if Engine.time_scale < 0.9 else delta

	# Fade suave do banner principal
	if _banner_container:
		_current_alpha = move_toward(_current_alpha, _target_alpha, 5.0 * real_delta)
		_banner_container.modulate.a = _current_alpha
		_banner_container.visible = (_current_alpha > 0.01)

	# Efeito pulsante de piscar do botão no Mobile
	if _is_pulsing_mobile:
		_pulse_timer += real_delta * 8.0
		var wave := (sin(_pulse_timer) + 1.0) * 0.5 # 0.0 a 1.0
		if _mobile_hint:
			_mobile_hint.visible = true
			_mobile_hint.modulate = Color(1.0 + wave * 0.3, 1.0 + wave * 0.2, 0.8 + wave * 0.4, 0.85 + wave * 0.15)
		if _missile_panel_ref and is_instance_valid(_missile_panel_ref):
			# Pisca com brilho dourado e escala leve
			_missile_panel_ref.modulate = Color(1.0 + wave * 0.6, 1.0 + wave * 0.5, 0.6 + wave * 0.4, 1.0)
			_missile_panel_ref.scale = Vector2.ONE * (1.0 + wave * 0.06)
	else:
		if _mobile_hint and _mobile_hint.visible:
			_mobile_hint.visible = false
		if _missile_panel_ref and is_instance_valid(_missile_panel_ref):
			if _missile_panel_ref.scale != Vector2.ONE:
				_missile_panel_ref.scale = Vector2.ONE


## Exibe uma instrução tática no banner
func show_instruction(text: String, tag: String = "// SISTEMA DE TREINAMENTO // CONTROLE TÁTICO", border_color: Color = Color(0.0, 0.85, 1.0, 0.95)) -> void:
	if _message_label:
		_message_label.text = text
	if _tag_label:
		_tag_label.text = tag
	if _panel:
		var sb := _panel.get_theme_stylebox("panel") as StyleBoxFlat
		if sb:
			sb.border_color = border_color
			sb.shadow_color = Color(border_color.r, border_color.g, border_color.b, 0.4)
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


## Mostra mensagem de sucesso temporária
func flash_completion(msg: String = "MÍSSEIS DISPARADOS // SISTEMAS DE COMBATE PRONTOS") -> void:
	show_instruction(msg, "// TREINAMENTO CONCLUÍDO // BOA SORTE, PILOTO", Color(0.1, 1.4, 0.45, 1.0))
	var tree := get_tree()
	if tree:
		await tree.create_timer(2.2).timeout
	hide_instruction()
