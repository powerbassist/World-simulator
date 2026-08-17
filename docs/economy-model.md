---
title: Economy Model
tags:
  - decision
  - economy
  - simulation
---

# Economy Model

The MVP economy and budget, as built in [[ROADMAP|S4]]. Every formula, every
constant, and the argument for why nothing runs away.

This is a **game model**, not a macroeconomic forecast. It is judged on whether
the player's decisions produce legible, delayed, reversible consequences — not on
whether it would survive a referee. Where realism and legibility conflict,
legibility wins, and the trade is noted.

## Scope and units

Everything is in **constant prices**. There is no inflation model at MVP
([[out-of-scope-mvp|monetary policy is out]] — France does not set its own
interest rate), so every rate below is a *real* rate and every EUR figure is a
real EUR.

| Quantity | Unit |
|---|---|
| Sector output, GDP, potential GDP, debt | EUR billions, float |
| Growth, unemployment, tax rates, spending lines, revenue, deficit | percent, range 0–100 |
| Sector shares | 0–1, sums to 1.0 |
| Spending and revenue lines | **percent of GDP** |

Budget lines are percent of GDP rather than absolute EUR. They then auto-scale
with the economy, which is the behaviour a player expects from a budget slider,
and it removes an indexation rule the MVP has no inflation model to supply.
The UI shows the derived EUR figure alongside.

### Three sectors, not four

Agriculture, industry, services — the three the data has. [[ROADMAP|S4]]'s scope
line originally said four, splitting energy out of industry; that was written
before [[data-sources]] established no open dataset provides the split. No MVP
mechanic distinguishes energy from industry — energy mix is [[someday]] tier — so
a fourth sector would be a hand-tuned constant with no reader. Corrected in the
ROADMAP rather than honoured.

## Tick order

```
clock.month_elapsed
  → Economy.tick_month(state)      GDP, sectors, unemployment, population
  → Budget.tick_month(state)       revenue, spending, deficit, debt
  → Opinion.tick_month(state)      satisfaction, salience, approval   (S5)
  → state.append_history()
```

Economy first, so budget percentages apply to the GDP the player will actually
see this month. Opinion **after** both — it reacts to figures that are already
settled. See [[opinion-model]].

**No randomness anywhere in this model.** Determinism is what makes the budget
projection exactly equal to what subsequently happens, which is a done-when
condition. That rule extends to [[opinion-model|opinion]]: polling noise is
applied when a figure is rendered, never stored, and is a pure function of the
poll rather than a live `randf()`.

## Economy

Run for all ten nations. Only the player's nation has a budget; the other nine
run steps 1–7 with `demand_impulse = external_impulse = 0`.

### 1. Trend growth

```
trend = Σ_s ( share_s × SECTOR_TREND[s] ) + potential_shift
```

| Constant | Value | Why |
|---|---|---|
| `SECTOR_TREND.agriculture` | 0.2 %/yr | Mature, land-constrained, near-zero real growth. |
| `SECTOR_TREND.industry` | 1.0 %/yr | Productivity growth, offset by secular share decline. |
| `SECTOR_TREND.services` | 1.4 %/yr | The growing share; carries most of the trend. |

France's mix (1.5 / 19.2 / 79.3 %) lands at **1.31 %/yr**, which is about right
for French potential growth, with no separate base constant needed. Because a
nation's trend is read off its own sector mix, ten nations get ten different
trends from one table — no per-nation constants, no `if nation_id ==` anywhere.

