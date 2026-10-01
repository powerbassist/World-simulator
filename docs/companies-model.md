---
title: Companies Model
tags:
  - model
  - economy
---

# Companies Model

**V1.4a–c, complete.** Named private firms partitioning a sector, a standing subsidy,
a sector burden the assembly passes as a law, and public ownership with a dividend
and a windfall. `src/sim/companies_constants.gd` holds the values; this page is the
argument. §1–9 are V1.4a, §10–19 V1.4b, §20–29 V1.4c; §30 is V2.2a's city field;
§31–38 are V4.7's two-tier register and autonomy machine.

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

> [!warning] V4.7a ships the face, not the interest
> Every major carries an executive `chief_id` — a person of the executive kind,
> resolved at load and validated loud — rendered on the card, the People window
> and B3's board-chair line. What §2 refused was a CEO who ACTS: a firm's own
> interest reaching the state through a verb of its own. That refusal still
> holds — the chief is a face and a bench tier until [[v4.2]]'s lobbying gives
> a firm's interest a lever, and §37 records the gap as the declared stopgap
> it is.

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

The jobs channel has **no tuned constant in it at all** — only the labour-force
conversion and a clamp. That is what lets its size be reported as a finding rather than
defended as a choice.

> [!note] [[demography-model|V1.5b]] deleted `LABOUR_FORCE_SHARE` and re-measured these figures
> That constant was 0.45 and its own comment defended it as "the measured
> participation-times-working-age figure for the roster, not a dial". V1.5b took the
> claim at its word and checked it: France is 0.7407 × 0.6134 = **0.4543**, right to
> three digits — and Germany is 0.7994 × 0.6289 = **0.5027**, with the roster spanning
> Italy 0.423 to the Netherlands 0.551. One number right for one nation. It is now
> `Demography.labour_force()`, two measured facts per nation, and the "no tuned
> constant" property above survives intact.
>
> The figures in this section are **re-measured rather than silently invalidated**. The
> new denominator ÷ old, by nation: ITA 0.940, BEL 1.001, FRA 1.010, GBR 1.080, ESP
> 1.101, DEU 1.117, AUT 1.128, LUX 1.141, CHE 1.215, NLD 1.225. France's is 1.010, so
> the **0.229 / 0.010** spread becomes ≈**0.227 / 0.0099** and V1.4b's kill-switch
> figure of 0.0942 becomes ≈0.0933, still clear of its 0.05 floor. Both France figures
> scale by one factor, so **the ordering is untouched** — which was the pre-committed
> condition for calling this a re-measure rather than a model change.
>
> Italy is the row worth noticing: its denominator **shrinks**, so it is the one nation
> where a given firm shedding a given number of jobs now costs *more* points of
> unemployment than the flat constant said. And the term now **moves over a run**: an
> ageing nation's labour force falls as a share of its population even where the
> population grows.

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

> [!warning] V4.7a made it all 29, by generation
> The register is 29 nations because the roster is — 317 majors and 2,420 body
> firms, the 25 new nations' majors generator-authored and pinned by
> `firms_generate.py --check` (§31). §8's decision-to-add-a-nation rule is spent:
> adding a nation is now a generator run, and the open call is whether the
> generated majors ever get the hand-curation pass the original three got
> (§37).

## 9. What is deliberately not built

> [!warning] V4.7b B1 builds the first half of this row
> Autonomous firm behaviour — the "not built" this section opened with — is now
> the industry machine: majors fail, bid, drift and relocate on their own
> initiative, with the bands and the refusals recorded at §33. What remains
> deliberately unbuilt is the firm as a NEGOTIATOR: nothing here answers back,
> lobbies or closes itself rather than fail — a firm interest model, still
> parked in [[someday]] and still a session, not a constant.

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

**Regulation and ownership.** ~~V1.4b and V1.4c.~~ Both read `effects.company`;
the first reaches it through a **law**, which is the split the decomposition was
taken on. Both are built — §10 and §20 below.

> [!warning] V1.4c INHERITS the stopgap above rather than discharging it
> Nationalisation is the state acting **on** a firm, not a firm acting: the price is
> derived rather than negotiated and there is nobody to refuse. A firm still cannot
> relocate, exit, lobby or close. What V1.4c answers is the half about *regulation* —
> a regulated firm now has one outcome other than arithmetic, and the state chose it.
> Still parked in [[someday]]; what discharges it is a firm interest model, which is a
> session and not a constant. See §28.

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

