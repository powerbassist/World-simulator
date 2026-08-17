extends RefCounted

## Tuned constants for unrest — V1.5c, the third session of the V1.5 block. The model,
## and the justification for every number here, is docs/unrest-model.md.
##
## Every value below was set by tools/unrest_probe.gd against a band AND a tiebreaker
## fixed BEFORE the sweep ran, and this session inherits three corrections to that rule
## rather than one: V1.4c's (fix the tiebreaker, not only the band), V1.5a's (a
## tiebreaker must strictly ORDER the survivors -- "below constant X" does not), and
## V1.5b's (it must also NOT MOVE when the candidate grid is widened, because two
## one-sided bands let the RANGE choose the constant).
##
## THE INHERITED RULE WAS NOT ENOUGH EITHER, and this file records four more ways a
## pre-committed measurement fails. Each is written beside the constant that found it,
## because a list of failures with no numbers attached is a doctrine rather than a
## record:
##
##   SETTLEMENT_BETA        V1.5b's own correction, INVERTED. "Smallest passing" is
##                          stable only while both bands are minimums; the moment the
##                          interval becomes two-sided it lands back on an edge. When
##                          both edges are MODEL criteria, take the midpoint. When one is
##                          a GUARD RAIL, the guard rail does not select.
##   UNREST_CONVERGENCE     A nearest-to-X tiebreaker is only as good as the grid's
##                          RESOLUTION. V1.5b's diagnostic is about widening; refining
##                          moved this one from 0.08 to 0.07.
##   UNREST_THRESHOLD_PCT   A band whose ceiling is ONE regime's measured peak makes
##                          "largest passing" mean "that peak, minus a rounding error".
##   UNREST_IMPULSE_SCALE   A band can be applied to an observable the channel does not
##                          reach. This one failed at every candidate and the constant
##                          was right; the band was measuring the wrong thing.
##
## UNREST_COOLDOWN_MONTHS is a fifth, and the oldest kind: every candidate passed, so
## the band was a bound and not a selector. It is set by argument and says so.


# --- Who is angry -------------------------------------------------------------

## Which voter blocs mobilise. A REGISTRY, not a mode flag -- society_constants'
## QUALITY_KEYS and src/ui/map_layers.gd's LAYERS -- and it is the reason this file
## carries no weights of its own: the grievance target reads each named bloc's OWN
## salience row out of opinion_constants.BLOC_SALIENCE_BASE, weighted by that bloc's own
## BLOC_SIZE share. Two existing tables, zero new numbers.
##
## THE EXCLUSIONS ARE THE DESIGN, the way QUALITY_KEYS' are. A national anger index
## already exists -- Discipline.unpopularity(), read by discipline.gd, government.gd and
## cabinet.gd -- so a target built on the whole electorate's satisfaction would be the
## military_capability / potential_shift_pct failure a fifth time: one quantity, two
## answers. What makes this a different quantity is that it is TWO ROWS and not six.
##
## And the division falls out of a table written at S5 for unrelated reasons, which is
## docs/bloc-model.md's finding a second time: workers weight `defence` at nothing and
## `tax_vat` at 0.08, which is exactly what balance_probe's `managed` regime moves. A
## well-governed France is structurally quiet, and nothing here authored that.
##
## tests/test_unrest.gd fails if `business` appears here. A business owner is not who
## strikes, and the row's own noun is "trade unions".
const UNREST_BLOCS := ["workers", "students"]


# --- The stock ----------------------------------------------------------------

## The grievance index, in points. UNREST_MAX is 100.0 and that is DEFINITIONAL rather
## than tuned: the hardship term arrives as a satisfaction in [-1, +1], so the stock is
## "percent of maximum grievance" and hardship 1.0 IS the maximum by construction. That
## is what keeps a hardship scale constant out of this file entirely --
## DEPENDENCY_ELASTICITY["pensions"] = 1.0's treatment at V1.5b, and called out for the
## same reason: a bare 100.0 in a tuned-constants file is a number a later session finds
## and sweeps.
##
## The floor is 0.0 and not negative. A country happier than it started is not
## *organising*; it is quiet, and quiet has one value. That is the one place in this
## file where a signed quantity was deliberately made one-sided, and it does not create
## defence-model.md's permanent monotone charge because the CHARGE is the act, not the
## level, and SETTLEMENT_BETA below can push the target back under the threshold.
const UNREST_MIN := 0.0
const UNREST_MAX := 100.0

