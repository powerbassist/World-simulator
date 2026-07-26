extends RefCounted

## Every tunable in the government model, in one file. Same shape as
## economy_constants.gd, opinion_constants.gd, election_constants.gd and
## legislature_constants.gd — model parameters, not content, so not in data/,
## per docs/engine-decision.md Rule 1.
##
## Rationale for every number is docs/government-model.md; this file is the
## values, that is the argument.

# --- Formation -----------------------------------------------------------------

## The seat fraction a formation search tries to clear. A coalition holding
## strictly more than half the chamber is a majority government; anything less
## is a minority government, which is a legal outcome, not a failure.
const MAJORITY_FRACTION := 0.5

## How far from a government's agreed position a party will go to join it.
## Beyond this it refuses, whether or not a formal cordon exists between them.
##
## Without this the greedy search will take any partner that closes an
## arithmetic gap: on the authored Italian roster it seated a left-populist
## party in a nationalist-right government, because the left's cordon had
## excluded everyone else and nothing else could reach 201. A minority
## government is the honest answer there, and Italy has had plenty.
##
## 1.2 sits a little beyond one full axis-width in a space whose axes each run
## [-1, +1]. Wide enough for a grand coalition across the economic axis, narrow
## enough to refuse a partner sitting in the opposite corner.
const MAX_PARTNER_DISTANCE := 1.2

## Below this share of the chamber a party is not seated in a directorial
## executive. Switzerland's magic formula seats the four largest parties; at the
## authored Swiss roster this cut-off selects exactly those four.
const DIRECTORIAL_MIN_SEAT_SHARE := 0.14

# --- Coalition cohesion ----------------------------------------------------------

## How fast a partner's enthusiasm for the government line falls off with
## distance from the agreed position. Tighter than legislature_constants'
## LAW_SIGMA (0.6) is not wanted here: a coalition partner has signed an
## agreement, so it tolerates more distance on an individual bill than a party
## judging that bill cold. Looser, at 0.9, so a partner one axis-width from the
## agreed position still delivers roughly half the bonus.
const COALITION_SIGMA := 0.9

## The largest bonus a perfectly disciplined party sitting exactly on the agreed
## position adds to its support for a government bill. Replaces
## legislature_constants.GOVERNMENT_BONUS, which was a flat 0.35 for one party;
## the ceiling is a little higher because it is now earned rather than given,
## and a distant or ill-disciplined partner scores well below the old flat rate.
const COALITION_BONUS_MAX := 0.45

# --- Censure ---------------------------------------------------------------------

## Fraction of the chamber's *total membership* a censure motion must exceed
## under the two absolute-majority rules. France's 289 of 577 is exactly this:
## abstentions and absences count as against, which is why French minority
## governments survive. `simple_present` compares supporters against opponents
## instead and never reads this table; `none` cannot be reached at all.
const CENSURE_ABSOLUTE_FRACTION := 0.5

## Censure rules that measure against total membership rather than against the
## parties actually voting.
const ABSOLUTE_CENSURE_RULES: Array[String] = ["absolute_members", "constructive_absolute"]

# --- Article 49.3 ----------------------------------------------------------------

## Months before the government may force another bill through without a vote.
## Real 49.3 is limited to one non-budget bill per parliamentary session; a
## twelve-month lockout is the same shape without modelling sessions.
const FORCE_COOLDOWN_MONTHS := 12

## Added to every party's hostility when a censure motion follows a forced bill.
## Forcing is what turns an abstainer into a censure vote -- without this term
## 49.3 would be a free pass on any bill, since the numbers that would censure a
## government are the numbers that would already have voted the bill down.
const FORCE_HOSTILITY_BONUS := 0.35

## Applied to every bloc when a bill is forced through, whether or not the
## censure motion that follows carries. Without a cost on use, Article 49.3 is
## strictly dominant: a government that can cover the censure threshold would
## force every bill the assembly would otherwise reject, for nothing. Surviving
## a censure motion is not the same as getting away with it -- the 2023 pension
## reform survived by nine votes and cost the government heavily in the polls.
const FORCE_BLOC_PENALTY := -0.08

## Applied to every bloc's approval target when a government falls, through the
## law_bloc_offset accumulator opinion.gd already reads. A collapse is a visible
## political failure and the opinion model has no other channel for one; routing
## it through the existing accumulator means inertia and every bound in
## docs/opinion-model.md still apply, exactly as they do for a law.
const FALLEN_BLOC_PENALTY := -0.12
