---
title: Sector Model
tags:
  - decision
  - economy
  - simulation
---

# Sector Model

Sectoral investment, as built at [[ROADMAP|V1.6e]] — the fifth session of the V1.6 block
and the block's **one genuine new player verb**. State money pointed at one of the three
sectors, a capital stock it accumulates, and the single channel through which that stock
reaches the economy.

`src/sim/investment.gd` is the model, `src/sim/investment_constants.gd` is the values,
`tools/investment_probe.gd` is the evidence, `data/investment-actions/` is the content and
`tests/test_sectors.gd` is what stops a later session quietly breaking the design.

**The row split, as this page recorded in advance.** [[v1]] §6's last bullet is
*"**Sectoral investment** and **infrastructure projects**"*, and the V1.6 decomposition
named projects as the cut. Counted, it splits — but on a harder reason than the
decomposition gave, which is [[ROADMAP|§1]] below.

## 1. The count, and why the cut is about TRACK rather than about a scheduler

Machines in the row as written: **five**.

| | |
|---|---|
| 1 | the investment capital stock, per sector |
| 2 | its channel into trend, plus the verb and content type that drive it |
| 3 | a project content type and an in-flight register keyed by date |
| 4 | a construction scheduler — nothing in this project has a multi-month build |
| 5 | a completion payoff, and the *"visible on the map"* clause [[mechanics-economy]] tiers and the row drops |

1–2 are (e); 3–5 are V1.6f. [[foreign-policy-model|V1.3e]]'s trigger fires on the count
alone, and the decomposition's stated reason — *a rate at a sector and a discrete dated
commitment are different shapes, and the second is a scheduler* — is true. But it is not
the binding one:

> **Machine 5 is a U-track surface**, a marker at a location on `map_view` with per-project
> geography as content. This project runs **one track per session**, and has since U1. A
> difference in architectural shape is an argument; a rule the roadmap has followed for
> twenty sessions is a rule.

(e) alone counts ~22 surfaces, between [[transition-model|V1.2d]]'s ~21 and
[[trade-model|V1.3b]]'s ~33.

## 2. Instance thirty-five: `sector_output` is a quantity with no room for a second writer

§6 says the lever *"acts on `sector_output` itself"*. It cannot.

`Economy._apply_growth_to_sectors()` grows each sector at its own rate, then distributes
the **residual** `target_gdp − after_trend` by cyclical beta and ends with
`ns.gdp_eur_bn = total`. The sector sum is the month's GDP target **by construction**, so
an absolute injection is cancelled inside the same tick. Probe table (a) measures it
rather than asserting it: 27.9 bn injected into French industry before a tick leaves GDP
**+0.0236 bn** against the control and moves the industry share **+0.006**.

> **A write to `sector_output` survives as composition and never as level.**

What has room is the per-sector **rate** — the slot `Trade.sector_shift()` occupies. And
the difference between the two is the whole of why one is a lever and the other a
reallocation:

> **A trade shift must sum to zero. An investment shift must not.**

`Investment.sector_trend_shift()` is therefore read at **two** sites in `economy.gd`, and
both are required:

- `_apply_growth_to_sectors()`, on each sector's own rate beside `trade_shift`;
- `trend_pct()`, added **share-weighted**, so `after_trend` is exactly the nation's trend
  and the residual has nothing to take back.

### The probe found the same leak in code that was already there

`Trade.sector_shift()` sums to zero as **raw points**, validated at load — but `trend_pct()`
share-weights, and `industrial_compact`'s (−0.15, +0.45, −0.30) share-weighted at France
is **−0.1538**, not zero. The residual absorbs it, which is what
`data/diplomatic-actions/agreements.json`'s own note describes from the other side.
`_apply_growth_to_sectors()`'s comment (*"summed, this is exactly the nation's trend, so
the two paths agree"*) predates V1.3b and is no longer exactly true for that term.

V1.6e does **not** inherit it, because its shift is added at `trend_pct()` as well. Recorded
here rather than repaired: the trade shift is a composition-only term by design, so the
residual taking its level back is the correct behaviour and only the comment is stale.

