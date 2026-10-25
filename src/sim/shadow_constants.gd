extends RefCounted

## V5.2c, the shadows' numbers: corruption, the affair, lies and exposure. The
## design is docs/design/v5.2-spec.md ("Corruption, in the author's four
## currencies", "Lies and their detection"); the bands are docs/design/bands-v5.2.md
## B6, B7 and B8; the plan is .superpowers/sdd/v5.2c-plan.md.

const ActK = preload("res://src/sim/character_act_constants.gd")
const LK = preload("res://src/sim/lever_constants.gd")
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

# --- Offers (src/sim/offers.gd draws them, src/sim/shadows.gd answers them) ---------

## Who comes with money, and which (the spec's currencies table): an executive to
## the president or to the party; a press owner to the president alone.
const OFFER_KINDS := {"executive": ["party_money", "personal_wealth"], "press_owner": ["personal_wealth"]}
## The chance a request from one of them comes with an offer. STARTING value: B6
## wants 2 to 6 offers reaching the president a term; the shadows probe sets it.
const OFFER_CHANCE := 0.25
## What an offer is worth, EUR millions, and the evidence each million leaves: one
## act of evidence size 1, the size RATE above is set at.
const OFFER_EUR_M := 1.0
const EVIDENCE_PER_EUR_M := 1.0
## A refused offer costs the offerer's regard -- half a declined request's -- and
## never a grudge (the visitors' precedent). OPINION, a starting value.
const OFFER_REFUSED_RAPPORT := 0.05
const SALT_OFFER := "offer"

# --- The corrupt bargain currencies (src/sim/shadows.gd) ---------------------------

## What each leaves: backroom, a person who knows (the spec's "favours"); aid, a gap
## in a spending line (the spec's "diverted budget"), the largest trail.
const CURRENCY_EVIDENCE := {LK.CURRENCY_BACKROOM: "favour", LK.CURRENCY_AID: "diverted_budget"}
## What each adds to a bargain's odds, the more exposed buying more. STARTING
## values: lever_probe L2 prices them at their expected cost (B5's amendment).
const CURRENCY_ODDS := {LK.CURRENCY_BACKROOM: 0.10, LK.CURRENCY_AID: 0.20}
## Every corrupt bargain leaves one act of evidence (the S1 size).
const ACT_EVIDENCE := 1.0

# --- Lies (src/sim/lies.gd) --------------------------------------------------------

## The levers a lie can be told on, and what it adds to that attempt's odds.
## STARTING value: lever_probe L2 prices it at P(caught) x the reveal (B5's amendment).
const LIE_LEVERS := ["argue", "promise_date"]
const LIE_ODDS := 0.10
## The catch: the listener's reading skill against the president's (both
## social_skill). At a middling 0.5 president a 0.8 reader catches 55.5 % and a 0.2
## reader 10.5 % -- inside B8's two bands, [0.40, 0.70] and [0.05, 0.20].
const LIE_CATCH_BASE := 0.33
const LIE_CATCH_SLOPE := 0.75
const LIE_CATCH_MIN := 0.02
const LIE_CATCH_MAX := 0.95
const SALT_LIE := "lie"

# --- The affair and the bonds (src/sim/shadows.gd) ---------------------------------

## The bond rule, B6's amendment: a rival is cold -- rapport below -0.30, R11's word
## -- and an enemy is a rival who holds the grudge that already promises a leak.
## No hysteresis: the bond follows the word the card shows, the same month.
const RIVAL_RAPPORT := -0.30
const ENEMY_GRUDGE := ActK.GRUDGE_BRIEF_THRESHOLD
## An affair needs a spark -- a seeded draw per pair, fixed, because chemistry does
## not re-roll -- and a person who is close (rapport above +0.30, R11's "close").
## STARTING values, OPINION.
const SPARK_CHANCE := 0.25
const AFFAIR_RAPPORT_MIN := 0.30
const SALT_SPARK := "spark"
## Evidence an affair leaves each month it lasts. STARTING value: B7 wants one kept
## 24 months exposed by month 60 in 25-50 % of runs; the shadows probe sets it.
const AFFAIR_EVIDENCE_PER_MONTH := 0.05
## Ending it costs the lover's regard: from just past close, enough to make a rival
## who can talk (the turned route). OPINION, a starting value.
const AFFAIR_END_RAPPORT := 0.70
