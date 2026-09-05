class_name EnemyTank
extends EnemyBase

## Inimigo terrestre Tanque de Guerra (Tank1).
## Permanece posicionado no cenário (ex: pontes ou estradas) e
## sua torreta/canhão gira dinamicamente rastreando a posição do jogador no ar.
## Dispara projéteis pesados de alta velocidade (TankBullet).

const DefaultTankBulletScene := preload("res://scenes/enemies/tank_bullet.tscn")

@export_category("Movimento Terrestre")
@export var move_speed: float = 12.0
@export var custom_move_direction: Vector3 = Vector3.ZERO ## Se ZERO, move na direção forward (-basis.z)
@export var active_move: bool = false ## Ativa a movimentação terrestre quando verdadeiro
@export var snap_to_ground: bool = true

@export_category("Torreta e Mira")
@export var turret_node_path: NodePath = "TankModel/tank1/Turret"
@export var turret_rotation_speed: float = 3.2
@export var aim_at_player: bool = true
@export var can_shoot: bool = false ## Ativado pelo GameController apenas quando o Player estiver entre os pontos 16 e 18
@export var fire_interval: float = 2.8
@export var max_shoot_distance: float = 1600.0

var _turret: Node3D = null
var _fire_timer: float = 0.0
var _player_ref: Node3D = null


func _ready() -> void:
	max_hp = 3
	score_value = 250
	enable_engine_sound = false
	
	if not bullet_scene:
		bullet_scene = DefaultTankBulletScene
		
	super._ready()
	
	if turret_node_path != ^"":
		_turret = get_node_or_null(turret_node_path) as Node3D
	if not _turret:
		_turret = find_child("Turret", true, false) as Node3D
		
	# Dispara logo após o jogador entrar no raio de alcance
	_fire_timer = randf_range(0.2, 0.7)
	_player_ref = _get_player_node()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
		
	super._physics_process(delta)
		
	if not _player_ref or not is_instance_valid(_player_ref):
		_player_ref = _get_player_node()
		
	var player_pos := _player_ref.global_position if _player_ref else Vector3.ZERO
	var dist_to_player := global_position.distance_to(player_pos) if _player_ref else 99999.0
	
	# 1. Movimentação terrestre (apenas se active_move for verdadeiro)
	if active_move and move_speed > 0.0:
		var dir := custom_move_direction.normalized()
		if dir.length_squared() < 0.01:
			dir = -global_transform.basis.z.normalized()
		global_position += dir * move_speed * delta
		
	if snap_to_ground:
		_snap_to_ground_surface()

	# 2. Rastreamento e mira da torreta em direção ao jogador
	if _turret and is_instance_valid(_turret) and _player_ref and aim_at_player:
		_aim_turret_at_player(player_pos, delta)

	# 3. Disparo de projétil pesado em direção ao jogador quando estiver no alcance e autorizado
	if can_shoot:
		if dist_to_player <= max_shoot_distance:
			_fire_timer -= delta
			if _fire_timer <= 0.0:
				_fire_timer = fire_interval + randf_range(-0.3, 0.3)
				_shoot_at_player()
		else:
			# Mantém pronto para disparar rapidamente assim que entrar no alcance
			_fire_timer = randf_range(0.2, 0.5)
	else:
		# Fora da janela de disparo (antes do ponto 16 ou após ponto 18): mantém engatilhado
		_fire_timer = randf_range(0.2, 0.5)


func _snap_to_ground_surface() -> void:
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return
	var from_pos := global_position + Vector3.UP * 40.0
	var to_pos := global_position + Vector3.DOWN * 60.0
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos, WORLD_LAYER_MASK)
	var result := space_state.intersect_ray(query)
	if result and result.has("position"):
		global_position.y = result["position"].y


func _aim_turret_at_player(target_pos: Vector3, delta: float) -> void:
	var parent_node := _turret.get_parent_node_3d()
	if not parent_node:
		return
		
	var local_target := parent_node.to_local(target_pos)
	var local_turret_pos := _turret.position
	
	var dir_to_target := local_target - local_turret_pos
	# O canhão do modelo 3D do tanque aponta para +Z local da torreta.
	# Portanto o ângulo correto para apontar o canhão de frente é atan2(dir.x, dir.z)
	var desired_yaw := atan2(dir_to_target.x, dir_to_target.z)
	
	_turret.rotation.y = lerp_angle(_turret.rotation.y, desired_yaw, turret_rotation_speed * delta)


func _shoot_at_player() -> void:
	if not bullet_scene:
		bullet_scene = DefaultTankBulletScene
		
	var base_turret_pos := _turret.global_position if _turret else global_position + Vector3.UP * 3.0
	var forward_dir := _turret.global_basis.z.normalized() if _turret else -global_basis.z.normalized()
	
	if _player_ref and is_instance_valid(_player_ref):
		var dir_to_player := (_player_ref.global_position - base_turret_pos).normalized()
		forward_dir = forward_dir.slerp(dir_to_player, 0.85).normalized()
		
	var spawn_pos := base_turret_pos + forward_dir * 8.5 + Vector3.UP * 1.5
	fire_bullet(spawn_pos, forward_dir)


const GroundVehicleWreckageScript := preload("res://scripts/effects/ground_vehicle_wreckage.gd")

func die() -> void:
	if _is_dead:
		return
	_is_dead = true

	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	# Destruição terrestre realista: casco queimando no solo + ejeção balística da torreta com gravidade
	GroundVehicleWreckageScript.spawn_for_tank(self)

	enemy_destroyed.emit(self, score_value)
	queue_free()
