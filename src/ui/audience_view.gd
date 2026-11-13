extends RefCounted

## What the audience scene is handed, read off the sim as it stands now -- V5.3. One builder for
## the scene's `view`: the voice and feelings the face wears, the question (audience_words.gd over
## Deal.answers and Systems' two reads), the deal's band once struck, and the talk's ranked rows
## with their sentences' variables and their faces resolved (talk_menu.gd). Static and read-only:
## the sim's copies of the world behind the two reads make it a redraw's cost, never a frame's.

const AudienceVoice = preload("res://src/ui/audience_voice.gd")
const DealWords = preload("res://src/ui/deal_words.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Deal = preload("res://src/sim/deal.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const Levers = preload("res://src/sim/levers.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const President = preload("res://src/sim/president.gd")
const Region = preload("res://src/core/region.gd")
const Shadows = preload("res://src/sim/shadows.gd")
const Strings = preload("res://src/ui/strings.gd")
const TalkMenu = preload("res://src/ui/talk_menu.gd")
const Words = preload("res://src/ui/lever_words.gd")
const AWords = preload("res://src/ui/audience_words.gd")
const Labels = preload("res://src/ui/labels.gd")


static func view_of(main, game: Dictionary) -> Dictionary:
	var state = main._state
	var ns = state.player()
	var loader = main._loader
	var session: Dictionary = game["session"]
	var pid := String(session["person_id"])
	var person = loader.person_by_id.get(pid)
	var kind := String(person.kind) if person != null else ""
	var feel := Feelings.of(ns, pid)
	var answers := Deal.answers(state, ns, loader, session)
	var struck := session.has("struck") or String(session.get("won", "")) != ""
	var wants := _want_words(loader, ns, person, String(session["object"]))
	var card := DealWords.card(loader, ns, answers, feel, wants, kind)
	# "money" is ALWAYS in the view: the scene merges a result's view over its own, and a key left
	# out would keep the offer on screen after it was answered.
	var view := {"voice": AudienceVoice.lines(loader, pid), "choices": {"feel": feel}, "struck": struck, "money": {}, "notice_lines": game.get("notice", []),
		"attempts_left": int(session["attempts_left"]), "talk_blocked": _blocked(state, ns, loader, session)}
	if struck:
		view["struck_lines"] = AWords.struck_lines(answers, card)
		if game.has("money_taken"):
			view["struck_lines"] += AWords.taken_lines(game["money_taken"])
		view["affair"] = _affair(state, ns, loader, session, pid)
		# Ranked once: the flow holds the first ranking, so a later redraw does not read it again.
		if not game["scene"].flow.ranked:
			view["talk"] = _talk(state, ns, loader, session)
		return view
	# An offer of money not yet answered holds the question (Deal.MONEY_FIRST is the sim's own rule):
	# the screen is the offer and its two answers, and the cards' reads wait for the answer.
	var money: Dictionary = answers["money"]
	game["money_open"] = money  # what the press will answer: read once per redraw, never again on the click
	if not money.is_empty():
		view["money"] = {"lead": "%s %s" % [String(card["want"]), String(card["give_stake"])], "terms": AWords.money_terms(money),
			"lines": AWords.money_lines(money), "take_why": String(money["take"]["why_not"]),
			"title": "offer_%s_%s" % [kind, String(money["currency"])]}
		return view
	# Both reads copy the world: only the question needs them, and a refusal's own band reuses them.
	var reads := {"refusal": Deal.refusal_risk(state, ns, loader, session), "silence": Deal.silence_worth(state, ns, loader, session)}
	view["question"] = AWords.question(loader, ns, session, answers, feel, wants, kind, reads)
	view["refused_lines"] = AWords.refused_lines(card, reads)
	view["counter_default"] = _default_date(state, int(answers["bargain"]["due_month"]))
	return view


## The affair as the sim reads it: a lover, a Flirt said this audience, a proposal already put (once an
## audience), and the reasons not even to put one (not_covered, already), shown on the line.
static func _affair(state, ns, loader, session: Dictionary, pid: String) -> Dictionary:
	var why := Shadows.may_begin_affair(state, ns, loader, pid, session)
	return {"lovers": President.relationship(ns, pid) == "affair", "flirted": (session["used_topics"] as Array).has("flirt"),
		"asked": bool(session.get("affair_asked", false)), "blocked": Words.reason(why) if why in ["not_covered", "already"] else ""}


## The topics the sim will not take now (no attempts left, dined already): topic -> its reason, shown.
static func _blocked(state, ns, loader, session: Dictionary) -> Dictionary:
	var out := {}
	for row in Levers.topics(state, ns, loader, session):
		if not bool(row["offered"]):
			out[String(row["topic"])] = Words.reason(String(row["why_not"]))
	return out


## The Counter opens on the month the counter offers, on today's day of the month (clamped).
static func _default_date(state, due_month: int) -> Dictionary:
	var year := floori((due_month - 1) / 12.0)
	var month := due_month - year * 12
	return {"year": year, "month": month, "day": mini(int(state.day), DateText.days_in(month, year))}


static func _want_words(loader, ns, person, object: String) -> String:
	var stance := ""
	if person != null:
		for w in person.wants:
			if String(w["object"]) == object:
				stance = String(w["stance"])
	var thing := PersonCard.object_text(loader, ns, object, {"object": object})
	return "%s %s" % [Strings.t(PersonCard.stance_label(stance)), thing] if stance != "" else thing


## TalkMenu's rows, their variables and faces resolved in words: {id, topic, tag, args, plain,
## vars, people: [{id, name, tip}]}.
static func _talk(state, ns, loader, session: Dictionary) -> Array:
	var out: Array = []
	for line in TalkMenu.lines(state, ns, loader, session):
		var people: Array = []
		for p in line["people"]:
			people.append({"id": String(p["id"]), "name": loader.person_name(String(p["id"])), "tip": _tie_words(loader, ns, p["tie"])})
		out.append({"id": line["id"], "topic": line["topic"], "tag": line["tag"], "args": line["args"], "people": people,
			"vars": _vars(loader, ns, line["facts"]), "plain": Words.topic(String(line["topic"]))})
	return out


static func _vars(loader, ns, facts: Dictionary) -> Dictionary:
	var out := {}
	if facts.has("law_id"):
		out["bill"] = PersonCard.object_text(loader, ns, "law:%s" % String(facts["law_id"]), {})
	if facts.has("company_id"):
		var firm: String = loader.firm_name(ns.id, String(facts["company_id"]))
		var city = Region.find_city(loader.regions.get(ns.id, []), String(facts.get("city_id", "")))
		out["plant"] = Strings.t("%s's plant at %s") % [firm, String(city.city_name) if city != null else firm]
		out["date"] = Words.when(int(facts.get("due", 0)))
	if facts.has("sector_id"):
		out["sector"] = Labels.sector(String(facts["sector_id"]))
	return out


## How a face in a gossip is tied, for its tooltip: the sim's links, in words.
static func _tie_words(loader, ns, tie: Dictionary) -> String:
	if String(tie["kind"]) == "office":
		return Strings.t("Wants the leadership of the party: their post.")
	if String(tie["kind"]) == "party":
		for party in loader.parties.get(ns.id, []):
			if String(party.id) == String(tie["party_id"]):
				return Strings.t("Of the same party: %s.") % String(party.party_name)
		return Strings.t("Of the same party.")
	var thing := PersonCard.object_text(loader, ns, String(tie["object"]), {})
	return Strings.t("Wants the same: %s.") % thing if bool(tie["same_side"]) else Strings.t("Takes the other side on %s.") % thing
