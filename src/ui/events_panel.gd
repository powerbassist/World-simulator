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
const Trends = preload("res://src/ui/trends.gd")
const Government = preload("res://src/sim/government.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const EventArt = preload("res://src/ui/event_art.gd")
const Grade = preload("res://src/ui/grade.gd")
const MessageSettings = preload("res://src/ui/message_settings.gd")
const SpeakerRow = preload("res://src/ui/speaker_row.gd")

var _state
var _loader
var _dirty := true
var _messages := {}  # V4.8c: the FEED band filters the ledger; empty = defaults

var _title: Label
var _body: VBoxContainer
## projects_panel.gd's reason, and here it applies at BOTH ends: the pending block is at
## the top and the ledger is at the bottom, so V1.6e's screenshot correction has a
## direction per flag rather than per panel. tools/screenshot.gd drives these; nothing
## in the game does.
var _scroll: ScrollContainer
var _pin_bottom := false
var _close_button: Button

## V5.3-0 (b), R10 ("dispatches menu is fucked", then "pas tres élégant comme
## menu"): each desk entry is ONE card -- the plate as a strip, the title, a
## category and countdown chip, the messenger -- and its choices are buttons that
## open their own authored text on select, with Choose under it. Three summaries
## printed whole above three buttons were 72 of the tab's 187 words at month 12;
## the player reads the one they are weighing. The ledger is a timeline: the
## date and the matter, then what was decided, its meaning on hover.
## event id -> the choice id whose text is open, "" for none. Presentation only:
## a load or a new desk entry starts closed.
var _picked := {}

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
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


## V4.8c. The player's message settings; main.gd hands them in at boot and again
## whenever the settings screen closes.
func set_messages(messages: Dictionary) -> void:
	_messages = messages
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
	if not _dirty or not is_visible_in_tree() or _state == null:
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

	_title.text = tr("Dispatches")

	for child in _body.get_children():
		child.queue_free()

	_build_pending(ns)
	_build_ledger(ns)

	if _pin_bottom:
		_apply_bottom()


# --- On the desk -------------------------------------------------------------------

func _build_pending(ns) -> void:
	PanelKit.heading(_body, tr("On your desk"))

	# An open choice is kept only for an entry still on the desk: one answered, or
	# gone with a load, starts closed if its event comes back.
	var live := {}
	for entry in ns.event_queue:
		live[String(entry.get("event_id", ""))] = true
	for id in _picked.keys():
		if not live.has(id):
			_picked.erase(id)

	# V4.4: the desk is a queue, ordered worst-first by the machine, and the panel
	# prints every entry -- a Dispatches window that showed only the head would
	# answer four deadlines with one clock's worth of information. Each entry
	# carries its own countdown and its own answer route (Events.answer, by id),
	# which is what keeps the buttons on the row they name.
	var longest_quiet := 0
	for category in ns.event_category_quiet:
		longest_quiet = maxi(longest_quiet, int(ns.event_category_quiet[category]))

	if ns.event_queue.is_empty():
		# Two states reach this line and they are not the same, so the caption names
		# which one -- projects_panel.gd's own correction, where a player who could not
		# tell an empty list from a closed gate would read the lever as broken.
		if longest_quiet > 0:
			var closed_ago: int = EventsK.CATEGORY_QUIET_MONTHS - longest_quiet
			if closed_ago <= 0:
				PanelKit.line(_body, tr("Nothing today. The last matter closed this month."))
			else:
				PanelKit.line(_body, tr_n("Nothing today. The last matter closed %d month ago.", "Nothing today. The last matter closed %d months ago.", closed_ago) % closed_ago)
		else:
			PanelKit.line(_body, tr("Nothing today."))
		return

	for entry in ns.event_queue:
		_build_entry(ns, entry)


## One desk entry: the crisis, the clock on it, the menu. The severity tag rides the
## title line because it is the queue's own ordering made visible -- the player who
## cannot see why this row sits above that one is the player who trusts the order
## for no reason.
func _build_entry(ns, entry: Dictionary) -> void:
	var ev = Events.event_by_id(_loader, String(entry.get("event_id", "")))
	if ev == null:
		return

	# A sited crisis names its place -- read off the register, which carries the
	# name because every reader of it (this panel, the calendar, the card) is a
	# leaf over pending state (V3.5).
	var title: String = Strings.row_name("events", ev)
	var where := String(entry.get("region_name", ""))
	if where != "":
		title = "%s — %s" % [title, where]

	# The plate above the title line: category art keyed by severity band, the
	# variant picked stably from the event's own id -- the same plate the
	# arrival card carries, so one crisis reads as one story in both places.
	# Missing art is silent (the lenient precedent): the entry is a line again,
	# never a hole where a header would have been.
	var card := PanelContainer.new()
	card.theme_type_variation = UiTheme.PLATE
	_body.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var art := EventArt.plate_texture(ev.category, int(entry.get("severity", 1)), ev.id)
	if art != null:
		var header := TextureRect.new()
		header.texture = art
		header.custom_minimum_size = Vector2(0, 64)
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		header.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		box.add_child(Grade.apply(header))

	var head := Label.new()
	head.text = title
	head.theme_type_variation = UiTheme.LEAD
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)

	# The chips: the category and its severity, then the clock. The deadline in the
	# same units the register holds and the diary prints -- two surfaces reporting
	# one fact in two units is how they come to disagree (U6c). NEUTRAL until the
	# last month: a deadline is not good news at any distance.
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 12)
	box.add_child(chips)
	var tag := Label.new()
	tag.text = "%s · %d/%d" % [Labels.event_category(String(ev.category)), int(entry.get("severity", 1)), EventsK.SEVERITY_MAX]
	tag.tooltip_text = tr("The category, and its severity out of %d.") % EventsK.SEVERITY_MAX
	tag.mouse_filter = Control.MOUSE_FILTER_PASS
	tag.theme_type_variation = UiTheme.MICRO
	chips.add_child(tag)
	var left := int(entry.get("months_left", 0))
	var clock := Label.new()
	clock.text = tr_n("%d month left", "%d months left", left) % left
	clock.theme_type_variation = UiTheme.BAD_TEXT if left <= 1 else UiTheme.CAPTION
	chips.add_child(clock)

	var who := _subject_label(ns, ev)
	if who != "":
		var who_label := Label.new()
		who_label.text = who
		who_label.theme_type_variation = UiTheme.MICRO
		box.add_child(who_label)

	# V5.2d: who brings it, the same face the decision card carries, so one crisis
	# has one messenger in both places it is read. The narrator adds nothing.
	var face = SpeakerRow.build(_loader, ev, entry)
	if face != null:
		box.add_child(face)

	PanelKit.rich(box, Strings.row_summary("events", ev))

	for choice in ev.choices:
		_build_choice(box, ev, choice)