## Fraction of the gap to target closed per month.
##
## BAND, fixed before the sweep, and two-sided by construction so it cannot suffer
## V1.5b's failure: the half-life must be SHORTER than service_quality's ~34 months (a
## grievance is not a hospital; anger organises faster than a health service decays) and
## LONGER than opinion's INERTIA_RATE ~2.4 months (else this is approval with a delay,
## and opinion_constants.gd's own comment forbids "two lags in series").
##
## TIEBREAKER: nearest the geometric mean of the two bracketing half-lives, which is
## ~9.0 months. Deliberately NOT "nearest CAPABILITY_CONVERGENCE" -- that tiebreaker
## worked for QUALITY_CONVERGENCE because a service and an army genuinely converge alike,
## and here it would reproduce 0.02 against a model reason that anger is faster.
## Interior to any grid that brackets the interval, so it is stable under widening.
##
## Full table: docs/unrest-model.md (a).
##
## RE-BASELINED AT V1.6a AND UNCHANGED, and unlike the threshold below the reason is
## structural rather than measured. This band is bounded by two OTHER constants'
## half-lives -- faster than society_constants.QUALITY_CONVERGENCE's ~34 months, slower
## than opinion_constants.INERTIA_RATE's ~2.4 -- and a business cycle moves neither, so
## the interval it was chosen from is the same interval. What the cycle could have
## broken is the stock's ability to TRACK a target that now oscillates: at 0.07 a month
## the half-life is 9.6 months, against a shortest cycle band of 29-47 months
## (cycle_constants.CYCLE_PERIOD_BANDS), so grievance follows the cycle with roughly a
## quarter-period lag rather than averaging it away. Checked, not assumed.
const UNREST_CONVERGENCE := 0.07


# --- The three terms of the target --------------------------------------------

## Points of unrest per point of Gini index the nation has drifted since the game began.
##
## THE DECLARED STOPGAP, and docs/tiers/v1.md §6 owns the instruments. There is no
## distribution in this model -- no brackets, no deciles, no capital/labour split -- so
## nothing the player does moves this number, which is the mechanical form of that
## split rather than a limitation to apologise for. Unrest.inequality_deviation() is a
## pure read of imported.inequality and the clock: no field, no accumulator, no save
## entry, Defence.allies()' shape.
##
## KILL SWITCH, fixed before the sweep: the measured drift must move the date of the
## first act at some candidate. If it cannot, this constant is DELETED and inequality
## ships as a readout that src/sim/ does not read -- DEPENDENCY_ELASTICITY["health"]'s
## treatment at V1.5b, where the entry was deleted rather than shipped at a value that
## looks alive in a constants file and is invisible in play.
##
## Measured on GERMANY and not on France, and that is the honest half: the roster's
## slopes run from the Netherlands at -0.417 to Germany at +0.329 points a year, six
## falling and four rising, and France's own is -0.113 -- so for the default nation this
## term is a small CALMING drift. The band is read on the widest playable riser, because
## a term that cannot be seen where it is largest cannot be seen anywhere.
##
## THE KILL SWITCH CLEARED, AND THE SURVIVING TERM IS SMALL: at 0.40, Germany's measured
## +4.61 points of drift over fourteen years brings its first act forward from month 36
## to month 35. One month in thirty-six. The selector is the pre-committed one -- the
## kill switch is a minimum with no model criterion above it, so the smallest passing
## candidate ships -- and the size is recorded rather than tuned away, because a stopgap
## that dominated the target would be the opposite failure. Section 6 owns the
## instruments, and an index nothing the player does can move should not decide the run.
##
## Full table: docs/unrest-model.md (d).
const INEQUALITY_BETA := 0.40

