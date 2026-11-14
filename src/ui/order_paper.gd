extends VBoxContainer

## The order paper -- V5.3 screen 4 (the author's call: one vote a month, plus a queue of three
## bills in an order the player picks). Four places across the top of the Bills tab: this
## month's slot (the bill that divides at the close) and the three queued behind it, each with
## the day it divides. Reads ns.tabled_bill and ns.bill_queue; the player's verbs are BillQueue's
## (remove, move), each followed by `changed` so the tab rebuilds. Nothing is checked against the
## Assembly until a bill reaches the slot (bill_queue.gd), so the paper offers no vote forecast.

signal changed

const PanelKit = preload("res://src/ui/panel_kit.gd")
const BillQueue = preload("res://src/sim/bill_queue.gd")
const BillVerbs = preload("res://src/ui/bill_verbs.gd")
const Bills = preload("res://src/sim/bills.gd")
const DateText = preload("res://src/ui/date_text.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const OrderSlot = preload("res://src/ui/order_slot.gd")
const Strings = preload("res://src/ui/strings.gd")
const VerbPlate = preload("res://src/ui/verb_plate.gd")
const TermText = preload("res://src/ui/term_text.gd")
const Calendar = preload("res://src/sim/calendar.gd")

var places: Array = []
var _row: HBoxContainer
var _state
var _loader
var _find_law: Callable


func _init() -> void:
	add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	PanelKit.heading(self, tr("Order paper"))
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	add_child(_row)


## `find_law` is the host's lookup of a law by id (a composed draft lives on the register, not
## the loader). Rebuilt from the state each time: the paper has no state of its own.
func refresh(state, loader, find_law: Callable) -> void:
	_state = state
	_loader = loader
	_find_law = find_law
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	places.clear()
	var ns = state.player()
	# Nothing before the Assembly and nothing queued: the queue is only behind a held slot
	# (#339), so four empty places would be a dead tile and prose on every visit. It shows the
	# moment a bill is tabled or queued.
	visible = not ns.tabled_bill.is_empty() or not ns.bill_queue.is_empty()
	_place(-1, _tabled_title(state, ns), _date_text(_slot_date(state, ns)), _name_of(ns.tabled_bill), false)
	for i in BillQueue.SIZE:
		var entry: Dictionary = ns.bill_queue[i] if i < ns.bill_queue.size() else {}
		var held := not entry.is_empty()
		_place(i, "%d · %s" % [i + 2, BillVerbs.month_name(state, i).to_upper()], _date_text(BillVerbs.division(state, i)),
			_name_of(entry) if held else "", held)


func _place(i: int, title: String, date: String, name_text: String, handle: bool) -> void:
	var place := OrderSlot.new()
	place.index = i if handle else -1
	place.drop_to = mini(i, _state.player().bill_queue.size() - 1) if i >= 0 else -1
	_row.add_child(place)
	place.show_place(title, date, name_text, _tip_of(i), handle)
	place.moved.connect(_move)
	place.menu_requested.connect(_menu)
	places.append(place)


func _tabled_title(state, ns) -> String:
	return "1 · %s" % DateText.month_long(int(ns.tabled_bill.get("vote_month", state.month))).to_upper()


## The day this month's slot divides: the tabled bill's own, or the month's last day.
func _slot_date(state, ns) -> Dictionary:
	if ns.tabled_bill.is_empty():
		return {"year": int(state.year), "month": int(state.month), "day": Calendar.days_in_month(int(state.year), int(state.month))}
	return {"year": int(ns.tabled_bill.get("vote_year", state.year)), "month": int(ns.tabled_bill.get("vote_month", state.month)),
		"day": int(ns.tabled_bill.get("vote_day", 1))}


static func _date_text(d: Dictionary) -> String:
	return "%s %s" % [DateText.weekday(int(d["day"]), int(d["month"]), int(d["year"])), DateText.day_month(int(d["day"]), int(d["month"]))]


## A bill's name, "" for an empty entry: a law's, or the finance bill's.
func _name_of(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	if entry.has("finance") and String(entry.get("law_id", "")) == "":
		return Strings.law_name(FinanceBillLaw.named(FinanceBillLaw.id_for(_state)))
	var id := String(entry.get("law_id", ""))
	return Strings.law_name(_find_law.call(id), id)


## The hover of place `i` (-1 the month's slot): the bill's summary, so every name explains itself.
func _tip_of(i: int) -> String:
	var ns = _state.player()
	var entry: Dictionary = ns.tabled_bill if i < 0 else (ns.bill_queue[i] if i < ns.bill_queue.size() else {})
	if entry.is_empty():
		return tr("Nothing before the Assembly.") if i < 0 else tr("A free place: a bill queued here is tabled when the one before it divides.")
	if entry.has("finance"):
		return tr("Every tax and spending change as one text, voted by the lower house.")
	var law = _find_law.call(String(entry.get("law_id", "")))
	return TermText.plain(Strings.law_summary(law)) if law != null else ""


func _move(from: int, to: int) -> void:
	if BillQueue.move(_state, from, to):
		changed.emit()


func _menu(i: int) -> void:
	var plate = VerbPlate.of(self)
	if plate == null:
		return
	var n: int = _state.player().bill_queue.size()
	plate.open(self, [
		{"text": tr("Move earlier"), "enabled": i > 0, "reason": tr("It is already first in the queue."), "call": _move.bind(i, i - 1)},
		{"text": tr("Move later"), "enabled": i < n - 1, "reason": tr("It is already last in the queue."), "call": _move.bind(i, i + 1)},
		{"text": tr("Take out of the queue"), "enabled": true, "call": _take_out.bind(i)},
	])


func _take_out(i: int) -> void:
	if BillQueue.remove(_state, i):
		changed.emit()
