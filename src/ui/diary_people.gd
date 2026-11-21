extends VBoxContainer

## The month page's people column, option C (the author's pick, 2026-11-21: "the matrix"): who
## wants to see the president as a row of faces, each ringed by the time left to answer (the
## dated thing that pulls him back, Design's read); the picked one's file with the CHOICE as a
## matrix -- See them, Call, Delegate, Decline against what each takes (a day), does to rapport,
## the odds of a lever and whether he learns about them -- so the prices sit beside the verbs
## and compare at a glance; then "someone else", his own reach: a summons (one a month, never
## the same person twice inside eight months) or a call.
##
## It takes ROWS (diary_month_page.gd reads the sim) and sends each verb out as a signal; it
## never reads or writes a NationState. "See them" arms the grid (diary_grid.gd arm()), and the
## click on a free day books.

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
const AudienceK = preload("res://src/sim/audience_constants.gd")
const LeverK = preload("res://src/sim/lever_constants.gd")
const DiaryDay = preload("res://src/ui/diary_day.gd")

## px at text size 100 %: the column beside the grid, a token, the file's face.
const WIDTH := 410.0
const TOKEN := Vector2(76, 82)
const FACE := Vector2(44, 58)
## px at text size 100 %: the matrix's columns -- the verb, then a day, rapport, odds, learn.
const COLUMNS := [86.0, 44.0, 132.0, 58.0, 44.0]

var _tokens: HBoxContainer
var _file: VBoxContainer
var _file_plate: PanelContainer
## show_rows()'s last arguments: a token's click redraws the file from them.
var _last: Array = []
var _pick: OptionButton
var _see: Button
var _call: Button
var _why: Label
var _cap: Label
var _booked: VBoxContainer
## person id per pick index, and its refusal words ("" when it can be summoned).
var _people: Array = []
## The request whose file is open, kept across refreshes; "" for the first.
var _open := ""
## The armed request last seen: a new one opens its file, and a token's click is not undone.
var _armed_was := ""
## The route of the last press: a key (true) or the mouse. See them hands the keyboard a day
## only from the keys -- a mouse route must not leave Space booking it (the #427 ruling).
var by_keys := false


func _init() -> void:
	name = "DiaryPeople"  # i18n: ok a node name, found by tests
	add_theme_constant_override("separation", PanelKit.SECTION_SEPARATION)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		by_keys = false
	elif (event is InputEventKey or event is InputEventJoypadButton) and event.pressed:
		by_keys = true


func _ready() -> void:
	custom_minimum_size.x = WIDTH * UiTheme.text_scale()
	var head := Label.new()
	head.name = "Waiting"  # i18n: ok a node name, found by tests
	head.theme_type_variation = UiTheme.MICRO
	add_child(head)
	_tokens = HBoxContainer.new()
	_tokens.add_theme_constant_override("separation", 4)
	add_child(_tokens)
	_file_plate = PanelContainer.new()
	_file_plate.theme_type_variation = UiTheme.PLATE
	add_child(_file_plate)
	_file = PanelKit.padded(_file_plate, 8, PanelKit.ROW_SEPARATION)
	var reach_plate := PanelContainer.new()
	reach_plate.theme_type_variation = UiTheme.PLATE
	add_child(reach_plate)
	var reach := PanelKit.padded(reach_plate, 8, PanelKit.ROW_SEPARATION)
	var top := HBoxContainer.new()
	reach.add_child(top)
	var title := Label.new()
	title.theme_type_variation = UiTheme.MICRO
	title.text = tr("Someone else")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_cap = Label.new()
	_cap.name = "SummonCap"  # i18n: ok a node name, found by tests
	_cap.theme_type_variation = UiTheme.CAPTION
	top.add_child(_cap)
	var verbs := HBoxContainer.new()
	verbs.add_theme_constant_override("separation", PanelKit.BUTTON_SEPARATION)
	reach.add_child(verbs)
	_pick = OptionButton.new()
	_pick.name = "SummonPick"  # i18n: ok a node name, found by tests
	_pick.fit_to_longest_item = false
	_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pick.item_selected.connect(func(_i: int) -> void: _show_pick())
	verbs.add_child(_pick)
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
	PanelKit.same_width([_see, _call])
	_why = PanelKit.plain_line(reach, "", PanelKit.Tone.DIM)
	_booked = VBoxContainer.new()
	reach.add_child(_booked)


