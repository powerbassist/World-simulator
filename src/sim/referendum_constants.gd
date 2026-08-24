extends RefCounted

## Referendum constants, V1.7c. Next to the other *_constants.gd files and not in
## data/, per docs/engine-decision.md Rule 1. The model and the rationale for both
## numbers is docs/referendum-model.md; this file is the values.
##
## ============================================================================
## THE YES-SHARE SHIPS NO CONSTANT AT ALL, WHICH IS THE HEADLINE
## ============================================================================
## src/sim/referendum.gd computes the popular vote as Elections.vote_share() with two
## "parties" -- the proposal at the law's own authored `position`, and the status quo at
## the size-weighted mean of election_constants.BLOC_IDEAL. Every number that reaches
## it already existed and was measured for something else:
##
##   AFFINITY_SIGMA      election_constants, S6, how affinity falls off with distance
##   INCUMBENT_SWING     election_constants, S6, what approval is worth at a ballot box
##   BLOC_IDEAL          election_constants, S5, derived from BLOC_SALIENCE_BASE
##   BLOC_SIZE           opinion_constants, S5
##   Campaign.turnout_of V1.7a, BLOC_TURNOUT as the campaign left it
##
## So the NO anchor is DERIVED rather than authored -- docs/media-model.md's V1.5d mean
## anchor, one block on -- and there is no dial that decides whether referendums pass.
## What decides is the law's authored position and the president's approval, which is
## the mechanic rather than a tuning.
##
## THE DECLARED ESCALATION FIRED, and the constant below is it. Named before the sweep
## ran: if tools/referendum_probe.gd finds every authored amendment unwinnable at every
## REACHABLE approval, the answer is a single STATUS_QUO_PULL scaling the NO weight --
## status-quo bias measured rather than accidental. It is NOT a raised INCUMBENT_SWING,
## which is measured for the election and would re-baseline every election this project
## has ever run. See STATUS_QUO_PULL below and docs/referendum-model.md section 6.


## How heavily the status quo is weighted against the proposal, before either is
## renormalised. 1.0 is the un-escalated model: NO sits at the electorate's own
## size-weighted mean, which is by construction the most broadly acceptable point in
## the space, so every proposal starts at a structural disadvantage.
##
## THE PROBE FIRED THE ESCALATION AND ALSO CORRECTED THE TEST THAT WAS SUPPOSED TO
## CATCH IT. Table R1's first kill switch swept approval from 30 to 65 and cleared --
## four of seven amendments winnable "somewhere". Table R6 then measured what a French
## president can actually reach under a budget they can hold office on: 40.6 to 50.3
## over fourteen years, against a crossover at ~52. The verb was winnable only at
## approvals no reachable government has. V1.3f's measuring-the-wrong-state error, a
## fifth time, inside the file written to avoid it -- and the fix is that a kill switch
## sweeping a range the player cannot reach is not a kill switch.
##
## Band, and it is the honest one because it is written on the MECHANIC rather than on
## a margin: the approval at which a reachable amendment crosses REFERENDUM_MAJORITY
## must lie strictly INSIDE the reachable approval range, so that being popular is what
## wins a referendum and being unpopular is what loses one. Outside it in either
## direction the vote is decided before it is called -- above, nothing ever carries;
## below, everything does, and the price is free money.
##
## Selected by putting the crossover nearest the MIDDLE of the reachable range, which
## is the only tiebreaker that does not privilege one outcome: a crossover at either
## end makes one result the default. Not smallest-passing and not largest -- V1.5b's
## finding is that a one-sided rule lets the swept range choose.
##
## MEASURED. Reachable approval under `managed` is [40.0, 50.3]; the crossover moves
## 34.87 -> 57.97 across a 0.70-1.10 sweep and lies inside the range for 0.80, 0.85,
## 0.90 and 0.95. Nearest the middle (45.1) is 0.90, at a crossover of 46.42 --
## interior to the passing set AND to the swept grid, so it is a result rather than a
## suspect. Iterated to a FIXED POINT: the sweep re-run at the shipped value selects
## the shipped value. The kill switch then reads 2 of 7 amendments winnable inside the
## reachable range and 7 losable, which is what CLEARED means here.
const STATUS_QUO_PULL := 0.90

