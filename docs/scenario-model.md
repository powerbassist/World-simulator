---
title: Scenario Model
tags:
  - decision
  - simulation
  - scope
---

# Scenario Model

Built at V1.2e. [docs/tiers/v1.md](tiers/v1.md) §2's last item, and
the one that closes V1.2: **start scenarios** — a nation plus an authored
starting state.

## Why this exists at all

[[declined]] declined a difficulty slider and accepted start scenarios in its
place. The argument is not about taste, it is about method: every balance number
in this project is **measured** — S10's ten regimes, V1.1b's discipline sweep,
V1.1c's 57-seat dissolution spread, V1.1d's competence spread, V1.2c's
reachability sweep. A multiplier over tuned constants invalidates each of those
measurements and multiplies every future probe run by the number of settings.
Varying the *starting state* changes data and no constant, so the simulation
being measured is unchanged.

Until this block, that answer was written down and unbuilt: the game had exactly
one starting state per nation.

## Three axes, and why not the fourth

§2 names four things a scenario varies: debt level, seat composition, approval,
coalition. Three are authored. **The coalition is not**, decided at plan time:

- Seats plus `excluded_partners` already determine the coalition.
  `Government.form()` is the load-bearing per-nation dispatch — it is what makes
  Germany's `chancellor_election` differ from Britain's `largest_party` — and
  authoring a coalition *alongside* the seats that imply one authors a
  contradiction that rule exists to resolve. It would also be a second,
  unchecked route into institutional state, which is exactly what
  [[political-systems]] built the template constraint to prevent.
- Under GBR's `largest_party` the axis is **degenerate**: the government is
  single-party by construction. A field one playable nation in three cannot use
  is a field authored against the other two.

A scenario also never varies the institutional system. That is
[[transition-model]]'s mechanism, and [[political-systems]]'s deferral note
already records the boundary.

## Where each axis lands

Three override points, each at the one place that value first enters live state,
in `GameState._build_nation()`:

| Axis | Where | Note |
|---|---|---|
| `debt_to_gdp_pct` | before `Budget.recompute()` | so the debt service it implies is in the starting deficit `Opinion` then measures against — an inherited debt is a permanent budget drag, not a number on a panel |
| `seat_share` | merged over the party file's shares in `Elections.init_nation()` | before `Government.init_nation()`, which reads `seats_by_party` to form the coalition |
| `bloc_approval` | over `APPROVAL_NEUTRAL` in `Opinion.init_nation()` | see the next section — it writes a second field too |

Everything downstream — `Discipline`, `Cabinet`, `Legislature`, `Dissolution` —
reads the overridden figures and needs no scenario awareness at all.

> [!note] `Legislature.init_nation()` moved ahead of `Opinion.init_nation()`
> It zeroes `bloc_offset`, which `Opinion.init_nation()` now writes. It
> zeroes law state and reads nothing, so it is order-independent against
> everything else in `_build_nation()`; moving it was cheaper and more honest
> than teaching it to spare one key.

### The approval axis needed a second write, and the measurement is why

Every satisfaction term in [[opinion-model]] is a **delta against the nation's
own starting figure**, so a fresh game's approval target is exactly
`APPROVAL_NEUTRAL`. An authored 38 written only to `bloc_approval` therefore has
nothing holding it there: `INERTIA_RATE = 0.25` gives a ~2.4-month half-life, so
it is within a rounding error of 50 inside a game year — while the debt and seat
axes persist indefinitely. An axis that evaporates is not a difficulty lever,
and that is [[declined]]'s own falsifier firing on one third of this feature.

Caught at design time, before content was authored. The fix reuses the channel
the model already has for an opinion effect with no budget line behind it:
`bloc_offset`, summed into the approval *target* rather than into approval
directly. `Government.penalise_blocs()` already writes it for a fallen
government, which is no more a law than a scenario is — the field is misnamed,
not misused.

The authored figure sets both, and the second is **derived, not authored twice**
— inverting `_tick_nation()`'s own target formula:

```
bloc_offset[bloc] = (authored - APPROVAL_NEUTRAL) / APPROVAL_SPAN
```

Clamped to `[BLOC_OFFSET_MIN, BLOC_OFFSET_MAX]`, which bounds the *sustainable*
band to [10, 90] — the same band a pure satisfaction score produces, so an
authored 5 is a starting position that rises rather than an equilibrium the
model cannot hold. `tests/test_scenario.gd` runs twelve months (five half-lives)
and asserts the approval has not drifted back toward neutral.

## Data

`data/scenarios/*.json`, directory-scanned like `data/laws/` and
`data/political-systems/` — no manifest, so adding a scenario is a file rather
than a file plus an index entry.

```json
{
  "id": "fra_inheritance",
  "nation": "FRA",
  "name": "Inheritance",
  "description": "Shown in the menu.",
  "overrides": {
    "debt_to_gdp_pct": 155.0,
    "seat_share": { "party_id": 0.18 },
    "bloc_approval": { "workers": 45.0 }
  }
}
```

Every override key is optional and every one is **partial**: a bloc the scenario
does not name stays neutral, a party it does not name keeps its authored share.
An `overrides` block naming none of the three fails to load — a scenario that
overrides nothing is Standard under another name.

**`scenario_id == ""` is the standard start**, and there is no file for it. That
keeps every existing measured balance number describing a real, reachable start
rather than one variant among several, and avoids three near-empty files.