## Points of unrest removed per unit of settlement stance.
##
## BAND (i), CLOSABLE: a saturated stance holds unrest BELOW the threshold under a
## budget that would otherwise cross it. Written first as demography_probe.gd's "at or
## below where it started", lifted verbatim, AND IT DID NOT TRANSFER -- a dependency
## ratio rises forever so holding it flat is the only interesting question, where unrest
## converges on a bounded target. Under the borrowed wording (i) demanded a beta near 60
## and (ii) one under 29, and the interval was EMPTY: an artefact of the borrowed band
## rather than a fact about settlements.
## BAND (ii), NOT IMMUNISING: ONE authored settlement law must not do it alone. A single
## law that ends the mechanic forever is the strictly-dominated shape this project has
## now named six times, arriving as a free permanent cure.
##
## A FOURTH WAY A PRE-COMMITTED TIEBREAKER FAILS, and it is the mirror of V1.5b's.
## V1.5b's correction was that when both bands are one-sided minimums the SMALLEST
## passing candidate ships, because "largest" just returns the top of the grid. That was
## pre-committed here -- and once (i) was corrected the interval became genuinely
## TWO-SIDED, [7.3, 16.3], at which point "smallest passing" lands back on an edge and is
## grid-dependent all over again: 7.0 leaves unrest at 45.24 against a threshold of
## 45.0, so a 0.5 % model change flips it.
##
## The rule, extended: when the passing interval is bounded by TWO MODEL CRITERIA, take
## the value nearest its MIDPOINT -- interior by construction, and it moves only if the
## interval moves. When one edge is a GUARD RAIL rather than a model criterion, the
## guard rail does not select and the model edge governs; see UNREST_OPINION_SCALE
## above, which is that case and therefore keeps the smallest-passing rule.
##
## Midpoint of [7.3, 16.3] is 11.8, and 12.0 is the nearest candidate: unrest 40.34 at a
## saturated stance (11 % clear of the threshold) and 46.79 at one law (4 % above it).
##
## Full table: docs/unrest-model.md (e).
const SETTLEMENT_BETA := 12.0

## What a law may accumulate on ns.settlement_stance, signed. Not swept -- set from the
## authored settlement laws reachable inside 168 months, which is how CORRUPTION_MAX and
## MIGRATION_STANCE_MAX are set, and law.gd's SOCIETY_TERMS reads it as the per-law bound.
##
## SIGNED, for corruption's and migration's reason plus one of its own: an imposed
## settlement -- a pay freeze, a service minimum during a strike -- is the negative
## direction on the same accumulator, not a repeal verb. A one-way stance would make
## every settlement law inert on a calm state, which is V1.3f's property that nothing on
## the law list does nothing.
const SETTLEMENT_STANCE_MAX := 1.00

## V1.5d. How much a censored press adds to the grievance target, per point of
## ns.press_freedom. The register and its clamp belong to media_constants.gd; this
## coefficient lives here, beside the two it has to be compared against and inside the
## file whose target reads all three.
##
## THIS IS V1.5d'S ANSWER TO "PRESS FREEDOM AS A DIAL WITH LEGITIMACY COSTS", and the
## row handed that session the choice of inventing a legitimacy quantity or dropping the
## clause. Neither was taken, because the quantity already exists and this file owns it:
## legitimacy is willingness to accept your rule OUTSIDE the ballot box, and section 2 of
## docs/unrest-model.md says of this very stock that "a country can be angry for reasons
## its approval figure does not contain". Censorship is such a reason, and UNREST_BLOCS
## is ["workers", "students"] -- exactly who marches over it. Twenty-sixth instance of
## the stale-row failure, and the second in one session.
##
## Band:
##   (i)  a saturated censorship must move the date of the first act -- INEQUALITY_BETA's
##        band, reused unchanged because it is the same question about a different term;
##   (ii) it must NOT on its own push `hands_off` over UNREST_THRESHOLD_PCT. Band (i) is
##        a one-sided minimum and table (b) above is what happens when such a band has no
##        ceiling: a country with nothing else wrong must not strike merely because the
##        press was restricted.
## BOTH CLAUSES FAILED TO SELECT, AND THE CONSTANT IS SET BY ARGUMENT. Band (i) passes
## at EVERY candidate from 1.0 to 40.0 -- the grievance stock is continuous, so any
## positive term shifts the crossing month and "moves the date" orders nothing. That is
## UNREST_COOLDOWN_MONTHS' failure a fourth session running. Band (ii) is a real ceiling
## and would have killed any value past about 41.7, but selecting on it would mean
## "`hands_off`'s measured peak, minus a rounding error", which is table (b)'s failure
## above, verbatim. A sweep that cannot order is not made to order by picking an edge.
##
## THE ARGUMENT, and it is a ratio against the constant this one sits beside. A saturated
## settlement closes 12.0 points of grievance; a saturated censorship must open FEWER,
## because a pay settlement addresses the material hardship the stock is built out of
## while press restriction is a political provocation reaching two blocs of six. That is
## society_constants.QUALITY_SCALE_PP's ratio rule -- the indirect half is worth less
## than the direct half -- and a ratio against a fixed constant is stable under both
## widening and refinement, which is what neither band was.
##
## 8.0, two thirds of SETTLEMENT_BETA. THE SWEEP STILL EARNED ITS KEEP: it could have
## falsified this value through band (ii) and did not, it produced the legibility figure
## (under `managed>austerity` a saturated censorship moves the first act from month 57 to
## month 41, sixteen months earlier), and it left a calm country peaking at 11.28 against
## a threshold of 45.0. Full table: docs/media-model.md.
##
## SIGNED, so a freer-than-baseline press calms very slightly. Not for symmetry: without
## it a press-liberalisation law is inert on a nation that has never censored, which is
## the objection SETTLEMENT_STANCE_MAX answers one constant up and CORRUPTION_MAX answers
## a session before that.
##
## THERE IS NO FOURTH ANTI-DOUBLE-COUNT because of this term, and the one that WOULD have
## been warranted is refused in a signature instead. See law.gd's block and
## Opinion.salience_weights().
const PRESS_UNREST_BETA := 8.0


