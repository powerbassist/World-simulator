---
title: Political Systems Model
tags:
  - decision
  - government
  - simulation
---

# Political Systems Model

Built at [[ROADMAP|V1.2b]]. [docs/tiers/v1.md](tiers/v1.md) §2's headline
feature, built once there was a working institutional layer to generalise —
government formation ([[government-model]]), discipline
([[discipline-model]]), dissolution ([[dissolution-model]]), cabinet
([[cabinet-model]]), and a second playable nation
([[ROADMAP|V1.2a]]).

## What changed, and why it had to

Every nation already declared its own `formation.method`, `formation.censure`,
`legislative.dissolution.rule`, `legislative.election.system`, and whether it
has a separately elected executive — all per-nation data, all dispatched on the
string, never on the nation id ([[engine-decision|Rule 1]]). A "political
system template" that only re-homed those fields would have been indirection
over data that already worked — the speculative abstraction
[docs/tiers/out-of-scope-mvp.md](tiers/out-of-scope-mvp.md) already flagged for
this feature.

So the template earns its keep on four things nations could not express
before this block:

- **The head of state.** Not modelled at all. Five of the ten nations are
  constitutional monarchies and nothing in the data said so.
- **A named lose condition.** The run-ending branch in `elections.gd` was
  dispatched on the structural flag `has_executive`, not on anything that said
  *why* an office was lost.
- **Term limits.** `NationState.terms_served` was incremented every re-election
  and read by nothing.
- **Referential integrity.** [[data-architecture]] already committed to *"every
  `system` names a real political system template"* before any template
  existed to check it against.

## The template is a constraint, not a defaults table

`data/political-systems/<id>.json`, one file per system, loaded by
`DataLoader._load_political_systems()` and parsed by `political_system.gd`
into a `PoliticalSystem` value type — the same `from_dict()`/`_extract_*`
shape `nation.gd` and `party.gd` already use.

