extends VBoxContainer

## The waiting requests, beside the Diary's month grid -- V5.3-0 (b2), the closing
## gate's R2 ("need new design more integrated into the agenda") and spec 3.4. The
## booking block under the grid (V5.2b's audience_booking.gd) is gone: a request is
## a card in this column -- a face, the name, the party, what they want, when they
## need an answer -- and it is booked ON the grid, where the days are:
##   - "Days" turns the grid to the request's first offered day and picks it, so the
##     day list carries "Book here: name" (the keyboard's path, and Book a day's);
##   - or the card is dragged onto one of its highlighted days.
## Delegate and Decline answer it from here, the inbox card's own verbs.
##
## Reads nothing of the sim: the rows are audience_driver's (`row_of`), and every
## verb goes out as a signal the driver performs (AGENTS.md rule 2).

signal focus_requested(request_id: String)
signal unfocus_requested(request_id: String)
signal delegate_requested(request_id: String)
signal decline_requested(request_id: String)
## An audience booked on the grid -- a day list's "Book here", or a card dropped on
## one of its days. audience_driver books it.
signal booked(request_id: String, date: Dictionary)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const PartyChip = preload("res://src/ui/party_chip.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")

## px at text size 100 %: the column beside the grid in the 1 240 px dock.
const WIDTH := 260.0
const FACE := Vector2(36, 48)
## The drag payload's key: a day cell takes the drop only of a request it offers.
const DRAG_KEY := "request"

var _focused := ""
## Where the president's word sits, under the grid (audience_driver's promise list).
var promise_slot := VBoxContainer.new()
## The month grid this column books on (beside()).
var _grid


func _init() -> void:
	name = "DiaryRequests"  # i18n: ok a node name, found by tests
	add_theme_constant_override("separation", 8)
	custom_minimum_size.x = WIDTH * UiTheme.text_scale()


## The grid and this column side by side, the grid taking the width.
func beside(grid: Control) -> HBoxContainer:
	_grid = grid
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(grid)
	row.add_child(self)
	return row


## A request's Days: the grid turns to the first day it offers that the Diary can
## take (else its first) and picks it, so the day list carries "Book here".
func show_days(dates: Array, state, loader) -> void:
	if dates.is_empty() or _grid == null:
		return
	# A Diary never drawn has no state yet; its next refresh brings the items and
	# keeps the page (show_items).
	if _grid._state == null:
		_grid.show_items(state, loader, [])
	var first: Dictionary = dates[0]
	for date in dates:
		if bool(date.get("free", false)):
			first = date
			break
	_grid.pick(int(first["year"]), int(first["month"]), int(first["day"]))


## The request whose days the grid shows, "" for none.
func request_id() -> String:
	return _focused


## `rows` are audience_driver.row_of()'s; `focused` the request being booked.
func show_requests(rows: Array, focused: String) -> void:
	_focused = focused
	for child in get_children():
		remove_child(child)
		child.queue_free()
	PanelKit.heading(self, Strings.t("Requests"))
	if rows.is_empty():
		PanelKit.line(self, Strings.t("Nobody is asking for an audience."))
		return
	for row in rows:
		add_child(_card(row))


func _card(row: Dictionary) -> Control:
	var id := String(row["id"])
	var card := PanelContainer.new()
	card.name = "Request_%s" % id
	card.theme_type_variation = UiTheme.PLATE
	card.set_drag_forwarding(func(_at: Vector2) -> Variant: return _drag(row), Callable(), Callable())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var face: Control = Portrait.framed_for(String(row.get("person_id", "")), FACE)
	face.custom_minimum_size = FACE
	head.add_child(face)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 2)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	var name_label := PanelKit.plain_line(who, String(row.get("person", "")), PanelKit.Tone.PLAIN)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = name_label.text
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	if row.has("party"):
		who.add_child(PartyChip.make(row["party"]))
	# The answer-by month as a chip, neutral as every deadline is (events_panel's
	# rule); the sentence and the price of a refusal ride its hover.
	var by := PanelKit.plain_line(who, Strings.t("Answer by %s") % String(row.get("by", "")))
	by.theme_type_variation = UiTheme.CAPTION
	by.tooltip_text = "%s\n%s" % [Strings.t("Unanswered, it counts as a refusal."),
		Strings.t("Declining: %s.") % String(row.get("price", ""))]
	by.mouse_filter = Control.MOUSE_FILTER_PASS

	var want := PanelKit.plain_line(box, String(row.get("wants", row.get("ask", ""))), PanelKit.Tone.PLAIN)
	want.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var verbs := PanelKit.buttons(box)
	var days := PanelKit.sized(Button.new())
	days.name = "Days"  # i18n: ok a node name, found by tests
	days.text = Strings.t("Days")
	days.toggle_mode = true
	days.button_pressed = id == _focused
	days.tooltip_text = Strings.t("Show the days they offer on the calendar, or drag this card onto one.")
	_answerable(days, row.get("book", {}))
	days.pressed.connect(func() -> void:
		if id == _focused:
			unfocus_requested.emit(id)
		else:
			focus_requested.emit(id))
	ActsOn.tag(days, [id])
	verbs.add_child(days)
	for verb in [[Strings.t("Delegate"), "delegate", delegate_requested], [Strings.t("Decline"), "decline", decline_requested]]:
		var b := PanelKit.sized(Button.new())
		b.name = String(verb[1])  # i18n: ok a node name, found by tests
		b.text = String(verb[0])
		_answerable(b, row.get(String(verb[1]), {}))
		var out: Signal = verb[2]
		b.pressed.connect(func() -> void: out.emit(id))
		verbs.add_child(b)
	return card


## The sim's refusal on a verb, as the inbox card shows it (request_lane._answer).
static func _answerable(button: Button, answer: Dictionary) -> void:
	if not bool(answer.get("ok", true)):
		button.disabled = true
		button.tooltip_text = String(answer.get("reason", ""))  # i18n: row-ok the sim's reason, worded where the sim's answer is read


## A card carried: its request id, and the person's name under the pointer. The
## grid turns to the request's days as the drag begins.
func _drag(row: Dictionary) -> Variant:
	if not bool((row.get("book", {}) as Dictionary).get("ok", true)):
		return null
	var preview := Label.new()
	preview.text = String(row.get("person", ""))
	preview.theme_type_variation = UiTheme.CAPTION
	set_drag_preview(preview)
	if String(row["id"]) != _focused:
		focus_requested.emit(String(row["id"]))
	return {DRAG_KEY: String(row["id"])}
