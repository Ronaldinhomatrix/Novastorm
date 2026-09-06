@tool
class_name CanyonMeshGenerator
extends MeshInstance3D

## Gerador Procedural de Cânions e Túneis Orgânicos
## Cria paredes rochosas realistas ao longo de um Path3D usando ruído 3D Simplex
## evitando a aparência "quadrada" ou poligonal rígida.

enum GenerationMode {
	OPEN_CANYON,   ## Cânion em formato de U aberto com penhascos altos e céu aberto
	CLOSED_TUNNEL, ## Caverna / túnel 360 fechado com teto rochoso
	HYBRID_VALLEY  ## Cânion aberto que se fecha em túnel no trecho intermediário
}

@export_group("Path & Mesh References")
@export var path_node: Path3D
@export var terrain_material: Material
@export var mobile_material: Material = preload("res://assets/materials/terrain_detailed_mobile.tres")
@export var auto_generate_on_ready: bool = true
@export var generate_collision: bool = true

@export_group("Geometry Settings")
## Distância entre cada anel ao longo da curva (em metros)
@export_range(4.0, 30.0, 1.0) var step_length: float = 8.0
## Quantidade de vértices no perfil transversal (quanto maior, mais suave e menos quadrado)
@export_range(15, 45, 1) var profile_segments: int = 25
## Largura média da passagem (metros)
@export_range(30.0, 400.0, 1.0) var base_width: float = 160.0
## Altura das paredes do cânion (metros)
@export_range(20.0, 300.0, 1.0) var wall_height: float = 160.0
## Profundidade do chão abaixo da linha de voo
@export_range(5.0, 100.0, 1.0) var floor_depth: float = 35.0

## Modo de geração do relevo
@export var mode: GenerationMode = GenerationMode.OPEN_CANYON

@export_group("Organic Noise Settings")
## Intensidade das saliências e penhascos de rocha
@export_range(0.0, 40.0, 0.5) var noise_displacement: float = 18.0
## Frequência do ruído 3D (valores menores criam elevações mais suaves e amplas)
@export_range(0.005, 0.1, 0.005) var noise_frequency: float = 0.02
## Escala secundária para relevo fino
@export_range(0.0, 10.0, 0.2) var detail_noise_displacement: float = 4.5

@export_group("Actions")
@export var regenerate: bool = false:
	set(val):
		if val:
			generate_canyon_mesh()

var _noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _static_body: StaticBody3D
var _collision_shape: CollisionShape3D

func _ready() -> void:
	_init_noise()
	_apply_platform_material()
	
	if auto_generate_on_ready or Engine.is_editor_hint():
		if path_node == null:
			if get_parent() is Path3D:
				path_node = get_parent() as Path3D
			elif get_parent() and get_parent().has_node("FlightPath"):
				path_node = get_parent().get_node("FlightPath") as Path3D
		
		if path_node and path_node.curve:
			generate_canyon_mesh()

func _apply_platform_material() -> void:
	var is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	var base_mat: Material = null
	
	if is_mobile and mobile_material:
		base_mat = mobile_material
	elif terrain_material:
		base_mat = terrain_material
	else:
		base_mat = load("res://assets/materials/terrain_detailed.tres")
		
	if base_mat:
		# Duplica para configurar renderização suave sem culling de faces traseiras
		var mat = base_mat.duplicate()
		if mat is StandardMaterial3D:
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_override = mat

func _init_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = 1337
	_noise.frequency = noise_frequency
	_noise.fractal_octaves = 4
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.5
	
	_detail_noise = FastNoiseLite.new()
	_detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_detail_noise.seed = 4242
	_detail_noise.frequency = noise_frequency * 3.5
	_detail_noise.fractal_octaves = 2

