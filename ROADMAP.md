# Roadmap

Build order for Nation Simulator. Short, scoped sessions — **one clear objective
each**, git commit at every session boundary.

This document is **forward-looking**. What shipped is one line each in the table
below; the corrections made along the way are in [[decision-log]]; the models are
in the model notes.

Scope reference: [docs/scope.md](docs/scope.md) · [docs/tiers/mvp.md](docs/tiers/mvp.md) · [docs/tiers/v1.md](docs/tiers/v1.md) · [docs/tiers/declined.md](docs/tiers/declined.md)
Stack reference: [docs/engine-decision.md](docs/engine-decision.md) · [docs/data-architecture.md](docs/data-architecture.md)

## Two tracks

Work runs on two interleaved tracks rather than one queue.

| | |
|---|---|
| **S-track** | Simulation systems — the model, the rules, the numbers. |
| **U-track** | The shell, the UI, and the feedback the player reads. |

The S-track existed from S0. The U-track was invented at U1, after an audit found
the roadmap contained **no UI work whatsoever** across the MVP and all of V1 —
presentation had been assumed to fall out of each feature session, and by V1.1a
that had produced a game with no menu, no pause, and seven overlays bound to
seven keypresses. See [[decision-log]].

One track at a time per session. Interleaved, not parallel.

**U5a interrupted the S-track queue, and it was asked for rather than
scheduled.** The queue below was V1.3c when the user asked for the shell to
become a geopolitical simulator's rather than a dashboard's — the player
incarnating a ruler, not administering a country. That is a legitimate reason to
interleave and exactly what the two-track split exists to allow, but it is worth
recording that the U-track's *own* backlog did not surface it: U5 had been
reserved since V1.1d for a Military tab, and that reservation is now spent
differently. Nothing in U1–U4's own record predicted a whole-shell relayout,
because each of those sessions improved the dashboard rather than asking whether
a dashboard was the right object.

---

## Shipped

