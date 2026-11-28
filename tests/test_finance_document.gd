extends SceneTree

## Headless test: godot --headless --script res://tests/test_finance_document.gd
## Non-zero exit on any failure.
##
## The finance bill's DOCUMENT in the running game (the author's pick C, 2026-11-28): the review surface is on the
## screen stack at SCENE, over the page and its scroll bar. P1 (the parent's ruling): the clock holds while it is
## open and comes back as it was -- running stays running, a player's pause stays a pause, a pending decision keeps
## its hold, however it is put away. A load rebuilds the game, so no document is carried into it. And the layout: it
## hugs, never wider or taller than its margins, and a long draft scrolls its list while the title and the foot stay;
## the keyboard stays inside it.

const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const ScreenStack = preload("res://src/ui/screen_stack.gd")
const SaveManager = preload("res://src/core/save_manager.gd")

const SLOT := "test_finance_document"

var _failures: Array[String] = []
var _main


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(3)
	_main._windows.open("finances")
	await _frames(3)
	await _check_a_running_clock_holds_and_comes_back()
	await _check_a_players_pause_stays()
	await _check_a_tabling_gives_the_clock_back()
	await _check_the_last_cross_and_discard_close_it()
	await _check_the_last_cross_with_share_moves_lands_on_discard()
	await _check_a_surplus_caption_is_one_line()
	await _check_a_pending_decision_keeps_the_hold()
	await _check_it_hugs_and_a_long_draft_scrolls()
	await _check_the_keyboard_stays_inside()
	await _check_a_load_keeps_the_loads_clock()
	for failure in _failures:
		print("FAIL ", failure)
	print("test_finance_document: %s" % ("FAILED (%d)" % _failures.size() if not _failures.is_empty() else "ok"))
	quit(1 if not _failures.is_empty() else 0)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _page():
	return _main._windows.content("finances")


func _doc() -> Control:
	return _page()._sheet


func _named(node_name: String) -> Button:
	return _doc().find_child(node_name, true, false) as Button


func _crosses() -> Array:
	return _doc().find_children("*", "BaseButton", true, false).filter(func(b) -> bool: return b.has_meta("drop"))


## `rows` [[channel, key, step]] drafted from the live register, then the page's own repaint.
func _draft(rows: Array) -> void:
	var draft = _page().shared_draft()
	draft.revert()
	for row in rows:
		draft.set_value(row[0], row[1], draft.live(row[0], row[1]) + float(row[2]))
	_page()._on_structure_changed()
	await _frames(3)


func _two() -> void:
	await _draft([[FinanceDraft.SPENDING, "health", 1.5], [FinanceDraft.TAX, "vat", 2.0]])


func _review() -> Button:
	return _page().rail().find_child("Review", true, false) as Button


## Opened by the rail's own button, with the clock `paused` before the press.
func _open(paused: bool) -> void:
	_main._clock.paused = paused
	_review().grab_focus()
	_review().pressed.emit()
	await _frames(3)
	if not _doc().visible:
		_fail("Review the bill did not open the document")


func _expect_closed(leg: String, paused: bool) -> void:
	if _doc().visible:
		_fail("%s: the document is still open" % leg)
	if _main._clock.paused != paused:
		_fail("%s: the clock is paused %s, want %s" % [leg, _main._clock.paused, paused])
	if _main._stack.top() >= ScreenStack.SCENE:
		_fail("%s: the screen stack still holds a scene" % leg)


func _check_a_running_clock_holds_and_comes_back() -> void:
	await _two()
	await _open(false)
	if not _main._stack.is_ancestor_of(_doc()) or _main._stack.top() != ScreenStack.SCENE:
		_fail("the document is not the screen stack's scene (top %d)" % _main._stack.top())
	if not _main._clock.paused:
		_fail("the clock runs under the open document")
	# No door starts it while the document is up: Space, a speed.
	_main._toggle_pause_by_hand()
	_main._set_speed_by_hand(2)
	if not _main._clock.paused:
		_fail("a hand started the clock under the open document")
	_named("SheetClose").pressed.emit()
	await _frames(2)
	_expect_closed("Close on a running clock", false)
	if _main.get_viewport().gui_get_focus_owner() != _review():
		_fail("Close does not give the keyboard back to Review")
	await _open(false)
	_named("SheetCross").pressed.emit()
	await _frames(2)
	_expect_closed("the title's cross", false)
	# Hidden by anything else (the page rebinding, a stray hide()): the hold goes with it.
	await _open(false)
	_doc().hide()
	await _frames(2)
	_expect_closed("a bare hide", false)


func _check_a_players_pause_stays() -> void:
	await _two()
	await _open(true)
	if not _main._stack.cancel():
		_fail("Escape does not put the document away")
	await _frames(2)
	_expect_closed("Escape on a player's pause", true)
	if _page().shared_draft().count() != 2:
		_fail("Escape lost the draft")


