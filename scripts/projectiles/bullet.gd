class_name Bullet
extends Area3D

## Projétil que viaja em linha reta e causa dano ao colidir.
##
## ARQUITETURA:
## - Viaja em direção definida via setup().
## - Colisão com inimigos detectada via signals (body_entered, area_entered).
## - Colisão com o CENÁRIO detectada via raycast (para obter ponto/normal
##   exatos e evitar "tunelamento" através de malha fina).
## - Auto-destrói ao sair da área de jogo.
## - O dano é tratado pelo alvo (target recebe o sinal e processa).

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------

@export var speed: float = 800.0  ## Velocidade do projétil (unidades/segundo)

# Camada de colisão do cenário/terreno ("world", layer 4).
const WORLD_LAYER_MASK: int = 1 << 3

# Script da explosão procedural (sem assets externos).
const ExplosionScript := preload("res://scripts/effects/explosion.gd")

# ---------------------------------------------------------------------------
# Propriedades exportadas
# ---------------------------------------------------------------------------

@export var damage: int = 1

# Distância máxima antes de auto-destruir (evita bullets eternos).
@export var max_distance: float = 2000.0

# ---------------------------------------------------------------------------
# Estado interno
# ---------------------------------------------------------------------------

var _direction: Vector3 = Vector3.FORWARD
var _spawn_position: Vector3 = Vector3.ZERO
var _prev_position: Vector3 = Vector3.ZERO
var _ray: RayCast3D = null

func _ready() -> void:
	collision_layer = 2
	collision_mask = 2
	monitoring = true
	monitorable = true

	add_to_group("player_bullets")

	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Raycast para detecção precisa de impacto no cenário.
	_ray = RayCast3D.new()
	_ray.enabled = false
	_ray.collision_mask = WORLD_LAYER_MASK
	_ray.collide_with_bodies = true
	_ray.collide_with_areas = false
	add_child(_ray)
	_prev_position = global_position


# ---------------------------------------------------------------------------
# API pública
# ---------------------------------------------------------------------------

func setup(dir: Vector3) -> void:
	## Define a direção de viagem.
	_direction = dir.normalized()
	_spawn_position = global_position
	_prev_position = global_position

	if _direction.length_squared() > 0.000001:
		var up := Vector3.UP
		if absf(_direction.dot(up)) > 0.99:
			up = Vector3.RIGHT
		look_at(global_position - _direction, up)


# ---------------------------------------------------------------------------
# Processamento
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_prev_position = global_position
	var next_pos := global_position + _direction * speed * delta

	# Varredura contínua rápida entre _prev_position e next_pos
	# Garante acerto sem tunelamento (CCD) contra inimigos e cenário
	if _check_sweep_hit(_prev_position, next_pos):
		return

	global_position = next_pos

	# Auto-destrói se ultrapassar a distância máxima percorrida
	if global_position.distance_squared_to(_spawn_position) > max_distance * max_distance:
		queue_free()


func _check_sweep_hit(from_pos: Vector3, to_pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if not space:
		return false

	# =========================================================================
	# 1. Detecção precisa contra INIMIGOS (Layer 2)
	# Utiliza raycast no trajeto percorrido no frame
	# =========================================================================
	var ray_enemy := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	ray_enemy.collision_mask = 2
	ray_enemy.collide_with_areas = true
	ray_enemy.collide_with_bodies = true
	ray_enemy.exclude = [self.get_rid()]

	var hit_enemy := space.intersect_ray(ray_enemy)
	if not hit_enemy.is_empty():
		var collider: Object = hit_enemy.collider
		if collider and collider != self:
			if collider.has_method("take_damage"):
				collider.take_damage(damage)
				queue_free()
				return true
			elif collider.get_parent() and collider.get_parent().has_method("take_damage"):
				collider.get_parent().take_damage(damage)
				queue_free()
				return true

	# =========================================================================
	# 2. Detecção contra CENÁRIO / TERRENO (Layer 8)
	# =========================================================================
	var ray_world := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	ray_world.collision_mask = WORLD_LAYER_MASK
	ray_world.collide_with_areas = false
	ray_world.collide_with_bodies = true
	ray_world.exclude = [self.get_rid()]

	var hit_world := space.intersect_ray(ray_world)
	if not hit_world.is_empty():
		if hit_world.has("position") and not hit_world.collider is CharacterBody3D:
			var normal: Vector3 = hit_world.normal if hit_world.has("normal") else Vector3.UP
			_spawn_explosion(hit_world.position, normal)
			queue_free()
			return true

	return false


func _spawn_explosion(point: Vector3, normal: Vector3) -> void:
	## Cria uma pequena faísca/puff no ponto de impacto na rocha (sem tocar som de explosão de nave)
	var explosion: Node3D = ExplosionScript.new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = point + normal * 0.5
	if explosion.has_method("set"):
		explosion.set("size_scale", 0.25)


# ---------------------------------------------------------------------------
# Colisões de Fallback (Sinais nativos de Area3D)
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if is_queued_for_deletion():
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
	elif not body is CharacterBody3D:
		queue_free()


func _on_area_entered(area: Area3D) -> void:
	if is_queued_for_deletion():
		return
	if area.has_method("take_damage"):
		area.take_damage(damage)
		queue_free()