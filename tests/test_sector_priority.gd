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
const EC = preload("res://src/sim/economy_constants.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")

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
	_test_the_term_stops_at_the_national_rate()
	_test_a_regions_priorities_share_one_cap()
	_test_no_priority_takes_a_region_under_the_nation()
	_test_a_priority_renews_once_then_rests()
	_test_the_game_month_ends_and_recaps_a_priority()
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
	if bool(Sectors.clear_priority(state, ns, "hospitals").get("ok", true)):
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
	Sectors.clear_priority(state, ns, "hospitals")
	if Sectors.priority_of(ns, "hospitals") != "" \
			or Sectors.regional_quantity(ns, _loader, "health", "hospitals", region) != Sectors.quantity(ns, _loader, "health", "hospitals"):
		_fail("a cleared priority still lifts its region")
	# QA on #267: the rest travels too, else a save and a load would wipe every wait
	# and the renewal rule with it.
	var rested = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	# The load path re-attaches the region register and the graph (SaveManager.load_game).
	rested.regions = _loader.regions
	rested.region_graph = _loader.region_graph
	var until := int((ns.sector_priority_rest.get("hospitals", {}) as Dictionary).get(region, -1))
	if until <= 0 or int((rested.player().sector_priority_rest.get("hospitals", {}) as Dictionary).get(region, -1)) != until:
		_fail("the rest %s did not survive a save, which read %s" % [ns.sector_priority_rest, rested.player().sector_priority_rest])
	if bool(Sectors.set_priority(rested, rested.player(), _loader, "health", "hospitals", region).get("ok", true)):
		_fail("a save and a load lifted the cleared priority's rest: %s" % rested.player().sector_priority_rest)


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
	# The region furthest above the nation's unemployment, a point above it so the
	# whole term applies (call B on #267 caps it at the nation's rate).
	var target := _behind(state)
	_set_headroom(state, target, 1.0)
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
	Sectors.clear_priority(state, ns, "hospitals")
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


## Every named region's unemployment now, region id -> points.
func _u(state) -> Dictionary:
	return Regions.unemployment_by_region(state.player(), _list(state), _access(state), _sites(state))


## The named region with the highest unemployment: the furthest above the nation's
## rate, so a priority there gets its term (call B on #267).
func _behind(state) -> String:
	var u := _u(state)
	var best := ""
	for id in _regions(state):
		if best == "" or float(u[id]) > float(u[best]):
			best = id
	return best


## The named region with the lowest unemployment.
func _ahead(state) -> String:
	var u := _u(state)
	var best := ""
	for id in _regions(state):
		if best == "" or float(u[id]) < float(u[best]):
			best = id
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
	Sectors.clear_priority(state, ns, pairs[0][1])
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


## Call B on #267 (the parent's): a priority lowers its region's unemployment only as
## far as the nation's rate. The factor is the region's headroom (its unemployment
## without the priorities, less the nation's) over the term's reach (OKUN x the booked
## points x (1 - its output weight)), between 0 and 1, read again every month.
func _test_the_term_stops_at_the_national_rate() -> void:
	var state = _state()
	var ns = state.player()
	var list := _list(state)
	var target := _behind(state)
	var nat := float(ns.unemployment_pct)
	_set_headroom(state, target, 1.0)
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", target)
	var reach := EC.OKUN * _gain(state, list)
	if reach <= 0.0 or reach >= 1.0:
		_fail("the fixture's term reaches %.4f points, not inside (0, 1)" % reach)
		return
	# A point above the nation: the whole booked term, from the press on.
	if float((ns.sector_priorities["hospitals"] as Dictionary).get("factor", -1.0)) != 1.0:
		_fail("a region a point above the nation gets %s of its term, not all of it" % (ns.sector_priorities["hospitals"] as Dictionary).get("factor"))
	var full := float(_without_u(state)[target]) - float(_u(state)[target])
	if absf(full - reach) > 1e-9:
		_fail("the whole term lowered the region's unemployment by %.9f, not its reach %.9f" % [full, reach])
	# Half the reach above the nation: half the term, and the region lands on the
	# nation's rate.
	_set_headroom(state, target, reach / 2.0)
	_tick(state)
	var half := float((ns.sector_priorities["hospitals"] as Dictionary).get("factor", -1.0))
	if absf(half - 0.5) > 1e-9:
		_fail("half the reach above the nation leaves a factor of %.9f, not 0.5" % half)
	if absf(float(_u(state)[target]) - nat) > 1e-9:
		_fail("the capped region's unemployment is %.9f, not the nation's %.9f" % [float(_u(state)[target]), nat])
	var moved := float(Regions.deviation_by_region(ns, list, _access(state), _sites(state))[target]) - float(_without(state, list)[target])
	if absf(moved - half * _gain(state, list)) > 1e-12:
		_fail("the half term moved the region by %.12f, not %.6f x the whole %.12f" % [moved, half, _gain(state, list)])
	# At or under the nation's rate: no term.
	_set_headroom(state, target, -0.1)
	_tick(state)
	var none := float((ns.sector_priorities["hospitals"] as Dictionary).get("factor", -1.0))
	var left := float(Regions.deviation_by_region(ns, list, _access(state), _sites(state))[target]) - float(_without(state, list)[target])
	if none != 0.0 or absf(left) > 1e-12:
		_fail("a region under the nation's rate still gets its term: factor %s, deviation %.12f" % [none, left])
	# Read again every month, not a ratchet: back above the nation, the whole term.
	_set_headroom(state, target, 1.0)
	_tick(state)
	if float((ns.sector_priorities["hospitals"] as Dictionary).get("factor", -1.0)) != 1.0:
		_fail("a region back above the nation did not get its term back")
	# A region under the nation's rate is not refused (the money still moves its
	# sector's quantity); the strip shows its unemployment unchanged.
	var rich = _state()
	var low := _ahead(rich)
	if float(_u(rich)[low]) >= float(rich.player().unemployment_pct):
		_fail("the fixture found no region under the nation's unemployment")
		return
	var e: Dictionary = Sectors.priority_estimate(rich, rich.player(), _loader, "health", "hospitals", low)
	if not bool(e.get("ok", false)) or absf(float(e["unemployment_after"]) - float(e["unemployment_now"])) > 1e-12:
		_fail("a priority in a region under the nation's rate moves its unemployment, or is refused: %s" % e)


