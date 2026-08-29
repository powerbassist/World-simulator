extends PanelContainer

## Dispatches -- V1.8's one new surface, and the last of the V1 tier.
##
## Reads simulation state and content, writes neither: the verb goes back as an
## explicit command through `acted`, which is the shape Budget.commit() set and
## companies_panel.gd, projects_panel.gd and campaign_panel.gd all follow.
##
## NOT MODAL, unlike the election result screen and the censure plate, and that is the
## design rather than a convenience. A crisis the player CAN ignore and pay for is the
## whole of "forces a response under time pressure"; a modal removes the choice by
## removing the option of not making it, which would turn the deadline into a dialogue
## box. The card in the message column is the interruption, this window is where the
## decision lives, and both can be left alone.
##
## TWO SECTIONS AND THE LEDGER IS THE SECOND ONE. What is on the desk is the decision;
## what was decided is the record of every decision before it, including the ones that
## were made by the clock. docs/pledge-model.md's own screenshot pass found a live
## promise that never said what it had cost -- the one figure that section existed to be
## a ledger of -- and this panel is the same kind of ledger, so it carries the record
## rather than only the question.

signal closed
## (before_snapshot, label) -- the same pair projects_panel.acted and law_panel.proposed
## emit, so answering an event earns a U4 decision delta on the terms a subsidy, a law
## and a project already do.
signal acted(before, label)

const Events = preload("res://src/sim/events.gd")
const EventsK = preload("res://src/sim/events_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const Government = preload("res://src/sim/government.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")

var _state
var _loader
var _dirty := true

var _title: Label
var _body: VBoxContainer
## projects_panel.gd's reason, and here it applies at BOTH ends: the pending block is at
## the top and the ledger is at the bottom, so V1.6e's screenshot correction has a
## direction per flag rather than per panel. tools/screenshot.gd drives these; nothing
## in the game does.
var _scroll: ScrollContainer
var _pin_bottom := false
var _close_button: Button

## The first enabled verb this panel built on its last refresh. See primary_action().
var _primary: Control = null


func _ready() -> void:
	custom_minimum_size = Vector2(520, 560)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_title = Label.new()
	_title.theme_type_variation = UiTheme.LEAD
	root.add_child(_title)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	# The right gutter is companies_panel.gd's fix inherited: a ScrollContainer draws
	# its bar OVER the content, and the right-aligned figures in PanelKit.row() run underneath
	# it without one.
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 14)
	_scroll.add_child(gutter)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	gutter.add_child(_body)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


## A STANDING FLAG rather than a one-shot scroll, projects_panel.gd's own correction:
## _refresh() rebuilds every child, so a scroll position set before the next rebuild is
## undone by it.
func scroll_to_bottom() -> void:
	_pin_bottom = true
	_dirty = true


func _apply_bottom() -> void:
	if _scroll == null:
		return
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func hide_close_button() -> void:
	_close_button.hide()


func _process(_delta: float) -> void:
	if not _dirty or not visible or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return
	_primary = null

	_title.text = "Dispatches"

	for child in _body.get_children():
		child.queue_free()

	_build_pending(ns)
	_build_ledger(ns)

	if _pin_bottom:
		_apply_bottom()


# --- On the desk -------------------------------------------------------------------

func _build_pending(ns) -> void:
	PanelKit.heading(_body, "On your desk")

	var ev = Events.pending_event(ns, _loader)
	if ev == null:
		# Two states reach this line and they are not the same, so the caption names
		# which one -- projects_panel.gd's own correction, where a player who could not
		# tell an empty list from a closed gate would read the lever as broken.
		if int(ns.event_quiet_months) > 0:
			PanelKit.line(_body, "Nothing today. The last matter closed %d %s ago." % [
				EventsK.EVENT_COOLDOWN_MONTHS - int(ns.event_quiet_months),
				"month" if EventsK.EVENT_COOLDOWN_MONTHS - int(ns.event_quiet_months) == 1 else "months",
			])
		else:
			PanelKit.line(_body, "Nothing today.")
		return

	PanelKit.line(_body, ev.event_name, PanelKit.Tone.PLAIN)

	var who := _subject_label(ns, ev)
	if who != "":
		var who_label := Label.new()
		who_label.text = who
		who_label.theme_type_variation = UiTheme.MICRO
		_body.add_child(who_label)

	PanelKit.line(_body, ev.summary)

	# The deadline in the same units the register holds and the diary prints. Two
	# surfaces reporting one fact in two units is how they come to disagree -- U6c's
	# hover read "12 of 96 months" against a project with twelve months LEFT.
	var left := Events.months_left(ns)
	var deadline := Label.new()
	deadline.text = "%d %s to answer, then: %s" % [
		left, "month" if left == 1 else "months", ev.default_choice().get("label", ""),
	]
	# NEUTRAL until the last month, and the first captured frame is why: this line was
	# GOOD_TEXT at any comfortable distance, so "2 months to answer, then: Say nothing"
	# rendered in green -- the colour this interface uses for a delta that is good news.
	# A deadline is not good news at any distance; it is only more or less urgent.
	deadline.theme_type_variation = UiTheme.BAD_TEXT if left <= 1 else UiTheme.CAPTION
	_body.add_child(deadline)

	for choice in ev.choices:
		_build_choice(ns, ev, choice)


