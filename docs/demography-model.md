---
title: Demography Model
tags:
  - decision
  - sim
  - balance
---

# Demography Model

Ageing and migration, as built at V1.5b — the second session of the V1.5
block. An age structure that drifts at a **measured** rate, the dependency ratio that
falls out of it, the denominator that ratio puts under [[society-model|V1.5a]]'s
quality stock, and migration as the one verb able to close what ageing opens.

Same standard as [[society-model]], [[companies-model]] and [[defence-model]]: a **game
model**, judged on whether the player's decisions produce a legible, attributable
political outcome. Where realism and legibility conflict, legibility wins, and the
trade is noted.

## 1. The row's central premise was wrong, and the dataset was already half-downloaded

's decomposition defers (b) partly on this: ten authored age structures
with **no dataset behind them** would be [[foreign-policy-model|the clustered
`coalition_position` finding]] a block later. `tools/import_data.py` imported six World
Bank indicators and none of them was an age structure, so the claim looked right.

It is not. The same provider, the same licence, the same script and the **same download
loop** carry the whole thing, and `docs/data-sources.md`'s loop has always fetched
`date=2015:2024` — so a per-nation ageing *slope* cost one extra read of a series
already on disk and **no extra download at all**.

| | 2015 | 2024 | slope |
|---|---|---|---|
| FRA 65+ | 18.85 | 22.15 | **+0.366** pt/yr |
| NLD 65+ | 17.76 | 20.50 | +0.304 |
| ITA 65+ | 22.03 | 24.62 | +0.288 |
| DEU 65+ | 21.05 | 23.20 | +0.238 |
| GBR 65+ | 17.77 | 19.50 | +0.192 |
| LUX 65+ | 14.20 | 15.48 | **+0.142** |

Old-age dependency spans **LUX 0.225 → ITA 0.388, 1.72×**; the slopes span **2.58×**,
wider than the levels. Nothing here is authored and nothing clusters. That is the
**twenty-third** instance of the stale-row failure [[trade-model|V1.3b]] first
recorded, and like the other twenty-two it was found by counting rather than by being
told.

## 2. The cohort machine was designed and then CUT, and Luxembourg is the proof

The obvious build is three cohorts and four monthly flows — births from fertility,
maturation at 1/(15·12), retirement at 1/(50·12), deaths at 1/((LE−65)·12). Three
things killed it, and only the third is about taste:

**Nothing reads a count.** `population` enters no equation in `economy.gd` — not GDP,
not potential, not trend, not unemployment. Its one live reader is
`Companies.firm_jobs_offset_pct()`, which returns at `if net_jobs == 0.0` **before** the
denominator is used, so the labour force is structurally invisible in any run with no
subsidy and no `business` law. The denominator wants a *ratio*; the labour force wants a
*share*. Neither wants a count, and counts would cost five serialised fields plus a
conservation invariant.

**A uniform 15–64 bucket is wrong exactly where the differentiation is.** The stationary
identity holds on France (working/50 = 1.227 %/yr against 65plus/(LE−65) = 1.232) and
fails on Luxembourg (1.37 against 0.85), because Luxembourg's working cohort is bulged
young by migration and a uniform outflow over-ages it. The machine predicts **Luxembourg
ages fastest of the ten**. Measured, it ages **slowest**. The model's largest artefact
would have sat on the two nations that motivated importing the data.

**And it re-derives, badly, a number the dataset already publishes.** Fertility and life
expectancy are *inputs* to a demographic projection; the 65+ share is its *output*.

So the drift is **linear at its own measured rate**, and this file carries **exactly one
tuned constant**. It is deliberately *not* `capability_target()`/`capability_step()`'s
shape, which three other stocks in this project do use: those converge on a target the
player sets, and a population converges on nothing a president decides. Forcing the
precedent would have added a convergence rate to buy a resemblance.

## 3. Two live shares, one residual, and no new kind of state

