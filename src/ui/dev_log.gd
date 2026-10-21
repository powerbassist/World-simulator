extends RefCounted

## THE IN-GAME ERROR LOG (V5.1-0b): a play gate's crash shows its error in the
## game. Godot's Logger (OS.add_logger, 4.5+) hears every push_error, push_warning
## and script error the engine prints; the console's counter and Errors tab read
## what it heard.
##
## A Logger callback arrives on WHATEVER THREAD raised the error -- a worker in
## src/core/parallel.gd's pool as readily as the main thread -- so the Capture only
## appends to a mutex-guarded buffer and poll(), called from the console's
## _process, moves it to `entries` on the main thread. The callback must also never
## raise an error of its own (the engine would call it again), so it does nothing
## but copy.
##
## WHERE AN ERROR IS: a script error carries its own script and line. A push_error
## reports the engine's C++ file, so the script that called it is the first frame of
## the backtrace the engine hands over; without one the engine's file is kept.

const MAX_ENTRIES := 200
## THE ONE KNOWN-EXPECTED LINE, kept out of the counter and named here with its reason:
## a decision's figure with no baseline reading is NaN by construction (V5.0 fix pass
## P1, Trends' "no data"), and the save path turns it into null with this by-design
## warning -- once per process. Without this every clean session would read WARN 1
## after its first save and the counter would stop meaning anything. It stays in the
## Errors tab, marked "(expected)". Only the NaN wording: Infinity, or any other line,
## still counts (that is a real bug).
const EXPECTED_PATTERN := "^`NaN` \\(\"Not a Number\"\\) found in argument passed to JSON\\.stringify\\(\\)"
## The engine's own text, for the test.
const EXPECTED_SAMPLE := "`NaN` (\"Not a Number\") found in argument passed to JSON.stringify(). `NaN` cannot be represented in JSON, so the value has been replaced with `null`."

var errors := 0
var warnings := 0
## Newest last: {kind: "error"|"warning", text, file, line, function}.
var entries: Array[Dictionary] = []

var _capture := Capture.new()
var _expected := RegEx.create_from_string(EXPECTED_PATTERN)
var _installed := false


class Capture extends Logger:
	var _mutex := Mutex.new()
	var _pending: Array[Dictionary] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var entry := {
			"kind": "warning" if error_type == Logger.ERROR_TYPE_WARNING else "error",
			"text": rationale if code.is_empty() else (code if rationale.is_empty() else "%s: %s" % [code, rationale]),
			"file": file,
			"line": line,
			"function": function,
		}
		if not file.ends_with(".gd") and not script_backtraces.is_empty() and script_backtraces[0].get_frame_count() > 0:
			var trace: ScriptBacktrace = script_backtraces[0]
			entry["file"] = trace.get_frame_file(0)
			entry["line"] = trace.get_frame_line(0)
			entry["function"] = trace.get_frame_function(0)
		_mutex.lock()
		_pending.append(entry)
		_mutex.unlock()

	func take() -> Array[Dictionary]:
		_mutex.lock()
		var out := _pending
		_pending = []
		_mutex.unlock()
		return out


func install() -> void:
	if not _installed:
		OS.add_logger(_capture)
		_installed = true


func uninstall() -> void:
	if _installed:
		OS.remove_logger(_capture)
		_installed = false
		poll()


## Moves what the Logger heard onto the main thread; returns how many entries.
func poll() -> int:
	var heard := _capture.take()
	for entry in heard:
		add(entry["kind"], entry["text"], entry["file"], entry["line"], entry["function"])
	return heard.size()


## Newest MAX_ENTRIES are kept; the counters count every one.
func add(kind: String, text: String, file: String, line: int, function: String) -> void:
	var expected := kind == "warning" and _expected.search(text) != null
	if expected:
		pass
	elif kind == "warning":
		warnings += 1
	else:
		errors += 1
	entries.append({"kind": kind, "text": text, "file": file, "line": line, "function": function,
		"expected": expected})
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()


func clear() -> void:
	entries.clear()
	errors = 0
	warnings = 0


## One line per entry, the way the Errors tab and `errors` print it.
static func format_entry(entry: Dictionary) -> String:
	return "[%s] %s  (%s:%d)%s" % [
		"E" if String(entry["kind"]) == "error" else "W",
		entry["text"], entry["file"], int(entry["line"]),
		" (expected)" if bool(entry.get("expected", false)) else ""]
