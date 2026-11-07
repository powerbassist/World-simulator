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

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LawMagnitude = preload("res://src/core/law_magnitude.gd")

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
	var failed := false
	for nation_id in ["FRA", "DEU", "GBR", "POL"]:
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
