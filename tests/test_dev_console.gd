extends SceneTree

## Headless test: godot --headless --script res://tests/test_dev_console.gd
## Non-zero exit on any failure.
##
## V5.1-0b. The dev console without a scene tree: the parser, the command table and
## each command family (src/ui/dev_registry.gd) against a stub host that stands in
## for the game, the Logger capture (src/ui/dev_log.gd), the perf overlay's numbers
## (src/ui/dev_perf.gd) and the release gate. What must hold, each a silent failure
## if it does not:
##
##   - `help` lists the table the commands run from, so a command cannot exist
##     without a help line or the reverse;
##   - a command that changes the game refuses while a month is closing, and one
##     that only reads does not -- the busy flag is the table's, not each handler's;
##   - `set` reaches the state through src/sim/dev_commands.gd and the console's own
##     files contain no write of their own (AGENTS.md rule 2, pinned by source);
##   - `skip n` asks the host for n months and `term_start` stops where the term
##     does, on a lost election, or at its cap -- and says which;
##   - a pushed error and a pushed warning reach the log, from the main thread and
##     from a worker, with the script and line that raised them;
##   - the console is absent in a release configuration unless asked for.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const DevRegistry = preload("res://src/ui/dev_registry.gd")
const DevLog = preload("res://src/ui/dev_log.gd")
const DevPerf = preload("res://src/ui/dev_perf.gd")
const DevConsole = preload("res://src/ui/dev_console.gd")

const COMMANDS := ["help", "get", "set", "person", "skip", "speed", "pause", "term_start",
	"event", "save", "load", "open", "errors", "perf", "clear", "hint"]
const CONSOLE_FILES := ["res://src/ui/dev_registry.gd", "res://src/ui/dev_console.gd",
	"res://src/ui/dev_log.gd", "res://src/ui/dev_perf.gd"]

var _failures: Array[String] = []
var _loader
var _state


## The game, as the registry sees it: a bare GameState and a record of what it was asked.
class StubHost extends DevRegistry.Host:
	var game_state
	var game_loader
	var is_busy := false
	var calls: Array[String] = []
	var months := 0
	## What a month does to the player's term, so term_start can be driven: a month
	## counts the term up and wraps it at term_months (a won election), or loses it.
	var lose_at := -1
	var save_error := ""
	var _log = DevLog.new()

	func _init(s, l) -> void:
		game_state = s
		game_loader = l

	func state():
		return game_state

	func loader():
		return game_loader

	func busy() -> bool:
		return is_busy

	func refresh() -> void:
		calls.append("refresh")

	func advance_month() -> void:
		months += 1
		var ns = game_state.player()
		ns.months_in_term += 1
		if months == lose_at:
			ns.in_government = false
		if ns.months_in_term >= ns.term_months:
			ns.months_in_term = 0

	func date_text() -> String:
		return "month+%d" % months

	func set_speed(n: int) -> String:
		calls.append("speed %d" % n)
		return "speed %d" % n

	func set_paused(mode: String) -> String:
		calls.append("pause %s" % mode)
		return "paused %s" % mode

	func open_panel(id: String) -> String:
		calls.append("open %s" % id)
		return "" if id == "budget" else "no panel '%s'" % id

	func save_game(slot: String) -> String:
		calls.append("save %s" % slot)
		return save_error

	func load_game(slot: String) -> String:
		calls.append("load %s" % slot)
		return save_error

	func event_staged(desk_before: Dictionary) -> void:
		calls.append("staged %s" % [desk_before.keys()])

	func term_started() -> void:
		calls.append("term_started")

	func perf(mode: String) -> String:
		calls.append("perf %s" % mode)
		return "perf %s" % mode

	func clear_output() -> void:
		calls.append("clear")

	func dev_log() -> DevLog:
		return _log


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_state = GameState.new_game(_loader, "FRA")

	_test_parse()
	_test_help_lists_the_table()
	_test_unknown_and_empty()
	_test_busy_refuses_only_mutating_commands()
	_test_get_set_person()
	_test_skip_and_term_start()
	_test_skip_stops_on_a_lost_election()
	_test_event_save_load_open()
	_test_errors_and_perf_commands()
	_test_the_console_writes_nothing_itself()
	_test_logger_capture()
	_test_logger_from_a_worker()
	_test_perf_numbers()
	_test_release_gate()
	_finish()


