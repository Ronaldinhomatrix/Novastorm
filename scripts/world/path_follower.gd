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
@export var look_ahead: float = 1.0  ## Distancia a frente usada para obter a direcao imediata sem antecipacao.
@export var turn_smoothing: float = 4.5  ## Rapidez de resposta da direcao (valores altos acompanham a pista fielmente).

@export_category("Tilt da Curva (Bank / Inclinacao Lateral)")
@export var tilt_intensity: float = 0.25  ## Intensidade do tilt nas curvas
@export var tilt_smoothing: float = 4.0  ## Suavizacao do tilt
@export_range(0.0, 90.0) var max_tilt_degrees: float = 30.0  ## Angulo maximo de inclinacao lateral (graus)

@export_category("Inclinacao Vertical (Pitch / Subidas e Descidas)")
## Ativa a inclinação vertical acentuada da câmera e nave ao subir e descer a pista.
@export var enable_vertical_pitch: bool = true
## Multiplicador de intensidade da inclinação vertical (1.0 = ângulo original da pista, 1.35 = mergulhos e subidas bem visíveis e marcados).
@export_range(0.5, 3.0, 0.05) var pitch_intensity: float = 1.35
## Suavização da inclinação vertical para transições fluidas e precisas.
@export var pitch_smoothing: float = 4.5
## Ângulo máximo de inclinação vertical permitido (em graus).
@export_range(10.0, 80.0, 1.0) var max_pitch_degrees: float = 55.0

@export_category("Giro em Parafuso (Barrel Roll)")
@export var enable_barrel_roll: bool = true  ## Ativa o efeito de giro em parafuso
@export var roll_start_point: int = 34  ## Ponto da curva onde inicia o giro
@export var roll_end_point: int = 38  ## Ponto da curva onde completa o giro
@export var roll_direction: float = 1.0  ## 1.0 = horario, -1.0 = anti-horario
@export_range(0.0, 1.0) var roll_start_ratio: float = -1.0  ## Opcional: sobrescreve por ratio
@export_range(0.0, 1.0) var roll_end_ratio: float = -1.0  ## Opcional: sobrescreve por ratio

@export_category("Debug e Teste de Trechos")
## Ponto inicial para testes (0 = início padrão do nível, 15 = pula direto pro ponto 15, etc.).
@export var debug_start_point: int = 0
## Inicia a partir de uma porcentagem da pista (0.0 a 1.0). Se > 0.0, tem prioridade sobre debug_start_point.
@export_range(0.0, 1.0) var debug_start_ratio: float = 0.0
## Ponto final para loop de teste (se > debug_start_point, o trajeto fica repetindo apenas este trecho).
@export var debug_loop_point_end: int = -1

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
var _smoothed_pitch: float = 0.0  ## Pitch suavizado (em radianos)
var _prev_forward: Vector3 = Vector3.ZERO  ## Direcao anterior
var _barrel_roll_angle: float = 0.0  ## Rotacao adicional de roll em radianos
var _debug_loop_start_offset: float = -1.0
var _debug_loop_end_offset: float = -1.0

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
	_setup_debug_offsets()
	reset_progress()
	_align_to_path(0.016)


func _setup_debug_offsets() -> void:
	var parent_path := get_parent() as Path3D
	var c: Curve3D = parent_path.curve if parent_path else null
	if not c or c.point_count < 2:
		return

	var total_len := c.get_baked_length()
	if debug_start_ratio > 0.0:
		_debug_loop_start_offset = clampf(debug_start_ratio * total_len, 0.0, total_len)
	elif debug_start_point > 0:
		var p_idx := clampi(debug_start_point, 0, c.point_count - 1)
		_debug_loop_start_offset = c.get_closest_offset(c.get_point_position(p_idx))
	else:
		_debug_loop_start_offset = 0.0

	if debug_loop_point_end > debug_start_point:
		var end_idx := clampi(debug_loop_point_end, 0, c.point_count - 1)
		_debug_loop_end_offset = c.get_closest_offset(c.get_point_position(end_idx))
	else:
		_debug_loop_end_offset = -1.0


