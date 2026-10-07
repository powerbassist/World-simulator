---
title: Inflation Model
tags:
  - decision
  - economy
  - simulation
---

# Inflation Model

Inflation, as built at V1.6b — the second session of the V1.6 block. A
per-nation price level as a stock, driven by the unemployment gap, charging two
prices. Every formula, every constant, and the argument for why three of the five
constants were never swept.

`src/sim/inflation.gd` is the model, `src/sim/inflation_constants.gd` is the values,
`tools/inflation_probe.gd` is the evidence, and `tests/test_inflation.gd` is what
stops a later session quietly breaking the design.

## 1. The boundary, decided before any code

**Everything in this project is in constant prices and every rate is real, so there
is nothing for inflation to deflate.** [[economy-model]] says so in its first
section, and the choice to express every budget line as a percent of GDP was made
precisely so the MVP would need no indexation rule.

**No nominal layer.** It would touch every measured constant in the project —
`TAX_BASE_SHARE`, every `SECTOR_TREND`, `DEBT_REAL_RATE_PCT`, every S10 opinion
scale, every balance figure ever quoted — in exchange for a number the player already
reads as real. Four nominal channels were considered and cut, recorded so a later
session does not re-propose them:

| Candidate | Why cut |
|---|---|
| Real-income erosion on households | Requires a nominal wage the model does not have |
| Inflation eroding the real debt stock | `debt_eur_bn` is already a real figure |
| VAT as a direct price-level shock | A level, not a rate — and it makes a tax slider write inflation which prices back to the voter through a loop with no lag in it |
| Indexing the spending lines | They are shares of GDP and already auto-scale |

What inflation *does* reach is **relative-price distortion and uncertainty**, which
is a real cost needing no nominal quantity. That is §4.

`tests/test_inflation.gd` checks the boundary rather than stating it: it walks
`src/sim/` and fails if any file outside `inflation.gd` reads the raw stock.

## 2. The row was wrong, and the data is what said so

[[v1]] §6's row: *"a price pressure from the gap, the impulse and (a)'s shock."*

**Two things are wrong with it, and only the first was visible without measuring.**

The three named inputs are **one quantity written three times**. The output gap is
the accumulated integral of the growth addends — `economy.gd` sums eight of them into
growth, and `growth − trend` is what closes the gap at `GAP_CLOSE`. A target reading
the gap *and* the impulses that fill it double-counts, which is [[coercion-model|
V1.3c]]'s `tariff_rate_pct` error and [[companies-model|V1.4a]]'s flat rival floor.

**Then the measurement refuted the surviving input as well.** Regressed on
`FP.CPI.TOTL.ZG` against a gap built the way the model builds one — the running sum
of (growth − own-mean growth), per nation, demeaned — all ten nations, 1990–2024:

| Window | π ~ output gap | π ~ unemployment gap |
|---|---|---|
| 1990–1998 pre-euro | +0.156, r **+0.204** | 0.376, r **−0.383** |
| 1999–2024 euro era | +0.048, r **+0.098** | 0.252, r **−0.339** |
| 1990–2024 pooled | −0.053, r **−0.140** | 0.148, r −0.207 |

> The output gap's sign **flips between sub-samples** and its correlation never
> leaves the noise. The unemployment gap carries a stable, correctly-signed Phillips
> relation in both disjoint halves.

So the model reads **unemployment**, which is [[economy-model]]'s own treatment of
Okun's law — *the honest textbook relationship rather than a bespoke one* — and it
dissolves the double count rather than patching it, because `unemployment_pct −
structural_unemployment_pct` is **one existing quantity** that already carries the
cycle, the demand impulse and every other shock.

Twenty-ninth stale-row instance. The row also names a *price* and never says what it
is — its only named price is the `ISSUE_KEYS` question, which is a surface question —
so §6's own block rule was load-bearing on an answer the row left open. Thirtieth.

## 3. The generator

```
gap_u   = structural_unemployment_pct − unemployment_pct
target  = inflation_anchor_pct + INFLATION_UNEMP_BETA × gap_u
π      += (target − π) × INFLATION_CONVERGENCE
```