## 3. It moves potential, where V1.6a's cycle deliberately does not

Trend enters `potential_gdp_eur_bn *= monthly_factor(trend)`. So this raises the level the
economy is heading for, where [[cycle-model|V1.6a]]'s impulse moves GDP **around** an
unchanged potential — *"a business cycle is by definition output around potential"*. The two
terms sit on opposite sides of that distinction and that is the cleanest available
statement of what each one is.

## 4. Instance thirty-six: "no employment term" is a CONSEQUENCE, not a prohibition

[[v1]] §6 hands (e) the rule *"it acts on `sector_output` itself and carries no employment
term — otherwise it is V1.4b a second time"*. [[companies-model|V1.4b]] earned its jobs
price because jobs-per-share is **firm** content and no sector lever can express it. True —
and the model goes further than the prohibition:

`Economy._update_unemployment()` reads Okun on `growth − trend`, and
`structural_unemployment_pct` reads the income-tax wedge, `law_structural_offset_pct` and
`firm_jobs_offset_pct`. **A term that raises TREND has no permanent employment channel
available to it at all.** There is a transitional one — a rising potential opens a negative
output gap, `GAP_CLOSE` pushes growth above trend, Okun bites while it closes — and it
closes.

> **Sectoral investment buys output and, in the long run, no jobs.**

Recorded rather than smoothed. `tests/test_sectors.gd` asserts structural unemployment is
**bit-identical** between an investing run and a quiet one, and reads the source to fail if
this module ever reaches the employment path. The balance re-run shows the same thing from
the other end: `managed` and `industrial_policy` print **identical unemployment in every
year** while GDP diverges by 4.9 %.

## 5. Boundary check before the band: it is not a second `INFRA_BETA`

[[credit-model|V1.6c]]'s rule — *a band is a test of size, not of legitimacy* — so this was
settled first and separately.

`INFRA_BETA` reads a player-set **spending line**, keyed 1:1 to a cabinet portfolio, and
produces a **uniform** shift through `potential_shift_pct`. `SECTOR_TREND_BETA` reads a
register written by a **verb** and produces a **per-sector** one. Against `src/core/law.gd`'s
criterion for the three existing anti-double-count pairs — *same act, same landing site
**and** same units* — it fails two of three, so it is not one. Written down because the next
session will reach for a fourth pair by symmetry and [[unrest-model|V1.5c]] already recorded
that **symmetry is not the test**.

**What did have to change is a sentence.** `economy_constants.SHIFT_MAX_PCT`'s comment said
`potential_shift` is *"the only term that feeds back into trend growth"*. It is not, from
this session on. The clause is amended rather than deleted, and the new term carries its own
bound because [[economy-model]]'s divergence argument is **per quantity**.

There is also a second-order loop, and it **already existed**: `trend_pct()` is
share-weighted over `SECTOR_TREND` (services 1.4 against agriculture 0.2), so a sector
growing faster than its neighbours lifts the national trend with nobody investing. (e) does
not create it; it steers it. Probe table (f) decomposes the measured move:

| sector | total trend move | of which the shift | of which share drift |
|---|---|---|---|
| agriculture | 0.0091 | 0.0099 | −0.0008 |
| industry | 0.1357 | 0.1389 | −0.0032 |
| services | 0.5725 | 0.5691 | +0.0034 |

The drift is **under one per cent** of the move in every row, so the lever is the shift and
not the loop.

## 6. The content, and the one call it makes

`data/investment-actions/`, `src/core/investment_action.gd`, and `effects.investment` — the
**seventh** effect channel. `data/company-actions/`'s shape exactly, which is
`data/diplomatic-actions/`'s: the third directory on one shape rather than a third kind of
content.

