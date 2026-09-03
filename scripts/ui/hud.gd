class_name CombatHUD
extends CanvasLayer

## HUD de combate tático estilo AAA para Novastorm.
## Painel militar/cyberpunk de monitoramento dual:
##   - Módulo de SHIELD (Células de energia holográfica ciano / aviso OFFLINE)
##   - Módulo de HULL INTEGRITY (Blindagem em células com estados Verde/Âmbar/Vermelho)
##   - Tremer de painel em impactos (Hit Shiver), vinheta e avisos cinematográficos.

@export_category("Cores do HUD")
@export var color_shield_active: Color = Color(0.0, 0.88, 1.0, 1.0)       # Ciano Neon
@export var color_shield_offline: Color = Color(0.95, 0.2, 0.15, 0.85)   # Vermelho Alerta
@export var color_hull_good: Color = Color(0.08, 0.92, 0.48, 1.0)         # Verde Esmeralda (3/3)
@export var color_hull_warning: Color = Color(1.0, 0.72, 0.1, 1.0)        # Âmbar Tático (2/3)
@export var color_hull_critical: Color = Color(1.0, 0.22, 0.2, 1.0)       # Vermelho Crítico (1/3)

# Referências de nós na cena
@onready var tactical_panel: PanelContainer = $SafeArea/BottomLeft/TacticalPanel
@onready var shield_row: HBoxContainer = $SafeArea/BottomLeft/TacticalPanel/Margin/StatusVBox/ShieldRow
@onready var shield_label: Label = $SafeArea/BottomLeft/TacticalPanel/Margin/StatusVBox/ShieldRow/ShieldLabel
@onready var shield_pips: HBoxContainer = $SafeArea/BottomLeft/TacticalPanel/Margin/StatusVBox/ShieldRow/ShieldPips

@onready var hull_row: HBoxContainer = $SafeArea/BottomLeft/TacticalPanel/Margin/StatusVBox/HullRow
@onready var hull_label: Label = $SafeArea/BottomLeft/TacticalPanel/Margin/StatusVBox/HullRow/HullLabel
@onready var hull_pips: HBoxContainer = $SafeArea/BottomLeft/TacticalPanel/Margin/StatusVBox/HullRow/HullPips

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
var _panel_shake_tween: Tween = null
var _shield_blink_tween: Tween = null
var _is_shield_down: bool = false
var _shield_down_time: float = 0.0
var _decrypt_timer: float = 0.0
var _is_decrypting: bool = false
var _target_title_text: String = "WARNING // INCOMING ENEMIES"

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
	# Pulsação suave de alarme quando o Hull está crítico (1 ponto restante)
	if _is_pulsing_critical and hull_pips:
		_critical_pulse_time += delta * 5.0
		var alpha_pulse := (sin(_critical_pulse_time) + 1.0) * 0.5 * 0.45 + 0.55
		hull_pips.modulate.a = alpha_pulse
		if hull_label:
			hull_label.modulate.a = alpha_pulse
	else:
		if hull_pips and hull_pips.modulate.a != 1.0:
			hull_pips.modulate.a = 1.0
		if hull_label and hull_label.modulate.a != 1.0:
			hull_label.modulate.a = 1.0

	# Alerta contínuo quando o Shield caiu completamente (0 de escudo)
	if _is_shield_down and shield_label:
		_shield_down_time += delta * 4.5
		var shield_down_alpha := (sin(_shield_down_time) + 1.0) * 0.5 * 0.6 + 0.35
		shield_label.modulate = Color(1.3, 0.25, 0.25, shield_down_alpha)

	# Decodificação hacker/computador das letras do alerta
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
	var prev := _current_shield
	_max_shield = max_val
	_current_shield = current
	_build_shield_pips()
	_update_shield_display(true)

	if current < prev:
		if current <= 0:
			_trigger_shield_break_blink()
		else:
			_trigger_shield_hit_blink()
	elif current > 0:
		_is_shield_down = false
		if _shield_blink_tween and _shield_blink_tween.is_running():
			_shield_blink_tween.kill()
		if shield_row:
			shield_row.modulate = Color.WHITE


func _on_player_hull_changed(current: int, max_val: int) -> void:
	_max_hull = max_val
	_current_hull = current
	_build_hull_pips()
	_update_hull_display(true)


func _on_player_damage_taken(_amount: int) -> void:
	flash_damage()
	_shiver_tactical_panel()


