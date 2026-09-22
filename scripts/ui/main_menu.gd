class_name MainMenu
extends Control

## Tela inicial Pterodon — visual AAA Sci-Fi Espacial Escuro:
## • Fundo preto espacial profundo (deep space) com gradiente cósmico
## • Nebulosas sutis em tons violeta e azul profundo
## • Arco planetário escuro com limbo luminoso ciano pulsante na base
## • Campo estelar cintilante com glints em cruz e estrelas cadentes
## • Título brilhante com brilho neon ciano e sombra profunda
## • Botões sci-fi translúcidos com bordas ciano e hover iluminado
## • Logo Nivora Games sutil no canto inferior direito
## • Transição fade-to-black cinematográfica ao iniciar

const SettingsMenuScript := preload("res://scripts/ui/settings_menu.gd")
const LOGO_PATH       := "res://assets/Nivora_logo.png"

var _settings_menu: CanvasLayer = null
var _title: Label         = null
var _sub_line: ColorRect  = null
var _buttons_root: Control = null
var _bg_texture: GradientTexture2D = null
var _time: float  = 0.0
var _redraw_timer: float = 0.0

var _stars: Array = []
var _star_palette: Array = []
var _shooting_stars: Array = []
var _next_shoot: float = 2.0

const STAR_COUNT_PC     := 140
const STAR_COUNT_MOBILE := 50


## Duração do fade-in lento da tela inicial (segundos).
@export var main_menu_fade_in_duration: float = 8.0

## Overlay temporário que faz o fade-in lento cobrir toda a tela em _ready().
var _startup_overlay: ColorRect = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_bg_texture()
	_star_palette = [
		Color(1.0, 1.0, 1.0),
		Color(0.85, 0.93, 1.0),
		Color(0.65, 0.85, 1.0),
		Color(1.0, 0.94, 0.80),
		Color(0.70, 0.90, 1.0),
	]
	_generate_stars()
	_build_ui()
	_setup_settings_menu()
	_startup_overlay = _make_full_fade_overlay()
	_start_animations()
	_start_fade_in()


func _build_bg_texture() -> void:
	# Gradiente de espaço profundo estritamente escuro
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 0.80, 1.0])
	grad.colors = PackedColorArray([
		Color(0.008, 0.012, 0.030),  # Azul noite profundo
		Color(0.015, 0.024, 0.055),  # Azul cósmico suave
		Color(0.006, 0.010, 0.022),  # Índigo escuro
		Color(0.002, 0.003, 0.008)   # Quase negro na base
	])
	_bg_texture = GradientTexture2D.new()
	_bg_texture.gradient = grad
	_bg_texture.fill_from = Vector2(0.5, 0.0)
	_bg_texture.fill_to = Vector2(0.5, 1.0)
	_bg_texture.width = 16
	_bg_texture.height = 256


func _generate_stars() -> void:
	_stars.clear()
	var count := STAR_COUNT_MOBILE if GameConfig.is_mobile else STAR_COUNT_PC
	for _i in count:
		var b := randf_range(0.25, 1.0)
		_stars.append({
			"pos":   Vector2(randf(), randf()),
			"size":  randf_range(0.7, 2.5),
			"speed": randf_range(0.004, 0.025),
			"brightness": b,
			"phase": randf() * TAU,
			"tint":  randi_range(0, _star_palette.size() - 1),
			"glint": b > 0.80 and randf() > 0.45,
		})


func _process(delta: float) -> void:
	_time += delta
	for s in _stars:
		var p: Vector2 = s["pos"]
		p.y += float(s["speed"]) * delta
		if p.y > 1.0:
			p.y = 0.0
			p.x = randf()
		s["pos"] = p
	_update_shooting_stars(delta)
	if GameConfig.is_mobile:
		_redraw_timer += delta
		if _redraw_timer >= 0.033:
			_redraw_timer = 0.0
			queue_redraw()
	else:
		queue_redraw()


