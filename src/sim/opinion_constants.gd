extends RefCounted

## Every tunable in the public-opinion model, in one file.
##
## Referenced as `const K = preload("res://src/sim/opinion_constants.gd")`, the
## same shape as economy_constants.gd, so opinion.gd and the polling panel cannot
## drift apart and S10's balance pass has a single place to edit. Rationale for
## every number is in docs/opinion-model.md; this file is the values, that file is
## the argument.
##
## Not in data/ on purpose. Starting tax rates are content — a designer plausibly
## authors more of them. Voter blocs are not: regional and generational breakdown
## is someday tier, so six blocs is one fixed set, forever, which is exactly the
## definition economy-model.md uses for "model parameter". See
## docs/data-architecture.md for the decision and the trigger that reverses it.
##
## Bloc names appear here and nowhere else. Every consumer iterates BLOC_KEYS, so
## moving blocs into data/ later is a change to this file plus a loader, not a
## rewrite of opinion.gd, the panel, S6 elections and the save format.

# --- Blocs -------------------------------------------------------------------

const BLOC_KEYS := ["workers", "pensioners", "urban", "rural", "business", "students"]

## Share of the electorate. A partition by dominant identity, summing to 1.0 —
## which is what makes the weighted roll-up defensible rather than arbitrary.
## V1.5b ASKED WHETHER `pensioners` SHOULD BECOME COHORT-DERIVED AND THE ANSWER IS NO,
## recorded here rather than in a doc for V1.4c's reason -- so a later session finds the
## reasons instead of the silence.
##
## The question is real and it is this project's most-named failure: `pensioners` is
## 0.24 and src/sim/demography.gd now carries France's measured 65+ share at 0.2215,
## drifting to about 0.27 over fourteen years. One quantity, two writers.
##
## Three reasons it stays authored, and the third is the one that decides:
##
##   1. It is an ELECTORATE share, not a population share. It excludes everyone under
##      18, so it is not the same quantity even before the drift -- and 0.24 against a
##      voting-age 65+ share is much closer than 0.24 against 0.2215 looks.
##   2. election_constants.BLOC_TURNOUT ALREADY models the age effect a second time.
##      Making this live would be the third writer of one story, not the second.
##   3. THE BLAST RADIUS IS ELECTIONS AND NOT APPROVAL. This table is read by
##      elections.gd twice (turnout and seats), cabinet.gd, opinion.gd and
##      polling_panel.gd -- so a live share moves election RESULTS, and would
##      re-baseline every constant measured at S5, S10, V1.3d, V1.4c and V1.5a at once,
##      inside the session that also re-baselines demographics. No measurement could
##      then attribute anything to either.
##
## THE STANDING CONSEQUENCE IS RECORDED RATHER THAN HIDDEN: over a fourteen-year run the
## model carries a growing disagreement between how many pensioners the budget serves
## and how many of them vote. V1.5c's unrest agent and docs/tiers/v1.md section 7 will
## both reach for a live electorate share, and this is the note that tells them the
## disagreement is known and priced rather than overlooked.
const BLOC_SIZE := {
	"workers": 0.30,
	"pensioners": 0.24,
	"urban": 0.15,
	"rural": 0.13,
	"business": 0.10,
	"students": 0.08,
}

const BLOC_LABEL := {
	"workers": "Workers",
	"pensioners": "Pensioners",
	"urban": "Urban",
	"rural": "Rural",
	"business": "Business owners",
	"students": "Students",
}

# --- Issues ------------------------------------------------------------------

