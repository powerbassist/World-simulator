---
title: Credit Model
tags:
  - decision
  - economy
  - simulation
---

# Credit Model

The bond market, as built at [[ROADMAP|V1.6c]] — the third session of the V1.6 block.
The rate a nation borrows at as a spread over a constant that has been flat since the
MVP, plus the credit rating that reads it. Every formula, every constant, and the
argument for why two of the four terms the row asked for do not exist.

`src/sim/credit.gd` is the model, `src/sim/credit_constants.gd` is the values,
`tools/credit_probe.gd` is the evidence, and `tests/test_credit.gd` is what stops a
later session quietly breaking the design.

## 1. What stays anchored, decided before any code

`economy_constants.DEBT_REAL_RATE_PCT` is flat at 2.0 and is the entire fiscal pressure
of the MVP — the reason a zero primary balance still walks the debt ratio upward. **Every
balance number this project has ever measured is quoted against it.**

So it stays the **anchor** and the yield is a spread around it:

```
yield = DEBT_REAL_RATE_PCT + spread(ns)
spread = YIELD_DEBT_BETA × (debt_to_gdp − start_debt_to_gdp)
       + YIELD_UNREST_BETA × unrest_pct
```

Every input is a deviation against the nation's **own start**, so the spread reads
**exactly 0.0** at new game and the register goes live moving nothing.
`trade_baseline_by_partner`'s, `firm_impulse_pct`'s, the cycle's and inflation's idiom,
and [[media-model|V1.5d]]'s six framing gains averaging back to the one `SALIENCE_GAIN`.
`tests/test_credit.gd` asserts it with exact equality rather than `is_zero_approx()`.

The alternative — a yield on the absolute debt **level** — was considered and cut. It
gives the ten different opening ratings, and it changes France's debt service on frame 1,
which reprices every measured constant in the project against a fiscal pressure that no
longer exists. It is also mostly decorative: only the player has a budget, so the other
nine would carry nine frozen letters.

**The baseline is read back through `ns.debt_to_gdp_pct()` rather than assigned from the
local it was computed from**, and the round trip is the point: the live read is
`debt_eur_bn / gdp_eur_bn * 100` and taking the local leaves a 1e-14 residue. *Almost
zero* is not the claim.

It is also set **after** the scenario override, so a scenario handing the player 140 % of
GDP is a France that has always carried it and starts at a zero spread rather than in
immediate breach of a market it never borrowed from.

## 2. No sovereign-rate series exists, and that is a checked result

[[cycle-model|V1.6a]] fitted its amplitude and [[inflation-model|V1.6b]] measured three
of five constants off the World Bank, so this session looked for a series on the same
licence-clean loop **before writing a band**. There is not one that covers the roster:

| Indicator | Roster coverage |
|---|---|
| `FR.INR.RINR` real interest rate | **4 of 10** — CHE 2008–24, GBR 1990–2014, ITA 1990–2024, NLD 1999–2013. FRA, DEU, ESP, BEL, LUX, AUT: **zero rows** |
| `GC.DOD.TOTL.GD.ZS` central govt debt | 7 of 10, but DEU 1 year, ITA 2, LUX 4, NLD 5 |

The windows are disjoint, so there is no cross-section at any date, and **France has
nothing at all**. OECD `IRLTLT01` carries it, and [[data-sources]] already rejected the
IMF World Economic Outlook on redistribution terms. So the slopes are swept. No new
download and no new [[data-sources]] line.

## 3. The row asked for four inputs and two of them do not exist

[[v1]] §6: *"Bond yields rising with debt and instability… Reads debt, deficit,
`unrest_pct` and (b)'s inflation."* Two survive.

### The deficit is the debt written twice, and the sweep is what said so

The deficit is the **derivative** of the debt — `budget.gd` integrates it monthly with no
other source — so on its face this is [[inflation-model|V1.6b]]'s *one quantity written
three times* a session later. That was a suspicion and not a result: a level and a
trajectory genuinely are different information, because a stock takes decades to unwind
and a yield on the level alone is blind to a player who fixed the budget this year.

`tools/credit_probe.gd` table (d) swept it against three clauses and **no candidate
passed**:

- isolated against a control, the deficit term moves debt service by 0.30 points of GDP
  over a term only above a slope of **0.20**;
- by **0.145** it already outweighs twelve months of the debt term it exists to lead.

Everywhere it is legible it dominates the level; everywhere it does not dominate it is
under the floor. Table (j) then corroborated it: **corr(debt gap, deficit gap) = 0.9948**
against the standard V1.6b used, `|corr(sat.jobs, sat.growth)| = 0.3185`, already carried
as distinct. **Thirty-first stale-row instance.**

