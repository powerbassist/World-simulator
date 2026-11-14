extends HBoxContainer

## The catalogue's two ways in -- V5.3 screen 4 (H12: "no categories"): a shelf (the thirteen
## categories Content gave the laws, #330) and a search over the names and summaries. They sit
## above the list of laws and narrow it; the bloc filter a briefing's Go sets (law_list.gd) stacks
## with them. A browsing aid only: no rule reads it, so no number moves with it.
##
## The shelf is a drop-down, not thirteen buttons: a row of thirteen names is prose on every visit
## (the prose ratchet) and a wall before the first law. Its entries carry their count, so a shelf
## with nothing to propose today is seen before it is opened.
##
## The state lives here, not in the list: the panel redraws every month and the list rebuilds its
## rows, but this widget is built once, so the typed words and the chosen shelf stay.

const LawCategory = preload("res://src/core/law_category.gd")
const Labels = preload("res://src/ui/labels.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const TermText = preload("res://src/ui/term_text.gd")

var category := ""
var query := ""
var _shelf: OptionButton
var _search: LineEdit
var _changed: Callable


## `on_change` redraws the list (the panel's mark_dirty).
func _init(on_change: Callable) -> void:
	_changed = on_change
	add_theme_constant_override("separation", 10)
	_shelf = OptionButton.new()
	_shelf.name = "Shelf"  # i18n: ok a node name, found by tests
	_shelf.fit_to_longest_item = false
	_shelf.item_selected.connect(_on_shelf)
	add_child(_shelf)
	_search = LineEdit.new()
	_search.name = "Search"  # i18n: ok a node name, found by tests
	_search.placeholder_text = tr("Search the laws")
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_on_search)
	add_child(_search)
	_fill_shelves({})


func is_active() -> bool:
	return category != "" or query != ""


## The laws that are on the chosen shelf and match the search, in their order.
func apply(laws: Array, loader) -> Array:
	_fill_shelves(_counts(laws, loader))
	if not is_active():
		return laws
	var needle := query.strip_edges().to_lower()
	return laws.filter(func(law) -> bool:
		if category != "" and LawCategory.of(loader, String(law.id)) != category:
			return false
		return needle == "" or _words_of(law).contains(needle))


## For a test or a Go: the shelf and the search set at once.
func set_filter(shelf: String, text: String) -> void:
	category = shelf
	query = text
	_search.text = text
	_select_shelf()
	_changed.call()


func empty_text() -> String:
	return tr("No law matches.")


func _words_of(law) -> String:
	return ("%s\n%s" % [Strings.law_name(law), TermText.plain(Strings.law_summary(law))]).to_lower()


## {shelf key: how many of `laws` are on it}.
func _counts(laws: Array, loader) -> Dictionary:
	var out := {}
	for law in laws:
		var key := LawCategory.of(loader, String(law.id))
		out[key] = int(out.get(key, 0)) + 1
	return out


## The entries, rebuilt with their counts (the first is every shelf), the choice kept.
func _fill_shelves(counts: Dictionary) -> void:
	_shelf.clear()
	_shelf.add_item(tr("All shelves"))
	for key in LawCategory.KEYS:
		var n := int(counts.get(key, 0))
		_shelf.add_item("%s (%d)" % [Labels.law_category(key), n] if not counts.is_empty() else Labels.law_category(key))
	_select_shelf()


func _select_shelf() -> void:
	_shelf.select(0 if category == "" else LawCategory.KEYS.find(category) + 1)


func _on_shelf(index: int) -> void:
	category = "" if index <= 0 else String(LawCategory.KEYS[index - 1])
	_changed.call()


func _on_search(text: String) -> void:
	query = text
	_changed.call()