func _draw() -> void:
	var sz := size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return

	# 1 ── Fundo espacial escuro garantido
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.005, 0.008, 0.016))
	if _bg_texture:
		draw_texture_rect(_bg_texture, Rect2(Vector2.ZERO, sz), false)

	# 2 ── Nebulosas coloridas difusas suaves (sem esbranquiçar)
	_draw_nebulae(sz)

	# 3 ── Planeta em arco na base (corpo escuro + limbo ciano iluminado)
	_draw_planet(sz)

	# 4 ── Campo estelar nítido
	for s in _stars:
		var twinkle: float = 0.55 + 0.45 * sin(_time * 2.2 + float(s["phase"]))
		var alpha: float = float(s["brightness"]) * twinkle
		var tint: Color  = _star_palette[int(s["tint"])]
		var pos: Vector2 = Vector2(float(s["pos"].x) * sz.x, float(s["pos"].y) * sz.y)
		draw_circle(pos, float(s["size"]), Color(tint.r, tint.g, tint.b, alpha))
		if bool(s["glint"]) and alpha > 0.82:
			var g: float = float(s["size"]) * 3.4
			var gc: Color = Color(1.0, 1.0, 1.0, (alpha - 0.82) * 1.5)
			draw_line(pos - Vector2(g, 0), pos + Vector2(g, 0), gc, 1.0)
			draw_line(pos - Vector2(0, g), pos + Vector2(0, g), gc, 1.0)

	# 5 ── Estrelas cadentes
	_draw_shooting_stars()

	# 6 ── Vinheta sutil para escurecer as bordas
	_draw_vignette(sz)


func _draw_vignette(sz: Vector2) -> void:
	var d := minf(sz.x, sz.y) * 0.28
	for i in 5:
		var a: float = 0.22 * (1.0 - float(i) / 5.0)
		draw_rect(Rect2(0, float(i) * d / 5.0, sz.x, d / 5.0), Color(0, 0, 0, a))
	for i in 5:
		var a: float = 0.30 * (1.0 - float(i) / 5.0)
		draw_rect(Rect2(0, sz.y - float(i + 1) * d / 5.0, sz.x, d / 5.0), Color(0, 0, 0, a))
	for i in 4:
		var a: float = 0.18 * (1.0 - float(i) / 4.0)
		draw_rect(Rect2(float(i) * d / 8.0, 0, d / 8.0, sz.y), Color(0, 0, 0, a))
		draw_rect(Rect2(sz.x - float(i + 1) * d / 8.0, 0, d / 8.0, sz.y), Color(0, 0, 0, a))


func _draw_nebulae(sz: Vector2) -> void:
	# Nebulosas cósmicas escuras e ricas
	_draw_glow(Vector2(sz.x * 0.16, sz.y * 0.26), sz.y * 0.22, Color(0.35, 0.12, 0.65, 0.045))
	_draw_glow(Vector2(sz.x * 0.60, sz.y * 0.14), sz.y * 0.20, Color(0.06, 0.32, 0.70, 0.050))
	_draw_glow(Vector2(sz.x * 0.84, sz.y * 0.35), sz.y * 0.18, Color(0.55, 0.22, 0.10, 0.035))
	_draw_glow(Vector2(sz.x * 0.50, sz.y * 0.80), sz.y * 0.30, Color(0.03, 0.20, 0.45, 0.055))


func _draw_glow(center: Vector2, radius: float, col: Color) -> void:
	var drift: float = sin(_time * 0.09 + center.x * 0.001) * radius * 0.15
	var c := center + Vector2(drift, 0)
	for i in 6:
		var rr: float = radius * (1.0 - float(i) * 0.14)
		var aa: float = col.a * (0.25 + float(i) * 0.13)
		draw_circle(c, rr, Color(col.r, col.g, col.b, aa))


func _draw_planet(sz: Vector2) -> void:
	var cx: float = sz.x * 0.50
	var cy: float = (sz.y * 1.34) if GameConfig.is_mobile else (sz.y * 1.40)
	var r: float  = (sz.y * 0.78) if GameConfig.is_mobile else (sz.y * 0.72)

	# Corpo do planeta (espaço ocupado em azul-marinho muito escuro)
	draw_circle(Vector2(cx, cy), r, Color(0.008, 0.015, 0.035, 0.92))

	# Halos de atmosfera no topo do arco
	for i in 6:
		var rr: float = r + 4.0 + float(i) * 12.0
		var halo_a: float = (0.04 - float(i) * 0.006)
		if halo_a > 0.0:
			draw_arc(Vector2(cx, cy), rr, PI * 1.05, PI * 1.95, 72,
				Color(0.08, 0.45, 0.90, halo_a), 10.0, true)

	# Limbo luminoso (borda brilhante do planeta)
	var limbo_pulse: float = 0.45 + 0.12 * sin(_time * 0.80)
	draw_arc(Vector2(cx, cy), r, PI * 1.06, PI * 1.94, 96,
		Color(0.35, 0.88, 1.0, limbo_pulse), 2.8, true)
	draw_arc(Vector2(cx, cy), r - 2.0, PI * 1.07, PI * 1.93, 80,
		Color(0.12, 0.50, 0.95, 0.35), 4.0, true)


