extends PanelContainer

## People -- rework 1 (Gameplay's people-cabinet brief; the author's direction A, "le
## tableau"). The decision this page carries: WHO GETS MY DAYS THIS MONTH. One roster,
## sorted by who needs the president (roster_rows.gd), a word before every figure, chips
## and a search box to pick a group, and the government as the first group, one row per
## portfolio, a vacant office marked with what a vacancy does.
##
## V4.3's page had no button "by design": every act on a person lived elsewhere, and the
## gate read it as "people panel is messy and unreadable" and "refusé m'a rien coûté en
## apparence". The verbs now sit on the focused row, on a right click and on focus
## (roster_verbs.gd), each greyed with the sim's own reason; after an act the row itself
## changes (the request's date, a seat marked vacant).
##
## Only the open group is built: "Needs you" and the government by default, a chip's
## group or a search's matches otherwise -- never the whole register.
##
## Reads simulation state; the commands are the sim's (Audiences.book through the Diary's
## path, the phone, Removal through cabinet_verbs.gd).

signal closed
## A right click or the Call verb asks to call them (phone_driver.gd).
signal call_requested(person_id: String)
## See: book the request on its first free offered day, the Diary's own path.
signal see_requested(request_id: String, date: Dictionary)
## A reshuffle or a dismissal, carrying the pre-command baseline (the effect card).
signal reassigned(before: Dictionary, title: String)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const RosterRows = preload("res://src/ui/roster_rows.gd")
const RosterLine = preload("res://src/ui/roster_line.gd")
const RosterVerbs = preload("res://src/ui/roster_verbs.gd")
const CabinetVerbs = preload("res://src/ui/cabinet_verbs.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")
const VerbPlate = preload("res://src/ui/verb_plate.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")

const HEADS := ["Person", "Holds", "Feels", "Wants now", "You owe", "Known"]  # i18n: msgid

var _state
var _loader
var _dirty := true
var _body: VBoxContainer
var _title: Label
var _search: LineEdit
var _chips: HFlowContainer
var _close_button: Button
var _card
var _verbs := CabinetVerbs.new()
var _chip := "needs"
## The focused line: ["person" | "office", id], or [] for none.
var _picked: Array = []
## The focused line takes the keyboard back after the rebuild that freed it.
var _refocus := false
## The briefing's person Go lands on that person's first verb.
var focused := ""


func _ready() -> void:
	custom_minimum_size = Vector2(460, 700)
	var root := PanelKit.padded(self, 16, 10)
	_title = Label.new()
	_title.theme_type_variation = UiTheme.LEAD
	_title.text = tr("Who gets your days this month?")
	root.add_child(_title)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 12)
	root.add_child(tools)
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 6)
	_chips.add_theme_constant_override("v_separation", 6)
	_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(_chips)
	for chip in RosterRows.CHIPS:
		var button := PanelKit.sized(Button.new())
		button.text = tr(String(chip[1]))
		button.toggle_mode = true
		button.set_meta("chip", String(chip[0]))
		button.pressed.connect(_pick_chip.bind(String(chip[0])))
		_chips.add_child(button)
	_search = LineEdit.new()
	_search.placeholder_text = tr("A name, a party, an office")
	_search.custom_minimum_size.x = 240 * UiTheme.text_scale()
	_search.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _dirty = true)
	tools.add_child(_search)
	var heads: Array = []
	for head in HEADS:
		heads.append(tr(head).to_upper())
	RosterLine.heads(root, heads)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 2)
	scroll.add_child(_body)
	# The removal's confirm card, its price and its refusal line (cabinet_verbs.gd).
	_verbs.reassigned.connect(func(before: Dictionary, title: String) -> void:
		reassigned.emit(before, title)
		_dirty = true)
	root.add_child(_verbs)
	# The hover card rides its own layer, over the scroll and every window (person_card.gd).
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_card = PersonCard.new()
	layer.add_child(_card)
	scroll.get_v_scroll_bar().value_changed.connect(func(_v): _hide_card())
	_close_button = Button.new()
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


## Docked-tab mode: the docking frame's X is the real close (window_manager.gd's register()).
func hide_close_button() -> void:
	_close_button.hide()


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


## The briefing's person Go: their line focused, in a group that lists them, and the
## keyboard on its first verb (a Go lands on a verb).
func focus(person_id: String) -> void:
	if not _loader.person_by_id.has(person_id):
		show_offices()  # the majority's Go: "seats", the office rows
		return
	focused = person_id
	_picked = ["person", person_id]
	_search.text = ""
	_chip = _chip_of(person_id)
	_dirty = true


## The majority's Go: the view that lists the offices.
func show_offices() -> void:
	if _chip != "government":
		_chip = "needs"
	_search.text = ""
	_dirty = true


func _chip_of(person_id: String) -> String:
	for chip in RosterRows.CHIPS:
		for row in RosterRows.rows(_state, _loader, String(chip[0]), ""):
			if String(row["id"]) == person_id:
				return String(chip[0])
	return "needs"


func _pick_chip(chip: String) -> void:
	_chip = chip
	_search.text = ""
	_dirty = true


