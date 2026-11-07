extends SceneTree

## V5.3 a (docs/design/v5.3-ab.md 3.1, bands A1 and A2): each spending line split
## into sectors, read from data/domains/<line>.json (the shape agreed with Content,
## 2026-11-01). The loader's parse step is public, so every refusal is tested on a
## dictionary with no file on disk (the parse_embassy_exceptions idiom). Nothing
## feeds a channel yet, so A1 holds trivially here; A2 -- every sector moves its
## quantity, by its declared elasticity -- is pinned below.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const DomainsLoader = preload("res://src/core/loaders/domains_loader.gd")
const Sectors = preload("res://src/sim/sectors.gd")
const DK = preload("res://src/sim/domains_constants.gd")

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_a_good_line_parses_and_renormalises()
	_test_every_refusal()
	_test_a_need_drift_is_optional()
	_test_every_sector_id_has_a_moving_elasticity()
	_test_a_share_move_moves_each_quantity_by_its_elasticity()
	_test_a_lower_is_better_quantity_falls_with_spending()
	_test_a_zero_line_stays_finite()
	_test_move_share_refusals()
	_test_moved_shares_survive_a_save()
	_finish()


## A line as Content writes it: three sectors, FRA and the default, shares that sum
## to 1.0 within the rounding the loader tolerates.
func _health() -> Dictionary:
	return {
		"line": "health",
		"sectors": [
			_sector("hospitals", "beds_per_1000", "higher", 0.433, 5.34, 0.493, 4.0),
			_sector("primary_care", "physicians_per_100k", "higher", 0.536, 340.0, 0.485, 300.0),
			_sector("prevention", "screening_index", "higher", 0.0305, 100.0, 0.022, 100.0),
		],
	}


func _sector(id: String, quantity: String, better: String, fra_share: float, fra_q: float,
		default_share: float, default_q: float) -> Dictionary:
	return {
		"id": id, "name": id, "summary": "A sector.", "codes": ["GF0703"],
		"quantity": {"id": quantity, "unit": "per 1 000", "better": better},
		"start": {
			"FRA": {"share": fra_share, "quantity": fra_q, "year": 2024.0, "source": "Eurostat"},
			"default": {"share": default_share, "quantity": default_q, "year": 2024.0, "source": "default"},
		},
	}


