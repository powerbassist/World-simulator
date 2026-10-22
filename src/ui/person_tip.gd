extends Control

## A person's card, shown where the UI prints their name -- V5.1-d1b2, G9 of the
## play gate: "i cant click any politician to get their card".
##
## The card is person_card.gd, V4.3's one surface for a person, until now shown only
## by the People panel's rows. A name marked [p=id]Name[/p] (term_text.gd) routes
## here: a hover shows the card while the pointer is on the name, a click pins it
## until Escape or a click away. It lives in the glossary layer (glossary_tip.gd),
## which already owns those two close rules, the layer above every screen, and the
## state the card reads. Holds no game state of its own.

const PersonCard = preload("res://src/ui/person_card.gd")

## Below and right of the name, as the People panel's hover card sits.
const OFFSET := Vector2(18, 12)
const EDGE := 8.0

var _card
var _state = null
var _loader = null
var _pinned := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PersonCard.new()
	add_child(_card)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	close()


func enter(person_id: String, anchor: Rect2) -> void:
	if not _pinned:
		_show(person_id, anchor)


func leave() -> void:
	if not _pinned:
		_card.hide_card()


func click(person_id: String, anchor: Rect2) -> void:
	_show(person_id, anchor)
	_pinned = _card.visible


func close() -> void:
	_pinned = false
	if _card != null:
		_card.hide_card()


func is_open() -> bool:
	return _card != null and _card.visible


func is_pinned() -> bool:
	return _pinned and is_open()


func _show(person_id: String, anchor: Rect2) -> void:
	if _state == null or _loader == null or _state.player() == null:
		return
	_card.show_for(person_id, _loader, _state.player(), Vector2.ZERO)
	var at := anchor.position + OFFSET
	var card_size: Vector2 = _card.get_combined_minimum_size()
	var room := get_viewport_rect().size
	at.x = minf(at.x, maxf(room.x - card_size.x - EDGE, EDGE))
	at.y = minf(at.y, maxf(room.y - card_size.y - EDGE, EDGE))
	_card.position = at
