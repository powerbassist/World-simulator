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
const TermText = preload("res://src/ui/term_text.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const RosterRows = preload("res://src/ui/roster_rows.gd")
const RosterLine = preload("res://src/ui/roster_line.gd")
const RosterVerbs = preload("res://src/ui/roster_verbs.gd")
const CabinetVerbs = preload("res://src/ui/cabinet_verbs.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")
const VerbBlock = preload("res://src/ui/verb_block.gd")
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
var _verbs := CabinetVerbs.new()
var _chip := "needs"
## The focused line: ["person" | "office", id], or [] for none.
var _picked: Array = []
## A right click asked to light the picked line's verbs once the roster is rebuilt.
var _light := false
## The focused line takes the keyboard back after the rebuild that freed it.
var _refocus := false
## The briefing's person Go lands on that person's first verb.
var focused := ""


func _ready() -> void:
	custom_minimum_size = Vector2(460, 0)  # the dock sets the height (tab_page.gd wanted_height)
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
		PanelKit.toggle(button)
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
	# A Go or a partner's line lands the keyboard on a line that may sit below view.
	scroll.follow_focus = true
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
	# The person card is the one every name opens (person_tip.gd, in the glossary layer:
	# themed, plated); the roster asks it to sit above the hovered line (QA's H1 on #388:
	# a private card on a bare CanvasLayer drew unthemed and over the focused verbs).
	scroll.get_v_scroll_bar().value_changed.connect(func(_v): _hide_card())
	_close_button = Button.new()
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true
	_light = false  # a right click of the discarded game lights nothing in this one


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
		show_offices()  # an office word's Go: "seats", the office rows
		return
	_verbs._refused("")  # a new pick: a refusal said about another line goes
	focused = person_id
	_picked = ["person", person_id]
	_search.text = ""
	_chip = _chip_of(person_id)
	_dirty = true


## An office word's Go (briefing_driver.gd): the view that lists the offices, the
## keyboard on the first. `party_id` (a partner's line on the Majority tab): that party's
## first office focused instead; a party holding none focuses nothing (its line on
## Majority is greyed and says so).
func show_offices(party_id := "") -> void:
	if _chip != "government":
		_chip = "needs"
	_search.text = ""
	_verbs._refused("")  # a new pick: a refusal said about another line goes
	focused = "seats" if party_id == "" else ""  # _land puts the keyboard on the first office line
	for f in CK.PORTFOLIO_KEYS:
		if party_id != "" and String(_state.player().cabinet.get(f, "")) == party_id:
			_picked = ["office", f]
			_refocus = true
			break
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
	PanelKit.heading(_body, tr_n("The government: %d office", "The government: %d offices", rows.size()) % rows.size())
	for row in rows:
		var f := String(row["portfolio"])
		var picked := _picked == ["office", f]
		var leader := String(row["leader_id"])
		var name := tr("Vacant") if bool(row["vacant"]) else String(row["party"])
		var sub := String(row["party"]) if bool(row["vacant"]) else (tr("Led by %s, %s") % [_loader.person_name(leader), row["seats"]])
		var line := RosterLine.build(_body, ["office", f], leader, {}, [
			{"text": name, "sub": sub, "tone": UiTheme.BAD_TEXT if bool(row["vacant"]) else ""},
			# What the office delivers is a reading of what is held, never a want (G21, blind play 11-28).
			{"text": row["office"], "sub": row["delivers"], "sub_tone": row["delivers_tone"]},
			{"text": row["feels"], "tone": row["feels_tone"]}, {"text": "—", "tone": UiTheme.CAPTION},
			{"text": row["owe"], "tone": row["owe_tone"]}, {"text": "—", "tone": UiTheme.CAPTION}],
			picked, _show_card, _hide_card, _pick.bind("office", f), _menu.bind("office", row))
		# An office word's Go lands here: an office's verbs are the reshuffle.
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


## The right click (the rework pass's C, no plate): the line is picked and its strip of verbs lit after the rebuild.
func _menu(kind: String, row: Dictionary) -> void:
	_pick(kind, String(row["id"] if kind == "person" else row["portfolio"]))
	_light = true
	_dirty = true


## After a rebuild: a Go lands on the focused person's first live verb; a pick keeps the
## keyboard on its line.
func _land() -> void:
	if _light:
		_light = false
		_refocus = false
		VerbBlock.light(_body)
		return
	if focused != "":
		var seats := focused == "seats"
		focused = ""
		for button in _body.find_children("*", "Button", true, false):  # i18n: ok a class name
			if (ActsOn.acts_on(button, "seats") if seats else button.has_meta("verb")) and not (button as Button).disabled:
				(button as Button).grab_focus()
				return
	if _refocus:
		_refocus = false
		for button in _body.find_children("*", "Button", true, false):  # i18n: ok a class name
			if button.has_meta("line") and String(button.get_meta("line")) == String(_picked[1]):
				(button as Button).grab_focus()
				return


## The shared card above the hovered line, at the pointer's column.
func _show_card(person_id: String, line: Control) -> void:
	var layer = get_tree().get_first_node_in_group(TermText.GROUP) if is_inside_tree() else null
	if layer == null or not _loader.person_by_id.has(person_id):
		return
	# The focused line's verbs sit right under it: the card keeps clear of both, above
	# them, or under the verbs where there is no room above (QA's H1 on #388).
	var rect := line.get_global_rect()
	var wrap := line.get_parent()
	var next: Node = wrap.get_parent().get_child(wrap.get_index() + 1) if wrap.get_index() + 1 < wrap.get_parent().get_child_count() else null
	if next is Control and next.has_meta("strip"):
		rect = rect.merge((next as Control).get_global_rect())
	rect.position.x = get_viewport().get_mouse_position().x
	layer.person_enter(person_id, rect, true)


func _hide_card() -> void:
	var layer = get_tree().get_first_node_in_group(TermText.GROUP) if is_inside_tree() else null
	if layer != null:
		layer.person_leave()
