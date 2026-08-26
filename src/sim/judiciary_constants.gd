extends RefCounted

## Judiciary constants, V1.1e. Next to the other *_constants.gd files and not in data/,
## per docs/engine-decision.md Rule 1. The model and the rationale for every number is
## docs/judiciary-model.md; this file is the values.
##
## ============================================================================
## THE VERDICT IS DERIVED FROM CLAMPS THAT ALREADY EXISTED
## ============================================================================
## A law's REACH is the largest fraction of any effect clamp it uses -- one number, read
## off legislature_constants, companies_constants and the four SOCIETY_TERMS maxima,
## every one of which was set by an earlier session for its own reasons. An authored
## `unconstitutionality` score would be one strength written twice, which
## src/core/investment_action.gd already refuses by name.
##
## ============================================================================
## THE COURT IS TRANSPARENT, AND THAT IS A DECISION RATHER THAN A CONCESSION
## ============================================================================
## docs/legislature-model.md blurs the VOTE forecast, because a division is meant to
## feel like an obstacle and the model is deterministic. This gate is not blurred, and
## the difference is what each one is for. A vote is a body of people whose minds the
## player is trying to read; a court is a RULE, and a rule the player cannot read is not
## a check on their power, it is a trap. So src/ui/law_panel.gd prints the verdict, the
## reach and the tolerance, and the doomed bill stays on the list rather than being
## filtered out of it -- because a lock removed from view teaches nobody that there is a
## key. That is docs/referendum-model.md's V1.7c readout finding: a lever whose only
## feedback is a wait has no readout at all.
##
## What makes it a decision rather than a filter is that the gate MOVES. `rule of law`
## is docs/tiers/v1.md section 5's own statistic, handed to section 1's judiciary bullet
## at V1.5's decomposition, and it is the fifth effects.society term -- so the set of
## laws a president can pass is a function of a stock they can change, at a price. A
## lock with a key you can buy.

## Whether a nation's courts may strike down primary legislation.
##
## TWO VALUES AND NOT FOUR, and the collapse is recorded rather than authored away.
## Abstract review before promulgation (France, Art. 61) and concrete review after it
## (Germany, Italy, Spain, Austria, Belgium, Luxembourg) differ only in TIMING, and this
## model applies a law's effects at passage -- so there is one behaviour, and authoring a
## distinction nothing reads is what docs/political-systems.md refuses when it declines
## to author absolute monarchy for a roster with none. The same shape
## docs/electoral-systems.md uses when it records a per-method reduction.
##
##   none            no review of primary legislation. GBR, NLD and CHE.
##   constitutional  a court may strike a bill down before it takes effect.
##
## THREE NATIONS SAY `none` FOR THREE DIFFERENT REASONS, and nothing authored that --
## it fell out of reading each constitution for its own sake. Britain: parliamentary
## sovereignty, the same doctrine that puts its amendment_rule at `ordinary_law`, with
## the Human Rights Act 1998 s.4(6) saying in terms that a declaration of
## incompatibility does not affect an Act's validity. The Netherlands: Art. 120 of the
## Grondwet EXPRESSLY forbids the courts to review an Act's constitutionality.
## Switzerland: Art. 190 Cst. binds every authority to APPLY federal statutes, which is
## a binding-force clause rather than a withheld grant -- cantonal law is reviewable and
## federal law is not.
const REVIEW_NONE := "none"
const REVIEW_CONSTITUTIONAL := "constitutional"
const KNOWN_REVIEWS: Array[String] = [REVIEW_NONE, REVIEW_CONSTITUTIONAL]

## Rule of law, on the 0-100 scale the World Bank's own governance SCORE uses and that
## every other stock this project keeps on a nation already uses -- approval,
## service_quality, unrest_pct, gini_index. Definitional bounds rather than guard rails:
## a score outside them is not a number this model can read.
const INDEPENDENCE_MIN := 0.0
const INDEPENDENCE_MAX := 100.0

