class_name EnemyScout
extends "res://scripts/enemies/enemy_base.gd"

## Inimigo Caça Leve / Reconhecimento (Starship.002) no Mundo 3D Real.
## Voa à frente do jogador ao longo do cânion, realizando manobras e curvas
## senoidais em ritmo suave de percurso para permitir combate ideal.

@export var flight_speed: float = 240.0  ## Velocidade de voo no mundo 3D (m/s)
@export var swoop_frequency: float = 1.8  ## Frequência da oscilação de voo
@export var swoop_amplitude: float = 22.0  ## Amplitude lateral do voo
@export var vertical_amplitude: float = 8.0  ## Amplitude vertical
@export var start_side: float = 1.0  ## 1.0 = curva pela direita, -1.0 = esquerda

var flight_direction: Vector3 = Vector3.FORWARD
var _time_alive: float = 0.0
var _has_fired: bool = false
var _initial_global_origin: Vector3 = Vector3.ZERO
var _right_vec: Vector3 = Vector3.RIGHT
var _up_vec: Vector3 = Vector3.UP


func _ready() -> void:
	max_hp = 1
	score_value = 100
	super._ready()
	_initial_global_origin = global_position

	if flight_direction.length_squared() < 0.001:
		flight_direction = -global_basis.z.normalized()
	else:
		flight_direction = flight_direction.normalized()

	_right_vec = flight_direction.cross(Vector3.UP).normalized()
	if _right_vec.length_squared() < 0.001:
		_right_vec = Vector3.RIGHT
	_up_vec = _right_vec.cross(flight_direction).normalized()


func setup_flight(start_pos: Vector3, dir: Vector3, side: float = 1.0, speed: float = 240.0) -> void:
	global_position = start_pos
	_initial_global_origin = start_pos
	flight_direction = dir.normalized()
	start_side = side
	flight_speed = speed

	_right_vec = flight_direction.cross(Vector3.UP).normalized()
	if _right_vec.length_squared() < 0.001:
		_right_vec = Vector3.RIGHT
	_up_vec = _right_vec.cross(flight_direction).normalized()

	look_at(global_position + flight_direction, _up_vec)


func _physics_process(delta: float) -> void:
	_time_alive += delta

	# Posição ao longo da rota do cânion à frente do jogador
	var forward_travel: Vector3 = flight_direction * (flight_speed * _time_alive)
	var lateral_offset: Vector3 = _right_vec * (sin(_time_alive * swoop_frequency) * swoop_amplitude * start_side)
	var vertical_offset: Vector3 = _up_vec * (cos(_time_alive * swoop_frequency * 0.7) * vertical_amplitude)

	global_position = _initial_global_origin + forward_travel + lateral_offset + vertical_offset

	# Rotação suave no sentido do voo
	var next_pos: Vector3 = global_position + flight_direction * 2.0 + (_right_vec * cos(_time_alive * swoop_frequency) * swoop_amplitude * start_side * 0.2)
	look_at(next_pos, _up_vec)

	# Banking roll nas curvas
	var bank_angle: float = -cos(_time_alive * swoop_frequency) * 0.4 * start_side
	rotate_object_local(Vector3(0, 0, 1), bank_angle)

	var player: Node3D = _get_player_node()
	if player:
		var to_scout: Vector3 = global_position - player.global_position
		var dist_to_player: float = global_position.distance_to(player.global_position)

		# Dispara quando o jogador estiver a uma distância de combate visível
		if not _has_fired and dist_to_player <= 220.0 and to_scout.dot(flight_direction) > 0.0:
			_has_fired = true
			_shoot()

		# Despawna quando o jogador ultrapassa a nave e fica na frente dela (sem perseguição)
		if to_scout.dot(flight_direction) < -40.0 or _time_alive > 12.0:
			queue_free()
	elif _time_alive > 14.0:
		queue_free()


func _shoot() -> void:
	# Dispara projétil para trás na direção do jogador que está se aproximando
	var shoot_pos: Vector3 = global_position + (-flight_direction * 2.0)
	var player: Node3D = _get_player_node()
	var dir_to_player: Vector3 = -flight_direction
	if player:
		dir_to_player = (player.global_position - global_position).normalized()
	fire_bullet(shoot_pos, dir_to_player)
