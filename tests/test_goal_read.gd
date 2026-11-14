extends SceneTree

## V5.3 e: what moves a goal (docs/design/finance-bill.md section 11, the author's laws
## direction B, the parent's rulings of 2026-11-14). Tier 1 reads every measure (each open
## law at its own size, each spending line and each tax rate in force by a standard step)
## once on a copy, through the game's own appliers; a goal ranks those reads. Tier 2 runs
## one measure's projection against the month's baseline. Both are kept for the month.
## Nothing here writes the game.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Bills = preload("res://src/sim/bills.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const GoalRead = preload("res://src/sim/goal_read.gd")
const GK = preload("res://src/sim/goal_read_constants.gd")

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	var state = _new_state()
	var list = _full_list(state)
	_check_the_measures_are_every_law_and_every_step_in_range(state)
	_check_a_step_costs_what_the_preview_books(state, list)
	_check_a_bloc_offset_law_ranks_for_its_bloc_only(state, list)
	_check_a_structural_law_reads_its_offset_on_unemployment(state, list)
	_check_a_demand_step_is_listed_unread_on_unemployment(list)
	_check_the_chance_is_the_forecast(state, list)
	_check_a_pledge_reads_through_its_field(state, list)
	_check_the_list_is_kept_for_the_month(state, list)
	_check_the_reads_write_nothing()
	_check_two_years_is_the_projection_against_the_baseline(state)
	_check_a_law_closed_mid_month_is_read_as_gone()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("PASS tests/test_goal_read.gd")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL " + f)
	quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _new_state():
	var state = GameState.new_game(_loader, "FRA")
	state.year = 2026
	state.month = 3
	return state


func _full_list(state):
	var list = GoalRead.list_for(null, state, _loader)
	while not list.done():
		GoalRead.step(list)
	return list


func _read_of(list, kind: String, key: String) -> Dictionary:
	for read in list.reads:
		var m: Dictionary = read["measure"]
		if String(m["kind"]) == kind and String(m.get("id", m.get("key", ""))) == key:
			return read
	return {}


func _check_the_measures_are_every_law_and_every_step_in_range(state) -> void:
	var ns = state.player()
	var laws: Array = Legislature.available(ns, Bills.open(state, ns, _loader))
	var measures: Array = GoalRead.measures(state, _loader)
	var counts := {"law": 0, "line": 0, "rate": 0}
	for m in measures:
		counts[String(m["kind"])] += 1
	if counts["law"] != laws.size():
		_fail("measures: %d law rows for %d open laws" % [counts["law"], laws.size()])
	if counts["line"] != 2 * EK.SPENDING_KEYS.size():
		_fail("measures: %d line steps, not two per spending line" % counts["line"])
	var rates := 0
	for kind in ns.tax_rates_pct:
		var band: Array = ns.tax_library[kind]["rate_range_pct"]
		for step in [-GK.RATE_STEP, GK.RATE_STEP]:
			var landed: float = float(ns.tax_rates_pct[kind]) + float(step)
			if landed >= float(band[0]) and landed <= float(band[1]):
				rates += 1
	if counts["rate"] != rates:
		_fail("measures: %d rate steps, not the %d inside each kind's band" % [counts["rate"], rates])
	for m in measures:
		if String(m["kind"]) == "rate" and String(m["key"]) == "wealth" and float(m["step"]) < 0.0 and float(ns.tax_rates_pct["wealth"]) < GK.RATE_STEP:
			_fail("measures: a cut below the wealth tax's floor was offered")


func _check_a_step_costs_what_the_preview_books(state, list) -> void:
	var ns = state.player()
	var read := _read_of(list, "line", "health")
	if read.is_empty():
		_fail("step: no health line read")
		return
	var step := float(read["measure"]["step"])
	var now := Budget.preview(state, {})
	var after := Budget.preview(state, {"spending_pct_gdp": {"health": float(ns.spending_pct_gdp["health"]) + step}})
	var want := (float(now["deficit_pct_gdp"]) * float(now["gdp_eur_bn"]) - float(after["deficit_pct_gdp"]) * float(after["gdp_eur_bn"])) / 100.0
	if not is_equal_approx(float(read["cost_bn"]), want):
		_fail("step: the health step reads %s bn a year, the preview books %s" % [read["cost_bn"], want])


