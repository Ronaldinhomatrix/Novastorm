class_name CinematicLevelEnd
extends Node

## Cutscene cinematográfica de transição entre o fim do Level 1 e o Level 1 Boss.
##
## Efeitos Inclusos:
##   1. Som "maneuver1" posicional em 3D emitido da nave Player no início da cena.
##   2. Nave Player leva 3.0s para passar ao lado da câmera a velocidade constante (260 u/s).
##   3. A cena permanece viva por mais 2.0s após a nave cruzar a câmera antes do fade-out.
##   4. Efeito contínuo de Zoom Cinematográfico (FOV fechando suavemente).
##   5. Letterbox Widescreen (Barras pretas 2.39:1 estilo cinema).
##   6. Tremor de Câmera (Sonic Boom / Screen Shake no voo rasante).

signal cutscene_completed

# Sons da cutscene
const ManeuverSound := preload("res://assets/audio/maneuver1.ogg")
const FlybySound := preload("res://assets/audio/maneuver2.ogg")

# ---------------------------------------------------------------------------
# Exportações — Câmera Externa
# ---------------------------------------------------------------------------

@export_category("Câmera Externa (Posição Editável)")
## Posição GLOBAL da câmera externa (calculada para 780m de percurso a 260 u/s em 3.0s).
@export var cutscene_camera_position := Vector3(10143.0, 1242.0, -546.0)
## Rotação inicial em graus da câmera (pitch, yaw, roll).
@export var cutscene_camera_rotation_deg := Vector3(-58.8, 79.9, 0.0)
## Se true, a câmera acompanha a nave suavemente durante toda a trajetória.
@export var camera_tracks_ship: bool = true
## Suavização do tracking da câmera (valores maiores = tracking mais rápido).
@export var camera_tracking_smoothing: float = 6.0

# ---------------------------------------------------------------------------
# Exportações — Velocidade Constante e Timing Preciso
# ---------------------------------------------------------------------------

@export_category("Velocidade e Voo Rasante")
## Velocidade CONSTANTE de subida da nave durante toda a cutscene (unidades/segundo).
@export var climb_speed: float = 260.0
## Tempo em segundos para a nave alcançar e passar ao lado da câmera.
@export var flyby_target_time: float = 3.0
## Deslocamento seguro em relação à câmera no ponto de maior aproximação (~52m).
@export var flyby_offset := Vector3(-20.0, -45.0, 18.0)
## Velocidade de alinhamento da rotação da nave com a direção de subida.
@export var rotation_smoothing: float = 4.0

# ---------------------------------------------------------------------------
# Exportações — Efeitos Cinematográficos e Zoom
# ---------------------------------------------------------------------------

@export_category("Efeitos Cinematográficos e Zoom")
## Ativa o efeito de Zoom contínuo durante toda a cutscene.
@export var enable_cinematic_zoom: bool = true
## FOV inicial no início da cutscene (graus).
@export_range(30.0, 90.0, 0.5) var initial_fov: float = 56.25
## FOV final no ápice do zoom (graus mais fechados = mais zoom).
@export_range(20.0, 80.0, 0.5) var target_zoom_fov: float = 36.0

## Ativa as barras pretas de cinema (Letterbox 2.39:1).
@export var enable_letterbox: bool = true
## Altura relativa das barras pretas (0.09 = 9% da tela em cima e embaixo).
@export_range(0.04, 0.2, 0.01) var letterbox_fraction: float = 0.09
## Ativa o tremor de tela na passagem rasante supersônica.
@export var enable_screen_shake: bool = true
## Intensidade do tremor da câmera ao passar rasante.
@export var shake_intensity: float = 1.2
## Duração do tremor em segundos.
@export var shake_duration: float = 0.5

# ---------------------------------------------------------------------------
# Exportações — Timing e Transição (6.2s total: 3s até câmera + 2s vivo + 1.2s fade)
# ---------------------------------------------------------------------------

@export_category("Timing e Transição")
## Duração total da cutscene em segundos.
@export var duration: float = 6.2
## Fração da duração em que o fade-out para preto se inicia (aos ~5.0s, permitindo 2s vivos após o flyby).
@export_range(0.3, 0.95, 0.05) var fade_start_ratio: float = 0.8
## Caminho da cena de destino (level1_boss).
@export var next_scene_path: String = "res://scenes/stages/level_1_boss.tscn"

# ---------------------------------------------------------------------------
# Referências (atribuídas pelo GameController)
# ---------------------------------------------------------------------------

var path_follower: PathFollower = null
var player: Node3D = null
var camera: Camera3D = null
var hud: CombatHUD = null

# ---------------------------------------------------------------------------
# Estado Interno
# ---------------------------------------------------------------------------

var _active: bool = false
var _timer: float = 0.0
var _cutscene_cam: Camera3D = null
var _ship_start_pos := Vector3.ZERO
var _climb_direction := Vector3.UP

