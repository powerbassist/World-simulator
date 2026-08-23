---
title: Tax Model
tags:
  - decision
  - economy
  - simulation
---

# Tax Model

Five taxes and brackets, as built at [[ROADMAP|V1.6d]] — the fourth session of the V1.6
block, and the first in it to ship a **verb**. Two new tax keys, a bracket lever inside
the income tax, and the discharge of [[unrest-model|V1.5c]]'s declared Gini stopgap.

`src/sim/tax.gd` is the model, `src/sim/tax_constants.gd` is the values,
`tools/tax_probe.gd` is the evidence, and `tests/test_tax.gd` is what stops a later
session quietly breaking the design. The two new taxes themselves are not in that
module: a fourth and fifth tax is the **same machine with more entries**, so their base
shares, erosion coefficients and multipliers extend
[[economy-model|`economy_constants.gd`]]'s existing three tables.

## 1. Step 0, and the answer inverted the prediction

[[credit-model|V1.6c]] found the World Bank government-finance branch too thin to use,
so this session was told to expect the same and to check **before** planning a measured
base share. Checked, over `date=1990:2024`, for all ten:

| Indicator | Roster coverage |
|---|---|
| `GC.TAX.TOTL.GD.ZS` tax revenue | **10 of 10**, 30–35 rows each |
| `GC.TAX.YPKG.RV.ZS` income, profits **and capital gains** | **10 of 10**, 30–35 rows |
| `GC.TAX.GSRV.RV.ZS` goods and services | **10 of 10**, 30–35 rows |
| `GC.TAX.PRPT.*` property | **no rows at all** |

**Coverage is not the problem, which is the opposite of what (c) found.** What rules the
branch out is universe and granularity, and either alone would be enough:

1. **`GC.*` is central government.** Measured latest tax/GDP: FRA **22.78**, DEU
   **10.89**, CHE **9.45** — against the general-government `tax_revenue_pct_gdp` of
   46.1, 39.3 and 27.8 the nation files carry. [[data-sources]] rejected exactly this at
   S1 in almost these words, so the fetch **confirms a standing rejection rather than
   discovering one**.
2. **`GC.TAX.YPKG.*` puts income, profits and capital gains in one bucket.** It is
   precisely the split this session exists to create, so it cannot supply it.
3. There is **no wealth or property series at all**.

So both new `TAX_BASE_SHARE` entries are **authored** — which is not a regression,
because the three that were already there are authored model parameters too. **No new
download and no new [[data-sources]] line.**

## 2. The wealth tax is not on the other four's scale, and three shared tables assumed it was

`TAX_BASE_SHARE` is a share of GDP and the four other entries are **flows** (0.02–0.53).
Net household wealth is a **stock** of roughly four times annual output taxed at
fractions of a point. That is the session's first structural finding, and none of the
three places it breaks is in this session's own code:

- **`opinion_constants.TAX_SCALE_PP` was shared by every tax key**, in points of rate,
  through `opinion.gd`'s `for key in C.TAX_KEYS` loop. One point of wealth rate is eight
  points of income tax in revenue. Shared, the largest wealth tax in Europe reads as a
  fraction of a satisfaction. `TAX_SCALE_PP_BY_KEY` is the answer, sparse, so the three
  taxes S5 measured still read the constant S5 measured.
- **`Budget._erosion()` returned a flat 1.0 when the nation's own starting rate was
  zero** — no diminishing returns at all, revenue linear in the rate forever. Correct
  for a tax nobody has, and wrong the moment a player invents one. **This session's
  content is what makes it reachable**: Switzerland taxes no private capital gain,
  Belgium and Luxembourg broadly neither, and eight of the ten start with no wealth tax.
  Left alone the player's best move is to invent a tax and take it to the ceiling —
  [[diplomacy-model|V1.3a]]'s exploit caught before the content shipped, one block later.
- `budget_panel.LEVER_MAX` was already per-key, so the control itself was free.

