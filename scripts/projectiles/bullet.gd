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
var _shape_cast: ShapeCast3D = null

# --- Visuais (juice) — não afetam a mecânica de colisão/dano ---
var _light: OmniLight3D = null
var _light_base_energy: float = 6.5
var _visual_root: Node3D = null
var _age: float = 0.0
var _flicker_seed: float = 0.0
const SPAWN_PULSE_DURATION: float = 0.07

# Shape estático compartilhado para ShapeCast (evita BoxShape3D.new() a cada tiro)
static var _shared_shape: BoxShape3D = null

func _ready() -> void:
	collision_layer = 2
	collision_mask = 2
	monitoring = true
	monitorable = true

	add_to_group("player_bullets")

	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	_prev_position = global_position

	# ShapeCast3D para detecção volumétrica contínua (CCD 3D) cobrindo
	# o feixe inteiro do laser (3.8m), evitando tunelamento e falso-negativos em alta velocidade.
	_shape_cast = get_node_or_null("BulletShapeCast") as ShapeCast3D
	if not _shape_cast:
		var col_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
		_shape_cast = ShapeCast3D.new()
		_shape_cast.name = "BulletShapeCast"
		if col_shape and col_shape.shape:
			_shape_cast.shape = col_shape.shape
		else:
			if not _shared_shape:
				_shared_shape = BoxShape3D.new()
				_shared_shape.size = Vector3(3.8, 3.8, 18.0)
			_shape_cast.shape = _shared_shape
		_shape_cast.collision_mask = 2 | WORLD_LAYER_MASK
		_shape_cast.collide_with_areas = true
		_shape_cast.collide_with_bodies = true
		_shape_cast.enabled = false
		_shape_cast.add_exception(self)
		_shape_cast.add_exception_rid(self.get_rid())
		add_child(_shape_cast)

	_setup_visuals()


func _setup_visuals() -> void:
	## Cacheia referências visuais e prepara o pulso de "nascimento" do tiro.
	_light = get_node_or_null("OmniLight3D") as OmniLight3D
	if not _light:
		_light = get_node_or_null("VisualRoot/OmniLight3D") as OmniLight3D
	if _light:
		if GameConfig.is_mobile:
			_light.visible = false
			_light.queue_free()
			_light = null
		else:
			_light_base_energy = _light.light_energy
	_flicker_seed = randf() * 100.0

	_visual_root = get_node_or_null("VisualRoot") as Node3D
	if not _visual_root:
		_visual_root = Node3D.new()
		_visual_root.name = "VisualRoot"
		var meshes: Array[Node] = []
		for child in get_children():
			if child is MeshInstance3D or child is CPUParticles3D or child is OmniLight3D:
				meshes.append(child)
		for child in meshes:
			remove_child(child)
			_visual_root.add_child(child)
		add_child(_visual_root)

	# Nasce levemente "esticado" e brilhante, assentando no tamanho real.
	_visual_root.scale = Vector3(1.35, 1.35, 1.15)
	if _light:
		_light.light_energy = _light_base_energy * 2.2


func _process(delta: float) -> void:
	_age += delta

	# Pulso de nascimento: escala e luz decaem rapidamente ao valor base.
	if _age < SPAWN_PULSE_DURATION and _visual_root:
		var t := _age / SPAWN_PULSE_DURATION
		var s := lerpf(1.35, 1.0, t * t)
		_visual_root.scale = Vector3(s, s, lerpf(1.15, 1.0, t))
		if _light:
			_light.light_energy = lerpf(_light_base_energy * 2.2, _light_base_energy, t)

	# Flicker orgânico da luz (plasma instável), barato e sem ruído externo.
	if _light and _age >= SPAWN_PULSE_DURATION:
		var f := sin(_age * 53.0 + _flicker_seed) * 0.5 + sin(_age * 91.0 + _flicker_seed * 2.0) * 0.5
		_light.light_energy = _light_base_energy * (0.88 + 0.18 * f)


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
	if not _shape_cast:
		return false

	# Varredura volumétrica 3D contínua no trajeto percorrido no frame (CCD)
	# Garante que qualquer parte do feixe do laser (3.8m) colidindo registre dano
	_shape_cast.global_position = from_pos
	_shape_cast.target_position = _shape_cast.to_local(to_pos)
	_shape_cast.force_shapecast_update()

	if not _shape_cast.is_colliding():
		return false

	var hit_world: bool = false
	var world_point: Vector3 = Vector3.ZERO
	var world_normal: Vector3 = Vector3.UP

	var count := _shape_cast.get_collision_count()
	for i in range(count):
		var collider: Object = _shape_cast.get_collider(i)
		if not collider or collider == self:
			continue

		# Ignora projéteis amigos, jogador e áreas aliadas para evitar auto-destruição em voo
		if collider is Node:
			var node_col := collider as Node
			if node_col.is_in_group("player_bullets") or node_col.is_in_group("player"):
				continue
			var parent := node_col.get_parent()
			if parent and (parent.is_in_group("player_bullets") or parent.is_in_group("player")):
				continue

		# 1. Alvos com método take_damage (inimigos, partes de chefe, etc.)
		if collider.has_method("take_damage"):
			collider.take_damage(damage)
			queue_free()
			return true
		elif collider.get_parent() and collider.get_parent().has_method("take_damage"):
			collider.get_parent().take_damage(damage)
			queue_free()
			return true

		# 2. Cenário / Terreno (World Layer 4)
		if not collider is CharacterBody3D and collider is Node3D:
			hit_world = true
			world_point = _shape_cast.get_collision_point(i)
			world_normal = _shape_cast.get_collision_normal(i)

	if hit_world:
		_spawn_explosion(world_point, world_normal)
		queue_free()
		return true

	return false


func _spawn_explosion(point: Vector3, normal: Vector3) -> void:
	## Cria uma pequena faísca/puff no ponto de impacto na rocha (sem tocar som de explosão de nave)
	var scene := get_tree().current_scene if get_tree() else null
	if not scene and get_tree():
		scene = get_tree().root
	if not scene:
		return
	var explosion: Node3D = ExplosionScript.new()
	scene.add_child(explosion)
	explosion.global_position = point + normal * 0.5
	if explosion.has_method("set"):
		explosion.set("size_scale", 0.25)


# ---------------------------------------------------------------------------
# Colisões de Fallback (Sinais nativos de Area3D)
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if is_queued_for_deletion():
		return
	if body == self or body.is_in_group("player") or body.is_in_group("player_bullets"):
		return
	var parent := body.get_parent()
	if parent and (parent.is_in_group("player") or parent.is_in_group("player_bullets")):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
	elif not body is CharacterBody3D:
		queue_free()


func _on_area_entered(area: Area3D) -> void:
	if is_queued_for_deletion():
		return
	if area == self or area.is_in_group("player") or area.is_in_group("player_bullets"):
		return
	var parent := area.get_parent()
	if parent and (parent.is_in_group("player") or parent.is_in_group("player_bullets")):
		return
	if area.has_method("take_damage"):
		area.take_damage(damage)
		queue_free()