# V1.4c — nationalisation and privatisation

## 20. Three fields, three writers, one apiece

`NationState.companies[id]` gains `state_share`, and the register is now the whole
of what V1.4 built:

| field | sole writer | scope | earned a bump? |
|---|---|---|---|
| `share` | `Companies.execute()`, subsidy ops | firm | **yes**, V1.4a |
| `state_share` | `Companies.execute()`, ownership ops | firm | no — see §24 |
| `regulation_burden` | `Legislature.apply()` | **sector** | no, V1.4b |

`tests/test_save_load.gd` asserted a serialised entry carried nothing beyond
`share` and `subsidy`. **That was turned red on purpose and widened by exactly one
key**, which is the change worth recording rather than the widening: the three
fields are the three things about a firm that *move*, and `name`, `sector`,
`headcount` and the *authored* share stay content. A fourth key still fails.

## 21. A dividend is a yield on OUTPUT, and §13 called it a session early

The binding decision V1.4b handed forward, taken as §13 argued it:

```
dividend = state_share × share × sector_output × DIVIDEND_YIELD
```

Owning margin whole would mean a profit or productivity quantity across three
sectors reconciled against `Economy._apply_growth_to_sectors()`, which is [[v1]]
§6's ground and a re-baseline of every measured balance number. A yield on output
needs none of it, and it is `output_eur_bn()`'s own "revenue is not authored" shape
one step on. **No third option was shipped.**

It lands as a computed **revenue** line — the second on that side after V1.3c's
tariffs, the fifth computed line overall, and read straight off `NationState` so it
takes the one-month lag the subsidy bill takes and for the same reason.

## 22. The purchase is a BALANCE-SHEET write, and that is why the session added no save field

`Companies.execute()` writes `ns.debt_eur_bn` directly — the only place in the
project outside `Budget.tick_month()` that does. Three reasons, and the third
decided it:

- A capital transaction is a swap, not income. Every existing line on this budget is
  a standing rate; a one-off has no shape here.
- It would move `deficit_pct_gdp` inside the month, and the deficit is **a company
  action's own precondition field** — the loop V1.4a's one-month lag exists to
  avoid. `tests/test_companies.gd` asserts the deficit moves by exactly zero.
- It costs nothing and buys three built machines: the interest is priced by
  `Budget.recompute()` at `DEBT_REAL_RATE_PCT`, the level is read by the bloc's own
  `debt_to_gdp_pct` rule in `data/bloc-proposals/fiscal.json`, and `debt_eur_bn` has
  been serialised since the MVP. **Nationalising a champion can put the player in
  breach of a rule Brussels passed** — V1.3d meeting V1.4c the way V1.3d met V1.3g.

The price is derived for the same reason revenue is: `value = output × PRICE_TO_OUTPUT`,
read through the **live** share, so a subsidy that grew a firm raises what
nationalising it costs. An authored valuation would let a content file disagree with
the register about what a firm is worth.

## 23. Row 14 — "a permanent loss of control" named a control the model did not have

The **fourteenth** instance of the stale/missing-row failure, and §13's shape
exactly. A grep says a subsidy works on any firm whoever owns it and a regulation
targets the sector, so before this session ownership controlled nothing.

The answer is one factor at one existing site, in `Companies.headcount()`:

```gdscript
var exposure: float = 1.0 - state_share_of(ns, company.id)
var compliance: float = maxf(
    1.0 - K.REGULATION_JOBS_BETA * regulation_burden_of(ns, company.sector) * exposure, 0.0
)
```

A state holding absorbs the sector's compliance cost so the payroll does not. It is
V1.4b's "one quantity, two prices" one quantity later, and it adds **no constant at
all** — which is why §26 can report its size as a finding rather than defend it as a
choice, exactly as V1.4a's jobs channel could.

**The shield is signed**, so a public firm in a *deregulated* sector also gives up
the hiring the deregulation would have brought. That is what stops it being free,
and `tests/test_companies.gd` asserts both directions — a shield that only ever
helps is the strictly-dominated shape three probes have already caught.

This is also what makes V1.4c read **(a) and (b)** as the decomposition table
claims, rather than (a) alone.

## 24. `SAVE_VERSION` stays at 15, which is not what the row expected