## Every issue is a satisfaction in [-1, +1], measured as a delta against the
## nation's own starting figure. At new-game every one of them is exactly zero,
## so the model needs no calibration constant — the same trick the economy's
## potential_shift uses.
## `europe` is V1.3d's, and it is the call V1.3a, V1.3b and V1.3c each deferred
## to it by name. Everything before it priced its domestic cost through
## bloc_offset; the bloc could not, for three structural reasons and not a
## thematic one. bloc_offset never enters issue_salience, so a Europe priced on
## it could never be named by the polling panel's agenda list or by
## elections.gd's attribution() -- the two surfaces that exist to tell the player
## WHY. A split price never clears the poll-noise floor in the headline figure,
## which docs/diplomacy-model.md measured, and Europe is a split issue by nature.
## And bloc_offset is a flat additive that cannot become more SALIENT, where a
## bloc rule biting hard is precisely the thing that should raise how much the
## country argues about Europe.
##
## The cost was measured before it was taken, by tools/bloc_probe.gd: every row
## below is scaled by 1/(1+w) once europe joins it, and S10's finding was the
## RATIO of public_finances to the five spending lines, which moves by +0.39%.
## See docs/bloc-model.md.
##
## V1.4c ASKED THE SAME QUESTION FOR `ownership` AND THE ANSWER IS NO, measured the
## same way and recorded here so a later session finds the reasons rather than the
## silence. tools/companies_probe.gd table (q), against V1.3d's four tests plus a
## fifth V1.4b forced:
##
##   1. The price is not nameable otherwise -- HOLDS, identically to europe's.
##   3. A flat offset cannot become more salient -- HOLDS, identically.
##   5. But a REGULATION has 1 and 3 identically too, and V1.4b took no key. The
##      proposed distinction was that state ownership is a single standing STOCK the
##      player can point at where a burden is a per-sector rule; it does not survive,
##      because `regulation_burden` summed over three sectors is equally a stock and
##      nothing about ownership's is more pointable-at. Same footing, same answer.
##   2. The satisfaction could not clear the model's own resolution: V1.4b measured
##      this layer's channels at ~0.1 %/yr of growth and ~0.02 points of
##      unemployment. A thirteenth row of near-zeroes on the polling panel is worse
##      than no row.
##   4. And the measured cost is -1.46% on the S10 ratio, in the UNSAFE direction,
##      where V1.3d's was +0.39% in the safe one. That is STRUCTURAL rather than a
##      bad candidate row: business carries `public_finances` at 0.34 and is the bloc
##      that makes ownership divisive at all, so any row expressing the mechanic
##      leans on the bloc S10's ratio lives in. Re-measured with business at 0.04 the
##      drift falls to -0.29% -- and a row that light does not express the mechanic.
##
## What names ownership to the player instead is the authored `bloc_offset` on
## data/company-actions/ownership.json, read on the polling panel's bloc rows -- the
## surface docs/diplomacy-model.md's finding has pointed at five times.
##
## V1.5a ASKED THE SAME QUESTION ABOUT `corruption` AND THE ANSWER IS ALSO NO, on one
## of V1.3d's four tests rather than on the S10 ratio, and without a sweep. Tests 1 and
## 3 pass easily -- corruption reaches the `health` issue, which the polling panel
## already lists and elections.gd already attributes, and a negative satisfaction is
## what SALIENCE_GAIN amplifies, so it can become more salient. Test 2 passes too: the
## isolated channel moves the headline -8.32 at a saturated register.
##
## TEST 4 FAILS OUTRIGHT AND STRUCTURALLY, which is V1.4c's deciding test reached by a
## different route. `spending.health` and `corruption` both write the SAME issue, so a
## thirteenth key would be COLLINEAR with a key that already exists: the salience
## simplex would merely re-split one issue's weight between two names for one quantity,
## and no value of a new BLOC_SALIENCE_BASE row turns two names into two quantities.
## The S10 ratio was NOT swept, deliberately -- V1.3d and V1.4c each swept it because
## tests 1-4 were genuinely in tension and the drift decided; here the answer is settled
## before the drift is relevant, and sweeping to choose between a yes and a no already
## decided would be a measurement nothing reads.
##
## What names corruption to the player is the same surface ownership uses: the authored
## `bloc_offset` on the two `society` laws, plus the `health` issue moving on the
## polling panel. Sixth time that finding has been pointed at.
##
## V1.5d ANSWERS IT NO FOR THE FIFTH TIME, and the reason is new -- which is why it is
## written out rather than folded into the four above, since a reader would otherwise
## assume they are the same reason four times.
##
## Framing does not have a satisfaction to key. It modifies the WEIGHTS in
## salience_weights(), so a thirteenth entry would be an issue whose satisfaction is a
## weight -- a category error rather than a close call, and the question never reaches
## V1.3d's test 1. The three earlier noes are all about a term that DOES have a
## satisfaction and should not get its own key: ownership (V1.4c) because the mechanic
## and the cost are the same number, corruption (V1.5a) because it is collinear with
## `health`, and unrest (V1.5c) because its price is an offset at the bloc_offset site.
##
## What names the press to the player is the polling panel's agenda list REORDERING and
## elections.gd's attribution naming a different issue -- both of which framing reaches
## for free through ns.issue_salience, with no edit near either file. See
## docs/media-model.md section 11.
## V1.6b ANSWERS IT YES FOR THE FIRST TIME, and the entry is longer than the five noes
## above it because a yes has to survive tests a no never reaches. `inflation` is the
## thirteenth key. V1.3d's four tests plus the fifth V1.4b forced, in the order they
## were settled:
##
##   1. The price is not nameable otherwise -- HOLDS, and MORE STRONGLY than europe's.
##      Every no above had an authored `bloc_offset` to fall back on: ownership.json,
##      the two `society` laws, the unrest offset. Inflation ships NO VERB AND NO
##      CONTENT OBJECT -- docs/tiers/v1.md section 6 runs (a), (b) and (c) under V1.5's
##      inverted rule because there is no monetary policy in this game -- so there is
##      no authored row anywhere it could hang on. Its only alternative was an
##      `inflation_opinion_load` on unrest_opinion_load's shape.
##   3. A flat offset cannot become more salient -- HOLDS, AND IT IS THE DISCRIMINATOR
##      that separates this from the load. SALIENCE_GAIN's entire justification is that
##      bad news crowds out the rest of the agenda, and inflation is the canonical case
##      of an issue that becomes the ONLY issue. A load never enters salience_weights()
##      at all, so the load would have made that structurally impossible.
##   5. Does a prior refusal have 1 and 3 identically? NO. Unrest's price is a load
##      precisely because a grievance number is already its own salience; ownership and
##      corruption both had a bloc_offset. Nothing already refused shares this footing.
##   4. NOT COLLINEAR, and this is the test the session was most exposed to, because
##      `jobs` and `inflation` are driven by ONE quantity -- unemployment. It was
##      measured with a FIT-STYLE criterion rather than a band, which is V1.6a's lesson:
##      a band edge moves under widening, a comparison against the model's own accepted
##      standard does not. |corr(sat.inflation, sat.growth)| must not exceed
##      |corr(sat.jobs, sat.growth)| ON THE SAME RUN -- the entanglement the model
##      already accepts between two keys Okun's law links mechanically. Two things save
##      it: the LAG (INFLATION_CONVERGENCE's half-life is 12.8 months, so this prices
##      where unemployment was a year ago) and the OPPOSITE SIGN (a boom is a plus on
##      `growth` and a minus here). That is not a re-split of one weight, which is what
##      killed `corruption`; it is the first genuine TRADE-OFF in this model, and it is
##      what makes a boom cost the president something.
##   2. The satisfaction clears the model's resolution -- see tools/inflation_probe.gd.
##
## THE S10 RATIO DRIFT IS +0.766 %, IN THE SAFE DIRECTION, against V1.3d's accepted
## +0.39 % and V1.4c's refused -1.46 %. The prediction was written before the table was
## computed and it held for the reason it named: ownership leaned on `business`, which
## carries public_finances at 0.34, where inflation's row is heaviest on `pensioners`
## and `workers` and LIGHTEST on business. A control confirms the mechanism rather than
## leaving it asserted -- the same key added at a FLAT 0.11 to all six blocs drifts
## -0.059 %, so the drift is the profile and not the thirteenth key as such.
## V1.6d ANSWERS IT TWICE AT ONCE, WHICH IS A FIRST -- every previous session asked
## about ONE key -- AND THE ANSWER IS YES FOR BOTH, at a measured cost in the UNSAFE
## direction. That combination has not happened before either, so the reasoning is
## written out rather than folded into the yeses above it.
##
## `tax_capital_gains` and `tax_wealth` are the fourteenth and fifteenth keys.
## V1.3d's four tests plus the fifth V1.4b forced:
##
##   1. The price is not nameable otherwise -- HOLDS, and MORE STRONGLY THAN ANY
##      PREVIOUS CANDIDATE, including inflation's. Every no on this list had an authored
##      `bloc_offset` to fall back on. A TAX HAS NO CONTENT OBJECT AT ALL: there is no
##      data/taxes/, no action, no law required, just a slider on the budget panel. There
##      is nowhere else for the price to live.
##   3. A flat offset cannot become more salient -- HOLDS. A tax rise is exactly the kind
##      of thing SALIENCE_GAIN exists to push up the agenda.
##   5. Does a prior refusal have 1 and 3 identically? NO, and this is the test that
##      separates these two from `ownership`, which they otherwise resemble. Ownership had
##      ownership.json's authored offset; these have nothing.
##   4. NOT COLLINEAR. Both are keyed to their own rate, which no other issue reads, and
##      docs/tiers/v1.md section 6 asks in its own words for each new tax to have "a
##      visibly different bloc-weight profile from the three that exist" -- which IS this
##      test restated in content terms, a thing the row does not notice it is doing.
##   2. The satisfaction clears the model's resolution -- see tools/tax_probe.gd table (a),
##      where the reachable wealth lever alone moves 4.2 points of GDP of revenue.
##
## THE S10 RATIO DRIFT IS -0.739 % FOR THE PAIR, IN THE UNSAFE DIRECTION, against V1.3d's
## accepted +0.39 %, V1.6b's accepted +0.766 % and V1.4c's REFUSED -1.46 %. Taken alone
## the keys drift -0.270 % (capital gains) and -0.508 % (wealth). It is paid rather than
## avoided, and the reason is that THE ALTERNATIVE IS NOT A CHEAPER PRICE, IT IS NO PRICE.
## opinion.gd writes sat["tax_%s"] for every TAX_KEYS entry, so a tax without a key is a
## satisfaction no bloc weights -- and a player could then take the wealth lever to its
## ceiling for 4.2 points of GDP that cost nothing at all. That is the strictly-dominated
## free-money shape this project has caught five times, and it is worse than the drift.
##
## Where V1.4c genuinely differs: ownership had somewhere else to be priced, so its
## -1.46 % bought nothing. This drift buys the only price these two taxes can have.
##
## THE FIRST AUTHORED ROWS DRIFTED -1.640 %, PAST V1.4c's REFUSAL LINE, AND THE FIX WAS
## CONTENT RATHER THAN A CONSTANT -- V1.3d's own move when its council turned out to be a
## legislature the player controlled. tools/tax_probe.gd's control is what said so: the
## same two keys at a FLAT 0.06 across all six blocs drift only -0.106 %, so the cause is
## the PROFILE and not the two extra keys as such, exactly as V1.6b's control found for
## inflation. The first rows gave the two new taxes 0.0419 and 0.0397 of the national
## agenda against `tax_corporate`'s 0.0223 -- two taxes eight of the ten nations barely
## levy, each outweighing corporation tax by two to one. Re-authored at the anchor
## `bloc_probe.gd` used for `europe` (above `defence`, below the tax every nation
## charges), they take 0.0162 and 0.0142 against defence's 0.0122 and corporate's 0.0203,
## and the drift halves.
##
## `students` carries NO `tax_wealth` entry at all rather than a small one, which is this
## table's sparsity used on purpose: students hold no wealth, and an entry saying they
## barely care is a different claim from the model's own "an issue a bloc has no entry
## for carries no weight for that bloc".
## V1.6e ASKS IT FOR THE SIXTEENTH KEY AND THE ANSWER IS NO, on ONE of V1.3d's four
## tests rather than on the S10 ratio -- V1.5a's shape, and for V1.5a's reason.
##
## TEST 1 FAILS IMMEDIATELY AND THAT SETTLES IT. Every YES on this list was paid because
## the price was NOT NAMEABLE OTHERWISE: `inflation` ships no verb and no content object,
## and a tax has no data/taxes/ anywhere, so neither had an authored `bloc_offset` to hang
## on. Sectoral investment ships data/investment-actions/ WITH one, which is exactly what
## `ownership` had at V1.4c and exactly why its -1.46 % on the ratio bought nothing.
##
## Tests 2, 3 and 5 are not reached, because 1 decides. The S10 ratio was NOT swept,
## deliberately: sweeping to choose between a yes and a no already settled is a
## measurement nothing reads -- V1.5a's own refusal, recorded there and applied here.
##
## WHAT HAD TO BE MEASURED INSTEAD is that the authored price is LEGIBLE, since an
## authored price nothing can read would put the question straight back.
## tools/investment_probe.gd table (i), twelve months after the act: the three largest
## packages move their worst bloc by +5.80 (rural), +5.27 (workers) and -6.14 (rural)
## against a +-3.0 poll-noise floor, and move the HEADLINE by +0.31, +1.31 and -1.08 --
## clearing on the per-bloc rows and on none of the headlines, which is
## docs/diplomacy-model.md's V1.3a finding used as designed rather than rediscovered.
## A policy that divides the country should not move the average.
##
## V1.6f ASKS IT FOR THE SEVENTEENTH KEY AND THE ANSWER IS NO, on test 1 again and for
## the same reason one session later: data/project-actions/ ships an authored
## `bloc_offset` on every one of its ten entries, so the price is nameable without a key
## and a key would be `ownership`'s -1.46 % bought twice. The ratio was not swept, on the
## same ground. What was measured instead is the same thing V1.6e measured: all ten
## actions clear the +-3.0 floor on their worst bloc row (+4.45 urban to -5.23 urban) and
## none of them on the headline.
##
## The interesting half is that TWO CONSECUTIVE SESSIONS FAILED ON THE SAME TEST FOR THE
## SAME REASON, which is what the list is for. A session that ships a content object has
## somewhere to put the price; a session that ships only a statistic does not. That, and
## not importance, is what has decided every one of the seventeen.
##
## V2.8 ASKS FOR AN EIGHTEENTH AND THE ANSWER IS NO ON TEST 1, the sixth consecutive
## session for the same reason: data/energy-actions/ authors a `bloc_offset` on all
## seven of its entries, and the LOCAL price lands on the same register --
## Energy.opposition_points() charges the blocs the action already names, scaled by
## the region's concentration, so the siting's politics is nameable without a key
## too. The ratio was not swept, on the same ground as V1.6e's and V1.6f's. See
## docs/energy-model.md section 10.
const ISSUE_KEYS := [
	"jobs", "growth",
	"tax_income", "tax_corporate", "tax_vat", "tax_capital_gains", "tax_wealth",
	"health", "education", "defence", "pensions", "infrastructure",
	"public_finances", "europe", "inflation",
]

