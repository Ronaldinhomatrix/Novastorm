class_name Player
extends CharacterBody3D

## Nave do jogador — estilo Novastorm (1994).
## A nave é FILHA do PathFollower (que percorre o Path3D), então herda
## automaticamente o movimento e a rotação do caminho.
##
## Controle:
##   - PC (Mouse): a nave segue a posição do ponteiro na tela.
##   - Mobile (Android/iOS): arrasto relativo — a nave se move conforme o
##     deslocamento do dedo, sem saltar para a posição tocada.
##   - Teclado (WASD / Setas): alternativa para movimentação lateral/vertical.
##
## Os limites de movimento são calculados DINAMICAMENTE a partir do frustum
## da câmera, para que a nave percorra quase toda a área visível da tela.

# ---------------------------------------------------------------------------
# Exportações e Configurações
# ---------------------------------------------------------------------------

@export_category("Movimento")
@export var speed: float = 40.0
@export var forward_offset: float = -40.0  # Distância à frente da câmera (Z local)

@export_category("Area de Movimento (fração da tela)")
@export_range(0.0, 1.0) var screen_margin: float = 0.88  # 0.88 = nave percorre 88% da área visível
@export_range(0.0, 1.0) var up_screen_fraction: float = 0.85  # Limite superior: nave sobe até 85% da área superior

@export_category("Mouse / Toque")
@export var pointer_follow_speed: float = 12.0  # Suavidade de seguir o ponteiro
@export var drag_sensitivity: float = 1.0  # Sensibilidade do arrasto relativo (mobile)

@export_category("Inclinacao (Juice)")
@export var roll_amount: float = 0.6
@export var pitch_amount: float = 0.3
@export var rotation_speed: float = 8.0
## Multiplicador do tilt da nave acompanhando a inclinação de curva da câmera
@export var path_tilt_amount: float = 1.4

@export_category("Combate")
@export var fire_rate: float = 0.25
@export var bullet_scene: PackedScene = null

@export_category("Mísseis e Lock-on (Secundário)")
@export var missile_scene: PackedScene = preload("res://scenes/projectiles/player_missile.tscn")
@export var max_missiles: int = 3
@export var missile_reload_time: float = 5.0
@export var lock_on_max_targets: int = 3
@export var lock_on_range: float = 650.0
## Raio do cone de mira em pixels na tela (área central onde o jogador precisa apontar).
@export var lock_on_radius: float = 260.0
## Tempo de processamento/trava após marcar o alvo com a mira (em segundos).
@export var lock_on_confirm_time: float = 1.0
## Som de bip ao travar alvo (lock-on).
@export var lock_on_sound: AudioStream = preload("res://assets/audio/lock_on.wav")
## Som de lançamento do míssil.
@export var missile_fire_sound: AudioStream = preload("res://assets/audio/missile.ogg")
@export var lock_on_volume_db: float = 0.5
@export var missile_volume_db: float = -2.0

@export_category("Áudio")
## Volume do tiro laser em dB. 0 = 100% (padrão Godot), -6 ≈ 50%, -12 ≈ 25%.
@export var laser_volume_db: float = -6.0

@export_category("Colisao")
## Velocidade inicial do "pulo" ao ricochetear (local, unidades/segundo).
@export var bounce_strength: float = 320.0
## Rapidez com que o ricochete decai (maior = some mais rápido).
@export var bounce_damping: float = 15.0

@export_category("Vida e Escudo")
@export var max_shield: int = 3
@export var max_hull: int = 3
@export var invulnerability_duration: float = 1.0

# Sinais para interface e lógica de combate
signal shield_changed(current: int, max_val: int)
signal hull_changed(current: int, max_val: int)
signal health_changed(current: int, max_val: int)
signal damage_taken(amount: int)
signal primary_fire_started
signal missile_fired(remaining: int, max_val: int)
signal missile_reloaded(current: int, max_val: int)
signal missile_reload_progress(progress: float)
signal missile_targets_changed(targets: Array[Node3D])
signal missile_targeting_updated(locked_targets: Array[Node3D], acquiring_targets: Dictionary)

# Scripts procedurais
const SparkScript := preload("res://scripts/effects/spark.gd")
const ExplosionScript := preload("res://scripts/effects/explosion.gd")
const ShieldBubbleScene := preload("res://scenes/effects/shield_bubble.tscn")
const DamageSmokeScript := preload("res://scripts/effects/damage_smoke.gd")
const EnemyWreckageScript := preload("res://scripts/effects/enemy_wreckage.gd")
const MuzzleFlashScript := preload("res://scripts/effects/muzzle_flash.gd")

# Som de disparo do laser, explosão e alerta de escudo.
const LaserSound := preload("res://assets/audio/laser0.wav")
const ShieldOfflineSound := preload("res://assets/audio/shield_offline.ogg")
const ExplosionSound := preload("res://assets/audio/explosion1.ogg")

# ---------------------------------------------------------------------------
# Estado Interno
# ---------------------------------------------------------------------------

var current_shield: int = 3
var current_hull: int = 3

# Mísseis e Lock-on
var current_missiles: int = 3
var _locked_targets: Array[Node3D] = []
var _targeting_progress: Dictionary = {}  ## Node3D -> float (tempo sustentado na mira)
var _missile_reload_timer: float = 0.0
var _is_reloading_missiles: bool = false
var _lock_scan_timer: float = 0.0
var _missile_wing_side: int = 0
var _lock_audio_player: AudioStreamPlayer = null
var _missile_audio_player: AudioStreamPlayer = null