## One option: what it does above the button that does it.
##
## The summary is printed rather than left in a tooltip, unlike projects_panel.gd's
## verb buttons, and the difference is what a deadline does to a decision. A project
## offer can be read at leisure and hovered; an event has a clock on it, and a
## consequence the player has to hover to discover is one they will not discover.
func _build_choice(ns, ev, choice: Dictionary) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	PanelKit.line(block, String(choice.get("summary", "")))

	var button := Button.new()
	# The default is named as such on its own button. Without it the one option that
	# will happen anyway looks like the other two, and the player cannot tell which
	# way silence falls -- which is the only thing the deadline is about.
	button.text = "%s%s" % [
		String(choice.get("label", "")),
		"   (happens if you say nothing)" if bool(choice.get("is_default", false)) else "",
	]
	button.pressed.connect(func(): _on_choose(ev, choice))
	if _primary == null and not button.disabled:
		_primary = button
	block.add_child(button)

	_body.add_child(block)


## U4's contract, projects_panel._on_act()'s shape exactly: the baseline is captured
## BEFORE the command, so the delta measures the month the choice was made against the
## month before it.
func _on_choose(ev, choice: Dictionary) -> void:
	var before := Budget.snapshot(_state)
	var record := Events.choose(_state, _loader, String(choice.get("id", "")))
	if record.is_empty():
		return
	_dirty = true
	acted.emit(before, "%s: %s" % [ev.event_name, String(choice.get("label", ""))])


## The person behind the office, resolved HERE and never in src/sim/.
##
## U6b's rule verbatim -- a law names an office and the nation's own data names who
## holds it -- so an event's content carries `subject_office` and this file is the only
## thing in the project that turns it into a name. That is what keeps "no mechanism on a
## person" true by construction: there is no field on a person for a mechanism to hang
## off, and no id crosses into the simulation.
func _subject_label(ns, ev) -> String:
	if not ev.has_subject():
		return ""
	var person_id := ""
	var office := ""
	match ev.subject_office:
		"head_of_government":
			person_id = ns.pm_person_id
			office = ns.head_of_government_title if ns.head_of_government_title != "" else "Head of government"
		"head_of_state":
			person_id = ns.head_of_state_person_id
			office = ns.head_of_state_title if ns.head_of_state_title != "" else "Head of state"
		"largest_party_leader":
			var party_list: Array = _loader.parties.get(ns.id, [])
			var largest := Government.largest_party_id(ns, party_list)
			for party in party_list:
				if party.id == largest:
					person_id = party.leader_person_id
					office = "%s, leader" % party.party_name
					break
	var who: String = _loader.person_name(person_id)
	if who == "":
		return office
	return "%s — %s" % [who, office]


# --- The ledger --------------------------------------------------------------------

func _build_ledger(ns) -> void:
	PanelKit.heading(_body, "What you decided")
	if ns.event_history.is_empty():
		PanelKit.line(_body, "Nothing has come up yet.")
		return
	for record in ns.event_history:
		_build_record(record)


func _build_record(record: Dictionary) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	PanelKit.line(block, "%04d-%02d  %s" % [
		int(record.get("year", 0)), int(record.get("month", 0)),
		String(record.get("event_name", "")),
	], PanelKit.Tone.PLAIN)

	var answer := Label.new()
	# A DEFAULT IS NOT A CHOICE AND THE LEDGER SAYS SO. Printing "Say nothing" beside a
	# month the player never opened this window would read as a decision they made, and
	# the one thing a ledger of forced choices has to be able to show is which of them
	# the clock made instead.
	if bool(record.get("defaulted", false)):
		answer.text = "No answer given — %s" % String(record.get("choice_label", ""))
		answer.theme_type_variation = UiTheme.BAD_TEXT
	else:
		answer.text = String(record.get("choice_label", ""))
		answer.theme_type_variation = UiTheme.CAPTION
	block.add_child(answer)

	# WHAT IT MEANT, and the first captured frame is why this line exists.
	# docs/pledge-model.md's own screenshot pass found a live promise that never said
	# what it had cost -- the one figure that section existed to be a ledger of -- and
	# the ledger here had the same shape: it named the button and not the consequence.
	#
	# DERIVED FROM THE CONTENT rather than stored with the record, which is the whole
	# reason it is affordable: the choice's own summary round-trips through
	# data/events/, so tests/test_save_load.gd's assertion that a serialised entry
	# carries three keys and nothing else survives intact. V1.4a's discipline, and
	# U6c's "the site belongs to the nation" one surface on.
	var what := _choice_summary(record)
	if what != "":
		var meant := Label.new()
		meant.text = what
		meant.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		meant.theme_type_variation = UiTheme.MICRO
		block.add_child(meant)

	_body.add_child(block)


## The authored sentence that sat above the button, looked up by id. Empty when the
## content no longer defines the event -- a save older than a content change is a legal
## state, and a ledger row that loses its footnote is better than one that cannot draw.
func _choice_summary(record: Dictionary) -> String:
	var ev = Events.event_by_id(_loader, String(record.get("event_id", "")))
	if ev == null:
		return ""
	var choice: Dictionary = ev.choice_by_id(String(record.get("choice_id", "")))
	return String(choice.get("summary", ""))


## The control this panel exists to let the player press -- V2.1a's fold contract,
## declared here at V2.1b.
##
## The choices are rebuilt on every refresh, so this is the first one in build
## order rather than a member held from _ready(). Null when nothing is pending,
## which is most months -- the panel is then the ledger of what was decided.
func primary_action() -> Control:
	return _primary