func _stub() -> StubHost:
	return StubHost.new(_state, _loader)


func _run(host: StubHost, text: String) -> String:
	return DevRegistry.new(host).run(text)


func _test_parse() -> void:
	var cases := {
		"": [],
		"   ": [],
		"help": ["help"],
		"  set   FRA.gdp   12.5 ": ["set", "FRA.gdp", "12.5"],
		"set FRA.x \"two words\"": ["set", "FRA.x", "two words"],
		"open \"\"": ["open", ""],
	}
	for text in cases:
		var got: Array = DevRegistry.parse(text)
		if got != cases[text]:
			_fail("parse(%s) = %s, expected %s" % [JSON.stringify(text), got, cases[text]])


func _test_help_lists_the_table() -> void:
	var host := _stub()
	var registry := DevRegistry.new(host)
	var names: Array = registry.command_names()
	if names != COMMANDS:
		_fail("the command table is %s, expected %s" % [names, COMMANDS])
	var listing := registry.run("help")
	for name in COMMANDS:
		if not listing.contains(name):
			_fail("help does not list '%s'" % name)
	for line in listing.split("\n", false):
		if line.length() < 12:
			_fail("a help line says nothing: '%s'" % line)
	var one := registry.run("help get")
	if not one.contains("<nation>.<field>"):
		_fail("help get should show its usage: %s" % one)
	if not registry.run("help nonsense").contains("no command"):
		_fail("help for an unknown command should say so")


func _test_unknown_and_empty() -> void:
	var host := _stub()
	if _run(host, "") != "":
		_fail("an empty line should answer nothing")
	var r := _run(host, "frobnicate now")
	if not r.contains("frobnicate") or not r.contains("help"):
		_fail("an unknown command should name itself and point at help: %s" % r)


func _test_busy_refuses_only_mutating_commands() -> void:
	var host := _stub()
	host.is_busy = true
	var before := JSON.stringify(_state.to_dict(), "", true)
	for text in ["set FRA.gdp_eur_bn 5", "skip 1", "speed 2", "pause", "term_start", "event x",
			"save", "load", "open budget"]:
		var r := _run(host, text)
		if not r.contains("month is closing"):
			_fail("'%s' should wait for the month while one closes: %s" % [text, r])
	if host.months != 0 or not host.calls.is_empty():
		_fail("a refused command still reached the game: months=%d calls=%s" % [host.months, host.calls])
	if JSON.stringify(_state.to_dict(), "", true) != before:
		_fail("a refused command changed the state")
	for text in ["help", "get FRA.gdp_eur_bn", "person nobody", "errors", "clear", "perf"]:
		if _run(host, text).contains("month is closing"):
			_fail("'%s' only reads and should answer during a month" % text)


func _test_get_set_person() -> void:
	var host := _stub()
	var ns = _state.player()
	var r := _run(host, "get me.gdp_eur_bn")
	if not r.contains(str(ns.gdp_eur_bn)):
		_fail("get me.gdp_eur_bn: %s" % r)
	if not _run(host, "get gdp").contains("<nation>.<field>"):
		_fail("get without a nation.field should show usage")
	r = _run(host, "set FRA.assembly_seats 123")
	if ns.assembly_seats != 123 or not host.calls.has("refresh"):
		_fail("set did not reach the state or the screen: %s seats=%d calls=%s" % [r, ns.assembly_seats, host.calls])
	var before := JSON.stringify(_state.to_dict(), "", true)
	host.calls.clear()
	r = _run(host, "set FRA.tax_rates_pct 5")
	if JSON.stringify(_state.to_dict(), "", true) != before or host.calls.has("refresh"):
		_fail("a refused set changed something: %s" % r)
	if not _run(host, "set FRA.population").contains("<nation>.<field> <value>"):
		_fail("set without a value should show usage")
	var multi := _run(host, "set FRA.incumbent_party_id some words here")
	if ns.incumbent_party_id != "some words here":
		_fail("set joins the rest of the line: %s -> '%s'" % [multi, ns.incumbent_party_id])
	var id := String(_loader.person_by_id.keys()[0])
	if not _run(host, "person %s" % id).contains(String(_loader.person_by_id[id].person_name)):
		_fail("person %s printed no name" % id)


