---
title: Cycle Model
tags:
  - decision
  - economy
  - simulation
---

# Cycle Model

The business cycle, as built at V1.6a — the first session of the V1.6
block. Every formula, every constant, and the argument for why the two constants
are *measured and fitted* rather than swept.

`src/sim/cycle.gd` is the model, `src/sim/cycle_constants.gd` is the values,
`tools/cycle_probe.gd` is the evidence, and `tests/test_cycle.gd` is what stops a
later session quietly breaking the design.

## 1. What the row asked for, and what it collides with

[[v1]] §6: *"Business cycle — booms and recessions arriving whether or not
deserved."*

[[economy-model]] forbids the obvious implementation outright:

> No randomness anywhere in this model. Determinism is what makes the budget
> projection exactly equal to what subsequently happens, which is a done-when
> condition.

`Budget.project()` runs the real model on `duplicate_state()`, and
`tests/test_budget.gd` asserts the projection equals what follows to 1e-9. A
`randf()` anywhere in `src/sim/` ends that.

**The resolution was already in the repo, on the other side of the same problem.**
`src/ui/poll_noise.gd` needed unpredictable-looking polling error with no RNG state
to serialise, and solved it with a *pure function of (poll id, key)*. §6's cycle
takes the same idiom into `src/sim/`.

**And the property the row actually asks for is ATTRIBUTION, not surprise.** A
recession you did not cause, that you are judged on anyway, is the mechanic. That
survives a cycle the player can see coming — see §5, where it turns out to be the
whole shape of the session.

## 2. The generator

Stateless. `Cycle.impulse_pct(ns, year, month)` is a function of its arguments and
nothing else; there is no `tick_month()`, no accumulator, and nothing serialised
except the content it reads.

```
t          = absolute_month(year, month) − absolute_month(CYCLE_EPOCH)

wave(seed) = ( Σ_k  s_k · sin(2π · t / P_k) ) / sqrt(K / 2)
             P_k = lo_k + u(seed, 2k)·(hi_k − lo_k)     from CYCLE_PERIOD_BANDS
             s_k = ±1                                    from u(seed, 2k+1)

impulse    = CYCLE_AMPLITUDE_PCT × amplitude_rel
             × ( sqrt(S)·wave("__common") + sqrt(1−S)·wave(nation_id) )
```

`u()` is splitmix32 over an FNV-1a of the seed string — `poll_noise.gd`'s hash with
the arguments the other way round, **deliberately duplicated rather than shared**:
that file's header states as an architectural claim that nothing in `src/sim/`
references it, and a preload would make the sentence false while changing no
behaviour. One is a render-time device that must never touch the model; the other
is model state.

Four properties fall out of the form rather than being arranged:

- **Exactly 0.0 at the epoch, for all ten.** Every term is `sin(·)` with no phase
  offset, so `t = 0` is exactly zero. This matters for the *content*, not for a
  re-run: `imported.unemployment_pct` and `SECTOR_TREND` describe a nation at
  potential, and a cycle that started mid-slump would contradict its own data file
  on the opening month.
- **They diverge immediately anyway**, because `s_k` is drawn per nation. A shared
  zero phase with no signs would put all ten into the same opening upswing.
- **Zero mean and no trend.** Each sine has zero mean, so the cycle moves output
  around potential and never moves potential. Compare `potential_shift_pct`, which
  is the only term allowed to feed back into trend and is clamped at ±1.0 for
  exactly that reason.
- **Bounded by construction** at `K / sqrt(K/2)` × amplitude — 2.449 for three
  terms — so it needs no tuned clamp where coercion, companies and unrest each
  carry one. `cycle_constants.max_impulse_pct()` is a function of the term count,
  which is a number nobody can set wrong.

### The epoch is a constant, and that is a harness fact

[[decision-log]]'s V1.5c entry records that `tools/balance_probe.gd` and
`tests/test_balance.gd` both set `state.year` **after** `GameState.new_game()`, so
anything captured at init reads year 0 and every derived elapsed time is wrong by
two millennia. That killed V1.5c's own stateless `inequality_deviation()`.

An epoch has nothing to capture, so it survives the harness where a captured
baseline does not — and it says something true as well as convenient: **the cycle
is a property of the world, not of the save.** `src/core/clock.gd` starts every
game at 2026-01 and no scenario moves it, so the epoch coincides with the start and
a later start date would begin mid-cycle, which is correct rather than a bound.

## 3. The two constants, and why neither was swept

