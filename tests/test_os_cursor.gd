extends SceneTree

## Headless test: godot --headless --script res://tests/test_os_cursor.gd
## Non-zero exit on any failure.
##
## One helper moves the author's real mouse cursor (tools/os_cursor.gd), and it is
## OFF unless NATION_OS_CURSOR=1. Two halves:
##
##   1. The gate. The flag reads "1" and nothing else, a headless display never
##      counts as on (it has no cursor to move), and with the flag off a warp
##      neither happens nor claims to have.
##   2. The lint. A call to the engine's warp function anywhere in tests/, tools/
##      or src/ outside the helper fails here -- the way a test that warped
##      "just once" would otherwise pass the suite and then drag the author's
##      pointer across the screen on a windowed run (the sites this was written
##      for: tests/click.gd, tests/test_front_page.gd, tools/screenshot.gd).
##
## The lint has a positive control: the scanner is run over a snippet that does
## call the function and over ones that only mention it in a comment.

const OsCursor = preload("res://tools/os_cursor.gd")

const HELPER := "res://tools/os_cursor.gd"
const ROOTS := ["res://tests", "res://tools", "res://src"]

var _failures: Array[String] = []


func _init() -> void:
	_check_gate()
	_check_plan()
	_check_scanner()
	_check_tree()
	if _failures.is_empty():
		print("test_os_cursor: all checks passed")
		quit(0)
	else:
		for f in _failures:
			push_error(f)
		quit(1)


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _check_gate() -> void:
	if not OsCursor.flag_on("1", "windows"):
		_fail("NATION_OS_CURSOR=1 on a windowed display did not turn the flag on")
	for off in ["", "0", "true", "yes", "2", " 1"]:
		if OsCursor.flag_on(off, "windows"):
			_fail("NATION_OS_CURSOR=%s turned the flag on; only \"1\" does" % [off])
	if OsCursor.flag_on("1", "headless"):
		_fail("the flag counted as on under a headless display, which has no cursor")
	# This process: headless, env unset -> off, and a warp is refused, not faked.
	if OsCursor.enabled():
		_fail("OsCursor.enabled() is true in a headless suite run")
	if OsCursor.warp(root, Vector2(5, 5)):
		_fail("OsCursor.warp() reported a warp with the flag off")
	if OsCursor.quiet_window():
		_fail("OsCursor.quiet_window() reported a change on a headless display")


## quiet_window() must READ the window each call. QA's measured failure: a capture tool that
## boots the menu has its window put fullscreen on the author's monitor by the menu's own
## SettingsPanel.apply_saved(), after the helper had moved it once -- so a helper that
## remembered "done" left it there. The plan is pure, so the state sequence is pinned here.
func _check_plan() -> void:
	var win := DisplayServer.WINDOW_MODE_WINDOWED
	var full := DisplayServer.WINDOW_MODE_FULLSCREEN
	var maxed := DisplayServer.WINDOW_MODE_MAXIMIZED
	var off := OsCursor.OFF_SCREEN
	if OsCursor.quiet_plan(win, off) != [false, false]:
		_fail("a windowed off-screen window needed work: %s" % [OsCursor.quiet_plan(win, off)])
	if OsCursor.quiet_plan(win, Vector2i(960, 540)) != [false, true]:
		_fail("a re-centred window was not moved off screen again")
	if OsCursor.quiet_plan(full, Vector2i(0, 0)) != [true, true]:
		_fail("a fullscreen window was not put windowed and off screen")
	if OsCursor.quiet_plan(maxed, off) != [true, true]:
		_fail("a maximized window was not put windowed and off screen (it ignores the position)")
	# The QA sequence: off screen, then the menu applies the saved settings -> fullscreen.
	var states := [[win, off], [full, Vector2i(0, 0)], [win, off]]
	var plans: Array = []
	for st in states:
		plans.append(OsCursor.quiet_plan(st[0], st[1]))
	if plans != [[false, false], [true, true], [false, false]]:
		_fail("the plan has a memory: %s" % [plans])
	if FileAccess.get_file_as_string(HELPER).contains("static " + "var"):
		_fail("tools/os_cursor.gd keeps static state; quiet_window must read the window every call")


func _check_scanner() -> void:
	var call_line := "\tviewport." + "warp_" + "mouse(at)\n"
	if _offenders(call_line).size() != 1:
		_fail("the scanner missed a plain warp call (positive control)")
	if _offenders("\tInput." + "warp_" + "mouse(Vector2(1, 2))\n").size() != 1:
		_fail("the scanner missed an Input warp call (positive control)")
	if _offenders("	viewport.call(\"warp_" + "mouse\", at)
").size() != 1:
		_fail("the scanner missed a call by name (positive control)")
	if _offenders("## Headless, the " + "warp_" + "mouse call is a no-op.\n").size() != 0:
		_fail("the scanner flagged a doc comment that only names the function")
	if _offenders("\tvar x := 1  # " + "warp_" + "mouse(at) was here\n").size() != 0:
		_fail("the scanner flagged a trailing comment")


func _check_tree() -> void:
	var seen := 0
	for dir in ROOTS:
		for path in _gd_files(dir):
			seen += 1
			if path == HELPER:
				continue
			var text := FileAccess.get_file_as_string(path)
			for hit in _offenders(text):
				_fail("%s:%d moves the OS cursor outside tools/os_cursor.gd: %s -- go through OsCursor.warp()" % [path, hit[0], hit[1]])
	if seen < 200:
		_fail("the lint saw only %d scripts; a root went missing" % seen)
	var helper_text := FileAccess.get_file_as_string(HELPER)
	if _offenders(helper_text).size() != 1:
		_fail("tools/os_cursor.gd should hold exactly one warp call, the one place it is allowed")


## [[line number, trimmed line], ...] for each line that CALLS the warp function.
## A '#' ends the code on a line (comments and trailing comments); a string that
## holds a '#' and then a warp call is not a thing this repo writes.
func _offenders(text: String) -> Array:
	var out: Array = []
	var needle := "warp_" + "mouse("
	var named := ["\"warp_" + "mouse\"", "'warp_" + "mouse'"]  # call("...") / callv by name
	var n := 0
	for line in text.split("\n"):
		n += 1
		var hash_at := line.find("#")
		var code := line if hash_at < 0 else line.substr(0, hash_at)
		if code.contains(needle) or code.contains(named[0]) or code.contains(named[1]):
			out.append([n, line.strip_edges()])
	return out


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_gd_files(dir_path + "/" + sub))
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
	return out