Deleted rather than left at zero — [[foreign-policy-model|V1.3e]]'s treatment of
`AGREEMENT_ACCEPT_MIN` — and **not eligible** for V1.6b's structural exception, because
cutting it breaks no loop.

**It takes the session's only positive feedback with it.** `debt_service_pct_gdp` is
*inside* `deficit_pct_gdp`, so a yield reading the deficit would have fed the line it
sets — the thing [[economy-model]] forbids outright. The surviving terms read the debt
**stock**, which `Budget.tick_month()` advances only after `Budget.recompute()` has read
it, so the figure the spread sees is always last month's. A lag that would have been an
argument is now a fact about the call order.

### Inflation cannot reach a real rate, and the band did not decide it

`YIELD_INFLATION_BETA` was pre-committed as the constant this session expected to delete.
It was swept, and **2 of 7 candidates passed the band** — so the band alone would have
kept it.

It is deleted anyway, on a ground the band cannot see. `DEBT_REAL_RATE_PCT` is a **real**
rate and inflation raises a **nominal** one, so a term here is the Fisher effect —
precisely the nominal layer [[inflation-model]] §1 cut, smuggled back in through the
yield. What survives in real terms is an inflation **risk** premium, and that is about
volatility rather than level: this model's realised inflation sd is **0.040** against a
measured 1.14, its own table (e).

> **A band can pass a term the model's own boundary forbids.** That is the finding, and
> it is a new one on this list — every previous deletion was a band failing.

## 4. The two constants, and how the bands were got wrong twice first

**`YIELD_DEBT_BETA` needed three sets of bands, and table (a) running first is what
caught each one.** That is the process working rather than a lapse, and it is recorded
because *the reachable path* is the thing five consecutive sessions have got wrong.

1. The first set measured a **spendthrift** regime, which does not widen the debt — it
   spirals to the clamp and a ratio past 1400 % of GDP. Every candidate down to 0.005
   passed. *A band measured on a saturated run measures the clamp.*
2. The second measured `hands_off` and passed at **0.0005**, because a debt ratio walking
   110 → 200 moves the service line by 1.8 points **at the anchor rate with no channel at
   all**. *A band on a raw move measures the model that was already there.* The fix is a
   control with the term zeroed — the control `tests/test_trade.gd` needed at V1.6a, one
   session later.
3. The third set is what ships.

| Clause | Measured on |
|---|---|
| (i) the debt term moves debt service ≥ 0.30 points of GDP over a five-year term | `hands_off` |
| (ii) it moves it ≤ 3.00 over fourteen years — **half** of `DEFICIT_SCALE_PP`, so the bond market cannot on its own saturate the one issue that prices it. **The closer** | `hands_off` |
| (iii) a well-governed run is not punished: the yield stays within 0.50 of the anchor | `managed` |
| (iv) no runaway on a path a player can reach | `managed_then_spendthrift`, 84 months |

Passing interval **[0.0110, 0.0190]**, interior to a grid running 0.0005–0.1200 and
stable under refinement at 0.0005. The response is smooth, so the model edge is a
crossing rather than a plateau and [[media-model|V1.5d]]'s extension applies — neither
edge selects and the **interior governs**. Midpoint **0.0150**.

**It is a fixed point, not one reading.** The interval is measured on a path the constant
is on, so it was iterated until the shipped value equalled the midpoint measured at it.
That is stronger than V1.6b's check that the table moves by less than 0.003 when the
constant does.

**`YIELD_UNREST_BETA` = 0.0115.** Both clauses are closed form given two measured inputs,
so the probe prints the crossings rather than bracketing them with whatever the grid
happened to contain — V1.5c's resolution finding taken to its conclusion. Exact crossings
**[0.00343, 0.01951]**, midpoint 0.01147, iterated to a fixed point the same way.

### The cross-check nearly agrees, which this session did not expect

The empirical literature puts a sovereign spread at 2–5 basis points per point of
debt-to-GDP, i.e. 0.02–0.05 here, against a swept **0.0150** — a factor of 1.3 below the
low end rather than the order of magnitude a model-driven band usually lands from the
world. Recorded as a cross-check and never as the selector.

**What excludes an empirically honest 0.02 is clause (ii), and the limit is the opinion
model's resolution rather than the bond market.** At 0.02 a do-nothing president's debt
service moves 3.04 points of GDP over fourteen years, so one channel would use half of
`DEFICIT_SCALE_PP`'s whole span on its own. [[cycle-model|V1.6a]]'s legibility floor from
the other side: there the model could not reach the world, here it cannot afford to.

