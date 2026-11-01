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
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", String(_regions(state)[0]))
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


## absent_ok: no save before V5.3 a held a priority, so absent is "none".
func _test_clearing_and_a_save() -> void:
	var state = _state()
	var ns = state.player()
	var region := String(_regions(state)[0])
	Sectors.set_priority(state, ns, _loader, "health", "hospitals", region)
	var kept = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	if Sectors.priority_of(kept.player(), "hospitals") != region:
		_fail("a priority did not survive the round trip")
	Sectors.clear_priority(ns, "hospitals")
	if Sectors.priority_of(ns, "hospitals") != "" \
			or Sectors.regional_quantity(ns, _loader, "health", "hospitals", region) != Sectors.quantity(ns, _loader, "health", "hospitals"):
		_fail("a cleared priority still lifts its region")


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
