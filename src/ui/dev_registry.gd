extends RefCounted

## THE DEV CONSOLE'S COMMANDS (V5.1-0b): one table -- name, arguments, help,
## whether it changes the game, handler -- that `help` prints and `run()` dispatches
## from, so a command cannot exist without a help line or the reverse
## (tests/test_dev_console.gd pins the list).
##
## THE CONSOLE NEVER WRITES THE GAME (AGENTS.md rule 2). Every change of sim state
## goes through src/sim/dev_commands.gd, which validates the field against
## src/core/nation_fields.gd; this file reads, parses, and asks a Host to do the
## UI's half (move the clock, open a window, save). A test greps these files for a
## direct write.
##
## A command that changes the game refuses while a month is closing (Host.busy()):
## the month runs across frames with the clock held (src/ui/month_runner.gd), and a
## write between two of its units is exactly the half-month that class of bug
## comes from. A command that only reads answers at once.
##
## `run(text) -> String` is the one entry the console and an agent share: through the
## MCP bridge, `execute_code` on the runtime channel (node_call_method is editor-only
## and cannot reach a running game -- docs/tooling.md).

const GlossaryHint = preload("res://src/ui/glossary_hint.gd")
const DevCommands = preload("res://src/sim/dev_commands.gd")
const DevLog = preload("res://src/ui/dev_log.gd")

const BUSY_MESSAGE := "a month is closing -- try again in a moment"
const DEFAULT_SLOT := "quick"
const SKIP_MAX := 120
const ERRORS_DEFAULT := 10


## What the registry needs from the game. The console's MainHost implements it over
## the running game; a test implements it over a bare GameState.
class Host extends RefCounted:
	func state():
		return null

	func loader():
		return null

	## Whether a month is closing across frames.
	func busy() -> bool:
		return false

	## Tell the screen the game moved (top bar, windows).
	func refresh() -> void:
		pass

	## One month, the way the game runs it (not a copy of it).
	func advance_month() -> void:
		pass

	func date_text() -> String:
		return ""

	## These return the line to print.
	func set_speed(_n: int) -> String:
		return ""

	func set_paused(_mode: String) -> String:
		return ""

	## "" on success, else why not.
	func open_panel(_id: String) -> String:
		return ""

	func save_game(_slot: String) -> String:
		return ""

	func load_game(_slot: String) -> String:
		return ""

	## A staged event is on the desk: let the UI notice it as it notices an arrival.
	func event_staged(_desk_before: Dictionary) -> void:
		pass

	func term_started() -> void:
		pass

	func perf(_mode: String) -> String:
		return ""

	func clear_output() -> void:
		pass

	func dev_log() -> DevLog:
		return null


var _host: Host
var _table: Array[Dictionary] = []


func _init(host: Host) -> void:
	_host = host
	_add("help", "[command]", "list the commands, or show one", false, _cmd_help)
	_add("get", "<nation>.<field>", "read a nation's field; 'me' is your nation", false, _cmd_get)
	_add("set", "<nation>.<field> <value>", "cheat: set a number, flag or text field", true, _cmd_set)
	_add("person", "<person_id>", "read a person: party, traits, loyalty, standing", false, _cmd_person)
	_add("skip", "<months>", "run n real months at once (1-%d)" % SKIP_MAX, true, _cmd_skip)
	_add("speed", "<1-3>", "set the clock speed", true, _cmd_speed)
	_add("pause", "[on|off]", "pause or resume the clock; no argument toggles", true, _cmd_pause)
	_add("term_start", "", "skip months until the next term starts, or say why it cannot", true, _cmd_term_start)
	_add("event", "<event_id>", "put an event on your desk", true, _cmd_event)
	_add("save", "[slot]", "save the game (slot '%s' by default)" % DEFAULT_SLOT, true, _cmd_save)
	_add("load", "[slot]", "load a saved game (slot '%s' by default)" % DEFAULT_SLOT, true, _cmd_load)
	_add("open", "<panel_id>", "open a window by its id", true, _cmd_open)
	_add("errors", "[n]", "the latest errors and warnings, with script and line", false, _cmd_errors)
	_add("perf", "[on|off]", "show or hide the frame-time and month-cost overlay", false, _cmd_perf)
	_add("clear", "", "clear the console's output", false, _cmd_clear)
	_add("hint", "reset", "re-arm the one-time glossary note (a run on a real profile spends it)", false, _cmd_hint)


