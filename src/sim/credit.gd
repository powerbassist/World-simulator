extends RefCounted

## The bond market -- V1.6c, the third session of the V1.6 block. The rate a nation
## borrows at, as a spread over economy_constants.DEBT_REAL_RATE_PCT, plus the credit
## rating that reads it. The model and every constant's rationale is
## docs/credit-model.md; src/sim/credit_constants.gd is the values.
##
## STATELESS. No tick_month(), no accumulator, nothing on NationState that this file
## writes. src/sim/cycle.gd's shape, and for a sharper reason than cycle.gd's: both inputs
## -- the debt ratio and the grievance -- are already stocks somebody else owns and ticks.
## A stock here would be a third writer of a number two modules already agree on.
## tests/test_credit.gd reads this file and fails if a tick_month() appears.
##
## NO PLAYER VERB, and that is the decomposition's call rather than an omission.
## docs/brainstorm/mechanics-economy.md tiers the central bank, interest rates and
## quantitative easing Someday, and docs/tiers/out-of-scope-mvp.md records that France
## does not set its own rate. docs/tiers/v1.md section 6 runs (a), (b) and (c) under
## V1.5's inverted rule, *ship a statistic and the price it charges*, and this is (c).
##
## *** DEBT_REAL_RATE_PCT STAYS THE ANCHOR AND THE SPREAD IS EXACTLY 0.0 AT NEW GAME. ***
## That is the whole of what keeps this session's re-baseline bounded. Every balance
## number this project has ever measured is quoted against a flat 2.0, and every input
## below is a deviation against the nation's OWN START, so a game that has just begun
## borrows at exactly the rate it always did. trade_baseline_by_partner's,
## firm_impulse_pct's and inflation's idiom -- a register that goes live moving nothing.
## tests/test_credit.gd asserts it with exact equality rather than is_zero_approx().
##
## THE PRICE IS AN EXISTING LINE. The yield reaches the player through
## ns.debt_service_pct_gdp, which Budget.recompute() has computed since the MVP -- no new
## budget line, no new effect channel, no new ISSUE_KEYS entry, no PRECONDITION_FIELDS
## entry. It reaches the electorate only through deficit_pct_gdp and the `public_finances`
## issue that already prices it.
##
## AND IT REACHES THE BUDGET AND NEVER THE ECONOMY, which is worth stating because a
## reader will look for a growth addend and not find one. debt_service_pct_gdp is not a
## player-set spending line, so Budget.commit() never writes it into demand_impulse_pct;
## there is no ninth addend in economy.gd's growth sum. What it does reach is
## docs/bloc-model.md's `deficit_pct_gdp <= 3.0` rule, so a downgrade can put the player
## in breach of something Brussels passed -- V1.4c's nationalisation doing the same, in a
## new place.
##
## Preloads its own constants AND economy_constants for the anchor, and nothing else -- a
## leaf. It does not preload budget.gd, unrest.gd or inflation.gd: all three reach THIS
## file's output through Budget.recompute() or read nothing from it at all, and a reverse
## edge would make that one-way relationship a convention rather than a fact.
## tests/test_credit.gd reads the file and asserts the preload list is exactly these two.
##
## TAKES ns AND NEVER state, which is a constraint rather than a tidiness: src/core/
## game_state.gd calls Budget.recompute(null, ns) once per nation at new game, on purpose
## and with a comment saying why, and that call is what makes the starting deficit real
## before Opinion measures against it. A yield that needed the roster would break it.

const K = preload("res://src/sim/credit_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")


## Points of debt-to-GDP above where this nation started. Positive is worse.
##
## Read through here rather than inline so the measured-against-its-own-start anchoring
## is not something a caller can bypass -- Inflation.inflation_deviation()'s and
## Society.quality_deviation()'s discipline.
static func debt_gap_pct(ns) -> float:
	return ns.debt_to_gdp_pct() - float(ns.start_debt_to_gdp_pct)


