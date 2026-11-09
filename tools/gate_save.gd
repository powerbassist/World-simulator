extends SceneTree

## A prepared save for a staged play gate: a nation played N months through the game's
## own month (WorldMonth.tick_month) under the balance probe's "managed" budget, with
## every card on the desk answered the way the probe's "soft" rule answers it, then
## written as an ordinary save slot.
##
##   godot --headless --script res://tools/gate_save.gd -- --make --months=33 --nation=FRA --out=PATH
##   godot --headless --script res://tools/gate_save.gd -- --verify --in=PATH --more=6
##   godot --headless --script res://tools/gate_save.gd -- --verify-main --in=PATH
##
## Always run under an isolated user dir (`APPDATA="$(mktemp -d)"`): the slot is written
## to user://saves/ first (SaveManager is the one writer, so the file is exactly what the
## game writes) and then copied to --out, and --verify copies --in into a throwaway
## user://saves/ before loading it. Nothing here reads or writes a player's own saves.
##
## --verify is the proof the file loads: SaveManager.load_game accepts it at the current
## save version, and --more further months tick through WorldMonth without an error,
## printing the sector warnings that arrive (V5.3 a: the first fire is the point of the
## staged part of the gate). --verify-main boots the real main scene and loads the slot
## through main.gd's own _on_load_requested -- the function the Load menu calls.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const Clock = preload("res://src/core/clock.gd")
const Budget = preload("res://src/sim/budget.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Events = preload("res://src/sim/events.gd")
const SectorWarnings = preload("res://src/sim/sector_warnings.gd")
const K = preload("res://src/sim/opinion_constants.gd")

const START_YEAR := 2026
const SLOT := "gate_staged"
## balance_probe.gd's REGIMES["managed"]: cut defence, fund it with VAT, the budget a
## player who reads the polling panel converges on.
const MANAGED := {
	"spending_pct_gdp": {"defence": -1.4},
	"tax_rates_pct": {"vat": 3.0},
}


var _main
var _frames := 0


func _arg(name: String, fallback: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return fallback


func _flag(name: String) -> bool:
	return OS.get_cmdline_user_args().has("--%s" % name)


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return
	if _flag("make"):
		quit(_make(loader))
	elif _flag("verify"):
		quit(_verify(loader))
	elif _flag("verify-main"):
		_start_main()
	else:
		printerr("usage: -- --make --months=N --nation=ID --out=PATH | --verify --in=PATH --more=N")
		quit(2)


func _make(loader) -> int:
	var months := int(_arg("months", "33"))
	var nation := _arg("nation", "FRA")
	var out_path := _arg("out")
	if out_path == "":
		printerr("--out=PATH is required")
		return 2
	var state = GameState.new_game(loader, nation)
	state.year = START_YEAR
	state.month = 1
	var ns = state.player()
	var pending := {}
	var rates := {}
	for key in MANAGED["tax_rates_pct"]:
		rates[key] = clampf(float(ns.start_tax_rates_pct.get(key, 0.0)) + float(MANAGED["tax_rates_pct"][key]), 0.0, 100.0)
	pending["tax_rates_pct"] = rates
	var spending := {}
	for key in MANAGED["spending_pct_gdp"]:
		spending[key] = clampf(float(ns.start_spending_pct_gdp.get(key, 0.0)) + float(MANAGED["spending_pct_gdp"][key]), 0.0, 100.0)
	pending["spending_pct_gdp"] = spending
	Budget.commit(state, pending)

	var year := START_YEAR
	var month := 1
	for i in range(months):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month
		WorldMonth.tick_month(state, loader, func(step: String, after: bool, _report: Dictionary) -> void:
			if after and step == "Events":
				_answer_desk(state, loader, ns))
	# The desk is left as the game would leave it at a month boundary: whatever arrived
	# this month stays pending, so the first thing the player sees is real.
	var clock := Clock.new()
	clock.year = year
	clock.month = month
	clock.day = 1
	var error := SaveManager.save_game(state, clock, SLOT)
	if error != "":
		printerr("save failed: %s" % error)
		return 1
	var written := ProjectSettings.globalize_path(SaveManager.SAVE_DIR + SLOT + ".json")
	var text := FileAccess.get_file_as_string(written)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write %s (%s)" % [out_path, error_string(FileAccess.get_open_error())])
		return 1
	f.store_string(text)
	f.close()
	print("GATE_SAVE nation=%s date=%d-%02d months=%d save_version=%d bytes=%d out=%s" % [
		nation, year, month, months, GameState.SAVE_VERSION, text.length(), out_path])
	return 0


## balance_probe.gd's "soft" rule: of the non-default choices, the one that buys the most
## approval on the day; every entry on the desk is answered, by id.
func _answer_desk(state, loader, ns) -> void:
	var ids: Array[String] = []
	for entry in ns.event_queue:
		var entry_id := String(entry.get("event_id", ""))
		if entry_id != "" and not ids.has(entry_id):
			ids.append(entry_id)
	for event_id in ids:
		var ev = Events.event_by_id(loader, event_id)
		if ev == null:
			continue
		var pick: Dictionary = {}
		var pick_score := 0.0
		for c in ev.choices:
			if bool(c["is_default"]):
				continue
			var score := 0.0
			var terms: Dictionary = (c["effects"] as Dictionary).get("bloc_offset", {})
			for bloc in terms:
				score += float(K.BLOC_SIZE.get(bloc, 0.0)) * float(terms[bloc])
			if pick.is_empty() or score > pick_score:
				pick = c
				pick_score = score
		if not pick.is_empty():
			Events.answer(state, loader, event_id, String(pick["id"]))


func _start_main() -> void:
	var in_path := _arg("in")
	if not FileAccess.file_exists(in_path):
		printerr("no such file: %s" % in_path)
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(SaveManager.SAVE_DIR)
	var copy := FileAccess.open(SaveManager.SAVE_DIR + "gate_verify.json", FileAccess.WRITE)
	copy.store_string(FileAccess.get_file_as_string(in_path))
	copy.close()
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _main == null:
		return false
	_frames += 1
	if _frames == 3:
		_main._on_load_requested("gate_verify")
	elif _frames == 8:
		var st = _main._state
		var ok: bool = st != null and String(st.player_nation_id) == "FRA" and st.save_version == GameState.SAVE_VERSION
		print("GATE_VERIFY_MAIN state after Load: player=%s date=%d-%02d save_version=%d -> %s" % [
			st.player_nation_id, st.year, st.month, st.save_version, "OK" if ok else "WRONG"])
		quit(0 if ok else 1)
	return false


func _verify(loader) -> int:
	var in_path := _arg("in")
	var more := int(_arg("more", "6"))
	if not FileAccess.file_exists(in_path):
		printerr("no such file: %s" % in_path)
		return 2
	DirAccess.make_dir_recursive_absolute(SaveManager.SAVE_DIR)
	var copy := FileAccess.open(SaveManager.SAVE_DIR + "gate_verify.json", FileAccess.WRITE)
	copy.store_string(FileAccess.get_file_as_string(in_path))
	copy.close()
	var result := SaveManager.load_game("gate_verify", loader)
	if not bool(result["ok"]):
		printerr("LOAD FAILED: %s" % result["error"])
		return 1
	var state = result["state"]
	var ns = state.player()
	print("GATE_VERIFY loaded ok: player=%s date=%d-%02d save_version=%d day=%d" % [
		ns.id, state.year, state.month, state.save_version, int(result["day"])])
	for i in range(more):
		var month: int = state.month + 1
		var year: int = state.year
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month
		var now := year * 12 + month
		WorldMonth.tick_month(state, loader, func(step: String, after: bool, _report: Dictionary) -> void:
			if after and step == "Events":
				_answer_desk(state, loader, ns))
		var arrived: Array = SectorWarnings.arrivals(ns, loader, now)
		print("GATE_VERIFY +%d %d-%02d ok | sector warnings arriving: %d" % [i + 1, year, month, arrived.size()])
	return 0