## The most one law may move it, in points of score.
##
## SEPARATE FROM THE CLAMP ABOVE, unlike the four effects.society terms this joins.
## `corruption`, `migration`, `settlement` and `press_freedom` are signed STANCES that
## start at 0.0 for everybody, so their per-law bound and their stock clamp are honestly
## the same number. This one is a LEVEL, imported per nation from a measured series, so
## passing the stock clamp as the per-law bound would let a single Act abolish the
## courts outright. Nine points is a little under half the roster's whole measured span
## (Italy 67.6 to Switzerland 87.3), so two Acts in one direction move a nation further
## than any two nations on the roster are apart -- which is as far as one term of one
## president should be able to reach.
const INDEPENDENCE_LAW_MAX := 9.0

## The roster's own mean rule of law, and it is MEASURED rather than chosen: the
## unweighted mean of the ten imported.institutions.rule_of_law_score figures.
##
##   ITA 67.6  ESP 73.0  FRA 73.8  GBR 78.8  BEL 79.0
##   AUT 85.8  DEU 84.9  NLD 86.3  CHE 87.3  LUX 87.3     mean 80.38
##
## docs/cycle-model.md's V1.6a shape exactly, where `cycle_amplitude_rel` is a ratio
## against a roster mean computed once for all ten -- and docs/media-model.md's V1.5d
## mean anchor and docs/referendum-model.md's status_quo_position() one block on. It is
## a constant here rather than a runtime read because src/sim/judiciary.gd is a leaf
## and has no loader; tools/import_data.py prints the mean on every run, so a re-import
## that moves it says so.
const ROSTER_MEAN_RULE_OF_LAW := 80.38

## How much of a law's reach a court of AVERAGE European strength will tolerate.
##
##   tolerance(ns) = JUDICIAL_TOLERANCE * ROSTER_MEAN_RULE_OF_LAW / judicial_independence
##   struck        = reach(law) > tolerance(ns)
##
## INVERSELY PROPORTIONAL, AND THE FIRST FORM WAS LINEAR. `1 - independence/100 * S`
## was written first and the sweep killed it: its zero point is arbitrary (a court at
## 100 tolerates exactly nothing, for no reason the model can state) and it AMPLIFIES
## the roster's spread -- a 15 % gap in independence between France and Germany came
## out as a 29 % gap in tolerance at the middle of the range and worse at the top, so
## the passing interval collapsed to two grid points and Germany could not legislate.
## The inverse form says something a model can defend instead -- a court twice as
## independent tolerates half as much -- and it holds the ratio at exactly the ratio of
## the scores.
##
## THE BAND IS WRITTEN ON THE CONTENT RATHER THAN ON A COUNT, which is
## docs/campaign-model.md's V1.7a correction taken seriously: that session's first
## clause was INVENTED (*at least 0.50 points of vote share*, a number that sounded
## like a margin) and every candidate failed it. So:
##
##   (i)   France's court must block BOTH `emergency_*` laws at new game. A
##         constitutional court that does not stop emergency powers is not one, and
##         "Emergency powers" is tiered Someday in mechanics-governance.md -- so the
##         two authored approximations of it are exactly what this gate is for.
##   (ii)  Germany, the second playable nation with a court, must still pass a
##         MAJORITY of ordinary laws. V1.2a chose Germany for institutional contrast,
##         not for paralysis.
##   (iii) A full capture must unlock both emergency laws, or the key does not work.
##   (iv)  A full capture must leave something still blocked, or it is a master key
##         and there is no reason ever not to turn it.
##   (v)   Every rung of the authored ladder must itself be passable at the
##         independence it is reached at, or the ladder has no first step.
##
## MEASURED. Passing [0.323, 0.367] on a 0.001 grid swept over [0.200, 0.599], so both
## edges are the MODEL'S and not the grid's; 45 points wide. Midpoint 0.345, interior
## to the passing set and to the swept range -- V1.5b's diagnostic that a value at an
## endpoint is a suspect rather than a result.
##
## WHAT IT BUYS, and the third line is the one nobody authored. France blocks 9 of 25
## reviewable laws; a full capture unlocks 6 and leaves 3 -- `anti_corruption_agency`,
## `farm_standards_act` and `public_sector_pay_settlement`, the three furthest-reaching
## laws in the game -- so a captured court is still a court. Germany blocks 17 and
## still passes 18 of 35 ordinary laws. And the ten split into THREE TIERS out of a
## World Bank series and one dial: Italy blocks 3, the middle four (Belgium, Britain,
## France, Spain) block 9, and the strong five (Germany, Austria, the Netherlands,
## Switzerland, Luxembourg) block 17. Britain's 78.8 is computed and never read,
## because its review rule is `none` -- which IS parliamentary sovereignty.
const JUDICIAL_TOLERANCE := 0.345