const ISSUE_LABEL := {
	"jobs": "Unemployment",
	"growth": "The economy",
	"tax_income": "Income tax",
	"tax_corporate": "Corporate tax",
	"tax_vat": "VAT",
	"tax_capital_gains": "Capital gains tax",
	"tax_wealth": "Wealth tax",
	"health": "Health",
	"education": "Education",
	"defence": "Defence",
	"pensions": "Pensions",
	"infrastructure": "Infrastructure",
	"public_finances": "Public finances",
	"europe": "Europe",
	"inflation": "Inflation",
}

## Deltas that saturate an issue's satisfaction at full strength.
const JOBS_SCALE_PP := 3.0        # points of unemployment
const GROWTH_SCALE_PP := 4.0      # points of growth away from trend
const TAX_SCALE_PP := 16.0        # points of a tax rate — the default, see below
const SPEND_SCALE_PP := 6.0       # points of GDP on a spending line

## V1.6d. PER-KEY OVERRIDES on TAX_SCALE_PP, for the taxes whose rate is not on the
## same scale as income's.
##
## Sparse on purpose, exactly like BLOC_SALIENCE_BASE below: a tax with no entry here
## reads the shared constant above. V3.0 deliberately ends the table's income
## abstention — the agency sweep's B1 lever IS income's rate scale (8.0 -> 24.0,
## the fiscal re-weight, see docs/opinion-model.md) — so corporate and VAT still
## ride the default and income no longer does. The wealth and capital_gains
## entries keep their S10-fitted values: their fits were per-key against their
## own reachable spans, and nothing this session measured moved them.
##
## THE SESSION WOULD RATHER NOT HAVE ADDED THIS, and what forced it is arithmetic
## rather than taste. opinion.gd prices every tax by `for key in C.TAX_KEYS`, in POINTS
## OF RATE, and economy_constants.TAX_BASE_SHARE puts the wealth base at 4.00 against
## income's 0.50 -- so one point of wealth rate is eight points of income tax in
## revenue and the whole reachable wealth lever is three points wide. Shared, an 8.0
## scale makes the largest wealth tax in Europe read as three eighths of a satisfaction
## and the issue is politically almost invisible; the alternative was to express the
## wealth rate on the 0-70 scale with a tiny base share, which makes the number the
## player sets not a wealth-tax rate in any real sense. The units are honest and the
## table pays for it. See docs/tax-model.md section 2.
##
## `capital_gains` is here for a much weaker reason and is a genuine judgement rather
## than a forced move: headline capital-gains rates swing further than income rates do
## -- the roster spans 0.0 to 31.0 where income spans 15.0 to 24.0 -- so a rate change
## that would be a revolution in income tax is an ordinary budget in this one.
##
## SWEPT, and the band and tiebreaker are pre-committed in tools/tax_probe.gd's header.
const TAX_SCALE_PP_BY_KEY := {
	"income": 24.0,
	"capital_gains": 4.80,
	"wealth": 0.48,
}

