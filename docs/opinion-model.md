---
title: Opinion Model
tags:
  - decision
  - opinion
  - simulation
---

# Opinion Model

The MVP public-opinion model, as built in [[ROADMAP|S5]]. Every formula, every
constant, and the argument for why approval moves fast enough to be worth
watching and slowly enough to be worth planning around.

Same standard as [[economy-model]]: this is a **game model**, judged on whether
the player's decisions produce legible, delayed, reversible political
consequences — not on whether it would survive a political scientist. Where
realism and legibility conflict, legibility wins, and the trade is noted.

## Where it sits

```
clock.month_elapsed
  → Economy.tick_month(state)      GDP, sectors, unemployment, population
  → Budget.tick_month(state)       revenue, spending, deficit, debt
  → Opinion.tick_month(state)      satisfaction, salience, approval
  → state.append_history()
```

Opinion runs **last**, on purpose. It reads figures that have already settled
this month; wired anywhere earlier, approval would react to last month's economy
and every response would carry a spurious extra month of lag.

Like `Budget.tick_month`, it is gated on `has_budget` rather than on the player
id — the nine AI nations have no reader for approval at MVP. Initialisation runs
for all ten so the state shape stays uniform.

> [!important] No randomness here either
> [[economy-model]]'s determinism rule extends to this file. `Opinion` never
> calls an RNG, and the model never stores a noisy number. Polling noise is
> applied at the moment a figure is rendered — see [Polling noise](#polling-noise)
> below. `tests/test_budget.gd` asserts the budget projection equals what
> subsequently happens to 1e-9, and a single `randf()` in a tick would break it.

## Where the blocs live

`src/sim/opinion_constants.gd`, as typed GDScript `const`s. **Not** in `data/`,
and this is a deliberate departure from the `voter_blocs` nation-schema field
[[data-architecture]] originally pencilled in for this session.

The argument used to be `policy_defaults.json`'s, one step further: only France
was playable, so nine authored bloc sets would have had no reader. Unlike
starting tax rates, blocs are still not content a designer adds more of:
regional and generational breakdown is [[someday]] tier, so six blocs is one
fixed set, forever — [[economy-model|the same definition]] used to keep the
economy's constants out of `data/`.

> [!note] The trigger fired at V1.2a, and the call was re-examined, not skipped
> "A second playable nation" was the named trigger. [[ROADMAP|V1.2a]] made
> Germany playable and the plan step re-opened this exact question, with a
> measurement instead of a restated assumption: `tools/balance_probe.gd`,
> parameterised by nation, ran the same relative "managed" budget against
> France and Germany. Germany's government lost its majority at its February
> 2029 legislative election; France held one through every election of the
> full fourteen-year run. Institutions
> (`chancellor_election`/`constructive_absolute` vs
> `presidential_appointment`/`absolute_members`, a 5% `pr_national` threshold
> vs `two_round`'s 0%) and party rosters alone already produce that divergence,
> with the bloc table completely untouched. Per-nation salience is still
> unsourced — roughly 660 numbers with nothing to author them from — and every
> tuned constant in this file (`SALIENCE_GAIN`, `DEFICIT_SCALE_PP`, the whole
> `public_finances` row) was measured against this one shared table; per-nation
> tables would mean ten measurements or nine assertions. Bloc weights stayed
> global. Recorded, with the measurement, in [[declined]].

**What would reopen this again:** per-nation bloc *size* (`BLOC_SIZE`)
acquiring a real source — World Bank/Eurostat splits for urban share, 65+
share, tertiary enrolment exist and could source that one table without
inventing salience. Full salience staying global is a standing decision, not a
parked one; see [[declined]] for what evidence would move it.

Two rules make that move cheap, and both are just [[engine-decision|Rule 1]]
applied:

1. **Bloc names appear in `opinion_constants.gd` and nowhere else.** `opinion.gd`,
   the polling panel and every test iterate `BLOC_KEYS`.
2. **`ns.has_budget` gates the tick, never `id == player_nation_id`.**

So the expensive version of this decision — an "exactly six blocs, named these"
assumption smeared across S6 vote share, S7 law effects, S9 saves and the UI —
never gets made. The cheap version, a table moving file, stays cheap.

## Blocs

A partition of the electorate by dominant identity. Sizes sum to 1.0, which is
what makes the headline an average rather than an arbitrary index.

| Bloc | Size |
|---|---|
| workers | 0.30 |
| pensioners | 0.24 |
| urban | 0.15 |
| rural | 0.13 |
| business | 0.10 |
| students | 0.08 |

The overlap is acknowledged rather than modelled: a worker also lives in a city.
Six mutually exclusive segments, each keyed on the identity that dominates how
that person votes, is the legible choice, and it is what makes the roll-up
honest. Cross-cutting membership is [[someday]] tier along with regional opinion.

## Issues

Twelve, each a satisfaction `s ∈ [−1, +1]`, each computed from state the economy
and budget already maintain.

| Issue | Formula | Scale |
|---|---|---|
| `jobs` | `(start_u − u) / JOBS_SCALE` | 3.0 pp of unemployment |
| `growth` | `(growth − trend) / GROWTH_SCALE` | 4.0 pp of growth |
| `tax_income` | `−Δrate / TAX_SCALE` | 8.0 pp of the rate |
| `tax_corporate` | " | " |
| `tax_vat` | " | " |
| `health` | `Δspend / SPEND_SCALE` | 3.0 pp of GDP |
| `education` | " | " |
| `defence` | " | " |
| `pensions` | " | " |
| `infrastructure` | " | " |
| `public_finances` | `−Δdeficit / DEFICIT_SCALE` | 6.0 pp of GDP |
| `europe` | `−Δbloc_burden / EUROPE_SCALE` | 0.80 of the burden |

All clamped to [−1, +1] after scaling.

**Every delta is against the nation's own starting value** — `start_unemployment_pct`,
`start_tax_rates_pct`, `start_spending_pct_gdp`, `start_deficit_pct_gdp`. So at
new-game every satisfaction is exactly zero, every bloc sits at neutral, and the
model needs no calibration constant. That is the same trick the economy's
`potential_shift` uses, and it means France's real 4.7 %-of-GDP starting deficit
is politically free until the player moves it — which is right. Voters price
changes, not levels.

`public_finances` is measured on the **deficit**, not on the debt ratio. Debt
walks upward every month by construction — [[economy-model|r exceeds g]] — so a
debt-level term would make every bloc slowly unhappy no matter what the player
did, which is a drift, not a mechanic.

`growth` uses growth *relative to trend* rather than absolute growth, so a nation
with a structurally low trend is not permanently unpopular for it.

`europe` is [[ROADMAP|V1.3d]]'s, and the only issue here whose scale is not a
quantity in percentage points — [[bloc-model|bloc burden]] is already a
normalised score. It is measured against `start_bloc_burden` like every other
term is measured against a start, so France beginning in real breach of a deficit
rule is politically free until the player moves it.

> [!important] `europe` is ONE-SIGNED, and that is a property of this model
> Nothing in `_tick_nation()` lets a bloc weight an issue negatively, so every
> satisfaction reaches all six blocs with the same sign. Blocs differ in how much
> they care, never in which way they move. The tax split in *What it does* below
> is not one issue signing two ways — it is `tax_income` falling while
> `public_finances` rises.
>
> That constrained V1.3d's design rather than being noticed afterwards: Europe
> had to be a sovereignty issue everyone dislikes, and the political division had
> to come from the table below. It does. Pensioners and rural carry **no
> `growth` entry at all**, so they take the constraint and none of the single
> market's upside, while business weights `growth` 0.19 and `public_finances`
> 0.34 and takes both. See [[bloc-model]].

## Salience

Each bloc has a sparse base weight vector. An issue a bloc has no entry for
carries no weight for that bloc, which is precisely what makes "fixing something
nobody cares about buys nothing" true rather than decorative.

| Bloc | Base weights |
|---|---|
| workers | jobs 0.34 · public_finances 0.18 · tax_income 0.15 · health 0.10 · tax_vat 0.08 · growth 0.08 · pensions 0.07 |
| pensioners | pensions 0.38 · health 0.21 · public_finances 0.20 · jobs 0.13 · tax_vat 0.08 |
| urban | health 0.19 · jobs 0.18 · public_finances 0.17 · education 0.14 · infrastructure 0.11 · tax_income 0.11 · growth 0.10 |
| rural | infrastructure 0.20 · public_finances 0.18 · jobs 0.16 · health 0.13 · defence 0.12 · tax_vat 0.11 · pensions 0.10 |
| business | public_finances 0.34 · tax_corporate 0.25 · growth 0.19 · infrastructure 0.09 · jobs 0.07 · education 0.06 |
| students | education 0.38 · jobs 0.22 · public_finances 0.14 · tax_vat 0.10 · growth 0.08 · health 0.08 |

[[ROADMAP|V1.3d]] added a `europe` entry to every row — workers 0.10, pensioners
0.10, urban 0.06, rural 0.14, business 0.06, students 0.05 — so the rows no
longer sum to 1.0 and `salience_weights()`'s renormalisation now does real work
at rest. What that cost the eleven measured issues was the first thing V1.3d
measured rather than the last: every existing weight is scaled by `1/(1+w)`, and
the ratio S10's finding was about moves by **+0.39 %**, in the safe direction.
`europe` takes 0.083 of the national agenda, fifth of the twelve. Six rows rather
than the two or three that would read as natural is forced by the finding in
[[diplomacy-model]]: a price hitting fewer than all six blocs never clears the
poll-noise floor in `overall_approval_pct`. See [[bloc-model]].

Three properties are load-bearing rather than incidental:

- **Pensioners weight pensions far above anything else and students at nothing.**
  The S5 done-when condition about a pension cut is therefore a property of this
  table, not of code.
- **`jobs` is the most-weighted issue overall.** [[economy-model]] gives
  unemployment the honest textbook treatment — Okun plus reversion to a structural
  rate — specifically so that bloc reactions to it feel earned. Leaning on it
  hardest is the payoff.
- **`public_finances` is second, at about 0.20 of the national agenda.** The
  [[ROADMAP|S10]] pass roughly doubled this row from its S5 weights; the argument
  is in the callout below. It is worth noting how *surgical* that change is: a
  player who never touches the budget sits at a `public_finances` satisfaction of
  about zero and is untouched by it. The row bites only once the player moves the
  deficit, in whichever direction — which is exactly when it should.

### Salience moves with the news

Static weights would make "issue salience" a synonym for "weight". Bad news
raises how much an issue is worth arguing about:

```
severity_i = clampf(−s_i, 0.0, 1.0)                 # only bad news counts
w_b[i]     = base_b[i] × (1 + SALIENCE_GAIN × severity_i)
w_b        = w_b / Σ w_b
```

`SALIENCE_GAIN = 5.0` — a fully bad issue counts six times before
renormalisation.

The renormalisation is the entire stability argument: the result is a point on
the simplex, so no amount of bad news can make the weights grow. It also means
salience is genuinely zero-sum, which is the behaviour worth having — a crisis in
one place crowds attention out of another.

> [!important] The gain was 1.0 until S10, and that made the game unloseable
> This constant does far more work than its S5 description suggested, and the
> [[ROADMAP|S10]] balance pass found it doing none of it. Three separate
> failures traced back here and to the `public_finances` weights beside it:
>
> **Fiscal discipline was strictly dominated.** `public_finances` carried about
> 0.10 of the national agenda against roughly 0.50 for the five spending lines.
> A budget with every line maxed and every tax at zero ran a deficit of 112 % of
> GDP, walked debt to 1346 % of GDP, and still held approval at 57 and won three
> consecutive elections — while an austerity budget running a surplus lost. There
> was no reason to ever open the budget screen except to spend more.
>
> **Saturation made the model non-monotone.** Satisfaction is clamped to
> [−1, +1], so once a deficit has pinned `public_finances` at −1 it cannot get
> worse, and every further giveaway is free upside. Maxing spending *and* zeroing
> taxes was more popular than either half alone: the second half added three
> saturated positives against a negative already on the floor. Widening
> `DEFICIT_SCALE` cannot fix this — no scale distinguishes −18 pp from −85 pp
> once both clamp — but the gain can, because it multiplies weight by severity
> rather than adding to score. The flip point for that budget sits between 4.0
> and 4.5.
>
> **Losing was unattributable.** The result screen names the most-salient issues
> at the moment of the vote. At a low gain it named whatever the base table said,
> regardless of what the player had actually broken, so every defeat read the
> same. At 5.0 each failure mode is blamed on the number that caused it:
> profligacy on `public_finances`, austerity on `health` and `pensions`, a tax
> squeeze on `jobs` and the tax lines.
>
> `tools/balance_probe.gd` is the harness that found all three;
> `tests/test_balance.gd` is the subset that now fails if they come back.

The size-weighted average of the per-bloc weights is stored as
`issue_salience` and is what the polling panel's "what the country is thinking
about" list reads. It sums to 1.0 by construction, which
`tests/test_opinion.gd` asserts every month for ten years.

## Approval

```
target_b    = NEUTRAL + SPAN × Σ_i w_b[i] × s_i
approval_b += (target_b − approval_b) × INERTIA_RATE
approval_b  = clampf(approval_b, 0, 100)
overall     = Σ_b size_b × approval_b
```

| Constant | Value | Why |
|---|---|---|
| `APPROVAL_NEUTRAL` | 50.0 | Where everyone starts and where a bloc with nothing to complain about sits. No honeymoon bonus — time in office as its own drag is [[v1]]. |
| `APPROVAL_SPAN` | 40.0 | Satisfaction is bounded to [−1, +1], so target approval lives in [10, 90]. The hard 0–100 clamp is a guard rail that never binds under sane play. |
| `INERTIA_RATE` | 0.25 /month | Half-life ≈ 2.4 months. |

### On inertia, and why it is fast

The obvious reading of "opinion inertia so nothing swings on a single month" is
*make it slow*. That is the trap, and it is worth stating why.

Opinion sits downstream of an economy that already lags. Unemployment responds to
growth through Okun at 1/12 per month and reverts to structural over roughly three
years. Put a slow inertia term on top and there are **two lags in series on the
game's most important channel** — the player changes the budget, waits a year for
unemployment to move, then waits again for anyone to notice. The game stops
answering, and no amount of feedback in the UI fixes a model that is not
responding.

So 0.25 is chosen so that opinion is deliberately *not* the bottleneck:

- On a **spending change**, the issue moves instantly — it is a delta against a
  starting value, with no economy in between — so inertia is the only lag, and
  roughly 58 % of the response lands within three months.
- On **unemployment**, the economy's lag dominates and inertia adds almost
  nothing on top of it.

Which is the right split: the player feels a pension cut quickly, because
pensioners feel it quickly, and feels a jobs crisis on the economy's schedule,
because that is how long a jobs crisis takes.

`tests/test_opinion.gd` checks the combined response rather than the model's own
half-life, which is the only number that matters.

## What it does

Selected paths, from the model as committed. France, default budget, starting
approval 50 everywhere.

| Scenario | What happens |
|---|---|
| **Do nothing** | Everyone holds near 50 for a decade; business drifts to 49 as debt service widens the deficit. A do-nothing game is not punished, and is not rewarded either. |
| **Pensions 14.5 → 11.5 % of GDP** | Pensioners 50 → 37.9 within three months, settling near 29. Students move 0.9 points. Business *gains*, to 60 — the deficit halved. |
| **Defence and infrastructure cut by 5 pp** | Unemployment 7.4 → 8.3 %. Rural collapses to 33 (infrastructure is their top issue), workers trough at 46 with no policy aimed at them at all, pensioners rise to 54 on the improved deficit. |
| **Income tax 20 → 30 %** | Workers 50 → 37, business to 57. The cleanest left-right split the model produces. |
| **Every spending line +3 pp** | Overall approval peaks at 66 after a year, then decays to 57 by year five as the boom unwinds and business falls to 38. |

The pattern worth noticing is that **no scenario moves every bloc the same way**.
That is the model earning its keep: there is no lever that is simply good, so
S6's election is a question of which coalition you built rather than how high you
pushed one number.

> [!note] A known soft spot, for [[ROADMAP|S10]]
> The last row is still a real approval win for a budget that takes debt from
> 116 % to roughly 215 % of GDP over five years. Every bloc now weights
> `public_finances` — that change alone took the peak from 73 down to 66 — but a
> blowout remains popular inside a single term, and the punishment arrives
> through debt service crowding out spending over the following one. Whether that
> is a flaw or the correct politics of deficit spending is a balance question,
> and it needs the S6 checkpoint playtest to answer rather than another
> pre-emptive constant.

## Polling noise

Approval is not published. The player sees a poll.

`src/ui/poll_noise.gd`, in `src/ui/` because it is a presentation concern and
nothing in `src/sim/` references it.

```
poll_id = year × 12 + month
shown   = clampf(true_value + (u(poll_id, key) × 2 − 1) × NOISE_MAX_PCT, 0, 100)
```

`NOISE_MAX_PCT = 3.0`, uniform, therefore unbiased over many polls.

The interesting constraint is that this cannot be `randf()`. The simulation
contains no randomness at all, so the noise is a **pure function of the poll and
what is being asked about**. Three things follow, all of them wanted:

- The panel shows the same figures on every repaint within a month. A poll is a
  published figure, not a fresh sample every frame — and the numbers do not
  flicker while a slider is being dragged.
- The figures survive a save and reload, because there is no RNG state to
  serialise. [[ROADMAP|S9]] gets this for free.
- `tests/test_budget.gd`'s projection-equals-reality guarantee is untouched.

`u()` is FNV-1a over the key mixed through splitmix32's finaliser, written out
rather than delegated to Godot's `hash()`, so the published figures do not depend
on an engine-internal detail that a save file would then be pinned to.

`tests/test_polling_panel.gd` checks the four properties that matter over 120
polls: bounded, varies between polls, deterministic on repeat calls, and centred
on zero.

## Why nothing diverges

Shorter than [[economy-model]]'s equivalent section, because there is less to
argue about.

| Quantity | Bound |
|---|---|
| Issue satisfaction | Clamped to [−1, +1] by construction. |
| Salience weights | Renormalised to sum to 1.0 every month. A simplex cannot grow. |
| Target approval | `NEUTRAL ± SPAN × 1` — [10, 90], since the weighted satisfaction is a convex combination of terms in [−1, +1]. |
| Bloc approval | First-order lag toward a bounded target, plus a hard [0, 100] clamp that never binds. |
| Overall approval | A convex combination of bounded values. |

There is **no term where approval feeds back into itself or into the economy**.
Opinion is a pure read of the simulation this month; it never writes to the
economy or the budget. That is what keeps the stability argument this short, and
it is a property worth defending — [[ROADMAP|S6]] elections consume approval, and
[[ROADMAP|S7]] laws will write to the economy, but neither should let approval
drive an economic variable directly.

The argument is not the evidence. `tests/test_opinion.gd` runs 120 months under
five budgets including the absurd ones and asserts finiteness, bounds and the
salience invariant on every bloc every month. **That** is the evidence.

## Where the constants live

`src/sim/opinion_constants.gd`, all of them, next to
`src/sim/economy_constants.gd` and for the same reason: [[ROADMAP|S10]]'s balance
pass gets one file per model, and `opinion.gd` and the polling panel cannot drift
apart.

The one number that is *not* there is `NOISE_MAX_PCT`, which lives with the noise
function in `src/ui/poll_noise.gd`. It is not a model parameter — the model does
not know polls exist.

---

Related: [[index]] · [[economy-model]] · [[data-architecture]] · [[engine-decision]] · [[mvp]] · [[ROADMAP]] · [[mechanics-society]]

## The thirteenth issue

`inflation` joined `ISSUE_KEYS` at [[ROADMAP|V1.6b]], and it is the **first yes** to a
question five sessions answered no — V1.3d (`europe`, yes), then V1.4c (`ownership`),
V1.5a (`corruption`), V1.5c (`unrest`) and V1.5d (`framing`), all no.
`src/sim/opinion_constants.gd` carries all six answers together, which is the point:
a reader finds the reasons rather than the silence.

What made this one different, in one line each:

- It ships **no verb and no content object**, so unlike every previous candidate there
  is no authored `bloc_offset` anywhere it could be priced on instead.
- It **must be able to become more salient**, and a flat bloc-level load structurally
  cannot — `SALIENCE_GAIN`'s whole justification is that bad news crowds out the
  agenda, and inflation is the canonical issue that becomes the only issue.
- It is **not collinear**, measured against the model's own accepted standard rather
  than a band: `|corr(inflation, growth)|` is 0.2276 against `|corr(jobs, growth)|`'s
  0.3185. The lag and the opposite sign are what save it.

It is also the first pair of issues here that **one event moves in opposite
directions** — a boom is a plus on `growth` and a minus on `inflation`. That does not
break the one-signed property this document describes: inflation still reaches all six
blocs with the same sign. It is a second issue with the other sign.

Full argument and every measurement: [[inflation-model]] §6.

## V3.0 — the game answers: honeymoon and fatigue, and the fiscal re-weight

The 2026-09-05 second playtest (reports/, gitignored) verified the V2.9 seat
live and left the agency problem as the tier's first row. The V2.9b probe's
four findings are the band inputs; this section records what moved and what
was measured and refused.

**Honeymoon and fatigue** — the deferral this file carried since S5
(`APPROVAL_NEUTRAL`'s old comment: *"No honeymoon bonus — time in office as
its own drag is V1"*) is discharged as a pure read of
`Elections.months_in_term`, which has counted the mandate since V1.2 under
the same `has_budget` + `in_government` gate Opinion ticks under, reset at
every executive resolution, and serialised since V1.8. **No new field, no
`SAVE_VERSION` move** — the missing piece was always a read, never a
register. The offset enters every bloc's target (uniform, like
`unrest_opinion_load`):

```
offset(m) = HONEYMOON_MAX * (1 - 0.5^(m/RISE)) * 0.5^(m/HALF_LIFE)
            - min(FATIGUE_MAX, FATIGUE_PER_YEAR * m / 12)
```

with 6.0 / 1.0 / 4.0 / 1.2 → 0.9 / 6.0. `offset(0)` is **exactly 0.0 on
purpose**: `test_opinion` and `test_scenario` pin the init figure, and a +6
day-one figure would have broken both pins and the scenario override's
equilibrium inversion with them. The first shape tried — offset(0) = +6,
decay only — was rejected on those pins before it ran; the pulse-then-drift
shape delivers the same play (approval climbing over a mandate's first
months, sagging in the second term) at zero re-baseline. The one-month lag
(Elections increments `months_in_term` after Opinion reads it) is absorbed
by the band, not corrected.

`FATIGUE_PER_YEAR` was declared at 1.2 and **failed its own constraint**:
at −6 by year five the do-nothing France run lost its 2031 re-election and
the gas regime lost its build cadence — `test_balance` caught both. Swept to
0.9 (fatigue caps at −6 only in a third term). The fatigue is deliberately
mandate-wide rather than activity-keyed: V3.0 takes no position on whether
idleness should cost more than governing badly (see the agency probe's
verdict, reports/agency-probe-v3.0.md).

**The fiscal re-weight** — V2.9b F1's lever. `TAX_SCALE_PP_BY_KEY` gains
`"income": 24.0` (pain per point of income tax falls 3×), the shared
`TAX_SCALE_PP` goes 8 → 16, `SPEND_SCALE_PP` 3 → 6. `DEFICIT_SCALE_PP`
**stays 6.0**: at 3.0 the spend-led style's deficit sits ON the −1 clamp and
its month-6 delta crashes to −13. The result: the best fiscal stance the
probe can construct (the pre-declared `budget-smart`: defence −1.5,
infrastructure −0.5, income +4) moves month-6 approval to **−2.00 against
idle, from −7.57**. The band's +1.0 upper edge is a **measured bound**, not
a refused obligation — every lever exhausted, the residual is the Okun cost
of the cuts plus the surviving income pain. The full argument is the probe
report; `test_tax`'s units check was re-pinned deliberately (income carries
its own scale now, and the test asserts it stays WEAKER than the shared
constant, which is the direction the sweep shipped).

**Grievance relief** — V2.9b F2's fix lives in [[unrest-model]] §"V3.0".