var current_health: int:
	get:
		return current_hull
	set(val):
		current_hull = val

var max_health: int:
	get:
		return max_hull
	set(val):
		max_hull = val

var _is_invulnerable: bool = false
var _invulnerability_timer: float = 0.0
var _is_dying: bool = false
var _damage_smoke: DamageSmokeEffect = null

var _is_firing: bool = false
var _fire_timer: float = 0.0

var _pointer_active: bool = false
var _pointer_pos: Vector2 = Vector2.ZERO

# Controle relativo (mobile)
var _drag_active: bool = false
var _touch_index: int = 0
var _drag_delta_acc: Vector2 = Vector2.ZERO

# Extensões visíveis (half width, half height) no plano da nave
var _half_w: float = 30.0
var _half_h: float = 30.0
var _max_up: float = 30.0  # Limite vertical superior (para cima)
var _recent_move_local: Vector3 = Vector3.ZERO
var _target_local_pos: Vector3 = Vector3.ZERO
var _bounce_vel: Vector3 = Vector3.ZERO  # Velocidade de ricochete (espaço local)
var _controls_enabled: bool = true

# Player de áudio do disparo. A nave fica fixa na câmera (rail-shooter),
# logo a nave e o ouvinte estão sempre co-localizados: cálculos 3D de
# atenuação/panning por distância são dispensáveis e só gastam CPU.
var _laser_player: AudioStreamPlayer = null

# Estado Dev / Look Back (Olhar para trás)
var _is_looking_back: bool = false
var _shield_bubble: ShieldBubble = null
var _muzzle_flash: Node3D = null

@onready var ship_model: Node3D = $ShipModel

# ---------------------------------------------------------------------------
# Ciclo de Vida
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("player")
	current_health = max_health

	# Mobile: usa a variante leve do projétil (sem OmniLight por tiro,
	# flares menores e menos partículas) para economizar fill-rate/shading.
	# Carregada sob demanda (load) para não ocupar memória no PC.
	if GameConfig.is_mobile:
		bullet_scene = load("res://scenes/bullet_mobile.tscn") as PackedScene

	# Áudio de disparo: som 2D com volume fixo padrão (nave sempre na câmera).
	_laser_player = AudioStreamPlayer.new()
	_laser_player.stream = LaserSound
	_laser_player.bus = "Master"
	_laser_player.volume_db = laser_volume_db  # ajustável via export "Laser Volume Db" (-6 dB = 50%)
	add_child(_laser_player)

	# Instancia o campo de força 3D (escudo holográfico)
	if not _shield_bubble:
		_shield_bubble = get_node_or_null("ShieldBubble") as ShieldBubble
		if not _shield_bubble and ship_model:
			_shield_bubble = ship_model.get_node_or_null("ShieldBubble") as ShieldBubble
		if not _shield_bubble and ShieldBubbleScene:
			_shield_bubble = ShieldBubbleScene.instantiate() as ShieldBubble
			_shield_bubble.name = "ShieldBubble"
			if ship_model:
				ship_model.add_child(_shield_bubble)
			else:
				add_child(_shield_bubble)

	# Instancia o efeito procedural de fumaça e fogo de dano
	if not _damage_smoke and DamageSmokeScript:
		_damage_smoke = DamageSmokeScript.new()
		_damage_smoke.name = "DamageSmokeEffect"
		if ship_model:
			ship_model.add_child(_damage_smoke)
		else:
			add_child(_damage_smoke)

	# Instancia o efeito de brilho e flash no disparo da nave
	if not _muzzle_flash and MuzzleFlashScript:
		_muzzle_flash = MuzzleFlashScript.new()
		_muzzle_flash.name = "MuzzleFlashEffect"
		if ship_model:
			ship_model.add_child(_muzzle_flash)
		else:
			add_child(_muzzle_flash)

	var col_shape := $CollisionShape3D as CollisionShape3D
	if col_shape and col_shape.shape is BoxShape3D:
		col_shape.shape.size = Vector3(5, 2.5, 9)

	current_shield = max_shield
	current_hull = max_hull
	shield_changed.emit(current_shield, max_shield)
	hull_changed.emit(current_hull, max_hull)
	health_changed.emit(current_hull, max_hull)

	# Inicializa mísseis secundários
	current_missiles = max_missiles
	_setup_missile_audio()
	missile_fired.emit(current_missiles, max_missiles)

	# Só reposiciona a nave quando ela é filha de um PathFollow3D (modo rail
	# shooter), onde a posição local deve ficar fixa à frente da câmera.
	# Quando a nave é filha direta do nível/Level (ex.: nível em edição, sem
	# trajetória), ela deve respeitar a posição definida no editor.
	if get_parent() is PathFollow3D:
		position = Vector3(0.0, 0.0, forward_offset)
	_target_local_pos = position


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	if not enabled:
		_is_firing = false
		_pointer_active = false
		_drag_active = false
		_drag_delta_acc = Vector2.ZERO
		_target_local_pos = Vector3(0.0, 0.0, forward_offset)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _controls_enabled:
		return
	if GameConfig.is_mobile:
		_handle_mobile_input(event)
	else:
		_handle_desktop_input(event)


