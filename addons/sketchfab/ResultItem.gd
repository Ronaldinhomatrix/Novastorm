@tool
class_name SketchfabResultItem
extends PanelContainer

signal model_clicked(model_data: Dictionary)

@onready var thumbnail: SketchfabHttpImage = $Margin/VBox/Thumbnail
@onready var title_label: Label = $Margin/VBox/Title
@onready var author_label: Label = $Margin/VBox/Author
@onready var stats_label: Label = $Margin/VBox/Stats

var _model_data: Dictionary = {}


func set_model_data(data: Dictionary) -> void:
	_model_data = data
	if not is_inside_tree():
		return
	_update_ui()


func _ready() -> void:
	_update_ui()


func _update_ui() -> void:
	if _model_data.is_empty():
		return

	if title_label:
		title_label.text = str(_model_data.get("name", "Untitled Model"))
	if author_label:
		var user: Dictionary = _model_data.get("user", {})
		author_label.text = "by " + str(user.get("displayName", user.get("username", "Unknown")))

	if stats_label:
		var face_count: int = int(_model_data.get("faceCount", 0))
		var vertex_count: int = int(_model_data.get("vertexCount", 0))
		var animated: bool = bool(_model_data.get("animationCount", 0) > 0)
		var stats_text := "▲ %dk faces" % [int(face_count / 1000.0)] if face_count >= 1000 else "▲ %d faces" % face_count
		if animated:
			stats_text += " • 🎬 Animated"
		stats_label.text = stats_text

	if thumbnail:
		var thumbs: Dictionary = _model_data.get("thumbnails", {})
		var images: Array = thumbs.get("images", [])
		var best_url := ""
		for img: Dictionary in images:
			var w: int = int(img.get("width", 0))
			if w >= 200 and w <= 600:
				best_url = str(img.get("url", ""))
				break
		if best_url.is_empty() and images.size() > 0:
			best_url = str(images[0].get("url", ""))

		thumbnail.load_url(best_url)


func _on_button_pressed() -> void:
	model_clicked.emit(_model_data)
