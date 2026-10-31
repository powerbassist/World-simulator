extends RefCounted

## The inbox note that answers a proposal the player just made. It moved out of
## main.gd (at its size ratchet) when the held bill needed its own wording: a bill
## the Assembly carried and the second chamber only HOLDS is not "Failed" -- the
## Legislature, the verdict window and the assembly news all say held (one word
## for different things is the readout bug this project keeps finding).
##
## V5.2 b+ R2 (the author: "i dont see when a vote is proposed, accepted,
## rejected"): the division reads as its verdict, Carried or Defeated, with
## resolve_vote()'s yes, no and abstain seats and who broke ranks; a bill adopted
## under Article 49.3 says no vote was taken and how the censure went. A bill
## divides the moment it is proposed until the sim tables it (Systems, after c1);
## then the tabled card is pushed at tabling and this body set on it in place at
## the division (inbox.set_body), so one card follows the bill.

const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const LawVerdict = preload("res://src/ui/law_verdict.gd")

## main's instance id -> {law_id, card}: the card the tabling pushed, which the
## division's verdict is set on in place (one card follows the bill). A static
## keyed by the game, AudienceDriver's shape, so main.gd (at its baseline) keeps
## no field for it.
static var _tabled := {}


## `parties`: the nation's Party rows, to name who broke ranks.
static func body(result: Dictionary, parties: Array = []) -> String:
	# V5.2 b+ R2 (Systems): the sim tables a bill and divides it at the month's close.
	if bool(result.get("tabled", false)):
		return Strings.t("Tabled: the Assembly votes on %s.") % DateText.day_month(int(result["vote_day"]), int(result["vote_month"]))
	if bool(result.get("refused", false)):
		if bool(result.get("already_tabled", false)):
			return Strings.t("A bill is already before the Assembly.")
		if bool(result.get("referendum_in_flight", false)):
			return Strings.t("A referendum is already in flight.")
		return Strings.t("The assembly would not take it.")
	if bool(result.get("withdrawn", false)):
		return Strings.t("Withdrawn.")
	if bool(result.get("referendum_route", false)):
		return Strings.t("To the country -- the vote is scheduled.")
	if bool(result.get("forced", false)):
		return _forced(result.get("censure", {}), bool(result.get("struck_down", false)))
	var counts := [int(result.get("yes_seats", 0)), int(result.get("no_seats", 0)), int(result.get("abstain_seats", 0))]
	# The assembly's verdict: a bill it carried and the court then struck down is
	# carried here, the strike a sentence of its own (QA on #158).
	var struck := bool(result.get("struck_down", false))
	var carried := bool(result.get("passed", false)) or bool(result.get("held_by_upper", false)) \
		or bool(result.get("blocked_by_upper", false)) or struck
	var verdict := Strings.t("Carried: %d for, %d against, %d abstaining.") % counts if carried \
		else Strings.t("Defeated: %d for, %d against, %d abstaining.") % counts
	var parts := PackedStringArray([verdict])
	# The second chamber's word after the assembly's (PRE-GATE 2 B3: held is not failed).
	var chamber := String(result.get("upper_chamber", Strings.t("second chamber")))
	if bool(result.get("held_by_upper", false)):
		var months := int(result.get("held_months", 0))
		parts.append(Strings.tn("The %s holds it; it comes into force in %d month.", "The %s holds it; it comes into force in %d months.", months) % [chamber, months])
	elif bool(result.get("blocked_by_upper", false)):
		parts.append(Strings.t("The %s has blocked it.") % chamber)
	if struck:
		parts.append(Strings.t("The court struck it down."))
	var rebels := PackedStringArray()
	var party_rebels: Dictionary = result.get("party_rebels", {})
	for party in parties:
		if int(party_rebels.get(party.id, 0)) > 0:
			rebels.append("%s %d" % [party.party_name, int(party_rebels[party.id])])
	if not rebels.is_empty():
		parts.append(Strings.t("Broke ranks: %s.") % ", ".join(rebels))
	return " ".join(parts)


## The proposal's card, pushed at the press; a tabled bill's card is remembered for
## its division.
static func push(main, title: String, result: Dictionary) -> void:
	var card: String = ResultTone.push(main._hud.inbox, title, body(result, main._loader.parties.get(main._state.player().id, [])), tone(result, main._state.player()))
	if bool(result.get("tabled", false)):
		remember(main, String(result.get("law_id", "")), card)


## The card a tabled bill's verdict goes on: the press's, or the Diary day's.
static func remember(main, law_id: String, card: String) -> void:
	_tabled[main.get_instance_id()] = {"law_id": law_id, "card": card}


## The division at the close (WorldMonth's Division step): its verdict set in place
## on the card the tabling pushed, raised as the news it is. A new card only when
## that one is gone: dismissed, or a load.
static func card_division(main, report: Dictionary) -> void:
	var result: Dictionary = report.get("division", {})
	if result.is_empty():
		return
	var law_id := String(result.get("law_id", ""))
	var text := body(result, main._loader.parties.get(main._state.player().id, []))
	var tabled: Dictionary = _tabled.get(main.get_instance_id(), {})
	_tabled.erase(main.get_instance_id())
	# V5.3-0 (d): the division is where a tabled bill is won or lost, so its sting
	# plays here (run_proposal's call only ever sees a 49.3; #223 pass 1).
	LawVerdict.sting(main, result, main._state.player())
	var card := String(tabled.get("card", ""))
	if String(tabled.get("law_id", "")) == law_id and main._hud.inbox.lane_of(card) != "":
		main._hud.inbox.set_body(card, text)
		ResultTone.mark(main._hud.inbox, card, tone(result, main._state.player()))
		main._hud.inbox.raise_card(card)
		return
	ResultTone.push(main._hud.inbox, Strings.law_name(main._law_panel._find_law(law_id), law_id), text, tone(result, main._state.player()))


## How the card's result landed (#222 QA T3: the vote is met on this card, so it
## carries the tone the Legislature's verdict line does). A tabled, withdrawn or
## scheduled bill has no verdict yet; a refusal is BLOCKED; a forced bill whose
## censure carried brought the government down.
static func tone(result: Dictionary, ns) -> String:
	if bool(result.get("refused", false)):
		return ResultTone.BLOCKED
	if bool(result.get("tabled", false)) or bool(result.get("withdrawn", false)) \
			or bool(result.get("referendum_route", false)) or not result.has("passed"):
		return ""
	if bool(result.get("forced", false)) and bool(result.get("censure", {}).get("carried", false)):
		return ResultTone.BAD
	return LawVerdict.tone(result, ns)


## Article 49.3: adopted with no division, then the censure it invites.
static func _forced(censure: Dictionary, struck := false) -> String:
	if censure.is_empty():
		return Strings.t("Adopted without a vote; the court struck it down.") if struck else Strings.t("Adopted without a vote.")
	var motion := Strings.t("Adopted without a vote; the censure motion that followed had %d for, %d needed.") % [
		int(censure.get("for_seats", 0)), int(censure.get("threshold", 0))]
	var outcome := Strings.t("It carried: the government falls.") if bool(censure.get("carried", false)) \
		else Strings.t("It failed: the government stays, but the court struck the bill down.") if struck \
		else Strings.t("It failed: the bill stands.")
	return "%s %s" % [motion, outcome]