func command_names() -> Array:
	var out: Array = []
	for row in _table:
		out.append(row["name"])
	return out


## Whitespace-separated words; "double quotes" keep one word together.
static func parse(text: String) -> Array:
	var words: Array = []
	var word := ""
	var started := false
	var quoted := false
	for ch in text:
		if ch == "\"":
			quoted = not quoted
			started = true
		elif ch == " " and not quoted or ch == "\t" and not quoted:
			if started:
				words.append(word)
			word = ""
			started = false
		else:
			word += ch
			started = true
	if started:
		words.append(word)
	return words


func run(text: String) -> String:
	var words := parse(text)
	if words.is_empty():
		return ""
	var name := String(words.pop_front()).to_lower()
	var row := _row(name)
	if row.is_empty():
		return "unknown command '%s' -- type help" % name
	if bool(row["mutating"]) and _host.busy():
		return BUSY_MESSAGE
	return (row["handler"] as Callable).call(words)


func _add(name: String, usage: String, help: String, mutating: bool, handler: Callable) -> void:
	_table.append({"name": name, "usage": usage, "help": help, "mutating": mutating, "handler": handler})


func _row(name: String) -> Dictionary:
	for row in _table:
		if row["name"] == name:
			return row
	return {}


func _usage(name: String) -> String:
	return "usage: %s %s" % [name, _row(name)["usage"]]


func _cmd_help(args: Array) -> String:
	if not args.is_empty():
		var row := _row(String(args[0]).to_lower())
		if row.is_empty():
			return "no command '%s'" % args[0]
		return "%s %s\n  %s" % [row["name"], row["usage"], row["help"]]
	var lines: Array[String] = []
	for row in _table:
		lines.append("%s %s  --  %s" % [row["name"], row["usage"], row["help"]])
	return "\n".join(lines)


## "FRA.gdp_eur_bn" -> ["FRA", "gdp_eur_bn"], or [] when it is not that shape.
func _split_ref(ref: String) -> Array:
	var at := ref.find(".")
	if at <= 0 or at == ref.length() - 1:
		return []
	return [ref.substr(0, at), ref.substr(at + 1)]


func _cmd_get(args: Array) -> String:
	var ref := _split_ref(String(args[0])) if args.size() == 1 else []
	if ref.is_empty():
		return _usage("get")
	return DevCommands.get_field(_host.state(), ref[0], ref[1])["text"]


func _cmd_set(args: Array) -> String:
	var ref := _split_ref(String(args[0])) if args.size() >= 2 else []
	if ref.is_empty():
		return _usage("set")
	var result := DevCommands.set_field(_host.state(), ref[0], ref[1], " ".join(args.slice(1)))
	if bool(result["ok"]):
		_host.refresh()
	return result["text"]


func _cmd_person(args: Array) -> String:
	if args.size() != 1:
		return _usage("person")
	return DevCommands.person_report(_host.state(), _host.loader(), String(args[0]))["text"]


func _cmd_skip(args: Array) -> String:
	if args.size() != 1 or not String(args[0]).is_valid_int():
		return _usage("skip")
	var months := String(args[0]).to_int()
	if months < 1 or months > SKIP_MAX:
		return "skip takes 1 to %d months" % SKIP_MAX
	var ns = _host.state().player()
	for i in months:
		_host.advance_month()
		# term_start's stop rule: once the election is lost there is no government
		# left to run the months of, and the run says so rather than playing on.
		if ns != null and not ns.in_government:
			_host.refresh()
			return "stopped after %d of %d months: the player is out of government (the election was lost) -- now %s" % [
				i + 1, months, _host.date_text()]
	_host.refresh()
	return "skipped %d month%s -- now %s" % [months, "" if months == 1 else "s", _host.date_text()]


