extends SceneTree

## Headless test: godot --headless --script res://tests/test_industry_tab.gd
## Non-zero exit on any failure.
##
## V5.3 a + b step 2, docs/design/v5.3-ab.md 3.2 "The tab, rebuilt": the In progress
## strip first, then three sector cards, closed until opened; an opened card lists
## its majors as rows with ONE Act button each; Act opens the firm's verbs, each its
## name and its money line, and the full three-line strip only for the verb that
## has focus (a click or the keyboard, never hover).
##
## Band A5 (spec section 9): a verb whose condition fails is greyed AND its failing
## line is on screen beside it -- never only in a tooltip, never first after a
## press. Staged with a live process on one firm, which refuses that firm's other
## ownership verbs with Processes.BUSY.
##
## Driven through the real controls (pressed, grab_focus), a frame apart, because a
## Control that is built but not shown is the silent failure AGENTS.md names.

const Companies = preload("res://src/sim/companies.gd")
const Processes = preload("res://src/sim/processes.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const Strings = preload("res://src/ui/strings.gd")
const Asks = preload("res://src/sim/process_asks.gd")
const Pending = preload("res://src/ui/pending.gd")
const Economy = preload("res://src/sim/economy.gd")
const Num = preload("res://src/ui/num.gd")

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0
var _acted := 0
var _major
var _sector := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_panel = _main._companies_panel
			_panel.acted.connect(func(_b, _l): _acted += 1)
			var ns = _main._state.player()
			_major = Companies.majors_of(_main._loader, ns.id)[0]
			_sector = String(_major.sector)
			_main._windows.open("companies")
		4:
			_check_closed()
			_press(_button_with_meta("sector", _sector))
		6:
			_check_sector_open()
			_press(_button_with_meta("fold", "body:" + _sector))
			_press(_button_with_meta("ledger", "ledger"))
		7:
			_check_folds()
			_press(_button_with_meta("company_id", String(_major.id)))
		8:
			_check_verbs()
			_focus_first_live_verb()
		10:
			_check_focused()
			_panel.mark_dirty()
		12:
			_check_open_state_survives()
			_start_process()
		14:
			_check_in_progress()
			_check_a5()
			_post_ask()
		16:
			_check_ask()
			_press(_button_with_meta("answer_id", "accept"))
		18:
			_check_answered()
			_press(_button_with_meta("process_id", _live_pid()))
		20:
			_check_stopped()
			_finish()
	return false


## Day one: three cards, every one closed; no Act and no verb on screen; no In
## progress strip while nothing runs.
func _check_closed() -> void:
	var headers := _visible_with_meta("sector")
	if headers.size() != 3:
		_fail("closed: %d sector cards on screen, expected 3" % headers.size())
	if not _visible_with_meta("company_id").is_empty():
		_fail("closed: an Act button is on screen before any card was opened")
	if not _visible_with_meta("action_id").is_empty():
		_fail("closed: a verb is on screen before any firm was opened")
	if _panel._progress != null and _panel._progress.is_visible_in_tree():
		_fail("closed: the In progress strip shows with nothing running")
	# The card's trend against the nation's (spec 3.2): the sim's own query, #254.
	var ns = _main._state.player()
	for head in headers:
		var sector := String(head.get_meta("sector"))
		var text := _text_under(head.get_parent())
		var own := Num.fs(Economy.sector_trend_pct(_main._state, ns, sector), 1)
		var nation := Num.fs(float(ns.trend_annual_pct), 1)
		# Each figure in its place (QA's T1 on #265): the two swapped would read the
		# nation's rate as the sector's, and both would still be on the line.
		if not text.contains("trend %s %%/yr, nation %s" % [own, nation]):
			_fail("closed: the %s card reads '%s', its trend is %s %%/yr against the nation's %s" % [sector, text, own, nation])


## An opened card: one Act per major of its sector, and no verb yet.
func _check_sector_open() -> void:
	var ns = _main._state.player()
	var want := 0
	for company in Companies.majors_of(_main._loader, ns.id):
		if String(company.sector) == _sector:
			want += 1
	var acts := _visible_with_meta("company_id")
	if acts.size() != want:
		_fail("%s open: %d Act buttons, expected one per major (%d)" % [_sector, acts.size(), want])
	if not _visible_with_meta("action_id").is_empty():
		_fail("%s open: a verb is on screen before Act was pressed" % _sector)


## The two folds open on a press: the body list names its largest firm, the public
## account its first row.
func _check_folds() -> void:
	var ns = _main._state.player()
	var largest = null
	for company in Companies.firms_in_sector(_main._loader, ns.id, _sector):
		if not Companies.is_major(company) and (largest == null
				or Companies.headcount(ns, company) > Companies.headcount(ns, largest)):
			largest = company
	var text := _text_under(_panel._body)
	if largest != null and not text.contains(String(largest.company_name)):
		_fail("body fold pressed: its largest firm %s is not listed" % largest.company_name)
	if not text.contains(_panel.tr("Subsidy bill")):
		_fail("public account pressed: its rows are not on screen")


## Act opened: one selector per verb on offer, each with its money line; no strip
## until a verb has focus.
func _check_verbs() -> void:
	var ns = _main._state.player()
	var offered: Array = Companies.available(_main._state, ns, _main._loader.company_actions, String(_major.id), _main._loader)
	var selectors := _visible_with_meta("action_id")
	if selectors.size() != offered.size():
		_fail("firm open: %d verbs on screen, %d on offer" % [selectors.size(), offered.size()])
	for button in selectors:
		var money: Label = button.get_meta("money_label")
		if money == null or not money.is_visible_in_tree() or money.text == "":
			_fail("firm open: the verb '%s' has no money line" % button.text)
	if not _visible_strips().is_empty():
		_fail("firm open: a strip shows before any verb has focus")


func _focus_first_live_verb() -> void:
	for button in _visible_with_meta("action_id"):
		if not button.disabled:
			(button as Button).grab_focus()
			return
	_fail("firm open: no verb can be focused")


## One verb focused: exactly one strip, at most three lines, and its money line is
## the sim's own figure for that verb (a process: Processes.estimate's range).
func _check_focused() -> void:
	var strips := _visible_strips()
	if strips.size() != 1:
		_fail("focused: %d strips on screen, expected 1" % strips.size())
		return
	var strip = strips[0]
	var lines := 0
	for child in strip.get_children():
		if (child as Control).is_visible_in_tree():
			lines += 1
	if lines > 3:
		_fail("focused: the strip shows %d lines, the most is 3" % lines)
	var action_id := String(_panel._focus_verb)
	var action = _action(action_id)
	var ns = _main._state.player()
	if Processes.is_process(action):
		var est: Dictionary = Processes.estimate(_main._state, ns, _main._loader, action, String(_major.id))
		var want := EffectsStrip.range_text(-maxf(float(est["price_lo"]), float(est["price_hi"])),
			-minf(float(est["price_lo"]), float(est["price_hi"])))
		if strip.money_label.text != want:
			_fail("focused %s: the strip's money reads '%s', the estimate prints '%s'" % [action_id, strip.money_label.text, want])
	var go = _go_button()
	if go == null or not go.is_visible_in_tree():
		_fail("focused %s: no Go under the strip" % action_id)


## A month's sweep rebuilds the body; the card, the firm and the focus stay.
func _check_open_state_survives() -> void:
	if _visible_with_meta("company_id").is_empty():
		_fail("after a refresh the opened card closed")
	if _visible_with_meta("action_id").is_empty():
		_fail("after a refresh the opened firm closed")
	if _visible_strips().size() != 1:
		_fail("after a refresh the focused verb's strip is gone")


func _start_process() -> void:
	var ns = _main._state.player()
	var stake = _action("minority_stake")
	var result: Dictionary = Processes.start(_main._state, ns, _main._loader, stake, String(_major.id))
	if not bool(result.get("applied", false)):
		_fail("could not stage a minority stake on %s: %s" % [_major.company_name, result])
	_panel.mark_dirty()


## The running stake: a row naming the firm, a Stop, and Stop's money line is what
## stopping costs now.
func _check_in_progress() -> void:
	var ns = _main._state.player()
	var rows := Processes.rows(ns)
	if rows.size() != 1:
		_fail("in progress: %d rows in the register, expected 1" % rows.size())
		return
	if _panel._progress == null or not _panel._progress.is_visible_in_tree():
		_fail("in progress: the strip is not on screen with a process running")
		return
	if not _text_under(_panel._progress).contains(String(_major.company_name)):
		_fail("in progress: no row names %s" % _major.company_name)
	var stop = _button_with_meta("process_id", String(rows[0]["id"]))
	if stop == null:
		_fail("in progress: no Stop on the running stake")
		return
	var price: Dictionary = Processes.stop_price(_main._state, ns, _main._loader, String(rows[0]["id"]))
	var money: Label = stop.get_meta("money_label")
	if money == null or money.text != EffectsStrip.cost_text(-float(price["debt_eur_bn"])):
		_fail("in progress: Stop's money reads '%s', stopping costs %s" % [
			money.text if money != null else "<none>", EffectsStrip.cost_text(-float(price["debt_eur_bn"]))])


## A5: every verb the live process refuses is greyed and its line is on screen.
func _check_a5() -> void:
	var ns = _main._state.player()
	var refused := 0
	for button in _visible_with_meta("action_id"):
		var action = _action(String(button.get_meta("action_id")))
		var why := CompanyVerb.refusal(_main._state, _main._loader, ns, _major, action)
		if why == "":
			continue
		refused += 1
		if not button.disabled:
			_fail("A5: '%s' is refused (%s) but not greyed" % [button.text, why])
		var line: Label = button.get_meta("refusal_label")
		if line == null or not line.is_visible_in_tree() or not line.text.contains(Strings.t(why)):
			_fail("A5: '%s' is greyed with no visible line saying why (%s)" % [button.text, why])
	if refused == 0:
		_fail("A5: the live stake refused no verb on its firm; the fixture proves nothing")


## #248: the stake's negotiation asks its final price, as the stage's last month does.
func _post_ask() -> void:
	var ns = _main._state.player()
	for row in ns.processes:
		if String(row["status"]) == Processes.OPEN:
			Asks.post(ns, row, _action(String(row["action_id"])), _main._state.year * 12 + _main._state.month, _major)
	_panel.mark_dirty()


## The ask on its row: the question, each answer with the money it books, no Stop
## beside it, the tab marked as waiting and the card saying so.
func _check_ask() -> void:
	var ns = _main._state.player()
	var asks := Processes.asks(ns)
	if asks.size() != 1:
		_fail("ask: %d asks in the register, expected 1" % asks.size())
		return
	for option in asks[0]["ask"]["answers"]:
		var button = _button_with_meta("answer_id", String(option["id"]))
		if button == null:
			_fail("ask: no '%s' answer on screen" % option["id"])
			continue
		var money: Label = button.get_meta("money_label")
		if money.text != EffectsStrip.cost_text(-float(option["debt_eur_bn"])):
			_fail("ask: '%s' reads '%s', it books %s" % [option["id"], money.text, EffectsStrip.cost_text(-float(option["debt_eur_bn"]))])
		# #280's counters: named by their percentage, their chances the shown range.
		if option.has("counter"):
			var counter := roundi(100.0 * float(option["counter"]))
			if (button as Button).text != Strings.t("Counter %d %%") % counter:
				_fail("ask: the %d %% counter is labelled '%s'" % [counter, button.text])
			var odds: Label = button.get_meta("odds_label") if button.has_meta("odds_label") else null
			var range_text := "%d to %d %%" % [roundi(100.0 * float(option["odds_lo"])), roundi(100.0 * float(option["odds_hi"]))]
			if odds == null or not odds.is_visible_in_tree() or not odds.text.contains(range_text):
				_fail("ask: the %d %% counter does not show its range %s (%s)" % [counter, range_text, odds.text if odds != null else "<none>"])
	if not asks[0]["ask"]["answers"].any(func(o): return (o as Dictionary).has("counter")):
		_fail("premise: the stake's price ask carries no counter (#280)")
	for b in _visible_with_meta("process_id"):
		if not b.has_meta("answer_id"):
			_fail("ask: a Stop stands beside the question (walking away is an answer)")
	if not Pending.window_ids(_main._state, _main._loader).has("companies"):
		_fail("ask: the Industry tab is not marked as waiting")
	var head = _button_with_meta("sector", _sector)
	if head == null or not _text_under(head.get_parent()).contains(_panel.tr("Decision due")):
		_fail("ask: the %s card does not say a decision is due" % _sector)


func _check_answered() -> void:
	var ns = _main._state.player()
	if not Processes.asks(ns).is_empty():
		_fail("answered: the ask still waits")
	if not _text_under(_panel._progress).contains(_panel.tr("Answered: %s.") % _panel.tr("Accept")):
		_fail("answered: the row does not say what was answered")
	if _acted < 1:
		_fail("answered: the panel emitted no acted")
	# #280: a refused counter says so on its row (staged as the draw writes it).
	for row in ns.processes:
		if String(row["status"]) == Processes.OPEN:
			row["negotiation"] = {"answer": "negotiate_10", "outcome": "back", "month": 0}
	_panel._refresh()
	var found := false
	for node in _panel._progress.find_children("*", "Label", true, false):
		if String(node.get_meta("negotiation", "")) == "back" and node.text == _panel.tr("Your counter was refused: the old price is asked again."):
			found = true
	if not found:
		_fail("negotiation: a refused counter is not said on its row")
	for row in ns.processes:
		row.erase("negotiation")


func _check_stopped() -> void:
	if not Processes.rows(_main._state.player()).is_empty():
		_fail("Stop pressed: the process still runs")
	if _acted < 2:
		_fail("Stop pressed: the panel emitted no acted")


# -- helpers --

func _action(id: String):
	for a in _main._loader.company_actions:
		if String(a.id) == id:
			return a
	return null


func _live_pid() -> String:
	var rows := Processes.rows(_main._state.player())
	return String(rows[0]["id"]) if not rows.is_empty() else ""


func _press(button) -> void:
	if button == null:
		_fail("frame %d: the control to press is not on screen" % _frame)
		return
	(button as Button).pressed.emit()


func _button_with_meta(key: String, value: String):
	for b in _visible_with_meta(key):
		if String(b.get_meta(key)) == value:
			return b
	return null


func _visible_with_meta(key: String) -> Array:
	var out := []
	for b in _panel.find_children("*", "Button", true, false):
		if b.has_meta(key) and (b as Control).is_visible_in_tree():
			out.append(b)
	return out


func _visible_strips() -> Array:
	var out := []
	for node in _panel.find_children("*", "", true, false):
		if node.get_script() == EffectsStrip and (node as Control).is_visible_in_tree():
			out.append(node)
	return out


func _go_button():
	for b in _panel.find_children("*", "Button", true, false):
		if b.has_meta("go") and (b as Control).is_visible_in_tree():
			return b
	return null


func _text_under(node: Node) -> String:
	var out := ""
	for label in node.find_children("*", "Label", true, false):
		out += (label as Label).text + " "
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_industry_tab: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