## 5. What the yield reaches, measured

`tools/credit_probe.gd` table (a), fourteen years, shipped constants. Regimes marked (\*)
are ones the electorate removes in 2027, named rather than assumed —
[[unrest-model|V1.5c]]'s blind spot avoided rather than repeated.

| regime | yield | spread | debt gap | Δ service | rating |
|---|---|---|---|---|---|
| `austerity` (\*) | 0.24 | −1.76 | −156.7 | −2.42 | AAA |
| `hands_off` | 3.19 | +1.19 | +63.4 | +3.36 | BB+ |
| `managed` | 2.34 | +0.34 | +16.7 | +0.77 | A |
| `tinkering` | 3.59 | +1.59 | +76.9 | +4.54 | BB |
| `managed_then_spendthrift` | 7.87 | +5.87 | +365.7 | +34.85 | B |
| `ruinous` (\*) | 25.00 | +120.5 | +8012 | +1986 | CCC |

**Both guard rails are slack on every reachable regime**: the peak is 7.87 against a
`YIELD_MAX` of 25.0 and the trough 2.005 against a `YIELD_MIN` of 0.0.
[[defence-model]]'s and [[companies-model]]'s treatment of their own clamps.

### The floor is 0.0, and it stops a sign inversion

The first version was −1.0, on `INFLATION_MIN`'s argument that a reward should keep
accruing. The probe found the bug that makes it wrong: `Budget.recompute()` computes
`yield × debt_eur_bn / gdp_eur_bn`, and a player who runs surpluses long enough drives
`debt_eur_bn` **negative** — `austerity` reaches −58 % of GDP. Two negatives multiply, so
**a treasury holding net assets would have paid interest on them.**

A floor at zero makes that quadrant unreachable, and the economics agrees for free: a
spread over the anchor is a **credit risk** premium, and a government with no debt has no
credit risk to price. The reward direction survives and is large — 2.0 down to 0.0 is the
whole of the anchor. What it cannot do is go past free.

## 6. The rating is one extra read, and staying that way is pinned

`Credit.rating(ns)` returns a band label off the yield. No `tick_month()`, no stored
rating, no downgrade record, no message card, no `PRECONDITION_FIELDS` entry —
`Defence.allies()`'s shape, which the V1.6 decomposition names by name as the difference
between (c) shipping and (c) splitting. Detecting a band **crossing** needs a remembered
previous rating, and that is a stateful module.

`tests/test_credit.gd` reads the file and fails if a `tick_month()` appears or if
`credit.gd` assigns to `NationState`; `tests/test_save_load.gd` asserts the save carries
no yield, no spread and no rating. **The split trigger is pinned in the save format, not
only in the docs.**

What the rating is *for* is legibility. The yield moves in fractions of a point and the
spread smaller still, so a letter changing is the event a player can see —
[[society-model]]'s *a level alone is a number with no units the player can act on*, a
fifth time.

The anchor is 2.0 and therefore `A`, so **every game opens on the same letter** and the
letter then says something about the player rather than about the content. Table (i)
checks every band is *reached* by some regime; the first set of edges left `B` unreached,
which is why the shipped edges are the second. The check itself needed a correction —
reading two sampled horizons reported `AA` unreached when what it had found was that no
regime happens to *end* there. **A rating a run passes through is a rating the player
sees.**

## 7. The price is an existing line, and it never reaches the economy

The yield reaches the player through `ns.debt_service_pct_gdp`, which
`Budget.recompute()` has computed since the MVP. **No new budget line, no new effect
channel, no new `ISSUE_KEYS` entry, no `PRECONDITION_FIELDS` entry.** It reaches the
electorate only through `deficit_pct_gdp` and the `public_finances` issue that already
prices it. [[unrest-model|V1.5]]'s inverted rule — *ship a statistic and the price it
charges* — and §6 runs (a), (b) and (c) under it.

**It reaches the budget and never the economy**, which is worth stating because a reader
will look for a growth addend and not find one. `debt_service_pct_gdp` is not one of the
five player-set spending lines, so `Budget.commit()` never writes it into
`demand_impulse_pct` and there is no ninth addend in `economy.gd`'s growth sum.
`tests/test_credit.gd` asserts no file in `src/sim/` outside `budget.gd` reads
`Credit.`, so a session wanting a growth channel has to come and say so.