`young_share` and `old_share` are per-nation floats on `NationState`. The 15–64 share is
**derived at every read** as `1 − young − old` and never stored — `_apply_growth_to_sectors()`'s
own discipline, which keeps sector output summing to GDP with no reconciliation. The
three sum to 1.0 by construction, so a conservation bug is structurally impossible
rather than prevented by a check somebody must remember to run. It is also why
`data/nations/` authors **two** shares and not three.

`dependency_ratio()` is a **function**, `GameState.debt_to_gdp_pct()`'s shape. A cached
ratio is a second answer to a question two live shares already answer.

The single-writer discipline holds and extends:

| Quantity | Sole writer |
|---|---|
| `share` | a subsidy, `Companies.execute()` |
| `state_share` | an ownership op, `Companies.execute()` |
| `regulation_burden` | a law, `Legislature.apply()` |
| `corruption` | a law, `Legislature.apply()` |
| `service_quality` | `Society.tick_month()` |
| **`young_share` / `old_share`** | **`Demography.tick_month()`** |
| **`migration_stance`** | **a law, `Legislature.apply()`** |

`tests/test_demography.gd` reads `demography.gd` and fails if the file contains a write
to `ns.migration_stance` — the read-the-file idiom [[people-model]], [[calendar-model]]
and [[society-model]] all use.

### The residual clamp, and the bug the test caught

The first version clamped inside `working_share()` with a `maxf()` against
`WORKING_SHARE_MIN`. `tests/test_demography.gd`'s sum-to-1.0 assertion caught it: the
moment that floor binds, `young + old + working` stops summing to 1.0, and it breaks
**precisely in the extreme states where somebody would be relying on it**. The floor is
enforced on the *pair* in `_tick_nation()` instead, by scaling both shares down together
— which preserves the floor, the sum, and their ratio at once.

## 4. The shortfall is a DENOMINATOR at one existing site

[[v1]] §5 asks for ageing to drive a *cost*, and `spending_pct_gdp` is a player-set
**rate**: nothing can drive it. What ageing can do is make the same rate buy less.

`Society.quality_target()` divides by `Demography.dependency_factor(ns)` raised to a
per-line elasticity. A nation's own starting spending is by definition adequate for its
own starting dependency, so the required rate **scales with the ratio** and nothing has
to be authored — no per-capita benefit, no beneficiary count, no cost side. The factor
is **exactly 1.0** at new game for all ten nations, so the layer is inert until the
clock runs.

That is what [[society-model]] §1 predicted a session in advance: *"pension adequacy is
spend per DEPENDENT, and the dependent count is V1.5b's."* `pensions` joins
`QUALITY_KEYS`, and it cost **one entry and zero lines in `opinion.gd`** — which is what
the registry was for, and `opinion.gd`'s own comment already promised it.

## 5. Migration is the second `effects.society` term, and the sign is load-bearing

[[society-model]] §3 declared `effects.society` as *"schema two later sessions read
rather than one session's private field"*. This is the first of them, and it widened
the channel by **exactly one key**: `law.gd`'s `_extract_society()` now accepts
`{corruption?, migration?}` and requires at least one. No new channel, no new verb, no
new content directory — the sixth session in a row to add none.

**Signed both ways**, and here the sign carries a second load V1.4b's deregulation
argument did not need. Every nation's dependency ratio rises forever; there is no
retirement-age, pension-age or fertility lever in this game; and nothing in this project
ever lifts a charge the player did not open. A one-directional migration stance would
therefore leave ageing as exactly the **permanent monotone charge** [[defence-model]]
names, with no verb able to close it. So *"can the open direction hold the ratio flat?"*
is a pre-committed band (§7, T1-ii) and an assertion in `tests/test_demography.gd`,
not a hope.

The price is the shape [[society-model]] named: the political gain is the law's own
authored `bloc_offset`, immediate and certain; the demographic cost arrives through
working share → dependency ratio → quality stock, slow and contingent. **Fast in, slow
out**, on a new machine.

`data/laws/social.json` carries both directions — `immigration_tightening`, re-authored
off `structural_unemployment_pct` exactly as the decomposition booked, and a new
`labour_migration_scheme`.

