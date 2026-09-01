class_name DamageSmokeEffect
extends Node3D

## Gerenciador procedural de efeitos visuais de dano na nave do jogador:
##   - Estágio 1 (1º dano): Fumaça leve saindo de um ponto da nave (asa esquerda/fuselagem).
##   - Estágio 2 (2º dano): Fumaça pesada + pequeno incêndio saindo de outro ponto (asa direita/motor).
##   - Estágio 0 (reset/cura/respawn): Desativa todas as emissões.

var _smoke_1: CPUParticles3D = null
var _smoke_2: CPUParticles3D = null
var _fire_2: CPUParticles3D = null


func _ready() -> void:
	_build_effects()


func _build_effects() -> void:
	# -----------------------------------------------------------------------
	# Ponto de Dano 1: Asa/Flanco Esquerdo (Fumaça leve cinza)
	# -----------------------------------------------------------------------
	_smoke_1 = CPUParticles3D.new()
	_smoke_1.name = "Smoke1"
	_smoke_1.position = Vector3(-1.1, 0.15, 1.0)
	_smoke_1.emitting = false
	_smoke_1.amount = 18
	_smoke_1.lifetime = 0.75
	_smoke_1.direction = Vector3(0.0, 0.2, 1.0)
	_smoke_1.spread = 25.0
	_smoke_1.gravity = Vector3(0.0, 3.0, 0.0)
	_smoke_1.initial_velocity_min = 12.0
	_smoke_1.initial_velocity_max = 24.0
	_smoke_1.scale_amount_min = 0.5
	_smoke_1.scale_amount_max = 1.8
	_smoke_1.mesh = _create_sphere_mesh(0.4)
	_smoke_1.material_override = _create_smoke_material()

	var ramp1 := Gradient.new()
	ramp1.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	ramp1.colors = PackedColorArray([
		Color(0.2, 0.2, 0.2, 0.0),
		Color(0.25, 0.25, 0.28, 0.5),
		Color(0.35, 0.35, 0.38, 0.3),
		Color(0.5, 0.5, 0.5, 0.0)
	])
	_smoke_1.color_ramp = ramp1
	add_child(_smoke_1)

	# -----------------------------------------------------------------------
	# Ponto de Dano 2: Asa/Flanco Direito (Fumaça pesada escura + Incêndio/Fogo)
	# -----------------------------------------------------------------------
	_smoke_2 = CPUParticles3D.new()
	_smoke_2.name = "Smoke2"
	_smoke_2.position = Vector3(1.2, 0.1, 0.6)
	_smoke_2.emitting = false
	_smoke_2.amount = 32
	_smoke_2.lifetime = 0.9
	_smoke_2.direction = Vector3(0.0, 0.3, 1.0)
	_smoke_2.spread = 30.0
	_smoke_2.gravity = Vector3(0.0, 4.5, 0.0)
	_smoke_2.initial_velocity_min = 15.0
	_smoke_2.initial_velocity_max = 30.0
	_smoke_2.scale_amount_min = 0.8
	_smoke_2.scale_amount_max = 2.8
	_smoke_2.mesh = _create_sphere_mesh(0.5)
	_smoke_2.material_override = _create_smoke_material()

	var ramp2 := Gradient.new()
	ramp2.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	ramp2.colors = PackedColorArray([
		Color(0.1, 0.1, 0.1, 0.0),
		Color(0.12, 0.12, 0.14, 0.8),
		Color(0.2, 0.2, 0.22, 0.5),
		Color(0.4, 0.4, 0.4, 0.0)
	])
	_smoke_2.color_ramp = ramp2
	add_child(_smoke_2)

	# Pequeno incêndio / chamas na raiz da fumaça 2
	_fire_2 = CPUParticles3D.new()
	_fire_2.name = "Fire2"
	_fire_2.position = Vector3(1.2, 0.1, 0.6)
	_fire_2.emitting = false
	_fire_2.amount = 22
	_fire_2.lifetime = 0.35
	_fire_2.direction = Vector3(0.0, 0.4, 1.0)
	_fire_2.spread = 20.0
	_fire_2.gravity = Vector3(0.0, 2.0, 0.0)
	_fire_2.initial_velocity_min = 8.0
	_fire_2.initial_velocity_max = 18.0
	_fire_2.scale_amount_min = 0.3
	_fire_2.scale_amount_max = 0.9
	_fire_2.mesh = _create_sphere_mesh(0.3)
	_fire_2.material_override = _create_fire_material()

	var ramp_fire := Gradient.new()
	ramp_fire.offsets = PackedFloat32Array([0.0, 0.2, 0.6, 1.0])
	ramp_fire.colors = PackedColorArray([
		Color(2.0, 1.8, 1.0, 1.0),   # Núcleo branco-amarelo vivo
		Color(1.5, 0.7, 0.1, 0.95),  # Amarelo/laranja fogo
		Color(1.0, 0.25, 0.02, 0.6), # Vermelho brasa
		Color(0.4, 0.05, 0.0, 0.0)   # Extinção
	])
	_fire_2.color_ramp = ramp_fire
	add_child(_fire_2)


## Atualiza o nível de dano (0 = limpo, 1 = fumaça leve, 2 = fumaça densa + fogo)
func set_damage_level(level: int) -> void:
	if not _smoke_1 or not _smoke_2 or not _fire_2:
		return

	match level:
		0:
			_smoke_1.emitting = false
			_smoke_2.emitting = false
			_fire_2.emitting = false
		1:
			_smoke_1.emitting = true
			_smoke_2.emitting = false
			_fire_2.emitting = false
		2, _:
			_smoke_1.emitting = true
			_smoke_2.emitting = true
			_fire_2.emitting = true


func reset() -> void:
	set_damage_level(0)


func _create_sphere_mesh(radius: float) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 6
	sphere.rings = 4
	return sphere


func _create_smoke_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _create_fire_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
