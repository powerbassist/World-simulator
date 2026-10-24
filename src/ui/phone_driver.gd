extends RefCounted

## The phone's wiring -- V5.2b b3: the call dialog to Systems' Phone.options() /
## Phone.dial() (v5.2b3-plan.md section 1). Two doors open it: a request card's
## "Call" answer, and a right click on a person in the People panel (that panel
## keeps no button, by its own rule). Static over main, as audience_driver.gd is.
##
## The UI writes nothing (AGENTS.md rule 2): options() says what may be tried and
## why not, dial() does it, and the card and lane are redrawn from what it left.
## A call holds the clock while the dialog is up, as the audience does, and lets
## it go on Close unless something else holds it.

const PhoneDialog = preload("res://src/ui/phone_dialog.gd")
const ScreenStack = preload("res://src/ui/screen_stack.gd")
const Words = preload("res://src/ui/lever_words.gd")
const Strings = preload("res://src/ui/strings.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const HoldReason = preload("res://src/ui/hold_reason.gd")

## Systems' module, resolved when it is there: the plan names its two commands
## and the UI is built against them before the module lands. No module, no call
## offered anywhere.
const PHONE := "res://src/sim/phone.gd"

## A test's stand-in for the module (tests/test_phone_ui.gd); null in the game.
static var backend = null
static var _games := {}


static func phone():
	if backend != null:
		return backend
	return load(PHONE) if ResourceLoader.exists(PHONE) else null


## `on_change` redraws what a call can move (the request lane, its mark).
static func register(main, on_change: Callable) -> void:
	var dialog := PhoneDialog.new()
	main._stack.add(ScreenStack.SCENE, dialog, true, dialog.close)
	dialog.hide()
	var game := {"dialog": dialog, "person_id": "", "was_paused": false, "on_change": on_change}
	_games[main.get_instance_id()] = game
	dialog.dialed.connect(func(what: String, args: Dictionary) -> void: _dial(main, game, what, args))
	dialog.closed.connect(func() -> void: _hang_up(main, game))


static func dialog_of(main) -> PhoneDialog:
	return _games.get(main.get_instance_id(), {}).get("dialog")


## Who is on the line, "" when no call is up: the clock's hold line names them.
static func calling(main) -> String:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	if game.is_empty() or String(game["person_id"]).is_empty():
		return ""
	return main._loader.person_name(String(game["person_id"]))


## The dialog for one person, on what the sim offers them now.
static func open_call(main, person_id: String, people: Array) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	var p = phone()
	if game.is_empty() or p == null or main._state == null:
		return
	var state = main._state
	var o: Dictionary = p.options(state, state.player(), main._loader, person_id)
	game["person_id"] = person_id
	game["was_paused"] = main._clock.paused
	main._clock.paused = true
	game["dialog"].open({"name": main._loader.person_name(person_id), "why_not": String(o.get("why_not", "")),
		"levers": o.get("levers", []), "topics": o.get("topics", []),
		"choices": {"now": int(state.year) * 12 + int(state.month), "people": people}})
	main._hud.clock_cluster.refresh(main._clock, HoldReason.show(main))


static func _dial(main, game: Dictionary, what: String, args: Dictionary) -> void:
	var p = phone()
	if p == null or String(game["person_id"]).is_empty():
		return
	var state = main._state
	var r: Dictionary = p.dial(state, state.player(), main._loader, String(game["person_id"]), what, args)
	var text := ""
	if not bool(r.get("ok", false)):
		text = Words.reason(String(r.get("error", "")))
	else:
		var paid := Words.paid_text(r.get("spent", {}), r.get("effects", {}), main._loader.person_name)
		if LK.LEVERS.has(what):
			text = Strings.t("They agree: the request is answered by phone.") if bool(r.get("success", false)) else Strings.t("They are not moved. The request stays open.")
			if paid != "":
				text += " " + Words.changed(paid)
		else:
			text = Words.changed(paid)
	game["dialog"].show_result(text)
	game["on_change"].call()
	main._windows.mark_all_dirty()


static func _hang_up(main, game: Dictionary) -> void:
	game["dialog"].hide()
	game["person_id"] = ""
	if not bool(game["was_paused"]) and not main._decision_holds_clock():
		main._clock.paused = false
	main._hud.clock_cluster.refresh(main._clock, HoldReason.show(main))
