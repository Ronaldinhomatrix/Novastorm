class_name WaveManager
extends Node

## Gerenciador de ondas de inimigos (Waves) no Mundo 3D Real (World Space).
## Monitora o progresso do PathFollower e instancia os inimigos diretamente no
## cenário 3D do cânion, com trajetórias e manobras aéreas realistas.

signal wave_started(wave_index: int, wave_name: String)
signal wave_cleared(wave_index: int)

@export_category("Referências")
@export var path_follower: PathFollower = null

@export_category("Cenas de Inimigos")
@export var scout_scene: PackedScene = preload("res://scenes/enemies/enemy_scout.tscn")
@export var fighter_scene: PackedScene = preload("res://scenes/enemies/enemy_fighter.tscn")
@export var heavy_scene: PackedScene = preload("res://scenes/enemies/enemy_heavy.tscn")

@export_category("Gatilhos por Ponto do Path3D")
@export var wave_1_point: int = 6   ## Ponto da curva Path3D onde a Wave 1 é disparada (Scouts)
@export var wave_2_point: int = 17  ## Ponto da curva Path3D onde a Wave 2 é disparada (Fighters nas pontes)
@export var wave_3_point: int = 28  ## Ponto da curva Path3D onde a Wave 3 é disparada (Heavy na bacia)

var _wave_1_triggered: bool = false
var _wave_2_triggered: bool = false
var _wave_3_triggered: bool = false

var _target_ratio_1: float = 0.14
var _target_ratio_2: float = 0.40
var _target_ratio_3: float = 0.65

var _active_enemies: Array[Node] = []
var _enemies_container: Node3D = null


func _ready() -> void:
	if not path_follower:
		path_follower = get_node_or_null("../FlightPath/PathFollower") as PathFollower
	if not path_follower:
		path_follower = get_parent().get_node_or_null("FlightPath/PathFollower") as PathFollower

	_setup_container()
	_update_target_ratios()


func _setup_container() -> void:
	_enemies_container = Node3D.new()
	_enemies_container.name = "WorldEnemiesContainer"
	get_tree().current_scene.add_child.call_deferred(_enemies_container)


func _update_target_ratios() -> void:
	if not path_follower:
		return
	var path3d: Path3D = path_follower.get_parent() as Path3D
	if not path3d or not path3d.curve or path3d.curve.point_count == 0:
		return

	var curve: Curve3D = path3d.curve
	var total_len: float = maxf(1.0, curve.get_baked_length())

	_target_ratio_1 = _get_point_ratio(curve, wave_1_point, total_len)
	_target_ratio_2 = _get_point_ratio(curve, wave_2_point, total_len)
	_target_ratio_3 = _get_point_ratio(curve, wave_3_point, total_len)


func _get_point_ratio(curve: Curve3D, point_index: int, total_length: float) -> float:
	var clamped_index: int = clampi(point_index, 0, curve.point_count - 1)
	var pos: Vector3 = curve.get_point_position(clamped_index)
	var offset: float = curve.get_closest_offset(pos)
	return offset / total_length


func _get_point_info(point_index: int) -> Dictionary:
	if not path_follower:
		return {"position": Vector3.ZERO, "forward": Vector3.FORWARD, "right": Vector3.RIGHT, "up": Vector3.UP}
	var path3d: Path3D = path_follower.get_parent() as Path3D
	if not path3d or not path3d.curve or path3d.curve.point_count == 0:
		return {"position": Vector3.ZERO, "forward": Vector3.FORWARD, "right": Vector3.RIGHT, "up": Vector3.UP}

	var curve: Curve3D = path3d.curve
	var clamped_idx: int = clampi(point_index, 0, curve.point_count - 1)
	var pos_local: Vector3 = curve.get_point_position(clamped_idx)
	var pos_global: Vector3 = path3d.global_transform * pos_local

	var next_idx: int = clampi(clamped_idx + 1, 0, curve.point_count - 1)
	var prev_idx: int = clampi(clamped_idx - 1, 0, curve.point_count - 1)
	var forward_dir: Vector3 = Vector3.FORWARD

	if next_idx != clamped_idx:
		var next_pos: Vector3 = path3d.global_transform * curve.get_point_position(next_idx)
		forward_dir = (next_pos - pos_global).normalized()
	elif prev_idx != clamped_idx:
		var prev_pos: Vector3 = path3d.global_transform * curve.get_point_position(prev_idx)
		forward_dir = (pos_global - prev_pos).normalized()

	var up_dir: Vector3 = Vector3.UP
	var right_dir: Vector3 = forward_dir.cross(up_dir).normalized()
	if right_dir.length_squared() < 0.001:
		right_dir = Vector3.RIGHT
	up_dir = right_dir.cross(forward_dir).normalized()

	return {
		"position": pos_global,
		"forward": forward_dir,
		"right": right_dir,
		"up": up_dir
	}


func _process(_delta: float) -> void:
	if not path_follower:
		return

	var current_progress: float = path_follower.progress_ratio

	if not _wave_1_triggered and current_progress >= _target_ratio_1:
		_wave_1_triggered = true
		_spawn_wave_1()

	if not _wave_2_triggered and current_progress >= _target_ratio_2:
		_wave_2_triggered = true
		_spawn_wave_2()

	if not _wave_3_triggered and current_progress >= _target_ratio_3:
		_wave_3_triggered = true
		_spawn_wave_3()


# ---------------------------------------------------------------------------
# Wave 1: Esquadrilha de Scouts (Starship.002) no Mundo 3D
# ---------------------------------------------------------------------------

