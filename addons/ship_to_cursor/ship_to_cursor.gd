@tool
extends EditorPlugin

## Atalhos:
##   Ctrl+Shift+1  → Move a nave (Player) para a posição exata da câmera do editor 3D.
##   Ctrl+Shift+2  → Move a POSIÇÃO da luz (DirectionalLight3D) para a posição exata da
##                   câmera do editor e orienta a luz para a direção de vôo (sombra
##                   "originando" daquele ponto). Útil para controlar a sombra da nave.

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1 and event.ctrl_pressed and event.shift_pressed:
			_move_ship_to_camera()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_2 and event.ctrl_pressed and event.shift_pressed:
			_move_light_to_camera()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Ctrl+Shift+1 — move a NAVe para a posição da câmera
# ---------------------------------------------------------------------------

func _move_ship_to_camera() -> void:
	var scene := EditorInterface.get_edited_scene_root()
	if scene == null:
		print("ShipToCursor: nenhuma cena editada.")
		return
	var cam := _get_editor_camera()
	if cam == null:
		return

	var ship := _find_ship(scene)
	if ship == null:
		print("ShipToCursor: nó 'Player' não encontrado na cena.")
		return

	# Move a curva inteira (Path3D) por um delta, levando a nave junto de forma
	# persistente (o PathFollow3D não recoloca a nave quando movemos o Path3D).
	var delta := cam.global_position - ship.global_position
	var path := _find_path(ship)
	if path == null:
		print("ShipToCursor: Path3D ancestral não encontrado; movendo só a nave.")
		ship.global_position = cam.global_position
		return
	path.global_position += delta
	print("ShipToCursor: nave movida para ", cam.global_position)


# ---------------------------------------------------------------------------
# Ctrl+Shift+2 — move a POSIÇÃO da luz (sol/origem da sombra) para a câmera
# ---------------------------------------------------------------------------

func _move_light_to_camera() -> void:
	var scene := EditorInterface.get_edited_scene_root()
	if scene == null:
		print("ShipToCursor: nenhuma cena editada.")
		return
	var cam := _get_editor_camera()
	if cam == null:
		return

	var light := _find_light(scene)
	if light == null:
		print("ShipToCursor: nó 'DirectionalLight3D' não encontrado na cena.")
		return

	# Posiciona a luz na posição exata da câmera do editor.
	light.global_position = cam.global_position

	# Como é uma luz direcional, a posição é "infinitamente distante" e o que
	# define a direção da sombra é a ORIENTAÇÃO. Para a sombra "originar" do
	# ponto da câmera, apontamos a luz para a direção do vôo (eixo +Z global,
	# por onde a nave avança) com 45° de elevação, vindo de trás.
	light.global_rotation = Vector3(0.78539816, 3.14159265, 0.0)  # X=45°, Y=180°
	print("ShipToCursor: luz posicionada em ", cam.global_position)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_editor_camera() -> Camera3D:
	var vp := EditorInterface.get_editor_viewport_3d()
	if vp == null:
		print("ShipToCursor: viewport 3D indisponível.")
		return null
	var cam := vp.get_camera_3d()
	if cam == null:
		print("ShipToCursor: câmera 3D indisponível.")
		return null
	return cam


func _find_ship(root: Node) -> Node3D:
	var player := root.find_child("Player", true, false)
	if player is Node3D:
		return player
	return null


func _find_path(ship: Node) -> Node3D:
	var current := ship.get_parent()
	while current != null:
		if current is Path3D:
			return current
		current = current.get_parent()
	return null


func _find_light(root: Node) -> DirectionalLight3D:
	var found := root.find_children("*", "DirectionalLight3D", true, false)
	if found.is_empty():
		return null
	return found[0] as DirectionalLight3D