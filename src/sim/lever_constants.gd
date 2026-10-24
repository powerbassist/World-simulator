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

## PROMISE A DATE: ambition takes a date; a good reader doubts one. The skill
## term only bites above a middling reader (0.5).
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

## A trait shows at a seeded point between this fraction of the known edge and
## the edge itself: a stranger sees none, a known person all of them.
const TRAIT_REVEAL_FLOOR := 0.1

const SALT_ROLL := "lever"
const SALT_FOG := "fog"
const SALT_TRAIT := "trait"
