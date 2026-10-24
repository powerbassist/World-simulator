extends RefCounted

## The audience (V5.2b b2): the levers' odds, the fog, the spends and the
## promises. The model is docs/audiences-model.md "The audience"; the bands that
## judge these numbers are docs/design/bands-v5.2.md B4 and B5, and
## tools/lever_probe.gd measures them. Every number below is an INITIAL value
## declared before the probe ran, from a prototype over France's 61 people; the
## model doc records where each landed.

## The six levers, in the order the scene lists them, and the other topics.
const LEVERS := ["argue", "bargain", "promise_date", "pressure", "flatter", "friendship"]
const TOPICS := ["family", "opinion", "gossip", "dinner", "flirt"]

## Three attempts an audience (the author's answer 2, 2026-10-21).
const ATTEMPTS := 3

## No lever is ever certain or hopeless: a sure thing is a button, not a reading
## of a person.
const ODDS_MIN := 0.05
const ODDS_MAX := 0.95

## Rapport moves every lever alike: a person who likes the president listens.
const K_RAPPORT := 0.20

## ARGUE costs nothing, so it must be the weak lever wherever the president does
## not know the person (the spec's dominance matrix: "low odds without
## knowledge"): almost all its strength is knowledge, picking the right argument.
## A low base is what keeps a free lever from Pareto-dominating every priced one.
const ARGUE_BASE := 0.08
const ARGUE_KNOW := 0.62
const ARGUE_ALIGN := 0.15
const ARGUE_STUBBORN := -0.14

## BARGAIN pays a real currency every time, and reads pragmatic against principled.
const BARGAIN_BASE := 0.28
const BARGAIN_KNOW := 0.25
const BARGAIN_PRAGMATIC := 0.22
const BARGAIN_PRINCIPLED := -0.22

## The neutral points the odds measure from: a middling reader (person.gd's own
## absent social_skill), middling standing, and an approval of half -- the levels
## at which a reader's doubt, a person's weight and the president's popularity
## move nothing.
const SKILL_MIDDLING := 0.5
const STANDING_NEUTRAL := 0.5
const APPROVAL_NEUTRAL := 50.0

## PROMISE A DATE: ambition takes a date; a good reader doubts one. The skill
## term only bites above a middling reader, and is PROMISE_SKILL at a perfect one.
const PROMISE_BASE := 0.30
const PROMISE_KNOW := 0.25
const PROMISE_AMBITIOUS := 0.22
const PROMISE_SKILL := -0.30

## PRESSURE leans on the weak: low standing is easier, a popular president
## stronger; the networked and the stubborn push back.
const PRESSURE_BASE := 0.48
const PRESSURE_KNOW := 0.25
const PRESSURE_STANDING := -0.50
const PRESSURE_APPROVAL := 0.20
const PRESSURE_NETWORKED := -0.16
const PRESSURE_STUBBORN := -0.12

## FLATTER works on the vain who read poorly; a good reader sees through it.
const FLATTER_BASE := 0.48
const FLATTER_KNOW := 0.20
const FLATTER_VAIN := 0.40
const FLATTER_SKILL := -0.40

## APPEAL TO FRIENDSHIP: offered only to a friend or a close person, and strong.
const FRIEND_BASE := 0.60
const FRIEND_KNOW := 0.25
const FRIEND_CLOSE := 0.10
const FRIEND_BONDS := ["friend", "close"]

## The fog (B4): the printed range is FOG_STRANGER wide below the acquaintance
## edge, narrows linearly to FOG_KNOWN at the known edge and stays there. The
## edges are president_constants.gd's, so B4's bands and the fog cannot drift.
const FOG_STRANGER := 0.36
const FOG_KNOWN := 0.08
## The fog's offset is re-drawn at every step of this much knowledge (QA's R1):
## the smallest gain a topic gives a well-known person is about 0.01.
const FOG_SEED_STEP := 0.01

## A trait shows at a seeded point between this fraction of the known edge and
## the edge itself: a stranger sees none, a known person all of them.
const TRAIT_REVEAL_FLOOR := 0.1

## What a lever that works buys, in the two channels people-model 14.1 names (no
## third number): the request settles without the decline price, plus loyalty
## and a grudge's relief. Flatter buys only the settle -- its effect is small and
## does not hold (the spec's dominance matrix).
const LOYALTY_ACCEPT := 0.05
const GRUDGE_ACCEPT_RELIEF := 0.05

## The spends, paid win or lose (the spec's levers table). A favour is rapport
## spent; a vote trade is an IOU due IOU_MONTHS on; AID is not in b2 (it needs a
## budget line of its own -- the parent's call).
const BARGAIN_FAVOUR_RAPPORT := 0.10
const IOU_MONTHS := 12
const CURRENCY_FAVOUR := "favour"
const CURRENCY_VOTE_TRADE := "vote_trade"
const CURRENCY_AID := "aid"
## A promised date the president names, inside this window from now: too near is
## not a promise, too far is not a date.
const PROMISE_MIN_MONTHS := 3
const PROMISE_MAX_MONTHS := 24
## Pressure spends rapport, and writes a grudge pulse on success as on failure.
const PRESSURE_RAPPORT := 0.06
const PRESSURE_GRUDGE := 0.04
## A failed flatter backfires on a principled reader above a middling one. Not
## 0.6, the first draft: France's sixteen principled people read at 0.35-0.59, so
## at 0.6 the backfire could never fire in the played nation; above the middle,
## ten of them see through it.
const FLATTER_BACKFIRE_SKILL := SKILL_MIDDLING
const FLATTER_BACKFIRE_RAPPORT := 0.08

## The other topics buy knowledge and rapport, never a vote. Every knowledge gain
## is amount * (1 - knowledge), so knowing someone well takes many evenings (B4:
## acquaintance in 2-5 audiences with a topic, known in at least 8). Dinner is the
## richest and once an audience; gossip teaches the president about the THIRD
## person only (spec C1).
const KNOW_TOPIC := 0.07
const RAPPORT_TOPIC := 0.04
const KNOW_DINNER := 0.10
const RAPPORT_DINNER := 0.08
const KNOW_GOSSIP := 0.05
const RAPPORT_GOSSIP := 0.02

const SALT_ROLL := "lever"
const SALT_FOG := "fog"
const SALT_TRAIT := "trait"

## A promise and an IOU are judged at their date, with no roll (spec, the lies
## table: "a broken dated promise IS a lie revealed at its date"). Kept, a promise
## buys rapport; broken, it is a lie -- rapport and knowledge collapse and a grudge
## pulses. An IOU unpaid is a betrayal, not a lie: rapport and a grudge, and the
## president's knowledge of the person stands.
const PROMISE_KEPT_RAPPORT := 0.10
const LIE_RAPPORT := 0.5
const LIE_KNOWLEDGE_KEEP := 0.5
const LIE_GRUDGE := 0.15
const IOU_BETRAYAL_RAPPORT := 0.2
const IOU_BETRAYAL_GRUDGE := 0.08
