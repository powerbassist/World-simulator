---
title: Cabinet Model
tags:
  - decision
  - government
  - simulation
---

# Cabinet Model

Cabinet and ministers, as built in [[v1|V1.1d]]. Five portfolios, held by
coalition parties, each modifying how far a point of GDP on its spending line
actually goes — and each capable of being resigned by a party the player has
under-served.

Same standard as [[government-model]], [[discipline-model]] and
[[dissolution-model]]: a **game model**, judged on whether the player's
decisions produce a legible, attributable political outcome — not on whether
it would survive a comparative-politics seminar. Where realism and legibility
conflict, legibility wins, and the trade is noted.

## What changed, and why it had to

V1.1a made a government a set of parties with an agreed position. V1.1b made
party discipline live. V1.1c gave the player dissolution. None of them gave
the player a decision *inside* their own government: the coalition forms
itself and there was nothing to do with it until it fell.

V1.1d adds that decision. A portfolio is held by a coalition party, and how
well that party governs it depends on two things the player controls only
indirectly (who is in the coalition) and one thing they control directly
(who holds what).

## Effort row: corrected before building, by cutting scope rather than raising effort

ROADMAP's V1.1d row read **Plan first Yes / Opus to plan, Sonnet to build /
High → Medium**, on the stated reasoning "ministers are a schema that
departments, opinion and events all read — S1 class." Counted cold at plan
time against the roadmap's own one-line description ("appointments with
competence and loyalty, modifying their department's output"), the surface
count came to roughly fourteen — V1.1c's own thirteen, plus two things V1.1c
did not have: a new content class (named individuals, exposed to
`check_names.sh`) and a whole dashboard tab rather than a button on an
existing panel.

Three scope decisions, taken with the user before planning, cut that back to
eleven and let the row's **Sonnet 5 / Medium** build hold:

| Fork | Taken | What it removed |
|---|---|---|
| Minister unit | Portfolio → **party**, not named individuals | The whole content roster and the `check_names.sh` exposure — one authored field per party instead. |
| Loyalty's channel | **Resignation** | A second equation inside `hostility()`, the term V1.1b measured most carefully. |
| UI | **Government panel now, Cabinet tab as U5** | A new tab, its rail registration and its own panel test. |

The fourth correction on the roadmap's effort table, and the first that
resolved by cutting scope rather than raising the model/effort tier — see
[[decision-log]].

## Portfolios are the five spending lines

`health, education, defence, pensions, infrastructure` —
`economy_constants.SPENDING_KEYS`, declared again in
`src/sim/cabinet_constants.gd` as `PORTFOLIO_KEYS` rather than re-exported, so
`cabinet.gd` names its own vocabulary the way every other `*_constants.gd`
file does. Not in `data/`: a fixed set forever, the same argument
`opinion_constants.BLOC_KEYS` makes for its six blocs.

A sixth "finance" portfolio was considered and rejected at plan time: it has
no distinct channel of its own, so it would be a name on a screen with
nothing behind it.

## A portfolio's position is derived, not authored — zero new coordinates

Every portfolio needs a point in the two-axis ideology space
`election_constants.SLOT_POSITION` already puts every party on. That point is
**computed**:

```
position(f) = Σ_b BLOC_SIZE[b] · BLOC_SALIENCE_BASE[b][f] · BLOC_IDEAL[b]
              ────────────────────────────────────────────────────────────
                     Σ_b BLOC_SIZE[b] · BLOC_SALIENCE_BASE[b][f]
```

the size-and-salience-weighted mean of the ideal points of the blocs that
actually weight that spending line. All three tables already exist, in
`opinion_constants.gd` and `election_constants.gd`. This is the same move
`BLOC_IDEAL` itself documents making once, for blocs: *"Reused, not invented:
the sign and rough magnitude follow directly from what `BLOC_SALIENCE_BASE`
already says each bloc cares about."* This is the third time the project has
taken this exact move to avoid an authored matrix — `government-model.md`
rejected one for coalition preferences, `election-model.md` for bloc-to-slot
— and it gets the same answer here: a 6×5×10 competence table would have been
300 numbers nobody could individually defend, retuned as a group at every
balance pass.

A salience retune moves the portfolios with it automatically, rather than
silently desynchronising them. `tests/test_cabinet.gd` asserts all five stay
inside the `[-1, 1]` square and stay mutually distinct, so a retune that
collapses two portfolios onto the same point fails loudly rather than
producing an assignment that quietly stops mattering.

