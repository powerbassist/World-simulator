extends SceneTree

## Headless test: godot --headless --script res://tests/test_finance_tray.gd
## Non-zero exit on any failure.
##
## G3 S4, Finances in C: the tray became the bill's RAIL beside the page. With rows drafted it walks the deficit as a
## waterfall (today, each change a signed step, the bill: the whole bill's figure at the end, a residual the rows
## miss as its own step), lists each change with who it is for or who pays, its money a year and a remove mark, says
## how the Assembly would divide (each number once); and carries ONE loud button, "Table the bill" (the sheet's act
## has the same name; Review and Discard all are links). A remove takes one change out and hands the focus back;
## Discard all empties the draft, moves alone too. A drag prices only the row it moves. With nothing drafted the
## rail stays, says so, and offers no verb.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const FinancesPanel = preload("res://src/ui/finances_panel.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const ControlStyle = preload("res://src/ui/control_style.gd")

var _failures: Array[String] = []
var _loader
var _state
var _panel
var _frame := 0
var _outside: Button


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
			# Five changes of three unit kinds: % of GDP and % (one shared 0-25 scale), EUR/l, the brackets.
			var draft = _panel.shared_draft()
			draft.set_value(FinanceDraft.SPENDING, "health", draft.live(FinanceDraft.SPENDING, "health") + 1.5)
			draft.set_value(FinanceDraft.SPENDING, "education", draft.live(FinanceDraft.SPENDING, "education") - 0.5)
			draft.set_value(FinanceDraft.TAX, "vat", draft.live(FinanceDraft.TAX, "vat") + 2.0)
			draft.set_value(FinanceDraft.TAX, "fuel_duty", draft.live(FinanceDraft.TAX, "fuel_duty") + 0.05)
			draft.set_brackets(draft.live(FinanceDraft.BRACKETS, "") + 0.1)
			_panel._on_structure_changed()
		6:
			_check_tray()
			_check_units()
			_check_each_number_once()
			_check_one_name()
			_check_drop_every_kind()
			_check_priced_once()
			_check_moves_only_discard()
			_press(_remove_mark("spending_pct_gdp:education"))
		9:
			var draft = _panel.shared_draft()
			if draft.count() != 4 or draft.is_moved(FinanceDraft.SPENDING, "education") or not draft.is_moved(FinanceDraft.TAX, "vat"):
				_fail("removing education left %d rows (education moved %s)" % [draft.count(), draft.is_moved(FinanceDraft.SPENDING, "education")])
			if _drawn().size() != 4:
				_fail("the tray did not redraw to four changes")
			var focus = _panel.get_viewport().gui_get_focus_owner()
			if focus == null or not _panel._foot.is_ancestor_of(focus):
				_fail("removing a change left the focus nowhere (%s)" % focus)
			_press(_panel._foot.find_child("Discard", true, false))
		11:
			if not _panel.shared_draft().is_clean() or _panel._foot._changes.visible or not _panel._foot._empty.visible:
				_fail("Discard all left a draft, the changes shown or no empty note")
			for b in _panel._foot.find_children("*", "Button", true, false):
				if (b as Button).is_visible_in_tree():
					_fail("the empty rail offers '%s'" % (b as Button).text)
			# QA on #429: the last change removed by its x hides the tray; a remove index left standing pulled the
			# focus onto the next draft's x, wherever it was, so a keyboard player's next Space removed it again.
			var draft = _panel.shared_draft()
			draft.set_value(FinanceDraft.SPENDING, "health", draft.live(FinanceDraft.SPENDING, "health") + 1.5)
			_panel._on_structure_changed()
		13:
			_press(_remove_mark("spending_pct_gdp:health"))
		15:
			if _panel._foot._changes.visible:
				_fail("removing the last change left the changes shown")
			_outside = Button.new()
			_outside.focus_mode = Control.FOCUS_ALL
			root.add_child(_outside)
			_outside.grab_focus()
			var draft = _panel.shared_draft()
			draft.set_value(FinanceDraft.TAX, "vat", draft.live(FinanceDraft.TAX, "vat") + 1.0)
			_panel._on_structure_changed()
		17:
			var focus = _panel.get_viewport().gui_get_focus_owner()
			if focus != _outside:
				_fail("a fresh draft after the last remove took the focus to %s" % (focus.name if focus != null else "nothing"))
			# Pass 2 T8 on #443: the last change removed while a share move stays: the focus goes to Discard all, never nowhere.
			var draft = _panel.shared_draft()
			draft.revert()
			draft.add_move("health", "hospitals", "primary_care", 0.01)
			draft.set_value(FinanceDraft.SPENDING, "health", draft.live(FinanceDraft.SPENDING, "health") + 1.5)
			_panel._on_structure_changed()
		19:
			_press(_remove_mark("spending_pct_gdp:health"))
		21:
			var focus = _panel.get_viewport().gui_get_focus_owner()
			var discard := _panel._foot.find_child("Discard", true, false) as Button
			if not _panel.shared_draft().has_moves() or not discard.is_visible_in_tree():
				_fail("premise: the share move or Discard all went with the last change")
			elif focus != discard:
				_fail("the last change removed with a share move left the focus on %s, not Discard all" % (focus.name if focus != null else "nothing"))
			_finish()
	return false