func _physics_process(delta: float) -> void:
	if _paused:
		return

	# Limita o delta para no máximo 50ms para evitar saltos bruscos no primeiro frame pós-carregamento
	var dt := minf(delta, 0.05)
	progress += _current_speed() * dt

	# Modo Loop de Trecho de Teste (se configurado debug_loop_point_end)
	if _debug_loop_end_offset > _debug_loop_start_offset and progress >= _debug_loop_end_offset:
		progress = _debug_loop_start_offset

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

	# 1. Tangente Direta Imediata no Ponto Atual (sem antecipar centenas de metros à frente)
	var sample_step := maxf(look_ahead, 0.5)
	var here := c.sample_baked(progress, true)
	var ahead := c.sample_baked(progress + sample_step, true)
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

	# 2. Bank / Tilt Lateral Imediato no Ponto da Curva (sem antecipação de centenas de metros)
	var short_ahead := c.sample_baked(progress + 8.0, true)
	var ahead_tangent := (short_ahead - ahead).normalized()
	
	# Produto vetorial no plano horizontal (X e Z) para detectar a curva atual
	var cross_y := raw_forward.z * ahead_tangent.x - raw_forward.x * ahead_tangent.z
	var curve_curvature := clampf(cross_y * 12.0, -1.0, 1.0)
	
	var speed_factor := clampf(_current_speed() / maxf(forward_speed * 0.3, 0.001), 0.0, 1.0)
	var max_tilt_rad := deg_to_rad(max_tilt_degrees)
	var target_tilt: float = -curve_curvature * max_tilt_rad * speed_factor * (tilt_intensity / 0.25)
	
	var tilt_t := 1.0 - exp(-tilt_smoothing * delta)
	_smoothed_tilt = lerpf(_smoothed_tilt, target_tilt, tilt_t)

	# 3. Inclinação Vertical (Pitch / Subidas e Descidas bem visíveis)
	var horiz_len := Vector2(forward.x, forward.z).length()
	var raw_pitch_rad := atan2(forward.y, horiz_len)
	var target_pitch := raw_pitch_rad
	if enable_vertical_pitch:
		var max_pitch_rad := deg_to_rad(max_pitch_degrees)
		target_pitch = clampf(raw_pitch_rad * pitch_intensity, -max_pitch_rad, max_pitch_rad)

	var pitch_t := 1.0 - exp(-pitch_smoothing * delta)
	_smoothed_pitch = lerpf(_smoothed_pitch, target_pitch, pitch_t)

	# 4. Construção da Direção 3D com Pitch Acentuado
	var horiz_dir := Vector3(forward.x, 0.0, forward.z)
	if horiz_dir.length_squared() > 0.0001:
		horiz_dir = horiz_dir.normalized()
	else:
		horiz_dir = Vector3.FORWARD

	var pitched_forward := (horiz_dir * cos(_smoothed_pitch) + Vector3.UP * sin(_smoothed_pitch)).normalized()

	# 5. Giro em Parafuso (Barrel Roll) e Roll Total
	var barrel_roll_angle := _calculate_barrel_roll_angle(c)
	_barrel_roll_angle = barrel_roll_angle
	_update_barrel_roll_sound(c)

	var total_roll := _smoothed_tilt + _barrel_roll_angle
	var up := Vector3.UP
	var tilted_up := up.rotated(pitched_forward, total_roll)

	var right := pitched_forward.cross(tilted_up).normalized()
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	var corrected_up := right.cross(pitched_forward).normalized()

	global_transform.basis = Basis(right, corrected_up, -pitched_forward).orthonormalized()


## Retorna o pitch da curva em radianos (inclinação vertical para cima/baixo)
func get_pitch() -> float:
	return _smoothed_pitch


## Retorna o pitch da curva em graus
func get_pitch_degrees() -> float:
	return rad_to_deg(_smoothed_pitch)


## Retorna o tilt lateral da curva em radianos (inclinação pura nas curvas, sem barrel roll)
func get_curve_tilt() -> float:
	return _smoothed_tilt


## Retorna o tilt lateral da curva em radianos (inclinação nas curvas)
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
	if _debug_loop_start_offset < 0.0:
		_setup_debug_offsets()
	progress = maxf(_debug_loop_start_offset, 0.0)
	_forward_initialized = false
	_barrel_roll_sound_played = false
	_smoothed_tilt = 0.0
	_smoothed_pitch = 0.0
	_align_to_path(0.016)


## Teletransporta o follower diretamente para um ponto específico do Path3D
func jump_to_point(point_index: int) -> void:
	var parent_path := get_parent() as Path3D
	var c: Curve3D = parent_path.curve if parent_path else null
	if not c or c.point_count == 0:
		return

	var idx := clampi(point_index, 0, c.point_count - 1)
	progress = c.get_closest_offset(c.get_point_position(idx))
	_forward_initialized = false
	_smoothed_tilt = 0.0
	_smoothed_pitch = 0.0
	_align_to_path(0.016)


## Teletransporta o follower para uma porcentagem da pista (0.0 a 1.0)
func jump_to_ratio(target_ratio: float) -> void:
	var parent_path := get_parent() as Path3D
	var c: Curve3D = parent_path.curve if parent_path else null
	if not c or c.point_count == 0:
		return

	var total_len := c.get_baked_length()
	progress = clampf(target_ratio * total_len, 0.0, total_len)
	_forward_initialized = false
	_align_to_path(0.016)