| Constant | Value | How it was set |
|---|---|---|
| `CYCLE_AMPLITUDE_PCT` | **1.70** | Fitted to France's measured growth volatility |
| `CYCLE_COMMON_SHARE` | **0.62** | Measured off the same series, two ways |
| `CYCLE_PERIOD_BANDS` | 29–47, 59–83, 97–131 months | Set by argument, and the file says so |
| `amplitude_rel` | 0.689 (FRA) – 1.475 (LUX) | Per-nation content, imported |

### The spread is measured, and it is the third session running to find a dataset

`NY.GDP.MKTP.KD.ZG`, all ten nations, on the loop `tools/import_data.py` already
runs. [[demography-model|V1.5b]] found the age structure the row said did not exist
and [[unrest-model|V1.5c]] found the Gini; this is the third.

**But it cost more than either of those**, and the cost is the interesting half.
V1.5b's ageing slope was "one extra read of a series already on disk and no extra
download". This needs a **different window** — 1990–2024 rather than 2015–2024 —
because measuring how volatile a country's growth is takes several cycles, and the
existing window contains one.

**The exclusion is the block's one editorial act and it is load-bearing.** On the
window the rest of the file uses, France's growth standard deviation is **3.333**,
and **0.579** with 2020 and 2021 removed — a factor of **5.8**. A session that had
reused the existing window would have shipped a business cycle whose entire
amplitude was one pandemic, and it would have looked measured. A pandemic is an
exogenous disaster, which is [[v1]] §8's; a business cycle is §6's. **2008–09 is
not excluded**, because a financial crisis *is* a business cycle.

The result does not cluster, which is the [[foreign-policy-model|clustered
`coalition_position`]] risk this kind of content always runs:

| | growth sd | amplitude_rel |
|---|---|---|
| FRA | 1.262 | **0.689** |
| BEL | 1.335 | 0.728 |
| AUT | 1.664 | 0.908 |
| CHE | 1.677 | 0.915 |
| ITA | 1.816 | 0.991 |
| NLD | 1.837 | 1.002 |
| GBR | 1.848 | 1.008 |
| DEU | 1.984 | 1.083 |
| ESP | 2.201 | 1.201 |
| LUX | 2.704 | **1.475** |

A 2.14× spread, and the ordering holds across five different windows — it is a fact
about the countries rather than about the window.

### `CYCLE_COMMON_SHARE` was going to be swept, and the sweep was deleted

The design pass had it as the session's second swept constant with a two-sided band.
It does not need one: the series that supplies `amplitude_rel` also says what the
common share **is**. Demean the ten and take the cross-nation mean as the common
factor:

```
var(common factor) / mean var(nation)  =  0.6187      over 33 years
mean pairwise correlation              =  0.6328      same ten series
```

Two different statistics of one dataset, agreeing to 0.014. That is
[[unrest-model|V1.5c]]'s two-harness rule applied to a measurement rather than to a
probe, and it is why the number is 0.62 rather than something a band produced.
`python tools/import_data.py` prints both.

The blend uses **variance shares** — `sqrt(S)` and `sqrt(1−S)` — so the total
standard deviation is exactly `CYCLE_AMPLITUDE_PCT` at every value of S. Plain
weights would shrink the total by up to 30 % in the middle of the range and make the
share a second amplitude control, which is the three-way weight table
[[bloc-model]]'s rule severities warn about, in miniature.

## 4. It runs for all ten, and that is what makes the trade channel live

`Economy.tick_month()` computes `external_impulse` only for `has_budget` nations, so
the nine's cycles reach the player through [[trade-model|V1.3b]]'s directed weight
while the player's never reaches them. The path stays one hop and that document's
deferral of the coupled common mode is untouched.

**The trade channel becomes non-trivially alive for the first time.** Its
quiet-state residual has been about 0.008 since V1.3b — partners drifting off their
own baselines as sector shares move. It now reaches **0.807** against France's own
peak cycle impulse of 1.727, a ratio of **0.467**.

That ratio is economically the right shape rather than a number to worry about:
France has the *lowest* `amplitude_rel` of the ten and imports from partners
averaging 1.0, so a quiet economy among louder ones takes nearly half its cycle from
abroad.

## 5. The measurement that decides the session: a legibility floor that cannot be met

`tools/cycle_probe.gd` table (a), on a grid refined to 0.05 and widened to 4.00:

| amplitude | workers row | headline | realised growth sd | band (i) | band (ii) |
|---|---|---|---|---|---|
| 1.50 | 2.317 | 2.142 | 1.112 | fail | PASS |
| 1.65 | 2.686 | 2.474 | 1.223 | fail | PASS |
| **1.70** | **2.814** | **2.589** | **1.260** | fail | PASS |
| 1.75 | 2.944 | 2.707 | 1.298 | fail | FAIL |
| 1.85 | 3.211 | 2.947 | 1.372 | PASS | FAIL |
| 2.00 | 3.628 | 3.321 | 1.483 | PASS | FAIL |

Band (i) is *the cycle moves approval past the ±3.0 poll-noise floor*. Band (ii) is
*the model's realised annual-growth standard deviation does not exceed France's
measured 1.262*. **They have no overlap at any candidate.**

> **At France's own measured growth volatility, a business cycle moves approval by
> about 2.8 points — under the ±3.0 floor — and it cannot be lifted over it without
> making France more volatile than France is.**

This is recorded rather than traded against, which is [[defence-model]]'s treatment
of the deployment that could not clear its own floor. Two things make it the right
way round rather than a defeat:

1. **The floor is about the wrong panel.** `poll_noise.gd` fuzzes *approval* because
   a poll is a published figure. Growth, GDP and unemployment carry no noise at all
   — the economy panel and the top bar print them exactly. The cycle's primary
   readout is exact and only its secondary one is fuzzy.
2. **It is the mechanic.** §6 asks for recessions arriving whether or not deserved,
   and §1 of this document says the essential property is attribution. A slump that
   is unmistakable in the figures and ambiguous in the polls is exactly a president
   who cannot prove it was not their fault.

So the constant is **fitted**: the candidate whose realised growth sd is nearest
France's measured one. At 1.70 the model returns **1.260** against **1.262**, a miss
of 0.0015. Interior to the grid with candidates failing on both sides, and — unlike
a band edge — a fit **converges** under refinement instead of moving, which is what
[[decision-log]]'s widening and refinement diagnostics are both really asking for.

## 6. The forecast band

A projection is exact and a forecast is not, and `src/ui/budget_panel.gd` prints the
second while the model computes the first.

Printing the projection to two decimals would hand the player a perfect two-year
forecast of the recession they are supposed to be judged on not having prevented —
§6's mechanic thrown away at the last surface. `poll_noise.gd`'s reasoning transfers
word for word: a government growth forecast is a published figure in the same sense
an approval poll is.

Three departures from that file, each argued:

- **A range, not a nudged point.** A nudge invents an error whose sign the model has
  no basis for; a band states the uncertainty and contains the truth. It also costs
  no hash — the half-width is derived, so there is nothing to keep stable across
  repaints and nothing to serialise, which are the two properties `poll_noise.gd`
  needed its hash for.
- **The half-width is one standard deviation of the cycle's own contribution**,
  `CYCLE_AMPLITUDE_PCT × amplitude_rel`. Derived, so a quieter country gets a tighter
  band with no second number to tune.
- **The same band on both columns.** The panel's job is now-against-proposed, so an
  independent error on each side would fuzz the comparison the player is actually
  making. One band keeps the *difference* exact and the *level* honest — which is
  also true of real forecasters, whose bias moves both scenarios together.

## 7. Three bugs, and all three were harnesses rather than the model

**`Budget.project()` never advanced the clock.** It ran its twelve ticks at one
date, for eleven sessions, and nothing noticed because nothing in it computed a
figure from the date — `bloc.gd`, `defence.gd` and `cabinet.gd` read `state.year`
only to stamp a record, and `calendar.gd`, which genuinely reads it, is not run
there. The cycle is the first thing in the projection that is a function of the
month. `tests/test_cycle.gd` caught it on its first run: month 1 projected −0.903
and delivered −0.690. This is [[media-model|V1.5d]]'s finding one layer down.

**`tests/test_budget.gd`'s own runner froze the clock too** — which is why the two
agreed to 1e-9 while both were wrong. Fixed on both sides, so the agreement now
means what it says.

**`tests/test_trade.gd` measured a partner recession against zero.** Until the cycle
existed, every partner sat at its baseline forever, so any non-zero impulse *was*
the injected recession. Now all nine move constantly and eight in a mild upswing
outweigh one in a 3-point slump: the raw figure came back **+0.039**. Re-measured
against a control, which is an idiom V1.3b already wrote four functions further down
the same file. Its order-independence check also read the weight table *after* the
tick when the impulse was computed from the table *before* it — an error of 4 parts
in ten thousand while partners were still, ten times that once they move.