| | Block | What it added |
|---|---|---|
| S0 | Project skeleton | Godot project, folder layout, git, attribution |
| S1 | Nation data | Schema, `tools/import_data.py`, loader, validator, ten nations |
| S2 | Fictional content | Leaders and party systems, banned-names check |
| S3 | Time | Daily tick, pause, three speeds, `month_elapsed` |
| S4 | Economy and budget | Three sectors, GDP/growth/unemployment, three taxes, six spending lines, debt service, projection-before-commit |
| S5 | Public opinion | Six voter blocs, salience, inertia, display-only polling noise |
| S6 | Elections | Ten real electoral systems, EP elections, seat allocation, win/lose — **the loop closed here** |
| S7 | Laws | Data-driven law templates, ideology-space vote resolution, blurred vote forecast |
| S8 | Map | GeoJSON Europe, colouring, hover, click, nation panel |
| S9 | Save and load | Versioned JSON saves, slot list |
| S10 | Balance | Ten probe regimes over fourteen simulated years, MVP done-when evidence |
| V1.1a | Government | Formation per nation's real rules, coalitions, cohabitation, minority, censure, Article 49.3 |
| U1 | Shell | Main menu, settings, credits, pause menu, keyboard navigation |
| X1 | Fixes | Atomic save writes; banned-names check green, closing the last MVP box |
| U2 | Shell | Dashboard: persistent top bar, left tab rail, seven panels docked, map as a tab |
| U3 | UI | Overview and Economy rebuilt as hierarchies, one code-built theme, `Trends` over `history` |
| U4 | UI | Decision deltas: `recent_effects`, a baseline captured at commit, measured against the next history entry |
| V1.1b | Sim | Party discipline as live state, seat-level rebellions, disaffection — the censure branch fires |
| V1.1c | Sim | Dissolution and snap elections — the rule as ten-nation data, measured before it was built, no election-model change needed |
| V1.1d | Sim | Cabinet and ministers — five portfolios keyed to spending lines, competence and portfolio position both derived rather than authored, shortfall-driven resignation measured before it was built |
| V1.2a | Sim | A second playable nation — Germany, per-nation starting fiscal policy (`policy_defaults.json` retired), bloc weights confirmed global by measurement rather than assumption |
| V1.2b | Sim | Political system templates as a constraint not a defaults table, the head of state (five constitutional monarchies now say so), a named lose condition replacing a structural-flag dispatch, term limits enforced (France's two-term limit termed-out on the merits), Italy's *semestre bianco* dissolution blackout |
| V1.2c | Sim | Constitutional amendment — a sixth per-nation dispatch field (`amendment_rule`) at real constitutional fractions, a seventh law effect channel that sets rather than nudges an institution, the load-bearing cross-check extended to amendments; measured, not assumed, that Germany's real two-thirds is unreachable, and left unauthored-against rather than detuned |
| V1.2d | Sim | System transition — the amendment mechanism pointed at `system_id`, a completeness rule on the institutional bundle, the cross-check inverted to validate against the amendment's target rather than the systems it is proposed under, a seventh per-nation dispatch field (`permits_system_change`); the United Kingdom made the third playable nation, added to the scope at plan time once the original scope was found to ship to zero playable nations |
| V1.2e | Sim | Start scenarios — an authored starting state as the project's answer to difficulty, three axes not §2's four (the coalition stays derived), a new directory-scanned content type with its validation split per-file/cross-file; the declined difficulty slider's own falsifier measured and not fired, an approval axis caught decorative at design time and fixed through the existing offset channel, and two of the three shipped scenarios corrected by the measurement before release — **V1.2 closed** |
| V1.3b | Sim | Trade: per-partner intensity and agreements — `external_impulse_pct` made **directed**, ninety entries from partner size, EU co-membership, a shared border and the pair's relations, retiring the one GDP-weighted aggregate that was the same number for every viewer; **V1.3a's dropped size asymmetry landed here**, because a normalised directed weight has two sides where a symmetric pair key has one (LUX→DEU is 13.1× DEU→LUX); bilateral agreements as a **third effect channel on the existing diplomatic action** rather than a content type of their own, with sector winners and losers that must sum to zero at load; a second declared stopgap; `SAVE_VERSION` 9 → 10. Both named escalation triggers were GBR-shaped and the first **fired** — at the obvious exponent the whole feature is arithmetically a no-op for one playable nation in three. The balance harness came back **bit-identical across thirty fourteen-year runs**, and the model was shaped to make that provable rather than likely |
| U5a | UI | The ruler's shell — the map stops being a tab and becomes the background the game is played on; the 150px tab rail is deleted and `dashboard.gd` with it; the seven docked pages become **floating windows that pin**, so reading the budget while proposing the law that changes it is possible for the first time. Bottom-left portrait card with the player's own approval, four themed clusters with a sub-row along the bottom, date and speed in the bottom-right corner, a message column stubbed for V1.8. One theme retuned from flat grey to deep navy with a **brass** accent, the repo's first committed fonts and its first four committed icons, and a 1920×1080 base that opens fullscreen. `flag` added to all ten nation files as data with a layout string, because a colour table in the UI is Rule 1's `if nation_id == "FRA"` wearing a hat |
| V1.3a | Sim | Relations and diplomatic actions — the block's schema session: **pair-keyed relations**, the first live state that is neither per-nation nor global, symmetric by construction and derived from the only two inputs the data can supply (EU co-membership, and a shared border added as fact); a new content type on the law template's preconditions/cooldown/effects shape but explicitly *not* its vote; four player verbs on the Europe tab's existing nation panel; `law_bloc_offset` → `bloc_offset` at the fifth writer that is not a law; `SAVE_VERSION` 8 → 9. The named escalation trigger did not fire, and the measurement set every content number — including one it made a table redo, and one exploit it caught before the content shipped |

MVP done-when checklist: [docs/tiers/mvp.md](docs/tiers/mvp.md). All boxes ticked.

---

## Next

**V1.3 is decomposed into six sessions** — the argument, and the four calls it
made, are under *V1.3 — the decomposition* below. V1.3a and V1.3b are shipped.
The next session is **V1.3c, tariffs and sanctions**.

### U5a — the ruler's shell (shipped)

The session that changed what the game *is a picture of*. U2 built a dashboard,
U3 and U4 made it a good one, and none of the three asked whether a dashboard
was the right object — the player was administering France through a set of
tabs. U5a makes the map the background, the interface instrument furniture laid
over it, and the player's own face a permanent fixture in the corner.

**The ask was three things and shipped as one, decomposed before any code.** The
request was the shell, a world satellite map, and a calendar of appointments
with named people. The calendar is a simulation feature wearing a UI costume —
it needs person entities that do not exist, which is the thing [[cabinet-model|V1.1d]]
explicitly deferred — and the map half is independent of the HUD half. Split
into U5a (this), **U5b** (the map) and **U6** (the calendar and the roster), each
with its own plan. The count for U5a alone came to ~28 surfaces, between V1.2d's
~21 and V1.3b's ~33.

**Four calls, recorded because each could have gone the other way:**

1. **Windows pin, and that is why the rail could die.** A tab rail guarantees
   one thing a set of floating windows does not: the player never has to tidy
   up. `window_manager.gd` keeps that guarantee as its single rule — *opening a
   panel closes the open unpinned one, and leaves every pinned one alone* — so
   the default behaves exactly like tabs and the pin buys the case tabs could
   never serve. Without the pin this would have been a reskin.
2. **Brass, not cyan.** The reference and every game HUD reach for a cool glow.
   Brass is the state's own material — seal, instrument bezel — and it is the
   one bold move in a palette that is otherwise disciplined navy. The signature
   is one rule applied everywhere: a 1px brass hairline on a plate's **top edge
   only**, light falling on glass laid over a map table. `tests/test_ui_theme.gd`
   asserts the other three edges stay bare, because that is precisely the kind
   of thing a later session tidies into `set_border_width_all()` without
   noticing the interface stopped having a point of view.
3. **The message column ships as furniture with nothing behind it.** Events are
   V1.8 and [docs/tiers/v1.md](docs/tiers/v1.md) argues at length that they stay
   last. Building the column now costs a file; wiring it to invented content now
   would cost the argument. The API is real and tested so V1.8 adds calls rather
   than a layout.
4. **The flag became data, not a table in the UI.** Ten `flag` blocks with a
   `layout` string `src/ui/flag.gd` dispatches on — the same
   dispatch-on-a-data-string shape as `formation_method` and the six fields
   after it. A colour table keyed by nation id inside a panel is
   `if nation_id == "FRA"` with extra steps, which
   [docs/engine-decision.md](docs/engine-decision.md) Rule 1 forbids outright.
   This is the one place the session touched `data/`, and it earns **no**
   `SAVE_VERSION` bump: a flag is static content read at startup and never
   written to a save.

**Two things the plan got wrong, both found by looking at the running game
rather than by reasoning.** The first: with the map promoted to background, its
opening zoom of 1.0 — fine inside a tab — left Europe as a 480×420 object
floating in the middle of 1920×1080, and every test passed while it did, because
no test asks what fraction of the screen the map fills. The second: the panels
report combined minimum heights up to 974px against a usable band of 886, so a
window sized to its content grew straight through the bottom furniture and the
player could not reach its last row. Both are the class of bug the U-track
exists for and neither is visible headless; `tools/shot.gd` (throwaway, not
committed) rendered the scene to a PNG because `--headless` draws nothing.

**One deviation from the plan, stated rather than absorbed.** The plan said the
session touched no `data/` and no `src/core/`. The flag did both — ten JSON
files, `Nation.from_dict()` and a validator. It is presentation content, it
fails at load like every other bad field, and it was the only way to draw a flag
without breaking Rule 1; but the plan's claim was wrong and the row says so.

### V1.3c — tariffs and sanctions (next)

Coercion in both directions: tariff revenue, sanctions imposed and received,
domestic blowback, retaliation. Reads a and b.

**It inherits a channel that is built, measured and waiting.** V1.3b made
`external_impulse_pct` per-partner and directed, and left it structurally
correct but numerically small — the nine AI nations have no budget and take no
shocks, so nothing perturbs a partner except a bilateral agreement. **V1.3c is
the first session that perturbs one on purpose**, and `tools/trade_probe.gd`
already measures what the channel does under a synthetic partner recession: at
France's weight on Germany the peak impulse is 6% of `IMPULSE_MAX`, so the
headroom is known rather than assumed. [[trade-model]] also records the coupled
ten-nation system's eigenvalues, so the decision to give the other nine an
external impulse of their own can be taken knowingly rather than re-derived.

**Two stopgaps are on the checklist now, not one.** V1.3c adds a third and
declares it the same way — see the decomposition's call 2 below.

### V1.3b — trade: per-partner intensity and agreements (shipped)

The session that made `external_impulse_pct` **per-partner**, and the one that
owed the balance harness a re-run. Full account: [[trade-model]]. What belongs
here is what the session's own record adds.

**"Unquiets `external_impulse_pct`" was an overclaim, and it is corrected above
and in [[v1]] rather than quietly delivered.** The decomposition table's own
wording — *made per-partner rather than one GDP-weighted aggregate* — shipped
literally and fully. The prose promised more. The channel is now structurally
correct and still numerically small, because nothing in the shipped game
perturbs a partner except an agreement, which is bilateral and so does move the
partner's trend. That makes the channel live rather than dormant, but it does
not make it loud, and saying so is cheaper than discovering it at V1.3c.

**The first named escalation trigger fired, and it was structural rather than a
tuning miss.** At the obvious gravity exponent of 1.0 the derived weight vector
is GDP-proportional — and GBR, which is in no EU pair and whose `neighbours`
list is empty, has both tie bonuses constant across all nine partners, so both
**cancel under normalisation**. Its vector is then *identically* the aggregate
the session replaced: L1 distance 0.000, measured. One playable nation in three
would have received a per-partner model that was arithmetically the thing it
replaced. The exponent is the only lever that moves GBR at all, and it shipped
at 0.70. This is the same class of cold read [[transition-model|V1.2d]] made
when it found its own scope shipping to zero playable nations — caught by the
plan's own named measurement, before any of the model was built.

**The second trigger did not fire, but it constrained a constant from above and
that consequence is recorded rather than left to be found.** Every GBR pair
rests at 45.0 and the strongest positive verb reaches 60.7, so any
relations-based gate must sit under 60.7 or the feature is closed to Britain
entirely — [[amendment-model|Germany's two-thirds]] repeated. It shipped at 52.
The consequence: for France and Germany the gate is non-binding against almost
every partner, so an agreement's difficulty there is carried by its **domestic
price** rather than by the gate. For GBR the gate *is* the difficulty. That
asymmetry is forced, not chosen, and it is thematically right.

**A second exploit was caught the way V1.3a's was, and it decided the model's
central call.** The obvious openness figure — trade mass over own GDP — would
have let relations move the trend *level*. `state_visit` is +5 relations, per
target, with no preconditions and **no domestic price at all**; nine clicks a
year would have bought about two permanent points of GDP on infrastructure for
free. Openness shipped as a ratio against a no-agreement counterfactual instead,
so relations move the **mix** and only an agreement moves the level. That choice
also killed a monotonic ratchet — partner GDP growing at trend forever would
have walked the index up ~20% over the harness's fourteen years from time
passing alone, putting the clamp rather than the model in charge of trend
growth, which is the `IMPULSE_MAX = ±50` failure [[economy-model]] already
records, committed a second time.

**And it made the harness re-run cheap by making it exact.** Because the
openness index is exactly 1.0 with nothing signed and the impulse is exactly
zero while partners sit at their own baselines — both by construction — the
re-run's question sharpened from *has anything moved materially?* to *has
anything moved at all?* Thirty fourteen-year runs, captured from the V1.3a tree
and diffed: **bit-identical**. Every economy constant measured through this
channel is still valid, unchanged and unargued.

**The synthetic probe found a real ordering bug that was invisible and would
have surfaced a session later.** The weight table is snapshotted before the tick
loop, but the impulse also reads each partner's `growth_annual_pct`, which
`_tick_nation()` overwrites — so resolved inside the loop, France read *this*
month's growth for the five partners sorted before it and *last* month's for the
four after. Both answers are zero while nothing is perturbed, so no test could
have seen it; it would have surfaced at V1.3c as a mystery. Found only because
the probe injected a partner recession the shipped game cannot produce.

**One repair the plan predicted and one it did not.** `Budget.project()` never
ticked `Diplomacy`, which was harmless until relations reached the economy;
measured at 2e-9 relative from a displaced state, small and still a broken
done-when condition, so `project()` now takes a loader. The one the plan did not
predict: storing an agreement's **terms** rather than its id in the register let
`src/sim/trade.gd` take no loader at all, which is what kept
`Economy.tick_month()`'s signature unchanged across **twenty-eight call sites**.

One piece of V1.2 work is still deferred rather than done, with somewhere to
point now: **V1.2c authored no amendment content naming `parliamentary_republic`**,
because Germany's real two-thirds bar was measured unreachable. V1.2e's
`deu_grand_coalition` start makes it reachable (0.727 against 0.667). The
content itself was left to the session that picks it up — see
[[scenario-model]].

### V1.3a — relations and diplomatic actions (shipped)

The block's schema session, and the first live state in this project that is
neither per-nation nor global. The full account — all four design questions,
every constant's rationale, and the measured tables — is [[diplomacy-model]].
What belongs here is what the session's own record adds to this document's
arguments.

**All four design questions went the cheap way, and one of them cost a third
input.** Relations are **symmetric** — one number per unordered pair, 45 in all,
keyed `"DEU|FRA"` by the one helper permitted to build a key, so
`rel(A,B) == rel(B,A)` is structurally true rather than maintained. Starting
values are **derived**, not authored, from EU co-membership (which every nation
file already carried) and a shared land border (added as a *fact*, the same
class as `assembly_seats`, cross-checked at load for mutuality). Size
asymmetry — the third input the roadmap expected to use — was **dropped as a
direct consequence of the symmetry call**: under a symmetric key a size
disparity cannot be expressed, because the pair's single number has no side to
attach it to. Handed to V1.3b's read-time trade weighting rather than quietly
omitted. `bloc_offset` was renamed, at the fifth writer that is not a law.

**The named escalation trigger did not fire, but the measurement rewrote
itself once.** The reachable range is ample — even the mildest authorable
content moves a pair further than the 8-point gap between two resting tiers,
so no precondition is unreachable. But the probe's first table asked *how long
a pair takes to return within one point of resting after sustained use*, which
from a twenty-point displacement is four-plus half-lives **by construction** —
so nearly every row read "> 120 months" and the table looked like it was
reporting that the drift does nothing. A second table was added rather than the
first one reinterpreted, and it is the one that justifies the constant: a
**single** action has a 35-month half-life, 78% present after a year and 30%
after a term.

**The measurement's real finding was in the other table, and it was not the one
the plan named.** The plan expected to check whether an action's bloc effect
clears poll noise. It does, at 0.08 and above — but only when the effect hits
**all six** blocs. An offset applied to fewer never clears the floor in
`overall_approval_pct`, not even at the content ceiling, because the roll-up is
weighted. A split price is legible on the polling panel's per-bloc rows and
nowhere else. Not a bug — a policy that divides the country should not move the
average — but an action whose only price was a two-bloc offset would have
shipped looking like a decision with no visible consequence.

**And it caught an exploit before the content shipped.** The obvious content
for the visible-cost slot was a six-bloc *gain*, since condemning foreigners is
domestically popular. The cooldown is per (action, target), so nothing would
have stopped the player applying it against all nine neighbours in one month —
+0.72 accumulated into a channel clamped at +1.0, saturating approval outright.
The visible six-bloc action shipped as a pure **cost** instead, and the popular
verb ships **split**, so mass use moves blocs in opposite directions and is
self-limiting. This is the first correction on this document's record to come
from a measurement finding an *exploit* rather than an unreachable number.

**The counterparty response is a declared stopgap, and the test asserts it.**
An action's own `relations` delta is the entire reaction; no reasoning, no
retaliation, no third pair moves. `tests/test_diplomacy.gd` asserts that acting
on Germany leaves `DEU|ITA` exactly at its resting value, so V1.3e replacing
the stopgap is a visible test change rather than a silent one.


### V1.3 — the decomposition, and why these six

Written before any code, which is where a block-shaped row belongs: V1.3 was
one line — relations, diplomatic actions, trade agreements, tariffs, sanctions,
an EU-shaped bloc, nation AI foreign policy, defence as domestic politics — and
one line is not a session.

| | Session | Content | Reads |
|---|---|---|---|
| **V1.3a** | Relations and diplomatic actions | Pair-keyed relations as live state, monthly drift, a small set of player verbs with a domestic price | — |
| **V1.3b** | ~~Trade: per-partner intensity and agreements~~ **shipped** | `external_impulse_pct` made per-partner rather than one GDP-weighted aggregate; bilateral agreements with sector winners and losers at home | a |
| **V1.3c** | Tariffs and sanctions | Coercion in both directions: tariff revenue, sanctions imposed and received, domestic blowback, retaliation | a, b |
| **V1.3d** | The bloc | EU-shaped membership as a real constraint on domestic policy, transfers, bloc-level voting where the player is one member among many | a, (b) |
| **V1.3e** | AI foreign policy | Nine nations pursuing their own interests. Replaces every stopgap rule b–d shipped | a–d |
| **V1.3f** | Defence as domestic politics | Capability derived from sustained spending, deployments, defensive alliances, alliance obligations that bill you at home | a, d |

Four calls, each of which could have gone the other way:

1. **Relations ship with a verb, not alone.** A relations score with no reader
   is the failure [[scenario-model|V1.2e]] caught at design time: an axis with
   no persistent channel decays back to neutral inside a game year and is
   decorative. V1.3a ships the smallest closed loop instead — act on a
   neighbour, relations move, blocs at home react — rather than a state layer
   whose first reader arrives a session later.
2. **AI is fifth, and every session before it ships a *named* stopgap.** An AI
   with no action space to score is unbuildable, and an AI built at b is
   rescored by c and again by d. So b, c and d each ship a deterministic
   counterparty rule and **declare it as a stopgap V1.3e replaces** — the same
   shape `lose_condition: "never"` and `referendum_required` already use for a
   declared-unresolved rule. V1.3e opens with the checklist of them, so the
   debt is a list rather than a discovery.
3. **The foreign-policy opinion issue is V1.3d's call, not V1.3a's.** a–c use
   `law_bloc_offset`, the persistent channel that already exists. Whether
   foreign policy earns its own `ISSUE_KEYS` entry is decided at d, where the
   domestic politics of Europe is the mechanic rather than a side effect — and
   the cost is named in advance rather than discovered: a new issue means six
   new `BLOC_SALIENCE_BASE` rows, and [[declined]] records that *every* tuned
   opinion constant was measured against that one table.
4. **Defence stays last, and takes defensive alliances with it.** Already
   committed — a deployment with no counterparty is a spending line with a
   different label — and an alliance obligation that bills you at home needs
   both a counterparty (a) and a bloc (d).

**V1.3e is the row most likely to split**, recorded in advance rather than
discovered: if its own plan-time count comes back above V1.3a's, it splits into
an interest model and an acting agent, and the letters run to g.

Three things the cold read found that the decomposition rests on:

- **`external_impulse_pct` is already wired and deliberately quiet.**
  `economy_constants.gd`'s `TRADE_BETA` comment says so in as many words. V1.3b
  is the session that unquiets it — and every tuned economy constant was
  measured through that channel, so b is where the balance harness gets re-run,
  not a. **Half right, and the wrong half was the word "unquiets"**: b made the
  channel per-partner and directed as promised, and did re-run the harness, but
  the term stays numerically small until something perturbs a partner. See
  V1.3b's row above.
- **All ten nations already have a formed government.**
  `GameState._build_nation()` runs `Government.form()` for every nation, so each
  carries a `coalition_position` on the same two-axis space laws are scored
  against. V1.3e's interest function has authored inputs already; it does not
  need a new per-nation content class.
- **`data/eu_parliament.json` and `src/core/eu.gd` exist and are
  elections-only.** V1.3d extends that file rather than inventing a bloc.

**LimboAI was evaluated for V1.3e and declined** — see [[declined]] for the four
reasons and the condition that reopens it.

### V1.2e — start scenarios (shipped)

[docs/tiers/v1.md](docs/tiers/v1.md) §2's last item, and the one that closes
V1.2. A scenario is an authored starting state for one nation, applied once at
`GameState.new_game()` and never again — the project's answer to difficulty, and
the reason [docs/tiers/declined.md](docs/tiers/declined.md) declined a slider:
every balance number here is measured, so a multiplier over tuned constants
invalidates each measurement, while varying the starting state changes data and
no constant.

**Three axes, not §2's four.** Debt, seat composition and starting approval are
authored; **the coalition stays derived** by `Government.form()` from the seats
a scenario already authors. Authoring both would author a contradiction the
formation rule exists to resolve, and under GBR's `largest_party` the axis is
degenerate — the government is single-party by construction, so it is a field
one playable nation in three cannot use.

**The plan's named measurement ran, changed the content twice, and its first
result was an artefact.** `tools/scenario_probe.gd` initially reported the seats
axis as changing *nothing* — identical approval, deficit, debt and election
timing at every extreme. That was the regime, not the finding: `hands_off`
proposes no law, and the legislature is the only channel seats have. Split into
a legislative table and an economic one, the axis moves the amendment ceiling by
±0.06 — enough to flip reachability in **both** directions. Both seat scenarios
were then found wrong and corrected before release: `deu_grand_coalition`
cleared two-thirds by *exactly nothing* (0.667 against 0.667, on a rounding
boundary) and was widened; `gbr_hung_parliament` made amendments **easier** than
the standard start, the opposite of what it claims to be, and had its freed
seats moved onto the party both large parties exclude.

**A third of the feature was decorative and nearly shipped that way.** Every
satisfaction term is a delta against the nation's own start, so a fresh game's
approval target is exactly neutral — an authored approval written only to
`bloc_approval` decays back to 50 on a ~2.4-month half-life and is gone inside a
game year, while debt and seats persist. Caught at design time and held at its
target through `law_bloc_offset`, the channel `Government.penalise_blocs()`
already uses for a fallen government. [docs/tiers/declined.md](docs/tiers/declined.md)'s
own falsifier was otherwise measured and did **not** fire.

`SAVE_VERSION` stays at 8 — the one runtime-readable addition since V1.2b that
does not earn a bump, because a version-8 save's absent `scenario_id` reads as
"" and that is *correct* rather than silently wrong. Full account:
[[scenario-model]].

### V1.2d — system transition, and a third playable nation (shipped)

[docs/tiers/v1.md](docs/tiers/v1.md) §2's last mechanism item, built after
[[amendment-model|V1.2c]] gave it the amendment machinery to point at
`system_id` itself. **The plan's own cold read found the block as scoped
would ship to zero playable nations** — FRA and DEU both prohibit a change to
the form of the state outright (Art. 89 §5, Art. 79(3)), and every nation the
mechanic is actually about (GBR, ESP, BEL, NLD, LUX) was `playable: false`.
Corrected before any code was written: the session became transition **and**
a third playable nation, the United Kingdom, chosen because its `ordinary_law`
amendment bar settles reachability by construction rather than needing a
sweep that could come back unshippable the way Germany's did.

A transition writes a **complete** institutional bundle — `system_id` plus
`formation_method`/`censure_rule`/`dissolution_rule`/`amendment_rule`/
`term_limit`/`head_of_state`, all at once — checked against the **target**
system rather than the systems the amendment is proposed under, the cross-
check `_validate_amendments()` had to invert. A new template field,
`allowed_head_of_state_kinds`, makes the head-of-state write checkable the
same way. A seventh per-nation dispatch field,
`government.amendment.permits_system_change`, gates the whole mechanic —
France, Germany, Italy and Austria each entrench their form of state and
carry `false`.

**The restoration-direction reachability sweep needed widening mid-plan, the
same way V1.2c's Germany sweep needed sharpening.** Measured against only
GBR's actually-formed government, the ceiling was exactly that coalition's
own seat share (0.560) — below `parliamentary_republic`'s real `two_thirds`
(0.667). Widened to every 1–3-party coalition, matching the Germany sweep's
own method, the true ceiling is 0.680 — reachable, with a 1.3pp margin.
`restore_the_monarchy` shipped on the strength of the wider sweep. Full
account, including why the block earned its own session for a different
reason than the roadmap originally gave: [[transition-model]].

### V1.2c — constitutional amendment (shipped)

[docs/tiers/v1.md](docs/tiers/v1.md) §2's next item after V1.2b built the
templates it constrains. An amendment is [[legislature-model|the existing law
pipeline]] plus three additions — `constitutional: true`, a `systems` filter,
and a new `effects.institutional` channel that **sets** an institution rather
than nudging it, the only channel in the model that does. Everything else
(preconditions, cooldowns, seat-level vote resolution, the rebellion split,
the forecast) is reused unchanged.

The threshold is a **sixth** per-nation dispatch-on-a-data-string field,
`government.amendment.rule`, constrained by the template's own
`allowed_amendment_rules` — real constitutional fractions researched per
nation (3/5 for France's Art. 89 Congress vote *and*, corrected from a
plan-time table error, Spain's Art. 167 ordinary revision path; 2/3 for
Germany, Italy, Austria, Belgium, Netherlands; **3/4** for Luxembourg's real
referendum-waiving bar, added as a fifth rule rather than rounded down to an
existing tier; an ordinary majority for the UK's uncodified constitution; a
declared-unresolved mandatory referendum for Switzerland, the same shape
`lose_condition: "never"` already gives it).

**The plan named a measurement to run before any content was authored, and it
changed the plan.** A live sweep of `spatial_support()`/`coalition_bonus()`
against each nation's real starting seats, cohesion and discipline found
France's real `three_fifths` clears with room to spare (0.660 achievable
against 0.600 needed) but Germany's real `two_thirds` is **unreachable even
at the best possible moment in a term** (0.519 achievable against 0.667
needed) — the unmodelled Bundesrat co-requirement stacked on six-party
fragmentation. The response, decided rather than tuned around: Germany keeps
its real threshold, and no amendment content this session names
`parliamentary_republic` in its `systems` list. A named trigger — an
upper-house model or a grand-coalition start scenario — could raise the
ceiling later; until then the mechanic is honestly unshipped there rather
than shipped against a nation that can never pass it.

Also new: the load-bearing template cross-check V1.2b built for a nation's
*flat* fields now runs for every value a constitutional amendment could ever
*write* — a violating amendment fails to load, the same discipline a bad
nation file already gets. Article 49.3 cannot force a constitutional
amendment through, matching the real Article 89 procedure's lack of an
executive bypass. `SAVE_VERSION` 6 → 7 for `amendment_rule`, which — unlike
every other V1.2b institutional field — is itself mutable at runtime.

Full account: [[amendment-model]]. Content is
[docs/tiers/v1.md](docs/tiers/v1.md) §2.

### V1.2b — political system templates, head of state, term limits (shipped)

[docs/tiers/v1.md](docs/tiers/v1.md) §2's headline feature, built once there
was a working institutional layer to generalise. Most of what a template would
declare, nations already declared flat — `formation.method`, `censure`,
`dissolution.rule`, `election.system` — so the template earns its keep only on
what nations could not express before: the **head of state** (five
constitutional monarchies now say so, where nothing did before), a **named
lose condition** (`elections.gd`'s run-ending branch was dispatched on the
structural flag `has_executive`; now on `lose_condition`), and an **enforced
term limit** (France's two-term rule; `terms_served` had been tracked and read
by nothing).

The template is a **constraint, not a defaults table** — no inheritance, no
override resolution, so there is nowhere for a half-understood institutional
state to come from. `data_loader.gd` fails at startup if a nation's flat
formation/censure/dissolution value falls outside its declared template's
allowed set, which is what makes the template load-bearing rather than
decorative. Four templates, matching the roster
(`semi_presidential_republic` FRA, `parliamentary_republic` DEU/ITA/AUT,
`constitutional_monarchy` GBR/ESP/BEL/NLD/LUX, `directorial_republic` CHE) —
§2's other two named templates, absolute monarchy and one-party state, have no
nation in a ten-nation Western European roster to attach to, and are deferred
with a named trigger rather than authored unattached.

Enforcing France's term limit found a real collision with the balance
harness's long-horizon check, and a real (not a bug) divergence along the way:
moving that check to Germany, as planned, found that a do-nothing German
budget does not survive three elections either — the chancellor's party
erodes under 50% and loses "largest party" status by the second one, a
previously-measured France/Germany divergence surfacing again in a new place.
Full account: [[political-systems]].

Content is [docs/tiers/v1.md](docs/tiers/v1.md) §2; the model is
[[political-systems]].

### V1.2a — a second playable nation (shipped)

**V1.1e is not next.** After V1.1d shipped, the user asked not to spend another
session deepening the French assembly: four sessions running (V1.1a–d) each added
another layer of institutional detail to one nation, which reads as narrowing.
The scope-alignment pass took that as settled and picked the breadth move
instead. V1.1e is still buildable and still in order — it is re-parked below, not
cancelled.

Why this one rather than diplomacy or the political-system templates: it was the
cheapest breadth per unit of work, because **the content already existed for ten
nations**. All ten had authored `data/nations/*.json` and `data/parties/*.json`,
a real electoral system, a real formation and censure rule (`DEU.json` carries
`"censure": "constructive_absolute"`), and V1.1c's dissolution rule as ten-nation
data. `GameState.new_game(loader, player_id)` was already parameterised; the only
hardcoded player nation under `src/` was `PLAYER_NATION_ID` in `src/ui/main.gd`
(now `main.gd`'s `pending_player_id`, set by the menu's nation-select panel,
defaulting to France only for a scene built directly rather than through it —
see [docs/decision-log.md](docs/decision-log.md)).
[docs/scope.md](docs/scope.md) already calls France-only "debt with a known due
date", and every further block adds more of it.

**Shipped.** Germany is playable, chosen for maximum institutional contrast with
France. The two shared things a second player nation made wrong:

- **`data/policy_defaults.json` was one file for every nation.** Retired —
  every nation's `fiscal` block now carries its own `tax_rates_pct`,
  `spending_pct_gdp` and `other_spending_pct_gdp`, sourced per nation with
  France as the anchor. See [docs/data-architecture.md](docs/data-architecture.md).
- **`opinion_constants.gd`'s bloc weights are one global table.** Stayed that
  way — a measured decision, not a restated assumption. See
  [docs/tiers/declined.md](docs/tiers/declined.md).

The nation-select screen is one list on the existing main menu, so it rode with
this block rather than triggering a U block. **U5 stays reserved** for the
dashboard tab V1.1d deferred.

Full account, including the roadmap-row correction and the mid-build fix to the
balance probe's extreme regimes: [docs/decision-log.md](docs/decision-log.md).
Content is in [docs/tiers/v1.md](docs/tiers/v1.md) §2; the models built so far
are [[government-model]], [[discipline-model]], [[dissolution-model]] and
[[cabinet-model]].

### Re-parked, still in order

| Block | Where it sits now |
|---|---|
| **V1.1e** Upper house and judiciary | Unchanged and unblocked. Deferred on a stated preference, not a dependency — pick it up when another France-institutions session is wanted. |
| **V1.1f** Referendums | Deferred toward V1.7, which brings campaigns. |

**`ns.term_months` says 60 while the first election is 41 months out** was found
in the U3 audit and fixed in V1.1c: `nation_state.gd`'s comment tying `term_months`
to the legislative block was the bug, not either clock — both numbers were always
right for their own schedule. See [[government-model|the two clocks]].

V1.1c left one thing on the table, recorded rather than quietly carried:

- **`INCUMBENT_SWING`.** Discipline erosion made the censure branch fire, but no
  regime that *wins* its presidential election ever gets unpopular enough to
  reach it — so censure is live for the sixteen months before May 2027 and not
  after. V1.1c's own measurement (a 57-seat spread in what a snap election
  returns, swept across the approval range a player can hold while still in
  office) found dissolution did not need this term touched, but that measured
  something different from sustained low-approval *survival*, which is still an
  [[election-model]] question and still the same lever cohabitation has been
  waiting on since V1.1a. Left as found; not this block's or the next one's
  problem unless one of them needs it.

---

## Per-session: plan, model, effort

**Plan first** asks whether the session should be designed in plan mode before any
code is written. The test is not size — it is **how expensive the decision is to
reverse**. A schema or a simulation model that turns out wrong is rewritten along
with everything that reads it. A map renderer that turns out wrong is rewritten
alone.

**Model and effort** follow the same logic. Opus 5 at high effort is for open
design judgement — deciding what the model *should be* when several plausible
answers exist. Sonnet 5 at low or medium effort is for executing a decision that
is already made, which is most sessions once the docs are written.

| Session | Plan first | Model | Effort | Why |
|---|---|---|---|---|
| V1.1c Dissolution | **Yes** *(corrected)* | Opus 5 to plan, Sonnet 5 to build | High → Medium | Originally logged **Light / Medium**, flagged in advance as known wrong — "reads the schedule schema [[electoral-systems]] already settled" assumed the dissolution rule was already in that schema; it was not, and adding it was S1 class. The cold count at plan time found thirteen surfaces: a ten-nation schema addition, six state fields plus a save-version bump, a new sim module, a tick change, two panels, five test files, two probe regimes, eight docs. Third correction on this table's own record; see [[decision-log]]. |
| V1.1d Cabinet | **Yes** *(corrected)* | Opus 5 to plan, Sonnet 5 to build | High → Medium | Logged **High → Medium** on "ministers are a schema that departments, opinion and events all read — S1 class." The cold count at plan time found ~fourteen surfaces against that reading — V1.1c's own thirteen, plus a new content class (named individuals) and a dashboard tab. **Corrected by cutting scope, not raising effort** — the first correction on this table's record to resolve that way rather than by moving to a higher tier: portfolio → party (not named individuals), loyalty → resignation only (not a second hostility() term), UI → the existing Government panel (not a new tab). Cut to eleven surfaces, Medium held. Fourth correction on this table's own record; see [[decision-log]]. |
| V1.1e Upper house | **Light** | Sonnet 5 | Medium | A second chamber is the existing vote resolution run twice with different composition. |
| V1.2a Second nation | **Yes** *(held)* | Opus 5 to plan, Sonnet 5 to build | High → Medium | Logged **High → Medium** on a scope-alignment-time count of roughly ten surfaces, with an explicit flag to challenge it cold and to treat the bloc-weight call as the thing that could blow the tier up to an S1-class schema session. The cold count at plan time found **sixteen**, not ten — two of the logged surfaces did not apply (no `SAVE_VERSION` bump; most `FRA` literals in `tests/` were intentional France-specific assertions, not things needing parameterising) against three the log missed (the tax-erosion reference, the loader's playable-count check, the balance probe's absolute-figure regimes). Bloc weights were measured rather than moved into data — see [[declined]] — which kept the tier at Medium rather than raising it. Fifth correction on this table's own record, and the second (after V1.1d) that held its tier once corrected rather than moving up or down; see [[decision-log]]. |
| V1.2b Political systems | **Yes** *(held)* | Opus 5 to plan, Sonnet 5 to build | High → Medium | Logged **Medium** on a plan-time count of seventeen surfaces — one above V1.2a's sixteen — on the reasoning that no new tuned constant and no new model needed deciding, only a fifth instance of a dispatch-on-a-data-string pattern already built four times. Held: the two open design questions (constraint vs defaults table, four templates vs §2's five) were resolved at plan time, and the one place a mechanical rename could have been a behaviour change — the lose-condition dispatch — was flagged in advance and caught nothing wrong, though a different collision surfaced instead (see below). Sixth correction on this table's own record, and the third that held its tier once corrected. |
| V1.2c Constitutional amendment | **Yes** *(held)* | Opus 5 to plan, Sonnet 5 to build | Medium | Logged **Medium** on a plan-time count of ~eighteen surfaces — one above V1.2b's seventeen — on the same reasoning: no new model, a sixth instance of the dispatch-on-a-data-string pattern, real constitutional fractions rather than tuned constants. Held, with one condition stated in advance rather than discovered: if the plan's own named reachability measurement came back showing an amendment unreachable for a playable nation, that was a model decision escalating to Opus, not a Sonnet tuning call. The measurement fired — Germany's real two-thirds is unreachable — and the build session's own response (leave the real threshold, author no content against it) matched the plan's stated response closely enough that no escalation was needed; the plan-time rough estimate itself needed a live-state re-measurement to sharpen from "marginal/erodes to unreachable" to "unreachable even at term start", and a table error (Spain grouped at two-thirds instead of its real three-fifths) surfaced during that same pass, before any content was authored against the wrong number. Seventh correction on this table's own record, and the fourth that held its tier once corrected. |
| V1.2e Start scenarios | **Yes** *(held)* | Opus 5, plan and build in one session | Medium | Logged **Medium** on a plan-time cold count of ~20 surfaces — between V1.2c's ~18 and V1.2d's ~21 — on the reasoning that a scenario adds one new value type, one new validator in a pattern built four times, and two optional sim arguments, with no new tuned constant and no new model. Held. Two things the count got right in advance: `new_game()`'s ~50 call sites made a defaulted third parameter mandatory rather than optional, and the coalition axis was cut at plan time rather than discovered mid-build. One thing it did not: the plan treated an authored `bloc_approval` as a single write, and it needed a second (`law_bloc_offset`) or the axis would have decayed to nothing inside a game year — found at design time from `INERTIA_RATE`, before content existed, which is the earliest any correction on this table has been caught. The plan's own named escalation trigger (the reachability sweep coming back too narrow) did **not** fire; a different measurement problem did, and the response the plan named for it — split the report rather than trust the first number — resolved it without escalating. Ninth correction on this table's own record, and the fifth that held its tier once corrected. |
| V1.2d System transition | **Yes** *(corrected)* | Opus 5, plan and build in one session | Medium | Logged **Medium** on a plan-time count of ~21 surfaces — three above V1.2c's ~eighteen, for the seventh dispatch-on-a-data-string field, the inverted target-side cross-check, and a new template field. **Corrected at plan time, not at build time**: a cold read of the scope found it would ship to zero playable nations, and the session's scope grew to include a third playable nation before any code was written — the eighth correction on this table's own record, and the first caught before the plan was even finalised rather than during or after the build. The plan's own named escalation trigger (a reachability sweep coming back unreachable) fired once, for restoration, and resolved by widening the sweep rather than escalating — the response the plan itself named in advance. |
| U5a The ruler's shell | **Yes** *(authored)* | Opus 5, plan and build in one session | Medium | **This table had no U-track row at all** — every entry on it is S-track, and U1–U4 shipped without one. Recorded because that is a different gap from the missing V1.3b row: V1.3b was a session the decomposition forgot to tier, whereas the U-track was never on this table in the first place, which quietly encoded that UI work does not need the discipline. It does: U2's and V1.1c's corrections are the two the preamble names, and U2 is a U block. The count came in at **~28** surfaces, above V1.2d's ~21 and below V1.3b's ~33. Medium rather than High on the reversibility test the preamble actually names — a layout that turns out wrong is rewritten alone, and no simulation model, tuned constant or save field is at risk. Held, with one flag stated in advance: the pinnable window manager is new machinery rather than a rearrangement and was the one place the estimate could break. It did not, because `window_frame.gd` was given no knowledge of any panel and the panels were not edited — every `setup()` and every signal connection survived the move from dock to window untouched. Two cuts were declared and both taken: the map's real treatment and the minimap went to U5b, the calendar and its roster to U6. What the count missed was smaller than any correction on this table and was caught by looking rather than reasoning: the map's opening zoom and the windows' maximum height were both wrong on a 1080p screen and both invisible to a headless suite. Twelfth correction on this table's own record, and the second (after V1.3b) to be an *addition* to it |
| V1.3b Trade: per-partner intensity and agreements | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **This table had no V1.3b row.** It stopped at V1.3a, so unlike every correction above this one is not a challenge to a logged estimate — it is an estimate authored at plan time with nothing to challenge, and the handoff convention's *read the row, count the surfaces yourself* had no row to read. Recorded because a missing row is a different failure from a wrong one, and the decomposition wrote per-session content and dependencies for all six without writing their tiers. The cold count came in at **~33 surfaces** — the largest on this table, eight above V1.3a's ~25, against V1.2d's ~21 and V1.2e's ~20. As with V1.3a the count is not what set the tier; the preamble's test is reversibility, and **both halves fire, the second for the first time in this block**: `w(A,B)` is schema-shaped with three downstream readers (c scales it, d reads it, e's interest function reads it), so a wrong weight function is rewritten with three sessions; and this is the first session to put **already-measured constants at risk** rather than add new ones, since every economy constant was tuned with this channel at zero and [[economy-model]]'s divergence argument had to be left standing. Held. Four cuts were declared in advance and the first was taken before any code: the separate `data/trade-agreements/` content type (terms ride the diplomatic action), then `economy_panel.gd`, a `Trade.tick_month()`, and a second agreement instance — the last three were not needed. Both named escalation triggers were GBR-shaped and stated before the model was built; **the first fired** and was resolved by the measurement it named rather than by escalating. Eleventh correction on this table's own record, and the first to be an *addition* to it. |
| V1.3a Relations and diplomatic actions | **Yes** | Opus 5, plan and build in one session | **High** | Logged **High** on a decomposition-time cold count of ~22 surfaces — one above V1.2d's ~21 — but the count is not what moves the tier. V1.2c, V1.2d and V1.2e each held Medium on the same stated reasoning: *no new model, no new tuned constant, an nth instance of a dispatch pattern already built n−1 times.* All three are false here. V1.3a is a new model (`docs/diplomacy-model.md`), new tuned constants (drift rate, action magnitudes), and the first state in the project that is neither per-nation nor global. What sets the tier is **reversibility**, which is the test this table's own preamble names: a pair-key schema that turns out wrong is rewritten along with everything V1.3b–f reads off it. The surfaces counted: `data/relations.json`, `src/core/relations.gd`, `data/diplomatic-actions/*.json`, `src/core/diplomatic_action.gd`, `src/sim/diplomacy.gd`, `src/sim/diplomacy_constants.gd`, `data_loader.gd` load plus cross-file validation, `GameState.relations` across `to_dict`/`from_dict`/`duplicate_state`, `SAVE_VERSION` 8 → 9 and `save_manager.gd`'s refusal path, `NationState` cooldowns and last-result, `main.gd`'s tick insertion, `nation_panel.gd`, `map_view.gd` colouring (the cut candidate), five test files, `tools/diplomacy_probe.gd`, and five docs. Counted by the **decomposition** session rather than by the one about to build — which by this table's own record is the estimate most likely to be wrong. Challenge it cold. **Challenged, and held.** The cold count at plan time came in at **~25**, three above the logged ~22, and High held on the reversibility test rather than on the count. Two of the logged surfaces were wrong in opposite directions: `data/relations.json` does not exist (starting values are derived, so it became ten `neighbours` arrays plus a mutuality check), and the `bloc_offset` rename logged as "nearly free" was ~30 edit sites across five code files, four test files and eight docs. Both cuts were named in advance; **the map-colouring cut was taken and the content cut was not** — four actions shipped, not three. The escalation trigger did not fire. Tenth correction on this table's own record, and the sixth that held its tier once corrected. |