That also answers the question the session was handed out loud. **A yield reading
inflation does not lift [[inflation-model]]'s GDP-axis floor**, and the reason is
structural rather than numeric: there is no path from the yield to GDP at all. Table (b)
measured it anyway on the opinion path — where the money does go — and the largest
approval move at any candidate slope is under 0.15 points.

What it *does* reach is [[bloc-model]]'s `deficit_pct_gdp <= 3.0` rule. **A downgrade can
put the player in breach of something Brussels passed**, which is [[companies-model|
V1.4c]]'s nationalisation doing the same in a new place.

## 8. V1.4c's obligation, discharged on a rate

[[companies-model|V1.4c]] set the dividend yield **on price** exactly equal to
`DEBT_REAL_RATE_PCT`, so the treasury neither gained nor lost on a nationalisation — the
honest model *only while there is no risk and no cycle*. [[cycle-model|V1.6a]] then
refuted the procyclical half: a dividend expressed as a share of GDP cancels, because the
cycle moves numerator and denominator together. The obligation arrived here whole, with
one extra thing to answer — price the premium on something that is not a GDP share, or
say out loud there is no channel.

**A rate is the one quantity in this model that is not a share of GDP**, and this is the
session that makes one move. The dividend stays fixed a measured distance above the
anchor while the **borrowing** rate floats:

```
DIVIDEND_YIELD / PRICE_TO_OUTPUT × 100 == DEBT_REAL_RATE_PCT + EQUITY_PREMIUM_PCT
0.0312         / 1.00             × 100 == 2.00 + 1.12 == 3.12
```

`tests/test_credit.gd` **pins the identity** rather than the constants file asserting it.

While the spread is under the premium the state gains on the flow; once it is above, the
debt that bought the firm costs more than the firm returns. **The crossing is exact and
needs no simulation** — the two rates meet precisely where `spread == EQUITY_PREMIUM_PCT`.
V1.4c's strictly-dominated shape does not come back, because which side you are on is a
consequence of your own fiscal record rather than a constant.

The kill switch — *ship 0.0 and record that there is no channel* — was pre-committed and
**did not fire**. Two clauses close the interval from opposite sides:

- **not free**: `hands_off`'s peak spread (1.192) must exceed the premium, so a president
  who does nothing for fourteen years ends up losing on the flow;
- **not pointless**: the extra revenue is ≥ 0.05 points of GDP at the largest holding
  France can actually take — Banque Méridienne at `state_share` 1.0, 0.0952 points of GDP
  at the anchor — which is [[companies-model]] table (m)'s own readability floor, applied
  to the increment because the increment is what shows on the budget panel's dividend row.

Exact crossings **[1.05086, 1.19225]**, midpoint **1.12**, iterated to a fixed point.

**Clause (i) was tightened from what the probe pre-committed, and the change is recorded
rather than hidden.** It read *some reachable regime*, and the only regime exceeding a
high premium is one that survives exactly one term — a clause satisfied by the most
extreme row in the set is a bound and not a selector, which is [[society-model|V1.5a]]'s
`CORRUPTION_DELIVERY_BETA` failure. Naming `hands_off` makes it select, and it makes the
better claim: **doing nothing for long enough turns a nationalisation into a loss.**

1.12 is well under a real-world equity risk premium of three to five points, and that is
the honest place for it: this model still has no equity risk to compensate for beyond the
sovereign's own.

## 9. `SAVE_VERSION` 20 → 21, on one field

`start_debt_to_gdp_pct` earns it, and it is the smallest addition on that list ever to —
a single float with no register behind it. Absent it reads 0.0 against a live ~140, so
the debt gap reads the whole stock as newly borrowed: the yield comes back at **4.1
against a kept 2.4**, a France paying seventy per cent more interest for the rest of the
run because it saved. `cycle_amplitude_rel` at V1.6a and `military_capability` at V1.3g.

Re-deriving on load does not rescue it, and that is what separates it from every derived
price on that list: the live ratio has moved, so re-anchoring on it would silently
forgive every point of debt the player has added.

**What was not added is the half worth pinning** — no stored yield, no stored spread, no
stored rating. `tests/test_save_load.gd` asserts those three absences.

The first draft of that check said the absent field puts the yield *on the clamp*. It
does not; it puts it at 4.1. **Measured rather than asserted**, and the check is written
against the number instead.

## 10. The re-baseline

Predicted before it ran: **not bit-identical, in every regime.** The spread is non-zero
from month 2 wherever the debt ratio has moved, and it has moved in all of them.

| | |
|---|---|
| Regimes bit-identical | **0 of 29** |
| Presidential outcome lines | 48 |
| Outcome changes | **1** — `tinkering` 2032, 24.6 HELD → 23.5 LOST |
| Largest vote-share move | **1.10 points** |
| New regimes needed | **0** |

