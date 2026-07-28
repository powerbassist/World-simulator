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

One track at a time per session. Interleaved, not parallel. U1–U4 are done, so
the queue below is S-track until a system session ends by needing a surface the
shell does not have.

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

MVP done-when checklist: [docs/tiers/mvp.md](docs/tiers/mvp.md). All boxes ticked.

---

## Next

Not yet scoped into a session. [docs/tiers/v1.md](docs/tiers/v1.md) §2's
remaining items — system transition, start scenarios — are next in the
written order, now that V1.2c built the amendment mechanism transition points
at. Per this document's own handoff convention below, the plan/model/effort
call belongs to the session that picks it up, read cold, not to this one.

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
| **V1.2 Political systems** | Additional playable nations **first**, then system templates as data, constitutional amendment, monarchy ↔ republic transitions, start scenarios |
| **V1.3 Diplomacy and trade** | Relations, diplomatic actions, trade agreements, tariffs, sanctions, EU-shaped bloc, nation AI foreign policy, **defence as domestic politics** |
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
| **Military** | V1.3's defence layer — capability, deployments, alliance obligations. No longer an open-ended "no model exists": the model is scheduled, thin, and named | One `defence` spending line under Budget, its opinion issue, and a Defence portfolio |
| **Demographics** | V1.5 — ageing, migration, inequality | One field, `population`, under Economy |

Beyond V1: [docs/tiers/someday.md](docs/tiers/someday.md), not scheduled, and
[docs/tiers/declined.md](docs/tiers/declined.md), decided against with a route
back.