func _check_tray() -> void:
	var draft = _panel.shared_draft()
	var foot = _panel._foot
	if not foot.is_visible_in_tree():
		_fail("no tray with rows drafted")
		return
	var drawn := _drawn()
	if drawn.size() != draft.count():
		_fail("the rail lists %d changes, the draft holds %d" % [drawn.size(), draft.count()])
	var chart = foot._chart
	var steps := 0
	for want in draft.rows():
		var id := "%s:%s" % [want["channel"], want["key"]]
		if not drawn.has(id):
			_fail("change %s is not listed" % id)
			continue
		var money: Label = foot.find_child("Money_" + id.replace(":", "_"), true, false)
		var gain: float = _panel._price.row_balance_bn(want)
		if money == null or money.text != EffectsStrip.money_text(gain):
			_fail("change %s's money reads '%s', priced %s" % [id, money.text if money != null else "<none>", EffectsStrip.money_text(gain)])
		if _remove_mark(id) == null:
			_fail("change %s has no remove mark" % id)
		# Its step in the waterfall: the opposite of its gain (a gain narrows the deficit), signed.
		steps += 1
		if chart.figure(steps) != Num.fs(-gain, 1):
			_fail("change %s's step reads %s, its gain %s" % [id, chart.figure(steps), gain])
	# Today and the bill, the whole bill's (FinancePrice.whole), at the waterfall's two ends; a residual is one more step.
	var whole: Dictionary = _panel._price.whole(_loader, draft, false)
	var last: int = chart.row_count() - 1
	if chart.figure(0) != Num.f(float(whole["deficit_now_bn"]), 0) or chart.figure(last) != Num.f(float(whole["deficit_after_bn"]), 0):
		_fail("the waterfall runs %s to %s, the whole bill %s to %s" % [chart.figure(0), chart.figure(last), whole["deficit_now_bn"], whole["deficit_after_bn"]])
	if last - 1 != steps and last - 2 != steps:
		_fail("the waterfall has %d steps for %d changes" % [last - 1, steps])
	# ONE button: Table the bill. Everything else in the tray is a link (flat).
	var loud := []
	for b in foot.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and not (b as Button).flat and (b as Button).theme_type_variation != UiTheme.GHOST:
			loud.append(b)
	# Gate T4 on #443: a change's money is a price, the text colour at the bold cut, never a tone.
	for id in drawn:
		var money: Label = foot.find_child("Money_" + String(id).replace(":", "_"), true, false)
		if money != null and money.theme_type_variation != ControlStyle.STRONG:
			_fail("change %s's money wears '%s', not the price's bold" % [id, money.theme_type_variation])
	# Gate T9: the Assembly's result in words under its bar, with its glyph.
	if not foot._verdict.visible or not (foot._verdict.text.begins_with("✓") or foot._verdict.text.begins_with("✗")):
		_fail("the rail does not say the Assembly's result in words: '%s'" % foot._verdict.text)
	if loud.size() != 1 or (loud[0] as Button).text != Strings.t("Table the bill"):
		_fail("the tray's loud buttons: %s" % [loud.map(func(b) -> String: return (b as Button).text)])