func _test_skip_and_term_start() -> void:
	var host := _stub()
	var r := _run(host, "skip 2")
	if host.months != 2 or not r.contains("month+2") or not host.calls.has("refresh"):
		_fail("skip 2 should ask for two months and show the date: months=%d %s" % [host.months, r])
	for bad in ["skip", "skip 0", "skip -3", "skip abc", "skip 1.5", "skip 100000"]:
		var before := host.months
		var refused := _run(host, bad)
		if host.months != before or refused.is_empty():
			_fail("'%s' should be refused without moving time: %s" % [bad, refused])

	var ns = _state.player()
	# At a term start already: nothing to wait for, and it says so.
	host = _stub()
	ns.months_in_term = 0
	r = _run(host, "term_start")
	if host.months != 0 or not r.contains("already"):
		_fail("term_start at a term start should not skip: %s months=%d" % [r, host.months])
	# Mid-term: skips exactly to the wrap, then tells the UI.
	host = _stub()
	ns.months_in_term = ns.term_months - 3
	r = _run(host, "term_start")
	if host.months != 3 or not host.calls.has("term_started") or ns.months_in_term != 0:
		_fail("term_start should skip to the next term start: %s months=%d" % [r, host.months])
	# A lost election ends it, and the reason is given.
	host = _stub()
	host.lose_at = 2
	ns.months_in_term = ns.term_months - 3
	r = _run(host, "term_start")
	ns.in_government = true
	if host.months != 2 or not r.contains("out of government") or host.calls.has("term_started"):
		_fail("a lost election should stop term_start with a reason: %s months=%d" % [r, host.months])
	# Out of government before it starts: refused up front.
	host = _stub()
	ns.in_government = false
	r = _run(host, "term_start")
	ns.in_government = true
	if host.months != 0 or not r.contains("out of government"):
		_fail("term_start with no government should refuse before skipping: %s" % r)


## skip follows term_start's rule: a lost election ends the run, and the answer says
## how many months ran and why it stopped.
func _test_skip_stops_on_a_lost_election() -> void:
	var host := _stub()
	host.lose_at = 2
	var ns = _state.player()
	var r := _run(host, "skip 5")
	ns.in_government = true
	if host.months != 2 or not r.contains("out of government") or not r.contains("2 of 5"):
		_fail("skip 5 should stop at the lost election after 2 months and say so: %s months=%d" % [r, host.months])
	if not host.calls.has("refresh"):
		_fail("skip stopped early without telling the screen")


