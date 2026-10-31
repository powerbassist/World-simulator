extends RefCounted

## The one place in the repo that may move the player's real mouse cursor, and
## the one place a dev window is told not to take the desk from them.
## Dev-only (tools/ never ships); `const OsCursor = preload("res://tools/os_cursor.gd")`.
##
## WHY IT EXISTS. A windowed Godot run reads the OS cursor: Viewport.get_mouse_position()
## and every Control's get_local_mouse_position() are the real pointer there, a pushed
## InputEventMouseMotion does not change them (measured, 4.7.2), and a RichTextLabel's
## meta hover reads the OS cursor alone (the memory note godot-rtl-hover-reads-os-cursor).
## So a test or a capture that needs "the pointer is HERE" has to warp it -- and a warp
## drags the author's cursor across whatever they are doing, out of a game or an editor,
## on every click of every run. Headless, there is no cursor: the warp is a no-op and
## the suite never touched it (DisplayServer.mouse_get_position() reads (0, 0) throughout).
##
## THE RULE. Nothing else calls the engine's warp function (tests/test_os_cursor.gd
## fails the suite on it), and this does so only when the author said so:
##
##   NATION_OS_CURSOR=1 godot --path . --script res://tools/screenshot.gd -- --hover-outline RUS
##
## OFF by default, so a run started by an agent, a hook or CI never moves the pointer.
## What a position-dependent proof does without it is the CALLER's call: push its own
## motion (the reticle follows a pushed motion), set the position itself, or say the
## frame is not a pointer proof. It is never silently "fine".
##
## The env var, not an argument: it reaches a SceneTree script, a child process of
## tools/suite_runner.py and tools/screenshot_all.py alike, without each one parsing it.

const ENV_FLAG := "NATION_OS_CURSOR"
## Past every monitor on any layout a player has; Windows keeps a window there.
const OFF_SCREEN := Vector2i(-30000, -30000)


## Pure, so the test can table it. Only "1" turns it on, and a headless display never
## counts: it has no cursor, and "on" would mean a caller waits for a move that cannot be.
static func flag_on(value: String, display_name: String) -> bool:
	return value == "1" and display_name != "headless"


static func enabled() -> bool:
	return flag_on(OS.get_environment(ENV_FLAG), DisplayServer.get_name())


## Put the real cursor at `at`, in `viewport`'s coordinates. Returns whether it did:
## false with the flag off, so a caller that needs the pointer there can say so.
static func warp(viewport: Viewport, at: Vector2) -> bool:
	if not enabled():
		return false
	viewport.warp_mouse(at)
	return true


## For a WINDOWED dev run that does not need the pointer (a capture, a probe): keep the
## window off every monitor, so no hand can be over it and no real mouse motion can land
## between a pushed press and release (the race tests/click.gd used to pin by warping).
## A window at (-30000, -30000) still renders and hands back a correct viewport image
## (measured, 4.7.2 windows: a ColorRect read back 0.90/0.20/0.10 there). A MINIMIZED
## window does not: the same readback came out blank, so this never minimizes.
##
## IDEMPOTENT AND RE-CALLABLE: it asks "is the window off screen NOW?" each time rather
## than remembering that it once moved it, because the game re-centres or re-fullscreens
## the window when it applies the saved settings (SettingsPanel._apply, after a script's
## _init), and an un-isolated run reads the author's settings.cfg. A fullscreen or
## maximized window ignores window_set_position, so the mode is forced to WINDOWED first.
## Call it again where a settings apply may have run (a capture tool does so each frame).
## Returns whether the window is off screen after the call (the position is read back).
##
## IT DOES NOT KEEP THE KEYBOARD. Moving the window does nothing for focus: a Godot window
## launched from the foreground app took the foreground in 3 of 7 measured launches, off
## screen or not (docs/tooling.md "The real mouse cursor"), and an off-screen window that
## holds the focus sends the author's keystrokes to a game they cannot see. What did stop
## it, in 6 of 6 launches, is the project setting display/window/size/no_focus=true,
## which only takes effect at window creation: an override.cfg beside project.godot
## (tools/screenshot_all.py writes one for its runs). NO_FOCUS / MOUSE_PASSTHROUGH set late
## through window_set_flag changed no Win32 style bit, so they are not used here.
## Not applied with the flag on (that run wants the real cursor, on screen), headless (no
## window), nor to timing probes, whose numbers a moved window could change.
## The window exists for the first moments of the boot before a script can move it:
## that flash is not avoidable from here (--position is clamped onto a monitor).
static func quiet_window() -> bool:
	if enabled() or DisplayServer.get_name() == "headless":
		return false
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if DisplayServer.window_get_position() != OFF_SCREEN:
		DisplayServer.window_set_position(OFF_SCREEN)
	return DisplayServer.window_get_position() == OFF_SCREEN