> [!note] V1.2b's plan got a real collision wrong, and the build found it
> The plan assumed enforcing France's term limit could move the balance
> harness's long-horizon three-election survival check to Germany "unchanged
> from V1.2a's numbers." Running it found Germany's own do-nothing budget does
> not survive three elections either — a real, previously-measured divergence,
> not a bug. The build session caught this by running the harness rather than
> reasoning from the plan's own text, and rewrote the check to assert what its
> name actually promises. See [[political-systems]] and [[decision-log]].

Every V1.2+ block gets a plan, on Opus 5. By then there is enough built that
changes ripple.

> [!tip] These are starting points
> If a session marked Sonnet stalls — repeated failed attempts, a bug that will
> not localise — escalate to Opus rather than grinding. The cost of one wrong
> model choice is minutes; the cost of grinding is a session.

> [!note] The effort column has been wrong before, in one direction
> U3 is the counterexample: counted at plan time, Medium held. The count is the
> discipline, not the correction. S7 was written High → Low and built at Medium.
> The tell each time is the same:
> the estimate counted the headline artefact (fifteen law templates) and not the
> wiring around it (vote resolution, four effect channels, a third UI surface,
> two tests). When in doubt, count the surfaces the session has to touch, not the
> feature it is named after. See [[decision-log]].

