class_name CombatHUD
extends CanvasLayer

## HUD de combate em tempo real para Novastorm.
## Gerencia a exibição da integridade do escudo/casco, efeito de vinheta de dano
## e texto de alerta estilizado com fonte de computador, zoom elástico e efeito decodificador.

@export_category("Cores do Escudo")
@export var color_high: Color = Color(0.0, 0.85, 1.0, 1.0)       # Ciano Sci-Fi
@export var color_medium: Color = Color(1.0, 0.75, 0.1, 1.0)     # Âmbar / Amarelo
@export var color_critical: Color = Color(1.0, 0.2, 0.2, 1.0)    # Vermelho Crítico

# Referências de nós na cena
@onready var shield_bar: ProgressBar = $SafeArea/BottomLeft/ShieldContainer/ShieldBar
@onready var shield_label: Label = $SafeArea/BottomLeft/ShieldContainer/HeaderHBox/ShieldLabel
@onready var shield_value_label: Label = $SafeArea/BottomLeft/ShieldContainer/HeaderHBox/ShieldValue
@onready var pips_container: HBoxContainer = $SafeArea/BottomLeft/ShieldContainer/PipsContainer
@onready var damage_vignette: ColorRect = $DamageVignette

# Alerta Cinematográfico
@onready var warning_container: Control = $SafeArea/TopCenter/WarningContainer
@onready var warning_title_rich: RichTextLabel = $SafeArea/TopCenter/WarningContainer/TitleRich

var _current_health: int = 3
var _max_health: int = 3
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
	_update_shield_display(false)


func _process(delta: float) -> void:
	# Efeito de pulsação luminosa quando a vida está em estado crítico
	if _is_pulsing_critical and shield_bar:
		_critical_pulse_time += delta * 6.0
		var alpha_pulse := (sin(_critical_pulse_time) + 1.0) * 0.5 * 0.5 + 0.5
		shield_bar.modulate = Color(1.0, 0.2, 0.2, alpha_pulse)
	elif shield_bar and shield_bar.modulate.a != 1.0:
		shield_bar.modulate.a = 1.0

	# Efeito de decodificação hacker/computador das letras
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

	if player.has_signal("health_changed"):
		if not player.is_connected("health_changed", _on_player_health_changed):
			player.connect("health_changed", _on_player_health_changed)

	if player.has_signal("damage_taken"):
		if not player.is_connected("damage_taken", _on_player_damage_taken):
			player.connect("damage_taken", _on_player_damage_taken)

	if "current_health" in player and "max_health" in player:
		_max_health = player.max_health
		_current_health = player.current_health
		_build_shield_pips()
		_update_shield_display(false)


func _on_player_health_changed(current: int, max_val: int) -> void:
	_max_health = max_val
	_current_health = current
	_build_shield_pips()
	_update_shield_display(true)


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


## Reconstrói os segmentos (pips) visuais de acordo com o max_health
func _build_shield_pips() -> void:
	if not pips_container:
		return

	for child in pips_container.get_children():
		child.queue_free()

	for i in range(_max_health):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(14, 8)
		pip.name = "Pip_%d" % i
		pips_container.add_child(pip)


## Atualiza a barra de vida e os segmentos
func _update_shield_display(animate: bool) -> void:
	if not shield_bar:
		return

	var ratio: float = float(_current_health) / float(maxi(1, _max_health))
	var target_value: float = ratio * 100.0

	_is_pulsing_critical = (_current_health <= 1 and _current_health > 0)

	# Atualiza cor da barra de acordo com a integridade
	var target_color: Color = color_high
	if ratio <= 0.25:
		target_color = color_critical
	elif ratio <= 0.60:
		target_color = color_medium

	var stylebox := shield_bar.get_theme_stylebox("fill")
	if stylebox is StyleBoxFlat:
		stylebox.bg_color = target_color

	if animate:
		var bar_tween := create_tween()
		bar_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		bar_tween.tween_property(shield_bar, "value", target_value, 0.25)
	else:
		shield_bar.value = target_value

	if shield_value_label:
		shield_value_label.text = "%d / %d" % [_current_health, _max_health]
		shield_value_label.modulate = target_color

	# Atualiza pips individuais
	if pips_container:
		var children := pips_container.get_children()
		for i in range(children.size()):
			var pip := children[i] as ColorRect
			if pip:
				if i < _current_health:
					pip.color = target_color
					pip.modulate.a = 1.0
				else:
					pip.color = Color(0.2, 0.2, 0.25, 0.5)


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