## Points of GDP of deficit. Widened from S5's 3.0 during the S10 balance pass:
## at 3.0 the issue saturated at ±1 on a three-point move, so a deficit two
## points over the starting one and a deficit twenty points over it read exactly
## the same to a voter. Six points spans a genuine consolidation or a genuine
## blowout, which is the range the player actually moves this number over.
const DEFICIT_SCALE_PP := 6.0

## Units of bloc burden. The one scale in this table that is not a quantity in
## percentage points, because burden is already a normalised score rather than a
## measurement.
##
## NOT 1.0, and the reason is DEFICIT_SCALE_PP's exactly. bloc_constants.BURDEN_MAX
## is 1.0 and is reached only by breaching all four rules to their full tolerance
## at once -- an extreme, not a policy. The range the player actually moves this
## number over is roughly [0, 0.6]: one rule defied outright is 0.33, two is 0.59.
## At a scale of 1.0 that whole band is squeezed into the middle third of the
## issue, and tools/bloc_probe.gd measured the consequence -- one defied rule moved
## the headline figure by 3.24 points against a 3.0 noise floor, clearing it by
## almost exactly nothing, which is docs/scenario-model.md's `deu_grand_coalition`
## mistake. 0.60 maps the reachable band onto the full satisfaction range.
##
## Deliberately not folded into BURDEN_MAX: that constant bounds the MODEL and is
## what makes the four severities sum to exactly 1.0; this one converts a burden
## into what a voter feels. Collapsing them would make the burden's ceiling
## unmovable without also moving the electorate's reaction to it.
##
## Swept rather than reasoned to, because SALIENCE_GAIN makes the response to this
## constant sharply non-linear -- 1.00 gives one defied rule a headline move of
## -3.2, 0.60 gives -13.0, and the anchor that settles it is docs/coercion-model.md's
## measured -4.9 to -7.4 for a full embargo by the largest trading partner. Defying
## one bloc rule and being embargoed by Germany should cost about the same, and at
## 0.80 they do.
const EUROPE_SCALE := 0.80

