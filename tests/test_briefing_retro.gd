extends SceneTree

## Headless test: godot --headless --script res://tests/test_briefing_retro.gd
## Non-zero exit on any failure.
##
## The chief's mark and voice, three finds of the retro UI review (2026-11-17):
##   - item 13: a line queued behind another voice was gated on the caption, which hides
##     on its reading timer, so a long messenger's clip silenced the chief. It is gated on
##     the mark, which stays up for the month;
##   - item 14: the mark re-ranked only when an inbox card closed, so a dispatch answered
##     in its window (or a request declined in the lane) left the mark naming it. Since #393
##     pass 2 (T1) every command re-ranks through the window manager's one sweep;
##   - item 5: a load kept the discarded game's ranking memory and report, so the first card
##     closed after it re-ranked from them and put the old game's mark back up.
## Driven through main.gd's real handlers, a frame at a time.

const SaveManager = preload("res://src/core/save_manager.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const ChiefMarkView = preload("res://src/ui/chief_mark_view.gd")
const Voice = preload("res://src/ui/voice.gd")
const Programme = preload("res://src/sim/programme.gd")

const SLOT := "__test_briefing_retro__"
## A line no ranking makes: still there after an answer, the mark was not re-ranked.
const STALE := {"kind": "stale", "subject": "stale", "standing": false, "held": false, "deadline_month": -1, "more": 0}

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			var offer: Array = Programme.available(_main._state, _main._state.player(), _main._loader)
			if not offer.is_empty():
				_main._on_programme_chosen(String(offer[0]["id"]))
			BriefingDriver.month_end(_main, {})
			if not _game().has("memory_before"):
				_fail("premise: a month end stored no ranking")
				return _end()
			_check_queued_line_outlives_the_caption()
			# The re-rank waits for the frame's end (one per frame, #393 pass 2 T1): each answer
			# is checked the frame after.
			_game()["lines"] = [STALE]
			_main._events_panel.acted.emit({}, "an answer in Dispatches")
		3:
			_check_reranked("an answer in the Dispatches window")
			_game()["lines"] = [STALE]
			var lane = preload("res://src/ui/audience_driver.gd")._games[_main.get_instance_id()]["lane"]
			lane.decline_requested.emit("__no_such_request__")
		4:
			_check_reranked("a request declined in the lane")
			# The one sink every command reaches (an audience's Grant, Counter, Money, End, the phone,
			# a law tabled, a budget committed): the window manager's sweep.
			_game()["lines"] = [STALE]
			_main._windows.mark_all_dirty()
		5:
			_check_reranked("a command's sweep of the windows")
			# #393 last pass 2, T1: a programme put in the finance bill is a command too.
			_game()["lines"] = [STALE]
			var sector = _main._windows.content("sector_industry")
			var list: Array = preload("res://src/ui/sector_programme.gd").stops(_main._loader, "industry")
			preload("res://src/ui/firm_commands.gd").invest(sector, list[list.size() - 1]["action"])
		6:
			_check_reranked("a programme put in the finance bill")
			# Under an open read the re-rank waits (its Go buttons index the lines shown); the
			# read's close runs it, or a file answered from the folder stays named on the mark.
			BriefingDriver.read(_main)
			_game()["lines"] = [STALE]
			_main._windows.mark_all_dirty()
		7:
			if not (_game()["lines"] as Array).has(STALE):
				_fail("premise: the re-rank ran under the open read")
			BriefingDriver.close(_main)
		8:
			_check_reranked("closing the read after a command under it")
			var error := SaveManager.save_game(_main._state, _main._clock, SLOT)
			if error != "":
				_fail("could not save: %s" % error)
				return _end()
		9:
			# The discarded game's ranking, which must not come back after the load.
			_game()["memory_before"] = {"last": [STALE]}
			_game()["lines"] = [STALE]
			_game()["report"] = {"stale": true}
			# T3: a consequence card held for the old game's month end.
			_game()["month_cards"] = [{"title": "old game", "body": "old game"}]
			_main = _main._on_load_requested(SLOT)
		11:
			_check_load_forgets_the_ranking()
			_game()["lines"] = [STALE]
			_main._hud.inbox.card_closed.emit("__any__")
		12:
			_check_reranked("a card closed after a load")
			if not _main._hud.title_bar.chief_mark.visible:
				_fail("a card closed after a load took the loaded game's mark down")
			_cleanup()
			_main.queue_free()
		14:
			_finish()
			return true
	return false


func _check_reranked(what: String) -> void:
	if (_game().get("lines", []) as Array).has(STALE):
		_fail("%s did not re-rank the chief's mark" % what)


func _game() -> Dictionary:
	return BriefingDriver._games.get(_main.get_instance_id(), {})


func _check_queued_line_outlives_the_caption() -> void:
	var player := _main.get_node_or_null(Voice.NODE) as AudioStreamPlayer
	if player == null:
		_fail("premise: the chief's first month said nothing (no voice node)")
		return
	# Another voice holds the line: a messenger's clip, longer than the caption's reading time.
	player.stop()
	player.set_meta("pending", true)
	player.set_meta("card", "messenger")
	ChiefMarkView.speak(_main, "retro-13")
	_main._hud.chief_caption.hide()  # its reading timer ran out while the messenger spoke
	player.set_meta("pending", false)
	Voice._next(_main, player, player.get_node(Voice.WAIT))
	if String(player.get_meta("card", "")) != BriefingDriver.LINE_CARD:
		_fail("the chief's line queued behind another voice was dropped when his caption hid")
	# #393 pass 2, T3: heard, so on screen -- the caption comes back when the queued line starts.
	if not _main._hud.chief_caption.visible or _main._hud.chief_caption.text() == "":
		_fail("the chief's queued line is heard with no caption on screen")
	player.stop()
	player.set_meta("pending", false)


## #393 pass 2, T2: the loaded game is ranked at the load from no memory, so the mark names
## its first line at once (not blank until the month's end), and nothing of the old ranking.
func _check_load_forgets_the_ranking() -> void:
	var game := _game()
	if game.has("month_cards"):
		_fail("a load keeps the discarded game's held consequence cards")
	if game.has("report") or game.get("memory_before", null) != {}:
		_fail("a load keeps the discarded game's ranking memory or report")
	if (game.get("lines", []) as Array).has(STALE):
		_fail("a load keeps the discarded game's lines")
	if not bool(_main._state.player().in_government):
		_fail("premise: the loaded player is out of government")
		return
	if not _main._hud.title_bar.chief_mark.visible:
		_fail("after a load the chief's mark is blank until the month's end")


func _end() -> bool:
	_cleanup()
	_finish()
	return true


func _cleanup() -> void:
	for p in [SaveManager._path_for(SLOT), SaveManager._path_for(SLOT) + SaveManager.TEMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_briefing_retro: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