The rule applied literally a fourth time. An absent `state_share` reads 0.0 — *the
state owns nothing* — which is the **truth** about every version-15 save, because
those games had no ownership verb. `measures` at V1.3c, `pacts` at V1.3g,
`appointments` at U6a, `regulation_burden` at V1.4b.

The two halves that could have earned one and do not:

- `dividend_revenue_pct_gdp` is recomputed from the register on the first tick.
- The purchase and the windfall were **never a field**: they are in `debt_eur_bn`.
  A capital transaction that needed its own save entry would have been the sign it
  should not have been a balance-sheet write, and `tests/test_save_load.gd` checks
  that premise rather than asserting it.

The one thing that *would* have bumped it is a `start_state_ownership` baseline for
a thirteenth issue — `start_bloc_burden` at V1.3d exactly. §27 is why there is none.
V1.3c's device is left in place a third time.

## 25. The probe corrected the model once and the content once, twelve sessions running

### (P10/P11) the price is chosen and the yield's band could NOT choose

`PRICE_TO_OUTPUT` swept against the debt jump from nationalising the largest firm,
banded 2–8 points of debt-to-GDP before the sweep:

| multiple | FRA | DEU | GBR | |
|---|---|---|---|---|
| 0.50 | 2.38 | 1.84 | 2.41 | split |
| **1.00** | **4.76** | **3.68** | **4.82** | **in band — shipped** |
| 2.00 | 9.52 | 7.36 | 9.65 | split |
| 3.00 | 14.27 | 11.04 | 14.47 | too large |

One row in band, and it is the only sweep in this file where that happened.

`DIVIDEND_YIELD` did the opposite. **Three of four rows passed** — 0.02, 0.04 and
0.06 all land inside 0.05–0.40 % of GDP — so the band did not choose the constant.
That is a finding rather than a nuisance: the band measures whether the line is
**readable**, which is not the same question as whether it is right.

### (C1) the model correction — a verb free on both axes

Shipped provisionally at 0.04, the yield on price was 4.0 % against a 2.0 %
borrowing rate, so every nationalisation paid for itself twice over. Table (p) came
back **better than a quiet run on the headline *and* on the deficit**, losing only a
debt ratio that reaches no opinion term at all. Free on both axes — V1.3c's, V1.3d's,
V1.4a's and V1.4b's shape a fifth time.

The correction moved **what the number is measured against**, not the band:
`DIVIDEND_YIELD / PRICE_TO_OUTPUT` is set **equal to `DEBT_REAL_RATE_PCT`**. At the
borrowing rate the treasury neither gains nor loses on the exchange, which is the
honest model when there is no risk and no business cycle for an equity premium to be
compensation *for* — [[v1]] §6 owns both. What nationalising costs is then a **stock
rather than a flow**: the whole purchase lands on `debt_to_gdp_pct` at once, and
privatising is the only lever in the game that moves a stock back down.

> [!note] [[ROADMAP|V1.6c]] discharged the obligation, and on a RATE
> [[cycle-model|V1.6a]] arrived with the cycle and discharged nothing: a dividend
> expressed as a share of GDP is not procyclical by construction, because the cycle
> moves numerator and denominator together. **A rate is the one quantity in this
> model that is not a share of GDP**, and V1.6c is the session that makes one move.
> The identity above becomes `DIVIDEND_YIELD / PRICE_TO_OUTPUT × 100 ==
> DEBT_REAL_RATE_PCT + EQUITY_PREMIUM_PCT` — 3.12 against 2.00 + 1.12 — with the
> dividend held fixed and the **borrowing** rate floating past it. While the spread
> is under the premium the state gains on the flow; above it, the debt that bought
> the firm costs more than the firm returns, and the crossing is exactly where
> `spread == EQUITY_PREMIUM_PCT`. The strictly-dominated shape does not come back,
> because which side you are on is a consequence of the player's own fiscal record.
> The premium's kill switch did **not** fire; the clause that chose it is *doing
> nothing for fourteen years turns a nationalisation into a loss*. The three-row
> table below is therefore the **anchor** case, not every case.
> Full argument: [[credit-model]] §8.

| | price bn | div bn/yr | interest bn | net | payback |
|---|---|---|---|---|---|
| FRA Méridienne | 138.5 | 2.77 | 2.77 | **+0.00** | 50 yr |
| DEU Rheinwerk | 158.6 | 3.17 | 3.17 | **+0.00** | 50 yr |
| GBR Sterling Mutual | 164.0 | 3.28 | 3.28 | **+0.00** | 50 yr |

