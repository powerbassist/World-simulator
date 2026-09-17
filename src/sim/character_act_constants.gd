extends RefCounted

## The character layer's PRICE constants -- the swept half. character_constants.gd
## holds the schema (what validates); this file holds the numbers the probe
## sweeps, so the two never share a file the way programme's dial never lived
## beside its vocabulary. Rationale for every number is docs/people-model.md
## section 14.6's DECLARED bands and the sweep verdicts recorded beside them;
## this file is the values, that file is the argument.
##
## *** EVERY NUMBER HERE IS PRE-DECLARED THEN SWEPT BY tools/characters_probe.gd,
## and the probe's verdicts are the record -- a later session retuning one
## re-runs the probe rather than editing on opinion. ***

## The act vocabulary, in the order tick_month evaluates them. Order is
## determinism, not priority: one act per person per month, and the same
## person in the same state always resolves to the same act.
const ACT_KEYS := ["resign", "defect", "challenge", "brief_against"]

# --- Standing seed ---------------------------------------------------------------------

## Where standing starts: everyone gets the base, ambition adds linearly, and
## the ambitious TRAIT adds its own floor -- the scalar is the dial, the trait
## is the floor (14.2's distinction, priced here for the one place it is read).
const STANDING_SEED_BASE := 0.3
const STANDING_SEED_AMBITION := 0.4
const STANDING_SEED_AMBITIOUS_BONUS := 0.1

# --- Loyalty and grudge movement -------------------------------------------------------

## What one month's want read moves. Small by design: loyalty is a record
## built over a term, not a switch, and P1's idle band (<= 2 acts in 168
## months) is what the want-settling must NOT breach on its own.
const LOYALTY_WANT_SERVED := 0.02
const GRUDGE_WANT_DENIED := 0.02
const GRUDGE_ACT_RELIEF := 0.2

## Grudge decay, monthly, straight (the trait modifiers live in
## characters.gd where the person is in hand). Half-life ~= 14 months at
## 0.05 -- the programme stock's own decay shape, so "this term" is worth
## more than "last term" in both registers.
const GRUDGE_DECAY_MONTHLY := 0.05

## Loyalty's band.
const LOYALTY_MIN := -1.0
const LOYALTY_MAX := 1.0

# --- Act thresholds --------------------------------------------------------------------

## Resign when loyalty falls below this. Negative: a resigned minister has
## been actively harmed, not merely unserved.
const LOYALTY_RESIGN_FLOOR := -0.4

## Defect when the grudge passes this.
const GRUDGE_DEFECT_THRESHOLD := 0.6

## Challenge when standing passes this (ambition's discount below it).
const CHALLENGE_STANDING_THRESHOLD := 0.7
const CHALLENGE_AMBITIOUS_DISCOUNT := 0.1

## Brief against when the grudge passes this -- below the defection
## threshold, because leaking is what a frustrated ally does on the way out.
const GRUDGE_BRIEF_THRESHOLD := 0.45

# --- Prices ----------------------------------------------------------------------------

## All prices are POINTS of bloc_offset, weighted by the actor's standing
## (0.5x at standing 0, 1.5x at standing 1). They are the government-price
## primitive's units, and the probe's P4 (total approval movement per year
## within +-3.0) is the readability bound the sweep answers.
const PRICE_RESIGN := 0.8
const PRICE_DEFECT := 0.5
const PRICE_CHALLENGE := 0.6
const PRICE_BRIEF := 0.25

## The networked trait's multiplier on a brief's magnitude (14.2's table).
const NETWORKED_MAGNITUDE := 1.5

## The loyal trait's grudge-relief factor when a grudge-decaying act fires
## (they let go of it, rather than marinating) -- 0.5, the table's "grudge
## from betrayal x0.5" read on the relief side.
const LOYAL_GRUDGE_RELIEF := 0.5
