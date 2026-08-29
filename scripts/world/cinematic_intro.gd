class_name CinematicIntro
extends Node

## Componente modular reutilizável para efeito cinematográfico de abertura de nível.
## Realiza o giro orbital da câmera, aproximação (zoom-out) e aceleração gradual da nave.

signal intro_completed

## Som de manobra tocado quando a câmera inicia o giro orbital (parafuso).
const ManeuverSound := preload("res://assets/audio/maneuver1.ogg")

@export_category("Componentes")
@export var path_follower: PathFollower = null
@export var player: Node3D = null
@export var camera: Camera3D = null

@export_category("Configurações da Animação")
@export var enabled: bool = true
@export var duration: float = 5.0  ## Duração total do efeito em segundos
@export var start_azimuth_deg: float = 135.0  ## Ângulo horizontal inicial (graus)
@export var start_elevation_deg: float = -20.0  ## Ângulo vertical inicial (graus)
@export_range(0.05, 1.0) var start_distance_fraction: float = 0.25  ## Distância inicial em relação à padrão (0.25 = 25%)

var _active: bool = false
var _timer: float = 0.0
var _default_camera_pos: Vector3 = Vector3(-0.0112, 0.0, 18.0)
var _default_camera_rot: Vector3 = Vector3.ZERO

# Player de áudio da manobra (não posicional, pois a câmera gira pela cena).
var _maneuver_player: AudioStreamPlayer = null


func _ready() -> void:
	# Busca automática de referências caso não estejam explicitamente atribuídas no Inspector
	var parent := get_parent()
	if not path_follower and parent:
		path_follower = parent.get_node_or_null("FlightPath/PathFollower") as PathFollower
	if not player and path_follower:
		player = path_follower.get_node_or_null("Player") as Node3D
	if not camera and path_follower:
		camera = path_follower.get_node_or_null("Camera3D") as Camera3D

	# Prepara o player de áudio da manobra (giro orbital da câmera).
	_maneuver_player = AudioStreamPlayer.new()
	_maneuver_player.stream = ManeuverSound
	_maneuver_player.bus = "Master"
	_maneuver_player.volume_db = 0.0
	add_child(_maneuver_player)

	if enabled and camera and player and path_follower:
		start()


func _process(delta: float) -> void:
	if not _active:
		return

	var dt := minf(delta, 0.05)
	_timer += dt
	var progress_ratio: float = clampf(_timer / maxf(duration, 0.001), 0.0, 1.0)
	_update_camera_and_speed(progress_ratio)

	if progress_ratio >= 1.0:
		_end()


func start() -> void:
	_active = true
	_timer = 0.0

	# Esconde o cursor do mouse durante a cinemática.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	# Toca a manobra assim que a câmera começa o giro orbital (parafuso).
	if _maneuver_player:
		_maneuver_player.pitch_scale = randf_range(0.97, 1.03)
		_maneuver_player.play()

	if path_follower:
		path_follower.set_paused(false)
		path_follower.set_speed_multiplier(0.5)

	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(false)

	if camera:
		_default_camera_pos = camera.position
		_default_camera_rot = camera.rotation
		_update_camera_and_speed(0.0)


func _update_camera_and_speed(raw_progress: float) -> void:
	if not camera or not player:
		return

	var s := _ease_in_out_cubic(raw_progress)

	if path_follower:
		path_follower.set_speed_multiplier(lerpf(0.5, 1.0, s))

	var ship_pos := player.position
	var final_offset := _default_camera_pos - ship_pos
	var final_dist := final_offset.length()
	if final_dist < 0.001:
		final_dist = 73.85669

	var initial_dist := final_dist * start_distance_fraction
	var start_azimuth := deg_to_rad(start_azimuth_deg)
	var start_elev := deg_to_rad(start_elevation_deg)

	var cur_azimuth := lerpf(start_azimuth, 0.0, s)
	var cur_elev := lerpf(start_elev, 0.0, s)
	var cur_dist := lerpf(initial_dist, final_dist, s)

	var cos_elev := cos(cur_elev)
	var sin_elev := sin(cur_elev)
	var offset := Vector3(
		cur_dist * cos_elev * sin(cur_azimuth),
		cur_dist * sin_elev,
		cur_dist * cos_elev * cos(cur_azimuth)
	)

	var cam_pos := ship_pos + offset
	camera.position = cam_pos

	var target_basis := Basis.from_euler(_default_camera_rot)
	var look_target := ship_pos
	var forward := (look_target - cam_pos).normalized()
	var up := Vector3.UP
	var right := forward.cross(up).normalized()
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	var true_up := right.cross(forward).normalized()
	var look_basis := Basis(right, true_up, -forward).orthonormalized()

	# Transição perfeitamente contínua e sem degrau para a orientação padrão
	camera.transform.basis = look_basis.slerp(target_basis, s * s).orthonormalized()

	if s >= 0.999:
		camera.position = _default_camera_pos
		camera.transform.basis = target_basis


func _end() -> void:
	_active = false

	if camera:
		camera.position = _default_camera_pos
		camera.rotation = _default_camera_rot

	if path_follower:
		path_follower.set_paused(false)
		path_follower.set_speed_multiplier(1.0)

	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(true)

	# Revela o cursor do mouse somente ao fim da introdução cinemática.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	intro_completed.emit()


func _ease_in_out_cubic(t: float) -> float:
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0