func _cmd_speed(args: Array) -> String:
	if args.size() != 1 or not String(args[0]).is_valid_int() or not String(args[0]).to_int() in [1, 2, 3]:
		return _usage("speed")
	return _host.set_speed(String(args[0]).to_int())


func _cmd_pause(args: Array) -> String:
	var mode := String(args[0]).to_lower() if args.size() == 1 else ""
	if args.size() > 1 or not mode in ["", "on", "off"]:
		return _usage("pause")
	return _host.set_paused(mode)


## The honest way: real months, one at a time, until the player's term starts again.
func _cmd_term_start(_args: Array) -> String:
	var state = _host.state()
	var blocked := DevCommands.term_start_blocker(state)
	if not blocked.is_empty():
		return blocked
	if DevCommands.at_term_start(state):
		return "already at a term start -- the agenda holds the offer"
	var ns = state.player()
	var cap: int = int(ns.term_months) + 1
	for i in cap:
		_host.advance_month()
		if not ns.in_government:
			_host.refresh()
			return "after %d month%s the player is out of government (the election was lost); there is no next term" % [
				i + 1, "" if i == 0 else "s"]
		if DevCommands.at_term_start(state):
			_host.refresh()
			_host.term_started()
			return "next term start reached after %d month%s -- now %s" % [
				i + 1, "" if i == 0 else "s", _host.date_text()]
	_host.refresh()
	return "no term start within %d months -- stopped at %s" % [cap, _host.date_text()]


func _cmd_event(args: Array) -> String:
	if args.size() != 1:
		return _usage("event")
	var desk_before := DevCommands.desk_ids(_host.state())
	var result := DevCommands.stage_event(_host.state(), _host.loader(), String(args[0]))
	if bool(result["ok"]):
		_host.event_staged(desk_before)
		_host.refresh()
	return result["text"]


func _slot(args: Array) -> String:
	return String(args[0]) if args.size() == 1 else DEFAULT_SLOT


func _cmd_save(args: Array) -> String:
	if args.size() > 1:
		return _usage("save")
	var error := _host.save_game(_slot(args))
	return "saved '%s'" % _slot(args) if error.is_empty() else "save failed: %s" % error


func _cmd_load(args: Array) -> String:
	if args.size() > 1:
		return _usage("load")
	var error := _host.load_game(_slot(args))
	return "loaded '%s'" % _slot(args) if error.is_empty() else "load failed: %s" % error


func _cmd_open(args: Array) -> String:
	if args.size() != 1:
		return _usage("open")
	var error := _host.open_panel(String(args[0]))
	return "opened %s" % args[0] if error.is_empty() else error


func _cmd_errors(args: Array) -> String:
	if args.size() > 1 or (args.size() == 1 and not String(args[0]).is_valid_int()):
		return _usage("errors")
	var entries: Array[Dictionary] = _host.dev_log().entries
	if entries.is_empty():
		return "no errors or warnings logged"
	var shown := maxi(1, String(args[0]).to_int()) if args.size() == 1 else ERRORS_DEFAULT
	var lines: Array[String] = []
	for entry in entries.slice(maxi(0, entries.size() - shown)):
		lines.append(DevLog.format_entry(entry))
	return "\n".join(lines)


func _cmd_perf(args: Array) -> String:
	var mode := String(args[0]).to_lower() if args.size() == 1 else ""
	if args.size() > 1 or not mode in ["", "on", "off"]:
		return _usage("perf")
	return _host.perf(mode)


## V5.1-d1c (the parent, on QA's #72 review): any run of the game on a real profile
## -- a smoke, a dev run, a windowed frame without its APPDATA line -- spends the
## one-time glossary note; this gives it back.
func _cmd_hint(args: Array) -> String:
	if args.size() != 1 or String(args[0]).to_lower() != "reset":
		return _usage("hint")
	GlossaryHint.reset()
	return "the glossary note shows again on the next game"


func _cmd_clear(_args: Array) -> String:
	_host.clear_output()
	return ""
