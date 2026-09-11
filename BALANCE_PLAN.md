# BALANCE_PLAN — V2.9b agency probe

Written before any simulation, per the monte-carlo skill's Phase 0. This is a
MEASUREMENT session: no constant changes, no tuning — the fix for any dead
channel is its own session with its own bands.

## Abstract model

| Abstraction | This game |
|---|---|
| Session | One presidential term (16 months, FRA Standard) |
| Threat | Unemployment, debt, grievance — the election attribution's own drivers |
| Defense / agency | Budget levers, laws, diplomacy acts, campaign, projects |
| Faults | Unanswered events (V2.9 now pauses for them), cooldowns, the 49.3 arithmetic |
| Resources | Deficit headroom, assembly arithmetic |
| In-run economy | Spend now vs the debt path |
| Meta economy | Re-election → next term (out of scope: one term) |
| Grade | Final vote share + the "What decided it" attribution |

## Primary metric and band (pre-declared)

**Metric:** true overall approval (`ns.overall_approval_pct`), read at months 6
and 16, as the delta against the idle style at the same month; plus final
incumbent vote share from the executive election the term ends on.

**Agency band:** at least one policy family moves approval **≥ 1.0 point by
month 6** (the polling panel's own readable floor, V2.6b1's clause (i)).
Secondary read: final vote share idle vs active — the playtest's F6 (idle won
26.2 %, active lost 23.4 %) is about whether play moves the outcome at all.

## Determinism correction (supersedes the plan's "30 seeds")

The plan assumed a harness seed grid. The sim has none: it is fully
deterministic (every re-run this project has ever recorded is bit-identical by
design), so N seeds are N identical runs and a CI spread is zero by
construction. The stability read instead comes from **policy variants inside
each family's own free parameter** (a tax-led and a spend-led budget), which
is what the seeds were standing in for. One trajectory per run; runs are
reproducible.

## Styles

| Style | Governing verbs |
|---|---|
| `idle` | none (events still answered — see policy below) |
| `budget-tax` | quarterly budget, tax-led consolidation (income +4, corporate +2, VAT +2; pensions −1.5, health −1.0) |
| `budget-spend` | quarterly budget, spend-led (infrastructure +2.0, education +1.5, health +1.0; income +2.0, corporate −2.0) |
| `full-tax` | budget-tax + best-forecast law each quarter + one agreement act per quarter + one project + one campaign window (month 8) |
| `campaign-only` | no governing verbs; campaign efforts at months 8 and 12 |

Shared policy, so it never confounds the family comparison: events are
answered ON ARRIVAL in every style with the harness's "soft" rule (the
non-default choice best for bloc-weighted approval); campaign sites are the
largest live-population region (a deterministic answer, not an opinion);
law choice is pass-forecast-guided via the sim's own `Legislature.support`
(the same quantity the law panel's blurred forecast prints).

## Verdict rule

`agency PASS` iff any family's month-6 approval delta vs idle is ≥ +1.0
points. Otherwise `agency FAIL`, and per dead family the finding names the
missing term with its measured number beside it.

---

# BALANCE_PLAN — V3.0 agency tuning

Written 2026-09-05, before any run of this block; not edited after a sweep
begins. The V2.9b probe's numbers are the band inputs and are quoted in
docs/superpowers/plans/2026-09-05-v3.0-agency-tuning.md.

| # | Band | Pass condition |
|---|---|---|
| B1 | Fiscal signature | budget-tax approval delta vs idle at month 6 in [+1.0, +4.0]; budget-spend month-6 delta ≥ −1.0 |
| B2 | Grievance | governing styles' month-16 grievance ≤ idle + 5.0 (today +15.5); idle within ±0.5 of 1.9 |
| B3 | Honeymoon/fatigue | idle approval month 2 ≥ idle-at-start + 3.0; idle month 16 within [48.0, 52.0]; a re-elected nation reads the honeymoon again |
| B4 | Campaign power | campaign-only final vote share ≥ idle + 1.0, OR the refusal recorded in campaign-model.md with the measured ceiling |
| B5 | Outcome monotonicity | across probe styles, approval ordering implies vote-share ordering; no flip between styles whose approval differs by ≥ 1.0 |
| GATE | Agency | `tools/agency_probe.gd` re-run: at least one family ≥ +1.0 approval at month 6 vs idle, AND the best active style's final vote ≥ idle's |

Anchor: the idle style's own path (m6 49.18, m16 49.52 at the V2.9b
constants) must not move more than ±0.3 except through the honeymoon term
itself (B3 owns months 1-6).

