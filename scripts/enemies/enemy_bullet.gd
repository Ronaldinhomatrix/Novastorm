class_name EnemyBullet
extends Area3D

## Projétil laser disparado por naves inimigas.
## Viaja em direção ao jogador e causa dano ao acertá-lo ou ao colidir com o cenário.

const SPEED: float = 450.0
const WORLD_LAYER_MASK: int = 1 << 3  # layer 4 ("world")
const ExplosionScript := preload("res://scripts/effects/explosion.gd")

@export var damage: int = 1
@export var max_distance: float = 1200.0

var _direction: Vector3 = Vector3.FORWARD
var _spawn_position: Vector3 = Vector3.ZERO
var _prev_position: Vector3 = Vector3.ZERO
var _ray_query: PhysicsRayQueryParameters3D = null


func _ready() -> void:
	add_to_group("enemy_bullets")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collision_mask = WORLD_LAYER_MASK
	_ray_query.collide_with_bodies = true
	_ray_query.collide_with_areas = false
	_prev_position = global_position


func setup(dir: Vector3) -> void:
	_direction = dir.normalized()
	_spawn_position = global_position
	_prev_position = global_position

	if _direction.length_squared() > 0.000001:
		var up := Vector3.UP
		if absf(_direction.dot(up)) > 0.99:
			up = Vector3.RIGHT
		look_at(global_position - _direction, up)


func _physics_process(delta: float) -> void:
	_prev_position = global_position
	global_position += _direction * SPEED * delta

	_check_world_hit()

	if global_position.distance_squared_to(_spawn_position) > max_distance * max_distance:
		queue_free()


func _check_world_hit() -> void:
	if not _ray_query:
		return

	var travel := global_position - _prev_position
	if travel.length_squared() < 0.000001:
		return

	var space := get_world_3d().direct_space_state
	if not space:
		return

	_ray_query.from = _prev_position
	_ray_query.to = global_position
	var result := space.intersect_ray(_ray_query)

	if not result.is_empty():
		var hit_point: Vector3 = result.position
		var hit_normal: Vector3 = result.normal
		_spawn_explosion(hit_point, hit_normal)
		queue_free()


func _spawn_explosion(point: Vector3, normal: Vector3) -> void:
	var explosion: Node3D = ExplosionScript.new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = point + normal * 0.5
	if explosion.has_method("set"):
		explosion.set("size_scale", 0.2)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
		return

	if not body is CharacterBody3D:
		queue_free()


func _on_area_entered(area: Area3D) -> void:
	if area.has_method("take_damage"):
		area.take_damage(damage)
		queue_free()