# --- The act ------------------------------------------------------------------

## Grievance at which industrial action fires.
##
## BAND, and it is two-sided on purpose because the first draft was not: (i) it must
## fire at least once under balance_probe's `austerity` inside 168 months, or the whole
## channel is unreachable and the balance harness's bit-identity would mean nothing --
## U6a's finding about the day loop, in a new place; and (ii) it must fire EXACTLY ZERO
## times under `hands_off` and under `managed`. Clause (ii) is doing three jobs at once:
## it turns a one-sided minimum into an interval, it is the reachability guard, and it
## is the cleanest available statement of *a well-governed France does not have a
## general strike*.
##
## TIEBREAKER: the largest passing candidate that still clears (i) with at least two
## fires. Interior to the interval, so stable under widening.
##
## Full table: docs/unrest-model.md (b).
##
## RE-BASELINED AT V1.6a AND UNCHANGED, which is a measurement rather than an omission.
## Every value in this file was set against a FLAT cycle, and docs/tiers/v1.md section 6
## says a cycle arriving there re-baselines this threshold and the convergence rate
## together. Band (ii) -- *fires exactly zero times under `hands_off` and under
## `managed`* -- is the half at risk, because a recession raises the hardship term
## through `jobs` and `growth`. Re-measured on BOTH harnesses at
## CYCLE_AMPLITUDE_PCT = 1.70: every peak rises (balance_probe's `hands_off` 3.29 -> 7.57,
## `managed` 5.31 -> 9.17) and the ACT COUNT IS UNCHANGED IN ALL 29 REGIMES -- zero
## everywhere except the two `managed_then_austerity` runs, which keep 2 and 1.
## tools/cycle_probe.gd table (f).
const UNREST_THRESHOLD_PCT := 45.0

## Months before the next act can fire.
##
## BAND: (i) more than one act inside a 60-month term under a sustained crisis, else the
## escalation labels below are dead content -- docs/trade-model.md's `refused_by_partner`
## failure; and (ii) short enough that the steady-state unemployment the acts add stays
## under a third of opinion_constants.JOBS_SCALE_PP, because a hardship term reading a
## SATURATED `jobs` satisfaction cannot tell bad from catastrophic and the escalation
## stops discriminating.
##
## Swept on a DISPLACED state and not on a new game. Unrest is exactly 0.0 at new game,
## so a new-game sweep of this measures nothing at all -- V1.3f's AGENDA_ACT_MIN error,
## which measured a static table and got an answer the live landscape did not share.
##
## AND THE BAND TURNED OUT TO BE A BOUND RATHER THAN A SELECTOR, which is the third time
## in three sessions -- V1.4c's, V1.5a's CORRUPTION_DELIVERY_BETA, and this. Every
## candidate from 3 to 36 months clears both clauses (36 still gives 1.43 acts a term,
## and even a 3-month cooldown adds only 0.12 points of unemployment), so the sweep
## ordered nothing. Set by ARGUMENT instead, and the argument is recorded rather than
## dressed up as a measurement: twelve months is one bargaining round a year, and it is
## what keeps a shock a shock -- IMPULSE_DECAY^12 = 0.28, so each act has decayed to
## under a third of itself before the next can fire. A cooldown short enough for the
## impulses to overlap would make industrial action a standing condition, and the whole
## decaying-not-sustained distinction this channel rests on would be false.
const UNREST_COOLDOWN_MONTHS := 12