### The third anti-double-count, scoped to the pair

`law.gd` refuses a law carrying both `effects.society.migration` and
`structural_unemployment_pct`, beside V1.4b's `company` refusal and V1.5a's
`spending_pct_gdp` one. A migration stance reaches structural unemployment through the
labour force — same act, same landing site, same units — and `immigration_tightening`
was the law that had it *both* ways until this session.

Scoped to the **pair** and not to the channel, deliberately: `data/laws/labour.json`'s
four laws keep `structural_unemployment_pct` and are right to, because a labour reform
is a claim about the matching rate rather than about who is in the country. A blanket
refusal would have cost four working laws to catch one.

## 6. What was deleted

**`economy_constants.POP_GROWTH_PCT`**, one flat 0.15 %/yr for all ten. Replaced by ten
measured facts spanning Italy's **−0.238** to Luxembourg's **+1.938** — the constant had
every nation in Europe growing, and one of them shrinks.

**`companies_constants.LABOUR_FORCE_SHARE`**, one flat 0.45. Its own comment called it
*"the measured participation-times-working-age figure for the roster, not a dial"*. The
claim was taken at its word and checked: France is 0.7407 × 0.6134 = **0.4543**, right
to three digits. Germany is 0.7994 × 0.6289 = **0.5027**, and the roster spans Italy
0.423 to the Netherlands 0.551. One number right for one nation became two measured
facts for all ten, and the jobs channel's *"no tuned constant at all"* property survives
intact.

Both deletions are `AGREEMENT_ACCEPT_MIN`'s treatment at [[foreign-policy-model|V1.3e]]
and the day budget's at [[calendar-model|U6a]]: a tuned constant nothing reads is a
number a later session finds and reasons from.

## 7. The probe, and a THIRD way a pre-committed tiebreaker fails

`tools/demography_probe.gd`. Bands, tiebreakers and isolation paths were fixed before
any sweep ran — [[decision-log]]'s V1.5a rule — and the finding is that **the rule as
V1.5a restated it was still not enough**.

### (T1) `MIGRATION_SHARE_BETA` — the tiebreaker was a bound for the third time

Band (i), *readable*: a saturated stance held one 60-month term moves the `pensioners`
bloc approval row past ±3.0 — the **bloc row and not the headline**, because
`society_probe.gd` table (c) already established that a single spending issue cannot
reliably carry a headline price. Band (ii), *closable*: a saturated **open** stance
holds the dependency ratio at or below where it started.

| beta | pensioners row | ratio t0 → t60 | band |
|---|---|---|---|
| 0.0060 | −2.03 | 0.3611 → 0.3499 | fail (i) |
| 0.0080 | −2.75 | 0.3611 → 0.3353 | fail (i) |
| **0.0090** | **−3.12** | **0.3611 → 0.3281** | **PASS** |
| 0.0100 | −3.49 | 0.3611 → 0.3211 | PASS |
| 0.0120 | −4.22 | 0.3611 → 0.3074 | PASS |
| 0.0160 | −5.70 | 0.3611 → 0.2811 | PASS |

The pre-committed tiebreaker was *"strictly less legible than a saturated corruption
register on its own bloc row, then take the **largest** passing candidate"*. It **is** a
strict ordering, which is what V1.5a's restated rule asks for — and it still failed,
because **both bands are one-sided minimums**. Every candidate above the threshold
passes, so "largest" returns the top row of whatever grid was swept. The first grid
stopped at 0.010; 0.010 was chosen; widening the grid moved the answer to 0.016. **The
range was choosing the constant.**

**The rule is therefore extended, and that is this session's contribution to the
discipline:** a pre-committed tiebreaker must strictly order the survivors **and its
answer must not move when the candidate range is widened**. That second clause is
checkable in advance — widen the grid and re-read — where *"is it a strict ordering?"*
is not.

The corrected selector is forced rather than chosen: when both bands are minimums, the
**smallest** passing candidate is the least-invasive lever that clears them, and it is
stable under widening by construction. It chooses **0.0090**, which is **interior** to
the grid — two candidates fail below it and three pass above — and that interiority is
the evidence the correction did something. The corruption reference stays, demoted to
what it always was: a ceiling, slack at −14.35.

