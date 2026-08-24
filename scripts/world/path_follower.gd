class_name PathFollower
extends PathFollow3D

## Avanca automaticamente ao longo da trajetoria definida por um Path3D pai.
## A CAMERA (filha deste no) acompanha o Path3D.
## A camera olha na direcao do movimento (tangente da curva), sem "strafe".
## A direcao de mira e suavizada para que as mudancas de direcao sejam fluidas
## (sem "socos"), mantendo a camera sempre apontada para onde se desloca.

# ---------------------------------------------------------------------------
# Exportacoes e Configuracoes
# ---------------------------------------------------------------------------

@export_category("Movimento ao Longo do Path")
@export var forward_speed: float = 65.0  ## Velocidade base (unidades por segundo ao longo da curva)
## Curva de velocidade opcional: eixo X = progresso do caminho (0 a 1),
## eixo Y = multiplicador de velocidade (0 = parado, 1 = velocidade base, 2 = dobro).
@export var speed_curve: Curve

@export_category("Suavizacao da Curva")
@export var look_ahead: float = 5.0  ## Distancia a frente (unidades) usada para mirar.
@export var turn_smoothing: float = 4.0  ## Rapidez de suavizar a direcao

@export_category("Tilt da Curva (Bank)")
@export var tilt_intensity: float = 0.25  ## Intensidade do tilt nas curvas
@export var tilt_smoothing: float = 3.0  ## Suavizacao do tilt
@export_range(0.0, 90.0) var max_tilt_degrees: float = 35.0  ## Angulo maximo de inclinacao (graus)

@export_category("Giro em Parafuso (Barrel Roll)")
@export var enable_barrel_roll: bool = true  ## Ativa o efeito de giro em parafuso
@export var roll_start_point: int = 34  ## Ponto da curva onde inicia o giro
@export var roll_end_point: int = 38  ## Ponto da curva onde completa o giro
@export var roll_direction: float = 1.0  ## 1.0 = horario, -1.0 = anti-horario
@export_range(0.0, 1.0) var roll_start_ratio: float = -1.0  ## Opcional: sobrescreve por ratio
@export_range(0.0, 1.0) var roll_end_ratio: float = -1.0  ## Opcional: sobrescreve por ratio

# ---------------------------------------------------------------------------
# Estado Interno
# ---------------------------------------------------------------------------

var _paused: bool = false
var _speed_multiplier: float = 1.0
var _smoothed_forward: Vector3 = Vector3.ZERO
var _forward_initialized: bool = false
var _smoothed_tilt: float = 0.0  ## Tilt suavizado (roll em radianos)
var _prev_forward: Vector3 = Vector3.ZERO  ## Direcao anterior
var _barrel_roll_angle: float = 0.0  ## Rotacao adicional de roll em radianos

# ---------------------------------------------------------------------------
# Ciclo de Vida
# ---------------------------------------------------------------------------

func _ready() -> void:
	rotation_mode = RotationMode.ROTATION_NONE
	_forward_initialized = false
	_prev_forward = Vector3.ZERO
	_align_to_path(0.016)


func _physics_process(delta: float) -> void:
	if _paused:
		return

	# Limita o delta para no máximo 50ms para evitar saltos bruscos no primeiro frame pós-carregamento
	var dt := minf(delta, 0.05)
	progress += _current_speed() * dt
	_align_to_path(dt)


# ---------------------------------------------------------------------------
# Velocidade atual
# ---------------------------------------------------------------------------

func _current_speed() -> float:
	var base_speed := forward_speed
	if speed_curve and speed_curve.point_count > 0:
		var parent_path := get_parent() as Path3D
		var total := 1.0
		if parent_path and parent_path.curve:
			total = maxf(parent_path.curve.get_baked_length(), 0.001)
		var normalized := clampf(progress / total, 0.0, 1.0)
		var factor := speed_curve.sample_baked(normalized)
		base_speed = forward_speed * clampf(factor, 0.1, 10.0)
	return base_speed * _speed_multiplier


# ---------------------------------------------------------------------------
# Alinhamento da Direcao
# ---------------------------------------------------------------------------

