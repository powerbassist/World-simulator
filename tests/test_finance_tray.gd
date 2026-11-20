extends SceneTree

## Headless test: godot --headless --script res://tests/test_finance_tray.gd
## Non-zero exit on any failure.
##
## The rework pass's Finances C ("tiroir des changements", the author's pick): the Books page's footer became a
## docked tray. With rows drafted it lists each change as a dumbbell on one axis (ring today, dot the draft), the
## change's money a year and a remove mark; says the deficit before and after and how the Assembly would divide;
## and carries ONE button, "Table the bill" (Review and Discard all are links). A remove takes one change out of
## the draft and leaves the others; Discard all empties it.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const FinancesPanel = preload("res://src/ui/finances_panel.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

var _failures: Array[String] = []
var _loader
var _state
var _panel
var _frame := 0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	Strings.set_language("en")
	_panel = FinancesPanel.new()
	root.add_child(_panel)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_panel.show()
			_panel.size = Vector2(1240, 820)
			_state = GameState.new_game(_loader, "FRA")
			_panel.setup(_state, _loader)
		3:
			var draft = _panel.shared_draft()
			draft.set_value(FinanceDraft.SPENDING, "health", draft.live(FinanceDraft.SPENDING, "health") + 1.5)
			draft.set_value(FinanceDraft.SPENDING, "education", draft.live(FinanceDraft.SPENDING, "education") - 0.5)
			draft.set_value(FinanceDraft.TAX, "vat", draft.live(FinanceDraft.TAX, "vat") + 2.0)
			_panel._on_structure_changed()
		6:
			_check_tray()
			_check_drop_every_kind()
			_press(_remove_mark("spending_pct_gdp:education"))
		9:
			var draft = _panel.shared_draft()
			if draft.count() != 2 or draft.is_moved(FinanceDraft.SPENDING, "education") or not draft.is_moved(FinanceDraft.TAX, "vat"):
				_fail("removing education left %d rows (education moved %s)" % [draft.count(), draft.is_moved(FinanceDraft.SPENDING, "education")])
			var chart = _changes_chart()
			if chart == null or chart.data().size() != 2:
				_fail("the tray did not redraw to two changes")
			_press(_panel._foot.find_child("Discard", true, false))
		11:
			if not _panel.shared_draft().is_clean() or _panel._foot.visible:
				_fail("Discard all left a draft or a visible tray")
			_finish()
	return false


func _check_tray() -> void:
	var draft = _panel.shared_draft()
	var foot = _panel._foot
	if not foot.is_visible_in_tree():
		_fail("no tray with three rows drafted")
		return
	var chart = _changes_chart()
	if chart == null:
		_fail("the tray draws no change chart")
		return
	var rows: Array = chart.data()
	if rows.size() != draft.count():
		_fail("the tray draws %d changes, the draft holds %d" % [rows.size(), draft.count()])
	for i in mini(rows.size(), draft.rows().size()):
		var want: Dictionary = draft.rows()[i]
		if absf(float(rows[i]["before"]) - float(want["live"])) > 1e-6 or absf(float(rows[i]["after"]) - float(want["draft"])) > 1e-6:
			_fail("change %d drawn %s -> %s, the draft says %s -> %s" % [i, rows[i]["before"], rows[i]["after"], want["live"], want["draft"]])
		var money: Label = foot.find_child("Money_" + String(rows[i]["id"]).replace(":", "_"), true, false)
		var gain: float = _panel._price.row_balance_bn(want)
		if money == null or money.text != EffectsStrip.money_text(gain):
			_fail("change %s's money reads '%s', priced %s" % [rows[i]["id"], money.text if money != null else "<none>", EffectsStrip.money_text(gain)])
		if _remove_mark(String(rows[i]["id"])) == null:
			_fail("change %s has no remove mark" % rows[i]["id"])
	# The deficit before and after, the whole bill's (FinancePrice.whole), in the sentence.
	var whole: Dictionary = _panel._price.whole(_loader, draft, false)
	var said: String = foot._text.text
	var deficit := "%s → %s" % [Num.f(float(whole["deficit_now_bn"]), 0), Num.f(float(whole["deficit_after_bn"]), 0)]
	if not said.contains(deficit):
		_fail("the tray does not run the deficit from now to after: '%s'" % said)
	# ONE button: Table the bill. Everything else in the tray is a link (flat).
	var loud := []
	for b in foot.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and not (b as Button).flat:
			loud.append(b)
	if loud.size() != 1 or (loud[0] as Button).text != Strings.t("Table the bill"):
		_fail("the tray's loud buttons: %s" % [loud.map(func(b) -> String: return (b as Button).text)])


## FinanceDraft.drop on each kind of change the tray can list: a birth, an abolition, the brackets.
func _check_drop_every_kind() -> void:
	var ns = _state.player()
	var draft = FinanceDraft.new()
	draft.setup(_state)
	var in_force := String(ns.tax_rates_pct.keys()[0])
	var outside := ""
	for kind in ns.tax_library:
		if not ns.tax_rates_pct.has(kind):
			outside = String(kind)
			break
	draft.toggle_abolish(in_force)
	draft.set_brackets(draft.live(FinanceDraft.BRACKETS, "") + 0.1)
	if outside != "":
		draft.set_create(outside, 1.0)
	draft.drop(FinanceDraft.ABOLISH, in_force)
	draft.drop(FinanceDraft.BRACKETS, "")
	if outside != "":
		draft.drop(FinanceDraft.TAX, outside)
		if draft.is_created(outside):
			_fail("a dropped birth is still a creation")
	if not draft.is_empty():
		_fail("dropping an abolition, the brackets and a birth left %d rows" % draft.count())
	# The staged draft is all percentages: the dumbbells share the one 0-25 scale.
	var chart = _changes_chart()
	if chart != null and chart._fixed != Vector2(0.0, 25.0):
		_fail("the tray's axis is %s, not the one 0-25 scale" % chart._fixed)


func _changes_chart():
	for node in _panel._foot.find_children("*", "", true, false):
		if node.has_meta("tray") and String(node.get_meta("tray")) == "changes":
			return node
	return null


func _remove_mark(row_id: String):
	for b in _panel._foot.find_children("*", "Button", true, false):
		if b.has_meta("drop") and String(b.get_meta("drop")) == row_id and (b as Control).is_visible_in_tree():
			return b
	return null


func _press(button) -> void:
	if button == null:
		_fail("frame %d: the control to press is not on screen" % _frame)
		return
	(button as Button).pressed.emit()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_finance_tray: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		quit(1)
