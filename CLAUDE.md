# Nation Simulator

Single-player geopolitics and nation-management game. You are the President of
France: budget, laws, an assembly that need not agree with you, and an election
at the end of the term. Ten European nations, 2D map, dense UI panels.

Design vault is `docs/` — open **the project root** as the Obsidian vault, not
`docs/`, or the `[[ROADMAP]]` links do not resolve. Start at [docs/index.md](docs/index.md).

## Stack

- **Godot 4.7.1-stable**, non-Mono. Pinned in `project.godot` (`config/features="4.7"`).
  Bump deliberately and re-run the tests before committing the bump.
- **GDScript with static typing** (`var gdp: float`). C# stays available as an
  escape hatch for a hot loop a profiler actually found — not preemptively.
- No database and no autoloads in the game code. Third-party addons are
  editor-side and gitignored by default; `src/` may reference an addon file
  **only if that file is committed** — see `.gitignore`. JSON content, JSON saves.

## Commands

```bash
bash tools/run_tests.sh
```

```bash
bash tools/check_names.sh
```

```bash
godot --path "<repo>"
```

Single test: `godot --headless --script res://tests/test_<name>.gd`.
`tools/` is dev-only and never ships.

## Architecture — three rules, from [docs/engine-decision.md](docs/engine-decision.md)

1. **Content lives in data, not code.** There is never an `if nation_id == "FRA"`
   anywhere. A nation that behaves differently has a field saying so, read by a
   general rule. Adding a law or a party is a `data/` edit.
2. **One-way dependencies: `data → sim → ui`.** `src/sim/` never knows the UI
   exists — no `get_node()`, no signals into scenes. The UI reads `GameState` and
   never writes it; player intent goes back as an explicit command
   (`Budget.commit()` is the model). The test of this rule is that a full
   ten-year run works headless with no scene tree.
3. **One system, one module, one clear job.** A narrow public surface, usually a
   `tick_month()` and a few queries. Systems talk through `GameState`, never to
   each other. A file past a few hundred lines is doing two jobs — split it then.

Deliberately absent: DI container, event bus, abstract base classes for a single
implementation, plugin architecture.

```
data/     static content, read once at startup, never mutated
          (nations, parties, laws, political-systems, scenarios, geo)
src/core/ game state, clock, save/load, data loader, value types
src/sim/  one file per system, no UI knowledge
src/ui/   scenes and panels, read-only over sim state
tools/    import scripts and checks, not shipped
tests/    headless
```

## Style

- Panels are built in code in `_ready()`, not in `.tscn` files. Two scenes exist:
  `src/ui/menu.tscn` (entry point) and `src/ui/main.tscn` (the game).
- Comments explain **why**, not what — a rejected alternative, a non-obvious
  invariant, the reason a number is that number. Match the existing density.
- Tuning constants live in `src/sim/*_constants.gd`, not inline.
- New simulation behaviour needs a headless test. New UI behaviour that can fail
  silently needs one too — most U1 bugs this session were silent.

## Gotchas

Both confirmed on 4.7.1 and written up in [docs/engine-decision.md](docs/engine-decision.md):

- **A class cannot reference its own `class_name` on first run**, before
  `.godot/global_script_class_cache.cfg` exists. Use bare `new()` for
  self-instantiation; use `const Foo = preload(...)` for cross-file references.
- **A `Control` outside the scene tree is half-dead.** `_ready()` has not run, so
  everything it builds is `null`, and `Range.value_changed` does not emit.
  Configure a panel *after* `add_child()`, and drive UI tests a frame at a time
  with `extends SceneTree` + `func _process(delta) -> bool`.
- **A new `.gd` gets no `.uid` until something imports it.** `--headless
  --script` runs the file without generating one, so a session that only runs
  the tests commits scripts whose siblings all have a `.uid` and whose own is
  missing — U5b did, and paid for it with a follow-up commit. Run `godot --path
  "<repo>" --headless --import` once before `git add`, and check that every new
  script has its pair.

## Current focus

**U5a shipped the ruler's shell, U5b the world map and U5c its layers,
interrupting the S-track queue on request.** The map is the background, not a
tab; `dashboard.gd` and its rail are deleted; the panels are pinnable floating
windows.