## Call B, shared: a region's priorities share one cap, so two together stop at the
## nation's rate with one factor; setting a second or clearing one re-caps the other
## at once, and the strip shows the capped figure it books.
func _test_a_regions_priorities_share_one_cap() -> void:
	var state = _state()
	var ns = state.player()
	var list := _list(state)
	var target := _behind(state)
	var nat := float(ns.unemployment_pct)
	_set_headroom(state, target, 1.0)
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", target)
	Sectors.set_priority(state, ns, _loader, "health", "primary_care", target)
	var r1 := EC.OKUN * _gain_of(state, list, "hospitals")
	var r2 := EC.OKUN * _gain_of(state, list, "primary_care")
	if r1 <= 0.0 or r2 <= 0.0:
		_fail("the fixture's terms reach %.6f and %.6f points" % [r1, r2])
		return
	# Above the nation by half of both terms' reach: one factor, the nation's rate.
	var head := (r1 + r2) / 2.0
	_set_headroom(state, target, head)
	_tick(state)
	var f1 := float((ns.sector_priorities["hospitals"] as Dictionary).get("factor", -1.0))
	var f2 := float((ns.sector_priorities["primary_care"] as Dictionary).get("factor", -1.0))
	if f1 != f2 or absf(f1 - head / (r1 + r2)) > 1e-9:
		_fail("two priorities in one region read factors %.9f and %.9f, not one %.9f" % [f1, f2, head / (r1 + r2)])
	if absf(float(_u(state)[target]) - nat) > 1e-9:
		_fail("two capped priorities leave the region at %.9f, not the nation's %.9f" % [float(_u(state)[target]), nat])
	# One cleared: the other is re-capped at once, alone.
	Sectors.clear_priority(state, ns, "primary_care")
	var alone := float((ns.sector_priorities["hospitals"] as Dictionary).get("factor", -1.0))
	if absf(alone - clampf(head / r1, 0.0, 1.0)) > 1e-9:
		_fail("the priority left alone reads a factor of %.9f, not %.9f, until a month passes" % [alone, clampf(head / r1, 0.0, 1.0)])
	# The strip for the second while the first is held shows the shared cap, and it is
	# what setting it books; the first is re-capped at once.
	# (The cleared sector's region now waits: the line's third sector takes its place.)
	var e: Dictionary = Sectors.priority_estimate(state, ns, _loader, "health", "prevention", target)
	if float((ns.sector_priorities["hospitals"] as Dictionary).get("factor", -1.0)) != alone:
		_fail("the estimate moved the held priority's factor")
	Sectors.set_priority(state, ns, _loader, "health", "prevention", target)
	if absf(float(e.get("unemployment_after", -1.0)) - float(_u(state)[target])) > 1e-12:
		_fail("the strip shows %s for the second priority, but setting it books %.9f" % [e.get("unemployment_after"), float(_u(state)[target])])
	var g1 := float((ns.sector_priorities["hospitals"] as Dictionary).get("factor", -1.0))
	var g2 := float((ns.sector_priorities["prevention"] as Dictionary).get("factor", -2.0))
	if g1 != g2:
		_fail("setting a second priority did not re-cap the first at once (%.9f against %.9f)" % [g1, g2])


