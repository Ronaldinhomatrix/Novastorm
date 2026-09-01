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

signal health_changed(current: int, max_health: int)
signal damage_taken(amount: int)

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

@export_category("Combate")
@export var fire_rate: float = 0.5
@export var bullet_scene: PackedScene = null

@export_category("Áudio")
## Volume do tiro laser em dB. 0 = 100% (padrão Godot), -6 ≈ 50%, -12 ≈ 25%.
@export var laser_volume_db: float = -6.0

@export_category("Colisao")
## Velocidade inicial do "pulo" ao ricochetear (local, unidades/segundo).
@export var bounce_strength: float = 320.0
## Rapidez com que o ricochete decai (maior = some mais rápido).
@export var bounce_damping: float = 15.0

@export_category("Vida e Escudo")
@export var max_health: int = 5
@export var invulnerability_duration: float = 1.0

# Scripts procedurais
const SparkScript := preload("res://scripts/effects/spark.gd")
const ExplosionScript := preload("res://scripts/effects/explosion.gd")
const ShieldBubbleScene := preload("res://scenes/effects/shield_bubble.tscn")

# Som de disparo do laser e alerta de escudo.
const LaserSound := preload("res://assets/audio/laser1_player.ogg")
const ShieldOfflineSound := preload("res://assets/audio/shield_offline.ogg")

# ---------------------------------------------------------------------------
# Estado Interno
# ---------------------------------------------------------------------------

var current_health: int = 5
var _total_damage_hits: int = 0
var _is_invulnerable: bool = false
var _invulnerability_timer: float = 0.0

var _is_firing: bool = false
var _fire_timer: float = 0.0

var _is_mobile: bool = false

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

@onready var ship_model: Node3D = $ShipModel

# ---------------------------------------------------------------------------
# Ciclo de Vida
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("player")
	current_health = max_health
	_is_mobile = OS.has_feature("android") or OS.has_feature("ios")

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

	var col_shape := $CollisionShape3D as CollisionShape3D
	if col_shape and col_shape.shape is BoxShape3D:
		col_shape.shape.size = Vector3(5, 2.5, 9)

	health_changed.emit(current_health, max_health)

	# Só reposiciona a nave quando ela é filha de um PathFollow3D (modo rail
	# shooter), onde a posição local deve ficar fixa à frente da câmera.
	# Quando a nave é filha direta do nível/Level (ex.: nível em edição, sem
	# trajetória), ela deve respeitar a posição definida no editor.
	if get_parent() is PathFollow3D:
		position = Vector3(0.0, 0.0, forward_offset)
	_target_local_pos = position


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
	if _is_mobile:
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

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_is_firing = event.pressed


func _handle_mobile_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if not _drag_active:
				_touch_index = event.index
				_drag_active = true
				_pointer_active = false
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
	var follow := clampf(pointer_follow_speed * delta, 0.0, 1.0)
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
	_target_local_pos.x += input_dir.x * speed * delta
	_target_local_pos.y -= input_dir.y * speed * delta
	_target_local_pos.z = forward_offset


# ---------------------------------------------------------------------------
# Rotação Estética (Juice)
# ---------------------------------------------------------------------------

func _handle_ship_rotation(delta: float) -> void:
	if not ship_model:
		return

	var dir_x := clampf(_recent_move_local.x / maxf(1.0, speed * delta), -1.0, 1.0)
	var dir_y := clampf(_recent_move_local.y / maxf(1.0, speed * delta), -1.0, 1.0)

	ship_model.rotation.z = lerpf(ship_model.rotation.z, -dir_x * roll_amount, rotation_speed * delta)
	ship_model.rotation.x = lerpf(ship_model.rotation.x, dir_y * pitch_amount, rotation_speed * delta)
	ship_model.rotation.y = lerpf(ship_model.rotation.y, -dir_x * 0.25, rotation_speed * delta)


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

	# O tiro sai exatamente na direção em que a nave (ShipModel) está apontando naquele momento.
	var aim_dir := _get_ship_aim_direction()
	var spawn_pos: Vector3
	if ship_model:
		spawn_pos = ship_model.global_position + aim_dir * 4.0
	else:
		spawn_pos = global_position + aim_dir * 4.0

	var bullet: Bullet = bullet_scene.instantiate() as Bullet
	if not bullet:
		return

	get_tree().current_scene.add_child(bullet)
	bullet.global_position = spawn_pos
	bullet.setup(aim_dir)

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
	if not _controls_enabled or _is_invulnerable:
		return

	current_health = maxi(0, current_health - amount)
	_total_damage_hits += 1

	if _total_damage_hits == 3:
		_play_shield_offline_sound()

	damage_taken.emit(amount)
	health_changed.emit(current_health, max_health)
	_trigger_damage_feedback()

	if current_health <= 0:
		_on_player_destroyed()
	else:
		_start_invulnerability()


func _play_shield_offline_sound() -> void:
	if not ShieldOfflineSound:
		return
	var audio_player := AudioStreamPlayer.new()
	audio_player.stream = ShieldOfflineSound
	audio_player.bus = "Master"
	audio_player.finished.connect(audio_player.queue_free)
	add_child(audio_player)
	audio_player.play()


func heal(amount: int) -> void:
	current_health = mini(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)


func _start_invulnerability() -> void:
	_is_invulnerable = true
	_invulnerability_timer = invulnerability_duration


func _trigger_damage_feedback() -> void:
	# Ativa o campo de força 3D (escudo holográfico) por 1 segundo
	if _shield_bubble:
		_shield_bubble.activate(invulnerability_duration)

	# Cria faíscas no corpo da nave indicando impacto
	_spawn_spark(global_position, -global_basis.z)
	# Ricochete de impacto para trás
	_bounce_vel = Vector3(randf_range(-60.0, 60.0), randf_range(-40.0, 40.0), 0.0)


func _on_player_destroyed() -> void:
	# Efeito de explosão dramática
	var explosion: Node3D = ExplosionScript.new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	if explosion.has_method("set"):
		explosion.set("size_scale", 2.0)

	# Recupera vida e reinicia temporizador de invulnerabilidade (respawn gracioso)
	current_health = max_health
	health_changed.emit(current_health, max_health)
	_start_invulnerability()
	_invulnerability_timer = invulnerability_duration * 1.5
	if _shield_bubble:
		_shield_bubble.activate(_invulnerability_timer)
