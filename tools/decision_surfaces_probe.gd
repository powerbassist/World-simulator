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
##
## V5.3-0, `--briefing` (docs/design/v5.3-0-readability.md section 5, bands RF4,
## RF1, RF2, RF9): the monthly briefing's run. Defaults to the four playable
## nations (`--nations=DEU,FRA,GBR,POL`), 120 months, and both regimes
## (`--regime=idle|active|both`):
##   idle    nothing answered, every default taken (the run above);
##   active  at each month's start the player answers every desk entry with its
##           first non-default choice and delegates every waiting request -- a
##           player who acts on everything, with no judgement in it.
## A run stops at a defeat: the game ends there.
##
## The holds are DERIVED here at the default settings, from the same registers
## main.gd reads (it cannot run headless), in the spec's hold order (2.2):
##   election   the month's election results (one panel);
##   briefing   every month the player is still in office;
##   programme  Programme.available() at the boundary (the term-start offer);
##   interrupt  each interrupt-flagged arrival;
##   major      each arrival of severity 2 or more (it holds on arrival);
##   minor      each severity-1 entry in its last month (the lapse guard), once.
## A STOP is a boundary with any hold; its DISMISSALS are its holds. RF4 fails
## when fewer than 90 % of stops take at most 2, or when the holds outside the
## briefing break the 4 + 6 a year budget. Stingers (RF9's count) are the
## month's front page, a division's result and an election night.
##
## RF1, RF2 and RF9's bed sequence read the ranking in src/ui/priorities.gd
## (Interface's, block 0 a), loaded at run time so this probe parses before that
## file exists; until it does those three print NOT MEASURED and do not pass.
## Exit code: 0 when every measured band passes, 1 when one fails.

