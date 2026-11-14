extends SceneTree

## Headless test: godot --headless --script res://tests/test_finance_read.gd
## Non-zero exit on any failure.
##
## V5.3 e: the Finances screen's reads (Interface's direction A, the author's pick; Gameplay's
## brief section 6). Reads only, each over a rule the game already runs:
##   (a) a draft before it is tabled: tabling's own verdict and the division it would meet;
##   (b) who gains and who loses from a spending line, through the goal read's copy;
##   (c) what one step of each tax kind in force yields, a year, both ways;
##   (d) what the budget's two unset lines hold, as the parts the model keeps.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const FinanceRead = preload("res://src/sim/finance_read.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const GoalRead = preload("res://src/sim/goal_read.gd")
const GK = preload("res://src/sim/goal_read_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Opinion = preload("res://src/sim/opinion.gd")

const EPS := 1e-9

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_a_draft_reads_what_tabling_would_meet()
	_check_a_draft_tabling_would_refuse_says_why()
	_check_a_lines_gainers_are_the_goal_reads()
	_check_a_steps_yield_is_the_budgets()
	_check_the_unset_lines_parts_sum_to_them()
	_finish()


func _state(nation := "FRA"):
	var state = GameState.new_game(_loader, nation)
	state.year = 2026
	state.month = 3
	return state


# --- (a) ------------------------------------------------------------------------

func _check_a_draft_reads_what_tabling_would_meet() -> void:
	var state = _state()
	var bill := {"spending_pct_gdp": {"health": 1.5}, "tax_rates_pct": {"vat": 2.0}}
	var before := JSON.stringify(state.to_dict())
	var draft := FinanceRead.draft(state, _loader, bill)
	if JSON.stringify(state.to_dict()) != before:
		_fail("draft: the read wrote the game")
	if String(draft["refusal"]) != "":
		_fail("draft: a plain draft reads refused '%s'" % draft["refusal"])
	# The division it would meet is the one the tabling forecasts, seat for seat.
	var tabled: Dictionary = FinanceBill.table(state, _loader, bill)
	var forecast: Dictionary = tabled.get("forecast", {})
	for key in ["passed", "yes_seats", "no_seats", "abstain_seats"]:
		if var_to_str(draft["vote"].get(key)) != var_to_str(forecast.get(key)):
			_fail("draft: %s reads %s, the tabling forecasts %s" % [key, draft["vote"].get(key), forecast.get(key)])
	# An amendment: the draft is the bill merged with the one already before the Assembly.
	var amend := {"spending_pct_gdp": {"education": -0.5}}
	var amended := FinanceRead.draft(state, _loader, amend)
	var after: Dictionary = FinanceBill.table(state.duplicate_state(), _loader, amend)
	if var_to_str(amended["vote"].get("yes_seats")) != var_to_str(after["forecast"].get("yes_seats")):
		_fail("draft: an amendment's seats are not the merged bill's")


func _check_a_draft_tabling_would_refuse_says_why() -> void:
	var state = _state()
	state.player().bill_queue = [{"finance": {"spending_pct_gdp": {"health": 0.5}}, "force": false}]
	var draft := FinanceRead.draft(state, _loader, {"tax_rates_pct": {"vat": 1.0}})
	if String(draft["refusal"]) != "finance_queued" or not (draft["vote"] as Dictionary).is_empty():
		_fail("draft: a queued finance text reads '%s' with a vote %s" % [draft["refusal"], draft["vote"]])


# --- (b) ------------------------------------------------------------------------

func _check_a_lines_gainers_are_the_goal_reads() -> void:
	var state = _state()
	var ns = state.player()
	# Off the opening, so the live weights (bad news amplified) differ from the base ones.
	ns.spending_pct_gdp["health"] = float(ns.spending_pct_gdp["health"]) - 3.0
	Budget.recompute(state, ns)
	# Who the line is for: each bloc's weight on its issue, Opinion's own.
	var health := FinanceRead.line_blocs(state, _loader, "health")
	var sat := Opinion.issue_satisfaction(ns)
	var listed := {}
	var prev := INF
	for pair in health["weights"]:
		var w := float(Opinion.bloc_weights(ns, String(pair[0]), sat).get("health", 0.0))
		if float(pair[1]) != w or w <= 0.0 or w > prev:
			_fail("weights: %s reads %s, Opinion weighs %s (or out of order)" % [pair[0], pair[1], w])
		prev = w
		listed[String(pair[0])] = true
	for bloc in OpinionK.BLOC_KEYS:
		if float(Opinion.bloc_weights(ns, bloc, sat).get("health", 0.0)) > 0.0 and not listed.has(bloc):
			_fail("weights: %s weighs health and is not listed" % bloc)
	if (health["weights"] as Array).is_empty():
		_fail("premise: no bloc weighs health")
	# What a step does, net of the deficit: education lifts the students and costs the rest.
	var blocs := FinanceRead.line_blocs(state, _loader, "education")
	var read := GoalRead.read(state, _loader, {"kind": "line", "key": "education", "step": GK.SPENDING_STEP})
	var seen := {}
	for side in ["gains", "loses"]:
		var last := INF if side == "gains" else -INF
		for pair in blocs[side]:
			var bloc := String(pair[0])
			var pts := float(pair[1])
			seen[bloc] = true
			if pts != float(read["bloc_target"][bloc]):
				_fail("blocs: %s reads %s, the goal read %s" % [bloc, pts, read["bloc_target"][bloc]])
			if (side == "gains" and (pts <= 0.0 or pts > last)) or (side == "loses" and (pts >= 0.0 or pts < last)):
				_fail("blocs: %s is out of order or on the wrong side (%s)" % [bloc, pts])
			last = pts
	for bloc in OpinionK.BLOC_KEYS:
		if float(read["bloc_target"][bloc]) != 0.0 and not seen.has(bloc):
			_fail("blocs: %s moves %s and is listed nowhere" % [bloc, read["bloc_target"][bloc]])
	if (blocs["gains"] as Array).is_empty() or (blocs["loses"] as Array).is_empty():
		_fail("premise: an education step should both gain and lose blocs: %s" % [blocs])


# --- (c) ------------------------------------------------------------------------

func _check_a_steps_yield_is_the_budgets() -> void:
	for nation in ["FRA", "GBR"]:
		var state = _state(nation)
		var ns = state.player()
		var yields := FinanceRead.step_yields(ns)
		if yields.size() != ns.tax_rates_pct.size():
			_fail("yield %s: %d kinds read, %d in force" % [nation, yields.size(), ns.tax_rates_pct.size()])
		var now := Budget.preview(state, {})
		for kind in ns.tax_rates_pct:
			var row: Dictionary = yields[kind]
			var step := TaxLibrary.step_pct(ns, kind)
			if float(row["step"]) != step:
				_fail("yield %s: %s steps by %s, its kind %s" % [nation, kind, row["step"], step])
			for dir in [["up_bn", step], ["down_bn", -step]]:
				var landed := float(ns.tax_rates_pct[kind]) + float(dir[1])
				var band: Array = ns.tax_library[kind]["rate_range_pct"]
				var open := landed >= float(band[0]) - 1e-9 and landed <= float(band[1]) + 1e-9
				if open != row.has(dir[0]):
					_fail("yield %s: %s %s offered=%s, in band=%s" % [nation, kind, dir[0], row.has(dir[0]), open])
				if not row.has(dir[0]):
					continue
				# The deficit the Budget's own preview books, in bn a year.
				var after := Budget.preview(state, {"tax_rates_pct": {kind: landed}})
				var want := (float(now["deficit_pct_gdp"]) - float(after["deficit_pct_gdp"])) * float(now["gdp_eur_bn"]) / 100.0
				if absf(float(row[dir[0]]) - want) > 1e-6 * maxf(1.0, absf(want)):
					_fail("yield %s: %s %s reads %s bn, the preview books %s" % [nation, kind, dir[0], row[dir[0]], want])
		if nation == "FRA" and not (yields.get("fuel_duty", {}) as Dictionary).has("up_bn"):
			_fail("yield: France's fuel duty has no step's yield")


# --- (d) ------------------------------------------------------------------------

func _check_the_unset_lines_parts_sum_to_them() -> void:
	var state = _state()
	var ns = state.player()
	var parts := FinanceRead.other_parts(ns)
	var gdp := float(ns.gdp_eur_bn)
	var revenue := 0.0
	for part in parts["revenue"]:
		revenue += float(part["bn"])
	var want_rev := float(ns.revenue_pct_gdp.get("other", 0.0)) * gdp / 100.0
	if absf(revenue - want_rev) > EPS * maxf(1.0, want_rev):
		_fail("other revenue: the parts sum to %s bn, the line holds %s" % [revenue, want_rev])
	var spending := 0.0
	for part in parts["spending"]:
		spending += float(part["bn"])
	var want_spend := float(ns.other_spending_pct_gdp) * gdp / 100.0
	if absf(spending - want_spend) > EPS * maxf(1.0, want_spend):
		_fail("other spending: the parts sum to %s bn, the line holds %s" % [spending, want_spend])
	# A law's own revenue shows as its own part.
	ns.law_other_revenue_pct_gdp = 0.5
	Budget.recompute(state, ns)
	var laws := 0.0
	for part in FinanceRead.other_parts(ns)["revenue"]:
		if String(part["key"]) == "laws":
			laws = float(part["bn"])
	if absf(laws - 0.5 * gdp / 100.0) > 1e-9 * gdp:
		_fail("other revenue: a law's 0.5 %% of GDP reads %s bn" % laws)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS tests/test_finance_read.gd")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL " + f)
	quit(1)