## `rows` audience_driver.row_of() per waiting request (plus `until`, `left`, `frac`); `people`
## [{person_id, person, why}] the nation's people a summons can reach (why: "" or the sim's
## refusal, in words); `summoned` [{id, person, when}] the summons booked and not yet held;
## `free` whether this month's summons is still to use; `armed` the grid's armed person.
func show_rows(rows: Array, people: Array, summoned: Array, free: bool, armed: Dictionary) -> void:
	if _tokens == null:
		return
	_last = [rows, people, summoned, free, armed]
	(get_node("Waiting") as Label).text = tr_n("%d wants to see you", "%d want to see you", rows.size()) % rows.size() \
		if not rows.is_empty() else tr("Nobody is waiting to see you")
	var armed_id := "" if bool(armed.get("summons", false)) else String(armed.get("id", ""))
	if armed_id != "" and armed_id != _armed_was:
		_open = armed_id
	_armed_was = armed_id
	if not rows.any(func(r: Dictionary) -> bool: return String(r["id"]) == _open):
		_open = String(rows[0]["id"]) if not rows.is_empty() else ""
	for child in _tokens.get_children() + _file.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	for row in rows:
		_token(row)
	var plus := Button.new()
	plus.name = "SomeoneElse"  # i18n: ok a node name, found by tests
	plus.theme_type_variation = UiTheme.SEGMENT
	plus.text = "+"  # i18n: ok a glyph
	plus.tooltip_text = tr("See or call someone who has not asked")
	plus.custom_minimum_size = Vector2(TOKEN.y * 0.6, TOKEN.y) * UiTheme.text_scale()
	plus.pressed.connect(func() -> void: _pick.grab_focus())
	_tokens.add_child(plus)
	_file_plate.visible = not rows.is_empty()
	for row in rows:
		if String(row["id"]) == _open:
			_show_file(row, String(armed.get("id", "")) == _open and not bool(armed.get("summons", false)))
	var kept := _picked()
	_people = people
	_pick.clear()
	for p in people:
		_pick.add_item(String(p["person"]))
		if String(p["person_id"]) == kept:
			_pick.select(_pick.item_count - 1)
	_cap.text = tr("Summons this month: ● free") if free else tr("Summons this month: ○ used")
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
	_see.tooltip_text = why if why != "" else tr("A summons takes a day: talk, no ask, rapport up. One a month; the same person not again within eight months.")  # i18n: row-ok the caller's refusal words
	_why.text = why  # i18n: row-ok the caller's refusal words
	_why.visible = why != ""


## A face ringed by the share of the window left to answer, the days left under the name.
func _token(row: Dictionary) -> void:
	var s := UiTheme.text_scale()
	var b := Button.new()
	b.name = "Token_%s" % String(row["id"])  # i18n: ok a node name, found by tests
	b.theme_type_variation = UiTheme.SEGMENT
	b.toggle_mode = true
	b.button_pressed = String(row["id"]) == _open
	b.custom_minimum_size = TOKEN * s
	b.tooltip_text = tr("%s: %d days left to answer") % [String(row["person"]), int(row.get("left", 0))]
	_tokens.add_child(b)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	b.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ring := Ring.new()
	ring.frac = float(row.get("frac", 1.0))
	ring.custom_minimum_size = Vector2(44, 44) * s
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ring)
	var face: Control = Portrait.framed_for(String(row["person_id"]), Vector2(26, 34) * s)
	DiaryDay.ignore_mouse(face)
	ring.add_child(face)
	face.position = (Vector2(44, 44) - Vector2(26, 34)) * s / 2.0
	for text in [String(row["person"]).get_slice(" ", String(row["person"]).get_slice_count(" ") - 1),
			tr_n("%d day", "%d days", int(row.get("left", 0))) % int(row.get("left", 0))]:
		var label := Label.new()
		label.theme_type_variation = UiTheme.CAPTION if box.get_child_count() == 1 else UiTheme.WARN_TEXT
		label.text = text  # i18n: row-ok a name, or a count already worded
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(label)
	var id := String(row["id"])
	b.pressed.connect(func() -> void:
		_open = id
		callv("show_rows", _last))


