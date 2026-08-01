---
title: Amendment Model
tags:
  - decision
  - government
  - simulation
---

# Amendment Model

Built at [[ROADMAP|V1.2c]]. [docs/tiers/v1.md](tiers/v1.md) §2's next item after
[[political-systems]]: constitutional amendment, the mechanism for changing the
institutions a template constrains. System transition (monarchy ↔ republic) is
built at [[ROADMAP|V1.2d]], as the same mechanism pointed at `system_id`
itself — see [[transition-model]] for why it earned a separate session (not,
in the end, the `lose_condition` reason first assumed).

## What changed, and why it had to

Until this block, every institutional field a nation carries —
`formation_method`, `censure_rule`, `dissolution_rule`, `term_limit`,
`term_months` — is fixed for the whole run: copied onto `NationState` at
new-game by `Government.init_nation()`, read by a dozen systems, and never
written again. The player can move every economic and opinion number in the
game and cannot move the rules they play under. That asymmetry is what
[[political-systems]]'s templates exist to constrain — a template that
constrains values nothing can ever change is constraining a constant.

## Amendments are laws, not a second pipeline

An amendment is `src/core/law.gd`'s existing shape plus three additions:

- **`constitutional: true`** — routes `resolve_vote()`'s threshold to the
  proposing nation's own `ns.amendment_rule` instead of a fixed fraction.
  Implemented as one more `MAJORITY_KEYS` entry, `"amendment"`, so there is
  still exactly one threshold-dispatch path, not two.
- **`systems: [...]`** — which political-system templates this amendment may
  be proposed under. Filters `Legislature.available()`, the same shape
  `preconditions` already filters on.
- **`effects.institutional: {...}`** — a seventh effect channel, and the only
  one that writes an **absolute value**, not a delta. Every other channel
  (`tax_rates_pct`, `bloc_offset`, …) accumulates; an institution is *set*.

Everything else — preconditions, cooldowns, `once`, seat-level vote
resolution, the rebellion split, the forecast in `law_panel.gd` — is reused
unchanged. `docs/legislature-model.md`'s vote-resolution argument therefore
still holds for an amendment; only the threshold and the effect target
differ.

## The threshold is per-nation data, not a global constant

`government.amendment.rule`, a per-nation string, constrained by the
template's `allowed_amendment_rules` — the sixth instance of the
dispatch-on-a-data-string pattern `formation_method` / `censure_rule` /
`dissolution_rule` / `lose_condition` / `head_of_state_kind` already use. Not
`law.majority` reused flat: a fixed fraction would mean every nation amends on
the identical bar, which is the thing templates exist to avoid.

| Rule | Fraction | Nations | Real basis |
|---|---|---|---|
| `ordinary_law` | 0.5 (absolute) | GBR | No codified constitution — Parliament amends by ordinary Act. |
| `three_fifths` | 0.60 | FRA, ESP | Art. 89 Congress vote (FRA); Art. 167's ordinary revision path (ESP) — corrected from a plan-time assumption of `two_thirds`, see below. |
| `two_thirds` | 2/3 | DEU, ITA, AUT, BEL, NLD | Art. 79(2) GG (DEU); Art. 138's referendum-proof second-vote bar (ITA); Art. 44 (AUT); the entrenching number in BEL/NLD's two-reading procedures, whose intervening dissolution-and-election step is not modelled. |
| `three_quarters` | 0.75 | LUX | The referendum-waiving second-vote bar, Art. 114 — kept at its real fraction rather than rounded down to an existing tier. |
| `referendum_required` | *(none)* | CHE | Declared, unresolved — see below. |

**A plan-time table error, caught by writing the real citation rather than
copying a rough cohort.** The plan grouped Spain with Germany/Italy/Austria at
`two_thirds`. Spain's *ordinary* amendment procedure (Constitution Art. 167)
is 3/5 of each chamber; only Art. 168's rare total-revision path — the
fundamental-rights title, requiring 2/3, a dissolution, and a referendum — is
stricter, and no amendment content in this game invokes it. Corrected to
`three_fifths` before any content was authored against the wrong number.

**Luxembourg's real bypass bar is 3/4, not rounded to 2/3.** The plan's first
draft of the per-nation table considered folding Luxembourg into the existing
`two_thirds` tier rather than adding a fifth rule for one nation. That would
have been a tuning fudge under a different name — this project's own rule is
that thresholds are real constitutional numbers, not detuned to fit an
existing tier — so `three_quarters` was added instead.