**U5b made the map a map of the world.** Four layers back to front: the NASA Blue
Marble raster, the outlines of ~160 countries the game does not simulate, the ten
it does at `LAND_ALPHA` over the photograph, and labels for those ten only. A
non-simulated country is unclickable **structurally** — `_nation_at_lonlat()`
iterates `_polygons` and world geometry lives in a separate `_world_polygons`, so
there is no filter anywhere that could be forgotten. `MIN_ZOOM` stopped being a
constant and became `min_zoom()`, the cover fit, so the furthest zoom out is
exactly the whole planet on any window size; `_clamp_pan()` is new and keeps the
world under the viewport, which nothing needed before there was anything out
there to leave. The minimap fills the slot `clock_cluster.gd` reserved a session
early, and `tests/test_minimap.gd` asserts the cluster did **not** grow — that,
not the minimap's presence, is what the reservation was for.

**U5c made the ten coloured by what the player has with them.**
`src/ui/map_layers.gd` is the only place a roster fill is chosen, and it is a
**registry, not a mode flag** — three layers today (political, relations, trade)
and a fourth is one `LAYERS` entry plus one branch in `_value()`/`ramp()`, which
is what let U5c run *before* V1.3c rather than after it as planned. Three calls:
the **viewer is always the player**, because the symmetric-vs-directed asymmetry
is about what a readout may claim (`FRA–DEU 68` names the pair; a trade share
never claims the partner's side) rather than about whose seat you sit in;
**alpha is per-layer** and `LAND_ALPHA`'s 0.20 is *not* inherited, since U5b's
0.42-goes-grey finding is about a ramp with no hue variation; and **both ramps
are anchored on measured values** — relations on
[docs/diplomacy-model.md](docs/diplomacy-model.md)'s resting tiers over a 40–72
domain, not the nominal 0–100, and trade mid-anchored on an even ninth. Hover
moved from the fill to the stroke: lifting a fill toward the accent is the one
place in this interface where pointing at a number would change it.

**U6** is the one named successor left (the calendar, as a scheduling skin over
existing verbs, plus the named-individual roster V1.1d deferred). It does not
block V1.3c.

`assets/map/blue_marble_5400x2700.jpg` is the repo's first large binary, 2.5 MB,
public domain, provenance in [docs/data-sources.md](docs/data-sources.md). It is
read as **bytes** and decoded in memory — never `load()` — for the same
fresh-clone reason as the fonts and icons, and it carries a committed
`.jpg.import` with `importer="keep"`, without which Godot spends ten minutes
VRAM-compressing 14.6 megapixels nothing reads on every run with no `.godot/`.
World borders are Natural Earth **1:110m** in `data/geo/world.geojson`; the
roster stays 1:50m in `europe.geojson`, and `build_world()` excludes the ten so
nothing is drawn twice.

**`tools/screenshot.gd` exists now, and a UI session that does not run it is not
finished — and V1.3g found the bug in the tool itself.** Every setup flag writes sim
state behind panels that have already refreshed, and hiding a window frame does
**not** clear the child panel's own `visible`, so each panel spent its one dirty
refresh on frame 1 and never rebuilt: `--defence --open budget` printed an em dash
against a live 0.498 bill, and every state-mutating flag since `--coerce` had been
capturing pre-mutation figures. The tool now marks panels dirty in `main.gd`'s own
idiom, and `_apply_view()` runs four frames before the capture rather than one. `--headless` draws nothing, so a green suite says nothing about
layout; U5a shipped two bugs invisible to one, and U5c's ramp was wrong at the
warm end until a frame was looked at. It saves a PNG of the running game — run it
windowed, not headless — and takes `--layer`, `--hover`, (U6a) `--book` and (V1.3c) `--coerce`,
so every map layer can be captured with something actually on it. That last flag
exists because a frame of an all-zero data layer proves nothing about its ramp,
which is the one claim a screenshot is there to check. V1.3d added `--bloc` on the
same argument — a new game's council is empty and a frame of three "None" captions
proves nothing — and a generic `--open <window id>`. It earned its keep twice in
one session: the bloc panel was printing `deficit_pct_gdp <= 3.0` at a player, and
its own budget section fell below the fold.

**V1.3 is decomposed into six sessions, V1.3a–f. V1.3a and V1.3b are built.**
The argument, the four calls it made, and the per-session table are in
[ROADMAP.md](ROADMAP.md); [docs/tiers/v1.md](docs/tiers/v1.md) §3 tags every
bullet with the session that builds it. Order: (a) relations and diplomatic
actions, (b) trade intensity and agreements, (c) tariffs and sanctions, (d) the
bloc, (e) AI foreign policy, (f) defence.

**V1.3a shipped the schema everything b–f reads.** Relations are pair state on
`GameState.relations`, **symmetric**, keyed `"DEU|FRA"` by `src/core/relations.gd`
— the only thing allowed to build a key — and derived at start from EU
co-membership and `government.neighbours`. The counterparty response is a
**declared stopgap** V1.3e replaces, asserted as such in `tests/test_diplomacy.gd`.
The model, every constant, and the measured tables are
[docs/diplomacy-model.md](docs/diplomacy-model.md).

**V1.3b made external demand directed.** `src/sim/trade.gd` derives a per-viewer
weight over the other nine from partner size, EU co-membership, a shared border
and the pair's relations; `Economy.neighbour_weighted_growth()` is retired.
`GameState.agreements` is the second piece of pair state, on the same key, written
only by `Diplomacy.execute()` through a third effect channel on the existing
diplomatic action — there is no `data/trade-agreements/`. **Relations move the
mix, only an agreement moves the level**, and that is a load-bearing call rather
than a detail: an openness *level* that responded to relations makes the free,
unpriced `state_visit` worth two permanent points of GDP. The model, both
escalation triggers, and the measured tables are
[docs/trade-model.md](docs/trade-model.md).

**V1.3c shipped coercion, on the project's first directed state.**
`GameState.measures` is keyed `"FRA>DEU"` by a second builder in
`src/core/relations.gd`, on a **different separator** so `other()` refuses a
directed key and `directed_parts()` refuses a symmetric one — the additive escape
hatch V1.3a named in advance, taken without touching a line of relations or
agreements, because a tariff and its retaliation are two acts where a
relationship and a contract are one. Tariffs and sanctions are one verb with two
prices on a fourth effect channel, `effects.measure`; there is no
`data/measures/`, for the same reason there is no `data/trade-agreements/`.

**Three things fall out of two constants rather than being authored**, and that
is the session's shape: a **real Laffer curve** (revenue is collected on the
trade that survives, so it peaks at severity 0.625 and falls after), the
protectionist trade-off (**revenue now, trend later** — the openness
counterfactual became "no agreements *and no measures*", so a tariff costs trend
through the channel V1.3b already measured), and the fact that **who you can hurt
is a different question from who matters to you** — damage scales with
`w(target → imposer)`, making FRA→LUX 12.1× LUX→FRA.

