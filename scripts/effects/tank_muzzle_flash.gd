class_name TankMuzzleFlash
extends Node3D

## Clarão e fumaça de disparo realistas da boca do canhão do tanque (Muzzle Flash & Cannon Smoke).
## Produz:
## 1. Flash de luz instantâneo e ofuscante com decaimento ultrarrápido (0.12s)
## 2. Jato/cone cônico de chamas saindo do cano
## 3. Nuvem densa e volumétrica de fumaça cinza/negra de pólvora se expandindo na boca do canhão

const DURATION: float = 1.4

var _age: float = 0.0
var _flash_light: OmniLight3D = null


func _ready() -> void:
	_build_flash_light()
	_build_bloom_flare()
	_build_fire_blast()
	_build_cannon_smoke()


func setup(direction: Vector3) -> void:
	if direction.length_squared() > 0.0001:
		var up := Vector3.UP
		if absf(direction.dot(up)) > 0.98:
			up = Vector3.RIGHT
		look_at(global_position + direction, up)


func _process(delta: float) -> void:
	_age += delta
	if _flash_light and is_instance_valid(_flash_light):
		var t := clampf(_age / 0.18, 0.0, 1.0)
		_flash_light.light_energy = lerpf(250.0, 0.0, t * t)
		if t >= 1.0:
			_flash_light.queue_free()
			_flash_light = null

	if _age >= DURATION:
		queue_free()


func _build_flash_light() -> void:
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.9, 0.55)
	_flash_light.light_energy = 250.0
	_flash_light.omni_range = 140.0
	_flash_light.omni_attenuation = 0.5
	add_child(_flash_light)


func _build_bloom_flare() -> void:
	# Clarão esférico/lens flare de alta intensidade HDR para acionar o Glow/Bloom da câmera
	var flare := Sprite3D.new()
	flare.name = "BloomGlowFlare"
	flare.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flare.modulate = Color(8.0, 5.5, 2.0, 1.0) # HDR alto para estourar o bloom threshold
	flare.pixel_size = 0.12
	flare.no_depth_test = false

	# Criação de textura procedural radial de gradiente suave para o brilho
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var center := Vector2(31.5, 31.5)
	for y in range(64):
		for x in range(64):
			var dist := center.distance_to(Vector2(x, y)) / 31.5
			var alpha := clampf(1.0 - dist, 0.0, 1.0)
			alpha = alpha * alpha # Curva exponencial suave
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	var tex := ImageTexture.create_from_image(img)
	flare.texture = tex
	add_child(flare)

	# Tween para expansão e fade out rápido do clarão/brilho
	var tw := create_tween()
	flare.scale = Vector3(1.0, 1.0, 1.0)
	tw.parallel().tween_property(flare, "scale", Vector3(9.0, 9.0, 9.0), 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(flare, "modulate:a", 0.0, 0.18).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(flare.queue_free)


func _build_fire_blast() -> void:
	# Cone/jato de fogo e gás superaquecido projetado para a frente do cano
	var p := CPUParticles3D.new()
	p.name = "FireBlast"
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 28
	p.lifetime = 0.22
	p.direction = Vector3.FORWARD
	p.spread = 22.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 45.0
	p.initial_velocity_max = 90.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.5

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
	ramp.colors = PackedColorArray([
		Color(6.0, 5.0, 2.5, 1.0),
		Color(3.5, 1.8, 0.3, 1.0),
		Color(1.5, 0.3, 0.02, 0.8),
		Color(0.2, 0.05, 0.0, 0.0)
	])
	p.color_ramp = ramp

	var sphere := SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 1.2
	p.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p.material_override = mat
	add_child(p)


func _build_cannon_smoke() -> void:
	# Nuvem volumétrica densa de fumaça de pólvora saindo do cano
	var s := CPUParticles3D.new()
	s.name = "CannonSmoke"
	s.emitting = true
	s.one_shot = true
	s.explosiveness = 0.9
	s.amount = 32
	s.lifetime = 1.3
	s.direction = Vector3.FORWARD
	s.spread = 40.0
	s.gravity = Vector3(0, 4.0, 0)
	s.initial_velocity_min = 12.0
	s.initial_velocity_max = 35.0
	s.angular_velocity_min = -60.0
	s.angular_velocity_max = 60.0
	s.scale_amount_min = 3.5
	s.scale_amount_max = 9.0

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.35, 0.30, 0.25, 0.85),
		Color(0.22, 0.20, 0.19, 0.75),
		Color(0.14, 0.13, 0.13, 0.45),
		Color(0.08, 0.08, 0.08, 0.0)
	])
	s.color_ramp = ramp

	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.6
	s.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	s.material_override = mat
	add_child(s)
