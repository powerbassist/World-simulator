extends PanelContainer

## The inbox -- V5.1-c3.1, U5a's card column (message_stack.gd) docked right as
## the BUREAU board drew it, behind the same calls: push(), set_body(),
## dismiss(), card_count(), clear() and the three signals. The writers (main.gd,
## world_news.gd, industry_news.gd, assembly_news.gd) went in without an edit
## but the handle's name.
##
## **Three lanes, by what a row asks of the player.** DECISIONS holds a row with
## answers or one its pusher protects (the term-start programme); a decision is
## never evicted -- the desk is bounded by the simulation, not by this column,
## and an evicted question read as "dismissed" would restart a held clock.
## REQUESTS is V5.2's audiences (C9: their own lane, not the desk's slots); it
## shows its empty state until the request register exists. NOTES holds the rest
## and keeps the newest NOTES_MAX, the oldest going first: news the player has
## not read is worth more than news that has sat there.
##
## The lanes scroll inside the dock, so a column of tall rows can no longer run
## off the bottom of the screen (someday: "the overlay message column has no
## bound", V5.1-0c). Newest first in every lane.
##
## **A note is grouped and folded** (V5.2 b+, R13 and R12: gate b's "too much
## clutter in the notes" and "too verbose ... tied into a bubble"). A note pushed
## again, the same title and the same body, joins the one in the lane: the count
## goes in the title, so six identical leaks are one row. A new body is new news (a
## tally, a default, a second person's leak) and keeps its own row. And a note over
## FOLD_MIN characters shows the whole sentences that fit, the rest behind More,
## which opens it in place -- a click on the card itself already goes to
## Dispatches, and the body's TermText takes the hover for its glossary plates, so
## neither could be the bubble. A short note is never folded: a division or a
## tally is data, not prose; and a glossary mark is never folded away.
##
## Holds no game state. A row is a title, a body and an id -- whoever pushes it
## owns what it means.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Motion = preload("res://src/ui/motion.gd")
const Grade = preload("res://src/ui/grade.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")

signal card_dismissed(id: String)
signal card_activated(id: String)
## V2.9: a decision row's choice buttons. Index is the action's position in the
## array push() was given; the consumer owns what answering means.
signal card_action(id: String, index: int)
## V5.1-c3.2: the inbox came over an open tab (true) or went back (false).
signal slid(shown: bool)

## The board's dock, beside the 1240 px workspace in the 1920 reference.
const WIDTH := 440
const DECISIONS := "decisions"
const REQUESTS := "requests"
const NOTES := "notes"
const LANES := [DECISIONS, REQUESTS, NOTES]
const NOTES_MAX := 40
## A note longer than this folds; two sentences of ordinary news fit under it.
const FOLD_MIN := 160
## What a folded note ends on, so the player sees there is more.
const FOLD_MARK := " …"

var _rows := {}      # lane -> VBoxContainer holding its rows
var _empty := {}     # lane -> the Label it shows with no row
var _cards := {}     # id -> PanelContainer
var _bodies := {}    # id -> Label, so a body can be rewritten in place
var _lane_of := {}   # id -> lane
var _notes := {}     # id -> {title, body, head, count, open, more}: a NOTES row's group and fold
var _next_id := 0
var _slid := false


## Built in _init, not _ready: U5a's column worked before it was in a tree (the
## grade test pushes into one that never enters it), and the lanes are plain
## structure that needs no theme to exist.
func _init() -> void:
	theme_type_variation = UiTheme.PLATE
	custom_minimum_size = Vector2(WIDTH, 0)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	var title := Label.new()
	title.text = tr("INBOX")
	title.theme_type_variation = UiTheme.HEADING
	column.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var lanes := VBoxContainer.new()
	lanes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lanes.add_theme_constant_override("separation", 10)
	scroll.add_child(lanes)

	var headings := {DECISIONS: tr("DECISIONS"), REQUESTS: tr("REQUESTS"), NOTES: tr("NOTES")}
	var empties := {
		DECISIONS: tr("Nothing waits on your decision."),
		REQUESTS: tr("Nobody is asking for an audience."),
		NOTES: tr("No news yet."),
	}
	for lane in LANES:
		var heading := Label.new()
		heading.text = headings[lane]
		heading.theme_type_variation = UiTheme.MICRO
		lanes.add_child(heading)
		var empty := Label.new()
		empty.text = empties[lane]
		empty.theme_type_variation = UiTheme.CAPTION
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lanes.add_child(empty)
		_empty[lane] = empty
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 6)
		lanes.add_child(rows)
		_rows[lane] = rows