## Competence is one new authored field; affinity is derived

`competence`, in `[0, 1]`, in `data/parties/*.json` next to `discipline` —
same class, same file, same reason: it describes a particular invented party
rather than the model.

```
affinity(p, f)   = exp(−(|SLOT_POSITION[p] − position(f)| / CABINET_SIGMA)²)
competence(p, f) = party.competence · affinity(p, f)
```

`CABINET_SIGMA` reuses `election_constants.AFFINITY_SIGMA`'s value (0.8)
rather than inventing a fourth sigma: both measure the same kind of falloff
— how far a fixed point in the ideology space can drift before the actor at
the other end stops caring.

Authored per party, currently by ideology slot (mainstream governing
slots — `christian_democrat`, `liberal`, `social_democratic`, `centre_right`
— at 0.75; `green` and `progressive_liberal` at 0.60–0.65; `nationalist_right`
and `regionalist*` at 0.55; `left_populist` at 0.50), reflecting which
invented parties plausibly have the civil-service depth to govern well. A
per-party hand-tune independent of slot is future work; the slot-based
starting point is honest about being a first pass and does not block the
model itself.

## Effectiveness multiplies the delta, not the level

```
effectiveness(f) = 1 + COMPETENCE_SPAN · (competence(holder, f) − COMPETENCE_NEUTRAL)
```

Read in `opinion.gd:issue_satisfaction()` on the line that already computes a
spending line's satisfaction:

```gdscript
sat[key] = _scaled(d_spend * Cabinet.effectiveness(ns, key), K.SPEND_SCALE_PP)
```

One multiplied term on an existing expression, the same "one added term, no
new equation" shape `law_bloc_offset` and `potential_shift_pct` already have.
Multiplying the **delta** rather than the level is deliberate: a player who
never touches a spending line is untouched by the whole cabinet system, the
same surgical property `opinion-model.md` argues for its own
`public_finances` retune.

`ns.cabinet_effectiveness` is a cache, computed at `seat()`/`assign()`/a
resignation and read directly by `opinion.gd` — the same pattern
`coalition_position` already uses so `legislature.gd` never needs a
party_list to read a government's agreed line. `opinion.gd` has no reason to
know a `Party` object exists, and now it still doesn't.

The economy channel — `infrastructure` and `education` already feed
`potential_shift_pct`, and a competent minister plausibly should move it too
— is **deliberately not built** this block. One channel is enough to answer
whether the mechanism matters; a second channel is easy to add once it does.

## Loyalty is derived, plus one new term: shortfall

```
loyalty(p) = clamp( Discipline.of(ns, p) · Government.cohesion(ns, p)
                    − SHORTFALL_PENALTY · shortfall(p),  0, 1 )
```

`Discipline.of()` already existed. `Government.cohesion()` is newly
**extracted** from `coalition_bonus()`'s previously-inline Gaussian — used
identically by `coalition_bonus()`, `hostility()` and now `Cabinet.loyalty()`,
so the same falloff curve backs three different questions (how much a
party's vote is worth, how much it wants the government gone, how loyal a
minister is) rather than three copies of it.

`shortfall` is the one genuinely new quantity, and it is the load-bearing
part of the design:

```
shortfall(p) = max(0, entitlement[p] − held[p]) / max(1, entitlement[p])   ∈ [0, 1]
```

`entitlement` is allocated by `ElectoralSystems.pr_dhondt()` over coalition
seats, given the five portfolios as "seats" to distribute — the seat
allocator that already exists, not a second one.

**Design intent:** a party held at its entitlement barely ever loses a
minister; a party stripped of its portfolios to over-serve a more competent
partner does. Resignation is a consequence of the player's own assignment,
not of general unpopularity — attributable, the standard every model note in
this vault is judged against. The section 1(b) measurement below confirms
this is not merely intended but actually true of the wired model: an
identically-shorted assignment fires resignations under an unpopular
government and never fires them under a popular one.

## Resignation

`Cabinet.tick_month()`, deterministic, no `rand()` anywhere:

```
Discipline.unpopularity(ns) · (1 − loyalty(ns, holder)) > RESIGNATION_THRESHOLD
    → portfolio vacated, Government.penalise_blocs(ns, RESIGNATION_BLOC_PENALTY)
```

