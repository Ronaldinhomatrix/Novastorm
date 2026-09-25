class_name MuzzleFlashEffect
extends Node3D

## Efeito de flash / clarão da nave no momento do disparo laser:
## - Luz dinâmica omnidirecional azul/ciano neon de decaimento rápido (ilumina a própria nave e o ambiente imediato).
## - Puramente luz dinâmica (sem mesh/objeto físico na frente da nave).
## - Duração ultracurta e alta intensidade para máximo feedback.

var _light: OmniLight3D = null
var _timer: float = 0.0
const FLASH_DURATION: float = 0.09


func _ready() -> void:
	if GameConfig.is_mobile:
		set_process(false)
		return
	_setup_effect()


func _setup_effect() -> void:
	if GameConfig.is_mobile:
		return
	# Luz dinâmica de disparo
	_light = OmniLight3D.new()
	_light.light_color = Color(0.15, 0.85, 1.0)
	_light.light_energy = 0.0
	_light.omni_range = 14.0
	_light.omni_attenuation = 1.6
	_light.position = Vector3(0.0, -0.52, -15.15)
	add_child(_light)


func trigger() -> void:
	_timer = FLASH_DURATION
	if _light:
		_light.light_energy = 16.0


func _process(delta: float) -> void:
	if _timer > 0.0:
		_timer = maxf(0.0, _timer - delta)
		var t := _timer / FLASH_DURATION
		if _light:
			_light.light_energy = 16.0 * (t * t)
	else:
		if _light and _light.light_energy > 0.0:
			_light.light_energy = 0.0