func _update_shooting_stars(delta: float) -> void:
	_next_shoot -= delta
	if _next_shoot <= 0.0 and _shooting_stars.size() < 3:
		_next_shoot = randf_range(3.0, 6.5)
		var life := randf_range(0.5, 0.9)
		_shooting_stars.append({
			"pos":      Vector2(randf_range(0.05, 0.92) * size.x, randf_range(-0.15, 0.20) * size.y),
			"vel":      Vector2(randf_range(280.0, 500.0), randf_range(150.0, 300.0)),
			"life":     life,
			"max_life": life,
		})
	var i := _shooting_stars.size() - 1
	while i >= 0:
		var s = _shooting_stars[i]
		var cur_pos: Vector2 = s["pos"]
		var cur_vel: Vector2 = s["vel"]
		s["pos"] = cur_pos + cur_vel * delta
		var cur_life: float = float(s["life"]) - delta
		s["life"] = cur_life
		if cur_life <= 0.0:
			_shooting_stars.remove_at(i)
		i -= 1


func _draw_shooting_stars() -> void:
	for s in _shooting_stars:
		var max_l: float = float(s["max_life"])
		var cur_l: float = float(s["life"])
		var t: float = 1.0 - (cur_l / max_l if max_l > 0.0 else 0.0)
		var head: Vector2 = s["pos"]
		var vel: Vector2 = s["vel"]
		var tail: Vector2 = head - vel * 0.15
		var a: float = clampf(1.0 - t * 1.5, 0.0, 1.0) * 0.95
		draw_line(tail, head, Color(0.85, 0.95, 1.0, a * 0.70), 1.6)
		draw_circle(head, 2.4, Color(1.0, 1.0, 1.0, a))

func _make_full_fade_overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 1.0)
	overlay.z_index = 200
	add_child(overlay)
	return overlay


func _start_fade_in() -> void:
	if not _startup_overlay:
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_startup_overlay, "color:a", 0.0, main_menu_fade_in_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		_startup_overlay.queue_free()
		_startup_overlay = null
	)

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 0)
	var vbox_w: float = 960.0 if GameConfig.is_mobile else 460.0
	vbox.custom_minimum_size = Vector2(vbox_w, 0)
	center.add_child(vbox)

	# Título com alto contraste luminoso no fundo escuro
	_title = Label.new()
	_title.text = tr("MENU_TITLE")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title_size: int = 140 if GameConfig.is_mobile else 84
	_title.add_theme_font_size_override("font_size", title_size)
	_title.add_theme_color_override("font_color",         Color(0.40, 0.95, 1.00))
	_title.add_theme_color_override("font_outline_color", Color(0.00, 0.35, 0.75, 1.0))
	_title.add_theme_constant_override("outline_size",    22 if GameConfig.is_mobile else 14)
	_title.add_theme_color_override("font_shadow_color",  Color(0.00, 0.65, 1.00, 0.85))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 6 if GameConfig.is_mobile else 4)
	_title.add_theme_constant_override("shadow_outline_size", 14 if GameConfig.is_mobile else 10)
	vbox.add_child(_title)

	var subtitle := Label.new()
	subtitle.text = tr("MENU_SUBTITLE")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub_size: int = 34 if GameConfig.is_mobile else 18
	subtitle.add_theme_font_size_override("font_size", sub_size)
	subtitle.add_theme_color_override("font_color", Color(0.60, 0.82, 0.96, 0.90))
	vbox.add_child(subtitle)

	var line_margin := MarginContainer.new()
	line_margin.add_theme_constant_override("margin_top",    26 if GameConfig.is_mobile else 18)
	line_margin.add_theme_constant_override("margin_bottom", 36 if GameConfig.is_mobile else 26)
	vbox.add_child(line_margin)

	_sub_line = ColorRect.new()
	_sub_line.custom_minimum_size = Vector2(920 if GameConfig.is_mobile else 440, 4 if GameConfig.is_mobile else 2)
	_sub_line.color = Color(0.30, 0.88, 1.0, 0.75)
	line_margin.add_child(_sub_line)

	_buttons_root = VBoxContainer.new()
	_buttons_root.add_theme_constant_override("separation", 28 if GameConfig.is_mobile else 16)
	_buttons_root.modulate.a = 0.0
	vbox.add_child(_buttons_root)

	# Botão START GAME vibrante
	var start_btn := _make_button(tr("MENU_START_GAME"), 26, true, _on_start_game)
	_buttons_root.add_child(start_btn)

	# Botão SETTINGS elegante
	var settings_btn := _make_button(tr("MENU_SETTINGS"), 20, false, _on_settings)
	_buttons_root.add_child(settings_btn)

	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 32 if GameConfig.is_mobile else 18)
	_buttons_root.add_child(sp2)

	var version := Label.new()
	version.text = tr("MENU_VERSION")
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_font_size_override("font_size", 20 if GameConfig.is_mobile else 13)
	version.add_theme_color_override("font_color", Color(0.40, 0.52, 0.68, 0.80))
	_buttons_root.add_child(version)

	_build_logo()


