class_name EnergyBall
extends Area3D

## Projétil de energia (torpedo) disparado pela Mothership.
## Visual: grande esfera brilhante com OmniLight.
## Dano: 1 HP de dano ao jogador.
## Velocidade: lenta (configurável).

const ExplosionScript := preload("res://scripts/effects/explosion.gd")
const WORLD_LAYER_MASK: int = 1 << 3  # layer 4 ("world")

@export var speed: float = 420.0            # Velocidade do torpedo (unidades/segundo)
@export var damage: int = 1                  # Dano de 1 HP
@export var max_distance: float = 7000.0    # Limite antes de auto-destruir
@export var torpedo_sound: AudioStream = null  # Áudio do torpedo (preparado para receber arquivo)

var _direction: Vector3 = Vector3.FORWARD
var _spawn_position: Vector3 = Vector3.ZERO
var _prev_position: Vector3 = Vector3.ZERO
var _ray: RayCast3D = null
var _audio_player: AudioStreamPlayer = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	_ray = RayCast3D.new()
	_ray.enabled = false
	_ray.collision_mask = WORLD_LAYER_MASK
	_ray.collide_with_bodies = true
	_ray.collide_with_areas = false
	add_child(_ray)

	_spawn_position = global_position
	_prev_position = global_position

	if torpedo_sound != null:
		play_launch_sound()


func play_launch_sound() -> void:
	if torpedo_sound == null:
		return
	if not _audio_player:
		_audio_player = AudioStreamPlayer.new()
		_audio_player.bus = "Master"
		add_child(_audio_player)
	_audio_player.stream = torpedo_sound
	_audio_player.play()


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
	if _direction == Vector3.ZERO:
		return

	_prev_position = global_position
	global_position += _direction * speed * delta

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
		var hit_collider = _ray.get_collider()
		if hit_collider and ("Mothership" in hit_collider.name or "mothership" in hit_collider.name.to_lower()):
			return
		var hit_point := _ray.get_collision_point()
		var hit_normal := _ray.get_collision_normal()
		_spawn_explosion(hit_point, hit_normal)
		queue_free()


func _spawn_explosion(point: Vector3, normal: Vector3) -> void:
	if ExplosionScript:
		var explosion: Node3D = ExplosionScript.new()
		if "size_scale" in explosion:
			explosion.size_scale = 1.8
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = point + normal * 0.5



func _on_body_entered(body: Node3D) -> void:
	if body and ("Mothership" in body.name or "mothership" in body.name.to_lower()):
		return

	if body.has_method("take_damage"):
		body.take_damage(damage)
		_spawn_explosion(global_position, Vector3.UP)
		queue_free()
		return

	if body is CharacterBody3D:
		_spawn_explosion(global_position, Vector3.UP)
		queue_free()


func _on_area_entered(area: Area3D) -> void:
	if area and ("Mothership" in area.name or "mothership" in area.name.to_lower()):
		return

	if area.has_method("take_damage"):
		area.take_damage(damage)
		_spawn_explosion(global_position, Vector3.UP)
		queue_free()


