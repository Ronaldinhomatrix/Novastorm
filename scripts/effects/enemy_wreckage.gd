class_name EnemyWreckage
extends Node3D

## Efeito de desmonte do asset 3D real do inimigo em 3 partes autênticas:
##   - Asa/Flanco Esquerdo (com turbina e textura original da nave)
##   - Fuselagem Central / Cockpit (com vidro da cabine, bico e casco original)
##   - Asa/Flanco Direito (com turbina e textura original da nave)
##
## Preserva 100% dos materiais PBR, texturas, emissões e detalhes do modelo 3D GLB,
## mantendo o momento inercial do vôo e adicionando trilhas de combustão em cada fragmento.

# Cache global de dados de fragmentos por tipo de nave para performance máxima (60+ FPS constante)
static var _wreckage_cache: Dictionary = {}

@export var lifetime: float = 2.2
@export var explosion_force: float = 1.0
@export var inherited_velocity: Vector3 = Vector3.ZERO

var _pieces: Array[Dictionary] = []
var _age: float = 0.0


## Cria e instancia os destroços a partir de um inimigo no momento da destruição
static func spawn_from_enemy(enemy: Node3D, force_mult: float = 1.0, vel: Vector3 = Vector3.ZERO) -> Node3D:
	if not enemy or not is_instance_valid(enemy):
		return null
		
	var parent: Node = null
	if enemy.get_tree() and enemy.get_tree().current_scene:
		parent = enemy.get_tree().current_scene
	elif enemy.get_parent():
		parent = enemy.get_parent()
	elif enemy.get_tree() and enemy.get_tree().root:
		parent = enemy.get_tree().root

	if not parent:
		return null

	var wreckage_script: GDScript = load("res://scripts/effects/enemy_wreckage.gd") as GDScript
	var wreckage: Node3D = wreckage_script.new() as Node3D
	wreckage.set("explosion_force", force_mult)

	# Se vel não foi informada ou é muito baixa, calcula a velocidade estimada a partir do forward da nave
	if vel.length_squared() < 10.0:
		var speed: float = 65.0
		if enemy.has_method("_get_path_follower"):
			var pf = enemy.call("_get_path_follower")
			if pf and pf.has_method("_current_speed"):
				speed = pf.call("_current_speed")
		vel = -enemy.global_basis.z.normalized() * speed

	wreckage.set("inherited_velocity", vel)
	parent.add_child(wreckage)
	# O wreckage fica no espaço mundial (Transform3D.IDENTITY) e cada pedaço recebe sua posição global exata
	wreckage.global_transform = Transform3D.IDENTITY
	wreckage.call("_build_from_enemy", enemy)
	return wreckage


func _build_from_enemy(enemy: Node3D) -> void:
	var ship_key: String = ""
	if "target_ship_node_name" in enemy and enemy.target_ship_node_name != "":
		ship_key = enemy.target_ship_node_name
	else:
		ship_key = enemy.name

	# Coleta todos os MeshInstance3D do modelo real da nave
	var mesh_instances: Array[MeshInstance3D] = []
	_find_visible_mesh_instances(enemy, mesh_instances)

	if mesh_instances.is_empty():
		queue_free()
		return

	# Se já temos o cache das 3 malhas para este tipo de nave, reutilizamos
	if _wreckage_cache.has(ship_key):
		_spawn_cached_pieces(enemy, _wreckage_cache[ship_key])
		return

	# Caso contrário, calcula o fatiamento das malhas reais em 3 partes
	var cache_data := _slice_ship_into_3_parts(enemy, mesh_instances)
	if cache_data and not cache_data.is_empty():
		_wreckage_cache[ship_key] = cache_data
		_spawn_cached_pieces(enemy, cache_data)
	else:
		queue_free()


func _find_visible_mesh_instances(enemy: Node3D, result: Array[MeshInstance3D]) -> void:
	var target_node_name: String = ""
	if "target_ship_node_name" in enemy and enemy.target_ship_node_name != "":
		target_node_name = enemy.target_ship_node_name.replace("_", ".")

	var ship_root: Node = enemy
	if target_node_name != "":
		var found := enemy.find_child(target_node_name, true, false)
		if not found:
			found = enemy.find_child(target_node_name.replace(".", "_"), true, false)
		if found:
			ship_root = found

	_collect_meshes_recursive(ship_root, result)