## V1.6b. Points of inflation ABOVE the nation's own starting rate that saturate the
## thirteenth issue. Here rather than in inflation_constants.gd for EUROPE_SCALE's own
## reason: that file describes what inflation IS and this converts it into what a voter
## feels, and collapsing the two would make the model's bounds unmovable without also
## moving the electorate's reaction to them.
##
## SWEPT, and the band, the tiebreaker and the measured table are pre-committed in
## tools/inflation_probe.gd's header. Table (b), on the isolated path at the 0.145
## points table (a) measured as reachable: band (i) (readable past the +-3.0 poll-noise
## floor) passes at 0.40 and fails at 0.45, and band (ii) (not prematurely saturated)
## passes above the reachable 0.145 -- so the interval is two-sided on two model
## criteria and V1.5c's midpoint rule applies. Stable under refinement: 0.45, 0.50 and
## 0.55 were added between the edges and all fail (i). [0.15, 0.40] -> 0.275.
##
## THE TABLE THAT CHOSE THIS IS INVARIANT TO IT, which had to be fixed before the
## answer meant anything. The probe cannot change a const at runtime, so a candidate
## scale is emulated by displacing the stock to whatever produces the SAME
## satisfaction -- exact, saturation included. The first version rescaled the measured
## headline linearly from the shipped value instead, and the passing interval MOVED
## when the shipped constant moved: V1.5b's "the range was choosing the constant" in a
## new costume. Caught only by setting the constant once and re-running.
##
## BAND (ii) WAS DECLARED TOO WEAK AND THE CORRECTION IS RECORDED RATHER THAN TIDIED.
## It asked that the issue not saturate at HALF the reachable deviation, which 0.10
## passes while saturating at the FULL one -- so as declared it would have admitted the
## exact DEFICIT_SCALE_PP failure it was written to prevent. The binding form is
## saturation at the peak, which is what the interval above uses. V1.4c's rule, fix the
## band as well as the tiebreaker, applied to a band that was merely loose rather than
## measuring the wrong thing.
const INFLATION_SCALE_PP := 0.275
##
## Small compared with every other scale in this table, and that is the model rather
## than a thumb on it. INFLATION_UNEMP_BETA is 0.25 and the reachable unemployment gap
## is a couple of points, so the whole reachable range of this quantity is under a
## point -- where DEFICIT_SCALE_PP spans six points of GDP because that is the range a
## player actually moves a deficit over. A scale is the range the number MOVES over,
## not a statement about how much the issue matters; how much it matters is
## BLOC_SALIENCE_BASE, where inflation is the fourth-heaviest row for pensioners.

