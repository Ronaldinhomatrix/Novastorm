# Ferramenta de apoio: gera a versão mobile (512x512) do normal map do terreno.
# Executar no editor via File > Run.
extends EditorScript


func _run() -> void:
	var img := Image.new()
	var err := img.load("res://assets/models/levels/mountains_1/textures/Material_25_normal.png")
	if err != OK:
		printerr("Falha ao carregar normal map: " + str(err))
		return

	var new_size := 512
	img.resize(new_size, new_size, Image.INTERPOLATE_BILINEAR)

	var save_path := "res://assets/models/levels/mountains_1/textures/Material_25_normal_mobile.png"
	var save_err := img.save_png(save_path)
	if save_err != OK:
		printerr("Falha ao salvar: " + str(save_err))
		return

	print("Normal map mobile salvo em: " + save_path)