`quality_step()` / `capability_step()`'s first-order lag, **third use** — defence at
V1.3g, society at V1.5a, here — so no new machine shape is invented. Including their
call that a starting stock is its **equilibrium and not zero**.

**Exactly 0.0 at new game for all ten.** `unemployment_pct ==
structural_unemployment_pct`, so the gap is zero, the target is the anchor, and the
stock is seeded there. Both prices read exactly 0.0 before anything happens, asserted
with exact equality rather than `is_zero_approx()`.

**That seed is load-bearing for two existing tests**, which is worth stating because
it looks like tidiness: `tests/test_opinion.gd` requires every issue's satisfaction
under 1e-9 at new game, and `tests/test_state_copy.gd` only catches a field missing
from `duplicate_state()` when its value is **non-zero**.

`structural_unemployment_pct` rather than `start_unemployment_pct` buys a consequence
nobody authored: raising income tax lifts the structural rate through
`STRUCT_INCOME_BETA`'s labour-tax wedge, which widens the gap and is therefore mildly
**inflationary**. The wage-push story, out of two existing constants.

### Three constants measured, two swept

| Constant | How it was set | Value |
|---|---|---|
| `inflation_anchor_pct` | **Measured**, per nation, mean 1990–2024 | CHE **1.117** → ESP **2.903** |
| `INFLATION_CONVERGENCE` | **Measured**, AR(1) ρ = 0.5232, converted exactly | **0.0526**/month |
| `INFLATION_UNEMP_BETA` | **Measured**, euro-era slope | **0.25** |
| `INFLATION_SCALE_PP` | **Swept**, two-sided band → midpoint | **0.275** |
| `INFLATION_OUTPUT_BETA` | **Swept**, band failed → recorded | **0.30** |

The anchors span 2.6× and do not cluster, which is the
[[foreign-policy-model|clustered `coalition_position`]] risk this kind of content
always runs.

**The persistence is converted exactly rather than approximately.** The series gives
an *annual* AR(1) coefficient; the monthly rate that reproduces it is the twelfth
root, `1 − 0.5232^(1/12) = 0.052551`. A linear `ρ/12` would have been 0.0436 and made
the model 20 % stickier than the data.

**The euro-era slope ships, and the selection rule is the model's own premise.**
[[out-of-scope-mvp]] records that France does not set its own interest rate and
[[mechanics-economy]] tiers the central bank *Someday* — so this game's nations have
no monetary autonomy, which is exactly what 1999–2024 measures and exactly what
pre-euro does not. Shipping 0.376 would calibrate on an independence the game does
not give the player. The **pooled** figure is the weakest of the three and would have
been the wrong one to ship on the use-all-the-data instinct.

**It reuses V1.6a's window but is still a real extra download** — one file per
indicator code — so [[data-sources]] gains a second `date=1990:2024` line. V1.5b's
"no extra download" does not transfer, and the plan's first draft claimed it did.

**The exclusion list is empty and that is an editorial act.** V1.6a drops 2020–21
because a pandemic is an exogenous *output* shock in a series measuring output; the
2022–23 energy spike is a *price* shock in a series measuring prices, which is the
thing the indicator exists to record. `"_excludes": []` is written into every nation
file rather than omitted, because a provenance record that hides its own editorial
act is worse than none. Keeping it costs what it should: Spain 2.90 against 2.62.

## 4. Price one — the real channel

```
inflation_impulse_pct = −INFLATION_OUTPUT_BETA × max(0, π − anchor)
```

The eighth addend in `economy.gd`'s growth sum. The standard **cost of inflation** —
relative-price distortion and uncertainty depressing output — which is a real effect
needing no nominal quantity, so §1's boundary survives.

**One-sided above the anchor, and the one-sidedness is forced rather than chosen.**
The two-sided form is the better economics and it is **unstable on its lower branch**:
below the anchor a negative impulse raises unemployment, which lowers inflation
further, which enlarges the cost. A deflation spiral, and the only self-amplifying
path this model would contain. A deflation trap is a **nominal** phenomenon — it
needs a zero lower bound on a nominal rate — so the same boundary that cuts the
nominal layer cuts the lower branch.

