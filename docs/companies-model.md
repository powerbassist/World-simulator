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

> [!warning] V1.4b turns that into a stopgap after all, and says so
> A subsidy is a gift and there is nothing to refuse. A **regulation is imposed**,
> and a regulated firm that cannot relocate, exit, lobby or close is a visible
> absence rather than an unasked question — the burden runs to
> `REGULATION_BURDEN_MAX` and the register answers with arithmetic. **Declared as
> a stopgap**, parked in [[someday]], and V1.4c's nationalisation is the nearest
> thing in the plan to a firm responding to what is done to it.

**Regulation and ownership.** ~~V1.4b and~~ V1.4c. Both read `effects.company`;
the first reaches it through a **law**, which is the split the decomposition was
taken on. V1.4b is built — see §10 below.

**Bond markets.** Moved to [[v1]] §6, where the yield they write belongs — see
[[ROADMAP]] for the argument.

---

# V1.4b — sector regulation

## 10. A regulation is a law, and that is the entire session boundary

`GameState`'s fourth companies-neighbourhood register is
`NationState.regulation_burden` — sector id → signed accumulated burden — and it
is written by `Legislature.apply()` and by **nothing else in the project**. A
subsidy reaches `effects.company` through `Companies.execute()` as an executive
act; a regulation reaches the same channel having first survived an assembly
division. That is [[diplomacy-model|V1.3a]]'s distinction between a diplomatic
action and a law, one block later, and it is worth a session because the
**approval path** differs, not because the subject does.

`src/core/law.gd` grows a fifth theme (`business`), a `_extract_company()`
validator beside `_extract_institutional()`, and one new entry on the whitelist at
`_extract_effects()`. `data/laws/business.json` is the content. Nothing else in
`src/sim/` learned a new verb: `legislature.gd` gained one dispatch branch and one
preload, for the clamp alone.

### A firm-targeted channel, refused a firm

`effects.company` is **the same channel name** `company_action.gd` uses with a
deliberately different shape — an action names an `op` against the one firm it is
pointed at, a law names a `sector` and a `burden`. `_extract_company()` refuses
any third key, and the refusal is the point rather than tidiness: **share movement
is the subsidy's persistent channel**, and a law that could name a firm would be a
second writer of it — two answers to the question of who is winning the sector.
The split is in the schema and not only in this file.

`tests/test_companies.gd` asserts every share is **exactly** unchanged after
twenty rounds of every rule in the file. Exact equality, not `is_equal_approx`:
"nearly unmoved" is a second writer that a tolerance would hide.

## 11. One quantity, read twice — and no new channel at all

The burden is priced through the **two channels V1.4a already built**, with no new
field, no new budget line and no new clamp:

| Read | Where | Reaches opinion through |
|---|---|---|
| growth | a negative term inside `Companies.firm_impulse_pct()`, scaled by the burdened sector's **named firms' live GDP share** | `growth`, `jobs` |
| jobs | a `(1 − REGULATION_JOBS_BETA × burden)` factor inside `Companies.headcount()`, which the existing `firm_jobs_offset_pct` picks up for free — it already measures live headcount against authored headcount | `jobs` |

This is [[coercion-model|V1.3c]]'s "one verb, two prices" **literally** rather than
by analogy: one quantity read at two existing sites. A second growth impulse
beside `firm_impulse_pct` would have been a second machine wearing the phrase, with
its own field, clamp and cached price to keep in step. A subsidy and a regulation
on one sector therefore **net off**, which is the honest answer — the player paid
for one and the assembly passed the other.

Both reads go through the **live** share, so a subsidy that grew a firm raises what
regulating its sector costs. That interaction is the whole reason both verbs run
against one register instead of two.

### The channel's charter is WIDENED, and it is written down as one

V1.4a's claim was that a firm layer adds **reallocation and nothing else**. A
sector burden is a **level** effect on top of that: it sheds staff without moving a
single share. `firm_jobs_offset_pct` now says two things.

That widening is not a compromise, it is the session's whole case — see §12.

### What a regulation BUYS uses no new channel either

`bloc_offset`, `potential_growth_pct`, `other_revenue_pct_gdp` and the budget
levers already exist on a law. The sixth session running with no new content type,
and the fifth with no new effect channel.

## 12. Row 12: `_validate_companies()`'s defence against §6 does not transfer

The sharpest thing in the session, and the **twelfth** instance of the
stale/missing-row failure [[trade-model|V1.3b]] first recorded.

