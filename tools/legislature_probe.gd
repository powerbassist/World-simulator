extends SceneTree

## Headless probe: band B4's size half (docs/design/v5.3-ab.md 4.4, section 9):
##   APPDATA="$(mktemp -d)" godot --headless --path . --script res://tools/legislature_probe.gd [-- --laws]
## Dev-only, never ships.
##
## THE BAND: the same graded law at ten times its magnitude moves its yes-share by at least
## 5 points on at least 60 % of graded laws. No row is tagged yet (Content's), so every
## ordinary law with a budget effect stands in as graded here, at reference size. resolve_vote
## is the function the game divides with, on a new game of each playable nation. `--laws`
## prints each law's yes-share at reference and its signed move at ten times.
##
## BAND B5, the address (`--address`): one address moves a close division, within 5 % of
## seats, by 2 to 6 % of seats. `--regimes` runs the band's two scripted players through the
## game's own month, 48 months per nation, the same bill policy: table the open bill nearest
## its line. One addresses every bill, the other the first three within 5 % each year; a
## third never does, for reference. The first must pass fewer bills and end lower in approval
## than the second.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LawMagnitude = preload("res://src/core/law_magnitude.gd")
const Address = preload("res://src/sim/address.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const NATIONS := ["FRA", "DEU", "GBR", "POL"]
const CLOSE_POINTS := 5.0
const REGIME_MONTHS := 48
const CLOSEST_A_YEAR := 3

const BUDGET := ["spending_pct_gdp", "tax_rates_pct", "other_revenue_pct_gdp"]
const POINTS := 5.0
const BAND := 60.0


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("data did not load: %s" % [loader.errors])
		quit(1)
		return
	var laws: Array = loader.laws.filter(func(law) -> bool:
		return not law.constitutional and BUDGET.any(func(key: String) -> bool: return law.effects.has(key)))
	print("%d ordinary laws with a budget effect stand in as graded" % laws.size())
	var per_law := OS.get_cmdline_user_args().has("--laws")
	if OS.get_cmdline_user_args().has("--address"):
		_address_band(loader)
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--regimes"):
		for nation_id in NATIONS:
			_regimes(loader, nation_id)
		quit(0)
		return
	var failed := false
	for nation_id in NATIONS:
		var ns = GameState.new_game(loader, nation_id).player()
		var parties: Array = loader.parties[nation_id]
		var moved := 0
		var any := 0
		var total := 0.0
		var flipped_verdict := 0
		var widest := 0.0
		for law in laws:
			var graded = LawMagnitude.copy(law)
			graded.magnitude = {"value": 1.0, "reference": 1.0, "unit": "stand-in"}
			var one: Dictionary = Legislature.resolve_vote(ns, parties, graded)
			var ten: Dictionary = Legislature.resolve_vote(ns, parties, LawMagnitude.scaled(graded, 10.0))
			var seats_total := float(ns.assembly_seats)
			var signed := 100.0 * (float(ten["yes_seats"]) - float(one["yes_seats"])) / seats_total
			var points := absf(signed)
			if per_law:
				print("  %s %-34s yes %5.1f -> %+6.1f" % [nation_id, law.id, 100.0 * float(one["yes_seats"]) / seats_total, signed])
			total += points
			widest = maxf(widest, points)
			if points >= POINTS:
				moved += 1
			if points > 0.0:
				any += 1
			if bool(one["passed"]) != bool(ten["passed"]):
				flipped_verdict += 1
		var share := 100.0 * float(moved) / float(laws.size())
		failed = failed or share < BAND
		print("%s  %s: %d of %d laws move %.0f points or more at ten times (%.0f %%, band %.0f), mean %.1f, widest %.1f, %d move at all, %d change their verdict" % [
			"PASS" if share >= BAND else "FAIL", nation_id, moved, laws.size(), POINTS, share, BAND, total / float(laws.size()), widest, any, flipped_verdict])
	print("legislature probe: B4's size band %s" % ("FAILS" if failed else "holds"))
	quit(0)


## How far from its line a division stands, in points of the chamber. Against the two tallies,
## as a simple majority reads them, whichever majority the law asks for.
func _margin(result: Dictionary, seats: int) -> float:
	return 100.0 * absf(float(result["yes_seats"]) - float(result["no_seats"])) / float(seats)


## One address on every close division of a new game: Address.estimate, the read the strip
## shows, whose after the verb is pinned to (tests/test_address.gd).
func _address_band(loader) -> void:
	for nation_id in NATIONS:
		var state = GameState.new_game(loader, nation_id)
		state.year = 2026
		state.month = 1
		state.day = 1
		var ns = state.player()
		var moves: Array[float] = []
		var in_band := 0
		var flips := 0
		for law in loader.laws:
			if law.constitutional:
				continue
			var read: Dictionary = Address.estimate(state, ns, loader, law)
			if _margin(read["before"], ns.assembly_seats) > CLOSE_POINTS:
				continue
			var points := 100.0 * absf(float(read["after"]["yes_seats"]) - float(read["before"]["yes_seats"])) / float(ns.assembly_seats)
			moves.append(points)
			if points >= 2.0 and points <= 6.0:
				in_band += 1
			if bool(read["before"]["passed"]) != bool(read["after"]["passed"]):
				flips += 1
		moves.sort()
		if moves.is_empty():
			print("%s: no close division" % nation_id)
			continue
		print("%s: %d close divisions, %d move 2 to 6 %% of seats, min %.1f, median %.1f, max %.1f, %d change their verdict" % [
			nation_id, moves.size(), in_band, moves[0], moves[moves.size() / 2], moves[-1], flips])


func _regimes(loader, nation_id: String) -> void:
	var rows := {}
	for regime in ["never", "closest", "always"]:
		rows[regime] = _regime(loader, nation_id, regime)
		print("%s %-8s tabled %2d, passed %2d, close carried %2d, addresses %2d, approval %.1f, diary refused %d" % [nation_id, regime,
			rows[regime]["tabled"], rows[regime]["passed"], rows[regime]["close_passed"], rows[regime]["addresses"], rows[regime]["approval"], rows[regime]["refused"]])
	var bills: bool = int(rows["always"]["passed"]) < int(rows["closest"]["passed"])
	var approval: bool = float(rows["always"]["approval"]) < float(rows["closest"]["approval"])
	print("%s  %s: always against the three closest: passed %d against %d, approval %.1f against %.1f" % [
		"PASS" if bills and approval else "FAIL", nation_id, rows["always"]["passed"], rows["closest"]["passed"], rows["always"]["approval"], rows["closest"]["approval"]])


## One scripted player. Acts at the top of each month, before the month that closes it divides.
func _regime(loader, nation_id: String, regime: String) -> Dictionary:
	var state = GameState.new_game(loader, nation_id)
	var out := {"tabled": 0, "passed": 0, "close_passed": 0, "addresses": 0, "approval": 0.0, "refused": 0}
	var this_year := {}
	for i in REGIME_MONTHS:
		state.year = 2026 + i / 12
		state.month = i % 12 + 1
		state.day = 1
		var ns = state.player()
		var was_close := false
		if ns.tabled_bill.is_empty():
			var pick := _nearest_its_line(state, ns, loader)
			if pick["law"] != null:
				was_close = float(pick["margin"]) <= CLOSE_POINTS
				var year_count := int(this_year.get(state.year, 0))
				if regime == "always" or (regime == "closest" and was_close and year_count < CLOSEST_A_YEAR):
					if bool(Address.give(state, loader, pick["law"].id).get("ok", false)):
						out["addresses"] += 1
						this_year[state.year] = year_count + 1
					else:
						out["refused"] += 1
				if bool(Legislature.propose(state, loader, pick["law"]).get("tabled", false)):
					out["tabled"] += 1
		var report: Dictionary = WorldMonth.tick_month(state, loader)
		var division: Dictionary = report.get("division", {})
		if bool(division.get("passed", false)):
			out["passed"] += 1
			if was_close:
				out["close_passed"] += 1
	out["approval"] = float(state.player().overall_approval_pct)
	return out


func _nearest_its_line(state, ns, loader) -> Dictionary:
	var best = null
	var margin := INF
	for law in Legislature.available(ns, loader.laws):
		if law.constitutional:
			continue
		var m := _margin(Legislature.resolve_vote(ns, loader.parties.get(ns.id, []), law), ns.assembly_seats)
		if m < margin:
			margin = m
			best = law
	return {"law": best, "margin": margin}
