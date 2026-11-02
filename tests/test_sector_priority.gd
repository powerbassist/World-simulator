extends SceneTree

## V5.3 a (docs/design/v5.3-ab.md 3.3 (a) 1): the regional priority -- "put hospitals
## first in Hauts-de-France". One priority per sector at a time; it moves money
## between regions, never the line's total, so the national quantity, the factor and
## every channel are unchanged, and the population-weighted mean of the regions'
## spending multipliers is exactly 1 (the same money).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Sectors = preload("res://src/sim/sectors.gd")
const DK = preload("res://src/sim/domains_constants.gd")
const RK = preload("res://src/sim/region_constants.gd")
const Society = preload("res://src/sim/society.gd")
const Regions = preload("res://src/sim/regions.gd")

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_no_priority_reads_the_nation()
	_test_a_priority_lifts_its_region_and_costs_the_others_the_same_money()
	_test_the_nation_is_unchanged()
	_test_one_priority_per_sector()
	_test_refusals_write_nothing()
	_test_the_estimate_is_what_the_priority_books()
	_test_clearing_and_a_save()
	_test_a_priority_moves_the_regions_unemployment()
	_test_a_cleared_priority_leaves_no_trace()
	_test_the_strip_shows_both_sides()
	_test_a_region_holds_two_priorities_at_most()
	_test_a_priority_lasts_three_years()
	_test_the_term_converges_and_stops_once_caught_up()
	_finish()


func _state():
	return GameState.new_game(_loader, "FRA")


func _regions(state) -> Array:
	var out: Array = []
	for r in state.regions.get("FRA", []):
		if r.id != RK.RESIDUAL_KEY:
			out.append(String(r.id))
	return out


func _test_no_priority_reads_the_nation() -> void:
	var state = _state()
	var ns = state.player()
	var q := Sectors.quantity(ns, _loader, "health", "hospitals")
	for region in _regions(state):
		if Sectors.regional_quantity(ns, _loader, "health", "hospitals", region) != q:
			_fail("%s reads %.4f with no priority, not the nation's %.4f" % [region,
				Sectors.regional_quantity(ns, _loader, "health", "hospitals", region), q])


## The priority region's spending per head on the sector rises by PRIORITY_UPLIFT;
## every other region's falls so the money is the same; each region's quantity moves
## by its spending ratio ^ elasticity, as the national quantity does.
func _test_a_priority_lifts_its_region_and_costs_the_others_the_same_money() -> void:
	var state = _state()
	var ns = state.player()
	var regions := _regions(state)
	var target := String(regions[0])
	var other := String(regions[1])
	var q := Sectors.quantity(ns, _loader, "health", "hospitals")
	var r: Dictionary = Sectors.set_priority(state, ns, _loader, "health", "hospitals", target)
	if not bool(r.get("ok", false)):
		_fail("a good priority was refused: %s" % r)
		return
	var e := float(DK.ELASTICITY["hospitals"])
	var up := Sectors.regional_quantity(ns, _loader, "health", "hospitals", target)
	if not is_equal_approx(up, q * pow(1.0 + DK.PRIORITY_UPLIFT, e)):
		_fail("the priority region reads %.4f, not x(1 + uplift)^e of %.4f" % [up, q])
	# Over the whole population, the unlocated residual included: it is one of the
	# "others" that pay for the region put first. The live shares need not sum to 1.
	var total := 0.0
	for region in ns.region_pop_share:
		total += float(ns.region_pop_share[region])
	var p := float(ns.region_pop_share[target])
	var down := Sectors.regional_quantity(ns, _loader, "health", "hospitals", other)
	if not is_equal_approx(down, q * pow(1.0 - DK.PRIORITY_UPLIFT * p / (total - p), e)):
		_fail("another region reads %.4f, not the same money's loss" % down)
	var mean := 0.0
	for region in ns.region_pop_share:
		mean += float(ns.region_pop_share[region]) * Sectors.spend_multiplier(ns, "hospitals", region)
	if not is_equal_approx(mean / total, 1.0):
		_fail("the regions' population-weighted multiplier is %.6f: not the same money" % (mean / total))


func _test_the_nation_is_unchanged() -> void:
	var state = _state()
	var ns = state.player()
	var q := Sectors.quantity(ns, _loader, "health", "hospitals")
	var quality := Society.quality_target(ns, "health")
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", _behind(state))
	if Sectors.quantity(ns, _loader, "health", "hospitals") != q or Society.quality_target(ns, "health") != quality \
			or Sectors.factor(ns, "health") != 1.0:
		_fail("a priority moved a national figure")