**The sector is authored, not passed as a target.** A company action takes its target as a
parameter because a firm's differentiator — headcount and share — is already per-firm
content, so nine firms behave nine ways under one action. Three sectors under one action
would share a single authored `bloc_offset`, making *which sector* an economic decision and
a politically identical one. That is [[companies-model|V1.4a]]'s own finding (a layer is
more than a sector lever exactly to the extent its members are authored **differently**),
applied one level up. Naming a sector in content is precedented: `law.gd`'s
`_extract_company()` already has a `business` law name the sector it burdens.

Nine actions: two intensities and a withdrawal per sector. The withdrawal hands back exactly
the **smaller** package's offsets, so stepping down from the larger one is a net political
loss.

### It does not go through `Budget.commit()`, and that is deliberate

[[tax-model]] §11 records a live bug: `budget_panel.gd` refreshes from a `_pending` captured
in `setup()`, so a budget committed by anything other than its own sliders leaves the panel
stale and offering to undo it. The obvious alternative shape for this lever — three more
sliders on the budget panel — walks straight into it. Writing an own register and letting the
cost arrive as a computed line means this verb **cannot reach that bug**.

## 7. The constants: three, all closed form or fitted to a fixed point

`tools/investment_probe.gd` carries every band and tiebreaker in its header, fixed before the
sweep, with the seven inherited corrections named rather than rediscovered.

### `INVESTMENT_COST_PCT_GDP` = 0.8161 — banded against what V1.6d left

The one thing this session was told to measure before assuming there was room.
[[tax-model]] §7 measured V1.6d's two new taxes at **4.62** of
`opinion_constants.DEFICIT_SCALE_PP`'s six-point span, so the headroom for a fourth computed
budget line is **1.38 points** — not `SUBSIDY_BILL_MAX_PCT_GDP`'s 2.50.

| clause | |
|---|---|
| (i) legible | the largest single-sector programme France can run costs ≥ 0.20 points of GDP |
| (ii) fits | the whole-economy programme plus the tax swing stays inside `DEFICIT_SCALE_PP` |

France's services sector is **0.7930** of GDP, so (i) is `0.20 / 0.7930 = 0.2522` and (ii) is
the headroom itself. Interval **[0.2522, 1.3800]**, midpoint **0.8161**. Both edges closed
form.

Confirmed once against the real model so a second-order effect could not hide inside the
arithmetic: the whole economy at full intensity for ten years widens the deficit **1.1074**
points against a quiet run — this constant plus debt service on what it borrowed.

### `CAPITAL_CONVERGENCE` = 0.4518 — closed form, and the midpoint is taken in MONTHS

Banded on **t90**, months to 90 % of the endpoint, which is
`companies_constants.SHARE_SHIFT_PER_MONTH`'s device. Band **36–84 months**, fixed before the
column existed: [[mechanics-economy]]'s sketch is *"direct state money at a sector and wait
several years"*, and a lever that pays inside a year is not this one.

`t90 = ln(0.1) / ln(1 − rate/12)`, so the band maps exactly onto rates **[0.3245, 0.7435]**.
The midpoint is taken **in months** and solved back, because the band is written in months
and the map between them is convex — a midpoint of the rate is a midpoint of the wrong
quantity, which is [[unrest-model|V1.5c]]'s resolution error one step earlier.
t90 = **60.0 months** exactly → **0.4518**.

Sixty months is five years, which is the time constant `SHIFT_ADJUST` already uses for
potential and for the same reason: **deliberately longer than a term**. Nothing arranged
that; the band was fixed first.

### `SECTOR_TREND_BETA` = 0.7124 — a fixed point, and clause (ii) had to be rewritten

| clause | |
|---|---|
| (i) legible | the national trend move at a reachable programme clears what a reachable infrastructure budget already buys through `INFRA_BETA` — one point of GDP is 0.15 %/yr |
| (ii) not dominant | it stays under `SHIFT_MAX_PCT` = 1.0, the whole long-run budget every other lever shares |

