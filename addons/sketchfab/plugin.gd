@tool
extends EditorPlugin

const MainScene := preload("res://addons/sketchfab/Main.tscn")
var main_instance: Control = null


func _enter_tree() -> void:
	if MainScene:
		main_instance = MainScene.instantiate() as Control
		if main_instance:
			EditorInterface.get_editor_main_screen().add_child(main_instance)
			_make_visible(false)


func _exit_tree() -> void:
	if main_instance:
		main_instance.queue_free()


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "Sketchfab"


func _get_plugin_icon() -> Texture2D:
	if FileAccess.file_exists("res://addons/sketchfab/icon.png.noimport"):
		var img := Image.new()
		var err := img.load("res://addons/sketchfab/icon.png.noimport")
		if err == OK:
			return ImageTexture.create_from_image(img)
	elif FileAccess.file_exists("res://addons/sketchfab/sketchfab.png.noimport"):
		var img := Image.new()
		var err := img.load("res://addons/sketchfab/sketchfab.png.noimport")
		if err == OK:
			return ImageTexture.create_from_image(img)
	return EditorInterface.get_editor_theme().get_icon("Spatial", "EditorIcons")


func _make_visible(visible: bool) -> void:
	if main_instance:
		main_instance.visible = visible
