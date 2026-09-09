class_name UserSettingsClass
extends Node

## Configurações gráficas do usuário, persistidas em user://settings.cfg.
## Autoload "UserSettings" — acessível globalmente como UserSettings.get_shadows() etc.
##
## O MESMO menu de opções aparece em todas as plataformas (PC e Mobile).
## Quando o jogador ainda não escolheu (override ausente), usa o default
## da plataforma definido no GameConfig.

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"

const KEY_SHADOWS := "shadows"
const KEY_GLOW := "glow"
const KEY_SSAO := "ssao"
const KEY_SSIL := "ssil"

var _cfg := ConfigFile.new()
var _overrides: Dictionary = {}


func _ready() -> void:
	_load()


func _load() -> void:
	_overrides.clear()
	if _cfg.load(SETTINGS_PATH) != OK:
		return
	for key in [KEY_SHADOWS, KEY_GLOW, KEY_SSAO, KEY_SSIL]:
		if _cfg.has_section_key("graphics", key):
			_overrides[key] = bool(_cfg.get_value("graphics", key))


func _get_bool(key: String, default: bool) -> bool:
	return bool(_overrides[key]) if _overrides.has(key) else default


func _set_bool(key: String, value: bool) -> void:
	_overrides[key] = value
	_cfg.set_value("graphics", key, value)
	_cfg.save(SETTINGS_PATH)
	settings_changed.emit()


func _default(pc_val: bool, mobile_val: bool) -> bool:
	return mobile_val if GameConfig.is_mobile else pc_val


# ---------------------------------------------------------------------------
# Leituras (valor efetivo: override do usuário OU default da plataforma)
# ---------------------------------------------------------------------------

func get_shadows() -> bool:
	return _get_bool(KEY_SHADOWS, _default(GameConfig.SHADOWS_DEFAULT_PC, GameConfig.SHADOWS_DEFAULT_MOBILE))

func get_glow() -> bool:
	return _get_bool(KEY_GLOW, _default(GameConfig.GLOW_DEFAULT_PC, GameConfig.GLOW_DEFAULT_MOBILE))

func get_ssao() -> bool:
	return _get_bool(KEY_SSAO, _default(GameConfig.SSAO_DEFAULT_PC, GameConfig.SSAO_DEFAULT_MOBILE))

func get_ssil() -> bool:
	return _get_bool(KEY_SSIL, _default(GameConfig.SSIL_DEFAULT_PC, GameConfig.SSIL_DEFAULT_MOBILE))


# ---------------------------------------------------------------------------
# Escritas (persistem e emitem settings_changed)
# ---------------------------------------------------------------------------

func set_shadows(v: bool) -> void: _set_bool(KEY_SHADOWS, v)
func set_glow(v: bool) -> void: _set_bool(KEY_GLOW, v)
func set_ssao(v: bool) -> void: _set_bool(KEY_SSAO, v)
func set_ssil(v: bool) -> void: _set_bool(KEY_SSIL, v)


func reset_to_defaults() -> void:
	_overrides.clear()
	_cfg.clear()
	_cfg.save(SETTINGS_PATH)
	settings_changed.emit()
