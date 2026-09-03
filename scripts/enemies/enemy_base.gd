class_name EnemyBase
extends Area3D

## Classe base para todas as naves inimigas no Novastorm.
## Gerencia vida (HP), detecção de dano do jogador, efeito visual de hit-flash,
## disparo de projéteis, isolamento de malha e explosão de destruição.

signal enemy_destroyed(enemy: Node, score: int)

const ExplosionScript := preload("res://scripts/effects/explosion.gd")
const EnemyWreckageScript := preload("res://scripts/effects/enemy_wreckage.gd")
const LaserSound := preload("res://assets/audio/laser1.ogg")
const EngineSound := preload("res://assets/audio/3_enemy_red_starships_engine.ogg")
const WORLD_LAYER_MASK: int = 1 << 3  # Layer 4: "World" (paredes do canyon e terreno)
const ExplosionSounds: Array[AudioStream] = [
	preload("res://assets/audio/explosion1.ogg"),
	preload("res://assets/audio/explosion2.ogg"),
]

@export_category("Atributos")
@export var max_hp: int = 1
@export var score_value: int = 100
@export var is_invulnerable: bool = false
@export var target_ship_node_name: String = ""  ## Nome do nó da nave a exibir do GLB (ex: Starship.002, Starship.v2, Starship.v3)

@export_category("Armas e Áudio")
@export var bullet_scene: PackedScene = null
@export var laser_volume_db: float = -4.0
@export var explosion_volume_db: float = -2.5
@export var enable_engine_sound: bool = true
@export var engine_volume_db: float = -0.5

var current_hp: int = 1
var _is_dead: bool = false
var _mesh_instances: Array[MeshInstance3D] = []
var _flash_tween: Tween = null
var _laser_audio_player: AudioStreamPlayer = null
var _engine_audio_player: AudioStreamPlayer3D = null
var _prev_global_pos: Vector3 = Vector3.ZERO
var _has_prev_pos: bool = false
var _linear_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	if not bullet_scene:
		bullet_scene = load("res://scenes/enemies/enemy_bullet_1.tscn")

	current_hp = max_hp
	collision_layer = 2
	collision_mask = 2
	monitoring = true
	monitorable = true

	add_to_group("enemies")

	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

	if target_ship_node_name != "":
		_isolate_target_ship()

	_setup_audio()
	_setup_engine_sound()
	_collect_mesh_instances(self)


func _on_area_entered(area: Area3D) -> void:
	if _is_dead or is_invulnerable:
		return
	# Ignora completamente projéteis disparados por inimigos
	if area.is_in_group("enemy_bullets") or area is EnemyBullet1 or area is EnemyBullet:
		return
	# Apenas projéteis do JOGADOR causam dano
	if area.is_in_group("player_bullets") or area is Bullet or (area.name.begins_with("Bullet") and not area.name.begins_with("EnemyBullet")):
		take_damage(1)
		if is_instance_valid(area) and not area.is_queued_for_deletion():
			area.queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _is_dead or is_invulnerable:
		return
	if body.is_in_group("enemy_bullets"):
		return
	if body.is_in_group("player_bullets") or body is Bullet:
		take_damage(1)
		if is_instance_valid(body) and not body.is_queued_for_deletion():
			body.queue_free()


func _isolate_target_ship() -> void:
	var glb_root: Node = get_node_or_null("ShipModel/3_enemy_red_starships")
	if not glb_root:
		glb_root = find_child("3_enemy_red_starships", true, false)
	if not glb_root:
		return

	var known_ships: Array[String] = ["Starship.002", "Starship.v2", "Starship.v3", "Starship_002", "Starship_v2", "Starship_v3"]
	for ship_name: String in known_ships:
		var node: Node = glb_root.find_child(ship_name, true, false)
		if node and node is Node3D:
			var match_name: String = String(ship_name).replace("_", ".")
			var target_clean: String = String(target_ship_node_name).replace("_", ".")
			if match_name == target_clean:
				(node as Node3D).visible = true
			else:
				(node as Node3D).visible = false


func _setup_audio() -> void:
	_laser_audio_player = AudioStreamPlayer.new()
	_laser_audio_player.stream = LaserSound
	_laser_audio_player.bus = "Master"
	_laser_audio_player.volume_db = laser_volume_db
	add_child(_laser_audio_player)


