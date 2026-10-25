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
const DialogueLines = preload("res://src/ui/dialogue_lines.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AudienceVerbs = preload("res://src/ui/audience_verbs.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const Shadows = preload("res://src/sim/shadows.gd")

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
	view["opening_title"] = DialogueLines.opening_title(ns, Audiences.request(ns, String(row["id"])))
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
	return {"fog": President.knowledge_band(ns, pid), "traits": traits,
		"offered": Levers.offered(state, ns, loader, session), "topics": Levers.topics(state, ns, loader, session),
		"attempts_left": int(session["attempts_left"]),
		"choices": {"now": int(state.year) * 12 + int(state.month), "people": gossip_people(main, pid),
			"given_due": AudienceVerbs.given_due(ns, pid, String(session["object"])), "feel": Feelings.of(ns, pid)},
		# V5.2c: the money on the table and the affair, as Shadows reads them now.
		"shadow": {"offer": Shadows.offer(ns, session), "kind": String(person.kind) if person != null else "",
			# Accept's refusals that are the scene's own state (Shadows.accept_offer's
			# reasons, its sentences): the button is down with them, never a dead press.
			"offer_why": "they have already agreed" if String(session.get("won", "")) != "" else ("no attempts left" if int(session["attempts_left"]) <= 0 else ""),  # i18n: ok the sim's reasons (shadows.gd), shown through Words.reason
			"affair_why": Shadows.may_begin_affair(state, ns, loader, pid),
			"flirted": (session["used_topics"] as Array).has("flirt"), "lovers": President.relationship(ns, pid) == "affair"}}


## The person spoken to, as the registers stand now (R11's words).
static func _feel(main, session: Dictionary) -> Dictionary:
	return Feelings.of(main._state.player(), String(session["person_id"]))


## Whom a gossip may name: everyone the president covers but the person spoken
## to, the people the president knows first, then by name (QA on #117: in loader
## order the list was a screen of strangers before anyone useful). The key is
## folded for case AND accents: a code-point compare puts "Élise" after "Zoé".
static func gossip_people(main, pid: String) -> Array:
	var state = main._state
	var ns = state.player()
	var loader = main._loader
	var people: Array = []
	for p in loader.people.get(String(ns.id), []):
		var id := String(p.id)
		if id != pid and President.covers(state, ns, loader, id):
			var shown: String = loader.person_name(id)
			people.append({"id": id, "name": shown, "know": President.knowledge(ns, id), "key": Capital.fold(shown)})
	people.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["know"] > b["know"] or (a["know"] == b["know"] and String(a["key"]) < String(b["key"])))
	return people


static func attempt(main, game: Dictionary, lever: String, args: Dictionary) -> void:
	var session: Dictionary = game.get("session", {})
	if session.is_empty():
		return
	var r := Levers.attempt(main._state, main._state.player(), main._loader, session, lever, args)
	if not bool(r["ok"]):
		game["scene"].show_result(Words.reason(String(r["error"])), view_of(main, game), "")
		return
	var said := Strings.t("They agree.") if bool(r["success"]) else Strings.t("They are not moved.")
	if bool(r.get("caught", false)):
		said += " " + Strings.t("They caught the lie.")
	var paid := Words.paid_text(r["spent"], r["effects"], main._loader.person_name, _feel(main, session))
	game["scene"].show_result(said + " " + Words.changed(paid) if paid != "" else said, view_of(main, game),
		lever_title(lever, args, r), {"lever": Words.lever(lever)})
	main._windows.mark_all_dirty()


## The person's line after a lever: a lie caught or swallowed is answered as one;
## a corrupt currency has its own lines (Content's lever_bargain_<currency>_*).
static func lever_title(lever: String, args: Dictionary, r: Dictionary) -> String:
	if bool(r.get("caught", false)):
		return "lie_caught"
	if bool(args.get("lie", false)):
		return "lie_uncaught"
	var how := "success" if bool(r.get("success", false)) else "failure"
	var currency := String(args.get("currency", ""))
	if lever == "bargain" and Shadows.is_currency(currency):
		return "lever_bargain_%s_%s" % [currency, how]
	return "lever_%s_%s" % [lever, how]


## The money on the table, answered (Shadows.accept_offer / refuse_offer): the
## person's reply in Content's offer_accept_ / offer_refuse_ lines, what it wrote.
static func offer(main, game: Dictionary, accepted: bool) -> void:
	var session: Dictionary = game.get("session", {})
	if session.is_empty():
		return
	var ns = main._state.player()
	var o := Shadows.offer(ns, session)
	var person = main._loader.person_by_id.get(String(session["person_id"]))
	var title := ("offer_accept_%s_%s" if accepted else "offer_refuse_%s_%s") % [String(person.kind) if person != null else "", String(o.get("currency", ""))]
	var r := Shadows.accept_offer(main._state, ns, main._loader, session) if accepted else Shadows.refuse_offer(main._state, ns, main._loader, session)
	if not bool(r["ok"]):
		game["scene"].show_result(Words.reason(String(r["error"])), view_of(main, game), "")
		return
	var spent: Dictionary = (r.get("paid", {}) as Dictionary).duplicate()
	if float(r.get("evidence", 0.0)) > 0.0:
		spent["evidence"] = float(r["evidence"])
	var paid := Words.paid_text(spent, {"rapport": float(r.get("rapport", 0.0))}, main._loader.person_name, _feel(main, session))
	var said := Strings.t("You take it.") if accepted else Strings.t("You turn it down.")
	game["scene"].show_result(said + " " + Words.changed(paid) if paid != "" else said, view_of(main, game), title)
	main._windows.mark_all_dirty()


## An affair proposed or ended (Shadows.begin_affair / end_affair). A refused
## proposal is the person's to explain: their affair_why_<reason> line, and the
## reason as the result.
static func affair(main, game: Dictionary, action: String) -> void:
	var session: Dictionary = game.get("session", {})
	if session.is_empty():
		return
	var pid := String(session["person_id"])
	var state = main._state
	var r := Shadows.begin_affair(state, state.player(), main._loader, pid) if action == "propose" else Shadows.end_affair(state, state.player(), main._loader, pid)
	if not bool(r["ok"]):
		var why := String(r["error"])
		game["scene"].show_result(Words.reason(why), view_of(main, game), "affair_why_" + why)
		return
	var paid := Words.paid_text({}, {"rapport": float(r.get("rapport", 0.0))}, main._loader.person_name, _feel(main, session))
	var said := Strings.t("It begins, and no one must know.") if action == "propose" else Strings.t("It is over.")
	game["scene"].show_result(said + " " + Words.changed(paid) if paid != "" else said, view_of(main, game),
		"affair_begin" if action == "propose" else "affair_end")
	main._windows.mark_all_dirty()


static func talk(main, game: Dictionary, topic: String, args: Dictionary) -> void:
	var session: Dictionary = game.get("session", {})
	if session.is_empty():
		return
	var r := Levers.talk(main._state, main._state.player(), main._loader, session, topic, args)
	if not bool(r["ok"]):
		game["scene"].show_result(Words.reason(String(r["error"])), view_of(main, game), "")
		return
	game["scene"].show_result(Words.changed(Words.paid_text({}, r["effects"], main._loader.person_name, _feel(main, session))), view_of(main, game),
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
		text += " " + Strings.t("Declining: %s.") % Words.price_text(r.get("price", {}), _feel(main, session), true)
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
