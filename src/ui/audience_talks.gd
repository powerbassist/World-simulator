extends RefCounted

## The audience itself, wired -- V5.2b b2: the scene's verbs to Levers' commands
## (open, attempt, talk, close) and the month's verdicts on the promises to cards.
## audience_driver.gd keeps the lane, the booking and the game's record (`game`,
## handed in, so neither file preloads the other); this one keeps the session.
##
## The session is Levers': a Dictionary the sim returns from open() and is handed
## back on every call, never written here and never saved (spec C11). The scene
## gets only what the sim reads back -- offered() and topics() after every verb --
## so a range narrows on screen because the register moved, not because the UI
## guessed.

const Levers = preload("res://src/sim/levers.gd")
const President = preload("res://src/sim/president.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const Words = preload("res://src/ui/lever_words.gd")
const Strings = preload("res://src/ui/strings.gd")
const HoldReason = preload("res://src/ui/hold_reason.gd")
const Capital = preload("res://src/core/capital.gd")

const WINDOW := "audience"


## The booked day: Levers opens the session (and holds the request); the scene
## owns the screen and the clock. `row` is the lane's row for the request.
static func open(main, game: Dictionary, row: Dictionary) -> bool:
	var ns = main._state.player()
	var session := Levers.open(main._state, ns, main._loader, String(row["id"]))
	if session.is_empty():
		return false
	game["session"] = session
	game["state"] = main._state
	main._save_load_panel.block_save(Strings.t("Finish the audience first"))
	var view := view_of(main, game)
	view.merge(row)
	view["president"] = main._loader.person_name(String(ns.head_of_state_person_id if ns.head_of_state_kind == "executive_president" else ns.pm_person_id))
	view["name"] = row["person"]  # i18n: row-ok the person's shown name, from the loader
	main._windows.open(WINDOW)
	main._clock.paused = true
	game["scene"].open(view)
	main._hud.clock_cluster.refresh(main._clock, HoldReason.show(main))
	return true


## What the scene shows, read off the sim as it stands now.
static func view_of(main, game: Dictionary) -> Dictionary:
	var state = main._state
	var ns = state.player()
	var loader = main._loader
	var session: Dictionary = game["session"]
	var pid := String(session["person_id"])
	var traits: Array = []
	var person = loader.person_by_id.get(pid)
	if person != null:
		for t in Levers.known_traits(ns, person):
			traits.append(Strings.t(String(PersonCard.TRAIT_LABEL.get(t, t))))  # i18n: row-ok a trait id, its label the msgid
	var people: Array = []
	for p in loader.people.get(String(ns.id), []):
		var id := String(p.id)
		if id != pid and President.covers(state, ns, loader, id):
			var shown: String = loader.person_name(id)
			people.append({"id": id, "name": shown, "know": President.knowledge(ns, id), "key": Capital.fold(shown)})
	# The people the president knows first, then by name (QA on #117: in loader
	# order the list was a screen of strangers before anyone useful). The key is
	# folded for case AND accents: a code-point compare puts "Élise" after "Zoé".
	people.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["know"] > b["know"] or (a["know"] == b["know"] and String(a["key"]) < String(b["key"])))
	return {"fog": President.knowledge_band(ns, pid), "traits": traits,
		"offered": Levers.offered(state, ns, loader, session), "topics": Levers.topics(state, ns, loader, session),
		"attempts_left": int(session["attempts_left"]),
		"choices": {"now": int(state.year) * 12 + int(state.month), "people": people}}


