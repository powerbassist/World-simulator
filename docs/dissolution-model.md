---
title: Dissolution Model
tags:
  - decision
  - government
  - elections
  - simulation
---

# Dissolution Model

Dissolution and snap elections, as built in [[v1|V1.1c]]. Who may end the
current assembly early, what it costs, and how the resulting election is
indistinguishable from a scheduled one except for a flag on its result.

Same standard as [[government-model]] and [[discipline-model]]: a **game
model**, judged on whether the player's decisions produce a legible,
attributable political outcome — not on whether it would survive a
comparative-politics seminar. Where realism and legibility conflict,
legibility wins, and the trade is noted.

## What changed, and why it had to

[[out-of-scope-mvp]] cut dissolution from the MVP partly because "an escape
hatch from the fixed-term clock undermines the one pressure the MVP has". What
that escape costs was this session's actual design decision, not the
snap-election plumbing, and two things had to be settled before writing any
code.

**The dissolution rule was not in the schema.** `government.legislative.election`
carried `system`, `next` and `threshold_pct` and nothing about who may
dissolve, how long a lockout runs, or whether it is possible at all —
Switzerland cannot, Germany only through a lost confidence vote, France has a
one-year lockout. Adding `government.legislative.dissolution` is a ten-nation
schema decision of the same class [[electoral-systems]] made for the election
schedule itself, and [[v1|V1.2]] political systems will read it the same way.

**The gamble did not obviously resolve.** Before any schema was written,
`tools/dissolution_probe.gd` swept a snap legislative election's result across
the approval range a player can hold while still in office — 27 to 50, since
only the May 2027 executive vote can end a run below that. The result:

| Approval | Incumbent seats | Coalition seats |
|---|---|---|
| 27 | 97 | 327 |
| 30 | 112 | 334 |
| 35 | 137 | 346 |
| 40 | 162 | 359 |
| 44 | 182 | 369 |
| 47 | 197 | 377 |
| 50 | 211 | 384 |

Starting assembly: 318. **Spread between the worst and best approval a player
can reach while still holding office: 57 seats** — well past the 40-seat
threshold this session's plan pre-committed to before running the probe.
**Section 4 (extending `INCUMBENT_SWING` to the governing coalition) was
correctly skipped**: the gamble already resolves through the existing election
model, because `two_round`'s power-law amplification does the work — a modest
approval swing at the vote-share level becomes a large swing at the seat
level, the same mechanism that gives the model its authored 318-seat starting
majority from a much flatter party-vote distribution.

That the gamble resolves does not mean it resolves *symmetrically*. Even at
the worst approval a sitting player can still reach (27), a snap returns 327 —
nine seats above the starting assembly. A dissolution called by a struggling
government barely helps; one called by a strong government helps a great
deal. `tools/balance_probe.gd`'s two dissolution regimes measure exactly that
asymmetry under played budgets, not a swept approval figure — see below.

## Effort row: corrected before building

ROADMAP's V1.1c row read **Light / Sonnet 5 / Medium**, flagged in advance as
known wrong. Counting the surfaces this session actually touched: a ten-nation
researched schema plus `nation.gd` validation, six new `NationState` fields
across `duplicate_state`/`to_dict`/`from_dict` plus a `SAVE_VERSION` bump, a
new `src/sim/` module and its constants file, the snap path in `elections.gd`,
two panels, tick wiring in two files, one new test file plus four edited, two
new balance-probe regimes, and eight documentation edits. **Corrected to Plan
first Yes, Opus 5 to plan / Sonnet 5 to build, High → Medium** — the same
shape as V1.1d, for the same reason: a schema several later blocks read.

## The rule is a method, not a branch

[[engine-decision|Rule 1]] still applies: no `if nation_id == "FRA"` anywhere.
`government.legislative.dissolution` in each `data/nations/*.json` names a
**method**, dispatched in `src/sim/dissolution.gd` — the same pattern
`formation.method` and `election.system` already set.

| Rule | Used by | What it models |
|---|---|---|
| `executive_discretion` | FRA, ESP, GBR, NLD, LUX | The head of state or government may dissolve at will (subject to any lockout). |
| `head_of_state_limited` | ITA | Dissolution exists, but is barred near the end of the head of state's own term (the *semestre bianco*) in the real constitution — not modelled here, see below. |
| `confidence_failure` | DEU, BEL | Only reachable after a lost confidence vote. **Refuses the player's command outright** — no confidence-vote command exists at V1.1c, and half-modelling one here would be worse than not building it. |
| `self_dissolution` | AUT | The chamber dissolves itself by simple law; the executive cannot. Refuses the player's command for the same reason `confidence_failure` does — it is not an executive act. |
| `none` | CHE | The Nationalrat cannot be dissolved under any circumstance. Fails safe everywhere, the same shape `censure_rule: "none"` already uses. |

`dissolution_lockout_months` and `dissolution_notice_months` are content
alongside the rule, in the same block. Every nation's rule and both figures
carry a `_note` naming a source, checked at build time per
[[electoral-systems]]'s standard — see each `data/nations/*.json`'s
`government.legislative.dissolution._note`.

