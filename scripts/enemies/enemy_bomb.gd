class_name EnemyBomb
extends Area3D

## Mina de aproximação / Bomba flutuante lançada pelo Enemy Bomber.
##
## Permanece parada no espaço 3D do mundo flutuando suavemente.
## O jogador deve desviar ou destruí-la com seus tiros antes de colidir.
## - Causa 1 de dano se colidir com o jogador.
## - Possui 1 HP e explode se atingida por tiros de laser do jogador (concedendo 50 pontos).
## - Auto-destrói suavemente quando o jogador a ultrapassa e fica para trás.

signal bomb_destroyed(bomb: Node, score: int)

const ExplosionScript := preload("res://scripts/effects/explosion.gd")
const ExplosionSounds: Array[AudioStream] = [
	preload("res://assets/audio/explosion1.ogg"),
	preload("res://assets/audio/explosion2.ogg"),
]

@export var max_hp: int = 1
@export var damage: int = 1
@export var score_value: int = 50
@export var explosion_scale: float = 0.85
@export var blink_speed: float = 10.0  ## Frequência das piscadas vermelhas
@export var forward_speed: float = 46.0  ## Velocidade de deslocamento à frente
@export var lifetime: float = 13.5  ## Tempo de vida útil da mina (em segundos) até se auto-destruir suavemente

var current_hp: int = 1
var _is_exploding: bool = false
var _float_time: float = 0.0
var _age: float = 0.0
var _random_rot_axis: Vector3 = Vector3.UP
var _random_rot_speed: float = 1.0
var _move_direction: Vector3 = Vector3.FORWARD
var _has_curve: bool = false
var _curve_offset: float = 0.0
var _lateral_offset: float = 0.0
var _vertical_offset: float = 0.0

@onready var light: OmniLight3D = get_node_or_null("OmniLight3D") as OmniLight3D
@onready var core_mesh: MeshInstance3D = get_node_or_null("CoreMesh") as MeshInstance3D
@onready var beacon_group: Node3D = get_node_or_null("BeaconGroup") as Node3D

var _beacon_material: StandardMaterial3D = null


func _ready() -> void:
	current_hp = max_hp
	_age = 0.0
	_random_rot_axis = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	if _random_rot_axis.length_squared() < 0.1:
		_random_rot_axis = Vector3.UP
	_random_rot_speed = randf_range(0.8, 1.8)

	# Instancia um material local para os pontos vermelhos piscantes
	if beacon_group and beacon_group.get_child_count() > 0:
		var first_beacon := beacon_group.get_child(0) as MeshInstance3D
		if first_beacon and first_beacon.mesh:
			var orig_mat := first_beacon.mesh.surface_get_material(0)
			if orig_mat:
				_beacon_material = orig_mat.duplicate() as StandardMaterial3D
				for child in beacon_group.get_children():
					if child is MeshInstance3D and child.mesh:
						child.material_override = _beacon_material

	collision_layer = 2 | 4  # Layer 2 (inimigo atingível por tiros) e Layer 4 (projétil/perigo)
	collision_mask = 1 | 2   # Detecta jogador (Layer 1) e tiros do jogador (Layer 2)
	monitoring = true
	monitorable = true

	add_to_group("enemy_hazards")
	add_to_group("enemies")

	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func setup_bomb(initial_pos: Vector3, forward_dir: Vector3 = Vector3.ZERO, curve_off: float = -1.0, lat: float = 0.0, vert: float = 0.0) -> void:
	global_position = initial_pos
	if forward_dir.length_squared() > 0.01:
		_move_direction = forward_dir.normalized()
	else:
		_move_direction = -global_basis.z.normalized()

	if curve_off >= 0.0:
		_has_curve = true
		_curve_offset = curve_off
		_lateral_offset = lat
		_vertical_offset = vert


