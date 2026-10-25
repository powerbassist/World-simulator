extends RefCounted

## V5.2c, the shadows' numbers: corruption, the affair, lies and exposure. The
## design is docs/design/v5.2-spec.md ("Corruption, in the author's four
## currencies", "Lies and their detection"); the bands are docs/design/bands-v5.2.md
## B6, B7 and B8; the plan is .superpowers/sdd/v5.2c-plan.md.

const ActK = preload("res://src/sim/character_act_constants.gd")
const PresidentK = preload("res://src/sim/president_constants.gd")

## The four ways a shadow is found out, named once (the spec, the currencies table).
const ROUTES := ["press", "courts", "auditors", "turned"]

## Which evidence each route can reach. The spec's table: the press and the courts
## follow personal money; the auditors read the party's accounts and the spending
## lines; a turned person can talk about anything they took part in. The affair's
## routes are the plan's reading (its Call 3): the press, and a lover who turns.
const ROUTE_KINDS := {
	"press": ["personal_wealth", "affair"],
	"courts": ["personal_wealth", "diverted_budget"],
	"auditors": ["party_money", "diverted_budget"],
	"turned": PresidentK.EVIDENCE_KINDS,
}


# --- Exposure (src/sim/exposure.gd) ----------------------------------------------

## How much each kind of evidence weighs on a route's hazard, per unit of size: the
## spec's order (favours < party money < personal wealth < diverted budget, B6's
## currency row), the affair as heavy as the worst money. STARTING values: the
## shadows probe (the plan's Task 7) sets them.
const EVIDENCE_WEIGHT := {
	"favour": 0.25, "party_money": 0.5, "personal_wealth": 0.75, "diverted_budget": 1.0, "affair": 1.0,
}

## The monthly hazard per unit of weighted reach. STARTING values from B6's
## arithmetic: one act of weighted size about 1, at month 6, found by month 60 in
## 10-30 % of runs needs a summed monthly hazard of about 0.002-0.0066; at 0.0035
## a route, France's courts (73.8/100) and a neutral press give party money 9 %,
## personal wealth 22 % and a diverted budget 28 %. A turned person talks far more
## readily than an institution digs. The probe tunes all four.
const RATE := {"press": 0.0035, "courts": 0.0035, "auditors": 0.0035, "turned": 0.02}

## No route finds more than this in a month, however much there is to find: the
## "always" regime's pile would otherwise make every month a certainty.
const HAZARD_MAX := 0.25

## The press: the base rate with no hostile owner, plus up to PRESS_HOSTILE more as
## the share of hostile press owners rises to 1 (doubled when they all are).
const PRESS_BASE := 1.0
const PRESS_HOSTILE := 1.0
## A press owner is hostile below zero rapport, or at the grudge that already
## promises a leak -- the brief gate, not a second number.
const PRESS_GRUDGE_HOSTILE := ActK.GRUDGE_BRIEF_THRESHOLD
