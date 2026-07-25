---
title: Legislature Model
tags:
  - decision
  - legislature
  - simulation
---

# Legislature Model

The MVP legislature model, as built in [[ROADMAP|S7]]. Law templates, how a
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
support(p, law) = clampf(spatial + GOVERNMENT_BONUS · [p is incumbent], −1, +1)
```

| Constant | Value | Why |
|---|---|---|
| `LAW_SIGMA` | 0.6 | Tighter than [[election-model]]'s `AFFINITY_SIGMA` (0.8) — parties are disciplined voting blocs deciding on a specific bill, not a fuzzy electorate; a party a full axis-width from a law is close to indifferent rather than merely lukewarm. |
| `GOVERNMENT_BONUS` | 0.35 | Added to a governing party's support for its own government's bill — party discipline, not ideology. The one non-spatial term in the model, a single constant rather than a table. |

`spatial` is rescaled to `[−1, +1]` rather than `[0, 1]` the way
[[election-model|vote-share affinity]] is, because a law has opponents, not
just varying enthusiasm — a party ideologically opposite a bill should
register a *negative* support, not a small positive one that then gets
outweighed. Vote share never needed that distinction because every party
always gets *some* electoral coalition; a law vote does not work that way.

## Vote resolution

Whole-party bloc voting: every seat a party holds votes the same way. Party
discipline and rebellions are explicitly [[v1|V1.1]]'s job.

```
yes    = Σ seats_by_party[p]  where support(p, law) >  ABSTAIN_BAND
no     = Σ seats_by_party[p]  where support(p, law) < −ABSTAIN_BAND
abstain = the rest

passed = yes  >  no                                   if majority == "simple"
       = yes  >  0.5 × seats_total                     if majority == "absolute"
       = yes  >= (2/3) × seats_total                   if majority == "two_thirds"