# ---------------------------------------------------------------------------
# Input (Desktop / Mobile)
# ---------------------------------------------------------------------------

func _handle_desktop_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_F or event.keycode == KEY_B:
			toggle_look_back()

	if event is InputEventMouseMotion:
		_pointer_pos = event.position
		_pointer_active = true

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not _is_firing:
				primary_fire_started.emit()
			_is_firing = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			fire_missiles()


func _handle_mobile_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if not _drag_active:
				_touch_index = event.index
				_drag_active = true
				_pointer_active = false
				if not _is_firing:
					primary_fire_started.emit()
				_is_firing = true
		elif event.index == _touch_index:
			_drag_active = false
			_is_firing = false

	elif event is InputEventScreenDrag:
		if event.index == _touch_index and _drag_active:
			_drag_delta_acc += event.relative


# ---------------------------------------------------------------------------
# Processamento por Frame
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Modo "estático" (nível em edição, nave fora de um PathFollow3D):
	# não processa movimento/combate — mantém a nave exatamente onde foi
	# posicionada no editor. O movimento só ocorre no modo rail shooter
	# (nave filha de um PathFollow3D).
	if not (get_parent() is PathFollow3D):
		return

	# Atualiza o temporizador de invulnerabilidade
	if _is_invulnerable:
		_invulnerability_timer -= delta
		if _invulnerability_timer <= 0.0:
			_is_invulnerable = false
		if ship_model and not ship_model.visible:
			ship_model.visible = true

	if not _controls_enabled:
		_is_firing = false
		position = position.lerp(Vector3(0.0, 0.0, forward_offset), 8.0 * delta)
		if ship_model:
			ship_model.rotation = ship_model.rotation.lerp(Vector3.ZERO, 8.0 * delta)
		return

	_update_screen_extents()

	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length_squared() > 0.001:
		_pointer_active = false
		_drag_active = false
		_drag_delta_acc = Vector2.ZERO

	if _drag_active:
		_apply_drag_delta(_drag_delta_acc)
		_drag_delta_acc = Vector2.ZERO
	elif _pointer_active:
		_update_pointer_target()
	else:
		_update_keyboard_target(input_dir, delta)

	# Limita o alvo para os limites da tela
	_target_local_pos.x = clampf(_target_local_pos.x, -_half_w, _half_w)
	_target_local_pos.y = clampf(_target_local_pos.y, -_half_h, _max_up)
	_target_local_pos.z = forward_offset

	# Aplica o "pulo" de ricochete e o decai ao longo do tempo.
	_target_local_pos += _bounce_vel * delta
	_bounce_vel = _bounce_vel.move_toward(Vector3.ZERO, bounce_damping * delta)

	# Re-limita após o bounce (só X/Y; Z permanece fixo na frente da câmera).
	_target_local_pos.x = clampf(_target_local_pos.x, -_half_w, _half_w)
	_target_local_pos.y = clampf(_target_local_pos.y, -_half_h, _max_up)
	_target_local_pos.z = forward_offset

	# Interpolação suave para a posição atual (suaviza teclado e ponteiro),
	# detectando colisão com o cenário para ricochetear.
	# Em câmera lenta (slow motion), compensa a escala de tempo para a mira permanecer ágil
	var effective_follow_delta: float = (delta / maxf(Engine.time_scale, 0.05)) if Engine.time_scale < 0.9 else delta
	var follow := clampf(pointer_follow_speed * effective_follow_delta, 0.0, 1.0)
	_apply_movement(follow)

	_handle_ship_rotation(delta)
	_update_camera_look_back(delta)

	if _is_firing or Input.is_action_pressed("ui_select"):
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer = fire_rate
			_spawn_bullet()
	else:
		_fire_timer = maxf(0.0, _fire_timer - delta)

	_process_missiles_and_lock_on(delta)


# ---------------------------------------------------------------------------
# Calcula a área visível no plano da nave a partir do frustum da câmera
# ---------------------------------------------------------------------------

func _update_screen_extents() -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return

	# A câmera e a nave são ambas filhas do PathFollower; a distância ao longo
	# do eixo Z local entre elas define a profundidade do plano da nave.
	var cam_z: float = cam.position.z
	var distance := absf(cam_z - forward_offset)
	if distance < 0.001:
		return

	var half_height := tan(deg_to_rad(cam.fov) * 0.5) * distance
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 0.001)
	var half_width := half_height * aspect

	# Aplica a margem (fração da área visível)
	_half_w = half_width * screen_margin
	_half_h = half_height * screen_margin

	# Limite superior: a nave sobe até uma fração da metade superior
	_max_up = _half_h * up_screen_fraction


# ---------------------------------------------------------------------------
# Atualização da posição alvo pelo ponteiro (mouse/toque)
# ---------------------------------------------------------------------------

func _update_pointer_target() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x < 0.001 or vp_size.y < 0.001:
		return

	var normalized := Vector2(
		(_pointer_pos.x / vp_size.x) * 2.0 - 1.0,
		(_pointer_pos.y / vp_size.y) * 2.0 - 1.0
	)

	# Mapeia o ponteiro normalizado para os limites visíveis.
	# Lateral: simétrico (-_half_w .. +_half_w).
	# Vertical: base (pointer.y=+1) desce até -_half_h;
	#           topo (pointer.y=-1) sobe até +_max_up (85% da área superior).
	var up_limit := _max_up
	var down_limit := -_half_h
	var y_range := (up_limit - down_limit) * 0.5
	var y_center := (up_limit + down_limit) * 0.5
	
	_target_local_pos = Vector3(
		normalized.x * _half_w,
		-normalized.y * y_range + y_center,
		forward_offset
	)