A nation gains `government.system: "<id>"`. The template does **not** supply
defaults a nation can override — there is no inheritance chain, and no
override-resolution order to get wrong. A half-understood institutional state
is exactly the failure the rest of this project refuses outright (a save at an
unrecognised version, a party excluding a party that doesn't exist), so a
template that could silently fill in what a nation forgot to say would be the
one place that discipline lapsed.

Instead the template does two things:

1. **Carries what a nation cannot express alone** — `lose_condition`, and
   whether `permits_term_limit`.
2. **Constrains what a nation already carries flat** —
   `allowed_formation_methods`, `allowed_censure_rules`,
   `allowed_dissolution_rules`. `DataLoader._validate_political_system()`
   fails at startup, naming the nation and the field, if a nation's own value
   falls outside its template's set.

That cross-check is what makes the template load-bearing rather than
decorative. `tests/test_political_systems.gd` proves it: a nation whose
`formation.method` disagrees with its declared `system` fails to load.

## Four templates, matching the roster

§2's written list names five: presidential republic, parliamentary republic,
constitutional monarchy, absolute monarchy, one-party state. The ten-nation
roster — real nations, per [[fictionalization]] — supports four:

| Template | Nations | Formation | Censure | Dissolution |
|---|---|---|---|---|
| `semi_presidential_republic` | FRA | `presidential_appointment` | `absolute_members` | `executive_discretion` |
| `parliamentary_republic` | DEU, ITA, AUT | `chancellor_election`, `investiture`, `coalition_negotiation` | `constructive_absolute`, `simple_present` | `confidence_failure`, `head_of_state_limited`, `self_dissolution` |
| `constitutional_monarchy` | GBR, ESP, BEL, NLD, LUX | `largest_party`, `investiture`, `coalition_negotiation` | `constructive_absolute`, `simple_present` | `executive_discretion`, `confidence_failure` |
| `directorial_republic` | CHE | `directorial` | `none` | `none` |

Two of the five named templates are not authored: **no European nation in a
ten-nation Western-European roster is an absolute monarchy or a one-party
state**, and neither is a plain presidential republic — France is
semi-presidential, so `semi_presidential_republic` is the accurate name for
what §2 called "presidential republic." Building unattached templates now
would be code for content that does not exist, the same measured-before-built
discipline [[dissolution-model]] and [[cabinet-model]] both used.

> [!note] Named trigger for the deferral, corrected at V1.2c
> Originally: "the first start scenario or system transition that produces
> one." Neither can, on inspection: a system transition inside a ten-nation
> Western European roster produces `constitutional_monarchy` ↔
> `parliamentary_republic` and never an absolute monarchy, and
> [docs/tiers/v1.md](tiers/v1.md) §2's start scenarios vary *starting state*
> (debt, seats, approval, coalition), never the institutional system itself.
> The honest trigger is a **roster addition outside Western Europe**, or an
> explicitly counterfactual authored scenario — either authors the template
> against a real instance rather than a guess at what one would need.

`parliamentary_republic` and `constitutional_monarchy` share most of their
allowed formation/censure/dissolution sets — `coalition_negotiation` forms a
government in Austria exactly as it does in Belgium. The two templates do not
differ on formation mechanics; they differ on the one thing this block adds,
the head of state.

## The head of state

New per-nation block `government.head_of_state`:

```json
"head_of_state": {
  "kind": "hereditary_monarch",
  "title": "King",
  "name": "Robert III"
}
```

`kind` is one of `Nation.KNOWN_HEAD_OF_STATE_KINDS`:

| Kind | Nations | Own clock? |
|---|---|---|
| `executive_president` | FRA | No — the President IS the executive; `government.executive`'s own clock already covers it. |
| `elected_president` | DEU, ITA, AUT | Yes — `term_years` and `next` are required. |
| `hereditary_monarch` | GBR, ESP, BEL, NLD, LUX | No. |
| `collegial` | CHE | No — a one-year rotation among the Federal Council, held by the same person already authored as `leader`. |

`term_years`/`next` are present only where `kind == "elected_president"`, and
must be complete if present — the same "field exists, and if present it must
be complete" rule `nation.gd` already enforces for the separately-elected
executive block.

**No new powers.** Every power a real head of state holds here is either
already modelled as a formation or dissolution rule, or is ceremonial.
Inventing a royal-assent mechanic would be behaviour authored for no nation to
measure it against — the model stays a **game model**
([[government-model|the same standard]]), not a comparative-politics survey.

The head of state has exactly two readers:

- **The Government panel** (`government_panel.gd`) — a line naming the office
  and its holder, skipped for `executive_president` since the title line
  already names the same person.
- **`head_of_state_limited` dissolution (Italy)** — see
  [[dissolution-model|the *semestre bianco* section]]. This is the one
  behaviour change the head of state buys: `dissolution.gd`'s
  `_months_to_head_of_state_election()` reads `elected_president`'s own clock,
  so Italy's dissolution rule stops dispatching identically to
  `executive_discretion`.

Names are invented per [[fictionalization]], structural titles ("King",
"Federal President") are real. `tools/check_names.sh` covers the ten new names
the same as every other invented name in the project.

## Amendment, added at V1.2c

Every field this page describes as fixed for the whole run — `formation_method`,
`censure_rule`, `dissolution_rule`, `term_limit` — can now be rewritten by a
constitutional amendment, itself gated by a fifth per-nation field this
template constrains: `allowed_amendment_rules`. Full argument, including the
measured finding that Germany's real `two_thirds` is unreachable and is left
unauthored-against rather than detuned: [[amendment-model]].

## System transition, and `allowed_head_of_state_kinds`, added at V1.2d

Even `system_id` itself is now rewritable, by the same amendment mechanism
pointed at a target template rather than a single field — [[transition-model]].
That is also what the head of state needed a template-side constraint for the
first time: `allowed_head_of_state_kinds`, one value per template today
(1:1 with the roster), which makes a transition's head-of-state write
checkable against the target rather than trusted, and makes every nation's
own starting kind checked against its declared system for the first time —
nothing checked this before V1.2d.

## Term limits, enforced

`government.term_limit`, an int, `0` meaning no limit — the same
"zero means absent" shape EU membership already uses. Only France's template
(`permits_term_limit: true`) allows a nonzero value; the loader rejects a
nonzero `term_limit` on a template that does not permit one. France's own
value is `2`, France's real rule.

Checked in `elections.gd` at the executive verdict: an incumbent at the limit
does not stand for a vote at all — the run ends the same way a lost election
ends it, without fabricating a result for a candidate who was never on the
ballot.

France's real rule is two **consecutive** terms. `terms_served` never resets,
but a player who leaves office is out of the run, so consecutive and total
coincide here — documented rather than modelled, since nothing in this game
lets a player leave and later return to the same office.

### What this changed in the balance harness, and a finding along the way

`tests/test_balance.gd`'s `_check_two_full_terms_without_softlock` asserted
`terms_served >= 3` and `in_government` true after a fixed 168-month run — a
do-nothing French President who wins every election. Enforcing the term limit
ends that run at the third executive election (2037-05, month 136), termed
out on the merits rather than defeated. The check is now
`_check_france_terms_out_at_the_limit()`, asserting exactly that: two terms
served, no softlock along the way, `in_government` false as the *correct*
outcome — the failure modes are firing early, firing late, or being
indistinguishable from an actual defeat.

The plan for this block assumed the long, uninterrupted three-election
survival check could simply move to Germany, which has no chancellor term
limit. Running it found that assumption wrong: a do-nothing German budget
does **not** keep winning. `tools/balance_probe.gd -- hands_off DEU` shows the
chancellor's party sliding under 50% approval under a static budget and
losing "largest party" status at the second legislative election, 2033-02 —
a real, previously-measured divergence
([[data-architecture|the bloc-weight note]] already found France and Germany
diverge sharply on institutions and party rosters alone), not a bug in this
block's refactor. `_check_two_full_terms_without_softlock` now runs on
Germany but checks only what its own name promises — no crash, no non-finite
value, no value stuck on a guard clamp across however many elections a
168-month run actually resolves — rather than asserting a win streak Germany's
own measured behaviour does not support.

`_check_managing_beats_ignoring` needed one more adjustment: both its ignored
and managed French budgets win every election, so both are now termed out at
the identical calendar month regardless of policy. The check no longer
requires `managed["months"] == MONTHS`; it requires the managed run not stop
*before* the ignored one — the regression it guards against (a managed budget
losing office early) stays caught, and reaching the term limit on schedule no
longer reads as that regression.

## Lose condition, named

`elections.gd`'s executive-verdict branch used to read `ns.has_executive` to
decide which vote to check, and used the same flag's presence to imply what
losing meant. `lose_condition` (`PoliticalSystem.KNOWN_LOSE_CONDITIONS`) names
it instead:

| Value | Meaning | Nations |
|---|---|---|
| `executive_election_defeat` | Incumbent loses the separate executive contest | FRA |
| `party_not_largest` | Incumbent's party is no longer largest after a legislative election | DEU, ITA, AUT, GBR, ESP, BEL, NLD, LUX |
| `never` | Collegial executive, does not lose | CHE (declared, unresolved — CHE is not playable) |

`term_limit_reached` is an additional terminator alongside whichever of these
applies, not a fourth alternative — see above.

`lose_condition` lives on the template, not the nation (a nation's *shape* of
government implies how its executive can fall; that is not something each
nation authors independently the way its formation method is). `game_state.gd`
reads it off the resolved template in `_build_nation()`, after
`Government.init_nation()`, and writes it onto `NationState` alongside the
copied `system_id`/head-of-state/`term_limit` fields.

Behaviour for France and Germany is provably unchanged: `test_elections.gd`
and `test_censure.gd`'s assertions on `in_government` pass unmodified, and
every balance number `tools/balance_probe.gd` reports for France and Germany's
existing regimes is the same as before this block — see the harness section
above for the one place that was not simply "unchanged."

## Files

- `data/political-systems/*.json` — the four templates
- `src/core/political_system.gd` — the value type
- `src/core/nation.gd` — `system`, `head_of_state`, `term_limit` parsing
- `src/core/data_loader.gd` — loads templates, cross-validates every nation
  against its own
- `src/core/nation_state.gd`, `src/core/game_state.gd` — live-state fields,
  `SAVE_VERSION` 5 → 6
- `src/sim/government.gd` — copies the fields onto `NationState`
- `src/sim/elections.gd` — lose-condition dispatch, term-limit bar
- `src/sim/dissolution.gd`, `src/sim/dissolution_constants.gd` — the
  *semestre bianco* clock
- `src/ui/government_panel.gd` — the display
- `tests/test_political_systems.gd` — the roster shape and the load-bearing
  cross-check

Related: [[government-model]] · [[dissolution-model]] · [[cabinet-model]] ·
[[amendment-model]] · [[transition-model]] · [[data-architecture]] · [[fictionalization]] ·
[docs/tiers/v1.md](tiers/v1.md)