Every check in one tick reads the state from *before* that tick's vacancies,
so a resignation earlier in `PORTFOLIO_KEYS` order cannot change another
portfolio's shortfall reading within the same month — the same determinism
guarantee every `tick_month()` in `src/sim/` keeps.

The penalty routes through `law_bloc_offset`, the accumulator Article 49.3, a
fallen government, and a dissolution already move, so `INERTIA_RATE` and
every bound in [[opinion-model]] still apply. Smaller than
`government_constants.FALLEN_BLOC_PENALTY`: a resigned minister is a
coalition partner voicing displeasure from inside the government, not the
government itself falling — the mechanical difference between this and a
censure.

## The player command

`Cabinet.assign(state, portfolio, party_id, party_list)` — the
`Budget.commit()` / `Legislature.propose()` shape. Coalition parties only,
refused through `can_assign()` / `refusal_reason()`, the pair
`dissolution.gd` established so the panel does not re-derive the rule. Costs
`RESHUFFLE_BLOC_PENALTY` on every call, win or lose — the same "cost on use"
shape Article 49.3 has, so a President who reshuffles constantly reads as
unstable regardless of whether the new assignment is better.

## Why `Cabinet.seat()` is not called from inside `government.gd`

The original plan had `Government.form()` call `Cabinet.seat()` directly.
Writing `cabinet.gd` surfaced the problem: `Cabinet` needs
`Government.cohesion()` and `Government.penalise_blocs()`, so `Government`
calling into `Cabinet` would make a `preload()` cycle out of two files that
each need the other — GDScript does not support this.

The fix moved `seat()` to the **orchestrator** — every external call site of
`Government.form()`/`fall()` (`game_state.gd`'s `_build_nation()`,
`elections.gd`'s two formation points, `legislature.gd`'s censure-fall
point) calls `Cabinet.seat(ns, party_list)` immediately after. `Cabinet`
depends on `Government`; `Government` never depends on `Cabinet`. This also
reads truer to [[engine-decision|Rule 3]] than the original plan did:
composing two systems' effects is the orchestrator's job, not one system
reaching into another.

## Seating

`entitlement()` by d'Hondt over coalition seats. Then, in entitlement-then-id
order, each party takes its highest-**affinity** remaining portfolio one at a
time (affinity, not competence — assignment follows ideological fit; skill
scales the outcome once seated). Ties on affinity break on portfolio key.
Deterministic and idempotent: two `seat()` calls on unchanged state produce an
identical cabinet, the same guarantee `Government.form()` already carries.

## Section 1: measured before the schema was written

`tools/cabinet_probe.gd`, modelled on `tools/dissolution_probe.gd`. Two
pre-commitments, fixed before the probe ran so the numbers could falsify
them.

### (a) Does competence matter?

Pre-commitment: **≥ 2.0 approval points**, best vs worst legal assignment
under a governing budget, at end of a 168-month term, or the channel is
decorative and the model changes before code is written.

**First run failed, and taught something the plan had not anticipated.** The
pre-committed test budget was `balance_probe.gd`'s `managed` regime — and
`managed` moves only `defence` away from the nation's own starting values;
health, education, pensions and infrastructure sit exactly at their starting
values.
Effectiveness multiplies a spending line's *delta from start*, so on four of
five lines it was multiplying zero. `managed` is S10-tuned to be
near-frictionless governance, which makes it exactly the wrong budget to
probe a channel that only ever acts on a change — the spread even ran
**negative** (best effectiveness scored *lower* than worst, because the one
line that did move was a cut, and a bigger multiplier on a cut is worse, not
better).

Corrected to a `GOVERNING` budget — moderate deltas on all five lines,
representative of a player who actually touches spending, none of it at a
`balance_probe.gd` extreme. At `COMPETENCE_SPAN = 0.6` (the first guess) the
spread was 1.77 points — under the line. At `COMPETENCE_SPAN = 0.75` it was
**2.21 points** — over it. `COMPETENCE_SPAN = 0.75` is the measured value in
`cabinet_constants.gd`, not the first guess.

`COMPETENCE_NEUTRAL = 0.5` is the value at which effectiveness is exactly
1.0, so an unauthored or freshly-vacated middle ground reads as neutral by
construction. `VACANT_EFFECTIVENESS = 0.5` sits below the worst a *held*
portfolio can score (0.625 at this span) — a vacancy is not merely a bad
minister, it is nobody steering the department.

