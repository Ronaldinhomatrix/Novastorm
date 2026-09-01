@tool
class_name SketchfabHttpImage
extends TextureRect

var _current_url: String = ""
var _http_request: HTTPRequest = null


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED


func load_url(image_url: String) -> void:
	if image_url == _current_url and texture != null:
		return

	_current_url = image_url
	texture = null

	if image_url.is_empty():
		return

	if not _http_request:
		_http_request = HTTPRequest.new()
		add_child(_http_request)
		_http_request.request_completed.connect(_on_request_completed)

	_http_request.cancel_request()
	_http_request.request(image_url)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or body.is_empty():
		return

	var img := Image.new()
	var err := img.load_jpg_from_buffer(body)
	if err != OK:
		err = img.load_png_from_buffer(body)
	if err != OK:
		err = img.load_webp_from_buffer(body)

	if err == OK:
		texture = ImageTexture.create_from_image(img)
