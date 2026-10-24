extends RefCounted

## The exchange weights B5 is read in (docs/design/bands-v5.2.md B5 and its
## "B5 amendment"), declared before any read and shared by the two probes that
## read it -- tools/lever_probe.gd (the levers) and tools/audience_probe.gd (the
## answers to a request) -- so the two rows price one world. Dev-only, never
## ships. Units: one ask won.

const K = preload("res://src/sim/lever_constants.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const Characters = preload("res://src/sim/characters.gd")

const GAIN := 1.0
## Flatter's effect is small and does not hold (the spec's dominance matrix).
const GAIN_FLATTER := 0.7
## A grudge point moves acts; a rapport point only later odds -- so half.
const WEIGHTS := {"grudge": 1.0, "rapport": 0.5, "commitment": 0.15, "bond": 0.30}
## One diary day (an audience takes one): bands-v5.2.md "B5 amendment
## (2026-10-24): the price of a diary day", 1.05 of one ask won, derived from the
## declared bands against delegation with its commitment, before any read.
const DIARY_DAY := 1.05
## B5's answers row, "The in-person gains": B4's slope (odds per unit of knowledge,
## from its declared midpoints) and the further encounters a term holds with one
## person (B1), which together value the knowledge an audience teaches.
const KNOW_SLOPE := 0.448
const ENCOUNTERS := 2.0


## The expected spend of one attempt, per register (the levers table, paid win or
## lose; flatter's backfire only on a failure).
static func spend(person, lever: String, p: float) -> Dictionary:
	match lever:
		"bargain":
			return {"rapport": K.BARGAIN_FAVOUR_RAPPORT}
		"promise_date":
			return {"commitment": 1.0}
		"pressure":
			return {"rapport": K.PRESSURE_RAPPORT, "grudge": K.PRESSURE_GRUDGE * Characters.grudge_intake(person)}
		"flatter":
			if person.traits.has("principled") and float(person.social_skill) > K.FLATTER_BACKFIRE_SKILL:
				return {"rapport": (1.0 - p) * K.FLATTER_BACKFIRE_RAPPORT}
		"friendship":
			return {"bond": 1.0}
	return {}


## A spend in asks.
static func cost(spent: Dictionary) -> float:
	var total := 0.0
	for r in spent:
		total += float(WEIGHTS[r]) * float(spent[r])
	return total


## One attempt's net value: odds x the lever's gain, minus its expected spend.
static func net(person, lever: String, p: float) -> float:
	return p * (GAIN_FLATTER if lever == "flatter" else GAIN) - cost(spend(person, lever, p))


# --- B5's answers row (bands-v5.2.md, "The first read, and the player model") ------
# Pure arithmetic in the row's own terms, so the declared legs can be checked
# on their own inputs before the read.

## Refuse: decline and unanswered, one answer (the tie rule).
static func refuse_value(g: float) -> float:
	return -(g + float(WEIGHTS["rapport"]) * -AK.DECLINE_RAPPORT)


## Delegate, with its commitment kept (`serve`) or broken at its date.
static func delegate_value(g: float, snub: float, serve: bool) -> float:
	var r_w := float(WEIGHTS["rapport"])
	var v := -(AK.DELEGATE_GRUDGE_SHARE * g + r_w * snub)
	if serve:
		return v + r_w * K.DELEGATED_KEPT_RAPPORT
	return v - ((1.0 - AK.DELEGATE_GRUDGE_SHARE) * g + K.IOU_BETRAYAL_GRUDGE + r_w * K.IOU_BETRAYAL_RAPPORT)


## Book on one lever: the three-attempt audience (p its odds, s its weighted
## spend per attempt), the diary day, being received, the knowledge it teaches
## (k the knowledge before), and for a promise its keeping in person (`serve`) or
## the lie at its date (intake the person's grudge intake). The agreement counts
## 1, as the row's table declares.
static func book_value(p: float, s: float, g: float, k: float, serve: bool, promise: bool, intake: float) -> float:
	var r_w := float(WEIGHTS["rapport"])
	var q := 1.0 - p
	var a := 1.0 - q * q * q
	var v := a - s * (1.0 + q + q * q) + q * q * q * refuse_value(g) - DIARY_DAY \
		+ r_w * AK.RECEIVED_RAPPORT + knowledge_value(AK.KNOW_AUDIENCE * (1.0 - k), q)
	if not promise:
		return v
	if serve:
		return v + a * r_w * K.PROMISE_KEPT_RAPPORT
	var k_then := k + AK.KNOW_AUDIENCE * (1.0 - k)
	return v - a * (r_w * K.LIE_RAPPORT + K.LIE_GRUDGE * intake + knowledge_value((1.0 - K.LIE_KNOWLEDGE_KEEP) * k_then, q))


## Knowledge `dk` in asks: B4's slope x the three-attempt sensitivity 3q^2 x the
## further encounters this term.
static func knowledge_value(dk: float, q: float) -> float:
	return dk * KNOW_SLOPE * 3.0 * q * q * ENCOUNTERS
