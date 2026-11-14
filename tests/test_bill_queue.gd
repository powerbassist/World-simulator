extends SceneTree

## V5.3 e, PR 2: the queue of three (docs/design/finance-bill.md section 10; the author's
## call 2, the parent's rulings of 2026-11-14). One bill divides a month from the slot
## (ns.tabled_bill); ns.bill_queue holds up to three more in the player's order. The
## player's verbs write only the queue. At the close, right after the division, the head
## is TABLED through the tabling functions that already exist, so every check a tabling
## makes runs in the month the bill reaches the slot; a refused head is dropped, the
## player told why, and the next tried. The finance bill's rate rows are range-checked
## at tabling (the parent's ruling on #334's call 2).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Bills = preload("res://src/sim/bills.gd")
const Government = preload("res://src/sim/government.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const BillQueue = preload("res://src/sim/bill_queue.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")

const START_YEAR := 2026
const MANAGED := {"spending_pct_gdp": {"defence": -1.4}, "tax_rates_pct": {"vat": 3.0}}

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_add_holds_three_in_order_and_writes_nothing_else()
	_check_add_refuses_a_bill_already_queued_or_in_the_slot()
	_check_one_budget_text_at_a_time()
	_check_remove_and_move_reorder_the_queue()
	_check_promotion_tables_the_head_only()
	_check_a_refused_head_is_dropped_and_the_next_tabled()
	_check_a_refused_finance_head_is_told_with_its_id_and_deltas()
	_check_force_rides_in_the_entry()
	_check_a_forced_law_never_takes_the_slot_so_the_next_is_tried()
	_check_the_close_promotes_after_the_division_in_the_new_month()
	_check_an_autumn_birth_queued_in_september_passes_the_gate()
	_check_an_empty_queue_adds_nothing_to_the_close()
	_check_a_fallen_government_keeps_the_queue()
	_check_the_rate_rows_are_range_checked_at_tabling()
	_check_the_range_check_takes_a_panel_bound_exactly()
	_check_the_queue_survives_a_save()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("PASS tests/test_bill_queue.gd")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL " + f)
	quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _new_state(nation_id := "FRA", month := 1):
	var state = GameState.new_game(_loader, nation_id)
	state.year = START_YEAR
	state.month = month
	return state


## Ordinary open laws (no constitutional amendment, which a 49.3 refuses and which may
## take the referendum route), in the order the scan lists them.
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


func _check_add_holds_three_in_order_and_writes_nothing_else() -> void:
	var state = _new_state()
	var ns = state.player()
	var ids := _open_laws(state, 4)
	if ids.size() < 4:
		return
	for i in 3:
		var got := BillQueue.add(state, {"law_id": ids[i]})
		if not bool(got.get("queued", false)):
			_fail("add: the %dth law was refused: %s" % [i + 1, got])
	var full := BillQueue.add(state, {"law_id": ids[3]})
	if bool(full.get("queued", false)) or not bool(full.get("full", false)):
		_fail("add: a fourth bill was not refused as full: %s" % [full])
	var order := []
	for entry in ns.bill_queue:
		order.append(String(entry["law_id"]))
	if order != ids.slice(0, 3):
		_fail("add: the queue reads %s, not the order added %s" % [order, ids.slice(0, 3)])
	if not ns.tabled_bill.is_empty() or not ns.last_law_result.is_empty():
		_fail("add: queuing wrote the slot or a result: %s / %s" % [ns.tabled_bill, ns.last_law_result])


func _check_add_refuses_a_bill_already_queued_or_in_the_slot() -> void:
	var state = _new_state()
	var ids := _open_laws(state, 2)
	if ids.size() < 2:
		return
	Legislature.propose(state, _loader, Legislature.open_law(state, state.player(), _loader, ids[0]))
	var in_slot := BillQueue.add(state, {"law_id": ids[0]})
	if bool(in_slot.get("queued", false)) or not bool(in_slot.get("already_queued", false)):
		_fail("add: the law in the slot was queued again: %s" % [in_slot])
	BillQueue.add(state, {"law_id": ids[1]})
	var twice := BillQueue.add(state, {"law_id": ids[1]})
	if bool(twice.get("queued", false)) or not bool(twice.get("already_queued", false)):
		_fail("add: a law already queued was queued twice: %s" % [twice])


func _check_one_budget_text_at_a_time() -> void:
	var state = _new_state()
	var first := BillQueue.add(state, {"finance": MANAGED})
	var second := BillQueue.add(state, {"finance": {"tax_rates_pct": {"income": 1.0}}})
	if not bool(first.get("queued", false)) or bool(second.get("queued", false)) or not bool(second.get("finance_queued", false)):
		_fail("add: a second finance bill was queued beside the first: %s / %s" % [first, second])
	var direct := FinanceBill.table(state, _loader, {"tax_rates_pct": {"income": 1.0}})
	if bool(direct.get("tabled", false)) or not bool(direct.get("finance_queued", false)) or not state.player().tabled_bill.is_empty():
		_fail("table: a finance bill was tabled beside the queued one: %s" % [direct])
	var tabled = _new_state()
	FinanceBill.table(tabled, _loader, MANAGED)
	var behind := BillQueue.add(tabled, {"finance": {"tax_rates_pct": {"income": 1.0}}})
	if bool(behind.get("queued", false)) or not bool(behind.get("finance_queued", false)):
		_fail("add: a finance bill was queued behind a tabled one: %s" % [behind])


func _check_remove_and_move_reorder_the_queue() -> void:
	var state = _new_state()
	var ns = state.player()
	var ids := _open_laws(state, 3)
	if ids.size() < 3:
		return
	for id in ids:
		BillQueue.add(state, {"law_id": id})
	if not BillQueue.move(state, 2, 0):
		_fail("move: a move inside the queue was refused")
	var order := []
	for entry in ns.bill_queue:
		order.append(String(entry["law_id"]))
	if order != [ids[2], ids[0], ids[1]]:
		_fail("move: 2 to 0 reads %s" % [order])
	if not BillQueue.remove(state, 1) or ns.bill_queue.size() != 2 or String(ns.bill_queue[0]["law_id"]) != ids[2] \
			or String(ns.bill_queue[1]["law_id"]) != ids[1]:
		_fail("remove: removing the second left %s" % [ns.bill_queue])
	if BillQueue.remove(state, 5) or BillQueue.move(state, 0, 2) or BillQueue.move(state, -1, 0):
		_fail("remove/move: an index outside the queue was accepted")
	if ns.bill_queue.size() != 2:
		_fail("remove/move: a refused verb changed the queue: %s" % [ns.bill_queue])


func _check_promotion_tables_the_head_only() -> void:
	var state = _new_state()
	var ns = state.player()
	var ids := _open_laws(state, 2)
	if ids.size() < 2:
		return
	BillQueue.add(state, {"law_id": ids[0]})
	BillQueue.add(state, {"law_id": ids[1]})
	var out := BillQueue.promote(state, _loader)
	if String(ns.tabled_bill.get("law_id", "")) != ids[0]:
		_fail("promote: the head was not tabled: %s" % [ns.tabled_bill])
	if ns.bill_queue.size() != 1 or String(ns.bill_queue[0]["law_id"]) != ids[1]:
		_fail("promote: the queue behind the slot reads %s" % [ns.bill_queue])
	if out.size() != 1 or not bool(out[0].get("tabled", false)):
		_fail("promote: the report reads %s, not the one tabling" % [out])
	if not BillQueue.promote(state, _loader).is_empty() or ns.bill_queue.size() != 1:
		_fail("promote: a second bill was promoted into a full slot")


func _check_a_refused_head_is_dropped_and_the_next_tabled() -> void:
	var state = _new_state()
	var ns = state.player()
	var ids := _open_laws(state, 1)
	if ids.is_empty():
		return
	ns.bill_queue = [{"law_id": "no_such_law"}, {"law_id": ids[0]}]
	var out := BillQueue.promote(state, _loader)
	if String(ns.tabled_bill.get("law_id", "")) != ids[0] or not ns.bill_queue.is_empty():
		_fail("refused head: the next was not tabled: slot %s, queue %s" % [ns.tabled_bill, ns.bill_queue])
	if out.size() != 2 or not bool(out[0].get("refused", false)) or not bool(out[0].get("unavailable", false)):
		_fail("refused head: the report does not name the refusal first: %s" % [out])
	if String(ns.last_law_result.get("law_id", "")) != "no_such_law" or not bool(ns.last_law_result.get("refused", false)):
		_fail("refused head: the refusal was not written as any refusal is: %s" % [ns.last_law_result])


func _check_a_refused_finance_head_is_told_with_its_id_and_deltas() -> void:
	var state = _new_state()
	var ns = state.player()
	var past := {"tax_rates_pct": {"vat": 25.0}}  # France's 20 + 25 = 45, past VAT's 40
	ns.bill_queue = [{"finance": past}]
	var out := BillQueue.promote(state, _loader)
	var told: Dictionary = out[0] if out.size() == 1 else {}
	if not bool(told.get("refused", false)) or not bool(told.get("range", false)) or not bool(told.get("finance", false)):
		_fail("finance head: the refusal does not name the range: %s" % [out])
	if String(told.get("law_id", "")) != FinanceBillLaw.id_for(state):
		_fail("finance head: the refusal carries no finance id: %s" % [told])
	if (told.get("finance_bill", {}) as Dictionary) != past or ns.last_law_result != told:
		_fail("finance head: the refused bill's deltas were not kept on the result: %s" % [ns.last_law_result])
	if not ns.tabled_bill.is_empty() or not ns.bill_queue.is_empty():
		_fail("finance head: a refused bill reached the slot or stayed queued")


func _check_force_rides_in_the_entry() -> void:
	var state = _new_state()
	var ns = state.player()
	ns.bill_queue = [{"finance": MANAGED, "force": true}]
	BillQueue.promote(state, _loader)
	if not bool(ns.tabled_bill.get("forced", false)):
		_fail("force: a forced finance entry was tabled without its 49.3: %s" % [ns.tabled_bill])
	var deu = _new_state("DEU")
	var dns = deu.player()
	var ids := _open_laws(deu, 1)
	if ids.is_empty():
		return
	dns.bill_queue = [{"finance": MANAGED, "force": true}, {"law_id": ids[0], "force": true}, {"law_id": ids[0]}]
	var out := BillQueue.promote(deu, _loader)
	if out.size() != 3 or not bool(out[0].get("refused", false)) or not bool(out[1].get("refused", false)):
		_fail("force: Germany forced a queued bill at promotion: %s" % [out])
	if String(dns.tabled_bill.get("law_id", "")) != ids[0]:
		_fail("force: after two refused forcings the plain entry was not tabled: %s" % [dns.tabled_bill])


func _check_a_forced_law_never_takes_the_slot_so_the_next_is_tried() -> void:
	var state = _new_state()
	var ns = state.player()
	var ids := _open_laws(state, 2)
	if ids.size() < 2:
		return
	ns.bill_queue = [{"law_id": ids[0], "force": true}, {"law_id": ids[1]}]
	var out := BillQueue.promote(state, _loader)
	if out.size() != 2 or not bool(out[0].get("forced", false)) or bool(out[0].get("refused", false)):
		_fail("forced law: the head was not adopted under 49.3: %s" % [out])
	if String(ns.tabled_bill.get("law_id", "")) != ids[1]:
		_fail("forced law: the slot a 49.3 never takes was not given to the next: %s" % [ns.tabled_bill])


## The close: the month's division first, then the head tabled in the NEW month (the
## caller has moved the month), so it divides at the close that ends that month.
func _check_the_close_promotes_after_the_division_in_the_new_month() -> void:
	var state = _new_state()
	var ns = state.player()
	var ids := _open_laws(state, 2)
	if ids.size() < 2:
		return
	Legislature.propose(state, _loader, Legislature.open_law(state, ns, _loader, ids[0]))
	BillQueue.add(state, {"law_id": ids[1]})
	state.month = 2
	var report := WorldMonth.tick_month(state, _loader)
	if String((report.get("division", {}) as Dictionary).get("law_id", "")) != ids[0]:
		_fail("close: the tabled bill did not divide first: %s" % [report.get("division")])
	if String(ns.tabled_bill.get("law_id", "")) != ids[1] or int(ns.tabled_bill.get("vote_month", 0)) != 2:
		_fail("close: the head was not tabled for the new month: %s" % [ns.tabled_bill])
	var queue: Array = report.get("queue", [])
	if queue.size() != 1 or not bool(queue[0].get("tabled", false)):
		_fail("close: the report does not carry the promotion: %s" % [queue])


## The autumn rule read at promotion (section 10): queued in September, the birth reaches
## the October slot and passes; one more month and it is refused and dropped.
func _check_an_autumn_birth_queued_in_september_passes_the_gate() -> void:
	for month in [10, 11]:
		var state = _new_state("FRA", 9)
		var ns = state.player()
		var row: Dictionary = (_loader.taxes["vat"] as Dictionary).duplicate(true)
		row["id"] = "test_levy"
		ns.tax_library["test_levy"] = row
		BillQueue.add(state, {"finance": {"create": {"test_levy": 8.0}}})
		state.month = month
		var report := WorldMonth.tick_month(state, _loader)
		var queue: Array = report.get("queue", [])
		var told: Dictionary = queue[0] if queue.size() == 1 else {}
		if month == 10 and (not bool(told.get("tabled", false)) or String(ns.tabled_bill.get("law_id", "")) != FinanceBillLaw.id_for(state)):
			_fail("autumn: the September queue did not reach the October slot: %s" % [told])
		if month == 11 and (not bool(told.get("autumn", false)) or not ns.tabled_bill.is_empty()):
			_fail("autumn: a birth reaching the November slot was not refused: %s" % [told])
		if not ns.bill_queue.is_empty():
			_fail("autumn: the entry stayed queued in month %d" % month)


func _check_an_empty_queue_adds_nothing_to_the_close() -> void:
	var state = _new_state()
	var ns = state.player()
	state.month = 2
	var report := WorldMonth.tick_month(state, _loader)
	if report.has("queue") or not ns.tabled_bill.is_empty() or not ns.bill_queue.is_empty():
		_fail("empty queue: the close wrote something: %s / %s" % [report.get("queue"), ns.tabled_bill])


## The parent's call 3 (a): a government that falls leaves the queue standing. A forced
## law at the head brings the government alone down on its censure; the entry behind it
## is still tabled, under the new state, by the same checks.
func _check_a_fallen_government_keeps_the_queue() -> void:
	var state = _new_state()
	var ns = state.player()
	var ids := _open_laws(state, 3)
	if ids.size() < 3:
		return
	var by_id := {}
	for party in _loader.parties["FRA"]:
		by_id[party.id] = party
	ns.coalition_party_ids = ["renouveau_civique"]
	ns.coalition_position = Government.position_of(ns.seats_by_party, ns.coalition_party_ids, by_id)
	ns.bill_queue = [{"law_id": ids[0], "force": true}, {"law_id": ids[1]}, {"law_id": ids[2]}]
	state.month = 2
	var report := WorldMonth.tick_month(state, _loader)
	var queue: Array = report.get("queue", [])
	if queue.is_empty() or not bool((queue[0].get("censure", {}) as Dictionary).get("carried", false)):
		_fail("fallen: the staged censure did not carry (stage broken): %s" % [queue])
		return
	if String(ns.tabled_bill.get("law_id", "")) != ids[1] or ns.bill_queue.size() != 1:
		_fail("fallen: the queue did not survive the government: slot %s, queue %s" % [ns.tabled_bill, ns.bill_queue])


func _check_the_rate_rows_are_range_checked_at_tabling() -> void:
	var cases := {
		"VAT past its ceiling": {"tax_rates_pct": {"vat": 20.5}},
		"income below zero": {"tax_rates_pct": {"income": -20.5}},
		"an amendment taking VAT past it": {"tax_rates_pct": {"vat": 21.0}},
	}
	for label in cases:
		var state = _new_state()
		var ns = state.player()
		if label.begins_with("an amendment"):
			FinanceBill.table(state, _loader, MANAGED)
		var before: Dictionary = ns.tabled_bill.duplicate(true)
		var got := FinanceBill.table(state, _loader, cases[label])
		if not bool(got.get("refused", false)) or not bool(got.get("range", false)):
			_fail("range: %s was tabled: %s" % [label, got])
		if ns.tabled_bill != before:
			_fail("range: a refused bill (%s) changed the slot" % label)
	var inside = _new_state()
	if not bool(FinanceBill.table(inside, _loader, {"tax_rates_pct": {"vat": 20.0, "income": -20.0}}).get("tabled", false)):
		_fail("range: a bill landing exactly on VAT's ceiling and income's floor was refused")


## The panel's own bounds, through from_pending: Germany's corporate rate 29.9 taken to
## exactly 70 and to exactly 0 is a delta that may land an ulp off; it must table.
func _check_the_range_check_takes_a_panel_bound_exactly() -> void:
	for target in [70.0, 0.0]:
		var state = _new_state("DEU")
		var bill := FinanceBill.from_pending(state.player(), {"tax_rates_pct": {"corporate": target}})
		var got := FinanceBill.table(state, _loader, bill)
		if not bool(got.get("tabled", false)):
			_fail("range: Germany's corporate tax to the panel bound %s was refused: %s" % [target, got])


func _check_the_queue_survives_a_save() -> void:
	var state = _new_state()
	var ids := _open_laws(state, 1)
	if ids.is_empty():
		return
	BillQueue.add(state, {"law_id": ids[0], "scale": 0.5, "referendum": false, "force": false})
	BillQueue.add(state, {"finance": MANAGED, "force": true})
	var data: Dictionary = state.to_dict()
	var copy = GameState.from_dict(JSON.parse_string(JSON.stringify(data)))
	var back: Array = copy.player().bill_queue
	if back.size() != 2 or String(back[0].get("law_id", "")) != ids[0] or not bool(back[1].get("force", false)):
		_fail("save: the queue did not survive: %s" % [back])
	if not is_equal_approx(float((back[1].get("finance", {}) as Dictionary).get("tax_rates_pct", {}).get("vat", 0.0)), 3.0):
		_fail("save: a queued finance bill's deltas did not survive: %s" % [back])
	var nations: Dictionary = data["nations"]
	for id in nations:
		(nations[id] as Dictionary).erase("bill_queue")
	var older = GameState.from_dict(JSON.parse_string(JSON.stringify(data)))
	if older == null or not older.player().bill_queue.is_empty():
		_fail("save: a save with no queue did not load as an empty one")
