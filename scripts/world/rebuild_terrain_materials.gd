extends Node

func _ready() -> void:
	rebuild_materials()

func rebuild_materials() -> void:
	print("=== Reconstruindo materiais do terreno ===")
	
	# Textura de albedo do Grand Canyon
	var albedo_tex = load("res://assets/models/levels/grand_canyon_0.jpg")
	if not albedo_tex:
		push_error("Falha ao carregar grand_canyon_0.jpg")
		return
	print("Albedo carregado:", albedo_tex.resource_path if albedo_tex else "null")
	
	# Textura normal do mountains_1 (única disponível)
	var normal_tex = load("res://assets/models/levels/mountains_1/textures/Material_25_normal.png")
	if not normal_tex:
		push_error("Falha ao carregar Material_25_normal.png")
		return
	print("Normal carregado:", normal_tex.resource_path if normal_tex else "null")
	
	# Recriar material mobile (StandardMaterial3D)
	var mobile_mat = StandardMaterial3D.new()
	mobile_mat.albedo_color = Color(1.05, 0.95, 0.88, 1.0)
	mobile_mat.albedo_texture = albedo_tex
	mobile_mat.normal_texture = normal_tex
	mobile_mat.normal_enabled = true
	mobile_mat.normal_scale = 1.2
	mobile_mat.roughness = 0.9
	mobile_mat.uv1_scale = Vector3(0.015, 0.015, 0.015)
	mobile_mat.uv1_triplanar = true
	mobile_mat.uv1_world_triplanar = true
	ResourceSaver.save(mobile_mat, "res://assets/materials/terrain_detailed_mobile.tres")
	print("Mobile material salvo.")
	
	# Recriar material PC (ShaderMaterial - usa o shader terrain_detailed_pc.gdshader)
	var pc_mat = ShaderMaterial.new()
	pc_mat.shader = load("res://assets/shaders/terrain_detailed_pc.gdshader")
	if not pc_mat.shader:
		push_error("Falha ao carregar shader terrain_detailed_pc.gdshader")
		return
	pc_mat.set_shader_parameter("albedo_texture", albedo_tex)
	pc_mat.set_shader_parameter("normal_texture", normal_tex)
	pc_mat.set_shader_parameter("uv_scale", 0.015)
	pc_mat.set_shader_parameter("triplanar_sharpness", 4.0)
	pc_mat.set_shader_parameter("normal_scale", 1.0)
	pc_mat.set_shader_parameter("flat_tint", Color(0.95, 0.85, 0.7, 1))
	pc_mat.set_shader_parameter("cliff_tint", Color(0.4, 0.38, 0.38, 1))
	pc_mat.set_shader_parameter("slope_threshold", 0.55)
	pc_mat.set_shader_parameter("slope_blend_smoothness", 0.2)
	pc_mat.set_shader_parameter("flat_roughness", 0.9)
	pc_mat.set_shader_parameter("cliff_roughness", 0.98)
	pc_mat.set_shader_parameter("macro_noise_scale", 0.0008)
	pc_mat.set_shader_parameter("macro_noise_strength", 0.5)
	pc_mat.set_shader_parameter("strata_red_clay", Color(1.05, 0.75, 0.6, 1))
	pc_mat.set_shader_parameter("strata_cool_slate", Color(0.7, 0.78, 0.9, 1))
	pc_mat.set_shader_parameter("height_min", 100.0)
	pc_mat.set_shader_parameter("height_max", 1600.0)
	pc_mat.set_shader_parameter("height_blend_strength", 0.25)
	pc_mat.set_shader_parameter("valley_tint", Color(0.85, 0.82, 0.78, 1))
	pc_mat.set_shader_parameter("peak_tint", Color(1, 0.98, 0.95, 1))
	pc_mat.set_shader_parameter("micro_detail_strength", 0.02)
	ResourceSaver.save(pc_mat, "res://assets/materials/terrain_detailed_pc.tres")
	print("PC material salvo.")
	
	print("=== Materiais reconstruídos ===")
