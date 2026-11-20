extends VBoxContainer

## The month page's people column (picture A, the author's pick, 2026-11-20): beside the grid,
## "who wants to see you" -- one card per waiting request, every verb with its price on its line
## -- then "reach someone", the president's own reach: summon a person of his nation, or call.
## Design's diary read (section 4): the four questions about a person -- who wants to see me,
## when can it be, what else can I do, what does each cost -- answered in one place.
##
## It takes ROWS (audience_driver.gd reads the sim) and sends each verb out as a signal; it
## never reads or writes a NationState. "See them" arms the grid (diary_grid.gd arm()), and
## the click on a free day books.

signal see_requested(request_id: String)
signal delegate_requested(request_id: String)
signal decline_requested(request_id: String)
signal call_requested(person_id: String)
signal summon_requested(person_id: String)
## A summons booked and not yet held, called off: Audiences.decline gives the cap back.
signal cancel_requested(request_id: String)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const MoodBadge = preload("res://src/ui/mood_badge.gd")
const PartyChip = preload("res://src/ui/party_chip.gd")

## px at text size 100 %: a card's face.
const FACE := Vector2(36, 48)
const BADGE := 14.0
## px at text size 100 %: the column's floor beside the grid -- a priced verb on one line.
const WIDTH := 400.0

var _cards: VBoxContainer
var _waiting: Label
var _pick: OptionButton
var _see: Button
var _call: Button
var _why: Label
var _booked: VBoxContainer
## person id per pick index, and its refusal words ("" when it can be summoned).
var _people: Array = []


func _init() -> void:
	name = "DiaryPeople"  # i18n: ok a node name, found by tests
	add_theme_constant_override("separation", PanelKit.SECTION_SEPARATION)


func _ready() -> void:
	custom_minimum_size.x = WIDTH * UiTheme.text_scale()
	var head := HBoxContainer.new()
	add_child(head)
	var title := Label.new()
	title.theme_type_variation = UiTheme.MICRO
	title.text = tr("Who wants to see you")
	head.add_child(title)
	_waiting = Label.new()
	_waiting.name = "Waiting"  # i18n: ok a node name, found by tests
	_waiting.theme_type_variation = UiTheme.MICRO
	head.add_child(_waiting)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", PanelKit.SECTION_SEPARATION)
	add_child(_cards)
	var reach := PanelKit.section(self, tr("Reach someone"))
	PanelKit.plain_line(reach, tr("A summons takes a day: talk, no ask, rapport up. One a month; eight months before the same person again. A call takes no day; its odds are lower, and nothing is learned."), PanelKit.Tone.DIM)
	_pick = OptionButton.new()
	_pick.name = "SummonPick"  # i18n: ok a node name, found by tests
	_pick.fit_to_longest_item = false
	_pick.item_selected.connect(func(_i: int) -> void: _show_pick())
	reach.add_child(_pick)
	var verbs := PanelKit.buttons(reach)
	_see = PanelKit.sized(Button.new())
	_see.name = "SummonSee"  # i18n: ok a node name, found by tests
	_see.text = tr("See them")
	_see.pressed.connect(func() -> void: summon_requested.emit(_picked()))
	verbs.add_child(_see)
	_call = PanelKit.sized(Button.new())
	_call.name = "SummonCall"  # i18n: ok a node name, found by tests
	_call.text = tr("Call")
	_call.pressed.connect(func() -> void: call_requested.emit(_picked()))
	verbs.add_child(_call)
	_why = PanelKit.plain_line(reach, "", PanelKit.Tone.DIM)
	_booked = VBoxContainer.new()
	reach.add_child(_booked)


## `rows` audience_driver.row_of() per waiting request; `people` [{person_id, person, why}] the
## nation's people a summons can reach (why: "" or the sim's refusal); `summoned` [{id, person,
## when}] the summons booked and not yet held; `armed` the grid's armed person.
func show_rows(rows: Array, people: Array, summoned: Array, armed: Dictionary) -> void:
	if _cards == null:
		return
	_waiting.text = str(rows.size()) if not rows.is_empty() else ""
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	if rows.is_empty():
		PanelKit.plain_line(_cards, tr("Nobody is waiting to see you."), PanelKit.Tone.DIM)
	for row in rows:
		_card(row, String(armed.get("id", "")) == String(row["id"]) and not bool(armed.get("summons", false)))
	var kept := _picked()
	_people = people
	_pick.clear()
	for p in people:
		_pick.add_item(String(p["person"]))
		if String(p["person_id"]) == kept:
			_pick.select(_pick.item_count - 1)
	_show_pick()
	for child in _booked.get_children():
		_booked.remove_child(child)
		child.queue_free()
	for s in summoned:
		var line := HBoxContainer.new()
		_booked.add_child(line)
		var text := PanelKit.plain_line(line, tr("You summoned %s for %s.") % [String(s["person"]), String(s["when"])], PanelKit.Tone.PLAIN)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cancel := PanelKit.sized(Button.new())
		cancel.name = "CancelSummons"  # i18n: ok a node name, found by tests
		cancel.text = tr("Cancel")
		cancel.tooltip_text = tr("No meeting is held, so it does not count against the cap.")
		var id := String(s["id"])
		cancel.pressed.connect(func() -> void: cancel_requested.emit(id))
		line.add_child(cancel)


