@tool
extends EditorPlugin

## Pterodon Mobile Launcher (plugin de editor)
##
## Adiciona o botão "Build + Rodar no Celular" na toolbar principal do editor,
## ao lado das opções de Play.
##
## O botão faz o ciclo completo de teste no aparelho: exporta o projeto
## (export-debug Android), instala o APK no celular via ADB e abre o jogo —
## ou seja, o código que você acabou de editar vai para o celular.
##
## Ctrl+clique no botão: apenas abre no celular o jogo já instalado (sem build).

const BUTTON_SCRIPT := preload("res://addons/pterodon_mobile_launcher/mobile_launcher_button.gd")

var _button: Button


func _enter_tree() -> void:
	_button = BUTTON_SCRIPT.new()
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, _button)


func _exit_tree() -> void:
	if is_instance_valid(_button):
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, _button)
		_button.queue_free()
	_button = null