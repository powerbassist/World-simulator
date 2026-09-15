---
title: Agency Model
tags:
  - model
  - simulation
  - opinion
  - balance
---

# Agency Model

The competence-credit channel: how running the country *well* — as opposed to
running it *differently* — reaches a voter. Designed and banded at
[[tiers/v4|V4.0]], before any code or sweep, on the author's route call of
2026-09-14. This document is the bands; every later task in the block is judged
against §4 exactly as written here.

Files (as planned; none exists yet): `src/sim/opinion_constants.gd` (one new
constant, `COMPETENCE_SPAN`) · `src/sim/opinion.gd` (one new addend in the
per-bloc target) · `tools/agency_probe.gd` (the sweep) · this file (the
argument).

## 1. The measured defect

The V3.0 probe (reports/agency-probe-v3.0.md, 2026-09-05, at `9155313`)
re-ran the agency question after the fiscal re-weight and the honeymoon, and
its gate **FAILED by measurement**. Quoted verbatim, because everything in
this document is an answer to these two sentences:

> The gap between the best active style and idle closed from **−7.57 to −2.00
> approval points** and from a 3-point vote deficit to a **0.2-point** deficit,
> but no declared lever flips the sign.

> idle is locally optimal BY CONSTRUCTION — every satisfaction is a delta
> against a starting figure, so doing nothing is exactly neutral while any
> change is partly punished, and the honeymoon/fatigue term applies to both.

The table behind it, restated because the bands below name its rows:

| style | appr m6 | appr m16 | d_m6 | unemp m16 | defic m16 | vote % |
|---|---|---|---|---|---|---|
| idle | 51.09 | 49.44 | +0.00 | 7.58 | 5.22 | 26.4 |
| budget-smart | 49.08 | 48.73 | **−2.00** | 8.17 | 2.02 | 26.2 |

`budget-smart` — the best active family the probe could construct (defence
−1.5, infrastructure −0.5, income +4.0) — **halved the deficit** (5.22 → 2.02
at month 16) and was *punished* 2.00 approval points for it at month six. The
V2.9b playtest's F1 had already suspected the shape: *"the competence credit
is real and out-muscled"* — it exists inside the current satisfactions only
in amplified-negative form. The probe's route list is this block's charter;
route 1 is the one taken.

## 2. The channel form — settled

The author's call of 2026-09-14, recorded here so the code in Task 2
implements it verbatim and no later session re-opens it: **outcome LEVEL vs
the inauguration figures, symmetric in sign, uniform across blocs**, added
into the per-bloc approval TARGET beside `K.time_in_office_offset(...)` —
the site the honeymoon already rides, so `INERTIA_RATE` governs the path and
nothing jumps.

```
credit = COMPETENCE_SPAN * clampf(
    (start_unemployment_pct - unemployment_pct) / JOBS_SCALE_PP
  + (start_deficit_pct_gdp   - deficit_pct_gdp)   / DEFICIT_SCALE_PP
  + (growth_annual_pct       - trend_annual_pct)  / GROWTH_SCALE_PP,
  -1.0, 1.0)

target = APPROVAL_NEUTRAL + time_in_office_offset(months_in_term)
       + credit
       + APPROVAL_SPAN * clampf(score + law_offset - unrest_opinion_load, -1, 1)
```

Three properties, each deliberate:

- **LEVEL, not delta.** The three addends are the *same expressions* the
  `jobs`, `public_finances` and `growth` satisfactions already compute —
  `opinion.gd:163`, `opinion.gd:164`, `opinion.gd:246` — read at their own
  scales (`JOBS_SCALE_PP` 3.0, `DEFICIT_SCALE_PP` 6.0, `GROWTH_SCALE_PP`
  4.0). What is new is not the measurement but the *sign structure*: the
  existing terms price the level inside the salience simplex, where a bloc
  that barely weights an issue barely feels the record; the credit prices
  the record itself, once, uniformly. Reusing the three expressions is the
  anti-double-counting answer **in the other direction**: the credit is
  deliberately small (§4's C1 names +1.0 the pass floor, not the target),
  and its clamp is separate so a saturated satisfaction cannot leak a second
  windfall through the credit.
- **Symmetric in sign.** A president who leaves unemployment *above* the
  inauguration figure gets a negative credit. Symmetry is what makes C2 (§4)
  a real test rather than a formality, and it is the property that keeps the
  channel honest: it prices the record, and a bad record is a record.
- **Uniform across blocs.** The same shape `unrest_opinion_load` and the
  honeymoon already use — a fact about the government, not about one row of
  the electorate. An authored per-bloc row would be a table with no
  measurement behind it, which is the reason `unrest_constants` gave for its
  own uniformity and the reason the credit inherits.

**Refused form 1 — milestones.** A register of fired thresholds ("deficit
under 3 %, once") was rejected on two grounds. It is pulse-gaming: a player
who crosses the line collects the credit once and can let the figure rot, so
the channel prices *crossing*, not *governing*. And the fired-register is
state the save must remember — a `SAVE_VERSION` move bought for a form whose
whole virtue over the level form is that it can be gamed *less* honestly.

**Refused form 2 — decaying credit.** A stock that accumulates while
outcomes are good and decays when they are not was rejected on one ground
with a named trigger. It is a second stored register (again
`SAVE_VERSION`-bearing), and what it buys over the level form is a *memory
of competence past* — a president coasting on a good first year. That is a
real shape, and it is the fallback: **if the level form misses C1's gate,
the decaying form is the next measurement, taken knowingly with its version
bump**, not a silent upgrade.

## 3. What the channel is not

- **Not an activity drag.** Route 2 (idle pays a fatigue the active player
  escapes) is the *mirror*, and the tier doc records the difference as
  legible in play: this channel rewards the player who acts and leaves the
  idle player where they were. C3 exists to prove the second half of that
  sentence by measurement rather than by assertion.
- **Not a new issue.** The credit enters the target directly, beside the
  honeymoon — it never enters `issue_satisfaction`, so it cannot be split by
  the salience simplex, cannot be amplified by `SALIENCE_GAIN`, and cannot
  be named as an issue on the polling panel. That is `unrest_opinion_load`'s
  placement argument (a same-quantity loop through the simplex is unbounded)
  applied to a positive term.
- **Not a verb, not content, not a new regime.** The tier row refuses new
  content outright; the channel is one constant and one addend.

## 4. The bands — pre-declared before any sweep

These are the pass conditions every later task is judged against. Written
2026-09-14, before `tools/agency_probe.gd` is touched. The probe's V3.0
instrument is reused; the poll-noise readable floor is **±3.0** on a
headline figure and the readability bar for a *family-vs-idle margin* is
**+1.0**, both carried from the V3.0 block unchanged.

| # | Band | Pass condition |
|---|---|---|
| C1 | Competence credit | `COMPETENCE_SPAN` swept; best active family moves month-6 approval ≥ **+1.0** vs idle (the poll-noise readable floor) WITHOUT moving idle's own m6 by more than ±0.3 |
| C2 | Negative control | `budget-bad` style (acts: cuts health/education, raises VAT — outcomes worsen) scores month-6 delta vs idle ≤ **0.0** — acting badly must not gain |
| C3 | No free lunch | idle's month-6 and month-16 approval stay within ±0.3 of the V3.0 baseline (51.09 / 49.44) once the honeymoon path is accounted — the channel must not pay the idle player |
| Q1 | QUALITY re-fit | on the ISOLATED path (stock moved, spending lines untouched) the quality channel moves the headline past ±3.0 at a reachable sustained deviation, AND `QUALITY_SCALE_PP / SPEND_SCALE_PP > 1.0`; ship interior of the crossing, target above 6.0 |
| E1 | Eurozone/Schengen price | a Schengen trade bonus / euro credit channel at any reachable magnitude moves a player-visible figure past the ±3.0 poll-noise floor; if not, record the bound and the number |

**Q1 is the re-fit, and both of its branches are declared now.** V1.5a chose
`QUALITY_SCALE_PP` 4.5 on the rule *delivery must be worth LESS than
announcement* — ratio > 1.0 against `SPEND_SCALE_PP`, then 3.0. V3.0's
fiscal re-weight moved `SPEND_SCALE_PP` to 6.0 and **inverted the rule to
0.75**, accepted rather than re-swept, with the obligation flagged for this
block ([[opinion-model]] §V3.0, and the constant's own comment). V4.0
discharges it: re-fit `QUALITY_SCALE_PP` on the isolated path V1.5a measured
(the stock moved, every spending line untouched), sweeping **above 6.0
toward 9.0** — the value the fit rule demands against a 6.0 spend scale.
*Branch one:* a passing value above 6.0 ships, interior of its crossing on
V1.5d's rule. *Branch two:* no value above 6.0 passes the readability
clause — then the bound is recorded with its number and **the
delivery-under-announcement rule is retired**, the constant stays 4.5, and
the record says the V3.0 inversion stands as the model's answer. What does
not ship is a third thing: the inversion left in place *unmeasured*.

**E1 is the zero-price obligation, discharged as a band rather than built as
a feature.** [[orgs-model]]'s deliberately-absent list ships Eurozone and
Schengen zero-priced and names this block's pre-declaration as the trigger
for pricing them. The band measures whether either channel — a Schengen
trade bonus or a euro credit channel, at any reachable magnitude — moves a
player-visible figure past the ±3.0 poll-noise floor. If one does, the
pricing decision goes back to the author *with the number*. If neither does,
the zero price is no longer an absence but a **measured bound**, recorded
here with the figure, and the obligation closes. Either outcome discharges
the trigger; what the band forbids is the question staying open by default.

**The V4.1 agreement clause.** [[tiers/v4|V4.1]]'s programme — a player
agenda with goals, deadlines and progress — ends its pitch with: *"succeeding
is the competence credit V4.0 may have just built a channel for — **the two
blocks must agree on that channel or state why they do not.**"* The agreement
is stated here so V4.1's plan cites it rather than re-deriving it: **a
programme entry's success is the natural competence credit — the SAME
channel.** A completed goal lands as a bounded, temporary lift to the credit
term of §2 (same target site, same clamp, same `INERTIA_RATE` path); a failed
goal lands symmetrically negative. What V4.1 does *not* build is a second
approval register keyed to promises — two machines pointed at one job is what
`legislature.gd`'s single-applier argument exists to prevent, and the pledge
absorption question is the decomposition session's, not this block's.

## 5. Predictions, written before the run

V1.7c's discipline: the predictions live here so the sweep's report can be
checked against something other than its own output.

- **C1 passes at a small `COMPETENCE_SPAN`.** The `budget-smart` family's
  record at month 6 is unemployment *worse* (Okun cost of the cuts) and
  deficit *better*; the credit nets the two, so the span that flips the
  family past +1.0 is an empirical question, not an obvious one. If no span
  in the swept grid passes C1 **and** C2 simultaneously, the decaying form
  (§2's refused form 2) is the declared next step.
- **C3 holds by construction and is tested anyway.** The idle run's outcomes
  never leave the inauguration figures, so its credit is exactly zero at
  every month — but "by construction" is what V3.0 said about the honeymoon
  before `test_unrest`'s reachability check caught the threshold at 2.5×
  the harshest sane austerity. The band is written because the assertion is
  cheap and the class is real.
- **Q1's branch is genuine.** V1.5a's isolated table passed at 3.0, 4.5 and
  6.0 and failed at 9.0 and 12.0 — against the *old* spend scale. The
  re-fit asks whether the interval above 6.0 is empty, and the answer is not
  known in advance.

### 5a. The sweep grid, declared before the run (2026-09-14, Task 4)

Written here before the first candidate ran, V1.7c's discipline applied to
the sweep itself:

- **Grid.** `COMPETENCE_SPAN` over **[1, 8] step 1** (the tier's declared
grid), refined to **step 0.25** at any crossing the coarse pass finds.
Each candidate is set in `src/sim/opinion_constants.gd`, then the probe is
run `godot --headless --script res://tools/agency_probe.gd -- --json`, and
C1 (best active family m6 delta ≥ +1.0), C2 (`control_bad_delta_m6` ≤ 0.0)
and C3 (idle's own m6 within ±0.3 of 51.03, the span-0 reading on this
tree) are read off the JSON. A span-0 control on this tree anchors the
per-unit slopes.
- **Q1 grid.** `QUALITY_SCALE_PP` over **{6.5, 7.0, 7.5, 8.0, 9.0}** on the
isolated path (below), refined at the crossing.
- **E1 method.** The Schengen `trade_bonus` set directly on the loaded org —
the path an authored price would take, `Trade._raw` reading it through
`Org.shared_bonus` — everything else bit-identical, the headline read at
60 and 168 months; the euro side checked for any existing channel to price.

### 5b. What the sweep measured — the gate verdict is FAIL

**The headline result: C1 is unreachable at ANY span in the declared grid,
and the reason is a mechanism no span can fix.** The response is exactly
linear in span (bit-stable across the whole grid) and the slope is NEGATIVE
for every style, idle included. Per span unit, idle's own m6 falls **0.2325**,
budget-smart falls **0.3002**, budget-bad falls **0.3916** — so the
best-active-family delta against idle moves **−0.0678 per unit**, away from
the +1.0 band, from a starting −2.04 at span 0. C1 would need span ≈ 45,
past the credit's own ±1.0 clamp long before; C3 caps the span at ≈ 1.02
(the 0.3-edge crossing: 0.296 measured at 1.0, 0.354 at 1.25).
The two bands are incompatible in opposite directions, which is the
V1.5c inconsistent-clause finding in a new place.

**The mechanism, measured with a scratch decomposition of the credit's three
addends at month 6:** at month 6 the sim's cycle has France 0.40 % below
potential (a fresh-game downswing, `cycle_impulse_pct` −0.27 → −1.22 over
the six months) with annual growth **0.08 %/yr against a 1.31 % trend**, so
the growth addend reads **−0.31 for EVERY style including idle** before any
policy moves. The three styles' records at m6: idle −0.370, budget-smart
−0.364, budget-bad −0.381 — a between-style differential of ~0.02 record
units against a shared −0.37 world term. (Note the m6 records order
differently from the measured slopes — idle's record is worse than
budget-smart's here, yet budget-smart falls faster per span unit — because
approval integrates the record's PATH over the six months through
inertia, not the m6 snapshot alone.) **The level form prices the WORLD,
not the RECORD's policy component**: the inauguration-anchored level reads
the business cycle the president inherited, and amplifying it moves idle and
the active families apart at only +0.068/span-unit while driving both down.

The measured table (every figure from the probe's own JSON; C3 quoted
against the V3.0 baseline 51.09/49.44, the span-0 tree anchor reading
51.0268/49.3666):

| span | C1 best Δm6 | C2 bad Δm6 | C3 idle m6 (|Δ 51.09|) | C3 idle m16 (|Δ 49.44|) | verdict per band |
|---|---|---|---|---|---|
| 0 (control) | −2.0380 | −5.5638 | 51.0268 (0.063) | 49.3666 (0.073) | C1 fail, C2 pass, C3 pass |
| 1 | −2.1057 | −5.7229 | 50.7943 (0.296) | 49.2954 (0.145) | C1 fail, C2 pass, C3 pass |
| 1.25 | −2.1227 | −5.7627 | 50.7362 (0.354) | 49.2776 (0.162) | C3 **fails** at m6 — the bound's edge |
| 2 | −2.1735 | −5.8824 | 50.5618 (0.528) | 49.2242 (0.216) | C1 fail, C2 pass, C3 fail |
| 3 | −2.2413 | −6.0414 | 50.3293 (0.761) | 49.1529 (0.287) | C1 fail, C2 pass, C3 pass m16 only |
| 4 | −2.3090 | −6.2002 | 50.0969 (0.993) | 49.0817 (0.358) | C1 fail, C2 pass, C3 fail both |
| 5 | −2.3768 | −6.3590 | 49.8644 (1.226) | 49.0105 (0.430) | C1 fail, C2 pass, C3 fail |
| 6 | −2.4445 | −6.5177 | 49.6319 (1.458) | 48.9392 (0.501) | C1 fail, C2 pass, C3 fail |
| 6.5 | −2.4781 | −6.5208 | 49.5135 (1.576) | 48.8961 (0.544) | C1 fail, C2 pass, C3 fail |
| 7 | −2.5123 | −6.6752 | 49.3994 (1.691) | 48.8680 (0.572) | C1 fail, C2 pass, C3 fail |
| 7.25 | −2.5289 | −6.6401 | 49.3391 (1.751) | 48.8426 (0.597) | C1 fail, C2 pass, C3 fail |
| 7.5 | −2.5459 | −6.6799 | 49.2810 (1.809) | 48.8248 (0.615) | C1 fail, C2 pass, C3 fail |
| 7.75 | −2.5628 | −6.7196 | 49.2229 (1.867) | 48.8070 (0.633) | C1 fail, C2 pass, C3 fail |
| 8 | −2.5801 | −6.8356 | 49.1669 (1.923) | 48.7967 (0.643) | C1 fail, C2 pass, C3 fail |

(The 6.5/7.25/7.5/7.75 rows are the 0.25-step refinement; they confirm the
best-family slope to four digits at both edges of the grid — linearity, not
a local fit.)

**C2 held at every candidate, and the Task-2 worry did not materialise.**
The deficit term does not rescue `budget-bad`: its record is *worse* than
idle's (−0.381 vs −0.370) because its Okun cost and growth damage outweigh
the surplus its cuts buy, so the credit falls on it FASTER than on idle
(−0.392/span-unit vs −0.233). Acting badly is punished more the louder the
channel is. The control is not the gate's weak half.

**C3 is the binding constraint and it inverts the design's intent at the
implementation's own site**: the channel was designed to leave idle exactly
where it was, and instead the shared world term drags idle DOWN as the span
rises. The largest span respecting C3 is ~1.01 (measured 0.296 at 1.0,
0.354 at 1.25); **0.0 ships** — the author's call of 2026-09-14: the FAILED
form stays INERT, so every fresh game keeps the pre-V4.0 baseline and the
measured ~0.3-point idle drift and the `ruinous` HELD→LOST flip are NOT
shipped. The sweep table and mechanism stay above as the record; 1.0 was
the C3 bound the sweep would have shipped had the gate passed, and it is
what the re-run of §5e measured.

**The verdict, wired into the probe this session (C2 now gates the verdict
beside C1): FAIL.** No policy family moves month-6 approval positively
against idle at any reachable span, for the mechanism above — a fresh-game
world term dominating the record's policy component at month 6. Per §2's
pre-declared fallback, the **decaying-credit form is the next measurement,
taken knowingly with its version bump, as its own scoped block** (the
handoff's "a miss spawns the next route, never a silent extension"), and the
activity-keyed drag stands behind it. What a later session should carry from
this table: the channel's *form*, not its span, is what missed. A record
term that anchors on the inauguration month inherits whatever the cycle was
doing at inauguration; the decaying form's stock (or a cycle-neutral
baseline for the growth addend) is the class of fix that can pass.

### 5c. Q1 discharged — branch one: the re-fit ships

The isolated path is V1.5a's own (the stock moved via the corruption
register, every spending line untouched, `spending_untouched=true` asserted
per run) with one correction: each candidate constant is **set live** rather
than rescaled from a single run — the INFLATION_SCALE_PP lesson, since
whether a candidate saturates `_scaled()`'s clamp is what the sweep must
find out (none does; the measured deviation is −2.2287 pt of GDP at 60
months, unchanged from V1.5a's table).

| scale | headline (isolated) | band ±3.0 | ratio vs 6.0 |
|---|---|---|---|
| 6.0 | −4.1378 | PASS | 1.0000 |
| 6.25 | −3.8980 | PASS | 1.0417 |
| 6.5 | −3.6808 | PASS | 1.0833 |
| **6.75** | **−3.4832** | **PASS** | **1.1250** |
| 7.0 | −3.3030 | PASS | 1.1667 |
| 7.25 | −3.1381 | PASS | 1.2083 |
| 7.40 | −3.0457 | PASS | 1.2333 |
| 7.45 | −3.0159 | PASS | 1.2417 |
| 7.5 | −2.9867 | fail | 1.2500 |
| 7.75 | −2.8473 | fail | 1.2917 |
| 8.0 | −2.7187 | fail | 1.3333 |
| 9.0 | −2.2913 | fail | 1.5000 |

The band is one-sided-down with the upper crossing at ≈ 7.47 (interpolated:
7.45 passes at −3.016, 7.50 fails at −2.987); the fit rule demands > 6.0.
One note on the grid: §5a pre-declared {6.5, 7.0, 7.5, 8.0, 9.0}, and the
run broadened it to add the 0.25-step refinements at the crossing (6.25,
6.75, 7.25, 7.40, 7.45, 7.75) — midpoint-stability reading, V1.5b's rule.
The interval is (6.0, 7.47) and **6.75 ships** — interior of the crossing,
midpoint-stable at both the 0.5 and the 0.25 grid steps, ratio **1.125**.
Q1's branch one: the V3.0 inversion is repaired, the
delivery-under-announcement rule stands, and the constant's comment in
`opinion_constants.gd` records the table. No test pins the constant; the
V1.5a records in `docs/society-model.md` (c) keep their old table as the
history of the 3.0 spend scale.

### 5d. E1 discharged — the zero price is a measured bound

Recorded in [[orgs-model]]'s deliberately-absent list beside the bullet it
closes: at the eu's own authored magnitude (0.50) the Schengen trade bonus
moves the FRA headline **+0.01** at 60 months; at the loader's own ceiling
(2.50) **+0.03** at 60 and **+0.05** at 168 months; at 5.00, past the bound
and run to prove saturation, **+0.03/+0.04**. The response saturates (the
only consumer is `TRADE_OPENNESS_BETA × d_open` inside `SHIFT_MAX_PCT`'s
clamp, and the settled trend delta at the ceiling is +0.002 points/yr), so
**no reachable magnitude clears the ±3.0 poll-noise floor** — the bound is
~60× short at the ceiling. The euro side has no code channel at all
(inflation.gd, trade.gd and economy.gd read nothing eurozone-shaped), so an
inflation or credit channel would be a build and not a price, and E1 was a
measurement only. The orgs-model trigger is discharged either way; the zero
price is no longer an absence but a measured bound with its number.

### 5e. The re-run, predicted then held (2026-09-14, Task 5)

The balance re-run the sim diff owes: `src/sim/opinion.gd` gained the credit
addend (`COMPETENCE_SPAN` 1.0) and `opinion_constants.gd` moved
`QUALITY_SCALE_PP` 4.5 → 6.75. Merge base `32e0e7e`, head `d752274`, both
sides from worktrees so the per-machine addon parse noise cancels, run
serially, MCP-port line filtered, V1.7c's third-stray-line check applied.
The suite gate ran first on HEAD: 82/82.

**A correction to the handoff's premise, written before the run because the
prediction must follow the mechanism rather than the handoff.** The handoff's
prediction draft said the idle path is bit-identical because "the credit is
zero at fresh-game and for the idle path (every outcome at its start)". The
first half is true and pinned by `tests/test_opinion.gd`; the second is
false twice over, and the committed record already says so:

- **The credit is NOT zero on the idle path.** §5b measured it: the
 fresh-game business cycle moves growth and unemployment off the
 inauguration figures with no policy at all, and idle's record reads
 −0.370 at month 6. The channel prices the WORLD on a fresh game — that
 is §5b's own finding, and it applies to `hands_off` first of all.
- **The quality stock drifts on the idle path.** `QUALITY_KEYS` is
 [health, pensions]; health's dependency elasticity is the deleted 0.0
 (`society_constants`), but pensions' divisor is the live dependency
 factor, which ageing raises on every path including hands_off. The stock
 converges down, the deviation goes negative, and re-pricing it at 6.75
 instead of 4.5 makes it cost LESS. Idle's approval is predicted to RISE
 slowly through the run, not hold still.

**The two channels, named:**

- **(a) Competence credit** (`COMPETENCE_SPAN` 1.0, one addend in the
 per-bloc approval target beside `time_in_office_offset`). Reads
 start-vs-live unemployment, deficit and growth at their existing scales,
 clamped ±1.0 over the net sum. Reaches `appr`, the worst-bloc column and
 `spread` through the target; reaches election `vote`/`seats` lines only
 through `INCUMBENT_SWING`'s pull and the attribution block's satisfaction
 column; reaches nothing else — no economy feedback exists (approval gates
 verb PRECONDITIONS, not the economy).
- **Quality re-fit** (`QUALITY_SCALE_PP` 4.5 → 6.75). Re-prices the
 `health` and `pensions` satisfactions at ratio 1.125 — a DAMPING in both
 directions: a negative deviation costs less, a positive one pays less.
 Reaches approval through the satisfaction dict, and unrest's hardship term
 reads the same dict, so regimes whose unrest actually fires acts see the
 impulse change too — and through `unrest_impulse_pct` that reaches
 `economy.gd:161`'s growth sum, GDP itself.

**The predictions, by family** (a moved line outside these is a DEFECT,
not rounding):

1. **`hands_off`**: `appr`, worst-bloc and `spread` move — early months
 from the credit's cycle term (idle reads NEGATIVE at m6, ~−0.37 record
 units × 1.0 span, inertia-governed), later years back UP from the
 pensions damping as ageing deepens. GDP, growth, unemployment, debt,
 deficit: **bit-identical** — no unrest act ever fires on idle, so the
 unrest→GDP leg stays dead and the credit has no economy reader.
 Election lines: last digits only, every HELD/LOST unchanged.
2. **Every budgeted regime** (all fifty others commit in month 1): `appr`,
 worst-bloc, `spread` move through BOTH channels — the credit from their
 diverging records, the damping from their health/pensions spending moves.
 The quality damping PUNISHES spenders (spendthrift, spend_max, ruinous,
 public_works-side regimes lose a fraction of the quality windfall) and
 SOFTENS cutters (austerity, spend_zero, managed_breaks_* recover a
 fraction of the quality pain) — the fit rule's own intent, delivery
 priced closer to announcement.
3. **Economy lines (`GDP/grow/trend/unemp/debt/defc`)**: bit-identical
 EVERYWHERE except where the damping moves an unrest act across its
 threshold or a strike's timing — the austerity family's unrest lines and
 unrest-act counts are the declared place where real figures may move.
 `managed_corrupts` is doubly exposed (corruption moves delivery, so its
 quality deviation is largest). Everywhere else a moved GDP/unemp digit is
 a DEFECT.
4. **Election and verdict lines**: vote shares and seat counts move at last
 digits through `INCUMBENT_SWING`; **no HELD/LOST flips, no
 COHABITATION/MINORITY label changes, no coalition recompositions** —
 decimal-scale approval movement cannot cross a seat threshold. A flipped
 verdict is a DEFECT.
5. **Verb-path lines** (diplomacy, amendment, referendum, pledge, campaign,
 energy, courts, migration, censorship): unchanged UNLESS an approval-
 or unrest-gated PRECONDITION flips at the verb's month — decimal-scale
 movement, predicted zero flips. `managed_breaks_its_word` /
 `managed_breaks_nothing` additionally carry a health cut, so their
 attribution and appr lines move through the damping channel as well.
6. **Structural**: `invariants: OK` in all 51 regimes, zero outcome
changes, unrest threshold lines unchanged, no new tick call, no
`SAVE_VERSION` move (the credit is derived, the quality change is a
constant — both serialise nothing). [Reviewed 2026-09-14: this clause
read the credit LIVE because the re-run measured span 1.0; the SHIPPED
span is 0.0, so the credit channel is inert and the re-run is
by-construction bit-identical on it — only `QUALITY_SCALE_PP` 4.5→6.75
still moves the quality channel. §5f records the decision.]

#### The re-run result — held, with one prediction miss recorded

Both sides ran from worktrees (base `32e0e7e` at `../nswt-v40-base`, head
`d752274` at `../nswt-v40-head`), serially, after a `--headless --import` on
each (the fresh-clone rule: no `.godot/`, no class cache, no parse). 1681 /
1673 output lines; **no MCP-port line appeared on either side this run** and
the third-stray-line check is clean — both files END on their last
`invariants: OK` line, nothing after it. The suite gate ran first on HEAD:
82/82 in 5:58.

**821 printed line pairs differ, in every one of the 51 regimes.** The shape:

- **`hands_off` exactly as clause 1 predicted.** `appr`, worst-bloc and
 `spread` moved (2027 49.2→48.9 — the credit's inherited-cycle term at m12,
 `grow 0.95 vs trend 1.31` → record ≈ −0.09; later years lifted by the
 pensions damping as ageing deepens); GDP, growth, unemployment, debt,
 deficit **bit-identical**; unrest acts 0→0; election lines last digits
 (22.9 %→22.8 %), verdict LOST→LOST.
- **Approval-side lines moved everywhere** (both channels): `appr` in 51,
 discipline rows in 49 (`Discipline.unpopularity()` reads
 `overall_approval_pct`), election vote/seat figures in 50 through
 `INCUMBENT_SWING`, attribution satisfaction columns in 17, SNAP/campaign
 event lines at the last digit (355→358 seats, +1.567→+1.568 pts).
- **Unrest ACT counts changed in five regimes — the declared place** (clause
 3's austerity/breaks family): `managed_abolishes_the_monarchy` (GBR) 4→3,
 `managed_breaks_its_word` 4→3, `managed_breaks_nothing` 4→3,
 `managed_then_austerity` 1→0, `managed_then_austerity_settles` 1→0. The
 damping softened the health-cut hardship and the suppressed strike's
 timing shifted the real economy in exactly those regimes
 (`managed_breaks_*` 2030: GDP 2907→2908, grow +1.91→+1.89; the
 then_austerity pair 2030: grow +2.13→+2.30). `managed_censors` shows the
 damping's magnitude without acts: peak 8.55→4.66 — a pensions deviation
 drifting toward −0.5 pts of GDP costs ~0.037 more satisfaction at 4.5
 than at 6.75, several index points of grievance over fourteen years.
- **The 0.01 `defc` movers (~25 managed-family regimes, last years only)
 are the unrest STOCK's credit reader**, a leg clause 3 under-specified:
 it named act thresholds but the stock is read at every month by
 `Credit.spread_pct()` (`YIELD_UNREST_BETA` 0.0115), so a ±0.16-point
 stock drift moves debt service ~0.002 pts/yr and crosses a `%.2f` print
 boundary by mid-run. Every such mover is one centesimal deficit digit;
 the arithmetic is the channel's, and it is recorded here as the
 prediction's under-specification rather than as a defect.
- **Verdicts: 49 of 51 unchanged; two flips, and they are not the same
 kind.** `managed_then_austerity_settles` flipped LOST→HELD at 2032-05
 (exit month 2032-05→2037-05) **through the declared channel**: the
 settlement regime's single strike never fired on head (peak 14.62→13.54
 against the 14.0 threshold, acts 1→0), the real economy recovered, and
 the election followed it. Clause 3 declared this regime's unrest lines
 movable; clause 4's "no verdict flips" was too strong wherever clause 3
 fires. **`ruinous` is the re-run's one prediction miss**: HELD→LOST at
 2027-05 with acts 0→0 and no unrest channel at all — the credit's cycle
 term plus the damping moved the knife-edge presidential vote 23.6 %→23.2
 % and the largest-party test flipped. The run then ends five years
 early, which is why base prints five `PROBLEM debt ratio running away`
 lines (a 1020 % debt ratio) where head prints `invariants: OK` — the
 blowout was never reached, not repaired. Per the pre-declared rule this
 is a moved line outside the prediction and is recorded as such: the
 MECHANISM is the two declared channels reaching a threshold the clause
 wrongly called unreachable, not a third channel — but the record's value
is the miss, and the next re-run's verdict clause reads "no verdict flips
EXCEPT at declared-channel threshold crossings AND margins inside the
poll-noise floor" — the `settles` flip was a threshold crossing (clause 3's
declared channel), the `ruinous` flip a floor margin (the 23.6 %→23.2 %
knife-edge vote) — not "none".

**Tally by channel**: credit + damping reached every regime's approval
column; the damping's unrest leg moved five act counts and one suppressed
strike; the stock's credit-yield leg crossed ~25 centesimal deficit
boundaries; two election verdicts changed (one through the declared act
channel, one outside every clause); `invariants: OK` on all 51 head runs.
No `SAVE_VERSION` move, no new tick call, no new regime. Worktrees removed
after the diff was recorded.

### 5f. The span decision — 0.0 ships, the FAILED form stays inert

The author's call of 2026-09-14, recorded at §5b's ship line: the level
form MISSED its gate (C1 unreachable at any span; the form prices the
inherited cycle, not the policy record), so `COMPETENCE_SPAN` ships **0.0**
and the channel is INERT — every fresh game stays on the pre-V4.0 baseline,
and the re-run above's measured ~0.3-point idle drift and `ruinous`
HELD→LOST flip are what 0.0 deliberately does NOT ship (that re-run,
commit 897348d, measured the 1.0 form, so its credit-channel movers are
documentation of the unshipped form, not a balance cost). The
infrastructure — the constant, `competence_credit`, the C2 control, the
test — survives for the decaying-form block (§2's declared next route) to
flip live; that block is its own scoped block with a SAVE_VERSION bump
taken knowingly.

### 5g. The shipped re-run at span 0.0 — predicted before the run (2026-09-14, Task 5b)

The re-run the shipped state owes: §5e's re-run measured the 1.0 form at
commit 897348d, but the review fix then set `COMPETENCE_SPAN` to **0.0**
(§5f's decision), so the shipped state is NOT what 897348d measured and a
re-run at the shipped constants is owed. Merge base `32e0e7e`, head
`910c617`, both sides from worktrees so the per-machine addon parse noise
cancels, run serially, MCP-port line filtered, V1.7c's third-stray-line
check applied. The suite gate ran first on HEAD: 82/82.

**The prediction, written before any run.** At `COMPETENCE_SPAN := 0.0`
the credit contributes exactly zero to every target — the term is
`0.0 * competence_record(ns)` — so every credit-channel mover §5e
recorded VANISHES: the fresh-game cycle drift on `hands_off`'s early
approval, the credit's contribution to every budgeted regime's record,
the credit-driven election last-digits, and the `ruinous` HELD→LOST flip
(the knife-edge 23.6 %→23.2 % vote was the credit's cycle term plus the
damping; with the credit inert the damping alone is predicted too small
to cross — **`ruinous` returns to its merge-base verdict HELD**). The
ONLY live sim change vs merge-base is `QUALITY_SCALE_PP` 4.5 → 6.75, so
the shipped re-run should show ONLY §5e's quality-damping channel:
health/pensions satisfaction re-pricing (a damping — negative deviations
cost less, positive pay less), the unrest hardship legs it feeds (the
five declared strike regimes' act counts), and the downstream
approval/discipline/election digits through those. Economy lines move
ONLY where an unrest act crosses its threshold through the damping.
`hands_off`'s economy lines bit-identical. The §5e finding that the
unrest STOCK is read at every month by `Credit.spread_pct()`
(`YIELD_UNREST_BETA`) still applies — damping-driven stock drift can
still cross centesimal `defc` print boundaries in the managed family.
No new tick call, no `SAVE_VERSION` move. **A moved line outside the
quality channel is a DEFECT.**

#### The shipped re-run result — the prediction held, two damping flips recorded

Both sides ran from worktrees (base `32e0e7e` at `../nswt-v40s-base`, head
`910c617` at `../nswt-v40s-head`), serially, after a `--headless --import`
on each. 1681 / 1681 output lines; no MCP-port line on either side and the
third-stray-line check is clean — both files END on their last
`invariants: OK`, nothing after it. The suite gate ran first on HEAD:
82/82 in 5:56.

**The central prediction held exactly.** The credit channel is gone: the
credit-channel movers §5e recorded do not appear — `hands_off`'s early
approval no longer drifts on the inherited cycle, and **`ruinous` is
bit-identical to merge-base** (both presidential votes 23.6 %/20.3 %,
verdicts HELD/LOST unchanged, acts 0→0). **`hands_off`'s economy columns
(GDP/grow/unemp/debt/defc) are bit-identical** — only `appr`, `spread`,
one election vote digit (22.9 %→22.8 %, LOST→LOST) and its unrest line
(peak 8.07→8.21, a damping re-pricing, no acts) moved. No `SAVE_VERSION`
move, no new tick call.

**819 printed line pairs differ, and every one is the quality-damping
channel** (`QUALITY_SCALE_PP` 4.5 → 6.75) or its downstream, matching the
prediction's families:

- **`appr`/`spread`/year lines moved in 46 of 51 regimes** — the damping
  re-pricing health/pensions on every path (idle included: pensions'
  dependency divisor drifts the stock negative even with no policy).
- **Act counts changed in exactly the five declared regimes**
  (`managed_abolishes_the_monarchy` 4→3, `managed_breaks_its_word` 4→3,
  `managed_breaks_nothing` 4→3, `managed_then_austerity` 1→0,
  `managed_then_austerity_settles` 1→0) — the damping softens the
  health-cut hardship legs.
- **Real-economy movers confine to those five regimes plus
  damping-scale debt/defc digits**: GDP/growth/unemployment move ONLY in
  the act-count regimes (the unrest→GDP leg firing a month earlier or
  later) plus last digits in `spendthrift`/`tinkering`; the ~50
  centesimal `defc` movers across the managed family are the §5e
  unrest-stock credit-yield leg (`Credit.spread_pct()` reads the stock
  every month), predicted in §5g. `hands_off`'s economy: bit-identical.
- **Election digits move broadly (vote shares ±0.1–2.0 pts, seats ±1–7),
  all through damping-driven approval; discipline rows in 39 regimes
  (`overall_approval_pct` reader); salience/satisfaction columns in 16.**

**Verdicts: 49 of 51 unchanged; two flips, both through the damping
channel, of §5e's two kinds.** `managed_then_austerity_settles` flipped
LOST→HELD (2032-05) through the DECLARED act-threshold crossing — its
single strike never fired on head (peak 14.62→13.54 against 14.0, acts
1→0), the real economy recovered and ran to 2037, the election followed
it; this is §5e's same flip, now attributable to the damping alone, so
the shipped state DOES carry it. `managed_dissolves_early` flipped
HELD→LOST (2032-05) with acts 0→0 and no threshold crossed — the
damping moved the knife-edge presidential vote 23.7 %→23.6 % and the
largest-party test flipped; this is §5e's `ruinous` class of floor-margin
flip at a different regime, and per §5e's amended rule ("no verdict flips
EXCEPT at declared-channel threshold crossings AND margins inside the
poll-noise floor") it is recorded rather than treated as a defect: the
MECHANISM is the one declared channel, and the margin is one print
digit. **`ruinous` itself — §5e's miss — did not flip at span 0.0**,
which is the shipped re-run's central result: the credit's cycle term,
not the damping, was what pushed it over in 897348d's run.

**Tally**: damping-only run; credit inert (bit-identical on every line
§5e attributed to it); five act-count movers (all declared); two verdict
flips (one threshold-crossing, one floor-margin, both damping); zero
moved lines outside the quality channel and its downstream; `invariants:
OK` on all 51 head runs. Worktrees removed after the diff was recorded.

## 6. Deliberately absent

- **No per-bloc competence row.** Uniform, §2; a bloc-differentiated credit
  is an authored table with no measurement behind it.
- **No regional or coalition credit.** The channel prices the national
  record. A coalition partner's patience with a competent government is
  [[cabinet-model]]'s and the legislature's business, not this term's.
- **No AI-facing behaviour.** The nine AI nations have no reader for
  approval at all — `Opinion._tick_nation` is gated on `has_budget` +
  `in_government` for the player's sake; the credit changes nothing they do.
- **No `SAVE_VERSION` move.** The credit is derived from fields the save
  already carries (`start_unemployment_pct`, `start_deficit_pct_gdp`, the
  live figures, `trend_annual_pct`); nothing is stored. The refused forms
  are the ones that would have cost the bump, and §2 records that as part of
  why they were refused.

---

Related: [[opinion-model]] · [[tiers/v4]] · [[unrest-model]] · [[orgs-model]] · [[cabinet-model]] · [[campaign-model]] · [[decision-log]]
