---
title: Discipline Model
tags:
  - decision
  - government
  - simulation
---

# Discipline Model

Party discipline as a live quantity, and the seat-level rebellions it allows, as
built in [[v1|V1.1b]]. What erodes a party's grip on its own members, what that
costs the government, and why a majority on paper is no longer a majority in the
chamber.

Same standard as [[economy-model]], [[opinion-model]], [[election-model]],
[[legislature-model]] and [[government-model]]: a **game model**, judged on
whether the player's decisions produce a legible, attributable political outcome
— not on whether it would survive a comparative-politics seminar. Where realism
and legibility conflict, legibility wins, and the trade is noted.

## What changed, and why it had to

Before this block, `discipline` was a number in `data/parties/*.json` that never
moved and did exactly one job: scaling [[government-model|`coalition_bonus()`]].
A party voted as one bloc, always — `Legislature.resolve_vote()` gave every seat
a party held to `yes`, `no` or `abstain` off a single scalar, and
`Government.resolve_censure()` did the same.

[[v1]] defines this block as "how reliably members follow the leader's line,
**and what erodes it**". Two things follow, and the second is the load-bearing
one.

**Discipline has to be state.** A number that never moves cannot erode. It is now
`ns.party_discipline`, seeded from the authored figure and moved every month.

**A division has to be resolvable seat by seat.** Otherwise the only thing
erosion can do is flip a whole party at once, which is a cliff rather than a
slope, and the player gets no warning before it costs them a vote.

## The authored figure is a ceiling

`discipline` in `data/parties/*.json` stays **content**: it says how cohesive
that particular invented party is *at its best*. Everything in
`src/sim/discipline_constants.gd` is **model** — what the world does to that
number, which is the same for every party.

The target is therefore clamped to `[DISCIPLINE_MIN, base]`. Nothing in the model
can make a party more cohesive than its own file says it is; the model only takes
away. That is what keeps a balance pass from quietly overriding authored content,
and it is the same split [[government-model|`excluded_partners`]] already makes.

```
target(p) = base(p)
          − APPROVAL_TERM · unpopularity
          − ELECTION_TERM · clamp(1 − months_to_legislative / ELECTION_HORIZON, 0, 1)
          → clamped to [DISCIPLINE_MIN, base(p)]

d ← d + (target − d) · DISCIPLINE_INERTIA
```

`unpopularity` is `(APPROVAL_NEUTRAL − approval) / APPROVAL_SPAN`, clamped to
`[0, 1]` — the government's standing expressed in the units [[opinion-model]]
already reasons in rather than in raw percentage points. It is **exactly zero for
any government at or above neutral approval**, which is why nothing in the V1.1a
balance moves.

Two terms and no new equation. Members of an unpopular government start voting
for their own re-election rather than for the whip; members close to a vote look
to their own seats. The election clock is the **legislative** one, not the
executive's — it is the members' seats on that ballot, and in France those two
dates are years apart ([[government-model|two clocks]]).

Recovery is the inertia pull back toward target and nothing else. No accumulator,
so [[government-model|"nothing here accumulates"]] survives intact.

## Rebellion is a seat-level split of scalars that already existed

One formula, used by both kinds of division:

```
strain(p)         = |line(p) − own(p)| / REBEL_STRAIN_SCALE
rebel_fraction(p) = clamp(REBEL_MAX · (1 − discipline(p)) · strain(p), 0, REBEL_MAX)
rebel_seats(p)    = round(seats[p] · rebel_fraction(p))
```

`line` is what the party votes; `own` is what its members left alone would vote.
Rebels are bucketed against the same `ABSTAIN_BAND` [[legislature-model]] uses
for the line, so they land in their own column rather than being assumed to be a
mirror of it.

| Division | `line` | `own` | So the strain is |
|---|---|---|---|
| Bill | `Legislature.support()` | `Legislature.spatial_support()` | `coalition_bonus()` — the whip's pull |
| Censure | `Government.hostility()` | `hostility(whipped = false)` | the discipline term itself |

`spatial_support()` is the pre-existing purely spatial term, split out of
`support()` so the gap is computed once rather than in two files that could
drift. `support()` is unchanged: it is still that term plus the coalition bonus,
clamped.

### Opposition parties never rebel

This is the model speaking, not a hole in it. An opposition party's support **is**
its spatial support — `coalition_bonus()` is zero for it by construction — so
nothing is dragging its members away from where they already stand, and there is
no strain to compute. A party that sits in government and votes a line it does
not hold is the only place this model has a whip at all.

Real opposition backbenchers do cross the floor. Modelling that would need a term
for why a party's stated position differs from its members' — a tribal or
leadership term the game does not have — and inventing one here would be exactly
the "numbers nobody could individually defend" [[legislature-model]] rejected for
laws and [[election-model]] rejected for blocs. `tests/test_discipline.gd`
asserts the property directly, so it is a claim rather than an accident.

### Why the censure strain reads the way it does

