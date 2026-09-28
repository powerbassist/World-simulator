extends SceneTree

## V4.7a A3: the tick budget on the REAL register -- the V4.6 probe's synthetic
## 2,900-firm scale, now measured against the shipped content. Band (declared
## in the plan before the block started): the firms layer's month across all 29
## nations stays inside 300 ms, the same headroom the commodity layer's gate
## kept. Verdict to reports/industry_scale_probe.txt (FileAccess -- stdout
## interleaves badly through pipes).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Companies = preload("res://src/sim/companies.gd")

var _lines: Array[String] = []


func _init() -> void:
	var loader = DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_line("DATA DID NOT LOAD CLEANLY: %s" % [loader.errors])
		_finish(1)
		return
	var state = GameState.new_game(loader, "FRA")
	var firm_total := 0
	var body_total := 0
	for nation_id in loader.companies.keys():
		firm_total += loader.companies[nation_id].size()
		for company in loader.companies[nation_id]:
			if not Companies.is_major(company):
				body_total += 1
	_line("register: %d majors + %d body = %d firms across %d nations" % [
		firm_total - body_total, body_total, firm_total, loader.companies.size()])

	# One warm tick excluded (the Dijkstra/class-cache warmup artifact V3.3's
	# probe documented), then the firms layer timed over 24 months -- the same
	# tick set the balance harness drives.
	var warm = state
	Companies.tick_month(warm, loader)
	var best_ms := 1e9
	var worst_ms := 0.0
	var total_ms := 0.0
	var runs := 3
	for r in runs:
		var probe = GameState.new_game(loader, "FRA")
		for m in 24:
			Economy.tick_month(probe)
			Budget.tick_month(probe)
			var t0 := Time.get_ticks_usec()
			Companies.tick_month(probe, loader)
			var dt_ms := float(Time.get_ticks_usec() - t0) / 1000.0
			if m > 0:
				total_ms += dt_ms
				best_ms = minf(best_ms, dt_ms)
				worst_ms = maxf(worst_ms, dt_ms)
	var n := float(runs * 23)
	_line("firms layer per month (excl. first warm tick), %d runs x 23 ticks:" % runs)
	_line("  mean %.3f ms | best %.3f ms | worst %.3f ms -- band 300 ms" % [
		total_ms / n, best_ms, worst_ms])
	var ok := worst_ms < 300.0
	_line("verdict: %s" % ["PASS" if ok else "FAIL"])
	_finish(0 if ok else 1)


func _line(s: String) -> void:
	_lines.append(s)
	print(s)


func _finish(code: int) -> void:
	var f := FileAccess.open("res://reports/industry_scale_probe.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	quit(code)