## What the act is called, by intensity. A REGISTRY like UNREST_BLOCS, and the tiers are
## NOT constants: the span from UNREST_THRESHOLD_PCT to UNREST_MAX is divided evenly by
## the number of labels here, so adding a third name re-spaces the two without a number
## being touched. Two tuned constants avoided by making the shape carry it.
##
## THERE WERE THREE, AND `general_strike` WAS CUT BY MEASUREMENT. Over 168 months the
## reachable peak grievance is 52.3 under `austerity`, 48.2 under `spend_zero` and 78.1
## under `tax_max`; the third tier of a three-way split starts at 81.7, so no budget in
## the harness ever produced one. A label the model cannot reach is
## docs/trade-model.md's `refused_by_partner` failure -- a figure computed and displayed
## nowhere -- so it is deleted rather than left in a list looking alive, which is
## DEPENDENCY_ELASTICITY["health"]'s treatment at V1.5b and the day budget's at U6a. At
## two labels both are reachable: `protest` under austerity, `strike` under tax_max.
##
## THE LABEL IS DISPLAY ONLY. It is written onto the act record and read by
## src/ui/message_stack.gd; nothing in src/sim/ reads it back, and tests/test_unrest.gd
## asserts that -- V1.3f's foreign_acts property, which is what keeps this one machine
## with three names rather than three machines wearing the row's vocabulary.
const ACT_LABELS := ["protest", "strike"]

## Points of annual growth a general strike costs at maximum grievance. The impulse
## scales linearly with the stock, so an act at the threshold costs its share and an act
## at the clamp costs all of it.
##
## BAND, pre-committed: legible on the workers bloc approval row past +-3.0, through
## `jobs` and `growth` and no direct opinion term at all.
##
## IT FAILED AT EVERY CANDIDATE, AND THE FAILURE IS THE SESSION'S CENTRAL FINDING rather
## than a bad grid. Fourteen years at maximum grievance costs 4.94 % of GDP at this
## value and moves the workers row 0.42 points, because the opinion model prices RATES
## and a permanent LEVEL loss is invisible to it -- see UNREST_OPINION_SCALE above,
## which exists because of this table. The band was applied to an observable this
## channel does not reach: V1.5a's QUALITY_SCALE_PP error in a new form, where that band
## was measured on a path that could not observe the channel and this one was measured
## against the wrong channel entirely.
##
## What selects instead is the half of the pre-committed tiebreaker that DID
## discriminate, plus the argument the clamp below already makes. The saturated impulse
## must leave UNREST_IMPULSE_MAX_PCT strictly slack, which excludes 3.0 and everything
## above it; and the accumulated peak must sit between FIRM_IMPULSE_MAX_PCT (2.00) and
## COERCION_IMPULSE_MAX (6.00), because a strike is a bigger shock than a subsidy
## programme and a smaller one than an embargo by your largest partner. At 2.0 the peak
## is 2.787 -- inside both, and the largest candidate that is.
##
## Full table: docs/unrest-model.md (c).
const UNREST_IMPULSE_SCALE := 2.0

