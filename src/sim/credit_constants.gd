extends RefCounted

## Tunables for src/sim/credit.gd -- V1.6c, the third session of the V1.6 block. The
## model and the evidence for every value here is docs/credit-model.md;
## tools/credit_probe.gd is where every one of them was measured.
##
## *** NONE OF THESE IS MEASURED OFF A DATASET, AND THAT IS A CHECKED RESULT RATHER THAN
## A REACH FOR A BAND. *** V1.6a fitted its amplitude and V1.6b measured three of five
## constants off the World Bank, so the first thing this session did was look for a
## sovereign-rate series on the same licence-clean loop. There is not one that covers the
## roster. Both candidates were fetched over 1990-2024 for all ten:
##
##     FR.INR.RINR       real interest rate      4 of 10 nations
##                       CHE 2008-24, GBR 1990-2014, ITA 1990-2024, NLD 1999-2013
##                       FRA, DEU, ESP, BEL, LUX, AUT: ZERO rows
##     GC.DOD.TOTL.GD.ZS central government debt  7 of 10, but DEU 1 year, ITA 2,
##                       LUX 4, NLD 5
##
## The windows are disjoint, so no cross-section exists at any date, and FRANCE -- the
## nation the game is about -- has nothing at all. OECD IRLTLT01 carries the series, and
## docs/data-sources.md already rejected the IMF World Economic Outlook on redistribution
## terms; the CC BY loop is the standard this project holds to. So the slopes below are
## SWEPT, and the empirical range for the debt slope is recorded as a sanity cross-check
## and explicitly NOT as a selector. No new download and no new docs/data-sources.md line.


## V1.6c. Points of annual yield per point of debt-to-GDP above the nation's OWN START.
##
## A DEVIATION AND NOT A LEVEL, which is the session's first call and the one that decides
## how much it re-baselines. economy_constants.DEBT_REAL_RATE_PCT stays the ANCHOR: the
## yield is that constant plus a spread whose every input is measured against the nation's
## own start, so the spread reads EXACTLY 0.0 at new game and every balance figure this
## project has ever quoted keeps its meaning. That is trade_baseline_by_partner's,
## firm_impulse_pct's, the cycle's and inflation's shape -- the register goes live moving
## nothing -- and it is docs/media-model.md's six framing gains averaging back to the one
## SALIENCE_GAIN. The alternative, a yield on the absolute debt LEVEL, gives the ten
## different starting ratings and changes France's debt service on frame 1, which reprices
## every measured constant in the project against a fiscal pressure that no longer exists.
## It would also be mostly decorative: only the player has a budget, so the other nine
## would carry nine frozen letters.
##
## SWEPT, AND THE BANDS THAT CHOSE IT ARE THE SECOND SET. The first asked a
## debt-widening regime to move the yield 0.25 points over fourteen years; table (a) ran
## first, as tools/credit_probe.gd requires, and showed every candidate down to 0.005
## passing -- because a spendthrift budget does not widen the debt, it SPIRALS to the
## clamp and a ratio past 1400 % of GDP. A band measured on a saturated run measures the
## clamp. The reachable path is `hands_off`, a president who does nothing, and it widens
## the debt on its own.
##
##   (i)   under `hands_off` the debt term moves debt service by >= 0.30 points of GDP
##         over a five-year term -- a twentieth of opinion_constants.DEFICIT_SCALE_PP's
##         six-point span, so the `public_finances` issue can express it;
##   (ii)  it moves it by <= 3.00 over fourteen years, HALF of DEFICIT_SCALE_PP, so the
##         bond market cannot on its own saturate the one issue that prices it. THE
##         CLOSER: (i) alone is a one-sided minimum, which is V1.5b's failure;
##   (iii) under `managed` the yield stays within 0.50 of the anchor over fourteen years;
##   (iv)  the peak yield under `managed_then_spendthrift` stays inside YIELD_MAX over
##         84 months -- the switch plus one full term, after which the electorate has
##         removed that government whatever the bond market does.
##
## AND EVERY FIGURE IS AGAINST A CONTROL WITH THIS TERM ZEROED, which was the third
## correction the row needed: a debt ratio walking 110 -> 200 moves the service line by
## 1.8 points at the ANCHOR rate with no channel at all, so the second band set passed at
## a beta of 0.0005. A band on a raw move measures the model that was already there --
## the control tests/test_trade.gd needed at V1.6a, one session later.
##
## Passing interval [0.0110, 0.0190], interior to a grid running 0.0005 to 0.1200 and
## stable under refinement at 0.0005. Tiebreaker: the response is smooth in the beta, so
## the model edge is a crossing rather than a plateau and NEITHER EDGE SELECTS --
## docs/media-model.md's extension of V1.5c rule (e). The interior governs, and the
## midpoint is 0.0150. It is a FIXED POINT rather than one reading: the interval is
## measured on a path this constant is on, so it was iterated until the shipped value
## equalled the midpoint measured at it.
##
## THE CROSS-CHECK NEARLY AGREES, WHICH IS MORE THAN THIS SESSION EXPECTED. The empirical
## literature puts a sovereign spread at 2-5 basis points per point of debt-to-GDP, i.e.
## 0.02-0.05 here, and the swept answer is 0.0150 -- a factor of 1.3 below the low end
## rather than the order of magnitude a model-driven band usually lands from the world.
## What excludes an empirically honest 0.02 is clause (ii), and that is worth naming: the
## limit is the OPINION MODEL'S RESOLUTION and not the bond market. At 0.02 a do-nothing
## president's debt service moves 3.04 points of GDP over fourteen years, so a single
## channel would use half of DEFICIT_SCALE_PP's whole span on its own. Recorded as a
## CROSS-CHECK and never as the selector, because a number this project cannot fetch and
## re-derive is not a measurement -- docs/cycle-model.md's distinction between a fit and
## an assertion.
const YIELD_DEBT_BETA := 0.0150

