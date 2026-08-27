class_name EnemyBase
extends Area3D

## Classe base para todas as naves inimigas no Astro Striker.
## Gerencia vida (HP), detecção de dano do jogador, efeito visual de hit-flash,
## disparo de projéteis, isolamento de malha e explosão de destruição.

signal enemy_destroyed(enemy: Node, score: int)

const ExplosionScript := preload("res://scripts/effects/explosion.gd")
const LaserSound := preload("res://assets/audio/laser1.ogg")

@export_category("Atributos")
@export var max_hp: int = 1
@export var score_value: int = 100
@export var is_invulnerable: bool = false
@export var target_ship_node_name: String = ""  ## Nome do nó da nave a exibir do GLB (ex: Starship.002, Starship.v2, Starship.v3)

@export_category("Armas")
@export var bullet_scene: PackedScene = preload("res://scenes/enemies/enemy_bullet.tscn")
@export var laser_volume_db: float = -4.0

var current_hp: int = 1
var _is_dead: bool = false
var _mesh_instances: Array[MeshInstance3D] = []
var _original_materials: Dictionary = {}
var _flash_tween: Tween = null
var _laser_audio_player: AudioStreamPlayer = null


func _ready() -> void:
	current_hp = max_hp
	collision_layer = 2
	collision_mask = 2

	if target_ship_node_name != "":
		_isolate_target_ship()

	_setup_audio()
	_collect_mesh_instances(self)


func _isolate_target_ship() -> void:
	var glb_root := get_node_or_null("ShipModel/3_enemy_red_starships")
	if not glb_root:
		glb_root = find_child("3_enemy_red_starships", true, false)
	if not glb_root:
		return

	var known_ships := ["Starship.002", "Starship.v2", "Starship.v3", "Starship_002", "Starship_v2", "Starship_v3"]
	for ship_name in known_ships:
		var node := glb_root.find_child(ship_name, true, false)
		if node and node is Node3D:
			var match_name := ship_name.replace("_", ".")
			var target_clean := target_ship_node_name.replace("_", ".")
			if match_name == target_clean:
				(node as Node3D).visible = true
			else:
				(node as Node3D).visible = false


func _setup_audio() -> void:
	_laser_audio_player = AudioStreamPlayer.new()
	_laser_audio_player.stream = LaserSound
	_laser_audio_player.bus = "Master"
	_laser_audio_player.volume_db = laser_volume_db
	add_child(_laser_audio_player)


func _collect_mesh_instances(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.is_visible_in_tree():
			_mesh_instances.append(mi)
	for child in node.get_children():
		_collect_mesh_instances(child)


func take_damage(amount: int) -> void:
	if _is_dead or is_invulnerable:
		return

	current_hp -= amount
	_play_hit_flash()

	if current_hp <= 0:
		die()


func _play_hit_flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	# Se não coletou malhas antes, coleta agora
	if _mesh_instances.is_empty():
		_collect_mesh_instances(self)

	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(2.5, 0.4, 0.4, 1.0)

	for mi in _mesh_instances:
		if is_instance_valid(mi):
			mi.material_override = flash_mat

	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.06)
	_flash_tween.tween_callback(func():
		for mi in _mesh_instances:
			if is_instance_valid(mi):
				mi.material_override = null
	)


func fire_bullet(from_pos: Vector3, dir: Vector3) -> void:
	if not bullet_scene:
		return

	var bullet: EnemyBullet = bullet_scene.instantiate() as EnemyBullet
	if not bullet:
		return

	get_tree().current_scene.add_child(bullet)
	bullet.global_position = from_pos
	bullet.setup(dir)

	if _laser_audio_player and not _is_dead:
		_laser_audio_player.pitch_scale = randf_range(0.9, 1.1)
		_laser_audio_player.play()


func fire_towards_player(from_pos: Vector3, aim_convergence: float = 0.8) -> void:
	var target_pos := _get_player_position()
	var dir := (target_pos - from_pos).normalized()
	
	var forward := -global_basis.z.normalized()
	var final_dir := forward.slerp(dir, aim_convergence).normalized()
	
	fire_bullet(from_pos, final_dir)


func _get_player_position() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		player = get_node_or_null("/root/Game/FlightPath/PathFollower/Player")
	if player:
		return player.global_position
	return global_position + Vector3(0, 0, 40)


func die() -> void:
	if _is_dead:
		return
	_is_dead = true

	var explosion: Node3D = ExplosionScript.new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	if explosion.has_method("set"):
		explosion.set("size_scale", 1.5)

	enemy_destroyed.emit(self, score_value)
	queue_free()
