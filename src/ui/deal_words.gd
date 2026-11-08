extends RefCounted

## The deal's words -- V5.3 b, step 6 (src/sim/deal.gd). What the audience's strip says before
## the choice, read off Deal.answers() and nothing else: the ask and the offer as things in the
## game, what the offer is worth (`seats` is what the division gains, never the faction's size:
## the parent's ruling on #301), and what each answer costs. It writes nothing and computes no
## odds or price of its own.

const K = preload("res://src/sim/deal_constants.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const Words = preload("res://src/ui/lever_words.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const ClosureCard = preload("res://src/ui/closure_card.gd")

const PRESS_OWNER := "press_owner"


## The card the scene shows. `wants` the request in the lane's words, `kind` the person's.
static func card(loader, ns, answers: Dictionary, feel: Dictionary, wants: String, kind: String) -> Dictionary:
	var ask: Dictionary = answers.get("ask", {})
	var offer: Dictionary = answers.get("offer", {})
	var grant: Dictionary = answers.get("grant", {})
	var refuse: Dictionary = answers.get("refuse", {})
	var refuse_text := Strings.t("Costs you: %s.") % Words.price_text(refuse, feel)
	if refuse.has("broken_word"):
		refuse_text += " " + Strings.t("They hold something on you. Refusing them breaks your word.")
	var out := {
		"grant_ok": bool(grant.get("ok", false)), "grant_why": Words.reason(String(grant.get("why_not", ""))),
		"bargain": _bargain(ask, answers),
		"refuse": refuse_text, "struck": String(grant.get("why_not", "")) == "they have already agreed",  # i18n: ok the sim's reason, compared
	}
	out.merge(_ask(loader, ns, ask, grant, wants))
	out.merge(_offer(loader, ns, offer, kind))
	return out


## The money on the table, and what taking it risks beside what is at risk without it.
static func risk(money: Dictionary) -> String:
	if money.is_empty():
		return ""
	return Strings.t("Found within a year: %s %% if you take it, %s %% if you do not.") % [
		Num.f(float(money.get("found_in_a_year", 0.0)) * 100.0, 0), Num.f(float(money.get("found_in_a_year_without", 0.0)) * 100.0, 0)]


## What a person owes, in the Diary's list: a pledge on a bill, or their silence.
static func owed_text(loader, ns, row: Dictionary) -> String:
	var who: String = loader.person_name(String(row["person_id"]))
	if String(row["kind"]) == "pledge":
		return Strings.t("%s has pledged a vote on %s, until %s.") % [who, PersonCard.object_text(loader, ns, String(row["object"]), {}), Words.when(int(row["due_month"]))]
	return Strings.t("%s keeps silent until %s.") % [who, Words.when(int(row["due_month"]))]


## What a person owed, judged, for the Diary's record beside the president's own words.
static func owed_verdict(loader, row: Dictionary) -> String:
	var who: String = loader.person_name(String(row["person_id"]))
	return Strings.t("%s kept their word to you.") % who if String(row["verdict"]) == "kept" else Strings.t("%s broke their word to you.") % who


## What Bargain settles for. A closing plant has no date to move: its smaller grant is a buyer.
static func _bargain(ask: Dictionary, answers: Dictionary) -> String:
	if String(ask.get("kind", "")) == K.ASK_FIRM:
		var buyer: Dictionary = ask.get("buyer", {})
		return "" if buyer.is_empty() else Strings.t("Or bargain for less: find a buyer. %s. %s") % [ClosureCard.money(buyer)[0], ClosureCard.jobs_text(buyer)]
	return Strings.t("Or bargain for less: your word by %s, or the date you promise, for the same offer.") % Words.when(int(answers.get("bargain", {}).get("due_month", 0)))


static func _ask(loader, ns, ask: Dictionary, grant: Dictionary, wants: String) -> Dictionary:
	var kind := String(ask.get("kind", ""))
	var object := String(ask.get("object", ""))
	var thing := PersonCard.object_text(loader, ns, object, {})
	if kind == K.ASK_POST:
		return {"want": Strings.t("The %s, for their party.") % thing, "want_stake": wants,
			"grant_cost": _post_cost(loader, ns, grant.get("removal", {}))}
	if kind == K.ASK_FIRM:
		# Paid now, as a post is: the rescue's price, and no word is written.
		var rescue: Dictionary = ask.get("rescue", {})
		return {"want": "%s%s." % [thing.left(1).to_upper(), thing.substr(1)], "want_stake": wants,
			"grant_cost": "" if rescue.is_empty() else Strings.t("The rescue: %s. %s") % [ClosureCard.money(rescue)[0], ClosureCard.jobs_text(rescue)]}
	var by := Words.when(int(ask.get("due_month", 0)))
	if kind == K.ASK_LAW:
		return {"want": Strings.t("Bring %s before the chamber.") % thing, "want_stake": wants,
			"grant_cost": Strings.t("Your word to bring it by %s. Not brought, it is a lie.") % by}
	return {"want": Strings.t("Your word on %s.") % thing, "want_stake": wants,
		"grant_cost": Strings.t("Your word, due %s. Broken, it is a lie.") % by}


## A portfolio taken from a partner is a removal, priced as one: the leader's feeling and the
## deputies who would break ranks (Removal.price, the Cabinet's own words).
static func _post_cost(loader, ns, removal: Dictionary) -> String:
	if removal.is_empty():
		return Strings.t("The portfolio is free: it costs you nothing.")
	var parts := PackedStringArray()
	var leader := String(removal["leader_id"])
	var pulse := float(removal["grudge_after"]) - float(removal["grudge_before"])
	if pulse >= Feelings.MOVED:
		parts.append(Strings.t("%s, its leader: %s.") % [loader.person_name(leader), ", ".join(Feelings.promised(Feelings.of(ns, leader), {"grudge": pulse}))])
	var rebels := int(removal.get("rebels_after", 0)) - int(removal.get("rebels", 0))
	if rebels > 0:
		parts.append(Strings.tn("%d more of its deputies would break ranks.", "%d more of its deputies would break ranks.", rebels) % rebels)
	return " ".join(parts) if not parts.is_empty() else Strings.t("It costs you nothing.")


static func _offer(loader, ns, offer: Dictionary, kind: String) -> Dictionary:
	if String(offer.get("kind", "")) == K.OFFER_VOTE:
		var seats := int(offer.get("seats", 0))
		var date: Dictionary = offer.get("date", {})
		var bill := PersonCard.object_text(loader, ns, "law:%s" % String(offer.get("law_id", "")), {})
		var stake := Strings.tn("It adds %d seat to the yes line at the next division.", "It adds %d seats to the yes line at the next division.", seats) % seats
		if not date.is_empty():
			stake = Strings.tn("It adds %d seat to the yes line on %s.", "It adds %d seats to the yes line on %s.", seats) % [seats,
				DateText.day_month_year(int(date["day"]), int(date["month"]), int(date["year"]))]
		return {"give": Strings.t("Their vote on %s.") % bill, "give_stake": stake, "give_good": seats > 0}
	var months := int(offer.get("months", 0))
	# Characters' brief gate reads the silence for any person; a press owner's brief is a paper's.
	var stake := Strings.tn("Their papers run no brief against you for %d month.", "Their papers run no brief against you for %d months.", months) % months if kind == PRESS_OWNER \
		else Strings.tn("No brief against you from them for %d month.", "No brief against you from them for %d months.", months) % months
	return {"give": Strings.t("Their silence."), "give_stake": stake, "give_good": false}