```

| Constant | Value | Why |
|---|---|---|
| `ABSTAIN_BAND` | 0.05 | Support within this band of zero counts as an abstention, not a firm yes or no — the same idea [[election-model]]'s incumbent-swing clamp uses: a small guard rail, not a modelling claim. |

Three majority types, matching how the sixteen authored templates actually
split: ordinary policy laws use `simple`; laws with a long-run structural
effect (retirement age, health funding) use `absolute`, since durable change
should cost more than a plurality; constitutional-adjacent laws (devolution)
use `two_thirds`.

**Reads `ns.seats_by_party`, never `party.seat_share`.** `seats_by_party` is
live state, seeded by `Elections.init_nation()` from the authored starting
roster and rewritten at every election; `party.seat_share` is the authored
starting composition and is never mutated after new-game — see
[[data-architecture]]. A law proposed after the assembly has turned over votes
against the assembly the player actually has.

**No `rand()` anywhere.** A vote is exactly reproducible from state — the same
discipline `economy.gd`, `budget.gd`, `opinion.gd` and `elections.gd` all keep,
and for the same reason: `tests/test_budget.gd`'s projection-equals-reality
guarantee would break if any tick called an RNG.

## Suspense is a display-layer trick

The law screen shows a forecast before the player commits to proposing. Since
the model is deterministic, an exact forecast would mean a law never surprises
the player — which is fine for the budget screen (a slider is not a
gamble) but wrong for a vote, which the roadmap wants to feel like an obstacle.

`src/ui/law_panel.gd` blurs it: a party whose `|support|` falls inside
`FORECAST_UNCERTAIN_BAND` (0.15 — wider than `ABSTAIN_BAND`'s 0.05) shows as
**Undecided** in the forecast, its seats pooled separately from the yes and no
tallies. The real vote still resolves off the exact same `support()` value at
the tighter `ABSTAIN_BAND` the moment the player actually proposes. This needs
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

| Channel | Field | Read by | Why |
|---|---|---|---|
| Budget levers | *(none — routed through `Budget.commit()`)* | `budget.gd:commit()` | A law that moves a tax rate or spending line **is** a budget change. Routing it through the same command the budget screen uses gets the demand impulse, the erosion curve and the matching opinion issue for free, and makes double-counting structurally impossible — a law cannot move a lever *and* carry its own separate demand-impulse term, because there is only one path a lever change can take. |
| Labour | `law_structural_offset_pct` | `economy.gd:_update_unemployment()`, added alongside the existing income-tax wedge, inside the same clamp | Flows into unemployment, then into the `jobs` issue, then into approval — with no new opinion plumbing, the same way [[economy-model]]'s own structural-unemployment term already does. |
| Long-run growth | `law_potential_target_pct` | `economy.gd:_update_potential_shift()`, added into `target` before the lag | Inherits the five-year time constant and the ±1.0 %/yr hard clamp that is [[economy-model|the model's whole stability argument]] — this is the only term that feeds back into trend, so a law cannot bypass the one guard rail that matters. |
| Off-budget revenue | `law_other_revenue_pct_gdp` | `budget.gd:recompute()`, added to `other_revenue_pct_gdp` | For levies with no slider — a carbon levy, a lobbying-registration fee — the same "authored residual" slot `other_revenue_pct_gdp` already fills for social contributions and local taxes. |
| Direct opinion | `law_bloc_offset{}` | `opinion.gd:_tick_nation()`, added to a bloc's approval **target**, clamped together with the satisfaction score before scaling | For laws with no budget footprint and so no matching issue — immigration rules, an anti-corruption agency. Added to the *target*, not to approval directly, so `INERTIA_RATE` and every bound in [[opinion-model|opinion's own stability argument]] still apply; a law cannot make approval jump in one month any more than a policy change can. |

**The rule that prevents double-counting:** a law with a genuine budget effect
expresses it as a lever, through `tax_rates_pct` or `spending_pct_gdp`. The
`bloc_offset` channel exists only for laws where there is no number the budget
produces — which is exactly why there is no issue for that law to be salient
about in the first place. A law is never authored with both a lever and a
`bloc_offset` entry for the same bloc's reaction to that lever; the sixteen
templates each pick one story and tell it once.

`opinion.gd`'s invariant that a bloc's target lives in `[10, 90]` is preserved
by construction: `score + law_offset` is clamped to `[−1, +1]` before being
scaled by `APPROVAL_SPAN`, the same bound a pure satisfaction score already
respects on its own.

## Template schema

`data/laws/{tax,labour,social,institutional}.json`, each `{"laws": [...]}` —
the same shape `data/parties/*.json` uses. See [[data-architecture]] for the
full field list and `src/core/law.gd` for validation.

Deliberately **not** in the schema: per-party amendment, sponsors,
multi-stage passage, upper-house readings, sunset clauses. All are [[v1|V1.1]]
territory, and the shape is extensible by adding keys — the same lesson
[[ROADMAP|S1]] leaves for the nation schema.

`preconditions` is a whitelisted field vocabulary
(`debt_to_gdp_pct`, `unemployment_pct`, `deficit_pct_gdp`,
`overall_approval_pct`, `growth_annual_pct`, `terms_served`), not an arbitrary
expression language. An unknown field is a startup error, not a silently-false
predicate — the same failure discipline `data_loader.gd` already applies to an
unpositioned `ideology_slot`.

## Constants vs content

`src/sim/legislature_constants.gd` holds every tunable — `LAW_SIGMA`,
`GOVERNMENT_BONUS`, `ABSTAIN_BAND`, the majority-threshold fractions, and every
effect channel's clamp. Model parameters, one set forever, next to
`economy_constants.gd`, `opinion_constants.gd` and `election_constants.gd` —
not in `data/`, per [[engine-decision|Rule 1]].

`FORECAST_UNCERTAIN_BAND` lives in `src/ui/law_panel.gd`, not here, for the
same reason `poll_noise.gd`'s `NOISE_MAX_PCT` lives in `src/ui/` and not in
`opinion_constants.gd`: it is not a model parameter, because the model does not
know a forecast exists.

## Why nothing diverges

| Quantity | Bound |
|---|---|
| `support(p, law)` | Clamped to `[−1, +1]` by construction. |
| Vote outcome | A deterministic comparison of two seat counts against `seats_total`; both are bounded by the assembly size. |
| `law_structural_offset_pct` | Hard-clamped, `[−5, +5]` points. |
| `law_potential_target_pct` | Hard-clamped to the same `±1.0 %/yr` [[economy-model|`potential_shift`]] already enforces — this cannot let a law compound trend growth beyond what the economy model already guards against. |
| `law_other_revenue_pct_gdp` | Hard-clamped, `[−10, +10]` points of GDP. |
| `law_bloc_offset[bloc]` | Hard-clamped to `[−1, +1]`, and clamped again in combination with the satisfaction score before it reaches `APPROVAL_SPAN`. |

Every channel is an accumulator a law writes once and a formula reads every
month afterward — never a term that grows on its own. The argument is not the
evidence: `tests/test_legislature.gd` applies every authored law at once and
runs 120 months, asserting every field stays finite and unemployment stays in
`[0, 100]`, the same shape `tests/test_economy.gd` uses for an absurd budget.

---

Related: [[index]] · [[election-model]] · [[electoral-systems]] ·
[[opinion-model]] · [[economy-model]] · [[data-architecture]] · [[ROADMAP]]
