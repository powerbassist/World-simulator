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
const VerbBlock = preload("res://src/ui/verb_block.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const TermText = preload("res://src/ui/term_text.gd")
const Calendar = preload("res://src/sim/calendar.gd")

## The picked key of the finance bill, whose queue entry has no law id.
const FINANCE := "finance"  # i18n: ok a key

var places: Array = []
var _row: HBoxContainer
var _state
var _loader
var _find_law: Callable
## The bill a right click picked (its law id, FINANCE for the finance bill), "" for none: its verbs dock under the
## places and follow the bill, not its place (a close promotes the queue; a move reorders it).
var _picked := ""
var _verbs: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	# The Bills second pass (G3-14): the paper is always on screen, empty places included, so the
	# rule is learnt before the first bill rather than after a refused press.
	# G3 S5 (Bills = C): one slim line, the heading and the four places side by side; the rule
	# is the heading's hover, and each place's own.
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	add_child(_row)
	var head: Control = PanelKit.heading(_row, tr("Order paper"))
	head.tooltip_text = tr("One law goes to the Assembly each month.")
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_verbs = VBoxContainer.new()
	VerbBlock.tag(_verbs)
	add_child(_verbs)


## `find_law` is the host's lookup of a law by id (a composed draft lives on the register, not
## the loader). Rebuilt from the state each time: the paper has no state of its own.
func refresh(state, loader, find_law: Callable) -> void:
	if state != _state:
		_picked = ""  # another game (a load): its queue is not the one the bill was picked in
	# The tab's refresh rebuilds the block; a verb the keyboard was on is lit again on the rebuilt one.
	var focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var relight := VerbBlock.key_of(focus) if focus is Button and _verbs.is_ancestor_of(focus) else ""
	_state = state
	_loader = loader
	_find_law = find_law
	for child in _row.get_children():
		if child is PanelContainer:  # the places; the heading stays
			_row.remove_child(child)
			child.queue_free()
	places.clear()
	var ns = state.player()
	_place(-1, _tabled_title(state, ns), _date_text(_slot_date(state, ns)), _name_of(ns.tabled_bill), false)
	for i in BillQueue.SIZE:
		var entry: Dictionary = ns.bill_queue[i] if i < ns.bill_queue.size() else {}
		var held := not entry.is_empty()
		# G3 S5: one slim line, so the month is short ("2 · FEB") and the day bare ("28 Feb").
		_place(i, "%d · %s" % [i + 2, DateText.month(int(BillVerbs.division(state, i)["month"])).to_upper()], _date_text(BillVerbs.division(state, i)),
			_name_of(entry) if held else "", held)
	_build_verbs(ns)
	if relight != "":
		VerbBlock.refocus(self, relight)


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
	return "1 · %s" % DateText.month(int(ns.tabled_bill.get("vote_month", state.month))).to_upper()


## The day this month's slot divides: the tabled bill's own, or the month's last day.
func _slot_date(state, ns) -> Dictionary:
	if ns.tabled_bill.is_empty():
		return {"year": int(state.year), "month": int(state.month), "day": Calendar.days_in_month(int(state.year), int(state.month))}
	return {"year": int(ns.tabled_bill.get("vote_year", state.year)), "month": int(ns.tabled_bill.get("vote_month", state.month)),
		"day": int(ns.tabled_bill.get("vote_day", 1))}


static func _date_text(d: Dictionary) -> String:
	return DateText.day_month(int(d["day"]), int(d["month"]))


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


## The picked bill's place in the queue, -1 when none is picked or it left the queue.
func picked_index() -> int:
	return _index_of(_picked)


func _index_of(key: String) -> int:
	if key == "" or _state == null:
		return -1
	var queue: Array = _state.player().bill_queue
	for i in queue.size():
		if _key_of(queue[i]) == key:
			return i
	return -1


static func _key_of(entry: Dictionary) -> String:
	var id := String(entry.get("law_id", ""))
	return id if id != "" else FINANCE


## A verb's press finds its bill's place at the press, never the place it was built at.
func _move_by(key: String, step: int) -> void:
	var i := _index_of(key)
	if i >= 0:
		_move(i, i + step)


## The rework pass's C: a right click on a queued place picks it, docks its verbs under the four places and lights
## them (no plate).
func _menu(i: int) -> void:
	var queue: Array = _state.player().bill_queue
	_picked = _key_of(queue[i]) if i >= 0 and i < queue.size() else ""
	# A mouse gesture: a verb the keyboard was on is let go, not carried onto the new bill's block by the relight.
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and _verbs.is_ancestor_of(focus):
		focus.release_focus()
	refresh(_state, _loader, _find_law)
	VerbBlock.light(self)


## The picked place's verbs, each down one with its reason in words under the row (never only a tooltip).
func _build_verbs(ns) -> void:
	for child in _verbs.get_children():
		_verbs.remove_child(child)
		child.queue_free()
	var n: int = ns.bill_queue.size()
	var i := _index_of(_picked)
	if i < 0:
		_picked = ""  # it left the queue (tabled by a close, or taken out)
	_verbs.visible = i >= 0
	if i < 0:
		return
	var key := _picked
	var head := Label.new()
	head.theme_type_variation = UiTheme.MICRO
	head.text = tr("What you can do · %s") % _name_of(ns.bill_queue[i])
	_verbs.add_child(head)
	var row := PanelKit.buttons(_verbs)
	var reasons := PackedStringArray()
	for verb in [
			[tr("Move earlier"), i > 0, tr("It is already first in the queue."), _move_by.bind(key, -1)],
			[tr("Move later"), i < n - 1, tr("It is already last in the queue."), _move_by.bind(key, 1)],
			[tr("Take out of the queue"), true, "", _take_out.bind(key)]]:
		var press := PanelKit.sized(Button.new())
		press.text = String(verb[0])
		press.disabled = not bool(verb[1])
		press.pressed.connect(verb[3])
		row.add_child(press)
		if press.disabled:
			reasons.append(String(verb[2]))
	if n == 1:
		reasons = PackedStringArray([tr("It is the only bill in the queue.")])  # one reason, not "first ... last"
	if not reasons.is_empty():
		PanelKit.plain_line(_verbs, " ".join(reasons))


func _take_out(key: String) -> void:
	var i := _index_of(key)
	if i >= 0 and BillQueue.remove(_state, i):
		_picked = ""
		changed.emit()