### (C2) the content correction — the offsets that made it free

With the fiscal gain gone the politics still was not paid for, so every
`bloc_offset` in `data/company-actions/ownership.json` was re-authored against
`BLOC_SIZE` rather than by eye — V1.4b's table (j) discipline, and the same answer:
**a firm layer's own channels cannot express a political price, so it has to be
written down.**

| bloc | quiet | nationalised | sold |
|---|---|---|---|
| workers | 49.63 | **53.64** | 48.83 |
| pensioners | 49.54 | 50.75 | 49.15 |
| urban | 49.61 | **44.02** | 48.02 |
| rural | 49.61 | 47.62 | 48.81 |
| business | 49.21 | **43.23** | 48.81 |
| students | 49.69 | 50.50 | 49.69 |
| **HEADLINE** | **49.57** | **49.43** | **48.85** |
| deficit | 5.34 | 5.33 | 5.34 |
| **debt ratio** | **133.64** | **138.08** | **133.57** |

Neither column is a free opening; the headline moves less than the ±3.0 noise floor
in both directions while workers move +4 and business −6. [[diplomacy-model|V1.3a]]'s
finding for the **sixth** time.

The `sold` column is a purchase *and* a sale, because a state that never nationalised
has nothing to sell. It is there to answer one question: **is buy-and-flip a pump?**
It is not — the round trip ends 0.07 points better on the debt ratio and 0.72 worse
on the headline.

## 26. (P13) the kill switch cleared, and its size is not a new number

The jobs shield against the 0.05-point floor V1.4b fixed, with the standing
prediction that agriculture cannot clear it:

| | agriculture | industry | services |
|---|---|---|---|
| FRA | 0.0126 | 0.0603 | 0.0690 |
| DEU | 0.0104 | **0.0942** | 0.0490 |
| GBR | 0.0083 | 0.0414 | 0.0728 |

**Clears at 0.0942, and the prediction held exactly.** But the sharper thing is that
these are **V1.4b's table (g) numbers, to the digit**: a total holding cancels the
compliance factor, so the shield's size *is* the burden's own jobs price read from
the other side. There was never a constant to sweep, and the identity is confirmed
through the live model rather than by arithmetic.

Agriculture is recorded as a **structural bound** for the second session running,
and for the same reason: 39 000 named jobs against a 30.9 M labour force.

## 27. The `ISSUE_KEYS` call, answered NO — and the reason is the business row

The call V1.4a, V1.4b and the whole V1.3 block deferred here by name. Measured the
way V1.3d measured it, against V1.3d's four tests and a fifth V1.4b forced.

Tests **1** (the price is not nameable otherwise) and **3** (a flat offset cannot
become more salient) hold, identically to `europe`'s. The other three fail:

**Test 5, the new one.** A regulation has 1 and 3 identically too, and V1.4b took no
key. The proposed distinction was that state ownership is a single standing **stock**
the player can point at where a burden is a per-sector rule — it does not survive,
because `regulation_burden` summed over three sectors is equally a stock and nothing
about ownership's is more pointable-at. Same footing, same answer.

**Test 2.** V1.4b measured this layer's channels at ~0.1 %/yr of growth and ~0.02
points of unemployment, **below the opinion model's resolution**. A thirteenth row of
near-zeroes on the polling panel is worse than no row.

**Test 4, and it is the one with a number.** The S10 ratio drifts **−1.46 %**, where
V1.3d's moved **+0.39 %** — 3.7× larger and in the *unsafe* direction:

| | `public_finances` | five spending lines | ratio |
|---|---|---|---|
| twelve keys | 0.1801 | 0.3493 | 0.5155 |
| thirteen | 0.1671 | 0.3290 | 0.5080 |
| | | | **−1.46 %** |

**That is structural, not a badly chosen candidate row.** `business` carries
`public_finances` at 0.34 and is the bloc that makes ownership divisive at all, so
any row expressing the mechanic leans on the bloc S10's ratio lives in. Re-measured
with business at 0.04 instead of 0.14 the drift falls to −0.29 % — and a row that
light does not express the mechanic. **The mechanic and the cost are the same
number.**