**The probe corrected the model twice before any content existed, which is the
whole case for measuring first.** An authored `tariff_rate_pct` was cut once
revenue came back exactly linear in it — one intensity written twice — and
cutting it is what made the Laffer curve real rather than asserted. Then damage,
read off the *post-measure* weight, made every severity above the revenue peak
**strictly dominated**: less money and less harm for more trend loss. Damage now
reads `Trade.weights_before_measures()`, because you damage in proportion to the
trade you destroy and collect in proportion to what still crosses. The named
escalation trigger — being sanctioned is below the readable floor — **fired on
the first sweep and was resolved by that second correction** rather than by
touching `TRADE_BETA`. `COERCION_IMPULSE_MAX` was separately found *binding in
reachable play* at 4.0 and raised to 6.0, equal to `IMPULSE_MAX_PCT`. The model,
every constant and the measured tables are
[docs/coercion-model.md](docs/coercion-model.md).

**V1.3d shipped the bloc, and the fourth kind of live state.** `GameState.bloc`
is not per-nation, not a symmetric pair and not a directed pair — it is **one
object binding eight nations at once**, and mirroring it onto each member would
be the divergence the symmetric pair key exists to prevent, at a wider scale. A
proposal reaches the council, the members divide on `coalition_position` weighted
by the `ep_seats` `data/eu_parliament.json` already carried, and what carries
binds the player **whether or not they voted for it**. A rule does not refuse a
budget: comply and you pay in the policy you could not run, defy and you pay a
penalty on the budget line and a share of the national agenda. The model, every
constant and the measured tables are [docs/bloc-model.md](docs/bloc-model.md).

**The `ISSUE_KEYS` question three sessions deferred to V1.3d was answered yes**,
and the reasons are structural rather than thematic. `bloc_offset` never enters
`issue_salience`, so a Europe priced on it could never be named by the polling
panel's agenda list or by the election result screen — the two surfaces that
exist to say *why*. A split price never clears the ±3.0 noise floor in the
headline figure, and Europe divides by nature. And a flat offset cannot become
more **salient**, which is exactly what a rule biting hard should do. The cost
was measured before it was taken: every existing salience weight is scaled by
`1/(1+w)`, and the ratio S10's finding was about moves **+0.39 %**, in the safe
direction. `europe` takes 0.083 of the national agenda, fifth of twelve.

