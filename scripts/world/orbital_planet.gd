class_name OrbitalPlanet
extends Node3D

## Controlador do Planeta Orbital e da Atmosfera de Alta Performance.
## Gerencia rotação axial suave do planeta, sincronização com a direção solar
## e posicionamento relativo à câmera para manter o horizonte curvo sempre visível.

@export_category("Rotação Planetária")
## Velocidade de rotação axial em radianos por segundo (movimento orbital lento e majestoso).
@export var rotation_speed: float = 0.003

@export_category("Iluminação e Atmosfera")
@export var sun_node_path: NodePath = ^"../DirectionalLight3D"
@export var planet_mesh: MeshInstance3D = null

@export_category("Enquadramento Orbital (Parallax)")
## Se ativo, o centro do planeta acompanha a câmera para manter o horizonte distante e estável.
@export var follow_camera_xz: bool = true
## Fator de parallax horizontal (1.0 = move 100% com a câmera, infinito distante).
@export_range(0.0, 1.0) var parallax_weight: float = 1.0
## Se ativo, acompanha o Y da câmera para que subir/descer na nave não mude a altitude relativa ao planeta.
@export var follow_camera_y: bool = true
## Fator de parallax vertical (1.0 = fixa a distância vertical perfeita da órbita, eliminando a sensação de "chegar perto").
@export_range(0.0, 1.0) var parallax_weight_y: float = 1.0
## Altitude base da superfície do planeta abaixo da zona de voo.
@export var planet_center_y: float = -450.0

@export_category("Textura do Planeta")
## Textura de alta fidelidade e ultra-leveza (2048x1024 WebP - apenas 469 KB).
@export var default_planet_texture: Texture2D = preload("res://assets/textures/orbital_planet_albedo_2k.webp")

@export_category("Comparação de Texturas (Debug / Comparador)")
## Permite alternar entre 2K e 1K em tempo real com a tecla F7.
@export var enable_texture_toggle: bool = true
@export var texture_2k: Texture2D = preload("res://assets/textures/orbital_planet_albedo_2k.webp")
@export var texture_1k: Texture2D = preload("res://assets/textures/orbital_planet_albedo_1k.png")

var _sun_light: DirectionalLight3D = null
var _camera: Camera3D = null
var _initial_pos_xz: Vector2 = Vector2.ZERO
var _is_2k_active: bool = true
var _debug_label: Label = null


func _ready() -> void:
	_initial_pos_xz = Vector2(global_position.x, global_position.z)
	
	if has_node(sun_node_path):
		_sun_light = get_node_or_null(sun_node_path) as DirectionalLight3D
	elif get_parent():
		_sun_light = get_parent().get_node_or_null("DirectionalLight3D") as DirectionalLight3D

	if not planet_mesh:
		planet_mesh = get_node_or_null("PlanetSurface") as MeshInstance3D

	_update_atmosphere_sun_direction()
	_setup_platform_filtering()
	_setup_comparison_ui()


func _setup_comparison_ui() -> void:
	if not enable_texture_toggle:
		return
	var canvas := CanvasLayer.new()
	canvas.name = "TextureCompareCanvas"
	canvas.layer = 120
	add_child(canvas)

	_debug_label = Label.new()
	_debug_label.position = Vector2(24, 24)
	_debug_label.add_theme_font_size_override("font_size", 16)
	_debug_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4, 1.0))
	_debug_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_debug_label.add_theme_constant_override("outline_size", 4)
	canvas.add_child(_debug_label)
	_update_ui_text()


func _update_ui_text() -> void:
	if not _debug_label:
		return
	var mode_str := "2K Ultra-Light WebP (2048x1024 - 469 KB)" if _is_2k_active else "1K Standard (1024x512 - 508 KB)"
	_debug_label.text = "[F7] Textura Atual: " + mode_str + "\n(Pressione F7 para alternar 2K vs 1K)"


func _unhandled_input(event: InputEvent) -> void:
	if not enable_texture_toggle:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F7:
			_toggle_planet_texture()


func _toggle_planet_texture() -> void:
	_is_2k_active = not _is_2k_active
	if not planet_mesh:
		return
	var mat := planet_mesh.get_active_material(0) as ShaderMaterial
	if mat:
		var target_tex := texture_2k if _is_2k_active else texture_1k
		mat.set_shader_parameter("planet_texture", target_tex)
	_update_ui_text()
	var mode_name := "2K WebP" if _is_2k_active else "1K"
	print("[TextureCompare] Alternado para: ", mode_name)


func _setup_platform_filtering() -> void:
	if not planet_mesh:
		return
	var mat := planet_mesh.get_active_material(0) as ShaderMaterial
	if mat:
		var is_mobile := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
		mat.set_shader_parameter("use_smooth_sampling", not is_mobile)
		mat.set_shader_parameter("enable_procedural_detail", not is_mobile)


func _process(delta: float) -> void:
	if rotation_speed != 0.0:
		rotate_y(rotation_speed * delta)

	if follow_camera_xz or follow_camera_y:
		_process_camera_tracking()


func _process_camera_tracking() -> void:
	if not _camera:
		var vp := get_viewport()
		if vp:
			_camera = vp.get_camera_3d()
	
	if _camera:
		var cam_pos := _camera.global_position
		if follow_camera_xz:
			global_position.x = _initial_pos_xz.x + cam_pos.x * parallax_weight
			global_position.z = _initial_pos_xz.y + cam_pos.z * parallax_weight
		if follow_camera_y:
			global_position.y = planet_center_y + cam_pos.y * parallax_weight_y
		else:
			global_position.y = planet_center_y


func _update_atmosphere_sun_direction() -> void:
	if not planet_mesh:
		return
	
	var mat := planet_mesh.get_active_material(0) as ShaderMaterial
	if mat and _sun_light:
		var sun_dir := _sun_light.global_transform.basis.z.normalized()
		mat.set_shader_parameter("sun_direction", sun_dir)
