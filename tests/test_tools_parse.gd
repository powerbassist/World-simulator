extends SceneTree

## Headless test: godot --headless --script res://tests/test_tools_parse.gd
## Non-zero exit on any failure.
##
## The suite only parses what a test loads, and no test loads tools/*.gd: the probes,
## the screenshot driver and the gate scripts call into src/ by a signature, and a
## signature that moves under them breaks nothing until someone runs the probe. QA's
## find, from the screenshot driver: #256 changed a sim function and #257's tools
## script was left calling the old arity, green everywhere. Loading a script
## compiles it, so a wrong arity, an unknown name or a type error leaves a script that cannot instantiate --
## the same check as `godot --headless --check-only --script <file>`, in-process, one
## file at a time with the cache ignored so a script that failed once is not served
## from memory.
##
## It runs under the isolated gate (tools/run_tests.sh, suite_runner.py) like every
## test, and CI through its shard. The mutant that proves it: a wrong-arity call in
## tools/screenshot.gd makes this test fail naming that file.
##
## A script that fails to compile is NOT a null load: see the comment at the check.

const TOOLS_DIR := "res://tools"
## A floor, not a count: the scan finding a handful of files means the directory
## read broke, and a pass over nothing would be the quietest failure this test has.
const MIN_SCRIPTS := 50

var _failures: Array[String] = []


func _init() -> void:
	var paths := _scripts(TOOLS_DIR)
	if paths.size() < MIN_SCRIPTS:
		_fail("the scan found %d scripts under %s, expected at least %d" % [paths.size(), TOOLS_DIR, MIN_SCRIPTS])
	for path in paths:
		var script = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		# A script that fails to compile still comes back as a GDScript object
		# (measured on 4.7.2, with "Failed to load script ... Parse error" printed):
		# the tell is can_instantiate(), false, and reload() answering ERR_PARSE_ERROR.
		if not (script is GDScript) or not script.can_instantiate():
			_fail("%s does not compile (see the SCRIPT ERROR above it)" % path)
	if _failures.is_empty():
		print("test_tools_parse: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


## Every .gd under `dir`, sorted, recursing into sub-folders.
func _scripts(dir: String) -> Array[String]:
	var found: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			found.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		found.append_array(_scripts(dir.path_join(d)))
	found.sort()
	return found


func _fail(msg: String) -> void:
	_failures.append(msg)
