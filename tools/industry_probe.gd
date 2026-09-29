extends SceneTree

## V4.7b B1: the autonomy machine's band probe. The bands were declared in
## industry_constants.gd BEFORE this ran; a number landing outside one is a
## finding, not a reason to widen the band. Idle world, the real register,
## 168 months (the balance harness's own horizon). Verdict to
## reports/industry_probe.txt via FileAccess -- stdout interleaves badly
## through pipes.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
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
	var majors_total := 0
	for nation_id in loader.companies.keys():
		majors_total += Companies.majors_of(loader, String(nation_id)).size()
	_line("register: %d majors across %d nations; 168 idle months" % [
		majors_total, loader.companies.size()])

	var failures_opened := 0
	var failures_committed := 0
	var rescues_pending := 0
	var bids_opened := 0
	var relocations := 0
	var was_failed := {}
	var moved := {}
	for _m in 168:
		state.month = int(state.month) + 1
		Economy.tick_month(state)
		Companies.tick_month(state, loader)
		for nation_id in state.nations.keys():
			var ns = state.nations[nation_id]
			for company in Companies.majors_of(loader, String(nation_id)):
				var failed_now: bool = bool(ns.companies.get(company.id, {}).get("failed", false))
				if failed_now and not was_failed.has(company.id):
					failures_opened += 1
					was_failed[company.id] = true
		Industry.tick_month(state, loader)
		for nation_id in state.nations.keys():
			var ns = state.nations[nation_id]
			for company in Companies.majors_of(loader, String(nation_id)):
				var entry: Dictionary = ns.companies.get(company.id, {})
				if bool(entry.get("failed", false)):
					if int(entry.get("rescue_months_left", 0)) == 0 and not bool(entry.get("failed_committed", false)):
						pass
				var city: String = String(entry.get("city", ""))
				if city != "" and city != String(company.city) and not moved.has(company.id):
					relocations += 1
					moved[company.id] = true

	# After the run: committed failures (failed with window exhausted) and
	# still-pending windows.
	for nation_id in state.nations.keys():
		var ns = state.nations[nation_id]
		for company in Companies.majors_of(loader, String(nation_id)):
			var entry: Dictionary = ns.companies.get(company.id, {})
			if bool(entry.get("failed", false)):
				if int(entry.get("rescue_months_left", 0)) > 0:
					rescues_pending += 1
				else:
					failures_committed += 1
			if String(entry.get("bid_bidder", "")) != "":
				bids_opened += 1

	_line("failures opened: %d (declared band: 0.15-0.7 per nation per 14yr)" % failures_opened)
	_line("failures committed: %d; windows still open at horizon: %d" % [failures_committed, rescues_pending])
	_line("bids still open at horizon: %d (band: <= a handful)" % bids_opened)
	_line("relocations: %d (declared band: a handful per run worldwide, ~4-12)" % relocations)
	var fail_per_nation := float(failures_opened) / float(loader.companies.size())
	var ok := fail_per_nation >= 0.15 and fail_per_nation <= 0.7
	var reloc_ok := relocations >= 2 and relocations <= 14
	_line("failures per nation over 14yr: %.2f -- band 0.15-0.7: %s" % [
		fail_per_nation, "PASS" if ok else "FAIL"])
	_line("relocations in band: %s" % ["PASS" if reloc_ok else "FAIL"])
	_finish(0 if (ok and reloc_ok) else 1)


func _line(s: String) -> void:
	_lines.append(s)
	print(s)


func _finish(code: int) -> void:
	var f := FileAccess.open("res://reports/industry_probe.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	quit(code)
