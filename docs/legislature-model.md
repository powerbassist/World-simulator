---
title: Legislature Model
tags:
  - decision
  - legislature
  - simulation
---

# Legislature Model

The MVP legislature model, as built in S7. Law templates, how a
party's support for a law is computed, how a vote resolves, and how a passed
law's effects land on the economy and on opinion.

Same standard as [[economy-model]], [[opinion-model]] and [[election-model]]:
a **game model**, judged on whether the player's decisions produce a legible,
attributable legislative outcome — not on whether it would survive a
comparative-politics seminar. Where realism and legibility conflict,
legibility wins, and the trade is noted.

## Where it sits

```
clock.month_elapsed
  → Economy.tick_month(state)      GDP, sectors, unemployment, population
  → Budget.tick_month(state)       revenue, spending, deficit, debt
  → Opinion.tick_month(state)      satisfaction, salience, approval
  → state.append_history()
  → Discipline.tick_month(state, loader)  party discipline erodes or recovers
  → Legislature.tick_month(state)  cooldowns count down
  → Elections.tick_month(state, loader)   schedule check, vote share, seats
```

`Legislature.tick_month()` only counts cooldowns down; proposing and resolving
a law is not a monthly event, it is a player command — `Legislature.propose()`
— the same shape `Budget.commit()` is. It runs before the election check for
the same ordering reason [[election-model]] gives for running last: whatever a
law changed this month should be visible to a vote that reads state before the
month ends, not held back a tick.

Gated on `has_budget`, the same flag every other opinion-reading system uses.
`Legislature.init_nation()` runs for all ten nations so the state shape stays
uniform, the same reason [[opinion-model|opinion]] and
[[election-model|elections]] initialise nations they never tick.

## No new ideology vocabulary

Every law gets a position on **the same two axes**
`src/sim/election_constants.gd`'s `SLOT_POSITION` already puts every party's
ideology slot on — economic (−1 left … +1 right), social (−1 open … +1
traditional). A bloc-to-law affinity matrix, or a second per-theme vocabulary,
was rejected for the same reason [[election-model]] rejected a direct
bloc-to-slot matrix: numbers nobody could individually defend, retuned as a
group at every balance pass. A law's position is one more point in a space
that already has twelve, arguable the same way a party's ideology slot is
argable against its name.

## Party support

```
dist(p, law)    = |SLOT_POSITION[p.ideology_slot] − law.position|      (2-D euclidean)
spatial(p, law) = 2 · exp(−(dist / LAW_SIGMA)²) − 1                    → [−1, +1]
support(p, law) = clampf(spatial + coalition_bonus(p), −1, +1)
```

| Constant | Value | Why |
|---|---|---|
| `LAW_SIGMA` | 0.6 | Tighter than [[election-model]]'s `AFFINITY_SIGMA` (0.8) — parties are disciplined voting blocs deciding on a specific bill, not a fuzzy electorate; a party a full axis-width from a law is close to indifferent rather than merely lukewarm. |

> [!note] Corrected in V1.1a: the government term used to be a flat constant
> This read `+ GOVERNMENT_BONUS · [p is incumbent]`, a flat 0.35 for whichever
> single party held `ns.incumbent_party_id`. A government is now a **coalition**,
> so the bonus is earned rather than given: `government.gd:coalition_bonus()`
> scales `COALITION_BONUS_MAX` by the party's distance from the coalition's
> agreed position and by its authored `discipline`. Opposition still scores zero,
> exactly as before. `GOVERNMENT_BONUS` is gone from
> `legislature_constants.gd`; the argument for what replaced it is
> [[government-model]].

`spatial` is rescaled to `[−1, +1]` rather than `[0, 1]` the way
[[election-model|vote-share affinity]] is, because a law has opponents, not
just varying enthusiasm — a party ideologically opposite a bill should
register a *negative* support, not a small positive one that then gets
outweighed. Vote share never needed that distinction because every party
always gets *some* electoral coalition; a law vote does not work that way.

## Three stages, not one — since V1.1e

```
propose()  →  the assembly divides        resolve_vote(), unchanged
           →  the SECOND CHAMBER divides  resolve_upper(), on a composition
                                          chambers.gd derives and a reduced whip
           →  (route B: the country)      referendum.gd, V1.7c
           →  the COURT reviews           judiciary.gd, a gate before apply()
           →  in force
```

`resolve_vote()` is **untouched** by either addition — about twenty-five call sites
read it, and reaching into it would be a second writer of this project's central verb.
The second chamber reuses `spatial_support()` and `vote_of()`, both already public
here, plus `Government.coalition_bonus()` at `chambers_constants.UPPER_WHIP`; the
court reads a `reach` [[judiciary-model|`law.gd` computes at load]].