## Select `person_id` in the summons picker (a test, the People page later).
func pick_person(person_id: String) -> void:
	for i in _people.size():
		if String(_people[i]["person_id"]) == person_id:
			_pick.select(i)
			_show_pick()
			return


func _picked() -> String:
	var i := _pick.selected if _pick != null else -1
	return String(_people[i]["person_id"]) if i >= 0 and i < _people.size() else ""


func _show_pick() -> void:
	var i := _pick.selected
	var why := String(_people[i]["why"]) if i >= 0 and i < _people.size() else ""
	_see.disabled = i < 0 or why != ""
	_call.disabled = i < 0
	_see.tooltip_text = Strings.t(why) if why != "" else ""  # i18n: row-ok the sim's refusal, its English the msgid
	_why.text = Strings.t(why) if why != "" else ""  # i18n: row-ok the sim's refusal, its English the msgid
	_why.visible = why != ""


func _card(row: Dictionary, armed: bool) -> void:
	var id := String(row["id"])
	var pid := String(row["person_id"])
	var plate := PanelContainer.new()
	plate.name = "Card_%s" % id  # i18n: ok a node name, found by tests
	plate.theme_type_variation = UiTheme.PLATE
	_cards.add_child(plate)
	var body := PanelKit.padded(plate, 8, PanelKit.ROW_SEPARATION)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	body.add_child(top)
	var s := UiTheme.text_scale()
	var feel: Dictionary = row.get("feel", {})
	var face: Control = Portrait.framed_for(pid, FACE * s, MoodBadge.mood_portrait(pid, feel))
	if not feel.is_empty():
		MoodBadge.wear(face, feel, BADGE * s)
	face.custom_minimum_size = FACE * s
	top.add_child(face)
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(who)
	var name_row := HBoxContainer.new()
	who.add_child(name_row)
	var person := Label.new()
	person.theme_type_variation = UiTheme.LEAD
	person.text = String(row["person"])
	name_row.add_child(person)
	if not (row.get("party", {}) as Dictionary).is_empty():
		name_row.add_child(PartyChip.make(row["party"]))
	PanelKit.plain_line(who, String(row.get("wants", "")), PanelKit.Tone.PLAIN)
	# The dated thing that pulls him back (Design's read, "return trigger"): in the attention tone.
	PanelKit.chip(who, tr("Answer by %s") % String(row.get("by", "")), UiTheme.CHIP_WARN)
	if bool(row.get("broken_word", false)):
		PanelKit.plain_line(who, tr("They hold something on you. Refusing them breaks your word."), PanelKit.Tone.BAD)
	if int(row.get("called", 0)) > 0:
		PanelKit.plain_line(who, tr("You called; they still want to see you."), PanelKit.Tone.DIM)
	var book: Dictionary = row.get("book", {})
	var see := _verb(body, "See_%s" % id, tr("See them"), book,
		String(row.get("until", "")) if not armed else tr("Now click a free day on the calendar."))
	see.toggle_mode = true
	see.button_pressed = armed
	see.pressed.connect(func() -> void: see_requested.emit(id))
	var call := _verb(body, "Call_%s" % id, tr("Call"), row.get("call", {}), tr("no day used; odds lower than across a desk; nothing learned"))
	call.pressed.connect(func() -> void: call_requested.emit(pid))
	var delegate := _verb(body, "Delegate_%s" % id, tr("Delegate"), row.get("delegate", {}), String(row.get("delegate_hint", "")))  # i18n: row-ok worded by lever_words.delegate_hint
	delegate.pressed.connect(func() -> void: delegate_requested.emit(id))
	var price := String(row.get("price", ""))
	if row.has("lapse_price"):
		price = tr("%s; no answer by then: %s") % [price, String(row["lapse_price"])]
	var decline := _verb(body, "Decline_%s" % id, tr("Decline"), row.get("decline", {}), price)
	decline.pressed.connect(func() -> void: decline_requested.emit(id))


## One verb and its price beside it; a refused verb stays, disabled, its reason as the price.
func _verb(parent: Control, node_name: String, label: String, answer: Dictionary, price: String) -> Button:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", PanelKit.BUTTON_SEPARATION)
	parent.add_child(line)
	var b := PanelKit.sized(Button.new())
	b.name = node_name
	b.text = label
	var ok := bool(answer.get("ok", true))
	b.disabled = not ok
	line.add_child(b)
	var words := price if ok else String(answer.get("reason", ""))
	var text := PanelKit.plain_line(line, words, PanelKit.Tone.DIM)  # i18n: row-ok a price or the sim's refusal, worded by the caller
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	b.tooltip_text = words
	return b
