class_name WaveManager
extends Node

## Gerenciador de ondas de inimigos (Waves) para o Astro Striker.
## Monitora o progresso do PathFollower ao longo do nível e dispara
## as waves de inimigos nos pontos exatos da curva do Path3D.

signal wave_started(wave_index: int, wave_name: String)
signal wave_cleared(wave_index: int)

@export_category("Referências")
@export var path_follower: PathFollower = null

@export_category("Cenas de Inimigos")
@export var scout_scene: PackedScene = preload("res://scenes/enemies/enemy_scout.tscn")
@export var fighter_scene: PackedScene = preload("res://scenes/enemies/enemy_fighter.tscn")
@export var heavy_scene: PackedScene = preload("res://scenes/enemies/enemy_heavy.tscn")

@export_category("Gatilhos por Ponto do Path3D")
@export var wave_1_point: int = 6   ## Número do ponto da curva Path3D onde a Wave 1 é disparada (Esquadrilha de Scouts)
@export var wave_2_point: int = 17  ## Número do ponto da curva Path3D onde a Wave 2 é disparada (Fighters)
@export var wave_3_point: int = 28  ## Número do ponto da curva Path3D onde a Wave 3 é disparada (Heavy Mini-Boss)

var _wave_1_triggered: bool = false
var _wave_2_triggered: bool = false
var _wave_3_triggered: bool = false

var _target_ratio_1: float = 0.14
var _target_ratio_2: float = 0.40
var _target_ratio_3: float = 0.65

var _active_enemies: Array[Node] = []


func _ready() -> void:
	if not path_follower:
		path_follower = get_node_or_null("../FlightPath/PathFollower") as PathFollower
	if not path_follower:
		path_follower = get_parent().get_node_or_null("FlightPath/PathFollower") as PathFollower

	_update_target_ratios()


func _update_target_ratios() -> void:
	if not path_follower:
		return
	var path3d := path_follower.get_parent() as Path3D
	if not path3d or not path3d.curve or path3d.curve.point_count == 0:
		return

	var curve := path3d.curve
	var total_len := maxf(1.0, curve.get_baked_length())

	_target_ratio_1 = _get_point_ratio(curve, wave_1_point, total_len)
	_target_ratio_2 = _get_point_ratio(curve, wave_2_point, total_len)
	_target_ratio_3 = _get_point_ratio(curve, wave_3_point, total_len)


func _get_point_ratio(curve: Curve3D, point_index: int, total_length: float) -> float:
	var clamped_index := clampi(point_index, 0, curve.point_count - 1)
	var pos := curve.get_point_position(clamped_index)
	var offset := curve.get_closest_offset(pos)
	return offset / total_length


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
# Wave 1: Esquadrilha de Scouts (Starship.002)
# ---------------------------------------------------------------------------

func _spawn_wave_1() -> void:
	wave_started.emit(1, "Wave 1: Scout Squadron")

	# Subwave 1A: 3 scouts pela direita
	_spawn_scout_squadron(3, 1.0, 0.0)

	# Subwave 1B: 3 scouts pela esquerda após pequeno intervalo
	var timer := get_tree().create_timer(3.0)
	timer.timeout.connect(func():
		_spawn_scout_squadron(3, -1.0, 0.0)
	)


func _spawn_scout_squadron(count: int, side: float, base_delay: float) -> void:
	for i in range(count):
		var delay := base_delay + (i * 0.45)
		var timer := get_tree().create_timer(delay)
		timer.timeout.connect(func():
			if not is_instance_valid(path_follower):
				return
			var scout: EnemyScout = scout_scene.instantiate() as EnemyScout
			if not scout:
				return
			path_follower.add_child(scout)
			scout.position = Vector3(side * (20.0 + i * 4.0), 12.0 + (i * 2.0), -230.0 - (i * 15.0))
			scout.start_side = side
			_register_enemy(scout)
		)


# ---------------------------------------------------------------------------
# Wave 2: Caças Táticos Fighters (Starship.v2)
# ---------------------------------------------------------------------------

func _spawn_wave_2() -> void:
	wave_started.emit(2, "Wave 2: Tactical Fighters")

	var spawn_configs := [
		{"pos": Vector3(-20.0, 8.0, -270.0), "delay": 0.0},
		{"pos": Vector3(0.0, 14.0, -300.0), "delay": 0.5},
		{"pos": Vector3(20.0, 8.0, -270.0), "delay": 1.0}
	]

	for cfg in spawn_configs:
		var timer := get_tree().create_timer(cfg["delay"])
		timer.timeout.connect(func():
			if not is_instance_valid(path_follower):
				return
			var fighter: EnemyFighter = fighter_scene.instantiate() as EnemyFighter
			if not fighter:
				return
			path_follower.add_child(fighter)
			fighter.position = cfg["pos"]
			_register_enemy(fighter)
		)


# ---------------------------------------------------------------------------
# Wave 3: Cruzador Pesado Heavy Gunship (Starship.v3) + Escolta
# ---------------------------------------------------------------------------

func _spawn_wave_3() -> void:
	wave_started.emit(3, "Wave 3: Heavy Cruiser Mini-Boss")

	# Heavy Mini-Boss
	if is_instance_valid(path_follower):
		var heavy: EnemyHeavy = heavy_scene.instantiate() as EnemyHeavy
		if heavy:
			path_follower.add_child(heavy)
			heavy.position = Vector3(0.0, 18.0, -330.0)
			_register_enemy(heavy)

	# 2 Escoltas Scouts nas alas
	var escort_timer := get_tree().create_timer(1.2)
	escort_timer.timeout.connect(func():
		if not is_instance_valid(path_follower):
			return
		for side in [-1.0, 1.0]:
			var scout: EnemyScout = scout_scene.instantiate() as EnemyScout
			if scout:
				path_follower.add_child(scout)
				scout.position = Vector3(side * 28.0, 10.0, -260.0)
				scout.start_side = side
				_register_enemy(scout)
	)


# ---------------------------------------------------------------------------
# Gerenciamento e Rastreamento de Inimigos
# ---------------------------------------------------------------------------

func _register_enemy(enemy: Node) -> void:
	_active_enemies.append(enemy)
	if enemy.has_signal("enemy_destroyed"):
		enemy.connect("enemy_destroyed", _on_enemy_destroyed)
	enemy.tree_exiting.connect(func():
		_active_enemies.erase(enemy)
	)


func _on_enemy_destroyed(enemy: Node, _score: int) -> void:
	_active_enemies.erase(enemy)