func _test_event_save_load_open() -> void:
	var host := _stub()
	var ns = _state.player()
	ns.event_queue.clear()
	var id := String(_loader.events[0].id)
	var r := _run(host, "event %s" % id)
	if not (r.contains(id) and ns.event_queue.size() == 1) or not str(host.calls).contains("staged"):
		_fail("event %s did not stage and announce: %s calls=%s" % [id, r, host.calls])
	r = _run(host, "event %s" % id)
	if ns.event_queue.size() != 1 or not r.contains("already"):
		_fail("staging the same event twice should be refused: %s" % r)
	ns.event_queue.clear()

	host = _stub()
	_run(host, "save")
	_run(host, "save mine")
	_run(host, "load")
	_run(host, "load mine")
	if host.calls != ["save quick", "save mine", "load quick", "load mine"]:
		_fail("save/load slots: %s" % [host.calls])
	host.save_error = "disk full"
	if not _run(host, "save").contains("disk full"):
		_fail("a save error should reach the console")

	host = _stub()
	if _run(host, "open budget").contains("no panel") or not host.calls.has("open budget"):
		_fail("open budget should open it: %s" % [host.calls])
	if not _run(host, "open nonsense").contains("no panel"):
		_fail("open of an unknown panel should say so")
	if not _run(host, "open").contains("<panel_id>"):
		_fail("open without an id should show usage")
	host = _stub()
	_run(host, "speed 3")
	_run(host, "pause off")
	if not host.calls.has("speed 3") or not host.calls.has("pause off"):
		_fail("speed / pause did not reach the host: %s" % [host.calls])
	for bad in ["speed", "speed 0", "speed 4", "speed x"]:
		var refused := _run(host, bad)
		if refused.is_empty() or host.calls.size() != 2:
			_fail("'%s' should be refused: %s calls=%s" % [bad, refused, host.calls])
	if not _run(host, "pause maybe").contains("on|off"):
		_fail("pause maybe should show its usage")


func _test_errors_and_perf_commands() -> void:
	var host := _stub()
	if not _run(host, "errors").contains("no errors"):
		_fail("an empty log should say so")
	host.dev_log().add("error", "first thing broke", "res://src/x.gd", 12, "f")
	host.dev_log().add("warning", "second thing odd", "res://src/y.gd", 7, "g")
	var r := _run(host, "errors")
	if not (r.contains("first thing broke") and r.contains("res://src/x.gd:12") and r.contains("second thing odd")):
		_fail("errors should list the log with script and line: %s" % r)
	var one := _run(host, "errors 1")
	if one.contains("first thing broke") or not one.contains("second thing odd"):
		_fail("errors 1 should list only the latest: %s" % one)
	_run(host, "perf on")
	_run(host, "clear")
	if not host.calls.has("perf on") or not host.calls.has("clear"):
		_fail("perf / clear did not reach the host: %s" % [host.calls])


## Rule 2 by source: the console's files hold no write to the sim -- the only door
## is src/sim/dev_commands.gd, which they preload by name.
func _test_the_console_writes_nothing_itself() -> void:
	for path in CONSOLE_FILES:
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			_fail("%s is missing or empty" % path)
			continue
		for forbidden in [".set(", "NationFields", "event_queue.", "months_in_term =", "in_government ="]:
			if text.contains(forbidden):
				_fail("%s contains '%s' -- a write belongs in src/sim/dev_commands.gd" % [path, forbidden])


