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
[[ROADMAP|S1]] leaves for the nation schema. **Upper-house readings left that list at
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

---

Related: [[index]] · [[election-model]] · [[electoral-systems]] ·
[[government-model]] · [[discipline-model]] · [[opinion-model]] ·
[[economy-model]] · [[amendment-model]] · [[data-architecture]] · [[ROADMAP]]
