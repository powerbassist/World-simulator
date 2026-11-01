extends SceneTree

## Sector probe: godot --headless --script res://tools/sector_probe.gd -- [--json=PATH]
##
## V5.3 a, band A2 (docs/design/v5.3-ab.md 3.1 and 9), on the game's own month
## (src/sim/world_month.gd), for the four playable nations:
##   (a) QUANTITIES -- every sector's quantity moves by its declared
##       (1 + MOVE) ^ elasticity (the sign from its `better`) when MOVE of its own
##       share is moved into it from the line's largest other sector, and the donor
##       moves the other way. A pure read: the line's money is unchanged.
##   (b) CHANNELS -- one month after a move of up to LINE_MOVE of the line from its
##       least to its most elastic sector, the channel the line feeds has moved in
##       the factor's direction against a twin that moved nothing: society's
##       quality (health, pensions), the potential shift (education,
##       infrastructure), capability (defence). Banded at month 1 because the twins
##       are whole worlds: by month MONTHS (printed, not banded) an election or a
##       cabinet can differ between them for reasons a tiny move (DEU's prevention
##       can give 0.002 of its line) does not control. A big move can cost the
##       channel even toward the more elastic sector (diminishing returns,
##       src/sim/sectors.gd), so the factor's own sign is the band, not "up".
## A probe that read the channels after one call would measure a world the game
## never runs (AGENTS.md: green is not measured), so (b) ticks both twins through
## WorldMonth.tick_month().
##
## Not a test, excluded from run_tests.sh. tests/test_sector_channels.gd pins the
## mechanisms; this prints the numbers a human reads, and exits 1 on a failed band.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Sectors = preload("res://src/sim/sectors.gd")
const DK = preload("res://src/sim/domains_constants.gd")

const NATIONS := ["DEU", "FRA", "GBR", "POL"]
const START_YEAR := 2026
## A2's "when its share moves by 10 %".
const MOVE := 0.10
## The channel run's move, as a share of the line, capped by the donor's floor.
const LINE_MOVE := 0.10
const MONTHS := 24


func _initialize() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return
	var json_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--json="):
			json_path = arg.substr(7)
	var out := {"nations": {}, "pass": true}
	for nation in NATIONS:
		var quantities := _quantities(loader, nation)
		var channels := _channels(loader, nation)
		for row in quantities + channels:
			if not bool(row["ok"]):
				out["pass"] = false
		out["nations"][nation] = {"quantities": quantities, "channels": channels}
	if json_path != "":
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		if f == null:
			printerr("could not write %s: %s" % [json_path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(JSON.stringify(out, "  "))
		f.close()
	print("sector_probe: %s" % ("PASS" if bool(out["pass"]) else "FAIL"))
	quit(0 if bool(out["pass"]) else 1)


func _fresh(loader, nation: String):
	var state = GameState.new_game(loader, nation)
	state.year = START_YEAR
	return state


## (a): one row per sector of every line.
func _quantities(loader, nation: String) -> Array:
	var rows: Array = []
	for line in DK.SECTOR_IDS:
		for s in Sectors.sectors_of(loader, line):
			var id := String(s["id"])
			var ns = _fresh(loader, nation).player()
			var shares: Dictionary = Sectors.shares(ns, loader, line)
			var donor := ""
			for other in shares:
				if other != id and (donor == "" or float(shares[other]) > float(shares[donor])):
					donor = String(other)
			var q0 := Sectors.quantity(ns, loader, line, id)
			var d0 := Sectors.quantity(ns, loader, line, donor)
			var r: Dictionary = Sectors.move_share(ns, loader, line, donor, id, MOVE * float(shares[id]))
			var sign := -1.0 if String(s["quantity"]["better"]) == "lower" else 1.0
			var declared := pow(1.0 + MOVE, sign * float(DK.ELASTICITY[id]))
			var got := Sectors.quantity(ns, loader, line, id) / q0 if q0 != 0.0 else 0.0
			var donor_moved := Sectors.quantity(ns, loader, line, donor) != d0
			var ok := bool(r.get("ok", false)) and is_equal_approx(got, declared) and donor_moved
			rows.append({"line": line, "sector": id, "declared": declared, "got": got, "ok": ok})
			print("%s %-15s %-16s x%.4f declared x%.4f %s" % [nation, line, id, got, declared, "ok" if ok else "FAIL"])
	return rows


## (b): one row per line, the moved twin against the still one after MONTHS.
func _channels(loader, nation: String) -> Array:
	var rows: Array = []
	for line in DK.SECTOR_IDS:
		var still = _fresh(loader, nation)
		var moved = _fresh(loader, nation)
		var ns = moved.player()
		var ends := _ends(loader, line)
		var shares: Dictionary = Sectors.shares(ns, loader, line)
		var amount := minf(LINE_MOVE, float(shares[ends[0]]) - DK.MIN_SHARE - 0.001)
		Sectors.move_share(ns, loader, line, ends[0], ends[1], amount)
		var factor := Sectors.factor(ns, line)
		var month_1 := {}
		for i in range(MONTHS):
			WorldMonth.tick_month(still, loader)
			WorldMonth.tick_month(moved, loader)
			if i == 0:
				month_1 = {"base": _channel(still.player(), line), "moved": _channel(ns, line)}
		var base := float(month_1["base"])
		var after := float(month_1["moved"])
		var ok := factor != 1.0 and signf(after - base) == signf(factor - 1.0)
		var base_n := _channel(still.player(), line)
		var after_n := _channel(ns, line)
		rows.append({"line": line, "from": ends[0], "to": ends[1], "amount": amount, "factor": factor,
			"base": base, "moved": after, "base_end": base_n, "moved_end": after_n, "ok": ok})
		print("%s %-15s %s -> %s %.3f  factor %.5f  month 1 %.6f -> %.6f %s  month %d %.6f -> %.6f" % [
			nation, line, ends[0], ends[1], amount, factor, base, after, "ok" if ok else "FAIL",
			MONTHS, base_n, after_n])
	return rows


## The least and the most elastic sector of the line (ties to the first, so equal
## elasticities give the first two sectors).
func _ends(loader, line: String) -> Array:
	var ids: Array = []
	for s in Sectors.sectors_of(loader, line):
		ids.append(String(s["id"]))
	var lo := String(ids[0])
	var hi := String(ids[0])
	for id in ids:
		if float(DK.ELASTICITY[id]) < float(DK.ELASTICITY[lo]):
			lo = id
		if float(DK.ELASTICITY[id]) > float(DK.ELASTICITY[hi]):
			hi = id
	if lo == hi:
		hi = String(ids[1])
	return [lo, hi]


static func _channel(ns, line: String) -> float:
	match line:
		"health", "pensions":
			return float(ns.service_quality.get(line, 0.0))
		"education", "infrastructure":
			return float(ns.potential_shift_pct)
		"defence":
			return float(ns.military_capability)
	return 0.0
