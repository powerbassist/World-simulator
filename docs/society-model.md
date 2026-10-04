---
title: Society Model
tags:
  - decision
  - sim
  - balance
---

# Society Model

The delivery layer, as built at [[ROADMAP|V1.5a]] — the first session of the V1.5
block. A service's quality as a stock converging on sustained spending, and
corruption as the factor that decides how much of that spending arrives.

Same standard as [[companies-model]], [[defence-model]] and [[bloc-model]]: a **game
model**, judged on whether the player's decisions produce a legible, attributable
political outcome. Where realism and legibility conflict, legibility wins, and the
trade is noted.

## 1. The row asked for a machine the project had already built three times

[[v1]] §5's ninth bullet reads *"healthcare and education quality as outcomes of
spending, feeding back into opinion."* Counted cold, of the five spending lines
**three already carry an outcome stock**, each under a different name:

| Line | Existing stock | Since |
|---|---|---|
| `defence` | `military_capability` | [[defence-model|V1.3g]] |
| `education` | `potential_shift_pct`, via `EDU_BETA` | S4 |
| `infrastructure` | `potential_shift_pct`, via `INFRA_BETA` | S4 |
| `health` | — | **V1.5a** |
| `pensions` | `service_quality`, given a denominator | **V1.5b** |

So V1.5a **completes and names a pattern rather than inventing one**, and
`src/sim/society.gd` lifts `capability_target()` / `capability_step()` from
`defence.gd` outright — including its call that a starting stock is its
**equilibrium and not zero**. A France that has spent 11.0 % of GDP on health for
decades has hospitals on the day the game starts.

`education` is excluded **forever**, and `society_constants.QUALITY_KEYS` is the
place that refusal lives rather than a doc: a second stock on the same input is
[[companies-model|V1.4b]]'s collision in a new place. `pensions` was excluded
**temporarily** — adequacy is spend per *dependent*, and the dependent count is
V1.5b's. `tests/test_society.gd` reads the list and fails if any of the three
permanent exclusions appears in it.

> [!note] The temporary exclusion is DISCHARGED, and it cost one entry
> [[demography-model|V1.5b]] shipped the dependency ratio, and `pensions` joined
> `QUALITY_KEYS` exactly as the paragraph above said it would — *"It joins by becoming
> an entry"* — for **one entry here and zero lines in `opinion.gd`**, which is what
> the registry was for. What it was waiting on was the denominator:
> `Society.quality_target()` now divides by `Demography.dependency_factor()`, so the
> same spending rate buys less pension as the country ages. §13's *"Pension adequacy.
> Needs a dependent count, which is V1.5b's"* is discharged with it.
>
> The same session found that a `health` ageing elasticity **cannot clear the readable
> floor at any value** — −0.51 on its widest bloc row even at 1.0 — so the entry was
> deleted and `DEPENDENCY_ELASTICITY` ships with one. See [[demography-model]] §7.

## 2. Two fields, three writers, and no new kind of state

`service_quality` and `start_service_quality` are per-spending-line dictionaries on
`NationState`; `corruption` is a signed scalar. The single-writer discipline
[[companies-model]] §11 established holds and extends:

| Quantity | Sole writer |
|---|---|
| `share` | a subsidy, `Companies.execute()` |
| `state_share` | an ownership op, `Companies.execute()` |
| `regulation_burden` | a law, `Legislature.apply()` |
| **`corruption`** | **a law, `Legislature.apply()`** |
| **`service_quality`** | **`Society.tick_month()`** |

`tests/test_society.gd` reads `society.gd` and fails if the file contains a write to
`ns.corruption` — the read-the-file idiom [[people-model]] and [[calendar-model]]
both use for a property no runtime check expresses.

## 3. `effects.society` is the sixth channel, and V1.5 owns it

`data/company-actions/` served three sessions and `data/diplomatic-actions/` served
five. `effects.society` is the same bet one block later: V1.5c's unrest and V1.5d's
press freedom reach it through here, so it is schema two later sessions read rather
than one session's private field.

A law names **one** term, `corruption`, and `law.gd`'s `_extract_society()` refuses
anything else. The refusal is the design, exactly as `_extract_company()`'s refusal
of a firm id was: `service_quality` has one writer, and a law that could set a
quality level directly would be a second — as well as bypassing the stock, which is
the one thing here that makes the consequence lag the decision.

