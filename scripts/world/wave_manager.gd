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
@export var bomber_scene: PackedScene = preload("res://scenes/enemies/enemy_bomber.tscn")

const AlertEnemyShipsSound := preload("res://assets/audio/alert_enemy_ships.wav")
const WarningBattlecruiserSound := preload("res://assets/audio/warning_enemy_battlecruiser.mp3")

@export_category("Gatilhos por Ponto do Path3D")
@export var wave_1_point: int = 8   ## Ponto da curva Path3D onde a Wave 1 é disparada (Scouts)
@export var wave_2_point: int = 15  ## Ponto da curva Path3D onde a Wave 2 é disparada (Fighters)
@export var warning_battlecruiser_point: int = 21  ## Ponto 21 para o áudio warning_enemy_battlecruiser
@export var wave_bomber_point: int = 25  ## Ponto 25 onde o Enemy Bomber é disparado
@export var bomber_dismiss_delay: float = 2.0  ## Tempo em segundos após o spawn do Bomber para as outras naves iniciarem a retirada cinematográfica
@export var wave_3_point: int = 37  ## Ponto da curva Path3D onde a Wave 3 é disparada (2 pontos antes do 39)

var _alert_enemy_ships_triggered: bool = false
var _warning_battlecruiser_triggered: bool = false
var _wave_1_triggered: bool = false
var _wave_2_triggered: bool = false
var _wave_bomber_triggered: bool = false
var _wave_3_triggered: bool = false
var _penultimate_exit_triggered: bool = false

var _target_ratio_1_alert: float = 0.10
var _target_ratio_1: float = 0.14
var _target_ratio_2: float = 0.35
var _target_ratio_warning_battlecruiser: float = 0.50
var _target_ratio_bomber: float = 0.53
var _target_ratio_3: float = 0.88
var _penultimate_ratio: float = 0.96

var _quiet_zone_start_ratio: float = 0.48
var _mothership_zone_clear_ratio: float = 0.65
var _quiet_zone_cleared: bool = false
var _mothership_zone_cleared: bool = false

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
	if get_tree().current_scene:
		get_tree().current_scene.add_child.call_deferred(_enemies_container)
	elif get_parent():
		get_parent().add_child.call_deferred(_enemies_container)
	else:
		add_child.call_deferred(_enemies_container)


func _update_target_ratios() -> void:
	if not path_follower:
		return
	var path3d: Path3D = path_follower.get_parent() as Path3D
	if not path3d or not path3d.curve or path3d.curve.point_count == 0:
		return

	var curve: Curve3D = path3d.curve
	var total_len: float = maxf(1.0, curve.get_baked_length())

	_target_ratio_1 = _get_point_ratio(curve, wave_1_point, total_len)
	_target_ratio_1_alert = _get_point_ratio(curve, maxi(0, wave_1_point - 1), total_len)
	_target_ratio_2 = _get_point_ratio(curve, wave_2_point, total_len)
	_target_ratio_warning_battlecruiser = _get_point_ratio(curve, warning_battlecruiser_point, total_len)
	_target_ratio_bomber = _get_point_ratio(curve, wave_bomber_point, total_len)
	_target_ratio_3 = _get_point_ratio(curve, wave_3_point, total_len)

	# Limpeza de inimigos remanescentes no ponto 22 (antes do bomber)
	_quiet_zone_start_ratio = _get_point_ratio(curve, 22, total_len)
	# Limpeza antes da Mothership no ponto 30
	_mothership_zone_clear_ratio = _get_point_ratio(curve, 30, total_len)

	# Penúltimo ponto do nível para debandada dos inimigos restantes
	var penultimate_idx: int = maxi(0, curve.point_count - 2)
	_penultimate_ratio = _get_point_ratio(curve, penultimate_idx, total_len)


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

	# 0. Áudio: Alerta de naves inimigas (ponto anterior à Wave 1)
	if not _alert_enemy_ships_triggered and current_progress >= _target_ratio_1_alert:
		_alert_enemy_ships_triggered = true
		_play_audio_alert(AlertEnemyShipsSound)

	# 0.5 Áudio: Alerta de Battlecruiser no Ponto 21
	if not _warning_battlecruiser_triggered and current_progress >= _target_ratio_warning_battlecruiser:
		_warning_battlecruiser_triggered = true
		_play_audio_alert(WarningBattlecruiserSound)

	# 1. Limpeza de inimigos remanescentes das waves anteriores antes de novos eventos
	if not _quiet_zone_cleared and current_progress >= _quiet_zone_start_ratio:
		_quiet_zone_cleared = true
		_clear_all_active_enemies()

	if not _mothership_zone_cleared and current_progress >= _mothership_zone_clear_ratio:
		_mothership_zone_cleared = true
		_clear_all_active_enemies()

	# 2. Penúltimo ponto: os inimigos que restarem aceleram para fora do nível
	if current_progress >= _penultimate_ratio:
		if not _penultimate_exit_triggered:
			_penultimate_exit_triggered = true
			_dismiss_all_active_enemies()

	# 3. Gatilhos de ondas
	if not _wave_1_triggered and current_progress >= _target_ratio_1:
		_wave_1_triggered = true
		_spawn_wave_1()

	if not _wave_2_triggered and current_progress >= _target_ratio_2:
		_wave_2_triggered = true
		_spawn_wave_2()

	if not _wave_bomber_triggered and current_progress >= _target_ratio_bomber:
		_wave_bomber_triggered = true
		_spawn_bomber()

	if not _wave_3_triggered and current_progress >= _target_ratio_3:
		_wave_3_triggered = true
		_spawn_wave_3()


