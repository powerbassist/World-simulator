---
title: Election Model
tags:
  - decision
  - elections
  - simulation
---

# Election Model

The MVP election model, as built in S6 — the session where the loop
closes. Vote share, seat allocation and the win/lose condition. Real electoral
systems and the schedule that drives them are [[electoral-systems]]; this file is
the vote-share model and the constants that decide who wins.

Same standard as [[economy-model]] and [[opinion-model]]: a **game model**, judged
on whether the player's decisions produce a legible, attributable electoral
verdict — not on whether it would survive a political scientist.

## Where it sits

```
clock.month_elapsed
  → Economy.tick_month(state)      GDP, sectors, unemployment, population
  → Budget.tick_month(state)       revenue, spending, deficit, debt
  → Opinion.tick_month(state)      satisfaction, salience, approval
  → state.append_history()
  → Elections.tick_month(state, loader)   schedule check, vote share, seats
```

Elections run in the same monthly handler as everything else — `main.gd`'s
`_on_month_elapsed` — rather than on a signal of their own. Two reasons. First,
the clock ([[engine-decision]]) deliberately knows nothing but the calendar; a
term is not a calendar concept, and giving `clock.gd` one would break the
one-system-one-job rule for a feature only elections need. Second, the election
must read approval that has already settled *this* month, which is the same
ordering argument [[opinion-model]] makes for running opinion after the economy
and budget: putting the check inside the existing handler, after
`append_history`, gets that guarantee for free, and puts the ordering bug in one
obvious place if it is ever broken rather than in a race between two signal
listeners.

`Elections.tick_month()` returns an **Array** of results, empty on an ordinary
month. It is an array and not a single nullable result because a national
election and a European Parliament election can land in the same month — France
and Belgium's do, in June 2029, as they do in reality (see
[[electoral-systems]]). `main.gd` pauses the clock and shows the result panel on
any non-empty array; the simulation itself has no idea a panel exists.

Gated on `has_budget`, the same flag [[opinion-model|opinion]] and
[[economy-model|the budget]] use. The other nine nations carry a real, sourced
schedule (see [[electoral-systems]]) but never resolve an election — there is no
opinion model computed for them to resolve one *from*. Resolution follows the
second playable nation, the same trigger that moves voter blocs into `data/`.

## No new opinion field

The vote-share model reads `ns.bloc_approval` and `ns.overall_approval_pct`
exactly as [[opinion-model]] already computes them. What it needed and did not
have was a way to turn "workers are 8 points less happy than usual" into "some of
those workers now vote for a different party" — approval alone says how many
voters left, not where they went. That gap is closed by two axes, not a new state
field.

## Ideology space

Every party's `ideology_slot` and every opinion bloc gets a position on two
axes, `economic` (−1 left … +1 right) and `social` (−1 open … +1 traditional).
Both tables live in `src/sim/election_constants.gd`, alongside every other
constant in this model.

**Rejected first:** a direct bloc-to-slot affinity matrix — six blocs by twelve
ideology slots authored today, more as [[fictionalization|content grows]] — would
be 72 hand-tuned numbers nobody could individually defend, and S10's
balance pass would have to retune all of them together. The two-axis space is 36
numbers (12 slots + 6 blocs, two coordinates each), each one independently
arguable against the party's name or the bloc's stated priorities, and it is the
same vocabulary S7's per-ideology-slot law support will read — one
space, not two.

Bloc positions follow directly from what `opinion_constants.gd`'s
`BLOC_SALIENCE_BASE` already says each bloc cares about, not from a separate
survey: pensioners weight pensions and health — state spending, so left of
centre economically — and are the most socially traditional bloc; students are
left economically and the most socially liberal bloc; business is the only bloc
right of centre on both axes. Nothing here contradicts what [[opinion-model]]
already committed to; it is the same six characters read on a second axis.

## Vote share