**Above the anchor the loop is negative feedback and the gain is analytic**, which is
`max_impulse_pct()`'s idiom — derived rather than chosen:

```
u − u* = OKUN × G × Δπ / UNEMP_REVERT = 1.143 × G × Δπ
loop gain = INFLATION_UNEMP_BETA × 1.143 × G = 0.286 × G
```

Stable for `G < 3.5`. Shipped gain **0.0857 against 1.0**, and the slack is reported
the way [[defence-model]]'s and [[companies-model]]'s clamps are.

## 5. Price two — the thirteenth issue

```
sat["inflation"] = clamp(−(π − start_inflation_pct) / INFLATION_SCALE_PP, −1, 1)
```

Signed delta against the nation's own start, the idiom every one of the twelve
existing issues uses. It gets the politics right for free: a president who inherits
5 % and delivers 2 % is **rewarded**.

The two prices take **different shapes** — the real channel one-sided against the
anchor, the opinion price signed against the start — and each is argued separately.
Not a forbidden double count: `law.gd`'s criterion is *same act, same landing site
**and** same units*, and these share none of the three. [[coercion-model]]'s one
verb, two prices.

**This is the first pair of issues in the model that one event moves in opposite
directions.** A boom is a plus on `growth` and a minus here.

## 6. The `ISSUE_KEYS` question, answered YES for the first time

Deferred by V1.3d, V1.4a–c, V1.5a, V1.5c and V1.5d. `opinion_constants.gd` records
five NOs; this is the sixth entry and the first yes.

| Test | Verdict |
|---|---|
| 1. Not nameable otherwise | **Pass, more strongly than europe's.** Every previous no had an authored `bloc_offset` to fall back on. Inflation ships **no verb and no content object**, so there is no authored row anywhere it could hang on. |
| 3. Can become more salient | **Pass — the discriminator.** `SALIENCE_GAIN`'s whole justification is that bad news crowds out the agenda, and inflation is the canonical issue that becomes the only issue. A load never enters `salience_weights()` at all. |
| 5. Does a prior refusal share 1 and 3? | **No.** Unrest's price is a load because a grievance number is already its own salience; ownership and corruption both had a `bloc_offset`. |
| 4. Not collinear | **Pass, measured as a FIT.** |
| 2. Clears the model's resolution | **Pass** at the shipped scale. |

**Test 4 is measured against the model's own accepted standard rather than a band**,
which is V1.6a's lesson: a band edge moves under widening, a comparison does not.

```
|corr(sat.inflation, sat.growth)| = 0.2276
|corr(sat.jobs,      sat.growth)| = 0.3185   <- already accepted as distinct
|corr(sat.inflation, sat.jobs)|   = 0.6683
```

Less entangled with `growth` than a pair the model already carries. Two things save
it: the **lag** (a 12.8-month half-life, so this prices where unemployment was a year
ago) and the **opposite sign**. That is not a re-split of one weight, which is what
killed `corruption`; it is a trade-off.

**The S10 ratio drift is +0.75 %, in the safe direction**, against V1.3d's accepted
+0.39 % and V1.4c's refused −1.46 %. The prediction was written before the table was
computed and held for the reason it named — ownership leaned on `business`, which
carries `public_finances` at 0.34, where inflation's row is heaviest on `pensioners`
and lightest on business. **A control confirms the mechanism**: the same key at a flat
0.11 across all six blocs drifts −0.059 %, so the drift is the profile and not the
thirteenth key as such.

## 7. The legibility floor, in a second place

`tools/inflation_probe.gd` table (a) runs **first**, and nothing is swept until it
has been read — sweeping a price against a floor the channel cannot reach is
`society_probe.gd` table (c)'s error, now recurred in four consecutive sessions.

**The reachable inflation deviation is 0.145 points.** `INFLATION_UNEMP_BETA` is a
measured 0.25, a reachable unemployment gap is about one point, and the 12.8-month lag
means the stock never catches a target that is itself decaying.

