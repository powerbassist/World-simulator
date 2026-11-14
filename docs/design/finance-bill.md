---
title: The finance bill — the budget goes through a vote
tags:
  - design
  - v5.3
  - budget
  - legislature
---

# The finance bill

**Status: accepted 2026-11-14 (the parent's go: (a) on all six calls; call 4 amended, the tax library of section 9 and the autumn gate are PR 1b, right after PR 1). Sections 1 to 4, 6 and 7 are built in PR 1 (Systems).** The author's call 1 for screen 4 (2026-11-14, on Gameplay's brief `F:/Dev/autoclaw-out/mockups/laws/brief.md`, row H10): pending budget and tax changes become one text, the finance bill. It takes the month's slot, divides at the month's end, and applies before the next month's books. The Assembly reads it by its channels, and forcing (49.3) is allowed where the constitution allows it, by a field in data. Read on `main` at `4f2b8df4`. The figures in sections 3 and 6 come from throwaway scans (`APPDATA` isolated, no code changed). The calls for the parent are in section 8.

## 1. What is pending

Today `Budget.commit(state, pending)` applies the budget and tax panels' absolute values at once. Under this spec the panels' Commit **tables a finance bill** instead, through a new player command:

`FinanceBill.table(state, loader, bill: Dictionary, force := false) -> Dictionary`

- **The bill is a set of DELTAS, not absolute values**: `{"tax_rates_pct": {key: Δpoints}, "spending_pct_gdp": {key: Δpoints}, "tax_progressivity": Δ}`. `FinanceBill.from_pending(ns, pending)` turns the panels' absolute pending values into deltas against the live register at tabling. A rate that a law, an event or a repeal moves between the tabling and the division keeps that move: the bill adds its delta on top (`Legislature.apply_effects`' rule; Statute's channels are deltas for the same reason).
- **What rides the bill:** every tax rate (the authored keys and composed ones), every spending line, and the progressivity schedule. **What does not:** sector share moves inside a line (`Sectors.move_share`: an allocation, not a total, and the executive's job, so they stay immediate), the regional fund's levels (their own verb), an event choice's fiscal effects (a decree, immediate), and a tax's birth or abolition (section 5).
- **Kept as it is:** `Budget.commit` stays the applier and the setup verb for harnesses and copies (`Budget.preview`, `EffectsStrip.books`, the dev console), as `Legislature.apply` is for laws. Only the player's panels and the two balance harnesses (section 7) move to the vote.

## 2. The slot, the division, the date it applies

- **The slot:** the bill is written into the existing register `ns.tabled_bill`, so the V5.2 b+ R2 rule (one player bill before the Assembly at a time) covers it with no new check. A law tabled this month refuses the finance bill (`already_tabled`), and the finance bill refuses a law. PR 2 replaces this with the queue of three.
- **Its id:** `finance:<absolute month>` (`year * 12 + month`), one id per tabling, so a pledge, an address or a measure poll on this year's bill never attaches to next year's. `Bills.open()` rebuilds the tabled finance bill as a `Law` (the `ownership:` precedent), so `Legislature.open_law`, the forecast, `Address`, `Deal` and the UI readers of `tabled_bill` find it unchanged.
- **The division:** at the close that ends the month, as the first step (`Division.divide`, which branches on the prefix to `FinanceBill.divide`).
- **When it applies:** if carried, at once inside that close, through `Budget.apply_pending` (live value + delta: the floors, the yield gate and the demand impulse all unchanged) and `Budget.recompute`. The close's Economy and Budget steps read it, so it is the first thing the next month's books show. For a player that means a change lands at the month's end instead of the instant they press. For the balance probe, which commits before its first tick, the bill divides at that tick's first step, the same tick that read the committed budget, so a bill that passes at once changes no timing there.
- **No political price at passage.** The opinion model already reads the budget per bloc through its issues; adding `Statute._derived_price` as a `bloc_offset` would charge the same cut twice. The channel price is not used at all in PR 1.

## 3. How the Assembly reads it

**Measured first, the card's face-value reading** (the bill as a law at a position derived from its channels, through the unchanged `resolve_vote`): it fails Britain's and Germany's own budgets. At the coalition's own centroid with no change at all, Britain divides 247 to 366 and Germany 317 to 313. This is not new: at game start Germany passes **1** of its 104 available authored laws and Britain **5** of 106 (France 61 of 105, Poland 71 of 104). Their coalitions are wide, so a partner sits far from the centroid (Britain's Liberal Union reads -0.46 spatially), and the whip on a law is worth at most `COALITION_BONUS_MAX` 0.45. Under that reading a British or German player could never pass a budget and cannot force one. The law-pass rate itself is a RECORD for the parent (section 8, call 5); it is not this PR's to tune.

**The reading this spec proposes: the bill is read like a law, and whipped like a confidence vote.** Every European parliament treats the budget as a matter of confidence (Britain's supply, Germany's coalition agreement, France's 49.3 tied to a censure motion, Poland's Art. 225 dissolution on no budget). So:

- **A party's support** = `Legislature.spatial_support(ns, party, bill)`, the law reading at `LAW_SIGMA`, unchanged;
- **plus, for a coalition partner, the censure whip** `Government.hostility` already carries: its live `Discipline.of(ns, party)`, minus `DISAFFECTION × unpopularity × (1 - discipline)`. The opposition gets no whip;
- **the rebel split** reads the same terms unwhipped (`hostility(whipped = false)`'s rule) through `Discipline.rebel_seats`, and the tally goes through `DivisionTerms.seats_of` with the pledged seats and the address's sway, so a pledge bought in an audience and an address to the nation work on the budget exactly as on a law. No size peel (a budget has no authored reference size);
- **majority:** simple (`yes > no`), every nation.

**The bill's position** = the coalition's agreed position (`ns.coalition_position`), moved toward where its content sits:

`position = centroid + t × (anchor_mean - centroid)`, with `t = min(1, size / FINANCE_REF_SIZE)`

- `anchor_mean` is the mean of each line's anchor position, weighted by `|Δ| × Statute's CHANNEL_COST` (the same size arithmetic as `Statute._size_of`).
- The anchors are cited from the authored laws, one row per line and direction, in `src/sim/finance_bill_constants.gd`: income up (high_earner_surtax, econ -0.6), corporate down (corporate_tax_cut, +0.6), VAT up (vat_consolidation, +0.3), wealth up (wealth_levy, -0.7), capital gains up (capital_gains_surtax, -0.5), pensions down (retirement_age_reform, +0.45 / +0.25 social) and up (pension_uplift_act, -0.45 / +0.1), health up (health_service_reform, -0.3 / -0.1), education up (student_grants_act, -0.4 / -0.3), infrastructure up (the mean of the twelve infrastructure movers, about -0.22 / -0.15; the scans used a rounded -0.25 / -0.1); each opposite direction mirrors its row. Defence has no authored mover: +0.3 social for a rise is authored judgement, flagged. A composed tax key reads the income row (the anchor row of `CHANNEL_PRICE` too). Progressivity reads the income row, weighted as if a full-range move were 5 income points (authored judgement, flagged).
- `FINANCE_REF_SIZE` = 1.0, high_earner_surtax's size: a bill that big reads wholly as its content; a small bill stays at the government's own place. The scans read the same verdicts at 0.5 and 1.0.
- **Known limit, stated:** a budget that cuts on one side and taxes on the other reads near the centre, because the anchors average. Its pain is the opinion model's, which already prices each line per bloc.

**The court:** a finance bill's `reach` is 0 (`Law._reach_of` reads no budget channel), so `Judiciary.strikes_down` never strikes it. Same pipeline, no new rule.

**The second chamber:** the finance bill skips it, in every nation. A suspensive hold today lasts `UPPER_HOLD_MONTHS` (12), which on a budget is absurd, and in all four playable nations the lower house has the last word on money (France Art. 45 and 47, Britain's Parliament Act 1911 s. 1, Germany Art. 77(4), Poland Art. 121 and 223). This is a **recorded reduction**, Germany's Art. 79(2) shape: Italy's Senate must pass the budget too and this model does not ask it. The alternative is a data field on the nation's upper block (section 8, call 3).

## 4. Forcing (49.3)

- **Where:** where `Government.can_force(ns)`'s data rule allows it: the nation's `government.formation.method` is `presidential_appointment` (France among the playable four). That is the field in data this spec reads; no nation id.
- **When:** the player engages it at tabling (`table(..., force = true)`). The bill still waits for the month's end. At the division it is adopted with no vote taken, and the censure motion is resolved then, at `FORCE_HOSTILITY_BONUS`, with the price an ordinary 49.3 pays (`FORCE_BLOC_PENALTY`, `FORCE_DISCIPLINE_PENALTY`, the rebellions charged). Forcing at once would bypass H10 in France; that is refused.
- **A carried censure kills the bill** (the government falls; the budget does not apply): the December 2024 sequence. A failed censure applies it.
- **The cooldown:** the finance bill neither reads nor writes `force_cooldown_months` (Art. 49.3 al. 3 as amended in 2008: unlimited on finance bills, once a session on other bills). Section 8, call 2.
- **The order differs from an ordinary 49.3, on purpose.** `Legislature._force` applies the law first and resolves the censure after, so a carried censure leaves the law in force. The finance bill resolves the censure first and applies only if it fails. The price itself (the bloc and discipline penalties, the rebellions) moves into one shared function, so the two forcings cannot drift on what they charge.

## 5. Taxes: the autumn rule

The author's call: a tax is created or abolished only in the autumn finance bill (signed in V5.3 e); a rate changes through any finance bill. **PR 1 builds the second half only.** Births today are composed laws (`Statute.draft` with `new_tax`, the Tax Code's "Propose a tax"), and V5.3 e replaces that path with the catalogue of real taxes (`data/taxes/`). Gating today's path to one month would make the autumn birth compete with the autumn finance bill for the same slot. **Proposed for V5.3 e:** a per-nation data field `government.finance_bill.autumn_month` (France 10, the PLF's tabling month); the autumn finance bill is the one text that may carry a birth or an abolition from the catalogue; the composed birth path retires. The catalogue's schema is section 9. Section 8, call 4.

## 6. What a failed bill leaves, and what moves

**A failed finance bill:** the live budget stands unchanged, as France's loi spéciale and Germany's provisional budget roll the previous year's on. No cooldown: the month's slot was the price, and the player may table it again next month. The division's result lands in `ns.last_law_result` with the bill's deltas copied in, so a panel can offer to table it again. Rebellions are charged as on any division.

**At game start (measured, the reading of section 3 with the rebel split, the nine base regimes that table something, in each playable nation; `hands_off` tables nothing):**

| nation | coalition seats | regimes that fail | rebels on a passing budget |
|---|---|---|---|
| France | 318 / 577 | none (yes 261 to 417) | 6 to 26 seats, 16 on `managed` |
| Germany | 390 / 630 | spend_zero (233 to 261) | 23 to 38 |
| Britain | 364 / 650 | tax_max (281 to 299) | 13 to 40 |
| Poland | 248 / 460 | tax_max (230 to 230, a tie fails), spend_zero (207 to 253) | 0 to 6 |

So **32 of 36** pass at the start. Partners whose own members would vote no if unwhipped (France's social democrats and greens on `managed`, Germany's and Britain's liberals even at the centroid) follow their whip, and a share of their seats rebels: every carried budget charges discipline (`Discipline.penalise_rebellions`), as every division does.

**France under stress (same scan, the nine regimes):**

| state | budgets that fail |
|---|---|
| start | 0 of 9 |
| approval 30 % | 3 (austerity, spend_max, ruinous) |
| approval 20 % | 5 |
| discipline after one 49.3 | 0 |
| after three 49.3 | 2 (tax_zero, spend_zero) |
| three 49.3 and approval 25 % | 7 (only `managed` and tax_max pass) |
| the social democrats leave the coalition (minority) | 5 |

So **a majority with its whips intact passes almost every budget; the vote bites once the government is unpopular, once forcings and rebellions have worn discipline down, or once the majority is gone.** That is how budgets behave in real parliaments, and it is where the vote becomes a decision: the forecast before tabling says who leaves and why.

**Prediction for the re-baseline (to be measured base vs tip before merge):**

- **`hands_off` cmp-identical**: it tables nothing, the control.
- **Every other regime moves a little**, and not because its budget fails: in the probe's France all nine pass at the first tick, at the same step the commit was read, but each carried budget charges 6 to 26 rebel seats to discipline in month 1, and lower discipline then reaches every later division and censure. Expect small moves in vote shares and possibly a flip where a later division or censure was close. The regimes that switch budget mid-run (`_switch_budget`) meet a later, possibly unpopular coalition and may fail outright: the likeliest larger movers.
- **The author was told "every regime moves".** True, but mostly through the discipline charge; no regime's budget is refused at the start in France. The game changes more for the player than for the probe: a month's wait, a vote that bites as the coalition weakens, the extremes failing in Germany, Britain and Poland.
- **Density (`decision_surfaces_probe.gd --density`), lever and audience probes:** unchanged unless their regimes commit a budget; checked at build. The corruption bands are not touched.

## 7. The harnesses, the save, the UI

**Moved to the vote:** `tools/balance_probe.gd` (its regimes and `_switch_budget`) and `tests/test_balance.gd`'s `_play`. A regime tables its bill in month 1; if it fails, it tables it again each month until it passes (section 8, call 1), and the run's JSON gains `"budget": {"landed": "YYYY-MM" or "", "tries": n}` so `balance_diff.py` shows a regime that never landed. **Left on `Budget.commit` as setup:** the other twenty probes and twenty-odd tests: their questions are about the economy, not the vote.

**The save:** no new NationState field. The bill lives inside `tabled_bill` (`DEEP, COPIED, {}, absent_ok`): an older save carries no `finance` payload, so its tabled bill reads as the law it was, which is correct. `last_law_result` carries the deltas on a failure, same shape plus one key. **No `SAVE_VERSION` bump.** `tests/test_save_load.gd` pins a tabled finance bill's round trip.

**The UI, minimal in PR 1** (Interface rebuilds screen 4 after its pictures): the Budget's and the Tax Code's Commit become "Table the finance bill", one bill carrying both panels' drafts (the Budget already reads the Tax Code's `draft()`); `main.gd`'s commit shortcut does the same; the Legislature list shows the tabled bill through the readers it already has. Interface gets the names before the build.

**Tests (TDD, mutation-checked):** the slot (a law refuses the bill and back), deltas against a rate moved after tabling, the division's tally against the reading of section 3 (a partner whipped, the opposition not), a carried bill applies at the close and not before, a failed bill leaves the books, forcing waits for the close, a carried censure kills the bill, no cooldown written, the second chamber skipped, the save pin, `hands_off` identical.

## 8. Calls for the parent

1. **A regime's failed bill:** (a, recommended) re-table every month until it passes, recording the month it landed; (b) stay failed; (c) force where allowed. With (b), the failing extremes become `hands_off`, and a stress check that runs one of them proves nothing. With (a), each retry is a division and charges its rebels, so a regime that keeps failing wears its own discipline down month after month: that is the real cost of insisting, and the JSON's `tries` shows it.
2. **49.3 on the finance bill:** (a, recommended) free of the 12-month cooldown (France's 2008 rule), the same price otherwise; (b) the ordinary cooldown, one forcing a year.
3. **The second chamber:** (a, recommended) skipped in every nation, Italy's Senate a recorded reduction; (b) a data field `government.upper.finance` (absent = no power), with rows for the equal-chamber nations.
4. **Tax births and abolitions:** (a, recommended) unchanged in PR 1; the autumn gate and the catalogue together in V5.3 e; (b) PR 1 gates today's composed births to an autumn month now.
5. **The reading (every call above depends on it):** (a, recommended) the position from the channels, the whip the censure's (section 3); (b) the card's plain law reading through the unchanged `resolve_vote`, which needs the law model fixed first: under it Germany and Britain cannot pass even an unchanged budget. **RECORD with it:** at game start Germany passes 1 of its 104 available laws and Britain 5 of 106. That is screen 4's laws problem in those nations, not the budget's, and it needs its own owner.
6. **What a defeat costs:** (a, recommended) nothing beyond the month's slot and the rebellions charged, re-tabling allowed next month; (b) a cooldown of N months, or a bloc or approval price on a lost budget. With (a) a defeat is cheap to retry; the cost is the month lost and the discipline the rebels take.

Open RECORDs from #326 (`pay_offer` ignores register refusals; `take_reason` duplicates `President._party`; the corrupt bargain with money open has no test; the per-read cost) touch none of this PR's files; they fold into the first later PR that opens `shadows.gd` or `deal.gd`.

## 9. The tax library (the author's call, 2026-11-14; built in V5.3 e)

**One library of tax kinds, each kind written once; each nation only says which kinds it has in force and at what rate.** No per-nation code, no per-nation copy of a kind's model. Content fills the rows against this schema; Systems wires the readers. Nothing in this section is built by PR 1.

### 9.1 A kind: `data/taxes/<id>.json`, one file per kind

```json
{
  "id": "vat",
  "name": "Value added tax",
  "summary": "A tax on consumption, collected at every stage of sale.",
  "rate_meaning": "statutory standard rate",
  "who_pays": ["workers", "pensioners", "rural", "students"],
  "base_share": 0.53,
  "erosion": 0.25,
  "zero_ref_pct": 20.0,
  "rate_range_pct": [0.0, 40.0],
  "demand_multiplier": 0.70,
  "opinion_scale_pp": 16.0,
  "bloc_salience": {"workers": 0.08, "pensioners": 0.08, "rural": 0.11, "students": 0.10},
  "progressive": false,
  "finance_anchor": {"up": {"economic": 0.3, "social": 0.0}, "down": {"economic": -0.3, "social": 0.0}},
  "reference": {"_source": "OECD Revenue Statistics, 5110", "yield_pct_gdp": {"FRA": 7.1}, "_note": "..."}
}
```

The figures in the example are VAT's as the model carries them today: its base, erosion, reference rate, multiplier, scale, the four blocs' salience and the Tax Code's 40-point ceiling. The `reference` yield is illustrative; Content sources it.

| field | what reads it | today's home (moved, values unchanged) |
|---|---|---|
| `id` | every reader of a tax key; `tax_<id>` is its opinion issue | `economy_constants.TAX_KEYS` |
| `name`, `summary` | the Tax Code, through `Strings.row("tax", id, ...)` | `opinion_constants` issue labels |
| `rate_meaning` | the panel's label, and Content's check that `base_share` matches it (an effective average or a statutory rate) | new, display only |
| `who_pays` | the panel and the effects strip: the blocs the kind falls on | new, display only; every bloc named needs a `bloc_salience` weight |
| `base_share` | `Budget.revenue_lines`: yield in % of GDP per rate point at the reference | `TAX_BASE_SHARE` |
| `erosion` | `Budget._erosion`: base lost per unit of relative rate rise | `TAX_EROSION` |
| `zero_ref_pct` | `_erosion`'s reference when the nation's start rate is 0 | `EROSION_ZERO_REF_PCT` |
| `rate_range_pct` | the loader's range check, the slider, the finance bill's floor and ceiling | `nation.gd`'s `MAX_TAX_RATE_PCT`, `WEALTH_RATE_MAX_PCT`, the panels' `LEVER_MAX` rows |
| `demand_multiplier` | `Budget.apply_pending`'s demand impulse | `MULT_TAX` |
| `opinion_scale_pp` | `Opinion`'s satisfaction scale for `tax_<id>` | `TAX_SCALE_PP_BY_KEY`, else the shared `TAX_SCALE_PP` |
| `bloc_salience` | each bloc's weight on `tax_<id>` (the "bloc reads") | the `tax_*` rows of `BLOC_SALIENCE_BASE` |
| `progressive` | the progressivity factor applies to this kind's base (income alone today) | the `key == "income"` test in `revenue_lines` |
| `finance_anchor` | the finance bill's position (section 3) | `finance_bill_constants.gd` from PR 1 |
| `reference` | Content's yield check and the REUSE provenance; nothing in `src/` reads it | new |

**The loader refuses:** a duplicate id; an id among the computed revenue lines (`other`, `tariffs`, `dividends`, `Budget.COMPUTED_REVENUE_LINES`); an id outside `[a-z0-9_]{2,24}` (the ledger's pipe rule); a `who_pays` bloc with no `bloc_salience` weight; a salience row that breaks a bloc's renormalisation; a `rate_range_pct` with no room.

**The check every row must pass** (Content's; a test pins it): `base_share` times the nation's rate reproduces the kind's real yield in % of GDP, within a stated band, for each playable nation that has it in force, against the row's `reference`.

**Order is data too.** Every revenue and opinion sum runs in dictionary order, so the library loads in a fixed order: today's five first, in today's order (income, corporate, vat, capital_gains, wealth), then the new kinds by file name. That keeps the five's arithmetic byte-identical when new kinds exist.

### 9.2 A nation: which kinds, at what rate

`fiscal.tax_rates_pct` keeps its shape, `{kind id: rate}`. **A kind listed is in force; a kind absent is not.** An absent kind may be created only in the autumn finance bill, and a kind in force may be abolished only there (section 5). A listed rate of 0 is a kind in force at 0: a lever any finance bill may raise, which is what every nation's zero wealth row is today.

- **The four playable nations** get researched rows (Content): the kinds really in force and their real rates, each with its source.
- **The default for the other 37:** today's five rows exactly as they stand (VAT each nation's own, income and corporate France's scaled, capital gains and wealth as authored), and **no new kind in force unless that nation's data lists it.** The 37 move nothing.

### 9.3 The revenue anchor: how a kind in force is carved out of it

Today `GameState.new_game` sets `other_revenue_pct_gdp = fiscal.tax_revenue_pct_gdp - Budget.modelled_revenue_total(rates, start_rates)`: the residual absorbs whatever the modelled taxes do not explain, so starting revenue equals the real figure. **The library keeps that rule and widens the sum:** `modelled_revenue_total` loops over the kinds the nation has in force (library order) instead of the five keys. A kind in force at start with a real rate adds its yield to the modelled total, and the residual shrinks by exactly that much. **Total revenue at new game is unchanged:** the kind moves money from "other" into its own line and adds none. (Exact to the bit only if the residual's subtraction is the last operation, as it is today; the build checks it with `cmp` on the start books.)

- **Nothing moves on day one from the catalogue alone.** At start every kind sits at its start rate: its opinion satisfaction reads 0 (rate minus start), its demand impulse is 0 (raised only by a change), and its yield in % of GDP stays constant until its rate moves, like the residual it came out of.
- **The guard:** the loader refuses a nation whose kinds in force explain more than its `tax_revenue_pct_gdp`; a negative residual would be revenue from nowhere. Content sees it before any run.
- **What does move, and goes to the author as a re-baseline:** a researched rate for one of the five in a playable nation, in place of France's scaled one. The total still starts at the real figure, but the erosion curve is relative to the start rate, so a regime's delta in points yields differently. That is Content's change, measured base vs tip, not the library's.

### 9.4 What goes, and the save

- **`custom_taxes` goes, with the Tax Code's "Propose a tax"** (`tax_compose.gd`, `Statute`'s `new_tax`, `Legislature._register_new_tax`, the custom branches of `revenue_lines`, `_erosion` and `Opinion`). A birth becomes "put a kind from the library in force" in the autumn finance bill: the kind's model is the library's, never the player's.
- **The save: a `SAVE_VERSION` bump** at the PR that removes it. `custom_taxes` is `absent_ok: false` today (bump 38), and a save from before the removal can hold a player-made kind with a live rate under its key in `tax_rates_pct` and a `tax|<key>` row in a composed law's ledger. Loaded without the register, that rate has no model behind it: revenue reads it as nothing and the ledger cannot repeal it. A missing model reads as something wrong, so the bump rule applies and such a save is refused, as every superseded save is.
- **The library itself is not saved.** It is content: `GameState` holds a reference set from the loader at new game and at load, as it does `region_graph`, so a game always reads the library it is loaded with.
- **Every reader of `C.TAX_KEYS` reads the library's ids instead** (about fifteen sites: the nation, law, event and programme loaders' key checks, `Budget`, `Opinion`, `Pledges`, `Statute`'s channel check, the Tax Code). Statute's composed tax channel retires with the rest: from V5.3 e a rate moves only through a finance bill.