func _setup_engine_sound() -> void:
	if not enable_engine_sound or not EngineSound:
		return
	_engine_audio_player = AudioStreamPlayer3D.new()
	_engine_audio_player.name = "EngineSound3D"

	var stream_copy: AudioStream = EngineSound.duplicate()
	if stream_copy is AudioStreamOggVorbis:
		(stream_copy as AudioStreamOggVorbis).loop = true
	_engine_audio_player.stream = stream_copy

	_engine_audio_player.bus = "Master"
	_engine_audio_player.volume_db = engine_volume_db
	_engine_audio_player.unit_size = 16.0
	_engine_audio_player.max_distance = 380.0
	_engine_audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_engine_audio_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	_engine_audio_player.pitch_scale = randf_range(0.97, 1.03)
	add_child(_engine_audio_player)
	_engine_audio_player.play()
	_engine_audio_player.finished.connect(_on_engine_sound_finished)


func set_engine_pitch(pitch: float) -> void:
	if _engine_audio_player and is_instance_valid(_engine_audio_player):
		_engine_audio_player.pitch_scale = pitch


func _on_engine_sound_finished() -> void:
	if not _is_dead and is_instance_valid(_engine_audio_player) and is_inside_tree():
		_engine_audio_player.play()


func _collect_mesh_instances(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.extra_cull_margin = 1000.0
		if mi.is_visible_in_tree():
			_mesh_instances.append(mi)
	for child in node.get_children():
		_collect_mesh_instances(child)


# ---------------------------------------------------------------------------
# Seguimento de Curva (Curve Following)
# ---------------------------------------------------------------------------
## Permite que as naves inimigas voem ao longo do Path3D do cânion (a mesma
## trajetória do jogador) em vez de seguirem uma linha reta tangente fixa.
## Assim elas permanecem dentro do cânion e à frente do jogador, acompanhando
## as curvas com banking natural.

var _flight_path: Path3D = null
var _path_follower: PathFollower = null
var _curve_offset: float = -1.0  ## Offset (unidades) ao longo da curva; -1 = não inicializado


func _get_flight_path() -> Path3D:
	if _flight_path and is_instance_valid(_flight_path):
		return _flight_path
	var pf := _get_path_follower()
	if pf:
		_flight_path = pf.get_parent() as Path3D
	if not _flight_path and get_tree() and get_tree().current_scene:
		_flight_path = get_tree().current_scene.find_child("FlightPath", true, false) as Path3D
	return _flight_path


func _get_path_follower() -> PathFollower:
	if _path_follower and is_instance_valid(_path_follower):
		return _path_follower
	# Deriva da hierarquia do jogador: Player é filho do PathFollower.
	var player: Node3D = _get_player_node()
	if player:
		var p: Node = player.get_parent()
		while p:
			if p is PathFollower:
				_path_follower = p as PathFollower
				break
			p = p.get_parent()
	# Fallback: busca por nome na cena atual.
	if not _path_follower and get_tree() and get_tree().current_scene:
		_path_follower = get_tree().current_scene.find_child("PathFollower", true, false) as PathFollower
	return _path_follower


## Inicializa o offset ao longo da curva com base na distância à frente do jogador.
func _init_curve_offset(ahead_distance: float) -> void:
	var pf := _get_path_follower()
	if pf:
		_curve_offset = pf.progress + ahead_distance
	else:
		_curve_offset = 0.0


## Retorna a posição global de um ponto ao longo da curva, extrapolando linearmente
## de forma suave e contínua se o offset for negativo (< 0) ou ultrapassar o fim (> length).
func _sample_curve_position(offset: float) -> Vector3:
	var path := _get_flight_path()
	if path and path.curve and path.curve.point_count > 1:
		var length := path.curve.get_baked_length()
		if offset < 0.0:
			var p0 := path.global_transform * path.curve.sample_baked(0.0, true)
			var p1 := path.global_transform * path.curve.sample_baked(minf(4.0, length), true)
			var fwd := (p1 - p0).normalized()
			return p0 + fwd * offset
		elif offset > length:
			var pend := path.global_transform * path.curve.sample_baked(length, true)
			var pprev := path.global_transform * path.curve.sample_baked(maxf(0.0, length - 4.0), true)
			var fwd := (pend - pprev).normalized()
			return pend + fwd * (offset - length)
		else:
			return path.global_transform * path.curve.sample_baked(offset, true)
	return global_position


## Retorna a tangente global (direção de voo) suave e contínua em qualquer offset.
func _sample_curve_tangent(offset: float) -> Vector3:
	var path := _get_flight_path()
	if path and path.curve and path.curve.point_count > 1:
		var length := path.curve.get_baked_length()
		var sample_off := clampf(offset, 0.0, length)
		var a := maxf(0.0, sample_off - 3.0)
		var b := minf(length, sample_off + 3.0)
		if b - a < 0.1:
			b = minf(length, a + 4.0)
		var tangent := path.curve.sample_baked(b, true) - path.curve.sample_baked(a, true)
		if tangent.length_squared() > 0.0001:
			return (path.global_basis * tangent).normalized()
	return -global_basis.z if global_basis.z.length_squared() > 0.001 else Vector3.FORWARD


func _get_player_progress() -> float:
	var pf := _get_path_follower()
	if pf:
		return pf.progress
	return 0.0


## Retorna o referencial local (posição, forward, right, up) em um offset específico com deslocamentos.
func _sample_curve_frame(offset: float, lateral: float = 0.0, vertical: float = 0.0) -> Dictionary:
	var path := _get_flight_path()
	if path and path.curve and path.curve.point_count > 1:
		var fwd := _sample_curve_tangent(offset)
		var right := fwd.cross(Vector3.UP).normalized()
		if right.length_squared() < 0.001:
			right = Vector3.RIGHT
		var up := right.cross(fwd).normalized()
		var center := _sample_curve_position(offset)
		var pos := center + right * lateral + up * vertical
		return {"position": pos, "forward": fwd, "right": right, "up": up}

	# Fallback: voo em linha reta (sem curva disponível).
	var fwd_fallback := Vector3.FORWARD
	var pos_fallback := global_position + Vector3.RIGHT * lateral + Vector3.UP * vertical
	return {"position": pos_fallback, "forward": fwd_fallback, "right": Vector3.RIGHT, "up": Vector3.UP}


## Avança o inimigo ao longo da curva e devolve posição/orientação com offsets
## lateral e vertical aplicados no referencial local da curva.
func _advance_curve(delta: float, speed: float, lateral: float, vertical: float) -> Dictionary:
	if _curve_offset < 0.0:
		_init_curve_offset(240.0)
	_curve_offset += speed * delta
	return _sample_curve_frame(_curve_offset, lateral, vertical)


var _basis_initialized: bool = false


## Orienta a nave apontando -Z para "forward", com bank opcional
## (roll ao redor do eixo de voo) e interpolação suave para evitar qualquer solavanco.
func _orient_ship(forward: Vector3, up: Vector3, bank_rad: float = 0.0, instant: bool = false) -> void:
	var fwd := forward.normalized()
	var right := fwd.cross(up).normalized()
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	var corrected_up := right.cross(fwd).normalized()
	if bank_rad != 0.0:
		corrected_up = corrected_up.rotated(fwd, bank_rad).normalized()
		right = fwd.cross(corrected_up).normalized()
	var target_basis := Basis(right, corrected_up, -fwd).orthonormalized()

	if instant or not _basis_initialized:
		global_transform.basis = target_basis
		_basis_initialized = true
	else:
		global_transform.basis = global_transform.basis.slerp(target_basis, 0.3).orthonormalized()


## Retorna true se a nave do jogador já ultrapassou a posição do inimigo
func _is_behind_player() -> bool:
	var pf := _get_path_follower()
	if pf and _curve_offset >= 0.0:
		return _curve_offset < pf.progress - 15.0
	return false



func take_damage(amount: int) -> void:
	if _is_dead or is_invulnerable:
		return

	current_hp -= amount
	_play_hit_flash()

	if current_hp <= 0:
		die()


func _play_hit_flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	if _mesh_instances.is_empty():
		_collect_mesh_instances(self)

	var flash_mat: StandardMaterial3D = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(2.5, 0.4, 0.4, 1.0)

	for mi: MeshInstance3D in _mesh_instances:
		if is_instance_valid(mi):
			mi.material_override = flash_mat

	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.06)
	_flash_tween.tween_callback(func():
		for mi: MeshInstance3D in _mesh_instances:
			if is_instance_valid(mi):
				mi.material_override = null
	)


