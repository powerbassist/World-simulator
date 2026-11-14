extends SceneTree

## Headless test: godot --headless --script res://tests/test_bill_verbs.gd
## Non-zero exit on any failure.
##
## V5.3 screen 4, PR 1: the verb a law offers toward the month's one slot and the queue of
## three (src/ui/bill_verbs.gd, the state table). The sheet and the right click read the
## same table, so a verb is never a press the sim refuses, and every cell is pinned here:
##
##   slot empty, law not queued      Propose                                 (no Queue verb)
##   slot empty, law queued          Propose down (queued), Take out shown
##   slot held by THIS law           Propose down, nothing else
##   slot held by another bill       Propose down, Queue for <month> enabled
##   ... and the queue is full       Queue shown, disabled, says why
##   law queued                      Take out of the queue, naming its month
##
## A queue entry k divides on the last day of month + 1 + k (promotion tables it at the close
## that ends the month, and it divides at the close that ends the next).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Bills = preload("res://src/sim/bills.gd")
const BillQueue = preload("res://src/sim/bill_queue.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const BillVerbs = preload("res://src/ui/bill_verbs.gd")

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_an_empty_slot_offers_propose_alone()
	_check_a_held_slot_offers_the_queue_naming_the_month()
	_check_the_law_in_the_slot_offers_nothing_else()
	_check_a_finance_bill_in_the_slot_holds_it_too()
	_check_a_full_queue_says_why()
	_check_a_queued_law_offers_to_leave_it()
	_check_a_queued_law_with_an_empty_slot_cannot_be_proposed_twice()
	_check_the_division_dates_roll_over_the_year()
	_check_every_cell_is_a_press_the_sim_accepts()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("PASS tests/test_bill_verbs.gd")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL " + f)
	quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _new_state(month := 1, year := 2026):
	var state = GameState.new_game(_loader, "FRA")
	state.year = year
	state.month = month
	return state


func _open_laws(state, count: int) -> Array:
	var out := []
	for law in Legislature.available(state.player(), Bills.open(state, state.player(), _loader)):
		if not law.constitutional:
			out.append(law.id)
		if out.size() == count:
			break
	if out.size() < count:
		_fail("stage: fewer than %d open ordinary laws" % count)
	return out


func _table(state, law_id: String) -> void:
	var law = Legislature.open_law(state, state.player(), _loader, law_id)
	var got: Dictionary = Legislature.propose(state, _loader, law)
	if not bool(got.get("tabled", false)):
		_fail("stage: %s did not table: %s" % [law_id, got])


func _check_an_empty_slot_offers_propose_alone() -> void:
	var state = _new_state()
	var ids := _open_laws(state, 1)
	if ids.is_empty():
		return
	var cells := BillVerbs.cells(state, _loader, ids[0])
	if cells["propose"] != "":
		_fail("an empty slot: Propose is down with '%s'" % cells["propose"])
	if bool(cells["queue"]["shown"]) or bool(cells["unqueue"]["shown"]):
		_fail("an empty slot: a queue verb is shown (queue %s, take out %s); the queue is only behind a held slot" % [cells["queue"], cells["unqueue"]])


func _check_a_held_slot_offers_the_queue_naming_the_month() -> void:
	var state = _new_state()
	var ids := _open_laws(state, 3)
	if ids.size() < 3:
		return
	_table(state, ids[0])
	var cells := BillVerbs.cells(state, _loader, ids[1])
	if cells["propose"] == "":
		_fail("a held slot: Propose is not down for another law")
	if cells["slot"] != "held":
		_fail("a held slot reads '%s'" % cells["slot"])
	var queue: Dictionary = cells["queue"]
	if not bool(queue["shown"]) or not bool(queue["enabled"]) or String(queue["reason"]) != "":
		_fail("a held slot, room in the queue: Queue is not an enabled verb: %s" % [queue])
	# January's slot holds ids[0]; the first queued bill divides at the end of February.
	if not String(queue["text"]).contains("February"):
		_fail("Queue does not name the month it would divide in (January slot, empty queue): '%s'" % queue["text"])
	BillQueue.add(state, {"law_id": ids[1]})
	var after := BillVerbs.cells(state, _loader, ids[2])
	if not String(after["queue"]["text"]).contains("March"):
		_fail("with one queued, the next free slot is not March: '%s'" % after["queue"]["text"])


func _check_the_law_in_the_slot_offers_nothing_else() -> void:
	var state = _new_state()
	var ids := _open_laws(state, 1)
	if ids.is_empty():
		return
	_table(state, ids[0])
	var cells := BillVerbs.cells(state, _loader, ids[0])
	if cells["slot"] != "here" or cells["propose"] == "":
		_fail("the tabled law: slot '%s', Propose reason '%s'" % [cells["slot"], cells["propose"]])
	if bool(cells["queue"]["shown"]) or bool(cells["unqueue"]["shown"]):
		_fail("the tabled law offers a queue verb: %s / %s" % [cells["queue"], cells["unqueue"]])


func _check_a_finance_bill_in_the_slot_holds_it_too() -> void:
	var state = _new_state()
	var ids := _open_laws(state, 1)
	if ids.is_empty():
		return
	var got: Dictionary = FinanceBill.table(state, _loader, {"spending_pct_gdp": {"defence": -1.0}})
	if not bool(got.get("tabled", false)):
		_fail("stage: the finance bill did not table: %s" % [got])
		return
	var cells := BillVerbs.cells(state, _loader, ids[0])
	if cells["slot"] != "held" or cells["propose"] == "" or not bool(cells["queue"]["shown"]):
		_fail("a finance bill in the slot does not hold a law's Propose or offer the queue: %s" % [cells])
	if not String(cells["propose"]).contains("Finance bill"):
		_fail("the held-slot reason does not name the finance bill: '%s'" % cells["propose"])


func _check_a_full_queue_says_why() -> void:
	var state = _new_state()
	var ids := _open_laws(state, 5)
	if ids.size() < 5:
		return
	_table(state, ids[0])
	for i in [1, 2, 3]:
		BillQueue.add(state, {"law_id": ids[i]})
	var cells := BillVerbs.cells(state, _loader, ids[4])
	var queue: Dictionary = cells["queue"]
	if not bool(queue["shown"]) or bool(queue["enabled"]) or String(queue["reason"]) == "":
		_fail("a full queue: Queue is not a disabled verb with a reason: %s" % [queue])


func _check_a_queued_law_offers_to_leave_it() -> void:
	var state = _new_state()
	var ids := _open_laws(state, 3)
	if ids.size() < 3:
		return
	_table(state, ids[0])
	BillQueue.add(state, {"law_id": ids[1]})
	BillQueue.add(state, {"law_id": ids[2]})
	var cells := BillVerbs.cells(state, _loader, ids[2])
	if int(cells["queued"]) != 1:
		_fail("the second queued law reads position %s, not 1" % cells["queued"])
	if bool(cells["queue"]["shown"]) or not bool(cells["unqueue"]["shown"]):
		_fail("a queued law: Queue shown %s, Take out shown %s" % [cells["queue"]["shown"], cells["unqueue"]["shown"]])
	# ids[2] is the second queued: it divides at the end of March.
	if not String(cells["unqueue"]["text"]).contains("March"):
		_fail("Take out does not name the month: '%s'" % cells["unqueue"]["text"])
	if cells["propose"] == "":
		_fail("a queued law can still be proposed")


func _check_a_queued_law_with_an_empty_slot_cannot_be_proposed_twice() -> void:
	var state = _new_state()
	var ids := _open_laws(state, 1)
	if ids.is_empty():
		return
	BillQueue.add(state, {"law_id": ids[0]})
	var cells := BillVerbs.cells(state, _loader, ids[0])
	if cells["slot"] != "empty" or cells["propose"] == "" or not bool(cells["unqueue"]["shown"]):
		_fail("a law queued while the slot is empty must be taken out before it is proposed: %s" % [cells])


func _check_the_division_dates_roll_over_the_year() -> void:
	var state = _new_state(12, 2026)
	var first := BillVerbs.division(state, 0)
	if int(first["year"]) != 2027 or int(first["month"]) != 1 or int(first["day"]) != 31:
		_fail("the first queued bill from December divides on %s, not 31/01/2027" % [first])
	var third := BillVerbs.division(state, 2)
	if int(third["year"]) != 2027 or int(third["month"]) != 3 or int(third["day"]) != 31:
		_fail("the third queued bill from December divides on %s, not 31/03/2027" % [third])
	var leap := BillVerbs.division(_new_state(1, 2027), 0)  # February 2028 is a leap month
	if int(leap["day"]) != 28:
		_fail("February 2027 has 28 days, got %s" % [leap])


## The table must never offer a press the sim refuses: Queue enabled means BillQueue.add accepts,
## Take out shown means remove() takes it, Propose allowed means propose() tables it.
func _check_every_cell_is_a_press_the_sim_accepts() -> void:
	var state = _new_state()
	var ids := _open_laws(state, 4)
	if ids.size() < 4:
		return
	var cells := BillVerbs.cells(state, _loader, ids[0])
	if cells["propose"] == "":
		var law = Legislature.open_law(state, state.player(), _loader, ids[0])
		if not bool(Legislature.propose(state, _loader, law).get("tabled", false)):
			_fail("the table allows Propose on an empty slot and the sim refuses it")
	for i in [1, 2, 3]:
		var cell := BillVerbs.cells(state, _loader, ids[i])
		if bool(cell["queue"]["enabled"]):
			var got := BillQueue.add(state, {"law_id": ids[i]})
			if not bool(got.get("queued", false)):
				_fail("the table enables Queue for law %d and BillQueue.add refuses it: %s" % [i, got])
	var full := BillVerbs.cells(state, _loader, ids[0])
	if bool(full["queue"]["enabled"]):
		_fail("the table enables Queue for the tabled law")