### (T2) `DEPENDENCY_ELASTICITY["health"]` — the kill switch FIRED

Band: with the pensions entry held out of the comparison and every spending line
untouched, ageing alone over 60 months moves the `health` issue's widest bloc row past
±3.0.

| elasticity | widest bloc row | headline |
|---|---|---|
| 0.15 | −0.07 | −0.04 |
| 0.35 | −0.16 | −0.09 |
| 0.60 | −0.29 | −0.17 |
| 1.00 | −0.51 | −0.31 |

**It failed at every candidate, including 1.00** — equal to the pensions entry and
therefore the largest defensible value. So the entry was **deleted** rather than shipped
at a value that looks alive in a constants file and is invisible in play, and
`DEPENDENCY_ELASTICITY` ships with one entry.

The reason is structural rather than a bad candidate row, and it is recorded because a
later session will be tempted to try again: the dependency factor reaches only ~1.10
over a term, so even at an elasticity of 1.0 the health target moves a fraction of a
point of GDP — which is [[companies-model|V1.4b]]'s finding that this whole layer's
channels sit below the opinion model's resolution. **Ageing is a health cost in the
world; it is not one this model can make a voter notice inside a term.**

`DEPENDENCY_ELASTICITY["pensions"] = 1.0` is **definitional, not tuned** — twice the
pensioners per worker is half the pension per pensioner at an unchanged rate — and is
commented as such, because a bare 1.0 in a constants file is a number a later session
finds and sweeps. `LABOUR_FORCE_SHARE`'s comment made the same defence of itself and was
right to.

### (T3) The labour force, re-measured rather than silently invalidated

Deleting `LABOUR_FORCE_SHARE` moves [[companies-model|V1.4a]]'s measured jobs figures
whether or not anyone likes the new ones, so the pre-committed question was only whether
the **ordering** survives. New denominator ÷ old, by nation: ITA **0.940**, BEL 1.001,
FRA 1.010, GBR 1.080, ESP 1.101, DEU 1.117, AUT 1.128, LUX 1.141, CHE 1.215, NLD **1.225**.

France's is 1.010, so V1.4a's 0.229/0.010 spread becomes ≈0.227/0.0099 — both scale by
one factor, so the ordering is untouched and this is a re-measure rather than a model
change. Italy is the interesting row: its denominator **shrinks**, so it is the one
nation where a given firm shedding a given number of jobs now costs *more* points of
unemployment than the flat constant said.

### (e) Every clamp is slack, measured

Over 168 months at a saturated stance in both directions across all three playable
nations: share ceiling **0.3245** against `SHARE_MAX` 0.60; working floor **0.5007**
against `WORKING_SHARE_MIN` 0.20; factor ceiling **1.7791** against
`DEPENDENCY_FACTOR_MAX` 2.50. All three are guard rails rather than levers, and none is
what sets any number the player sees — [[defence-model]]'s bill-clamp discipline.

## 8. Where it sits

```
Economy.tick_month()
Budget.tick_month()
Opinion.tick_month()        <- reads LAST month's stock
Demography.tick_month()     <- V1.5b
Society.tick_month()        <- V1.5a
Cabinet.tick_month()
```

Immediately **before** Society, because the quality stock divides by this layer's
dependency factor. Both stay **after** Opinion, which is `society.gd`'s argument
inherited whole: quality feeds an opinion issue, opinion feeds `overall_approval_pct`,
and that is an entry in `legislature_constants.PRECONDITION_FIELDS` — so approval →
which laws are available → a `society` law → migration → shares → quality is a closed
loop, broken structurally by the one-month lag rather than by being careful.

`Demography.init_nation()` runs **before** `Society.init_nation()` in
`game_state.gd`, a second ordering constraint of the same kind as V1.5a's: initialised
after, the start references are 0.0 when the quality equilibrium is captured and every
nation's quality steps on frame one.

