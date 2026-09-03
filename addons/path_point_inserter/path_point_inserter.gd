@tool
extends EditorPlugin

## Path Point Inserter
## Insere um ponto no Path3D selecionado exatamente na posição da câmera do
## editor 3D. Voe pelo espaço com o botão DIREITO do mouse (RMB) + WASD/QE
## e pressione F8 (ou o botão "Path+" na toolbar) para cravar um ponto.

const INSERT_KEY := Key.KEY_F8  # Atalho para inserir um ponto
const AUTO_SMOOTH := true       # Gera tangentes suaves automaticamente

var _toolbar_container: HBoxContainer
var _btn_insert_end: Button
var _btn_insert_between: Button
var _spin_from: SpinBox
var _spin_to: SpinBox


func _enter_tree() -> void:
	set_process_unhandled_key_input(true)

	_toolbar_container = HBoxContainer.new()
	_toolbar_container.name = "PathPointInserterBar"

	# Botão de inserção no Fim
	_btn_insert_end = Button.new()
	_btn_insert_end.text = "Path+ (Fim / F8)"
	_btn_insert_end.tooltip_text = "Inserir ponto no final do Path3D (F8)"
	_btn_insert_end.pressed.connect(func(): _insert_point(-1))
	_toolbar_container.add_child(_btn_insert_end)

	var sep := VSeparator.new()
	_toolbar_container.add_child(sep)

	# Label 'Entre:'
	var lbl := Label.new()
	lbl.text = " Entre #"
	_toolbar_container.add_child(lbl)

	# Ponto A
	_spin_from = SpinBox.new()
	_spin_from.min_value = 0
	_spin_from.max_value = 500
	_spin_from.value = 13
	_spin_from.tooltip_text = "Ponto inicial do intervalo (ex: 13)"
	_spin_from.custom_minimum_size = Vector2(65, 0)
	_spin_from.value_changed.connect(_on_spin_from_changed)
	_toolbar_container.add_child(_spin_from)

	# Label 'e #'
	var lbl2 := Label.new()
	lbl2.text = " e #"
	_toolbar_container.add_child(lbl2)

	# Ponto B
	_spin_to = SpinBox.new()
	_spin_to.min_value = 1
	_spin_to.max_value = 500
	_spin_to.value = 14
	_spin_to.tooltip_text = "Ponto final do intervalo (ex: 14)"
	_spin_to.custom_minimum_size = Vector2(65, 0)
	_toolbar_container.add_child(_spin_to)

	# Botão de inserção Intermediária
	_btn_insert_between = Button.new()
	_btn_insert_between.text = "📍 Inserir Intermediário (Shift+F8)"
	_btn_insert_between.tooltip_text = "Insere o novo ponto exatamente entre os pontos definidos nas caixas numéricas (Shift+F8)"
	_btn_insert_between.pressed.connect(func(): _insert_point_between_selected())
	_toolbar_container.add_child(_btn_insert_between)

	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _toolbar_container)


func _exit_tree() -> void:
	if _toolbar_container:
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _toolbar_container)
		_toolbar_container.queue_free()
		_toolbar_container = null


func _on_spin_from_changed(val: float) -> void:
	if _spin_to:
		_spin_to.min_value = int(val) + 1
		if _spin_to.value <= val:
			_spin_to.value = val + 1


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == INSERT_KEY:
		if event.shift_pressed:
			_insert_point_between_selected()
		else:
			_insert_point(-1)
		get_viewport().set_input_as_handled()


func _insert_point_between_selected() -> void:
	var from_idx := int(_spin_from.value) if _spin_from else 13
	# Inserir no índice (from_idx + 1) coloca o novo ponto exatamente após o ponto 'from'
	# Ex: entre 13 e 14 -> insere no índice 14, empurrando o antigo 14 para 15
	var target_index := from_idx + 1
	_insert_point(target_index)


func _insert_point(target_index: int = -1) -> void:
	var editor := get_editor_interface()

	var path := _find_selected_path3d(editor)
	if not path:
		_toast(editor, "Selecione o nó FlightPath (Path3D) na árvore antes de inserir o ponto.")
		return

	var vp := editor.get_editor_viewport_3d()
	if not vp:
		_toast(editor, "Não foi possível acessar o viewport 3D do editor.")
		return
	var cam := vp.get_camera_3d()
	if not cam:
		_toast(editor, "Não foi possível acessar a câmera do editor 3D.")
		return

	# Posição da câmera convertida para o espaço local do Path3D.
	var local_pos: Vector3 = path.to_local(cam.global_position)

	# SALVAGUARDA: Nunca insere pontos na origem (0,0,0)
	if local_pos.length_squared() < 0.01:
		_toast(editor, "ERRO: Posição inválida (origem). Verifique o Path3D e a câmera.")
		return

	var curve: Curve3D = path.curve
	if not curve:
		curve = Curve3D.new()
		path.curve = curve

	var final_index := target_index
	if target_index >= 0 and target_index <= curve.point_count:
		curve.add_point(local_pos, Vector3.ZERO, Vector3.ZERO, target_index)
		final_index = target_index
	else:
		curve.add_point(local_pos, Vector3.ZERO, Vector3.ZERO)
		final_index = curve.point_count - 1

	if AUTO_SMOOTH:
		_smooth_nearby_tangents(curve, final_index)

	# Atualiza o SpinBox 'Entre' para o próximo índice sugerido caso vá adicionar vários em sequência
	if _spin_from and _spin_to and target_index >= 0:
		_spin_from.value = final_index
		_spin_to.value = final_index + 1

	# Persiste a curva no disco
	_save_curve(curve)

	editor.mark_scene_as_unsaved()
	_toast(editor, "Ponto inserido com sucesso na posição #%d! (Total: %d pontos)".format([final_index, curve.point_count]))




# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_selected_path3d(editor: EditorInterface) -> Path3D:
	var sel := editor.get_selection()
	if not sel:
		return null
	for node in sel.get_selected_nodes():
		if node is Path3D:
			return node
	return null


func _smooth_nearby_tangents(curve: Curve3D, index: int) -> void:
	var n := curve.point_count
	if n < 2:
		return
	var lo := maxi(index - 1, 0)
	var hi := mini(index + 1, n - 1)
	for i in range(lo, hi + 1):
		var prev: Vector3 = curve.get_point_position(maxi(i - 1, 0))
		var next: Vector3 = curve.get_point_position(mini(i + 1, n - 1))
		var tangent := (next - prev) * (1.0 / 6.0)
		# Evita tangentes de comprimento zero (causa "Zero length interval")
		if tangent.length_squared() < 0.0001:
			continue
		# in/out são offsets relativos ao ponto (API Godot 4.x).
		curve.set_point_in(i, -tangent)
		curve.set_point_out(i, tangent)


func _save_curve(curve: Curve3D) -> void:
	# Salva no .tres APENAS para curvas externas reais (arquivo .tres/.res).
	# Curvas embutidas (SubResource no .tscn) têm resource_path vazio ou um
	# pseudo-caminho ("...tscn::Curve3D_xxx") que não deve ser salvo isolado.
	var rpath := curve.resource_path
	if rpath != "" and (rpath.ends_with(".tres") or rpath.ends_with(".res")):
		ResourceSaver.save(curve, rpath)


func _toast(editor: EditorInterface, message: String) -> void:
	var toaster := editor.get_editor_toaster()
	if toaster:
		toaster.push_toast(message)
	else:
		print("[Path Inserter] ", message)