## Session handoff

Every session runs in a **fresh chat**. Context from building S3 is dead weight
when starting S4, and a long session degrades before it ends.

That only works if the handoff is written down, so **the last thing every session
does, after the commit, is output a copy-ready prompt for the next one** — a
prompt, in a code block, ready to paste with nothing to edit.

### Keep it short, and put nothing in it that a doc already says

A handoff carries **only what is written nowhere else**: a gotcha, a rejected
approach, a version pin, a thing that surprised the session. If a line of it
restates [CLAUDE.md](CLAUDE.md) or this file, delete the line — a prompt that
duplicates a document is a second copy that drifts, and the copy is the one that
will be believed.

Anything load-bearing enough to want in the prompt belongs in a doc **instead**.
Write it there, and let the prompt say which doc to read.

Past **fifteen lines**, the surplus is duplication. Treat the length as the test.

The prompt contains:

- Which session, and the instruction to do that one only.
- Which docs to read first.
- What is written nowhere else, if anything. Often nothing.
- The instruction to verify against that session's done-when list before claiming
  done, and to write the next handoff after the commit.

### The effort call belongs to the receiving session, not the handing-off one

The prompt does **not** argue the plan / model / effort row. It says: *read the
row, count the surfaces yourself, challenge it before accepting it.*