### (b) Is resignation reachable?

This is the V1.1b trap restated: discipline erosion shipped, and the censure
branch turned out to be unreachable without a term nobody had planned
(`DISAFFECTION`). Pre-commitment: a shorted coalition partner must cross the
resignation signal at least once across 168 months under at least one
regime, and an entitled partner under `managed` must never cross it.

A back-of-envelope check of the formula already ruled out a threshold
anywhere near 0.45: at approval 30 with an entitled, disciplined partner the
signal is only ~0.20. Measured rather than guessed: at
`SHORTFALL_PENALTY = 0.5`, `RESIGNATION_THRESHOLD = 0.20`, the entitled
reading under `managed` peaked at **0.021** (safe, well clear of 0.20) and
the shorted reading crossed in every regime tried — **0.057** under
`managed`, **0.577** under `austerity`. Both hold.

### Confirmed again, under the full pipeline

`tools/balance_probe.gd` gained two regimes exercising the real wiring end to
end, not the probe's isolated formula — the same second-pass structure
`dissolution-model.md` used to confirm its own section 1 finding under
played budgets:

| Regime | What it does | Resignations over 168 months |
|---|---|---|
| `managed_cabinet_shorted` | Strips the largest partner's biggest-affinity portfolio, hands it to the weakest-fit remaining coalition partner (shortfall 0.33), under `managed` | **0** |
| `austerity_cabinet_shorted` | The identical reassignment, under `austerity` | **5**, the first at month 10 |

This is the cleanest evidence the design intent is real rather than merely
argued: the *identical* shortfall produces zero resignations under a
government worth re-electing and five under one that already fails on its
own terms. Shortfall alone is not enough; it has to combine with
unpopularity the player has already earned some other way. A minister does
not resign because the player made one bad call — only because the player
made a bad call *and* is already losing.

## Constants

`src/sim/cabinet_constants.gd`, next to the other six `*_constants.gd`
files and not in `data/`, per [[engine-decision|Rule 1]].

| Constant | Value | Why |
|---|---|---|
| `CABINET_SIGMA` | 0.8 | Reuses `election_constants.AFFINITY_SIGMA`'s scale rather than a fourth sigma — the same kind of ideological falloff. |
| `COMPETENCE_SPAN` | 0.75 | Measured: 0.6 gave a 1.77-point spread, under the 2.0 pre-commitment; 0.75 gave 2.21. |
| `COMPETENCE_NEUTRAL` | 0.5 | Half the `[0, 1]` competence range — an unauthored middle ground is neutral by construction. |
| `VACANT_EFFECTIVENESS` | 0.5 | Below 0.625, the worst a *held* portfolio can score at this span — a vacancy is worse than a bad minister. |
| `SHORTFALL_PENALTY` | 0.5 | Measured alongside `RESIGNATION_THRESHOLD` as one finding, not two independent guesses. |
| `RESIGNATION_THRESHOLD` | 0.20 | Entitled-under-`managed` peaked at 0.021; shorted crossed at 0.057–0.577 across regimes tried. |
| `RESIGNATION_BLOC_PENALTY` | −0.06 | Smaller than `FALLEN_BLOC_PENALTY` (−0.12): a resignation is a partner's displeasure from inside government, not the government falling. |
| `RESHUFFLE_BLOC_PENALTY` | −0.04 | Cost on use, the same shape `FORCE_BLOC_PENALTY` gives Article 49.3. |

`competence` stays content, in `data/parties/*.json`, for the same reason
`discipline` does: it describes a particular invented party, not the model.

## Why nothing diverges