func _clear_all_active_enemies() -> void:
	for enemy in _active_enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	_active_enemies.clear()


func _dismiss_all_active_enemies() -> void:
	for enemy in _active_enemies:
		if is_instance_valid(enemy):
			if enemy.has_method("force_exit"):
				enemy.force_exit()


func _dismiss_non_bomber_enemies() -> void:
	for enemy in _active_enemies:
		if is_instance_valid(enemy) and not (enemy is EnemyBomber or enemy.name.to_lower().contains("bomber")):
			if enemy.has_method("force_exit"):
				enemy.force_exit()


# ---------------------------------------------------------------------------
# Wave 1: 5 Scouts (Starship.002) no Mundo 3D (3 Líderes com rasante Direita/Esquerda/Cima)
# ---------------------------------------------------------------------------


func _spawn_wave_1() -> void:
	wave_started.emit(1, "Wave 1: Scout Squadron")

	var info: Dictionary = _get_point_info(wave_1_point)
	var base_pos: Vector3 = info["position"]
	var fwd: Vector3 = info["forward"]

	var configs: Array[Dictionary] = [
		{ "side": 1.0, "delay": 0.0, "cinematic_lead": true, "lane": 0 },   # Líder 1: Rasante Direita
		{ "side": -1.0, "delay": 0.45, "cinematic_lead": true, "lane": 1 }, # Líder 2: Rasante Esquerda
		{ "side": 1.0, "delay": 0.90, "cinematic_lead": true, "lane": 2 },  # Líder 3: Rasante por Cima
		{ "side": -1.0, "delay": 2.8, "cinematic_lead": false, "lane": 0 }, # Flanco Esquerdo
		{ "side": 1.0, "delay": 4.2, "cinematic_lead": false, "lane": 0 },  # Flanco Direito
	]

	for cfg: Dictionary in configs:
		var timer: SceneTreeTimer = get_tree().create_timer(cfg["delay"])
		timer.timeout.connect(func():
			var scout: EnemyScout = scout_scene.instantiate() as EnemyScout
			if not scout:
				return

			if cfg["cinematic_lead"]:
				scout.is_cinematic_entrance = true

			_add_enemy_to_world(scout)
			scout.setup_flight(base_pos, fwd, cfg["side"], 55.0, cfg["lane"])
			_register_enemy(scout)
		)


# ---------------------------------------------------------------------------
# Wave 2: 5 Caças Táticos Fighters (Starship.v2) no Mundo 3D (Dupla de Líderes em rasante sincronizado)
# ---------------------------------------------------------------------------

