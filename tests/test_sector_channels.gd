extends SceneTree

## V5.3 a (docs/design/v5.3-ab.md 3.1, bands A1 and A2): a moved sector share moves
## its sector's quantity and, through it, the channel its line already fed --
## society's quality (health, pensions), trend growth (education, infrastructure)
## and capability (defence). Read over the shipped data/domains/ rows.
##
## A1's byte half is the balance gate (no regime moves a share); the half pinned
## here is structural: with nothing moved every line's factor is exactly 1.0 and
## the register is empty, so each channel multiplies by exactly 1.0.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const Clock = preload("res://src/core/clock.gd")
const Sectors = preload("res://src/sim/sectors.gd")
const DK = preload("res://src/sim/domains_constants.gd")
const Society = preload("res://src/sim/society.gd")
const Defence = preload("res://src/sim/defence.gd")
const DefenceK = preload("res://src/sim/defence_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const EconomyC = preload("res://src/sim/economy_constants.gd")

const SLOT := "__test_sector_channels__"
## The channel each line feeds, by line id (the design's table, 3.1).
const QUALITY_LINES := ["health", "pensions"]
const TREND_BETA := {"education": EconomyC.EDU_BETA, "infrastructure": EconomyC.INFRA_BETA}
const SMALL_MOVE := 0.01

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_nothing_moved_reads_one()
	_test_the_factor_is_the_quantities_weighted_by_start_share()
	_test_more_to_the_more_elastic_sector_raises_the_factor()
	_test_society_quality_follows_its_factor()
	_test_capability_follows_its_factor()
	_test_trend_growth_follows_its_factor()
	_test_a_projection_carries_the_factor()
	_test_a_load_rebuilds_the_factor()
	_test_a_stale_vector_reads_one_after_a_load()
	_finish()


func _ns():
	return GameState.new_game(_loader, "FRA").player()


## The sector the line's least and most elastic, in the line's file order (ties to
## the first), so a move between them is the move the factor rewards most.
func _ends(line: String) -> Array:
	var lo := ""
	var hi := ""
	for s in Sectors.sectors_of(_loader, line):
		var id := String(s["id"])
		if lo == "" or float(DK.ELASTICITY[id]) < float(DK.ELASTICITY[lo]):
			lo = id
		if hi == "" or float(DK.ELASTICITY[id]) > float(DK.ELASTICITY[hi]):
			hi = id
	return [lo, hi]


## A small move, SMALL_MOVE of the line (less when the donor is near its floor):
## the factor's first-order direction. A large one meets the diminishing returns,
## so a big enough move toward the more elastic sector costs the channel too
## (education's schools -> universities at half of schools' share reads 0.93).
func _move(ns, line: String, from_id: String, to_id: String) -> void:
	var shares: Dictionary = Sectors.shares(ns, _loader, line)
	var amount := minf(SMALL_MOVE, 0.5 * (float(shares[from_id]) - DK.MIN_SHARE))
	var r: Dictionary = Sectors.move_share(ns, _loader, line, from_id, to_id, amount)
	if not bool(r.get("ok", false)):
		_fail("the fixture move %s -> %s on %s was refused: %s" % [from_id, to_id, line, r])


func _test_nothing_moved_reads_one() -> void:
	var ns = _ns()
	if not ns.sector_factor.is_empty():
		_fail("a new game holds a sector factor nobody bought: %s" % [ns.sector_factor])
	for line in DK.SECTOR_IDS:
		if Sectors.factor(ns, line) != 1.0:
			_fail("%s reads a factor of %s with nothing moved, not exactly 1.0" % [line, Sectors.factor(ns, line)])


## "A moved share moves its sector's quantity and, through it, the existing
## channel" (3.1): the factor is the start-share-weighted mean of what the move did
## to each sector's quantity, as an improvement (q / q0, or q0 / q for a
## lower-is-better figure), with the line's spending unchanged.
func _test_the_factor_is_the_quantities_weighted_by_start_share() -> void:
	for line in DK.SECTOR_IDS:
		var ns = _ns()
		var start: Dictionary = Sectors.shares(ns, _loader, line)
		var q0 := {}
		for id in start:
			q0[id] = Sectors.quantity(ns, _loader, line, id)
		var ends := _ends(line)
		_move(ns, line, ends[0], ends[1] if ends[0] != ends[1] else String(start.keys()[1]))
		var want := 0.0
		var weight := 0.0
		for s in Sectors.sectors_of(_loader, line):
			var id := String(s["id"])
			var gain := Sectors.quantity(ns, _loader, line, id) / float(q0[id])
			if String(s["quantity"]["better"]) == "lower":
				gain = 1.0 / gain
			want += float(start[id]) * gain
			weight += float(start[id])
		want /= weight
		if not is_equal_approx(Sectors.factor(ns, line), want):
			_fail("%s's factor is %.6f, not its quantities' weighted mean %.6f" % [line, Sectors.factor(ns, line), want])
		if Sectors.factor(ns, line) == 1.0:
			_fail("a move on %s left its factor at 1.0" % line)


## The design's direction: money moved toward the more elastic sector buys more of
## the channel, the reverse buys less, and with equal elasticities (pensions) any
## move away from the start buys less (each quantity's returns diminish).
func _test_more_to_the_more_elastic_sector_raises_the_factor() -> void:
	for line in DK.SECTOR_IDS:
		var ends := _ends(line)
		var lo := String(ends[0])
		var hi := String(ends[1])
		if float(DK.ELASTICITY[lo]) == float(DK.ELASTICITY[hi]):
			var ids: Array = Sectors.shares(_ns(), _loader, line).keys()
			var ns = _ns()
			_move(ns, line, String(ids[0]), String(ids[1]))
			if Sectors.factor(ns, line) >= 1.0:
				_fail("%s: a move between equally elastic sectors did not cost the channel" % line)
			continue
		var up = _ns()
		_move(up, line, lo, hi)
		if Sectors.factor(up, line) <= 1.0:
			_fail("%s: %s -> %s did not raise the factor (%.6f)" % [line, lo, hi, Sectors.factor(up, line)])
		var down = _ns()
		_move(down, line, hi, lo)
		if Sectors.factor(down, line) >= 1.0:
			_fail("%s: %s -> %s did not lower the factor (%.6f)" % [line, hi, lo, Sectors.factor(down, line)])


func _test_society_quality_follows_its_factor() -> void:
	for line in QUALITY_LINES:
		var ns = _ns()
		var before := Society.quality_target(ns, line)
		var ends := _ends(line)
		_move(ns, line, ends[0], ends[1] if ends[0] != ends[1] else String(Sectors.shares(ns, _loader, line).keys()[1]))
		var after := Society.quality_target(ns, line)
		if not is_equal_approx(after, before * Sectors.factor(ns, line)):
			_fail("%s quality moved x%.6f, not by its factor x%.6f" % [line, after / before, Sectors.factor(ns, line)])


func _test_capability_follows_its_factor() -> void:
	var ns = _ns()
	var before := Defence.capability_target(ns)
	var ends := _ends("defence")
	_move(ns, "defence", ends[0], ends[1])
	var want := clampf(float(ns.spending_pct_gdp["defence"]) * Sectors.factor(ns, "defence"),
		DefenceK.CAPABILITY_MIN, DefenceK.CAPABILITY_MAX)
	if not is_equal_approx(Defence.capability_target(ns), want) or Defence.capability_target(ns) == before:
		_fail("capability's target %.6f does not follow the defence factor (%.6f)" % [Defence.capability_target(ns), want])


## The potential shift's target reads the line as spend x factor - start, so one
## month of its lag moves the shift by beta x spend x (factor - 1) x SHIFT_ADJUST / 12
## against an identical nation that moved nothing.
func _test_trend_growth_follows_its_factor() -> void:
	for line in TREND_BETA:
		var still = GameState.new_game(_loader, "FRA")
		var moved = GameState.new_game(_loader, "FRA")
		var ns = moved.player()
		var ends := _ends(line)
		_move(ns, line, ends[0], ends[1])
		Economy._update_potential_shift(still, still.player())
		Economy._update_potential_shift(moved, ns)
		var want := float(TREND_BETA[line]) * float(ns.spending_pct_gdp[line]) \
			* (Sectors.factor(ns, line) - 1.0) * EconomyC.SHIFT_ADJUST / 12.0
		var got := float(ns.potential_shift_pct) - float(still.player().potential_shift_pct)
		if want == 0.0 or not is_equal_approx(got, want):
			_fail("%s moved the potential shift by %.8f, not %.8f" % [line, got, want])


## Budget.project() and every preview tick a copy, so the copy keeps the factor.
func _test_a_projection_carries_the_factor() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var ends := _ends("health")
	_move(ns, "health", ends[0], ends[1])
	var copy = state.duplicate_state()
	if Sectors.factor(copy.player(), "health") != Sectors.factor(ns, "health"):
		_fail("a projection lost the health factor")
	(copy.player().sector_factor as Dictionary)["health"] = 2.0
	if Sectors.factor(ns, "health") == 2.0:
		_fail("a projection shares the live nation's factor register")


## The factor is derived, not saved (Economy, Society and Defence read it with no
## loader): the load path re-derives it from the saved moves and the shipped rows.
func _test_a_load_rebuilds_the_factor() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var ends := _ends("education")
	_move(ns, "education", ends[0], ends[1])
	var bought := Sectors.factor(ns, "education")
	var loaded = _round_trip(state)
	if loaded == null:
		return
	if not is_equal_approx(Sectors.factor(loaded.player(), "education"), bought):
		_fail("a load re-derived the education factor as %.6f, not %.6f" % [Sectors.factor(loaded.player(), "education"), bought])
	var raw: Dictionary = state.to_dict()
	if (raw["nations"]["FRA"] as Dictionary).has("sector_factor"):
		_fail("the factor was written to the save (it is derived)")


## A content edit that renamed a sector since the save drops the moved vector for
## the start shares (Sectors.shares), and the load drops its factor with it, so
## the channel and the tile never disagree.
func _test_a_stale_vector_reads_one_after_a_load() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var ends := _ends("health")
	_move(ns, "health", ends[0], ends[1])
	(ns.sector_shares["health"] as Dictionary)["casino_wing"] = 0.0
	var loaded = _round_trip(state)
	if loaded == null:
		return
	if Sectors.factor(loaded.player(), "health") != 1.0:
		_fail("a stale moved vector kept a factor of %.6f after a load" % Sectors.factor(loaded.player(), "health"))


func _round_trip(state):
	var clock := Clock.new()
	clock.year = state.year
	clock.month = state.month
	clock.day = 1
	var error := SaveManager.save_game(state, clock, SLOT)
	clock.free()
	if not error.is_empty():
		_fail("save_game failed: %s" % error)
		return null
	var result := SaveManager.load_game(SLOT, _loader)
	SaveManager.delete_slot(SLOT)
	if not bool(result["ok"]):
		_fail("load_game failed: %s" % result["error"])
		return null
	return result["state"]


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_sector_channels")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)