## Returns the row's id, so the caller can dismiss it later without having
## tracked it -- a resolved crisis should be able to take its own row away.
##
## `art`, when given (V4.4), is the event plate beside the title. `protect` puts
## a row without answers in DECISIONS (the term-start programme explains a live
## clock hold); `lane` names one outright (REQUESTS, for V5.2).
func push(title: String, body: String, actions: Array = [], art: Texture2D = null, protect: bool = false, lane: String = "") -> String:
	var id := "card_%d" % _next_id
	_next_id += 1
	if lane.is_empty():
		lane = DECISIONS if protect or not actions.is_empty() else NOTES
	if lane == NOTES and actions.is_empty():
		for other in _notes:
			if _notes[other]["title"] == title and _notes[other]["body"] == body:
				_group(other)
				return other

	var card := PanelContainer.new()
	card.theme_type_variation = UiTheme.PLATE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			card_activated.emit(id)
	)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	if art != null:
		var plate := TextureRect.new()
		plate.texture = art
		plate.custom_minimum_size = Vector2(32, 18)  # 16:9, the plate's own aspect
		plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		header.add_child(Grade.apply(plate))
	var title_label := Label.new()
	title_label.text = title.to_upper()
	title_label.theme_type_variation = UiTheme.HEADING
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close := Button.new()
	close.text = "X"
	close.theme_type_variation = UiTheme.SUBROW_BUTTON
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): dismiss(id))
	header.add_child(close)

	# V5.1-c. A rich line, so a term marked in the body opens its glossary plate;
	# it passes clicks through to the card as the Label did (term_text.gd).
	var body_label := PanelKit.rich(column, body)
	if lane == NOTES and actions.is_empty():
		_notes[id] = {"title": title, "body": body, "head": title_label, "count": 1, "open": false, "more": null}

	# V2.9: the answers, a decision answered where the news is. Stacked, one per
	# line, each wrapping: a row of unwrapped buttons widened U5a's column to the
	# longest label (~755 px in English, ~1075 in French: QA #45's fit take).
	if not actions.is_empty():
		var answers := VBoxContainer.new()
		answers.add_theme_constant_override("separation", 3)
		for i in range(actions.size()):
			var button := Button.new()
			button.text = String(actions[i]["label"])  # i18n: row-ok routed by the pusher
			button.theme_type_variation = UiTheme.SUBROW_BUTTON
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			# V5.2b: a request's refused answer stays, disabled, its reason on hover.
			button.disabled = bool(actions[i].get("disabled", false))
			button.tooltip_text = String(actions[i].get("tooltip", ""))
			var index := i
			button.pressed.connect(func():
				# main.gd slides the inbox back once no decision holds the clock:
				# a second one still holding keeps it out (QA on #54).
				card_action.emit(id, index)
			)
			answers.add_child(button)
		column.add_child(answers)

	var rows: VBoxContainer = _rows[lane]
	rows.add_child(card)
	rows.move_child(card, 0)
	# V4.9a. A row arrives rather than existing: a fade only, since the lane lays
	# it out. Clickable from its first frame -- the fade gates nothing.
	Motion.arrive(card)
	_cards[id] = card
	_bodies[id] = body_label
	_lane_of[id] = lane
	_empty[lane].hide()
	if _notes.has(id):
		_show_note(id)

	if lane == NOTES:
		var notes := rows.get_child_count()
		while notes > NOTES_MAX:
			dismiss(_id_of(rows.get_child(notes - 1)))
			notes -= 1
	return id


## Rewrites a live row's body in place. A standing row whose content ages --
## main.gd's "Your term" countdown -- must not be re-pushed to say so: that moves
## it. A gone id is a clean no-op.
func set_body(id: String, body: String) -> void:
	if _notes.has(id):
		_notes[id]["body"] = body
		_show_note(id)
	elif _bodies.has(id):
		_bodies[id].set_marked(body)


## A note pushed again: counted, and the row to the top of the lane, pulsed -- it
## is the newest news, as a fresh row would have been.
func _group(id: String) -> void:
	var note: Dictionary = _notes[id]
	note["count"] = int(note["count"]) + 1
	_rows[NOTES].move_child(_cards[id], 0)
	Motion.pulse(_cards[id])
	_show_note(id)