What names ownership to the player instead is the authored `bloc_offset`, read on the
polling panel's bloc rows — the surface [[diplomacy-model]]'s finding has now pointed
at six times. Recorded in `opinion_constants.gd` beside `ISSUE_KEYS`, so a later
session finds the reasons rather than the silence.

## 28. What V1.4c does NOT discharge

**V1.4b's declared stopgap is INHERITED and narrowed, not discharged.** A firm still
cannot refuse, exit, relocate, lobby or close. Nationalisation is the **state acting
on a firm**, not a firm acting: the price is derived rather than negotiated and there
is nobody to say no. What would discharge it is a firm interest model — a session,
not a constant, and [[someday]] keeps it.

What V1.4c *does* answer is the half the stopgap named about **regulation**: a
regulated firm now has one outcome other than arithmetic. The state chose it.

**The dividend is inert against a cycle that does not exist.** Owning a claim on
output is a procyclical position, and there is no business cycle until [[v1]] §6. The
asset is real and its risk is not modelled — which is the same fact §25's correction
took the other way, and it is recorded here so §6 finds it.

## 29. Balance, and the screenshot pass's ninth session

**Bit-identical across all sixteen existing regimes**, predicted in advance: both new
channels read exactly 0.0 until a verb runs and no autonomous actor issues one. The
whole difference in the probe output is the 38 lines of the **seventeenth** regime,
which is the *expensive* kind — an ownership op is a verb no budget regime issues,
the way V1.3c's, V1.3g's, U6a's and V1.4a's were. A **no** on §27 is what kept the
re-run clean; a yes would have renormalised every salience weight in every month and
forced a re-baseline, and that trade was written down before the measurement rather
than discovered after it.

**The screenshot pass earned its keep for the ninth session running, and two of the
three bugs it found were older than this session.**

- **The date has read `01 JAN 2026` under every tick-forward flag since `--agenda`.**
  Each flag hand-rolled a month loop calling `main.gd`'s `_on_month_elapsed()`, which
  advances the simulation and leaves the Clock node alone, so
  `clock_cluster.refresh()` had nothing new to draw. V1.4a found the same
  disagreement one row up on the top bar and fixed *that*; the date under it stayed
  wrong for four flags. `_tick_months()` now drives `advance_one_day()`, which is the
  path a played game takes — and immediately surfaced a second thing no hand-rolled
  loop ever saw: two years of the real clock cross a real election, and the result
  screen opens over the panel the flag just set up.
- **The budget panel has never had a deployments row.** V1.3g wrote
  `_set_figure("deployments", …)` and no `FIGURE_ROWS` entry; `_set_figure()` returns
  silently on an unknown key. V1.4a then wrote *"beside the deployment line"* about a
  line that was not there. V1.3g's own pass could not catch it — the tool bug it did
  find made that figure an em dash anyway.
- And the flag's own: the first draft put both holdings on the two largest firms,
  which are both in **services**, and the companies panel is sorted by sector. Every
  visible firm read `private`, every visible sector heading read its plain caption,
  and the live figures sat in the ledger above rows that proved nothing. The whole
  holding stays on the largest firm; the minority stake and a second burden go where
  the frame can reach them.

## 30. A firm gained a fifth field at V2.2a, and it is a place

`Company.city` names a city in `data/regions/<its nation>.json`. [[v2]] section 2 put
it here rather than in the region register — *"a city's employment is already written
in `data/companies/` and needs no second authoring"* — and the direction is the point:
a city holding a list of its firms would be the same relationship written twice, and
the two would disagree the first time a session added a firm and forgot the other file.

It is **required**, because a firm with no city is one that tier cannot draw, and an
optional field would be one eighteen entries silently never filled in. Checked at the
loader rather than in `company.gd`, which sees one entry where the cities live in a
different file.

What makes it load-bearing rather than decorative — U6c's rule about a coordinate
nothing reads — is `Companies.headcount_in_city()`, which reads **live** headcount, so
a subsidy that has moved a firm's share has already moved its city's payroll. It lives
in `companies.gd` and not on `src/core/region.gd`, because a core value type
preloading a sim system would invert `data → sim → ui`.

The measured consequence is in [[geography-model]] section 7: **one city holds a third
to a half of a nation's named payroll** — Lille 33.1 % of France's, Manchester 44.0 %
of Britain's — which nothing authored, and which is what makes section 6's migration a
decision rather than a diffusion.

---

# V4.7 — the two-tier register and the autonomy machine