func _test_one_priority_per_sector() -> void:
	var state = _state()
	var ns = state.player()
	var regions := _regions(state)
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", String(regions[0]))
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", String(regions[1]))
	if Sectors.priority_of(ns, "hospitals") != String(regions[1]):
		_fail("a second priority on the sector did not replace the first")
	if Sectors.regional_quantity(ns, _loader, "health", "hospitals", String(regions[0])) \
			>= Sectors.quantity(ns, _loader, "health", "hospitals"):
		_fail("the replaced region kept its lift")
	# A priority on another sector is its own choice.
	Sectors.set_priority(state, ns, _loader, "health", "primary_care", String(regions[0]))
	if Sectors.priority_of(ns, "hospitals") != String(regions[1]) or Sectors.priority_of(ns, "primary_care") != String(regions[0]):
		_fail("a priority on one sector moved another's")


func _test_refusals_write_nothing() -> void:
	var state = _state()
	var ns = state.player()
	var region := String(_regions(state)[0])
	var bad := {
		"an unknown line": ["casinos", "hospitals", region],
		"a sector of another line": ["education", "hospitals", region],
		"an unknown region": ["health", "hospitals", "FRZ"],
		"the residual": ["health", "hospitals", RK.RESIDUAL_KEY],
	}
	for label in bad:
		var a: Array = bad[label]
		var r: Dictionary = Sectors.set_priority(state, ns, _loader, String(a[0]), String(a[1]), String(a[2]))
		if bool(r.get("ok", true)) or String(r.get("reason", "")) == "":
			_fail("set_priority accepted %s, or refused with no reason" % label)
	if not ns.sector_priorities.is_empty():
		_fail("a refused priority wrote the register")
	# The only populated region: nobody else is there to pay for it (a one-region nation).
	var alone = _state()
	var ans = alone.player()
	ans.region_pop_share = {region: float(ans.region_pop_share[region])}
	var r1: Dictionary = Sectors.set_priority(alone, ans, _loader, "health", "hospitals", region)
	if bool(r1.get("ok", true)) or not ans.sector_priorities.is_empty():
		_fail("a priority with no other region to pay for it was accepted")
	# A region holding most of the people: the rest would have to spend under the floor.
	var other := String(_regions(alone)[1])
	ans.region_pop_share = {region: 0.9, other: 0.1}
	var r2: Dictionary = Sectors.set_priority(alone, ans, _loader, "health", "hospitals", region)
	if bool(r2.get("ok", true)) or not ans.sector_priorities.is_empty():
		_fail("a priority the other regions cannot pay for was accepted")
	if bool(Sectors.clear_priority(ns, "hospitals").get("ok", true)):
		_fail("clearing a sector with no priority was accepted")


## The strip's figures are the booked ones: the region before and after, the other
## regions' loss.
func _test_the_estimate_is_what_the_priority_books() -> void:
	var state = _state()
	var ns = state.player()
	var regions := _regions(state)
	var est: Dictionary = Sectors.priority_estimate(state, ns, _loader, "health", "hospitals", String(regions[0]))
	if not bool(est.get("ok", false)):
		_fail("the estimate refused a good priority: %s" % est)
		return
	var before := Sectors.regional_quantity(ns, _loader, "health", "hospitals", String(regions[0]))
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", String(regions[0]))
	if not is_equal_approx(float(est["region_before"]), before) \
			or not is_equal_approx(float(est["region_after"]), Sectors.regional_quantity(ns, _loader, "health", "hospitals", String(regions[0]))) \
			or not is_equal_approx(float(est["others_after"]), Sectors.regional_quantity(ns, _loader, "health", "hospitals", String(regions[1]))):
		_fail("the estimate %s is not what the priority booked" % est)
	# Under an existing priority on another region: the target is a payer before.
	var moved: Dictionary = Sectors.priority_estimate(state, ns, _loader, "health", "hospitals", String(regions[1]))
	var payer := Sectors.regional_quantity(ns, _loader, "health", "hospitals", String(regions[1]))
	if payer >= Sectors.quantity(ns, _loader, "health", "hospitals") or not is_equal_approx(float(moved["region_before"]), payer):
		_fail("the estimate's before (%s) is not the payer's %.4f" % [moved.get("region_before"), payer])
	# QA's TAKE on #267: a lower-is-better quantity (schools: pupils per teacher) falls
	# where the money goes and rises where it leaves, on the strip and in the read.
	var schools: Dictionary = Sectors.priority_estimate(state, ns, _loader, "education", "schools", String(regions[0]))
	var pupils := Sectors.quantity(ns, _loader, "education", "schools")
	if not (float(schools["region_after"]) < pupils and float(schools["others_after"]) > pupils):
		_fail("schools first: the region reads %s and the others %s pupils per teacher against the nation's %.3f" % [
			schools.get("region_after"), schools.get("others_after"), pupils])
	Sectors.set_priority(state, ns, _loader, "education", "schools", String(regions[0]))
	if not (Sectors.regional_quantity(ns, _loader, "education", "schools", String(regions[0])) < pupils \
			and Sectors.regional_quantity(ns, _loader, "education", "schools", String(regions[1])) > pupils):
		_fail("schools first: the booked pupils per teacher do not fall in the region and rise elsewhere")


