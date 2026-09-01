@tool
class_name SketchfabMain
extends Control

const ResultItemScene := preload("res://addons/sketchfab/ResultItem.tscn")
const ModelDialogScene := preload("res://addons/sketchfab/ModelDialog.tscn")

@onready var search_input: LineEdit = $Margin/VBox/TopBar/SearchInput
@onready var search_btn: Button = $Margin/VBox/TopBar/SearchBtn
@onready var category_option: OptionButton = $Margin/VBox/TopBar/CategoryOption
@onready var sort_option: OptionButton = $Margin/VBox/TopBar/SortOption
@onready var animated_check: CheckBox = $Margin/VBox/TopBar/AnimatedCheck
@onready var staff_check: CheckBox = $Margin/VBox/TopBar/StaffCheck
@onready var token_btn: Button = $Margin/VBox/TopBar/TokenBtn

@onready var grid_container: GridContainer = $Margin/VBox/Scroll/Center/GridContainer
@onready var status_label: Label = $Margin/VBox/StatusHBox/StatusLabel
@onready var load_more_btn: Button = $Margin/VBox/StatusHBox/LoadMoreBtn

# Token Dialog
@onready var token_dialog: ConfirmationDialog = $TokenDialog
@onready var token_input: LineEdit = $TokenDialog/Margin/VBox/TokenInput

var _next_page_url: String = ""
var _is_searching: bool = false

const CATEGORIES: Array[Dictionary] = [
	{"name": "All Categories", "slug": ""},
	{"name": "Weapons & Military", "slug": "weapons-military"},
	{"name": "Vehicles & Transport", "slug": "cars-vehicles"},
	{"name": "Characters & Creatures", "slug": "characters-creatures"},
	{"name": "Architecture", "slug": "architecture"},
	{"name": "Science & Technology", "slug": "science-technology"},
	{"name": "Nature & Plants", "slug": "nature-plants"},
	{"name": "Space & Sci-Fi", "slug": "space-astronomy"},
]

const SORT_OPTIONS: Array[Dictionary] = [
	{"name": "Relevance", "value": ""},
	{"name": "Recent", "value": "-publishedAt"},
	{"name": "Most Liked", "value": "-likeCount"},
	{"name": "Most Viewed", "value": "-viewCount"},
]


func _ready() -> void:
	_populate_dropdowns()
	if load_more_btn:
		load_more_btn.visible = false

	# Realiza uma busca inicial automática se houver conexão
	_start_search()


func _populate_dropdowns() -> void:
	if category_option:
		category_option.clear()
		for cat in CATEGORIES:
			category_option.add_item(cat["name"])

	if sort_option:
		sort_option.clear()
		for s in SORT_OPTIONS:
			sort_option.add_item(s["name"])
		sort_option.selected = 1  # Recent


func _on_search_pressed() -> void:
	_start_search()


func _on_search_input_submitted(_text: String) -> void:
	_start_search()


func _start_search(next_url: String = "") -> void:
	if _is_searching:
		return

	_is_searching = true
	var is_next_page := not next_url.is_empty()

	if not is_next_page:
		_clear_results()
		status_label.text = "Buscando modelos no Sketchfab..."
	else:
		status_label.text = "Carregando mais modelos..."

	load_more_btn.visible = false

	var query := search_input.text.strip_edges() if search_input else ""
	var cat_slug := ""
	if category_option and category_option.selected >= 0 and category_option.selected < CATEGORIES.size():
		cat_slug = CATEGORIES[category_option.selected]["slug"]

	var sort_val := "-publishedAt"
	if sort_option and sort_option.selected >= 0 and sort_option.selected < SORT_OPTIONS.size():
		sort_val = SORT_OPTIONS[sort_option.selected]["value"]

	var anim := animated_check.button_pressed if animated_check else false
	var staff := staff_check.button_pressed if staff_check else false

	var data := await SketchfabApi.search_models(self, query, cat_slug, anim, staff, sort_val, next_url)
	_is_searching = false

	if data.has("error"):
		status_label.text = "Erro ao buscar: " + str(data.get("error", "Desconhecido"))
		return

	var results: Array = data.get("results", [])
	_next_page_url = str(data.get("next", ""))

	for item_data: Dictionary in results:
		_add_result_card(item_data)

	if grid_container.get_child_count() == 0:
		status_label.text = "Nenhum modelo encontrado para esta pesquisa."
	else:
		status_label.text = "Exibindo %d modelos encontrados." % grid_container.get_child_count()

	if not _next_page_url.is_empty():
		load_more_btn.visible = true


func _clear_results() -> void:
	for child in grid_container.get_children():
		child.queue_free()


func _add_result_card(data: Dictionary) -> void:
	if not ResultItemScene:
		return

	var card := ResultItemScene.instantiate() as SketchfabResultItem
	if card:
		grid_container.add_child(card)
		card.set_model_data(data)
		card.model_clicked.connect(_on_model_card_clicked)


func _on_model_card_clicked(data: Dictionary) -> void:
	if not ModelDialogScene:
		return

	var dlg := ModelDialogScene.instantiate() as SketchfabModelDialog
	add_child(dlg)
	dlg.show_model(data)


func _on_load_more_pressed() -> void:
	if not _next_page_url.is_empty():
		_start_search(_next_page_url)


func _on_token_btn_pressed() -> void:
	if token_dialog:
		if token_input:
			token_input.text = SketchfabApi.get_token()
		token_dialog.popup_centered(Vector2i(520, 180))


func _on_token_dialog_confirmed() -> void:
	if token_input:
		var new_token := token_input.text.strip_edges()
		SketchfabApi.set_token(new_token)
		status_label.text = "✔ Token salvo com sucesso!"