There is **no sixth law theme**. `institutional` already existed and
`anti_corruption_agency` was already using it.

### The anti-double-count, made mechanical for the second time

`law.gd` refuses a law carrying both `effects.society` and `effects.spending_pct_gdp`,
beside V1.4b's refusal of `company` + `structural_unemployment_pct`. Same act, same
landing site, same units — and the more insidious half is that the two can be given
**opposite signs**, so a law could buy approval on a service while quietly degrading
it and the ledger would net them to nothing.

## 4. Corruption multiplies the STOCK, not the delta

§5's bullet says corruption degrades *"policy effectiveness"*, which names
`Cabinet.effectiveness()`. Placed there it would cost a do-nothing player **exactly
zero**, because that function multiplies the spending **delta** only — deliberately,
and `opinion.gd`'s own comment says so: *"A player who never touches this spending
line is untouched by the whole cabinet system."* The obvious implementation is free
to precisely the player most likely to deserve it.

So corruption multiplies the stock's **target**: a corrupt state's hospitals decay at
unchanged spending. `tests/test_society.gd` asserts it with the spending line never
written, and that omission is the whole test.

**Signed both ways**, which is V1.4b's deregulation argument plus one V1.4b did not
need. Updated at V4.2, when the repeal verb landed: repeal removes whole acts rather
than nudging a stance back, so `[0, MAX]` would still be the permanent monotone
charge [[defence-model]] names — *and* an anti-corruption law would be **inert on a
clean state**, breaking [[foreign-policy-model|V1.3f]]'s property that nothing on the
law list does nothing. Negative corruption is a
cleaner-than-baseline administration and raises delivery above 1.0.

## 5. The double count, and the three resolutions that were rejected

`health` was **already** an opinion issue, keyed to the spending delta ×
effectiveness. A quality stock on the same input is a second monotone function of the
same number. Four resolutions; three fail on this project's own written record.

| | Rejected because |
|---|---|
| **Replace** | `opinion_constants.gd` commits explicitly to no lag and warns against *"two lags in series"*; a stock at `QUALITY_CONVERGENCE` has a ~34-month half-life. Replacing builds the thing that comment exists to forbid. |
| **Multiply** | That is `Cabinet.effectiveness()` a second time on one expression. Two multipliers on one delta are unattributable — the player cannot tell an incompetent minister from a decayed service, and `elections.gd`'s attribution has one slot per issue. |
| **A 13th `ISSUE_KEYS` entry** | `spending.health` writes both keys, so they are collinear and the salience simplex merely re-splits one issue's weight. §8. |

**Additive and post-effectiveness** ships — `deployment_opinion_load`'s shape, and
the argument transfers verbatim: the delta is a claim about how well a *change of
policy* is delivered, quality is a **fact on the ground**, so running it through
effectiveness would let a competent minister cancel the price. The two then price
**different times** rather than the same thing twice: the delta prices the
announcement, the stock prices the delivery. Fast in, slow out.

## 6. Where it sits

```
Economy.tick_month()
Budget.tick_month()
Opinion.tick_month()        <- reads LAST month's stock
Companies.tick_month()
Society.tick_month()        <- V1.5a
Cabinet.tick_month()
```

**After Opinion, not before it.** The first draft of `society.gd`'s own comment said
"before Opinion", on the general tick-order argument that opinion should react to
figures that have already settled. That is the wrong argument here and Companies'
comment has the right one: quality feeds `health` satisfaction, which feeds
`overall_approval_pct`, which **is** an entry in
`legislature_constants.PRECONDITION_FIELDS` — so quality → approval → which laws are
available → a `society` law → corruption → quality is a closed loop, and the
one-month lag breaks it structurally rather than by being careful. A stock with a
~34-month half-life is indifferent to the lag; the loop is not. Fifth time that
argument has been made, and the first where the loop runs through opinion rather than
through the deficit.

## 7. The probe corrected itself three times, and thirteen sessions running

`tools/society_probe.gd`. Bands **and** tiebreakers were fixed before the sweep — the
[[companies-model|V1.4c]] lesson, which is that a band can pass three rows and choose
nothing. The finding is that **naming a tiebreaker in advance is still not enough**.

### (b) `QUALITY_CONVERGENCE` — the only pair that worked as designed

Band: at a sustained +1.0 pt spending change, cover 40–90 % of the distance inside one
60-month term. Tiebreaker: nearest `CAPABILITY_CONVERGENCE = 0.02`.

