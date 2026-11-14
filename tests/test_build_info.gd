extends SceneTree

## Headless test: godot --headless --script res://tests/test_build_info.gd
## Non-zero exit on any failure.
##
## The build version a player reads (AGENTS.md, "Versions and changelog"). What must
## hold, each a silent failure if it does not:
##
##   - the string is the one tools/export_windows.py stamped into the stage's
##     version.json ("build"), verbatim: a kit from a v* tag reads "0.5.3-gate.3", any
##     other export "dev build <sha> (after 0.5.3-gate.2)". The game never decides that
##     itself, so the two can never disagree;
##   - the TRACKED version.json carries no "build": a stamp committed by mistake would
##     make every editor run and every later export claim to be a cut release;
##   - with no stamp (the editor, this suite) it reads "<version>+dev", never a bare
##     released version;
##   - the menu shows it, and the dev console's `version` prints it with the save format.

const BuildInfo = preload("res://src/core/build_info.gd")
const DevRegistry = preload("res://src/ui/dev_registry.gd")
const GameState = preload("res://src/core/game_state.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## SemVer 2.0.0 without build metadata -- the same grammar tools/changelog.py checks.
const SEMVER := "^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)(-((0|[1-9]\\d*|\\d*[A-Za-z-][0-9A-Za-z-]*)(\\.(0|[1-9]\\d*|\\d*[A-Za-z-][0-9A-Za-z-]*))*))?$"

var _failures: Array[String] = []
var _menu
var _frame := 0


func _init() -> void:
	_check_from_dict()
	_check_tracked_file()
	_check_console()
	_menu = load("res://src/ui/menu.tscn").instantiate()
	root.add_child(_menu)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_check_menu()
	_menu.queue_free()
	if _failures.is_empty():
		print("test_build_info: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)
	return true


func _fail(what: String) -> void:
	_failures.append(what)


func _check_from_dict() -> void:
	var cases := [
		[{"version": "0.5.3-gate.3", "build": "0.5.3-gate.3"}, "0.5.3-gate.3"],
		[{"version": "0.5.3-gate.2", "build": "dev build ec92a406 (after 0.5.3-gate.2)"},
			"dev build ec92a406 (after 0.5.3-gate.2)"],
		[{"version": "0.5.3-gate.2"}, "0.5.3-gate.2+dev"],
		[{"version": "0.5.3-gate.2", "build": ""}, "0.5.3-gate.2+dev"],
		[{}, "?"],
	]
	for c in cases:
		var got: String = BuildInfo.from_dict(c[0])
		if got != c[1]:
			_fail("from_dict(%s) = '%s', want '%s'" % [c[0], got, c[1]])


func _check_tracked_file() -> void:
	var d: Dictionary = BuildInfo.read()
	if d.has("build"):
		_fail("the tracked version.json carries a 'build' stamp; only an export's stage copy may")
	var re := RegEx.create_from_string(SEMVER)
	if re.search(String(d.get("version", ""))) == null:
		_fail("version.json's version '%s' is not SemVer" % d.get("version", ""))
	if BuildInfo.text() != String(d.get("version", "")) + "+dev":
		_fail("unstamped, text() is '%s', want the version + '+dev'" % BuildInfo.text())


func _check_console() -> void:
	var out: String = DevRegistry.new(DevRegistry.Host.new()).run("version")
	if not out.contains(BuildInfo.text()):
		_fail("console `version` does not print the build string: %s" % out)
	if not out.contains("save format %d" % GameState.SAVE_VERSION):
		_fail("console `version` does not print the save format: %s" % out)
	if not DevRegistry.new(DevRegistry.Host.new()).run("help").contains("version"):
		_fail("`help` does not list `version`")


func _check_menu() -> void:
	var label: Label = _menu.find_child("BuildVersion", true, false)
	if label == null:
		_fail("the menu has no BuildVersion label")
		return
	if label.text != BuildInfo.text():
		_fail("the menu shows '%s', want '%s'" % [label.text, BuildInfo.text()])
	if label.theme_type_variation != UiTheme.CAPTION:
		_fail("the menu's version line is not a Caption (theme_type_variation '%s')" % label.theme_type_variation)
	if not label.is_visible_in_tree() or label.get_global_rect().size.x <= 0.0:
		_fail("the menu's version line is not on screen")
	if label.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("the version line takes clicks meant for the menu")