## Call B holds for every region of three nations: a region above the nation's rate
## never ends under it, and one at or under it stays where it was. Where some region
## sits above the nation's rate, a priority there moves it: Germany's DE5, whose output
## per head reads a flat 1.0 where the convergence on output per head never ran, sits
## at 1.77 x the nation's unemployment. Where none does (Britain's regions carry no
## unemployment spread and no deviation in the data, the Content card), none moves.
func _test_no_priority_takes_a_region_under_the_nation() -> void:
	for nation in ["FRA", "DEU", "GBR"]:
		var s = GameState.new_game(_loader, nation)
		var nsx = s.player()
		var lst: Array = s.regions.get(nation, [])
		var acc := Regions.accessibility_for(nsx, lst, s.region_graph)
		var sites: Dictionary = s.project_sited_pct.get(nation, {})
		var nat := float(nsx.unemployment_pct)
		var best := 0.0
		var above := false
		for region in lst:
			if region.id == RK.RESIDUAL_KEY:
				continue
			var before: Dictionary = Regions.unemployment_by_region(nsx, lst, acc, sites)
			above = above or float(before[region.id]) > nat + 1e-9
			if not bool(Sectors.set_priority(s, nsx, _loader, "health", "hospitals", region.id).get("ok", false)):
				_fail("%s: a priority in %s was refused" % [nation, region.id])
				continue
			var after: Dictionary = Regions.unemployment_by_region(nsx, lst, acc, sites)
			var lowest := minf(float(before[region.id]), nat)
			if float(after[region.id]) < lowest - 1e-9:
				_fail("%s: a priority takes %s from %.9f to %.9f, under the nation's %.9f" % [
					nation, region.id, float(before[region.id]), float(after[region.id]), nat])
			best = maxf(best, float(before[region.id]) - float(after[region.id]))
			Sectors.clear_priority(s, nsx, "hospitals")
		if above and best <= 1e-6:
			_fail("%s: a region sits above the nation's rate, yet no priority moves one (best %.9f)" % [nation, best])
		if not above and best > 1e-12:
			_fail("%s: no region sits above the nation's rate, yet a priority moved one by %.12f" % [nation, best])


## The parent's renewal call on #267: a region's priority on a sector renews once (6
## years in all, the literal 1 and 36), then that region waits 36 months before taking
## the sector again; a clear or a replacement starts the wait too. The strip says so.
func _test_a_priority_renews_once_then_rests() -> void:
	var state = _state()
	var ns = state.player()
	var target := _behind(state)
	var e: Dictionary = Sectors.priority_estimate(state, ns, _loader, "health", "hospitals", target)
	if int(e.get("renewals_left", -1)) != 1 or int(e.get("rest_months", -1)) != 36:
		_fail("the strip offers %s renewals and a %s-month wait, not 1 and 36" % [e.get("renewals_left"), e.get("rest_months")])
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", target)
	for i in 12:
		_tick(state)
	var renewed: Dictionary = Sectors.set_priority(state, ns, _loader, "health", "hospitals", target)
	if not bool(renewed.get("ok", false)) or int((ns.sector_priorities["hospitals"] as Dictionary).get("renewals", -1)) != 1:
		_fail("the first renewal was refused or not counted: %s" % renewed)
	if bool(Sectors.priority_estimate(state, ns, _loader, "health", "hospitals", target).get("ok", true)):
		_fail("the strip offers a second renewal")
	var again: Dictionary = Sectors.set_priority(state, ns, _loader, "health", "hospitals", target)
	if bool(again.get("ok", true)) or String(again.get("reason", "")) == "":
		_fail("a second renewal was accepted: %s" % again)
	for i in 36:
		_tick(state)
	if ns.sector_priorities.has("hospitals"):
		_fail("the renewed priority outlived its second term")
	for i in 36:
		if bool(Sectors.set_priority(state, ns, _loader, "health", "hospitals", target).get("ok", true)):
			_fail("the region took the sector again %d months after its priority ended" % i)
			return
		_tick(state)
	if not bool(Sectors.set_priority(state, ns, _loader, "health", "hospitals", target).get("ok", false)):
		_fail("the region could not take the sector again 36 months after its priority ended")
	# A clear rests the region too, else clear-and-set restarts the count; another
	# region may take the sector meanwhile, and the region it replaces rests.
	Sectors.clear_priority(state, ns, "hospitals")
	if bool(Sectors.set_priority(state, ns, _loader, "health", "hospitals", target).get("ok", true)):
		_fail("a cleared priority could be set again at once")
	var other := _ahead(state)
	if not bool(Sectors.set_priority(state, ns, _loader, "health", "hospitals", other).get("ok", false)):
		_fail("another region could not take the sector while the first rests")
	Sectors.set_priority(state, ns, _loader, "health", "primary_care", target)
	Sectors.set_priority(state, ns, _loader, "health", "primary_care", other)
	if bool(Sectors.set_priority(state, ns, _loader, "health", "primary_care", target).get("ok", true)):
		_fail("a replaced region took the sector straight back")