## Gera a malha 3D completa ao longo de toda a extensão do Path3D
func generate_canyon_mesh() -> void:
	if not path_node or not path_node.curve:
		push_warning("CanyonMeshGenerator: Path3D ou Curve3D não atribuído.")
		return
		
	_init_noise()
	var curve: Curve3D = path_node.curve
	var total_length = curve.get_baked_length()
	if total_length < 10.0:
		return

	var num_steps = int(ceil(total_length / step_length))
	if num_steps < 2:
		return

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)

	var ring_vertex_indices: Array[PackedInt32Array] = []
	var vertex_counter: int = 0

	# Parallel transport frame para rotação suave e sem torção
	var last_forward = Vector3.FORWARD
	var last_up = Vector3.UP

	for step in range(num_steps + 1):
		var offset = min(step * step_length, total_length)
		var t = curve.sample_baked_with_rotation(offset, true, true)
		var center = t.origin
		var forward = -t.basis.z.normalized()
		var up = t.basis.y.normalized()
		var right = t.basis.x.normalized()
		
		# Estabilização de orientação da curva
		if step == 0:
			last_forward = forward
			last_up = up
		else:
			var dot = forward.dot(last_forward)
			if dot < 0.9999 and dot > -0.9999:
				var axis = last_forward.cross(forward).normalized()
				var angle = acos(clamp(dot, -1.0, 1.0))
				last_up = last_up.rotated(axis, angle)
			up = (last_up - forward * last_up.dot(forward)).normalized()
			right = forward.cross(up).normalized()
			last_forward = forward
			last_up = up

		var progress_ratio = offset / total_length
		var is_tunnel = (mode == GenerationMode.CLOSED_TUNNEL) or (mode == GenerationMode.HYBRID_VALLEY and progress_ratio > 0.35 and progress_ratio < 0.65)

		var current_ring = PackedInt32Array()
		var v_coord = offset * 0.03

		for i in range(profile_segments):
			var u_factor: float
			var local_dir: Vector2

			if is_tunnel:
				# Perfil circular/elíptico orgânico fechado
				var angle = (float(i) / float(profile_segments)) * TAU
				var rad_x = base_width * 0.45
				var rad_y = wall_height * 0.4
				var y_squash = 1.1 if sin(angle) > 0.0 else 0.75
				local_dir = Vector2(cos(angle) * rad_x, sin(angle) * rad_y * y_squash)
				u_factor = float(i) / float(profile_segments)
			else:
				# Perfil U-shape orgânico de cânion aberto (sem teto!)
				u_factor = float(i) / float(profile_segments - 1)
				var s = (u_factor - 0.5) * 2.0 # -1.0 a +1.0
				var abs_s = abs(s)
				var px = 0.0
				var py = 0.0

				if abs_s < 0.35:
					# Chão do cânion com leve concavidade natural
					var floor_ratio = abs_s / 0.35
					px = s * (base_width * 0.7)
					py = -floor_depth + (floor_ratio * floor_ratio * 3.0)
				elif abs_s < 0.8:
					# Paredes íngremes do cânion subindo
					var t_wall = (abs_s - 0.35) / 0.45
					px = sign(s) * (base_width * 0.35 + t_wall * base_width * 0.25)
					py = -floor_depth + 3.0 + pow(t_wall, 0.8) * wall_height
				else:
					# Bordas superiores / planaltos do cânion
					var t_rim = (abs_s - 0.8) / 0.2
					px = sign(s) * (base_width * 0.6 + t_rim * base_width * 0.6)
					py = (-floor_depth + 3.0 + wall_height) - t_rim * 6.0

				local_dir = Vector2(px, py)

			# Posição básica no espaço global
			var point_on_slice = center + (right * local_dir.x) + (up * local_dir.y)

			# Amostragem de ruído tridimensional
			var n1 = _noise.get_noise_3dv(point_on_slice)
			var n2 = _detail_noise.get_noise_3dv(point_on_slice)
			var total_displacement = (n1 * noise_displacement) + (n2 * detail_noise_displacement)

			# Se for as bordas externas do chão, suaviza o ruído para a nave não colidir no início
			var radial_normal = (right * local_dir.normalized().x + up * local_dir.normalized().y).normalized()
			var displaced_pos = point_on_slice + (radial_normal * total_displacement)

			var local_pos = to_local(displaced_pos)
			st.set_uv(Vector2(u_factor * 4.0, v_coord))
			st.add_vertex(local_pos)

			current_ring.append(vertex_counter)
			vertex_counter += 1

		ring_vertex_indices.append(current_ring)

	# Criação da malha conectando os anéis
	var num_rings = ring_vertex_indices.size()
	for r in range(num_rings - 1):
		var ring_a = ring_vertex_indices[r]
		var ring_b = ring_vertex_indices[r + 1]
		var progress = float(r) / float(num_rings - 1)
		var is_tunnel_sec = (mode == GenerationMode.CLOSED_TUNNEL) or (mode == GenerationMode.HYBRID_VALLEY and progress > 0.35 and progress < 0.65)

		var max_i = profile_segments if is_tunnel_sec else (profile_segments - 1)

		for i in range(max_i):
			var next_i = (i + 1) % profile_segments

			var v0 = ring_a[i]
			var v1 = ring_b[i]
			var v2 = ring_b[next_i]
			var v3 = ring_a[next_i]

			# Triângulo 1
			st.add_index(v0)
			st.add_index(v1)
			st.add_index(v2)

			# Triângulo 2
			st.add_index(v0)
			st.add_index(v2)
			st.add_index(v3)

	st.generate_normals()
	st.generate_tangents()

	var new_mesh = st.commit()
	mesh = new_mesh
	_apply_platform_material()

	if generate_collision and not Engine.is_editor_hint():
		_update_collision(new_mesh)

func _update_collision(built_mesh: ArrayMesh) -> void:
	if not _static_body:
		_static_body = StaticBody3D.new()
		_static_body.name = "CanyonCollision"
		add_child(_static_body)
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "Shape"
		_static_body.add_child(_collision_shape)

	var shape = built_mesh.create_trimesh_shape()
	_collision_shape.shape = shape