func _check_a_tabling_gives_the_clock_back() -> void:
	await _two()
	await _open(false)
	_named("SheetTable").pressed.emit()
	await _frames(3)
	_expect_closed("a tabling", false)
	if _main._state.player().tabled_bill.is_empty():
		_fail("premise: the document's verb tabled nothing")
	_page()._on_withdraw()
	_main._state.player().tabled_bill = {}
	await _frames(2)


## The last change taken out empties the draft: the document closes by itself, and so on Discard all.
func _check_the_last_cross_and_discard_close_it() -> void:
	await _draft([[FinanceDraft.SPENDING, "health", 1.5], [FinanceDraft.SPENDING, "education", -0.5], [FinanceDraft.TAX, "vat", 2.0]])
	await _open(false)
	if _crosses().size() != 3:
		_fail("%d remove marks for 3 changes" % _crosses().size())
		return
	# A middle one: the keyboard goes to the mark now in its place.
	_crosses()[1].grab_focus()
	_crosses()[1].pressed.emit()
	await _frames(3)
	var marks := _crosses()
	if marks.size() != 2 or _main.get_viewport().gui_get_focus_owner() != marks[1]:
		_fail("after a middle remove the keyboard is not on the next mark (%d marks)" % marks.size())
	# The last row: the previous mark.
	marks[1].pressed.emit()
	await _frames(3)
	marks = _crosses()
	if marks.size() != 1 or _main.get_viewport().gui_get_focus_owner() != marks[0]:
		_fail("after the last row's remove the keyboard is not on the previous mark")
		return
	if not _main._clock.paused:
		_fail("a remove inside the open document ran the clock")
	marks[0].pressed.emit()
	await _frames(3)
	_expect_closed("the last remove mark", false)
	await _two()
	await _open(false)
	_named("SheetDiscard").pressed.emit()
	await _frames(3)
	_expect_closed("Discard all", false)
	if not _page().shared_draft().is_empty():
		_fail("Discard all kept the draft")


## The parent's ruling on #468: the last change taken out while share moves are drafted leaves the keyboard on the
## rail's "Discard all", as the rail's own mark does, never on "Apply the moves", where Enter books them with no vote.
func _check_the_last_cross_with_share_moves_lands_on_discard() -> void:
	await _draft([[FinanceDraft.TAX, "vat", 2.0]])
	var draft = _page().shared_draft()
	draft.add_move("health", "hospitals", "prevention", 0.02)
	_page()._on_structure_changed()
	await _frames(3)
	await _open(false)
	if _crosses().size() != 1:
		_fail("premise: %d remove marks for 1 change and a share move" % _crosses().size())
		return
	_crosses()[0].grab_focus()
	_crosses()[0].pressed.emit()
	await _frames(3)
	_expect_closed("the last remove mark with a share move drafted", false)
	var held: Control = _main.get_viewport().gui_get_focus_owner()
	if held == null or held != _page().rail().find_child("Discard", true, false):
		_fail("with a share move left the keyboard is on %s, want Discard all" % (held.name if held != null else "nothing"))
	if draft.moves().size() != 1:
		_fail("taking out the last change lost or booked the share move (%d left)" % draft.moves().size())
	draft.revert()
	_page()._on_structure_changed()
	await _frames(2)


## "Deficit -> surplus, a year" is the longest caption: it keeps one line under its figure.
func _check_a_surplus_caption_is_one_line() -> void:
	await _draft([[FinanceDraft.SPENDING, "pensions", -8.0]])
	await _open(true)
	var captions: Array = _doc().find_child("SheetTotals", true, false).get_children().slice(2).map(
		func(box) -> Label: return box.get_child(1))
	if not (captions[0] as Label).text.begins_with("Deficit → surplus"):
		_fail("premise: the bill does not end in surplus (%s)" % (captions[0] as Label).text)
	for caption in captions:
		if (caption as Label).get_line_count() != 1:
			_fail("'%s' runs on %d lines" % [(caption as Label).text, (caption as Label).get_line_count()])
	_named("SheetClose").pressed.emit()
	await _frames(2)


func _check_a_pending_decision_keeps_the_hold() -> void:
	await _two()
	await _open(false)
	_main._paused_for_decision = true
	_main._unseen_events = {"probe": true}
	_named("SheetClose").pressed.emit()
	await _frames(2)
	_expect_closed("a decision waiting at the close", true)
	_main._paused_for_decision = false
	_main._unseen_events = {}