That is enough for the **opinion** price and not for the **real** one.

> Band (iii) — the growth channel must move GDP by more than 0.25 % over a term —
> **fails at every honest candidate.** Clearing it needs `G ≥ 2.0`: one point of
> inflation costing two points of annual growth, more per point than V1.6a's whole
> business cycle, and not a number about the world.

**The band's own prescription — ship it visible or delete it — is refused in both
halves, for different reasons.** Not raised, because tuning a measured slope's
consequence until it is visible is what [[demography-model|V1.5b]] refused for
`DEPENDENCY_ELASTICITY["health"]` and [[cycle-model|V1.6a]] refused for
`CYCLE_AMPLITUDE_PCT`. Not deleted, because unlike U6a's day budget this term is
**structural rather than decorative**: it is the only thing making the loop negative
feedback, and without it the statistic reaches the economy not at all.

**What is honestly true: on the GDP axis this channel is below the readable floor**
— 0.049 % of GDP over a term. The player feels inflation through the thirteenth
issue, not through output. [[defence-model]]'s unliftable deployment, recorded rather
than traded against.

The asymmetry underneath is worth naming: the **largest reachable deviation is
deflationary** (−0.140 under a contractionary budget against +0.134 under an
expansionary one), and the cost is one-sided above the anchor, so it never fires on
the biggest movement the player can cause.

## 8. The probe corrected itself twice, sixteen sessions running

**The isolated path double-ticked Opinion.** The first version displaced the stock
after the tick sequence and then called `Opinion.tick_month()` again, so opinion ran
twice a month and the response carried an inertia nobody chose.

**The table that chose `INFLATION_SCALE_PP` was not independent of it.** The probe
cannot change a `const` at runtime, so the first version measured the headline at the
shipped scale and rescaled linearly. Approval is not linear in satisfaction —
`SALIENCE_GAIN` amplifies bad news — and, worse, the rescale was anchored on the
shipped value, so **the passing interval moved when the shipped constant moved**.
V1.5b's *the range was choosing the constant* in a new costume, and it was caught only
by setting the constant once and re-running. The fix is exact rather than
extrapolated: emulate a candidate by displacing the stock to whatever produces the
**same satisfaction**. Verified — changing the shipped value now moves the table by
less than 0.003.

**A declared band was too weak.** Band (ii) asked that the issue not saturate at
*half* the reachable deviation, which 0.10 passes while saturating at the full one —
admitting the exact `DEFICIT_SCALE_PP` failure it was written to prevent. The binding
form is saturation at the peak. Interval [0.15, 0.40], stable under refinement,
midpoint **0.275**.

**Table (e) is not the units check it was designed as, and that is recorded rather
than quietly dropped.** The realised-sd cross-check compares the model's inflation
volatility with the measured one: FRA 0.040 against 1.14. The model is far quieter and
*should* be — this harness has no oil shock, no reunification and no 2022 energy
spike, all of which are [[v1]] §8's. So it does not discriminate, and the real units
check is the twelfth-root identity in `INFLATION_CONVERGENCE`'s comment plus
`tests/test_inflation.gd`'s assertion that one month closes exactly that fraction.

## 9. `SAVE_VERSION` 19 → 20, on three fields of four

A first on this list — V1.6a earned it on one of two, V1.5c on two of seven — and the
three fail the rule by **three different failures**, which is why
`tests/test_save_load.gd` asserts them separately. A single combined check would let
any one of three be quietly wrong.

- `inflation_pct` — absent reads 0.0, a country of permanently stable prices, and
  re-deriving on load cannot rescue it because the accumulation **is** the state.
  `service_quality` at V1.5a, `unrest_pct` at V1.5c.
- `inflation_anchor_pct` — content-derived, and `from_dict()` rebuilds from the
  dictionary alone and never sees the loader. Absent, every nation's target collapses
  toward zero and the growth channel bills a deflation the nation never had: a
  reloaded game running a *different model*. `cycle_amplitude_rel` at V1.6a.
