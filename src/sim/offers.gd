extends RefCounted

## V5.2c. Whether a request comes with an offer of money -- the draw alone, in a
## leaf, so Audiences can stamp it on the row as the request arrives: shadows.gd,
## which takes or refuses the offer in the scene, reads Audiences, and the reverse
## call from there would be a preload cycle.
##
## Its own salt, keyed by the person and the absolute month: drawing it moves no
## other draw in the game (I1), and a game that never draws it sees the same
## request stream.

const Cycle = preload("res://src/sim/cycle.gd")
const SC = preload("res://src/sim/shadow_constants.gd")


## {} or {currency, amount_eur_m}. The person's kind decides whether and in which
## currencies (SC.OFFER_KINDS); a seeded draw at SC.OFFER_CHANCE decides whether
## this month, a second on the same salt which currency.
static func offer_for(ns, person, now: int) -> Dictionary:
	var currencies: Array = SC.OFFER_KINDS.get(String(person.kind), [])
	if currencies.is_empty():
		return {}
	var salt := Cycle.salted("%s|%s" % [SC.SALT_OFFER, person.id], ns.draw_seed)
	if Cycle.unit(salt, now) >= SC.OFFER_CHANCE:
		return {}
	var pick := mini(int(Cycle.unit(salt + ":currency", now) * currencies.size()), currencies.size() - 1)
	return {"currency": String(currencies[pick]), "amount_eur_m": SC.OFFER_EUR_M}
