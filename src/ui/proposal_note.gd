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


## `parties`: the nation's Party rows, to name who broke ranks.
static func body(result: Dictionary, parties: Array = []) -> String:
	if bool(result.get("refused", false)):
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
