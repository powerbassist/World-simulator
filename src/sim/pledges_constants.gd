extends RefCounted

## Every bound in the pledge model, in one file. Same shape as
## campaign_constants.gd, projects_constants.gd and the rest -- model parameters,
## not content, so not in data/. Rationale for every number is
## docs/pledge-model.md; this file is the values, that file is the argument.
##
## *** IT SHIPS NO TUNED CONSTANT AT ALL, which is projects_constants.gd's position
## inherited whole and the second time this project has reached it. *** What a pledge
## pays for being made and what it charges for being broken are two independent
## authored facts about a named promise, so data/pledges/ is the ladder and
## tools/pledge_probe.gd bands the ladder rather than a coefficient. Everything below
## is either a whitelist that fails a bad file at load or a ceiling that catches a
## mistyped digit, and each says which it is.
##
## *** AND THERE IS NO CONCURRENCY CEILING. *** How many promises may be live at once
## is the `pledge_count` precondition every authored pledge carries, which makes it
## CONTENT -- data/campaign-actions/'s call one session on, and a model constant
## duplicating a content gate is the clamp-guarding-arithmetic failure V1.6e deleted
## INVESTMENT_BILL_MAX_PCT_GDP for.

# --- What may be promised ---------------------------------------------------------

## *** THIS IS NOT legislature_constants.PRECONDITION_FIELDS, AND THE ROW SAID IT
## WOULD BE. *** ROADMAP.md's V1.7 decomposition calls a pledge "a {field, op, value}
## triple -- PRECONDITION_FIELDS' own shape", which is right about the SHAPE and wrong
## as a list. Three of that list's seven entries cannot be promised:
##
##   overall_approval_pct  circular. A promise to be popular, priced in popularity.
##   terms_served          not a state of the country, and the player cannot fail it.
##   growth_annual_pct     is here, but see below -- it is the ladder's gamble end.
##
## and the interesting half is what this list has that that one does not: the rates
## and the spending lines the PLAYER SETS. That is the session's own division:
##
##   AN OUTCOME PLEDGE IS A BET ON THE WORLD. tools/pledge_probe.gd table (c0)
##     measures each field's LUCK (the widest span within one budget) against its
##     CHOICE (the span across three budgets at the end of a term).
##     growth_annual_pct is 8.215 against 0.641 -- twelve to one, almost pure luck,
##     and V1.6a's cycle is what puts it there. unemployment_pct is 1.182 against
##     0.656; you cannot govern your way out of an unemployment promise, you can only
##     be lucky.
##   A RATE PLEDGE IS A SELF-IMPOSED CONSTRAINT. Every tax and spending row measures
##     luck EXACTLY 0.000 and choice 2.5 to 6.0, because nothing but the player moves
##     them. Breaking one of these is never bad luck; it is a decision.
##
## *** inflation_pct WAS ON THIS LIST AND WAS DELETED BY THE PROBE. *** Table (c0)
## measures its luck at 0.114 and its choice at 0.045 over a full term -- both below
## the resolution of the model that produces it, which is docs/inflation-model.md's
## own finding (a reachable deviation of 0.145 points) arriving from the other side.
## An authored threshold either side of that is a CONSTANT VERDICT: the promise is
## kept in all sixty months or broken in all sixty, and nothing the player does moves
## it. Deleted rather than left in and authored around -- V1.5b's treatment of
## DEPENDENCY_ELASTICITY["health"], and V1.5a's rule that a tuned thing nothing can
## reach is a number a later session finds and reasons from.
const PLEDGE_OUTCOME_FIELDS := [
	"unemployment_pct",
	"deficit_pct_gdp",
	"debt_to_gdp_pct",
	"growth_annual_pct",
	"unrest_pct",
]

## The player-set half. One entry per economy_constants.TAX_KEYS entry and one per
## SPENDING_KEYS entry, written out rather than derived because a `const` cannot loop
## -- and tests/test_pledges.gd asserts the correspondence BOTH WAYS, so a sixth tax
## added at some later session turns a test red rather than silently becoming
## unpromisable. That is docs/people-model.md's read-the-source idiom pointed at two
## lists instead of at one file.
const PLEDGE_RATE_FIELDS := [
	"tax_income_pct", "tax_corporate_pct", "tax_vat_pct",
	"tax_capital_gains_pct", "tax_wealth_pct",
	"spending_health_pct_gdp", "spending_education_pct_gdp",
	"spending_defence_pct_gdp", "spending_pensions_pct_gdp",
	"spending_infrastructure_pct_gdp",
]

