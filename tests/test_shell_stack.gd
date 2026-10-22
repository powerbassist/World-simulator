extends SceneTree

## Headless test: godot --headless --script res://tests/test_shell_stack.gd
## Non-zero exit on any failure.
##
## V5.1-c2.1, the screen stack. Before it, "what is on top" was answered four
## times in main.gd's Escape branch, in an order a comment had to defend, and
## nowhere else: a panel hotkey under a summit closed the summit, an interrupt
## under one opened Dispatches and closed it too, and Escape over the settings
## screen opened a second pause menu. One ranked stack now answers it for the
## keys, Escape and the game's own arrivals.
##
## Driven a frame at a time because a Control outside the scene tree has not run
## _ready() -- see docs/engine-decision.md -- and because the budget builds its
## levers on the frame after it opens.

const ScreenStack = preload("res://src/ui/screen_stack.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the scene's _ready() run
	if _frame == 2:
		# `get()` rather than `_main._stack`: a main.gd without the field (or one
		# that fails to parse) must fail here, not raise a script error the
		# runner could read as a pass.
		if _main.get("_stack") == null:
			_fail("main scene built no screen stack")
			_finish()
			return false
		_main._windows.close_all()
		_main._windows.open("budget")
		return false
	if _frame < 4:
		return false  # the budget builds its levers on its first visible frame
	_check_focus_returns_below()
	_check_escape_pops_the_top()
	_check_hotkeys_only_below_scenes()
	_check_placement_is_a_layer()
	_check_arrival_under_a_scene()
	_check_holding_arrival_slides_in()
	_check_a_note_does_not_slide_in()
	_check_answer_slides_back()
	_check_an_ordinary_hold_slides_in()
	_check_answer_keeps_the_inbox_while_one_holds()
	_check_space_waits_under_a_scene()
	_finish()
	return false


## Review focus 1's neighbour: a system screen over a domain takes the keyboard
## away from it -- a lever below must not move on an arrow key the player meant
## for the menu -- and gives it back where it was when the screen goes.
func _check_focus_returns_below() -> void:
	var budget: Control = _main._budget_panel
	var lever := _first_focusable(budget)
	if lever == null:
		_fail("the open budget has no focusable control to test focus with")
		return
	lever.grab_focus()
	_main._open_pause_menu()
	var owner: Control = _main.get_viewport().gui_get_focus_owner()
	if owner != null and budget.is_ancestor_of(owner):
		_fail("the pause menu opened and the budget below kept the keyboard (%s)" % owner.name)
	_main._close_pause_menu()
	owner = _main.get_viewport().gui_get_focus_owner()
	if owner != lever:
		_fail("the pause menu closed and focus did not return to the budget's lever (got %s)"
			% ("nothing" if owner == null else owner.name))
	lever.release_focus()


## System over scene over workspace: three Escapes take them off in that order,
## the map is what is left, and the fourth Escape is the pause menu -- the key's
## meaning when there is nothing to put away.
func _check_escape_pops_the_top() -> void:
	var stack = _main._stack
	_main._windows.close_all()
	_main._windows.open("budget")
	# V5.1-d1a (G1): the inbox the map showed rides over the tab, a layer of its own.
	if not _main._hud.inbox.is_slid() or stack.top() != ScreenStack.INBOX:
		_fail("the inbox did not ride over the budget as the INBOX layer (top %d)" % stack.top())
	_main._briefing.show()
	_main._hud.title_bar.save_load_requested.emit()
	if stack.top() != ScreenStack.SYSTEM:
		_fail("save dialog over a briefing over the budget: top is %d, not SYSTEM" % stack.top())

	_press(KEY_ESCAPE)
	if _main._save_load_panel.visible:
		_fail("first Escape did not close the save dialog")
	if not _main._briefing.visible or stack.top() != ScreenStack.SCENE:
		_fail("first Escape reached below the save dialog (top %d)" % stack.top())

	_press(KEY_ESCAPE)
	if _main._briefing.visible:
		_fail("second Escape did not close the briefing")
	if not _main._windows.is_open("budget") or stack.top() != ScreenStack.INBOX:
		_fail("second Escape reached below the briefing (top %d)" % stack.top())

	_press(KEY_ESCAPE)
	if _main._hud.inbox.visible or not _main._windows.is_open("budget"):
		_fail("third Escape did not put the inbox away, the budget kept")
	if stack.top() != ScreenStack.WORKSPACE:
		_fail("third Escape reached below the inbox (top %d)" % stack.top())

	_press(KEY_ESCAPE)
	if _main._windows.is_open("budget"):
		_fail("fourth Escape did not put the budget away")
	if stack.top() != ScreenStack.MAP:
		_fail("four Escapes over four layers left top %d, not the map" % stack.top())
	if _main._pause_menu.visible:
		_fail("an Escape that closed something also opened the pause menu")

	_press(KEY_ESCAPE)
	if not _main._pause_menu.visible:
		_fail("Escape on the bare map did not open the pause menu")
	_press(KEY_ESCAPE)
	if _main._pause_menu.visible:
		_fail("Escape did not close the pause menu it opened")


## A scene owns the screen: B under a summit used to open the budget AND close
## the summit (open() closes the unpinned window), and M swept it away.
func _check_hotkeys_only_below_scenes() -> void:
	var stack = _main._stack
	_main._windows.close_all()
	_main._windows.open("summit")
	if stack.top() != ScreenStack.SCENE:
		_fail("the summit is not a scene (top %d)" % stack.top())
	_press(KEY_B)
	if _main._windows.is_open("budget"):
		_fail("a panel hotkey opened the budget under the summit")
	if not _main._windows.is_open("summit"):
		_fail("a panel hotkey closed the summit")
	_press(KEY_M)
	if not _main._windows.is_open("summit"):
		_fail("M swept the summit away")
	if stack.accepts_hotkeys():
		_fail("the stack accepts hotkeys with a scene on top")

	_main._windows.close("summit")
	_press(KEY_B)
	if not _main._windows.is_open("budget"):
		_fail("with the summit gone, B no longer opens the budget")
	if not stack.accepts_hotkeys():
		_fail("the stack refuses hotkeys with only a domain open")
	_main._windows.close_all()


## The armed reticle is a layer of its own: a key that would open a window
## while the map waits for a point is refused, and Escape ends the placement
## before anything else.
func _check_placement_is_a_layer() -> void:
	var stack = _main._stack
	_main._windows.open("energy")
	_main._on_energy_order_armed("stack_test_action")
	if stack.top() != ScreenStack.PLACEMENT:
		_fail("an armed placement is not the top layer (top %d)" % stack.top())
	_press(KEY_B)
	if _main._windows.is_open("budget"):
		_fail("a panel hotkey opened a window while a placement was armed")
	_press(KEY_ESCAPE)
	if _main._armed_energy_action != "":
		_fail("Escape did not cancel the armed placement")
	# V5.1-d1a (G6): arming put the workspace away, so the map is what is left.
	if stack.top() != ScreenStack.MAP:
		_fail("cancelling the placement did not drop to the map (top %d)" % stack.top())
	_main._windows.close_all()


## Review focus 1: a clock-holding decision that arrives while a scene is up.
## The scene stays on top, nothing opens behind it (open() would close a
## summit), and the clock stays held. When the scene goes, the inbox is up: a
## paused clock with nothing on screen saying why is the silent failure this
## pins.
func _check_arrival_under_a_scene() -> void:
	var Events := load("res://src/sim/events.gd")
	var stack = _main._stack
	var ns = _main._state.player()
	var clock: Node = _main.get_node("Clock")
	var interrupt_ev = Events.event_by_id(_main._loader, "blackout_night")
	if interrupt_ev == null or not bool(interrupt_ev.interrupt):
		_fail("blackout_night missing or not an interrupt")
		return
	_main._windows.close_all()
	ns.event_queue.clear()
	_main._unseen_events.clear()
	_main._event_cards.clear()
	_main._paused_for_decision = false
	clock.paused = false

	_main._windows.open("summit")
	var month: int = Events._absolute_month(int(_main._state.year), int(_main._state.month))
	Events.announce(ns, interrupt_ev, month, Events.region_names(ns, _main._loader))
	_main._enforce_interrupt()
	if not clock.paused or not _main._paused_for_decision:
		_fail("an interrupt under a scene did not hold the clock")
	if _main._windows.is_open("events") or _main._hud.inbox.is_slid():
		_fail("an interrupt under a scene opened Dispatches or slid the inbox under it")
	if not _main._windows.is_open("summit") or stack.top() != ScreenStack.SCENE:
		_fail("an interrupt under a scene took the scene off the top")

	_main._windows.close("summit")
	if not _main._hud.inbox.visible:
		_fail("the scene closed over a held interrupt and the inbox is not up")

	ns.event_queue.clear()
	_main._paused_for_decision = false
	clock.paused = false
	_main._windows.close_all()


## V5.1-c3.2, the author's call 4: a decision that holds the clock while a tab is
## open slides the inbox over the strip of map beside it; the tab stays, the
## keys still work, and Escape slides it back before it closes the tab.
func _check_holding_arrival_slides_in() -> void:
	var stack = _main._stack
	var inbox = _main._hud.inbox
	_stage_interrupt_with("budget")
	if not _main._windows.is_open("budget"):
		_fail("a holding arrival closed the open tab")
	if not inbox.visible or not inbox.is_slid():
		_fail("a holding arrival over a tab did not slide the inbox in")
	if stack.top() != ScreenStack.INBOX or not stack.accepts_hotkeys():
		_fail("a slid inbox is not the INBOX layer (top %d) with the keys live" % stack.top())
	_press(KEY_ESCAPE)
	if inbox.visible or not _main._windows.is_open("budget"):
		_fail("Escape did not slide the inbox back over the open tab")
	_clear_interrupt()


## A note is news, not a question: it waits in the inbox, which stays away.
func _check_a_note_does_not_slide_in() -> void:
	_main._windows.open("budget")
	_main._hud.inbox.slide_out()  # put away (G1: it rode over the tab)
	_main._hud.inbox.push("A note", "body")
	if _main._hud.inbox.visible:
		_fail("a note slid the inbox over the open tab")
	_main._windows.close_all()


## Answering slides the inbox back: the tab it came over is the player's again.
func _check_answer_slides_back() -> void:
	var inbox = _main._hud.inbox
	var card: String = _stage_interrupt_with("budget")
	var answer: Button = null
	for button in inbox._cards[card].find_children("*", "Button", true, false):
		if button.text != "X":
			answer = button
			break
	if answer == null:
		_fail("the decision row has no answer to press")
	else:
		answer.pressed.emit()
		if inbox.visible or not _main._windows.is_open("budget"):
			_fail("answering did not slide the inbox back over the open tab")
	_clear_interrupt()


## The parent's ruling on #54: the author's call 4 is "a decision that holds
## the clock", not only an interrupt. QA's smoke: `event ratings_letter` with the
## budget open held the clock and the inbox stayed hidden -- 56 of the 102 events
## hold at the default pause band.
func _check_an_ordinary_hold_slides_in() -> void:
	var clock: Node = _main.get_node("Clock")
	_stage_with("budget", ["ratings_letter"])
	if not clock.paused:
		_fail("ratings_letter did not hold the clock at the default pause band")
	if not _main._hud.inbox.is_slid():
		_fail("an ordinary holding arrival over a tab did not slide the inbox in")
	_clear_interrupt()


## QA's record on #54: answering one decision slid the inbox back while a second
## still held the clock. It stays until nothing holds.
func _check_answer_keeps_the_inbox_while_one_holds() -> void:
	var inbox = _main._hud.inbox
	var cards: Dictionary = _stage_with("budget", ["blackout_night", "ratings_letter"])
	_answer(String(cards.get("blackout_night", "")))
	if not inbox.is_slid():
		_fail("answering one decision slid the inbox away while another holds the clock")
	_answer(String(cards.get("ratings_letter", "")))
	if inbox.visible or not _main._windows.is_open("budget"):
		_fail("answering the last holding decision did not slide the inbox back")
	_clear_interrupt()


## The parent's ruling on #54: the clock ran behind "RE-ELECTED" -- Space toggled
## it under a modal scene. A scene owns the keyboard (c2.1's claim), Space too.
func _check_space_waits_under_a_scene() -> void:
	var clock: Node = _main.get_node("Clock")
	# Pausing, not starting: a new game sits at a term start with no programme,
	# where the Agenda guard refuses a start by hand whatever the stack says.
	_main._windows.close_all()
	clock.paused = false
	_main._windows.open("summit")
	_press(KEY_SPACE)
	if clock.paused:
		_fail("Space toggled the clock under a scene")
	_main._windows.close("summit")
	clock.paused = false


## Events staged on the desk with `tab` open, through the month's arrival path
## (no _enforce_interrupt); returns event id -> its row's id.
func _stage_with(tab: String, event_ids: Array) -> Dictionary:
	var Events := load("res://src/sim/events.gd")
	var ns = _main._state.player()
	_main._windows.close_all()
	ns.event_queue.clear()
	_main._unseen_events.clear()
	_main._event_cards.clear()
	_main._windows.open(tab)
	var month: int = Events._absolute_month(int(_main._state.year), int(_main._state.month))
	for event_id in event_ids:
		Events.announce(ns, Events.event_by_id(_main._loader, String(event_id)), month,
			Events.region_names(ns, _main._loader))
	_main._card_events(_main._state.year, _main._state.month, {}, {})
	var out := {}
	for card in _main._event_cards:
		out[String(_main._event_cards[card])] = String(card)
	return out


func _answer(card: String) -> void:
	var inbox = _main._hud.inbox
	if not inbox._cards.has(card):
		_fail("no decision row %s to answer" % card)
		return
	for button in inbox._cards[card].find_children("*", "Button", true, false):
		if button.text != "X":
			button.pressed.emit()
			return


## An interrupt staged on the desk with `tab` open; returns its row's id.
func _stage_interrupt_with(tab: String) -> String:
	var Events := load("res://src/sim/events.gd")
	var ns = _main._state.player()
	var interrupt_ev = Events.event_by_id(_main._loader, "blackout_night")
	_main._windows.close_all()
	ns.event_queue.clear()
	_main._unseen_events.clear()
	_main._event_cards.clear()
	_main._windows.open(tab)
	var month: int = Events._absolute_month(int(_main._state.year), int(_main._state.month))
	Events.announce(ns, interrupt_ev, month, Events.region_names(ns, _main._loader))
	_main._card_events(_main._state.year, _main._state.month, {}, {})
	_main._enforce_interrupt()
	for id in _main._event_cards:
		return String(id)
	return ""


func _clear_interrupt() -> void:
	_main._state.player().event_queue.clear()
	_main._unseen_events.clear()
	_main._paused_for_decision = false
	_main.get_node("Clock").paused = false
	_main._hud.inbox.slide_out()
	_main._windows.close_all()


func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE and child.is_visible_in_tree():
			return child
		var deeper := _first_focusable(child)
		if deeper != null:
			return deeper
	return null


func _press(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_main._unhandled_input(event)


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_shell_stack: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
