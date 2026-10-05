---
title: Transition Model
tags:
  - decision
  - government
  - simulation
---

# Transition Model

Built at V1.2d. [docs/tiers/v1.md](tiers/v1.md) §2's last item:
system transition (monarchy ↔ republic), the same amendment mechanism
[[amendment-model]] built, pointed at `system_id` itself.

## Zero playable nations, and the scope correction that fixed it

As scoped in §2, this block would have shipped to nobody. Only FRA and DEU are
`playable: true`, and both **prohibit** a change to the form of the state
outright, not at a higher bar — France Art. 89 §5 ("the republican form of
government shall not be the object of an amendment"), Germany Art. 79(3), the
eternity clause. Italy (Art. 139) is the same, on a nation this game does not
yet let a player govern either. The nations a monarchy↔republic transition is
actually *about* — GBR, ESP, BEL, NLD, LUX — were all unplayable, and DEU's
`two_thirds` was already measured unreachable
([[amendment-model]], 0.519 ceiling). [[amendment-model|V1.2c]] shipped one
nation unauthored-against; shipping this block as scoped would have shipped
the *entire mechanic* that way.

**The scope was corrected before any code was written:** this block is
transition **and** a third playable nation, decided with the user at plan
time rather than discovered mid-build. GBR was picked over the alternatives
for a structural reason, not a narrative one — its `ordinary_law` amendment
bar is an ordinary absolute majority, so reachability is settled *by
construction*: no live sweep can come back "unshippable" the way Germany's
did. GBR's data was already complete from V1.2a (fiscal block,
per-party `leader_name`, FPTP with `threshold_pct: 0`, no executive block,
head of state authored), so [docs/tiers/v1.md](tiers/v1.md) §2's "a third
nation onward is a one-flag data edit" held up on inspection — no split into
two blocks.

## The gate: a seventh per-nation dispatch field

`government.amendment.permits_system_change`, a bool, alongside
`amendment.rule` — the seventh instance of the dispatch-on-a-data-string
pattern `formation_method` / `censure_rule` / `dissolution_rule` /
`lose_condition` / `head_of_state_kind` / `amendment_rule` already use
([[amendment-model|amendment_rule was the sixth]]).

| Value | Nations | Basis |
|---|---|---|
| `false` | FRA, DEU, ITA | Art. 89 §5; Art. 79(3) eternity clause; Art. 139 |
| `false` | AUT | The 1919 Habsburg Law and republican practice — a thinner citation than the other three, flagged as such rather than asserted with equal confidence |
| `true` | GBR, ESP, BEL, NLD, LUX | No entrenchment of the form of state |
| `false` | CHE | Moot — `referendum_required`, and no transition content names `directorial_republic` |

Per-**nation**, not per-template: DEU, ITA and AUT share `parliamentary_republic`
with a transitioned GBR, and the prohibition on changing the form of state
belongs to each nation's own constitution, not to the template's shape.
Immutable this block — no amendment in this game can un-entrench itself
(named deferral, not a silent gap).

Checked in `Legislature.available()`: `law.changes_system and not
ns.permits_system_change` refuses a transition law, on top of the ordinary
`systems` filter every constitutional law already gets.

## Threshold: the same `amendment_rule`, no new bar

For the playable roster the question dissolves before it needs answering:
FRA and DEU are prohibited outright, and GBR has no stricter path because it
has no codified constitution to put one in. A separate `transition_rule`
would have been a tuned constant wearing a citation — the move
[[amendment-model|V1.2c]] already refused for Luxembourg.

The one real stricter-path case in the ten-nation roster is Spain — Art.
168's total-revision path (2/3 + dissolution + referendum) against Art.
167's ordinary 3/5 — recorded as a **named deferral**: the trigger is the
first playable nation whose constitution has a distinct total-revision bar.

## Channel: a seventh key, and the check inverts

`effects.institutional.system_id`. Not a new law shape — `constitutional`,
`systems` and `effects.institutional` are unchanged as concepts. Two things
had to change inside them:

### 1. Completeness

