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

# ---------------------------------------------------------------------------
# Ciclo de vida
# ---------------------------------------------------------------------------

func _ready() -> void:
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
	# Captura a posição de spawn AQUI (após o global_position já ter sido
	# atribuído pelo spawner). Em _ready() o global_position ainda é (0,0,0),
	# o que fazia o projétil ser destruído já no primeiro frame por exceder a
	# distância máxima ao nascer a ~2000 unidades da origem.
	_spawn_position = global_position
	_prev_position = global_position

	# Alinha o comprimento do projétil com a direção de viagem.
	# look_at() aponta o eixo -Z para o alvo; usando (posição - direção) fazemos
	# o eixo +Z (comprimento da cápsula) apontar na direção de viagem.
	if _direction.length_squared() > 0.000001:
		var up := Vector3.UP
		if absf(_direction.dot(up)) > 0.99:
			up = Vector3.RIGHT
		look_at(global_position - _direction, up)


# ---------------------------------------------------------------------------
# Processamento
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Salvamos a posição atual antes de avançar para o raycast cobrir o
	# deslocamento deste frame (evita "tunelamento" através de malha fina).
	_prev_position = global_position
	global_position += _direction * speed * delta

	_check_world_hit()

	# Auto-destrói se ultrapassar a distância máxima percorrida (relativa
	# ao ponto de spawn).
	if global_position.distance_squared_to(_spawn_position) > max_distance * max_distance:
		queue_free()


func _check_world_hit() -> void:
	## Dispara um raycast do ponto anterior ao atual para detectar acerto no
	## cenário. Ao acertar, gera a explosão procedural no ponto de impacto e
	## destrói o projétil.
	if not _ray:
		return

	var travel := global_position - _prev_position
	if travel.length_squared() < 0.000001:
		return

	_ray.global_position = _prev_position
	_ray.target_position = travel
	_ray.force_raycast_update()

	if _ray.is_colliding():
		var hit_point := _ray.get_collision_point()
		var hit_normal := _ray.get_collision_normal()
		_spawn_explosion(hit_point, hit_normal)
		queue_free()


func _spawn_explosion(point: Vector3, normal: Vector3) -> void:
	## Cria a explosão procedural no ponto de impacto.
	var explosion: Node3D = ExplosionScript.new()
	get_tree().current_scene.add_child(explosion)
	# Desloca levemente para fora da superfície para o efeito não ficar
	# enterrado/clipado dentro do terreno.
	explosion.global_position = point + normal * 0.5


# ---------------------------------------------------------------------------
# Colisões
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	## Colisão com corpo físico (ex: inimigo).
	if body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
		return

	# Colisão com paredes/obstáculos: apenas destrói o projétil
	if not body is CharacterBody3D:  # Não destrói ao colidir com CharacterBody (nave)
		queue_free()


func _on_area_entered(area: Area3D) -> void:
	## Colisão com outra área (ex: área de dano, escudo).
	if area.has_method("take_damage"):
		area.take_damage(damage)
		queue_free()