## QA's TAKE on #267: the priorities through the game's own month (WorldMonth), not
## the step called by hand: one month re-caps the term against that month's rates,
## and 36 months end it and rest its region. A region whose headroom is under the term's
## reach, so the cap binds and follows the nation's rate.
func _test_the_game_month_ends_and_recaps_a_priority() -> void:
	var state = _state()
	var ns = state.player()
	var list := _list(state)
	var target := ""
	for id in _regions(state):
		var headroom := float(_u(state)[id]) - float(ns.unemployment_pct)
		if headroom > 0.0 and target == "":
			Sectors.set_priority(state, ns, _loader, "pensions", "basic_pension", id)
			var f := float((ns.sector_priorities.get("basic_pension", {}) as Dictionary).get("factor", 0.0))
			if f > 0.05 and f < 0.95:
				target = id
			else:
				ns.sector_priorities.clear()
				ns.sector_priority_rest.clear()
	if target == "":
		_fail("the fixture found no FRA region whose cap binds on basic pensions")
		return
	var pressed := float((ns.sector_priorities["basic_pension"] as Dictionary)["factor"])
	_game_month(state)
	var row: Dictionary = ns.sector_priorities.get("basic_pension", {})
	var reach := EC.OKUN * _gain_of(state, list, "basic_pension")
	var want := clampf((float(_without_u(state)[target]) - float(ns.unemployment_pct)) / reach, 0.0, 1.0)
	if int(row.get("months_left", -1)) != 35 or absf(float(row.get("factor", -1.0)) - want) > 1e-9 or float(row["factor"]) == pressed:
		_fail("a game month left the priority at %s months and factor %s (pressed %.9f, this month's cap %.9f)" % [
			row.get("months_left"), row.get("factor"), pressed, want])
	for i in 35:
		_game_month(state)
	if ns.sector_priorities.has("basic_pension") \
			or int((ns.sector_priority_rest.get("basic_pension", {}) as Dictionary).get(target, 0)) <= int(state.year) * 12 + int(state.month):
		_fail("36 game months did not end the priority and rest its region: %s, %s" % [ns.sector_priorities, ns.sector_priority_rest])


## One month of the whole game, in its own order (the clock is the caller's).
func _game_month(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	WorldMonth.tick_month(state, _loader)


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


## Every region's unemployment with the register emptied for one read.
func _without_u(state) -> Dictionary:
	var ns = state.player()
	var held: Dictionary = ns.sector_priorities.duplicate(true)
	ns.sector_priorities.clear()
	var out := _u(state)
	ns.sector_priorities.merge(held)
	return out


## The whole term's gain in its region now: its booked points x (1 - its output weight).
func _gain(state, list: Array) -> float:
	return _gain_of(state, list, "hospitals")


func _gain_of(state, list: Array, sector: String) -> float:
	var ns = state.player()
	var row: Dictionary = ns.sector_priorities[sector]
	return float(row["pts"]) * (1.0 - _weight(state, list, String(row["region_id"])))


## A region's share of the nation's output, over the regions' own total.
func _weight(state, list: Array, region_id: String) -> float:
	var shares: Dictionary = Regions.shares_of(state.player(), list)
	var output := 0.0
	for region in list:
		output += float(shares[region.id])
	return float(shares[region_id]) / output


## Put a region's unemployment without the priorities `headroom` points above the
## nation's, through a sited term on this state's own map (the region records are the
## loader's, shared by every test): a sited s moves the region's deviation by
## s x (1 - its output weight), so its unemployment by -OKUN x that.
func _set_headroom(state, region_id: String, headroom: float) -> void:
	var ns = state.player()
	var list := _list(state)
	var gap := float(_without_u(state)[region_id]) - float(ns.unemployment_pct)
	var sites: Dictionary = _sites(state).duplicate()
	sites[region_id] = float(sites.get(region_id, 0.0)) + (gap - headroom) / (EC.OKUN * (1.0 - _weight(state, list, region_id)))
	state.project_sited_pct["FRA"] = sites