**The zero-reference is per key, and the first draft was one shared number.** That
version read *"two points, whatever the tax, because the reference is relative to the
rate being set"*. It is not. An invented capital-gains tax is normally levied around
twenty-five points and an invented wealth tax below one, so a shared reference of two put
the capital-gains revenue peak at about **three points** — an order of magnitude under
every rate any of the ten charges. **One constant cannot serve two rate scales**, which
is `WEALTH_RATE_MAX_PCT`'s finding at a second site inside the same session.

## 3. Brackets, and the two prices that are not a fourth revenue channel

[[v1]] §6 asks for brackets *"within income rather than as further keys, so the
distributional lever exists without a fourth revenue channel"*. `tax_progressivity` is a
dimensionless index on `NationState`, initialised for all ten from `PROGRESSIVITY_BASE`,
with exactly two prices, both through machinery that already existed:

1. **A factor on the income revenue line** — a steeper schedule shrinks the effective
   base, because the top of the distribution is its mobile part and progressivity is what
   points the rate at it.
2. **The Gini policy offset** in §4, which reaches [[unrest-model]]'s grievance.

Writing revenue directly would be [[coercion-model|V1.3c]]'s `tariff_rate_pct` error —
one intensity written twice. `tests/test_tax.gd` asserts the revenue dictionary gains no
line and that no other tax's line moves.

**It is one value for all ten and deliberately not per-nation content**, which is the
opposite of the call [[demography-model|V1.5b]] made for the ageing slope and
[[cycle-model|V1.6a]] for the cycle amplitude — and the difference is that those two had
a dataset and this does not. Ten identical authored values in ten nation files would be
the clustered `coalition_position` failure with extra steps: a field that looks
per-nation and carries no information.

### It went on the erosion curve first, and that failed as ZERO rather than as a wrong number

The first version multiplied `TAX_EROSION["income"]`. That coefficient multiplies
`(rate − ref)`, so a player who steepens the brackets and leaves the headline rate alone
leaves that difference at **exactly zero** — and the entire price disappears for
precisely the budget the lever exists to express. Then the sign was **also** backwards,
so a steeper schedule collected *more*. Both were caught by `tests/test_tax.gd` rather
than by reading, which is the argument for writing the behavioural check before believing
the model.

## 4. The stopgap discharge: a second READ, and not even a second field

[[unrest-model|V1.5c]] shipped `gini_index` as a declared stopgap and wrote
`tests/test_unrest.gd`'s insensitivity assertion so it would **go red the day §6
landed**. The V1.6 decomposition's call 4 said the discharge needs *a second field, not a
second writer*. It needs neither:

```
Unrest.inequality_deviation(ns)
    = gini_index + Tax.gini_policy_offset(ns) − start_gini_index
```

`gini_policy_offset()` is a pure function of `tax_progressivity` and the two new rates,
all of which the save already carries. So `Demography.tick_month()` remains the **only**
writer of the drift, both file-reading checks pass unchanged, and there is **no stored
offset, no stored effective index and no save entry** — `Defence.allies()`'s shape and
`Credit.rating()`'s at V1.6c. `tests/test_save_load.gd` pins the absences.

**Three instruments and no more, and the absences are the design.** §6 owns brackets,
capital gains and wealth. The **corporate rate** is not on that list, and neither is a
state holding or a sector burden — [[companies-model|V1.4c]] refused an ownership channel
into the distribution by name.

> **The tripwire did not fire, and that is a finding rather than a pass.** V1.5c's
> assertion mutates the corporate rate, every `state_share` and every
> `regulation_burden`, and requires the index to be bit-identical. Under this discharge
> it still is — because **the three things it was armed against are the three §6 does not
> own**. It was written against the instruments the model *already had* rather than the
> instruments §6 was going to add, so it could never have fired. The old assertion is
> kept, because it is still true and still worth pinning, and the assertion that would
> have been the real tripwire is added beside it: the index must **move** under
> progressivity and both new rates.

