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
## Zonas de velocidade personalizadas entre pontos do Path3D (ex: ponto 13 ao 18 a 150 u/s)
@export var speed_zones: Array[PathSpeedZone] = []
## Curva de velocidade opcional: eixo X = progresso do caminho (0 a 1),
## eixo Y = multiplicador de velocidade (0 = parado, 1 = velocidade base, 2 = dobro).
@export var speed_curve: Curve

@export_category("Suavizacao da Curva")
@export var look_ahead: float = 5.0  ## Distancia a frente (unidades) usada para mirar.
@export var turn_smoothing: float = 4.0  ## Rapidez de suavizar a direcao

@export_category("Tilt da Curva (Bank)")
@export var tilt_intensity: float = 0.25  ## Intensidade do tilt nas curvas
@export var tilt_smoothing: float = 3.5  ## Suavizacao do tilt
@export_range(0.0, 90.0) var max_tilt_degrees: float = 30.0  ## Angulo maximo de inclinacao (graus)

@export_category("Giro em Parafuso (Barrel Roll)")
@export var enable_barrel_roll: bool = true  ## Ativa o efeito de giro em parafuso
@export var roll_start_point: int = 34  ## Ponto da curva onde inicia o giro
@export var roll_end_point: int = 38  ## Ponto da curva onde completa o giro
@export var roll_direction: float = 1.0  ## 1.0 = horario, -1.0 = anti-horario
@export_range(0.0, 1.0) var roll_start_ratio: float = -1.0  ## Opcional: sobrescreve por ratio
@export_range(0.0, 1.0) var roll_end_ratio: float = -1.0  ## Opcional: sobrescreve por ratio

# Som de manobra tocado quando o giro em parafuso (barrel roll) da câmera inicia.
const ManeuverSound := preload("res://assets/audio/maneuver1.ogg")

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

# Player de áudio da manobra (barrel roll) + controle de disparo único.
var _maneuver_player: AudioStreamPlayer = null
var _barrel_roll_sound_played: bool = false

# ---------------------------------------------------------------------------
# Ciclo de Vida
# ---------------------------------------------------------------------------