# ---------------------------------------------------------------------------
# Atualização da posição alvo pelo arrasto relativo (mobile)
# ---------------------------------------------------------------------------

func _apply_drag_delta(screen_delta: Vector2) -> void:
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x < 0.001 or vp_size.y < 0.001:
		return

	# Converte pixels da tela para unidades do mundo no plano da nave,
	# mantendo a mesma escala usada no controle absoluto do mouse.
	var scale_x := (2.0 * _half_w) / vp_size.x
	var scale_y := (_half_h * (1.0 + up_screen_fraction)) / vp_size.y

	_target_local_pos.x += screen_delta.x * scale_x * drag_sensitivity
	_target_local_pos.y -= screen_delta.y * scale_y * drag_sensitivity


# ---------------------------------------------------------------------------
# Atualização da posição alvo pelo teclado (WASD / Setas)
# ---------------------------------------------------------------------------

func _update_keyboard_target(input_dir: Vector2, delta: float) -> void:
	# O teclado move a posição alvo local diretamente de forma contínua
	var effective_delta: float = (delta / maxf(Engine.time_scale, 0.05)) if Engine.time_scale < 0.9 else delta
	_target_local_pos.x += input_dir.x * speed * effective_delta
	_target_local_pos.y -= input_dir.y * speed * effective_delta
	_target_local_pos.z = forward_offset


# ---------------------------------------------------------------------------
# Rotação Estética (Juice)
# ---------------------------------------------------------------------------

func _handle_ship_rotation(delta: float) -> void:
	if not ship_model:
		return

	var dir_x := clampf(_recent_move_local.x / maxf(1.0, speed * delta), -1.0, 1.0)
	var dir_y := clampf(_recent_move_local.y / maxf(1.0, speed * delta), -1.0, 1.0)

	# 1. Obtém o tilt/bank da curva sincronizado com o PathFollower
	var curve_tilt := 0.0
	var is_barrel_rolling := false

	var parent_node := get_parent()
	if parent_node:
		# Exceção: durante o Barrel Roll (giro em parafuso da câmera), o tilt de curva é desativado na nave
		if parent_node.has_method("is_in_barrel_roll") and parent_node.call("is_in_barrel_roll"):
			is_barrel_rolling = true
		elif parent_node.has_method("get_barrel_roll_angle") and absf(float(parent_node.call("get_barrel_roll_angle"))) > 0.001:
			is_barrel_rolling = true

		if not is_barrel_rolling:
			if parent_node.has_method("get_curve_tilt"):
				curve_tilt = float(parent_node.call("get_curve_tilt"))
			elif parent_node.has_method("get_smoothed_tilt"):
				curve_tilt = float(parent_node.call("get_smoothed_tilt"))

	# A nave inclina acompanhando a curvatura do trilho com limite máximo de 30 graus
	# curve_tilt < 0 é curva para a esquerda -> -curve_tilt gera roll positivo (asa esquerda baixa)
	var max_curve_tilt_rad := deg_to_rad(30.0)
	var curve_roll := clampf(-curve_tilt * 1.2 * path_tilt_amount, -max_curve_tilt_rad, max_curve_tilt_rad)
	var curve_yaw := clampf(-curve_tilt * 0.3 * path_tilt_amount, -deg_to_rad(18.0), deg_to_rad(18.0))
	var target_roll := clampf((-dir_x * roll_amount) + curve_roll, -deg_to_rad(35.0), deg_to_rad(35.0))
	var target_pitch := dir_y * pitch_amount
	var target_yaw := clampf((-dir_x * 0.25) + curve_yaw, -deg_to_rad(20.0), deg_to_rad(20.0))

	ship_model.rotation.z = lerpf(ship_model.rotation.z, target_roll, rotation_speed * delta)
	ship_model.rotation.x = lerpf(ship_model.rotation.x, target_pitch, rotation_speed * delta)
	ship_model.rotation.y = lerpf(ship_model.rotation.y, target_yaw, rotation_speed * delta)


# ---------------------------------------------------------------------------
# Modo Dev - Olhar para Trás (Camera 180 Flip)
# ---------------------------------------------------------------------------

func toggle_look_back() -> void:
	_is_looking_back = not _is_looking_back