On a censure motion the gap between `line` and `own` is `d · (1 + DISAFFECTION ·
unpopularity)`, so the rebel fraction goes as `(1 − d) · d`, peaking at `d = 0.5`.
That is the right shape: a perfectly disciplined party has no rebels, and a party
at zero discipline has no line to rebel *against* — its stated position already
is its members'. The interesting behaviour is in the middle, which is where a
governing party under strain actually sits.

## Disaffection, and the measurement that forced it

`hostility()` gains one term at V1.1b, and it is the only term in that function
that can turn a partner against a government it *agrees with*:

```
h(p) = (1 − 2·cohesion(p))
     − d                                        p ∈ C
     + DISAFFECTION · unpopularity · (1 − d)    p ∈ C
     + FORCE_HOSTILITY_BONUS                    after a forced bill
     → clamped to [−1, +1]
```

This was not in the plan for the session. It went in because the plan's balance
goal turned out to be unreachable without it, and the measurement is worth
recording because it is a general fact about the formation model rather than a
one-off.

**The measurement.** `Government.form()` builds a coalition by adding the party
*closest* to the agreed position, so a coalition is by construction made of
parties that like it. On the authored French roster the three governing parties
sit **0.26, 0.32 and 0.36** from the line, giving a raw hostility near **−0.8**
apiece. Subtracting discipline only pushes that further down. So eroding
discipline to the floor moved the censure tally not one seat — 259 of 289 at
every discipline from 0.85 to 0.10 — and the opposition, holding exactly
`577 − 318 = 259`, could never reach 289 no matter how badly the player governed.
**Discipline had no route into the censure arithmetic at all.**

**The reading.** Cohesion and disaffection are two different questions. Cohesion
asks whether a party likes this government's *policy*. Disaffection asks whether
its members want to be standing next to it at the next election. Only the second
explains why coalitions collapse under unpopular leaders, and the model had no
term for it. Gating it on `(1 − d)` is what keeps it a *discipline* term rather
than a second parallel channel: a disciplined party stays loyal whatever the
polls say, and it is erosion — not unpopularity on its own — that costs the
player their coalition.

`whipped = false` drops the discipline subtraction and runs disaffection at full
strength, which is the same party with no leadership on its shoulder.

## What a division costs

Both applied by the mutating caller, so `resolve_vote()` and `resolve_censure()`
stay pure functions of state — the law screen's forecast calls them freely.

| Event | Where | What |
|---|---|---|
| Members broke ranks | `Legislature.propose()`, from the result | `REBELLION_PENALTY` scaled by the rebellion's size against `REBEL_MAX`. A whip that failed fails more easily next time. |
| Article 49.3 | `Legislature._force()` | `FORCE_DISCIPLINE_PENALTY` on every coalition party. |

Article 49.3 now charges two prices: `FORCE_BLOC_PENALTY` with the public, which
[[government-model]] already argued for, and this one in the chamber. Going over
your own majority's head makes that majority less willing the next time you ask.

## Constants

| Constant | Value | Why |
|---|---|---|
| `DISCIPLINE_MIN` | 0.10 | Not zero: a party whose members ignore it entirely is not a party, and every formula reading discipline would then read as if it were not in government at all. |
| `APPROVAL_TERM` | 0.50 | What an utterly unpopular government costs its coalition. Reaches full strength only at the floor of [[opinion-model]]'s own range; zero at or above neutral. |
| `ELECTION_TERM` | 0.20 | Smaller than the above, because it is about timing rather than standing — a popular government still holds its majority into an election. |
| `ELECTION_HORIZON_MONTHS` | 12 | Ramped linearly rather than switched on, so no month exists where the assembly's behaviour changes discontinuously. |
| `DISCIPLINE_INERTIA` | 0.08 | Half-life ~8 months, against [[opinion-model|`INERTIA_RATE`]]'s 0.25. A poll turns in a news cycle; a parliamentary party's cohesion does not. This is also what stops one bad month from costing the player their majority — discipline follows the trend in approval, not its noise. |
| `DISAFFECTION` | 1.0 | Set so a party at the discipline floor under a government at the bottom of the approval range crosses from "against" to "for" on a censure motion following a forced bill, and does not cross before that. |
| `REBEL_MAX` | 0.35 | A party losing more than a third of its seats on a division has split rather than rebelled, and splits are not modelled. |
| `REBEL_STRAIN_SCALE` | 0.45 | Equal to [[government-model|`COALITION_BONUS_MAX`]], the largest pull the whip can exert on a bill, so a party dragged as far as the model allows rebels at `REBEL_MAX · (1 − d)` and no further. |
| `REBELLION_PENALTY` | −0.05 | A step down, not an accumulator: inertia pulls it back toward target. |
| `FORCE_DISCIPLINE_PENALTY` | −0.07 | Larger, because bypassing the chamber is the more direct insult to it. |

`discipline` and `excluded_partners` remain content in `data/parties/*.json`.

## What the balance does with all this

Fourteen simulated years per regime, `tools/balance_probe.gd`, which now reports
mean coalition discipline and what a censure motion following a forced bill would
collect. The censure branch only ever fires after Article 49.3
([[government-model|opposition-initiated censure]] is not modelled), so this is
the number that matters.