func _physics_process(delta: float) -> void:
	if _is_exploding:
		return

	# Controle direto de tempo de vida (ultra leve, sem consultas ao jogador ou à árvore)
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	_float_time += delta

	# Rotação suave no próprio eixo
	rotate(_random_rot_axis, _random_rot_speed * delta)

	# Flutuação e oscilação suave no ar
	var bob_y := sin(_float_time * 2.5) * 0.35
	var bob_x := cos(_float_time * 1.8) * 0.2

	# Deslocamento para a frente ao longo do percurso / direção de voo
	if _has_curve:
		_curve_offset += forward_speed * delta
		var path := _get_flight_path()
		if path and path.curve and path.curve.point_count > 1:
			var curve_pos: Vector3 = path.curve.sample_baked(_curve_offset)
			var global_center: Vector3 = path.global_transform * curve_pos
			var tangent: Vector3 = (path.curve.sample_baked(_curve_offset + 1.0) - curve_pos).normalized()
			var fwd: Vector3 = (path.global_basis * tangent).normalized()
			var right: Vector3 = fwd.cross(Vector3.UP).normalized()
			if right.length_squared() < 0.001:
				right = Vector3.RIGHT
			var up: Vector3 = right.cross(fwd).normalized()
			global_position = global_center + right * (_lateral_offset + bob_x) + up * (_vertical_offset + bob_y)
		else:
			global_position += _move_direction * (forward_speed * delta) + Vector3(bob_x, bob_y, 0.0) * delta
	else:
		global_position += _move_direction * (forward_speed * delta)

	# Piscar stroboscópico/pulsante das luzes vermelhas
	var blink_phase := fmod(_float_time * blink_speed, 1.0)
	var is_on := blink_phase < 0.45  # 45% aceso, 55% apagado
	var red_intensity := 1.0 if is_on else 0.05

	if _beacon_material:
		_beacon_material.albedo_color = Color(red_intensity, 0.02 * red_intensity, 0.02 * red_intensity, 1.0)

	if light:
		light.light_energy = 16.0 if is_on else 0.0


var _cached_flight_path: Path3D = null


func _get_flight_path() -> Path3D:
	if _cached_flight_path and is_instance_valid(_cached_flight_path):
		return _cached_flight_path
	if not is_inside_tree():
		return null

	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var p: Node = player.get_parent()
		while p:
			if p is PathFollow3D:
				_cached_flight_path = p.get_parent() as Path3D
				break
			p = p.get_parent()

	if not _cached_flight_path and get_tree().current_scene:
		_cached_flight_path = get_tree().current_scene.find_child("FlightPath", true, false) as Path3D

	return _cached_flight_path




func take_damage(amount: int = 1) -> void:
	if _is_exploding:
		return

	current_hp -= amount
	if current_hp <= 0:
		_award_score()
		_explode()


func _on_body_entered(body: Node3D) -> void:
	if _is_exploding:
		return

	# Colisão direta com o jogador (CharacterBody3D)
	if body.is_in_group("player") or body.has_method("take_damage"):
		body.take_damage(damage)
		_explode()
	elif body.is_in_group("player_bullets"):
		take_damage(1)


func _on_area_entered(area: Area3D) -> void:
	if _is_exploding:
		return

	# Tiros do jogador
	if area.is_in_group("player_bullets") or (area.name.begins_with("Bullet") and not area.name.begins_with("Enemy")):
		take_damage(1)
		if is_instance_valid(area) and not area.is_queued_for_deletion():
			area.queue_free()


func _award_score() -> void:
	bomb_destroyed.emit(self, score_value)
	var game_ctrl := get_tree().get_first_node_in_group("game_controller")
	if game_ctrl and game_ctrl.has_method("add_score"):
		game_ctrl.add_score(score_value)


func _explode() -> void:
	if _is_exploding:
		return
	_is_exploding = true

	# Explosão visual com múltiplas camadas
	var explosion: Node3D = ExplosionScript.new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	if explosion.has_method("set"):
		explosion.set("size_scale", explosion_scale)

	# Som de explosão
	if ExplosionSounds.size() > 0:
		var sound: AudioStream = ExplosionSounds.pick_random()
		var audio := AudioStreamPlayer.new()
		audio.stream = sound
		audio.bus = "Master"
		audio.volume_db = -2.0
		audio.finished.connect(audio.queue_free)
		get_tree().current_scene.add_child(audio)
		audio.play()

	queue_free()