`demography.gd` preloads its own constants and **nothing else** — the strictest leaf in
the project, where `society.gd` preloads `cabinet.gd`.

## 9. `SAVE_VERSION` 16 → 17, earned twice and the second half adds no field

| Field | Earns the bump? |
|---|---|
| `young_share`, `old_share` | **YES.** Absent they read 0.0, which is not a neutral default but a **different model** — working share 1.0, dependency ratio 0.0, denominator 0/start, labour force the whole population. `military_capability`'s case at [[defence-model|V1.3g]] and `eu_member`/`neighbours`' at [[trade-model|V1.3b]]. Init-from-content does not rescue them, for `service_quality`'s reason: re-deriving on load erases a drift the player spent a term living through. |
| **`service_quality["pensions"]`** | **YES — and it adds NO FIELD AT ALL**, which is new on this list. A version-16 save carries `{"health": …}` and no `pensions` key. `_tick_nation()` reads `.get(key, 0.0)`, so the stock starts at **zero** and climbs, while `quality_deviation()` measures it against a `start_service_quality` that is also absent and therefore 0.0 — so the deviation reads as a large and growing **positive**. A France whose pension system has just been invented and is improving fast: a windfall the player did not earn, mis-signed for the rest of the run. |
| `start_young_share`, `start_old_share` | No. Recomputed at init from `imported.cohorts`, so they round-trip through `data/nations/` — `start_service_quality`'s case. Serialised regardless. |
| the four content fields | No. They are content. |
| `migration_stance` | No. Absent it reads 0.0 — no standing policy — the truth about every version-16 save, because those games had no migration law to pass. `corruption`'s case one session earlier. Serialised regardless for V1.4b's reason: a law writes it once and no tick recomputes it. |

`tests/test_save_load.gd` asserts both halves **separately**, and that split is the
assertion worth having rather than the bump: it pins that **growing a registry
dictionary can earn a version bump**, which nothing in this project had said out loud
and which V1.5c and V1.5d will each be tempted to do.

## 10. The balance re-run, against a prediction written before it

Not bit-identical — the row books the re-baseline. The prediction was that the **only
universal mover** would be `pensions` joining `QUALITY_KEYS` with a denominator drifting
from month one, that the labour-force change would be **invisible** except where a firm
has moved, and that the bloc transfer would move **nothing**.

**23 of 24 shared regimes are bit-identical in the economics** — GDP, growth, trend,
unemployment, debt and deficit — and the one exception is `managed_subsidises`, which is
exactly the regime the labour-force denominator was predicted to reach. **Zero outcome
changes** across all 24. Approval moves by under a point in 19 regimes, which is the
salience simplex re-weighting around a thirteenth live issue term.

The bloc transfer moved nothing for a reason worth recording, because it is *not* what
the session handoff assumed: `Bloc.net_positions()` reads the **loader's** Nation
objects and is called exactly once, at `game_state.gd:409`. It is never re-ticked, so a
drifting per-nation population cannot reach it. Per-capita transfers are a start-fact by
design, and their own comment says so.

**The nineteenth regime is the cheap kind** — `managed_tightens_migration`, a law
applied at a month, which is a shape the harness has known since `AMENDMENT_REGIMES`.
It is also the legibility evidence, and it is sharper than the headline: under
`managed_corrupts` the result screen's attribution now reads

```
health      salience 0.25  satisfaction -0.53
pensions    salience 0.17  satisfaction -0.42
```

where before V1.5b `pensions` could not appear at all. The screen that exists to say
*why* names the thing the player let happen.

## 11. Where it is read

The **dependency ratio** is on the economy panel, under the population caption it
decomposes: *"43 retired per 100 of working age, +7 since the start."* Not on the
overview beside V1.5a's two delivery lines, and the split is deliberate — a delivery
figure is a fact about the **government**, an age structure is a fact about the
**country**, and that column already reports the country.

The **pensions delivery line** arrives on the overview for free, because
`_fill_services()` already loops `QUALITY_KEYS`. It obeys the same silence rule as
health's, and the screenshot pass confirms both halves: under `--migrate` the overview
reads *"Pensions delivery −0.34 on baseline."* in red while the health line stays
**silent**, which is correct for a game with no `society` law and no health elasticity.

