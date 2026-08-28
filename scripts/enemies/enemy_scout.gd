class_name EnemyScout
extends "res://scripts/enemies/enemy_base.gd"

## Inimigo Caça Leve / Reconhecimento (Starship.002) no Mundo 3D Real.
## Voa pelo espaço aéreo do cânion em trajetória tridimensional,
## realizando curvas senoidais e inclinação (banking) nas curvas.

@export var flight_speed: float = 115.0  ## Velocidade de voo no mundo 3D (m/s)
@export var swoop_frequency: float = 1.8  ## Frequência da oscilação de voo
@export var swoop_amplitude: float = 18.0  ## Amplitude lateral do voo
@export var vertical_amplitude: float = 6.0  ## Amplitude vertical
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


func setup_flight(start_pos: Vector3, dir: Vector3, side: float = 1.0, speed: float = 115.0) -> void:
	global_position = start_pos
	_initial_global_origin = start_pos
	flight_direction = dir.normalized()
	start_side = side
	flight_speed = speed

	_right_vec = flight_direction.cross(Vector3.UP).normalized()
	if _right_vec.length_squared() < 0.001:
		_right_vec = Vector3.RIGHT
	_up_vec = _right_vec.cross(flight_direction).normalized()

	# Alinha a nave com a direção de voo
	look_at(global_position + flight_direction, _up_vec)


func _physics_process(delta: float) -> void:
	_time_alive += delta

	# Posição base ao longo do vetor de voo
	var forward_travel: Vector3 = flight_direction * (flight_speed * _time_alive)
	var lateral_offset: Vector3 = _right_vec * (sin(_time_alive * swoop_frequency) * swoop_amplitude * start_side)
	var vertical_offset: Vector3 = _up_vec * (cos(_time_alive * swoop_frequency * 0.7) * vertical_amplitude)

	global_position = _initial_global_origin + forward_travel + lateral_offset + vertical_offset

	# Rotação suave: aponta o nariz para o vetor de deslocamento com banking
	var next_pos: Vector3 = global_position + flight_direction * 2.0 + (_right_vec * cos(_time_alive * swoop_frequency) * swoop_amplitude * start_side * 0.2)
	look_at(next_pos, _up_vec)

	# Inclinação lateral (Banking roll nas curvas)
	var bank_angle: float = -cos(_time_alive * swoop_frequency) * 0.45 * start_side
	rotate_object_local(Vector3(0, 0, 1), bank_angle)

	# Disparo de oportunidade ao se aproximar da nave do jogador
	var player: Node3D = _get_player_node()
	if player:
		var dist_to_player: float = global_position.distance_to(player.global_position)
		if not _has_fired and dist_to_player <= 260.0:
			_has_fired = true
			_shoot()

		# Despawna se a nave já ultrapassou o jogador e ficou muito para trás
		var to_scout: Vector3 = global_position - player.global_position
		if to_scout.dot(flight_direction) > 180.0 or _time_alive > 14.0:
			queue_free()
	elif _time_alive > 15.0:
		queue_free()


func _shoot() -> void:
	var shoot_pos: Vector3 = global_position + (flight_direction * 2.5)
	fire_towards_player(shoot_pos, 0.85)