## *** THERE IS NO DEFICIT TERM, AND THE ROW ASKED FOR ONE. ***
##
## docs/tiers/v1.md section 6 names debt AND deficit, and the deficit is the DERIVATIVE
## of the debt: src/sim/budget.gd integrates it monthly with no other source, so on its
## face this is docs/inflation-model.md's *one quantity written three times* a session
## later. That was a counting challenge and not yet a result -- a level and a trajectory
## genuinely are different information, because a stock takes decades to unwind and a
## yield on the level alone is blind to a player who fixed the budget this year.
##
## tools/credit_probe.gd table (d) SWEPT IT AND NO CANDIDATE PASSED, which is what turned
## the challenge into a finding. The three clauses are mutually inconsistent: isolated
## against a control, the deficit term moves debt service by 0.30 points of GDP over a
## term only at a slope above 0.20, and at 0.145 it already outweighs twelve months of
## the debt term it is supposed to lead. Below the readable floor everywhere it is not
## dominant. It is not structural either -- deleting it breaks no loop and changes no
## sign, so V1.6b's exception for INFLATION_OUTPUT_BETA does not reach it, and V1.3e's
## rule applies instead: a tuned constant nothing reads is a number a later session finds
## and reasons from, so it is DELETED rather than left at zero.
##
## What the model keeps instead costs nothing: fixing the budget slows the debt stock,
## which slows the spread, so the trajectory does reach the yield -- through the level,
## with a lag, and at a size the service line can express.
##
## Deleting it also removes the only positive feedback this session could have created.
## debt_service_pct_gdp is INSIDE deficit_pct_gdp, so a yield reading the deficit would
## have fed the line it sets; the surviving terms read the debt STOCK, which
## Budget.tick_month() advances after Budget.recompute() has run, so the figure the
## spread sees is always last month's. The lag that would have been an argument is now
## a fact about the call order.


## The premium a nation pays over the anchor, in points of annual yield.
##
## TWO terms and NO WEIGHTS BETWEEN THEM beyond the two betas, which is the shape
## Unrest.unrest_target() holds to: each term is already in points of its own quantity, so
## each beta is a unit conversion with a swept band rather than one of three numbers
## nobody can sweep independently. A third, on the deficit, is what the row asked for and
## what the sweep deleted -- see above.
##
## SIGNED. A player who runs surpluses walks the debt ratio down, the gap goes negative
## and the spread with it, so governing well is REWARDED with a cheaper stock of debt
## rather than merely not punished. That is what makes this the first channel in the V1.6
## block whose austerity regimes move in the virtuous direction, and it is why YIELD_MIN
## is below zero.
static func spread_pct(ns) -> float:
	return (
		K.YIELD_DEBT_BETA * debt_gap_pct(ns)
		+ K.YIELD_UNREST_BETA * float(ns.unrest_pct)
	)


## The real rate this nation borrows at, %/yr. Read by Budget.recompute() where
## economy_constants.DEBT_REAL_RATE_PCT was read directly from the MVP until now.
##
## The clamp is a guard rail and not the model -- see YIELD_MIN/YIELD_MAX. The probe
## measures its slack rather than trusting it.
static func yield_pct(ns) -> float:
	return clampf(C.DEBT_REAL_RATE_PCT + spread_pct(ns), K.YIELD_MIN, K.YIELD_MAX)


## The credit rating, as a letter.
##
## ONE EXTRA READ OF THE YIELD AND NOT A SECOND MACHINE -- Defence.allies()'s shape, and
## the thing the V1.6 decomposition names by name as the difference between (c) shipping
## and (c) splitting. No stored rating, no previous-rating field, no downgrade card: an
## edge trigger needs memory and memory here would be a stateful module.
static func rating(ns) -> String:
	return rating_for(yield_pct(ns))


## The band a bare yield falls in. Split out because the economy panel needs the letter
## the ANCHOR sits in to know whether the player has been downgraded, and a panel
## recomputing the band table itself is the second reader of a content list that this
## project keeps to one.
static func rating_for(y: float) -> String:
	for band in K.RATING_BANDS:
		if y <= float(band[0]):
			return String(band[1])
	return String(K.RATING_BANDS[K.RATING_BANDS.size() - 1][1])
