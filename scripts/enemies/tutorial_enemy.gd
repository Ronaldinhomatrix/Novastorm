class_name TutorialEnemy
extends EnemyScout

## Inimigo exclusivo do Tutorial para Novastorm.
## Mantém voo constante em formação à frente do jogador ao longo do Path3D,
## sem disparar armas hostis e sem fugir da tela.
## Suporta modo imune a lasers primários para a etapa de mísseis secundários.

var immune_to_lasers: bool = false
var target_dist_ahead: float = 65.0
var target_lat: float = 0.0
var target_vert: float = 4.0
var _anim_time: float = 0.0
var _entry_progress: float = 0.0
var _entry_duration: float = 1.0
var _start_dist: float = 120.0
var _is_holding_formation: bool = false


func _ready() -> void:
	max_hp = 1
	current_hp = 1
	score_value = 100
	enable_engine_sound = true
	super._ready()


func setup_tutorial_formation(lat: float, dist: float = 65.0, vert: float = 4.0, laser_immune: bool = false) -> void:
	target_lat = lat
	target_dist_ahead = dist
	target_vert = vert
	immune_to_lasers = laser_immune
	_start_dist = dist + 60.0
	_current_distance = _start_dist
	_current_lateral = lat
	_current_vertical = vert + 6.0
	_entry_progress = 0.0
	_is_holding_formation = false

	# Garante posicionamento imediato na curva
	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]
	_orient_ship(frame["forward"], frame["up"], 0.0, true)


func _physics_process(delta: float) -> void:
	_anim_time += delta

	# Entrada suave na formação à frente do jogador
	if not _is_holding_formation:
		_entry_progress = clampf(_entry_progress + (delta / maxf(0.01, _entry_duration)), 0.0, 1.0)
		var t := _entry_progress * _entry_progress * (3.0 - 2.0 * _entry_progress)
		_current_distance = lerpf(_start_dist, target_dist_ahead, t)
		_current_lateral = target_lat
		_current_vertical = lerpf(target_vert + 6.0, target_vert, t)
		if _entry_progress >= 1.0:
			_is_holding_formation = true
	else:
		# Hovering suave orgânico para o alvo não parecer estático
		var bob := sin(_anim_time * 2.2 + target_lat) * 0.6
		var drift := cos(_anim_time * 1.5 + target_lat) * 0.35
		_current_distance = target_dist_ahead
		_current_lateral = target_lat + drift
		_current_vertical = target_vert + bob

	_curve_offset = _get_player_progress() + _current_distance
	var frame := _sample_curve_frame(_curve_offset, _current_lateral, _current_vertical)
	global_position = frame["position"]

	var bank := clampf(-(_current_lateral / 25.0) * 0.25, -0.3, 0.3)
	_orient_ship(frame["forward"], frame["up"], bank)


func _on_area_entered(area: Area3D) -> void:
	if _is_dead or is_invulnerable:
		return
	if area.is_in_group("enemy_bullets"):
		return

	var is_missile := area is PlayerMissile or area.is_in_group("player_missiles")
	var is_bullet := area.is_in_group("player_bullets") or area is Bullet or (area.name.begins_with("Bullet") and not area.name.begins_with("EnemyBullet"))

	if is_missile:
		take_damage(3)
		return

	if is_bullet:
		if immune_to_lasers:
			_spawn_spark(global_position, -global_basis.z)
			if is_instance_valid(area) and not area.is_queued_for_deletion():
				area.queue_free()
			return
		else:
			take_damage(1)
			if is_instance_valid(area) and not area.is_queued_for_deletion():
				area.queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _is_dead or is_invulnerable:
		return
	if body.is_in_group("enemy_bullets"):
		return

	var is_missile := body is PlayerMissile or body.is_in_group("player_missiles")
	var is_bullet := body.is_in_group("player_bullets") or body is Bullet

	if is_missile:
		take_damage(3)
		return

	if is_bullet:
		if immune_to_lasers:
			_spawn_spark(global_position, -global_basis.z)
			if is_instance_valid(body) and not body.is_queued_for_deletion():
				body.queue_free()
			return
		else:
			take_damage(1)
			if is_instance_valid(body) and not body.is_queued_for_deletion():
				body.queue_free()