const DataLoader = preload("res://src/core/data_loader.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const GameState = preload("res://src/core/game_state.gd")
const Events = preload("res://src/sim/events.gd")
const Programme = preload("res://src/sim/programme.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const ElectionVerdict = preload("res://src/ui/election_verdict.gd")

const START_YEAR := 2026
const PLAYABLE := ["DEU", "FRA", "GBR", "POL"]
const PRIORITIES_PATH := "res://src/ui/priorities.gd"
## RF4's bars (spec section 5; decision-surfaces.md's budget).
const RF4_MAX_DISMISSALS := 2
const RF4_SHARE := 0.90
const BUDGET_MODAL_A_YEAR := 4.0
const BUDGET_CARDS_A_YEAR := 6.0

var _loader


func _init() -> void:
	var months := 24
	var nation_id := "FRA"
	var nations: Array = []
	var regime := "both"
	var briefing := false
	var months_set := false
	var json_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--months="):
			months = int(arg.trim_prefix("--months="))
			months_set = true
		elif arg.begins_with("--nation="):
			nation_id = arg.trim_prefix("--nation=")
		elif arg.begins_with("--nations="):
			nations = Array(arg.trim_prefix("--nations=").split(","))
		elif arg.begins_with("--regime="):
			regime = arg.trim_prefix("--regime=")
		elif arg == "--briefing":
			briefing = true
		elif arg.begins_with("--json="):
			json_path = arg.trim_prefix("--json=")

	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [_loader.errors])
		quit(1)
		return

	if briefing:
		if not months_set:
			months = 120
		if nations.is_empty():
			nations = PLAYABLE.duplicate()
		var regimes: Array = ["idle", "active"] if regime == "both" else [regime]
		var out := _briefing(nations, regimes, months)
		if json_path != "":
			_write(json_path, out)
		quit(0 if bool(out["pass"]) else 1)
		return

	var rows := _run(nation_id, months, "idle", false)
	_print(rows)
	if json_path != "":
		_write(json_path, {"nation": nation_id, "months": months, "rows": rows})
	quit(0)


func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()


func _run(nation_id: String, months: int, regime: String, briefing: bool) -> Array:
	var state = GameState.new_game(_loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	var ns = state.player()
	var rows: Array = []
	var year := START_YEAR
	var month := 1
	var minor_held := {}
	for i in range(months):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month
		if regime == "active":
			_act(state, ns)

		# A Dictionary, not locals: the step hook is a lambda, and a lambda
		# captures a local by value.
		var seen := {"desk_before": {}, "history_before": 0}
		var report: Dictionary = WorldMonth.tick_month(state, _loader, func(step: String, after: bool, _step_report: Dictionary) -> void:
			if step == "Events" and not after:
				seen["desk_before"] = _desk_ids(ns)
				seen["history_before"] = ns.event_history.size()
		)
		var row := _row(state, ns, year, month, seen, report)
		if briefing:
			_holds(state, ns, row, report, minor_held)
		rows.append(row)
		if briefing and bool(row["defeated"]):
			break
	return rows


## The active regime's month: every desk entry answered with its first
## non-default choice, every waiting request delegated. Ids are snapshotted
## first: an answer removes its entry from the desk.
func _act(state, ns) -> void:
	var ids: Array[String] = []
	for entry in ns.event_queue:
		ids.append(String(entry.get("event_id", "")))
	for event_id in ids:
		var ev = Events.event_by_id(_loader, event_id)
		if ev == null:
			continue
		for c in ev.choices:
			if not bool(c["is_default"]):
				Events.answer(state, _loader, event_id, String(c["id"]))
				break
	for request in Audiences.pending(ns):
		Audiences.delegate(state, ns, _loader, String(request["id"]))


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
	# An arrival is an id on the desk now that was not on it before the Events
	# step. An event that defaults and re-arrives in the same month is on both
	# sides and is missed: rare under today's cooldowns, and the note says so.
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


## The boundary's holds, in the spec's order (the header lists the rule for
## each), the defeat that ends the run, and the month's stingers.
func _holds(state, ns, row: Dictionary, report: Dictionary, minor_held: Dictionary) -> void:
	var holds: Array = []
	var results: Array = report.get("election_results", [])
	var defeated := false
	if not results.is_empty():
		holds.append("election")
		defeated = bool(ElectionVerdict.read(results, ns)["defeated"])
	if not defeated:
		holds.append("briefing")
	if not Programme.available(state, ns, _loader).is_empty():
		holds.append("programme")
	for arrival in row["arrivals"]:
		if String(arrival["kind"]) in ["interrupt", "major"]:
			holds.append(String(arrival["kind"]))
	for entry in ns.event_queue:
		var event_id := String(entry.get("event_id", ""))
		if bool(entry.get("interrupt", false)) or int(entry.get("severity", 1)) >= 2:
			continue
		if int(entry.get("months_left", 0)) <= 1 and not minor_held.has(event_id):
			minor_held[event_id] = true
			holds.append("minor")
	# An entry gone from the desk may come back later as a new arrival; its
	# lapse guard then fires again.
	for event_id in minor_held.keys():
		if not _desk_ids(ns).has(event_id):
			minor_held.erase(event_id)
	row["holds"] = holds
	row["defeated"] = defeated
	row["stingers"] = {
		"front_page": 0 if (report.get("front_page", {}) as Dictionary).is_empty() else 1,
		"division": 0 if (report.get("division", {}) as Dictionary).is_empty() else 1,
		"election": 1 if not results.is_empty() else 0,
	}


func _briefing(nations: Array, regimes: Array, months: int) -> Dictionary:
	var priorities = load(PRIORITIES_PATH) if ResourceLoader.exists(PRIORITIES_PATH) else null
	var runs: Array = []
	var all_pass := true
	for nation_id in nations:
		for regime in regimes:
			var rows := _run(String(nation_id), months, String(regime), true)
			var rf4 := _rf4(rows)
			var run := {"nation": nation_id, "regime": regime, "months": rows.size(), "rf4": rf4, "rows": rows}
			if priorities == null:
				run["rf1"] = "NOT MEASURED"
			all_pass = all_pass and bool(rf4["pass"])
			runs.append(run)
			_print_run(run)
	if priorities == null:
		print("RF1 / RF2 / RF9: NOT MEASURED -- %s is not in the tree yet" % PRIORITIES_PATH)
	print("BANDS: %s" % ("PASS" if all_pass else "FAIL"))
	return {"pass": all_pass, "priorities": priorities != null, "runs": runs}


## RF4 over one run: the briefing's holds, the others against the budget, the
## stops and the dismissals per stop.
func _rf4(rows: Array) -> Dictionary:
	var counts := {"briefing": 0, "election": 0, "programme": 0, "interrupt": 0, "major": 0, "minor": 0}
	var stops := 0
	var short_stops := 0
	var by_dismissals := {}
	var stingers := {"front_page": 0, "division": 0, "election": 0}
	for row in rows:
		var holds: Array = row["holds"]
		for h in holds:
			counts[h] = int(counts[h]) + 1
		for s in stingers:
			stingers[s] = int(stingers[s]) + int(row["stingers"][s])
		if holds.is_empty():
			continue
		stops += 1
		by_dismissals[holds.size()] = int(by_dismissals.get(holds.size(), 0)) + 1
		if holds.size() <= RF4_MAX_DISMISSALS:
			short_stops += 1
	var years := maxf(rows.size() / 12.0, 1.0 / 12.0)
	var modal := (int(counts["election"]) + int(counts["interrupt"])) / years
	var cards := (int(counts["major"]) + int(counts["minor"])) / years
	var share := float(short_stops) / maxf(float(stops), 1.0)
	return {
		"counts": counts, "stops": stops, "by_dismissals": by_dismissals,
		"share_at_most_2": share, "briefing_a_year": int(counts["briefing"]) / years,
		"modal_a_year": modal, "cards_a_year": cards,
		"programme_a_year": int(counts["programme"]) / years,
		"stingers_a_year": {"front_page": stingers["front_page"] / years,
			"division": stingers["division"] / years, "election": stingers["election"] / years},
		"pass": share >= RF4_SHARE and modal <= BUDGET_MODAL_A_YEAR and cards <= BUDGET_CARDS_A_YEAR,
	}


func _print_run(run: Dictionary) -> void:
	var rf4: Dictionary = run["rf4"]
	print("%s %-6s %3d months  RF4 %s: briefing %.1f/yr, modal %.1f/yr, cards %.1f/yr, programme %.1f/yr; %d stops, %.0f %% take <= %d (by dismissals %s); stingers/yr %s" % [
		run["nation"], run["regime"], int(run["months"]), "PASS" if bool(rf4["pass"]) else "FAIL",
		rf4["briefing_a_year"], rf4["modal_a_year"], rf4["cards_a_year"], rf4["programme_a_year"],
		int(rf4["stops"]), 100.0 * float(rf4["share_at_most_2"]), RF4_MAX_DISMISSALS,
		JSON.stringify(rf4["by_dismissals"]), JSON.stringify(rf4["stingers_a_year"]),
	])


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