## absent_ok: no save before V5.3 a held a priority, so absent is "none".
func _test_clearing_and_a_save() -> void:
	var state = _state()
	var ns = state.player()
	var region := String(_regions(state)[0])
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", region)
	var kept = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	if Sectors.priority_of(kept.player(), "hospitals") != region:
		_fail("a priority did not survive the round trip")
	# Its points travel with it: the term is fixed at set time, never re-derived.
	var pts := float((ns.sector_priorities["hospitals"] as Dictionary)["pts"])
	if pts <= 0.0 or not is_equal_approx(float((kept.player().sector_priorities["hospitals"] as Dictionary).get("pts", 0.0)), pts):
		_fail("a priority's points did not survive the round trip")
	Sectors.clear_priority(ns, "hospitals")
	if Sectors.priority_of(ns, "hospitals") != "" \
			or Sectors.regional_quantity(ns, _loader, "health", "hospitals", region) != Sectors.quantity(ns, _loader, "health", "hospitals"):
		_fail("a cleared priority still lifts its region")


func _list(state) -> Array:
	return state.regions.get("FRA", [])


func _access(state) -> Dictionary:
	return Regions.accessibility_for(state.player(), _list(state), state.region_graph)


func _sites(state) -> Dictionary:
	return state.project_sited_pct.get("FRA", {})


## #267 redesign (the parent's ruling: a priority must move a real outcome): the money
## a priority moves feeds the region's growth deviation, zero-mean, as a fund's does.
## pts = PRIORITY_BETA x 100 x money / the region's output, money = PRIORITY_UPLIFT x
## the region's share of the population x the sector's spending. The region's
## deviation rises by pts x (1 - its output weight), every other region's falls by
## pts x that weight, the output-weighted sum is 0, and through Okun the region's
## unemployment falls while every other region's rises.
func _test_a_priority_moves_the_regions_unemployment() -> void:
	var state = _state()
	var ns = state.player()
	var list := _list(state)
	# The region furthest behind: a priority's term converges on the nation's output
	# per head, so a region ahead of it gets none (the parent's TAKE on #267).
	var target := _behind(state)
	var dev0: Dictionary = Regions.deviation_by_region(ns, list, _access(state), _sites(state))
	var u0: Dictionary = Regions.unemployment_by_region(ns, list, _access(state), _sites(state))
	if not bool(Sectors.set_priority(state, ns, _loader, "health", "hospitals", target).get("ok", false)):
		_fail("a good priority was refused")
		return
	var people := 0.0
	for region in ns.region_pop_share:
		people += float(ns.region_pop_share[region])
	var spend := float(ns.spending_pct_gdp["health"]) / 100.0 \
		* float(Sectors.shares(ns, _loader, "health")["hospitals"]) * float(ns.gdp_eur_bn)
	var money := DK.PRIORITY_UPLIFT * float(ns.region_pop_share[target]) / people * spend
	var pts := DK.PRIORITY_BETA * 100.0 * money / Regions.output_eur_bn(ns, target)
	var booked := float((ns.sector_priorities.get("hospitals", {}) as Dictionary).get("pts", 0.0))
	if pts <= 0.0 or not is_equal_approx(booked, pts):
		_fail("the priority booked %.6f points, not the money's %.6f" % [booked, pts])
	var dev1: Dictionary = Regions.deviation_by_region(ns, list, _access(state), _sites(state))
	var u1: Dictionary = Regions.unemployment_by_region(ns, list, _access(state), _sites(state))
	var shares: Dictionary = Regions.shares_of(ns, list)
	var output := 0.0
	for region in list:
		output += float(shares[region.id])
	var w := float(shares[target]) / output
	var weighted := 0.0
	for region in list:
		var id := String(region.id)
		var moved := float(dev1[id]) - float(dev0[id])
		weighted += float(shares[id]) * moved
		var want := pts * (1.0 - w) if id == target else -pts * w
		if absf(moved - want) > 1e-12:
			_fail("%s's deviation moved %.9f, not %.9f" % [id, moved, want])
		var du := float(u1[id]) - float(u0[id])
		if (id == target and du >= 0.0) or (id != target and du <= 0.0):
			_fail("%s's unemployment moved %.5f points (the region put first falls, the others rise)" % [id, du])
	if absf(weighted) > 1e-12:
		_fail("the priority moved the output-weighted deviation by %.12f: not zero-mean" % weighted)