| rate | term % | 168 mo % | band | ratio |
|---|---|---|---|---|
| 0.010 | 45.3 | 81.5 | PASS | 0.50 |
| **0.020** | **70.2** | **96.6** | **PASS** | **1.00** |
| 0.040 | 91.4 | 99.9 | fail | 2.00 |
| 0.080 | 99.3 | 100.0 | fail | 4.00 |

Two rows pass, so the band chose nothing — and the tiebreaker chose **0.02** outright,
at a ratio of exactly 1.00. This is the constant the discipline was written for.

### (c) `QUALITY_SCALE_PP` — the band was measured on a path that could not observe it

Original band: the quality channel **alone** moves the headline past ±3.0, measured
through a +1.0 pt spending increase. It failed at every candidate — and the failure is
a defect in the band, not a finding about the model: **raising a spending line
necessarily widens the deficit**, so "the quality channel alone" was never observable
on that path. [[foreign-policy-model|V1.3f]]'s measuring-the-wrong-state error, in the
probe written to avoid it, the third session running.

The headline came back **−0.70 for a spending INCREASE**, because the line widens the
deficit by 1.00 pt and `public_finances` is weighted heavily by the blocs that weight
`health` lightly. That is [[defence-model|V1.3g]]'s finding from the other side.

On the **isolated** path — the stock moved with every spending line untouched, so every
other issue is bit-identical between the runs:

| scale | headline | band | ratio vs `SPEND_SCALE_PP` |
|---|---|---|---|
| 3.0 | −8.27 | PASS | 1.00 |
| **4.5** | **−5.51** | **PASS** | **1.50** |
| 6.0 | −4.14 | PASS | 2.00 |
| 9.0 | −2.76 | fail | 3.00 |
| 12.0 | −2.07 | fail | 4.00 |

No candidate saturates `_scaled()`'s clamp, which the probe **measured** rather than
assumed — that was the objection to an earlier version of this sweep, which rescaled a
single run by `shipped / candidate` and was therefore only valid if the answer was
already known.

**And the pre-committed tiebreaker was a test that could not fail.** It said: if the
two terms summed exceed what `SPEND_SCALE_PP` produced alone, re-measure
`SPEND_SCALE_PP` down. Any positive stock term adds to the total, so it fires for
every candidate — [[foreign-policy-model|V1.3e]]'s own criticism of its split trigger,
in a new place.

What replaced it: **the delivery half must be worth less than the announcement half**,
because an announcement is certain and immediate where delivery is contingent and
lagged. That is ratio > 1.0, and the smallest passing value satisfying it ships. The
rule chose **4.5** where the constant had been provisionally set to 6.0, which is the
evidence it was not written backwards from a number already picked.

`SPEND_SCALE_PP` is **not** re-measured: doing so would re-baseline all five spending
issues to correct a change that reaches one, and S10's measurement of it stays valid
for the four lines with no stock.

### (d) `CORRUPTION_DELIVERY_BETA` — the kill switch cleared, and the tiebreaker was a bound

Band: a saturated register moves the headline past ±3.0, else the constant is
**deleted**. It cleared at every candidate — −4.55 at 0.10, −6.34 at 0.20, −8.32 at
0.30, −12.72 at 0.50.

**Which means the pre-committed tiebreaker was a bound and not a selector.** Every
candidate satisfies `beta × MAX ≤ 0.50`. V1.4c's failure repeating inside the session
written to avoid it, and the sharpest thing this probe found: a tiebreaker can be
pre-committed **and still not select**.

The selector that resolved it has two parts, both criteria this session had already
established:

| beta | delivery | headline | widest bloc | clamp | verdict |
|---|---|---|---|---|---|
| 0.10 | 0.960 | −1.24 | −1.88 | slack | fail |
| 0.20 | 0.920 | −1.69 | −2.55 | slack | fail |
| **0.30** | **0.880** | **−2.19** | **−3.29** | **slack** | **PASS** |
| 0.50 | 0.800 | −3.32 | −4.94 | **BINDS** | fail |

(i) **one law's** corruption must be legible on a **bloc row** — not on the headline,
which table (c) had just shown a single spending issue cannot reliably carry; and
(ii) the saturated value must leave `DELIVERY_MIN` strictly slack, since 0.50 pins it
at exactly 0.500, the clamp-sets-the-number failure this project has now named five
times. **Exactly one row passes both.**

