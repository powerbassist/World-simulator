extends SceneTree

## Headless test: godot --headless --script res://tests/test_offsets_by_source.gd
## Non-zero exit on any failure.
##
## Call A, PR 2 (sim half): every write to a nation's bloc_offset goes through ONE
## writer, NationState.add_bloc_offset(bloc, delta, source, lo, hi), which books the
## delta it applied (after the caller's clamp) into offset_by_source {source -> {bloc ->
## pts}}. So for a game started on this build, each bloc's offset IS the sum of its
## sources, every month, for every nation; Opinion.causes() then splits its direct row by
## source. Two guards: a real run in the game's own month (WorldMonth.tick_month), which
## catches a site that books the wrong amount, and a read of src/, which catches a site
## that writes bloc_offset without the writer even when the run never reaches it.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Companies = preload("res://src/sim/companies.gd")

const MONTHS := 36
const EPS := 1e-9
## The austerity budget of tools/balance_probe.gd, so the run moves opinion hard; the
## run also nationalises a firm (_austerity_run).
const AUSTERITY := {
	"spending_pct_gdp": {"health": -2.5, "education": -2.0, "defence": -1.0, "pensions": -3.5, "infrastructure": -2.0},
	"tax_rates_pct": {"income": 6.0, "corporate": 5.0, "vat": 4.0},
}
## The files allowed to touch bloc_offset as a whole, and why:
##   nation_state.gd  the writer itself, and the declaration
##   legislature.gd   init_nation() resets the register and its sources together
##   processes.gd     _land() puts back what Companies.execute wrote, sources included
const WHOLE_WRITE_ALLOWED := ["res://src/core/nation_state.gd", "res://src/sim/legislature.gd", "res://src/sim/processes.gd"]

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_the_sources_sum_to_the_offset_every_month()
	_test_no_site_writes_around_the_writer()
	_test_the_writer_books_what_the_clamp_let_through()
	_test_causes_splits_the_direct_row_by_source()
	_test_an_old_save_reads_its_offset_as_earlier()
	_finish()


## A real run: every month, for every nation, each bloc's offset equals the sum its
## sources booked. A site that books the wrong amount, or writes without booking,
## breaks the sum for the nation it wrote.
func _test_the_sources_sum_to_the_offset_every_month() -> void:
	var state = _austerity_run()
	var moved := {}
	for i in range(MONTHS):
		_next_month(state)
		WorldMonth.tick_month(state, _loader)
		for ns in state.nations.values():
			var bad := _mismatch(ns)
			if bad != "":
				_fail("month %d, %s: %s" % [i + 1, ns.id, bad])
				return
			for source in ns.offset_by_source:
				for bloc in ns.offset_by_source[source]:
					if absf(float(ns.offset_by_source[source][bloc])) > 1e-6:
						moved[source] = true
	# Premise: the run reached several writers, not only the scenario's start.
	moved.erase("start")
	if moved.size() < 3 or not moved.has("firms"):
		_fail("premise: only %s booked anything besides the start in %d months" % [moved.keys(), MONTHS])


## A read of src/: outside the writer, nothing assigns a bloc's offset or rewrites the
## register whole. The run above reaches only the sites a run fires; this one reaches
## every site, so a new writer that skips add_bloc_offset fails here first.
func _test_no_site_writes_around_the_writer() -> void:
	var item := RegEx.create_from_string("(?<!act_)bloc_offset\\[[^\\]]*\\]\\s*(=|\\+=|-=)(?!=)")
	var whole := RegEx.create_from_string("(?<!act_)bloc_offset\\s*=(?!=)|(?<!act_)bloc_offset\\.(clear|merge|erase)\\(")
	var files := _gd_files("res://src")
	if files.size() < 100:
		_fail("premise: read only %d files under src/" % files.size())
	for path in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for n in lines.size():
			var line: String = lines[n].strip_edges()
			if line.begins_with("#"):
				continue
			if path != "res://src/core/nation_state.gd" and item.search(line) != null:
				_fail("%s:%d writes a bloc's offset without the writer: %s" % [path, n + 1, line])
			if not WHOLE_WRITE_ALLOWED.has(path) and whole.search(line) != null:
				_fail("%s:%d rewrites bloc_offset whole: %s" % [path, n + 1, line])


## The writer books the APPLIED delta: past the bound, only what the clamp let through.
func _test_the_writer_books_what_the_clamp_let_through() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var start := float(ns.bloc_offset.get("workers", 0.0))
	ns.add_bloc_offset("workers", 5.0, "events", -1.0, 1.0)
	ns.add_bloc_offset("workers", -0.25, "laws", -1.0, 1.0)
	var events := float(ns.offset_by_source.get("events", {}).get("workers", NAN))
	if absf(events - (1.0 - start)) > EPS:
		_fail("past the bound the writer booked %.6f, the clamp let %.6f through" % [events, 1.0 - start])
	if absf(float(ns.bloc_offset["workers"]) - 0.75) > EPS:
		_fail("the offset is %.6f, not 0.75" % float(ns.bloc_offset["workers"]))
	var bad := _mismatch(ns)
	if bad != "":
		_fail("after two writes: %s" % bad)