## Pass 2 T3 on #429, kept: a change says its value in its own unit and decimals -- the waterfall's step names it so.
func _check_units() -> void:
	var ns = _state.player()
	var rows: Array = _panel.shared_draft().rows()
	for i in rows.size():
		if not _panel._foot._chart.label(i + 1).contains(FinanceRows.change_figures(ns, rows[i])):
			_fail("step %d reads '%s', not its figures '%s'" % [i + 1, _panel._foot._chart.label(i + 1), FinanceRows.change_figures(ns, rows[i])])


## Pass 2 T10: each number once -- the seats in the bar only, the deficit in the tray only.
func _check_each_number_once() -> void:
	if _panel._foot._text.text.contains("undecided"):
		_fail("the tray's sentence repeats the seats the bar draws: '%s'" % _panel._foot._text.text)
	var whole: Dictionary = _panel._price.whole(_loader, _panel.shared_draft(), false)
	if _panel._with.text.contains(Num.f(float(whole["deficit_after_bn"]), 0)):
		_fail("the page's note repeats the tray's deficit: '%s'" % _panel._with.text)


## Pass 2 T7: one name for the act, the tray's and the sheet's.
func _check_one_name() -> void:
	_panel._open_sheet()
	var sheet_table := _panel._sheet.find_child("SheetTable", true, false) as Button
	if sheet_table == null or sheet_table.text != Strings.t("Table the bill"):
		_fail("the sheet's act reads '%s', the tray's 'Table the bill'" % (sheet_table.text if sheet_table != null else "<none>"))
	_panel._close_sheet()


## Pass 2 T2: a drag prices only the row it moves; the others are priced once per draft change.
func _check_priced_once() -> void:
	var counting := CountingPrice.new()
	counting.setup(_state)
	var draft = _panel.shared_draft()
	var foot = _panel._foot
	foot.refresh(_state, _loader, draft, counting)
	var first := counting.rows
	draft.set_value(FinanceDraft.SPENDING, "health", draft.value(FinanceDraft.SPENDING, "health") + 0.1)
	var t0 := Time.get_ticks_usec()
	foot.refresh(_state, _loader, draft, counting)
	print("tray refresh after one drag step, %d rows: %d us" % [draft.count(), Time.get_ticks_usec() - t0])
	if counting.rows - first != 1:
		_fail("one drag step re-priced %d rows, not 1" % (counting.rows - first))
	draft.set_value(FinanceDraft.SPENDING, "health", draft.value(FinanceDraft.SPENDING, "health") - 0.1)
	foot.refresh(_state, _loader, draft, _panel._price)


## Pass 2 T1: share moves alone can be discarded.
func _check_moves_only_discard() -> void:
	var draft = FinanceDraft.new()
	draft.setup(_state)
	draft.add_move("health", "hospitals", "primary_care", 0.01)
	var foot = _panel._foot
	foot.refresh(_state, _loader, draft, _panel._price)
	var discard := foot.find_child("Discard", true, false) as Button
	if discard == null or not discard.is_visible_in_tree():
		_fail("a draft of moves alone shows no Discard")
	foot.refresh(_state, _loader, _panel.shared_draft(), _panel._price)


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


## Counts the previews a price runs (a miss of its kept answers): the rows are priced once, whichever surface asks
## (pass 2 T7 on #443 moved the rows' cache into the price).
class CountingPrice extends "res://src/ui/finance_price.gd":
	var rows := 0

	func after(pending: Dictionary) -> Dictionary:
		_check()
		if not _kept.has(var_to_str(pending)):
			rows += 1
		return super.after(pending)


## {row id: its line} over the rail's listed changes on screen.
func _drawn() -> Dictionary:
	var out := {}
	for node in _panel._foot.find_children("*", "HBoxContainer", true, false):
		if node.has_meta("rail") and String(node.get_meta("rail")) == "change" and (node as Control).is_visible_in_tree() \
				and not node.is_queued_for_deletion():
			out[String(node.get_meta("id"))] = node
	return out


func _remove_mark(row_id: String):
	for b in _panel._foot.find_children("*", "BaseButton", true, false):
		if b.has_meta("drop") and String(b.get_meta("drop")) == row_id and (b as Control).is_visible_in_tree() \
				and not b.is_queued_for_deletion():
			return b
	return null


func _press(button) -> void:
	if button == null:
		_fail("frame %d: the control to press is not on screen" % _frame)
		return
	(button as BaseButton).pressed.emit()


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