## A law whose only effect is a bloc_offset moves those blocs' targets by the offset
## times APPROVAL_SPAN, ranks on their goals, and is absent from every other bloc's.
func _check_a_bloc_offset_law_ranks_for_its_bloc_only(state, list) -> void:
	var law = null
	for l in Legislature.available(state.player(), Bills.open(state, state.player(), _loader)):
		if l.effects.keys() == ["bloc_offset"]:
			law = l
			break
	if law == null:
		_fail("stage: no open law of bloc_offset alone")
		return
	var read := _read_of(list, "law", law.id)
	var offsets: Dictionary = law.effects["bloc_offset"]
	for bloc in OpinionK.BLOC_KEYS:
		var moved := float(read["bloc_target"].get(bloc, 0.0))
		var want := OpinionK.APPROVAL_SPAN * float(offsets.get(bloc, 0.0))
		if not is_equal_approx(moved, want):
			_fail("bloc: %s moves %s's target by %s, not %s" % [law.id, bloc, moved, want])
		var listed := false
		for row in GoalRead.rank(list.reads, "bloc:" + bloc, state, _loader):
			if String(row["measure"].get("id", "")) == law.id:
				listed = true
		if listed != (float(offsets.get(bloc, 0.0)) != 0.0):
			_fail("bloc: %s listed=%s on %s's goal, with an offset of %s" % [law.id, listed, bloc, offsets.get(bloc, 0.0)])
	if float(read["cost_bn"]) != 0.0:
		_fail("bloc: a law of bloc_offset alone costs %s" % read["cost_bn"])


func _check_a_structural_law_reads_its_offset_on_unemployment(state, list) -> void:
	var law = null
	for l in Legislature.available(state.player(), Bills.open(state, state.player(), _loader)):
		if l.effects.has("structural_unemployment_pct") and not l.effects.has("tax_rates_pct"):
			law = l
			break
	if law == null:
		_fail("stage: no open law with a structural unemployment offset")
		return
	var read := _read_of(list, "law", law.id)
	if not is_equal_approx(float(read["unemployment_target"]), float(law.effects["structural_unemployment_pct"])):
		_fail("unemployment: %s moves the structural target by %s, its offset is %s" % [law.id, read["unemployment_target"], law.effects["structural_unemployment_pct"]])
	var rows: Array = GoalRead.rank(list.reads, "unemployment", state, _loader)
	var found := false
	for row in rows:
		if String(row["measure"].get("id", "")) == law.id:
			found = bool(row["read"]) and is_equal_approx(float(row["effect"]), -float(law.effects["structural_unemployment_pct"]))
	if not found:
		_fail("unemployment: %s is not ranked with its read effect" % law.id)
	for i in range(1, rows.size()):
		if bool(rows[i]["read"]) and bool(rows[i - 1]["read"]) and float(rows[i]["effect"]) > float(rows[i - 1]["effect"]):
			_fail("unemployment: the read rows are not ranked by effect")
			break


## A spending step moves unemployment through demand, which tier 1 cannot size: listed,
## marked unread, with the sign of the demand impulse it raises.
func _check_a_demand_step_is_listed_unread_on_unemployment(list) -> void:
	var rows: Array = GoalRead.rank(list.reads, "unemployment", null, _loader)
	var up := {}
	for row in rows:
		var m: Dictionary = row["measure"]
		if String(m["kind"]) == "line" and String(m["key"]) == "infrastructure":
			up[float(m["step"]) > 0.0] = row
	if up.size() != 2:
		_fail("demand: the infrastructure steps are not both listed on unemployment: %s" % [up.keys()])
		return
	if bool(up[true]["read"]) or int(up[true]["sign"]) != 1 or int(up[false]["sign"]) != -1:
		_fail("demand: a spending rise reads %s, a cut %s (want unread, +1 and -1)" % [up[true], up[false]])