## causes(): the direct row is one row per source plus `direct:earlier` (what no source
## booked), each size-weighted, and the rows still sum to the target.
func _test_causes_splits_the_direct_row_by_source() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	ns.add_bloc_offset("workers", -0.2, "events", -1.0, 1.0)
	ns.add_bloc_offset("business", 0.1, "laws", -1.0, 1.0)
	var c: Dictionary = Opinion.causes(ns)
	var rows: Dictionary = c["rows"]
	if rows.has("direct"):
		_fail("causes() still carries one `direct` row beside its sources: %s" % [rows.keys()])
	var want_events := float(K.BLOC_SIZE["workers"]) * K.APPROVAL_SPAN * -0.2
	if absf(float(rows.get("direct:events", NAN)) - want_events) > EPS:
		_fail("direct:events is %s, want %.6f" % [rows.get("direct:events", NAN), want_events])
	if not rows.has("direct:laws") or not rows.has("direct:earlier"):
		_fail("no direct:laws or direct:earlier row: %s" % [rows.keys()])
	if absf(float(rows["direct:earlier"])) > EPS:
		_fail("a game started on this build has an earlier row of %s" % rows["direct:earlier"])
	var total := 0.0
	for key in rows:
		total += float(rows[key])
	if absf(total - float(c["target"])) > EPS:
		_fail("split by source the rows sum to %.9f, the target is %.9f" % [total, float(c["target"])])


## A save from before the register: offset_by_source is absent and reads {}, so the
## whole offset is `direct:earlier`, and the rows still sum.
func _test_an_old_save_reads_its_offset_as_earlier() -> void:
	var state = _austerity_run()
	for i in range(4):
		_next_month(state)
		WorldMonth.tick_month(state, _loader)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	for nd in (saved["nations"] as Dictionary).values():
		(nd as Dictionary).erase("offset_by_source")
	var old = GameState.from_dict(saved)
	var ns = old.player()
	if not ns.offset_by_source.is_empty():
		_fail("an old save's register reads %s, not {}" % [ns.offset_by_source])
		return
	var c: Dictionary = Opinion.causes(ns)
	var direct := 0.0
	for bloc in K.BLOC_KEYS:
		direct += float(K.BLOC_SIZE[bloc]) * K.APPROVAL_SPAN * float(ns.bloc_offset.get(bloc, 0.0))
	if absf(float(c["rows"].get("direct:earlier", NAN)) - direct) > 1e-6:
		_fail("an old save's earlier row is %s, the whole offset is %.6f" % [c["rows"].get("direct:earlier", NAN), direct])
	var total := 0.0
	for key in c["rows"]:
		total += float(c["rows"][key])
	if absf(total - float(c["target"])) > EPS:
		_fail("an old save's rows sum to %.9f, the target is %.9f" % [total, float(c["target"])])


## "" when every bloc's offset is the sum of its sources, otherwise what is off.
func _mismatch(ns) -> String:
	var sums := {}
	for source in ns.offset_by_source:
		for bloc in ns.offset_by_source[source]:
			sums[bloc] = float(sums.get(bloc, 0.0)) + float(ns.offset_by_source[source][bloc])
	for bloc in ns.bloc_offset:
		sums[bloc] = float(sums.get(bloc, 0.0))
	for bloc in sums:
		var offset := float(ns.bloc_offset.get(bloc, 0.0))
		if absf(offset - float(sums[bloc])) > EPS:
			return "bloc %s: offset %.12f, its sources sum to %.12f (%s)" % [bloc, offset, float(sums[bloc]), ns.offset_by_source]
	return ""


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(sub)))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out


func _austerity_run():
	var state = GameState.new_game(_loader, "FRA")
	state.year = 2026
	state.month = 1
	var ns = state.player()
	var pending := {}
	for field in AUSTERITY.keys():
		var start: Dictionary = ns.start_tax_rates_pct if field == "tax_rates_pct" else ns.start_spending_pct_gdp
		var values := {}
		for key in AUSTERITY[field]:
			values[key] = clampf(float(start.get(key, 0.0)) + float(AUSTERITY[field][key]), 0.0, 100.0)
		pending[field] = values
	FinanceBill.table(state, _loader, FinanceBill.from_pending(ns, pending))
	# A nationalisation of the biggest firm: a process whose stages write "firms" and
	# whose landing (Processes._land) puts back what Companies.execute wrote, sources too.
	var best := ""
	var share := -1.0
	for company in Companies.majors_of(_loader, ns.id):
		if Companies.share_of_company(ns, company) > share:
			share = Companies.share_of_company(ns, company)
			best = String(company.id)
	Legislature.apply_effects(state, ns, {"company_ownership": {"company_id": best, "action_id": "full_nationalisation"}}, _loader, "laws")
	return state


func _next_month(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_offsets_by_source: OK")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		print("test_offsets_by_source: %d failure(s)" % _failures.size())
		quit(1)
