class_name EnemyTruck
extends EnemyBase

## Inimigo terrestre Caminhão de Transporte / Comboio Militar (Truck1).
## Permanece posicionado no cenário (ex: pontes ou estradas).

@export_category("Movimento Terrestre")
@export var move_speed: float = 12.0
@export var custom_move_direction: Vector3 = Vector3.ZERO ## Se ZERO, move na direção forward (-basis.z)
@export var active_move: bool = false ## Ativa a movimentação terrestre quando verdadeiro
@export var snap_to_ground: bool = true

var _player_ref: Node3D = null
var _snap_query: PhysicsRayQueryParameters3D = null
var _snap_timer: float = 0.0

func _ready() -> void:
	max_hp = 2
	score_value = 150
	enable_engine_sound = false
	super._ready()
	
	_snap_query = PhysicsRayQueryParameters3D.new()
	_snap_query.collision_mask = WORLD_LAYER_MASK
	_snap_query.collide_with_bodies = true
	_snap_query.collide_with_areas = false
	
	_player_ref = _get_player_node()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
		
	super._physics_process(delta)
		
	# 1. Movimentação terrestre (apenas se active_move for verdadeiro)
	if active_move and move_speed > 0.0:
		var dir := custom_move_direction.normalized()
		if dir.length_squared() < 0.01:
			dir = -global_transform.basis.z.normalized()
		global_position += dir * move_speed * delta
		
	if snap_to_ground:
		_snap_timer -= delta
		if _snap_timer <= 0.0:
			_snap_timer = 0.1  # 10Hz
			_snap_to_ground_surface()


func _snap_to_ground_surface() -> void:
	var space_state := get_world_3d().direct_space_state
	if not space_state or not _snap_query:
		return
	_snap_query.from = global_position + Vector3.UP * 40.0
	_snap_query.to = global_position + Vector3.DOWN * 60.0
	var result := space_state.intersect_ray(_snap_query)
	if result and result.has("position"):
		global_position.y = result["position"].y


const GroundVehicleWreckageScript := preload("res://scripts/effects/ground_vehicle_wreckage.gd")

func die() -> void:
	if _is_dead:
		return
	_is_dead = true

	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	# Destruição terrestre realista: chassi carbonizado no solo fumegando com chamas
	GroundVehicleWreckageScript.spawn_for_truck(self)

	enemy_destroyed.emit(self, score_value)
	queue_free()