## 5. The constants

`tools/tax_probe.gd` carries every band and tiebreaker in its header, fixed before the
sweep. Six inherited corrections to that discipline are named in it rather than
rediscovered.

### `PROGRESSIVITY_BASE_BETA` = 0.15 — banded, and the response is closed form

The cost of taking the brackets to `PROGRESSIVITY_MAX` is exactly
`income_revenue × beta × deviation`, so table (b) prints the closed form and is
**invariant to the shipped constant** — V1.6b's own correction, where a table rescaled
from the shipped value moved when that value moved.

| Clause | |
|---|---|
| (i) legible | costs ≥ 0.50 points of GDP of income revenue, about one point of income tax |
| (ii) not dominant | costs ≤ 2.50, a quarter of what France's income tax collects; above that the bracket lever is a bigger tax change than the tax slider |

Passing interval **[0.05, 0.25]**, midpoint **0.150**. The response is linear, so the
model edge is a crossing rather than a plateau, [[media-model|V1.5d]]'s extension applies
and the interior governs — and because it is closed form, **no refinement or widening of
any grid can move it**.

### The three Gini betas — FITTED, on V1.6a's rule

A band edge moves when the grid is widened; a fit converges. Something outside the model
measures this quantity: `SI.POV.GINI`, already on `tools/import_data.py`'s loop, and
[[unrest-model]]'s `INEQUALITY_BETA` was set against it.

**The anchor**: a *reachable* redistributive budget — brackets +0.5, capital gains +10
points, wealth +0.5 points, a left-wing programme and **not the maximum**, which is
[[credit-model|V1.6c]]'s clause (i) correction — moves the effective index by as much as
the widest measured roster drift moves it over one five-year term. NLD at **0.417 points
a year → 2.085 over a term**.

**The split is equal thirds**, and it is an authoring choice stated rather than derived:
nothing in the data ranks brackets against a wealth tax, so any other split would be a
claim the measurement cannot support.

| | solved | shipped |
|---|---|---|
| `GINI_PROGRESSIVITY_BETA` | 1.3900 | **1.39** |
| `GINI_RATE_BETA["capital_gains"]` | 0.0695 | **0.0695** |
| `GINI_RATE_BETA["wealth"]` | 1.3900 | **1.390** |

At the shipped constants the reachable budget moves the index **2.0850** against a target
of **2.0850** — a fixed point, V1.6c's standard.

The factor of twenty between the two rate betas is **the units and not a claim about
importance**: one point of wealth rate reaches two hundred times the base one point of
capital-gains rate does, and they are per *point of rate*.

### The kill switch CLEARED, and it had to be measured on an isolated path

Pre-committed: the offset must move the **date of the first strike**, or the three betas
are deleted — [[demography-model|V1.5b]]'s treatment of `DEPENDENCY_ELASTICITY["health"]`.

**The first version of table (d) committed real budgets and could not see this channel at
all.** A budget that moves the Gini also moves the deficit and two tax satisfactions, and
both reach `hardship()` far harder: the flat-bracket row came back **calmer** than the
quiet one, because flattening raises income revenue, which narrows the deficit, which
lifts `public_finances`. [[society-model|V1.5a]]'s `QUALITY_SCALE_PP` failure, inside the
probe written to avoid it.

Isolated — the offset applied to the index directly, every budget line untouched, the
same provocation in every row so it cancels — Germany, 168 months:

| offset source | first act | peak grievance |
|---|---|---|
| quiet | month **27** | 57.91 |
| regressive, reachable | month **26** | 58.49 |
| redistributive, reachable | month **29** | 56.91 |
| redistributive, every lever | month **32** | 55.11 |

Up to **six months on twenty-seven, in both directions**, against V1.5c's own
`INEQUALITY_BETA` result of one month in thirty-six.

