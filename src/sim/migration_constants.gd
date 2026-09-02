extends RefCounted

## Tuning for src/sim/migration.gd. See docs/migration-model.md.
##
## ONE RATE AND ONE BOUND, which is src/sim/region_constants.gd's position one
## session on, and the reason is the model rather than restraint: the PULL carries
## no free weight at all. Between regions it is Harris-Todaro expected income --
## output per head times the probability of being employed, a product of two ratios
## the register already publishes -- and between the cities of one region it is named
## jobs per head. Neither is a weighted sum, so there is no coefficient to author.
##
## docs/tiers/v2.md section 6 names THREE inputs -- jobs, unemployment, service
## quality -- and service quality is one figure per nation (src/sim/society.gd's
## QUALITY_KEYS), so it has ZERO variance across cities and cannot discriminate
## between two of them at any weight. Dropped and recorded rather than included at a
## weight that would be measuring nothing: V1.5b deleted DEPENDENCY_ELASTICITY
## ["health"] on the same reasoning rather than tuning against an arithmetic
## impossibility.


## Share points moved per year at a pull deviation of 1.0, applied proportionally
## to the share already there. The session's only tuned constant.
##
## PROPORTIONAL RATHER THAN ABSOLUTE, and that is what makes a share bounded with no
## number to set wrong -- src/sim/campaign.gd's log-odds argument in a second place.
## `s * (1 + rate * (pull - mean) / 12)` cannot reach zero from a positive share for
## any rate small enough that the monthly factor stays positive, so this file ships
## no share floor and tests/test_migration.gd asserts positivity instead of a clamp
## enforcing it. THAT ARGUMENT HOLDS ONLY BECAUSE EVERY PULL IS NON-NEGATIVE: the
## employment probability stays in [0.6, 1.0] because Regions.unemployment_pct() is
## clamped by economy_constants.UNEMP_MAX_PCT = 40.0, and a head count and an output
## share are both non-negative by construction -- three facts that live in other
## modules, so a session that raises that clamp past 100 or adds a negative term to a
## pull owes this argument a second look before trusting the no-floor claim.
##
## BAND, two parts, both fixed before the sweep (docs/migration-model.md section 6):
##   (i)  READABLE. Over 60 months -- one presidential term -- the largest mover's
##        share of its nation must move at least 0.1 percentage point, which is one
##        digit of src/ui/region_panel.gd's own "%.1f%%". A movement the panel
##        printing it cannot resolve is not a movement the player can see.
##   (ii) BOUNDED, AND THE CEILING IS MEASURED RATHER THAN BORROWED. Over 168 months
##        no region's share may drift more than 0.0164.
##
##        THE FIRST VERSION OF THIS CLAUSE READ SHARE_DRIFT_MAX AND WAS THE DEFECT IT
##        WAS MEANT TO AVOID. That bound is 0.05, it is evaluated on exactly the
##        quantity Migration.worst_share_drift() returns, and reading it here made the
##        clause and the guard rail ONE NUMBER WITH TWO NAMES -- so the upper crossing
##        restated the guard rail instead of measuring the model. This project names
##        that failure repeatedly: a band whose ceiling is the clamp measures the
##        clamp, V1.5c's ceiling was one regime's own peak and V1.6e's beta band was
##        measuring the clamp one session after V1.6d's was. The sensitivity was
##        measured rather than argued: at a ceiling of 0.03 the interval becomes
##        [0.0081, 0.0244] and the midpoint 0.01625, forty per cent below what a 0.05
##        ceiling shipped. A clause that mobile is not a clause.
##
##        The replacement is drawn from a ruler the bound does not own, and it is a
##        statement about Europe rather than about this file: THE MODEL'S REGIONAL
##        POPULATION SHARES MAY NOT DRIFT FURTHER OVER FOURTEEN YEARS THAN REAL
##        EUROPEAN REGIONAL POPULATION SHARES ACTUALLY DRIFT OVER A COMPARABLE SPAN.
##        A model whose people move faster than Europe's people move is wrong in a way
##        no internal consistency check can see. V1.6a's precedent exactly: the
##        business cycle's amplitude was FITTED to France's own measured growth
##        volatility rather than banded, on the rule that a band edge moves under
##        widening or refinement while a fit converges.
##
##        MEASURED, tools/region_drift.py, from the same data family the register
##        itself came from -- Eurostat demo_r_pjangrp3, read over exactly the NUTS
##        codes data/regions/<ID>.json names so the shares compared are shares of the
##        same partition the model runs, and share OF THE NATION at each end, which is
##        import_data.py's own `region population / national`. The window is the widest
##        that keeps each nation's roster stable, and where it stops is a finding:
##
##          nation  window     span  worst region        raw     /yr        @168m
##          AUT     2014-2025    11  AT13 Wien           0.0129  0.001170   0.0164
##          BEL     2014-2025    11  BE3  Bruxelles      0.0071  0.000645   0.0090
##          CHE     2014-2025    11  CH02 Espace Mitt.   0.0054  0.000493   0.0069
##          DEU     2014-2025    11  DE1  Baden-Wuertt.  0.0029  0.000265   0.0037
##          ESP     2014-2025    11  ES30 Madrid         0.0077  0.000705   0.0099
##          FRA     2014-2025    11  FRE  Hauts-de-Fr.   0.0040  0.000364   0.0051
##          GBR     2014-2019     5  UKI  London         0.0030  0.000606   0.0085
##          ITA     2014-2025    11  ITC4 Lombardia      0.0057  0.000517   0.0072
##          LUX     2014-2025    11  LU00 Luxembourg     0.0000  0.000000   0.0000
##          NLD     2014-2023     9  NL31 Utrecht        0.0034  0.000380   0.0053
##
##        THE CEILING IS THE LARGEST OF THOSE AND NOT THEIR MEAN -- 0.016381, AT13
##        (Wien) in Austria over 2014-2025, rounded to 0.0164. The model must be ABLE
##        to reproduce Europe's most mobile real region without exceeding the ceiling;
##        a mean would forbid the interesting case, which is the whole reason the
##        register carries Vienna rather than an average of Austria.
##
##        TWO WINDOWS STOP EARLY AND BOTH ARE RECORDED RATHER THAN PATCHED. Britain's
##        series ends at 2019 -- Eurostat dropped UK regions after withdrawal, the gate
##        docs/region-economy-model.md section 8 records -- so its span is five years
##        against everyone else's eleven, and it is a bound rather than a blocker
##        because its scaled figure is nowhere near the ceiling anyway. The Dutch
##        window stops at 2023 because NL31/NL33, the 2021 codes the register names,
##        VANISH at 2024 and are replaced by NL35/NL36, the 2024 codes for the same two
##        provinces -- equal to the person in every overlapping year, so a window
##        crossing that boundary measures A RE-CODING RATHER THAN A MIGRATION.
##        docs/data-sources.md carries the collision; tools/region_drift.py detects it
##        by name and prints both columns for all twelve years, so the exclusion is
##        visible rather than assumed. 2011-2013 return an EMPTY response for this
##        request, which is where the NUTS 2021 back-cast begins.
##
##        HEADROOM IS ABOUT A THIRD, ON A DEFINITION STATED RATHER THAN ASSUMED,
##        AND IT IS THE INTERESTING NUMBER RATHER THAN A COMFORTABLE ONE. THE
##        DEFINITION: the measured ceiling over the band's upper edge, 0.0164 /
##        0.0123 - 1 = 0.333 -- the ceiling's figure a third above the edge's. The
##        two are not the same unit (the edge is a monthly rate, the ceiling a
##        168-month drift), so the ratio compares magnitudes rather than like
##        quantities; on the same formula against a LIKE quantity, the ceiling is
##        ~20 % above the worst realised drift (0.0164 / 0.0137 - 1 = 0.197).
##        Realised drift is linear in the rate (table below): 0.0081
##        -> 0.0110 at 168 months, 0.0102 -> 0.0137, 0.0123 -> 0.0163. Clause (i)
##        crosses at 0.0081, so ANY CEILING BELOW ABOUT 0.0110 EMPTIES THE PASSING
##        INTERVAL ENTIRELY -- a fired kill switch, not a re-sweep, because there would
##        be no rate left that is both readable and bounded. The roster's RUNNER-UP
##        region is ES30 Madrid at 0.009858 (table above, ESP row, @168m column) --
##        BELOW that collapse threshold. If Austria's roster or this window ever moves
##        and AT13 Wien drops out of it, the next-largest real region in Europe does
##        not clear clause (i) at any rate. A later session re-measuring this ceiling
##        must re-sweep against whatever region is largest THEN rather than inherit
##        0.0164, and a re-measured ceiling that lands below ~0.0110 is a kill switch
##        to be HONOURED -- V1.5b's deletion of DEPENDENCY_ELASTICITY["health"] rather
##        than a number to tune around.
##
##        SHARE_DRIFT_MAX IS UNCHANGED AT 0.05 AND STAYS A GUARD RAIL. It is now more
##        than three times the ceiling and nothing approaches it -- worst realised
##        drift 0.0137 (FRA), slack 0.0363 -- which is a bound doing its job rather
##        than a dial that lost its purpose.
##
## TIEBREAKER, fixed before the sweep: the response is linear in the rate, so the
## band's edges are SMOOTH CROSSINGS rather than plateaux and neither edge selects.
## docs/decision-log.md's V1.5d rule therefore applies: the interior governs, and the
## midpoint of the passing interval ships. Checked for stability by refining the grid
## (V1.5b's diagnostic) -- a value that moves under refinement is a statement about
## the grid rather than a result.
##
## MEASURED, tools/migration_probe.gd table (e), emulating each candidate through
## share_delta() rather than rescaling from the shipped value -- a probe that
## rescales has its passing interval move when the shipped value moves, which is
## V1.6b's "the range was choosing the constant" wearing a second costume. The two
## columns are the largest mover's change in its share of the nation at month 60 and
## the worst region drift at month 168, over the three playable nations:
##
## PRINTED TO FIVE DECIMALS, not four -- the fourth was not enough to show the row
## the clause actually turns on. At four decimals 0.0080 and 0.0081 both print DEU's
## column as 0.0010, so a later session re-deriving this constant from the comment
## sees a fail and a pass over identical numbers. The fifth decimal is where they
## part (0.00100 against 0.00101), and it is taken from tools/migration_probe.gd's
## own table (e) rather than computed by hand, on the same rule this file already
## follows for the ceiling: measure it, do not invent it.
##
##   rate     FRA @60    DEU @60    worst region @168   band
##   0.0070   0.00351    0.00087    0.00959              fail (i)
##   0.0080   0.00401    0.00100    0.01089              fail (i)
##   0.0081   0.00406    0.00101    0.01102              PASS   <- clause (i) crosses
##   0.0090   0.00450    0.00112    0.01218              PASS
##   0.0102   0.00508    0.00126    0.01370              PASS   <- SHIPPED, the midpoint
##   0.0120   0.00596    0.00148    0.01593              PASS
##   0.0123   0.00610    0.00152    0.01630              PASS   <- clause (ii) crosses
##   0.0124   0.00615    0.00153    0.01642              fail (ii)
##   0.0140   0.00692    0.00172    0.01835              fail (ii)
##
## Passing interval [0.0081, 0.0123], midpoint 0.0102, and the value is INTERIOR to
## every grid swept -- 0.0020-0.1000, 0.0040-0.0300, 0.0050-0.0200 and 0.0060-0.0180,
## with candidates failing on BOTH sides in each. STABLE UNDER REFINEMENT, which is
## the diagnostic rather than the reassurance: the midpoint reads 0.0110 at a step of
## 0.0020, 0.0103 at 0.0005 and 0.0102 at both 0.0002 and 0.0001, so the two finest
## resolutions agree and the answer has stopped being a statement about the grid.
##
## BRITAIN IS A STRUCTURAL BOUND AND CLAUSE (i) IS NOT READ ON IT, recorded with the
## number beside it rather than tuned around -- V1.6e's treatment of the two sectors
## that sat under its floor, and V1.6a's legibility floor before that. Every British
## region carries an identical expected income by construction (docs/region-economy-model.md
## section 8: ten of twelve ITL1 codes exist, so the index was taken as a proxy), so
## its region column is EXACTLY 0.0000 at every candidate and its whole signal is
## named employers at the city level. That column reaches 0.0010 only at ~0.095,
## against a clause (ii) crossing at 0.0123 -- no rate satisfies both clauses for
## Britain, at any grid, and raising the rate until it did would break clause (ii)
## for France by a factor of eight. Luxembourg is the second bound and a harder one:
## ONE region holding ONE city, so `pull - mean` is exactly 0.0 at both levels and it
## cannot move at any rate whatever. Table (f) reports both.
const MIGRATION_RATE := 0.0102


## How far a region's share of its nation's population may drift from where it
## started, in share points. docs/economy-model.md's divergence argument is PER
## QUANTITY, so a new quantity feeding a compounding path owes it a bound -- and this
## is a bound rather than a dial: tools/migration_probe.gd reports the slack rather
## than tuning against it, which is src/sim/projects_constants.gd's position and
## src/sim/region_constants.gd's.
##
## IT IS NOT AND MUST NOT BE CLAUSE (ii)'S CEILING. It was, once, and that is the
## defect MIGRATION_RATE's comment above records: one number with two names, evaluated
## on the one quantity it guards, so the band's upper crossing restated the guard rail
## instead of measuring anything. With the ceiling measured independently at 0.0164
## this bound is more than three times it and NOTHING APPROACHES IT -- worst realised
## drift 0.0137 (FRA) at month 168, slack 0.0363, probe table (d) -- which is a guard
## rail doing its job. A later session tempted to read it as a band edge should read
## this paragraph first.
const SHARE_DRIFT_MAX := 0.05