func _parse(raw: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	DomainsLoader.parse_line(_loader, raw, "health.json", errors)
	return errors


func _test_a_good_line_parses_and_renormalises() -> void:
	var errors: Array[String] = []
	var line: Dictionary = DomainsLoader.parse_line(_loader, _health(), "health.json", errors)
	if not errors.is_empty():
		_fail("a good line was refused: %s" % [errors])
		return
	var total := 0.0
	for s in line["sectors"]:
		total += float(s["start"]["FRA"]["share"])
	# 0.433 + 0.536 + 0.0305 = 0.9995, inside the tolerance and renormalised to 1.
	if not is_equal_approx(total, 1.0):
		_fail("FRA's shares sum to %.6f after the parse, not 1.0" % total)


func _test_every_refusal() -> void:
	var cases := {
		"an unknown line": func(r: Dictionary) -> void: r["line"] = "casinos",
		"a line in the wrong file": func(r: Dictionary) -> void: r["line"] = "education",
		"one sector": func(r: Dictionary) -> void: (r["sectors"] as Array).resize(1),
		"a duplicate sector id": func(r: Dictionary) -> void: r["sectors"][1]["id"] = "hospitals",
		"a missing name": func(r: Dictionary) -> void: (r["sectors"][0] as Dictionary).erase("name"),
		"codes not strings": func(r: Dictionary) -> void: r["sectors"][0]["codes"] = [703],
		"a bad better": func(r: Dictionary) -> void: r["sectors"][0]["quantity"]["better"] = "more",
		"no default": func(r: Dictionary) -> void:
			for s in r["sectors"]:
				(s["start"] as Dictionary).erase("default"),
		"a start key off the roster": func(r: Dictionary) -> void:
			for s in r["sectors"]:
				s["start"]["XXX"] = s["start"]["FRA"],
		"a nation missing from one sector": func(r: Dictionary) -> void: (r["sectors"][2]["start"] as Dictionary).erase("FRA"),
		"a share of zero": func(r: Dictionary) -> void: r["sectors"][0]["start"]["FRA"]["share"] = 0.0,
		"shares off 1.0": func(r: Dictionary) -> void: r["sectors"][0]["start"]["FRA"]["share"] = 0.5,
		"a quantity of zero": func(r: Dictionary) -> void: r["sectors"][0]["start"]["FRA"]["quantity"] = 0.0,
		"an empty source": func(r: Dictionary) -> void: r["sectors"][0]["start"]["FRA"]["source"] = "",
		"a sector with no elasticity": func(r: Dictionary) -> void: r["sectors"][0]["id"] = "casino_sector",
		"a need drift that is no number": func(r: Dictionary) -> void:
			r["sectors"][0]["start"]["FRA"]["need_drift_pct_year"] = "fast"
			r["sectors"][0]["start"]["FRA"]["need_source"] = "Eurostat",
		"a need drift with no source": func(r: Dictionary) -> void: r["sectors"][0]["start"]["FRA"]["need_drift_pct_year"] = 2.4,
		"a need drift of a shrinking kind of nonsense": func(r: Dictionary) -> void:
			r["sectors"][0]["start"]["FRA"]["need_drift_pct_year"] = -100.0
			r["sectors"][0]["start"]["FRA"]["need_source"] = "Eurostat",
	}
	for label in cases:
		var raw := _health().duplicate(true)
		(cases[label] as Callable).call(raw)
		if _parse(raw).is_empty():
			_fail("the loader accepted %s" % label)


## A row with no need drift reads 0, the need of a line with no demographic driver.
func _test_a_need_drift_is_optional() -> void:
	var errors: Array[String] = []
	var raw := _health().duplicate(true)
	raw["sectors"][0]["start"]["FRA"]["need_drift_pct_year"] = 2.4
	raw["sectors"][0]["start"]["FRA"]["need_source"] = "Eurostat"
	var line: Dictionary = DomainsLoader.parse_line(_loader, raw, "health.json", errors)
	if not errors.is_empty():
		_fail("a sourced need drift was refused: %s" % [errors])
		return
	var fra: Dictionary = line["sectors"][0]["start"]["FRA"]
	if float(fra["need_drift_pct_year"]) != 2.4 or String(fra["need_source"]) != "Eurostat":
		_fail("the need drift did not load: %s" % [fra])
	if float(line["sectors"][1]["start"]["FRA"]["need_drift_pct_year"]) != 0.0:
		_fail("a row with no need drift did not read 0")


## A2's load half: a sector that moves nothing is refused, so every sector id the
## agreed ids name has an elasticity above zero (a magnitude: `better` gives the
## sign, more spending always improves the quantity).
func _test_every_sector_id_has_a_moving_elasticity() -> void:
	for line in DK.SECTOR_IDS:
		for id in DK.SECTOR_IDS[line]:
			if float(DK.ELASTICITY.get(id, 0.0)) <= 0.0:
				_fail("sector %s has no elasticity: it would move nothing" % id)


func _state_with_health():
	_loader.domains.clear()
	var errors: Array[String] = []
	var line: Dictionary = DomainsLoader.parse_line(_loader, _health(), "health.json", errors)
	_loader.domains["health"] = line
	var state = GameState.new_game(_loader, "FRA")
	return state


## A2: a 10 % move of a sector's share moves its quantity by its elasticity -- the
## spec's "a declared amount" -- and the line's spending unchanged moves nothing.
func _test_a_share_move_moves_each_quantity_by_its_elasticity() -> void:
	var state = _state_with_health()
	var ns = state.player()
	var before := {}
	for id in ["hospitals", "primary_care", "prevention"]:
		before[id] = Sectors.quantity(ns, _loader, "health", id)
	if not is_equal_approx(float(before["hospitals"]), 5.34):
		_fail("the start quantity is %.4f, not the row's 5.34" % float(before["hospitals"]))
	var shares: Dictionary = Sectors.shares(ns, _loader, "health")
	var amount := 0.1 * float(shares["hospitals"])
	var r: Dictionary = Sectors.move_share(ns, _loader, "health", "primary_care", "hospitals", amount)
	if not bool(r.get("ok", false)):
		_fail("a 10 %% move was refused: %s" % r)
		return
	var gained := pow(1.1, float(DK.ELASTICITY["hospitals"]))
	if not is_equal_approx(Sectors.quantity(ns, _loader, "health", "hospitals"), float(before["hospitals"]) * gained):
		_fail("hospitals moved by %.4f, not its declared x%.4f" % [
			Sectors.quantity(ns, _loader, "health", "hospitals") / float(before["hospitals"]), gained])
	var lost_ratio := (float(shares["primary_care"]) - amount) / float(shares["primary_care"])
	var lost := pow(lost_ratio, float(DK.ELASTICITY["primary_care"]))
	if not is_equal_approx(Sectors.quantity(ns, _loader, "health", "primary_care"), float(before["primary_care"]) * lost):
		_fail("primary care did not move by its declared elasticity")
	if not is_equal_approx(Sectors.quantity(ns, _loader, "health", "prevention"), float(before["prevention"])):
		_fail("a sector the move did not touch moved")
	var total := 0.0
	for v in Sectors.shares(ns, _loader, "health").values():
		total += float(v)
	if not is_equal_approx(total, 1.0):
		_fail("a pure reallocation changed the line's total share to %.6f" % total)
	_loader.domains.erase("health")


## A spending line cut to zero reads its floor, never infinity.
func _test_a_zero_line_stays_finite() -> void:
	var raw := _health()
	raw["sectors"][1]["quantity"]["better"] = "lower"
	var errors: Array[String] = []
	_loader.domains.clear()
	_loader.domains["health"] = DomainsLoader.parse_line(_loader, raw, "health.json", errors)
	var ns = GameState.new_game(_loader, "FRA").player()
	ns.spending_pct_gdp["health"] = 0.0
	for id in ["hospitals", "primary_care"]:
		var q := Sectors.quantity(ns, _loader, "health", id)
		if is_inf(q) or is_nan(q) or q <= 0.0:
			_fail("%s reads %s with its line at zero" % [id, q])
	_loader.domains.erase("health")


## `better` gives the sign: more spending on a lower-is-better sector (pupils per
## teacher) lowers its quantity, by the same elasticity.
func _test_a_lower_is_better_quantity_falls_with_spending() -> void:
	_loader.domains.clear()
	var raw := _health()
	raw["sectors"][1]["quantity"]["better"] = "lower"
	var errors: Array[String] = []
	_loader.domains["health"] = DomainsLoader.parse_line(_loader, raw, "health.json", errors)
	var ns = GameState.new_game(_loader, "FRA").player()
	var q0 := Sectors.quantity(ns, _loader, "health", "primary_care")
	var share := float(Sectors.shares(ns, _loader, "health")["primary_care"])
	Sectors.move_share(ns, _loader, "health", "hospitals", "primary_care", 0.1 * share)
	var want := q0 * pow(1.1, -float(DK.ELASTICITY["primary_care"]))
	if not is_equal_approx(Sectors.quantity(ns, _loader, "health", "primary_care"), want):
		_fail("a lower-is-better quantity did not fall by its elasticity with more spending")
	_loader.domains.erase("health")


func _test_move_share_refusals() -> void:
	var state = _state_with_health()
	var ns = state.player()
	var shares: Dictionary = Sectors.shares(ns, _loader, "health")
	var bad := {
		"an unknown line": ["casinos", "hospitals", "prevention", 0.01],
		"an unknown sector": ["health", "hospitals", "casinos", 0.01],
		"the same sector": ["health", "hospitals", "hospitals", 0.01],
		"a negative amount": ["health", "hospitals", "prevention", -0.01],
		"a sector below its floor": ["health", "prevention", "hospitals", float(shares["prevention"])],
	}
	for label in bad:
		var a: Array = bad[label]
		if bool(Sectors.move_share(ns, _loader, a[0], a[1], a[2], a[3]).get("ok", true)):
			_fail("move_share accepted %s" % label)
	if not ns.sector_shares.is_empty():
		_fail("a refused move wrote the register")
	_loader.domains.erase("health")


## The register holds the player's moves only: absent reads the start shares, the
## truth for every older save, so no SAVE bump.
func _test_moved_shares_survive_a_save() -> void:
	var state = _state_with_health()
	var ns = state.player()
	if not ns.sector_shares.is_empty():
		_fail("a new game stored shares nobody moved (a content copy would need a bump)")
	Sectors.move_share(ns, _loader, "health", "primary_care", "hospitals", 0.05)
	var moved := Sectors.shares(ns, _loader, "health")
	var kept = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	var again := Sectors.shares(kept.player(), _loader, "health")
	for id in moved:
		if not is_equal_approx(float(moved[id]), float(again[id])):
			_fail("the moved share of %s did not survive the round trip" % id)
	var without: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(without["nations"]["FRA"] as Dictionary).erase("sector_shares")
	var start := Sectors.shares(GameState.from_dict(without).player(), _loader, "health")
	if not is_equal_approx(float(start["hospitals"]), 0.433 / 0.9995):
		_fail("an absent register did not read the start shares")
	_loader.domains.erase("health")


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_domains")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)
