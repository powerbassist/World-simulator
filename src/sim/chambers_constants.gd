extends RefCounted

## Second-chamber constants, V1.1e. Next to the other *_constants.gd files and not in
## data/, per docs/engine-decision.md Rule 1. The model and the rationale for every
## number is docs/upper-house-model.md; this file is the values.
##
## ============================================================================
## THE COMPOSITION SHIPS NO ELECTION, WHICH IS THE HEADLINE
## ============================================================================
## The design that suggests itself -- run Elections.vote_share() again with a different
## electorate -- is wrong for eight of the ten, and the nation files say so. NOT ONE of
## the ten upper houses is elected by the national electorate: France's Senat by about
## 162 000 grands electeurs, Germany's Bundesrat delegated by Land governments, the
## Lords appointed, the Dutch Eerste Kamer chosen by provincial councils, Spain's Senado
## four per province, Switzerland's Standerat two per canton. Only Italy's Senato and
## Switzerland's Standerat are directly elected at all, and Italy's is elected by the
## same electorate on the same day -- which is exactly why Italian bicameralism is
## called "perfect" and reproduces the lower chamber's majority.
##
## So a second chamber is the LOWER CHAMBER, LAGGED -- and the only machinery it needs
## is ElectoralSystems.pr_national(), written at S6 to turn a share into seats. This
## file adds two numbers: how fast the chamber renews, and how long a suspensive
## refusal holds a bill.
##
## ============================================================================
## AN IDEOLOGICAL TILT WAS DESIGNED, MEASURED AND DELETED
## ============================================================================
## The first model gave each nation an `electorate` key naming the slice of the country
## that returns its second chamber -- `rural` for France's grands electeurs -- and
## re-weighted the lower chamber by each party's affinity for that bloc's ideal point.
## Swept, it put `front_souverainiste` at 122 of France's 348 senators at a tilt of 1.0
## and 267 at 4.0, which is the nationalist right running the Senat. That is the
## opposite of the real chamber -- the RN has almost no senators precisely BECAUSE the
## indirect election through municipal councillors filters it out -- and the cause is
## structural rather than a bad choice of bloc: every socially-traditional bloc ideal in
## election_constants.BLOC_IDEAL sits nearest `nationalist_right`, so any anchor that
## means 'small-town and conservative' hands the chamber to it.
##
## The replacement was worse in a more interesting way. Anchoring on the lower
## chamber's OWN seat-weighted centre -- the establishment reading, and a derivation
## with no authored field at all -- made the second chamber refuse ZERO of the bills
## the first one carried at every tilt from 1.0 to 6.0, and CARRY up to nine it had
## rejected. Moderation concentrates a chamber where the laws are, so it is a more
## permissive body and not a check.
##
## ============================================================================
## WHAT MAKES IT A CHECK WAS ALREADY THERE, AND IT COSTS NOTHING
## ============================================================================
## src/sim/legislature.gd resolves the second chamber on `spatial_support()` and the
## first on `support()`, and the difference between those two IS the coalition bonus.
## A government bill carries the Assembly because the coalition is whipped; the Senat
## has no government in it and no whip on it, so it votes on the bill alone. That is
## the French dynamic exactly, it is true of the Bundesrat and the Lords as well, and
## it needs no constant -- so the tilt was not replaced by a better tilt, it was
## removed. THE SECOND CHAMBER IS THE ASSEMBLY YOU USED TO HAVE, VOTING WITHOUT YOUR
## WHIP: unwhipped from the start, and out of date from the first election onward.

## What an upper house does to a bill it refuses. Two rows per nation --
## `government.upper.ordinary` and `government.upper.amendment` -- because the real
## distinction is not between chambers but between CLASSES OF BILL, and the nation files
## carry the citations: France's Senat delays an ordinary bill (Art. 45 gives the
## Assembly the last word) and cannot be overridden on a revision (Art. 89); Germany's
## Bundesrat is the same shape at Arts. 77 and 79(2); Belgium's Senate does not see an
## ordinary bill at all since 2014 but keeps full competence under Art. 195.
##
## A single-valued enum could not say that without a fourth and fifth value meaning "the
## first thing for ordinary bills and the second for amendments", which is two facts
## wearing one name. Two rows of three values is the smaller schema AND the truer one.
##
##   none        the chamber does not see this class of bill.
##   suspensive  a refusal HOLDS the bill for UPPER_HOLD_MONTHS and it then passes.
##   absolute    a refusal kills the bill.
const VERDICT_NONE := "none"
const VERDICT_SUSPENSIVE := "suspensive"
const VERDICT_ABSOLUTE := "absolute"
const KNOWN_VERDICTS: Array[String] = [
	VERDICT_NONE, VERDICT_SUSPENSIVE, VERDICT_ABSOLUTE,
]