| Regime | Discipline | 49.3 censure vs 289 | Rebels | Outcome |
|---|---|---|---|---|
| `hands_off` | 0.78–0.84 | 259 | 0 | holds, every year |
| `managed` | 0.80–0.84 | 192–193 | 0 | holds, every year |
| `tinkering` | 0.73–0.82 | 204–209 | 0 | holds, every year |
| `spendthrift` | 0.76 | 259 | 0 | holds |
| `tax_zero` | 0.73 | 282 | 36 | holds, by seven seats |
| `tax_max` | 0.73 | 282 | 68 | holds, by seven seats |
| `austerity` | 0.68 | **343** | 84 | **carries** |

> [!tip] The censure branch is now live, and it is graded
> [[government-model]] recorded that censure worked and never fired in a played
> game. It fires now. A government that governs competently is untouched — the
> three surviving regimes show zero rebels across all fourteen years. A
> government that wrecks the public finances loses its own benches within a year
> and cannot use Article 49.3 without falling. The two tax extremes sit seven
> seats from the line, which is the shape wanted: reachable, and not by accident.

The remaining honest caveat is not about this model. **No regime that survives
its presidential election ever becomes unpopular enough to reach these states.**
`austerity`, `tax_max` and `tax_zero` all lose in May 2027 — the censure branch
is live for the sixteen months before that vote and not after it. Making
sustained low-approval survival possible is an [[election-model]] question
(`INCUMBENT_SWING`), the same lever [[government-model]] already names for
cohabitation, and it is left as found.

## Why nothing diverges

| Quantity | Bound |
|---|---|
| `party_discipline[p]` | `[DISCIPLINE_MIN, base(p)]`, clamped in the tick and again in every event step. Asserted every month of a 168-month run. |
| `target(p)` | Same interval, by the same clamp. Cannot exceed authored content at any approval or any point in the term. |
| `rebel_fraction(p)` | `[0, REBEL_MAX]`: a product of `(1 − d) ∈ [0, 1]`, a clamped strain, and the ceiling. |
| `rebel_seats(p)` | `[0, seats[p]]` by `clampi`. Seats are conserved — a split moves seats between columns and never creates one. Asserted across every law at four discipline levels. |
| `hostility(p)` | Still clamped to `[−1, +1]`; the disaffection term is bounded by `DISAFFECTION · 1 · 1`. |
| `coalition_bonus(p)` | Still `[0, COALITION_BONUS_MAX]` — discipline is live now but its range is a subset of `[0, 1]`. |

Nothing accumulates. The one stored quantity is discipline itself, and every
event effect is a step inside bounds that inertia then pulls back — the failure
mode [[opinion-model|`SALIENCE_GAIN`]] documents cannot arise here.

The argument is not the evidence. `tests/test_discipline.gd` checks seeding for
all ten nations against their rosters, that the authored figure is a ceiling at
every approval and every point in the term, that an unpopular government loses
its grip and gets it back, that an approaching election costs discipline, that
discipline stays in bounds over a 168-month run, that a perfectly disciplined
party never rebels, that seats are conserved and rebels never exceed a party, that
the opposition never rebels at any discipline, that two resolutions of one state
are identical, that a bill carried by the party lines can be rejected by the
division, that forcing a bill costs discipline, that seat-level rebels are not
party-level defectors, that an unpopular government can be censured after a 49.3
where a popular one on the same assembly cannot, and that the table survives a
save. `tests/test_government_panel.gd` and `tests/test_law_panel.gd` cover the
two screens that have to make a rebellion visible before it costs a vote.

## Where it sits

```
clock.month_elapsed
  → Economy.tick_month(state)
  → Budget.tick_month(state)
  → Opinion.tick_month(state)
  → state.append_history()
  → Discipline.tick_month(state, loader)   reads the approval just settled
  → Legislature.tick_month(state)          cooldowns
  → Elections.tick_month(state, loader)
```

After `Opinion`, because the target reads the approval it has just settled;
before anything that reads a coalition bonus or resolves a division. Gated on
`has_budget`, the same flag every other opinion-reading system uses — the other
nine nations have no approval figure for the target to read, and
`Discipline.of()` falls back to the authored number for them.

## What is deliberately not built

**No whip or concession command.** Rebellion's counterplay is the lever set that
already exists: which bills you propose, who is in the coalition, and whether you
force. A costed command to suppress a rebellion lands when there is a model that
needs one — the same reasoning [[government-model]] uses for the
`constructive_absolute` successor requirement.

**No party splits.** `REBEL_MAX` is a third of a party's seats precisely because
past that point what has happened is a split, and a new party appearing mid-term
is a roster change [[v1|V1.2]] would own.

**No per-member state.** Rebels are a fraction of a party's seats, not named
backbenchers with their own positions. That is the same reduction
[[opinion-model]] makes for voters and for the same reason.

---

Related: [[index]] · [[government-model]] · [[legislature-model]] ·
[[opinion-model]] · [[election-model]] · [[v1]] · [[ROADMAP]]
