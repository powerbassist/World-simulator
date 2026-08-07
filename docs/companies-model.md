---
title: Companies Model
tags:
  - model
  - economy
---

# Companies Model

**V1.4a.** Named private firms partitioning a sector, a standing subsidy as the
player's first verb, and the two channels through which a firm reaches the
national economy. `src/sim/companies_constants.gd` holds the values; this page is
the argument.

Related: [[economy-model]] · [[people-model]] · [[coercion-model]] ·
[[defence-model]] · [[data-architecture]] · [[fictionalization]] · [[v1]] ·
[[ROADMAP]]

## 1. The first content class that fronts nothing

[[people-model|U6b]]'s "no new effect channel" held because every named person was
the **face of something the game already shipped** — a leader fronts a nation, a
party leader fronts a party. A firm fronts nothing. So V1.4 owns a channel,
`effects.company`, and scoping it was the decomposition's real work.

The answer is the one `data/diplomatic-actions/` has been giving since V1.3a:
**one action directory, one shape, many sessions.** That directory served V1.3a,
b, c, f and g — ten verbs, five sessions, no new content type — and
`data/company-actions/` is meant to serve V1.4a, b and c the same way.

`src/core/company_action.gd` mirrors `src/core/diplomatic_action.gd`, and what it
does **not** borrow is as deliberate as what it does:

| Not borrowed | Because |
|---|---|
| `effects.relations` | Required there, absent here. A subsidy is a domestic act with no pair to move; borrowing it would give the block a foreign-policy vocabulary for a mechanism with no counterparty. |
| `cooldown_months` | A subsidy is standing **state**, not an event. `subsidy_active` gates it directly, and a cooldown register beside that is two gates on one fact. |
| `position` / `majority` / `once` | An executive act has no assembly division to score — V1.3a's own distinction. V1.4b's regulation **is** a law and gets all three by being one. |

## 2. A firm is four fields, and the count is the design

```
id · name · sector · share · headcount
```

`share` is of its **sector**, never of GDP. `headcount` is jobs at the authored
share, and it is the **differentiator** — the field that makes picking a firm a
decision rather than picking a sector.

Without it every firm in a sector answers alike, and V1.4's subsidy *is* [[v1]]
§6's "sectoral investment — a lever pointed at a sector". That is the clustered
`coalition_position` finding [[foreign-policy-model]] records, caught at design
time rather than by a probe. It is also why `_validate_companies()` **refuses a
sector with one named firm**: a firm with no rival cannot gain share from
anybody, so a subsidy pointed at it is a sector lever wearing a company's name.

Deliberately absent, and each for a stated reason:

- **Revenue.** It is `share × sector output`. Authoring it is one quantity
  written twice — the redundancy [[coercion-model]]'s probe cut when it deleted
  `tariff_rate_pct`.
- **A CEO.** A person is the *face of a firm*, and the mechanism that gives one
  something to do is [[v1]] §5. [[people-model]] §13 already parks it.
- **Any owner, margin or productivity term.** Ownership arrives with the verb
  that changes it, at V1.4c.

## 3. Load-bearing on GDP, without a second reconciliation

Firms are load-bearing rather than decorative: a firm's state reaches GDP and
jobs. The literal reading of that — `sector_output = Σ firm_output + residual`
with free-floating absolutes — is where divergence would come from, because
`Economy._apply_growth_to_sectors()` already reconciles three sectors against the
month's GDP target **exactly**, and a firm layer of absolutes beside it is a
second claim on one quantity.

So a firm holds a **share**, and its output is read through it:

```
firm_output = share × sector_output[sector]
Σ share over one sector's named firms ≤ 1.0    # the rest is the unnamed residual
```

The partition is exact by construction. There is no second reconciliation
anywhere, and a later session naming a seventh firm takes its share out of the
residual and moves no existing number.

What reaches the economy is **two deviation terms**, both of which read exactly
`0.0` until a verb moves something — `trade_baseline_by_partner`'s idiom and
V1.3f's inert-act property in a new place:

| Channel | Where it lands | Reads 0.0 when |
|---|---|---|
| `firm_impulse_pct` | the fifth additive term in the growth equation | no subsidy stands |
| `firm_jobs_offset_pct` | beside `law_structural_offset_pct` in structural unemployment | every firm sits at its authored share |
| `subsidy_bill_pct_gdp` | a computed spending line on the budget | no subsidy stands |

That is what let the whole register go live with the balance harness
**bit-identical across every existing regime**. `tests/test_companies.gd` asserts
exact equality rather than `is_zero_approx`, because a test that accepted 1e-9
would not prove it.

### Headcount follows share, not output

The sharpest call in `src/sim/companies.gd`. Read off the sector **level**, a
firm would hire every month the economy grew — which would make the jobs channel
non-zero in every run ever played, destroy the bit-identity property, and, worse,
be a **second answer to a question the macro model already answers**. Aggregate
employment is Okun's law in `Economy._update_unemployment()`.