## Dispara o efeito de tremer o painel tático ao sofrer impacto
func _shiver_tactical_panel() -> void:
	if not tactical_panel:
		return
	if _panel_shake_tween and _panel_shake_tween.is_running():
		_panel_shake_tween.kill()

	var orig_pos := Vector2(0, 0)
	_panel_shake_tween = create_tween()
	_panel_shake_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_panel_shake_tween.tween_property(tactical_panel, "position:x", orig_pos.x - 8.0, 0.04)
	_panel_shake_tween.tween_property(tactical_panel, "position:x", orig_pos.x + 6.0, 0.04)
	_panel_shake_tween.tween_property(tactical_panel, "position:x", orig_pos.x - 3.0, 0.04)
	_panel_shake_tween.tween_property(tactical_panel, "position:x", orig_pos.x, 0.04)


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
# Células Táticas de Energia / Blindagem (AAA Pips)
# ---------------------------------------------------------------------------

func _build_shield_pips() -> void:
	if not shield_pips:
		return
	if shield_pips.get_child_count() == _max_shield:
		return
	for child in shield_pips.get_children():
		child.queue_free()

	for i in range(_max_shield):
		var pip := PanelContainer.new()
		pip.custom_minimum_size = Vector2(0, 10)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.size_flags_vertical = Control.SIZE_FILL
		pip.name = "ShieldPip_%d" % i
		shield_pips.add_child(pip)


func _build_hull_pips() -> void:
	if not hull_pips:
		return
	if hull_pips.get_child_count() == _max_hull:
		return
	for child in hull_pips.get_children():
		child.queue_free()

	for i in range(_max_hull):
		var pip := PanelContainer.new()
		pip.custom_minimum_size = Vector2(0, 10)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.size_flags_vertical = Control.SIZE_FILL
		pip.name = "HullPip_%d" % i
		hull_pips.add_child(pip)


func _update_shield_display(animate: bool) -> void:
	if not shield_pips:
		return

	if _current_shield > 0:
		_is_shield_down = false
		if shield_label:
			shield_label.modulate = Color(0.2, 1.15, 1.35, 1.0)
	else:
		_is_shield_down = true

	var children := shield_pips.get_children()
	for i in range(children.size()):
		var pip := children[i] as PanelContainer
		if not pip:
			continue

		var is_active := (i < _current_shield)
		var sb := StyleBoxFlat.new()
		sb.corner_radius_top_left = 2
		sb.corner_radius_top_right = 2
		sb.corner_radius_bottom_right = 2
		sb.corner_radius_bottom_left = 2

		if is_active:
			# ACESO: Extremamente brilhante, neon emissivo com contorno luminoso e sombra de glow intensa
			sb.bg_color = Color(0.1, 1.1, 1.35, 1.0)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.border_color = Color(0.9, 1.3, 1.4, 1.0)
			sb.shadow_color = Color(0.0, 0.95, 1.0, 0.85)
			sb.shadow_size = 6
			pip.modulate = Color(1.15, 1.15, 1.15, 1.0)
		else:
			# APAGADO: Escuro, oco, desativado, sem brilho
			sb.bg_color = Color(0.03, 0.05, 0.08, 0.85)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.border_color = Color(0.15, 0.2, 0.28, 0.35)
			sb.shadow_size = 0
			pip.modulate = Color(1.0, 1.0, 1.0, 0.5)

		pip.add_theme_stylebox_override("panel", sb)

		if animate and i == _current_shield:
			var flash_tween := create_tween()
			pip.modulate = Color(3.0, 3.0, 3.0, 1.0)
			flash_tween.tween_property(pip, "modulate", Color(1.0, 1.0, 1.0, 0.5), 0.25)