func _test_logger_capture() -> void:
	var capture := DevLog.new()
	capture.install()
	## expects-error: test_dev_console: expected error
	push_error("test_dev_console: expected error")
	## expects-error: test_dev_console: expected warning
	push_warning("test_dev_console: expected warning")
	capture.poll()
	capture.uninstall()
	if capture.errors != 1 or capture.warnings != 1:
		_fail("the log counted %d errors, %d warnings; expected 1 and 1" % [capture.errors, capture.warnings])
	var found := false
	for entry in capture.entries:
		if String(entry["text"]).contains("expected error"):
			found = true
			if String(entry["file"]) != "res://tests/test_dev_console.gd" or int(entry["line"]) <= 0:
				_fail("the error should name the script and line that raised it: %s" % [entry])
			if String(entry["kind"]) != "error":
				_fail("a pushed error should be kind 'error': %s" % [entry])
	if not found:
		_fail("a pushed error never reached the log: %s" % [capture.entries])
	# Uninstalled, it hears nothing more.
	## expects-error: test_dev_console: unheard
	push_error("test_dev_console: unheard")
	capture.poll()
	if capture.errors != 1:
		_fail("an uninstalled log still counted an error")
	# The save path's by-design warning (a decision's figure with no baseline is NaN)
	# is listed, marked expected, and not counted: a clean session must read WARN 0.
	var expected := DevLog.new()
	expected.add("warning", DevLog.EXPECTED_SAMPLE, "res://src/core/save_manager.gd", 89, "save_game")
	if expected.warnings != 0 or expected.errors != 0 or expected.entries.size() != 1:
		_fail("the known NaN warning should be listed but not counted: %d warnings, %d entries" % [expected.warnings, expected.entries.size()])
	elif not DevLog.format_entry(expected.entries[0]).contains("(expected)"):
		_fail("the known NaN warning should be marked (expected) in the list")
	expected.add("warning", "`Infinity` found in argument passed to JSON.stringify()", "res://src/core/save_manager.gd", 89, "save_game")
	expected.add("warning", "some other warning", "res://src/x.gd", 1, "f")
	if expected.warnings != 2:
		_fail("only the NaN line is expected; an Infinity or any other warning still counts: %d" % expected.warnings)
	var capped := DevLog.new()
	for i in DevLog.MAX_ENTRIES + 25:
		capped.add("error", "n%d" % i, "f", i, "fn")
	if capped.entries.size() != DevLog.MAX_ENTRIES or capped.errors != DevLog.MAX_ENTRIES + 25:
		_fail("the log should keep the newest %d and count them all: %d / %d" % [
			DevLog.MAX_ENTRIES, capped.entries.size(), capped.errors])


func _test_logger_from_a_worker() -> void:
	var capture := DevLog.new()
	capture.install()
	var task := WorkerThreadPool.add_task(_push_from_worker)
	WorkerThreadPool.wait_for_task_completion(task)
	capture.poll()
	capture.uninstall()
	var heard := false
	for entry in capture.entries:
		if String(entry["text"]).contains("from a worker"):
			heard = true
	if not heard:
		_fail("an error pushed on a worker thread never reached the log")


func _push_from_worker() -> void:
	## expects-error: test_dev_console: from a worker
	push_error("test_dev_console: from a worker")


func _test_perf_numbers() -> void:
	var perf := DevPerf.new()
	perf.record(16.0, 0.0)
	perf.record(80.0, 1.0)
	perf.record(17.0, 2.0)
	if perf.current() != 17.0 or perf.worst() != 80.0:
		_fail("frame numbers: current %s worst %s" % [perf.current(), perf.worst()])
	perf.record(16.0, 1.0 + DevPerf.WINDOW_SEC + 0.5)
	if perf.worst() != 17.0:
		_fail("a spike older than the window should drop out: worst %s" % perf.worst())
	var text := perf.month_text({"Economy": 90000, "Diplomacy": 60000, "Budget": 1000,
		"Opinion": 2000, "Events": 3000, "Society": 500, "Unrest": 400, "Media": 300})
	if not text.begins_with("month 157 ms") or text.find("Economy") > text.find("Diplomacy"):
		_fail("month cost text should total and sort the heaviest first: %s" % text)
	if text.contains("Unrest") or text.contains("Media"):
		_fail("month cost text should show only the top few: %s" % text)
	if not perf.month_text({}).contains("no real-time month"):
		_fail("an empty cost table should say there is no real-time month: %s" % perf.month_text({}))


func _test_release_gate() -> void:
	if DevConsole.enabled(false, []):
		_fail("a release build with no flag must not have the console")
	if not DevConsole.enabled(true, []):
		_fail("a debug build has the console")
	if not DevConsole.enabled(false, ["--dev-console"]):
		_fail("the explicit flag turns the console on in a release build")
	var host := Control.new()
	var made = DevConsole.install(host, false, [])
	if made != null or host.get_child_count() != 0:
		_fail("install in a release build must add nothing")
	host.free()


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_dev_console: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		printerr("test_dev_console: %d check(s) failed" % _failures.size())
		quit(1)