func _check_the_chance_is_the_forecast(state, list) -> void:
	var ns = state.player()
	var parties: Array = _loader.parties["FRA"]
	for law in Legislature.available(ns, Bills.open(state, ns, _loader)).slice(0, 10):
		var forecast := Legislature.resolve_vote(ns, parties, law, Legislature.takes_route(ns, law, false))
		var read := _read_of(list, "law", law.id)
		if bool(read["passes"]) != bool(forecast["passed"]) or int(read["yes"]) != int(forecast["yes_seats"]):
			_fail("chance: %s reads %s, the forecast %s" % [law.id, [read["passes"], read["yes"]], [forecast["passed"], forecast["yes_seats"]]])


func _check_a_pledge_reads_through_its_field(state, list) -> void:
	var growth := GoalRead.rank(list.reads, "field:growth_annual_pct", state, _loader)
	if growth.size() != 1 or not bool(growth[0].get("no_read", false)):
		_fail("pledge: a growth goal does not say it has no tier-1 read: %s" % [growth.slice(0, 1)])
	var emissions := GoalRead.rank(list.reads, "field:co2e_per_capita_t", state, _loader)
	if emissions.size() != 1 or not bool(emissions[0].get("no_read", false)):
		_fail("pledge: an emissions goal does not say it has no tier-1 read")
	var deficit := GoalRead.rank(list.reads, "field:deficit_pct_gdp", state, _loader)
	if deficit != GoalRead.rank(list.reads, "deficit", state, _loader):
		_fail("pledge: a deficit pledge does not rank as the deficit goal")


func _check_the_list_is_kept_for_the_month(state, list) -> void:
	if GoalRead.list_for(list, state, _loader) != list:
		_fail("cache: the same month built a second list")
	state.month = 4
	var next = GoalRead.list_for(list, state, _loader)
	if next == list or next.done():
		_fail("cache: a new month kept last month's list")
	state.month = 3


func _check_the_reads_write_nothing() -> void:
	var state = _new_state()
	var before := JSON.stringify(state.to_dict())
	_full_list(state)
	if JSON.stringify(state.to_dict()) != before:
		_fail("write: reading every measure changed the game")


## Tier 2 at three months (the game's run is 24; three keeps the test cheap): the
## measure's path against the baseline, each the real projection.
func _check_two_years_is_the_projection_against_the_baseline(state) -> void:
	var ns = state.player()
	var step := {"kind": "line", "key": "education", "step": GK.SPENDING_STEP}
	var years = GoalRead.years_for(null, state, _loader, step, 3)
	while not years.done():
		years.step()
	var base := Budget.project(state, {}, 3, _loader)
	var with := Budget.project(state, {"spending_pct_gdp": {"education": float(ns.spending_pct_gdp["education"]) + GK.SPENDING_STEP}}, 3, _loader)
	var got: Dictionary = years.result()
	for key in ["unemployment_pct", "deficit_pct_gdp", "debt_to_gdp_pct", "growth_annual_pct"]:
		var want := float(with[2][key]) - float(base[2][key])
		if float(got[key]) != want:
			_fail("two years: %s moved %s, the projections %s" % [key, got[key], want])
	var again = GoalRead.years_for(years, state, _loader, {"kind": "line", "key": "health", "step": GK.SPENDING_STEP}, 3)
	if again.baseline != years.baseline:
		_fail("two years: a second measure the same month ran the baseline again")


## The list is kept for the month, so a law the player tables or passes after it was built
## is no longer open when its turn comes: read as gone, never ranked, and no crash.
func _check_a_law_closed_mid_month_is_read_as_gone() -> void:
	var state = _new_state()
	var ns = state.player()
	var list = GoalRead.list_for(null, state, _loader)
	var gone := String(list.measures[0]["id"])
	ns.law_cooldown_months[gone] = 3
	while not list.done():
		GoalRead.step(list)
	if not bool(list.reads[0].get("unavailable", false)):
		_fail("closed: a law no longer open was read as if it were: %s" % [list.reads[0].keys()])
	for goal in ["deficit", "unemployment", "approval"]:
		for row in GoalRead.rank(list.reads, goal, state, _loader):
			if String(row["measure"].get("id", "")) == gone:
				_fail("closed: a law no longer open ranks on %s" % goal)
	if GoalRead.years_for(null, state, _loader, list.measures[0], 3) != null:
		_fail("closed: two years were begun for a law no longer open")
