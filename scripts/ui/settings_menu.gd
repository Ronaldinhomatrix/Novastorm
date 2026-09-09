class_name SettingsMenu
extends CanvasLayer

## Menu de opções gráficas — idêntico em PC e Mobile.
## Auto-contido: botão de engrenagem (⚙) sempre visível abre/fecha;
## ESC fecha no desktop. As escolhas persistem via UserSettings e
## re-aplicam os gráficos na hora (via sinal settings_changed).

var _panel: PanelContainer = null
var _dim: ColorRect = null
var _toggles: Dictionary = {}
var _panel_open: bool = false

## Mostra o botão de engrenagem (⚙). Desative quando o menu é aberto
## a partir do menu principal (que tem o botão "GRAPHICS SETTINGS").
@export var show_gear_button: bool = true


func _ready() -> void:
	layer = 100
	_build_ui()
	_visible_panel(false)


func _build_ui() -> void:
	# Botão de engrenagem (opcional; no menu principal o acesso é via botão próprio)
	if show_gear_button:
		var gear := Button.new()
		gear.text = "⚙"
		gear.tooltip_text = "Configurações"
		gear.anchor_left = 1.0
		gear.anchor_right = 1.0
		gear.offset_left = -60.0
		gear.offset_right = -16.0
		gear.offset_top = 16.0
		gear.offset_bottom = 56.0
		gear.pressed.connect(_toggle)
		add_child(gear)

	# Fundo escuro (dim)
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.65)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	# Centralizador
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(440.0, 0.0)
	center.add_child(_panel)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.96)
	sb.border_color = Color(0.1, 0.9, 1.0, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "CONFIGURAÇÕES GRÁFICAS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	_toggles["shadows"] = _make_toggle("Sombras", func(v): UserSettings.set_shadows(v))
	_toggles["glow"] = _make_toggle("Glow (Brilho / Bloom)", func(v): UserSettings.set_glow(v))
	_toggles["ssao"] = _make_toggle("SSAO (Oclusão de Ambiente)", func(v): UserSettings.set_ssao(v))
	_toggles["ssil"] = _make_toggle("SSIL (Luz Indireta)", func(v): UserSettings.set_ssil(v))
	for key in _toggles:
		vbox.add_child(_toggles[key])

	vbox.add_child(HSeparator.new())

	var reset_btn := Button.new()
	reset_btn.text = "Restaurar Padrão"
	reset_btn.pressed.connect(_on_reset)
	vbox.add_child(reset_btn)

	var close_btn := Button.new()
	close_btn.text = "Fechar"
	close_btn.pressed.connect(_toggle)
	vbox.add_child(close_btn)


func _make_toggle(label_text: String, callback: Callable) -> CheckButton:
	var cb := CheckButton.new()
	cb.text = label_text
	cb.toggled.connect(callback)
	return cb


func _refresh_toggles() -> void:
	_toggles["shadows"].button_pressed = UserSettings.get_shadows()
	_toggles["glow"].button_pressed = UserSettings.get_glow()
	_toggles["ssao"].button_pressed = UserSettings.get_ssao()
	_toggles["ssil"].button_pressed = UserSettings.get_ssil()


func _on_reset() -> void:
	UserSettings.reset_to_defaults()
	_refresh_toggles()


func _toggle() -> void:
	_visible_panel(not _panel_open)


## Abre o painel (usado pelo menu principal via "GRAPHICS SETTINGS").
func open() -> void:
	_visible_panel(true)


## Fecha o painel.
func close() -> void:
	_visible_panel(false)


func _visible_panel(show: bool) -> void:
	_panel_open = show
	_dim.visible = show
	_panel.visible = show
	if show:
		_refresh_toggles()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _panel_open:
		_toggle()
