extends RefCounted

## The phone's wiring -- V5.2b b3: the call dialog to Systems' Phone.options() /
## Phone.dial() (src/sim/phone.gd). Two doors open it: a request card's
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
const Phone = preload("res://src/sim/phone.gd")
const President = preload("res://src/sim/president.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const AudienceVerbs = preload("res://src/ui/audience_verbs.gd")
const Feelings = preload("res://src/ui/feelings.gd")

static var _games := {}


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
	if game.is_empty() or main._state == null:
		return
	var state = main._state
	var ns = state.player()
	var o := Phone.options(state, ns, main._loader, person_id)
	var request := Audiences.request(ns, String(o["request_id"]))
	game["person_id"] = person_id
	game["was_paused"] = main._clock.paused
	main._clock.paused = true
	# No open request, nothing to ask: the levers are left off (each would only
	# repeat "nothing to ask about"), and the dialog says why there are none.
	game["dialog"].open({"name": main._loader.person_name(person_id), "why_not": String(o["why_not"]),
		"levers": o["levers"] if String(o["request_id"]) != "" else [], "topics": o["topics"],
		"stance": String(request.get("stance", "")), "president": main._loader.person_name(President.leader_id(ns)),
		"ask": PersonCard.object_text(main._loader, ns, String(request["object"]), request) if not request.is_empty() else "",
		"choices": {"now": int(state.year) * 12 + int(state.month), "people": people,
			"given_due": AudienceVerbs.given_due(ns, person_id, String(request.get("object", ""))), "feel": Feelings.of(ns, person_id)}})
	main._hud.clock_cluster.refresh(main._clock, HoldReason.show(main))


## After a load: a call up over the discarded game is put down -- its rows were
## that game's, and a press would dial the loaded one (QA on #125). The clock is
## left to the load, which owns it now.
static func after_load(main) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	if game.is_empty() or String(game["person_id"]).is_empty():
		return
	game["dialog"].hide()
	game["person_id"] = ""
	main._hud.clock_cluster.refresh(main._clock, HoldReason.show(main))


static func _dial(main, game: Dictionary, what: String, args: Dictionary) -> void:
	if String(game["person_id"]).is_empty():
		return
	var state = main._state
	var r := Phone.dial(state, state.player(), main._loader, String(game["person_id"]), what, args)
	var text := ""
	var titles: Array = []
	if not bool(r.get("ok", false)):
		text = Words.reason(String(r.get("error", "")))
	else:
		var paid := Words.paid_text(r.get("spent", {}), r.get("effects", {}), main._loader.person_name, Feelings.of(state.player(), String(game["person_id"])))
		if LK.LEVERS.has(what):
			var won := bool(r.get("success", false))
			text = Strings.t("They agree: the request is answered by phone.") if won else Strings.t("They are not moved. The request stays open.")
			if paid != "":
				text += " " + Words.changed(paid)
			# The lever's own line, then the call's close (Content's #126).
			titles = ["lever_" + what + ("_success" if won else "_failure"),
				("phone_close_promised" if what == "promise_date" else "phone_close_settled") if won else "phone_close_unresolved"]
		else:
			text = Words.changed(paid)
			titles = ["topic_" + what]
	game["dialog"].show_result(text, titles, {"lever": Words.lever(what), "topic": Words.topic(what)})
	game["on_change"].call()
	main._windows.mark_all_dirty()


static func _hang_up(main, game: Dictionary) -> void:
	game["dialog"].hide()
	game["person_id"] = ""
	if not bool(game["was_paused"]) and not main._decision_holds_clock():
		main._clock.paused = false
	main._hud.clock_cluster.refresh(main._clock, HoldReason.show(main))
