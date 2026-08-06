extends RefCounted

## Every tunable the defence model has. The model and the argument for each
## number is docs/defence-model.md; src/sim/defence.gd is the rules.
##
## Every value below was set by tools/defence_probe.gd BEFORE a single verb was
## authored in data/diplomatic-actions/defence.json -- coercion_constants.gd's
## ordering, and what cut the authored `tariff_rate_pct` at V1.3c: a constant set
## before the measurement is a number the measurement is then read to justify.
## The tables are pasted into docs/defence-model.md §7.
##
## The probe corrected the model three times, which is seven sessions running:
## the nine never coerce each other so the obligation is unreachable without the
## COUNCIL (table d); the headline approval figure cannot move on a `defence` price
## at all, because five blocs of six weight that issue at zero (table e); and the
## first table measured only half the price, having set the opinion load and not
## the bill that widens the deficit every bloc does weight.
##
## The pact ACCEPTANCE tunables are deliberately not here -- they live in
## foreign_policy_constants.gd beside the other counterparty thresholds, because
## whether a partner signs is the interest model's question and not this file's.

# --- Capability ---------------------------------------------------------------

## Fraction of the gap between capability and the current defence spending line
## closed each month. Both bounds are failures rather than one: below, a stock
## that has not visibly moved inside a five-year term is a lever the player cannot
## pull; above, capability tracks spending closely enough to BE the spending line
## under a second name, and every reader could have read spending_pct_gdp instead.
## Swept over {0.005, 0.01, 0.02, 0.04, 0.08} on a France moved 2.0 -> 4.0 points
## of GDP, table (b). Half-lives 139, 69, 35, 17 and 9 months against a 60-month
## term: 0.005 and 0.01 are past a full term and so unpullable, 0.08 is 63 % of the
## way inside a single year and is the spending line renamed. 0.02 closes half the
## gap in 35 months and is a fifth of the way at twelve -- inside a term, and
## visibly a stock rather than the lever.
const CAPABILITY_CONVERGENCE := 0.02

## Bounds on the stock. The maximum is the defence lever's own ceiling, so a
## player who pins the slider converges on the top of this range rather than
## through it.
const CAPABILITY_MIN := 0.0
const CAPABILITY_MAX := 30.0

## What "an ordinary military" is, in points of GDP: the roster's mean authored
## defence spending, 16.6 over ten nations. A REFERENCE rather than an absolute
## threshold, for the reason every threshold in foreign_policy_constants.gd is
## expressed against EVEN_SHARE -- an absolutely-anchored capability term reads a
## small nation as weak by construction, which is V1.3e's GBR finding in a new
## place and has now fired five times.
const CAPABILITY_REFERENCE := 1.66

# --- Deployments --------------------------------------------------------------

## What one deployment costs a nation of exactly reference capability, in points
## of GDP per year. Set from table (c) against two anchors already in the tree: one
## point of VAT is 0.25 points of GDP (economy_constants.TAX_BASE_SHARE), and
## bloc_constants.CONTRIBUTION_BASE_PCT_GDP is 0.30, what an EU member already pays
## in. At 0.30 one deployment costs France 0.249 points of GDP -- almost exactly one
## VAT point, or EUR 7.2 bn -- and four cost EUR 29 bn. A commitment that costs
## about a tax point is one the player has to find the money for and can still
## afford; the same deployment costs Switzerland 0.45 points, because it has spent
## 1.1 %% of GDP on defence rather than 2.0 %%.
const DEPLOYMENT_COST_PCT_GDP := 0.30

## Clamps on the capability ratio the cost divides by. Without them a nation that
## has never funded a military pays an unbounded price for one commitment, and a
## nation at the lever's ceiling deploys for nothing.
const DEPLOYMENT_COST_MIN_RATIO := 0.50
const DEPLOYMENT_COST_MAX_RATIO := 2.00

