class_name CombatHUD
extends CanvasLayer

## HUD de combate em tempo real para Novastorm.
## Gerencia a exibição dual:
##   - Barra e pips de SHIELD (3 cargas, esgota com aviso de Shields Offline)
##   - Barra e pips de HULL (3 pontos de casco, ativa fumaça/fogo e morte)
##   - Vinheta de dano e alerta cinematográfico de texto flutuante.

@export_category("Cores do HUD")
@export var color_shield_active: Color = Color(0.0, 0.85, 1.0, 1.0)     # Ciano
@export var color_shield_offline: Color = Color(0.9, 0.25, 0.2, 0.8)    # Vermelho/Cinza Offline
@export var color_hull_good: Color = Color(0.1, 0.9, 0.45, 1.0)         # Verde intacto (3/3)
@export var color_hull_warning: Color = Color(1.0, 0.75, 0.1, 1.0)      # Âmbar danificado (2/3)
@export var color_hull_critical: Color = Color(1.0, 0.2, 0.2, 1.0)      # Vermelho crítico (1/3)

# Referências de nós na cena
@onready var shield_bar: ProgressBar = $SafeArea/BottomLeft/StatusContainer/ShieldContainer/ShieldBar
@onready var shield_value_label: Label = $SafeArea/BottomLeft/StatusContainer/ShieldContainer/HeaderHBox/ShieldValue
@onready var shield_pips: HBoxContainer = $SafeArea/BottomLeft/StatusContainer/ShieldContainer/ShieldPips

@onready var hull_bar: ProgressBar = $SafeArea/BottomLeft/StatusContainer/HullContainer/HullBar
@onready var hull_value_label: Label = $SafeArea/BottomLeft/StatusContainer/HullContainer/HeaderHBox/HullValue
@onready var hull_pips: HBoxContainer = $SafeArea/BottomLeft/StatusContainer/HullContainer/HullPips

@onready var damage_vignette: ColorRect = $DamageVignette

# Alerta Cinematográfico
@onready var warning_container: Control = $SafeArea/TopCenter/WarningContainer
@onready var warning_title_rich: RichTextLabel = $SafeArea/TopCenter/WarningContainer/TitleRich

var _current_shield: int = 3
var _max_shield: int = 3
var _current_hull: int = 3
var _max_hull: int = 3

var _vignette_tween: Tween = null
var _warning_tween: Tween = null
var _decrypt_timer: float = 0.0
var _is_decrypting: bool = false
var _target_title_text: String = "WARNING // INCOMING ENEMYS"

var _is_pulsing_critical: bool = false
var _critical_pulse_time: float = 0.0

const GLYPHS: String = "X0#9@$?>*!/\\%123456789ABCDEF"


func _ready() -> void:
	if damage_vignette:
		damage_vignette.modulate.a = 0.0
		damage_vignette.visible = true

	if warning_container:
		warning_container.modulate.a = 0.0
		warning_container.visible = false

	_build_shield_pips()
	_build_hull_pips()
	_update_shield_display(false)
	_update_hull_display(false)


func _process(delta: float) -> void:
	# Pulsação luminosa quando o Hull está crítico (1 ponto restante)
	if _is_pulsing_critical and hull_bar:
		_critical_pulse_time += delta * 6.0
		var alpha_pulse := (sin(_critical_pulse_time) + 1.0) * 0.5 * 0.5 + 0.5
		hull_bar.modulate = Color(1.0, 0.2, 0.2, alpha_pulse)
	elif hull_bar and hull_bar.modulate.a != 1.0:
		hull_bar.modulate.a = 1.0

	# Efeito de decodificação hacker/computador das letras de alerta
	if _is_decrypting and warning_title_rich:
		_decrypt_timer -= delta
		if _decrypt_timer <= 0.0:
			_is_decrypting = false
			_set_rich_title(_target_title_text)
		else:
			var scrambled := ""
			for i in range(_target_title_text.length()):
				if _target_title_text[i] == " " or _target_title_text[i] == "/":
					scrambled += _target_title_text[i]
				elif randf() > (_decrypt_timer / 0.35):
					scrambled += _target_title_text[i]
				else:
					scrambled += GLYPHS[randi() % GLYPHS.length()]
			_set_rich_title(scrambled)


## Conecta os sinais do jogador automaticamente
func attach_player(player: Node) -> void:
	if not is_instance_valid(player):
		return

	if player.has_signal("shield_changed"):
		if not player.is_connected("shield_changed", _on_player_shield_changed):
			player.connect("shield_changed", _on_player_shield_changed)

	if player.has_signal("hull_changed"):
		if not player.is_connected("hull_changed", _on_player_hull_changed):
			player.connect("hull_changed", _on_player_hull_changed)

	if player.has_signal("damage_taken"):
		if not player.is_connected("damage_taken", _on_player_damage_taken):
			player.connect("damage_taken", _on_player_damage_taken)

	if "current_shield" in player and "max_shield" in player:
		_max_shield = player.max_shield
		_current_shield = player.current_shield

	if "current_hull" in player and "max_hull" in player:
		_max_hull = player.max_hull
		_current_hull = player.current_hull

	_build_shield_pips()
	_build_hull_pips()
	_update_shield_display(false)
	_update_hull_display(false)


func _on_player_shield_changed(current: int, max_val: int) -> void:
	_max_shield = max_val
	_current_shield = current
	_build_shield_pips()
	_update_shield_display(true)


func _on_player_hull_changed(current: int, max_val: int) -> void:
	_max_hull = max_val
	_current_hull = current
	_build_hull_pips()
	_update_hull_display(true)


