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
const CompanyVerb = preload("res://src/ui/company_verb.gd")
const ClosureCard = preload("res://src/ui/closure_card.gd")
const Priorities = preload("res://src/ui/priorities.gd")
const PriorityWords = preload("res://src/ui/priority_words.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const CK = preload("res://src/sim/closures_constants.gd")

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0
var _acted := 0
var _major
var _closure_id := ""
var _third
var _counter_id := ""
var _option := {}


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
			_announce_third()
		12:
			_pick_the_last_chip()
		14:
			_make_the_counter()
		16:
			_check_countered()
			_stage_the_buyer_back()
		18:
			_check_re_ask()
			_press(_with_meta("closure_answer", "buyer"))
		20:
			_check_re_ask_answered()
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
	# The author's call on #286: the reason is what the record kept, the firm's own fall
	# and the economy's gap, as literals over what this test staged (a 20 % fall).
	var fell := Strings.tn("Its output fell %s %% in %d month.", "Its output fell %s %% in %d months.", int(row["window_months"])) % ["20", int(row["window_months"])]
	if not text.contains(fell):
		_fail("card: '%s' does not say what fell: %s" % [text, fell])
	var below := Strings.t("The economy was %s %% below its potential.") % Num.f(-float(row["gap_pct"]), 1)
	if text.contains(below) != (float(row["gap_pct"]) <= -0.05):
		_fail("card: the economy's clause and the record's gap %s disagree: '%s'" % [row["gap_pct"], text])
	# The sentence, whole: a gap that rounds to nothing is no reason to give (pass 1 on
	# #286), a real one is said in the past, as the record's month it is.
	var six := Strings.tn("Its output fell %s %% in %d month.", "Its output fell %s %% in %d months.", 6) % ["20", 6]
	var flat := ClosureCard.reason({"window_months": 6, "fall": 0.2, "gap_pct": -0.03})
	if flat != six:
		_fail("card: a gap of -0.03 reads '%s', not '%s'" % [flat, six])
	var slump := ClosureCard.reason({"window_months": 6, "fall": 0.2, "gap_pct": -2.0})
	var said := six + " " + Strings.t("The economy was %s %% below its potential.") % Num.f(2.0, 1)
	if slump != said:
		_fail("card: a gap of -2.0 reads '%s', not '%s'" % [slump, said])
	var answers: Array = Closures.answers(state, ns, loader, _closure_id)
	var parent: Node = null
	# QA's TAKE 2 on #277: the rescue's own texts -- its label, a cost (not a gain) for
	# its term, and the jobs kept for that term.
	for answer in answers:
		if String(answer["kind"]) != "rescue":
			continue
		var money: Array = ClosureCard.money(answer)
		var jobs_line := ClosureCard.jobs_text(answer)
		var months := Strings.tn("%d month", "%d months", CK.RESCUE_MONTHS) % CK.RESCUE_MONTHS
		if ClosureCard.label(answer) != Strings.t("Rescue the plant") or float(money[1]) >= 0.0 \
				or not String(money[0]).contains(months) or not jobs_line.contains(months):
			_fail("card: the rescue reads '%s' / %s / '%s', not a labelled cost and jobs for its %s" % [
				ClosureCard.label(answer), money, jobs_line, months])
	for answer in answers:
		var id := String(answer["id"])
		# #285's counters are one row of chips (_make_the_counter), not columns.
		if String(answer["kind"]) == "negotiate":
			if _with_meta("counter_id", id) == null:
				_fail("card: no chip for the counter '%s'" % id)
			continue
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
			return Strings.t("No cost.")
		"buyer", "negotiate":
			# A small search in millions, never "0.0 bn" (QA's TAKE on #270): the first
			# major's search (Verdelis, ~0.023 bn) is one of them.
			var search := -float(answer["debt_eur_bn"])
			var shown := (Strings.t("%s m") % Num.fs(search * 1000.0, 0)) if absf(search) < 0.1 else EffectsStrip.money_text(search)
			if search < -0.0005 and shown.begins_with("0.0"):
				_fail("card: the buyer's search reads as free ('%s')" % shown)
			return Strings.t("%s now, %s at a sale") % [shown, EffectsStrip.sum_text(-float(answer["sweetener_eur_bn"]))]
	var months := int(answer["months"])
	return Strings.tn("%s a year, %d month", "%s a year, %d months", months) % [
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
	# Its change cell (QA's H6 on #279): an em dash with nothing proposed, the shape
	# CHANGE_ROWS gives; a row missing from it carries an empty cell.
	elif cells.size() < 3 or String((cells[2] as Array)[0]) != "—":
		_fail("budget: the plant rescue line has no change cell (%s)" % [cells])
	# QA's H1/H2/H3: the rescue alone (the searching closure ended), a few months into
	# its term; the strip still drawn, the months counted down, the jobs printed.
	var first = Companies.majors_of(_main._loader, ns.id)[0]
	(ns.companies[first.id] as Dictionary).erase("closure")
	Closures.tick_month(state, _main._loader)
	var row: Dictionary = Closures.rescues(ns)[0]
	_panel._refresh()
	if _panel._progress == null:
		_fail("rescue alone: the In progress strip is not drawn")
		return
	# Read in the new strip: the old rows are queued for freeing, still in the tree.
	var later = null
	for node in _panel._progress.find_children("*", "Label", true, false):
		if node.has_meta("rescue") and String(node.get_meta("rescue")) == String(row["company_id"]):
			later = node
	var months := int(row["months_left"])
	var jobs := CompanyVerb.thousands(float(row["jobs"]))
	if later == null or months >= left or not later.text.contains(Strings.tn("%d month left", "%d months left", months) % months) \
			or not later.text.contains(jobs + " jobs kept"):
		_fail("rescue alone: '%s' should say %d months left and %s jobs kept" % [later.text if later != null else "<none>", months, jobs])


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


## #285: a third closure, on the third major, for the counter's leg.
func _announce_third() -> void:
	var state = _main._state
	var ns = state.player()
	_third = Companies.majors_of(_main._loader, ns.id)[2]
	Closures._announce(ns, _third, ns.companies[_third.id], 0.2, _main._loader.closure_rule, state.year * 12 + state.month)
	_panel.mark_dirty()


## A chip other than the first, then a rebuild: the pick must survive it.
func _pick_the_last_chip() -> void:
	var state = _main._state
	for a in Closures.answers(state, state.player(), _main._loader, _row_of_third()["id"]):
		if String(a["kind"]) == "negotiate":
			_option = a
	var chip = _with_meta("counter_id", String(_option.get("id", "")))
	if chip == null:
		_fail("counter: no chip for the last counter (%s)" % [_option])
		return
	(chip as Button).pressed.emit()
	_panel.mark_dirty()


## After the rebuild: the chip still pressed, the strip reads ITS figures, the button
## makes it.
func _make_the_counter() -> void:
	var option := _option
	var chip = _with_meta("counter_id", String(option.get("id", "")))
	if chip == null or not (chip as Button).button_pressed:
		_fail("counter: the pick did not survive a rebuild (%s)" % [option.get("id", "")])
	var strip = null
	for node in _panel.find_children("*", "", true, false):
		if node.has_meta("counter_strip") and (node as Control).is_visible_in_tree():
			strip = node
	if strip == null:
		_fail("counter: no strip under the chips")
		return
	var text := _text_under(strip)
	if strip.money_label.text != _money_of(option):
		_fail("counter: the strip's money reads '%s', its figures print '%s'" % [strip.money_label.text, _money_of(option)])
	for want in ["%d to %d %%" % [roundi(100.0 * float(option["odds_lo"])), roundi(100.0 * float(option["odds_hi"]))],
			"(%d %% of refusals)" % roundi(100.0 * float(option["walk"])), EffectsStrip.sum_text(-float(option["back_sweetener_eur_bn"]))]:
		if not text.contains(want):
			_fail("counter: the strip '%s' does not carry %s" % [text, want])
	_counter_id = String(option["id"])
	_press(_with_meta("closure_answer", "counter"))


func _check_countered() -> void:
	var row := _row_of_third()
	if String(row.get("answer", "")) != _counter_id or String(row.get("status", "")) != Closures.SEARCHING:
		_fail("counter made: the row is %s / '%s', expected searching on '%s'" % [row.get("status", ""), row.get("answer", ""), _counter_id])
	var said := Strings.t("Answered: %s.") % (Strings.t("Counter %d %%") % int(_counter_id.trim_prefix("negotiate_")))
	if not _text_under(_panel._progress).contains(said):
		_fail("counter made: the searching row does not say '%s'" % said)


## As the search's end writes it when the buyer's answer comes back (closures.gd).
func _stage_the_buyer_back() -> void:
	var state = _main._state
	var row := _row_of_third()
	var now: int = state.year * 12 + state.month
	row["status"] = Closures.OFFERED
	row["offered"] = now
	row["due"] = now + 1
	row.erase("answer")
	_panel.mark_dirty()


## Ruling (b): one month's re-ask at the old sweetener; the default is the SALE.
func _check_re_ask() -> void:
	var state = _main._state
	var row := _row_of_third()
	var text := _text_under(_panel._progress)
	var old: String = EffectsStrip.sum_text(-float(row["back_sweetener_eur_bn"]))
	if not text.contains(Strings.t("Unanswered, the plant is sold at the old price.")) or text.contains(Strings.t("Unanswered, the plant closes.")):
		_fail("re-ask: the default line is not the sale ('%s')" % text)
	var sell = _with_meta("closure_answer", "buyer")
	if sell == null or (sell as Button).text != Strings.t("Sell at the old price") or not (sell.get_meta("money_label") as Label).text.contains(old):
		_fail("re-ask: no 'Sell at the old price' reading %s (%s)" % [old, sell.text if sell != null else "<none>"])
	if _with_meta("closure_answer", "close") == null:
		_fail("re-ask: no 'Let it close'")
	if _with_meta("counter_id", _counter_id) != null:
		_fail("re-ask: the chips are offered again")
	if not Pending.window_ids(state, _main._loader).has("companies"):
		_fail("re-ask: the Industry tab is not marked as waiting")
	var head = _with_meta("sector", String(_third.sector))
	if head == null or not _text_under(head.get_parent()).contains(_panel.tr("Decision due")):
		_fail("re-ask: the %s card does not say a decision is due" % _third.sector)
	if not text.contains(String(_third.company_name)):
		_fail("re-ask: the row does not name %s" % _third.company_name)
	_check_re_ask_ranks(true)


## Answered once: the row says so, and nothing waits any more.
func _check_re_ask_answered() -> void:
	var ns = _main._state.player()
	var text := _text_under(_panel._progress)
	if not text.contains(Strings.t("Answered: %s.") % Strings.t("Sell at the old price")):
		_fail("re-ask answered: the row does not say so ('%s')" % text)
	if text.contains(Strings.t("Unanswered, the plant is sold at the old price.")):
		_fail("re-ask answered: the default line still stands")
	if _with_meta("closure_answer", "buyer") != null:
		_fail("re-ask answered: the answers still stand")
	if Pending._closure_waiting(ns):
		_fail("re-ask answered: the closure still waits on the player")
	_check_re_ask_ranks(false)
	_check_results()
	_check_unknown_kind()


## The parent's ruling on #287: a countered closure's result is one toned line for one
## month, the words whole, staged as the machine writes each ending (closures.gd).
func _check_results() -> void:
	var state = _main._state
	var ns = state.player()
	var row := _row_of_third()
	var now: int = state.year * 12 + state.month
	var firm: String = _main._loader.firm_name(ns.id, String(row["company_id"]))
	var city = Region.find_city(_main._loader.regions.get(ns.id, []), String(row["city_id"]))
	var place: String = String(city.city_name) if city != null else firm
	var jobs: String = CompanyVerb.thousands(float(row["jobs"]))
	var cut: String = EffectsStrip.sum_text(-float(row["sweetener_eur_bn"]))
	var old: String = EffectsStrip.sum_text(-float(row["back_sweetener_eur_bn"]))
	var drawn := func(outcome: String) -> Dictionary: return {"answer": _counter_id, "outcome": outcome, "month": now}
	var earlier := {"answer": _counter_id, "outcome": "back", "month": now - 1}
	for c in [
			["accepted", "sold", drawn.call("accepted"), Strings.t("%s's plant in %s is sold at your counter, %s: %s jobs kept.") % [firm, place, cut, jobs], ResultTone.GOOD],
			["sold", "sold", earlier, Strings.t("%s's plant in %s is sold at the old price, %s: %s jobs kept.") % [firm, place, old, jobs], ResultTone.GOOD],
			["walked", "closed", drawn.call("walked"), Strings.t("The buyer walked away from %s's plant in %s, and it closed: %s jobs lost.") % [firm, place, jobs], ResultTone.BAD],
			["no_buyer", "closed", {}, Strings.t("No buyer came for %s's plant in %s, and it closed: %s jobs lost.") % [firm, place, jobs], ResultTone.BAD],
			["closed", "closed", earlier, Strings.t("%s's plant in %s closed, as you chose: %s jobs lost.") % [firm, place, jobs], ""],
			["void", "void", earlier, Strings.t("%s failed before a buyer came for its plant in %s.") % [firm, place], ""]]:
		row["status"] = c[1]
		row["ended"] = now
		row["negotiation"] = c[2]
		if (c[2] as Dictionary).is_empty():
			row.erase("negotiation")
		_panel._refresh()
		var lines := _result_lines()
		if lines.size() != 1 or String(lines[0].get_meta("closure_result")) != c[0]:
			_fail("result: '%s' should be said once, found %d" % [c[0], lines.size()])
			continue
		if (lines[0] as Label).text != c[3]:
			_fail("result: '%s' reads '%s', not '%s'" % [c[0], lines[0].text, c[3]])
		var colour: Variant = lines[0].get_theme_color("font_color") if lines[0].has_theme_color_override("font_color") else null
		if colour != ResultTone.TINT.get(c[4]):
			_fail("result: '%s' wears %s, its tone is '%s'" % [c[0], colour, c[4]])
	# The month after, it is gone.
	row["status"] = "closed"
	row["ended"] = now - 1
	row["negotiation"] = {"answer": _counter_id, "outcome": "walked", "month": now - 1}
	_panel._refresh()
	if not _result_lines().is_empty():
		_fail("result: still said the month after")
	# A counter that came back is the re-ask's own row, not a result.
	row["status"] = Closures.OFFERED
	row["ended"] = -1
	row["negotiation"] = {"answer": _counter_id, "outcome": "back", "month": now}
	row["due"] = now + 1
	_panel._refresh()
	if not _result_lines().is_empty():
		_fail("result: a re-ask is said as a result too")


func _result_lines() -> Array:
	var out := []
	for node in _panel.find_children("*", "Label", true, false):
		var gone := false
		var up: Node = node
		while up != null and not gone:
			gone = up.is_queued_for_deletion()
			up = up.get_parent()
		if node.has_meta("closure_result") and not gone:
			out.append(node)
	return out


## The parent's ruling on #287: a pending re-ask is one of the briefing's three, its
## title names the plant's firm; answered, it is not.
func _check_re_ask_ranks(pending: bool) -> void:
	var state = _main._state
	var found := {}
	for line in Priorities.rank(state, _main._loader, {"held_events": [], "programme_held": false})["lines"]:
		if String(line["kind"]) == "plant" and String(line["subject"]) == String(_row_of_third()["id"]):
			found = line
	if found.is_empty() == pending:
		_fail("briefing: a %s re-ask %s the three priorities" % ["pending" if pending else "answered", "is not among" if pending else "is still among"])
	elif pending and not PriorityWords.title(found, state, _main._loader).contains(String(_third.company_name)):
		_fail("briefing: the re-ask's line does not name %s" % _third.company_name)


## The parent's ruling on #287: a kind the card does not know is no other answer's
## words and no crash. The error line is the loud half, declared here for the runner.
## expects-error: closure_card: an answer of unknown kind
func _check_unknown_kind() -> void:
	var odd := {"id": "odd_answer", "kind": "odd", "jobs_lost": 1.0, "months": 1}
	if ClosureCard.label(odd) != "odd_answer" or ClosureCard.jobs_text(odd) != "" or String(ClosureCard.money(odd)[0]) != "":
		_fail("unknown kind: the card reads '%s' / '%s' / %s" % [ClosureCard.label(odd), ClosureCard.jobs_text(odd), ClosureCard.money(odd)])


func _row_of_third() -> Dictionary:
	# The register's own row: Closures.open() hands out copies, and a stage must write.
	return _main._state.player().companies[_third.id].get("closure", {})


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