```
affinity(b, p) = exp(−(dist(bloc_ideal_b, slot_position_p) / AFFINITY_SIGMA)²)

base_b,p  = seat_share_p × affinity(b, p)
pull_b    = clampf((approval_b − 50) / 50, −1, +1)
w_b,p     = base_b,p × (1 + INCUMBENT_SWING × pull_b)    if p is the incumbent
          = base_b,p                                     otherwise
w_b       = w_b / Σ_p w_b                                # per bloc, onto the simplex

vote_share_p = Σ_b turnout_b × size_b × w_b,p  /  Σ_b turnout_b × size_b
```

| Constant | Value | Why |
|---|---|---|
| `AFFINITY_SIGMA` | 0.8 | A bloc sitting on a slot scores affinity 1.0; a bloc a full axis-width away (distance 1.0) scores ≈0.32. Close enough to still compete for, far enough that a party cannot coast on prominence alone against a bloc it shares nothing with. |
| `INCUMBENT_SWING` | 0.9, not 1.0 | The incumbent's multiplier lands in `[0.1, 1.9]`. A universally hated incumbent shrinks hard but never divides by zero; a beloved one roughly doubles. Guard rail, not a modelling claim — the same reasoning as [[economy-model|the economy's clamps]]. |
| `BLOC_TURNOUT` | pensioners 0.82 … students 0.45 | Not from a dataset — the ordering matters more than the precision: pensioners vote most reliably, students least. Same "six defensible numbers, not a model" shape as `BLOC_SIZE`. |

Three properties are load-bearing:

- **`seat_share` as the prior**, not a flat starting point. At approval 50
  everywhere the election approximately reproduces the assembly the player
  inherited — a do-nothing term is not punished, matching
  [[opinion-model|the opinion model's own do-nothing row]]. `tests/test_elections.gd`
  checks this directly.
- **Renormalising per bloc** is the same simplex trick
  `opinion.gd`'s `salience_weights()` already uses. A bloc that turns against the
  incumbent does not vanish into the electorate; its vote is redistributed among
  the *other* parties in proportion to their existing base with that bloc, which
  already encodes ideological fit — a disaffected rural voter drifts toward the
  party rural voters were already nearest, not to a random one.
- **Monotonicity.** Raising a bloc's approval can never lower the incumbent's
  vote share; `tests/test_elections.gd` sweeps one bloc's approval from 10 to 90
  and checks every step.

## Win and lose

**Win = the incumbent party is the largest by seats** in the national election.
No coalition or confidence-vote model at MVP — that is [[v1|V1.1]]'s job — and
plurality-forms-government is the legible rule that needs none of it.

**Loss ends the run.** The result screen reads DEFEATED, the clock stays paused,
and there is no Continue button. This was a deliberate call, not a default: the
alternatives were "continue in opposition" (a second game mode with no budget
control, well past S6's scope) and "keep governing regardless of the result"
(which would make the election screen advisory and contradict the roadmap's own
"you can lose it"). Restart is a relaunch until S9 gives the game
save slots.

**A European Parliament election never ends a run.** It scores, allocates seats,
and attributes an outcome exactly like a national election, but
`ns.in_government` is untouched by it — see [[electoral-systems]] for why the EP
result exists at all and what it deliberately does not model.

Win → `Elections.tick_month()` increments `terms_served`, resets
`months_in_term` to zero, and sets `next_executive_year/_month` to exactly
`term_months` later — the nation's own term, not a hardcoded five, because
[[electoral-systems|the ten nations do not all serve the same term]].

> [!important] Which election is the win/lose condition changed in V1.1a
> This model was written when a nation had one election, so the national
> legislative vote decided both the assembly *and* whether the player kept
> office. Where the executive is elected separately — of the ten, only France —
> that is now false. **Only an executive election sets `ns.in_government`.** A
> legislative election rewrites `seats_by_party` and forces a new government to
> form, and cannot remove the player; the result may be cohabitation, which is
> neither a win nor a loss. Everything below about vote share, turnout weighting,
> attribution and the absence of election-day noise is unchanged and applies to
> both votes — `Elections.resolve_executive()` calls the same `vote_share()` and
> the same `attribution()`. Full argument in [[government-model]].
>
> **Since V1.2b**, the verdict itself is dispatched on
> `ns.lose_condition`, not on `has_executive` — the same code path, named
> rather than inferred. See [[political-systems]].

## Attribution

The result screen must say *why*, not just *what* — the roadmap's own done-when
condition. `Elections.attribution()` reuses `Opinion.top_issues()` and
`Opinion.issue_satisfaction()` rather than inventing a second ranking: the three
most salient issues at the moment of the vote, each reported with its
satisfaction sign. No new opinion machinery, because none was needed —
[[opinion-model|the opinion model]] already tracks exactly what a voter would
point to.

## No election-day noise

[[opinion-model|Polling noise]] exists because a *displayed* figure must not be
readable as the truth underneath it, and it lives in `src/ui/` precisely because
`src/sim/` contains no randomness at all — `tests/test_budget.gd`'s
projection-equals-reality guarantee depends on that. An election result *writes*
to state (`seats_by_party`, `in_government`, `last_election`), so a noise term
here would have to be a pure function of `(year, month, party_id)`, exactly the
`poll_noise.gd` pattern, applied inside the simulation layer for the first time.
That is not a contradiction waiting to happen so much as a cost with no
matching benefit: the player has already spent the whole term reading blurred
polls, so a result that turns out different from the last poll already happens
without any election-specific noise term. If a future session wants a genuine
swing on election day — a late-breaking scandal, a turnout shock — it is a
`year, month, party_id → offset` function added to `elections.gd` at that point,
not retrofitted into this one.

## Why nothing diverges

| Quantity | Bound |
|---|---|
| Vote share | Convex combination of per-bloc weights that are renormalised onto the simplex every time; sums to 1.0 by construction. |
| Seat counts | Every allocation method in [[electoral-systems]] sums to the assembly size by construction — checked directly in `tests/test_electoral_systems.gd`, not argued. |
| `incumbent_seats`, `terms_served` | Bounded by the assembly size and by how many terms the game has actually run. |
| `next_election_year/_month` | Advances by exactly the chamber's `term_years` at every legislative election, won or lost, because the assembly is re-elected either way. |
| `next_executive_year/_month` | Advances by exactly `term_months` per win; a loss stops advancing it at all, because the game is over. |

Elections read state and write a small, bounded set of fields once per term.
Nothing here feeds back into the economy, the budget, or opinion — the same
one-way argument [[opinion-model|opinion makes about itself]], one layer further
down the tick order.

## Balance signal, recorded per the S6 checkpoint

[[opinion-model]] flagged a soft spot for S10: every spending line
raised 3pp of GDP peaks approval at 66% within a year and only decays to 57 by
year five, on a budget that walks debt toward roughly 215% of GDP over a full
five-year term.

Run through S6's own vote-share model, over the 41-month term the player
actually inherits (January 2026 to France's June 2029 election — see
[[electoral-systems]] on why that term is short), that budget produces:

- Overall approval at the election: **59.5%**.
- Debt-to-GDP at the election: **171.9%** (a shorter run than the five-year one
  the soft-spot note measured, so a lower peak).
- Result: **comfortable re-election** — 250 of 577 seats, up from a starting 210,
  and the incumbent's own vote share rises from 28.0% to 29.4%.

So the signal holds: a budget the opinion model itself flags as fiscally
unsustainable wins, and wins more comfortably than the starting assembly. This is
recorded rather than fixed here, per the roadmap's instruction — no opinion or
election constant in this session was retuned to make it come out differently.

The result plate's tally (V3.6) is display-only: each seat bar tweens to a
final that `show_results()` already computed, skippable by any press, and no
model quantity is recomputed or gated on the animation. The attribution block
on the verdict carries one told line stating the agency bound the V3.0 probe
measured (approval prices change, not level); it says the bound, it does not
re-open it.

It is S10's first concrete balance question: whether unlimited
short-term deficit spending should cost votes *within* a single term, not only
across the one after it.

---

Related: [[index]] · [[electoral-systems]] · [[opinion-model]] · [[economy-model]]
· [[data-architecture]]
