extends VBoxContainer

## The catalogue's shelves -- the Bills second pass, the author's pick "A : les rayons" (G3-1
## messy, G3-2 not in categories). A search over every shelf's names and summaries, then one
## button per shelf with how many laws stand on it, open or shut, then the line that sends budget
## lines and tax rates to Finances. The list shows the open shelf; a search reads every shelf,
## because a player who types a name wants that law wherever it is filed. A browsing aid only: no
## rule reads it, so no number moves with it.
##
## The state lives here, not in the list: the panel redraws every month and the list rebuilds its
## rows, but this widget is built once, so the typed words and the chosen shelf stay.

## A shelf button pressed, before the redraw (law_list.gd ends a bloc's Go on it).
signal shelf_pressed

const LawCategory = preload("res://src/core/law_category.gd")
const Labels = preload("res://src/ui/labels.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const TermText = preload("res://src/ui/term_text.gd")

## The shelves, in the order they stand: the categories of everyday government first, the
## constitution and the elections last. Tax laws keep their shelf (the parent's ruling): they are
## voted laws and ride the same one-a-month queue; only the budget lines and the tax RATES are
## Finances', which the line under the shelves points to.
const SHELVES := ["work", "welfare_health", "education_culture", "housing", "energy_environment",
	"business", "farming", "justice_transparency", "europe_migration", "media", "elections",
	"constitution", "taxes"]
## The shelf of the player's own composed laws, which carry no category: shown only while one exists.
const DRAFTS := "drafts"  # i18n: ok a key, shown through Labels
## The column's width at text size 100 %.
const WIDTH := 220.0

var category: String = SHELVES[0]
var query := ""
var _search: LineEdit
var _shelves: VBoxContainer
var _buttons := {}
var _changed: Callable


## `on_change` redraws the list (the panel's mark_dirty).
func _init(on_change: Callable) -> void:
	_changed = on_change
	add_theme_constant_override("separation", 6)
	_search = LineEdit.new()
	_search.name = "Search"  # i18n: ok a node name, found by tests
	_search.placeholder_text = tr("Find a law")
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search)
	add_child(_search)
	_shelves = VBoxContainer.new()
	_shelves.add_theme_constant_override("separation", 2)
	add_child(_shelves)
	var group := ButtonGroup.new()
	for key in SHELVES + [DRAFTS]:
		var b := Button.new()
		b.name = "Shelf_%s" % key  # i18n: ok a node name, found by tests
		PanelKit.toggle(b)
		b.button_group = group
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_shelf.bind(String(key)))
		_shelves.add_child(b)
		_buttons[key] = b
	PanelKit.line(self, tr("Budget lines, tax rates and the finance bill are in Finances."))


func _ready() -> void:
	custom_minimum_size.x = WIDTH * UiTheme.text_scale()


## The shelf buttons, in SHELVES order (the drafts shelf is not among them).
func shelf_buttons() -> Array:
	return SHELVES.map(func(key): return _buttons[key])


## The laws the list shows, in their order: the open shelf's, or every shelf's that match the
## search. `laws` are the catalogue's (law_list.gd keeps every shelved law, open or shut).
## `every_shelf`: the caller has narrowed them already (a bloc's Go), so no shelf narrows them again.
func apply(laws: Array, loader, every_shelf := false) -> Array:
	var counts := {}
	for law in laws:
		var key := shelf_of(law, loader)
		counts[key] = int(counts.get(key, 0)) + 1
	for key in _buttons:
		var b: Button = _buttons[key]
		b.text = "%s   %d" % [Labels.law_category(key), int(counts.get(key, 0))]
		b.set_pressed_no_signal(key == category and query == "" and not every_shelf)
		# A flat button draws no pressed state: the open shelf stands raised, the others flat.
		b.flat = not b.button_pressed
	_buttons[DRAFTS].visible = counts.has(DRAFTS)
	# The last draft gone (proposed, carried): its shelf goes with it, back to the first.
	if category == DRAFTS and not counts.has(DRAFTS):
		category = SHELVES[0]
		_buttons[category].set_pressed_no_signal(query == "" and not every_shelf)
		_buttons[category].flat = not _buttons[category].button_pressed
	var needle := query.strip_edges().to_lower()
	return laws.filter(func(law) -> bool:
		if needle != "":
			return _words_of(law).contains(needle)
		return every_shelf or shelf_of(law, loader) == category)


## A law's shelf: its category, or the drafts shelf for a composed law; "" when no shelf here holds it.
static func shelf_of(law, loader) -> String:
	var key := LawCategory.of(loader, String(law.id))
	if key == "":
		return DRAFTS
	return key if SHELVES.has(key) else ""


## For a test or a Go: the shelf and the search set at once.
func set_filter(shelf: String, text: String) -> void:
	category = shelf if shelf != "" else SHELVES[0]
	query = text
	_search.text = text
	_changed.call()


## Opens `key`'s shelf without a redraw: the caller redraws (law_list.select).
func open_shelf(key: String) -> void:
	category = key
	query = ""
	_search.text = ""


func empty_text() -> String:
	return tr("No law matches.") if query != "" else tr("No law stands on this shelf.")


func _words_of(law) -> String:
	return ("%s\n%s" % [Strings.law_name(law), TermText.plain(Strings.law_summary(law))]).to_lower()


func _on_shelf(key: String) -> void:
	shelf_pressed.emit()
	category = key
	query = ""
	_search.text = ""
	_changed.call()


func _on_search(text: String) -> void:
	query = text
	_changed.call()