Measured slope **0.8072** points of national trend per unit of beta, exactly linear, so both
crossings are one division: interval **[0.1858, 1.2389]**, midpoint **0.7124**. Smooth
crossing rather than a plateau, so [[media-model|V1.5d]]'s extension applies and the interior
governs. **Iterated to a fixed point** — the slope is measured on a path this constant is on,
and the shipped value is the one at which the measured midpoint equals it, which is
[[credit-model]]'s `EQUITY_PREMIUM_PCT` standard. It converged in one pass to four decimals.

Measured by **exact emulation** rather than by rescaling the shipped figure: a candidate is
run by holding the capital at `true × candidate / shipped` for the two economy reads and
restoring it before the stock advances. [[inflation-model|V1.6b]]'s correction — its first
table rescaled from the shipped constant and the passing interval moved when that constant
moved.

## 8. What the probe corrected, and one of the three is about the probe itself

**Sixteen sessions running.**

### (1) The price was flat and the return was not — the strictly-dominated shape, in a PRICE

Table (e), on the isolated path, at a flat cost:

| sector | growth move |
|---|---|
| services | +0.4865 |
| industry | +0.1147 |
| agriculture | +0.0077 |

**Sixty-three to one, against an identical bill.** Same money for less of everything — the
shape this project has caught at [[coercion-model|V1.3c]]'s severities,
[[bloc-model|V1.3d]]'s rules, `SHARE_SHIFT_PER_MONTH`'s floor, `DIVIDEND_YIELD` and
`GINI_POLICY_MAX_PT` — and the **first time it has appeared in a price rather than in an
effect**.

The fix moves the model and adds **no constant**: the bill scales with the sector's own share
of GDP, so the return per euro is the same wherever it is spent and *which sector* goes back
to being a question about composition and politics. `RIVAL_FLOOR_FRACTION`'s correction in a
new place — there too the endpoint became content and the rate went back to setting speed.

**It also deleted a constant.** The three shares sum to exactly 1.0 by
`_apply_growth_to_sectors()`'s own reconciliation, so the whole bill is bounded above by
`INVESTMENT_COST_PCT_GDP` itself: every sector at full intensity is one economy's worth.
`INVESTMENT_BILL_MAX_PCT_GDP` was **deleted rather than left unused** — U6a's treatment of
the day budget and [[foreign-policy-model|V1.3e]]'s of `AGREEMENT_ACCEPT_MIN`. Table (g)
prints the peak bill at **0.8161** against a constructed bound of 0.8161.

### (2) Clause (ii) was measuring the clamp — V1.6d's finding in the session after it

Read off the shipped figure, the national shift is scaled down to `SECTOR_TREND_MAX_PCT` the
moment it would exceed it. So *"stays under `SHIFT_MAX_PCT`"* is true at **every** candidate
above the clamp point **by the clamp**, and a grid wide enough to reach it reports an interval
whose upper edge is a guard rail. Clause (ii) reads the **unclamped** weighted shift now, and
the probe prints both columns so the difference is visible rather than asserted.

### (3) The grid nearly chose two constants whose whole claim was that no grid could

Both (P1) and (P2) are closed form, and the first run still reported the interval as the
widest **passing grid row**: 0.40 where the exact edge is 0.46, and t90 38.3–77.8 where the
band says 36–84. That is [[demography-model|V1.5b]]'s *the range was choosing the constant* in
the one place it should have been impossible. Both edges are solved arithmetically now and
the grid is kept only as a legibility column.

## 9. The kill switch cleared, and two of three sectors are below the floor

Pre-committed: the lever must move `growth_annual_pct` by ≥ **0.20 %/yr** sustained at a
reachable programme, on an **isolated path** — the capital displaced with every budget line
untouched, so the deficit and every tax satisfaction cancel between rows.
[[society-model|V1.5a]]'s `QUALITY_SCALE_PP` failure, which [[tax-model|V1.6d]] hit again
inside the probe written to avoid it.

| sector | growth vs quiet | clears 0.20 |
|---|---|---|
| services | **+0.5760** | yes |
| industry | +0.1365 | no |
| agriculture | +0.0091 | no |

