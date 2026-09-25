class_name LevelComplete
extends CanvasLayer

## Tela de "LEVEL COMPLETE" exibida quando o jogador termina um nível.
## Aguarda clique do jogador e emite sinal para transição de nível.

signal level_completed

# ---------------------------------------------------------------------------
# Exportações
# ---------------------------------------------------------------------------

@export var next_level_path: String = "res://scenes/stages/level_2.tscn"

# ---------------------------------------------------------------------------
# Estado Interno
# ---------------------------------------------------------------------------

var _can_click: bool = false

# ---------------------------------------------------------------------------
# Ciclo de Vida
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Pequeno delay antes de permitir clique (evita clique acidental)
	await get_tree().create_timer(0.5).timeout
	_can_click = true


func _input(event: InputEvent) -> void:
	if not _can_click:
		return
	
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_on_click()
	
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			_on_click()

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_SPACE):
			_on_click()


func _on_click() -> void:
	_can_click = false
	level_completed.emit()
	
	# Transição para próximo nível
	get_tree().change_scene_to_file(next_level_path)