What a firm layer adds is **reallocation**: two firms of equal share employ
different numbers of people, so moving share between them creates or destroys
jobs on net. That is the only thing this channel says, and it is the only thing
it should say.

### A subsidy bill is not a sixth spending line

`SPENDING_KEYS` and `PORTFOLIO_KEYS` are **the same list**, so a sixth spending
line is a sixth minister, and [[v1]] §6 rules one out. The bill is a computed
line instead — V1.3c's tariff revenue and V1.3g's deployment bill took the same
route, and this is the fourth. It lags one month behind the budget for the reason
both of those do: `deficit_pct_gdp` is a company action's own precondition field,
so a same-month bill would close a loop through the verb list.

## 4. The probe corrected the model twice, ten sessions running

Every band below was **written before the sweep ran**, so a number landing
outside one is a finding rather than a reason to widen the band.

### (C1) A flat rival floor made the rate meaningless

The first sweep of `SHARE_SHIFT_PER_MONTH` came back:

| rate | FRA | DEU | GBR |
|---|---|---|---|
| 0.0005 | 50.0 % | 23.1 % | 50.0 % |
| 0.0010 | 75.0 % | 46.2 % | 75.0 % |
| **0.0020** | **75.0 %** | **80.8 %** | **75.0 %** |
| **0.0040** | **75.0 %** | **80.8 %** | **75.0 %** |
| **0.0080** | **75.0 %** | **80.8 %** | **75.0 %** |

Three different rates, one outcome. The floor under a rival's share was a flat
`0.0050`, far below the smallest authored share of `0.04`, so a subsidy could
take **ninety per cent of a rival's position** — and the endpoint was set by that
floor rather than by the rate. The clamp-sets-the-number failure
[[economy-model]] records for `IMPULSE_MAX`, and V1.3c's strictly-dominated
severities, in a third place.

The fix moved the **model**, not the number. `RIVAL_FLOOR_FRACTION = 0.50`: a
rival keeps at least half of what it was authored with. Two things fall out:

- The endpoint of a subsidy becomes a property of the **content** — how big the
  rival was authored — instead of a global constant meaning something different
  in every sector. Re-swept, all three nations land at **41.7 / 42.3 / 41.7 %**,
  the centre of the 25–75 % band.
- A two-firm sector can never collapse into a one-firm sector, which would have
  handed V1.4b and V1.4c a register whose rivals had already been driven out.

And the rate goes back to setting **how fast**, which is what a rate is for — so
it had to be re-chosen on a column that did not exist before the correction:
`t90`, months to reach 90 % of the endpoint, banded 12–48. At `0.0020`, t90 is
**25 months**: a subsidy pays off inside a term without being over in a year.

### (C2) One firm out-punching a whole budget

`SUBSIDY_GROWTH_BETA` was 0.30. Measured against a band of 0.05–0.60 %/yr:

| beta | FRA | DEU | GBR | |
|---|---|---|---|---|
| 0.10 | 0.238 | 0.184 | 0.241 | in band |
| **0.20** | **0.476** | **0.368** | **0.482** | **in band** |
| 0.30 | 0.714 | 0.552 | 0.724 | France and Britain over the ceiling |

The ceiling was the half doing work. A subsidy to **one firm** must not out-punch
a whole budget, whose demand impulse runs to several points; at 0.30 one firm was
worth more than a percentage point of every tax at once. Shipped at **0.20**.

### (P3) The kill switch fired the other way — the jobs channel CLEARS

Pre-committed: the jobs channel must reach ≥ 0.05 points of unemployment over
five years on the widest reachable pairing, or it is below the readable floor and
gets **recorded as a bound rather than tuned around** — [[defence-model]]'s
`DEPLOYMENT_OPINION_CHOSEN` finding, where raising a constant until an
arithmetically impossible number moved would have been tuning against the size of
a real electorate. Here it would have been the size of a real labour force.

It cleared, at **0.2286 points** for GBR's retail firm. And the table says why in
a way nothing authored:

| pairing | net jobs | unemployment pts |
|---|---|---|
| GBR Ravenhill (retail) over Sterling Mutual (bank) | +71 300 | **0.229** |
| FRA Halbert (retail) over Banque Méridienne | +53 000 | 0.172 |
| DEU Vollmar (retail) over Hanseatische Bank | +56 500 | 0.150 |
| GBR Ashcombe (engineering) over Tarnbridge (chemicals) | +12 500 | 0.040 |
| FRA Aurignac over Sévrenne (both industry) | +3 000 | 0.010 |
| FRA Verdelis over Grainval (both agriculture) | +643 | 0.002 |

**The services rows dominate by an order of magnitude**, because retail and
banking differ in jobs-per-share by 3.4×, while the industry and agriculture
pairs are nearly matched. Nothing in the model says "services"; the whole
spread comes from two authored headcounts. That is the differentiator earning its
place, and it is the answer to whether a firm layer is more than a sector lever.

