extends SceneTree

## Headless test: godot --headless --script res://tests/test_window_frame.gd
## Non-zero exit on any failure.
##
## U5a's window machinery, tested on its own rather than through main.tscn. The
## manager holds no game state and every panel it shows is just a Control, so a
## test that built the whole game to check that pinning works would be measuring
## the wrong thing -- and would not fail for the right reason when it broke.
##
## What this pins down is the one rule the layout rests on: **opening a panel
## closes the open unpinned one, and leaves every pinned one alone.** Get that
## wrong in either direction and the interface is either a stack of windows the
## player has to tidy by hand, or a set of tabs with extra steps.
##
## Driven a frame at a time -- a Control outside the tree has not run _ready(),
## so everything it builds is null. See docs/engine-decision.md.

const WindowManager = preload("res://src/ui/window_manager.gd")

const BOUNDS := Vector2(1920, 1080)

var _failures: Array[String] = []
var _manager
var _contents := {}
var _frame := 0


## The manager goes inside an explicitly-sized host rather than straight under
## the root window. Headless, the root window is 64x64 and a full-rect Control
## added to it reports 1920x1920 -- neither of which is the 1920x1080 the HUD is
## laid out against, so a clamp test hung off the root would be measuring a
## screen that does not exist. In the game the manager's parent is main.tscn's
## root Control, which is exactly what this host stands in for.
func _init() -> void:
	var host := Control.new()
	root.add_child(host)
	host.size = BOUNDS

	_manager = WindowManager.new()
	host.add_child(_manager)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let _ready() run on the manager and everything under it

	_register_three()
	_check_closed_at_start()
	_check_open_replaces_unpinned()
	_check_pinned_survives()
	_check_close_closes_exactly_one()
	_check_z_order_follows_the_last_opened()
	_check_drag_clamps_to_bounds()
	_check_content_survives_close()
	_finish()
	return false


func _register_three() -> void:
	for id in ["alpha", "beta", "gamma"]:
		var content := Label.new()
		content.text = "content of %s" % id
		content.custom_minimum_size = Vector2(300, 200)
		_contents[id] = content
		_manager.register(id, id.to_upper(), content)


func _check_closed_at_start() -> void:
	if not _manager.open_ids().is_empty():
		_fail("registering a panel opened it: %s" % str(_manager.open_ids()))


## The core rule, in the direction that is easy to get right.
func _check_open_replaces_unpinned() -> void:
	_manager.open("alpha")
	if not _manager.is_open("alpha"):
		_fail("open('alpha') did not open it")

	_manager.open("beta")
	if _manager.is_open("alpha"):
		_fail("opening 'beta' left the unpinned 'alpha' open")
	if not _manager.is_open("beta"):
		_fail("open('beta') did not open it")


## The same rule in the direction that is easy to get wrong, and the reason the
## player was offered a pin at all.
func _check_pinned_survives() -> void:
	_close_everything()

	_manager.open("alpha")
	_manager.frame("alpha").set_pinned(true)
	_manager.open("beta")

	if not _manager.is_open("alpha"):
		_fail("a pinned panel was closed by opening another one")
	if not _manager.is_open("beta"):
		_fail("opening 'beta' beside a pinned panel did not open it")

	# A third open closes the unpinned 'beta' and still leaves the pinned one.
	_manager.open("gamma")
	if not _manager.is_open("alpha"):
		_fail("a pinned panel did not survive a second unrelated open")
	if _manager.is_open("beta"):
		_fail("the unpinned 'beta' survived opening 'gamma'")
	if not _manager.is_open("gamma"):
		_fail("open('gamma') did not open it")

	# Unpinning has to actually give the panel back to the rule.
	_manager.frame("alpha").set_pinned(false)
	_manager.open("beta")
	if _manager.is_open("alpha"):
		_fail("unpinning did not return the panel to the close-on-open rule")


func _check_close_closes_exactly_one() -> void:
	_close_everything()

	_manager.open("alpha")
	_manager.frame("alpha").set_pinned(true)
	_manager.open("beta")
	_manager.frame("beta").set_pinned(true)

	# The X on the title bar, driven through the signal the button emits rather
	# than by clicking it -- same reason map_view.gd exposes pan_by().
	_manager.frame("alpha").close_requested.emit()

	if _manager.is_open("alpha"):
		_fail("the close button did not close its own panel")
	if not _manager.is_open("beta"):
		_fail("closing one pinned panel closed the other one too")


## Whatever was opened last is the thing the player is looking at, so it has to
## draw over the panels that were already there.
func _check_z_order_follows_the_last_opened() -> void:
	_close_everything()

	_manager.open("alpha")
	_manager.frame("alpha").set_pinned(true)
	_manager.open("beta")

	var frames: Array = _manager.get_children()
	if frames.back() != _manager.frame("beta"):
		_fail("the last-opened panel is not the frontmost child")

	# Re-opening an already-open pinned panel is how the player raises it.
	_manager.open("alpha")
	frames = _manager.get_children()
	if frames.back() != _manager.frame("alpha"):
		_fail("re-opening a pinned panel did not raise it to the front")


## A window dragged off the edge of the screen is a window the player cannot get
## back, because the title bar is the only thing that drags it.
func _check_drag_clamps_to_bounds() -> void:
	_close_everything()
	_manager.open("alpha")
	var frame = _manager.frame("alpha")

	frame.drag_by(Vector2(-9000, -9000))
	if frame.position.x < 0.0 or frame.position.y < 0.0:
		_fail("dragging up-left left the window at %s, outside the screen" % str(frame.position))

	frame.drag_by(Vector2(9000, 9000))
	if frame.position.x + frame.size.x > BOUNDS.x or frame.position.y + frame.size.y > BOUNDS.y:
		_fail("dragging down-right left the window at %s, outside %s" % [str(frame.position), str(BOUNDS)])


## Closing hides a panel, it does not free it. Every panel in this game holds a
## setup(state, loader) and a signal connection made once at startup; freeing one
## on close would mean rebuilding and rewiring it on every open.
func _check_content_survives_close() -> void:
	_close_everything()
	_manager.open("gamma")
	_manager.close("gamma")

	var content: Control = _contents["gamma"]
	if not is_instance_valid(content):
		_fail("closing a panel freed its content")
		return
	if content.text != "content of gamma":
		_fail("closing a panel disturbed its content")
	if _manager.frame("gamma").visible:
		_fail("closing a panel left its frame visible")


func _close_everything() -> void:
	for id in _manager.open_ids():
		_manager.frame(id).set_pinned(false)
		_manager.close(id)


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_window_frame: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
