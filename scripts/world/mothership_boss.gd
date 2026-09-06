class_name MothershipBoss
extends Node3D

## Controlador do Boss Mothership_1 no Nível de Órbita Planetária.
## Gerencia hitboxes, recepção de dano dos lasers do jogador, efeitos visuais
## de impacto, explosões localizadas e barra de vida no HUD.

signal boss_damaged(current_hp: int, max_hp: int)
signal boss_defeated

const SparkScript := preload("res://scripts/effects/spark.gd")
const ExplosionScript := preload("res://scripts/effects/explosion.gd")
const HitSound := preload("res://assets/audio/laser0.ogg")
const ShieldDownSound := preload("res://assets/audio/shield_offline.ogg")

@export_category("Vida e Pontuação")
@export var max_hp: int = 120
@export var score_value: int = 5000

@export_category("Movimento Orbital Sutil")
## Flutuação lenta da nave no vácuo orbital
@export var float_speed: float = 0.5
@export var float_amplitude: float = 8.0

var current_hp: int = 120
var _is_defeated: bool = false
var _initial_pos_y: float = 0.0
var _time: float = 0.0
var _hitbox_area: Area3D = null


func _ready() -> void:
	current_hp = max_hp
	_initial_pos_y = position.y
	_setup_hitboxes()


class BossHitboxArea extends Area3D:
	var boss: MothershipBoss = null
	func take_damage(amount: int) -> void:
		if boss:
			boss.take_damage(amount, global_position)


func _setup_hitboxes() -> void:
	# Cria uma Area3D na camada de colisão 2 ("bullet"/"enemy") para registrar tiros do jogador
	var area := BossHitboxArea.new()
	area.boss = self
	area.name = "BossHitboxArea"
	area.collision_layer = 2
	area.collision_mask = 2
	area.monitoring = true
	area.monitorable = true
	area.add_to_group("enemies")
	add_child(area)
	_hitbox_area = area

	# Bounding boxes principais para cobrir a gigantesca carcaça da nave
	# Casco frontal / proa
	_add_box_shape(_hitbox_area, Vector3(0.0, 0.0, 4.0), Vector3(3.5, 3.0, 10.0))
	# Seção central / asas
	_add_box_shape(_hitbox_area, Vector3(0.0, 0.0, -3.0), Vector3(8.0, 3.5, 12.0))
	# Motores traseiros
	_add_box_shape(_hitbox_area, Vector3(0.0, 0.0, -10.0), Vector3(5.0, 4.0, 6.0))


func _add_box_shape(parent_area: Area3D, local_pos: Vector3, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = local_pos
	parent_area.add_child(col)


func _process(delta: float) -> void:
	_time += delta
	# Flutuação orbital suave
	if not _is_defeated:
		position.y = _initial_pos_y + sin(_time * float_speed) * float_amplitude


## Chamado quando lasers colidem com a Area3D da nave
func take_damage(amount: int, hit_global_pos: Vector3 = Vector3.ZERO) -> void:
	if _is_defeated:
		return

	current_hp = max(0, current_hp - amount)
	boss_damaged.emit(current_hp, max_hp)

	# Som de impacto
	if HitSound:
		var audio := AudioStreamPlayer.new()
		audio.stream = HitSound
		audio.pitch_scale = randf_range(0.85, 1.15)
		audio.volume_db = -5.0
		add_child(audio)
		audio.play()
		audio.finished.connect(audio.queue_free)

	# Efeito visual de fagulhas/impacto
	if hit_global_pos != Vector3.ZERO and SparkScript:
		var spark := SparkScript.new()
		get_tree().current_scene.add_child(spark)
		spark.global_position = hit_global_pos
		spark.setup(Vector3.UP)

	if current_hp <= 0:
		_defeat_boss()


func _defeat_boss() -> void:
	_is_defeated = true
	boss_defeated.emit()

	if ShieldDownSound:
		var audio := AudioStreamPlayer.new()
		audio.stream = ShieldDownSound
		audio.volume_db = 2.0
		add_child(audio)
		audio.play()

	# Efeito de explosões secundárias ao longo do casco
	var tween := create_tween()
	for i in range(8):
		tween.tween_callback(func():
			_spawn_hull_explosion()
		)
		tween.tween_interval(0.3)


func _spawn_hull_explosion() -> void:
	if not ExplosionScript:
		return
	var offset := Vector3(
		randf_range(-60.0, 60.0),
		randf_range(-20.0, 20.0),
		randf_range(-150.0, 150.0)
	)
	var exp_instance: Node3D = ExplosionScript.new()
	get_tree().current_scene.add_child(exp_instance)
	exp_instance.global_position = global_position + offset
