extends SceneTree

## Region fund probe: godot --headless --script res://tools/region_fund_probe.gd -- [--json=PATH]
##
## V5.3 a, band A7 (docs/design/v5.3-ab.md 3.3 and 9), on the game's own month
## (src/sim/world_month.gd): for each playable nation, a fund of 1 bn a year to the
## named region with the highest unemployment at the start (ties to the first in the
## nation's region list) lowers that region's unemployment by 0.3 to 1.0 point in 24
## months, against a twin that opened no fund. The fund runs FUND_YEARS so it is still
## open at month 24; the figure at month 12 and the strip's own estimate are printed
## beside it. A probe that read the formula once would measure a world the game
## never runs (AGENTS.md: green is not measured): the national rate, the fund's own
## spending and the regions' levels all move in 24 months.
##
## Not a test, excluded from run_tests.sh. tests/test_region_funds.gd pins the
## mechanism; this prints the numbers a human reads, and exits 1 on a failed band.
##
## `--priority` (#267): the same twin run for a sector priority instead of a fund --
## each PRIORITY_SECTORS sector put first in the same worst region, against a twin
## with none: the region's drop at months 12 and 24, the other named regions' rise
## (weighted by their people), the strip's estimate, and the national unemployment
## and GDP moves (a priority moves money between regions, so they stay near 0). No
## band is declared for it; it exits 1 only if the region does not fall or the
## others do not rise.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Regions = preload("res://src/sim/regions.gd")
const RegionFunds = preload("res://src/sim/region_funds.gd")
const RK = preload("res://src/sim/region_constants.gd")
const Sectors = preload("res://src/sim/sectors.gd")

const NATIONS := ["DEU", "FRA", "GBR", "POL"]
const EUR_BN := 1.0
const FUND_YEARS := 3
const MONTHS := 24
const BAND := Vector2(0.3, 1.0)
## [line, sector]: a mid-sized sector and the largest one (basic pensions).
const PRIORITY_SECTORS := [["health", "hospitals"], ["pensions", "basic_pension"]]


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
	if "--priority" in OS.get_cmdline_user_args():
		quit(_priorities(loader))
		return
	var rows: Array = []
	var ok_all := true
	for nation in NATIONS:
		var still = GameState.new_game(loader, nation)
		var funded = GameState.new_game(loader, nation)
		var region := _worst(still)
		var est: Dictionary = RegionFunds.estimate(funded, funded.player(), loader, region, EUR_BN, FUND_YEARS)
		var start: Dictionary = RegionFunds.start(funded, funded.player(), loader, region, EUR_BN, FUND_YEARS)
		var at_12 := 0.0
		for i in range(MONTHS):
			WorldMonth.tick_month(still, loader)
			WorldMonth.tick_month(funded, loader)
			if i == 11:
				at_12 = _u(still, region) - _u(funded, region)
		var drop := _u(still, region) - _u(funded, region)
		var ok := bool(start.get("ok", false)) and drop >= BAND.x and drop <= BAND.y
		ok_all = ok_all and ok
		var estimated := float(est.get("unemployment_now", 0.0)) - float(est.get("unemployment_after", 0.0))
		rows.append({"nation": nation, "region": region, "output_eur_bn": Regions.output_eur_bn(still.player(), region),
			"pts": float(est.get("pts", 0.0)), "estimated_drop": estimated, "drop_12": at_12, "drop_24": drop, "ok": ok})
		print("%s %-6s output %6.1f bn  term %.3f pts  estimate %.3f  month 12 %.3f  month 24 %.3f %s" % [
			nation, region, Regions.output_eur_bn(still.player(), region), float(est.get("pts", 0.0)),
			estimated, at_12, drop, "ok" if ok else "FAIL"])
	if json_path != "":
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		if f == null:
			printerr("could not write %s" % json_path)
			quit(1)
			return
		f.store_string(JSON.stringify({"rows": rows, "pass": ok_all}, "  "))
		f.close()
	print("region_fund_probe: %s" % ("PASS" if ok_all else "FAIL"))
	quit(0 if ok_all else 1)


## The --priority run: one twin pair per nation and sector. 0 when every region put
## first fell and every other side rose, else 1.
static func _priorities(loader) -> int:
	var bad := 0
	for nation in NATIONS:
		for pick in PRIORITY_SECTORS:
			var still = GameState.new_game(loader, nation)
			var first = GameState.new_game(loader, nation)
			var region := _worst(still)
			var est: Dictionary = Sectors.priority_estimate(first, first.player(), loader, pick[0], pick[1], region)
			var applied: Dictionary = Sectors.set_priority(first, first.player(), loader, pick[0], pick[1], region)
			var at_12 := 0.0
			for i in range(MONTHS):
				WorldMonth.tick_month(still, loader)
				WorldMonth.tick_month(first, loader)
				if i == 11:
					at_12 = _u(still, region) - _u(first, region)
			var drop := _u(still, region) - _u(first, region)
			var rise := _others(first, region) - _others(still, region)
			var nat_u: float = float(first.player().unemployment_pct) - float(still.player().unemployment_pct)
			var nat_gdp: float = 100.0 * (float(first.player().gdp_eur_bn) / float(still.player().gdp_eur_bn) - 1.0)
			var ok := bool(applied.get("ok", false)) and drop > 0.0 and rise > 0.0
			if not ok:
				bad += 1
			print("%s %-6s %-14s term %.3f pts  estimate %.3f / others +%.4f  month 12 %.3f  month 24 %.3f  others +%.4f  nation u %+.5f gdp %+.5f %%  %s" % [
				nation, region, pick[1], float(est.get("pts", 0.0)),
				float(est.get("unemployment_now", 0.0)) - float(est.get("unemployment_after", 0.0)),
				float(est.get("others_unemployment_after", 0.0)) - float(est.get("others_unemployment_now", 0.0)),
				at_12, drop, rise, nat_u, nat_gdp, "ok" if ok else "FAIL"])
	print("region_fund_probe --priority: %s" % ("PASS" if bad == 0 else "FAIL"))
	return 0 if bad == 0 else 1


## The other named regions' unemployment, weighted by their people.
static func _others(state, region_id: String) -> float:
	var ns = state.player()
	var weighted := 0.0
	var people := 0.0
	for region in state.regions.get(ns.id, []):
		if region.id != RK.RESIDUAL_KEY and region.id != region_id:
			var p := float(ns.region_pop_share.get(region.id, 0.0))
			weighted += p * _u(state, region.id)
			people += p
	return weighted / people if people > 0.0 else 0.0


static func _u(state, region_id: String) -> float:
	var ns = state.player()
	var list: Array = state.regions.get(ns.id, [])
	var access := Regions.accessibility_for(ns, list, state.region_graph)
	return Regions.unemployment_pct(ns, list, region_id, access, state.project_sited_pct.get(ns.id, {}))


## The named region with the highest unemployment now, ties to the first in list order.
static func _worst(state) -> String:
	var best := ""
	var best_u := -1.0
	for region in state.regions.get(state.player().id, []):
		if region.id == RK.RESIDUAL_KEY:
			continue
		var u := _u(state, region.id)
		if u > best_u + 1e-9:
			best = region.id
			best_u = u
	return best