**The political map of Europe fell out of a table written at S5 for unrelated
reasons.** The opinion model has no signed split — every satisfaction reaches
every bloc with the same sign — so `europe` had to be one-signed and the division
had to come from elsewhere. Pensioners and rural weight `growth` at **nothing**,
so 37 % of the electorate takes the sovereignty cost and none of the single
market, while business weights `growth` 0.19 and `public_finances` 0.34 and takes
both. Nothing authored that.

**The probe corrected the model twice again, and a test caught a third.** Rule
severities summing to 1.35 against a ceiling of 1.0 made the fourth rule free to
break — V1.3c's strictly-dominated shape in a new place, fixed by rescaling to
exactly 1.0. `EUROPE_SCALE` at 1.00 cleared the noise floor by almost nothing and
was swept to 0.80, landing on the figure V1.3c measured for a full embargo. And
under a whole-council denominator **abstaining and opposing are the same act**,
so the threshold is a share of the seats *cast*. The council was also a
legislature the player controlled — six of seven proposals decided by France —
and the fix was **content, not a constant**: the members are clustered in ideology
space, so moving `common_defence_floor` to where a defence commitment actually
sits is what put a proposal beyond reach.

`SAVE_VERSION` is **11**, answering the assertion V1.3c left. The rule is
unchanged — *would a missing field read as something wrong?* — and three fields
fail it, the loud ones being `bloc_base_transfer_pct_gdp` (a France that never
paid into a budget it has always paid into) and `start_bloc_burden` (a game
reloaded while in breach scores the breach as new).

**The balance re-run is not bit-identical, and V1.3d said so in advance.** V1.3b's
and V1.3c's were, because an agreement and a measure each need a player command
and no regime issues one; the council meets whether or not the player engages.
That is the difference between a verb and an institution, and it is why this
session needed **no eleventh regime** where b and c each did. GDP, growth, trend
and unemployment are bit-identical in all thirty runs; exactly one run changed
outcome, on a two-seat censure margin.

