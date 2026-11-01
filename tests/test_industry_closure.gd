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
			return Strings.t("%s now, %s more at a sale") % [
				EffectsStrip.money_text(-float(answer["debt_eur_bn"])), EffectsStrip.money_text(-float(answer["sweetener_eur_bn"]))]
	return Strings.t("%s a year") % EffectsStrip.money_text(-float(answer["debt_eur_bn_per_year"]))


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
