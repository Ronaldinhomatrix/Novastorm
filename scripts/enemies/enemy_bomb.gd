class_name EnemyBomb
extends Area3D

## Mina de aproximação / Bomba flutuante lançada pelo Enemy Bomber.
##
## Permanece parada no espaço 3D do mundo flutuando suavemente.
## O jogador deve desviar ou destruí-la com seus tiros antes de colidir.
## - Causa 1 de dano se colidir com o jogador.
## - Possui 1 HP e explode se atingida por tiros de laser do jogador (concedendo 50 pontos).
## - Auto-destrói suavemente quando o jogador a ultrapassa e fica para trás.

signal bomb_destroyed(bomb: Node, score: int)

const ExplosionScript := preload("res://scripts/effects/explosion.gd")
const ExplosionSounds: Array[AudioStream] = [
	preload("res://assets/audio/explosion1.ogg"),
	preload("res://assets/audio/explosion2.ogg"),
]

@export var max_hp: int = 1
@export var damage: int = 1
@export var score_value: int = 50
@export var explosion_scale: float = 0.85
@export var blink_speed: float = 6.0

var current_hp: int = 1
var _is_exploding: bool = false
var _initial_pos: Vector3 = Vector3.ZERO
var _float_time: float = 0.0
var _random_rot_axis: Vector3 = Vector3.UP
var _random_rot_speed: float = 1.0

@onready var light: OmniLight3D = get_node_or_null("OmniLight3D") as OmniLight3D
@onready var core_mesh: MeshInstance3D = get_node_or_null("CoreMesh") as MeshInstance3D
@onready var plasma_halo: MeshInstance3D = get_node_or_null("PlasmaHalo") as MeshInstance3D
@onready var plasma_inner: MeshInstance3D = get_node_or_null("PlasmaInner") as MeshInstance3D


func _ready() -> void:
	current_hp = max_hp
	_initial_pos = global_position
	_random_rot_axis = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	if _random_rot_axis.length_squared() < 0.1:
		_random_rot_axis = Vector3.UP
	_random_rot_speed = randf_range(0.8, 1.8)

	collision_layer = 2 | 4  # Layer 2 (inimigo atingível por tiros) e Layer 4 (projétil/perigo)
	collision_mask = 1 | 2   # Detecta jogador (Layer 1) e tiros do jogador (Layer 2)
	monitoring = true
	monitorable = true

	add_to_group("enemy_hazards")
	add_to_group("enemies")

	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _is_exploding:
		return

	_float_time += delta

	# Rotação suave no próprio eixo
	rotate(_random_rot_axis, _random_rot_speed * delta)

	# Flutuação e oscilação suave no ar
	var bob_y := sin(_float_time * 2.5) * 0.35
	var bob_x := cos(_float_time * 1.8) * 0.2
	global_position = _initial_pos + Vector3(bob_x, bob_y, 0.0)

	# Efeito pulsante de alerta na luz e brilho intenso
	var pulse := (sin(_float_time * blink_speed) + 1.0) * 0.5
	if light:
		light.light_energy = lerpf(8.0, 22.0, pulse)
	if plasma_halo:
		var halo_scale := lerpf(1.0, 1.25, pulse)
		plasma_halo.scale = Vector3.ONE * halo_scale

	# Verificação de descarte caso o jogador tenha ultrapassado
	_check_despawn()


func _check_despawn() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not player or not is_instance_valid(player):
		return

	# Vetor do jogador até a bomba
	var to_bomb := global_position - player.global_position
	var forward_dir := -player.global_basis.z.normalized()
	var forward_distance := to_bomb.dot(forward_dir)

	# Se a bomba ficou mais de 35m atrás do jogador na direção do voo, remove
	if forward_distance < -35.0:
		queue_free()


func take_damage(amount: int = 1) -> void:
	if _is_exploding:
		return

	current_hp -= amount
	if current_hp <= 0:
		_award_score()
		_explode()


func _on_body_entered(body: Node3D) -> void:
	if _is_exploding:
		return

	# Colisão direta com o jogador (CharacterBody3D)
	if body.is_in_group("player") or body.has_method("take_damage"):
		body.take_damage(damage)
		_explode()
	elif body.is_in_group("player_bullets"):
		take_damage(1)


func _on_area_entered(area: Area3D) -> void:
	if _is_exploding:
		return

	# Tiros do jogador
	if area.is_in_group("player_bullets") or (area.name.begins_with("Bullet") and not area.name.begins_with("Enemy")):
		take_damage(1)
		if is_instance_valid(area) and not area.is_queued_for_deletion():
			area.queue_free()


func _award_score() -> void:
	bomb_destroyed.emit(self, score_value)
	var game_ctrl := get_tree().get_first_node_in_group("game_controller")
	if game_ctrl and game_ctrl.has_method("add_score"):
		game_ctrl.add_score(score_value)


func _explode() -> void:
	if _is_exploding:
		return
	_is_exploding = true

	# Explosão visual com múltiplas camadas
	var explosion: Node3D = ExplosionScript.new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	if explosion.has_method("set"):
		explosion.set("size_scale", explosion_scale)

	# Som de explosão
	if ExplosionSounds.size() > 0:
		var sound: AudioStream = ExplosionSounds.pick_random()
		var audio := AudioStreamPlayer.new()
		audio.stream = sound
		audio.bus = "Master"
		audio.volume_db = -2.0
		audio.finished.connect(audio.queue_free)
		get_tree().current_scene.add_child(audio)
		audio.play()

	queue_free()