## Guard rails on the authored seat count, not levers. The roster spans Switzerland's
## 46 to Britain's ~800, and the Lords has no fixed statutory size at all -- so the
## upper bound is generous on purpose and the lower one only refuses a chamber too
## small for a majority to mean anything.
const MIN_SEATS := 10
const MAX_SEATS := 1000

## What share of the chamber is renewed at each legislative election, the rest carrying
## over. A first-order step on the chamber's SHARE rather than on its seats, because
## seats are integers and a partial renewal of them is a rounding rule pretending to be
## a model -- docs/defence-model.md's capability_step() shape a sixth time.
##
## THIS IS THE LAG, AND IT IS THE SECOND HALF OF THE CHECK. The first half is the
## missing whip, which costs nothing and works from month one; this is what stops a
## landslide sweeping both chambers on the same day. France's Senat is a check
## precisely because it survived 2012 and 2017.
##
## MEASURED, and then SET ON THE REAL ARRANGEMENT because the real arrangement is
## inside the passing set. Half of France's Senat is renewed every three years on a
## six-year term, which over one legislative cycle is about half the chamber -- so 0.50
## is not a tuning, it is the figure, and the sweep is there to show it is feasible
## rather than to choose it.
##
## Table U2 on a 0.05 grid. Band (i), the lag must SURVIVE a career: after the two
## legislative elections a French president lives through, the Senat must still differ
## from the Assembly by more than one seat of the smallest chamber on the roster
## (1/46 = 0.0217). Fails from 0.65 up. Band (ii), a career must be able to MOVE it:
## the lag decays geometrically, and the elections needed to reach that floor must be
## at most the THREE a fourteen-year run holds. Fails below 0.45, at 3.26 elections.
## Passing [0.45, 0.60]; 0.50 catches up in 2.08 elections and sits interior on both
## sides.
##
## BAND (ii) WAS WRONG TWICE AND THE SECOND TIME IS THE INSTRUCTIVE ONE. The first
## version only asked that the distance FALL, which every rate above zero satisfies, so
## the passing set ran to the bottom of the grid and V1.5b's diagnostic fired -- a value
## at an endpoint of the swept range is a suspect rather than a result. The second asked
## it to HALVE across two elections, which is a ratio nobody measured, and it cut
## France's real 50 % by a hair: 0.532 against a threshold of 0.500. An invented
## threshold that lands within 6 % of the real figure is not a check, it is a coin toss
## with a rationale. The third is anchored on the harness's own horizon.
const UPPER_RENEWAL := 0.50

## How long a `suspensive` refusal holds a bill before it passes anyway.
##
## THE HOLD IS PURE TIME, THE PROBE CHECKED WHETHER TIME IS A COST, AND THE ANSWER WAS
## NO. docs/calendar-model.md's U6a finding is that every observable here is
## piecewise-constant across a month, so a deferral that buys nothing is the
## strictly-dominated shape this project has killed ten times. Table U3 swept the hold
## against the widest per-bloc approval spread between a bill in force from month one
## and the same bill arriving N months later: 1 month moves the worst bloc 0.0227
## points, 6 months 0.3557, 12 months 2.3655 -- all under the 3.0 poll floor -- and the
## first candidate to clear it is 15, which is one month short of the whole first
## playable term. A hold that only registers when it consumes the term is not a delay,
## it is a block with a countdown on it.
##
## THE ESCALATION THIS FILE DECLARED IN ADVANCE THEREFORE FIRED, and it was honoured by
## the response the plan named rather than by lengthening this number: the RELEASE
## carries a price. See UPPER_OVERRIDE_OFFSET below.
##
## With the price carrying the legibility, this number is SET BY ARGUMENT and says so
## -- docs/unrest-model.md's UNREST_COOLDOWN_MONTHS, where every candidate passed. One
## year is the Parliament Acts 1911 and 1949 figure, the longest suspensive veto on the
## roster and the only one a statute states rather than practice settling (Spain's
## Art. 90 override is two months, France's Art. 45 last word is whenever the
## Government asks). It also satisfies the one band that is not about legibility: a
## bill held on day one arrives inside the first playable term, which is 16 months.
const UPPER_HOLD_MONTHS := 12