## No priority, no term: a priority set and then cleared leaves every region's
## deviation the float it was (A1 by construction, as a nation with no fund).
func _test_a_cleared_priority_leaves_no_trace() -> void:
	var state = _state()
	var ns = state.player()
	var list := _list(state)
	var before: Dictionary = Regions.deviation_by_region(ns, list, _access(state), _sites(state))
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", _behind(state))
	Sectors.clear_priority(ns, "hospitals")
	if Regions.deviation_by_region(ns, list, _access(state), _sites(state)) != before:
		_fail("a cleared priority left a trace in the regions' deviation")


## The strip shows both sides, read through the game's own arithmetic: the region's
## unemployment now and with the priority, and the other regions' (population-
## weighted) now and after. The after figures are the booked ones, and the estimate
## leaves the register as it found it, a priority already set elsewhere included.
func _test_the_strip_shows_both_sides() -> void:
	var state = _state()
	var ns = state.player()
	var list := _list(state)
	var regions := _regions(state)
	var target := _behind(state)
	var est: Dictionary = Sectors.priority_estimate(state, ns, _loader, "health", "hospitals", target)
	if not ns.sector_priorities.is_empty():
		_fail("the estimate left a priority set")
	var u0: Dictionary = Regions.unemployment_by_region(ns, list, _access(state), _sites(state))
	if float(est.get("unemployment_now", -1.0)) != float(u0[target]) \
			or float(est.get("others_unemployment_now", -1.0)) != _others_mean(ns, u0, target):
		_fail("the strip's now figures %s are not the region's and the others' today" % est)
	if not (float(est.get("unemployment_after", 99.0)) < float(est.get("unemployment_now", -1.0)) \
			and float(est.get("others_unemployment_after", -1.0)) > float(est.get("others_unemployment_now", 99.0))):
		_fail("the strip %s does not show the region's gain and the others' loss" % est)
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", target)
	var u1: Dictionary = Regions.unemployment_by_region(ns, list, _access(state), _sites(state))
	if float(est["unemployment_after"]) != float(u1[target]) \
			or float(est["others_unemployment_after"]) != _others_mean(ns, u1, target):
		_fail("the strip's after figures %s are not what the priority booked" % est)
	# An estimate for another region while this one holds the sector: the register is
	# the same afterwards, its points included.
	var held: Dictionary = (ns.sector_priorities["hospitals"] as Dictionary).duplicate()
	Sectors.priority_estimate(state, ns, _loader, "health", "hospitals", String(regions[0] if regions[0] != target else regions[1]))
	if ns.sector_priorities.get("hospitals") != held:
		_fail("the estimate for another region moved the priority already set")


## The other named regions' unemployment, weighted by their share of the population.
func _others_mean(ns, rates: Dictionary, target: String) -> float:
	var weighted := 0.0
	var people := 0.0
	for id in rates:
		if String(id) != target and String(id) != RK.RESIDUAL_KEY:
			var p := float(ns.region_pop_share.get(id, 0.0))
			weighted += p * float(rates[id])
			people += p
	return weighted / people if people > 0.0 else 0.0


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_sector_priority")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)


# --- The parent's two TAKEs on #267 ---------------------------------------------------

