class_name MainMenu
extends Control

## Tela inicial (main menu) estilo AAA — fundo espacial animado com estrelas,
## título brilhante e os botões "START GAME" e "GRAPHICS SETTINGS".

const SettingsMenuScript := preload("res://scripts/ui/settings_menu.gd")

var _settings_menu: CanvasLayer = null
var _stars: Array = []
var _bg_texture: GradientTexture2D = null
var _title: Label = null
var _time: float = 0.0
var _redraw_timer: float = 0.0

const STAR_COUNT_PC := 170
const STAR_COUNT_MOBILE := 60


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_bg_texture()
	_generate_stars()
	_build_ui()
	_setup_settings_menu()
	_start_title_animation()


func _build_bg_texture() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(0.01, 0.02, 0.06),
		Color(0.02, 0.06, 0.15),
		Color(0.0, 0.0, 0.0)
	])
	_bg_texture = GradientTexture2D.new()
	_bg_texture.gradient = grad
	_bg_texture.fill_from = Vector2(0.5, 0.0)
	_bg_texture.fill_to = Vector2(0.5, 1.0)
	_bg_texture.width = 4
	_bg_texture.height = 256


func _generate_stars() -> void:
	_stars.clear()
	for i in (STAR_COUNT_MOBILE if GameConfig.is_mobile else STAR_COUNT_PC):
		_stars.append({
			"pos": Vector2(randf(), randf()),
			"size": randf_range(0.6, 2.6),
			"speed": randf_range(0.004, 0.03),
			"brightness": randf_range(0.2, 1.0),
			"phase": randf() * TAU
		})


func _process(delta: float) -> void:
	_time += delta
	for s in _stars:
		s["pos"].y += s["speed"] * delta
		if s["pos"].y > 1.0:
			s["pos"].y = 0.0
			s["pos"].x = randf()
	if GameConfig.is_mobile:
		_redraw_timer += delta
		if _redraw_timer >= 0.033:
			_redraw_timer = 0.0
			queue_redraw()
	else:
		queue_redraw()


func _draw() -> void:
	# Fundo gradiente (espaço profundo)
	if _bg_texture:
		draw_texture_rect(_bg_texture, Rect2(Vector2.ZERO, size), false)
	# Brilho de horizonte planetário na base da tela
	var horizon_top := size.y * 0.70
	draw_rect(Rect2(0.0, horizon_top, size.x, size.y - horizon_top), Color(0.03, 0.16, 0.32, 0.30))
	draw_rect(Rect2(0.0, size.y * 0.86, size.x, size.y * 0.14), Color(0.02, 0.10, 0.22, 0.35))
	# Estrelas
	for s in _stars:
		var twinkle := 0.55 + 0.45 * sin(_time * 2.0 + s["phase"])
		var col := Color(1.0, 1.0, 1.0, s["brightness"] * twinkle)
		draw_circle(Vector2(s["pos"].x * size.x, s["pos"].y * size.y), s["size"], col)


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 22)
	center.add_child(vbox)

	# Título
	_title = Label.new()
	_title.text = tr("MENU_TITLE")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 78)
	_title.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
	_title.add_theme_color_override("font_outline_color", Color(0.0, 0.45, 0.7, 0.9))
	_title.add_theme_constant_override("outline_size", 10)
	_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.8, 1.0, 0.6))
	_title.add_theme_constant_override("shadow_offset_y", 4)
	_title.add_theme_constant_override("shadow_outline_size", 6)
	vbox.add_child(_title)

	# Subtítulo
	var subtitle := Label.new()
	subtitle.text = tr("MENU_SUBTITLE")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.8, 0.9, 0.9))
	vbox.add_child(subtitle)

	# Espaçamento
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 46.0)
	vbox.add_child(spacer)

	# Botão START GAME
	var start_btn := Button.new()
	start_btn.text = tr("MENU_START_GAME")
	start_btn.custom_minimum_size = Vector2(360.0, 66.0)
	start_btn.add_theme_font_size_override("font_size", 26)
	start_btn.pressed.connect(_on_start_game)
	_style_button(start_btn, Color(0.05, 0.55, 0.85), Color(0.08, 0.72, 1.0), Color(0.9, 1.0, 1.0))
	vbox.add_child(start_btn)

	# Botão SETTINGS
	var settings_btn := Button.new()
	settings_btn.text = tr("MENU_SETTINGS")
	settings_btn.custom_minimum_size = Vector2(360.0, 54.0)
	settings_btn.add_theme_font_size_override("font_size", 20)
	settings_btn.pressed.connect(_on_settings)
	_style_button(settings_btn, Color(0.08, 0.12, 0.18), Color(0.13, 0.20, 0.28), Color(0.75, 0.85, 0.95))
	vbox.add_child(settings_btn)

	# Versão
	var version := Label.new()
	version.text = tr("MENU_VERSION")
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_font_size_override("font_size", 14)
	version.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.8))
	vbox.add_child(version)


func _style_button(btn: Button, bg: Color, bg_hover: Color, fg: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = fg * 0.6
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(12)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg_hover
	hover.border_color = fg
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.35)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", fg)


func _setup_settings_menu() -> void:
	_settings_menu = SettingsMenuScript.new()
	_settings_menu.show_gear_button = false
	add_child(_settings_menu)


func _start_title_animation() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(_title, "modulate:a", 0.82, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_title, "modulate:a", 1.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_settings() -> void:
	if _settings_menu:
		_settings_menu.open()