## One option: its button opens what it does, and Choose under that does it.
##
## The summary is printed on select rather than left in a tooltip, unlike
## projects_panel.gd's verb buttons: an event has a clock on it, and a consequence
## the player has to hover to discover is one they will not discover. But it is
## printed for the option being weighed, not for all three at once (R10).
func _build_choice(box: Control, ev, choice: Dictionary) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	var choice_id := String(choice.get("id", ""))
	var open := String(_picked.get(ev.id, "")) == choice_id

	var button := Button.new()
	# The default is named as such on its own button. Without it the one option that
	# will happen anyway looks like the other two, and the player cannot tell which
	# way silence falls -- which is the only thing the deadline is about.
	button.text = "%s%s" % [
		Strings.choice_label(ev.id, choice),
		tr("  (if you say nothing)") if bool(choice.get("is_default", false)) else "",
	]
	button.toggle_mode = true
	button.button_pressed = open
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(func():
		_picked[ev.id] = "" if open else choice_id
		_dirty = true)
	if _primary == null and not button.disabled:
		_primary = button
	block.add_child(button)

	if open:
		var detail := VBoxContainer.new()
		detail.add_theme_constant_override("separation", 4)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_child(detail)
		block.add_child(margin)
		PanelKit.rich(detail, Strings.choice_summary(ev.id, choice))
		var choose := PanelKit.sized(Button.new())
		choose.text = tr("Choose")
		choose.pressed.connect(func(): _on_choose(ev, choice))
		detail.add_child(choose)
		# The open option's Choose stands in for its own toggle only, so the first
		# entry on the desk keeps the primary verb (primary_action()'s build order).
		if _primary == button:
			_primary = choose

	box.add_child(block)