## Every (line, sector) of the nation's sectors, in line order.
func _pairs(ns) -> Array:
	var out: Array = []
	var lines: Array = ns.spending_pct_gdp.keys()
	lines.sort()
	for line in lines:
		for sector in Sectors.sectors_of(_loader, String(line)):
			out.append([String(line), String(sector["id"])])
	return out


## The named regions' output per head against the nation's, region id -> index.
func _indices(state) -> Dictionary:
	var ns = state.player()
	var people := 0.0
	for region in ns.region_pop_share:
		people += float(ns.region_pop_share[region])
	var out := {}
	for id in _regions(state):
		out[id] = Regions.gdp_per_head_index(ns, _list(state), id, float(ns.region_pop_share.get(id, 0.0)) / people)
	return out


## The named region with the lowest output per head.
func _behind(state) -> String:
	var idx := _indices(state)
	var best := ""
	for id in idx:
		if float(idx[id]) > 0.0 and (best == "" or float(idx[id]) < float(idx[best])):
			best = String(id)
	return best


## The named region with the highest output per head.
func _ahead(state) -> String:
	var idx := _indices(state)
	var best := ""
	for id in idx:
		if best == "" or float(idx[id]) > float(idx[best]):
			best = String(id)
	return best


## TAKE 1, no free stacking: one region per sector (a second replaces the first) and
## a REGION holds at most two priorities. Pinned as the literal 2 (QA on #248).
func _test_a_region_holds_two_priorities_at_most() -> void:
	var state = _state()
	var ns = state.player()
	var target := _behind(state)
	var pairs := _pairs(ns)
	if pairs.size() < 3:
		_fail("the fixture found %d sectors, not three or more" % pairs.size())
		return
	for i in 2:
		if not bool(Sectors.set_priority(state, ns, _loader, pairs[i][0], pairs[i][1], target).get("ok", false)):
			_fail("priority %d of 2 in one region was refused" % (i + 1))
			return
	var third: Dictionary = Sectors.set_priority(state, ns, _loader, pairs[2][0], pairs[2][1], target)
	if bool(third.get("ok", true)) or String(third.get("reason", "")) == "" or ns.sector_priorities.size() != 2:
		_fail("a third priority in one region was not refused: %s" % third)
	if bool(Sectors.priority_estimate(state, ns, _loader, pairs[2][0], pairs[2][1], target).get("ok", true)):
		_fail("the strip offers a third priority in a region that holds two")
	# Renewing one of the two in its region is not a third.
	if not bool(Sectors.set_priority(state, ns, _loader, pairs[0][0], pairs[0][1], target).get("ok", false)):
		_fail("renewing a region's priority was refused as a third")
	Sectors.clear_priority(ns, pairs[0][1])
	if not bool(Sectors.set_priority(state, ns, _loader, pairs[2][0], pairs[2][1], target).get("ok", false)):
		_fail("a cleared priority did not free its region's place")


## TAKE 2, a term: a priority lasts 36 months (pinned as the literal), the month it
## ends is on its row for the strip, and setting it again renews it.
func _test_a_priority_lasts_three_years() -> void:
	var state = _state()
	var ns = state.player()
	var target := _behind(state)
	var now := int(state.year) * 12 + int(state.month)
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", target)
	if int((ns.sector_priorities.get("hospitals", {}) as Dictionary).get("ends", -1)) != now + 36:
		_fail("the priority ends in month %s, not 36 months on (%d)" % [
			(ns.sector_priorities.get("hospitals", {}) as Dictionary).get("ends"), now + 36])
	for i in 10:
		_tick(state)
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", target)
	var renewed := int(state.year) * 12 + int(state.month) + 36
	if int((ns.sector_priorities.get("hospitals", {}) as Dictionary).get("ends", -1)) != renewed:
		_fail("setting the priority again did not renew its 36 months")
	for i in 35:
		_tick(state)
	if Sectors.priority_of(ns, "hospitals") != target:
		_fail("the renewed priority ended before its 36 months")
	_tick(state)
	if ns.sector_priorities.has("hospitals"):
		_fail("the priority outlived its 36 months: %s" % ns.sector_priorities)


