extends RefCounted

## A delegated word: a minister answers a request in the president's name and
## gives their word that the person's want is served by the diary's horizon
## (Audiences.delegate; bands-v5.2.md "Delegation's commitment"). Levers judges the
## word at its date; this file is the minister's half of that verdict.
##
## WHY THE MINISTER IS HERE (V5.3-0 gate; the author, 2026-11-01, on QA's 8 broken
## words in 9: "cela ne doit pas etre la norme"). b2.1 judged the word on the world
## alone -- kept only if the want was served at its date -- and a request exists
## only because its want is NOT served. Three words in four name a programme entry
## the president did not choose, which the register reopens once a term, so almost
## nothing a minister promised could come true. MEASURED with
## tools/delegation_probe.gd (20 seeds x 96 months, every request delegated): 56
## words kept of 1,161 judged, and 1,089 of them never saw their want served in the
## window. The minister was prose. Now the minister keeps the word or breaks it,
## for reasons the player can read on the card before delegating:
##   - THE OBJECT. No minister can hand out an office, lift a measure only the
##     president lifts, or drop the president's own programme. Such a word is kept
##     only if the president serves it (chance 0, and `why` names the reason).
##   - THE CABINET. Its competence is the Government panel's effectiveness, a
##     vacancy at VACANT_EFFECTIVENESS; its loyalty is Cabinet.loyalty of each
##     portfolio's holder, a vacancy 0 (no minister, no word). An emptied or
##     disloyal cabinet keeps few words.
## Levers judges a served want first: kept, whatever the odds. Otherwise the word
## keeps the odds the card showed when it was given (frozen on the row, see
## keeps()): MEASURED first with live odds read at the date, an idle government's
## coalition loyalty decays inside the window (0.75 to 0.55 over its third year)
## and words given at odds 0.5-0.6 kept none of 89. So the simplification is
## stated: a word keeps its odds even if that cabinet later falls apart. A word the
## minister keeps leaves the want itself unserved, so the person may ask again once
## their cooldown has passed.
##
## A leaf over Cabinet's reads and Cycle's draw. Determinism: one seeded draw per
## word (Cycle.unit_pair over the person, the object and the month it was given),
## so the verdict is the same on a reload and never depends on what else rolled.

const K = preload("res://src/sim/audience_constants.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const CabinetK = preload("res://src/sim/cabinet_constants.gd")
const Characters = preload("res://src/sim/characters.gd")
const Cycle = preload("res://src/sim/cycle.gd")


## The rapport a delegation costs on the day: a snub for a `vain` person, or for one
## who wanted an office and is handed a minister (b2's price, moved here from
## Audiences.delegate with the rest of delegation's prices).
static func snub(person, object: String) -> float:
	if person != null and (person.traits.has("vain") or object.begins_with("office:")):
		return K.DELEGATE_SNUB_RAPPORT
	return 0.0


## A broken word: the share of a decline's grudge that delegating deferred lands
## now (bands-v5.2.md "Delegation's commitment"); Levers adds the betrayal.
static func price_broken(ns, person) -> void:
	var deferred := 1.0 - K.DELEGATE_GRUDGE_SHARE
	Characters.price_refusal(ns, person, K.DECLINE_GRUDGE * deferred, K.DECLINE_LOYALTY * deferred)


## Why no minister can deliver this object, or "" when one can: one of
## K.DELEGATE_WHY_*. `stance` is the want's; an `oppose` of a programme entry is
## unserved exactly while the entry is live on the president's own register.
static func impossible(object: String, stance: String) -> String:
	if object.begins_with("office:"):
		return K.DELEGATE_WHY_OFFICE
	if object.begins_with("measure:"):
		return K.DELEGATE_WHY_MEASURE
	if object.begins_with("programme:") and stance == "oppose":
		return K.DELEGATE_WHY_PROGRAMME
	return ""


## The chance the cabinet in office keeps a word on this object, with what it read:
## {chance, why, effectiveness, loyalty}, the last two each a mean over the five
## portfolios. `why` non-empty means the chance is 0.
static func odds(ns, loader, object: String, stance: String) -> Dictionary:
	var by_id := {}
	for party in loader.parties.get(ns.id, []):
		by_id[party.id] = party
	var effectiveness := 0.0
	var loyalty := 0.0
	for f in CabinetK.PORTFOLIO_KEYS:
		effectiveness += Cabinet.effectiveness(ns, f)
		var holder := String(ns.cabinet.get(f, ""))
		if by_id.has(holder):
			loyalty += Cabinet.loyalty(ns, by_id[holder])
	effectiveness /= float(CabinetK.PORTFOLIO_KEYS.size())
	loyalty /= float(CabinetK.PORTFOLIO_KEYS.size())
	var why := impossible(object, stance)
	var chance := 0.0
	if why == "":
		chance = clampf(K.DELEGATE_KEPT_BASE
			+ K.DELEGATE_KEPT_PER_EFFECTIVENESS * (effectiveness - 1.0)
			+ K.DELEGATE_KEPT_PER_LOYALTY * (loyalty - K.DELEGATE_LOYALTY_NEUTRAL),
			K.DELEGATE_KEPT_MIN, K.DELEGATE_KEPT_MAX)
	return {"chance": chance, "why": why, "effectiveness": effectiveness, "loyalty": loyalty}


## The word's one draw in [0, 1): kept when it falls under the odds.
static func roll(ns, person_id: String, object: String, made_month: int) -> float:
	return Cycle.unit_pair(person_id, Cycle.salted("%s|%s" % [K.SALT_DELEGATION, object], int(ns.draw_seed)), made_month)


## Whether the minister keeps a word the world has not served: `row` a commitment
## as President casts it ({kind, person_id, object, made_month, chance?}), `stance`
## the want's. Only a `delegated` row is a minister's: a promise or an IOU is the
## president's own, and false here. The odds are the ones the card showed, frozen
## on the word at delegation (Audiences.delegate): the number the player read is
## the deal, so a cabinet that decays inside the window does not break a word for a
## reason shown nowhere. A word with no stored odds (an older save's) is judged on
## the cabinet at its date.
static func keeps(ns, loader, row: Dictionary, stance: String) -> bool:
	if String(row.get("kind", "")) != "delegated":
		return false
	var object := String(row["object"])
	var chance := float(row["chance"]) if row.has("chance") else float(odds(ns, loader, object, stance)["chance"])
	return roll(ns, String(row["person_id"]), object, int(row["made_month"])) < chance
