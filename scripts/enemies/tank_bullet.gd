class_name TankBullet
extends Area3D

## Projétil pesado de artilharia disparado por tanques de guerra (Tank1).
## Viaja a alta velocidade (380 u/s) com rastro de fumaça, faíscas e formato de projétil balístico/tracer.

const SPEED: float = 380.0
const WORLD_LAYER_MASK: int = 1 << 3  # layer 4 ("world")
const ExplosionScript := preload("res://scripts/effects/explosion.gd")

@export var damage: int = 2
@export var max_distance: float = 2200.0

var _direction: Vector3 = Vector3.FORWARD
var _spawn_position: Vector3 = Vector3.ZERO
var _prev_position: Vector3 = Vector3.ZERO
var _ray: RayCast3D = null


func _ready() -> void:
	add_to_group("enemy_bullets")
	collision_layer = 4  # Layer 3: enemy_projectiles (mask bit 4)
	collision_mask = 1   # Layer 1: player
	monitoring = true
	monitorable = true

	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	_ray = RayCast3D.new()
	_ray.enabled = false
	_ray.collision_mask = WORLD_LAYER_MASK
	_ray.collide_with_bodies = true
	_ray.collide_with_areas = false
	add_child(_ray)
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
	if not _ray:
		return

	var travel := global_position - _prev_position
	if travel.length_squared() < 0.000001:
		return

	_ray.global_position = _prev_position
	_ray.target_position = travel
	_ray.force_raycast_update()

	if _ray.is_colliding():
		var hit_point := _ray.get_collision_point()
		var hit_normal := _ray.get_collision_normal()
		_spawn_explosion(hit_point, hit_normal)
		queue_free()


func _spawn_explosion(point: Vector3, normal: Vector3) -> void:
	var explosion: Node3D = ExplosionScript.new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = point + normal * 0.5
	if explosion.has_method("set"):
		explosion.set("size_scale", 0.45)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
		_spawn_explosion(global_position, -_direction)
		queue_free()
		return

	if not body is CharacterBody3D:
		_spawn_explosion(global_position, -_direction)
		queue_free()


func _on_area_entered(area: Area3D) -> void:
	if area.has_method("take_damage"):
		area.take_damage(damage)
		_spawn_explosion(global_position, -_direction)
		queue_free()