func _spawn_wave_1() -> void:
	wave_started.emit(1, "Wave 1: Scout Squadron")

	var info: Dictionary = _get_point_info(wave_1_point)
	var base_pos: Vector3 = info["position"]
	var fwd: Vector3 = info["forward"]
	var right: Vector3 = info["right"]
	var up: Vector3 = info["up"]

	# Subwave 1A: 3 scouts pela direita cruzando o cânion
	_spawn_world_scout_squadron(3, base_pos, fwd, right, up, 1.0, 0.0)

	# Subwave 1B: 3 scouts pela esquerda após 2.5s
	var timer: SceneTreeTimer = get_tree().create_timer(2.5)
	timer.timeout.connect(func():
		_spawn_world_scout_squadron(3, base_pos, fwd, right, up, -1.0, 0.0)
	)


func _spawn_world_scout_squadron(count: int, base_pos: Vector3, fwd: Vector3, right: Vector3, up: Vector3, side: float, base_delay: float) -> void:
	for i: int in range(count):
		var delay: float = base_delay + (i * 0.4)
		var timer: SceneTreeTimer = get_tree().create_timer(delay)
		timer.timeout.connect(func():
			var scout: EnemyScout = scout_scene.instantiate() as EnemyScout
			if not scout:
				return

			var spawn_pos: Vector3 = base_pos + (fwd * (180.0 + i * 25.0)) + (right * (side * (25.0 + i * 6.0))) + (up * (15.0 + i * 3.0))
			var fly_dir: Vector3 = -fwd  # Voa em direção de aproximação ao jogador

			_add_enemy_to_world(scout)
			scout.setup_flight(spawn_pos, fly_dir, side, 120.0)
			_register_enemy(scout)
		)


# ---------------------------------------------------------------------------
# Wave 2: Caças Táticos Fighters (Starship.v2) no Mundo 3D
# ---------------------------------------------------------------------------

func _spawn_wave_2() -> void:
	wave_started.emit(2, "Wave 2: Tactical Fighters")

	var info: Dictionary = _get_point_info(wave_2_point)
	var base_pos: Vector3 = info["position"]
	var fwd: Vector3 = info["forward"]
	var right: Vector3 = info["right"]
	var up: Vector3 = info["up"]

	var configs: Array[Dictionary] = [
		{
			"pos": base_pos + (fwd * 220.0) + (up * 25.0),
			"b_type": 0,  # Quebra subindo
			"delay": 0.0
		},
		{
			"pos": base_pos + (fwd * 190.0) - (right * 30.0) + (up * 14.0),
			"b_type": 1,  # Quebra para a esquerda
			"delay": 0.3
		},
		{
			"pos": base_pos + (fwd * 190.0) + (right * 30.0) + (up * 14.0),
			"b_type": 2,  # Quebra para a direita
			"delay": 0.6
		}
	]

	for cfg: Dictionary in configs:
		var timer: SceneTreeTimer = get_tree().create_timer(cfg["delay"])
		timer.timeout.connect(func():
			var fighter: EnemyFighter = fighter_scene.instantiate() as EnemyFighter
			if not fighter:
				return

			var fly_dir: Vector3 = -fwd
			_add_enemy_to_world(fighter)
			fighter.setup_fighter(cfg["pos"], fly_dir, cfg["b_type"])
			_register_enemy(fighter)
		)


# ---------------------------------------------------------------------------
# Wave 3: Cruzador Pesado Heavy Gunship (Starship.v3) no Mundo 3D
# ---------------------------------------------------------------------------

func _spawn_wave_3() -> void:
	wave_started.emit(3, "Wave 3: Heavy Cruiser Mini-Boss")

	var info: Dictionary = _get_point_info(wave_3_point)
	var base_pos: Vector3 = info["position"]
	var fwd: Vector3 = info["forward"]
	var right: Vector3 = info["right"]
	var up: Vector3 = info["up"]

	# Heavy Mini-Boss em órbita aérea sobre a bacia do cânion
	var heavy: EnemyHeavy = heavy_scene.instantiate() as EnemyHeavy
	if heavy:
		var center_orbit: Vector3 = base_pos + (fwd * 60.0) + (up * 35.0)
		_add_enemy_to_world(heavy)
		heavy.setup_heavy(center_orbit)
		_register_enemy(heavy)

	# 2 Escoltas Scouts voando pelo espaço aéreo
	var escort_timer: SceneTreeTimer = get_tree().create_timer(1.0)
	escort_timer.timeout.connect(func():
		for side: float in [-1.0, 1.0]:
			var scout: EnemyScout = scout_scene.instantiate() as EnemyScout
			if scout:
				var spawn_pos: Vector3 = base_pos + (fwd * 160.0) + (right * (side * 35.0)) + (up * 20.0)
				_add_enemy_to_world(scout)
				scout.setup_flight(spawn_pos, -fwd, side, 130.0)
				_register_enemy(scout)
	)


# ---------------------------------------------------------------------------
# Helpers de Registro e Hierarquia
# ---------------------------------------------------------------------------

func _add_enemy_to_world(enemy: Node3D) -> void:
	if is_instance_valid(_enemies_container):
		_enemies_container.add_child(enemy)
	else:
		get_tree().current_scene.add_child(enemy)


func _register_enemy(enemy: Node) -> void:
	_active_enemies.append(enemy)
	if enemy.has_signal("enemy_destroyed"):
		enemy.connect("enemy_destroyed", _on_enemy_destroyed)
	enemy.tree_exiting.connect(func():
		_active_enemies.erase(enemy)
	)


func _on_enemy_destroyed(enemy: Node, _score: int) -> void:
	_active_enemies.erase(enemy)