If `system_id` is written, the amendment must **also** write
`formation_method`, `censure_rule`, `dissolution_rule`, `amendment_rule`,
`term_limit` and `head_of_state`. GBR is the live proof of why:
`largest_party` and `ordinary_law` are **both** illegal under
`parliamentary_republic`, so a bare `system_id` write would land the nation
in exactly the half-understood institutional state
[[political-systems|V1.2b's cross-check]] refuses for a nation file. Checked
in `Law._extract_institutional()` at load time, purely intra-law — it needs
no data from `data_loader.gd` to decide.

### 2. Target-side validation

[[amendment-model|V1.2c's]] `_validate_amendments()` checks written fields
against every system in `law.systems` — the systems the law is proposed
**under**. A `system_id` write inverts that: the written state has to be
legal under the **target**, not the systems it started from. `systems` still
gates proposability; only the direction the cross-check runs changed.
`DataLoader._validate_institutional_against_system()` is the same per-system
check both paths now call — extracted, not duplicated, when the second
caller appeared.

## Head of state: office authored, holder kind-dependent

`effects.institutional.head_of_state: {kind, title, term_years?, name?}`,
validated by `Law._extract_head_of_state()`:

- `elected_president` → `term_years` **required**, `name` **forbidden**. The
  holder is derived at `Legislature.apply()` time from `Government
.largest_party_id()`'s own leader — the same "largest party" formation
  already computes, not a second implementation. The clock is set to the
  transition month plus `term_years`.
- `hereditary_monarch` → `term_years` **forbidden**.

A name is forbidden for **both**, and that is [[people-model|U6b]]'s
correction. It used to be *required* for a monarch, on the reasoning that an
elected president is someone already on the board (a party leader) while a
restored monarch is not. The reasoning was right and the conclusion was
wrong: the law applies to any `parliamentary_republic`, so one authored king
meant **every republic in Europe restored the same man**. A law names an
OFFICE; the acting nation's own `government.pretender_person` names the
person, and a monarchy points that slot at its own sitting monarch so a
republic-then-restoration returns the right house. Load-time checkable,
the same present-only-if-required, complete-if-present rule `Nation.gd`
already applies to its own head-of-state block.

**New template field, `allowed_head_of_state_kinds`.** Before this block, a
template said nothing about the head of state at all — a
`parliamentary_republic` with a `hereditary_monarch` was authorable and
nothing would catch it. Adding the field (one value per template today, 1:1
with the existing roster) makes a transition's head-of-state write checkable
target-side rather than trusted, and makes every nation's own starting
head-of-state kind checked against its declared system for the first time —
the same constraint-not-defaults discipline every other `allowed_*` field
already gives [[political-systems]].

## `lose_condition`: re-read, and the roadmap's own framing corrected

`Legislature.apply()` re-reads `lose_condition` off the **target** template,
mirroring how `game_state.gd`'s `_build_nation()` reads it at new-game — a
transition has to update it for the same reason a fresh load does, since it
lives on the template, not the nation.

**But** `constitutional_monarchy` and `parliamentary_republic` both declare
`lose_condition: "party_not_largest"`, so for the only transition pair this
block ships, **it does not change**. ROADMAP.md's stated
reason for keeping transition separate from amendment — "changes
`lose_condition` and the head of state at the same time, not one field" — is
true in principle and false in this block's own content. The real reason
transition earned a separate session is completeness and target-side
validation (above), not a `lose_condition` change that, in practice, never
fires. Corrected here rather than left standing.

## Content: two amendments

| Law | `systems` | Target | Bundle |
|---|---|---|---|
| `abolish_the_monarchy` | `constitutional_monarchy` | `parliamentary_republic` | `investiture` / `simple_present` / `confidence_failure` / `two_thirds` / `term_limit: 0` / `elected_president` "President", 5-year term |
| `restore_the_monarchy` | `parliamentary_republic` | `constitutional_monarchy` | `largest_party` / `simple_present` / `executive_discretion` / `ordinary_law` / `term_limit: 0` / `hereditary_monarch`, holder from the nation's own `pretender_person` |

`investiture` and `confidence_failure` are chosen for `abolish_the_monarchy`
because GBR's own `largest_party`/`executive_discretion` are illegal under
the target — **no template loosened to fit content**, the same discipline
every prior block in this model has kept. `two_thirds` is
`parliamentary_republic`'s *only* allowed amendment rule, so the new republic
entrenches its own amendment procedure **by data, not by authoring** — that
is where restoration's reachability question comes from, and it is emergent
rather than designed in.

`restore_the_monarchy`'s `systems: [parliamentary_republic]` would otherwise
make it proposable by DEU, ITA and AUT, who also use that template;
`permits_system_change: false` is what actually stops it, not the systems
filter — worth stating plainly, since the two mechanisms look similar and
only one of them is doing the work for those three nations.

## The measurement that kept the plan honest: restoration's reachability

Same discipline [[amendment-model|V1.2c's Germany sweep]] used, run before
`restore_the_monarchy` was authored, not after: replicate
`Legislature.spatial_support()` and `Government.coalition_bonus()` against a
transitioned GBR's live `seats_by_party`, sweeping a hypothetical bill's
ideology position over a grid **and** every 1–3-party coalition combination
(`Government.position_of()`'s real seat-weighted centroid, not a guess), to
find the term-start *ceiling* — not one run's number.

| Nation (post-transition) | Measured max yes-seat fraction, term start | Needed |
|---|---|---|
| GBR | 0.680, at the `national_unity_party` + `progress_alliance` coalition, neutral bill position | 0.667 (`two_thirds`) — **passes, with a 1.3pp margin** |

The first pass of this sweep — evaluating only GBR's *actually formed*
government (the coalition `Government.init_nation()` real formation rules
produce) — found a ceiling of exactly that coalition's own seat share, 0.560,
below the bar. That number is a real property of the model (opposition
parties carry no `coalition_bonus()`, so only a coalition holding roughly
two-thirds of seats outright can ever clear a two-thirds bar), but it
answers a narrower question than "is restoration reachable" — it answers "is
restoration reachable *by the one government the formation algorithm actually
produced*." Widening the sweep to every 1–3-party combination, matching
[[amendment-model|the Germany sweep's own method]] rather than a narrower
reading of it, found the true ceiling at 0.680: a `national_unity_party` +
`progress_alliance` coalition (62% of seats) plus other parties' own spatial
support at a neutral bill position clears it. Recorded here rather than
silently discarded, because the same undercount would just as easily have
gone the other way and made a reachable transition look unshippable.

**GBR's own margin is tighter than France's** ([[amendment-model|6pp for
`three_fifths`]] against 1.3pp here) — real, not tuned toward a target: GBR's
roster is six parties against France's smaller assembly-effective set, and no
constant moved to produce this number.

`restore_the_monarchy` is shipped, at the real `two_thirds` bar
`parliamentary_republic` forces, on the strength of this measurement — the
plan's own escalation trigger (widen the sweep or escalate to Opus if the
first pass came back unreachable) fired and resolved without needing to
change scope.

## Reachability in a played run, the same distinction V1.2c drew

The ceiling above answers "can any coalition at any position clear this bar."
`tools/balance_probe.gd`'s `TRANSITION_REGIMES` answers a narrower question —
does *this* bill, at *its* authored position, against the coalition the
player *actually has* — and, as with
[[amendment-model|France's `abolish_term_limits`]], the answer for
`abolish_the_monarchy` is **no** in the `managed` regime: 117/650 yes (18%),
against `ordinary_law`'s >50% bar, at the bill's authored position
(`economic: 0.0, social: -0.6`). Not a contradiction of the reachability
finding above — the sweep asks whether the mechanic is shippable at all, the
probe asks whether one specific, ideologically-committed bill passes against
one specific coalition, and a real constitutional vote failing sometimes is
the correct behaviour of a majority-gated mechanic, the precedent
[[amendment-model]] already set. 168 months, invariants clean, no crash, no
non-finite value, no clamp stuck.

## Save format

`SAVE_VERSION` 7 → 8 for `permits_system_change`. Refused outright, no
migration, the project's standing rule.

Unlike every prior `SAVE_VERSION` bump in this model,
`system_id`/`lose_condition`/the head-of-state fields become **mutable at
runtime** for the first time this block — they were always serialized, but a
version-7 save format never had to round-trip a value any of them held
*after* new-game. `tests/test_save_load.gd`'s `_run_transition_roundtrip()`
applies a transition before round-tripping, rather than only at new-game, to
catch a serializer that only ever saw the starting value.

## Files

- `data/laws/amendments.json` — `abolish_the_monarchy`, `restore_the_monarchy`
- `data/nations/*.json` (10) — `government.amendment.permits_system_change`
- `data/nations/GBR.json` — `playable: true`
- `data/political-systems/*.json` (4) — `allowed_head_of_state_kinds`
- `src/core/nation.gd` — `permits_system_change` parsing
- `src/core/political_system.gd` — `allowed_head_of_state_kinds`
- `src/core/law.gd` — `system_id`/`head_of_state` in `_extract_institutional()`,
  the completeness rule, `changes_system`
- `src/core/data_loader.gd` — `_validate_amendments()`'s target-side branch,
  `_validate_institutional_against_system()`, the head-of-state-kind check in
  `_validate_political_system()`
- `src/core/nation_state.gd`, `src/core/game_state.gd` — `permits_system_change`,
  `SAVE_VERSION` 7 → 8
- `src/sim/government.gd` — copies `permits_system_change`;
  `largest_party_id()`, the public entry point onto formation's own
  "largest party" for `_apply_head_of_state()` to reuse
- `src/sim/legislature.gd` — `available()`'s gate, `apply()`'s `loader`
  parameter (now required, not defaulted — a defaulted param would let a
  transition silently half-apply), the institutional arm's `system_id` and
  re-read `lose_condition`, `_apply_head_of_state()`
- `src/ui/law_panel.gd` — the target system named structurally in a
  transition's detail, off the loaded template's own `display_name`
- `tools/balance_probe.gd` — `TRANSITION_REGIMES`, pinned to GBR
- `tests/test_transition.gd` — new; `tests/test_political_systems.gd`,
  `tests/test_data.gd`, `tests/test_save_load.gd`, `tests/test_balance.gd`,
  `tests/fixtures/nation_bad_formation_method.json` — edits
- `tests/fixtures/laws_bad_transition/` — the completeness and target-side
  cross-check fixtures

Related: [[political-systems]] · [[amendment-model]] · [[government-model]] ·
[[legislature-model]] · [[data-architecture]] · [docs/tiers/v1.md](tiers/v1.md) ·
[[decision-log]]