## Ceiling on the whole deployment bill, points of GDP. A GUARD RAIL, and the
## session's first escalation trigger is that it stops being one: if the reachable
## obliged stack measured by table (d) sits ON this number, then the clamp and not
## the model is setting the bill -- economy_constants.IMPULSE_MAX's failure in its
## fifth place. The answer to that is not a larger clamp.
##
## MEASURED AND SLACK, so the trigger did not fire. The worst reachable stack over
## fourteen years with the agenda AND the council live is two obliged deployments
## and a bill of 0.586 points of GDP -- under a third of this. It is a guard rail
## doing a guard rail's job, which is the first time in this block a clamp has been
## measured and found slack rather than found binding.
const DEPLOYMENT_BILL_MAX_PCT_GDP := 2.00

## What one CHOSEN deployment takes off the `defence` issue's satisfaction, on the
## [-1, +1] scale opinion_constants.gd's terms use, against poll_noise.gd's
## NOISE_MAX_PCT of 3.0 points.
##
## Table (e) is where the probe's second correction landed and it moved what this
## number is measured AGAINST rather than what it is. `defence` is weighted 0.00 by
## five blocs of six and 0.12 by rural alone, so no value here can move the headline
## approval figure past the noise floor -- raising it until it did would be tuning
## against an arithmetic impossibility. Read on the rural row instead, at 0.15 the
## reachable stack of two costs 3.3 points chosen and 6.5 obliged. One deployment
## costs 1.3 and does not clear; see DEPLOYMENT_OBLIGED_MULT for why that is a
## structural bound rather than a number left untuned.
const DEPLOYMENT_OPINION_CHOSEN := 0.15

## How much worse an OBLIGED deployment reads than a chosen one. Above 1.0: a
## commitment the player did not choose is the one they cannot defend at home,
## because there is no case to be made for it beyond the treaty.
##
## SET BY THE MEASUREMENT, and the first version was decorative. At 1.50 the
## chosen-obliged gap at the stack table (d) actually reaches -- one or two
## deployments -- was 0.72 and 2.05 points on the only bloc that weights defence,
## against a 3.0 noise floor: a distinction that existed in the register and
## nowhere a player could read it, which is diplomacy-model.md's own finding about
## a split price. Solved off the measured slope of 13.7 rural points per unit of
## load rather than guessed at: 1.73 puts the two-deployment gap exactly on the
## floor, and 1.75 is the round number above it.
##
## A SINGLE deployment stays below the floor either way -- 1.32 points chosen and
## 2.46 obliged -- and that is not tuned away, because it CANNOT be. Raising
## DEPLOYMENT_OPINION_CHOSEN until one chosen deployment reads needs 0.316, and at
## 0.316 two obliged ones carry a load of 1.11 against a satisfaction term that
## clamps at 1.00: the third deployment would be free. There is no value of the
## pair that makes one deployment legible without saturating two, and two is the
## top of the reachable stack. The bound is structural and is recorded rather than
## traded against.
const DEPLOYMENT_OBLIGED_MULT := 1.75

## The severity a measure against an ally must reach before it obliges anybody.
## The same job coercion_constants.RETALIATION_MIN_SEVERITY does for an answer: it
## is what lets the model say NO rather than only HOW MUCH, so a token tariff on a
## pact partner is a diplomatic incident rather than a standing charge on the
## player's budget.
##
## Measured against the only thing in the project that actually imposes on an ally
## unprompted: the council's `common_external_tariff` at severity 0.35, comfortably
## over this floor. A player-imposed measure spans the whole range, so the floor is
## what keeps a 0.1 gesture off somebody else's budget.
const OBLIGATION_MIN_SEVERITY := 0.20

# --- The register's vocabulary ------------------------------------------------

## The two kinds of deployment. A flat list rather than a bool because the
## precondition fields read it by name and the panel labels it, and both would
## otherwise carry their own spelling of "obliged".
const DEPLOYMENT_CHOSEN := "chosen"
const DEPLOYMENT_OBLIGED := "obliged"
const DEPLOYMENT_KINDS := [DEPLOYMENT_CHOSEN, DEPLOYMENT_OBLIGED]

## The four ops effects.pact may carry, validated at load by
## src/core/diplomatic_action.gd. Four ops on one channel rather than a sixth
## channel for the deployment verbs: a chosen deployment needs a verb, and giving
## it a channel of its own would be a parallel vocabulary for a mechanism that
## already exists.
const PACT_OPS := ["sign", "abandon", "deploy", "withdraw"]