func _align_to_path(delta: float) -> void:
	var curve := get_parent() as Path3D
	if not curve or not curve.curve or curve.curve.point_count < 2:
		return

	var c: Curve3D = curve.curve
	var first_point := c.get_point_position(0)
	if first_point.length_squared() < 0.0001 and c.point_count > 1:
		first_point = c.get_point_position(1)
		if first_point.length_squared() < 0.0001:
			return

	var here := c.sample_baked(progress, true)
	var ahead := c.sample_baked(progress + look_ahead, true)
	var raw_forward := ahead - here
	if raw_forward.length_squared() < 0.000001:
		return
	raw_forward = raw_forward.normalized()

	if not _forward_initialized:
		_smoothed_forward = raw_forward
		_forward_initialized = true

	var t := 1.0 - exp(-turn_smoothing * delta)
	_smoothed_forward = _smoothed_forward.slerp(raw_forward, t).normalized()
	var forward := _smoothed_forward

	# Bank / Tilt (com amortecimento na partida para evitar solavancos iniciais)
	var angular_velocity: float = 0.0
	if _prev_forward.length_squared() > 0.0001:
		var dot := clampf(_prev_forward.dot(forward), -1.0, 1.0)
		angular_velocity = acos(dot) / maxf(delta, 0.0001)
		var cross := _prev_forward.cross(forward)
		var turn_sign: float = signf(cross.y)
		angular_velocity = clampf(angular_velocity * turn_sign, -12.0, 12.0)
	
	_prev_forward = forward
	
	# Escala o tilt pela velocidade da nave para que a câmera não dê solavancos angulares ao acelerar do zero
	var speed_factor := clampf(_current_speed() / maxf(forward_speed * 0.3, 0.001), 0.0, 1.0)
	var target_tilt: float = -angular_velocity * tilt_intensity * speed_factor
	var max_tilt_rad := deg_to_rad(max_tilt_degrees)
	target_tilt = clampf(target_tilt, -max_tilt_rad, max_tilt_rad)
	
	var tilt_t := 1.0 - exp(-tilt_smoothing * delta)
	_smoothed_tilt = lerpf(_smoothed_tilt, target_tilt, tilt_t)
	
	# Giro em Parafuso (Barrel Roll)
	var barrel_roll_angle := _calculate_barrel_roll_angle(c)
	_barrel_roll_angle = barrel_roll_angle

	var up := Vector3.UP
	var total_roll := _smoothed_tilt + _barrel_roll_angle
	var tilted_up := up.rotated(forward, total_roll)

	var right := forward.cross(tilted_up).normalized()
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	var corrected_up := right.cross(forward).normalized()

	global_transform.basis = Basis(right, corrected_up, -forward).orthonormalized()


# ---------------------------------------------------------------------------
# Calculo do Giro em Parafuso (Curva Organica)
# ---------------------------------------------------------------------------

func _calculate_barrel_roll_angle(c: Curve3D) -> float:
	if not enable_barrel_roll or c == null or c.point_count < 2:
		return 0.0

	var start_offset: float = 0.0
	var end_offset: float = 0.0
	var total_len := maxf(c.get_baked_length(), 0.001)

	if roll_start_ratio >= 0.0 and roll_end_ratio > roll_start_ratio:
		start_offset = roll_start_ratio * total_len
		end_offset = roll_end_ratio * total_len
	else:
		if roll_start_point >= 0 and roll_start_point < c.point_count and roll_end_point >= 0 and roll_end_point < c.point_count:
			var p_start := c.get_point_position(roll_start_point)
			var p_end := c.get_point_position(roll_end_point)
			start_offset = c.get_closest_offset(p_start)
			end_offset = c.get_closest_offset(p_end)
		else:
			return 0.0

	if end_offset <= start_offset:
		return 0.0

	if progress < start_offset or progress > end_offset:
		return 0.0

	var t := clampf((progress - start_offset) / (end_offset - start_offset), 0.0, 1.0)
	var organic_t := t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
	var full_rotation := TAU * roll_direction
	return organic_t * full_rotation


# ---------------------------------------------------------------------------
# API Publica
# ---------------------------------------------------------------------------

func set_paused(paused: bool) -> void:
	_paused = paused


func set_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = multiplier


func reset_progress() -> void:
	progress = 0.0
	_forward_initialized = false