### `GINI_POLICY_MAX_PT` = 8.60 — a guard rail, and the first value bound

Declared in advance as a guard rail and **not** a selector, which is V1.5a's
`CORRUPTION_DELIVERY_BETA` failure and V1.6c's clause (i) both named ahead of time. The
first value was **half** the roster's measured Gini span, 4.30, and table (e) caught it
binding. It is the **whole** span instead: a president may not move their own country's
index further than the most equal nation in this game is from the least.

| | points |
|---|---|
| reachable redistributive budget | **2.0850** |
| every lever at its ceiling, unclamped | 9.7300 |
| `GINI_POLICY_MAX_PT` | 8.6000 |

Slack on reachable play by a factor of **4.1**. The absolute corner — all three levers at
their ceiling at once, a tax revolution rather than a budget — is clamped, which is the
relationship `IMPULSE_MAX_PCT` has to the largest budget a player can commit.

### `TAX_SCALE_PP_BY_KEY` — the band could not select, and a fit replaced it

Pre-committed: (i) a reachable move clears the ±3.0 poll floor; (ii) the issue is not
saturated at half the reachable move. **Both failed as instruments and the failure is
recorded rather than tidied.** Clause (i) passed at *every* candidate with the identical
approval move, because the whole reachable move saturates the satisfaction at every scale
in the grid — so it was measuring the clamp. Clause (ii) then reduces to
`candidate ≥ reach / 2`, a rearranged inequality and not a measurement. **V1.5a's two
failures at once, in one row.**

What ships is a **fit against the model's own accepted standard**, which is how V1.6b
settled its collinearity test: `TAX_SCALE_PP`'s 8.0 is a fixed fraction of income's own
reachable upward span, `8.0 / 50.0 = 0.16`, and each new tax takes the same fraction of
its own.

| tax | span up | fitted |
|---|---|---|
| `capital_gains` | 30.00 | **4.80** |
| `wealth` | 3.00 | **0.48** |

It converges because the ratio is a property of constants already fixed for other
reasons, so no grid can move it.

## 6. The `ISSUE_KEYS` question, asked twice at once, answered YES at a cost

The fourteenth and fifteenth keys, and the first session to ask about two. V1.3d's four
tests plus the fifth V1.4b forced are in `opinion_constants.gd` beside `ISSUE_KEYS`
itself. What belongs here is the measurement.

**§6's own criterion is V1.3d's collinearity test restated in content terms** — *"each of
the two new taxes earns its row by having a visibly different bloc-weight profile from
the three that exist; a tax that moves the same voters as an existing one is a rate
change, not a lever"* — which the row does not notice it is doing.

**The S10 ratio drifts −0.739 % for the pair**, in the *unsafe* direction, against
V1.3d's accepted +0.39 %, V1.6b's accepted +0.766 % and V1.4c's **refused** −1.46 %.
Alone: capital gains −0.270 %, wealth −0.508 %.

**It is paid rather than avoided, and the reason is that the alternative is not a cheaper
price but NO price.** `opinion.gd` writes `sat["tax_%s"]` for every `TAX_KEYS` entry, so a
tax without a key is a satisfaction no bloc weights — and a player could take the wealth
lever to its ceiling for **4.2 points of GDP that cost nothing at all**. That is the
strictly-dominated free-money shape this project has caught five times, and it is worse
than the drift. Where V1.4c genuinely differs: `ownership` had `ownership.json`'s authored
offset to be priced on instead, so its −1.46 % bought nothing. **A tax has no content
object anywhere.**

### The first rows drifted −1.640 %, and the fix was CONTENT

Past V1.4c's refusal line. The probe's control is what said so, on V1.6b's own device:
the same two keys at a **flat 0.06** across all six blocs drift only **−0.106 %**, so the
cause is the **profile** and not the two extra keys as such.