## TAKE 2, a convergence term: the term scales with the region's shortfall in output
## per head against the nation's, from all of it at the press (the strip's figure) to
## none once caught up; a region not behind gets no term at all.
func _test_the_term_converges_and_stops_once_caught_up() -> void:
	var state = _state()
	var ns = state.player()
	var list := _list(state)
	var target := _behind(state)
	var gap0 := 1.0 - float(_indices(state)[target])
	if gap0 <= 0.0:
		_fail("the fixture found no region behind the nation")
		return
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", target)
	var row: Dictionary = ns.sector_priorities["hospitals"]
	if float(row.get("factor", -1.0)) != 1.0:
		_fail("a priority's term starts at %s of its booked points, not all of them" % row.get("factor"))
	# Half the shortfall made up: the region's output per head at 1 - gap0 / 2.
	_set_index(state, target, 1.0 - gap0 / 2.0)
	_tick(state)
	var factor := float(row.get("factor", -1.0))
	if absf(factor - 0.5) > 1e-6:
		_fail("half the shortfall made up leaves a factor of %.6f, not 0.5" % factor)
	var moved := float(Regions.deviation_by_region(ns, list, _access(state), _sites(state))[target]) \
		- float(_without(state, list)[target])
	if absf(moved - factor * _gain(state, list)) > 1e-9:
		_fail("the half-way term moved the region by %.9f, not %.6f x the whole %.9f" % [moved, factor, _gain(state, list)])
	# Caught up: the term stops.
	_set_index(state, target, 1.02)
	_tick(state)
	var after := float(Regions.deviation_by_region(ns, list, _access(state), _sites(state))[target])
	# _without() put copies back: read the register's own row again.
	var caught := float((ns.sector_priorities["hospitals"] as Dictionary).get("factor", -1.0))
	if caught != 0.0 or absf(after - float(_without(state, list)[target])) > 1e-12:
		_fail("a region caught up still gets its term: factor %s" % caught)
	# A shortfall inside PRIORITY_BEHIND_EPS is float noise, not behind (GBR's
	# regions all read 1.0000): no term at the press, so the strip shows none.
	var level = _state()
	var lns = level.player()
	var near := _behind(level)
	_set_index(level, near, 0.995)
	Sectors.set_priority(level, lns, _loader, "health", "hospitals", near)
	if String((lns.sector_priorities.get("hospitals", {}) as Dictionary).get("region_id", "")) == near 			and float((lns.sector_priorities["hospitals"] as Dictionary).get("factor", -1.0)) != 0.0:
		_fail("a region half a percent behind (inside the epsilon) got a term at the press")
	# A region not behind the nation gets no term from the press on.
	var rich = _state()
	var e: Dictionary = Sectors.priority_estimate(rich, rich.player(), _loader, "health", "hospitals", _ahead(rich))
	if not bool(e.get("ok", false)) or absf(float(e["unemployment_after"]) - float(e["unemployment_now"])) > 1e-12:
		_fail("a priority in the region with the most output per head moves its unemployment: %s" % e)


## One month of the priorities' step (the clock moves first, as WorldMonth's does).
func _tick(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	Sectors.tick_month(state)


## The deviation with the register emptied for one read (the term's zero).
func _without(state, list: Array) -> Dictionary:
	var ns = state.player()
	var held: Dictionary = ns.sector_priorities.duplicate(true)
	ns.sector_priorities.clear()
	var out: Dictionary = Regions.deviation_by_region(ns, list, _access(state), _sites(state))
	ns.sector_priorities.merge(held)
	return out


## The whole term's gain in its region now: its booked points x (1 - its output weight).
func _gain(state, list: Array) -> float:
	var ns = state.player()
	var row: Dictionary = ns.sector_priorities["hospitals"]
	var shares: Dictionary = Regions.shares_of(ns, list)
	var output := 0.0
	for region in list:
		output += float(shares[region.id])
	return float(row["pts"]) * (1.0 - float(shares[String(row["region_id"])]) / output)


## Move one region's output so its output per head reads `index` of the nation's.
func _set_index(state, region_id: String, index: float) -> void:
	var ns = state.player()
	var people := 0.0
	for region in ns.region_pop_share:
		people += float(ns.region_pop_share[region])
	var share := index * float(ns.region_pop_share[region_id]) / people
	var rest := 0.0
	for id in ns.region_gdp_eur_bn:
		if String(id) != region_id:
			rest += float(ns.region_gdp_eur_bn[id])
	ns.region_gdp_eur_bn[region_id] = share * rest / (1.0 - share)
