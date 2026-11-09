extends SceneTree

## V5.3 a (docs/design/v5.3-ab.md 3.3 (a), band A7): the regional development
## fund -- N bn a year to one region for 1 to 5 years -- and the opened region's
## one problem. The fund's money is a Budget line of its own; its effect is a term
## in the region's growth deviation, zero-mean like the sited-project term (the
## national level comes through the spending), so the region's unemployment falls
## and the nation's regions still sum to the nation. A7's 24-month figure is
## tools/region_probe.gd's, on the game's own month; this file pins the mechanism.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const RegionsLoader = preload("res://src/core/loaders/regions_loader.gd")
const Regions = preload("res://src/sim/regions.gd")
const RegionFunds = preload("res://src/sim/region_funds.gd")
const RK = preload("res://src/sim/region_constants.gd")
const FK = preload("res://src/sim/region_fund_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Budget = preload("res://src/sim/budget.gd")

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_the_rule_loads_and_refuses_a_bad_row()
	_test_start_refusals_write_nothing()
	_test_a_fund_stores_its_term_and_moves_the_blocs_by_population()
	_test_the_same_level_is_the_same_effort_in_every_nation()
	_test_the_region_gains_and_the_nation_is_unchanged()
	_test_the_estimate_is_what_the_start_books()
	_test_the_bill_runs_for_the_fund_and_stops()
	_test_stopping_ends_the_term_and_the_bill()
	_test_one_fund_per_region()
	_test_the_register_survives_a_save()
	_test_the_one_problem()
	_test_the_funded_region_grows_faster()
	_test_the_forecast_sees_the_fund_end()
	_test_three_funds_at_most()
	_test_the_snapshot_carries_the_bill()
	_test_the_bill_moves_demand_as_spending_does()
	_finish()


func _state(nation := "FRA"):
	return GameState.new_game(_loader, nation)


func _list(state, nation := "FRA") -> Array:
	return state.regions.get(nation, [])


func _access(state, ns) -> Dictionary:
	return Regions.accessibility_for(ns, _list(state, ns.id), state.region_graph)


func _sites(state, ns) -> Dictionary:
	return state.project_sited_pct.get(ns.id, {})


func _unemployment(state, ns, region_id: String) -> float:
	return Regions.unemployment_pct(ns, _list(state, ns.id), region_id, _access(state, ns), _sites(state, ns))


## The named region with the highest unemployment (the first on a tie).
func _worst(state, ns) -> String:
	var u := Regions.unemployment_by_region(ns, _list(state, ns.id), _access(state, ns), _sites(state, ns))
	var best := ""
	for region in _list(state, ns.id):
		if region.id == RK.RESIDUAL_KEY:
			continue
		if best == "" or float(u[region.id]) > float(u[best]):
			best = region.id
	return best


func _test_the_rule_loads_and_refuses_a_bad_row() -> void:
	var rule: Dictionary = _loader.region_fund_rule
	for key in ["share_pct", "years", "bloc_offset_per_pct"]:
		if not rule.has(key):
			_fail("the fund rule lacks %s: %s" % [key, rule])
	# The panel prints the range from limits(), since the refusal msgids carry no figures.
	var lim: Dictionary = RegionFunds.limits(_loader)
	if lim.get("share_pct", []) != rule.get("share_pct") or lim.get("years", []) != rule.get("years"):
		_fail("limits() is %s, not the rule's ranges" % [lim])
	var good := {"share_pct": [1.0, 3.0], "years": [1, 5], "bloc_offset_per_pct": {"workers": 0.04},
		"arrival": {"ratio": 1.25, "rearm_months": 24}}
	var cases := {
		"a range upside down": func(r: Dictionary) -> void: r["share_pct"] = [3.0, 1.0],
		"a zero floor": func(r: Dictionary) -> void: r["share_pct"] = [0.0, 3.0],
		"years not whole": func(r: Dictionary) -> void: r["years"] = [1.5, 5],
		"an unknown bloc": func(r: Dictionary) -> void: r["bloc_offset_per_pct"] = {"wizards": 0.1},
		"no offsets": func(r: Dictionary) -> void: r.erase("bloc_offset_per_pct"),
		"no arrival": func(r: Dictionary) -> void: r.erase("arrival"),
		"an arrival at the nation's own level": func(r: Dictionary) -> void: r["arrival"]["ratio"] = 1.0,
		"a part month's rearm": func(r: Dictionary) -> void: r["arrival"]["rearm_months"] = 1.5,
	}
	var errors: Array[String] = []
	RegionsLoader.parse_fund_rule(good.duplicate(true), "fund.json", errors)
	if not errors.is_empty():
		_fail("a good fund rule was refused: %s" % [errors])
	for label in cases:
		var raw := good.duplicate(true)
		(cases[label] as Callable).call(raw)
		var e: Array[String] = []
		RegionsLoader.parse_fund_rule(raw, "fund.json", e)
		if e.is_empty():
			_fail("the fund rule accepted %s" % label)


func _test_start_refusals_write_nothing() -> void:
	var state = _state()
	var ns = state.player()
	var region := _worst(state, ns)
	var lo := float(_loader.region_fund_rule["share_pct"][0])
	var hi := float(_loader.region_fund_rule["share_pct"][1])
	var bad := {
		"an unknown region": ["FRZ", 1.0, 2],
		"the residual": [RK.RESIDUAL_KEY, 1.0, 2],
		"too small a share": [region, lo * 0.5, 2],
		"too large a share": [region, hi * 2.0, 2],
		"no years": [region, 1.0, 0],
		"too many years": [region, 1.0, 99],
	}
	var debt := float(ns.debt_eur_bn)
	var offsets: Dictionary = (ns.bloc_offset as Dictionary).duplicate()
	for label in bad:
		var a: Array = bad[label]
		var r: Dictionary = RegionFunds.start(state, ns, _loader, String(a[0]), float(a[1]), int(a[2]))
		if bool(r.get("ok", true)) or String(r.get("reason", "")) == "":
			_fail("start accepted %s, or refused with no reason: %s" % [label, r])
	if not ns.region_funds.is_empty() or float(ns.debt_eur_bn) != debt or ns.bloc_offset != offsets:
		_fail("a refused start wrote the nation")


## The term is stored at the start (the strip's figure is the booked one), as
## FUND_BETA x sqrt(the fund as a share of the region's output, in points); the
## bloc move is the rule's offsets per level x the level x the region's population share.
func _test_a_fund_stores_its_term_and_moves_the_blocs_by_population() -> void:
	var state = _state()
	var ns = state.player()
	var region := _worst(state, ns)
	var gdp := Regions.output_eur_bn(ns, region)
	var before: Dictionary = (ns.bloc_offset as Dictionary).duplicate()
	var r: Dictionary = RegionFunds.start(state, ns, _loader, region, 1.0, 2)
	if not bool(r.get("ok", false)):
		_fail("a good fund was refused: %s" % r)
		return
	var row: Dictionary = ns.region_funds[0]
	var eur := 0.01 * gdp
	if not is_equal_approx(float(row["eur_bn_per_year"]), eur):
		_fail("a fund of 1 %% costs %.4f bn a year, not 1 %% of the region's %.2f bn" % [float(row["eur_bn_per_year"]), gdp])
	var want: float = FK.FUND_BETA * sqrt(1.0)
	if not is_equal_approx(float(row["pts"]), want):
		_fail("the fund's term is %.4f, not %.4f" % [float(row["pts"]), want])
	var pop := float(ns.region_pop_share.get(region, 0.0))
	var per_pct: Dictionary = _loader.region_fund_rule["bloc_offset_per_pct"]
	for bloc in per_pct:
		var moved := float(ns.bloc_offset.get(bloc, 0.0)) - float(before.get(bloc, 0.0))
		var bloc_want := clampf(float(before.get(bloc, 0.0)) + float(per_pct[bloc]) * 1.0 * pop,
			LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX) - float(before.get(bloc, 0.0))
		if not is_equal_approx(moved, bloc_want) or moved == 0.0:
			_fail("%s moved %.6f, not %.6f (the offset per level x population share)" % [bloc, moved, bloc_want])


## The author, 2026-11-09: one bn was 0.12 % of London and 2.2 % of Germany's DE5, so "the same
## fund" was not the same effort. At one level the term is the same everywhere; the bill is not.
func _test_the_same_level_is_the_same_effort_in_every_nation() -> void:
	var terms := {}
	var euros := {}
	for nation in ["DEU", "FRA", "GBR", "POL"]:
		var state = GameState.new_game(_loader, nation)
		var ns = state.player()
		var region := _worst(state, ns)
		var opened: Dictionary = RegionFunds.start(state, ns, _loader, region, 2.0, 2)
		if not bool(opened.get("ok", false)):
			_fail("%s: a fund at 2 %% was refused: %s" % [nation, opened])
			continue
		var row: Dictionary = ns.region_funds[0]
		terms[nation] = float(row["pts"])
		euros[nation] = float(row["eur_bn_per_year"])
		# The parent's ruling on #316: the blocs read the level and the region's people, not the euros.
		for bloc in _loader.region_fund_rule["bloc_offset_per_pct"]:
			var offset_want := float(_loader.region_fund_rule["bloc_offset_per_pct"][bloc]) * 2.0 * float(ns.region_pop_share.get(region, 0.0))
			if not is_equal_approx(float(row["bloc_offset"][bloc]), offset_want):
				_fail("%s: %s moves %.5f at 2 %%, not %.5f" % [nation, bloc, float(row["bloc_offset"][bloc]), offset_want])
		if not is_equal_approx(float(row["eur_bn_per_year"]), 0.02 * Regions.output_eur_bn(ns, region)):
			_fail("%s: the bill is %.3f bn, not 2 %% of the region" % [nation, float(row["eur_bn_per_year"])])
	for nation in terms:
		if not is_equal_approx(float(terms[nation]), FK.FUND_BETA * sqrt(2.0)):
			_fail("%s: the term at 2 %% is %.4f" % [nation, float(terms[nation])])
	if not euros.has("GBR") or float(euros["GBR"]) <= 2.0 * float(euros.get("DEU", 0.0)):
		_fail("the same level in London and in DE5 cost the same: %s" % [euros])


## The term is zero-mean over the nation's output shares: the funded region's
## deviation rises by pts x (1 - its weight), each other region's falls by its
## weight's share, and the output-weighted sum is unchanged -- so the funded
## region's unemployment falls by OKUN x that, and the nation's total GDP is moved
## only by the spending.
func _test_the_region_gains_and_the_nation_is_unchanged() -> void:
	var state = _state()
	var ns = state.player()
	var list := _list(state)
	var region := _worst(state, ns)
	var other := ""
	for r in list:
		if r.id != region and r.id != RK.RESIDUAL_KEY:
			other = r.id
			break
	var access := _access(state, ns)
	var sites := _sites(state, ns)
	var dev0 := {}
	for r in list:
		dev0[r.id] = Regions.trend_deviation_pct(ns, list, r.id, access, sites)
	var u0 := _unemployment(state, ns, region)
	var o0 := _unemployment(state, ns, other)
	RegionFunds.start(state, ns, _loader, region, 1.0, 2)
	var pts := float(ns.region_funds[0]["pts"])
	var shares := Regions.shares_of(ns, list)
	var total := 0.0
	for r in list:
		total += float(shares[r.id])
	var w := float(shares[region]) / total
	var gain := Regions.trend_deviation_pct(ns, list, region, access, sites) - float(dev0[region])
	if not is_equal_approx(gain, pts * (1.0 - w)):
		_fail("the funded region's deviation rose %.6f, not pts x (1 - w) = %.6f" % [gain, pts * (1.0 - w)])
	var weighted := 0.0
	for r in list:
		weighted += float(shares[r.id]) * (Regions.trend_deviation_pct(ns, list, r.id, access, sites) - float(dev0[r.id]))
	if absf(weighted) > 1e-9:
		_fail("the fund moved the output-weighted deviation by %.3e: not zero-mean" % weighted)
	var u1 := _unemployment(state, ns, region)
	if not is_equal_approx(u0 - u1, C.OKUN * pts * (1.0 - w)):
		_fail("the region's unemployment fell %.4f, not OKUN x the gain %.4f" % [u0 - u1, C.OKUN * pts * (1.0 - w)])
	if _unemployment(state, ns, other) <= o0:
		_fail("another region's unemployment did not rise a little with the zero-mean term")
	# The three copies of the deviation arithmetic agree with a fund live.
	var by := Regions.unemployment_by_region(ns, list, access, sites)
	for r in list:
		if not is_equal_approx(float(by[r.id]), _unemployment(state, ns, r.id)):
			_fail("unemployment_by_region and unemployment_pct disagree on %s with a fund" % r.id)


## The strip shows the booked figures (B1's rule, here for the fund).
func _test_the_estimate_is_what_the_start_books() -> void:
	var state = _state()
	var ns = state.player()
	var region := _worst(state, ns)
	var est: Dictionary = RegionFunds.estimate(state, ns, _loader, region, 1.0, 2)
	if not bool(est.get("ok", false)):
		_fail("the estimate refused a good fund: %s" % est)
		return
	if not is_equal_approx(float(est["unemployment_now"]), _unemployment(state, ns, region)):
		_fail("the estimate's unemployment now is not the region's")
	RegionFunds.start(state, ns, _loader, region, 1.0, 2)
	if not is_equal_approx(float(est["unemployment_after"]), _unemployment(state, ns, region)):
		_fail("the estimate said %.4f %%, the start booked %.4f %%" % [float(est["unemployment_after"]), _unemployment(state, ns, region)])
	if not is_equal_approx(float(est["pts"]), float(ns.region_funds[0]["pts"])):
		_fail("the estimate's term is not the booked term")
	var eur := float(ns.region_funds[0]["eur_bn_per_year"])
	if not is_equal_approx(float(est["total_eur_bn"]), 2.0 * eur) or not is_equal_approx(float(est["eur_bn_per_year"]), eur):
		_fail("the estimate's money is wrong: %s" % est)


## The bill is the fund's bn a year as a share of GDP, written by the tick for the
## Budget to read (a month behind, the other computed lines' lag), for exactly
## years x 12 months; then the fund closes and the bill is zero.
func _test_the_bill_runs_for_the_fund_and_stops() -> void:
	var state = _state()
	var ns = state.player()
	var region := _worst(state, ns)
	RegionFunds.start(state, ns, _loader, region, 2.0, 1)
	var months := 0
	for i in range(14):
		_month(state)
		if float(ns.region_fund_bill_pct_gdp) > 0.0:
			months += 1
			if not is_equal_approx(float(ns.region_fund_bill_pct_gdp), 100.0 * float(ns.region_funds[0]["eur_bn_per_year"]) / float(ns.gdp_eur_bn)):
				_fail("the bill is %.5f %% of GDP, not the fund's euros / GDP" % float(ns.region_fund_bill_pct_gdp))
	if months != 12:
		_fail("a one-year fund billed %d months, not 12" % months)
	if String(ns.region_funds[0]["status"]) != "done":
		_fail("a fund past its years is %s, not done" % ns.region_funds[0]["status"])
	var spending := float(ns.total_spending_pct_gdp)
	ns.region_fund_bill_pct_gdp = 1.0
	Budget.recompute(state, ns)
	if not is_equal_approx(float(ns.total_spending_pct_gdp) - spending, 1.0):
		_fail("the Budget does not count the fund's bill")


func _test_stopping_ends_the_term_and_the_bill() -> void:
	var state = _state()
	var ns = state.player()
	var region := _worst(state, ns)
	var u0 := _unemployment(state, ns, region)
	var before: Dictionary = (ns.bloc_offset as Dictionary).duplicate()
	RegionFunds.start(state, ns, _loader, region, 1.0, 3)
	var gained: Dictionary = (ns.bloc_offset as Dictionary).duplicate()
	var r: Dictionary = RegionFunds.stop(state, ns, String(ns.region_funds[0]["id"]))
	if not bool(r.get("ok", false)):
		_fail("a live fund could not be stopped: %s" % r)
		return
	if not is_equal_approx(_unemployment(state, ns, region), u0):
		_fail("a stopped fund still lowers the region's unemployment")
	_month(state)
	if float(ns.region_fund_bill_pct_gdp) != 0.0:
		_fail("a stopped fund still bills")
	# The U-turn: every bloc the fund pleased gives back FUND_STOP_SHARE of what it gained.
	for bloc in gained:
		var up := float(gained[bloc]) - float(before.get(bloc, 0.0))
		if up > 0.0 and not is_equal_approx(float(ns.bloc_offset[bloc]), float(gained[bloc]) - FK.FUND_STOP_SHARE * up):
			_fail("%s did not give back the stop share of its gain" % bloc)
	if bool(RegionFunds.stop(state, ns, String(ns.region_funds[0]["id"])).get("ok", true)):
		_fail("a stopped fund was stopped twice")


func _test_one_fund_per_region() -> void:
	var state = _state()
	var ns = state.player()
	var region := _worst(state, ns)
	RegionFunds.start(state, ns, _loader, region, 1.0, 2)
	var r: Dictionary = RegionFunds.start(state, ns, _loader, region, 1.0, 2)
	if bool(r.get("ok", true)) or ns.region_funds.size() != 1:
		_fail("a second fund opened in a region that has one")


## absent_ok: no save before V5.3 a held a fund, so absent is "none".
func _test_the_register_survives_a_save() -> void:
	var state = _state()
	var ns = state.player()
	var region := _worst(state, ns)
	RegionFunds.start(state, ns, _loader, region, 1.0, 2)
	var u := _unemployment(state, ns, region)
	var kept = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	# The snapshot rides the row through a save (the register's absent_ok is unchanged).
	var start_row: Dictionary = (ns.region_funds as Array)[0]
	# Within a printed tenth: the JSON here is not the save's full-precision writer.
	if absf(float((kept.player().region_funds as Array)[0].get("unemployment_at_start", -1.0)) - float(start_row.get("unemployment_at_start", -2.0))) > 0.001:
		_fail("save: the fund's start figure did not survive the round trip")
	kept.regions = state.regions
	kept.region_graph = state.region_graph
	if not is_equal_approx(_unemployment(kept, kept.player(), region), u):
		_fail("a saved fund did not survive the round trip")
	var raw: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(raw["nations"]["FRA"] as Dictionary).erase("region_funds")
	if not GameState.from_dict(raw).player().region_funds.is_empty():
		_fail("an absent register did not read as no fund")


## The opened region's one problem: its worst figure against the nation, the
## larger of unemployment / the nation's and the nation's output per head / its
## own (ties to unemployment). Britain's regions are measured since V5.3 (ONS), so
## the same rule has to hold for them as for France: London's problem is the
## unemployment above the nation's, the North East's the output below it.
func _test_the_one_problem() -> void:
	var state = _state()
	var ns = state.player()
	var list := _list(state)
	var region := _worst(state, ns)
	var p: Dictionary = Regions.problem(ns, list, region, _access(state, ns), _sites(state, ns),
		float(ns.region_pop_share.get(region, 0.0)))
	for key in ["kind", "value", "nation", "ratio"]:
		if not p.has(key):
			_fail("the one problem lacks %s: %s" % [key, p])
			return
	var u := _unemployment(state, ns, region)
	var idx := Regions.gdp_per_head_index(ns, list, region, float(ns.region_pop_share.get(region, 0.0)))
	var u_ratio := u / float(ns.unemployment_pct)
	var g_ratio := 1.0 / idx if idx > 0.0 else 0.0
	var kind := "unemployment" if u_ratio >= g_ratio else "output_per_head"
	if String(p["kind"]) != kind or not is_equal_approx(float(p["ratio"]), maxf(u_ratio, g_ratio)):
		_fail("the one problem is %s, not %s at x%.3f" % [p, kind, maxf(u_ratio, g_ratio)])
	var gbr = _state("GBR")
	var g = gbr.player()
	var glist := _list(gbr, "GBR")
	var kinds := {}
	for r in glist:
		if r.id == RK.RESIDUAL_KEY:
			continue
		var gshare := float(g.region_pop_share.get(r.id, 0.0))
		var gp: Dictionary = Regions.problem(g, glist, r.id, _access(gbr, g), _sites(gbr, g), gshare)
		var gu_ratio := _unemployment(gbr, g, r.id) / float(g.unemployment_pct)
		var gidx := Regions.gdp_per_head_index(g, glist, r.id, gshare)
		var gg_ratio := 1.0 / gidx if gidx > 0.0 else 0.0
		var gkind := "unemployment" if gu_ratio >= gg_ratio else "output_per_head"
		if String(gp["kind"]) != gkind or not is_equal_approx(float(gp["ratio"]), maxf(gu_ratio, gg_ratio)):
			_fail("a British region's problem is %s, not %s at x%.3f" % [gp, gkind, maxf(gu_ratio, gg_ratio)])
		kinds[String(gp["kind"])] = true
	if kinds.size() < 2:
		_fail("Britain's measured regions all share one kind of problem (%s): the ONS figures should split them" % [kinds.keys()])


## The level path (Regions.tick_month, the third copy of the deviation arithmetic):
## the same national growth grows the funded region faster than its unfunded twin,
## and the nation's sum moves only at second order (zero-mean in rates).
func _test_the_funded_region_grows_faster() -> void:
	var still = _state()
	var funded = _state()
	var region := _worst(still, still.player())
	RegionFunds.start(funded, funded.player(), _loader, region, 1.0, 2)
	var totals := []
	var shares := []
	for state in [still, funded]:
		var ns = state.player()
		totals.append(Regions.tick_month(ns, _list(state), 1.0, _access(state, ns), _sites(state, ns)))
		shares.append(Regions.share_of(ns, region))
	if float(shares[1]) <= float(shares[0]):
		_fail("a month of the same growth left the funded region's share at %.6f, not above %.6f" % [shares[1], shares[0]])
	if absf(float(totals[1]) - float(totals[0])) > 1e-6 * float(totals[0]):
		_fail("the fund moved the nation's summed output by %.4f bn in a month: not zero-mean" % (float(totals[1]) - float(totals[0])))


## Budget.project() ticks the funds in WorldMonth's slot, so a forecast books the
## fund's bill while it runs and drops it when its years are over.
func _test_the_forecast_sees_the_fund_end() -> void:
	var still = _state()
	var funded = _state()
	var region := _worst(still, still.player())
	RegionFunds.start(funded, funded.player(), _loader, region, 2.0, 1)
	var a: Array = Budget.project(still, {}, 24, _loader)
	var b: Array = Budget.project(funded, {}, 24, _loader)
	var during := float(b[5]["total_spending_pct_gdp"]) - float(a[5]["total_spending_pct_gdp"])
	var after := float(b[20]["total_spending_pct_gdp"]) - float(a[20]["total_spending_pct_gdp"])
	var bill := 100.0 * float(funded.player().region_funds[0]["eur_bn_per_year"]) / float(funded.player().gdp_eur_bn)
	if absf(during - bill) > 0.1 * bill:
		_fail("the forecast's spending in the fund's sixth month is up %.4f, not about its bill %.4f" % [during, bill])
	if absf(after) > 0.1 * bill:
		_fail("the forecast still books %.4f of spending after the fund ended" % after)


## The parent's cap: at most three funds open at once, so funding every region
## (where the zero-mean term cancels and only the spending is left) is not a verb.
## Pinned as the literal 3 (QA on #248: a test that read the constant stayed green
## when it moved); a stopped or finished fund frees its place.
func _test_three_funds_at_most() -> void:
	var state = _state()
	var ns = state.player()
	var regions: Array = []
	for r in _list(state):
		if r.id != RK.RESIDUAL_KEY:
			regions.append(String(r.id))
	for i in range(3):
		if not bool(RegionFunds.start(state, ns, _loader, regions[i], 1.0, 2).get("ok", false)):
			_fail("fund %d of 3 was refused" % (i + 1))
	var fourth: Dictionary = RegionFunds.start(state, ns, _loader, regions[3], 1.0, 2)
	if bool(fourth.get("ok", true)) or String(fourth.get("reason", "")) == "" or ns.region_funds.size() != 3:
		_fail("a fourth fund opened while three ran: %s" % fourth)
	if int(RegionFunds.limits(_loader).get("max_open", -1)) != 3:
		_fail("limits() does not give the panel the cap of 3")
	RegionFunds.stop(state, ns, String(ns.region_funds[0]["id"]))
	if not bool(RegionFunds.start(state, ns, _loader, regions[3], 1.0, 2).get("ok", false)):
		_fail("a stopped fund did not free its place")


## Interface's Budget row reads the bill off the snapshot, as every computed line's
## row does (the projection has no NationState for the panel to reach).
func _test_the_snapshot_carries_the_bill() -> void:
	var state = _state()
	var ns = state.player()
	RegionFunds.start(state, ns, _loader, _worst(state, ns), 2.0, 1)
	_month(state)
	var snap: Dictionary = Budget.snapshot(state)
	if not snap.has("region_fund_bill_pct_gdp") or float(ns.region_fund_bill_pct_gdp) <= 0.0 \
			or not is_equal_approx(float(snap["region_fund_bill_pct_gdp"]), float(ns.region_fund_bill_pct_gdp)):
		_fail("the Budget snapshot does not carry the fund's bill: %s" % [snap.get("region_fund_bill_pct_gdp")])


## A fund is spending (the parent's ruling on #263, QA's call 1), so its bill moves
## demand through the channel every spending change takes: Budget.commit()'s
## MULT_SPENDING over impulse_level_factor(), on the bill's change. Up when the fund
## starts billing, down when it stops, so the level effect over its life sums to
## zero (no free lunch, no lasting stimulus). _month() runs no Economy, so the impulse
## does not decay between the reads and every step is the fund's alone.
func _test_the_bill_moves_demand_as_spending_does() -> void:
	var state = _state()
	var ns = state.player()
	RegionFunds.start(state, ns, _loader, _worst(state, ns), 2.0, 1)
	var bill := 0.0
	var level := 0.0
	var rose := false
	var fell := false
	for i in range(14):
		var impulse := float(ns.demand_impulse_pct)
		_month(state)
		var step := float(ns.demand_impulse_pct) - impulse
		var want := (float(ns.region_fund_bill_pct_gdp) - bill) * C.MULT_SPENDING / C.impulse_level_factor()
		if not is_equal_approx(step, want):
			_fail("month %d: the fund moved demand by %.6f, not its bill's change x MULT_SPENDING (%.6f)" % [i + 1, step, want])
		rose = rose or step > 0.0
		fell = fell or step < 0.0
		level += step * C.impulse_level_factor()
		bill = float(ns.region_fund_bill_pct_gdp)
	if not rose or not fell:
		_fail("a one-year fund did not raise demand at its start and lower it at its end")
	if not is_equal_approx(level, 0.0):
		_fail("the fund's level effect over its life is %.6f points of GDP, not zero" % level)
	# Two funds that overlap, each stopped early: every step is the SUMMED bill's
	# change, and the stops close the sum.
	state = _state()
	ns = state.player()
	var first := _worst(state, ns)
	var second := ""
	for r in _list(state):
		if r.id != first and r.id != RK.RESIDUAL_KEY:
			second = r.id
			break
	bill = 0.0
	level = 0.0
	RegionFunds.start(state, ns, _loader, first, 2.0, 3)
	for i in range(10):
		if i == 3:
			RegionFunds.start(state, ns, _loader, second, 1.0, 3)
		if i == 6:
			RegionFunds.stop(state, ns, String(ns.region_funds[0]["id"]))
		if i == 8:
			RegionFunds.stop(state, ns, String(ns.region_funds[1]["id"]))
		var impulse := float(ns.demand_impulse_pct)
		_month(state)
		var step := float(ns.demand_impulse_pct) - impulse
		if not is_equal_approx(step, (float(ns.region_fund_bill_pct_gdp) - bill) * C.MULT_SPENDING / C.impulse_level_factor()):
			_fail("month %d of two funds: demand moved %.6f, not the summed bill's change" % [i + 1, step])
		level += step * C.impulse_level_factor()
		bill = float(ns.region_fund_bill_pct_gdp)
	if bill != 0.0 or not is_equal_approx(level, 0.0):
		_fail("two stopped funds left a bill of %.5f or a level effect of %.6f" % [bill, level])


func _month(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	RegionFunds.tick_month(state)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_region_funds")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)