This is not a preference, it is what the record shows. The effort column has been
corrected twice, and **both corrections came from the session about to do the
work, reading the row cold at plan time** — U2's, and V1.1c's. Neither came from
the handoff that preceded it, and the preceding session shipped both times
without noticing. A session writing its own successor's estimate is doing it at
the point of worst context degradation, on the subject it is least able to be
objective about.

> [!tip] A cold read is worth buying before a plan-first session
> Both catches above came from a fresh chat that had built nothing and read the
> repo from scratch. Before a session marked **Plan first: Yes**, a short
> throwaway chat that reads only the roadmap and the code and reports what the
> row misses costs little and has a hit rate of two for two. Not worth it
> routinely.

If the handoff prompt is hard to write because the session ended in a messy
state, that is the signal — finish or revert the mess before writing it, not
after.

---

## V1.2 onward

Deliberately coarse. These are not broken into sessions until the block before
them is done, because the shape of each depends on what the previous one turns
out to need. Full detail in [docs/tiers/v1.md](docs/tiers/v1.md).

| Block | Rough content |
|---|---|
| **V1.2 Political systems** | ~~Additional playable nations **first**, then system templates as data, constitutional amendment, monarchy ↔ republic transitions, start scenarios~~ — **all shipped, block closed at V1.2e** |
| **V1.3 Diplomacy and trade** | ~~Relations, diplomatic actions, trade agreements, tariffs, sanctions, EU-shaped bloc, nation AI foreign policy, **defence as domestic politics**~~ — **decomposed into six sessions, V1.3a–f**, before any code. The table and the argument are under *Next* above |
| **V1.4 Companies** | Named fictional firms, subsidies, regulation, nationalisation, privatisation, bond markets |
| **V1.5 Society** | Media, scandals, unions, strikes, protests, corruption, demographics, migration, inequality |
| **V1.6 Economic depth** | Inflation, business cycle, tax brackets to a target of five taxes, sectoral investment, infrastructure — sector count stays at three |
| **V1.7 Campaigns** | Campaign phase, binding promises, electoral system choice, referendums |
| **V1.8 Events** | Data-defined events with preconditions, choices, consequences — last, on purpose, and re-argued rather than assumed |