func _spawn_wave_2() -> void:
	wave_started.emit(2, "Wave 2: Tactical Fighters")

	var info: Dictionary = _get_point_info(wave_2_point)
	var base_pos: Vector3 = info["position"]
	var fwd: Vector3 = info["forward"]

	var configs: Array[Dictionary] = [
		{
			"b_type": 0,
			"delay": 0.0,
			"cinematic_lead": true,
			"lane": 0, # Líder 1: Rasante Direita
			"cinematic_exit": false
		},
		{
			"b_type": 0,
			"delay": 0.08, # Quase ao mesmo tempo que o Líder 1
			"cinematic_lead": true,
			"lane": 1, # Líder 2: Rasante Esquerda (dupla sincronizada)
			"cinematic_exit": false
		},
		{
			"b_type": 0, # Caça 3: Mergulho frontal tático à frente
			"delay": 2.5,
			"cinematic_lead": false,
			"lane": 0,
			"cinematic_exit": false
		},
		{
			"b_type": 1, # Caça 4: Flanco Esquerdo
			"delay": 4.0,
			"cinematic_lead": false,
			"lane": 0,
			"cinematic_exit": false
		},
		{
			"b_type": 2, # Caça 5: Flanco Direito com rasante de saída
			"delay": 5.5,
			"cinematic_lead": false,
			"lane": 0,
			"cinematic_exit": true
		}
	]

	for cfg: Dictionary in configs:
		var timer: SceneTreeTimer = get_tree().create_timer(cfg["delay"])
		timer.timeout.connect(func():
			var fighter: EnemyFighter = fighter_scene.instantiate() as EnemyFighter
			if not fighter:
				return

			if cfg["cinematic_lead"]:
				fighter.is_cinematic_entrance = true
			if cfg["cinematic_exit"]:
				fighter.is_cinematic_exit = true

			_add_enemy_to_world(fighter)
			fighter.setup_fighter(base_pos, fwd, cfg["b_type"], cfg["lane"])
			_register_enemy(fighter)
		)


# ---------------------------------------------------------------------------
# Wave Bomber: Bombardeiro Pesado no Ponto 25 (Rasante + Fileira de Bombas)
# ---------------------------------------------------------------------------

func _spawn_bomber() -> void:
	wave_started.emit(25, "Enemy Bomber Encounter")

	# Se houver qualquer outra nave inimiga ativa na cena, faz elas saírem cinematograficamente após o delay configurado
	if bomber_dismiss_delay > 0.0:
		var dismiss_timer: SceneTreeTimer = get_tree().create_timer(bomber_dismiss_delay)
		dismiss_timer.timeout.connect(func():
			_dismiss_non_bomber_enemies()
		)
	else:
		_dismiss_non_bomber_enemies()

	var info: Dictionary = _get_point_info(wave_bomber_point)
	var base_pos: Vector3 = info["position"]
	var fwd: Vector3 = info["forward"]

	var bomber: Node3D = bomber_scene.instantiate() as Node3D
	if not bomber:
		return

	_add_enemy_to_world(bomber)
	if bomber.has_method("setup_bomber"):
		bomber.setup_bomber(base_pos, fwd, 1.0)
	_register_enemy(bomber)





# ---------------------------------------------------------------------------
# Wave 3: 3 Cruzadores Heavy (Starship.v3) no Mundo 3D (ponto 37)
# ---------------------------------------------------------------------------

func _spawn_wave_3() -> void:
	wave_started.emit(3, "Wave 3: Heavy Gunships")

	var info: Dictionary = _get_point_info(wave_3_point)
	var base_pos: Vector3 = info["position"]
	var fwd: Vector3 = info["forward"]

	var configs: Array[Dictionary] = [
		{ "side": 1.0, "delay": 0.0 },
		{ "side": -1.0, "delay": 1.8 },
		{ "side": 1.0, "delay": 3.6 },
	]

	for cfg: Dictionary in configs:
		var timer: SceneTreeTimer = get_tree().create_timer(cfg["delay"])
		timer.timeout.connect(func():
			var heavy: EnemyHeavy = heavy_scene.instantiate() as EnemyHeavy
			if not heavy:
				return

			_add_enemy_to_world(heavy)
			heavy.setup_heavy(base_pos, fwd, cfg["side"])
			_register_enemy(heavy)
		)


# ---------------------------------------------------------------------------
# Helpers de Registro e Hierarquia
# ---------------------------------------------------------------------------

func _add_enemy_to_world(enemy: Node3D) -> void:
	if is_instance_valid(_enemies_container) and _enemies_container.is_inside_tree():
		_enemies_container.add_child(enemy)
	elif get_tree().current_scene:
		get_tree().current_scene.add_child(enemy)
	elif get_parent():
		get_parent().add_child(enemy)
	else:
		add_child(enemy)


func _register_enemy(enemy: Node) -> void:
	_active_enemies.append(enemy)
	if enemy.has_signal("enemy_destroyed"):
		enemy.connect("enemy_destroyed", _on_enemy_destroyed)
	enemy.tree_exiting.connect(func():
		_active_enemies.erase(enemy)
	)


func _on_enemy_destroyed(enemy: Node, _score: int) -> void:
	_active_enemies.erase(enemy)


func _play_audio_alert(stream: AudioStream) -> void:
	if not stream:
		return
	var audio_player := AudioStreamPlayer.new()
	audio_player.stream = stream
	audio_player.bus = "Master"
	audio_player.finished.connect(audio_player.queue_free)
	add_child(audio_player)
	audio_player.play()