func _toggle(id: String) -> void:
	_notes[id]["open"] = not bool(_notes[id]["open"])
	_show_note(id)


## A note as it stands: its title with the count once grouped, its body folded
## unless opened, and More only where there is more to show.
func _show_note(id: String) -> void:
	var note: Dictionary = _notes[id]
	var full := String(note["body"])
	var folded := full if bool(note["open"]) else fold(full)
	var count := int(note["count"])
	(note["head"] as Label).text = String(note["title"]).to_upper() if count == 1 else "%s ×%d" % [String(note["title"]).to_upper(), count]
	_bodies[id].set_marked(folded)
	# Made the first time there is more to show: a short note carries no button.
	if note["more"] == null and folded != full:
		var more := Button.new()
		more.name = "More"  # i18n: ok a node name, found by tests
		more.theme_type_variation = UiTheme.SUBROW_BUTTON
		more.focus_mode = Control.FOCUS_NONE
		more.pressed.connect(func(): _toggle(id))
		_bodies[id].add_sibling(more)
		note["more"] = more
	if note["more"] != null:
		(note["more"] as Button).visible = bool(note["open"]) or folded != full
		(note["more"] as Button).text = tr("Less") if bool(note["open"]) else tr("More")


## A long body cut to the whole sentences that fit FOLD_MIN, then the fold mark;
## the body itself when it is short, is one sentence, or would hide a mark ([g=..]
## or [p=..]: rich prose escapes every other "[", so a "[" past the cut is one).
static func fold(text: String) -> String:
	if text.length() <= FOLD_MIN:
		return text
	var cut := -1
	for i in range(mini(text.length() - 1, FOLD_MIN)):
		if ".!?".contains(text[i]) and text[i + 1] == " ":
			cut = i + 1
	if cut < 0 or text.substr(cut).contains("["):
		return text
	return text.substr(0, cut) + FOLD_MARK


func dismiss(id: String) -> void:
	if not _cards.has(id):
		return
	var card: Control = _cards[id]
	var lane: String = _lane_of[id]
	_cards.erase(id)
	_bodies.erase(id)
	_lane_of.erase(id)
	_notes.erase(id)
	_rows[lane].remove_child(card)
	card.queue_free()
	_empty[lane].visible = _rows[lane].get_child_count() == 0
	card_dismissed.emit(id)


## V5.1-d1b3: the card a hold is about, to the top of its lane and pulsed -- the
## inbox may already be up, and then nothing else on screen moves when the clock
## stops.
func raise_card(id: String) -> void:
	if not _cards.has(id):
		return
	_rows[_lane_of[id]].move_child(_cards[id], 0)
	Motion.pulse(_cards[id])


## V5.1-c3.2, the author's call 4: a decision that holds the clock while a tab
## is open slides the inbox over the strip of map beside it. On the map it is
## already there, and this does nothing.
func slide_in() -> void:
	if visible:
		return
	show()
	Motion.arrive(self)
	_slid = true
	slid.emit(true)


func slide_out() -> void:
	if not _slid:
		return
	_slid = false
	hide()
	slid.emit(false)


## The sidebar's Inbox entry.
func toggle_slide() -> void:
	if _slid:
		slide_out()
	else:
		slide_in()


func is_slid() -> bool:
	return _slid


## On the map the inbox is furniture; over a tab it is slid in or away. The map
## takes it back from a slide. V5.1-d1a (G1, the play gate: "the inbox disapear as
## soon as i click something on the left panel"): leaving the map no longer puts
## it away -- the inbox the player had in front of them rides over the tab, from
## tab to tab, until they put it away or answer what held it; once away it stays
## away until the map has it back. A scene does not carry it (`carry` false): the
## inbox goes away under a scene, as it always did.
func dock_on_map(on_map: bool, carry := true) -> void:
	if on_map or not carry:
		if _slid:
			_slid = false
			slid.emit(false)
		visible = on_map
	elif visible and not _slid:
		_slid = true
		slid.emit(true)


func card_count() -> int:
	return _cards.size()


## The lane a live row sits in, or "" for a gone id.
func lane_of(id: String) -> String:
	return String(_lane_of.get(id, ""))


func lane_count(lane: String) -> int:
	return _rows[lane].get_child_count()


func clear() -> void:
	for id in _cards.keys():
		dismiss(id)


func _id_of(card: Control) -> String:
	for id in _cards.keys():
		if _cards[id] == card:
			return String(id)
	return ""
