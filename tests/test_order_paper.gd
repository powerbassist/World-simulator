extends SceneTree

## Headless test: godot --headless --script res://tests/test_order_paper.gd
## Non-zero exit on any failure.
##
## V5.3 screen 4, PR 1: the order paper on the Bills tab, the Queue verb on a law's sheet and the
## right click. What can fail silently, pinned before the PR left the branch:
##   - THE PAPER READS THE SIM: four places (the month's slot, then the queue's three), each with
##     the bill's name and the day it divides; a free place says so.
##   - THE ORDER IS THE PLAYER'S: a drag (drag data and drop, since a headless run has no cursor)
##     and the plate's Move earlier / Move later / Take out are BillQueue commands, and the paper
##     redraws in the new order. The month's slot takes no drop and gives no drag.
##   - THE VERB IS NEVER A DEAD PRESS: while the slot is held a law's sheet offers Queue, a real
##     press queues it at the sheet's size grade, a full queue shows it down with its reason, a
##     queued law shows Take out, and the briefing's Go still finds an ENABLED control tagged
##     with the law (the dead end RF3 exists to catch).
##   - THE RIGHT CLICK is the same table: Propose (down, with the slot's reason), Queue, Open the
##     sheet, on the row's own button.

const BillQueue = preload("res://src/sim/bill_queue.gd")
const BillVerbs = preload("res://src/ui/bill_verbs.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Bills = preload("res://src/sim/bills.gd")
const Strings = preload("res://src/ui/strings.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")
const OrderSlot = preload("res://src/ui/order_slot.gd")
const VerbPlate = preload("res://src/ui/verb_plate.gd")
const Click = preload("res://tests/click.gd")
const DateText = preload("res://src/ui/date_text.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _ids: Array = []
var _queue_button: Button


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_main._windows.open("legislature")
		6:
			_check_the_paper_is_absent_at_rest()
			_stage()
			if not _paper().visible:
				_fail("the order paper is hidden with a bill in the slot")
			_check_the_paper_reads_the_sim()
			_check_the_slot_takes_no_drop()
			_check_a_free_place_means_to_the_end()
			_check_the_plate_moves_and_takes_out()
			_check_the_sheet_offers_queue_and_the_go_finds_it()
			_check_the_right_click_is_the_same_table()
			_set_queue([_ids[1], _ids[2]])
		8:
			# A real drag through the viewport (the engine's own pipeline, so set_drag_preview
			# and the drop run as they do under a mouse): queue place 1 onto queue place 2.
			Click.half(root, _paper().places[1], true)
		9:
			_drag_to(_paper().places[2], 0.5)
		10:
			_drag_to(_paper().places[2], 1.0)
		11:
			Click.half(root, _paper().places[2], false)
		14:
			_check_the_real_drag_reordered()
			_set_queue([_ids[1], _ids[2]])
			_select(_ids[3])
		16:
			_queue_button = _sheet_button("Queue")
			if _queue_button == null:
				_fail("no Queue button to press")
				_finish()
				return true
			Click.half(root, _queue_button, true)
		18:
			Click.half(root, _queue_button, false)
		22:
			_check_a_real_press_queued_it()
			_check_a_full_queue_shows_queue_down_with_its_reason()
			_check_a_queued_law_shows_take_out()
			_finish()
			return true
	return false


func _panel():
	return _main._law_panel


func _ns():
	return _main._state.player()


func _refresh() -> void:
	_panel().mark_dirty()
	_panel()._process(0.0)


## Open ordinary laws, the first one in the slot, the next two queued, a fourth for the sheet.
func _stage() -> void:
	var state = _main._state
	for law in Legislature.available(_ns(), Bills.open(state, _ns(), _main._loader)):
		if not law.constitutional:
			_ids.append(String(law.id))
		if _ids.size() == 5:
			break
	if _ids.size() < 5:
		_fail("stage: only %d open ordinary laws" % _ids.size())
		return
	var law = Legislature.open_law(state, _ns(), _main._loader, _ids[0])
	if not bool(Legislature.propose(state, _main._loader, law).get("tabled", false)):
		_fail("stage: the first law did not table")
	BillQueue.add(state, {"law_id": _ids[1]})
	BillQueue.add(state, {"law_id": _ids[2]})
	_refresh()


## The queue is exactly `ids`, in order; the tab redrawn.
func _set_queue(ids: Array) -> void:
	_ns().bill_queue.clear()
	for id in ids:
		BillQueue.add(_main._state, {"law_id": id})
	_refresh()


## A mouse motion toward `target`, `part` of the way from where the press landed.
func _drag_to(target: Control, part: float) -> void:
	var at: Vector2 = target.get_global_rect().get_center()
	var from: Vector2 = _paper().places[1].get_global_rect().get_center()
	var here := from.lerp(at, part)
	var move := InputEventMouseMotion.new()
	move.position = here
	move.global_position = here
	move.relative = Vector2(here.x - from.x, 0.0)
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(move, true)


func _name_of(id: String) -> String:
	return Strings.law_name(_panel()._find_law(id), id)


func _paper():
	return _panel()._paper


## At rest (no bill, no queue) the paper is not on the page: no empty places, no prose.
func _check_the_paper_is_absent_at_rest() -> void:
	_refresh()
	if _paper().visible:
		_fail("the order paper is shown with nothing in the slot and nothing queued")


func _check_the_paper_reads_the_sim() -> void:
	var places: Array = _paper().places
	if places.size() != 4:
		_fail("the paper has %d places, not the slot and the queue's three" % places.size())
		return
	var want := [_name_of(_ids[0]), _name_of(_ids[1]), _name_of(_ids[2]), "—"]
	for i in 4:
		if (places[i] as OrderSlot).place_name() != want[i]:
			_fail("place %d reads '%s', not '%s'" % [i + 1, places[i].place_name(), want[i]])
	var date: String = (places[1]._date as Label).text
	var due: Dictionary = BillVerbs.division(_main._state, 0)
	if not date.contains(DateText.day_month(int(due["day"]), int(due["month"]))):
		_fail("the first queued place says '%s', not the day it divides (%s)" % [date, due])
	if (places[1]._title as Label).text.find("2 ·") != 0:
		_fail("the first queued place is not numbered 2: '%s'" % places[1]._title.text)
	if places[3].tooltip_text == "":
		_fail("a free place has no hover saying what it is")
	if places[0].tooltip_text == "":
		_fail("a bill in the slot has no hover (every name explains itself, H1)")


func _check_the_real_drag_reordered() -> void:
	var order := []
	for entry in _ns().bill_queue:
		order.append(String(entry["law_id"]))
	if order != [_ids[2], _ids[1]]:
		_fail("a real drag of the first queued place onto the second left the queue %s, wanted %s" % [order, [_ids[2], _ids[1]]])
	if _paper().places[1].place_name() != _name_of(_ids[2]):
		_fail("the paper did not redraw in the new order: '%s'" % _paper().places[1].place_name())


## A drop on a free place means "to the end"; the data and the rule are the place's own, so the
## drop itself is called (no preview is made outside a drag).
func _check_a_free_place_means_to_the_end() -> void:
	_set_queue([_ids[1], _ids[2]])
	var data := {OrderSlot.DRAG_KEY: 0}
	var free = _paper().places[3]
	if not free._can_drop_data(Vector2.ZERO, data):
		_fail("a free place refuses a dropped bill while the queue has two")
		return
	free._drop_data(Vector2.ZERO, data)
	_panel()._process(0.0)
	if String(_ns().bill_queue[1]["law_id"]) != _ids[1]:
		_fail("a drop on the free place did not send the bill to the end: %s" % [_ns().bill_queue])


func _check_the_slot_takes_no_drop() -> void:
	var slot = _paper().places[0]
	if slot._get_drag_data(Vector2.ZERO) != null:
		_fail("the month's slot can be dragged")
	if slot._can_drop_data(Vector2.ZERO, {OrderSlot.DRAG_KEY: 0}):
		_fail("the month's slot takes a dropped bill (a bill reaches it by the close)")


func _check_the_plate_moves_and_takes_out() -> void:
	_set_queue([_ids[1], _ids[2]])
	_paper().places[1].menu_requested.emit(0)
	var plate = _plate()
	if plate == null or not plate.visible:
		_fail("a right click on a queued place opened no plate")
		return
	var items: Array = _plate_buttons(plate)
	if items.size() != 3 or not (items[0] as Button).disabled or (items[1] as Button).disabled:
		_fail("the plate for the first of two: %s (Move earlier should be down, Move later up)" % [items.map(func(b): return "%s/%s" % [b.text, b.disabled])])
		return
	items[1].pressed.emit()
	_panel()._process(0.0)
	if String(_ns().bill_queue[0]["law_id"]) != _ids[2]:
		_fail("Move later did not swap the queue: %s" % [_ns().bill_queue])
	if plate.visible:
		_fail("the plate stays open after a press")
	_paper().places[1].menu_requested.emit(0)
	_plate_buttons(_plate())[2].pressed.emit()  # Take out of the queue
	_panel()._process(0.0)
	if _ns().bill_queue.size() != 1 or String(_ns().bill_queue[0]["law_id"]) != _ids[1]:
		_fail("Take out did not remove the first place: %s" % [_ns().bill_queue])


func _plate():
	return VerbPlate.of(_panel())


func _plate_buttons(plate: Node) -> Array:
	return plate.find_children("*", "Button", true, false)


## The detail's button called `name` (a node name tests find them by).
func _sheet_button(button_name: String) -> Button:
	return _panel()._laws._detail.find_child(button_name, true, false) as Button


func _select(id: String) -> void:
	_panel()._laws.select(id)


func _check_the_sheet_offers_queue_and_the_go_finds_it() -> void:
	_select(_ids[3])
	var propose: Button = _sheet_button("Propose")
	if propose == null or not propose.disabled or not propose.tooltip_text.contains("before the Assembly"):
		_fail("Propose is not down with the slot's reason while a bill is in the slot")
	var queue: Button = _sheet_button("Queue")
	if queue == null or queue.disabled:
		_fail("a held slot with room: the sheet offers no enabled Queue")
		return
	if not queue.text.begins_with("Queue for "):
		_fail("Queue does not name the month: '%s'" % queue.text)
	var go := ActsOn.find(_panel(), _ids[3])
	if go == null:
		_fail("the briefing's Go finds no enabled control tagged with the law (a dead end)")


func _check_the_right_click_is_the_same_table() -> void:
	var row: Button = _panel()._laws._rows.get_children()[0].get_child(0)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	row.gui_input.emit(event)
	var plate = _plate()
	if plate == null or not plate.visible:
		_fail("a right click on a law's row opened no plate")
		return
	var texts: Array = _plate_buttons(plate).map(func(b): return b.text)
	if not texts.has("Propose") or not texts.has("Open the sheet") or not texts.any(func(t): return String(t).begins_with("Queue for ") or String(t).begins_with("Take out")):
		_fail("the plate offers %s; wanted Propose, a queue verb and Open the sheet" % [texts])
	var propose: Button = _plate_buttons(plate).filter(func(b): return b.text == "Propose")[0]
	if not propose.disabled or propose.tooltip_text == "":
		_fail("with a bill in the slot the plate's Propose is not down with a reason")
	plate.hide()


func _check_a_real_press_queued_it() -> void:
	var ids: Array = _ns().bill_queue.map(func(e): return String(e["law_id"]))
	if not ids.has(_ids[3]):
		_fail("a real press on Queue did not queue the law: the queue is %s" % [ids])
	elif float(_ns().bill_queue[ids.find(_ids[3])].get("scale", 0.0)) != 1.0:
		_fail("the queued entry has no size grade: %s" % [_ns().bill_queue])


func _check_a_full_queue_shows_queue_down_with_its_reason() -> void:
	if _ns().bill_queue.size() != BillQueue.SIZE:
		_fail("stage: the queue holds %d, not %d" % [_ns().bill_queue.size(), BillQueue.SIZE])
		return
	_select(_ids[4])
	var queue: Button = _sheet_button("Queue")
	if queue == null or not queue.disabled or queue.tooltip_text == "":
		_fail("a full queue: Queue is not shown down with its reason")
	elif queue.text.begins_with("Queue for "):
		_fail("a full queue names a month it has no place for: '%s'" % queue.text)


func _check_a_queued_law_shows_take_out() -> void:
	_select(_ids[1])
	var out: Button = _sheet_button("TakeOut")
	if out == null or out.disabled:
		_fail("a queued law's sheet has no Take out")
		return
	out.pressed.emit()
	_panel()._process(0.0)
	if BillVerbs.queued_at(_ns(), _ids[1]) >= 0:
		_fail("Take out left the law in the queue")
	var places: Array = _paper().places
	if (places[3] as OrderSlot).place_name() != "—" and _ns().bill_queue.size() < BillQueue.SIZE:
		_fail("the paper still shows a bill in the free place after a take out")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS tests/test_order_paper.gd")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	quit(1)