Unlike the two delivery lines, the dependency caption is **never silent** — every nation
has an age structure on frame 1. That is why `tools/screenshot.gd` gained `--migrate`:
the figure it *leads* with is a deviation, and on frame 1 that deviation is exactly 0.0,
so an unflagged capture proves the caption renders and proves nothing about whether the
drift reaches it.

## 12. Why nothing diverges

| Quantity | Bound |
|---|---|
| `young_share`, `old_share` | `[SHARE_MIN, SHARE_MAX]`, plus a pro-rata rescale that holds the working share above its floor **without** breaking the sum to 1.0. |
| `working_share()` | The residual, so it cannot disagree with the two shares by construction. |
| `dependency_factor()` | `[DEPENDENCY_FACTOR_MIN, DEPENDENCY_FACTOR_MAX]`, and it is a **divisor**, so the floor being above zero is what keeps `quality_target()`'s own clamp slack. |
| `migration_stance` | `[−MIGRATION_STANCE_MAX, +MIGRATION_STANCE_MAX]`, clamped on the accumulated value in `Legislature.apply()`. One writer, no tick. |
| `population` | A compound rate bounded at load by `nation.gd`'s `MIN_POP_GROWTH_PCT`, which is what stops a bad import authoring a nation into a negative population — a checklist item that was trivially true while the rate was one shared constant. |

## 13. What is deliberately not built

**A cohort machine.** §2.

**A fertility response.** `data/laws/social.json`'s `childcare_expansion` is the
real-world lever and the model has no response to it. Recorded as a deliberate
non-connection rather than left for the next session to invent.

**A live `BLOC_SIZE.pensioners`.** It is 0.24, authored and static, against a measured
65+ share of 22.15 drifting to ~27 — the same quantity with two writers, which is the
failure this project names most often. It stays authored, and the refusal is recorded
beside `BLOC_SIZE` itself ([[companies-model|V1.4c]]'s precedent for its `ISSUE_KEYS`
no) for three reasons: it is an **electorate** share rather than a population share
(it excludes under-18s), `election_constants.BLOC_TURNOUT` already models the age effect
a second time, and `BLOC_SIZE` is read by `elections.gd` twice, `cabinet.gd`,
`opinion.gd` and `polling_panel.gd` — so making it live would move **election results**,
not just approval, and re-baseline every constant measured at S5, S10, V1.3d, V1.4c and
V1.5a at once. The standing consequence is recorded with it: over fourteen years the
model carries a growing disagreement between how many pensioners the budget serves and
how many vote.

**A health ageing channel.** §7 (T2). The kill switch fired.

**Birth rate and life expectancy as live quantities.** [[v1]] §5 lists them as an orphan
with no data; there is now data, and there is still no mechanism that would read them
that §2 did not cut.

> **RESOLVED AT V2.6c, IN THE REGIONAL REGISTER'S FAVOUR AND NOT THIS FILE'S.** The
> mechanism that reads births and deaths arrived -- per REGION
> (docs/natural-change-model.md), through the live population shares -- and this
> file's national machine is untouched by exactly one fact: `ns.population` was
> already Economy's compound and the natural component was already inside its
> measured `pop_growth_pct`. The national age structure still drifts at its measured
> slope with no cohort machine, and the orphan's real content -- *nothing reads a
> head count* -- died when V2.5 made regions load-bearing and V2.6a made them move.
> What is STILL deliberately not built: a regional age structure (the register's
> dataset publishes the crude rate directly, and importing 22 brackets to author an
> age-mix-to-rate mapping would be the weighted sum §2 refused), and life expectancy
> as a separate live quantity (the death component of the measured natural rate
> already carries it; a second answer to the same question).

---

Related: [[index]] · [[society-model]] · [[companies-model]] · [[economy-model]] ·
[[opinion-model]] · [[legislature-model]] · [[data-sources]] · [[v1]]