func _collect_meshes_recursive(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh:
			result.append(mi)
	for child in node.get_children():
		if child is Node3D and not (child as Node3D).visible:
			continue
		_collect_meshes_recursive(child, result)


func _get_transform_relative_to(child: Node3D, ancestor: Node3D) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var curr: Node3D = child
	while curr and curr != ancestor:
		t = curr.transform * t
		curr = curr.get_parent() as Node3D
	return t


## Fatia as malhas 3D autênticas da nave em 3 pedaços ao longo do eixo X local
func _slice_ship_into_3_parts(enemy: Node3D, mesh_instances: Array[MeshInstance3D]) -> Dictionary:
	# 1. Encontra a extensão total em X no referencial do modelo da nave
	var min_x: float = INF
	var max_x: float = -INF

	for mi: MeshInstance3D in mesh_instances:
		var mesh: Mesh = mi.mesh
		if not mesh:
			continue
		var to_enemy: Transform3D = _get_transform_relative_to(mi, enemy)
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var local_v: Vector3 = to_enemy * v
				min_x = minf(min_x, local_v.x)
				max_x = maxf(max_x, local_v.x)

	if min_x >= max_x:
		min_x = -1.0
		max_x = 1.0

	var span: float = max_x - min_x
	var split_x: float = span * 0.22

	# Estrutura para os 3 fragmentos reais: 0 = Asa Esquerda, 1 = Fuselagem Central, 2 = Asa Direita
	var part_surfaces: Array = [[], [], []] # [part_index] -> Array de {mesh, material, transform}
	var part_vertex_sums: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var part_vertex_counts: Array[int] = [0, 0, 0]

	for mi: MeshInstance3D in mesh_instances:
		var mesh: Mesh = mi.mesh
		if not mesh:
			continue
		var to_enemy: Transform3D = _get_transform_relative_to(mi, enemy)

		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			if arrays.is_empty():
				continue

			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays.size() > Mesh.ARRAY_NORMAL else PackedVector3Array()
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays.size() > Mesh.ARRAY_TEX_UV else PackedVector2Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX else PackedInt32Array()

			var has_normals: bool = not normals.is_empty()
			var has_uvs: bool = not uvs.is_empty()

			var num_triangles: int = 0
			if not indices.is_empty():
				num_triangles = indices.size() / 3
			else:
				num_triangles = verts.size() / 3

			var sts: Array[SurfaceTool] = [SurfaceTool.new(), SurfaceTool.new(), SurfaceTool.new()]
			for st in sts:
				st.begin(Mesh.PRIMITIVE_TRIANGLES)

			var part_has_triangles: Array[bool] = [false, false, false]

			for t in range(num_triangles):
				var i0: int = indices[t * 3] if not indices.is_empty() else t * 3
				var i1: int = indices[t * 3 + 1] if not indices.is_empty() else t * 3 + 1
				var i2: int = indices[t * 3 + 2] if not indices.is_empty() else t * 3 + 2

				var v0: Vector3 = verts[i0]
				var v1: Vector3 = verts[i1]
				var v2: Vector3 = verts[i2]

				var ev0: Vector3 = to_enemy * v0
				var ev1: Vector3 = to_enemy * v1
				var ev2: Vector3 = to_enemy * v2

				var cx: float = (ev0.x + ev1.x + ev2.x) / 3.0
				var part_idx: int = 1
				if cx < -split_x:
					part_idx = 0
				elif cx > split_x:
					part_idx = 2

				var target_st: SurfaceTool = sts[part_idx]
				part_has_triangles[part_idx] = true

				part_vertex_sums[part_idx] += ev0 + ev1 + ev2
				part_vertex_counts[part_idx] += 3

				for idx in [i0, i1, i2]:
					if has_normals:
						target_st.set_normal(normals[idx])
					if has_uvs:
						target_st.set_uv(uvs[idx])
					target_st.add_vertex(verts[idx])

			# IMPORTANTE: Sempre utiliza o material original da superfície do asset GLB (ignora flash_mat)
			var mat: Material = mesh.surface_get_material(s)
			if not mat:
				mat = mi.get_surface_override_material(s)

			for p in range(3):
				if part_has_triangles[p]:
					if mat:
						sts[p].set_material(mat)
					var sub_mesh: ArrayMesh = sts[p].commit()
					if mat:
						sub_mesh.surface_set_material(0, mat)
					part_surfaces[p].append({
						"mesh": sub_mesh,
						"material": mat,
						"transform": to_enemy
					})

	# Calcula os centros de massa (pivôs) de cada parte
	var centroids: Array[Vector3] = [
		Vector3(-span * 0.35, 0, 0),
		Vector3.ZERO,
		Vector3(span * 0.35, 0, 0)
	]
	for p in range(3):
		if part_vertex_counts[p] > 0:
			centroids[p] = part_vertex_sums[p] / float(part_vertex_counts[p])

	return {
		"parts": part_surfaces,
		"centroids": centroids
	}


## Instancia as 3 partes na cena com suas físicas e partículas
func _spawn_cached_pieces(enemy: Node3D, data: Dictionary) -> void:
	var parts: Array = data["parts"]
	var centroids: Array = data["centroids"]

	var enemy_gt: Transform3D = enemy.global_transform
	var basis: Basis = enemy_gt.basis
	var forward: Vector3 = -basis.z.normalized()
	var right: Vector3 = basis.x.normalized()
	var up: Vector3 = basis.y.normalized()

	for p in range(3):
		var piece_surfaces: Array = parts[p]
		if piece_surfaces.is_empty():
			continue

		var centroid: Vector3 = centroids[p]
		var piece_root := Node3D.new()
		piece_root.name = "Piece_%d" % p
		add_child(piece_root)

		# Posiciona e orienta o pedaço no espaço mundial exatamente onde o modelo estava
		piece_root.global_position = enemy_gt * centroid
		piece_root.global_basis = basis

		for item in piece_surfaces:
			var sub_mesh: ArrayMesh = item["mesh"]
			var mat: Material = item["material"]
			var to_enemy: Transform3D = item["transform"]

			var mi := MeshInstance3D.new()
			mi.mesh = sub_mesh
			mi.material_override = null # Garante que usará os materiais reais da malha
			# Ajusta a transformação da malha relativa ao pivô do pedaço
			mi.transform = Transform3D(Basis(), -centroid) * to_enemy
			piece_root.add_child(mi)

		# Adiciona emissor de trilha de fumaça e fogo nos destroços
		_attach_fire_smoke_trail(piece_root)

		# Configura a dinâmica física do pedaço (mantendo a velocidade do vôo + impulso da explosão)
		var vel := _calculate_initial_velocity(p, forward, right, up)
		var ang_vel := _calculate_initial_angular_velocity(p)

		_pieces.append({
			"node": piece_root,
			"velocity": vel,
			"angular_velocity": ang_vel,
			"initial_scale": piece_root.scale
		})


func _calculate_initial_velocity(part_index: int, forward: Vector3, right: Vector3, up: Vector3) -> Vector3:
	var f := explosion_force
	var impulse := Vector3.ZERO
	var speed_ratio := 1.0

	match part_index:
		0: # Asa Esquerda: arremessada lateralmente para a esquerda e leve salto
			impulse = (-right * randf_range(16.0, 26.0) + up * randf_range(3.0, 8.0) + forward * randf_range(-3.0, 4.0)) * f
			speed_ratio = 0.96
		1: # Fuselagem Central: sobe e é projetada para frente em alta velocidade
			impulse = (up * randf_range(6.0, 14.0) + forward * randf_range(8.0, 18.0) + right * randf_range(-4.0, 4.0)) * f
			speed_ratio = 1.02
		2: # Asa Direita: arremessada lateralmente para a direita e leve salto
			impulse = (right * randf_range(16.0, 26.0) + up * randf_range(3.0, 8.0) + forward * randf_range(-3.0, 4.0)) * f
			speed_ratio = 0.96

	return inherited_velocity * speed_ratio + impulse


func _calculate_initial_angular_velocity(part_index: int) -> Vector3:
	match part_index:
		0: # Asa Esquerda: rolagem acentuada e rotação no eixo de vôo
			return Vector3(
				randf_range(-4.0, 4.0),
				randf_range(5.0, 9.0),
				randf_range(-8.0, -4.0)
			)
		1: # Fuselagem: giro frontal acentuado
			return Vector3(
				randf_range(7.0, 13.0),
				randf_range(-3.0, 3.0),
				randf_range(-4.0, 4.0)
			)
		2: # Asa Direita: rolagem acentuada oposta
			return Vector3(
				randf_range(-4.0, 4.0),
				randf_range(-9.0, -5.0),
				randf_range(4.0, 8.0)
			)
	return Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))