const PLEDGE_FIELDS := PLEDGE_OUTCOME_FIELDS + PLEDGE_RATE_FIELDS

## *** TWO OPS OF FIVE, AND THE THREE REFUSALS ARE THE DESIGN. *** A promise is a
## BOUND: "unemployment below seven" or "health spending no lower than eleven".
##
##   `==`  on a float is a promise nobody could keep and no player could read.
##   `<` and `>` are `<=` and `>=` a hair apart, so shipping both would be one
##        promise expressible two ways, and a content author choosing between them
##        would be choosing nothing.
##
## Refused at LOAD, which is src/core/company_action.gd's refusal of a firm id in a
## new place: the distinction lives in the schema and not only in the docs.
const PLEDGE_OPS := ["<=", ">="]

## What an authored PRECONDITION may ask about: everything that may be promised, plus
## two gates that may not be. `pledge_count` is the concurrency ceiling and
## `months_to_election` is "only in the last two months of the run-up" -- both are
## real authorial choices about when a promise may be MADE, and neither is a state of
## the country anyone could promise.
##
## There is no `campaign_open` field, for campaign_constants.gd's reason exactly:
## whether the run-up has begun is a property of the clock and not an authorial
## choice, so Pledges.available() refuses everything outside it structurally. A
## content file that had to remember the window would be a file that could forget it.
const PRECONDITION_FIELDS := PLEDGE_FIELDS + ["pledge_count", "months_to_election"]

const PRECONDITION_OPS := ["<", "<=", ">", ">=", "=="]

# --- Content ceilings --------------------------------------------------------------

## What one authored promise may take off one bloc's approval target for each month it
## stands broken, on the same [-1, +1] scale opinion_constants.gd's satisfaction terms
## use. A content ceiling set to catch a mistyped digit rather than to shape the
## ladder: the largest authored rate is 0.0050.
##
## *** IT IS AUTHORED AS A MAGNITUDE AND APPLIED AS A CHARGE. *** The sign is not the
## author's to choose. A promise broken can only cost, so src/sim/pledges.gd
## SUBTRACTS, and an authored negative would be a promise that pays you for breaking
## it -- which is the one thing a signed term could express here and the one thing it
## must not. That is the opposite call from campaign_constants.MAX_MOBILISATION_PER_MONTH,
## which is signed precisely because a broadcast that fires up your base and disgusts
## everybody else is one act with two signs; a broken promise has one.
##
## Measured against the accumulator it charges. tools/pledge_probe.gd table (b0):
## sixty months at 0.0100 on one bloc reaches 0.6000 against a BLOC_OFFSET_MIN of
## -1.00, which is 60 % of the clamp -- so a ladder at the ceiling with the
## concurrency gate open leaves the guard rail slack, and the CONTENT is the lever.
const MAX_BREACH_OFFSET_PER_MONTH := 0.010

## The terms `effects.pledge` reads. A table rather than branches in
## src/core/pledge_action.gd, for CAMPAIGN_OP_TERMS' and PROJECT_OP_TERMS' reason: a
## term added without a row here fails to load rather than being silently ignored.
##
## *** THERE IS NO `op` FIELD ON THIS CHANNEL AND EVERY PREVIOUS ONE HAS HAD ONE. ***
## Five directories ship a start and a stop, because an obligation only the clock can
## close is a permanent monotone charge -- docs/defence-model.md's rule, which is why
## campaign_constants.CAMPAIGN_OPS carries `stop`. It does not transfer, and the
## reason is the model: a pledge charges only while it stands BROKEN, so it stops the
## month the player comes back into compliance. The off switch already exists and it
## is called governing. A `renounce` op priced below the accrual would be strictly
## better than complying and priced above it would never be used -- the
## strictly-dominated shape, refused a ninth time rather than shipped as a third op.
const PLEDGE_TERMS := ["pledge_id", "pledge_name", "field", "op", "value", "breach_offset"]
