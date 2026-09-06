extends Node3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var btn := get_node_or_null("UI/VBoxContainer/RestartBtn") as Button
	if btn and not btn.pressed.is_connected(_on_restart_pressed):
		btn.pressed.connect(_on_restart_pressed)

func _on_restart_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/stages/level_1.tscn")