## What a point of lost rule of law does to the grievance stock, per month.
##
## LEGITIMACY IS THE GRIEVANCE, AND V1.5d IS WHY. docs/media-model.md sent press
## freedom's legitimacy cost to docs/unrest-model.md's grievance rather than inventing a
## quantity, on the argument that legitimacy is willingness to accept your rule OUTSIDE
## the ballot box -- and unrest_constants.UNREST_BLOCS is ["workers", "students"], who
## are exactly who marches when a government captures its own courts.
##
## NOT A SECOND PRESS FREEDOM WITH A DIFFERENT LABEL, and the check is written down
## rather than assumed: press freedom moves `framing_gain`, how loudly bad news travels;
## this moves whether a passed law survives. Different landing site, different units, so
## docs/legislature-model.md's `same act, same landing site, same units` criterion is not
## met and the two are two mechanisms.
##
## READ ON THE DEVIATION FROM THE NATION'S OWN START, not on the level, for
## start_service_quality's reason: a country whose courts have always been weak is not
## permanently rioting about it. Italy is not angrier than Switzerland at new game, and
## `tests/test_judiciary.gd` asserts the term is exactly 0.0 for all ten on frame one.
##
## SET BY ARGUMENT AS A RATIO, BECAUSE THE BAND COULD NOT SELECT -- the one-sided
## failure docs/society-model.md, docs/demography-model.md, docs/unrest-model.md and
## docs/media-model.md each recorded, here for a fifth time. Table J2's band (i) --
## the whole ladder must move the grievance at least as much as one point of press
## freedom does -- passes at 0.15 and at every candidate above it, and band (ii), that
## a capture must not on its own carry a calm country over UNREST_THRESHOLD_PCT, never
## binds inside the sweep at all (peak unrest 15.95 at a beta of 1.00 against a
## threshold of 45.0). A bound is not a selector, and a passing set running to the top
## of the grid is the grid choosing.
##
## So the ratio chooses, against the sibling this term was modelled on:
##
##   JUDICIAL_UNREST_BETA = PRESS_UNREST_BETA / INDEPENDENCE_LAW_MAX = 8.0 / 9.0
##
## which says that capturing the courts as far as one Act may reach costs what
## censoring the press as far as one law may reach costs. The two are the same kind of
## act on the same two blocs through the same register, so equal is the claim that needs
## no evidence and any other number is one that would. docs/media-model.md set
## PRESS_UNREST_BETA itself the same way, as a ratio against SETTLEMENT_BETA, when its
## own band failed in the same manner.
##
## MEASURED CONSEQUENCE: the full three-Act ladder adds 8.00 points of grievance and
## takes a quiet France's peak unrest from 7.40 to about 15.4 -- readable, and nowhere
## near the strike threshold, which is the right shape. Capturing the courts is a
## legitimacy cost, not a general strike; docs/unrest-model.md already owns that machine.
const JUDICIAL_UNREST_BETA := 0.889