**Only `executive_discretion` and `head_of_state_limited` accept the player's
command.** `Dissolution.EXECUTIVE_RULES` names them; everything else refuses
through `can_dissolve()` before the lockout or blackout is even checked.

## What the command does

`src/sim/dissolution.gd` — narrow surface, no engine access, no randomness, a
pure function of state the same way every other module in `src/sim/` is:

- `can_dissolve(state, ns)` — the rule permits an executive command, no
  dissolution is already pending, the lockout has expired, and the scheduled
  election is not inside the blackout window.
- `refusal_reason(state, ns)` — the one place the rule is turned into words,
  so `government_panel.gd` does not re-derive it.
- `dissolve(state, ns)` — the player command, the
  `Budget.commit()`/`Legislature.propose()` shape. Moves
  `next_election_year/month` to now + `notice_months` and applies the cost.
  **The executive's own clock is untouched** — a French President who
  dissolves keeps their office and their May 2027 date, which falls straight
  out of [[government-model|the two clocks]] with no special case here.
- `tick_month(state)` — counts the lockout down. Its own module rather than
  folded into `Legislature.tick_month()` next to `force_cooldown_months` —
  [[engine-decision|Rule 3]], one system one job. Runs after `Legislature` and
  before `Elections`, in `main.gd`, `tools/balance_probe.gd` and
  `tests/test_balance.gd`'s harness alike.

`src/sim/elections.gd`'s `_tick_nation()` consumes `dissolution_pending` the
month the moved election actually fires: it stamps `"snap": true` on the
result and sets `dissolution_lockout_remaining` from
`dissolution_lockout_months` **at the resulting election, not at the
command** — France's rule is one year from the new Assembly, not from the
decree. Everything else about resolving a snap election is the ordinary
legislative path: `Elections.resolve()`, `Government.form()`, and
`censure_barred_party_ids` clearing exactly as a scheduled election already
does. A snap election is a scheduled election with an earlier date and a flag
on its result, not a second code path.

### What it costs

| Cost | Mechanism |
|---|---|
| Public patience | `Government.penalise_blocs(ns, DISSOLUTION_BLOC_PENALTY)` on every call — the same accumulator Article 49.3 and a fallen government already move, so inertia and every [[opinion-model]] bound still apply. |
| The lockout | `dissolution_lockout_months`, set at the resulting election. |
| The blackout | No dissolution within `DISSOLUTION_BLACKOUT_MONTHS` of an already-scheduled legislative election — without it, dissolving one month early is a free reroll of a vote already coming, paying the bloc penalty for no gamble at all. |

## Constants

`src/sim/dissolution_constants.gd`, next to the other five `*_constants.gd`
files and not in `data/`, per [[engine-decision|Rule 1]].

| Constant | Value | Why |
|---|---|---|
| `DISSOLUTION_BLOC_PENALTY` | −0.08 | Equal to `government_constants.FORCE_BLOC_PENALTY` — both are an executive going over the ordinary process's head. Section 1's 57-seat spread found the structural upside large enough that this number does not need to carry the whole downside on its own: the gamble is real because a bad dissolution barely helps, not because this penalty is punishing. |
| `DISSOLUTION_BLACKOUT_MONTHS` | 6 | Half a year — long enough that "dissolve one month early" is never a free reroll of a vote already scheduled. |

`dissolution_rule`, `dissolution_lockout_months` and `dissolution_notice_months`
stay content in `data/nations/*.json`, because they describe one nation's real
constitutional rule rather than the model.

## Emergent, measured rather than assumed

Announcing a dissolution moves `next_election_year/month`, and
`Discipline.months_to_legislative()` reads that date — so calling one ramps
the election-proximity term toward full immediately, and the player's own
benches get measurably (if only slightly) more skittish during the one-month
notice period France's rule gives. At `notice_months = 1`,
`ELECTION_TERM = 0.20` and `DISCIPLINE_INERTIA = 0.08` this is worth roughly
0.016 of discipline in the announcement month — real, and too small on its own
to change a division. Not claimed as a designed consequence: it is what
[[discipline-model|the existing formula]] does when handed a date that moved,
and it was worth writing down rather than rediscovering.

## What the balance does with all this

`tools/balance_probe.gd` gained two regimes, each dissolving once, well clear
of the blackout, under a budget already established in the base regime set:

| Regime | Before | Dissolved at | After the snap | Outcome |
|---|---|---|---|---|
| `managed_dissolves_early` | 318/577 | month 8 | 377/577 | Holds comfortably through all three terms in the 168-month run; the term resets to the ordinary five-year cadence, and later legislative elections land at 378/577, 377/577. |
| `austerity_dissolves_late` | 318/577 | month 10 | 325/577 | Barely moves — the discipline erosion `austerity` already carries by month 10 means the snap adds only seven seats. Still loses the May 2027 presidential vote and is censured under Article 49.3 with 88 rebel seats. |

