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

var _rows := {}      # lane -> VBoxContainer holding its rows
var _empty := {}     # lane -> the Label it shows with no row
var _cards := {}     # id -> PanelContainer
var _bodies := {}    # id -> Label, so a body can be rewritten in place
var _lane_of := {}   # id -> lane
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
			var index := i
			button.pressed.connect(func():
				card_action.emit(id, index)
				# Answered: the tab it slid over is the player's again.
				slide_out()
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
	if _bodies.has(id):
		_bodies[id].set_marked(body)


func dismiss(id: String) -> void:
	if not _cards.has(id):
		return
	var card: Control = _cards[id]
	var lane: String = _lane_of[id]
	_cards.erase(id)
	_bodies.erase(id)
	_lane_of.erase(id)
	_rows[lane].remove_child(card)
	card.queue_free()
	_empty[lane].visible = _rows[lane].get_child_count() == 0
	card_dismissed.emit(id)


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


## On the map the inbox is furniture; over a tab it is away unless slid in. A
## move between the two ends a slide.
func dock_on_map(on_map: bool) -> void:
	if _slid:
		_slid = false
		slid.emit(false)
	visible = on_map


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