## U4's contract, projects_panel._on_act()'s shape exactly: the baseline is captured
## BEFORE the command, so the delta measures the month the choice was made against the
## month before it.
func _on_choose(ev, choice: Dictionary) -> void:
	var before := Trends.snapshot_now(_state)
	# answer() by id, not choose() on the head: with several entries on the desk
	# the button must answer ITS row -- a panel whose buttons resolved whatever
	# sat on top would be a panel that answered the wrong crisis on purpose.
	var record := Events.answer(_state, _loader, ev.id, String(choice.get("id", "")))
	if record.is_empty():
		return
	_picked.erase(ev.id)
	_dirty = true
	acted.emit(before, "%s: %s" % [Strings.row_name("events", ev), Strings.choice_label(ev.id, choice)])


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
			office = ns.head_of_government_title if ns.head_of_government_title != "" else tr("Head of government")
		"head_of_state":
			person_id = ns.head_of_state_person_id
			office = ns.head_of_state_title if ns.head_of_state_title != "" else tr("Head of state")
		"largest_party_leader":
			var party_list: Array = _loader.parties.get(ns.id, [])
			var largest := Government.largest_party_id(ns, party_list)
			for party in party_list:
				if party.id == largest:
					# Override first, the panel's own read (people_panel.gd):
					# a fired challenge deposed the authored leader, and this
					# line naming the deposed person is the resurrected-rival
					# class in a second surface.
					person_id = String(ns.party_leader_override.get(party.id, party.leader_person_id))
					office = tr("%s, leader") % party.party_name
					break
	var who: String = _loader.person_name(person_id)
	if who == "":
		return office
	return "%s — %s" % [who, office]


# --- The ledger --------------------------------------------------------------------

func _build_ledger(ns) -> void:
	PanelKit.heading(_body, tr("Your decisions"))
	if ns.event_history.is_empty():
		PanelKit.line(_body, tr("Nothing has come up yet."))
		return
	# V4.8c: the FEED band per category. Only the ledger is filtered -- the desk
	# above is where a decision is answered, so it shows every entry whatever the
	# settings say. Severity is the event's own (the record does not carry it).
	# A hidden row is COUNTED, never silent: a ledger that shrank with nothing
	# saying why reads as lost history.
	var hidden := 0
	for record in ns.event_history:
		var ev = Events.event_by_id(_loader, String(record.get("event_id", "")))
		var severity := int(ev.severity) if ev != null else EventsK.SEVERITY_MAX
		if not MessageSettings.allows(_messages, String(record.get("category", "")), severity, "feed"):
			hidden += 1
			continue
		_build_record(record)
	if hidden > 0:
		PanelKit.line(_body, tr_n("%d record hidden by your message settings.", "%d records hidden by your message settings.", hidden) % hidden)


func _build_record(record: Dictionary) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	# The place, for a sited event: the record carries the name because a past
	# act's site cannot be re-derived once the shares have moved (V2.6b1).
	var heading := Strings.record_event_name(record)
	var where := String(record.get("region_name", ""))
	if where != "":
		heading = "%s — %s" % [heading, where]

	PanelKit.line(block, "%04d-%02d  %s" % [
		int(record.get("year", 0)), int(record.get("month", 0)),
		heading,
	], PanelKit.Tone.PLAIN)

	var answer := Label.new()
	# A DEFAULT IS NOT A CHOICE AND THE LEDGER SAYS SO. Printing "Say nothing" beside a
	# month the player never opened this window would read as a decision they made, and
	# the one thing a ledger of forced choices has to be able to show is which of them
	# the clock made instead.
	if bool(record.get("defaulted", false)):
		answer.text = tr("No answer given — %s") % Strings.record_choice_label(record)
		answer.theme_type_variation = UiTheme.BAD_TEXT
	else:
		answer.text = Strings.record_choice_label(record)
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
	# V5.3-0 (b): the meaning rides the answer's hover -- the timeline reads down
	# the dates and the decisions, the consequence one point away.
	var what := _choice_summary(record)
	if what != "":
		answer.tooltip_text = PanelKit.TermText.plain(what)
		answer.mouse_filter = Control.MOUSE_FILTER_PASS

	_body.add_child(block)


## The authored sentence that sat above the button, looked up by id. Empty when the
## content no longer defines the event -- a save older than a content change is a legal
## state, and a ledger row that loses its footnote is better than one that cannot draw.
func _choice_summary(record: Dictionary) -> String:
	var ev = Events.event_by_id(_loader, String(record.get("event_id", "")))
	if ev == null:
		return ""
	var choice: Dictionary = ev.choice_by_id(String(record.get("choice_id", "")))
	return Strings.choice_summary(ev.id, choice)


## The control this panel exists to let the player press -- V2.1a's fold contract,
## declared here at V2.1b.
##
## The choices are rebuilt on every refresh, so this is the first one in build
## order rather than a member held from _ready(). Null when nothing is pending,
## which is most months -- the panel is then the ledger of what was decided.
func primary_action() -> Control:
	return _primary