This is the section 1 measurement played out under governed conditions rather
than swept approval: a government worth re-electing gains almost the whole
structural upside from dissolving, and a government already failing gains
almost none of it. Dissolving does not rescue a bad term; it amplifies a good
one.

## Why nothing diverges

| Quantity | Bound |
|---|---|
| `dissolution_lockout_remaining` | Set once, from `dissolution_lockout_months`, at the resulting election; counted down to zero and never below by `tick_month()`'s own guard. |
| `dissolutions_called` | Monotonically increasing, never reset — the same shape `governments_fallen` already uses. |
| Coalition seats after a snap | Bounded by `assembly_seats`, through the same `ElectoralSystems.allocate()` and `Government.form()` every scheduled election already uses. Nothing here computes a seat count of its own. |
| `overall_approval_pct` | Untouched directly by `dissolve()` — the bloc penalty moves the *target* opinion.gd ticks toward, through `law_bloc_offset`, so [[opinion-model|`INERTIA_RATE`]] and every existing bound still apply. `tests/test_dissolution.gd` asserts this directly: approval does not move in the commit month. |

The one stored quantity with a nontrivial lifecycle is
`dissolution_lockout_remaining`, and it moves only by `tick_month()`'s
decrement and by `elections.gd`'s one-time seed — the same shape
`force_cooldown_months` already has, and no new failure mode.

The argument is not the evidence. `tests/test_dissolution.gd` checks every
nation resolves to a recognised rule, that Switzerland can never dissolve,
that `confidence_failure` and `self_dissolution` refuse the player's command,
that a dissolution moves only the legislative clock and leaves the executive's
term untouched, that the lockout blocks, counts down and expires, that the
blackout refuses a dissolution too close to a scheduled vote, that a snap
election resolves and forms a government and clears the censure bar and reads
`snap = true` where a scheduled election reads `snap = false`, that seats are
conserved and two resolutions of the same state agree, that a second dissolve
call while one is pending is refused, and that the new state survives a save.
`tests/test_government_panel.gd` covers the button's three readings — absent,
disabled with a reason, enabled. `tests/test_balance.gd` runs a managed budget
that also dissolves through the full clamp-and-invariant check the rest of
that file applies.

## Where it sits

```
clock.month_elapsed
  → Economy.tick_month(state)
  → Budget.tick_month(state)
  → Opinion.tick_month(state)
  → state.append_history()
  → Discipline.tick_month(state, loader)
  → Legislature.tick_month(state)          cooldowns
  → Dissolution.tick_month(state)          lockout countdown
  → Elections.tick_month(state, loader)    consumes dissolution_pending
```

`Dissolution` has no tick beyond the lockout countdown. Calling one is a
command at a boundary, not a per-month update — the same shape
`Government.form()`, `Budget.commit()` and `Legislature.propose()` already
have.

## What is deliberately not built

**A confidence-vote command.** `confidence_failure` refuses rather than
half-implements — the same call [[government-model]] makes for
`constructive_absolute`'s successor requirement. Code with no caller is worse
than an honest refusal, and it is Germany's and Belgium's actual mechanism, not
a placeholder for one this session ran out of time to build.

**Italy's *semestre bianco* blackout.** The real rule bars dissolution during
the last six months of the **head of state's own** seven-year term. No nation
but France tracks a separate executive term in this schema (`has_executive`),
so there is no clock to measure Italy's head of state against without
inventing one for a nation whose own executive is never resolved. Modelling it
would be new state for a caveat only ITA's authored roster could ever exercise
— the same "code with no caller" reasoning as the confidence-vote gap.
`head_of_state_limited` is present in the schema and dispatched identically to
`executive_discretion` today; the blackout itself is recorded here as future
work rather than silently dropped.

**Dissolution for the nine non-resolving nations.** Only the player's
dissolution is ever called — the same split [[electoral-systems]] makes for
the election schedule itself: there is no opinion model computed for the
other nine to gamble with.

**A seat forecast on the panel.** The government screen names the rule, the
lockout, the blackout, and the cost, in words — no projected assembly. The
player already has the Society tab's noisy polls, and that is the gamble, the
same reason `law_panel.gd` blurs its own forecast and `poll_noise.gd` exists
at all. An exact projection would remove the gamble; a blurred one would need
a new display-layer constant to justify a decision this session's
measurement already settled without one.

**Re-seeding the starting assembly through each nation's own electoral
system.** The obvious fix for the structural step section 1 describes — one
line in `Elections.init_nation()` — and it was checked and rejected: under
`two_round` the authored French roster gives the top two parties roughly 355
seats between them, which destroys
[[government-model|the no-two-parties-reach-289 property]] that makes every
French majority government a three-party coalition.
`tests/test_government.gd` asserts that property directly. Fixing it needs the
roster re-authored, which is [[ROADMAP|S2]] content work, not this session's.

---

Related: [[index]] · [[government-model]] · [[discipline-model]] ·
[[election-model]] · [[electoral-systems]] · [[v1]] · [[ROADMAP]]