## *** YIELD_DEFICIT_BETA WAS SWEPT AND DELETED, AND THE DELETION IS THE ROW'S ANSWER. ***
##
## docs/tiers/v1.md section 6 asks the yield to read debt AND deficit. The deficit is the
## DERIVATIVE of the debt -- src/sim/budget.gd integrates it monthly with no other source
## -- so the row names one quantity twice, which is docs/inflation-model.md's finding a
## session later. That was a suspicion, not a result: a level and a trajectory really are
## different information.
##
## tools/credit_probe.gd table (d) is what made it a result. Three clauses, mutually
## inconsistent: isolated against a control, the deficit term moves debt service 0.30
## points of GDP over a term only above a slope of 0.20, and by 0.145 it already outweighs
## twelve months of the debt term it exists to lead. Everywhere it is legible it dominates
## the level; everywhere it does not dominate it is below the floor. NO CANDIDATE PASSED.
##
## Deleted rather than left at zero -- V1.3e's treatment of AGREEMENT_ACCEPT_MIN -- and
## NOT eligible for V1.6b's structural exception, because cutting it breaks no loop. It
## takes the session's only positive feedback with it: debt_service_pct_gdp is inside
## deficit_pct_gdp, so a yield on the deficit fed the line it set, where the surviving
## terms read a stock Budget.tick_month() advances only after Budget.recompute() has run.
## See src/sim/credit.gd.

## V1.6c. Points of annual yield per point of ns.unrest_pct.
##
## NEEDS NO BASELINE, unlike the two above, and that is a property of V1.5c's register
## rather than an inconsistency here: unrest_pct starts at exactly 0.0 in every game, so
## the level IS the deviation. Said out loud because a reader looking at two
## measured-against-start terms and one absolute one will otherwise invent a third rule.
##
## SWEPT, on `hands_off` for YIELD_DEBT_BETA's reason -- the reference has to be a path a
## government survives.
##   (i)  at the reachable grievance peak tools/unrest_probe.gd measured -- 48.74 under
##        `managed_then_austerity` -- the term moves debt_service_pct_gdp by >= 0.30
##        points of GDP, the same floor the debt term clears;
##   (ii) it does NOT exceed the debt term on that same run. A bond market pricing strikes
##        above solvency is describing something other than a bond market, and without
##        (ii) the band is another one-sided minimum.
##
## BOTH CLAUSES ARE CLOSED FORM given the two measured inputs, so tools/credit_probe.gd
## prints the crossings rather than bracketing them with whatever the grid happened to
## contain. That is V1.5c's resolution finding taken to its conclusion: if the edge can be
## solved, a grid is a worse answer than the solution. Exact crossings [0.00343, 0.01951],
## midpoint 0.01147, iterated to a fixed point the same way the debt slope was.
const YIELD_UNREST_BETA := 0.0115