A refusal is a THIRD and FOURTH outcome rather than a defeat. `absolute` kills the
bill and writes its cooldown; `suspensive` **holds** it — no cooldown, off the open
list, and `tick_month()` releases it `UPPER_HOLD_MONTHS` later at a price. That is
V1.7c's in-flight shape reused rather than a second scheduler, and it is why the hold
needed **no new tick anywhere**.

## Vote resolution

A party's **line** is `support(p, law)` read against `ABSTAIN_BAND`. Until
[[v1|V1.1b]] every seat the party held went with that line; since V1.1b a share
of them set by [[discipline-model]] goes with `spatial(p, law)` instead — what
the same members would vote with no whip on them. `party_votes` in the result
still names the line, and `party_rebels` says how many seats did not follow it.

```
line(p)     = support(p, law)         >  ABSTAIN_BAND → yes,  < −ABSTAIN_BAND → no,  else abstain
unwhipped(p) = spatial(p, law)        bucketed the same way
rebels(p)   = Discipline.rebel_seats(...)   0 unless the two buckets differ

yes / no / abstain = Σ (seats_by_party[p] − rebels(p)) into line(p)'s column
                   + Σ rebels(p)              into unwhipped(p)'s column

passed = yes  >  no                                   if majority == "simple"
       = yes  >  0.5 × seats_total                     if majority == "absolute"
       = yes  >= (2/3) × seats_total                   if majority == "two_thirds"
       = yes  >= FRACTION[ns.amendment_rule] × seats_total   if majority == "amendment"
```

`"amendment"` (V1.2c) reads the *proposing nation's own* threshold off
`ns.amendment_rule` rather than a fixed fraction — the whole point of a
constitutional amendment being gated by real, per-nation data instead of one
global constant. Full argument, including the measurement that found
Germany's real `two_thirds` unreachable even at full term-start cohesion:
[[amendment-model]].

The three columns still sum to `seats_total` exactly: a rebellion moves seats
between them and never creates one.

| Constant | Value | Why |
|---|---|---|
| `ABSTAIN_BAND` | 0.05 | Support within this band of zero counts as an abstention, not a firm yes or no — the same idea [[election-model]]'s incumbent-swing clamp uses: a small guard rail, not a modelling claim. |

Three majority types for ordinary laws, matching how the sixteen
tax/labour/social/institutional templates actually split: ordinary policy
laws use `simple`; laws with a long-run structural effect (retirement age,
health funding) use `absolute`, since durable change should cost more than a
plurality; institutional laws that fall short of a full constitutional
amendment (devolution) use `two_thirds`. A fourth, `"amendment"`, is
V1.2c's own — see above.

**Reads `ns.seats_by_party`, never `party.seat_share`.** `seats_by_party` is
live state, seeded by `Elections.init_nation()` from the authored starting
roster and rewritten at every election; `party.seat_share` is the authored
starting composition and is never mutated after new-game — see
[[data-architecture]]. A law proposed after the assembly has turned over votes
against the assembly the player actually has.

**No `rand()` anywhere**, rebellions included. A vote is exactly reproducible
from state — the same discipline `economy.gd`, `budget.gd`, `opinion.gd` and
`elections.gd` all keep, and for the same reason: `tests/test_budget.gd`'s
projection-equals-reality guarantee would break if any tick called an RNG.

**`resolve_vote()` does not mutate.** The rebellion a division provokes costs the
party discipline, but that step is applied by `propose()` from the result, so the
resolver stays a pure function of state and the law screen's forecast can call it
as often as it likes.

## Suspense is a display-layer trick

The law screen shows a forecast before the player commits to proposing. Since
the model is deterministic, an exact forecast would mean a law never surprises
the player — which is fine for the budget screen (a slider is not a
gamble) but wrong for a vote, which the roadmap wants to feel like an obstacle.

