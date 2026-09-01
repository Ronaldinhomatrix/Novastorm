class_name ShieldBubble
extends Node3D

## Campo de força 3D holográfico procedural.
## Suporta ativação normal (azul ciano) e efeito dramático de quebra (laranja/vermelho piscante).

const COLOR_NORMAL := Color(0.0, 0.85, 1.0, 1.0)
const COLOR_BREAK := Color(1.0, 0.25, 0.05, 1.0)
const SparkScript := preload("res://scripts/effects/spark.gd")

@export var duration: float = 1.0

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var _material: ShaderMaterial = null
var _tween: Tween = null


func _ready() -> void:
	_init_material()
	visible = false


func _init_material() -> void:
	if _material:
		return
	if not mesh_instance:
		mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance:
		if mesh_instance.material_override is ShaderMaterial:
			_material = mesh_instance.material_override.duplicate() as ShaderMaterial
			mesh_instance.material_override = _material
		elif mesh_instance.mesh and mesh_instance.mesh.material is ShaderMaterial:
			_material = mesh_instance.mesh.material.duplicate() as ShaderMaterial
			mesh_instance.material_override = _material


## Ativa o campo de força normal por 1 segundo (ciano)
func activate(custom_duration: float = 1.0) -> void:
	var shield_dur := custom_duration if custom_duration > 0.0 else duration
	_init_material()

	if not _material:
		return

	visible = true

	if _tween and _tween.is_running():
		_tween.kill()

	# Garante a cor ciano padrão
	_material.set_shader_parameter("shield_color", COLOR_NORMAL)
	_material.set_shader_parameter("impact_flash", 0.5)
	_material.set_shader_parameter("energy_intensity", 1.2)

	_tween = create_tween()
	
	# 1. Decaimento rápido do flash inicial (0.15s)
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_method(func(val: float):
		if _material:
			_material.set_shader_parameter("impact_flash", val)
	, 0.5, 0.0, 0.15)

	# 2. Transição suave da energia para nível contínuo elegante (0.2s)
	_tween.tween_method(func(val: float):
		if _material:
			_material.set_shader_parameter("energy_intensity", val)
	, 1.2, 0.75, 0.2)

	# 3. Mantém ativo até iniciar a dissolução final
	_tween.chain().set_parallel(false)
	var hold_time := maxf(0.0, shield_dur - 0.45)
	_tween.tween_interval(hold_time)

	# 4. Dissolução suave da energia do escudo até sumir aos 1.0s
	_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_method(func(val: float):
		if _material:
			_material.set_shader_parameter("energy_intensity", val)
	, 0.75, 0.0, 0.35)

	# 5. Oculta o nó ao terminar
	_tween.tween_callback(func():
		visible = false
	)


## Dispara o efeito especial de quebra / sobrecarga do escudo ("Shields Offline")
func trigger_shield_break(custom_duration: float = 1.0) -> void:
	var shield_dur := custom_duration if custom_duration > 0.0 else duration
	_init_material()

	if not _material:
		return

	visible = true

	if _tween and _tween.is_running():
		_tween.kill()

	# Define a cor de sobrecarga (laranja/vermelho elétrico)
	_material.set_shader_parameter("shield_color", COLOR_BREAK)
	_material.set_shader_parameter("impact_flash", 1.0)
	_material.set_shader_parameter("energy_intensity", 1.6)

	# Spawna várias faíscas ao redor da nave
	_spawn_break_sparks()

	_tween = create_tween()

	# 1. Flash inicial de sobrecarga e oscilações/piscadas caóticas rápidas (glitch elétrico de 0.6s)
	_tween.set_parallel(false)
	var flicker_count := 7
	var step_time := 0.6 / float(flicker_count * 2)

	for i in range(flicker_count):
		_tween.tween_method(func(val: float):
			if _material:
				_material.set_shader_parameter("energy_intensity", val)
		, 1.5, 0.15, step_time)
		_tween.tween_method(func(val: float):
			if _material:
				_material.set_shader_parameter("energy_intensity", val)
		, 0.15, 1.4, step_time)

	# 2. Desintegração final rápida
	_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_method(func(val: float):
		if _material:
			_material.set_shader_parameter("energy_intensity", val)
	, 1.4, 0.0, 0.35)

	# 3. Oculta e restaura a cor padrão para o próximo ciclo
	_tween.tween_callback(func():
		visible = false
		if _material:
			_material.set_shader_parameter("shield_color", COLOR_NORMAL)
	)


func _spawn_break_sparks() -> void:
	if not SparkScript:
		return
	for i in range(4):
		var spark: Node3D = SparkScript.new()
		get_tree().current_scene.add_child(spark)
		var rand_dir := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		spark.global_position = global_position + rand_dir * randf_range(1.0, 2.5)
		if spark.has_method("setup"):
			spark.setup(rand_dir)
