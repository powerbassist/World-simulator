extends SceneTree

## The decision-surface count -- what reaches the player, month by month, in a
## France run nobody plays. docs/design/decision-surfaces.md reads this table; it
## is kept because V5.2 adds requests and calls to the same inbox, and the
## interruption budget that note declares has to be re-measured then.
##
## Run isolated (AGENTS.md, "One Godot at a time"):
##   APPDATA="$(mktemp -d)" godot --headless --path . --script res://tools/decision_surfaces_probe.gd -- [--months=24] [--nation=FRA] [--json=PATH]
##
## The month is WorldMonth.tick_month()'s, with this probe's reads in the step
## hook, never a copy of the order (tests/test_world_month.gd fails a copy). No
## event is answered: every decision runs to its default, which is what a player
## who never opens the inbox gets.
##
## What it cannot see is the UI's half: which arrival pauses, which only cards,
## and the lapse guard are main.gd's reads of message_settings.gd. The probe
## records the inputs those reads take (severity, the interrupt flag, the answer
## window), and the note derives the surfaces from them at the default settings.

const DataLoader = preload("res://src/core/data_loader.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const GameState = preload("res://src/core/game_state.gd")

const START_YEAR := 2026

var _loader


func _init() -> void:
	var months := 24
	var nation_id := "FRA"
	var json_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--months="):
			months = int(arg.trim_prefix("--months="))
		elif arg.begins_with("--nation="):
			nation_id = arg.trim_prefix("--nation=")
		elif arg.begins_with("--json="):
			json_path = arg.trim_prefix("--json=")

	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [_loader.errors])
		quit(1)
		return

	var rows := _run(nation_id, months)
	_print(rows)
	if json_path != "":
		var file := FileAccess.open(json_path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"nation": nation_id, "months": months, "rows": rows}, "  "))
		file.close()
	quit(0)


func _run(nation_id: String, months: int) -> Array:
	var state = GameState.new_game(_loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	var ns = state.player()
	var rows: Array = []
	var year := START_YEAR
	var month := 1
	for i in range(months):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month

		# A Dictionary, not locals: the step hook is a lambda, and a lambda
		# captures a local by value.
		var seen := {"desk_before": {}, "history_before": 0}
		var report: Dictionary = WorldMonth.tick_month(state, _loader, func(step: String, after: bool, _step_report: Dictionary) -> void:
			if step == "Events" and not after:
				seen["desk_before"] = _desk_ids(ns)
				seen["history_before"] = ns.event_history.size()
		)
		rows.append(_row(state, ns, year, month, seen, report))
	return rows


func _desk_ids(ns) -> Dictionary:
	var out := {}
	for entry in ns.event_queue:
		out[String(entry.get("event_id", ""))] = true
	return out


func _row(state, ns, year: int, month: int, seen: Dictionary, report: Dictionary) -> Dictionary:
	var row := {
		"year": year, "month": month,
		"interrupt": 0, "major": 0, "minor": 0, "arrivals": [],
		"defaulted": 0, "answered": 0,
		"visits_to_player": 0, "acts_to_player": 0, "acts_between_others": 0,
		"elections": (report.get("election_results", []) as Array).size(),
		"desk_size": ns.event_queue.size(),
	}
	var before: Dictionary = seen["desk_before"]
	for entry in ns.event_queue:
		var event_id := String(entry.get("event_id", ""))
		if before.has(event_id):
			continue
		var kind := "minor"
		if bool(entry.get("interrupt", false)):
			kind = "interrupt"
		elif int(entry.get("severity", 1)) >= 2:
			kind = "major"
		row[kind] = int(row[kind]) + 1
		(row["arrivals"] as Array).append({
			"event_id": event_id, "kind": kind,
			"severity": int(entry.get("severity", 1)),
			"window": int(entry.get("months_left", 0)),
		})
	# Records written this month: the resolutions. An event the probe never
	# answers resolves only by its default, so "answered" stays 0 here, and a
	# non-zero count would mean something else answered it.
	var history: Array = ns.event_history
	for record in history:
		if int(record.get("year", 0)) != year or int(record.get("month", 0)) != month:
			continue
		if bool(record.get("defaulted", false)):
			row["defaulted"] = int(row["defaulted"]) + 1
		else:
			row["answered"] = int(row["answered"]) + 1
	for act in state.foreign_acts:
		if int(act["year"]) != year or int(act["month"]) != month:
			continue
		if String(act["target_id"]) == state.player_nation_id:
			row["acts_to_player"] = int(row["acts_to_player"]) + 1
			if String(act["action_id"]) == "state_visit":
				row["visits_to_player"] = int(row["visits_to_player"]) + 1
		elif String(act["actor_id"]) != state.player_nation_id:
			row["acts_between_others"] = int(row["acts_between_others"]) + 1
	return row


func _print(rows: Array) -> void:
	print("year-mo  int maj min  dflt ans  visits acts_to_me others  elect desk")
	var totals := {}
	for row in rows:
		print("%04d-%02d  %3d %3d %3d  %4d %3d  %6d %10d %6d  %5d %4d" % [
			row["year"], row["month"], row["interrupt"], row["major"], row["minor"],
			row["defaulted"], row["answered"], row["visits_to_player"],
			row["acts_to_player"], row["acts_between_others"], row["elections"], row["desk_size"],
		])
		for key in ["interrupt", "major", "minor", "defaulted", "answered", "visits_to_player", "acts_to_player", "acts_between_others", "elections"]:
			totals[key] = int(totals.get(key, 0)) + int(row[key])
	print("totals: %s" % JSON.stringify(totals))