| Quantity | Bound |
|---|---|
| `portfolio_position(f)` | A weighted mean of points inside the `[-1, 1]` square, so inside it by construction. Asserted directly by `tests/test_cabinet.gd`. |
| `affinity(p, f)` | `(0, 1]`, a Gaussian of a non-negative argument. |
| `effectiveness(f)` | `[1 - SPAN·NEUTRAL, 1 + SPAN·(1-NEUTRAL)]` = `[0.625, 1.375]` for a held portfolio; `VACANT_EFFECTIVENESS` (0.5) sits below that floor by construction. Asserted every month of a 168-month run by `tests/test_balance.gd`. |
| `shortfall(p)` | `[0, 1]`: a ratio of a clamped-non-negative numerator to a positive denominator. |
| `loyalty(p)` | `[0, 1]` by an explicit `clampf`. |
| `cabinet_entitlement` | Sums to exactly `PORTFOLIO_KEYS.size()` — `ElectoralSystems.pr_dhondt()` already guarantees its output sums to the seat count requested. |
| A held portfolio | Always a coalition party or `""` — `seat()` only ever assigns from `ns.coalition_party_ids`, and `assign()` refuses anything else through `can_assign()`. Asserted every month of a 168-month run. |
| `resignations_count`, `reshuffles_called` | Monotonically increasing, never reset — the same shape `dissolutions_called` and `governments_fallen` already use. |
| A resignation's cost | Routed through `law_bloc_offset`, clamped by the same `BLOC_OFFSET_MIN/MAX` a law's own offset is, before reaching `APPROVAL_SPAN` — see [[legislature-model]]. Cannot walk approval down without bound. |

No quantity here accumulates outside those bounds. A cabinet is computed
fresh from `ns.coalition_party_ids` whenever the coalition changes, so there
is no accumulator to drift — the same argument `government-model.md` makes
for coalition formation.

The argument is not the evidence. `tests/test_cabinet.gd` checks the derived
positions are distinct and bounded, affinity falls off with distance, a
cabinet exists from new-game for all ten nations, `seat()` is idempotent, no
portfolio is ever held outside the coalition, entitlement sums correctly,
`assign()` refuses a non-coalition party and an unknown portfolio, a
successful assignment charges the reshuffle penalty without moving approval
in the commit month, shortfall reads zero when entitled and positive when
stripped, a resignation vacates exactly one portfolio, and cabinet state
survives a save. `tests/test_government_panel.gd` covers the entitled,
shorted and vacant readings of the screen. `tests/test_balance.gd` asserts
every cabinet bound above across the full 168-month run under every existing
regime.

## Where it sits

```
clock.month_elapsed
  → Economy.tick_month(state)
  → Budget.tick_month(state)
  → Opinion.tick_month(state)        reads Cabinet.effectiveness() per line
  → state.append_history()
  → Discipline.tick_month(state, loader)
  → Legislature.tick_month(state)    cooldowns; may call Government.fall() → Cabinet.seat()
  → Dissolution.tick_month(state)    lockout countdown
  → Cabinet.tick_month(state, loader)   resignations; reads unpopularity Opinion just settled
  → Elections.tick_month(state, loader) may call Government.form() → Cabinet.seat()
```

`Cabinet` has no tick beyond the monthly resignation check. Seating a cabinet
is not a per-month event — it happens when the coalition changes, at the same
three boundaries `Government.form()` already fires at (a legislative
election, a re-elected executive, a carried censure), called by the
orchestrator immediately after each one rather than from inside
`government.gd` itself. `assign()` is a command at a boundary, the same
shape `Budget.commit()`, `Legislature.propose()` and `Dissolution.dissolve()`
already have.

## What is deliberately not built

**The economy channel.** `infrastructure` and `education` already feed
`potential_shift_pct`; a competent minister plausibly should move it too.
One channel this block was enough to answer whether the mechanism matters at
all — a second channel is easy to add once it does, and is not code with no
caller, just code this session did not need to write to answer its own
question.

**Named individual ministers.** A portfolio is held by a party, not a named
person. Lands with [[v1|V1.2]], the same session that gives a second nation
a budget and an opinion model — the same "code with no caller" reasoning
`government-model.md` gives for `constructive_absolute`'s successor
requirement, and the same content-cost argument that kept this session's
scope to eleven surfaces instead of fourteen.

**A Cabinet dashboard tab.** The player reads and reassigns the cabinet from
the existing Government panel. A dedicated tab is **U5** — and this session
is ROADMAP's own trigger for building one: "until a system session ends by
needing a surface the shell does not have."

**Cabinets for the nine non-resolving nations.** The same split
[[electoral-systems]] already makes for the election schedule itself: there
is no opinion model computed for the other nine, so there is nothing for a
minister to be competent or incompetent *at*. `Cabinet.init_nation()` and
`seat()` still run for all ten, the same "field exists, tick does nothing"
shape `has_budget` already uses, so a second playable nation is a data
change, not a change here.

---

Related: [[index]] · [[government-model]] · [[discipline-model]] ·
[[dissolution-model]] · [[opinion-model]] · [[election-model]] ·
[[data-architecture]] · [[v1]] · [[ROADMAP]]
