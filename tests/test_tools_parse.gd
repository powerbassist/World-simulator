extends SceneTree

## Headless test: godot --headless --script res://tests/test_tools_parse.gd
## Non-zero exit on any failure.
##
## The suite only parses what a test loads, and no test loads tools/*.gd: the probes,
## the screenshot driver and the gate scripts call into src/ by a signature, and a
## signature that moves under them breaks nothing until someone runs the probe. QA's
## find, from the screenshot driver: #256 changed a sim function and #257's tools
## script was left calling the old arity, green everywhere. Loading a script
## compiles it, so a wrong arity, an unknown name or a type error on a call the
## compiler can resolve leaves a script that cannot compile -- the same check as
## `godot --headless --check-only --script <file>`, in-process, one file at a time
## with the cache ignored so a script that failed once is not served from memory.
##
## What it does NOT see (QA's records on #262):
##   - A call through an untyped receiver (`var state = ...; state.player().foo(1, 2)`)
##     compiles whatever its arity, and a changed return shape or dictionary key is
##     never a compile error. Only typed and static calls are gated, so a tools
##     script that wants this protection types its receivers.
##   - Loading runs a script's static initialisers (today one harmless
##     `static var ... := 0.0` in tools/media_probe.gd). A tools script whose static
##     initialiser has a side effect would have it here.
##
## It scans the WORKING TREE, not git's file list: an untracked or gitignored .gd
## under tools/ (a session's scratch copy) fails this test locally while CI, which
## only has tracked files, never sees it. That is deliberate -- a scratch script
## that no longer compiles is noise worth hearing about -- but it is how a run can
## be red here and green in CI.
##
## It runs under the isolated gate (tools/run_tests.sh, suite_runner.py) like every
## test, and CI through its shard. The mutants that prove the broken side: a
## wrong-arity call, a syntax error, an unknown name and a type error in a tools
## script each make this test fail naming that file. They cannot be a control inside
## the test, because the runner fails any run whose output carries a `Parse Error`.
##
## A script that fails to compile is NOT a null load: see _compiles().

const TOOLS_DIR := "res://tools"
## A floor, not a count: the scan finding a handful of files means the directory
## read broke, and a pass over nothing would be the quietest failure this test has.
const MIN_SCRIPTS := 50

var _failures: Array[String] = []


func _init() -> void:
	_check_classifier()
	var paths := _scripts(TOOLS_DIR)
	if paths.size() < MIN_SCRIPTS:
		_fail("the scan found %d scripts under %s, expected at least %d" % [paths.size(), TOOLS_DIR, MIN_SCRIPTS])
	for path in paths:
		var script = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if not _compiles(script):
			_fail("%s does not compile (see the SCRIPT ERROR above it)" % path)
	if _failures.is_empty():
		print("test_tools_parse: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


## Whether a loaded script compiled. A script that fails to compile still comes back
## as a GDScript object (measured on 4.7.2, with "Failed to load script ... Parse
## error" printed), so a null check passes it; the tell is can_instantiate() false
## (and reload() answering ERR_PARSE_ERROR). An @abstract script is NOT a false
## positive on 4.7.2 -- it reports can_instantiate() true, is_abstract() true --
## which _check_classifier() pins: QA recorded the opposite as a risk on #262.
func _compiles(script) -> bool:
	return script is GDScript and script.can_instantiate()


## The classifier's accepting side, on sources written here: a plain script and an
## @abstract one. The second is the premise _compiles() rests on; if a later engine
## makes can_instantiate() false for it, a tools script that is abstract would be
## reported as broken, and the fix is to also accept `script.reload() == OK`. The
## rejecting side has no control in-process (see the header), so a classifier that
## accepted everything is caught by the mutants, not by this.
func _check_classifier() -> void:
	var plain := GDScript.new()
	plain.source_code = "extends RefCounted
func f() -> int:
	return 1
"
	plain.reload()
	if not _compiles(plain):
		_fail("control: a plain valid script was classified as not compiling")
	var abstract_script := GDScript.new()
	abstract_script.source_code = "@abstract
extends RefCounted
func f() -> int:
	return 1
"
	abstract_script.reload()
	if not _compiles(abstract_script):
		_fail("control: an @abstract script that compiles was classified as not compiling -- also accept reload() == OK")


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