## How much a country at maximum grievance takes off every bloc's approval target, on
## the [-1, +1] scale opinion_constants.gd's satisfaction terms use.
##
## THIS CONSTANT EXISTS BECAUSE THE PROBE REFUTED THE DESIGN, and that is the session's
## central correction. The price was to be OUTPUT ONLY, on the premise that approval
## would fall through `growth` and `jobs` -- issues that already exist and that
## elections.gd can already attribute -- so that no direct opinion term was needed and
## no thirteenth ISSUE_KEYS entry had to be argued. Table (d) measured the premise on an
## isolated path and it is false, at every candidate and for a STRUCTURAL reason rather
## than a tuning one:
##
##   at UNREST_IMPULSE_SCALE = 2.0, a country held at maximum grievance for fourteen
##   years ends 4.94 % POORER and its workers bloc approval row moves 0.42 POINTS.
##
## The whole opinion model is written in RATES and RATIOS. `growth` reads
## growth_annual_pct - trend and returns to zero once the shock is steady; unemployment
## mean-reverts to a structural level a strike never writes; and every fiscal figure is
## a share of GDP, so a GDP that is 5 % smaller changes almost none of them. A permanent
## LEVEL loss is invisible to a model that prices CHANGES -- which is opinion.gd's own
## deficit-not-debt argument read from the other side. No value of the output scale
## clears the floor, so tuning it upward would be tuning against an arithmetic
## impossibility, which is exactly what V1.5b refused to do for
## DEPENDENCY_ELASTICITY["health"].
##
## V1.5b's answer there was to DELETE the term. That answer is not available here: the
## impulse is this session's price, and a block whose rule is *ship a statistic and the
## price it charges* cannot ship a price nobody can feel. So the model takes the direct
## term it was designed without.
##
## READ OFF THE STOCK AND NOT OFF THE ACT, which is what makes it the statistic's price
## rather than the strike's. A country at grievance 44 has not struck and is still
## angry, and the row's own bullet is about organised opposition rather than about
## work stoppages.
##
## Applied at opinion.gd's `bloc_offset` site rather than inside an issue, and that is a
## deliberate refusal of the nameability V1.3d argued for. Subtracting it from `jobs` --
## deployment_opinion_load's shape, and the obvious move -- would put it inside
## issue_satisfaction(), which Unrest.hardship() reads, closing a same-quantity loop
## through the salience simplex that no clamp in this file bounds. The offset site is
## outside that read by construction. What names a strike to the player instead is the
## unrest readout on the economy panel and the card on the message stack, which is
## exactly the surface V1.5a's delivery lines use.
##
## UNIFORM ACROSS THE SIX BLOCS, and the absence of a split is recorded rather than
## hidden: a general strike inconveniences everybody, and an authored per-bloc row would
## be a table with no measurement behind it -- the clustered `coalition_position`
## failure. docs/tiers/v1.md section 7's campaign phase is where a split would belong.
##
## BAND: the workers bloc approval row past +-3.0 at a REACHABLE grievance, not at the
## clamp. TIEBREAKER, two-part, V1.5a's: legible AND the combined score at the reachable
## worst case leaves opinion.gd's own +-1.0 clamp slack, since a term that pins it is
## the clamp-sets-the-number failure a sixth time.
##
## Full table: docs/unrest-model.md (d2).
const UNREST_OPINION_SCALE := 0.15

## Clamp on the accumulated output impulse, points of annual growth.
##
## NOT A TUNED CONSTANT -- a guard rail, and docs/economy-model.md's per-quantity
## divergence rule is why a new addend in the growth sum owes one. Placed between
## companies_constants.FIRM_IMPULSE_MAX_PCT (2.00) and coercion_constants'
## COERCION_IMPULSE_MAX (6.00), and the argument is economy.gd's own distinction: a
## subsidy is a standing condition and a strike is a SHOCK, so this sits above the
## subsidy; but a general strike is not an embargo by your largest trading partner, so
## it sits below the measure.
##
## If this clamp BINDS in any reachable regime the loop gain is above 1 and the model is
## wrong rather than the number -- reported as a finding, not retuned. Measured slack:
## docs/unrest-model.md (f).
const UNREST_IMPULSE_MAX_PCT := 4.00

## How many acts GameState.unrest_acts keeps before dropping the oldest. Not tuned --
## foreign_policy_constants.AGENDA_ACTS_KEPT's shape and reason: a column of cards is a
## window on the recent past, not an archive, and an unbounded list on a fourteen-year
## run is a save that grows without limit.
##
## Held here rather than in src/core/game_state.gd because the dependency only runs one
## way: game_state.gd preloads the systems, not the other way round.
const ACTS_KEPT := 12