The first rows gave the two new taxes **0.0419 and 0.0397** of the national agenda against
`tax_corporate`'s 0.0223 — two taxes eight of the ten barely levy, each outweighing
corporation tax two to one. Re-authored at the anchor `bloc_probe.gd` used for `europe`
(above `defence`, below the tax every nation charges) they take **0.0162 and 0.0142**
against defence's 0.0122 and corporate's 0.0203, and the drift halves. [[bloc-model|V1.3d]]'s
own move: the fix that is content rather than a constant.

`students` carries **no `tax_wealth` entry at all** rather than a small one — this table's
sparsity used on purpose.

## 7. The escalation trigger fired at 77 % and is recorded, not retuned

Named in advance: `DEFICIT_SCALE_PP` is 6.0 and was measured at S10 for a **three-tax**
world, and [[credit-model]]'s clause (ii) already refused a channel that used half its
span. Two new taxes want a share of the same six points.

| | points of GDP |
|---|---|
| deficit with both new taxes abolished | 5.5974 |
| deficit with both at their ceiling | 0.9774 |
| the whole new swing | **4.6200** |
| as a share of `DEFICIT_SCALE_PP` | **0.77** |

Under the span, so the pre-committed response applies: **record it**. Retuning that
constant re-baselines every opinion constant measured since S5. It is a large fraction and
saying so is the point — a later session widening the tax set again should read this row
first.

## 8. New game moves nothing, by construction

`game_state.gd` calibrates `other_revenue_pct_gdp = tax_revenue_pct_gdp − modelled`, so
authoring the two new rates at their real values shifts revenue **out of the residual and
into the two named lines** and total revenue at new game is the nation's own authored
figure, unchanged. `tests/test_tax.gd` asserts it for FRA, CHE and NLD.

`tax_progressivity` starts at `PROGRESSIVITY_BASE` and `start_tax_progressivity` captures
it, so the bracket deviation, the base factor and the Gini offset all read **exactly**
0.0 / 1.0 / 0.0 at new game for all ten — asserted with exact equality, not
`is_zero_approx()`.

## 9. `SAVE_VERSION` 21 → 22, on three fields

`tax_rates_pct["capital_gains"]` and `["wealth"]` **grow a dictionary serialised since
S4** — V1.5b's `service_quality["pensions"]` case, the second on that list. Absent, both
taxes come back at a rate of zero: a save that silently **abolishes two taxes** and
widens the deficit by what they collected. The matching `start_tax_rates_pct` keys are
absent too, so `_erosion()` falls to its zero-reference branch and every later rise is
priced as a tax invented from nothing.

`tax_progressivity` and `start_tax_progressivity` earn it **together and by one failure
between them**, which is why the test asserts them as a pair where V1.6b's three are
separate: absent, both read 0.0 — `PROGRESSIVITY_MIN`, the flattest schedule the model
has — and because the *start* reads 0.0 as well the deviation is still exactly zero, so
the reloaded game does not merely forget the player's brackets, **it agrees a flat tax was
always normal**.

What was **not** added is pinned: no stored offset, no stored effective index, no stored
base factor.

## 10. The re-baseline

Predicted before it ran: **not bit-identical**. The prediction was right and **the reason
given for it was wrong**, which is recorded rather than quietly corrected. The plan
expected float-ordering — five revenue keys plus a smaller residual need not sum to the
last bit the way three plus a larger one did. That is not what moved. What moved is the
**salience simplex**: two new `ISSUE_KEYS` entries renormalise every weight, approval
shifts, `hardship()` reads those weights, the grievance moves, and V1.6c's yield reads the
grievance.

| column | identical | worst move |
|---|---|---|
| trend | **217 / 217** | 0.00 |
| GDP | 216 / 217 | 4 EUR bn |
| growth | 216 / 217 | 0.79 |
| unemployment | 216 / 217 | 0.05 |
| debt | 206 / 217 | 0.10 |
| deficit | 189 / 217 | 0.06 |
| approval | 100 / 217 | **0.90** |