func _update_camera_look_back(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var target_rot_y := PI if _is_looking_back else 0.0
	cam.rotation.y = lerp_angle(cam.rotation.y, target_rot_y, 10.0 * delta)



# ---------------------------------------------------------------------------
# Sistema de Armas
# ---------------------------------------------------------------------------
# NOTA CRÍTICA: A mecânica dos tiros NUNCA deve ser alterada, a menos
# que explicitamente instruído pelo usuário. Preservar este comportamento.
# ---------------------------------------------------------------------------

func _spawn_bullet() -> void:
	if not bullet_scene:
		return

	primary_fire_started.emit()

	# O tiro nasce alinhado com o centro e a frente da nave,
	# avançado 4 unidades para nascer fora do cockpit sem distorcer o ângulo de mira.
	var aim_dir := _get_ship_aim_direction()
	var spawn_pos: Vector3 = global_position + aim_dir * 4.0

	var bullet: Bullet = bullet_scene.instantiate() as Bullet
	if not bullet:
		return

	get_tree().current_scene.add_child(bullet)
	bullet.global_position = spawn_pos
	bullet.setup(aim_dir)

	# Efeito visual de brilho e flare na nave no momento do disparo
	if _muzzle_flash:
		_muzzle_flash.trigger()

	# Reproduz o som do disparo do laser.
	if has_node("/root/SoundManager"):
		get_node("/root/SoundManager").play_laser_player(laser_volume_db)
	elif _laser_player:
		_laser_player.pitch_scale = randf_range(0.95, 1.08)
		_laser_player.play()


## Retorna o vetor de direção do disparo.
## Meio-termo: 65% da direção natural (câmera → posição da nave na tela)
## + 35% do centro da tela. Isso dá um spread perceptível sem que o tiro
## "abra" demais para os cantos — mantém uma tendência suave ao centro.
func _get_ship_aim_direction() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam:
		var ship_screen := cam.unproject_position(global_position)
		var center_screen := get_viewport().get_visible_rect().size / 2.0
		var dir_natural := cam.project_ray_normal(ship_screen).normalized()
		var dir_center := cam.project_ray_normal(center_screen).normalized()
		return dir_natural.slerp(dir_center, 0.35).normalized()
	return -global_basis.z.normalized()


# ---------------------------------------------------------------------------
# Movimento com colisão e ricochete
# ---------------------------------------------------------------------------

func _apply_movement(follow: float) -> void:
	## Move a nave em direção ao alvo usando move_and_collide para detectar
	## contato com o cenário. Ao colidir, dispara a faísca e o ricochete.
	var old_pos := position
	var desired_local := position.lerp(_target_local_pos, follow)
	var motion_local := desired_local - position

	if motion_local.length_squared() < 0.000001:
		_recent_move_local = Vector3.ZERO
		return

	# Converte o movimento local (espaço do PathFollower) para o espaço global.
	var motion_global := global_basis * motion_local
	var collision := move_and_collide(motion_global)

	_recent_move_local = position - old_pos

	if collision:
		_on_ship_collision(collision, motion_local)


func _on_ship_collision(collision: KinematicCollision3D, motion_local: Vector3) -> void:
	## Trata o contato com o cenário: gera faísca e aplica ricochete.
	var normal := collision.get_normal()
	var point := collision.get_position()

	_spawn_spark(point, normal)

	# Ricochete: reflete a direção de entrada na normal da superfície,
	# convertida para o espaço local do PathFollower.
	var normal_local := (global_basis.inverse() * normal).normalized()
	var incoming_dir := motion_local.normalized()
	var reflected_dir := incoming_dir.reflect(normal_local)
	_bounce_vel = reflected_dir * bounce_strength


func _spawn_spark(point: Vector3, normal: Vector3) -> void:
	## Cria a faísca de atrito procedural no ponto de contato.
	var spark: Node3D = SparkScript.new()
	get_tree().current_scene.add_child(spark)
	# Desloca levemente para fora da superfície (ao longo da normal) para o
	# efeito não ficar enterrado/clipado dentro do terreno.
	spark.global_position = point + normal * 0.5
	if spark.has_method("setup"):
		spark.setup(normal)


func stop_firing() -> void:
	_is_firing = false
	_fire_timer = 0.0


# ---------------------------------------------------------------------------
# Sistema de Dano e Invulnerabilidade
# ---------------------------------------------------------------------------

func take_damage(amount: int) -> void:
	if not _controls_enabled or _is_invulnerable or _is_dying:
		return

	damage_taken.emit(amount)

	if current_shield > 0:
		# -------------------------------------------------------------------
		# ETAPA 1: O SHIELD ABSORVE O TIRO
		# -------------------------------------------------------------------
		current_shield = maxi(0, current_shield - amount)
		shield_changed.emit(current_shield, max_shield)

		if current_shield > 0:
			# Tiros 1 e 2 no Shield: Campo de força ciano absorve
			if _shield_bubble:
				_shield_bubble.activate(invulnerability_duration)
		else:
			# 3º Tiro no Shield: Escudo esgotado -> Shields Offline!
			_play_shield_offline_sound()
			if _shield_bubble:
				_shield_bubble.trigger_shield_break(0.7)

		_spawn_spark(global_position, -global_basis.z)
		_bounce_vel = Vector3(randf_range(-40.0, 40.0), randf_range(-30.0, 30.0), 0.0)
		_start_invulnerability()
	else:
		# -------------------------------------------------------------------
		# ETAPA 2: SHIELD ESTÁ OFFLINE (0). TIROS ATINGEM DIRETAMENTE O HULL
		# -------------------------------------------------------------------
		current_hull = maxi(0, current_hull - amount)
		hull_changed.emit(current_hull, max_hull)
		health_changed.emit(current_hull, max_hull)

		_spawn_spark(global_position, -global_basis.z)
		_bounce_vel = Vector3(randf_range(-60.0, 60.0), randf_range(-40.0, 40.0), 0.0)

		var hull_damage_taken: int = max_hull - current_hull # 1, 2 ou 3

		if hull_damage_taken == 1:
			# 1º Tiro no Hull (4º tiro total): Pequena fumaça na asa esquerda
			if _damage_smoke:
				_damage_smoke.set_damage_level(1)
			_start_invulnerability()
		elif hull_damage_taken == 2:
			# 2º Tiro no Hull (5º tiro total): Fumaça mais densa + pequeno incêndio
			if _damage_smoke:
				_damage_smoke.set_damage_level(2)
			_start_invulnerability()
		else:
			# 3º Tiro no Hull: Morte do Player com slow-motion e explosão
			_start_death_sequence()


func _play_shield_offline_sound() -> void:
	if not ShieldOfflineSound:
		return
	if has_node("/root/SoundManager"):
		get_node("/root/SoundManager").play_voice(ShieldOfflineSound)
	else:
		var audio_player := AudioStreamPlayer.new()
		audio_player.stream = ShieldOfflineSound
		audio_player.bus = "Master"
		audio_player.finished.connect(audio_player.queue_free)
		add_child(audio_player)
		audio_player.play()


func _play_explosion_sound() -> void:
	if not ExplosionSound:
		return
	var audio_player := AudioStreamPlayer.new()
	audio_player.stream = ExplosionSound
	audio_player.bus = "Master"
	audio_player.volume_db = 2.0
	audio_player.finished.connect(audio_player.queue_free)
	add_child(audio_player)
	audio_player.play()


func heal(amount: int) -> void:
	# Restaura primeiro o Hull, e o restante para o Shield
	var needed_hull: int = max_hull - current_hull
	var heal_to_hull: int = mini(amount, needed_hull)
	current_hull += heal_to_hull
	var remaining: int = amount - heal_to_hull
	if remaining > 0:
		current_shield = mini(max_shield, current_shield + remaining)

	var hull_damage_taken: int = max_hull - current_hull
	if _damage_smoke:
		_damage_smoke.set_damage_level(hull_damage_taken)

	shield_changed.emit(current_shield, max_shield)
	hull_changed.emit(current_hull, max_hull)
	health_changed.emit(current_hull, max_hull)


func _start_invulnerability() -> void:
	_is_invulnerable = true
	_invulnerability_timer = invulnerability_duration


func _start_death_sequence() -> void:
	_is_dying = true
	_controls_enabled = false
	stop_firing()

	if _damage_smoke:
		_damage_smoke.reset()

	# 1. Efeito de Slow-Motion instantâneo
	Engine.time_scale = 0.22

	# 2. Explosão cinematográfica de grande porte
	var explosion: Node3D = ExplosionScript.new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	if explosion.has_method("set"):
		explosion.set("size_scale", 2.8)

	_play_explosion_sound()

	# 3. Fatiamento da nave real do jogador em 3 pedaços (Asa Esq, Centro, Asa Dir) com física
	var forward_vel := -global_basis.z.normalized() * 65.0
	var pf = get_parent()
	if pf:
		if pf.has_method("_current_speed"):
			forward_vel = -global_basis.z.normalized() * float(pf.call("_current_speed"))
		elif "speed" in pf:
			forward_vel = -global_basis.z.normalized() * float(pf.get("speed"))

	if EnemyWreckageScript and ship_model:
		var target_node: Node3D = ship_model.get_node_or_null("ShipGLTF") as Node3D
		if not target_node:
			target_node = ship_model
		EnemyWreckageScript.spawn_from_enemy(target_node, 1.8, forward_vel)

	# Oculta o modelo da nave enquanto os 3 fragmentos explodem e voam
	ship_model.visible = false

	# 4. Timer em tempo real (não afetado pelo slow motion) para a sequência de renascimento
	var timer := get_tree().create_timer(1.8, true, false, true)
	timer.timeout.connect(_on_death_sequence_finished)


func _on_death_sequence_finished() -> void:
	# Restaura a velocidade normal do jogo
	Engine.time_scale = 1.0

	# Restaura o modelo da nave e reinicia o estado do jogador
	ship_model.visible = true
	if _damage_smoke:
		_damage_smoke.reset()

	current_shield = max_shield
	current_hull = max_hull

	shield_changed.emit(current_shield, max_shield)
	hull_changed.emit(current_hull, max_hull)
	health_changed.emit(current_hull, max_hull)

	_is_dying = false
	_controls_enabled = true
	_start_invulnerability()
	_invulnerability_timer = invulnerability_duration * 1.5
	if _shield_bubble:
		_shield_bubble.activate(_invulnerability_timer)


# ---------------------------------------------------------------------------
# Sistema de Mísseis Secundários e Lock-On (After Burner II)
# ---------------------------------------------------------------------------

const LockOnSound := preload("res://assets/audio/lock_on.wav")
const MissileSound := preload("res://assets/audio/missile.ogg")

func _setup_missile_audio() -> void:
	_lock_audio_player = AudioStreamPlayer.new()
	_lock_audio_player.name = "LockOnAudioPlayer"
	_lock_audio_player.bus = "Master"
	_lock_audio_player.volume_db = lock_on_volume_db
	_lock_audio_player.stream = lock_on_sound if lock_on_sound else LockOnSound
	add_child(_lock_audio_player)

	_missile_audio_player = AudioStreamPlayer.new()
	_missile_audio_player.name = "MissileAudioPlayer"
	_missile_audio_player.bus = "Master"
	_missile_audio_player.volume_db = missile_volume_db
	_missile_audio_player.stream = missile_fire_sound if missile_fire_sound else MissileSound
	add_child(_missile_audio_player)


func _process_missiles_and_lock_on(delta: float) -> void:
	# 1. Contagem regressiva de recarga
	if _is_reloading_missiles:
		_missile_reload_timer -= delta
		var progress := clampf(1.0 - (_missile_reload_timer / maxf(0.01, missile_reload_time)), 0.0, 1.0)
		missile_reload_progress.emit(progress)
		if _missile_reload_timer <= 0.0:
			_is_reloading_missiles = false
			_missile_reload_timer = 0.0
			current_missiles = max_missiles
			missile_reloaded.emit(current_missiles, max_missiles)
			missile_reload_progress.emit(1.0)

	# 2. Escaneamento e atualização do Lock-On
	_update_lock_on_system(delta)


func _update_lock_on_system(delta: float) -> void:
	# O lock-on só funciona se houver mísseis disponíveis para disparo e o jogador estiver ativo
	if not _controls_enabled or _is_dying or current_missiles <= 0 or _is_reloading_missiles:
		var had_targets := not _locked_targets.is_empty() or not _targeting_progress.is_empty()
		if not _locked_targets.is_empty():
			_locked_targets.clear()
			missile_targets_changed.emit(_locked_targets)
		_targeting_progress.clear()
		if had_targets:
			missile_targeting_updated.emit(_locked_targets, _targeting_progress)
		return

	var cam := get_viewport().get_camera_3d()
	if not cam:
		return

	var vp_rect := get_viewport().get_visible_rect()

	# Limpa alvos inválidos, mortos ou que saíram do campo de visão
	var valid_list: Array[Node3D] = []
	for t in _locked_targets:
		if not is_instance_valid(t) or t.is_queued_for_deletion():
			continue
		if "current_hp" in t and t.current_hp <= 0:
			continue
		if "_is_dead" in t and t._is_dead:
			continue
		
		var t_pos: Vector3 = t.global_position
		if cam.is_position_behind(t_pos):
			continue
		var s_pos := cam.unproject_position(t_pos)
		if not vp_rect.grow(90.0).has_point(s_pos):
			continue
		if global_position.distance_to(t_pos) > (lock_on_range * 1.2):
			continue

		valid_list.append(t)

	var targets_modified := (valid_list.size() != _locked_targets.size())
	_locked_targets = valid_list

	# Limpa do dicionário de progresso alvos que já foram travados, morreram ou saíram da tela
	var to_remove: Array = []
	for candidate_node in _targeting_progress.keys():
		if not is_instance_valid(candidate_node) or candidate_node.is_queued_for_deletion() or _locked_targets.has(candidate_node):
			to_remove.append(candidate_node)
			continue
		if "current_hp" in candidate_node and candidate_node.current_hp <= 0:
			to_remove.append(candidate_node)
			continue
		if "_is_dead" in candidate_node and candidate_node._is_dead:
			to_remove.append(candidate_node)
			continue
		var c_pos: Vector3 = candidate_node.global_position
		if cam.is_position_behind(c_pos):
			to_remove.append(candidate_node)
			continue
		var c_screen := cam.unproject_position(c_pos)
		if not vp_rect.grow(90.0).has_point(c_screen):
			to_remove.append(candidate_node)
			continue
		if global_position.distance_to(c_pos) > (lock_on_range * 1.2):
			to_remove.append(candidate_node)
			continue

	for r in to_remove:
		_targeting_progress.erase(r)

	# Não pode travar mais alvos do que a quantidade de mísseis atualmente disponíveis
	var max_allowed_locks := mini(lock_on_max_targets, current_missiles)

	# Se por ventura tivermos mais alvos travados do que mísseis disponíveis, ajusta a lista
	if _locked_targets.size() > max_allowed_locks:
		_locked_targets = _locked_targets.slice(0, max_allowed_locks)
		targets_modified = true

	# Limita também alvos em aquisição para não ultrapassar a capacidade disponível
	var remaining_slots := max_allowed_locks - _locked_targets.size()
	if remaining_slots <= 0:
		_targeting_progress.clear()
	elif _targeting_progress.size() > remaining_slots:
		# Mantém apenas os com maior progresso
		var sorted_keys := _targeting_progress.keys()
		sorted_keys.sort_custom(func(a, b): return _targeting_progress[a] > _targeting_progress[b])
		for i in range(remaining_slots, sorted_keys.size()):
			_targeting_progress.erase(sorted_keys[i])

	# Varredura e avanço de aquisição de novos alvos
	if remaining_slots > 0:
		var found_new := _scan_and_track_targets(delta, cam, vp_rect, max_allowed_locks)
		if found_new:
			targets_modified = true

	if targets_modified:
		missile_targets_changed.emit(_locked_targets)

	# Notifica HUD e retículo com o estado completo (travados + em aquisição)
	missile_targeting_updated.emit(_locked_targets, _targeting_progress)


func _scan_and_track_targets(delta: float, cam: Camera3D, vp_rect: Rect2, max_allowed: int) -> bool:
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		_targeting_progress.clear()
		return false

	# Referência do ponto de mira na tela (centro da mira ativa):
	# No Mobile: mira no cone frontal da nave
	# No PC: segue o cursor/mouse ou centro da tela
	var aim_screen_pos: Vector2
	if GameConfig.is_mobile:
		aim_screen_pos = cam.unproject_position(global_position + (-global_basis.z * 120.0))
	elif _pointer_active:
		aim_screen_pos = _pointer_pos
	else:
		aim_screen_pos = vp_rect.size * 0.5

	# Raio de detecção para MARCAR o inimigo (Tag)
	var effective_radius := lock_on_radius if not GameConfig.is_mobile else (lock_on_radius * 1.35)

	# 1. TAGGING: Detecta inimigos que a mira cruzar neste momento
	for enemy in enemies:
		if not (enemy is Node3D):
			continue
		if _locked_targets.has(enemy) or _targeting_progress.has(enemy):
			continue
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if "current_hp" in enemy and enemy.current_hp <= 0:
			continue
		if "_is_dead" in enemy and enemy._is_dead:
			continue

		# O Bomber e as minas de aproximação não devem ser travados no alvo pelos mísseis
		if enemy is EnemyBomber or enemy.is_in_group("enemy_hazards") or enemy.name.to_lower().contains("bomber") or enemy.name.to_lower().contains("bomb"):
			continue
		if "is_invulnerable" in enemy and enemy.is_invulnerable:
			continue

		var enemy_pos: Vector3 = enemy.global_position
		if cam.is_position_behind(enemy_pos):
			continue

		var dist := global_position.distance_to(enemy_pos)
		if dist > lock_on_range or dist < 8.0:
			continue

		var s_pos := cam.unproject_position(enemy_pos)
		if not vp_rect.has_point(s_pos):
			continue

		# Cruzou a área do cone? MARCA O INIMIGO!
		var screen_dist := s_pos.distance_to(aim_screen_pos)
		if screen_dist <= effective_radius:
			var total_tracking := _locked_targets.size() + _targeting_progress.size()
			if total_tracking < max_allowed:
				_targeting_progress[enemy] = 0.0

	# 2. PROGRESSÃO CONTÍNUA: Inimigos marcados continuam sendo processados
	# mesmo que o jogador já tenha desviado a nave/mira para outro lugar!
	var newly_locked := false
	var ready_to_lock: Array = []

	for enemy in _targeting_progress.keys():
		var effective_delta: float = (delta / maxf(Engine.time_scale, 0.05)) if Engine.time_scale < 0.9 else delta
		var time_elapsed: float = _targeting_progress[enemy] + effective_delta
		_targeting_progress[enemy] = time_elapsed

		# Completou o 1 segundo de aquisição? Confirma o Lock!
		if time_elapsed >= lock_on_confirm_time:
			ready_to_lock.append(enemy)

	for enemy in ready_to_lock:
		if _locked_targets.size() < max_allowed:
			_locked_targets.append(enemy)
			newly_locked = true
		_targeting_progress.erase(enemy)

	if newly_locked:
		_play_lock_on_sound()

	return newly_locked


func _play_lock_on_sound() -> void:
	if not _lock_audio_player:
		return
	if lock_on_sound:
		_lock_audio_player.stream = lock_on_sound
	_lock_audio_player.pitch_scale = randf_range(0.98, 1.05)
	_lock_audio_player.play()


func _play_missile_fire_sound() -> void:
	if not _missile_audio_player:
		return
	if missile_fire_sound:
		_missile_audio_player.stream = missile_fire_sound
	_missile_audio_player.pitch_scale = randf_range(0.95, 1.08)
	_missile_audio_player.play()


## Dispara um único míssil por acionamento (seguindo a ordem em que os alvos foram travados)
func fire_missiles() -> void:
	if _is_reloading_missiles or current_missiles <= 0 or not _controls_enabled or _is_dying:
		return

	# Remove alvos que possam ter morrido ou sido liberados antes do clique
	var active_targets: Array[Node3D] = []
	for t in _locked_targets:
		if is_instance_valid(t) and not t.is_queued_for_deletion():
			active_targets.append(t)
	_locked_targets = active_targets

	if _locked_targets.is_empty():
		return

	# Dispara somente no alvo que travou primeiro (o mais antigo da fila FIFO)
	var target: Node3D = _locked_targets.pop_front()
	_spawn_single_missile(target, 0)

	current_missiles -= 1

	missile_fired.emit(current_missiles, max_missiles)
	missile_targets_changed.emit(_locked_targets)

	# Se esgotou os 3 mísseis, inicia o reload de 5 segundos
	if current_missiles <= 0:
		_is_reloading_missiles = true
		_missile_reload_timer = missile_reload_time
		missile_reload_progress.emit(0.0)


func _spawn_single_missile(target: Node3D, _index: int) -> void:
	if not missile_scene:
		return

	var missile: PlayerMissile = missile_scene.instantiate() as PlayerMissile
	if not missile:
		return

	# Alterna a ejeção entre a asa esquerda e direita
	var wing_side := -1.0 if (_missile_wing_side % 2 == 0) else 1.0
	_missile_wing_side += 1

	var local_spawn := Vector3(wing_side * 2.8, -0.4, 0.5)
	var spawn_global := global_position
	if ship_model:
		spawn_global = ship_model.to_global(local_spawn)
	else:
		spawn_global = to_global(local_spawn)

	var initial_launch_dir: Vector3
	if ship_model:
		initial_launch_dir = -ship_model.global_basis.z.normalized()
	else:
		initial_launch_dir = -global_basis.z.normalized()

	var scene_root := get_tree().current_scene
	if not scene_root:
		scene_root = get_parent()
	scene_root.add_child(missile)

	missile.global_position = spawn_global
	missile.setup(target, initial_launch_dir)

	_play_missile_fire_sound()