`potential_shift` is the budget's long-run channel, described under
[Budget → economy](#budget--economy).

### 2. Potential output

```
potential_gdp *= (1 + trend/100) ^ (1/12)
```

A single aggregate scalar. Per-sector potential was considered and dropped — it
would double the state for no reader, since nothing in the MVP asks whether
*industry specifically* is above capacity.

### 3. Output gap

```
gap = 100 × (gdp − potential_gdp) / potential_gdp
```

### 4. Actual growth

```
growth = trend + GAP_CLOSE × (−gap) + demand_impulse + external_impulse
         + coercion_impulse + firm_impulse + unrest_impulse + cycle_impulse
growth = clampf(growth, GROWTH_MIN, GROWTH_MAX)
```

| Constant | Value | Why |
|---|---|---|
| `GAP_CLOSE` | 0.30 | Gap half-life ≈ 28 months. A shock is visible for most of a five-year term and mostly spent by the end of it — the pacing the game needs. |
| `GROWTH_MIN` / `GROWTH_MAX` | −12 / +12 %/yr | Hard bound. Not a modelling claim; a guard rail so an absurd budget produces an absurd-but-finite economy. |

`cycle_impulse` is the seventh addend, added at [[cycle-model|V1.6a]], and it is the
only one that is non-zero without the player or any AI having done anything — which
is what [[v1]] §6 means by *booms and recessions arriving whether or not deserved*.
It is a **pure function of (nation id, absolute month)**, so the no-randomness rule
above survives intact and `Budget.project()` reproduces a recession exactly rather
than approximately; and it moves GDP and never `potential_gdp`, because a business
cycle is by definition output *around* potential. Full argument: [[cycle-model]].

The half-life follows from the gap's own equation of motion: each month the gap
changes by `(growth − trend)/12 = −GAP_CLOSE × gap / 12`, a decay rate of
0.025/month, so `ln 2 / 0.025 ≈ 28` months.

### 5. Apply growth to sectors

Two-part distribution, so the trend and the cycle land in different places:

```
# trend part: each sector grows at its own rate
for s: sector_output[s] *= (1 + (SECTOR_TREND[s] + potential_shift)/100) ^ (1/12)

# cyclical part: whatever is left to reach the month's GDP target
target_gdp   = gdp_prev × (1 + growth/100) ^ (1/12)
cyclical     = target_gdp − Σ_s sector_output[s]
weight_s     = share_s × SECTOR_CYCLE_BETA[s]
sector_output[s] += cyclical × weight_s / Σ weight
gdp = Σ_s sector_output[s]
```

| Constant | Value | Why |
|---|---|---|
| `SECTOR_CYCLE_BETA.agriculture` | 0.4 | Food demand is inelastic; agriculture barely notices a recession. |
| `SECTOR_CYCLE_BETA.industry` | 1.8 | Durable goods and investment — the classic cyclical amplifier. |
| `SECTOR_CYCLE_BETA.services` | 0.8 | Large and stable, so it damps the aggregate. |

Splitting it this way matters. Distributing *all* growth by cyclical beta would
push industry's share **up** over a decade, the opposite of the secular trend.
Trend by own rate, cycle by beta, gives the right long-run drift toward services
and the right short-run amplitude in industry. And because the cyclical part is
computed as a residual against the GDP target, sector output sums to GDP exactly
by construction — no drift, no reconciliation step.

### 6. Unemployment

Okun's law plus reversion to a structural rate:

```
du = ( −OKUN × (growth − trend) + UNEMP_REVERT × (structural − u) ) / 12
u  = clampf(u + du, UNEMP_MIN, UNEMP_MAX)
```

| Constant | Value | Why |
|---|---|---|
| `OKUN` | 0.4 | One point of growth above trend for a year removes 0.4 points of unemployment. Within the empirical range for European labour markets, which are less responsive than the US ~0.5. |
| `UNEMP_REVERT` | 0.35 /yr | Unemployment finds its structural level over roughly three years once growth is back at trend. |
| `UNEMP_MIN` / `UNEMP_MAX` | 1.0 / 40.0 | Guard rails. |

Unemployment is the number [[mvp|the MVP]] leans on hardest, because S5 voter
blocs react to it more than to GDP. It gets the honest textbook relationship
rather than a bespoke one.

### 7. Population

```
population *= (1 + ns.pop_growth_pct/100) ^ (1/12)
```

**Per nation and measured, since [[demography-model|V1.5b]].** This was
`POP_GROWTH_PCT = 0.15 %/yr`, one flat constant shared by all ten, and the constant is
**deleted** rather than left unused. `pop_growth_pct` is read off
`imported.cohorts`, from the World Bank series 2015→2024, and it spans Italy's
**−0.238** to Luxembourg's **+1.938** — so the old constant had every nation in Europe
growing and one of them shrinks.

The done-when check "no negative population" stops being trivially true the moment the
rate can be negative, which is why `nation.gd` now bounds it at load
(`MIN_POP_GROWTH_PCT`) rather than trusting the one constant.

The age structure that sits under this figure, and the dependency ratio derived from it,
belong to `src/sim/demography.gd` rather than here — see [[demography-model]].

## Budget

Player's nation only.

### Revenue

Three levers, each a rate in percent, each with a diminishing-returns curve:

```
erosion(r, ref, k) = clampf(1 − k × (r − ref)/ref, EROSION_MIN, EROSION_MAX)
revenue_pct_gdp_s  = BASE_SHARE[s] × rate_s × erosion(rate_s, REF_RATE[s], EROSION[s])
```

With `rate` in percent and `BASE_SHARE` a share of GDP, the product is already a
percent of GDP — no scaling factor to get wrong.

| Lever | `BASE_SHARE` | `EROSION` |
|---|---|---|
| Income tax | 0.50 | 0.35 |
| Corporate tax | 0.18 | 0.55 |
| VAT | 0.53 | 0.25 |

`BASE_SHARE` is the share of GDP the tax nominally falls on — labour and
household income, corporate profits, consumption. Erosion rises with mobility of
the base, which is why corporate is nearly double income and VAT is lowest.

> [!note] `REF_RATE` was a shared constant until V1.2a; it is now `ns.start_tax_rates_pct`
> `Budget._erosion()`'s reference used to be `economy_constants.TAX_REF_RATE_PCT`,
> one table for all ten nations, matched to `data/policy_defaults.json`'s
> 20/25/20 — the same file starting rates lived in before V1.2a made them
> per-nation. Once they were, a shared reference put every nation but France
> off its own erosion curve at new-game. `revenue_lines()`,
> `modelled_revenue_total()` and `_erosion()` now all take the reference as an
> explicit argument, and every call site passes `ns.start_tax_rates_pct` — the
> same "delta against the nation's own start" shape `start_spending_pct_gdp`,
> `start_deficit_pct_gdp` and `start_unemployment_pct` already used. Erosion is
> then exactly 1.0 for every nation at new-game, France included, with numbers
> unchanged: `TAX_BASE_SHARE × rate` at the nation's own starting rate.

`EROSION_MIN` / `EROSION_MAX` = 0.35 / 1.25 clamp the multiplier, so a rate of
zero or of 100 % still produces a finite, signed number, at whatever reference
the nation's own start set.

### The revenue residual

At reference rates the three modelled taxes yield `BASE_SHARE × rate` summed —
**25.1 % of GDP** for France's 20/25/20. France actually collects 46.1 %
(`fiscal.tax_revenue_pct_gdp`). The difference is social contributions, local
taxes, and everything else the player does not have a slider for. Every nation
calibrates its own residual the same way, against its own rates and its own
authored `tax_revenue_pct_gdp` — the United Kingdom's modelled 25.1 % against
its authored 35.3 % is the tightest margin of the ten as of V1.2a.

```
other_revenue_pct_gdp = nation.tax_revenue_pct_gdp − Σ revenue_pct_gdp_s(starting rates)
```

Computed once at new-game, per nation, then held constant. France gets 21.0.
This is the calibration that makes the model start on the real number instead of
near it, and it costs one subtraction.

Switzerland is the binding case at 27.8 % total, leaving a residual of 2.7. If a
future tuning pass raises the base shares, that goes negative — so new-game
checks it, clamps to zero, and records a loud error rather than silently
producing a nation that collects taxes it does not have.

### Spending

Five player-set lines, one authored constant, one computed:

| Line | Default, % of GDP | Player-set |
|---|---|---|
| Health | 11.0 | yes |
| Education | 5.5 | yes |
| Defence | 2.0 | yes |
| Pensions | 14.5 | yes |
| Infrastructure | 3.5 | yes |
| Other (administration, transfers, everything unmodelled) | 12.0 | no |
| Debt service | computed | no |

```
debt_service_pct_gdp = DEBT_REAL_RATE_PCT × debt_eur_bn / gdp_eur_bn
```

The rate is already in percent and `debt / gdp` is a bare ratio, so the product
is a percent of GDP with no scaling factor — 2.0 × 1.16 = 2.32 % for France.

`DEBT_REAL_RATE = 2.0 %/yr`. Flat — bond yields and credit ratings are
[[v1|V1]]. The number that matters is that **2.0 > 1.31**: r exceeds trend
growth, so a zero primary balance still walks the debt ratio upward, and
stabilising it requires a small primary surplus. That is the entire fiscal
pressure of the MVP, and it comes from one constant being larger than another.

Defaults total **50.8 %** of GDP against 46.1 % revenue — France opens on a
4.7 %-of-GDP deficit, close to the real figure, and hands the player a problem
on turn one.

### Deficit and debt

```
deficit_pct_gdp = total_spending_pct_gdp − total_revenue_pct_gdp
debt_eur_bn    += deficit_pct_gdp / 100 × gdp_eur_bn / 12
```

## Budget → economy

Three channels, deliberately. Each one exists because a done-when condition or a
later session needs it; nothing is wired "for completeness".

### Demand impulse — short run

Fires on **commit**, not continuously. A budget change is a shock; a budget left
alone is not.

```
Δimpulse = ( Δspending_pct × MULT_SPENDING
             − Σ_s Δrevenue_pct_s × MULT_TAX[s] ) / LEVEL_FACTOR
LEVEL_FACTOR = 1 / (12 × (1 − IMPULSE_DECAY))
```

and each month `demand_impulse *= IMPULSE_DECAY`.

| Constant | Value | Why |
|---|---|---|
| `IMPULSE_DECAY` | 0.90 /month | Half-life ≈ 6.6 months, effectively spent after three years. |
| `MULT_SPENDING` | 0.90 | Standard fiscal multiplier for government purchases. |
| `MULT_TAX.income` | 0.60 | Households save part of a tax change, so the multiplier is below the spending one. |
| `MULT_TAX.corporate` | 0.40 | Weakest demand channel; corporate tax does most of its work on potential, below. |
| `MULT_TAX.vat` | 0.70 | Falls on consumption directly. |
| `IMPULSE_MAX` | ±6 %/yr | Must sit *inside* `GROWTH_MAX`, not outside it. See below. |

`LEVEL_FACTOR` converts "the GDP level effect I want" into "the annualised
impulse that produces it once decayed to nothing" — the geometric sum
`Σ impulse₀ × decay^n / 12`. Stating the multipliers as multipliers keeps
[[ROADMAP|S10]]'s balance pass legible; without it, the tunables would be
opaque products.

> [!note] `IMPULSE_MAX` was ±50 %/yr until S10
> Two guard rails bound growth — this one and `GROWTH_MAX` at ±12 %/yr — and at
> ±50 the wrong one was binding. A large budget commit produced an impulse of
> 20–90 %/yr, growth pinned against ±12, and it *stayed* pinned for a year or
> more while the impulse decayed underneath it. For that whole period the clamp,
> not the model, was setting the growth rate: two different budgets one of which
> was three times as expansionary as the other produced the same +12 %.
>
> A guard rail is meant to be unreachable under any input the player can express.
> At ±6 the largest committable budget produces a boom of about +6 %/yr fading
> over two years, `GROWTH_MAX` goes back to being unreachable, and the two rails
> stop competing. `tests/test_balance.gd` asserts the growth clamp is never
> touched across a fourteen-year run.

`Δrevenue` is computed by running the revenue function at the old and new rates
on the current GDP, rather than by a separate approximation. Same function both
sides, so the erosion curve is automatically respected and the two cannot drift.

**This is what the done-when condition describes.** Raising income tax lifts
revenue immediately and pushes growth below trend for a year or two; the impulse
then decays, growth returns to trend, and the GDP *level* stays permanently
lower. Delayed, legible, and not permanent-as-a-death-spiral.

### Potential shift — long run

Where multi-year payoff lives, and the reason infrastructure and education are
not just opinion levers.

```
target = INFRA_BETA × Δinfrastructure + EDU_BETA × Δeducation
         − CORP_TAX_BETA × Δcorporate_rate
         + TRADE_OPENNESS_BETA × (openness_index − 1)
potential_shift += (target − potential_shift) × SHIFT_ADJUST / 12
potential_shift  = clampf(potential_shift, −SHIFT_MAX, SHIFT_MAX)
```

All deltas are against the nation's starting values.

> [!note] The fourth writer, added at V1.3b
> `openness_index` is a **ratio** — the nation's raw trade mass against what that
> mass would be with no agreement in force — so it is exactly 1.0 for a nation
> that has signed nothing, and this whole term is exactly zero for every regime in
> the balance harness. That is what let V1.3b's re-run assert *bit-identical*
> rather than *close enough*. Trade openness is a trend effect rather than a
> demand one, so this is the right channel, and sharing `SHIFT_MAX` with
> infrastructure is the point rather than a compromise: a treaty and a public
> investment programme compete for the same ±1.0. The argument for the ratio form,
> including the three defects of the obvious trade-to-GDP alternative, is
> [[trade-model]].

| Constant | Value | Why |
|---|---|---|
| `INFRA_BETA` | 0.15 | A sustained extra point of GDP on infrastructure buys 0.15 points of trend growth. Real, small, and only visible after years. |
| `EDU_BETA` | 0.10 | Same channel, slower and weaker still. |
| `CORP_TAX_BETA` | 0.02 /pp | Ten points of corporate tax costs 0.2 points of trend growth through investment. |
| `SHIFT_ADJUST` | 0.20 /yr | Five-year time constant. A player cannot see this land inside one term, which is the point. |
| `SHIFT_MAX` | ±1.0 %/yr | Hard clamp. The single most important guard in the model — it is the only term that feeds back into trend, so it is the only one that could compound. |

### Structural unemployment shift

```
structural = clampf(start_u + STRUCT_INCOME_BETA × Δincome_rate, 2.0, 25.0)
```

`STRUCT_INCOME_BETA = 0.08` — the labour-tax wedge. Five points of income tax
adds 0.4 points of structural unemployment. One term, clamped, because a
plausible mechanism the player can feel beats three the player cannot separate.

## Neighbours and trade

The nine AI nations run the economy above with no budget and no demand impulse.
Their trends differ because their sector mixes differ, and their shares drift.

**This section described a single GDP-weighted aggregate from S4 to V1.3a. It is
now a model of its own** — [[trade-model]] — and the summary here is deliberately
short, because that document is where the argument lives.

```
external_impulse = TRADE_BETA × Σ_B w(A,B) × (growth_B − baseline_B)
```

`w(A,B)` is a **directed** trade weight from `src/sim/trade.gd`: partner GDP under
an exponent, times bonuses for EU co-membership and a shared border, times a term
in the pair's relations, normalised over the other nine. Ninety entries,
snapshotted once per tick before any nation ticks. `Economy.neighbour_weighted_growth()`
is retired — two answers to "how much does B matter to A" is the divergence
[[diplomacy-model|the symmetric pair key]] exists to make impossible.

`baseline_B` is **per partner**, captured at new-game, and that is what makes the
sum exactly zero whenever every partner sits at its own baseline *whatever the
weights say*. Under the single scalar it replaced, re-weighting alone produced an
impulse — a free growth boost bought by improving relations with whichever nation
happened to have the highest trend.

`TRADE_BETA = 0.25`, unchanged, and it now lives in `src/sim/trade_constants.gd`
with the rest of the trade tunables.

> [!note] Still quiet, and now honestly so
> The term is exactly zero at new-game and stays near zero while nothing perturbs
> a partner — the nine AI nations have no budget and take no shocks, so the
> quiet-state residual is about **0.008**, from partners drifting off their own
> baselines as sector shares move. Two things now move it for real: a signed trade
> agreement, which is bilateral and so raises the partner's trend as well as the
> player's; and, from [[v1|V1.3c]], tariffs and sanctions. Under a synthetic
> partner recession the term reaches 6 % of `IMPULSE_MAX` — measured, in
> [[trade-model]], so the headroom is known rather than assumed.

The other nine still get no external impulse of their own. Not a stability
concern: the coupled ten-nation system's common mode is provably stable, and the
eigenvalues are recorded in [[trade-model]] so V1.3c can lift the restriction
knowingly. The reason to defer it is that turning it on **replaces the 28-month
gap half-life** this document argues the game's pacing from.

## Why nothing diverges

Every dynamic quantity in the model is exactly one of:

| Kind | Terms | Bound |
|---|---|---|
| Mean-reverting | output gap, unemployment | Pulled back toward a target every month. |
| Decaying to zero | demand impulse | Geometric, ×0.90/month. |
| Hard-clamped level shift | potential shift, structural unemployment | Cannot exceed ±1.0 %/yr and [2, 25] %. |
| Clamped outright | growth, unemployment, erosion multiplier | Bounded by construction. |
| Bounded by its inputs | sector output, GDP, potential, population | Grow at a clamped rate. |
| **Bounded by content, at load** | **trade openness index, external impulse** | **`MAX_AGREEMENT_WEIGHT_MULTIPLIER` bounds the openness index before `SHIFT_MAX` ever sees it; the trade weight is normalised so it sums to 1 by construction.** |
| **Bounded by construction** | **the cycle impulse** | **A sum of three sines normalised to unit standard deviation, so its extreme is `K / sqrt(K/2)` × amplitude — derived from the term count rather than chosen, and therefore a bound nobody can set wrong. [[cycle-model]] §10.** |

The only unbounded quantity is **debt**, and at a flat 2 %/yr it grows at most
close to linearly. The default budget takes France from 116 % to roughly 148 %
of GDP over ten years — pressure, not a spiral. The most abusive budget the test
suite throws at it lands near 400 %, which is a finite number describing a
ruined country.

Note what is *not* in the model: no term where a variable feeds its own growth
rate without a clamp in between. `potential_shift` is the only feedback into
trend, and it is clamped at ±1.0 before it is ever read. That is the whole
stability argument, and it is short on purpose.

**V1.3b left that argument intact deliberately, and it was the harder of its two
options.** The obvious openness figure — raw trade mass over own GDP — does not
break the sentence above, but it makes the clamp *bind under ordinary play*:
partner GDP grows at trend forever, so the index ratchets up about 20 % over the
harness's fourteen years from time passing alone, and the clamp rather than the
model ends up setting trend growth. That is the `IMPULSE_MAX = ±50` failure this
document already writes up, one section down, committed a second time. The ratio
form has no time trend at all, and the table above gains one row that is bounded
by a load-time content check rather than by a runtime clamp. See [[trade-model]].

The argument is not the evidence. `tests/test_economy.gd` runs 120 months under
five budgets, including the absurd ones, and asserts finiteness and sanity on
every field of every nation every month. **That** is the evidence.

## Where the constants live

`src/sim/economy_constants.gd`, all of them, as typed GDScript `const`s. One
file, so [[ROADMAP|S10]]'s balance pass has one place to edit and
`economy.gd` and `budget.gd` cannot drift apart.

They are deliberately **not** in `data/`. [[engine-decision|Rule 1]] puts
*content* in data — nations, parties, laws, the things a designer adds more of.
These are model parameters: there is exactly one set, forever, and moving them to
JSON would buy a loader and a validator in exchange for nothing.

The one thing that *is* content is starting tax rates and spending split, and it
lives in `data/nations/*.json`'s `fiscal` block, per nation, since [[ROADMAP|V1.2a]].
It was a single shared `policy_defaults.json` from S4 through V1.1d, on the
stated grounds that only France had a budget at MVP; V1.2a made a second nation
playable and that grounds ran out. See [[data-architecture]] for the schema and
the sourcing behind the other nine nations' numbers.

---

Related: [[index]] · [[data-architecture]] · [[engine-decision]] · [[mvp]] · [[ROADMAP]] · [[mechanics-economy]]