**V1.3e shipped the interest model, and the row split.** All four declared
stopgaps are discharged — the counterparty *reaction*, its *decision*, its
*retaliation* and the council's *vote* — and all four mutation tests were watched
going red before being rewritten. The acting agent is now **V1.3f**; defence runs
to **V1.3g**. The split was taken on **machine count**, not on the surface count
the ROADMAP row named: that trigger (*a plan-time count above V1.3a's ~25*) had
already fired on V1.3b, V1.3c and V1.3d without any of them splitting.

**Interest is material; ideology is one weak term**, and that is the session's
central call. `tools/bloc_probe.gd` prints the eight non-player members clustered
in ideology space — economic spanning 0.87, social 1.13 — so a function resting on
`coalition_position` gives nine nations that behave alike, which is `trade.gd`'s
`GRAVITY_EXPONENT = 1.0` finding in a new place. The spine is the directed trade
weight instead. `src/sim/foreign_policy.gd` is a **pure read**: no `tick_month()`,
nothing on `NationState`, nothing new on `GameState`, so `SAVE_VERSION` stays at
**11** — which is what *no grievance ledger* buys, because the relations number
**is** the memory. The model, every constant and the measured tables are
[docs/foreign-policy-model.md](docs/foreign-policy-model.md).

**The probe corrected the model three times and a test caught a fourth**, which is
five sessions running. A globally-anchored amity read Britain's structural
detachment as hostility and closed agreements to it entirely (**0 of 9**);
anchoring sentiment on the pair's own resting value fixed it *and* cut a
double-count, since EU co-membership and the border were already inside the trade
weight. An ideology term commensurate with a rule's severity had every member in
breach of the deficit rule voting **for** it. `vote_reason()` named a cost term
that had lost by a factor of five. And **constructive abstention has a window
11 % of the range wide** that V1.3d never measured — it swept three columns where
four were needed, and got its own abstention property from the content by luck.

**`AGREEMENT_ACCEPT_MIN` and `SUPPORT_SIGMA` are deleted, not left unused**, along
with `bloc_probe.gd`'s sigma sweep — a tuned constant nothing reads is a number a
later session finds and reasons from.

**The screenshot pass earned its keep twice again**: every diplomatic action
button had fallen below the fold at a height unchanged since V1.3a, and a treaty
the partner would refuse rendered as a **live button** that refused silently —
V1.3b's own unread `refused_by_partner`, reappearing inside the session fixing it.
A fold is something the headless suite structurally cannot see: two of that
panel's labels autowrap, and with no layout pass an autowrapped label reports its
one-word-per-line height, so the assertion reads a 500px fold that is not there.
`tests/test_nation_panel.gd` says so rather than shipping a flaky check.

**The re-run is not bit-identical and could not be.** 15 of 30 runs move; every
large mover is GBR taking the bloc's `common_external_tariff` — a V1.3d feature
V1.3d's own re-run never fired, because the old council never adopted it inside
fourteen years. Exactly **one run of thirty changed outcome**, on a one-seat
margin. The re-run also caught a break the suite could not: `balance_probe.gd`
referenced the deleted constant and every new run failed to parse, because
`tools/` is excluded from `run_tests.sh` by design.

**V1.3f shipped the acting agent, and the block has no stopgaps left.**
`_tick_agenda()` lives in `diplomacy.gd` beside `_tick_retaliation()` — the
interest model preloads `trade.gd` preloads `coercion.gd` and can never reach
`available()` or `execute()`, so it **scores what it is handed** and Diplomacy
decides what to hand it. No new content type, no new effect channel, no new verb:
the agenda uses the ten actions `data/diplomatic-actions/` already ships, the
fifth session running. `SAVE_VERSION` is **12**, earned by exactly one of two
added fields — an absent `diplo_months_to_act` reads as 0 and 0 means *act now*,
so a reload fires nine acts in one month; an absent `foreign_acts` reads as
"nothing yet", which is correct. The test asserts **both** halves.

**Interest MULTIPLIES a bounded opportunity; it is never an addend, and that is
the session's central correction.** As a standing addend a partner's importance
made friendly acts free forever — every nation state-visiting its largest partner
on a loop, mean relations **79.6** against resting tiers of 45–68 and a pair on
the clamp. `AGENDA_AMITY_TARGET` closes the `deepen` term to exactly 0.0 once a
pair is warm enough, so the ratchet is structurally impossible rather than damped.
An inert act reads **exactly 0.0** for all ninety ordered pairs.

**The probe corrected the model four times and each correction is load-bearing.**
Free concessions get spent freely, so the agenda reads the action's **own
authored** `bloc_offset` as its domestic price — the content already said how hard
each act was and the nine were the only ones not listening. `third_party_effects()`
was **unbounded** (an uncapped `care/EVEN_SHARE` reaching 3.0 moved eight other
pairs harder than the act's own) and **backwards for friendly acts** (solidarity
said being nice to Germany cools everyone else toward Germany); both survived
V1.3e because only a player ever reached that function. And the `AGENDA_ACT_MIN`
sweep **measured the wrong state** — the static new-game table said 0.05, but by
month 24 Britain is everyone's top pick and the whole landscape has fallen under
the bar, so the world goes silent and Britain's turn never comes. GBR-aimed acts
**0 → 35** over fourteen years. Model notes:
[docs/foreign-policy-model.md](docs/foreign-policy-model.md) §7.

**The re-run was budgeted as a re-baseline and came back quieter than planned**:
6 of 30 runs differ, all GBR, all last-digit, **zero outcome changes**, FRA and
DEU bit-identical across all twenty. Relations move the trade *mix*, and the mix
reaches an economy only through partner deviations no balance regime produces.

`message_stack.gd` takes its first content since U5a built it as furniture, and
that spends nothing of V1.8's argument: an act by a simulated nation is state
`src/sim/` just wrote, not invented content. The sim writes
`GameState.foreign_acts`, the UI decides what earns a card, and
`tests/test_foreign_policy.gd` asserts **nothing in `src/sim/` reads it back** —
V1.3e's *no grievance ledger* property survives only if that stays true.

**V1.3g shipped defence, and the V1.3 block is complete.** `GameState.pacts` is
symmetric pair state on `relations.gd`'s existing key builder and
`GameState.deployments` is directed pair state on the one `measures` uses — **two
registers and no new *shape* of live state**, the first session since V1.3a to add
two and no kind. An alliance looks like a set and does not need to be stored as
one: `Defence.allies()` derives it, and the genuinely multilateral case already
exists as the bloc. Capability is a stock converging on the nation's own
`spending_pct_gdp["defence"]`, so **`has_budget` was not lifted** — all ten nations
already author that line, the nine's never moves, and `tests/test_defence.gd`
asserts their capability sits still for a full run rather than leaving it to a
comment. `SAVE_VERSION` is **13**.

**The obligation opens itself, and it is a LEVEL READ rather than an edge trigger.**
That was the design pass's correction and it is the session's sharpest call:
nothing in this project ever lifts a retaliation, so an obligation only the player
could close is a permanent monotone charge and `DEPLOYMENT_BILL_MAX_PCT_GDP` stops
being a guard rail — `IMPULSE_MAX` in a fifth place, avoided rather than found. The
player still cannot close one; only the aggressor lifting its measure, or
abandoning the pact, can.

**What the obligation fires on was authored by nobody.** The probe found the nine
**never coerce each other** — 168 months, no player, `state.measures` stays empty
and every recorded act is `state_visit` — so the only thing that reaches an ally
unprompted is the council's `common_external_tariff`. An alliance obligation
therefore fires on a pact held **outside** the bloc and never on one held inside
it: your pact with Britain bills you when Brussels turns on Britain. That is V1.3d
meeting V1.3g, and it is why the decomposition's "reads a, d" was right in a way it
could not have known.

**The probe corrected the model three times, seven sessions running**, and the
second correction moved what a constant is measured *against* rather than the
constant: `defence` is weighted **0.00 by five blocs of six**, so no value of
`DEPLOYMENT_OPINION_CHOSEN` can move the headline past the ±3.0 noise floor, and
raising it until one did would be tuning against an arithmetic impossibility. The
price is read on the rural row instead — V1.3a's own finding from the other
direction. The third correction was that the first opinion table measured **half
the price**, having set the load and not the bill that widens the deficit every
bloc *does* weight. `DEPLOYMENT_OBLIGED_MULT` was **decorative at 1.50** and is
1.75, solved off a measured slope. One deployment stays below the readable floor
and **cannot be lifted above it** — the value needed saturates two — which is a
structural bound recorded rather than traded against. Of five named triggers one
fired: GBR unable to ally, the sixth time in the block, fixed by a sweep that put
`PACT_ACCEPT_MIN` **below** the trade bar. The bill clamp was measured and found
**slack** (0.586 against 2.00), a first for this block. The model, every constant
and the measured tables are [docs/defence-model.md](docs/defence-model.md).

**The re-run is bit-identical across every shared regime**, which the plan did not
predict, and the probe explains it: `state_visit` wins **90 pairs of 90** on being
the only verb in `data/diplomatic-actions/` priced at exactly 0.000, so four new
verbs changed no AI choice. That is also the session's honest limitation — **the
four verbs are player content**; AI-to-AI pacts are reachable by the model and
unreachable by the agenda, and the fix is a security term in `_desire_parts()`,
which is a session rather than a constant. A **13th balance regime** was still
needed where V1.3d and V1.3f needed none: a pact is a verb, and no budget regime
issues a command.

**The screenshot pass earned its keep for the fifth session running, and this time
the bug was in the tool.** `--defence --open budget` showed an em dash against a
live 0.498 bill: hiding a window frame does **not** clear the child panel's own
`visible`, so every panel spends its one dirty refresh on frame 1 and never
rebuilds — meaning every state-mutating flag since `--coerce` had been capturing
pre-mutation figures and getting away with it. `screenshot.gd` now marks panels
dirty in `main.gd`'s own idiom. The nation panel's fold also reappeared one session
after V1.3e paid for it there, and **height alone could not fix it**: four verbs are
~136px against a ~886px ceiling, so it took 80px of height plus two tightenings.

**U6 split, and U6a shipped the president's diary.** The row counted **~40
surfaces and four machines** — the largest ever on this project — so it split on
machine count, V1.3e's trigger, cutting the half with the unmade content
decision exactly as U5b cut U5c. **U6b is the roster.**

**The session is judged on legibility, not on scarcity, and that is a
measurement rather than a preference.** Every observable here is
piecewise-constant across a month: `clock.gd` has emitted `day_advanced` since
the MVP and nothing in `src/sim/` has ever listened, so 14 March and 22 March
differ only in the label — which makes booking *as a replacement for acting* a
deferral that buys nothing, V1.3c's and V1.3d's strictly-dominated shape a third
time. So **booking is optional**, every verb keeps its act-now button, and
`tests/test_calendar.gd` asserts a booking moves nothing at the moment it is
made. What the diary shows instead is dated state the game has carried for
sessions with no surface anywhere: election day, the European election, the
presidential term, the council's next proposal and its pending vote, the
dissolution lockout, and every diplomatic and legislative cooldown expiry.

**The one tuned constant this session would have added was DELETED by its own
probe, which is a first.** A monthly budget of the player's days was swept
against a band fixed before the sweep ran, and the band is not mis-tuned but
**structurally unreachable**: the median month offers 27 legal acts asking 124
days, so every budget from 4 to 24 bound in **100 %** of months. A ceiling that
always binds is a cap, not an allocation. Deleted rather than left unused —
V1.3e's treatment of `AGREEMENT_ACCEPT_MIN` — so `src/sim/calendar_constants.gd`
carries **no tuned constant at all**. The reason is carried forward because it is
not about calendars: `available()` returns what is **legal** and nothing yet
models what the player **wants**, so any ceiling priced against legality always
binds. That gap is a session, not a constant.

**The probe corrected itself twice and a panel test found the third, which is
eight sessions running.** The fixed-date density table read a player who never
acts, so cooldowns — much the densest source — reported exactly **0**; and it
counted *after* the tick, so an election had already pushed its own date forward
and 168 months showed **one**. Both are V1.3f's measuring-the-wrong-state error,
in the file written to avoid it: 19.6 % → **31.0 %**. The third is sharper than
the average: a **new game's next twelve months are completely empty**, because
France's nearest dated event is sixteen months out and cooldowns do not exist
until the player has acted — so the page every player sees first is the page with
nothing on it. The pre-committed response to a thin diary was shape rather than a
constant (widening the horizon would have been the constant, since it also bounds
booking), so: a **twelve-month strip** rather than a month's page, a `later`
footer, and a `Next:` line outside the scroll.

**`src/sim/calendar.gd` preloads no other system, and the test reads the file to
say so.** `due()` returns entries as **data** and `main.gd` fires the verb —
`cabinet-model.md`'s orchestrator precedent one scale wider, and it cost **zero**
new preloads because `main.gd` already had all three. `_queue_effect()`'s U4
baseline moved from the button press to arrival, because a booking commits
nothing in the month it is made. `clock.gd` emits `month_elapsed` **before**
`day_advanced`, so a day-1 booking acts *after* that month's tick; `due()` reads
`<=` rather than `==`, so a save reloaded past a date still fires it.

**The re-run is bit-identical across all thirteen existing regimes, and a
fourteenth was needed for a reason V1.3g's was not.** `balance_probe.gd` and
`tests/test_balance.gd` are month loops with **no clock** — this harness has never
called `advance_one_day()` — so a day-resolution dispatch was structurally
invisible to all thirteen and their bit-identity would have meant nothing. The day
loop now runs for every regime; with an empty register it is one `is_empty()`
check.

**Booking does NOT go on `nation_panel.gd`, and the plan said it would.** Every
verb row there is an HBox holding an autowrapping summary label beside one button:
a second button narrows the label, the wrap grows the row, and that panel is at
860px against a ~886 ceiling having paid for that fold twice. Booking lives on the
diary alone. The **screenshot pass earned its keep for the sixth session running**
— `upcoming()` filtered to unfired entries, so the strip's own resolved-entry
styling was dead code and a kept appointment vanished from the diary. And
`tests/test_state_copy.gd` had a branch that had **never run**: its array probe
pushes a float sentinel, every copied Array had been untyped until now, and the
three `Array[Dictionary]` fields were all excluded for unrelated reasons — so it
reported "shared with the copy" for a field that is duplicated correctly.

**Next: U6b** — the named-individual roster, **political faces only** (foreign
leaders, party leaders, ministers). Each is the face of a target that already
exists, so *no new effect channel* stays literally true; a journalist has none,
and journalists, celebrities and business therefore belong to `docs/tiers/v1.md`
§4 and §5 with the mechanisms that give them something to do. The diary's entry
already carries an unread `person_id`, so U6b is additive.

MVP, V1.1a–d, V1.2a–e, V1.3a–g, U1–U5 and U6a are done. V1.1e (upper house and
judiciary) is re-parked, not cancelled. One piece of V1.2 work is deferred with
somewhere to point now: V1.2c authored no amendment content for
`parliamentary_republic` because Germany's two-thirds bar was unreachable, and
V1.2e's `deu_grand_coalition` start makes it reachable.

Save format is at **version 13**. There has never been a migration: a superseded
save is refused outright, because a half-understood political state is worse than
a clear refusal. The rule is not "a new field bumps" but "a missing field would
read as something wrong" — V1.2e added `GameState.scenario_id` **without** a bump
because an absent one reads as `""`, which is correct; V1.3a bumped because an
absent `relations` reads every pair as 0.0, which is the *worst possible*
relations rather than a neutral default. V1.3b is the sharpest case yet: neither
`agreements` nor the trade baselines earned it (one reads correctly as "nothing
signed", the other fails soft), and what did is `NationState.eu_member` and
`.neighbours` — absent, the trade weight silently collapses back to the aggregate
V1.3b replaced, so a reloaded game runs a *different model* from the one that
saved it. All three are checked in `tests/test_save_load.gd`, not argued in prose. **V1.3c
earned no bump and the test said so** — an absent `measures` reads as `{}`, which
is correct for every version-10 save because those games could not impose one —
and it left an assertion that the version was *still* 10 so a later session
raising it had to come and say why. **V1.3d is that session.** Three fields fail
the rule: an absent `bloc` register reads as a bloc with no rules, an absent
`bloc_base_transfer_pct_gdp` as a France that never paid into a budget it has
always paid into, and an absent `start_bloc_burden` as 0.0 against a live burden,
which mis-signs the `europe` issue for the rest of the run. **V1.3e adds no serialised field at
all**, and the test says why: both interest functions are pure reads over live
state, and the two things they write — `relations` and `measures` — were
serialised at V1.3a and V1.3c. That is a property rather than a coincidence, and
it is what *no grievance ledger* buys: the relations number **is** the memory, so
there is nothing for a save to carry. **V1.3g is the sharpest case on this list,
because one of its three fields falls on BOTH sides.** `military_capability` is the
bump: absent it reads 0.0 against a France that has spent 2 % of GDP on defence
since before the game started, the deployment cost divides by it so every
commitment jumps to the clamp, and `would_accept_pact()` reads the whole roster as
militarily worthless — a reloaded game running a *different model*, which is
`eu_member`/`neighbours` in its strongest form. `pacts` earns nothing, reading
correctly as "nothing signed" for every version-12 save. `deployments` **splits**:
the *obliged* half is re-derived on the next tick from `pacts` × `measures`, both
of which the save carries, and fails soft for one month the way
`trade_baseline_by_partner` does — while the *chosen* half is derivable from
nothing, so an absent register silently withdraws the player's own forces and drops
their bill with them. `tests/test_save_load.gd` asserts all four, and the split is
the assertion worth having rather than the bump: it **pins** the property that
obliged deployments are derived, so a later session making them stateful turns it
red and has to come and say why. **U6a adds one field and earns nothing, and what
it did NOT add is the interesting half**: `appointments` absent reads as "nothing
booked", correct for every version-13 save because those games could not book one
— `measures`' case exactly. `GameState.day` is not serialised at all, because
`save_manager.gd` already carries `clock.day` at the payload's top level and a
copy in `to_dict()` would be two records of one fact; the test asserts its
**absence**, which pins that property. And the field that *would* have earned a
bump — a spent-days counter, which reads 0 when absent and hands a save-scumming
player their month back — was never written, because the probe cut the currency it
counted first.

Styling rule since U3: colours and the type scale come from `ui_theme.gd`, set
per control with `theme_type_variation`. Never `add_theme_stylebox_override()` or
`add_theme_font_size_override()` in a panel — `tests/test_ui_theme.gd` fails on
it. Separation and margin constants stay at their call sites; they are layout.

**U5a retuned that theme and moved the shell around it.** The palette is deep
navy with a single **brass** accent, and the visual signature is one rule: a HUD
plate carries a 1px brass hairline on its **top edge only**. `test_ui_theme.gd`
asserts the other three edges stay bare — do not "tidy" it into
`set_border_width_all()`. `assets/fonts/` holds the repo's first committed
binaries (Barlow Condensed for chrome, IBM Plex Mono for figures, both SIL OFL);
they are loaded by a path that works before the editor has imported anything,
because `tools/run_tests.sh` runs headless from a fresh clone. Icons are read
and rasterised from `.svg` text for the same reason — never `load()` an at-icons
path.

The shell is: `map_view` full-rect at the back, `window_manager` over it, `hud`
on top. There is no tab rail. A panel is registered with
`_windows.register(id, title, panel)` **before** its `setup()` is called, because
`register()` is what puts it in the tree. Adding a surface is that one call plus
one line in `main.gd`'s `_build_action_bar()`.

## Workflow

One session, one objective, a fresh chat each time. Commit at every session
boundary, and end each session by writing the next one's handoff prompt — the
convention is in [ROADMAP.md](ROADMAP.md). Verify against the session's
done-when list before claiming done.
