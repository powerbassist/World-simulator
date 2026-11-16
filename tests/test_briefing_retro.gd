extends SceneTree

## Headless test: godot --headless --script res://tests/test_briefing_retro.gd
## Non-zero exit on any failure.
##
## The chief's mark and voice, three finds of the retro UI review (2026-11-17):
##   - item 13: a line queued behind another voice was gated on the caption, which hides
##     on its reading timer, so a long messenger's clip silenced the chief. It is gated on
##     the mark, which stays up for the month;
##   - item 14: the mark re-ranked only when an inbox card closed, so a dispatch answered
##     in its window (or a request declined in the lane) left the mark naming it;
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
const STALE := {"kind": "stale", "subject": "stale", "standing": false, "held": false}

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
			_check_answers_outside_the_inbox_rerank()
			var error := SaveManager.save_game(_main._state, _main._clock, SLOT)
			if error != "":
				_fail("could not save: %s" % error)
				return _end()
		4:
			_main._on_load_requested(SLOT)
		6:
			_check_load_forgets_the_ranking()
			_cleanup()
			_main.queue_free()
		8:
			_finish()
			return true
	return false


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
	player.stop()
	player.set_meta("pending", false)


func _check_answers_outside_the_inbox_rerank() -> void:
	_game()["lines"] = [STALE]
	_main._events_panel.acted.emit({}, "an answer in Dispatches")
	if (_game()["lines"] as Array).has(STALE):
		_fail("an answer in the Dispatches window did not re-rank the chief's mark")
	_game()["lines"] = [STALE]
	var lane = preload("res://src/ui/audience_driver.gd")._games[_main.get_instance_id()]["lane"]
	lane.decline_requested.emit("__no_such_request__")
	if (_game()["lines"] as Array).has(STALE):
		_fail("a request declined in the lane did not re-rank the chief's mark")


func _check_load_forgets_the_ranking() -> void:
	var game := _game()
	if game.has("memory_before") or game.has("report"):
		_fail("a load keeps the discarded game's ranking memory or report")
	_main._hud.inbox.card_closed.emit("__any__")
	if _main._hud.title_bar.chief_mark.visible:
		_fail("a card closed after a load put the discarded game's mark back up")


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