**Cleared at 0.5760.** And the two that do not clear are a **structural bound recorded rather
than tuned around**: the lever's power is proportional to the sector's share of GDP, and
French agriculture is 1.4 % of it. Nothing a president does to it can move France. That is
[[companies-model|V1.4b]]'s own agriculture prediction — *39k named jobs against a 30.9M
labour force* — arriving a second time from the other direction, and the share-scaled price
is what stops it being a trap: backing agriculture is now proportionately **cheap**, so it is
a political act with a small economic one attached rather than a full bill for nothing.

## 10. The guard rail is slack, and the escalation trigger did not fire

`SECTOR_TREND_MAX_PCT` = 1.00, declared a guard rail and explicitly not a selector. The
largest programme a player can run — all three sectors at full intensity for ten years —
reaches **0.7053**. Slack, so the model and not the clamp sets every reachable number.

**Escalation trigger 1**, named in advance: if a withdrawal reversed most of the gain inside a
game year, the lever would be [[scenario-model]]'s decorative axis and an **asymmetric decay
constant** would be warranted. Measured, after ten years at full intensity in industry:

| months after withdrawal | capital left |
|---|---|
| 6 | 79 % |
| 12 | **63 %** |
| 24 | 40 % |
| 36 | 25 % |
| 60 | 10 % |

**Did not fire.** A withdrawal is not a demolition, so no second constant was added — the
symmetric rate stays, and what a president leaves behind outlives them by about a term.

**Escalation trigger 2** (no candidate both legible and inside what V1.6d left of
`DEFICIT_SCALE_PP`) did not fire either: the interval is 1.13 points wide.

## 11. The `ISSUE_KEYS` question — the sixteenth, answered NO

Recorded in `opinion_constants.gd` beside `ISSUE_KEYS` whatever the answer, so a later session
finds the reasons rather than the silence.

**Test 1 fails immediately, and that settles it.** Every YES on this list —
[[inflation-model|V1.6b]]'s `inflation`, [[tax-model|V1.6d]]'s two tax keys — was paid because
the price was **not nameable otherwise**: inflation ships no verb and no content object, and a
tax has no `data/taxes/` anywhere. This ships a content object with an authored `bloc_offset`,
which is exactly what [[companies-model|V1.4c]]'s `ownership` had and why its −1.46 % bought
nothing.

The S10 ratio was **not swept**, deliberately, on V1.5a's ground: sweeping to choose between a
yes and a no already settled is a measurement nothing reads.

**What had to be checked is that the authored price is legible**, because an authored price
nothing can read would put the question back. Probe table (i), twelve months after the act:

| action | headline move | worst bloc |
|---|---|---|
| `agricultural_transformation` | +0.31 | rural **+5.80** |
| `reindustrialisation` | +1.31 | workers **+5.27** |
| `knowledge_economy_plan` | −1.08 | rural **−6.14** |

All three clear the ±3.0 poll-noise floor **on the per-bloc rows and none of them on the
headline**, which is [[diplomacy-model|V1.3a]]'s own finding used as designed rather than
rediscovered: a policy that divides the country should not move the average.

## 12. `SAVE_VERSION` stays at 22

`sector_investment` absent reads as no programme running and nothing built, which is **correct
for every version-22 save** because those games had no investment verb. `measures` at V1.3c,
`pacts` at V1.3g, `regulation_burden` at V1.4b.

Serialised all the same, and that half is not free: the capital stock is written by a tick and
**no tick re-derives it from content**, unlike V1.4a's four prices. A save that dropped it
would silently demolish everything the player spent a term building.
`tests/test_save_load.gd` **checks that premise** rather than asserting it — dropping the
register must take the trend shift to zero — then pins that a serialised entry carries
**exactly two keys**, so a later session storing a baseline or a cached shift turns it red.

