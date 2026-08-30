class_name MothershipMuzzleFlash
extends Node3D

## Clarão cinematográfico ultra-intenso localizado no canhão da Mothership.
## Cria um clarão de luz de alta energia 3D com luzes dinâmicas potentes,
## flare óptico expansivo em HDR, feixe horizontal anamórfico e estrela de brilho central.

const FLASH_DURATION: float = 0.42

var _age: float = 0.0
var _light_global: OmniLight3D = null
var _light_core: OmniLight3D = null
var _optical_flare: MeshInstance3D = null
var _optical_mat: StandardMaterial3D = null
var _anamorphic_flare: MeshInstance3D = null
var _anamorphic_mat: StandardMaterial3D = null
var _star_flare: MeshInstance3D = null
var _star_mat: StandardMaterial3D = null


func _ready() -> void:
	_build_muzzle_lights()
	_build_optical_lens_flare()
	_build_anamorphic_streak()
	_build_starburst_core()


func setup(_direction: Vector3 = Vector3.ZERO) -> void:
	pass


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / FLASH_DURATION, 0.0, 1.0)
	var fade := (1.0 - t) * (1.0 - t)

	# 1. Decaimento das luzes dinâmicas ultra-intensas na Mothership
	if _light_global:
		_light_global.light_energy = 4500.0 * fade
	if _light_core:
		_light_core.light_energy = 2800.0 * (fade * fade)

	# 2. Expansão e fade do halo óptico principal
	if _optical_flare and _optical_mat:
		var s := lerpf(65.0, 340.0, ease(t, 0.22))
		_optical_flare.scale = Vector3.ONE * s
		_optical_mat.albedo_color.a = lerpf(1.0, 0.0, t)

	# 3. Expansão e fade do feixe horizontal anamórfico
	if _anamorphic_flare and _anamorphic_mat:
		var s_x := lerpf(180.0, 750.0, ease(t, 0.18))
		var s_y := lerpf(12.0, 32.0, ease(t, 0.28))
		_anamorphic_flare.scale = Vector3(s_x, s_y, 1.0)
		_anamorphic_mat.albedo_color.a = lerpf(1.0, 0.0, t)

	# 4. Expansão e fade da estrela de brilho focal central
	if _star_flare and _star_mat:
		var star_s := lerpf(80.0, 260.0, ease(t, 0.25))
		_star_flare.scale = Vector3.ONE * star_s
		_star_mat.albedo_color.a = lerpf(1.0, 0.0, t)

	if _age >= FLASH_DURATION:
		queue_free()


func _build_muzzle_lights() -> void:
	# Luz 3D de altíssima intensidade que ilumina fortemente a proa e o casco da Mothership
	_light_global = OmniLight3D.new()
	_light_global.name = "FlashLightGlobal"
	_light_global.light_color = Color(1.0, 0.35, 0.08, 1.0)  # Vermelho-alaranjado incandescente
	_light_global.light_energy = 4500.0
	_light_global.omni_range = 2400.0
	add_child(_light_global)

	# Luz focal ultra-quente concentrada no ponto do canhão
	_light_core = OmniLight3D.new()
	_light_core.name = "FlashLightCore"
	_light_core.light_color = Color(1.0, 0.96, 0.88, 1.0)  # Branco incandescente
	_light_core.light_energy = 2800.0
	_light_core.omni_range = 900.0
	add_child(_light_core)


func _build_optical_lens_flare() -> void:
	# Halo de luz suave em gradiente radial com cores em HDR de alta intensidade
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.42, 1.0])
	grad.colors = PackedColorArray([
		Color(5.0, 4.5, 4.0, 1.0),   # Núcleo branco ultra-ofuscante
		Color(3.5, 1.6, 0.3, 0.95),  # Halo dourado incandescente
		Color(2.0, 0.35, 0.04, 0.6), # Halo avermelhado
		Color(0.8, 0.0, 0.0, 0.0)    # Fade transparente suave
	])

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256

	_optical_mat = StandardMaterial3D.new()
	_optical_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_optical_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_optical_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_optical_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_optical_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_optical_mat.albedo_texture = tex
	_optical_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	_optical_flare = MeshInstance3D.new()
	_optical_flare.name = "OpticalLensFlare"
	_optical_flare.mesh = quad
	_optical_flare.material_override = _optical_mat
	_optical_flare.scale = Vector3.ONE * 65.0
	add_child(_optical_flare)


func _build_anamorphic_streak() -> void:
	# Feixe horizontal luminoso cinematográfico de alta potência
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.0, 0.0, 0.0),
		Color(4.5, 2.5, 1.2, 1.0),
		Color(1.0, 0.0, 0.0, 0.0)
	])

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 64

	_anamorphic_mat = StandardMaterial3D.new()
	_anamorphic_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_anamorphic_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_anamorphic_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_anamorphic_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_anamorphic_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_anamorphic_mat.albedo_texture = tex
	_anamorphic_mat.albedo_color = Color(1.0, 0.8, 0.5, 1.0)

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	_anamorphic_flare = MeshInstance3D.new()
	_anamorphic_flare.name = "AnamorphicStreak"
	_anamorphic_flare.mesh = quad
	_anamorphic_flare.material_override = _anamorphic_mat
	_anamorphic_flare.scale = Vector3(180.0, 12.0, 1.0)
	add_child(_anamorphic_flare)


func _build_starburst_core() -> void:
	# Estrela de brilho focal central (cruz de luz óptica)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.0, 0.0, 0.0),
		Color(5.0, 4.0, 3.0, 1.0),
		Color(1.0, 0.0, 0.0, 0.0)
	])

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 64
	tex.height = 256

	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_star_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_star_mat.albedo_texture = tex
	_star_mat.albedo_color = Color(1.0, 0.9, 0.7, 1.0)

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	_star_flare = MeshInstance3D.new()
	_star_flare.name = "StarburstCore"
	_star_flare.mesh = quad
	_star_flare.material_override = _star_mat
	_star_flare.scale = Vector3(14.0, 180.0, 1.0)
	add_child(_star_flare)