func _build_logo() -> void:
	var logo_tex: Texture2D = load(LOGO_PATH)
	if not logo_tex:
		return
	var logo := TextureRect.new()
	logo.texture = logo_tex
	logo.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	logo.offset_left   = -170.0 if GameConfig.is_mobile else -130.0
	logo.offset_top    = -140.0 if GameConfig.is_mobile else -110.0
	logo.offset_right  = -24.0
	logo.offset_bottom = -24.0
	logo.expand_mode   = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	logo.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.modulate      = Color(1, 1, 1, 0.60)
	add_child(logo)


func _make_button(label: String, font_size: int, primary: bool, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	var btn_w: float = 920.0 if GameConfig.is_mobile else 440.0
	var btn_h: float = (122.0 if primary else 100.0) if GameConfig.is_mobile else (66.0 if primary else 54.0)
	btn.custom_minimum_size = Vector2(btn_w, btn_h)
	var final_font_size: int = (46 if primary else 36) if GameConfig.is_mobile else font_size
	btn.add_theme_font_size_override("font_size", final_font_size)
	btn.pressed.connect(cb)
	_style_button_glass(btn, primary)
	return btn


func _style_button_glass(btn: Button, primary: bool) -> void:
	var bg_col: Color  = Color(0.04, 0.28, 0.60, 0.70) if primary else Color(0.03, 0.08, 0.16, 0.75)
	var hov_col: Color = Color(0.08, 0.44, 0.85, 0.90) if primary else Color(0.06, 0.16, 0.32, 0.90)
	var bdr_col: Color = Color(0.40, 0.90, 1.00, 0.85) if primary else Color(0.25, 0.50, 0.75, 0.65)
	var txt_col: Color = Color(0.92, 1.00, 1.00)        if primary else Color(0.75, 0.88, 0.98)

	var s := StyleBoxFlat.new()
	s.bg_color = bg_col
	s.border_color = bdr_col
	s.set_border_width_all(4 if (primary and GameConfig.is_mobile) else (2 if primary else 1))
	s.border_width_top = 5 if (primary and GameConfig.is_mobile) else (3 if primary else 2)
	s.set_corner_radius_all(18 if GameConfig.is_mobile else 10)
	s.set_content_margin_all(24 if GameConfig.is_mobile else 14)
	s.shadow_color = Color(0.0, 0.5, 0.9, 0.40 if primary else 0.20)
	s.shadow_size = 16 if (primary and GameConfig.is_mobile) else (8 if primary else 4)

	var h := s.duplicate() as StyleBoxFlat
	h.bg_color = hov_col
	h.border_color = Color(0.70, 0.98, 1.00, 1.00) if primary else Color(0.55, 0.80, 1.00, 0.90)
	h.set_border_width_all(3 if primary else 2)
	h.shadow_size = 14 if primary else 8

	var p := s.duplicate() as StyleBoxFlat
	p.bg_color = bg_col.darkened(0.40)

	btn.add_theme_stylebox_override("normal",  s)
	btn.add_theme_stylebox_override("hover",   h)
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_color_override("font_color",         txt_col)
	btn.add_theme_color_override("font_hover_color",   Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", txt_col.darkened(0.15))
	btn.add_theme_color_override("font_outline_color", Color(0, 0.35, 0.65, 0.90))
	btn.add_theme_constant_override("outline_size", 3 if primary else 0)


func _setup_settings_menu() -> void:
	_settings_menu = SettingsMenuScript.new()
	_settings_menu.show_gear_button = false
	add_child(_settings_menu)


func _start_animations() -> void:
	var tw_title := create_tween().set_loops()
	tw_title.tween_property(_title, "modulate:a", 0.85, 1.80) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw_title.tween_property(_title, "modulate:a", 1.0, 1.80) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var tw_line := create_tween().set_loops()
	tw_line.tween_property(_sub_line, "modulate:a", 0.45, 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw_line.tween_property(_sub_line, "modulate:a", 1.00, 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_buttons_root.modulate.a = 0.0
	var tw_btn := create_tween()
	tw_btn.tween_interval(0.35)
	tw_btn.tween_property(_buttons_root, "modulate:a", 1.0, 0.65) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_start_game() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 100
	add_child(overlay)
	var tw := create_tween()
	tw.tween_property(overlay, "color", Color(0, 0, 0, 1), 0.40) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/game.tscn"))


func _on_settings() -> void:
	if _settings_menu:
		_settings_menu.open()