V1.4a's answer to "*a subsidy IS [[v1]] §6's sectoral investment — a lever pointed
at a sector*" was to refuse a sector holding one named firm. **That rule is about
the target, and a regulation's target is the sector itself.** A sector-wide burden
priced on sector output is §6's lever with a minus sign, however many firms sit in
the sector, and no validator can catch it.

Two things keep them apart, and both are structural rather than coefficients:

1. **A regulation reaches only the named partition.** The growth term sums over
   `firms_in_sector()`, so a sector that is 24 % named is a quarter as regulable as
   one that is fully named. The **unnamed residual is unregulated** — a bound
   recorded rather than a rounding error, and the line §6 must not cross.
2. **The jobs price has no analogue in a sector lever**, because jobs-per-share is
   firm content. Without it V1.4b *is* §6 early and the a/b/c boundary collapses.
   That is why the jobs channel is not optional here, and why widening its charter
   was the right trade.

Both are cross-referenced from [[v1]] §4 **and** §6, so this does not become the
thirteenth.

## 13. Row 13: the margin quantity that was cut before it was written

The ROADMAP row reads "*rules that cost margin*". A grep over `src/sim/` finds
**no margin, profit or productivity quantity anywhere** — "cost margin" names
something the model does not have.

The obvious reading was a `regulation_margin_pct_gdp` landing on
`revenue_pct_gdp["corporate"]`, mirroring V1.4a's computed spending line on the
other side of the budget. It was **cut before it was written**, for three reasons
and the third is the one that matters:

- It is a negative `law_other_revenue_pct_gdp` with extra machinery, and a
  computed subtraction from `corporate` is a corporate rate cut the player cannot
  see on the slider — which [[legislature-model]]'s own anti-double-count rule
  already forbids.
- Its register read collapses to `burden × named-share × sector-GDP-share`, both
  factors per-sector constants. **A §6 sector lever reproduces it exactly**, so it
  fails the test §12 sets.
- **It creates V1.4c's dependency rather than discharging it.** A dividend can be a
  yield on *output* — `state_share × share × sector_output × DIVIDEND_YIELD`,
  mirroring "revenue is not authored" — and needs no profit quantity. Ship a
  half-invented margin here and V1.4c must either read it (a state-owned firm in a
  burdened sector paying undiminished dividends is two answers to profitability) or
  contradict it. **If V1.4c wants margin, V1.4c owns it whole.**

## 14. Deregulation is a direction, not an undo

There is no repeal verb in this project and a `once` law never returns. So the
clamp is **symmetric**: a deregulation law carries a negative burden on the same
accumulator.

An asymmetric `[0, MAX]` would have been a **permanent monotone charge** —
[[defence-model]]'s named failure mode, where a clamp stops being a guard rail and
becomes the number — and it would have made a repeal law *inert at burden 0*,
breaking [[foreign-policy-model|V1.3f]]'s inert-act property on the law list. It
would also have needed a new whitelisted `PRECONDITION_FIELDS` entry carrying a
sector parameter that list has never had. The signed burden costs none of that, and
deregulation pays honestly in `bloc_offset` instead of being free.

## 15. The anti-double-count is a load error, not a convention

A law carrying **both** `effects.company` and `structural_unemployment_pct` fails
at load. Same act, same landing site (`Economy._update_unemployment()`), same
units.

[[legislature-model]] states the equivalent rule for levers vs `bloc_offset` in
**prose** — "the sixteen templates each pick one story and tell it once". This one
is mechanical, because a convention only the docs enforce is one an author breaks
by not reading them. [[coercion-model]]'s separator, which refuses a symmetric key
where a directed one belongs, is the same shape.

## 16. The probe corrected the content twice and itself once

Eleven sessions running, and this time **not one correction was to the model** —
which is itself the finding. The two channels were V1.4a's, already measured; what
was unmeasured was the content.

### (g) the kill switch cleared, and the standing prediction held

`REGULATION_JOBS_BETA` was swept against a floor of **0.05 unemployment points**
fixed before the sweep, and against a prediction written in advance that
agriculture could not clear it at any sane value.

| beta | best pts | verdict |
|---|---|---|
| 0.05 | 0.0471 | below floor |
| **0.10** | **0.0942** | **in band — shipped** |
| 0.20 | 0.1884 | in band |
| 0.40 | 0.3768 | in band |