## How long between calling a referendum and holding it.
##
## Band (i): the yes-share at resolution must differ measurably from the yes-share at
## announcement, or the delay buys nothing and the verb is an instant vote wearing a
## countdown -- which is the strictly-dominated shape this project has killed ten times,
## arriving as a decision that is not one.
## Band (ii): a referendum called in the first playable term must resolve inside it. The
## player inherits a term already in progress and France's presidential election is 16
## months out (docs/electoral-systems.md), so a delay that outruns it makes the verb
## unreachable for the term the game actually opens on.
##
## Selected by MAXIMIN SLACK over the feasible region -- docs/campaign-model.md's V1.7a
## tiebreaker, one session on, because the interior of a passing LIST is a statement
## about the grid and V1.5b's finding is that a grid must never choose. A value sitting
## at an endpoint of the swept range is a suspect, not a result.
##
## MEASURED. One point of approval is worth 0.4387 points of yes share, so band (i)
## needs a median drift above that: it fails at 1, 2, 3, 4 and 6 months and passes from
## 8. Band (ii) cuts at 16, and the sweep runs to 24 so the upper edge is proved to be
## the MODEL'S rather than the grid's -- 18, 20 and 24 all pass (i) and fail (ii).
## Passing: [8, 10, 11, 12, 13, 14, 16]. Maximin slack picks 11, at 0.313, interior to
## the passing set. Fixed point: the sweep re-run at 11 selects 11.
const REFERENDUM_DELAY_MONTHS := 11

## What the result is worth, in points on ns.bloc_offset, applied to every bloc.
##
## THE PRICE EXISTS BECAUSE ROUTE B IS OTHERWISE FREE. With no price the effective
## amendment bar is min(supermajority, popular majority) and the player takes whichever
## is easier at no cost -- the strictly-dominated shape a tenth time. Signed both ways,
## the treatment V1.4b gave deregulation and V1.5b gave migration: a won referendum is a
## mandate and a lost one is a rebuke, and a one-way charge would make calling one
## strictly worse than not calling one, which is the same failure mirrored.
##
## Band (i): at least what one point of approval is worth, V1.7a's ruler -- a result the
## published polls cannot resolve is a result the player cannot act on.
## Band (ii): the worst reachable stack leaves legislature_constants.BLOC_OFFSET_MAX
## slack, so the clamp is a guard rail rather than the thing setting the number
## (V1.6d's and V1.6e's correction, which is that a band measuring a clamp measures
## nothing).
##
## CLOSED FORM, and the grid in the probe is only there to show that it is one. The
## approval response is exactly linear at 10.0000 points of approval per point of
## offset, measured at two offsets and required to agree, so band (i) solves to
## [0.1000, 0.3000] and band (ii) -- four results reachable in fourteen years at
## REFERENDUM_DELAY_MONTHS plus the loser's 24-month cooldown -- to below 0.2500. The
## feasible interval is [0.1000, 0.2500], band (ii) binds above, and the midpoint is
## 0.1750. Iterated to a fixed point: the delay chosen above sets how many results a
## run reaches, which sets band (ii), which sets this. V1.6e's discipline that a
## closed form beats a swept row.
const REFERENDUM_RESULT_OFFSET := 0.175

## The popular bar. Not swept and not tunable: a referendum carries on a majority of
## votes cast, which is a real number rather than a dial. Switzerland's real double
## majority of the people AND the cantons is not modelled -- this game has no cantons --
## and docs/referendum-model.md records that as a named reduction, the same shape
## docs/electoral-systems.md's per-method caveats already use.
const REFERENDUM_MAJORITY := 0.5

## Modes a nation's constitution may declare for the referendum route, dispatched in
## src/sim/referendum.gd, never on the nation id -- docs/engine-decision.md Rule 1 and
## the SEVENTH instance of the dispatch-on-a-data-string pattern formation_method,
## censure_rule, dissolution_rule, lose_condition, head_of_state_kind and
## amendment_rule already use.
##
##   none       there is no referendum route; the assembly supermajority is the only
##              path. DEU (Art. 79), GBR (ordinary Act), BEL and NLD (dissolution and
##              re-election instead), AUT (referendum only for a total revision, which
##              no content in this game writes).
##   optional   the head of state may choose the referendum instead of the
##              supermajority. FRA (Art. 89), ITA (Art. 138), ESP (Art. 167), LUX
##              (Art. 114).
##   mandatory  there is no seats-only path at all. CHE (Art. 195).
const MODE_NONE := "none"
const MODE_OPTIONAL := "optional"
const MODE_MANDATORY := "mandatory"
const KNOWN_MODES: Array[String] = [MODE_NONE, MODE_OPTIONAL, MODE_MANDATORY]