## V1.5a. Points of GDP of service-quality DEVIATION that saturate the satisfaction
## term, in the same units as SPEND_SCALE_PP above and deliberately so: quality and
## the spending delta land on the same issue, so the RATIO of these two constants IS
## the double-count answer, and expressing them in different units would hide it.
##
## BAND, fixed before the sweep: the quality channel must move the headline approval
## figure past the ±3.0 noise floor at a reachable sustained spending change.
##
## TIEBREAKER, also fixed before the sweep: the ratio against SPEND_SCALE_PP = 3.0,
## with the pre-committed rule that if the two terms SUMMED under a sustained change
## exceed what SPEND_SCALE_PP produced on its own, SPEND_SCALE_PP is re-measured
## DOWNWARD rather than this constant being shaved. That direction is the point --
## the delta term was measured at S10 against a world where delivery was instant, and
## it is the older number that was wrong about the total, not the new one.
##
## THE BAND FAILED AND THE TIEBREAKER TURNED OUT TO BE A TEST THAT COULD NOT FAIL.
## Both are recorded rather than tidied, because both are the session's findings.
##
## The band was measured on the wrong path: it asked whether "the quality channel
## alone" moves the headline, through a +1.0 pt spending increase -- and raising a
## line necessarily widens the deficit, so the quality channel alone was never
## observable there. On the isolated path (the stock moved with every spending line
## untouched, so every other issue is bit-identical between the runs) it passes at
## 3.0, 4.5 and 6.0 and fails at 9.0 and 12.0.
##
## The tiebreaker said: if the two terms summed exceed what SPEND_SCALE_PP produced
## alone, re-measure SPEND_SCALE_PP down. Any positive stock term adds to the total, so
## it fires for every candidate -- V1.3e's own criticism of its split trigger, in a new
## place. What replaced it: the delivery half must be worth LESS than the announcement
## half, because an announcement is certain and immediate where delivery is contingent
## and lagged, which is ratio > 1.0 against SPEND_SCALE_PP; and the smallest passing
## value satisfying that is what ships. That rule chose 4.5 where this constant had
## been provisionally set to 6.0, which is the evidence it was not written backwards
## from a number already picked.
##
## SPEND_SCALE_PP was deliberately NOT re-measured AT V1.5A, and that sentence is
## now history rather than fact: V3.0's fiscal re-weight moved it 3.0 -> 6.0 as a
## B1 lever (the S10 scales priced a spending change at twice what the agency band
## could survive), which HALVES this ratio to 0.75 -- delivery is now worth more
## per point than the announcement, the opposite of the rule that chose 4.5. The
## inversion is accepted, not re-swept: the V1.5a fit rule would demand 9.0
## against a 6.0 spend scale, and re-measuring quality's own band was outside the
## block's declared levers. FLAGGED for the next balance pass -- either
## QUALITY_SCALE_PP re-fits to the rule or the rule is retired; see
## docs/opinion-model.md's V3.0 section.
##
## Full tables: docs/society-model.md (c).
const QUALITY_SCALE_PP := 4.5