func _ready() -> void:
	loop = false
	rotation_mode = RotationMode.ROTATION_NONE
	_forward_initialized = false
	_prev_forward = Vector3.ZERO
	# Prepara o player de áudio para o som de manobra do barrel roll.
	_maneuver_player = AudioStreamPlayer.new()
	_maneuver_player.stream = ManeuverSound
	_maneuver_player.bus = "Master"
	_maneuver_player.volume_db = 0.0
	add_child(_maneuver_player)
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
	var parent_path := get_parent() as Path3D
	var c: Curve3D = parent_path.curve if parent_path else null

	# 1. Zonas de Velocidade por Pontos (Prioridade alta para trechos específicos)
	if c and speed_zones.size() > 0:
		for zone in speed_zones:
			if not zone:
				continue
			if zone.start_point < 0 or zone.start_point >= c.point_count:
				continue
			if zone.end_point < 0 or zone.end_point >= c.point_count:
				continue

			var s_off := c.get_closest_offset(c.get_point_position(zone.start_point))
			var e_off := c.get_closest_offset(c.get_point_position(zone.end_point))
			if e_off <= s_off:
				continue

			var zone_target := zone.target_speed if zone.target_speed > 0.0 else (forward_speed * zone.speed_multiplier)
			var blend := maxf(zone.blend_distance, 0.0)

			# Verifica se está no intervalo da zona (incluindo margens de blend)
			if progress >= (s_off - blend) and progress <= (e_off + blend):
				var weight := 1.0
				if blend > 0.0:
					if progress < s_off:
						# Entrada suave na zona
						weight = smoothstep(s_off - blend, s_off, progress)
					elif progress > e_off:
						# Saída suave da zona
						weight = 1.0 - smoothstep(e_off, e_off + blend, progress)
				base_speed = lerpf(base_speed, zone_target, weight)

	# 2. Curva Global de Velocidade (Opcional)
	if speed_curve and speed_curve.point_count > 0 and c:
		var total := maxf(c.get_baked_length(), 0.001)
		var normalized := clampf(progress / total, 0.0, 1.0)
		var factor := speed_curve.sample_baked(normalized)
		base_speed = base_speed * clampf(factor, 0.1, 10.0)

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

	# --- Bank / Tilt preditivo baseado na curvatura da pista ---
	# Segmentos têm ~500m: amostramos à frente proporcionalmente à velocidade para capturar a curva completa
	var look_dist := maxf(_current_speed() * 0.5, 150.0)
	var ahead_sample := c.sample_baked(progress + look_dist, true)
	var far_sample := c.sample_baked(progress + look_dist * 2.2, true)
	
	var here_tangent := raw_forward
	var ahead_tangent := (far_sample - ahead_sample).normalized()
	
	# Produto vetorial no plano horizontal determina a direção e intensidade da curva
	var cross_y := here_tangent.z * ahead_tangent.x - here_tangent.x * ahead_tangent.z
	var curve_curvature := clampf(cross_y * 2.0, -1.0, 1.0)
	
	# Converte a curvatura em ângulo de inclinação (Bank forte nas curvas)
	var speed_factor := clampf(_current_speed() / maxf(forward_speed * 0.3, 0.001), 0.0, 1.0)
	var max_tilt_rad := deg_to_rad(max_tilt_degrees)
	var target_tilt: float = -curve_curvature * max_tilt_rad * speed_factor
	
	var tilt_t := 1.0 - exp(-tilt_smoothing * delta)
	_smoothed_tilt = lerpf(_smoothed_tilt, target_tilt, tilt_t)
	
	# Giro em Parafuso (Barrel Roll)
	var barrel_roll_angle := _calculate_barrel_roll_angle(c)
	_barrel_roll_angle = barrel_roll_angle
	_update_barrel_roll_sound(c)

	var up := Vector3.UP
	var total_roll := _smoothed_tilt + _barrel_roll_angle
	var tilted_up := up.rotated(forward, total_roll)

	var right := forward.cross(tilted_up).normalized()
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	var corrected_up := right.cross(forward).normalized()

	global_transform.basis = Basis(right, corrected_up, -forward).orthonormalized()


## Retorna o tilt da curva em radianos (inclinação pura nas curvas, sem barrel roll)
func get_curve_tilt() -> float:
	return _smoothed_tilt


## Retorna o tilt da curva em radianos (inclinação nas curvas)
func get_smoothed_tilt() -> float:
	return _smoothed_tilt


## Indica se o PathFollower está executando um barrel roll no momento
func is_in_barrel_roll() -> bool:
	return absf(_barrel_roll_angle) > 0.001


## Retorna o ângulo atual de barrel roll em radianos
func get_barrel_roll_angle() -> float:
	return _barrel_roll_angle


## Retorna a inclinação total (tilt de curva + barrel roll) em radianos
func get_total_tilt() -> float:
	return _smoothed_tilt + _barrel_roll_angle


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


## Dispara o som de manobra uma única vez, exatamente quando o barrel roll
## (giro em parafuso da câmera) inicia (progresso cruza roll_start_point).
func _update_barrel_roll_sound(c: Curve3D) -> void:
	if not enable_barrel_roll or _maneuver_player == null or _barrel_roll_sound_played:
		return
	if c == null or c.point_count < 2:
		return

	var start_offset: float = 0.0
	var end_offset: float = 0.0
	var total_len := maxf(c.get_baked_length(), 0.001)

	if roll_start_ratio >= 0.0 and roll_end_ratio > roll_start_ratio:
		start_offset = roll_start_ratio * total_len
		end_offset = roll_end_ratio * total_len
	else:
		if roll_start_point >= 0 and roll_start_point < c.point_count and roll_end_point >= 0 and roll_end_point < c.point_count:
			start_offset = c.get_closest_offset(c.get_point_position(roll_start_point))
			end_offset = c.get_closest_offset(c.get_point_position(roll_end_point))
		else:
			return

	if end_offset <= start_offset:
		return
	if progress < start_offset or progress > end_offset:
		return

	_maneuver_player.pitch_scale = randf_range(0.97, 1.03)
	_maneuver_player.play()
	_barrel_roll_sound_played = true


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
	_barrel_roll_sound_played = false