## 31. The register went from three nations of majors to 29 nations of two tiers

V4.7a's register is **317 majors + 2,420 body = 2,737 firms across all 29
nations**, and the tier is a FIELD (`tier: major|body`, validated loud at load)
because the two kinds answer different questions: a major is verb-worthy and has
an executive chief; a body firm is the sector's texture and is never an actor.
The bands, declared in `companies_constants.gd` before generation ran:
`BODY_SHARE_MAX` 0.03 (a body firm can never again be a subsidy's escalator —
§32), `MIN_BODY_SHARE` 0.001 scoped by tier, named coverage [0.85, 0.97] of
sector share, payroll [0.25, 0.50] of the nation's named employment against the
V2.2a Lille/Düsseldorf/Manchester finding, `BODY_MIN_PER_NATION` 80.

The register is **sparse**: `init_nation()` seeds majors only, and a body firm
gains an entry only when an act touches it. Every read over the full roster
therefore goes through `share_of_company()` (authored fallback), and
`share_of()` (register-only) is the read for a firm you already know is in the
register. The A3 review caught both panels printing the register-only read over
the full roster — a present figure printed as a confident zero, V1.6d's class —
and the fix was one word at each site.

The old-save repair is the load-bearing consequence: a v37 save predating the
roster carries `"companies": {}` for 25 nations, and the verbatim-restore load
path plus the sparse register meant every unseeded nation crashed at the first
read. **The PR #46 review's headline** (four lenses independently): `_seed_missing_majors()`
runs at the top of `tick_month()` and lazily seeds whatever the content now
carries — an old save repairs itself on its first tick, pinned by a test that
ticks a hand-built v37 payload.

## 32. The escalator: the step-0 finding that scoped the whole block

The share channel is **absolute, not scale-aware**. A 0.01-share firm pointed at
the same subsidy pool as a 0.14 major drains the same monthly step and ends a
60-month subsidy at 0.13 — five doublings of itself. Everything else in the
block's design is a consequence of refusing the two obvious "fixes":

- **Scale-aware steps refused**: a second calibration beside V1.4's, and a
  second quantity to keep bit-stable.
- **The body in the pool refused**: with body rivals giving down to half their
  authored share, a subsidised major's reachable share grows with the generated
  body count — the escalator at roster scale, differing between nations only
  because the generator drew different counts.

