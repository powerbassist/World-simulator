extends SceneTree

## Headless test: godot --headless --script res://tests/test_industry_closure.gd
## Non-zero exit on any failure.
##
## V5.3 a + b, docs/design/v5.3-ab.md 3.2 "A plant closure announced" (#251): a
## closure is a decision card on the Industry tab's In progress strip -- the firm,
## its city, the jobs and the month it lands -- with its answers SIDE BY SIDE, each
## its own strip (what it books, the jobs it keeps or loses, the blocs it moves) and
## its button; the answer taken if the player says nothing; the sector card's
## "Decision due" and the tab's pending mark. A buyer search shows its months left.
##
## The expected texts are built here from Closures.answers()' own figures, never by
## calling the panel's formatter, so a card that priced the wrong answer fails.

const Companies = preload("res://src/sim/companies.gd")
const Closures = preload("res://src/sim/closures.gd")
const Region = preload("res://src/core/region.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const Strings = preload("res://src/ui/strings.gd")
const Pending = preload("res://src/ui/pending.gd")
const Num = preload("res://src/ui/num.gd")
const IndustryProgress = preload("res://src/ui/industry_progress.gd")
const CK = preload("res://src/sim/closures_constants.gd")

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0
var _acted := 0
var _major
var _closure_id := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_panel = _main._companies_panel
			_panel.acted.connect(func(_b, _l): _acted += 1)
			_announce()
			_main._windows.open("companies")
		4:
			_check_card()
			_press(_with_meta("closure_answer", "buyer"))
		6:
			_check_searching()
			_announce_second()
		8:
			_press(_with_meta("closure_answer", "rescue"))
		10:
			_check_rescue()
			_finish()
	return false


## A closure on the first major, as Closures.tick_month() announces one.
func _announce() -> void:
	var state = _main._state
	var ns = state.player()
	_major = Companies.majors_of(_main._loader, ns.id)[0]
	Closures._announce(ns, _major, ns.companies[_major.id], 0.2, _main._loader.closure_rule, state.year * 12 + state.month)
	var open := Closures.open(ns)
	if open.size() != 1:
		_fail("premise: %d closures open after the announcement" % open.size())
		return
	_closure_id = String(open[0]["id"])
	_panel.mark_dirty()


func _check_card() -> void:
	var state = _main._state
	var ns = state.player()
	var loader = _main._loader
	if _panel._progress == null or not _panel._progress.is_visible_in_tree():
		_fail("card: the In progress strip is not on screen with a closure announced")
		return
	var row: Dictionary = Closures.open(ns)[0]
	var text := _text_under(_panel._progress)
	var city = Region.find_city(loader.regions.get(ns.id, []), String(row["city_id"]))
	if not text.contains(String(_major.company_name)) or (city != null and not text.contains(String(city.city_name))):
		_fail("card: '%s' names neither %s nor its city" % [text, _major.company_name])
	var answers: Array = Closures.answers(state, ns, loader, _closure_id)
	var parent: Node = null
	# QA's TAKE 2 on #277: the rescue's own texts -- its label, a cost (not a gain) for
	# its term, and the jobs kept for that term.
	for answer in answers:
		if String(answer["kind"]) != "rescue":
			continue
		var money: Array = IndustryProgress._closure_money(answer)
		var jobs_line := IndustryProgress._closure_jobs(answer)
		var months := Strings.tn("%d month", "%d months", CK.RESCUE_MONTHS) % CK.RESCUE_MONTHS
		if IndustryProgress._closure_label(loader, answer) != Strings.t("Rescue the plant") or float(money[1]) >= 0.0 \
				or not String(money[0]).contains(months) or not jobs_line.contains(months):
			_fail("card: the rescue reads '%s' / %s / '%s', not a labelled cost and jobs for its %s" % [
				IndustryProgress._closure_label(loader, answer), money, jobs_line, months])
	for answer in answers:
		var id := String(answer["id"])
		var button = _with_meta("closure_answer", id)
		if button == null:
			_fail("card: no '%s' answer on screen" % id)
			continue
		var money: Label = button.get_meta("money_label")
		var want := _money_of(answer)
		if money == null or money.text != want:
			_fail("card: '%s' reads '%s', its figures print '%s'" % [id, money.text if money != null else "<none>", want])
		# Side by side: every answer's column shares one flow.
		var column: Node = button.get_parent()
		if parent == null:
			parent = column.get_parent()
		elif column.get_parent() != parent:
			_fail("card: the answers are not side by side ('%s' in another row)" % id)
	if not (parent is HFlowContainer):
		_fail("card: the answers' row is not a flow (%s)" % parent)
	if not Pending.window_ids(state, loader).has("companies"):
		_fail("card: the Industry tab is not marked as waiting")
	var head = _with_meta("sector", String(_major.sector))
	if head == null or not _text_under(head.get_parent()).contains(_panel.tr("Decision due")):
		_fail("card: the %s card does not say a decision is due" % _major.sector)


## The money each answer books, from Closures.answers()' own fields.
func _money_of(answer: Dictionary) -> String:
	match String(answer["kind"]):
		"close":
			return EffectsStrip.cost_text(0.0)
		"buyer":
			# A small search in millions, never "0.0 bn" (QA's TAKE on #270): the first
			# major's search (Verdelis, ~0.023 bn) is one of them.
			var search := -float(answer["debt_eur_bn"])
			var shown := (Strings.t("%s m") % Num.fs(search * 1000.0, 0)) if absf(search) < 0.1 else EffectsStrip.money_text(search)
			if search < -0.0005 and shown.begins_with("0.0"):
				_fail("card: the buyer's search reads as free ('%s')" % shown)
			return Strings.t("%s now, %s more at a sale") % [shown, EffectsStrip.sum_text(-float(answer["sweetener_eur_bn"]))]
	var months := int(answer["months"])
	return Strings.tn("%s a year for %d month", "%s a year for %d months", months) % [
		EffectsStrip.sum_text(-float(answer["debt_eur_bn_per_year"])), months]


## A second closure, on the second major, to be rescued (#277).
func _announce_second() -> void:
	var state = _main._state
	var ns = state.player()
	var second = Companies.majors_of(_main._loader, ns.id)[1]
	Closures._announce(ns, second, ns.companies[second.id], 0.2, _main._loader.closure_rule, state.year * 12 + state.month)
	_panel.mark_dirty()


## A rescue running is seen (the parent's call on #277): its line on In progress with
## its months left, and its bill on the Budget's own line once the month books it.
func _check_rescue() -> void:
	var state = _main._state
	var ns = state.player()
	var rescues := Closures.rescues(ns)
	if rescues.size() != 1:
		_fail("rescue pressed: %d rescues running, expected 1" % rescues.size())
		return
	var line = _with_meta("rescue", String(rescues[0]["company_id"]))
	var left := int(rescues[0]["months_left"])
	if line == null or not (line as Label).text.contains(Strings.tn("%d month left", "%d months left", left) % left):
		_fail("rescue: no In progress line with its %d months left (%s)" % [left, line.text if line != null else "<none>"])
		return
	# Its money a year and its place (pass 1): the sim's figures, not the firm's name twice.
	var money := EffectsStrip.sum_text(-float(rescues[0]["rescue_eur_bn_per_year"]))
	var city = Region.find_city(_main._loader.regions.get(ns.id, []), String(rescues[0]["city_id"]))
	if not (line as Label).text.contains(money + " a year") or (city != null and not (line as Label).text.contains(String(city.city_name))):
		_fail("rescue: '%s' does not carry %s a year in %s" % [line.text, money, city.city_name if city != null else "?"])
	Closures.tick_month(state, _main._loader)
	var budget = _main._budget_panel
	budget.mark_dirty()
	budget._refresh()
	var cells: Array = budget._figures.get("rescues", [])
	if cells.is_empty() or String(cells[0]) == "—":
		_fail("budget: no plant rescue line with a rescue billed (%s)" % [cells])


func _check_searching() -> void:
	var ns = _main._state.player()
	var open := Closures.open(ns)
	if open.size() != 1 or String(open[0]["status"]) != Closures.SEARCHING:
		_fail("buyer pressed: the closure is not searching (%s)" % [open])
		return
	if _acted < 1:
		_fail("buyer pressed: the panel emitted no acted")
	if _with_meta("closure_answer", "buyer") != null:
		_fail("buyer pressed: the answers still stand")
	var months := int(open[0]["months_left"])
	if not _text_under(_panel._progress).contains(Strings.tn("%d month left", "%d months left", months) % months):
		_fail("searching: the row does not say the search's months left (%d)" % months)


# -- helpers --

func _with_meta(key: String, value: String):
	for node in _panel.find_children("*", "", true, false):
		if node.has_meta(key) and str(node.get_meta(key)) == value and (node as Control).is_visible_in_tree():
			return node
	return null


func _press(button) -> void:
	if button == null:
		_fail("frame %d: the control to press is not on screen" % _frame)
		return
	(button as Button).pressed.emit()


func _text_under(node: Node) -> String:
	var out := ""
	for label in node.find_children("*", "Label", true, false):
		out += (label as Label).text + " "
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_industry_closure: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