## How much of the government's whip survives into the second chamber.
##
## THE PROBE'S THIRD MODEL CORRECTION THIS SESSION, and the sharpest, because it was
## caught by tests/test_save_load.gd rather than by a sweep. The design was that the
## second chamber votes on Legislature.spatial_support() alone -- no coalition bonus,
## because there is no government in it and no confidence vote to lose. Measured, that
## chamber refuses SEVEN OF SEVEN authored constitutional amendments: France's Senat
## reads `single_term_reform` 63-156 where the Assembly carries it 308-210. Since
## France's amendment row is `absolute` under Art. 89, that makes every amendment in
## the game unpassable and kills docs/referendum-model.md's whole verb one session
## after it shipped -- a regression, not a mechanic.
##
## What was wrong is the claim rather than the number. No whip at all is not `unwhipped`,
## it is `no government exists`: senators belong to the same parties as deputies, and a
## government's own parties vote for its bills in both chambers. What the second chamber
## lacks is the THREAT -- it cannot bring the government down, so the whip is weaker
## there, not absent. The real Senat has passed twenty-four revisions since 1958.
##
## Band, written on the two things that must both be true:
##   (i)   the chamber must refuse at least one ordinary bill the Assembly carries, or
##         it is a second reading and not a second chamber;
##   (ii)  at least one authored amendment must survive BOTH chambers, or V1.2c's
##         amendment machine and V1.7c's referendum are dead in the nation the game is
##         about;
##   (iii) a MAJORITY of the ordinary bills the Assembly carries must survive, or the
##         country cannot legislate.
##
## MEASURED. Table U5 sweeps [0.00, 1.00] on a 0.05 grid against France's own roster:
## band (i) fails from 0.70 up, where the Senat refuses nothing the Assembly carries;
## band (ii) fails below 0.15, where no amendment survives both chambers; band (iii)
## never binds, because the worst refusal count is 5 of the 13 bills the Assembly
## carries. Passing [0.15, 0.65]; both edges are the MODEL'S and both are interior to
## the swept range, so the midpoint selects -- V1.5c's rule for a two-sided interval.
##
## WHAT 0.40 BUYS: the Senat refuses 3 of the 13 ordinary bills the Assembly carries,
## and 2 of the 7 authored amendments survive both chambers. France can still amend its
## constitution and still has to fight for it, which is the shape Art. 89 describes.
const UPPER_WHIP := 0.40

## What overriding the second chamber costs, in points on every bloc's `bloc_offset`.
##
## THE PRICE IS ON THE RELEASE AND NOT ON THE REFUSAL, because that is when the
## government has actually insisted. Art. 45 lets the French Government ask the
## Assembly to rule definitively and the Parliament Acts let the Commons pass a bill
## over the Lords a session later; both are political acts, and a second chamber
## overridden for free is a second chamber that does nothing.
##
## Routed through Government.penalise_blocs(), which is Article 49.3's own accumulator
## and the one a fallen government, a reshuffle, a resignation and a dissolution all
## already use -- so this session adds a price and no channel.
##
## CLOSED FORM, and the probe's grid is only there to show that it is one.
## docs/referendum-model.md measured the approval response to `bloc_offset` as exactly
## linear at 10.0 points of approval per point of offset, checked at two offsets and
## required to agree. So band (i) -- at least what one point of approval is worth,
## V1.7a's ruler -- solves to 0.1000, and band (ii) -- the worst reachable career of
## overrides must leave legislature_constants.BLOC_OFFSET_MAX slack, which is the
## correction V1.6d and V1.6e both made, that a band measuring a clamp measures nothing
## -- solves against the override count table U0 prints.
##
## MEASURED, AND THE CAREER BOUND IS WHAT CHOSE IT -- docs/events-model.md's E1b in a
## new place, where a per-decision band passed while a career of the same decision
## saturated the clamp by a factor of four and every regime converged on the same
## floor. Table U0's played run releases THIRTEEN held bills over fourteen years, and
## the first version of this constant at 0.15 stacked those to 1.95 against a
## BLOC_OFFSET_MAX of 1.00 -- the run's worst bloc reached the clamp exactly.
##
## Table U4, swept: one override costs 0.79 points of headline approval at 0.02, 1.58
## at 0.04, 2.38 at 0.06 and 3.17 at 0.08, and the career stack passes 1.00 at 0.08. So
## band (i) cuts below 0.04 and band (ii) above 0.06; passing [0.04, 0.06], midpoint
## 0.05. Two model edges, so the midpoint selects -- V1.5c's rule.
const UPPER_OVERRIDE_OFFSET := 0.05