`src/ui/law_panel.gd` blurs it: a party whose `|support|` falls inside
`FORECAST_UNCERTAIN_BAND` (0.15 — wider than `ABSTAIN_BAND`'s 0.05) shows as
**Undecided** in the forecast, its seats pooled separately from the yes and no
tallies. The real vote still resolves off the exact same `support()` value at
the tighter `ABSTAIN_BAND` the moment the player actually proposes.

Rebel seats are **not** blurred. They are counted into the column they will
actually vote in, with the total called out beside the tally, because the
government screen already publishes the per-party figure and hiding it here would
make the forecast optimistic in one direction only. The uncertainty a forecast is
allowed to manufacture is about where a party stands, not about arithmetic the
player can already read on another tab. This needs
no hash-based noise function the way [[opinion-model|polling]] and
[[election-model|no election-day noise]] both discuss and reject for their own
cases — the two bands are both plain functions of state, so the blur is
already deterministic and already survives a reload with nothing to
serialise. `src/sim/` has no forecast concept at all; only `law_panel.gd`
knows the two bands differ.

## Effect channels

A passed law's effects are additive, persistent state on `NationState`,
clamped in `legislature_constants.gd`. Every channel is one extra term folded
into a formula that already exists — nothing here is a new equation.

> [!note] Since V1.8 the dispatch is `apply_effects()` and a law is not its only caller
> `Legislature.apply()` now calls `apply_effects(state, ns, effects, loader)`, split out
> unchanged so an **event choice** reaches the same channels. What made the split worth
> taking rather than duplicating is what it protects: `bloc_offset`,
> `regulation_burden`, `corruption`, `migration_stance`, `settlement_stance` and
> `press_freedom` each have exactly ONE writer, and it is that function. A second applier
> in `src/sim/events.gd` would have been a second writer of all six at once, with the six
> clamps agreeing by inspection rather than by being the same line of code.
>
> **The approval path is what separates the two callers**, and that is V1.4a/V1.4b's a/b
> line one block later: a law reaches these channels through a vote, an event choice
> through a decision made under a deadline. Same mechanism, different route, one writer.
> `effects.institutional` stays in `apply()` and is refused on an event choice by name —
> it is "Emergency powers", tiered Someday. `extract_preconditions()` and `read_field()`
> went public in the same commit, so an event evaluates the same triple against the same
> whitelist rather than against a third copy of a list this file already records as
> existing twice. See [[events-model]] §4.

| Channel | Field | Read by | Why |
|---|---|---|---|
| Budget levers | *(none — routed through `Budget.commit()`)* | `budget.gd:commit()` | A law that moves a tax rate or spending line **is** a budget change. Routing it through the same command the budget screen uses gets the demand impulse, the erosion curve and the matching opinion issue for free, and makes double-counting structurally impossible — a law cannot move a lever *and* carry its own separate demand-impulse term, because there is only one path a lever change can take. |
| Labour | `law_structural_offset_pct` | `economy.gd:_update_unemployment()`, added alongside the existing income-tax wedge, inside the same clamp | Flows into unemployment, then into the `jobs` issue, then into approval — with no new opinion plumbing, the same way [[economy-model]]'s own structural-unemployment term already does. |
| Long-run growth | `law_potential_target_pct` | `economy.gd:_update_potential_shift()`, added into `target` before the lag | Inherits the five-year time constant and the ±1.0 %/yr hard clamp that is [[economy-model|the model's whole stability argument]] — this is the only term that feeds back into trend, so a law cannot bypass the one guard rail that matters. |
| Off-budget revenue | `law_other_revenue_pct_gdp` | `budget.gd:recompute()`, added to `other_revenue_pct_gdp` | For levies with no slider — a carbon levy, a lobbying-registration fee — the same "authored residual" slot `other_revenue_pct_gdp` already fills for social contributions and local taxes. |
| Direct opinion | `bloc_offset{}` | `opinion.gd:_tick_nation()`, added to a bloc's approval **target**, clamped together with the satisfaction score before scaling | For laws with no budget footprint and so no matching issue — immigration rules, an anti-corruption agency. Added to the *target*, not to approval directly, so `INERTIA_RATE` and every bound in [[opinion-model|opinion's own stability argument]] still apply; a law cannot make approval jump in one month any more than a policy change can. |
| Institutional | `censure_rule`, `dissolution_rule`, `formation_method`, `amendment_rule`, `term_limit`, `term_months` on `NationState` | Whichever system already reads that field — `government.gd`, `dissolution.gd`, `elections.gd` | The only channel that sets an **absolute value** rather than accumulating a delta — an institution is changed, not nudged. Constitutional-amendment-only (`law.constitutional == true`); see [[amendment-model]] for the load-bearing check that stops an amendment writing a value its own declared system doesn't permit. |
| Sector regulation (V1.4b) | `regulation_burden{}`, keyed by sector | `companies.gd:headcount()` and `firm_impulse_pct()`, the two channels V1.4a already built | The only channel pointed at something that is **not the nation** — a firm, through the sector it sits in. A law names a `sector` and a signed `burden` and may never name a firm, because share movement is the subsidy's channel and a second writer of it would be two answers to one question. Adds no price and no clamp of its own: one quantity read at two existing sites. See [[companies-model]] §10–15. |

**The rule that prevents double-counting:** a law with a genuine budget effect
expresses it as a lever, through `tax_rates_pct` or `spending_pct_gdp`. The
`bloc_offset` channel exists only for laws where there is no number the budget
produces — which is exactly why there is no issue for that law to be salient
about in the first place. A law is never authored with both a lever and a
`bloc_offset` entry for the same bloc's reaction to that lever; the sixteen
templates each pick one story and tell it once.

> [!note] V1.4b makes one instance of that rule a LOAD ERROR
> A law carrying both `effects.company` and `structural_unemployment_pct` fails at
> load in `law.gd`: a sector burden already reaches structural unemployment through
> the firm register, so the two are the same act, the same landing site and the same
> units. The rule above is enforced by convention, which is something an author
> breaks by not reading this file; that one is enforced by the loader. Where a rule
> *can* be mechanical it should be — [[coercion-model]]'s separator, which refuses a
> symmetric key where a directed one belongs, is the precedent.
>
> The `bloc_offset` half went the other way, and the probe is why. A saturated
> burden moves growth ~0.1 %/yr and unemployment ~0.02 points, **below the opinion
> model's resolution** — so a regulation's political price cannot be expressed by the
> measured channel and must be authored. Refusing to name the losers made the whole
> regulation stack free: +6.45 headline against a ±3.0 floor. See
> [[companies-model]] §16.

`opinion.gd`'s invariant that a bloc's target lives in `[10, 90]` is preserved
by construction: `score + law_offset` is clamped to `[−1, +1]` before being
scaled by `APPROVAL_SPAN`, the same bound a pure satisfaction score already
respects on its own.

## Template schema

`data/laws/{tax,labour,social,institutional,business}.json`, each `{"laws": [...]}` —
the fifth theme is V1.4b's and is named for a **domain** like the other four rather
than for a mechanism: a theme called "regulation" is where [[v1]] §6's sectoral
investment would wrongly land, and what separates those two is the firm register,
not the word. `_load_laws()` directory-scans, so a fifth file needed no loader
change —
the same shape `data/parties/*.json` uses. See [[data-architecture]] for the
full field list and `src/core/law.gd` for validation.

Deliberately **not** in the schema: per-party amendment, sponsors,
multi-stage passage, sunset clauses. All are [[v1|V1.1]]
territory, and the shape is extensible by adding keys — the same lesson
S1 leaves for the nation schema. **Upper-house readings left that list at
V1.1e** and cost the law schema nothing: a second chamber is `resolve_upper()` over a
composition `src/sim/chambers.gd` derives, and what it may do to a bill is per-NATION
data (`government.upper`) rather than per-law — see [[upper-house-model]].

`preconditions` is a whitelisted field vocabulary
(`debt_to_gdp_pct`, `unemployment_pct`, `deficit_pct_gdp`,
`overall_approval_pct`, `growth_annual_pct`, `terms_served`), not an arbitrary
expression language. An unknown field is a startup error, not a silently-false
predicate — the same failure discipline `data_loader.gd` already applies to an
unpositioned `ideology_slot`.

## Constants vs content

`src/sim/legislature_constants.gd` holds every tunable — `LAW_SIGMA`,
`ABSTAIN_BAND`, the majority-threshold fractions, and every effect channel's
clamp. Model parameters, one set forever, next to `economy_constants.gd`,
`opinion_constants.gd`, `election_constants.gd` and `government_constants.gd` —
not in `data/`, per [[engine-decision|Rule 1]]. `AMENDMENT_RULE_FRACTIONS` is
the one exception to "one set forever" in spirit but not in mechanism: the
*fractions* are model constants same as the other three, but *which fraction
applies* is read off `ns.amendment_rule` — per-nation data, constrained by the
political-system template — not a single value this file picks for everyone.
See [[amendment-model]].

`FORECAST_UNCERTAIN_BAND` lives in `src/ui/law_panel.gd`, not here, for the
same reason `poll_noise.gd`'s `NOISE_MAX_PCT` lives in `src/ui/` and not in
`opinion_constants.gd`: it is not a model parameter, because the model does not
know a forecast exists.

## Why nothing diverges

| Quantity | Bound |
|---|---|
| `support(p, law)` | Clamped to `[−1, +1]` by construction. |
| Vote outcome | A deterministic comparison of two seat counts against `seats_total`; both are bounded by the assembly size. |
| The three columns | Sum to `seats_total` exactly, at any discipline and on any law — a rebellion moves seats between them and never creates one. Asserted in `tests/test_discipline.gd`. |
| `law_structural_offset_pct` | Hard-clamped, `[−5, +5]` points. |
| `law_potential_target_pct` | Hard-clamped to the same `±1.0 %/yr` [[economy-model|`potential_shift`]] already enforces — this cannot let a law compound trend growth beyond what the economy model already guards against. |
| `law_other_revenue_pct_gdp` | Hard-clamped, `[−10, +10]` points of GDP. |
| `bloc_offset[bloc]` | Hard-clamped to `[−1, +1]`, and clamped again in combination with the satisfaction score before it reaches `APPROVAL_SPAN`. |

Every channel is an accumulator a law writes once and a formula reads every
month afterward — never a term that grows on its own. The argument is not the
evidence: `tests/test_legislature.gd` applies every authored law at once and
runs 120 months, asserting every field stays finite and unemployment stays in
`[0, 100]`, the same shape `tests/test_economy.gd` uses for an absurd budget.

## The effect ledger — V4.2 T1

Every law that passes leaves a record of what its passage *actually moved*.
`ns.law_ledger[law_id]` holds `{"channels": {...}, "months": [...]}`, where
`channels` is the before/after diff `apply()` takes around `apply_effects()`.
Three properties carry the design.

**Realized, not authored.** Every accumulator clamps, so a law authored +2.0
against a register already at +0.9 of a ±1.0 clamp records +0.1 — the amount
that landed — and a repeal that subtracted the authored number would push the
register past the bound in the other direction. Two consequences, both
enforced at `_record_ledger()`: the snapshot reads **only the fields the law's
own effects name** (one that walked every register would record another
writer's movement as this law's), and a zero realized delta records NOTHING —
a clamp binding at both ends moved nothing, and an entry that claimed it did
would subtract nothing and lie.

**One act, one entry.** A non-`once` law passed twice merges into the same
sub-keys rather than opening a second entry — one act, repealed once.
`months` carries each passage's `year*12 + month` stamp.

**The first-order bound, stated where it can bite.** The repeal's subtraction
clamps like any write, so a register already pushed past a bound by *other*
writers absorbs part of the removal. The true counterfactual register is not
recoverable once other writers have moved in between, and inventing one would
be a second answer. A declared bound of realized-delta bookkeeping, not a
patchable defect. **The two budget channels have no clamp and take their own
floor instead** (the ultra pass-8 finding): a removal whose recorded delta
exceeds what the register holds lands what is there, and no more — a negative
rate is a state every other writer refuses, and the floor is the register's
own, the one every slider already applies.

`SAVE_VERSION` 38 carries the register; absence reads empty, and the repeal
gate refuses a law with no record loudly rather than repealing nothing
silently.

## Repeal — V4.2 T1

A repeal is a bill like any other — proposed, divided on, court-reviewable —
whose `repeals` field names a law id. At the TOP of `apply()` sit the
subtraction and the ledger record, because `apply()` is *every* path on which
a bill takes effect: the division, the referendum settle, the upper-house
release. `_subtract_ledger()` negates the target's **live** ledger and pushes
it back through `apply_effects()` — the one applier, so budget levers route
through `Budget.commit()` and the erosion curve and demand impulse fire exactly
as any budget change would — then erases the entry and writes the target's own
cooldown, so a repealed act sits out its cooldown before it can be re-proposed.

**A pure repeal records no ledger entry of its own.** Its subtraction runs
*before* the snapshot, and its negation is not re-recorded, so the book has no
path back *through the repealer*: repealing a repeal removes nothing and
re-adds nothing. The repealed act returns the only way an act can — by being
re-proposed and re-passed after its cooldown, a new passage with new realized
deltas. (An early draft of this section, and of the `repeals` field's comment
in `law.gd`, claimed the repealer's passage got its own ledger entry and that
repealing a repeal re-added; neither is mechanically possible, and the draft
gate refuses both shapes loudly.) The cooldown comes off the target law
wherever it lives — an id the loader does not know is a composed law, found a
second time in `ns.custom_laws` — which is what makes the 24-month re-proposal
cadence hold for the compositions as well as the authored book.

`Legislature.repeal_target_legal()` gates the draft at composition time, not
at passage. Two refusals, and the second is the one that earns the loader
parameter on `Statute.draft()`: the book must record the target, and the
target must not SET anything. That is not only the constitutional case — the
ordinary-reform route lets a non-constitutional law carry
`effects.institutional` (the electoral-reform Acts), and a setting has no
inverse delta: the repeal would subtract the bloc price and leave the electoral
system in force, the half-removed act class. Restoring a system is a NEW
reform act, not a repeal. A law id the loader does not know is a composed law
(T2's register); composed laws are never constitutional and never authored
with an institutional channel, so the null lookup reads legal.

## Composition — V4.2 T2

The player drafts a bill out of named effect channels;
`Statute.draft(state, ns, loader, spec)` validates it, sizes it, prices it
politically, and parks it for a drafting period; `tick_month()` counts the
parked drafts down; at zero each becomes a law in the nation's own register —
proposed, voted, failable, repealable like any other.

**The channels are the applier's vocabulary, minus two by construction.** A
spec may name `tax_rates_pct` / `spending_pct_gdp` (keyed), the three scalars
(`structural_unemployment_pct`, `potential_growth_pct`,
`other_revenue_pct_gdp`), one `company` {sector, burden} and any `society`
terms — exactly the shapes `apply_effects()` reads, because passage runs the
merged dictionary through the ONE applier. `bloc_offset` is refused because
the political price is what the machine *derives* (`bloc_offset` in a spec
would be the player writing their own approval); `institutional` is refused
because T1's repeal gate would refuse the bill at birth — a composed setting
is an unrepealable act. The three anti-double-count pairs `law.gd` enforces at
load are enforced here at the machine (a sector burden with a structural
delta, a corruption stance with a spending line, a migration stance with a
structural delta): one story per bill, or passage would run effects the schema
exists to refuse.

**The budget is arithmetic, not judgement.** Size = Σ |value| ×
`CHANNEL_COST[channel]`, refused past `DRAFT_SIZE_MAX`; drafting time =
`DRAFT_MONTHS_BASE + ceil(size × DRAFT_MONTHS_PER_SIZE)` months. Cost per unit
is scaled so a typical authored single-channel law spends ~1.0 of budget — the
tax levers are cheap because the authored ones move in points, the accumulators
dear because the authored ones move in fractions.

**The price is derived, never authored.** `CHANNEL_PRICE` holds a per-unit,
per-bloc row per channel — every row cites the authored law it mirrors, and
the anchor row IS `high_earner_surtax` verbatim (−0.03 business / +0.01
workers per point of income rate). Contribution = value × per-unit price,
signed for either sign of value, so a composed cut reads the mirror of the
composed rise exactly as `corporate_tax_cut` does against its authored
sibling. Spending prices per portfolio with separate rise/cut rows, because
loss aversion is authored content (`retirement_age_reform`'s pension cut buys
−0.35 on −1.2; no authored rise pays that). Exact-zero sums are dropped, so a
single-channel draft always prices at least the blocs its row names — the
all-upside guard at width one. What the table does *not* do is read back: the
price lands on the composed law's effects as `bloc_offset` and reaches the
country through the approval target, the same channel any authored law uses.

**The register is the save form.** `ns.custom_laws` holds `to_save_dict()`
payloads, rebuilt through `Law.composed_register()` — the ONE rebuild shared
by `propose()`'s legality scan and the UI read, so a composed law is scannable
by the sim and visible to the player without two factories drifting.
Composed laws carry `origin "player"`, `composed`, `once = false` and the
drafting cooldown. No `rand()` anywhere — the countdown is a counter, the id
arithmetic on an append-only register, the price a pure function of the spec —
so two identical states draft identically.

## The drafting budget and its bands — V4.2 T3

The composition constants were DECLARED at T2 as starting midpoints and are
swept here, bands first. The instrument is `tools/composition_probe.gd`: the
grid is breadth {single-best channel, single-worst channel, half the kinds,
full} × size {1.0, 3.0, 6.0} × position {five points per axis, 5×5}, 100
seeded assemblies per cell — the same assembly pool reused across every cell,
so comparisons are paired. Assemblies are `Elections.init_nation` variants:
each party's authored seat share is multiplied by a seeded draw in
[0.55, 1.45] and re-allocated through the same largest-remainder step any
election uses. The coalition is the new-game one throughout — one government,
many assemblies, which is the variation a drafted bill actually faces.
"Full" breadth is SIX kinds, not seven: the anti-double-count law makes
`structural_unemployment_pct` uncomposeable with both `company` and
`society.migration`, so the largest conflict-free kind-set is six — full
breadth is the ceiling the machine allows, which is itself a finding. Within a
cell the size budget is split into equal slices per channel. All numbers
below were produced by that probe and none by a hand calculation.

| Constant | Value | Why |
|---|---|---|
| `DRAFT_SIZE_MAX` | 6.0 | The budget a maximal omnibus may spend. Sized against the authored laws: a surtax-scale lever costs ~1.0, so the cap admits a six-channel omnibus at surtax scale and refuses a thirty-point income rise alone. |
| `DRAFT_MONTHS_BASE` | 2 | The floor drafting time — even a minuscule bill does not reach the floor in the month it was drafted. |
| `DRAFT_MONTHS_PER_SIZE` | 1.0 | Months per unit of budget. A 6.0 omnibus drafts 8 months — most of a playable quarter-year, cheap next to a 24-month cooldown. |
| `DRAFT_COOLDOWN_MONTHS` | 24 | The composed law's re-proposal cooldown, two years — an omnibus should not become a monthly entitlement. |
| `CHANNEL_COST` | see file | Budget price per unit of movement per channel; the ratio between rows is the model's claim about what a government can bundle. |

The bands, declared before the run:

- **P1 — the anti-all-upside clause.** The full-breadth max-size bill (the
  grid's `full × max` cell) must (i) carry a derived worst-bloc price ≥ 1.0
  point of approval-target — the standing readability floor: the polling panel
  prints one decimal, and V2.6b1 measured a movement under 1.0 point as
  unprintable against the ±3.0 displayed-noise band — and (ii) be carried by
  FEWER of the 100 assemblies than a single-channel bill at the same position.
- **P2 — breadth monotone.** At a fixed position, the pass count is
  non-increasing in size, within every breadth family.
- **P3 — tempo.** A max-size bill takes ≥ 8 months draft-to-vote; a min-size
  bill ≤ 3. A composed bill must not arrive faster than an authored one could
  be proposed, and a tiny one must not stall a term.
- **P4 — determinism.** Two identical states draft the same spec into
  identical ids, sizes, months and bit-identical derived prices.
- **P5 — bounds.** Every grid cell's derived price, pushed through the ONE
  applier, leaves `bloc_offset` inside `[BLOC_OFFSET_MIN, MAX]`; the sweep
  records where the clamp binds — a binding clamp is the gap between the price
  the player was quoted and the price that lands, which the ledger records as
  the realized delta.

**The negative control, and what it decides.** The max-breadth max-size bill
composed with `CHANNEL_PRICE` ZEROED (the probe derives what the machine would:
every row × 0 is exact-zero, and exact-zero is erased — the price is empty)
must dominate the grid: tie-or-beat every real bill's pass count at the same
position and undercut every real bill's worst-bloc price. If the control
dominates, breadth without the table is free — which is the proof that the
price table, not the vote arithmetic alone, closes the all-upside hole. The
division in this model prices POSITION only (`support()` is spatial plus the
coalition bonus; effects never enter), so the table's price lands on the
country and not on the division — P1(ii) is the clause that probes whether any
division-side cost exists at all.

### The swept verdicts (probe run 2026-10-03, seed 20261003, FRA, 100 assemblies)

The grid's worst-bloc prices, position-blind because the derived price reads
channels only: single-best reaches 0.900 at the cap (business, the anchor row
on a 30-point income move), single-worst 0.750 (the growth analogue row), and
breadth is what buys price — half 1.325, full 1.183, both on urban, both from
the spending rows doing most of the work. Only the four full/half cells at
max size clear the 1.0 floor; breadth is not one input among several, it is
the floor's only route.

- **P1 — PASS on (i), FAIL on (ii), and (ii) is the record, not a tuning
  debt.** (i): the full|max bill carries |urban| = 1.183 ≥ 1.0. (ii): the
  same bill is carried by **69 of 100** assemblies at its most accommodated
  position (0.0, −0.5) — and so is `single_best|max` (69) and
  `single_best|min` (69); full|max ties the single-channel bill at **25 of 25
  positions**, bit for bit. No constant reaches this clause, because
  `resolve_vote()` reads the law's position and majority and nothing else —
  the division is effects-blind *by measurement now, not by inspection*.
  That is the design working as documented, and it is why the negative
  control's sentence reads "the price table, not the vote arithmetic alone":
  breadth's political cost lands entirely on the approval target, at the
  next election, and never on the division. **Making breadth cost divisions
  is an author call on `resolve_vote()` — a machine change with ~25 call
  sites and the forecast reading it — and is recorded here as open, not
  taken.** The price table carries the whole anti-all-upside load, which
  P1(i) says it can bear.
- **P2 — PASS, flat.** Zero violations in the probe's 100 position-breadth
  windows (4 breadth families × 25 positions, two size transitions each),
  and zero strict size-drops: the monotonicity holds trivially for the same
  reason
  P1(ii) fails — size never reaches the division either. The pass-rate
  surface over positions is sharply peaked (69 of 100 at France's centre
  left, 0 at every corner), so the assembly pool has real variance and the
  flatness is not a degenerate pool.
- **P3 — PASS at both edges.** Size 1.0 drafts in 3 months, size 6.0 in 8 —
  the shipped `DRAFT_MONTHS_BASE` 2 + `DRAFT_MONTHS_PER_SIZE` 1.0 arithmetic
  lands exactly on the band the model declared, at both ends, with no
  interior to tune.
- **P4 — PASS.** Two identical states draft the full|max spec into identical
  ids, and the parked entries and derived prices are byte-equal
  (`var_to_bytes`, not `==`).
- **P5 — PASS, with the binding count recorded.** All 12 distinct derived
  prices land inside [−1.0, +1.0] through the one applier, and two BIND:
  half|max quotes urban +1.325 and full|max quotes +1.183 against the ±1.0
  clamp — passage lands +1.0, and the ledger records the realized (smaller)
  delta. The quote-to-landing gap is bounded by exactly the bills P1(i) is
  about, and it is structural: the readability floor (1.0) sits AT the
  clamp, so any bill that clears the floor on one bloc has said everything
  the clamp allows. Recorded as the declared bound of the derived-price
  form; T5's briefing surfaces should quote the derived price and the
  realized ledger is the record of what landed.

**The negative control — DOMINATES.** The zeroed-table control ties the best
real pass count at every position (worst real-better gap 0) and prices 0.0 on
every bloc against a grid whose cheapest real worst-bloc price is 0.050. Max
breadth at zero price is carried everywhere the assembly allows and costs
nothing anywhere — the all-upside hole is real and open, and the one thing
standing in it is `CHANNEL_PRICE`. The constants held: **no value moved in
this sweep.** P1(i) clears the floor with the shipped rows, P3 lands on the
shipped arithmetic at both band edges, and P5's binding cells are a recorded
bound of the form rather than a tuning failure — the V1.5d rule cuts both
ways, and a sweep whose bands hold is a sweep that changes nothing.

## The assembly's own life — V4.2 T6

The statute book stops being the player's alone: `statute.gd`'s tick also
runs the assembly's own life, and `ns.assembly_bills` is its in-tray. Two
deterministic hazards table bills. The backbench floor is
`PMB_HAZARD_MONTHLY` 0.08 — just under one draw a year, often enough that a
player who never drafts still has a book moving under them; the measured
idle band is 9 bills in 120 months (FRA), and the test pins 1–20. The
chiefs' lobby is `LOBBY_HAZARD_MONTHLY` 0.02, five times rarer on purpose,
because a lobbied bill exists to raise the question a plain PMB does not
("whose bill is this?") and a raised question stays raised only when it is
rare; it fires only when a sector's `regulation_burden` stands above
`LOBBY_BURDEN_FLOOR` 0.1 (a tenth of the register's clamp) AND that sector
has a major whose chief can sign the ask AND the book carries a
burden-easing law to name. Both draws ride `Cycle.unit` over the absolute
month — no `rand()`, a replay tables the same bills — and the whole machine
sits behind `has_budget`, the standing refusal of AI nations legislating.

The endorsement is the player's one verb on a private member's bill, and the
window is one month (`PMB_MONTHS_TO_VOTE`): the announcement card IS the
window, and the assembly divides on the next tick with or without the
president — the assembly proposes and the assembly decides. The stand is
`PMB_ENDORSE_SUPPORT` 0.10 added to every party's support line through
`resolve_vote()`'s DEFAULTED `support_bonus` parameter — the sanctioned
reading, since that signature owns ~25 call sites and a statute-side wrapper
would have re-mirrored the loop and the majority match verbatim; every
existing call is source-identical. The bonus re-clamps like every line, so
it can carry a bill sitting on the `ABSTAIN_BAND` (0.05) fence and cannot
buy one the house opposes — and a line dragged onto a bill the backbench
does not back can shed seats through the rebellion split that already
prices exactly that strain. The endorsement's own political price
(`PMB_ENDORSE_PRICE`, workers +0.05 / business −0.05) lands ONCE through
the ONE applier at endorse time — the endorsement is the news, the vote a
month later is not — and a second stand is refused, because a re-priced
stand would be two charges for one act.

Two recordings the machine made of its own costs. The **fall-through**: a
fired lobby whose ask cannot be built never wastes the month — the chief
still brings a plain backbench bill — so on its fire months a burdened
nation's effective plain-bill rate is 0.08 + 0.02 = 0.10 rather than 0.08
alone. The inflation is recorded in `statute_constants.gd` and accepted
rather than tuned away: fires run ~0.24/yr and only where a sector stands
burdened (an idle world holds none above the floor), far inside the test's
band.

**The pipeline, corrected by the version-close review.** A carried assembly
bill walks the SAME stages `propose()`'s ordinary route walks, in the same
order: the second chamber between the division and everything after it
(`Chambers.power_over()` → `resolve_upper()` — an absolute refusal kills the
bill with the authored cooldown, a suspensive one holds it `UPPER_HOLD_MONTHS`
in `ns.held_bills` exactly as `propose()` parks one), then the court through
`Legislature.review_and_apply_after_division()`. An assembly bill that divided
clean is the ordinary legislative procedure, and that is what the court
reviews — `propose()`'s ordinary route has court-reviewed every carried bill
since V1.1e; a division was never an exemption. (The first draft of this
section recorded a "court skip" on exactly the opposite ground — that the
court's gate was for bills taking effect without a division — and the
division the first draft reasoned beside, the assembly's own, was skipping
the second chamber entirely; both halves were false, and neither was marked.)
A FAILED division faces neither stage: there is nothing yet for a chamber or
a court to review, and the result carries no `upper_*` or `reviewable` key.
The result records each stage under the standard keys — `upper_chamber` /
`upper_passed` / `blocked_by_upper` / `held_by_upper` from the chamber,
`reviewable` / `struck_down` from the court — plus `assembly_bill: true`,
the bill's id, its backer if a chief signed it, and
`assembly_division_month`, the stamp the division card's memory keys on.
`tests/test_statute_assembly.gd` pins the whole machine — the pipeline
included, a Senat-passing and a Senat-held bill both — and the endorsement's
measured effect (control 115/307, endorsed 268/309 on the same assembly).

---

Related: [[index]] · [[election-model]] · [[electoral-systems]] ·
[[government-model]] · [[discipline-model]] · [[opinion-model]] ·
[[economy-model]] · [[amendment-model]] · [[data-architecture]]
