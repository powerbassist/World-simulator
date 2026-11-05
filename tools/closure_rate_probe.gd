extends SceneTree

## The plant-closure rate (src/sim/closures.gd): a decade of the real machine for each
## playable nation, nobody answering, counted by announcement. The parent's ruling on
## the majors PR: adding real majors must not change the calibrated rate (FRA ~14 a
## decade, accepted by the author at #251; DEU 11, GBR 14, POL 15). Run isolated:
##   APPDATA="$(mktemp -d)" godot --headless --path . --script res://tools/closure_rate_probe.gd

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Companies = preload("res://src/sim/companies.gd")


func _init() -> void:
	var loader = DataLoader.new()
	loader.load_all()
	# --fall=X tries another threshold without editing the data.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fall="):
			loader.closure_rule["fall"] = float(arg.trim_prefix("--fall="))
	for id in ["FRA", "DEU", "GBR", "POL"]:
		var state = GameState.new_game(loader, id)
		var ns = state.player()
		var seen := {}
		var jobs: Array = []
		var by_sector := {}
		for m in 120:
			state.month += 1
			if state.month > 12:
				state.month = 1
				state.year += 1
			WorldMonth.tick_month(state, loader)
			for company in Companies.majors_of(loader, id):
				var row: Dictionary = (ns.companies.get(company.id, {}) as Dictionary).get("closure", {})
				if not row.is_empty() and not seen.has(String(row["id"])):
					seen[String(row["id"])] = true
					jobs.append(float(row["jobs"]))
					by_sector[company.sector] = int(by_sector.get(company.sector, 0)) + 1
		var total: float = jobs.reduce(func(sum: float, j: float) -> float: return sum + j, 0.0)
		jobs.sort()
		print("closure_rate %s: %d a decade, %d majors, mean plant %.0f jobs, median %.0f, workers bloc %.3f, %s" % [
			id, seen.size(), Companies.majors_of(loader, id).size(), total / maxf(float(seen.size()), 1.0),
			float(jobs[jobs.size() / 2]) if not jobs.is_empty() else 0.0, float(ns.bloc_offset.get("workers", 0.0)), by_sector])
	quit(0)