## Anexa um sistema de partículas de chamas e fumaça ao pedaço em chamas
func _attach_fire_smoke_trail(parent: Node3D) -> void:
	# 1. Trilha de Fumaça Escura Volumétrica
	var smoke := CPUParticles3D.new()
	smoke.name = "SmokeTrail"
	smoke.local_coords = false # Para as partículas ficarem no espaço mundial (trilha)
	smoke.emitting = true
	smoke.amount = 22
	smoke.lifetime = 0.85
	smoke.spread = 45.0
	smoke.gravity = Vector3(0.0, 2.5, 0.0)
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 5.0
	smoke.angular_velocity_min = -60.0
	smoke.angular_velocity_max = 60.0
	smoke.scale_amount_min = 1.5
	smoke.scale_amount_max = 6.0

	var smoke_ramp := Gradient.new()
	smoke_ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	smoke_ramp.colors = PackedColorArray([
		Color(0.9, 0.45, 0.1, 0.85),  # Início fogo/brasa
		Color(0.35, 0.3, 0.28, 0.6), # Fumaça densa
		Color(0.15, 0.15, 0.15, 0.4), # Fumaça escura
		Color(0.05, 0.05, 0.05, 0.0)  # Dissipação
	])
	smoke.color_ramp = smoke_ramp

	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.35
	sphere_mesh.height = 0.7
	sphere_mesh.radial_segments = 6
	sphere_mesh.rings = 3
	smoke.mesh = sphere_mesh

	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	smoke.material_override = smoke_mat

	parent.add_child(smoke)

	# 2. Faíscas / Brasas Incandescentes
	var sparks := CPUParticles3D.new()
	sparks.name = "SparksTrail"
	sparks.local_coords = false
	sparks.emitting = true
	sparks.amount = 14
	sparks.lifetime = 0.5
	sparks.spread = 90.0
	sparks.gravity = Vector3.ZERO
	sparks.initial_velocity_min = 5.0
	sparks.initial_velocity_max = 14.0
	sparks.scale_amount_min = 0.2
	sparks.scale_amount_max = 0.6

	var sparks_ramp := Gradient.new()
	sparks_ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	sparks_ramp.colors = PackedColorArray([
		Color(2.0, 1.8, 0.5, 1.0), # Dourado incandescente
		Color(1.2, 0.4, 0.05, 0.9), # Laranja fogo
		Color(0.5, 0.05, 0.0, 0.0)
	])
	sparks.color_ramp = sparks_ramp

	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.15
	spark_mesh.height = 0.3
	spark_mesh.radial_segments = 4
	spark_mesh.rings = 2
	sparks.mesh = spark_mesh

	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.vertex_color_use_as_albedo = true
	sparks.material_override = spark_mat

	parent.add_child(sparks)