An earlier version of (i) asked for the headline and chose 0.50, on the mistaken
premise that a saturated register was unreachable in play. It is not:
`emergency_procurement_powers` is repeatable on a 48-month cooldown, so three passes
inside fourteen years reach the clamp.

### (e) Both clamps are slack, and so is the stock's

0.700 against `DELIVERY_MIN` 0.500; 1.300 against `DELIVERY_MAX` 1.500; and the
roster's largest authored line in `QUALITY_KEYS` is FRA's health at 11.00 against
`QUALITY_MAX` 30.0. `DELIVERY_MIN` is held at `VACANT_EFFECTIVENESS` and may not go
under it — a factor degrading delivery further than an **empty ministry** claims
corruption is worse than having no minister at all.

## 8. The `ISSUE_KEYS` question is answered NO, on test 4 and without a sweep

V1.3d's four tests, which answered **yes** for `europe` and which V1.4c re-ran and
answered **no** for ownership.

| | |
|---|---|
| (1) nameable by the polling panel / attribution? | **yes** — priced through the `health` issue, which both surfaces already carry |
| (2) clears the ±3.0 headline floor alone? | **yes** — −8.32 on the isolated channel |
| (3) can it become more salient? | **yes** — a negative satisfaction is what `SALIENCE_GAIN` amplifies |
| (4) mechanic and cost the same number? | **FAILS** |

`spending.health` and `corruption` both write the **same issue**, so a thirteenth key
would be **collinear** with a key that exists: the simplex would re-split one issue's
weight between two names for one quantity, and no value of a new
`BLOC_SALIENCE_BASE` row turns two names into two quantities.

The S10 ratio was **not** swept, deliberately. V1.3d and V1.4c each swept it because
tests 1–4 were genuinely in tension and the drift decided; here the answer is settled
before the drift is relevant, and sweeping to choose between a yes and a no already
decided would be a measurement nothing reads. The reasons are recorded beside
`ISSUE_KEYS` itself — V1.4c's precedent — so a later session finds them rather than
the silence.

## 9. `SAVE_VERSION` 15 → 16, on one field of three

| Field | Earns the bump? |
|---|---|
| `service_quality` | **YES.** Absent it reads 0.0 against a France that has funded hospitals for decades, so every reader sees a country whose hospitals have ceased to exist and the satisfaction term scores a collapse the player did not cause. `military_capability`'s case at V1.3g, in its **strongest form**: equilibrium-init does *not* rescue it, because re-deriving on load would erase an accumulated decline the player spent a term earning. |
| `corruption` | No. Absent it reads 0.0, the truth about every version-15 save because those games had no `society` law to pass — `measures` at V1.3c, `regulation_burden` at V1.4b. Serialised regardless, for V1.4b's reason: a law writes it once and no tick recomputes it. |
| `start_service_quality` | No. Recomputed at init from the `spending_pct_gdp` every nation file already authors, so like a firm's authored share it round-trips through `data/nations/`. |

`tests/test_save_load.gd` asserts all three, and the *split* is the assertion worth
having rather than the bump: it checks that `service_quality` does **not** come back
on one tick, which is exactly what separates it from V1.4a's and V1.4c's four derived
prices.

## 10. The balance re-run is not bit-identical, and one of the two causes was not predicted

Predicted in the plan **before** the run: every session since V1.3d has been
bit-identical because its channel read exactly 0.0 until a player *command* fired,
where this one's trigger is the **budget slider**, which the regimes move.

**18 of 23 shared regimes bit-identical, 5 movers, and zero outcome changes** across
182 outcome lines.

| Cause | Regimes | Predicted? |
|---|---|---|
| Moves the `health` line | `spendthrift`, `austerity`, `austerity_dissolves_late` | yes |
| Moves `Cabinet.effectiveness()` | `managed_cabinet_shorted`, `austerity_cabinet_shorted` | **no** |

`managed` and `tinkering` are bit-identical because neither touches `health` —
`managed` moves `defence` and VAT, and `defence` has its own stock.

**The second cause is a finding.** `quality_target()` multiplies by
`Cabinet.effectiveness()`, so a reshuffle or a resignation moves the stock with every
spending line untouched. That **widens the cabinet system's charter**: V1.1d chose
deliberately to have effectiveness multiply the delta only, so that a player who never
moves a line is untouched by it, and V1.5a un-chooses that through a different
channel. Kept rather than gated, and the reason is that the alternative is
indefensible — a model where a *corrupt* state delivers less but an *incompetently
run* one delivers the same is not a model anyone would defend. Recorded here because
it was not planned, and the evidence for keeping it is that zero outcomes moved.