0.10 is the **smallest passing value**, which is why it ships. Per sector at that
value: DEU industry 0.0942, GBR services 0.0728, FRA services 0.0690, FRA industry
0.0603 — and agriculture **0.0083–0.0126 across all three nations**. The prediction
held exactly. That is **recorded as a structural bound**, not tuned around: 39 000
named agricultural jobs against a 30.9 M labour force is arithmetic, and raising a
constant until it moved would be tuning against the size of a real labour force —
[[defence-model]]'s `DEPLOYMENT_OPINION_CHOSEN` finding reached from a second
direction.

`FIRM_JOBS_MAX_PCT` is **slack**: 0.1419 against 1.50 at the reachable worst case.

### (h) growth, against the band the subsidy was held to

| beta | worst %/yr | verdict |
|---|---|---|
| 0.05 | 0.2211 | in band |
| **0.10** | **0.4422** | **in band — shipped** |
| 0.20 | 0.8844 | too large |
| 0.40 | 1.7688 | too large |

The **ceiling is the half doing work**, exactly as it was for
`SUBSIDY_GROWTH_BETA`: a rule on one sector must no more out-punch a whole budget
than a subsidy to one firm may. 0.20 is the first row over it.

### (i) the two betas are not one decision wearing two names

The redundancy check — U6a's precedent is that a constant nothing distinguishes is
**deleted**, not left unused. Growth-per-jobs-point, by sector:

| | agriculture | industry | services |
|---|---|---|---|
| FRA | 2.79 | 3.82 | 6.32 |
| DEU | 1.98 | 3.60 | 6.50 |
| GBR | 1.60 | 4.80 | 6.07 |

A **4× spread**, and nothing authored it: it is output-per-share divided by
jobs-per-share, two fields written for unrelated reasons at V1.4a. A government
that wants to shed the fewest jobs per point of growth given up regulates
**services**; one that wants to give up the least growth per job shed regulates
**agriculture**. Both constants earn their place; neither is deleted.

### (j) the content correction: the first draft was free approval

**The design rule this session set was too broad.** The plan said the burden is the
cost and `bloc_offset` is the buy, and that a regulation's losers must not *also* be
named in `bloc_offset` — one bloc's reaction to one fact, counted twice.

Table (j) stacked every rule and got **+6.45 headline points against a noise floor
of 3.0**. Passing everything was free, which is the strictly-dominated shape
[[coercion-model|V1.3c]], [[bloc-model|V1.3d]] and V1.4a each hit.

The rule was wrong because of a fact the probe itself had just measured: a
saturated burden moves growth by ~0.1 %/yr and unemployment by ~0.02 points, which
is **below the opinion model's resolution**. The measured channels cannot express
the political price of a rule, so it has to be authored. Every law now names its
losers, weighted against `BLOC_SIZE` rather than by eye — workers are 0.30 of the
electorate and business 0.10.

| | quiet | regulated | deregulated |
|---|---|---|---|
| workers | 49.63 | 51.86 | 41.45 |
| pensioners | 49.54 | 55.39 | 44.58 |
| urban | 49.61 | **65.15** | 45.60 |
| rural | 49.61 | 40.16 | 53.48 |
| business | 49.21 | **11.08** | 66.27 |
| students | 49.69 | 55.88 | 46.53 |
| **HEADLINE** | **49.57** | **49.42** | **47.28** |
| GDP bn | 3108.00 | 3075.99 | 3127.54 |
| unemployment | 7.39 | 7.65 | 7.25 |

Neither column is a free opening, and the headline moves **less than the ±3.0 noise
floor in both directions** while bloc rows move by 15 and 38 points. That is
[[diplomacy-model|V1.3a]]'s finding for the fifth time, and V1.4a's for the second:
*the decision is legible on a bloc row and not on the headline*.

The worst accumulated `bloc_offset` is **business at −0.940 against a clamp of
1.00 — slack, but only just**, and only because five rules on 24-to-36-month
cooldowns cannot realistically pass inside one term. Measured rather than assumed,
because the clamp-setting-the-number failure has now been found three times.

### (k) the probe's own bug, and the two dominations it was hiding

The cost-against-buy table summed `bloc_offset` **unweighted**. A sum over blocs is
a sum over unequal things: it read `financial_deregulation` as the best row on both
axes while hiding a charge on pensioners (0.24 of the electorate) paid for with a
gift to business (0.10 of it). Weighting by `BLOC_SIZE` exposed two same-sector
dominations:

- **Industry.** `workplace_safety_act` was cheaper than `emissions_standards` on
  both costs *and* bought more — emissions was strictly dominated. The two
  **burdens were swapped** rather than the offsets retuned, because a safety regime
  genuinely is the heavier compliance load and the fix that is also true is the
  better fix.
- **Services.** `banking_conduct_rules` cost double `competition_enforcement` for a
  buy 0.0009 larger — domination inside the rounding. `pensioners` went 0.11 →
  0.16, so it is now the bigger lever at the worse rate rather than the worse lever
  outright.

The table also gained a `trend` column, because `competition_enforcement`'s entire
buy is `potential_growth_pct` and a table without it read that law as pure cost.

**Domination is only meaningful within one sector.** Two rules on different sectors
are not substitutes, because the sector decides which of the player's own
subsidised firms the rule reaches — which is §11's interaction, showing up as a
content property.

`data/laws/business.json` ships **no agriculture deregulation**, deliberately: both
measured channels are below the readable floor there, so such a law would buy
nothing measurable and cost real approval — strictly dominated by construction. The
sector is regulable in one direction only, and that is a property of the content
rather than a gap in it.

## 17. `SAVE_VERSION` stays at 15, and the test pins it

The rule applied literally: a version-15 save comes from a game **with no `business`
law in it at all**, so an absent `regulation_burden` reads as every burden 0.0 —
which is not a soft failure but the truth about that save. `measures` at V1.3c,
`pacts` at V1.3g, `appointments` at U6a.

It is still serialised, and that half is not free: a law writes the burden once and
**no tick recomputes it**, unlike the three cached prices, so a save that dropped it
would silently repeal every rule the assembly ever passed.
`tests/test_save_load.gd` checks that dropping it changes `firm_impulse_pct` — the
premise, rather than the claim — and then asserts the version is **still 15**, so
V1.4c's ownership register has to come and say why it bumps. V1.3c's own device.

The register is keyed by **sector**, so V1.4a's assertion that a company entry
carries nothing beyond `share` and `subsidy` stays green. A later session moving the
burden onto a firm turns that one red and has to say why.

## 18. Balance: bit-identical, and the cheap kind of new regime

**Predicted in advance and confirmed: bit-identical across all fifteen existing
regimes.** The only difference in the whole probe output is the forty lines of the
new sixteenth. Nothing autonomous passes a law, and the burden reads exactly 0.0
until one does.

A regulation is a verb and no budget regime issues a command, which is why V1.3c,
V1.3g, U6a and V1.4a each needed a new regime. **This one is the cheap kind**, and
that is worth naming: `AMENDMENT_REGIMES` and `TRANSITION_REGIMES` already apply a
*law* at a month, so the shape existed and only the content is new.

Both harnesses call `Legislature.apply()` rather than `propose()`: the assembly
division is `tests/test_legislature.gd`'s subject, and a balance row whose numbers
depend on a chamber agreeing measures two things at once.
`_check_a_regulated_run_stays_off_every_clamp()` runs fourteen years of every
sector saturated **with the subsidy stack live underneath it**, because the two
verbs share the channels and their clamps.

## 19. The screenshot pass, eighth session running

`--regulate` applies two rules in opposite directions on two sectors, so a frame
carries both captions the sector heading can draw.

**The first version of the flag drew an empty row.** One rule each way came out at
`-0.000 pts unemployment` on the ledger: industry's 186 000 named jobs at a +0.40
burden and services' 213 000 at a −0.35 one shed and hire within **fifteen people**
of each other. The frame showed both sector captions and a dead jobs figure — a
capture proving one of the two things it exists to prove. The flag now applies the
industry rule twice.

The ledger's two deviation rows are **net**, and deliberately not split into a
subsidy half and a regulation half: splitting them means recomputing each channel
against a hypothetical register, which is a second model of one quantity kept in
step by hand. The sector headings carry the burden instead
(`INDUSTRY · 570 BN · 24 % NAMED · REGULATED +0.80`), so attribution is read off
which sectors are marked.

`--open society` is the third capture rather than `--open budget`, and the reason is
the session's shape: **a regulation has no budget line at all**, so a budget frame
would prove nothing. The polling panel is where the price is, and it reads workers
+7, business −8, pensioners −5, urban +2 against a headline that has not moved.

---

Related: [[index]] · [[legislature-model]] · [[economy-model]] · [[opinion-model]] ·
[[coercion-model]] · [[defence-model]] · [[v1]] · [[ROADMAP]]