## The open request's file: who, what they want, by when, and the choice as a matrix.
func _show_file(row: Dictionary, armed: bool) -> void:
	var id := String(row["id"])
	var pid := String(row["person_id"])
	var s := UiTheme.text_scale()
	_file.name = "Card_%s" % id  # i18n: ok a node name, found by tests
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_file.add_child(top)
	var feel: Dictionary = row.get("feel", {})
	var face: Control = Portrait.framed_for(pid, FACE * s, MoodBadge.mood_portrait(pid, feel))
	if not feel.is_empty():
		MoodBadge.wear(face, feel, 14.0 * s)
	face.custom_minimum_size = FACE * s
	top.add_child(face)
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(who)
	var person := Label.new()
	person.theme_type_variation = UiTheme.LEAD
	person.text = String(row["person"])
	who.add_child(person)
	if not (row.get("party", {}) as Dictionary).is_empty():
		who.add_child(PartyChip.make(row["party"]))
	PanelKit.plain_line(who, String(row.get("wants", "")), PanelKit.Tone.PLAIN)
	PanelKit.chip(_file, tr("Answer by %s") % String(row.get("by", "")), UiTheme.CHIP_WARN)
	if bool(row.get("broken_word", false)):
		PanelKit.plain_line(_file, tr("They hold something on you. Refusing them breaks your word."), PanelKit.Tone.BAD)
	_cells(_file, null, ["", tr("a day"), tr("rapport"), tr("odds"), tr("learn")], PanelKit.Tone.DIM)
	var grudge := roundi(AudienceK.DELEGATE_GRUDGE_SHARE * 100.0)
	var see := _verb(id, "See", tr("See them"), row.get("book", {}),
		["●", tr("▲ up"), tr("full"), "●"], tr("Now click a free day on the calendar.") if armed else String(row.get("until", "")))
	see.toggle_mode = true
	see.button_pressed = armed
	see.pressed.connect(func() -> void: see_requested.emit(id))
	var call := _verb(id, "Call", tr("Call"), row.get("call", {}),  # i18n: ok a node-name key
		["○", tr("▲ if it lands"), "−%d" % roundi(LeverK.CALL_ODDS_PENALTY * 100.0), "○"], tr("no day used; one call a month"))
	call.pressed.connect(func() -> void: call_requested.emit(pid))
	# Delegate's odds are a minister keeping the word (the sim's chance), or none where only the
	# president can answer; the full sentence rides on the hover.
	var given: Dictionary = row.get("delegate", {})
	var keeps := tr("%d in 10") % roundi(float(given["chance"]) * 10.0) if given.has("chance") and String(given.get("why", "")) == "" else tr("✕ none")
	var delegate := _verb(id, "Delegate", tr("Delegate"), given,  # i18n: ok a node-name key
		["○", tr("▼ %d %% of a no") % grudge, keeps, "○"], tr("a minister gives their word"))
	delegate.tooltip_text = String(row.get("delegate_hint", ""))  # i18n: row-ok worded by lever_words.delegate_hint
	delegate.pressed.connect(func() -> void: delegate_requested.emit(id))
	var price := String(row.get("price", ""))
	if row.has("lapse_price"):
		price = tr("%s; no answer by then: %s") % [price, String(row["lapse_price"])]
	var decline := _verb(id, "Decline", tr("Decline"), row.get("decline", {}),  # i18n: ok a node-name key
		["○", tr("▼ a grudge"), PanelKit.MISSING, "○"], price)
	decline.pressed.connect(func() -> void: decline_requested.emit(id))
	PanelKit.same_width([see, call, delegate, decline])


## One verb's row of the matrix and its note under it; a refused verb stays, disabled, its
## reason as the note.
func _verb(id: String, key: String, label: String, answer: Dictionary, marks: Array, note: String) -> Button:
	var b := PanelKit.sized(Button.new())
	b.name = "%s_%s" % [key, id]
	b.text = label
	var ok := bool(answer.get("ok", true))
	b.disabled = not ok
	var words := note if ok else String(answer.get("reason", ""))
	b.tooltip_text = words
	_cells(_file, b, [""] + marks, PanelKit.Tone.PLAIN)
	var line := PanelKit.plain_line(_file, words, PanelKit.Tone.DIM)  # i18n: row-ok a note or the sim's refusal, worded by the caller
	line.autowrap_mode = TextServer.AUTOWRAP_WORD
	line.name = "Note_%s_%s" % [key, id]  # i18n: ok a node name, found by tests
	return b


## A matrix row at COLUMNS' widths: `lead` (a verb's button, or nothing for the header), then
## the texts; a ▲ is good news and a ▼ bad, said by the glyph as well as the tone.
func _cells(parent: Control, lead: Button, texts: Array, tone: PanelKit.Tone) -> void:
	var s := UiTheme.text_scale()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	parent.add_child(row)
	for i in COLUMNS.size():
		var holder := HBoxContainer.new()
		holder.custom_minimum_size.x = float(COLUMNS[i]) * s
		holder.alignment = BoxContainer.ALIGNMENT_BEGIN if i < 3 else BoxContainer.ALIGNMENT_CENTER
		row.add_child(holder)
		if i == 0 and lead != null:
			holder.add_child(lead)
			continue
		var t := String(texts[i])
		var cell := PanelKit.plain_line(holder, t, tone)  # i18n: row-ok a mark or a word worded above
		cell.autowrap_mode = TextServer.AUTOWRAP_OFF
		if tone == PanelKit.Tone.DIM:
			cell.theme_type_variation = UiTheme.MICRO
		elif t.begins_with("▲"):
			cell.theme_type_variation = UiTheme.GOOD_TEXT
		elif t.begins_with("▼"):
			cell.theme_type_variation = UiTheme.BAD_TEXT


## The ring of a token: the share of the window left, in the attention tone, on an EDGE track.
class Ring extends Control:
	var frac := 1.0

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 2.0
		draw_arc(c, r, 0.0, TAU, 48, UiTheme.EDGE, 3.0, true)
		if frac > 0.0:
			draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * clampf(frac, 0.0, 1.0), 48, UiTheme.WARN, 3.0, true)