The one change is the mechanism read politically, and it lands on the right regime:
`tinkering` is the budget whose whole point is that churning every line produces a
*worse* deficit than doing nothing, so a bond market that charges for it is the model
working. `tests/test_balance.gd`'s `_check_a_ruinous_budget_loses()` still passes.

**The column-by-column split is the sharpest confirmation §7's claim could have got**,
and it was not predicted this cleanly. Over 217 printed year-rows across all 29 regimes:

| column | identical | worst move |
|---|---|---|
| growth, trend, unemployment | **217 / 217** | 0.00 |
| GDP | **216 / 217** | 1 EUR bn, `tinkering` 2032 |
| debt | 4 / 217 | +238.8, `ruinous` |
| deficit | 0 / 217 | 142.7, `ruinous` |
| approval | 28 / 217 | **3.20**, `hands_off` |

**Growth, trend and unemployment do not move at all**, because there is no path from the
yield to them — `debt_service_pct_gdp` is not a player-set line, so it never enters
`demand_impulse_pct` and `economy.gd`'s growth sum gained no addend. What moves is the
debt stock, the deficit that services it, and the approval that prices the deficit. The
single GDP row is a one-unit rounding on the regime whose election flipped.

`hands_off` is the largest reachable mover and reads exactly as designed: debt 156.3 →
**162.7**, deficit −5.54 → **−7.08**, approval 45.5 → **42.3**, and GDP identical to the
euro at 3343. A president who does nothing is charged for it, and is charged on the
books rather than in the economy.

**No thirtieth regime**, which V1.6a and V1.6b also found: a yield is not a verb, so
there is nothing for a regime to issue.

## 11. The readout, and the twelfth screenshot pass

One caption on the economy panel's PUBLIC FINANCES column, directly under the
debt-service line, because that is the line it explains — the panel reads in the order
the model computes in, which is the discipline [[inflation-model]]'s caption established
one session ago.

**Never silent**, which is the dependency ratio's and inflation's rule rather than the
delivery lines': every game has a borrowing rate from the first frame, so a line that
appeared only once it moved would hide the level the spread is measured against. It leads
with the **rating**, and turns red once the letter has fallen out of the band the anchor
sits in — a threshold named by the model rather than invented for the panel.

Two decimals on the yield and on the spread, chosen against table (a)'s reachable range
rather than copied from the neighbouring row, which is V1.6b's own screenshot bug one
session old: `managed` runs at +0.33 for fourteen years, so one decimal would print two
distinct values of the figure a well-governed run ever shows.

`tools/screenshot.gd --downgrade` runs a debt-widening budget forward **40 months** —
measured off table (i), which puts `hands_off` into BB+ at month 64, so a spendthrift
budget clears the opening band with room and stops short of the spiral. Both failure
directions are already on this project's record and both were checked: V1.4c's flags
ticked without advancing the clock, and V1.6b's `--inflate` ticked *past* its subject.

The pass found **no bug**, which is the first time in twelve sessions and is reported as
such rather than dressed up. It confirmed both halves of the claim: unflagged the panel
reads *"Rated A. Borrowing at 2.00 %, +0.00 on the anchor"* in plain text, and under
`--downgrade` at May 2029 with debt at 169.6 % it reads *"Rated BB. Borrowing at 3.23 %,
+1.23 on the anchor"* in red.

## 12. What is deliberately not built

- **No monetary policy and no verb at all.** [[mechanics-economy]] tiers the central
  bank, interest rates and quantitative easing *Someday*, and [[out-of-scope-mvp]]
  records that France does not set its own rate.
- **No stored rating and no downgrade card.** An edge trigger needs memory, and memory
  here is the second machine the decomposition says would have split this session.
- **No `PRECONDITION_FIELDS` entry.** The session ships no verb, so there is nothing to
  gate, and no content asks to be gated on market confidence.
- **No per-nation yield.** Only the player has a budget, so the other nine would carry
  nine frozen letters. The spread is computed on demand from `ns` alone and costs nothing
  for a nation nobody reads it for.
- **No `trends.gd` `WATCHED` entry.** `debt_to_gdp_pct` is already watched and the yield
  is a function of it, so a second row would be the same movement counted twice.

---

Related: [[index]] · [[economy-model]] · [[cycle-model]] · [[inflation-model]] · [[companies-model]] · [[bloc-model]] · [[unrest-model]] · [[decision-log]] · [[ROADMAP]] · [[v1]]
