class_name EnemyTruck
extends EnemyBase

## Inimigo terrestre Caminhão de Transporte / Comboio Militar (Truck1).
## Permanece posicionado em comboio sobre o cenário (ex: pontes ou estradas) e
## inicia deslocamento lento quando a nave do jogador se aproxima.

@export_category("Movimento Terrestre")
@export var move_speed: float = 12.0
@export var activation_distance: float = 1500.0
@export var custom_move_direction: Vector3 = Vector3.ZERO ## Se ZERO, move na direção forward (-basis.z)
@export var active_move: bool = false
@export var snap_to_ground: bool = true

var _is_activated: bool = false
var _player_ref: Node3D = null


func _ready() -> void:
	max_hp = 2
	score_value = 150
	super._ready()
	
	_player_ref = _get_player_node()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
		
	super._physics_process(delta)
		
	if not _player_ref or not is_instance_valid(_player_ref):
		_player_ref = _get_player_node()
		
	var player_pos := _player_ref.global_position if _player_ref else Vector3.ZERO
	var dist_to_player := global_position.distance_to(player_pos) if _player_ref else 99999.0
	
	# 1. Ativação de movimento por proximidade do jogador
	if not _is_activated and (active_move or dist_to_player <= activation_distance):
		_is_activated = true
		
	if _is_activated and move_speed > 0.0:
		var dir := custom_move_direction.normalized()
		if dir.length_squared() < 0.01:
			dir = -global_transform.basis.z.normalized()
		global_position += dir * move_speed * delta
		
		if snap_to_ground:
			_snap_to_ground_surface()


func _snap_to_ground_surface() -> void:
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return
	var from_pos := global_position + Vector3.UP * 8.0
	var to_pos := global_position + Vector3.DOWN * 15.0
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos, WORLD_LAYER_MASK)
	var result := space_state.intersect_ray(query)
	if result and result.has("position"):
		global_position.y = result["position"].y