func fire_bullet(from_pos: Vector3, dir: Vector3) -> void:
	if not bullet_scene:
		return

	var bullet: Node = bullet_scene.instantiate()
	if not bullet or not bullet is Node3D:
		return

	get_tree().current_scene.add_child(bullet)
	(bullet as Node3D).global_position = from_pos
	if bullet.has_method("setup"):
		bullet.setup(dir)

	if not _is_dead:
		if has_node("/root/SoundManager"):
			get_node("/root/SoundManager").play_laser_enemy(laser_volume_db)
		elif _laser_audio_player:
			_laser_audio_player.pitch_scale = randf_range(0.9, 1.1)
			_laser_audio_player.play()


func fire_towards_player(from_pos: Vector3, aim_convergence: float = 0.8) -> void:
	var target_pos: Vector3 = _get_player_position()
	var dir: Vector3 = (target_pos - from_pos).normalized()
	
	var forward: Vector3 = -global_basis.z.normalized()
	var final_dir: Vector3 = forward.slerp(dir, aim_convergence).normalized()
	
	fire_bullet(from_pos, final_dir)


func _get_player_node() -> Node3D:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		player = get_node_or_null("/root/Game/FlightPath/PathFollower/Player")
	return player


func _get_player_position() -> Vector3:
	var player: Node3D = _get_player_node()
	if player:
		return player.global_position
	return global_position + Vector3(0, 0, 40)