static func attempt(main, game: Dictionary, lever: String, args: Dictionary) -> void:
	var session: Dictionary = game.get("session", {})
	if session.is_empty():
		return
	var r := Levers.attempt(main._state, main._state.player(), main._loader, session, lever, args)
	if not bool(r["ok"]):
		game["scene"].show_result(Words.reason(String(r["error"])), view_of(main, game), "")
		return
	var said := Strings.t("They agree.") if bool(r["success"]) else Strings.t("They are not moved.")
	var paid := Words.paid_text(r["spent"], r["effects"], main._loader.person_name)
	game["scene"].show_result(said + " " + Words.changed(paid) if paid != "" else said, view_of(main, game),
		"lever_%s_%s" % [lever, "success" if bool(r["success"]) else "failure"], {"lever": Words.lever(lever)})
	main._windows.mark_all_dirty()


static func talk(main, game: Dictionary, topic: String, args: Dictionary) -> void:
	var session: Dictionary = game.get("session", {})
	if session.is_empty():
		return
	var r := Levers.talk(main._state, main._state.player(), main._loader, session, topic, args)
	if not bool(r["ok"]):
		game["scene"].show_result(Words.reason(String(r["error"])), view_of(main, game), "")
		return
	game["scene"].show_result(Words.changed(Words.paid_text({}, r["effects"], main._loader.person_name)), view_of(main, game),
		"topic_" + topic, {"topic": Words.topic(topic)})


## End: the sim closes the audience (a lever won settles it; none, and it is a
## decline priced once) and the scene says how it ended. The scene stays up.
static func end(main, game: Dictionary) -> void:
	var session: Dictionary = game.get("session", {})
	if session.is_empty() or bool(session.get("closed", false)):
		return
	var r := Levers.close(main._state, main._state.player(), main._loader, session)
	var text := Words.outcome(String(r["outcome"]))
	if String(r["outcome"]) == "declined":
		text += " " + Strings.t("Declining: %s.") % Words.price_text(r.get("price", {}))
	game["scene"].show_close(String(r["outcome"]), text)
	main._windows.mark_all_dirty()


## The scene comes down -- Leave, or the frame's X at any point (then the audience
## ends as End would, priced once). True when a session was closed here.
static func leave(main, game: Dictionary) -> bool:
	var session: Dictionary = game.get("session", {})
	if session.is_empty():
		return false
	# The session's own game: after a load main._state is the loaded one, and the
	# discarded game's audience is closed in the game it was opened in.
	var state = game.get("state", main._state)
	if not bool(session.get("closed", false)):
		Levers.close(state, state.player(), main._loader, session)
	game["session"] = {}
	main._save_load_panel.block_save("")
	game["scene"].close_scene()
	main._windows.close(WINDOW)
	if state == main._state and not main._decision_holds_clock():
		main._clock.paused = false
	main._hud.clock_cluster.refresh(main._clock, HoldReason.show(main))
	main._windows.mark_all_dirty()
	return true


## What the person wants, as the lane says it ("opposes The Sworn Offices"): a
## promise or an IOU is on that want, and its object alone reads backwards for
## an opposed one.
static func want_words(main, person_id: String, object: String) -> String:
	var ns = main._state.player()
	var person = main._loader.person_by_id.get(person_id)
	var stance := ""
	if person != null:
		for w in person.wants:
			if String(w["object"]) == object:
				stance = String(w["stance"])
	var thing := PersonCard.object_text(main._loader, ns, object, {"object": object})
	return "%s %s" % [Strings.t(PersonCard.stance_label(stance)), thing] if stance != "" else thing


## The month's verdicts on the promises and IOUs that fell due (Levers.tick_month,
## the report's `commitments`): a card each, kept or broken. A void row -- a want
## the content no longer carries -- was never priced and says nothing.
static func card_verdicts(main, report: Dictionary) -> void:
	var judged: Dictionary = report.get("commitments", {})
	for kept in [true, false]:
		for row in judged.get("kept" if kept else "broken", []):
			var who: String = main._loader.person_name(String(row["person_id"]))
			var want := want_words(main, String(row["person_id"]), String(row["object"]))
			main._hud.inbox.push(Strings.t("Your word"), Words.verdict_text(String(row["kind"]), kept, who, want))