0 of 29 shared regimes bit-identical; **one outcome change of 51** — `tinkering` 2032,
23.5 LOST → 23.6 **HELD**, which is the regime [[credit-model|V1.6c]]'s own re-run flipped
the other way, flipping back on a tenth of a point. Approval's worst move is **0.90**,
under the ±3.0 poll-noise floor.

**Three new regimes, 29 → 32**, and they are needed for the reason V1.5c's blind spot was:
every existing regime sets three tax keys and no schedule, so this whole session is
**structurally unreachable** by all of them. (a), (b) and (c) each needed none because a
statistic is not a verb. `redistributive`, `flat_tax`, and `managed_then_redistributive`
on V1.5c's own mid-run switch shape.

## 11. The readout, and the thirteenth screenshot pass

One row on the budget panel, `Inequality (Gini)`, under `Debt` — not a budget figure, and
on this panel anyway because this is where all three instruments that move it live.
**Never silent**, which is the dependency ratio's and the credit rating's rule: every game
has an inequality index from the first frame.

**The pass earned its keep and found two bugs, after V1.6c's clean sheet.**

1. **The row printed a confident `0.00` against a live 31.80.** `Budget.snapshot()` never
   carried `gini_effective` at all, and the panel read it with `.get(key, 0.0)` — a
   defensive default reading as a plausible figure. That is `_set_figure()`'s own
   silent-return failure at V1.4c in a new place: **a default that hides a missing key is
   worse than a crash.** The panel now returns an em dash for a figure that is not there,
   which is what a missing figure looks like everywhere else on it.
2. **The lever column showed the pre-commit position**, and the *proposed* column offered
   a budget that would have undone the one just committed — capital gains reading 30.0
   against a live 42.0. `budget_panel.gd` captures `_pending` in `setup()` and refreshes
   *from* it, so a budget committed by anything other than its own sliders leaves the
   panel stale.

> **The second is a live bug and not only a tool one, and it is recorded rather than
> fixed.** `Legislature.apply()` commits tax changes exactly this way, so a law passing
> while the budget window is open does the same thing. Fixing it needs a design call this
> session is not the place for — *what happens to a player's half-finished edits when a
> law lands underneath them?* — so `tools/screenshot.gd --redistribute` re-syncs the panel
> and the bug is written down here for the session that takes it.

Unflagged the panel reads `Capital gains tax 30.0%`, `Wealth tax 0.00%`, `Income brackets
1.00` and `Inequality (Gini) 31.80`; under `--redistribute` at July 2027 it reads `42.0%`,
`0.80%`, `1.60` and **28.85**.

Two decimals on the index, chosen against the reachable range rather than copied from the
row above: the grain a player moves it in is a bracket notch, which is hundredths.

## 12. What is deliberately not built

- **No sixth tax and no tariff key.** [[v1]] §6 fixes the count at five and
  [[coercion-model|V1.3c]]'s tariffs stay a revenue line of their own — no slider, no base
  share, no erosion curve, and a per-partner rate.
- **No law channel for brackets.** A law can already move `tax_rates_pct`;
  `tax_progressivity` is a budget lever only. Adding it means a new effect key and a
  fourth writer of the schedule, which is a session rather than a line.
- **No `PRECONDITION_FIELDS` entry.** Nothing in the content asks to be gated on a tax
  rate that is not already a bloc rule field.
- **No per-nation bracket structure.** There is no dataset, and ten identical authored
  values would be a content field carrying no information.
- **No corporate-rate channel into the distribution.** §6's instrument list is brackets,
  capital gains and wealth, and `tests/test_unrest.gd` has asserted that blindness since
  V1.5c — an assertion this session **keeps**.

---

Related: [[index]] · [[economy-model]] · [[unrest-model]] · [[opinion-model]] · [[credit-model]] · [[inflation-model]] · [[companies-model]] · [[demography-model]] · [[decision-log]] · [[ROADMAP]] · [[v1]]