Three of those cells changed in the scope-alignment pass rather than in a build
session. The arguments are in [docs/tiers/v1.md](docs/tiers/v1.md) and
[[decision-log]]; the short version is that defence is scheduled thin and only
where it has a counterparty, the economy's granularity numbers are now decided
rather than open, and Events stays last for a better reason than the one
originally written — with a named condition that would move it.

### Two dashboard tabs waiting on a model

Neither exists, and neither gets a tab until it has something behind it. Recorded
here so the omission is a decision rather than an oversight.

| Tab | Blocked on | Today |
|---|---|---|
| **Military** | **V1.3f** specifically, now that V1.3 is decomposed — capability, deployments, alliance obligations. No longer an open-ended "no model exists", and no longer a whole block away: it is one named session, and the tab is that session's own UI call | One `defence` spending line under Budget, its opinion issue, and a Defence portfolio |
| **Demographics** | V1.5 — ageing, migration, inequality | One field, `population`, under Economy |

Both are cheaper than they were: U5a replaced the tab rail with four themed
clusters and a sub-row, so neither needs a bar redesign. A new surface is one
`register()` in `main.gd` and one line in `_build_action_bar()`'s list.

### U5b and U6 — the two sessions U5a split off

Both were part of the same request and are scheduled rather than parked.

| Session | Content |
|---|---|
| **U5b** The map | A world satellite raster (NASA Blue Marble is public domain and equirectangular, which is already `map_view.gd`'s projection, so it drops onto the existing transform), Natural Earth world borders, map layer colouring by relations and trade weight, the minimap in the slot `clock_cluster.gd` already reserves at its final size, nation labels. Non-simulated countries render from the texture and are **not clickable** — no hover, no cursor change, so the edge of the game is visible without a click that leads nowhere. This is the repo's first large binary asset and needs a provenance line in [[data-sources]] under the same rule the at-icons exception already states |
| **U6** The calendar and the people | An appointment is a **scheduling skin over the verbs that already exist** — a meeting *is* a diplomatic action or a law proposal, booked to a date and costing days of the player's time. No new effect channel. What it does need is the roster: politicians, celebrities, journalists, business, foreign leaders, which means **named individuals**, the thing [[cabinet-model|V1.1d]] deferred on purpose, plus the banned-names check and a `SAVE_VERSION` bump. S-track, not U — the surface is the easy half |

Beyond V1: [docs/tiers/someday.md](docs/tiers/someday.md), not scheduled, and
[docs/tiers/declined.md](docs/tiers/declined.md), decided against with a route
back.