## Remove o inimigo se saiu completamente do campo de visão da câmera:
## muito atrás da câmera ou muito fora das bordas laterais/verticais.
## Margem generosa de 50% para não remover antes da hora.
func _check_off_screen() -> void:
	var vp := get_viewport()
	if not vp:
		return
	var cam := vp.get_camera_3d()
	if not cam:
		return

	# Coordenadas no espaço da câmera:
	#   local.x = +direita, local.y = +cima, local.z = -frente (Godot -Z = forward)
	var local: Vector3 = cam.global_basis.inverse() * (global_position - cam.global_position)

	# Atrás da câmera: local.z > 0 (eixo +Z da câmera) OU muito perto do near plane (z > -3).
	if local.z > -3.0:
		queue_free()
		return

	# Fora das bordas da tela com margem de 50% extra em cada lado.
	var dist := absf(local.z)
	var half_h := tan(deg_to_rad(cam.fov) * 0.5) * dist
	var aspect := vp.get_visible_rect().size.aspect()
	var half_w := half_h * aspect
	var margin := 1.5
	if absf(local.x) > half_w * margin or absf(local.y) > half_h * margin:
		queue_free()


func _physics_process(delta: float) -> void:
	if _has_prev_pos and delta > 0.0001:
		_linear_velocity = (global_position - _prev_global_pos) / delta
	_prev_global_pos = global_position
	_has_prev_pos = true


## Retorna a velocidade linear atual do inimigo (usada para transferir momento aos destroços)
func get_linear_velocity() -> Vector3:
	if _linear_velocity.length_squared() > 10.0:
		return _linear_velocity
	var path_speed: float = 65.0
	var pf := _get_path_follower()
	if pf and pf.has_method("_current_speed"):
		path_speed = pf._current_speed()
	return -global_basis.z.normalized() * path_speed


func die() -> void:
	if _is_dead:
		return
	_is_dead = true

	# Desativa colisões imediatamente para evitar múltiplos hits no mesmo frame
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	if _engine_audio_player and is_instance_valid(_engine_audio_player):
		if _engine_audio_player.finished.is_connected(_on_engine_sound_finished):
			_engine_audio_player.finished.disconnect(_on_engine_sound_finished)
		_engine_audio_player.stop()

	# Desmonte do asset 3D em 3 partes mantendo o movimento de vôo da nave
	var vel := get_linear_velocity()
	EnemyWreckageScript.spawn_from_enemy(self, 1.0, vel)

	var explosion: Node3D = ExplosionScript.new()
	var spawn_parent: Node = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if spawn_parent:
		spawn_parent.add_child(explosion)
	explosion.global_position = global_position
	if explosion.has_method("set"):
		explosion.set("size_scale", 1.5)

	_play_explosion_sound()

	enemy_destroyed.emit(self, score_value)
	queue_free()


## Toca explosion1 ou explosion2 aleatoriamente via SoundManager (zero latency).
func _play_explosion_sound() -> void:
	if has_node("/root/SoundManager"):
		get_node("/root/SoundManager").play_explosion(explosion_volume_db)
		return

	if ExplosionSounds.is_empty():
		return
	var scene: Node = get_tree().current_scene if get_tree() else null
	if not scene:
		return
	var p := AudioStreamPlayer.new()
	p.stream = ExplosionSounds.pick_random()
	p.bus = "Master"
	p.volume_db = explosion_volume_db
	p.pitch_scale = randf_range(0.95, 1.05)
	scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
