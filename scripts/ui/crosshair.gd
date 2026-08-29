class_name Crosshair
extends Control

## Retículo de mira.
##
## Desktop: segue o mouse. O tiro converge para o ponto 3D sob a mira.
## Mobile: fixo no centro da tela. O jogador posiciona a nave para
##         mirar (tiro reto pra frente, estilo rail shooter clássico).
##
## Cor: verde = normal, laranja = alvo travado.

@export var color_normal := Color(0.0, 1.0, 0.3, 0.75)
@export var color_locked := Color(1.0, 0.3, 0.1, 0.85)
@export var arm_length := 16.0
@export var arm_thickness := 2.0
@export var gap := 8.0

var _target_color := Color(0.0, 1.0, 0.3, 0.75)
var _current_color := Color(0.0, 1.0, 0.3, 0.75)
var _camera: Camera3D = null
var _is_mobile: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(func():
		position = Vector2.ZERO
		size = get_viewport().get_visible_rect().size
	)


func set_camera(cam: Camera3D) -> void:
	_camera = cam


## No mobile a mira fica fixa no centro da tela (modo rail shooter clássico).
func set_mobile_mode(mobile: bool) -> void:
	_is_mobile = mobile


func _process(delta: float) -> void:
	if _is_mobile:
		return  # Mobile: sem crosshair — a nave é a referência
	_current_color = _current_color.lerp(_target_color, 12.0 * delta)
	queue_redraw()
	_update_enemy_detection()


## Retorna o ponto 2D onde a mira está posicionada.
## Desktop: posição do mouse. Mobile: centro fixo da tela.
func get_aim_screen_pos() -> Vector2:
	if _is_mobile:
		return get_viewport().get_visible_rect().size / 2.0
	return get_viewport().get_mouse_position()


func _update_enemy_detection() -> void:
	if not _camera or not is_inside_tree():
		_target_color = color_normal
		return

	var aim_pos := get_aim_screen_pos()
	var vp := get_viewport()
	if not vp:
		return
	var world_3d: World3D = vp.world_3d
	if not world_3d:
		return
	var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	if not space_state:
		return

	var origin: Vector3 = _camera.project_ray_origin(aim_pos)
	var ray_end: Vector3 = origin + _camera.project_ray_normal(aim_pos) * 2000.0

	var query := PhysicsRayQueryParameters3D.create(origin, ray_end)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var result: Dictionary = space_state.intersect_ray(query)
	_target_color = color_locked if not result.is_empty() else color_normal


func _draw() -> void:
	var center := get_aim_screen_pos()
	var c := _current_color
	var t := arm_thickness
	var ht := t / 2.0

	# Top
	draw_rect(Rect2(center.x - ht, center.y - gap - arm_length, t, arm_length), c)
	# Bottom
	draw_rect(Rect2(center.x - ht, center.y + gap, t, arm_length), c)
	# Left
	draw_rect(Rect2(center.x - gap - arm_length, center.y - ht, arm_length, t), c)
	# Right
	draw_rect(Rect2(center.x + gap, center.y - ht, arm_length, t), c)
	# Center dot
	draw_circle(center, 2.0, c)
	# Outer ring
	draw_arc(center, 7.0, 0.0, TAU, 32, c, 1.0, true)