`referendum_required` (CHE) is declared and unresolved, the same shape
`lose_condition: "never"` already uses for Switzerland: every Swiss amendment
requires a mandatory popular referendum with a double majority of the people
and the cantons, so no seat fraction applies at all. No amendment in
`data/laws/amendments.json` names `directorial_republic` in its `systems`, so
this is never looked up at runtime — reaching the `"amendment"` match arm
with a rule absent from `AMENDMENT_RULE_FRACTIONS` is a content bug, not a
reachable game state, and `resolve_vote()` `push_error()`s if it ever happens.

## The measurement that changed the plan: Germany's real threshold is unreachable

The plan named this as the one thing to verify before authoring content, not
assume: replicate `spatial_support()` and `coalition_bonus()` against each
nation's **live** `seats_by_party`, `cohesion` and `discipline`, sweeping a
hypothetical amendment's position over the whole ideology grid and every
1–3-party coalition, and find the *best possible* achievable yes-seat
fraction — not a played run's actual number, its ceiling.

| Nation | Measured max yes-seat fraction, term start | Needed |
|---|---|---|
| FRA | 0.660 | 0.600 (`three_fifths`) — **passes, with room to spare (~6pp)** |
| DEU | 0.519 | 0.667 (`two_thirds`) — **fails, even at the best possible moment in a term** |

This is stronger than the plan's rough estimate, which used only authored
`seat_share` and a full-strength coalition bonus and found France marginal
(0.660 against a 0.667 needed, i.e. under `two_thirds`) and Germany
"probably unreachable" only once discipline erodes. The **live** measurement,
run against the real starting coalition, cohesion and discipline, found
Germany's ceiling below 2/3 **at term start**, before any erosion — the real
Bundesrat co-requirement is not modelled at all, and this game's authored
six-party roster cannot clear the Bundestag half alone even under the most
favourable coalition and bill placement available. An `austerity` run was
also swept for the erosion figure; both France and Germany fell from
government before month 60 under it, so no erosion number exists — moot,
since the term-start ceiling already answers the question for Germany.

**The response, decided with the user rather than tuned around:** Germany
keeps its real `two_thirds`. No amendment content in this session names
`parliamentary_republic` in its `systems` list — the mechanic is not shipped
against a nation that can never pass it, the same honesty
`referendum_required` already gives Switzerland. This is a **measured
divergence**, not a bug, in the same family as [[declined|the France/Germany
bloc-weight finding]] and [[political-systems|V1.2b's term-limit harness
collision]]: institutions this game already authors per-nation (six-party
fragmentation, no upper house) produce a real, different ceiling, without
touching a single tuned constant.

**Named trigger to revisit:** an upper-house model (V1.1e, re-parked, not
cancelled) or a grand-coalition-shaped start scenario (V1.2, also scheduled)
could raise Germany's ceiling. Until one of those lands, Germany's
`two_thirds` is real and correctly unauthored-against, not a placeholder.

## Content: four amendments, none targeting Germany

`data/laws/amendments.json`:

| Law | Systems | Effect |
|---|---|---|
| `abolish_term_limits` | `semi_presidential_republic` | `term_limit: 0` |
| `constructive_confidence_reform` | `constitutional_monarchy` | `censure_rule: "constructive_absolute"` |
| `executive_dissolution_reform` | `constitutional_monarchy` | `dissolution_rule: "executive_discretion"` |
| `streamline_amendment_procedure` | `constitutional_monarchy` | `amendment_rule: "ordinary_law"` |

France's own template constrains `formation_method`, `censure_rule` and
`dissolution_rule` to a single allowed value each — real, not an oversight —
so `term_limit` and `amendment_rule` are the only institutional fields an
amendment can meaningfully move for France. `abolish_term_limits` targets the
one with real dramatic stakes: extending or abolishing a term limit is a
live real-world fight, and it is the entrenchment case in reverse — the
player spends a scarce supermajority to remove the very rule that would end
their run. `parliamentary_republic` gets no content this session — see above.

## Article 49.3 cannot force a constitutional amendment through

The real Article 89 revision procedure has no executive bypass — 49.3 is an
ordinary-legislation tool. `Legislature.propose(force = true)` refuses a
constitutional law immediately, before touching any state (`refused: true`,
`passed: false`, `censure` never resolved), and `law_panel.gd` does not
render the Force button for a constitutional law at all. This game invents no
bypass for any other nation's amendment rule either.

## The load-bearing cross-check: at load, not just at nation-load

[[political-systems]]'s template validates every *nation's* flat field
against its declared system once, at startup. An amendment can write an
institutional field at **runtime**, long after that check has run — so the
same check has to hold for every value an amendment could ever write, not
just the value a nation starts with.