func _on_player_damage_taken(_amount: int) -> void:
	flash_damage()


## Dispara o efeito de vinheta de dano na tela (flash vermelho nas bordas)
func flash_damage() -> void:
	if not damage_vignette:
		return

	if _vignette_tween and _vignette_tween.is_running():
		_vignette_tween.kill()

	damage_vignette.modulate.a = 0.85
	_vignette_tween = create_tween()
	_vignette_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_vignette_tween.tween_property(damage_vignette, "modulate:a", 0.0, 0.45)


# ---------------------------------------------------------------------------
# Sistema de Segmentos (Pips) e Barras
# ---------------------------------------------------------------------------

func _build_shield_pips() -> void:
	if not shield_pips:
		return
	for child in shield_pips.get_children():
		child.queue_free()
	for i in range(_max_shield):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(16, 6)
		pip.name = "Pip_%d" % i
		shield_pips.add_child(pip)


func _build_hull_pips() -> void:
	if not hull_pips:
		return
	for child in hull_pips.get_children():
		child.queue_free()
	for i in range(_max_hull):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(16, 6)
		pip.name = "Pip_%d" % i
		hull_pips.add_child(pip)


func _update_shield_display(animate: bool) -> void:
	if not shield_bar:
		return

	var ratio: float = float(_current_shield) / float(maxi(1, _max_shield))
	var target_value: float = ratio * 100.0

	var stylebox := shield_bar.get_theme_stylebox("fill")
	if stylebox is StyleBoxFlat:
		stylebox.bg_color = color_shield_active if _current_shield > 0 else color_shield_offline

	if animate:
		var bar_tween := create_tween()
		bar_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		bar_tween.tween_property(shield_bar, "value", target_value, 0.25)
	else:
		shield_bar.value = target_value

	if shield_value_label:
		if _current_shield <= 0:
			shield_value_label.text = "OFFLINE"
			shield_value_label.modulate = color_shield_offline
		else:
			shield_value_label.text = "%d / %d" % [_current_shield, _max_shield]
			shield_value_label.modulate = color_shield_active

	if shield_pips:
		var children := shield_pips.get_children()
		for i in range(children.size()):
			var pip := children[i] as ColorRect
			if pip:
				if i < _current_shield:
					pip.color = color_shield_active
					pip.modulate.a = 1.0
				else:
					pip.color = Color(0.2, 0.2, 0.25, 0.4)


func _update_hull_display(animate: bool) -> void:
	if not hull_bar:
		return

	var ratio: float = float(_current_hull) / float(maxi(1, _max_hull))
	var target_value: float = ratio * 100.0

	_is_pulsing_critical = (_current_hull <= 1 and _current_hull > 0)

	var target_color: Color = color_hull_good
	if _current_hull == 2:
		target_color = color_hull_warning
	elif _current_hull <= 1:
		target_color = color_hull_critical

	var stylebox := hull_bar.get_theme_stylebox("fill")
	if stylebox is StyleBoxFlat:
		stylebox.bg_color = target_color

	if animate:
		var bar_tween := create_tween()
		bar_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		bar_tween.tween_property(hull_bar, "value", target_value, 0.25)
	else:
		hull_bar.value = target_value

	if hull_value_label:
		hull_value_label.text = "%d / %d" % [_current_hull, _max_hull]
		hull_value_label.modulate = target_color

	if hull_pips:
		var children := hull_pips.get_children()
		for i in range(children.size()):
			var pip := children[i] as ColorRect
			if pip:
				if i < _current_hull:
					pip.color = target_color
					pip.modulate.a = 1.0
				else:
					pip.color = Color(0.25, 0.1, 0.1, 0.4)


func _set_rich_title(text: String) -> void:
	if warning_title_rich:
		warning_title_rich.text = "[center][b][wave amp=18.0 freq=3.5][color=#ffcc00]%s[/color][/wave][/b][/center]" % text


## Exibe o alerta com Zoom Explosivo, Efeito Elástico e Decodificador de Computador
func show_cinematic_warning(title: String = "WARNING // INCOMING ENEMYS", _subtitle: String = "", duration: float = 3.5) -> void:
	if not warning_container:
		return

	_target_title_text = title
	_decrypt_timer = 0.35
	_is_decrypting = true

	warning_container.visible = true

	if _warning_tween and _warning_tween.is_running():
		_warning_tween.kill()

	# 1. Entrada com ZOOM EXPLOSIVO (Scale 2.4x -> 1.0x com impacto elástico)
	warning_container.scale = Vector2(2.4, 2.4)
	warning_container.pivot_offset = Vector2(350.0, 30.0)
	warning_container.modulate.a = 0.0

	_warning_tween = create_tween()
	_warning_tween.set_parallel(true)
	_warning_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_warning_tween.tween_property(warning_container, "modulate:a", 1.0, 0.25)
	_warning_tween.tween_property(warning_container, "scale", Vector2.ONE, 0.45)

	# 2. Duração de exibição
	_warning_tween.chain().set_parallel(false)
	_warning_tween.tween_interval(duration)

	# 3. Saída: dissolução e colapso suave
	_warning_tween.set_parallel(true)
	_warning_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_warning_tween.tween_property(warning_container, "scale", Vector2(1.15, 0.0), 0.25)
	_warning_tween.tween_property(warning_container, "modulate:a", 0.0, 0.25)

	_warning_tween.chain().set_parallel(false)
	_warning_tween.tween_callback(func():
		if warning_container:
			warning_container.visible = false
			warning_container.scale = Vector2.ONE
	)