### Validation, split in two

Range and shape live in `scenario.gd`; anything needing the nation's own roster
lives in `PoliticsLoader.validate_scenarios()`, beside the other cross-file checks.
Both fail loudly at startup, the same discipline a bad nation file gets:

- an unknown nation, or one that is not `playable` — a scenario offered from a
  surface that lists playable nations only is unreachable content otherwise
- a `seat_share` key that is not a party in that nation's file
- **the merged roster not summing to 1.0** — checked against what the scenario
  actually produces, not against the override fragment, which is not required to
  sum to anything on its own. This is the one check that passes every per-file
  test and fails only cross-file, which is why the split exists.
- a `bloc_approval` key outside `BLOC_KEYS`, or a value outside [0, 100]

## No `SAVE_VERSION` bump

`SAVE_VERSION` stays at **8**. `scenario_id` lives on `GameState` beside
`player_nation_id`, and a scenario applies once at `new_game()` and mutates
nothing after — its effects live in the ordinary fields a save already carries.
A version-8 save with no `scenario_id` reads as `""`, which is **correct** for
every save that exists rather than silently wrong. That is the condition
`game_state.gd`'s own `SAVE_VERSION` comment gives for a bump, and it does not
hold here. Same call V1.2a made and held.

## The measurement

`tools/scenario_probe.gd`. [[declined]] attached a falsifier to this feature —
*the difficulty range start scenarios can reach is too narrow* — so the range
was measured before content was finalised, not asserted after.

Two tables, because **the axes act on two different things and one table hid
that**. The first run reported the seats axis as changing *nothing*: identical
approval, deficit, debt and election timing at every extreme. That was an
artefact of the regime, not a finding — `hands_off` proposes no law, and the
legislature is the only channel seats have. Splitting the report into a
legislative table (measured at month 0, through the real `resolve_vote()`) and an
economic one turned it back into a measurement.

### The envelope, at the extremes

Extremes are deliberately past anything shipped: debt ×2, the governing party cut
to a 0.14 rump, every bloc at 25.0.

| Axis | What moves |
|---|---|
| debt | deficit +1.3 to +2.4pp, debt after 60 months +65 to +120pp; DEU loses an election it otherwise holds |
| approval | approval 50 → 25 at month 0, → ~14 at month 12, → 10–12.6 at month 60; FRA and DEU each lose an election |
| seats | the amendment ceiling by ±0.06, **enough to flip reachability in both directions** — FRA 0.624 → 0.560 loses a reachable amendment, GBR 0.497 → 0.612 gains one. No economic or opinion effect whatsoever. |

**The falsifier does not fire.** A ~40-point approval range, a ~120pp debt range,
and an amendment ceiling that moves reachability both ways is not a narrow band.

### The shipped content, and the two things the measurement changed

| Scenario | Against its own baseline |
|---|---|
| `fra_inheritance` | deficit 5.04 → 5.84, debt at 60 months 132.2 → 172.6, approval 49.6 → 45.9 |
| `deu_grand_coalition` | amendment ceiling 0.503 → **0.727** against a 0.667 bar; coalition 0.619 → 0.811 |
| `gbr_hung_parliament` | amendment ceiling 0.497 → **0.446** against a 0.500 bar; coalition 0.560 → 0.509 |

Both seat scenarios were authored wrong first, and the probe said so:

- **`deu_grand_coalition` cleared two-thirds by exactly nothing.** At 0.69
  combined it measured 0.667 against 0.667 needed — passing on a rounding
  boundary. Widened to 0.75 for real margin rather than shipped on the knife
  edge, the same call [[transition-model]]'s restoration sweep made.
- **`gbr_hung_parliament` made amendments *easier* than the standard start**
  (0.497 → 0.505), the opposite of what the file claims to be. The freed seats
  had been spread onto `liberal_union`, building a centrist bloc some law could
  always rally. Rewritten to spread onto `patriot_front`, which both large
  parties list in `excluded_partners` — seats that are dead weight for assembling
  anything.

### Germany's two-thirds bar is now reachable, and that was a named prior claim

[[amendment-model]] recorded Germany's real `two_thirds` as unreachable at the
standard start and named **a grand-coalition-shaped start scenario** as one of
two things that could raise the ceiling. It does: 0.727 against 0.667, a 6.0pp
margin. V1.2c shipped no amendment content naming `parliamentary_republic` in its
`systems` list because there was no state in which one could pass; there is now
one, and the parked content has somewhere to point.

Left for the session that authors it rather than done here — this block shipped
the mechanism and the measurement, not V1.2c's deferred content.

## UI

Two steps, one panel. `nation_select_panel.gd` swaps its own list rather than
opening a second overlay: the question is "which game am I starting", and
splitting one question across two panels puts a Back button in the middle of it.
A nation with no authored start emits straight through, so the second step never
appears as a list with one entry. Standard is always first — it is the game every
measured figure in these docs describes, and burying it under the variants would
make the baseline look like one variant among several.

Overview's title carries the running start's name, and carries **nothing** for
the standard one: a label that is always there says nothing, and the point is to
mark the games that differ from the baseline.

---

Related: [[v1]] · [[declined]] · [[amendment-model]] ·
[[transition-model]] · [[political-systems]] · [[opinion-model]] ·
[[data-architecture]]
