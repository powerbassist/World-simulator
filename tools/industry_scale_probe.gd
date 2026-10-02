extends SceneTree

## V4.7a A3: the tick budget on the REAL register -- the V4.6 probe's synthetic
## 2,900-firm scale, now measured against the shipped content. Band (declared
## in the plan before the block started): the firms layer's month across all 29
## nations stays inside 300 ms, the same headroom the commodity layer's gate
## kept. Verdict to reports/industry_scale_probe.txt (FileAccess -- stdout
## interleaves badly through pipes).
##
## V4.7b B4 EXTENDED THE VERDICT to the autonomy machine, and the pass-5
## fleet forced the extension: B1's re-baseline found Industry.tick_month at
## 1,124 ms/month over the roster while this probe's PASS printed from a
## Companies-only number -- and B4's own fix then put the machine inside
## Budget.project(), the budget panel's per-frame 2x24-month projection, so
## an unbudgeted heaviest system sat on a per-frame path behind a gate that
## could not see it. The machine's month is now its own timed line with its
## own 300 ms band, and the verdict requires both. The projection path is
## BANDED TOO (7.0 s per 24-month project -- the pass-6 find; its ~4.5 s
## base predates this PR and stays recorded as PR #46's finding 6).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Companies = preload("res://src/sim/companies.gd")
const Industry = preload("res://src/sim/industry.gd")

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
	# tick set the balance harness drives. Companies and Industry are timed
	# on separate clocks from the SAME months: the memo makes the machine's
	# first month the expensive one, and its band is declared at 300 ms
	# against B4's measured 16.45 ms (worst 19.44) post-memo, 1,124 pre.
	var warm = state
	Companies.tick_month(warm, loader)
	Industry.tick_month(warm, loader)
	var best_ms := 1e9
	var worst_ms := 0.0
	var total_ms := 0.0
	var ind_best_ms := 1e9
	var ind_worst_ms := 0.0
	var ind_total_ms := 0.0
	var runs := 3
	for r in runs:
		var probe = GameState.new_game(loader, "FRA")
		for m in 24:
			Economy.tick_month(probe)
			Budget.tick_month(probe)
			var t0 := Time.get_ticks_usec()
			Companies.tick_month(probe, loader)
			var dt_ms := float(Time.get_ticks_usec() - t0) / 1000.0
			var t1 := Time.get_ticks_usec()
			Industry.tick_month(probe, loader)
			var dt_i := float(Time.get_ticks_usec() - t1) / 1000.0
			if m > 0:
				total_ms += dt_ms
				best_ms = minf(best_ms, dt_ms)
				worst_ms = maxf(worst_ms, dt_ms)
				ind_total_ms += dt_i
				ind_best_ms = minf(ind_best_ms, dt_i)
				ind_worst_ms = maxf(ind_worst_ms, dt_i)
	var n := float(runs * 23)
	_line("firms layer per month (excl. first warm tick), %d runs x 23 ticks:" % runs)
	_line("  companies mean %.3f ms | best %.3f ms | worst %.3f ms -- band 300 ms" % [
		total_ms / n, best_ms, worst_ms])
	_line("  industry mean %.3f ms | best %.3f ms | worst %.3f ms -- band 300 ms (B4's memo: 1,124 -> 16.45 measured)" % [
		ind_total_ms / n, ind_best_ms, ind_worst_ms])

	# V4.7a, the PR-46 review's sixth important: the LIVE tick was the only
	# thing this probe timed, but the roster's growth is multiplied 48x on the
	# budget panel's projection -- Budget.project ticks Companies, Industry
	# (B4's addition) AND Migration once per projected month, and the panel
	# runs TWO 24-month projections per refresh, re-refreshed per frame while
	# a slider drags. The projection path gets its own line here so the gate
	# cannot again be blind to the path that multiplies the register.
	const Budget = preload("res://src/sim/budget.gd")
	var proj_best := 1e9
	var proj_worst := 0.0
	var proj_total := 0.0
	var proj_runs := 3
	for r in proj_runs:
		var pstate = GameState.new_game(loader, "FRA")
		for i in proj_runs:
			var t0 := Time.get_ticks_usec()
			Budget.project(pstate, {}, 24, loader)
			var dt_ms := float(Time.get_ticks_usec() - t0) / 1000.0
			proj_total += dt_ms
			proj_best = minf(proj_best, dt_ms)
			proj_worst = maxf(proj_worst, dt_ms)
	_line("budget projection (1x24-month project), %d runs:" % (proj_runs * proj_runs))
	_line("  mean %.1f ms | best %.1f ms | worst %.1f ms -- panel refresh = 2x this, per frame on drag" % [
		proj_total / float(proj_runs * proj_runs), proj_best, proj_worst])
	# The projection gets a band too, not an informational line (the pass-6
	# fleet's find: the machine x48 multiplication stayed unbudgeted -- a
	# 50 ms/month regression would PASS the month bands while adding ~2.4 s
	# per refresh-frame). Declared from measurement: 4.85 s mean / 5.78 s
	# worst at head, the band's ~1.2 s headroom over worst catching a
	# per-month regression that matters without flaking on machine variance.
	# The ~4.5 s BASE predates this PR -- PR-46's finding 6, still open.
	var proj_mean_ms := proj_total / float(proj_runs * proj_runs)
	var proj_ok := proj_mean_ms < 7000.0
	var ok := worst_ms < 300.0 and ind_worst_ms < 300.0 and proj_ok
	_line("verdict: %s (firms month band 300 ms, Companies AND Industry; projection 24-month band 7.0 s, mean %.1f s -- the base is PR-46's still-open finding 6)" % ["PASS" if ok else "FAIL", proj_mean_ms / 1000.0])
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