# --- Salience ----------------------------------------------------------------

## What each bloc cares about, before the news moves it. Sparse — an issue a bloc
## has no entry for carries no weight for that bloc, which is what makes
## "fixing something nobody cares about buys nothing" true. Each row sums to 1.0;
## the code normalises anyway, so a tuning pass need not keep it that way.
##
## Note pensioners weight pensions far above anything else and students at
## nothing. That pair is the S5 done-when condition, and it is a property of this
## table, not of code.
##
## The public_finances row was raised across every bloc during the S10 balance
## pass. At the S5 weights it carried about 0.10 of the national agenda against
## roughly 0.50 for the five spending lines, which made fiscal discipline a
## strictly dominated strategy: a budget with every spending line maxed and every
## tax at zero ran a deficit of 112% of GDP, walked debt to 1346% of GDP, and
## still held approval at 57 and won three consecutive elections, while an
## austerity budget that ran a surplus lost. Roughly doubling this one row is the
## whole fix — and it is surgical, because a player who never touches the budget
## sits at a public_finances satisfaction of about zero and is untouched by the
## change. It bites only once the player moves the deficit, in whichever
## direction. Found by tools/balance_probe.gd.
## The `europe` row is V1.3d's, and it is the only issue in this table whose
## entries are NOT the row a bloc would write for itself. Every satisfaction in
## opinion.gd enters every bloc's score with the SAME SIGN -- blocs differ in how
## much they weigh an issue, never in which way it moves them -- so a bloc cannot
## be authored as pro-European through this channel. The entries below are
## therefore "how much does being overruled from Brussels dominate this bloc's
## agenda", one-signed, and the political SPLIT falls out of the rows that were
## already here rather than being authored:
##
##   pensioners (0.24) and rural (0.13) carry NO `growth` entry at all, so 37% of
##   the electorate receives the sovereignty cost and none of the single market's
##   upside, while business weights growth 0.19 and public_finances 0.34 and gets
##   both. A eurosceptic countryside and a pro-European boardroom, measured off a
##   table written at S5 for reasons that had nothing to do with Europe.
##
## Rows no longer sum to 1.0 and do not need to -- salience_weights() renormalises
## and the comment above already said a tuning pass need not keep them that way.
## What that renormalisation costs the eleven measured issues was the session's
## first measurement, not an afterthought: see tools/bloc_probe.gd table (a) and
## docs/bloc-model.md.
const BLOC_SALIENCE_BASE := {
	"workers": {
		"jobs": 0.34,
		"public_finances": 0.18,
		"tax_income": 0.15,
		"inflation": 0.13,
		"health": 0.10,
		"europe": 0.10,
		"tax_vat": 0.08,
		"growth": 0.08,
		"pensions": 0.07,
		"tax_capital_gains": 0.01,
		"tax_wealth": 0.01,
	},
	"pensioners": {
		"pensions": 0.38,
		"health": 0.21,
		"public_finances": 0.20,
		"inflation": 0.16,
		"jobs": 0.13,
		"europe": 0.10,
		"tax_vat": 0.08,
		"tax_capital_gains": 0.03,
		"tax_wealth": 0.02,
	},
	"urban": {
		"health": 0.19,
		"jobs": 0.18,
		"public_finances": 0.17,
		"education": 0.14,
		"infrastructure": 0.11,
		"tax_income": 0.11,
		"inflation": 0.10,
		"growth": 0.10,
		"europe": 0.06,
		"tax_capital_gains": 0.02,
		"tax_wealth": 0.01,
	},
	"rural": {
		"infrastructure": 0.20,
		"public_finances": 0.18,
		"jobs": 0.16,
		"europe": 0.14,
		"health": 0.13,
		"defence": 0.12,
		"tax_vat": 0.11,
		"inflation": 0.11,
		"pensions": 0.10,
		"tax_wealth": 0.02,
		"tax_capital_gains": 0.01,
	},
	"business": {
		"public_finances": 0.34,
		"tax_corporate": 0.25,
		"growth": 0.19,
		"infrastructure": 0.09,
		"jobs": 0.07,
		"europe": 0.06,
		"inflation": 0.06,
		"education": 0.06,
		"tax_wealth": 0.06,
		"tax_capital_gains": 0.05,
	},
	"students": {
		"education": 0.38,
		"jobs": 0.22,
		"public_finances": 0.14,
		"tax_vat": 0.10,
		"inflation": 0.09,
		"growth": 0.08,
		"health": 0.08,
		"europe": 0.05,
		"tax_capital_gains": 0.01,
	},
}

