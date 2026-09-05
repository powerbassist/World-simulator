extends VBoxContainer

## The left-edge column of cards a minister or an adviser puts in front of the
## player -- U5a, and **furniture only this session**.
##
## The API is real and tested; nothing calls push(). That is a deliberate split
## rather than an unfinished job. The thing that fills this column is events,
## which docs/tiers/v1.md schedules last (V1.8) and argues at length should stay
## last: authored consequences are only legible once systemic ones already are.
## Building the surface now costs a file; wiring it to invented content now
## would cost the argument.
##
## What it does buy immediately: the layout is decided. When V1.8 arrives it
## adds calls, not a column, and nothing else on screen moves to make room.
##
## Holds no game state. A card is a title, a body and an id -- whoever pushes it
## owns what it means.

const UiTheme = preload("res://src/ui/ui_theme.gd")

signal card_dismissed(id: String)
signal card_activated(id: String)
## V2.9: a decision card's choice buttons. Index is the action's position in the
## array push() was given; the consumer owns what answering means.
signal card_action(id: String, index: int)

const CARD_WIDTH := 232

## Past this many the column would run into the portrait card at 1080p. The
## oldest is dropped rather than the newest refused: a message the player has
## not read yet is worth more than one that has been sitting there.
const MAX_CARDS := 6

var _cards := {}   # id -> PanelContainer
var _next_id := 0


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Returns the card's id, so the caller can dismiss it later without having
## tracked it -- a resolved crisis should be able to take its own card away.
func push(title: String, body: String, actions: Array = []) -> String:
	var id := "card_%d" % _next_id
	_next_id += 1

	var card := PanelContainer.new()
	card.theme_type_variation = UiTheme.PLATE
	card.custom_minimum_size.x = CARD_WIDTH
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			card_activated.emit(id)
	)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)

	var title_label := Label.new()
	title_label.text = title.to_upper()
	title_label.theme_type_variation = UiTheme.HEADING
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var close := Button.new()
	close.text = "X"
	close.theme_type_variation = UiTheme.SUBROW_BUTTON
	close.pressed.connect(func(): dismiss(id))
	header.add_child(close)

	var body_label := Label.new()
	body_label.text = body
	body_label.theme_type_variation = UiTheme.CAPTION
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body_label)

	# V2.9: the answer row. A decision answered where the news is, instead of a
	# route through Dispatches -- the playtest's F4, with the clock paused behind
	# it (main.gd's arrival branch). One button per choice, in the order given.
	if not actions.is_empty():
		var actions_box := HBoxContainer.new()
		actions_box.add_theme_constant_override("separation", 4)
		for i in range(actions.size()):
			var act_btn := Button.new()
			act_btn.text = String(actions[i]["label"])
			act_btn.theme_type_variation = UiTheme.SUBROW_BUTTON
			var index := i
			act_btn.pressed.connect(func(): card_action.emit(id, index))
			actions_box.add_child(act_btn)
		column.add_child(actions_box)

	add_child(card)
	_cards[id] = card

	while _cards.size() > MAX_CARDS:
		dismiss(_cards.keys()[0])

	return id


func dismiss(id: String) -> void:
	if not _cards.has(id):
		return
	var card: Control = _cards[id]
	_cards.erase(id)
	remove_child(card)
	card.queue_free()
	card_dismissed.emit(id)


func card_count() -> int:
	return _cards.size()


func clear() -> void:
	for id in _cards.keys():
		dismiss(id)