`DataLoader._validate_amendments()` (new, called after both `laws` and
`political_systems` are loaded) checks every constitutional law's
`effects.institutional` against every template named in its own `systems`
list, the same fields `_validate_political_system()` checks for a nation:
`censure_rule` against `allowed_censure_rules`, `dissolution_rule` against
`allowed_dissolution_rules`, `formation_method` against
`allowed_formation_methods`, `amendment_rule` against
`allowed_amendment_rules`, `term_limit` against `permits_term_limit`. A
violating amendment fails to load, naming the law, the field and the system —
so the half-understood institutional state [[political-systems]] refuses for
a nation cannot be produced by an amendment either, by construction rather
than by a runtime guard. `tests/test_amendment.gd`'s
`_check_load_bearing_cross_check()` proves it, the same way
`tests/test_political_systems.gd` proves the nation-side check.

`term_months` has no template constraint — no template schema field bounds
it — so an amendment may set it freely within `law.gd`'s own range check
(`[12, 120]` months). `SCALAR_EFFECT_KEYS`'s discipline (numeric, hard-clamped
at load) is what bounds it, not a per-template allowed set.

## Reachability in a played run, not just in principle

`tools/balance_probe.gd`'s `AMENDMENT_REGIMES` (a third regime family
alongside `DISSOLUTION_REGIMES` and `CABINET_REGIMES`) proposes
`abolish_term_limits` at month 12 of a `managed` French run and reports the
result. Run: `godot --headless --script res://tools/balance_probe.gd`
(no args runs every regime including this one).

The measured ceiling above is the *best possible* ceiling, not what a real
starting coalition scores against a specific bill's ideological position —
and the probe found the difference: against FRA's actual starting coalition
and `abolish_term_limits`'s authored position, the amendment **fails**
(270/577 yes, 46.8%, against the 60% `three_fifths` needs). This is not a
contradiction of the reachability finding — the sweep answers "can any
coalition at any position clear this bar", the probe answers "does this
specific bill, at this specific moment, against the coalition the player
actually has" — and a real constitutional vote failing sometimes is the
correct behaviour of a majority-gated mechanic, the same way an ordinary law
sometimes fails against a hostile assembly in `test_legislature.gd`'s own
`_check_failed_vote_names_opponents()`. 168 months, every other check green,
no clamp hit, no non-finite value.

## Save format

`amendment_rule` joins `NationState`, `SAVE_VERSION` 6 → 7. Unlike every
other V1.2b political-system field, `amendment_rule` is **mutable at
runtime** — an amendment may entrench (or loosen) its own threshold, which is
why it lives on `NationState` copied at new-game, not read straight off
`Nation` on demand. A version-6 save carries no `amendment_rule`; loading one
would read `""`, which matches nothing in `AMENDMENT_RULE_FRACTIONS`, and no
amendment would ever be proposable after the load — silent, not loud, which
is exactly the failure mode every prior version bump in this project refuses.
Refused outright, as always; no migration.

## Files

- `data/laws/amendments.json` — the four amendments
- `data/nations/*.json` (10) — `government.amendment.rule`
- `data/political-systems/*.json` (4) — `allowed_amendment_rules`
- `src/core/nation.gd` — `amendment_rule`, `KNOWN_AMENDMENT_RULES`
- `src/core/political_system.gd` — `allowed_amendment_rules`
- `src/core/nation_state.gd` — `amendment_rule` (mutable, unlike its siblings)
- `src/core/law.gd` — `constitutional`, `systems`, `effects.institutional`
- `src/core/data_loader.gd` — `_validate_amendments()`, plus one line in `_validate_political_system()`
- `src/core/game_state.gd` — `SAVE_VERSION` 6 → 7
- `src/sim/legislature.gd` — `available()`'s systems filter, `resolve_vote()`'s amendment arm, `apply()`'s institutional channel, `propose()`'s 49.3 refusal
- `src/sim/legislature_constants.gd` — `"amendment"` majority key, `AMENDMENT_RULE_FRACTIONS`
- `src/sim/government.gd` — copies `amendment_rule` onto `NationState`, alongside `formation_method`/`censure_rule`
- `src/ui/law_panel.gd` — the nation's own threshold displayed, Force button suppressed
- `src/ui/government_panel.gd` — the amendment rule, one line
- `tools/balance_probe.gd` — `AMENDMENT_REGIMES`
- `tests/test_amendment.gd` — new; `tests/test_political_systems.gd`, `test_save_load.gd` — edits
- `tests/fixtures/laws_bad_amendment/` — the load-bearing cross-check fixture

Related: [[political-systems]] · [[transition-model]] · [[government-model]] ·
[[legislature-model]] · [[data-architecture]] · [docs/tiers/v1.md](tiers/v1.md) ·
[[declined]]