var _canvas_layer: CanvasLayer = null
var _curtain: ColorRect = null
var _bar_top: ColorRect = null
var _bar_bottom: ColorRect = null
var _ship_basis: Basis = Basis.IDENTITY

# Controle de áudio 3D
var _maneuver_player: AudioStreamPlayer3D = null
var _flyby_sound_played: bool = false
var _flyby_player: AudioStreamPlayer = null

# Screen Shake
var _shake_time: float = 0.0
var _shake_power: float = 0.0


# ---------------------------------------------------------------------------
# Inicialização e Início da Cutscene
# ---------------------------------------------------------------------------

func start() -> void:
	if _active:
		return
	_active = true
	_timer = 0.0
	_flyby_sound_played = false

	# 1. Som 3D "maneuver1" emitido diretamente da nave Player
	_maneuver_player = AudioStreamPlayer3D.new()
	_maneuver_player.stream = ManeuverSound
	_maneuver_player.bus = "Master"
	_maneuver_player.volume_db = 6.0
	_maneuver_player.unit_size = 40.0
	_maneuver_player.max_distance = 4000.0
	_maneuver_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	if player:
		player.add_child(_maneuver_player)
	else:
		add_child(_maneuver_player)
	_maneuver_player.play()

	# Áudio secundário do voo rasante (sonic boom na passagem dos 3s)
	_flyby_player = AudioStreamPlayer.new()
	_flyby_player.stream = FlybySound
	_flyby_player.bus = "Master"
	_flyby_player.volume_db = 3.0
	add_child(_flyby_player)

	# 2. Desativa controles do jogador e recentraliza a nave no trilho
	if player:
		if player.has_method("set_controls_enabled"):
			player.set_controls_enabled(false)
		player.position = Vector3(0.0, 0.0, -40.0)
		player.rotation = Vector3.ZERO
		player.set_physics_process(false)
		player.set_process(false)

	# 3. Congela o PathFollower no ponto final para assumirmos o controle 3D direto
	if path_follower:
		path_follower.set_paused(true)
		path_follower.set_physics_process(false)
		path_follower.set_process(false)
		_ship_start_pos = path_follower.global_position
		_ship_basis = path_follower.global_transform.basis
	elif player:
		_ship_start_pos = player.global_position
		_ship_basis = player.global_transform.basis

	# 4. Esconde o HUD de combate
	if hud:
		hud.visible = false

	# 5. Cálculo geométrico do voo rasante
	var target_flyby_point := cutscene_camera_position + flyby_offset
	var to_cam := target_flyby_point - _ship_start_pos
	if to_cam.length_squared() > 1.0:
		_climb_direction = to_cam.normalized()
	else:
		_climb_direction = Vector3.UP

	# 6. Instancia a câmera externa cinematográfica na posição configurada
	_cutscene_cam = Camera3D.new()
	_cutscene_cam.name = "CutsceneLevelEndCam"
	_cutscene_cam.fov = initial_fov
	_cutscene_cam.far = 14000.0
	get_parent().add_child(_cutscene_cam)
	_cutscene_cam.global_position = cutscene_camera_position

	# Orientação inicial da câmera
	if camera_tracks_ship:
		var initial_target := player.global_position if player else _ship_start_pos
		_cutscene_cam.look_at(initial_target, Vector3.UP)
	else:
		_cutscene_cam.rotation_degrees = cutscene_camera_rotation_deg

	_cutscene_cam.make_current()

	# 7. UI Cinematográfica: CanvasLayer com Barras Pretas e Cortina de Fade
	_setup_cinematic_ui()


# ---------------------------------------------------------------------------
# Configuração da UI Cinematográfica (Letterbox + Fade)
# ---------------------------------------------------------------------------