- `start_inflation_pct` — absent reads 0.0 against a live ~1.8, so the issue is not
  missing but **pinned at the floor** from the first month. `start_bloc_burden` at
  V1.3d.
- `inflation_impulse_pct` earns nothing and is serialised anyway.
  `coercion_impulse_pct`'s case.

**The choice of a real channel is what makes all three load-bearing.** Under
opinion-only, an absent anchor would have been silent rather than a standing charge.

The test then pins what was **not** added — no stored expectation series, no month
counter, no accumulated wave — so a later session making the module stateful turns it
red and has to come and say why.

## 10. The re-baseline

**Predicted before it ran: not bit-identical, in every regime.** The channel is
non-zero for all ten nations from month 2 — inflation is exactly 0.0 at the epoch, but
V1.6a's cycle moves unemployment immediately.

**Result: 0 of 29 regimes bit-identical, 1 outcome change of 47.**

| | |
|---|---|
| Economic movers (GDP…deficit) | **23** |
| Approval-only movers | **6** |
| Largest approval move | 8.00 points |
| Outcome changes | **1** — `ruinous` 2027, 23.0 LOST → 23.4 HELD |
| New regimes needed | **0** |

**The six approval-only movers are exactly the contractionary regimes**, and that is
the one-sided cost visible in the harness rather than a coincidence: `austerity`,
`tax_zero`, `spend_zero`, `ruinous` and two austerity variants all push unemployment
*up*, so inflation falls below the anchor, so the growth channel never fires and only
the opinion price moves.

The one outcome change is the same mechanism read politically: a ruinous budget wrecks
the economy, unemployment rises, prices fall, and the voter rewards the disinflation.
It is a one-election flip on a marginal share — **`ruinous` still loses in 2032 at
21.9 %**, and `tests/test_balance.gd`'s own `_check_a_ruinous_budget_loses()` passes.

**No thirtieth regime was needed**, which V1.6a also found: inflation is not a verb,
so there is nothing for a regime to issue.

## 11. The readout, and the eleventh screenshot pass

One line on the economy panel's LABOUR column, under the unemployment rows the
Phillips curve reads — the panel reads in the order the model computes in, which is
what makes the relationship legible without a sentence of explanation. A fact about
the **country**, which is [[demography-model|V1.5b]]'s own split.

**Never silent**, which is the dependency ratio's rule and not the delivery lines':
every nation has an inflation rate from the first frame, so a line that appeared only
once it moved would hide the level the deviation is measured against.

**The pass earned its keep for the eleventh session running, and both bugs were the
readout's own.** The line printed `+0.0 since the start` against a live, correct,
moved figure:

- **The format was copied from the neighbouring row.** The dependency ratio's `%+.1f`
  can express exactly two values of a quantity whose whole reachable range is 0.145
  points. Two decimals on the deviation, one on the level.
- **The flag ticked past the thing it exists to photograph.** `--inflate` ran 48
  months; the demand impulse has a 6.6-month half-life and is spent after three years,
  so unemployment was back at structural and inflation had converged back to the
  anchor. 18 months.

It now reads *"Inflation 1.8%, +0.08 since the start"* under an unemployment rate of
6.5 % against a 7.2 % structural floor.

## 12. What is deliberately not built

- **No monetary policy, and no verb at all.** [[mechanics-economy]] tiers the central
  bank, interest rates and quantitative easing *Someday*. The player fights inflation
  fiscally or not at all — [[unrest-model|V1.5]]'s inverted rule, in a block that also
  contains verbs.
- **No `PRECONDITION_FIELDS` entry.** The session ships no verb, so there is nothing
  to gate.
- **No `trends.gd` `WATCHED` entry.** A 0.145-point reachable deviation never wins the
  "what's moving" column at any honest scale, so it would be a permanently-losing row
  and would re-order `NOTABLE_SEVERITY` on every existing screen.
- **No inflation expectations as a second stock.** The anchor *is* the expectation,
  and a second one would need its own band with no reader until V1.6c.

---

Related: [[index]] · [[economy-model]] · [[cycle-model]] · [[opinion-model]] · [[unrest-model]] · [[decision-log]] · [[v1]]
