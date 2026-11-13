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
const Shadows = preload("res://src/sim/shadows.gd")
const Deal = preload("res://src/sim/deal.gd")
const President = preload("res://src/sim/president.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const Words = preload("res://src/ui/lever_words.gd")
const MoodBadge = preload("res://src/ui/mood_badge.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Strings = preload("res://src/ui/strings.gd")
const HoldReason = preload("res://src/ui/hold_reason.gd")
const Capital = preload("res://src/core/capital.gd")
const DialogueLines = preload("res://src/ui/dialogue_lines.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AudienceView = preload("res://src/ui/audience_view.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")

const WINDOW := "audience"


## The booked day: Deal opens the session (and holds the request, the ask fixed on it);
## the scene owns the screen and the clock. `row` is the lane's row for the request.
static func open(main, game: Dictionary, row: Dictionary) -> bool:
	var ns = main._state.player()
	var session := Deal.open(main._state, ns, main._loader, String(row["id"]))
	if session.is_empty():
		return false
	game["session"] = session
	game["state"] = main._state
	main._save_load_panel.block_save(Strings.t("Finish the audience first"))
	game.erase("money_taken")
	game.erase("money_open")
	var view := view_of(main, game)
	view.merge(row)
	view["president"] = main._loader.person_name(President.leader_id(ns))
	view["name"] = row["person"]  # i18n: row-ok the person's shown name, from the loader
	view["opening_title"] = String(view["money"]["title"]) if not (view["money"] as Dictionary).is_empty() \
		else DialogueLines.opening_title(ns, Audiences.request(ns, String(row["id"])))
	main._windows.open(WINDOW)
	main._clock.paused = true
	game["scene"].open(view)
	main._hud.clock_cluster.refresh(main._clock, HoldReason.show(main))
	return true


## What the scene shows, read off the sim as it stands now (audience_view.gd).
static func view_of(main, game: Dictionary) -> Dictionary:
	return AudienceView.view_of(main, game)


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


## The Counter: the same word at the date the field shows (Deal.bargain's promise_date), the day with it.
## A refused Counter binds nothing the UI says; the scene stays on the question either way.
static func counter(main, game: Dictionary, date: Dictionary) -> void:
	var session: Dictionary = game.get("session", {})
	if session.is_empty():
		return
	var args := {"due_month": int(date["year"]) * 12 + int(date["month"]), "due_day": int(date["day"])}
	var r := Deal.bargain(main._state, main._state.player(), main._loader, session, "promise_date", args)
	if not bool(r["ok"]):
		game["scene"].show_result(Words.reason(String(r["error"])), view_of(main, game), "", {}, ResultTone.BLOCKED)
		return
	var said := Strings.t("They agree.") if bool(r["success"]) else Strings.t("They are not moved.")
	var paid := Words.paid_text(r["spent"], r["effects"], main._loader.person_name, _feel(main, session))
	game["scene"].show_result(said + " " + Words.changed(paid) if paid != "" else said, view_of(main, game),
		"lever_promise_date_" + ("success" if bool(r["success"]) else "failure"), {"lever": Words.lever("promise_date")},
		ResultTone.GOOD if bool(r["success"]) else ResultTone.BAD)
	main._windows.mark_all_dirty()


## Grant: the ask paid and the offer taken, no roll (Deal.grant). The scene stays up: small
## talk is still open, and End says how it ended.
static func grant(main, game: Dictionary) -> void:
	var session: Dictionary = game.get("session", {})
	if session.is_empty():
		return
	var r := Deal.grant(main._state, main._state.player(), main._loader, session)
	if not bool(r["ok"]):
		game["scene"].show_result(Words.reason(String(r["error"])), view_of(main, game), "", {}, ResultTone.BLOCKED)
		return
	var paid := Words.paid_text({}, r["effects"], main._loader.person_name, _feel(main, session))
	var said := Strings.t("The deal is struck.")
	game["scene"].show_result(said + " " + Words.changed(paid) if paid != "" else said, view_of(main, game), "deal_grant", {}, ResultTone.GOOD)
	main._windows.mark_all_dirty()


## The money on the table, answered: Take is Deal.take (Grant plus the money, the evidence it leaves),
## Leave is Shadows.refuse_offer (her regard, nothing else). Her reply is Content's offer_accept_ /
## offer_refuse_ line for her kind and the currency; what Take paid is kept for the struck band.
static func money(main, game: Dictionary, take: bool) -> void:
	var session: Dictionary = game.get("session", {})
	if session.is_empty():
		return
	var ns = main._state.player()
	var snapshot: Dictionary = game.get("money_open", {})
	var person = main._loader.person_by_id.get(String(session["person_id"]))
	var title := ("offer_accept_%s_%s" if take else "offer_refuse_%s_%s") % [String(person.kind) if person != null else "", String(snapshot.get("currency", ""))]
	var r := Deal.take(main._state, ns, main._loader, session) if take else Shadows.refuse_offer(main._state, ns, main._loader, session)
	if not bool(r["ok"]):
		game["scene"].show_result(Words.reason(String(r["error"])), view_of(main, game), "", {}, ResultTone.BLOCKED)
		return
	if take:
		game["money_taken"] = snapshot
	var said := Strings.t("You take it.") if take else Strings.t("You turn it down.")
	var paid := "" if take else Words.paid_text({}, {"rapport": float(r.get("rapport", 0.0))}, main._loader.person_name, _feel(main, session))
	game["scene"].show_result(said + " " + Words.changed(paid) if paid != "" else said, view_of(main, game), title, {},
		ResultTone.RISKY if take else ResultTone.of_rapport(float(r.get("rapport", 0.0))))
	main._windows.mark_all_dirty()


## The affair, put or ended (Shadows.begin_affair / end_affair): the president's own ask, never hers.
## A refusal is the person's to explain in their own words (affair_why_<key>); the sim marks the
## proposal on the session whatever the answer, so it is asked once an audience.
static func affair(main, game: Dictionary, line_id: String) -> void:
	var session: Dictionary = game.get("session", {})
	if session.is_empty():
		return
	var ns = main._state.player()
	var pid := String(session["person_id"])
	var asking := line_id == "affair_ask"
	var r := Shadows.begin_affair(main._state, ns, main._loader, pid, session) if asking else Shadows.end_affair(main._state, ns, main._loader, pid)
	if not bool(r["ok"]):
		var why := String(r["error"])
		game["scene"].show_result(Words.reason(why), view_of(main, game), "affair_why_" + why, {},
			ResultTone.BAD if why in ["too_cold", "no_spark"] else ResultTone.BLOCKED)
		return
	var paid := Words.paid_text({}, {"rapport": float(r.get("rapport", 0.0))}, main._loader.person_name, _feel(main, session))
	var said := Strings.t("It begins, and no one must know.") if asking else Strings.t("It is over.")
	game["scene"].show_result(said + " " + Words.changed(paid) if paid != "" else said, view_of(main, game),
		"affair_begin" if asking else "affair_end", {}, ResultTone.RISKY if asking else ResultTone.of_rapport(float(r.get("rapport", 0.0))))
	main._windows.mark_all_dirty()


## A line put to her: the topic it maps to (Levers.talk) spends an attempt for knowledge and rapport.
## Her answer is the line's own title, yes or no by how it landed; a gossip names the face picked.
static func ask(main, game: Dictionary, line_id: String, topic: String, args: Dictionary) -> void:
	var session: Dictionary = game.get("session", {})
	if session.is_empty():
		return
	if topic == "affair":
		affair(main, game, line_id)
		return
	# Cold or hostile before the talk, she deflects (her _no); else she answers (her _yes).
	var cold := MoodBadge.emotion_of(_feel(main, session)) == Portrait.Emotion.STERN
	var r := Levers.talk(main._state, main._state.player(), main._loader, session, topic, args)
	if not bool(r["ok"]):
		game["scene"].show_result(Words.reason(String(r["error"])), view_of(main, game), "", {}, ResultTone.BLOCKED)
		return
	var tone := ResultTone.of_rapport(float((r["effects"] as Dictionary).get("rapport", 0.0)))
	var extra := {"topic": Words.topic(topic)}
	for row in game["scene"].flow.lines:
		if String(row["id"]) == line_id:
			extra.merge(row.get("vars", {}), true)
	if args.has("about"):
		extra["third"] = main._loader.person_name(String(args["about"]))
	var answer := "no" if cold else "yes"
	game["scene"].show_result(Words.changed(Words.paid_text({}, r["effects"], main._loader.person_name, _feel(main, session))), view_of(main, game),
		"talk_%s_%s" % [line_id, answer], extra, tone)


## End: the sim closes the audience (a lever won settles it; none, and it is a
## decline priced once) and the scene says how it ended. The scene stays up.
static func end(main, game: Dictionary) -> void:
	var session: Dictionary = game.get("session", {})
	if session.is_empty() or bool(session.get("closed", false)):
		return
	# c1c rule 1: an audience settled as declined is a crossing; read before the close
	# settles the request, so the close can say why the price was a broken word.
	var broken := Audiences.decline_price(main._state.player(), main._loader, String(session.get("request_id", ""))).has("broken_word")
	var r := Levers.close(main._state, main._state.player(), main._loader, session)
	# Good news only for an outcome worded as one: anything else -- an outcome the sim leaves
	# empty included -- is said as the refusal it is (Words.outcome). The price it cost is the
	# refused band's own lines, read before the close (audience_view.gd).
	var text := Words.outcome(String(r["outcome"]))
	if String(r["outcome"]) == "declined" and broken:
		text += " " + Strings.t("They held something on you. Refusing them broke your word.")
	game["scene"].show_close(String(r["outcome"]), text, ResultTone.GOOD if String(r["outcome"]) in ["settled", "promised"] else ResultTone.BAD)
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