So **the pool is majors-only**: body firms neither give nor receive share, and
nothing writes a body entry at all — the body is inert by design (industry.gd's
own header: THE BODY IS NOT AN ACTOR, pinned by the suite's BODY SILENCE), and
the reads' authored fallback is what keeps a body firm visible anyway. A later
block's body market is where entries would start, and the sparse register is
already shaped for it.
The subsidy's calibration is V1.4's exactly, which is what kept 7a's
bit-identical re-run honest. The cost is stated plainly: the body tier is
texture the verbs cannot reach until a later block gives it a market of its
own.

## 33. The autonomy machine, and the bands that were declared first

`src/sim/industry.gd` ticks after Companies, before Migration, per nation:
**failures → bids → invest → relocate** — the plan's own order, and not for
taste: failures first so a firm that fails this month commits at its pre-tick
share (invest-then-fail leaked up to one `INVEST_STEP` per failure into the
partition audit, found by the zero-sum pin to exactly that magnitude). Every
draw is `Cycle.unit("industry|<id>|<event>", month)` — a private key namespace
nothing else consumes, over the absolute month index, no RNG state anywhere.

The bands, **declared before the probe ran and corrected by it**:
`FAIL_BASE_MONTHLY` 0.0003 (the first draft's 0.001 measured 1.86
failures/nation/run against a band topping at 0.7 — arithmetic that is the
base alone speaking, ~10.9 majors × 168 months × 0.001 — and the shipped
0.0003 measures ~0.55, in band; the correction story's declining-sector ×2
was mis-recorded and is fixed here: NO declining sector exists in shipped
content, every `SECTOR_TREND` has been positive since c4f8f3c, so the
declining term is inert arithmetic kept for content that authors one),
`RELOCATE_HAZARD_YEARLY` 0.002 (the draft's 0.02 made the comment's "a handful
over a run" ~89), `INVEST_STEP` 0.002/month from rivals' spare above
`RIVAL_FLOOR_FRACTION` × authored — with the pool's joint-drain SCALING
inherited beside the floor, so k takers in one month cannot push a rival
below the floor (unreachable on shipped content; true by construction
regardless) — `RESCUE_WINDOW_MONTHS` 6, `RESCUE_BAILOUT_PRICE_SHARE` 0.25 of
firm value as the rescue's one-off capital price on top of the recurring
support the same verb starts, `BID_HAZARD_YEARLY`
0.01 on a larger same-sector foreign major, `BID_WINDOW_MONTHS` 3,
`COURTED_BID_MULTIPLIER` 5.0. Measured idle: 0.62 failures/nation per 168-month
run (band 0.15–0.7), 8 relocations.

The relocation's single draw carries the distance discount INSIDE it — a first
draft drew hazard then a price gate, p² × discount, dead by construction — and
the nearest-region target is the graph's own answer. Three more pre-ship
defects the pins caught: `is_equal_approx`'s 1e-5 ABSOLUTE floor skipped real
9.8e-6 drains (V3.6's settled-is-a-tolerance lesson, third appearance — the
write skip is exact `== 0.0` with the number in the comment), and the
two-stage draw above.

**The relocation boundary, a design line and not an oversight**: the
register's `city` override moves the city SURFACE — the payroll total
(`headcount_in_city`'s live read) and the named-employers filter beside it —
while `Migration._jobs_by_city` keys on the AUTHORED city, so the pull does
not re-price mid-window behind a move it never saw. A rare event (~8
relocations per 168-month run worldwide), and the two stale records the
split briefly falsified (migration.gd's bit-exact claim; the pass-5 fleet's
find) now say the same thing this line does.

**The tick cost, found by B4's wall clock and not by any gate**: the scale
probe predates B1 and times Companies only, so the machine's month was never
inside a band — the re-baseline's head side ran 2.5× slow, and the scratch
timing probe measured **1,124 ms/month over the 29-nation roster**: ~8
unconditional Dijkstras per nation-month (`_relocate` needs the distance BEFORE
the single draw, and `distances_from` sorts inside its frontier loop). The memo
(`_dist_memo`, keyed on the graph's structural hash — content is immutable
post-load, and the memo lives in industry.gd rather than network.gd because
tests pass synthetic same-size graphs) carries it to **16.45 ms**. No distance
changes, no draw moves: results bit-identical, suite 93/93.

## 34. Five verbs on the one channel

B2's verbs ride `effects.company` through `Companies.execute()`, the channel
V1.4 built: **block_bid / allow_bid** (±0.5 relations pulses to the bidder's
bloc via `Relations.adjust` — an answered bid ends the courtship), **court**
(the ×5 hazard flag), **break_up** (pro-rata split to the sector's OTHER
MAJORS, refusing loud when no absorber exists — the body-tier draft pushed body
firms past `BODY_SHARE_MAX`, the escalator's second appearance), and
**appoint_board** (an unseated executive drawn by `Cycle`, B3). **Rescue is a
bailout, not a resurrection**: `execute()`'s bailout arm is gated on the
rescue WINDOW — gated on `failed` alone it revived committed failures and
undid break-ups (the B2 review's C1, both legs pinned). The bailout prices at
`RESCUE_BAILOUT_PRICE_SHARE` — one-off capital on top of the recurring
support the same verb then starts (the failure cleared it; the rescue
re-authors it). And a failure or break-up ends the firm's foreign interest
with it: the bid scalars clear at the commit, because a bid on a collapsed
firm is a bid on nothing, and a rescue brings the firm back without it.

The surfaces ride what exists: autonomy sections in the companies panel (the
open bid's block/allow row, failing majors with rescue rows), the SOE chair
line via `_loader.person_name()`, one card per announced event routing to the
companies window, and `pending.gd` marks the cluster — the V4.8 obligation,
landed a block early because the top-bar entry was already in hand.

## 35. The first non-bit-identical re-baseline

Every earlier re-run could predict bit-identity because the idle register was
never read by a printed figure. V4.7b's idle world acts, and the register is
priced into national figures at four named places:

1. **Jobs** — `headcount()` reads live share and 0 for a failed firm, into
   `firm_jobs_offset_pct()` (clamp 1.50), into structural unemployment
   (`economy.gd:307`). A failure is a permanent step of
   `min(1.50, 100 × headcount / labour_force)` points.
2. **Growth** — `firm_impulse_pct()` prices standing subsidies and burdens
   through the LIVE share (clamp ±2.00), into `economy.gd:161`'s growth sum.
3. **Revenue** — the dividend is `state_share × output(live) × yield`.
4. **City** — migration's `_jobs_by_city` reads live headcounts; city-level
   only, never printed.

The prediction (`reports/v47b-rerun-prediction.md`, written before the run):
FRA's idle failure timeline is regime-invariant (Cycle keys carry no regime),
so the ~48 clean regimes move together at FRA's first failure month or not at
all — Poisson at the measured 0.62 band gives P(none) ≈ 54 %; the three firm
verb regimes move from their verb month regardless; a moved line that no
channel reaches is a defect.

**RESULT (2026-09-29): HELD.** 51 regimes, both sides from worktrees
(`fb6b1d7` vs `66299a2`): 0 identical, 840 moved line pairs, every one in a
named channel's downstream — unemployment 395 rows and approval 382 lead;
GDP moves 13 rows at print precision through the Okun/deficit feedback. The
coin landed "move": FRA's failure timeline is non-empty and shared (clean
regimes diverge together at the 2027 rows), GBR through its own. Class B
confirmed: `managed_subsidises` diverges at verb month + 1, pre-failure.
**One verdict flip: `managed_bill_is_held` LOST→HELD on a 0.1-point
vote-share margin** through jobs→approval→poll — recorded, not tuned.
Zero `characters:` acts, zero verb-answer lines, invariants 50/50, PROBLEM
lines identical (the ruinous regime's designed debt-runaway). The A3 clamp
obligation closed with it: the ±2.00 impulse clamp did not newly bind
(growth moves ≤ 0.05) and the suite's stay-off-every-clamp checks are green —
no re-sizing owed.

## 36. `SAVE_VERSION` stays 37 — argued per field, three times

B1's header argument: absent, every machine key reads its default — no
relocation, not failed, no window, no bid, no shadow — and that is the truth
about every save that predates the machine; a pre-B1 save cannot HAVE a
pending bid, so "absent means none" is exactly right across this line. B2's
verbs write only keys whose absence already means the pre-verb state. The
sparse register repairs itself through the seed rather than through a version
gate. The pin lives in `tests/test_companies_tiers.gd` beside the round-trip.

## 37. The declared stopgaps and the open calls

- **The executive kind carries no meter and no wants** — a firm's chief is a
  face until [[v4.2]]'s lobbying gives a firm's interest a lever. Sunset
  pinned in `tests/test_people.gd`.
- **The relocation discount is nearly inert**: the nearest-region target makes
  the distance discount a near-constant ×0.85–0.98; the constants comment's
  Lisbon–Warsaw is unreachable by construction. Recorded, band holds.
- **A second simultaneous bid is invisible** until the first is answered
  (`pending_bid` returns the first); p ≈ 0.008/yr per nation. Recorded.
- **The 25 generated nations' majors are generator-owned**, pinned by
  `--check`; hand-curating them means narrowing `--check` to the body tier
  first. The AUTHOR's call, carried open since the A3 review.
- **The from_dict aliasing hazard** (V4.6 §6) is fixed for `companies` (T5's
  rebuild) and still recorded live for `companies`' neighbours
  (`plants`, `projects`, `sector_investment`): the sweep stays open.

## 38. The screenshot pass

**RESULT (2026-09-29): two flags added to the capture harness and two frames
judged clean.** `--bid` stages the machine's own bid (three scalars, the
target chosen by the machine's eligibility — a larger same-sector foreign
major) on the player's register; `--failing` stages the machine's own failure
(flag, share 0.0 to the residual, rescue window). Neither ticks afterwards:
the bid window is three months and the rescue window six, so a staged-and-
ticked capture lapses the very row it exists to show. Frames:
`.superpowers/sdd/frames/v47b_bid.png` (FOREIGN TAKEOVER BID, "AUI offers
€ 4.3 bn for Granval Cooperative — 3 months left", Block/Allow verbs) and
`v47b_failing.png` (FAILING FIRMS, "Banque Méridienne — rescue window:
6 months left", Strategic Rescue Package). The panels drew the machine's
state without a tick — the sections read the register directly.

---

Related: [[index]] · [[legislature-model]] · [[economy-model]] · [[opinion-model]] ·
[[coercion-model]] · [[defence-model]] · [[bloc-model]] · [[geography-model]] ·
[[v1]] · [[ROADMAP]]
