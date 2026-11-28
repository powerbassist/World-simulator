extends SceneTree

## Headless test: godot --headless --script res://tests/test_approval_causes.gd
## Non-zero exit on any failure.
##
## Call A, PR 1 (sim half): Opinion.causes(ns) splits the player's approval TARGET into
## the terms Opinion._tick_nation adds up -- time in office, competence, programme, one row
## per issue, the direct offsets, unrest and what the +-1 clamp cut off -- each bloc's
## weighted by its size, so the rows sum to the national target exactly. The lag is
## approval minus that target: the inertia still to close. The History step carries the
## split in the month's entry, so a later reader diffs two saved entries rather than
## re-running a model. Checked against an independent recompute through Opinion.target_of
## in the game's own month (WorldMonth.tick_month), with a finance bill moving many terms.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")

const MONTHS := 14
const EPS := 1e-9
## The austerity budget of tools/balance_probe.gd: it moves jobs, growth, the deficit,
## three taxes and five spending lines, and the unrest it raises.
const AUSTERITY := {
	"spending_pct_gdp": {"health": -2.5, "education": -2.0, "defence": -1.0, "pensions": -3.5, "infrastructure": -2.0},
	"tax_rates_pct": {"income": 6.0, "corporate": 5.0, "vat": 4.0},
}

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_the_rows_sum_to_the_target_every_month()
	_test_the_clamp_row_carries_what_the_clamp_cut()
	_test_a_target_past_the_band_is_cut_to_it()
	_test_history_carries_the_split()
	_test_an_entry_from_before_reads_as_no_split()
	_finish()


## Every month of a run that moves many terms: the rows sum to the target, the target is
## the tick's own (size-weighted target_of over the six blocs), approval is the headline
## the tick wrote, and the lag is the difference.
func _test_the_rows_sum_to_the_target_every_month() -> void:
	var run := _austerity_run()
	var state = run["state"]
	var ns = state.player()
	var seen := {"months": 0, "issues_moved": 0, "time_moved": false}
	for i in range(MONTHS):
		_next_month(state)
		WorldMonth.tick_month(state, _loader, func(step: String, after: bool, _report: Dictionary) -> void:
			if not (after and step == "Opinion"):
				return
			var c: Dictionary = Opinion.causes(ns)
			var rows: Dictionary = c.get("rows", {})
			var total := 0.0
			for key in rows:
				total += float(rows[key])
			var target := _independent_target(ns)
			if absf(total - float(c.get("target", NAN))) > EPS:
				_fail("month %d: the rows sum to %.12f, the split's target is %.12f" % [i + 1, total, float(c.get("target", NAN))])
			if absf(float(c.get("target", NAN)) - target) > EPS:
				_fail("month %d: the split's target %.12f is not the tick's %.12f" % [i + 1, float(c.get("target", NAN)), target])
			if absf(float(c.get("approval", NAN)) - float(ns.overall_approval_pct)) > EPS:
				_fail("month %d: the split's approval %.6f is not the headline %.6f" % [i + 1, float(c.get("approval", NAN)), float(ns.overall_approval_pct)])
			if absf(float(c.get("lag", NAN)) - (float(ns.overall_approval_pct) - target)) > EPS:
				_fail("month %d: the lag %.6f is not approval minus target" % [i + 1, float(c.get("lag", NAN))])
			for key in ["neutral", "time_in_office", "competence", "programme", "direct:earlier", "unrest", "clamp"]:
				if not rows.has(key):
					_fail("month %d: no '%s' row: %s" % [i + 1, key, rows.keys()])
			for issue in ns.issue_salience.keys():
				if not rows.has("issue:%s" % issue):
					_fail("month %d: issue '%s' has weight but no row" % [i + 1, issue])
			seen["months"] = int(seen["months"]) + 1
			seen["issues_moved"] = maxi(int(seen["issues_moved"]), rows.keys().filter(func(k: String) -> bool: return k.begins_with("issue:") and absf(float(rows[k])) > 0.01).size())
			if absf(float(rows.get("time_in_office", 0.0))) > 0.01:
				seen["time_moved"] = true)
	# Premise: the run exercised the split, not a run of zeros.
	if int(seen["months"]) != MONTHS:
		_fail("premise: the Opinion step ran %d of %d months" % [int(seen["months"]), MONTHS])
	if int(seen["issues_moved"]) < 5 or not bool(seen["time_moved"]):
		_fail("premise: the austerity run moved only %d issue rows (time in office moved: %s)" % [int(seen["issues_moved"]), seen["time_moved"]])


## A target pushed past the clamp: the clamp row is what it cut (negative here), the rows
## still sum to the target, and a target inside the clamp has a clamp row of zero.
func _test_the_clamp_row_carries_what_the_clamp_cut() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var inside: Dictionary = Opinion.causes(ns)
	if absf(float((inside.get("rows", {}) as Dictionary).get("clamp", NAN))) > EPS:
		_fail("a fresh game's clamp row is %s, not 0" % [(inside.get("rows", {}) as Dictionary).get("clamp", NAN)])
	for bloc in K.BLOC_KEYS:
		ns.bloc_offset[bloc] = 1.0
	ns.unemployment_pct = float(ns.start_unemployment_pct) - 5.0  # jobs saturates at +1 too
	var c: Dictionary = Opinion.causes(ns)
	var rows: Dictionary = c.get("rows", {})
	var total := 0.0
	for key in rows:
		total += float(rows[key])
	if not float(rows.get("clamp", 0.0)) < -1.0:
		_fail("a target past the clamp shows a clamp row of %s" % [rows.get("clamp", NAN)])
	if absf(total - _independent_target(ns)) > EPS:
		_fail("past the clamp the rows sum to %.9f, the target is %.9f" % [total, _independent_target(ns)])