## 8. The re-baseline

**Predicted before it ran: not bit-identical, in every regime, from month 1.** Every
channel since V1.3d read exactly 0.0 until a player command fired; this one is
non-zero for all ten nations with nobody having done anything.

That prediction is written down because [[media-model|V1.5d]] predicted a difference,
got a zero-line diff, and the *wrong prediction* is what found that neither balance
harness had ever called `Media.tick_month()`. A bit-identical re-run is the
reassuring outcome, so nothing about it invites suspicion.

**Result: all 29 regimes differ. Zero outcome changes.** No presidential verdict
flipped and no government fell that did not fall before.

| | largest movement, 29 regimes × 14 years |
|---|---|
| GDP | 3.32 % |
| growth | 2.74 points |
| unemployment | 1.26 points |
| debt / GDP | 3.30 points |
| deficit | **0.07 points** |
| approval | 7.60 points |

The deficit barely moves because every budget line is a share of GDP, so the books
scale with the economy — which is [[economy-model]]'s own reason for that choice,
visible for the first time.

**No thirtieth regime was needed**, and that is a first for a session that changes
the economy: the cycle is not a verb, so there is nothing for a regime to issue.

## 9. `SAVE_VERSION` 18 → 19, on one field of two

**The plan predicted no bump and gave a reason that was true about the wrong thing.**
It reasoned that a stateless system has nothing to serialise, and `src/sim/cycle.gd`
genuinely stores nothing. But `NationState.from_dict()` rebuilds from the dictionary
**alone** and never sees the loader, so every content-derived static fact on that
class is already serialised: `eu_member`, `neighbours`, `pop_growth_pct`,
`gini_index_per_yr`.

> **Statelessness is a property of the module, not of the save file.**

- `cycle_amplitude_rel` **is** the bump. Absent it reads the default 1.0, every
  nation runs the roster-average cycle instead of its own — France 45 % louder than
  its content says — and the reloaded game runs a *different model* from the one that
  saved it. `eu_member` at V1.3b and `military_capability` at V1.3g.
- `cycle_impulse_pct` earns nothing: absent it reads 0.0 and `Economy.tick_month()`
  overwrites it from the clock on the next tick. `coercion_impulse_pct`'s case.

`tests/test_save_load.gd` asserts both halves and then pins what was *not* added —
no stored phase, no month counter, no accumulated wave — so a later session that
makes the module stateful turns it red and has to come and say why.

## 10. Why nothing diverges

[[economy-model]]'s table gains a row, and it is a kind that table did not have:

| Kind | Terms | Bound |
|---|---|---|
| **Bounded by construction** | **the cycle impulse** | **A sum of three sines normalised to unit standard deviation. Its extreme is `K / sqrt(K/2)` × amplitude, a number derived from the term count rather than chosen.** |

That is a stronger guarantee than a clamp — there is no value to set wrong — and a
less familiar one, so `tests/test_economy.gd` measures it rather than asserting it:
the impulse stays inside the analytic bound for every nation every month, growth
never reaches the guard clamp with no budget committed, and the output gap stays
inside `(max impulse + IMPULSE_MAX) / GAP_CLOSE` while averaging near zero over ten
years.

The first version of that last check compared quarter-window means and was **wrong**:
a quarter of a ten-year run is 30 months against a longest period band of 97–131, so
the two windows sit at arbitrary and unrelated *phases* of one oscillation. It was
comparing where the wave happened to be, not whether it was going anywhere.

## 11. What is deliberately not built

- **No monetary policy.** [[mechanics-economy]] tiers the central bank, interest
  rates and quantitative easing **Someday**, and [[out-of-scope-mvp]] records that
  France does not set its own rate. So the cycle is a pressure with no dedicated
  lever: the player fights it fiscally or not at all. That is why V1.6a ships a
  statistic and its price rather than a verb — [[unrest-model|V1.5]]'s inverted rule,
  in a block that also contains verbs.
- **No effect on potential output.** A business cycle is by definition output around
  potential.
- **No asymmetry.** Real recessions are shorter and sharper than expansions. A signed
  skew is one constant with no reader today and would want its own band; the wave is
  symmetric and the file says so.

---

Related: [[index]] · [[economy-model]] · [[trade-model]] · [[unrest-model]] · [[decision-log]] · [[v1]]