## V1.6c. Guard rails on the yield, %/yr. tools/credit_probe.gd table (h) measures the
## slack rather than asserting it, because a clamp nobody has measured is a clamp that
## might be setting the model -- docs/defence-model.md's and docs/companies-model.md's
## treatment of theirs. Measured: the worst reachable regime reaches 7.9 against a ceiling
## of 25.0, so the upper rail is the unreachable guard rail it is meant to be.
##
## *** THE FLOOR IS 0.0, AND IT IS NOT AN OPINION ABOUT HOW LOW REAL RATES GO. *** The
## first version was -1.0, on INFLATION_MIN's argument that a reward should keep accruing
## in the direction the model is trying to describe. The probe found the sign bug that
## makes it wrong: Budget.recompute() computes `yield * debt_eur_bn / gdp_eur_bn`, and a
## player who runs surpluses long enough drives `debt_eur_bn` NEGATIVE -- `austerity`
## reaches -58 % of GDP. Two negatives multiply, so a treasury holding net assets would
## have PAID interest on them. A floor at zero makes that quadrant unreachable, and the
## economics agrees for free: a spread over the anchor is a CREDIT RISK premium, and a
## government with no debt has no credit risk to price.
##
## The reward direction survives the floor, and it is large: 2.0 down to 0.0 is the whole
## of the anchor. What it cannot do is go past free.
const YIELD_MIN := 0.0
const YIELD_MAX := 25.0

## V1.6c. The credit rating, as ceilings on the yield. Read top down: the first row whose
## ceiling the yield does not exceed is the rating.
##
## NOT A SECOND MACHINE, and the decomposition names this by name -- *the rating is that
## machine read at a second point*, src/sim/defence.gd's allies() shape. There is no stored
## rating, no tick, no downgrade record and no message card, because detecting a band
## CROSSING needs a remembered previous rating and that is a stateful module, which is the
## decomposition's own stated split trigger. tests/test_credit.gd reads the file and fails
## if credit.gd grows a tick_month().
##
## What the rating is FOR is legibility. The yield moves in fractions of a point and the
## spread smaller still; a letter changing is the event a player can see. That is
## unrest_pct's threshold line and military_capability's ratio -- a level alone is a number
## with no units the player can act on, which is docs/society-model.md's finding a fourth
## time.
##
## THE ANCHOR SITS INSIDE ONE BAND BY CONSTRUCTION: every nation starts at exactly
## DEBT_REAL_RATE_PCT, which is 2.0 and therefore `A`, so every game opens on the same
## letter and the letter then says something about the player rather than about the
## content. tools/credit_probe.gd table (i) checks that every band below is REACHED by
## some balance regime; a band nothing can reach is a decorative row, and the first set of
## edges left `B` unreached, which is why these are the second.
## *** THE LADDER SKIPS THE RUNG A READER WILL EXPECT, AND tools/check_names.sh IS WHY. ***
## The obvious fourth grade -- the three-letter one between A and BB -- is also a real
## Dutch political party, and the first version of this table failed the fictionalisation
## check on its first run. See tools/banned_names.txt and docs/fictionalization.md; it is
## deliberately not spelled here, because the check is a plain grep and cannot tell a note
## about the ban from the ban. `BB+` sits in that slot instead.
##
## Recorded rather than silently corrected, for two reasons. The next reader to "tidy"
## this table back to the standard ladder reintroduces the failure. And a rating scale is
## the last place anyone expects a fictionalisation check to bite, which is the point:
## content is not only what lives in data/.
const RATING_BANDS := [
	[1.00, "AAA"],
	[1.60, "AA"],
	[2.40, "A"],
	[3.20, "BB+"],
	[4.50, "BB"],
	[8.00, "B"],
	[INF, "CCC"],
]
