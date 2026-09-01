@tool
class_name SketchfabModelDialog
extends Window

signal import_completed(imported_path: String)

@onready var thumbnail: SketchfabHttpImage = $Margin/VBox/HBox/Left/Thumbnail
@onready var title_label: Label = $Margin/VBox/HBox/Right/Title
@onready var author_label: Label = $Margin/VBox/HBox/Right/Author
@onready var stats_label: Label = $Margin/VBox/HBox/Right/Stats
@onready var license_label: Label = $Margin/VBox/HBox/Right/License
@onready var download_button: Button = $Margin/VBox/BottomHBox/DownloadBtn
@onready var view_site_button: Button = $Margin/VBox/BottomHBox/ViewSiteBtn
@onready var status_label: Label = $Margin/VBox/BottomHBox/StatusLabel
@onready var progress_bar: ProgressBar = $Margin/VBox/ProgressBar

var _model_data: Dictionary = {}
var _view_url: String = ""


func _ready() -> void:
	close_requested.connect(queue_free)
	if progress_bar:
		progress_bar.visible = false


func show_model(data: Dictionary) -> void:
	_model_data = data
	popup_centered(Vector2i(750, 480))
	_update_ui()


func _update_ui() -> void:
	if _model_data.is_empty():
		return

	var name_str := str(_model_data.get("name", "Model Details"))
	title = name_str
	if title_label:
		title_label.text = name_str

	var user: Dictionary = _model_data.get("user", {})
	if author_label:
		author_label.text = "Author: " + str(user.get("displayName", user.get("username", "Unknown")))

	_view_url = str(_model_data.get("viewerUrl", ""))

	if stats_label:
		var face_count: int = int(_model_data.get("faceCount", 0))
		var vertex_count: int = int(_model_data.get("vertexCount", 0))
		var animated: bool = bool(_model_data.get("animationCount", 0) > 0)
		stats_label.text = "Geometry: %d faces, %d vertices\nAnimation: %s" % [
			face_count,
			vertex_count,
			"Yes" if animated else "No"
		]

	if license_label:
		var lic: Dictionary = _model_data.get("license", {})
		license_label.text = "License: %s\n(%s)" % [
			str(lic.get("fullName", "Standard")),
			str(lic.get("requirements", "Attribution required"))
		]

	if thumbnail:
		var thumbs: Dictionary = _model_data.get("thumbnails", {})
		var images: Array = thumbs.get("images", [])
		var best_url := ""
		for img: Dictionary in images:
			var w: int = int(img.get("width", 0))
			if w >= 400 and w <= 800:
				best_url = str(img.get("url", ""))
				break
		if best_url.is_empty() and images.size() > 0:
			best_url = str(images[images.size() - 1].get("url", ""))

		thumbnail.load_url(best_url)


func _on_download_pressed() -> void:
	var uid := str(_model_data.get("uid", ""))
	if uid.is_empty():
		return

	var token := SketchfabApi.get_token()
	if token.is_empty():
		status_label.text = "⚠ Por favor, configure seu Sketchfab API Token primeiro!"
		return

	download_button.disabled = true
	status_label.text = "Solicitando link de download ao Sketchfab..."
	progress_bar.visible = true
	progress_bar.value = 20.0

	var download_info := await SketchfabApi.request_download(self, uid)
	if download_info.has("error") or not download_info.has("gltf"):
		status_label.text = "Erro ao solicitar download. Verifique se o Token é válido."
		download_button.disabled = false
		progress_bar.visible = false
		return

	var gltf_info: Dictionary = download_info.get("gltf", {})
	var zip_url := str(gltf_info.get("url", ""))
	if zip_url.is_empty():
		status_label.text = "Modelo não possui formato glTF disponível."
		download_button.disabled = false
		progress_bar.visible = false
		return

	status_label.text = "Baixando arquivo glTF..."
	progress_bar.value = 50.0

	var safe_name := _model_data.get("name", "model").to_lower()
	var regex := RegEx.new()
	regex.compile("[^a-zA-Z0-9_]")
	safe_name = regex.sub(safe_name, "_", true)
	if safe_name.is_empty():
		safe_name = "sketchfab_model_" + uid

	var dest_dir := "res://sketchfab/%s/" % safe_name
	var temp_zip := "res://sketchfab/temp_%s.zip" % uid
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://sketchfab/"))

	var success := await SketchfabApi.download_file(self, zip_url, temp_zip)
	if not success:
		status_label.text = "Falha no download da internet."
		download_button.disabled = false
		progress_bar.visible = false
		return

	status_label.text = "Extraindo modelo no projeto..."
	progress_bar.value = 85.0

	var unzipped := SketchfabApi.unzip_file(temp_zip, dest_dir)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_zip))

	if unzipped:
		progress_bar.value = 100.0
		status_label.text = "✔ Modelo importado com sucesso em: " + dest_dir
		EditorInterface.get_resource_filesystem().scan()
		import_completed.emit(dest_dir)
		download_button.text = "Importado com Sucesso!"
	else:
		status_label.text = "Falha ao extrair arquivo ZIP."
		download_button.disabled = false
		progress_bar.visible = false


func _on_view_site_pressed() -> void:
	if not _view_url.is_empty():
		OS.shell_open(_view_url)
