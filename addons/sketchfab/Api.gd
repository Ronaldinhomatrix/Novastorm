@tool
class_name SketchfabApi
extends RefCounted

const API_BASE := "https://api.sketchfab.com/v3"
const TOKEN_FILE := "user://sketchfab_token.cfg"

static func get_token() -> String:
	if Engine.has_meta("__sketchfab_token"):
		return str(Engine.get_meta("__sketchfab_token"))
	var cfg := ConfigFile.new()
	if cfg.load(TOKEN_FILE) == OK:
		var token := str(cfg.get_value("auth", "token", ""))
		if not token.is_empty():
			Engine.set_meta("__sketchfab_token", token)
			return token
	return ""


static func set_token(token: String) -> void:
	Engine.set_meta("__sketchfab_token", token)
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "token", token)
	cfg.save(TOKEN_FILE)


static func make_request(url: String, caller: Node, custom_headers: PackedStringArray = PackedStringArray(), method: HTTPClient.Method = HTTPClient.METHOD_GET, request_data: String = "") -> Dictionary:
	if not caller:
		return {"error": "No caller node"}

	var http := HTTPRequest.new()
	caller.add_child(http)

	var headers := custom_headers.duplicate()
	var token := get_token()
	if not token.is_empty():
		var has_auth := false
		for h in headers:
			if h.to_lower().begins_with("authorization:"):
				has_auth = true
				break
		if not has_auth:
			headers.append("Authorization: Token %s" % token)

	var err := http.request(url, headers, method, request_data)
	if err != OK:
		http.queue_free()
		return {"error": "HTTP request failed to start: %d" % err}

	var response_data: Array = await http.request_completed
	http.queue_free()

	var result_code: int = response_data[0]
	var status_code: int = response_data[1]
	var body: PackedByteArray = response_data[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"error": "HTTP request failed with result: %d" % result_code, "status": status_code}

	var body_text := body.get_string_from_utf8()
	var json_parsed := JSON.parse_string(body_text)
	if json_parsed is Dictionary:
		json_parsed["_status_code"] = status_code
		return json_parsed
	elif json_parsed is Array:
		return {"results": json_parsed, "_status_code": status_code}
	else:
		return {"error": "Invalid JSON response", "raw": body_text, "_status_code": status_code}


static func search_models(caller: Node, query: String = "", category: String = "", animated: bool = false, staff_picked: bool = false, sort_by: String = "-publishedAt", next_url: String = "") -> Dictionary:
	var url := next_url
	if url.is_empty():
		var params: Array[String] = ["type=models", "downloadable=true"]
		if not query.is_empty():
			params.append("q=" + query.uri_encode())
		if not category.is_empty():
			params.append("categories=" + category.uri_encode())
		if animated:
			params.append("animated=true")
		if staff_picked:
			params.append("staffpicked=true")
		if not sort_by.is_empty():
			params.append("sort_by=" + sort_by.uri_encode())
		url = "%s/models?%s" % [API_BASE, "&".join(params)]

	return await make_request(url, caller)


static func get_categories(caller: Node) -> Array:
	var res := await make_request("%s/categories" % API_BASE, caller)
	if res.has("results") and res["results"] is Array:
		return res["results"]
	return []


static func get_model_details(caller: Node, uid: String) -> Dictionary:
	return await make_request("%s/models/%s" % [API_BASE, uid], caller)


static func request_download(caller: Node, uid: String) -> Dictionary:
	return await make_request("%s/models/%s/download" % [API_BASE, uid], caller)


static func download_file(caller: Node, url: String, target_zip_path: String) -> bool:
	if not caller:
		return false

	var http := HTTPRequest.new()
	http.download_file = ProjectSettings.globalize_path(target_zip_path)
	caller.add_child(http)

	var err := http.request(url)
	if err != OK:
		http.queue_free()
		return false

	var res: Array = await http.request_completed
	http.queue_free()

	var result_code: int = res[0]
	var status_code: int = res[1]
	return result_code == HTTPRequest.RESULT_SUCCESS and status_code == 200


static func unzip_file(zip_res_path: String, destination_dir_res: String) -> bool:
	var global_zip := ProjectSettings.globalize_path(zip_res_path)
	var global_dest := ProjectSettings.globalize_path(destination_dir_res)

	var reader := ZIPReader.new()
	var err := reader.open(global_zip)
	if err != OK:
		printerr("Sketchfab: Falha ao abrir ZIP: ", global_zip, " (erro ", err, ")")
		return false

	DirAccess.make_dir_recursive_absolute(global_dest)
	var files := reader.get_files()
	for f in files:
		if f.ends_with("/") or f.ends_with("\\"):
			DirAccess.make_dir_recursive_absolute(global_dest.path_join(f))
			continue
		var data := reader.read_file(f)
		var out_file_path := global_dest.path_join(f)
		var parent_dir := out_file_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(parent_dir)
		var fa := FileAccess.open(out_file_path, FileAccess.WRITE)
		if fa:
			fa.store_buffer(data)
			fa.close()

	reader.close()
	return true