## A target below the approval band (full fatigue, a failed programme, every offset and
## the unrest load at the clamp): the band's cut sits in the clamp row, the target is the
## reachable one, and the lag is measured to it -- not a gap approval can never close.
func _test_a_target_past_the_band_is_cut_to_it() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	ns.months_in_term = 120
	ns.programme_stock = -1.0
	ns.unrest_opinion_load = 1.0
	for bloc in K.BLOC_KEYS:
		ns.bloc_offset[bloc] = -1.0
	var sat := Opinion.issue_satisfaction(ns)
	var unclamped := 0.0
	for bloc in K.BLOC_KEYS:
		unclamped += float(K.BLOC_SIZE[bloc]) * Opinion.target_of(ns, bloc, sat, Opinion.bloc_weights(ns, bloc, sat))
	if not unclamped < K.APPROVAL_MIN:
		_fail("premise: the staged target %.3f is not below the band" % unclamped)
		return
	var c: Dictionary = Opinion.causes(ns)
	var total := 0.0
	for key in c["rows"]:
		total += float(c["rows"][key])
	if float(c["target"]) < K.APPROVAL_MIN - EPS or absf(total - float(c["target"])) > EPS:
		_fail("a target past the band: the split's target %.6f, its rows sum %.6f" % [float(c["target"]), total])
	if absf(float(c["lag"]) - (float(ns.overall_approval_pct) - float(c["target"]))) > EPS:
		_fail("past the band the lag %.6f is not measured to the reachable target" % float(c["lag"]))


## The History step carries the split: the month's entry holds causes(ns) as it stood
## after that month's Opinion, and Opinion.causes_of(entry) reads it back.
func _test_history_carries_the_split() -> void:
	var run := _austerity_run()
	var state = run["state"]
	var ns = state.player()
	var at_opinion := {}
	for i in range(3):
		_next_month(state)
		WorldMonth.tick_month(state, _loader, func(step: String, after: bool, _report: Dictionary) -> void:
			if after and step == "Opinion":
				at_opinion["c"] = Opinion.causes(ns))
	var entry: Dictionary = state.history[-1]
	var read: Dictionary = Opinion.causes_of(entry)
	if read.is_empty():
		_fail("the month's history entry carries no split: %s" % [entry.keys()])
		return
	if var_to_str(read) != var_to_str(at_opinion["c"]):
		_fail("the history entry's split is not the month's causes(ns):\n%s\n%s" % [read, at_opinion["c"]])
	# A copy: a reader that edits what it got cannot rewrite the saved month.
	(read["rows"] as Dictionary)["neutral"] = -1.0
	if float(Opinion.causes_of(entry)["rows"]["neutral"]) == -1.0:
		_fail("causes_of() handed out the history entry's own dictionary")
	# A mid-month snapshot (Trends.snapshot_now) carries no split: only History adds it.
	if Opinion.snapshot(state).has("approval_causes"):
		_fail("Opinion.snapshot carries the split; a mid-month caller would read an unticked one")
	# Through a save: the split survives the round trip (JSON may cost the last bits).
	var loaded = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	var back: Dictionary = Opinion.causes_of(loaded.history[-1])
	if absf(float(back.get("target", NAN)) - float(read["target"])) > 1e-6 \
			or absf(float((back.get("rows", {}) as Dictionary).get("time_in_office", NAN)) - float(read["rows"]["time_in_office"])) > 1e-6:
		_fail("the split did not survive a save: %s" % [back])


## A history entry saved before the split existed carries no key, and reads as no split:
## {} -- "no comparison yet" for a reader, never a split of zeros that would claim
## nothing moved.
func _test_an_entry_from_before_reads_as_no_split() -> void:
	var old := {"overall_approval_pct": 48.0, "bloc_approval": {}, "issue_salience": {}}
	if not Opinion.causes_of(old).is_empty():
		_fail("an entry without the split reads as %s, not {}" % [Opinion.causes_of(old)])


func _austerity_run() -> Dictionary:
	var state = GameState.new_game(_loader, "FRA")
	state.year = 2026
	state.month = 1
	var ns = state.player()
	var pending := {}
	for field in AUSTERITY.keys():
		var start: Dictionary = ns.start_tax_rates_pct if field == "tax_rates_pct" else ns.start_spending_pct_gdp
		var values := {}
		for key in AUSTERITY[field]:
			values[key] = clampf(float(start.get(key, 0.0)) + float(AUSTERITY[field][key]), 0.0, 100.0)
		pending[field] = values
	FinanceBill.table(state, _loader, FinanceBill.from_pending(ns, pending))
	return {"state": state}


func _next_month(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


## The tick's own target, size-weighted: target_of over the six blocs, each cut to the
## approval band the tick clamps that bloc's approval to.
func _independent_target(ns) -> float:
	var sat := Opinion.issue_satisfaction(ns)
	var total := 0.0
	for bloc in K.BLOC_KEYS:
		total += float(K.BLOC_SIZE[bloc]) * clampf(Opinion.target_of(ns, bloc, sat, Opinion.bloc_weights(ns, bloc, sat)), K.APPROVAL_MIN, K.APPROVAL_MAX)
	return total


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_approval_causes: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