`investment_bill_pct_gdp` earns nothing and is recomputed on the first tick
(`subsidy_bill_pct_gdp`'s case). V1.3c's device is re-armed: *the version is still 22*, so
V1.6f has to come and say why it moves.

## 13. The re-baseline: 32 of 32 shared regimes bit-identical

**Predicted, and it held exactly.** The trend shift reads exactly 0.0 — asserted with exact
equality, not `is_zero_approx()` — for every nation in every month in which no investment
action has executed, and no existing regime issues a verb.

**Two new regimes (32 → 34), the expensive kind**, because every one of the thirty-two is
structurally unreachable by this session. Both survive both presidential elections, which is
the reachability check [[foreign-policy-model|V1.3f]]'s error and V1.5c's blind spot both
demand.

The legibility evidence, same budget, `managed` against `industrial_policy` in 2037:

| | managed | industrial_policy |
|---|---|---|
| GDP | 3340 | **3502** |
| trend | +1.31 | **+1.89** |
| unemployment | 7.67 | **7.67** |
| deficit | −2.79 | −3.54 |
| approval | 46.1 | 45.3 |
| worst bloc | rural 43 | **rural 38** |

Output bought with money and with the countryside's goodwill, and **unemployment identical to
the digit** — §4's claim visible in the harness rather than only in a test.

## 14. The readout, and the fourteenth screenshot pass

Two surfaces, no new window. `companies_panel.gd` already grouped by sector and already
carried a `SECTOR_LABEL` table, so the readout and both verbs hang under the heading they
point at. The window's **title** changed — "Companies" → "Industry" — because the panel is no
longer only about firms; the id stays `companies`, which is what the action bar and
`--open` address.

Three figures per sector and not one, because they are three different times: the standing
**intensity** is what the treasury is committed to now, the **capital** is what that has
built, and the **shift** is what the capital is worth. A sector with no programme prints a
zero line rather than nothing, because an absent row reads as "this sector cannot be invested
in".

On the budget panel, one indented row under Spending — the **fifth** line to take that route
after the Union, deployments and subsidies. Its missing-key branch is separate from its zero
branch: both print an em dash, but a key vanishing from `Budget.snapshot()` cannot be quietly
absorbed into "nothing is running", which is [[tax-model]] §11's `.get(key, 0.0)` failure
guarded against rather than repeated.

> **The pass found one bug and it was the tool's.** The first frame of `--invest` showed the
> ledger reading a live 0.654 % of GDP and +0.513 %/yr — and every visible sector row saying
> *"No state programme"*, because the sector the flag had backed is the **last of the three**
> and sits below the fold of a panel whose whole body scrolls by design. The figures were
> right and the frame was still evidence for the wrong claim. `--invest` now pins the panel
> to the bottom, and the frame reads *"State programme 100 % · capital 0.90 · +0.641 %/yr to
> this sector"* with `End the Services Programme` beside it.

`--invest` ticks **sixty** months rather than a round number, because that is the capital's own
t90: [[inflation-model|V1.6b]]'s pass found a flag that ran *past* what it existed to
photograph, and this one could have stopped short of it.

## 15. What is deliberately not built

- **No infrastructure projects.** V1.6f — see §1.
- **No employment term.** Structural, not a policy: see §4.
- **No `disinvest` op.** Capital is a stock and a negative stock is a sector the state has
  demolished. Withdrawal already carries the whole downside.
- **No sixth spending line.** `SPENDING_KEYS` is keyed 1:1 to cabinet portfolios, so a sixth
  line is a sixth minister, and [[v1]] §6 rules it out.
- **No law channel.** A sector law is [[companies-model|V1.4b]]'s regulation with a plus sign;
  (e) is an executive verb by the decomposition's call 2.
- **No AI use of the verb.** The nine have no agenda term for it, which is what keeps the
  re-run bit-identical and is the same honest limitation [[defence-model|V1.3g]] recorded for
  its four. `tests/test_sectors.gd` pins it.
- **No per-sector efficiency.** There is no dataset, and three authored values would be a
  content field carrying no information — [[tax-model]] §3's refusal for the bracket index.

---

Related: [[index]] · [[economy-model]] · [[companies-model]] · [[tax-model]] · [[credit-model]] · [[cycle-model]] · [[opinion-model]] · [[decision-log]] · [[ROADMAP]] · [[v1]]