### The eighteenth regime, and it is the cheap kind

`managed_corrupts`. V1.4b's case: corruption reaches the stock through a **law**, and
applying a law at a month is a shape the harness has known since `AMENDMENT_REGIMES`,
so only the content is new — unlike V1.3c, V1.3g, U6a and V1.4a, each of which had to
teach the harness a verb.

It is also the session's legibility evidence, and the comparison is exact. Same
budget, same everything, corruption the only difference:

| | 2032 presidential | Top attributed issue |
|---|---|---|
| `managed` | 26.8 % — **HELD**, run continues to 2034 | — |
| `managed_corrupts` | 23.8 % — **LOST**, simulation stops | `health`, salience 0.29, satisfaction −0.53 |

Approval decays 46.7 → 42.9 over six years and `health` salience climbs 0.14 → 0.29
as `SALIENCE_GAIN` amplifies the bad news. The player loses, and the screen that
exists to say why names the thing they did.

## 11. The readout is on the OVERVIEW, and the plan said the polling panel

Both lines sit under GOVERNMENT beside `military_capability`, which is where [[v1]] §3
put the last derived national statistic of this shape, and `_fill_defence()` is the
template rather than a coincidence — its comment says capability alone is a number
with no units the player can act on, and capability *with the price it sets* is the
loop.

**Not the polling panel**, and the plan said it would be. That panel's contract is
that **every figure on it has been through `PollNoise`** — the player never sees a
true number there — and a service statistic is not a poll: the government knows how
well its own hospitals run. An un-noised figure on a screen whose whole discipline is
that nothing is un-noised would be a contract the player cannot see being broken. The
"no new window" cut still holds; only the panel changed.

Both lines are **silent when there is nothing to say**. A permanent "delivery 100 %"
row says nothing in every game that never passes a `society` law, which is the
failure the alliance line beside it already avoids the same way — and
`tests/test_overview_panel.gd` asserts the silence as well as the speech, because a
figure computed and displayed nowhere is the failure this project has hit four times
([[trade-model|V1.3b]]'s `refused_by_partner`, [[foreign-policy-model|V1.3f]]'s
`act_reason()`).

## 12. Why nothing diverges

| Quantity | Bound |
|---|---|
| `service_quality` | `[QUALITY_MIN, QUALITY_MAX]`, and it converges on a target that is itself a clamped product of a bounded spending line. A first-order lag on a bounded target cannot overshoot it. |
| `corruption` | `[-CORRUPTION_MAX, +CORRUPTION_MAX]`, clamped on the accumulated value in `Legislature.apply()`. One writer, no tick. |
| `delivery_factor()` | `[DELIVERY_MIN, DELIVERY_MAX]`, and both are measured **slack** at a saturated register. |
| The satisfaction term | `_scaled()` clamps to `[-1, +1]` and the sum is re-clamped after, which is `deployment_opinion_load`'s treatment. |
| The reference | `start_service_quality` is written once at init and never again, so the deviation cannot drift by its baseline moving. |

## 13. What is deliberately not built

**A second education stock.** §1. `potential_shift_pct` is that stock, and
`QUALITY_KEYS` enforces the exclusion.

**Pension adequacy.** ~~Needs a dependent count, which is V1.5b's.~~ **Built at
[[demography-model|V1.5b]]**, as a denominator under this stock rather than as a
machine of its own. §1.

**Any recovered-revenue line for anti-corruption.** `anti_corruption_agency` used to
price itself as `other_revenue_pct_gdp: 0.1` — recovered money — which described the
law's side effect and called it the mechanism. Re-authored onto `effects.society`, and
the revenue is **not modelled** rather than modelled at zero: a receipts line for one
law is the corporate-receipts channel [[companies-model|V1.4b]] cut, arriving through
a side door.

**A `corruption` opinion issue.** §8.

**Rule of law.** It left the block at decomposition time for [[v1]] §1's judiciary —
two uncontestable gates on player action is one machine claimed twice.

---

Related: [[index]] · [[opinion-model]] · [[economy-model]] · [[cabinet-model]] ·
[[defence-model]] · [[companies-model]] · [[legislature-model]] · [[v1]] · [[ROADMAP]]