func _update_hull_display(animate: bool) -> void:
	if not hull_pips:
		return

	_is_pulsing_critical = (_current_hull <= 1 and _current_hull > 0)

	var target_color: Color = Color(0.15, 1.15, 0.55, 1.0)  # Verde esmeralda brilhante
	var target_glow: Color = Color(0.1, 0.95, 0.45, 0.85)
	var target_border: Color = Color(0.8, 1.3, 0.9, 1.0)

	if _current_hull == 2:
		target_color = Color(1.2, 0.85, 0.1, 1.0)  # Âmbar brilhante
		target_glow = Color(1.0, 0.75, 0.1, 0.85)
		target_border = Color(1.3, 1.1, 0.6, 1.0)
	elif _current_hull <= 1:
		target_color = Color(1.35, 0.2, 0.15, 1.0)  # Vermelho alarme brilhante
		target_glow = Color(1.0, 0.15, 0.1, 0.85)
		target_border = Color(1.4, 0.6, 0.5, 1.0)

	if hull_label:
		hull_label.modulate = target_color

	var children := hull_pips.get_children()
	for i in range(children.size()):
		var pip := children[i] as PanelContainer
		if not pip:
			continue

		var is_active := (i < _current_hull)
		var sb := StyleBoxFlat.new()
		sb.corner_radius_top_left = 2
		sb.corner_radius_top_right = 2
		sb.corner_radius_bottom_right = 2
		sb.corner_radius_bottom_left = 2

		if is_active:
			# ACESO: Muito brilhante com contorno e glow correspondentes
			sb.bg_color = target_color
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.border_color = target_border
			sb.shadow_color = target_glow
			sb.shadow_size = 6
			pip.modulate = Color(1.15, 1.15, 1.15, 1.0)
		else:
			# APAGADO: Vazio e escuro
			sb.bg_color = Color(0.05, 0.03, 0.03, 0.85)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.border_color = Color(0.25, 0.12, 0.12, 0.35)
			sb.shadow_size = 0
			pip.modulate = Color(1.0, 1.0, 1.0, 0.5)

		pip.add_theme_stylebox_override("panel", sb)

		if animate and i == _current_hull:
			var flash_tween := create_tween()
			pip.modulate = Color(3.0, 3.0, 3.0, 1.0)
			flash_tween.tween_property(pip, "modulate", Color(1.0, 1.0, 1.0, 0.5), 0.25)


## Pisca intensamente toda a linha de Shield quando o escudo cai para 0
func _trigger_shield_break_blink() -> void:
	_is_shield_down = true
	_shield_down_time = 0.0

	if not shield_row:
		return

	if _shield_blink_tween and _shield_blink_tween.is_running():
		_shield_blink_tween.kill()

	_shield_blink_tween = create_tween()
	# Sequência rápida de 5 piscadas estroboscópicas em vermelho alarme
	for _i in range(5):
		_shield_blink_tween.tween_property(shield_row, "modulate", Color(2.6, 0.3, 0.3, 1.0), 0.07)
		_shield_blink_tween.tween_property(shield_row, "modulate", Color(0.3, 0.06, 0.06, 0.2), 0.07)

	_shield_blink_tween.tween_property(shield_row, "modulate", Color.WHITE, 0.1)


## Pisca sutilmente a linha de Shield ao tomar dano parcial
func _trigger_shield_hit_blink() -> void:
	if not shield_row:
		return
	var hit_tween := create_tween()
	hit_tween.tween_property(shield_row, "modulate", Color(2.2, 2.2, 2.5, 1.0), 0.06)
	hit_tween.tween_property(shield_row, "modulate", Color(0.4, 0.8, 1.0, 0.6), 0.06)
	hit_tween.tween_property(shield_row, "modulate", Color.WHITE, 0.08)


func _set_rich_title(text: String) -> void:
	if warning_title_rich:
		warning_title_rich.text = "[center][b][wave amp=24.0 freq=4.0][color=#ffcc00]%s[/color][/wave][/b][/center]" % text


## Exibe o alerta com animação elástica das letras crescendo
func show_cinematic_warning(title: String = "WARNING // INCOMING ENEMIES", _subtitle: String = "", duration: float = 5.5) -> void:
	if not warning_container:
		return

	_target_title_text = title
	_decrypt_timer = 0.45
	_is_decrypting = true

	warning_container.visible = true

	if _warning_tween and _warning_tween.is_running():
		_warning_tween.kill()

	# 1. Efeito Elástico: as letras iniciam em escala quase zero e crescem com overshoot elástico elástico
	warning_container.scale = Vector2(0.02, 0.02)
	warning_container.pivot_offset = Vector2(350.0, 30.0)
	warning_container.modulate.a = 0.0

	_warning_tween = create_tween()
	_warning_tween.set_parallel(true)
	# Entrada rápida de opacidade para visibilidade imediata
	_warning_tween.tween_property(warning_container, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# As letras explodem e quicam elásticamente (0.02 -> 1.35x -> 0.88x -> 1.05x -> 1.0x)
	_warning_tween.tween_property(warning_container, "scale", Vector2.ONE, 1.05).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	# 2. Duração de permanência para o jogador ler com calma durante a aproximação da wave
	_warning_tween.chain().set_parallel(false)
	_warning_tween.tween_interval(duration)

	# 3. Saída cinematográfica: colapso elástico vertical suave e fade out
	_warning_tween.chain().set_parallel(true)
	_warning_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	_warning_tween.tween_property(warning_container, "scale", Vector2(1.2, 0.0), 0.35)
	_warning_tween.tween_property(warning_container, "modulate:a", 0.0, 0.3)

	_warning_tween.chain().set_parallel(false)
	_warning_tween.tween_callback(func():
		if warning_container:
			warning_container.visible = false
			warning_container.scale = Vector2.ONE
	)