func _refresh() -> void:
	if _state.player() == null:
		return
	# The lines under the pointer are about to be freed: their card goes with them.
	_hide_card()
	_verbs.sync(_state, _loader)
	for chip in _chips.get_children():
		(chip as Button).set_pressed_no_signal(String(chip.get_meta("chip")) == _chip and _search.text.strip_edges() == "")
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var query := _search.text.strip_edges()
	if query != "":
		var found := RosterRows.rows(_state, _loader, "", query)
		# "Nobody" only when no office matched either (pass 1 on #388).
		var none := tr("Nobody of that name, party or office.") if not _offices(query) else ""
		if not found.is_empty() or none != "":
			_group(tr("Matches (%d)") % found.size(), found, none)
	elif _chip == "needs":
		_group(tr("Needs you"), RosterRows.rows(_state, _loader, "needs", ""), tr("Nobody waits on you this month."))
		_offices()
		PanelKit.line(_body, tr("The rest: pick a group above."))
	elif _chip == "government":
		_offices()
		_group(tr("The government's people"), RosterRows.rows(_state, _loader, "government", ""), "")
	else:
		for chip in RosterRows.CHIPS:
			if String(chip[0]) == _chip:
				var rows := RosterRows.rows(_state, _loader, _chip, "")
				_group("%s (%d)" % [tr(String(chip[1])), rows.size()], rows, "")
	_land.call_deferred()


func _group(title: String, rows: Array, empty: String) -> void:
	PanelKit.heading(_body, title)
	if rows.is_empty() and empty != "":
		PanelKit.line(_body, empty)
	var ns = _state.player()
	for row in rows:
		var pid := String(row["id"])
		var picked := _picked == ["person", pid]
		RosterLine.build(_body, ["person", pid], pid, Feelings.of(ns, pid), [
			{"text": row["name"], "sub": row["side"]}, {"text": row["holds"]}, {"text": row["feels"], "tone": row["feels_tone"]},  # i18n: row-ok the roster reader's own row, its words already resolved
			{"text": row["wants"], "tone": row["wants_tone"]}, {"text": row["owe"]}, {"text": row["known"], "tone": UiTheme.CAPTION}],
			picked, _show_card, _hide_card, _pick.bind("person", pid), _menu.bind("person", row))
		if picked:
			RosterVerbs.strip(_body, _person_items(row), RosterLine.FACE.x + 20)


## The office rows; a search (`query`) keeps those whose office, party or leader match it.
## Whether any row was drawn.
func _offices(query := "") -> bool:
	var rows := RosterRows.offices(_state, _loader).filter(func(r) -> bool:
		return query == "" or ("%s %s %s" % [r["office"], r["party"], _loader.person_name(String(r["leader_id"]))]).to_lower().contains(query.to_lower()))
	if rows.is_empty():
		return false
	PanelKit.heading(_body, tr("The government: %d offices") % rows.size())
	for row in rows:
		var f := String(row["portfolio"])
		var picked := _picked == ["office", f]
		var leader := String(row["leader_id"])
		var name := tr("Vacant") if bool(row["vacant"]) else String(row["party"])
		var sub := String(row["party"]) if bool(row["vacant"]) else (tr("Led by %s, %s") % [_loader.person_name(leader), row["seats"]])
		var line := RosterLine.build(_body, ["office", f], leader, {}, [
			{"text": name, "sub": sub, "tone": UiTheme.BAD_TEXT if bool(row["vacant"]) else ""}, {"text": row["office"]},
			{"text": row["feels"], "tone": row["feels_tone"]}, {"text": row["delivers"], "tone": row["delivers_tone"]},
			{"text": row["owe"], "tone": row["owe_tone"]}, {"text": "—", "tone": UiTheme.CAPTION}],
			picked, _show_card, _hide_card, _pick.bind("office", f), _menu.bind("office", row))
		# The briefing's majority Go lands here: an office's verbs are the reshuffle.
		ActsOn.tag(line.get_child(0), ["seats"])
		if picked:
			RosterVerbs.strip(_body, RosterVerbs.for_office(_state, _loader, row, _verbs), RosterLine.FACE.x + 20)
	return true


func _person_items(row: Dictionary) -> Array:
	return RosterVerbs.for_person(_state, _loader, row, see_requested.emit, call_requested.emit)


## A line pressed, clicked or right-clicked: it becomes the focused one.
func _pick(kind: String, id: String) -> void:
	if _picked == [kind, id]:
		return
	_picked = [kind, id]
	_verbs._refused("")  # a refusal said about another line is not this one's
	_refocus = true
	_dirty = true


## The right click's plate: the same items as the strip.
func _menu(kind: String, row: Dictionary) -> void:
	var plate = VerbPlate.of(self)
	if plate == null:
		return
	plate.open(self, _person_items(row) if kind == "person" else RosterVerbs.for_office(_state, _loader, row, _verbs))


## After a rebuild: a Go lands on the focused person's first live verb; a pick keeps the
## keyboard on its line.
func _land() -> void:
	if focused != "":
		focused = ""
		for button in _body.find_children("*", "Button", true, false):  # i18n: ok a class name
			if button.has_meta("verb") and not (button as Button).disabled:
				(button as Button).grab_focus()
				return
	if _refocus:
		_refocus = false
		for button in _body.find_children("*", "Button", true, false):  # i18n: ok a class name
			if button.has_meta("line") and String(button.get_meta("line")) == String(_picked[1]):
				(button as Button).grab_focus()
				return


## The card at the cursor, clamped to the viewport, after show_for has filled it.
func _show_card(person_id: String) -> void:
	var vp := get_viewport()
	if _card == null or vp == null or not _loader.person_by_id.has(person_id):
		return
	_card.show_for(person_id, _loader, _state.player(), Vector2.ZERO)
	var pos := vp.get_mouse_position() + Vector2(18, 12)
	var card_size: Vector2 = _card.get_combined_minimum_size()
	var vp_size := vp.get_visible_rect().size
	pos.x = minf(pos.x, maxf(vp_size.x - card_size.x - 8.0, 8.0))
	pos.y = minf(pos.y, maxf(vp_size.y - card_size.y - 8.0, 8.0))
	_card.position = pos


func _hide_card() -> void:
	if _card != null:
		_card.hide_card()