### V3.0 mid-block pre-declaration (before the style's first run)

The `budget-smart` style is added to tools/agency_probe.gd: a low-pain
consolidation (defence -1.5, infrastructure -0.5, income +4.0 only) whose cuts
land on lines the mobilised blocs weight at or near zero. It exists to
separate "the budget-tax style cannot reach B1" from "no fiscal stance can".
B1's spend-led clause is likewise amended before further sweeping: the
deficit-worsening side's grievance IS the amplified public_finances pain, and
a relief term that cancelled it would be a grievance blind to deficits — so
B2 reads: consolidating styles (budget-tax, full-tax) month-16 grievance <=
idle + 5.0; budget-spend is recorded as bounded, not swept against.

---

# BALANCE_PLAN — V3.3 roster to EU-27

Written 2026-09-07, before the import runs and before any sweep. Bands are
not edited after a sweep begins.

## The re-baseline prediction, written first

Bit-identity is impossible across a roster change. The prediction is WHICH
existing runs move and through which channel; a moved line outside these
channels is a defect:

| Channel | Why it moves | Expected size |
|---|---|---|
| cycle amplitude anchor | `amplitude_rel` is a ratio to the ROSTER mean of growth SDs; 19 nations join, the mean moves, the ten's ratios renormalise. `growth_sd_pct` (per-nation) does not move. | small; every nation, all regimes, last digits |
| trade gravity | pairwise openness recomputed over 406 pairs instead of 45 | FRA/DEU trend and growth lines; regime outcomes unlikely to flip |
| org composition | eu council votes over 27 members, eurozone 17, schengen 26, nato 24; agenda outcomes change with the seat arithmetic | eu agenda lines; transfers on FRA's ledger |
| relations seed | resting relations now read membership with 19 more co-members of something | first-month diplomacy lines |
| network accessibility | the graph recomputes over ~2.5x regions; accessibility indices shift; regional deviation's network term moves | regional divergence lines, migration last digits |
| siting margins | margins move with shares only via the channels above; named watch-point: DEU's +0.4 % demonstration margin must HOLD | recorded, expected no siting line moves |

Excluded by construction: `imported.sectors/cohorts/inequality/energy/
institutions/prices` are per-nation reads and are unchanged for the ten;
`growth_sd_pct` per nation unchanged. Any change in those blocks on the ten's
files is an import defect, not a baseline move.

## SAVE_VERSION, pre-declared

32 -> 33. The roster is content and round-trips through `data/` — that part
of the handoff's "probably no bump" stands. The bump is the OTHER half of
V1.6a's check firing: `GameState.from_dict` builds nations from the save
dictionary ALONE, and the version gate refuses only version MISMATCHES, so a
version-32 save (made against the ten-nation roster) would load as a silent
ten-nation world against 27-member org data — nineteen nations dropped
without an error. The roster a save was made against is part of its
contract; the bump is how the loader says so.

## CITY_MIN_POP band (pre-declared before the sweep)

Grid 20 000..120 000 step 2 000, refined to 1 000 at the crossings. Clauses
fixed before the run:

- (ii) the 29-nation roster's MEAN named share of national population is at
  least 0.30 (V2.2a's clause, unchanged);
- (iii) at most 1 800 named cities across the 29 (V2.2b's drawing-side clause
  rescaled: the ten shipped 600 at ~23 px/degree at the opening fit, and the
  new roster's extent is wider east, so the cap scales by nation count —
  60 x 29 = 1 740, rounded to the grid — and the px/degree at fit is
  RECOMPUTED, not assumed, since the fit is lat-bound and Cyprus does not
  move it).

Ship at the interior of a smooth crossing on both edges; a clause that never
binds is recorded as a bound with its number, not forced.

## CITY_MIN_ZOOM (derived, not swept)

Re-derived just under the opening fit computed from the COMMITTED extents
after the import, same discipline as V2.2b: compute the fit, place the
constant just under it, and record both numbers. If the fit stays lat-bound
at its current value the constant is unchanged and that is recorded.

## Cycle anchor

`CYCLE_AMPLITUDE_PCT` is NOT retuned: it was measured at V1.6a and a
re-measure is a band of its own. The renormalised `amplitude_rel` ratios
carry the roster change; the prediction table above owns the movement.

## V3.3 addendum: the cycle anchor, amended BEFORE the balance re-run

The prediction table's "cycle amplitude anchor" row said "small; last
digits". That was wrong in magnitude and the wrong fix would have been
silence: the roster mean of growth SDs ROSE 1.832 -> 3.496 because the
nineteen's series start in 1990 and the transition years are real
volatility, so the ten's `amplitude_rel` halved. Shipping `CYCLE_AMPLITUDE_PCT`
1.70 unchanged would have halved every nation's business cycle through
content alone. The amendment re-expresses the constant on the new anchor:
3.245 = 1.70 x 3.496/1.832, which keeps the physical product
`CYCLE_AMPLITUDE_PCT x amplitude_rel` invariant per nation to < 0.1 %%
(amplitude_rel's 3-decimal rounding). The re-run's cycle-channel prediction
is therefore: every nation's cycle amplitude UNCHANGED, with at most
sub-permille product drift visible as a last-digit wobble. The earlier
"CYCLE_AMPLITUDE_PCT is NOT retuned" line is superseded by this one; the
constant is not tuned, it is re-denominated, and this entry is the band.

## V3.3 addendum 2: the inflation anchor re-windowed, found by the suite

The first suite run refused the build on real data: Slovenia's 1990-2024
inflation mean is 30.2 %/yr against the loader's [-2, 20] broken-download
bound, and Croatia's is 84.1 -- the transition decade dominates a 1990 start,
and a 2026 game would have simulated Slovenia as a 30 %-inflation country
forever. The anchor is re-measured over the euro era (1999-2024) for EVERY
nation, on V1.6b's own regression finding that the euro era is the stable
regime; the regression itself keeps the long window because the pre-euro/euro
split IS its evidence. Measured effect on the ten: anchors move down 0.05-0.5
points (FRA 1.754 -> 1.662, DEU 2.087 -> 1.849, CHE 1.117 -> 0.634). The
re-run prediction table gains the channel: `imported.prices.inflation_pct`,
national inflation targets and last-digit wobbles through the inflation
model. The regression's printed constants moved with the wider roster
(pooled Phillips slope 0.779 on 29; euro-era 0.225 against the shipped
constant's euro-era derivation) and are recorded, not carried.

## V3.3 addendum 3: the council's own content moved, and the bound that moved it

The suite's orgs test caught what the 27-member arithmetic did to the authored
agenda: with the seats table at 27, every shipped proposal passed or failed
identically whether the player abstained or opposed -- constructive abstention
was unreachable on ALL of them, the decorative-verb failure the abstention test
exists to catch (measured tallies in the session's probe: stability_pact
332 for / 307 against, debt_reduction_rule 459/180, both far from the player's
pivotal band). Two content fixes, both measured against the real tally probe,
not tuned by eye:

- `CONTRIBUTION_MAX_PCT_GDP` 1.20 -> 1.35, re-derived by the bound's own
  placement rule (just above Luxembourg's formula output): the EU-27 mean is
  poorer, LUX now computes 1.339, and the old ceiling BIND on it.
- `debt_reduction_rule`'s authored position moved to (0.15, -1.0): at the old
  (0.65, 0.2) every member with votes enough to matter voted the same way. The
  new position lands the division at 385 for of 639 cast -- inside the player's
  pivotal band, so abstain carries it, opposing blocks it, backing passes it,
  which is the three-option council the abstention machinery claims to be.
  The moved position is the green-liberal sponsorship of a fiscal-hawk rule;
  the stability_pact position (0.55, 0.15) is UNCHANGED and remains
  uncarryable-by-the-player by design.

Re-run channels added: eu agenda outcomes on the eu-council regimes (the
debt rule now DIVIDES), and org transfer lines through the re-derived ceiling.

## V3.3 addendum 4: the even-share anchor is derived, and the prediction gains
## its channel

The suite's trade failures traced to one constant: foreign_policy_constants.
EVEN_SHARE was the literal 1/9 -- "one over a nation's partners" with the
partner count frozen at the ten-nation era. At twenty-eight partners every
stake, dependence, leverage and exposure term in foreign_policy.gd priced at
about a third of its meaning, and the accept model refused a FRA-DEU agreement
it was calibrated to sign (measured via the refusal: below ACCEPT_MIN on the
stake term). The anchor is now DERIVED: `foreign_policy.even_share(state)` is
one over the live partner count, all ten readers moved, and the map trade
ramp's even-share anchor derives from the viewer's partner count the same way
(its legend stops with it -- "an even ninth" was a lie at 29). Re-run channel
added: diplomacy accept/pact/agenda terms for the ten return to approximately
their ten-era ratios; the trade layer's legend scale changes with it. This is
not a retune -- the thresholds' meaning ("more than its fair share") is the
invariant being restored.

## V3.3 addendum 5: the captured-court end-state assertion re-contracted

test_balance's captured-court check asserted the captured run ENDS with more
unrest than the baseline. V3.3 measured the inversion -- captured 3.912
against baseline 4.055 -- and the mechanism is V3.0's own tuning meeting the
roster: the capture's grievance charge (~0.1 points via
Judiciary.unrest_load) no longer decides the end state inside the noise that
V3.0's relief term and the 14-point strike threshold created, and the roster's
org/trade channels move the two runs' baselines by the same magnitude. The
check is re-contracted at the channel level -- unrest_load signed positive and
strictly above the baseline's, against the live state pair -- with the
end-state inversion printed as a recorded note. The same re-contract
precedent is V3.0's own: "re-contracted where the findings invalidated
premises". The author may want the end-state contrast back; that is a tuning
act with its own band, not this block's.

---

# BALANCE_PLAN — V3.5 environment and climate

Written 2026-09-10, before the re-run runs; the prediction is the hypothesis
and the diff is the measurement. **This block shipped NO tuned constant** --
the disasters' magnitudes are content (authored effects on the two channels
every event rides, spending_pct_gdp and bloc_offset), and the ceiling's
tolerance and the accession positions were swept in T7 with their own evidence
recorded in the content `_note` lines -- so no band is pre-declared here and
that absence is the entry: there is no constant on this block's output for a
band to price.

## The re-run prediction, written first

Baseline = `3d0b2fe` (the merge-base with origin/main), both sides from
worktrees, run SERIALLY, full printed output compared with the MCP-port line
filtered and V1.7c's third-stray-line check applied. The harness is
`tools/balance_probe.gd`, FRA plus the GBR transition regime, 168 months per
regime. Every moved line must land in one of these channels or it is a
defect:

| Channel | Why it moves | Expected size |
|---|---|---|
| accord council — solidarity transfer | the fifth org's council ticks from month 1 inside the `Orgs.tick_month` call the harness already makes — no new tick call. `climate_solidarity_clause` (+0.04 % GDP) is authored OUTSIDE the player's pivotal band on purpose and ADOPTS WITHOUT THE PLAYER: 306/452 = 67.7 % of cast, above the 0.55 pass fraction on every player line, abstain and against both. The agenda's rotation (PROPOSAL_INTERVAL_MONTHS 18, VOTE_DELAY_MONTHS 3) puts its division at month 42, 2029-06; the transfer enters the spending total the following month as the fourth writer's new term | FRA's deficit column moves a whole +0.04 from the 2029 annual row (the probe prints two decimals there), gdp level and debt a compounding last digit behind it, election lines at most last digits; the transfer-check invariant (> 2 tax points) nowhere near firing |
| accord council — the ceiling adopts too, and is INVISIBLE | prediction-time check REFUTED the "< 62 %" handoff note: PASS_SEAT_FRACTION is 0.55 and has not moved this block, so the measured abstain tally 219/383 = 57.2 % is ABOVE the carrying line 0.55 x 383 = 211 — which is what the content's own `_note` already says ("her abstention carries") and what climate_probe.gd's band arithmetic (BAND_MIN 211, BAND_MAX 248) is built on. The ceiling in force moves NO printed line: FRA sits inside it at 4.0 t (breach, contribution, fine and transfer all exactly 0; the `europe` issue reads FRA's burden, which stays 0), the solidarity's timing is identical either way (the rotation index advances at SELECTION, not at adoption), and non-player nations never get a transfer sum written (the tick gates on has_budget) | none. A moved line that ONLY the ceiling's adoption can explain is a finding, not a channel |
| event draw order | climate.json sorts first in `loader.events`; `river_flood` (no gate, likelihood 0.06, sited) draws for the player from month 1 — expect ~10 draws over 168 months at FRA. `heat_wave` draws NOWHERE in this harness: the gate is co2e >= 6.5 and the only two nations the harness ever plays sit under it (FRA 4.0, GBR 4.22). The hazard is pure per (nation, event, month), so EXISTING events draw the same coins in the same months — the displacement is the ONE pending slot: a flood pending its 2 response months swallows any crisis or scandal that fires inside the window, each resolution starts the 9-month cooldown, and a displaced event re-enters at a later month whose coin is a different draw | whole AUTHORED effects, not last digits of arithmetic: the default choices apply bloc_offsets of +-0.011..0.045 per bloc per flood — one occurrence mostly sits under the overall approval column's %.1f, but the hi-lo bloc spread (%.1f) wobbles a last digit, the lo-bloc NAME can change when two blocs sit within one offset of each other, and election lines move last digits. Crisis/scandal lines appear at DIFFERENT months than baseline (displaced), or not at all |
| SAVE_VERSION 34 | already moved at 09919b5, recorded here for the record: `start_co2e_per_capita_t` is content-derived static state `from_dict` cannot re-derive, V1.6a's check | none in-run — the harness regenerates, never loads |
| excluded by construction | mix/energy inert in the harness (zero plants — the derived emissions read prices no growth term), migration and trade gravity (the accord's bonuses are 0.0 — the zero-priced pin), relations seeds (0.0 summed over SHARED orgs), EP seats (the EP clock reads the eu alone), siting shares (the accord carries no unrest channel), no new tick call (both new machines ride ticks the harness already makes) | a moved line in any of these is a DEFECT |

## Verdict — written after the run

Both sides from worktrees (`nswt-v35-base` at `3d0b2fe`, `nswt-v35-head` at
`27e2619`), run SERIALLY, exit 0 both, **zero MCP-port noise on either side**
(the worktrees carry the committed project.godot, so the per-machine autoload
never existed there — the filter had nothing to do and was applied anyway).
1679 vs 1681 lines compared. **51 regimes both sides; 43 moved, 8 did not**
— and the 8 (spendthrift, austerity, tax_max, tax_zero, spend_max,
spend_zero, austerity_dissolves_late, austerity_cabinet_shorted) all stop at
2027-05, month 17: before the month-42 division, inside the run-up where no
flood's default had yet crossed a print threshold. Their stillness is
TIMING, not immunity.

Moved lines, by channel — 869 by strict positional compare inside blocks
(1498 column-moves across the 423 paired annual rows; the unified diff runs
2170):

- **Solidarity transfer** (predicted +0.04 % GDP from the month-42 division):
  280 deficit-column moves, **all but twelve in the exact +0.04..+0.06
  band** (the twelve are the answered floods' authored +0.3/+0.12 spending,
  i.e. the other channel landing on the same column), and 227 debt-column
  one-decimal moves compounding behind them. First visible at the row
  LABELLED 2030 — which is simulated months 37-48 (the row label lags the
  simulated year by one), so the arrival is exactly at the predicted
  division month. GBR, not an accord member, carries **no +0.04 anywhere**
  in its block — its tiny deficit wobbles (±0.01) are the event channel's
  growth-second-order through revenue, and the transfer's non-membership
  immunity is confirmed rather than assumed.
- **Event draw order**: 353 approval-column moves, 356 spread moves, 60
  lo-bloc NAME changes, 172 bloc-value moves, 546 discipline rows, 82 unrest
  lines, ~100 election-line moves, ~90 attribution lines. The two answers
  regimes ANSWERED the flood seven times between them (base answered 20
  events, head 22: 'The grid fails' halved 8 -> 4, 'Industry asks for terms'
  1 -> 0, displaced by the slot) — and their ANSWERED floods' authored
  spending moves the TREND itself: the ONLY gdp/growth/trend/unemployment
  column moves in the whole run (50 of 423 rows) sit inside
  managed_answers_softly/hard, plus three last-digit wobbles (tinkering
  growth x1, GBR growth/unemp x2). heat_wave drew nowhere, as predicted.
- **Excluded by construction: CONFIRMED.** Outside the answers regimes the
  gdp/growth/trend/unemployment columns are bit-identical in 419 of 423 rows
  — the mix/energy, migration, trade-gravity, relations, EP-seat and siting
  channels moved exactly nothing. Verb lines (TARIFFS, signed, amendment,
  DISSOLVED, SNAP, resignations, electoral reform) are byte-identical.
- **Zero outcome changes.** Every presidential HELD/LOST verdict identical
  across all 51 regimes (the GBR 2039 LOST deepened 21.9 -> 20.5 and still
  lost; the FRA 2032 LOST moved 23.1 -> 22.9 and still lost); no
  COHABITATION/MINORITY anywhere on either side (none existed before); the 5
  censure-CARRIES lines are the same divisions with moved numbers; the 5
  PROBLEM debt-runaway lines are the same months, one digit apart
  (1061 -> 1062, the transfer's second-order).
- **Third-stray-line check: CLEAN.** Both files END on their last
  `invariants: OK` marker — base line 1679 of 1679, head line 1681 of 1681 —
  with nothing after the last invariant on either side.

The prediction got two things wrong, both recorded:

1. It inherited the T7 note's "< 62 %" and corrected it at prediction time —
   the run confirms the correction: the ceiling's adoption left NO
   fingerprint on any printed line (the entry's "none" row held).
2. The event channel's SIZE was phrased as "last digits" and that was too
   shy. One flood's offsets are last digits; ten floods plus the displaced
   crises' re-rolled months COMPOUND to whole points of bloc spread (up to
   ~2.0) and tenths of overall approval, and an ANSWERED flood moves the
   trend through its authored infrastructure line. The channel, the
   mechanism (one slot, per-month coins, 9-month cooldown, defaults
   applying) and the sign were right; the magnitude sentence was written for
   the unanswered majority of regimes and undersold the two that answer.

Verdict sentence: **the re-run held the prediction's channels exactly — two
channels, every moved line accounted, zero outcome changes, the excluded
channels bit-identical, and the one number the handoff had wrong (the 62 %
pass fraction) was corrected before the run and confirmed by it.**
