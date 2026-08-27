class_name EnemyHeavy
extends "res://scripts/enemies/enemy_base.gd"

## Inimigo Cruzador Pesado / Mini-Boss (Starship.v3)
## Nave pesada com padrão de voo em infinito (figura-8), disparos em leque triplo
## e sequência de destruição com múltiplas explosões encadeadas.

@export var combat_z: float = -115.0
@export var figure8_speed: float = 1.0
@export var width_amplitude: float = 24.0
@export var height_amplitude: float = 8.0

var _time_alive: float = 0.0
var _attack_timer: float = 1.5
var _attack_pattern_index: int = 0
var _dying_sequence: bool = false


func _ready() -> void:
	max_hp = 12
	score_value = 1000
	super._ready()


func _physics_process(delta: float) -> void:
	if _dying_sequence:
		return

	_time_alive += delta

	# Entrada suave até a zona de combate
	if position.z < combat_z:
		position.z = move_toward(position.z, combat_z, 60.0 * delta)

	# Movimento contínuo em formato de figura-8 (Lemniscata)
	var t := _time_alive * figure8_speed
	var target_x := sin(t) * width_amplitude
	var target_y := 12.0 + sin(t * 2.0) * height_amplitude

	position.x = lerpf(position.x, target_x, 3.0 * delta)
	position.y = lerpf(position.y, target_y, 3.0 * delta)

	# Inclinação imponente e pesada
	var bank := -cos(t) * 0.25
	rotation.z = lerpf(rotation.z, bank, 4.0 * delta)
	rotation.x = lerpf(rotation.x, -cos(t * 2.0) * 0.1, 4.0 * delta)

	# Gerenciador de ataques
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = 2.4
		_execute_attack()


func _execute_attack() -> void:
	_attack_pattern_index = (_attack_pattern_index + 1) % 2

	if _attack_pattern_index == 0:
		_shoot_triple_spread()
	else:
		_shoot_twin_heavy_burst()


func _shoot_triple_spread() -> void:
	# Disparo triplo em leque (esquerda, centro, direita)
	var center_pos := global_position + (-global_basis.z * 3.0)
	var left_pos := global_position + (-global_basis.x * 5.0) + (-global_basis.z * 2.0)
	var right_pos := global_position + (global_basis.x * 5.0) + (-global_basis.z * 2.0)

	var target_center := _get_player_position()
	var base_dir := (target_center - global_position).normalized()

	var left_dir := (base_dir + -global_basis.x * 0.18).normalized()
	var right_dir := (base_dir + global_basis.x * 0.18).normalized()

	fire_bullet(left_pos, left_dir)
	fire_bullet(center_pos, base_dir)
	fire_bullet(right_pos, right_dir)


func _shoot_twin_heavy_burst() -> void:
	# Rajada concentrada das asas principais
	var left_pos := global_position + (-global_basis.x * 3.8) + (-global_basis.z * 2.5)
	var right_pos := global_position + (global_basis.x * 3.8) + (-global_basis.z * 2.5)

	fire_towards_player(left_pos, 0.9)
	fire_towards_player(right_pos, 0.9)


func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_dying_sequence = true
	is_invulnerable = true

	# Sequência de explosões dramáticas de mini-boss
	_run_death_sequence()


func _run_death_sequence() -> void:
	for i in range(4):
		var offset := Vector3(
			randf_range(-4.0, 4.0),
			randf_range(-2.0, 2.0),
			randf_range(-3.0, 3.0)
		)
		var exp_small: Node3D = ExplosionScript.new()
		get_tree().current_scene.add_child(exp_small)
		exp_small.global_position = global_position + offset
		if exp_small.has_method("set"):
			exp_small.set("size_scale", 1.0)
		await get_tree().create_timer(0.18).timeout

	# Grande explosão final
	var exp_big: Node3D = ExplosionScript.new()
	get_tree().current_scene.add_child(exp_big)
	exp_big.global_position = global_position
	if exp_big.has_method("set"):
		exp_big.set("size_scale", 3.0)

	enemy_destroyed.emit(self, score_value)
	queue_free()