func _physics_process(delta: float) -> void:
	_age += delta

	# Aplica física cinemática a cada pedaço
	var gravity := Vector3(0.0, -6.0, 0.0)
	var drag: float = 0.995 # Suave resistência do ar para manter o vôo à frente

	for piece in _pieces:
		var node: Node3D = piece["node"]
		if not is_instance_valid(node):
			continue

		var vel: Vector3 = piece["velocity"]
		var ang_vel: Vector3 = piece["angular_velocity"]

		# Atualiza velocidade linear com gravidade e arrasto
		vel += gravity * delta
		vel *= pow(drag, delta * 60.0)
		piece["velocity"] = vel

		# Move o pedaço no espaço mundial
		node.global_position += vel * delta

		# Aplica rotação nos eixos locais do pedaço
		node.rotate_x(ang_vel.x * delta)
		node.rotate_y(ang_vel.y * delta)
		node.rotate_z(ang_vel.z * delta)

	# Fade out / encolhimento suave no final da vida útil (últimos 30%)
	if _age >= lifetime * 0.70:
		var fade_t := clampf((_age - lifetime * 0.70) / (lifetime * 0.30), 0.0, 1.0)
		var scale_factor: float = 1.0 - fade_t
		for piece in _pieces:
			var node: Node3D = piece["node"]
			if is_instance_valid(node):
				var init_scale: Vector3 = piece["initial_scale"]
				node.scale = init_scale * maxf(scale_factor, 0.01)

	if _age >= lifetime:
		queue_free()