func _check_it_hugs_and_a_long_draft_scrolls() -> void:
	await _two()
	await _open(true)
	var view: Vector2 = _main.get_viewport().get_visible_rect().size
	var short := _doc().size.y
	if not is_equal_approx(_doc().size.x, minf(1080.0, view.x - 48.0)):
		_fail("the document is %s wide, want 1080" % _doc().size.x)
	if absf(short - _doc().get_combined_minimum_size().y) > 0.5 or short > 620.0:
		_fail("the document does not hug two changes: %s tall" % short)
	_check_the_list_whole("two changes")
	print("two changes: %s in %s" % [_doc().size, view])
	_named("SheetClose").pressed.emit()
	await _frames(2)
	var ns = _main._state.player()
	var rows := []
	for key in ns.spending_pct_gdp:
		rows.append([FinanceDraft.SPENDING, String(key), 0.5])
	for key in ns.tax_rates_pct:
		if float(ns.tax_rates_pct[key]) > 0.0:
			rows.append([FinanceDraft.TAX, String(key), 0.1])
	# Every line and every tax in force: more rows than the screen holds (the canvas is never shorter than 1080,
	# interface_size.gd), so the cap bites.
	await _draft(rows)
	await _open(true)
	await _frames(3)
	view = _main.get_viewport().get_visible_rect().size
	var box := _doc().get_global_rect()
	var verb := _named("SheetTable")
	if box.position.y < 39.5 or box.end.y > view.y - 39.5:
		_fail("%d changes: the document runs %s in a %s screen" % [rows.size(), box, view])
	if verb == null or not box.encloses(verb.get_global_rect()):
		_fail("a long draft: the filled verb is not on the document")
	var list := _doc().find_child("SheetList", true, false) as ScrollContainer
	if list == null or list.get_v_scroll_bar().max_value <= list.size.y or list.size.y < 200.0:
		_fail("%d changes: the list does not scroll in place (%s)" % [rows.size(), list.size if list else Vector2.ZERO])
	# A taller screen gives the room back to the list.
	var capped := list.size.y
	root.size = Vector2i(1920, 1400)
	await _frames(4)
	if list.size.y <= capped:
		_fail("a taller screen does not give the list more room (%s then %s)" % [capped, list.size.y])
	root.size = Vector2i(1920, 1080)
	await _frames(4)
	if not is_equal_approx(list.size.y, capped):
		_fail("the list does not come back to its cap (%s, was %s)" % [list.size.y, capped])
	_named("SheetClose").pressed.emit()
	await _frames(2)


## With room to spare, the list shows every row: no bar, nothing cut.
func _check_the_list_whole(leg: String) -> void:
	var list := _doc().find_child("SheetList", true, false) as ScrollContainer
	var rows: Control = list.get_child(0) if list != null else null
	if rows == null or list.size.y + 0.5 < rows.get_combined_minimum_size().y:
		_fail("%s: the list is cut (%s of %s)" % [leg, list.size.y if list else -1.0, rows.get_combined_minimum_size().y if rows else -1.0])


## Every arrow, from every button of the document, lands in the document: Godot gives an unpinned one to the closest
## control in that direction, which may be one under the dim.
func _check_the_arrows_stay_inside(leg: String) -> void:
	for start in _doc().find_children("*", "BaseButton", true, false):
		for key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			(start as Control).grab_focus()
			for down in [true, false]:
				var event := InputEventKey.new()
				event.keycode = key
				event.physical_keycode = key
				event.pressed = down
				root.push_input(event)
			var at := root.gui_get_focus_owner()
			if at == null or not _doc().is_ancestor_of(at):
				_fail("%s: %s from '%s' leaves the document for %s" % [leg, OS.get_keycode_string(key), start.get("text"),
					at.name if at != null else "nothing"])
				return


## Tab walks every remove mark, the box and the verbs, and never leaves the document.
func _check_the_keyboard_stays_inside() -> void:
	await _two()
	await _open(true)
	var start := _main.get_viewport().gui_get_focus_owner() as Control
	if start != _named("SheetTable"):
		_fail("the document opens with the keyboard off its filled verb")
		return
	var seen: Array = [start]
	var at: Control = start
	for i in 20:
		at = at.find_next_valid_focus()
		if at == null or seen.has(at):
			break
		seen.append(at)
		if not _doc().is_ancestor_of(at):
			_fail("Tab leaves the document for %s" % at.name)
			break
	var wanted: Array = _crosses() + [_named("SheetCross"), _named("SheetDiscard"), _named("SheetClose"), _doc().find_child("Force", true, false)]
	for node in wanted:
		if not seen.has(node):
			_fail("Tab does not reach %s" % (node.name if node != null else "<missing>"))
	_check_the_arrows_stay_inside("as opened")
	(_doc().find_child("Force", true, false) as CheckBox).button_pressed = true  # rebuilds the verbs
	await _frames(2)
	_check_the_arrows_stay_inside("with the force box ticked")
	_named("SheetClose").pressed.emit()
	await _frames(2)


func _check_a_load_keeps_the_loads_clock() -> void:
	await _two()
	await _open(false)
	var error := SaveManager.save_game(_main._state, _main._clock, SLOT)
	if error != "":
		_fail("premise: could not save: %s" % error)
		return
	var old = _main
	_main = _main._on_load_requested(SLOT)
	await _frames(4)
	SaveManager.delete_slot(SLOT)
	if _main == old:
		_fail("premise: the load did not rebuild the game")
		return
	if not _main._clock.paused:
		_fail("a load with the document open did not leave the loaded clock paused")
	if _doc().visible or _main._stack.top() >= ScreenStack.SCENE:
		_fail("a load carried the document into the loaded game")


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("FAIL: " + message)