func _setup_cinematic_ui() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100
	get_parent().add_child(_canvas_layer)

	# Cortina de fade para preto (inicia transparente)
	_curtain = ColorRect.new()
	_curtain.color = Color(0.0, 0.0, 0.0, 0.0)
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(_curtain)

	# Barras pretas de cinema (Letterbox 2.39:1)
	if enable_letterbox:
		var vp_height := get_viewport().get_visible_rect().size.y
		var bar_h := vp_height * letterbox_fraction

		_bar_top = ColorRect.new()
		_bar_top.color = Color.BLACK
		_bar_top.anchor_left = 0.0
		_bar_top.anchor_right = 1.0
		_bar_top.anchor_top = 0.0
		_bar_top.anchor_bottom = 0.0
		_bar_top.offset_left = 0.0
		_bar_top.offset_right = 0.0
		_bar_top.offset_top = 0.0
		_bar_top.offset_bottom = 0.0
		_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas_layer.add_child(_bar_top)

		_bar_bottom = ColorRect.new()
		_bar_bottom.color = Color.BLACK
		_bar_bottom.anchor_left = 0.0
		_bar_bottom.anchor_right = 1.0
		_bar_bottom.anchor_top = 1.0
		_bar_bottom.anchor_bottom = 1.0
		_bar_bottom.offset_left = 0.0
		_bar_bottom.offset_right = 0.0
		_bar_bottom.offset_top = 0.0
		_bar_bottom.offset_bottom = 0.0
		_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas_layer.add_child(_bar_bottom)

		# Animação suave de entrada das barras cinematográficas (0.45s)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_bar_top, "offset_bottom", bar_h, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(_bar_bottom, "offset_top", -bar_h, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# Processamento por Frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _active:
		return

	var dt := minf(delta, 0.05)
	_timer += dt
	var progress_ratio := clampf(_timer / maxf(duration, 0.001), 0.0, 1.0)

	# --- 1. Movimentação a Velocidade Constante (260 u/s) ---
	var cur_ship_pos := _ship_start_pos + _climb_direction * (climb_speed * _timer)

	# Alinhamento suave da rotação da nave com a direção de subida
	var current_forward := -_ship_basis.z.normalized()
	var rot_t := 1.0 - exp(-rotation_smoothing * dt)
	var new_forward := current_forward.slerp(_climb_direction, rot_t).normalized()

	var up := Vector3.UP
	var right := new_forward.cross(up).normalized()
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	var corrected_up := right.cross(new_forward).normalized()
	_ship_basis = Basis(right, corrected_up, -new_forward).orthonormalized()

	# Atualiza a posição e orientação no PathFollower
	if path_follower:
		var xform := path_follower.global_transform
		xform.origin = cur_ship_pos
		xform.basis = _ship_basis
		path_follower.global_transform = xform

	# --- 2. Voo Rasante aos 3 Segundos: Sonic Boom & Tremor ---
	var target_pos := player.global_position if player else cur_ship_pos

	if not _flyby_sound_played and _timer >= (flyby_target_time - 0.1):
		_flyby_sound_played = true
		if _flyby_player:
			_flyby_player.play()
		if enable_screen_shake:
			_shake_time = shake_duration
			_shake_power = shake_intensity

	# --- 3. Efeito de Zoom Contínuo Durante Toda a Cutscene ---
	if enable_cinematic_zoom and _cutscene_cam:
		var zoom_t := clampf(_timer / maxf(duration, 0.001), 0.0, 1.0)
		var smooth_zoom := zoom_t * zoom_t * (3.0 - 2.0 * zoom_t)
		_cutscene_cam.fov = lerpf(initial_fov, target_zoom_fov, smooth_zoom)

	# --- 4. Câmera Externa: Tracking Suave + Screen Shake ---
	if _cutscene_cam:
		if camera_tracks_ship:
			var cam_pos := _cutscene_cam.global_position
			var look_dir := (target_pos - cam_pos).normalized()
			if look_dir.length_squared() > 0.001:
				var cam_target_basis := Basis.looking_at(look_dir, Vector3.UP)
				var cam_t := 1.0 - exp(-camera_tracking_smoothing * dt)
				_cutscene_cam.global_transform.basis = _cutscene_cam.global_transform.basis.slerp(cam_target_basis, cam_t).orthonormalized()

		# Aplicação do Tremor de Câmera (Screen Shake)
		if _shake_time > 0.0:
			_shake_time -= dt
			var shake_norm := clampf(_shake_time / maxf(shake_duration, 0.001), 0.0, 1.0)
			var cur_shake := _shake_power * shake_norm * shake_norm
			_cutscene_cam.h_offset = randf_range(-1.0, 1.0) * cur_shake * 0.9
			_cutscene_cam.v_offset = randf_range(-1.0, 1.0) * cur_shake * 0.7
			_cutscene_cam.rotation.z = deg_to_rad(randf_range(-1.0, 1.0) * cur_shake * 1.6)
		else:
			_cutscene_cam.h_offset = 0.0
			_cutscene_cam.v_offset = 0.0
			_cutscene_cam.rotation.z = 0.0

	# --- 5. Fade-Out para Preto (Inicia aos ~5.0s, deixando 2s vivos pós-rasante) ---
	if progress_ratio >= fade_start_ratio and _curtain:
		var fade_t := clampf((progress_ratio - fade_start_ratio) / (1.0 - fade_start_ratio), 0.0, 1.0)
		var smooth_fade := fade_t * fade_t  # Curva quadrática suave
		_curtain.color = Color(0.0, 0.0, 0.0, smooth_fade)

	# --- 6. Término e Transição de Cena ---
	if progress_ratio >= 1.0:
		_end()


# ---------------------------------------------------------------------------
# Finalização
# ---------------------------------------------------------------------------

func _end() -> void:
	_active = false
	cutscene_completed.emit()

	# Transição para a cena do boss
	if next_scene_path != "":
		if ResourceLoader.exists(next_scene_path):
			get_tree().change_scene_to_file(next_scene_path)
		else:
			push_warning("CinematicLevelEnd: cena '%s' não encontrada. Crie-a para completar a transição." % next_scene_path)