The jobs channel has **no tuned constant in it at all** — only
`LABOUR_FORCE_SHARE`, which is a measured participation figure and not a dial,
and a clamp. That is what lets its size be reported as a finding rather than
defended as a choice.

## 5. What a subsidy costs, and who notices

`SUBSIDY_COST_PCT_GDP = 0.30` per firm at full intensity. Anchored against the
tax lines it sits beside on the same panel: `TAX_BASE_SHARE` makes one point of
VAT worth 0.53 % of GDP and one of income tax 0.50 %, so **one tax point is
roughly half a percent of GDP**, and one national champion costs 0.60 of a tax
point. Subsidising the whole French register costs 3.6 tax points.

**The bill clamp is slack**, 1.800 reachable against 2.500 — a second measured
slack clamp after V1.3g's, and `tests/test_balance.gd`'s fifteenth regime asserts
it stays that way over fourteen years.

The politics, measured over a five-year subsidised run against an identical quiet
one:

| bloc | delta |
|---|---|
| workers | **+5.88** |
| business | **+3.52** |
| rural | −0.18 |
| pensioners | −2.30 |
| students | −3.03 |
| urban | **−3.57** |
| **HEADLINE** | **+0.76** (noise floor ±3.0) |

The expectation was written down before the run and **held exactly**: a subsidy
to one firm does *not* clear the headline noise floor and *is* plainly visible on
the bloc rows. That is [[diplomacy-model|V1.3a]]'s finding, reached for the fourth
time — and it is the argument for the polling panel being where this decision is
read, not the approval figure.

Underneath it: deficit +0.287, unemployment −0.164, GDP +53.3 bn over five years.
**The subsidy pays for itself in output and not in politics**, which is the
tension the verb exists to create.

## 6. `SAVE_VERSION` 14 → 15, on one field of five

`NationState.companies` earns it. Absent, every firm reads as share 0.0 — the
partition simply is not there, every firm produces nothing, and a subsidy the
save is still billing for through a serialised budget line moves a share that
does not exist. `military_capability` at V1.3g and `eu_member`/`neighbours` at
V1.3b: a reloaded game running a **different model** from the one that saved it.

The other four fail the rule cleanly. `subsidy_bill_pct_gdp`, `firm_impulse_pct`
and `firm_jobs_offset_pct` are recomputed from the register on the first tick and
read 0.0 when absent, which is right for every version-14 save because those
games could not subsidise anybody — `measures` at V1.3c and `appointments` at
U6a. `last_company_result` has no reader in `src/sim/` at all.

**What is not in the register is the interesting half.** A firm's authored share
and headcount are **content**, so the baseline every deviation is measured against
round-trips through `data/companies/` rather than through the save. A stored
baseline would be one fact in two places, and the copy in the save is the one a
content edit would silently disagree with. `tests/test_save_load.gd` asserts a
save carries no company content and that a register entry holds nothing beyond
`share` and `subsidy`.

## 7. Where it sits

```
DataLoader.load_all()
  → _load_companies(id)     ×10, an ABSENT file is legal
  → _load_company_actions()
  → _validate_companies()   ≥2 firms per named sector; shares sum ≤ 1.0

GameState._build_nation() → Companies.init_nation(ns, company_list)
main.gd monthly            → Companies.tick_month(state, loader)   [after Defence]
Budget.project()           → the same call, so the projection is the real model
```

`src/sim/companies.gd` **takes a loader**, where `trade.gd`, `coercion.gd` and
`defence.gd` take none. That is the price of keeping the baseline in content, and
it is paid in exactly one place: all three prices are **cached onto NationState**
once a month, so `economy.gd`'s twenty-eight call sites and `budget.gd`'s
`recompute()` never grow an argument. `Defence._recompute_prices()`'s argument,
one register wider.

## 8. Three nations, not ten

`data/companies/` holds FRA, DEU and GBR — the three playable nations. An absent
file gives unpartitioned sectors, which is exactly what all ten looked like before
this session, so the seven that are not yet playable run the model they always
ran and their bit-identity is free.

[[declined]]'s rule is why the count per nation stays small: **sector count scales
with the nation roster, tax count does not.** Firms scale with the roster too, and
forever. A session making a fourth nation playable authors its firms first —
named here so it is a decision rather than a discovery.

## 9. What is deliberately not built

**Autonomous firm behaviour.** Firms do not invest, relocate, hire or fail on
their own initiative. [[someday]] already parks it, and V1.4a adds nothing that
implies it.

**A counterparty gate.** A firm cannot refuse a subsidy. There is no interest
model behind one and this is **not a declared stopgap** — nothing here stands in
for a decision a later session has to make. Whether a firm should answer back is
V1.4c's question, asked fresh.

**Regulation and ownership.** V1.4b and V1.4c. Both read `effects.company`; the
first reaches it through a **law**, which is the split the decomposition was taken
on.

**Bond markets.** Moved to [[v1]] §6, where the yield they write belongs — see
[[ROADMAP]] for the argument.
