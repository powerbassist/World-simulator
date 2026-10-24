extends RefCounted

## The exchange weights B5 is read in (docs/design/bands-v5.2.md B5 and its
## "B5 amendment"), declared before any read and shared by the two probes that
## read it -- tools/lever_probe.gd (the levers) and tools/audience_probe.gd (the
## answers to a request) -- so the two rows price one world. Dev-only, never
## ships. Units: one ask won.

const K = preload("res://src/sim/lever_constants.gd")
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