## How much bad news raises an issue's weight. Applied as
## `base * (1 + GAIN * severity)` and then renormalised, so weights stay on the
## simplex and no amount of bad news can make them compound.
##
## Raised from S5's 1.0 in the S10 balance pass. This is the constant that makes
## losing *attributable*: the election result screen names the most-salient
## issues at the moment of the vote, so at a low gain it names whatever the base
## table says regardless of what actually went wrong in the run. At 5.0 the issue
## the player is failing on climbs to the top of the agenda and the result screen
## names it. The renormalisation argument above is what keeps this safe to raise.
##
## It is also the constant that repairs the model's one non-monotone corner.
## Satisfaction is clamped to [-1, +1], so once a deficit has saturated
## public_finances at -1 it cannot get any worse — and every further giveaway is
## then free upside. A budget with every spending line maxed *and* every tax at
## zero used to be more popular than either half on its own, because the second
## half added three saturated positives against a negative already at the floor.
## The gain is the only term that can outweigh that: it multiplies the weight by
## (1 + GAIN * severity), so an issue in crisis (severity 1.0) grows six times
## while one that is merely uncomfortable (severity 0.3) grows 2.5 times. The
## flip point for that combined-giveaway budget sits between 4.0 and 4.5; 5.0 is
## chosen for headroom past it, and costs a managed budget nothing measurable
## against a do-nothing one. Found by tools/balance_probe.gd.
const SALIENCE_GAIN := 5.0

# --- Approval ----------------------------------------------------------------

## Where every bloc starts and where a bloc with nothing to complain about sits.
## V3.0 discharges this file's own S5 deferral — see time_in_office_offset()
## below for the honeymoon and fatigue that were "V1" for four tiers.
const APPROVAL_NEUTRAL := 50.0

## Satisfaction is bounded to [-1, +1], so target approval lives in [10, 90] and
## the hard clamp below is a guard rail that never binds under sane play.
const APPROVAL_SPAN := 40.0

const APPROVAL_MIN := 0.0
const APPROVAL_MAX := 100.0

## Fraction of the gap to target closed per month. Half-life ~2.4 months.
##
## Deliberately fast. Opinion sits downstream of an economy that already lags —
## Okun plus a three-year reversion — so a slow inertia term would put two lags in
## series on the channel that is already the slowest, and the game would stop
## answering. A spending change hits its issue with no lag at all, which is where
## this constant actually shows: roughly 58% of the move lands within three
## months. See docs/opinion-model.md.
const INERTIA_RATE := 0.25

# --- Time in office (V3.0) ---------------------------------------------------

## The S5 deferral, discharged. Points of approval added to every bloc's TARGET,
## uniform across the six blocs the way unrest_opinion_load is — a fresh mandate
## is a fact about the government, not about one row of the electorate. Because
## it rides the target, INERTIA_RATE still governs the path: nothing jumps.
##
## The SHAPE is a rise-then-decay pulse minus a capped drift, and offset(0) is
## EXACTLY 0.0 on purpose: test_opinion and test_scenario both pin the init
## figure (the standard start sits on APPROVAL_NEUTRAL to 1e-9; a scenario's
## authored bloc_approval reaches state to 0.001), and init_nation's own
## _tick_nation call would read this at month 0. A +6 day-one figure would have
## broken both pins and the scenario override's equilibrium inversion with them;
## a pulse that climbs through INERTIA delivers the same play shape — approval
## rising over a mandate's first months — at zero re-baseline. The one-month
## lag this shape implies (Elections increments months_in_term AFTER Opinion
## reads it) is absorbed by the band sweep, not corrected here.
##
## The counter is Elections'. months_in_term has counted the mandate since V1.2
## — incremented under the same has_budget + in_government gate Opinion ticks
## under, reset at every executive resolution, serialised since V1.8 — so the
## deferral needed no new field and no SAVE_VERSION move, which is the finding
## the plan that built this wrote down: the missing piece was always a READ,
## never a register.
const HONEYMOON_MAX := 6.0
const HONEYMOON_RISE_MONTHS := 1.0
const HONEYMOON_HALF_LIFE := 4.0
const FATIGUE_PER_YEAR := 0.9
const FATIGUE_MAX := 6.0

## months_in_office is the mandate age, Elections.months_in_term. Negative is
## "unknown" and reads exactly zero — the silence-first shape every absence in
## this save format uses — though no save can carry one: the field has existed
## since V1.8.
static func time_in_office_offset(months_in_office: int) -> float:
	if months_in_office <= 0:
		return 0.0
	var t := float(months_in_office)
	var honeymoon := HONEYMOON_MAX \
		* (1.0 - pow(0.5, t / HONEYMOON_RISE_MONTHS)) \
		* pow(0.5, t / HONEYMOON_HALF_LIFE)
	var fatigue := minf(FATIGUE_MAX, FATIGUE_PER_YEAR * t / 12.0)
	return honeymoon - fatigue
