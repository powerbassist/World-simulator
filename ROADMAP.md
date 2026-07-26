# Roadmap

Build order for Nation Simulator. Short, scoped sessions — **one clear objective
each**, git commit at every session boundary.

This document is **forward-looking**. What shipped is one line each in the table
below; the corrections made along the way are in [[decision-log]]; the models are
in the model notes.

Scope reference: [docs/scope.md](docs/scope.md) · [docs/tiers/mvp.md](docs/tiers/mvp.md) · [docs/tiers/v1.md](docs/tiers/v1.md)
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

MVP done-when checklist: [docs/tiers/mvp.md](docs/tiers/mvp.md). All boxes ticked.

---

## Next

| # | Track | Block | Depends on |
|---|---|---|---|
| **U2** | UI | Dashboard shell | U1 |
| **U3** | UI | Tab content and hierarchy | U2 |
| **U4** | UI | Decision deltas | U2 |
| **V1.1b** | Sim | Party discipline and rebellions | V1.1a |
| **V1.1c** | Sim | Dissolution and snap elections | V1.1a, V1.1b |
| **V1.1d** | Sim | Cabinet and ministers | V1.1a |
| **V1.1e** | Sim | Upper house and judiciary | — |

V1.1f referendums is deferred toward V1.7, which brings campaigns.

The U-track goes first because every system session currently ends by bolting one
more overlay and one more keybind onto a scheme that is already at its limit.
Doing the shell now makes V1.1b–e cheaper, not more expensive.

### U2 — Dashboard shell

**Goal:** the game has a frame, and panels live inside it instead of floating
over it.

**Scope:** a persistent **top bar** — date, pause and speed control, and the four
headline figures — replacing the five-line HUD `Label`. A persistent **left tab
rail**: Overview · Economy · Budget · Politics · Society · Legislature · Europe.
The seven existing panels are re-hosted as docked tabs with their **content
unchanged**; the map becomes the Europe tab instead of a full-screen background.
Existing keybinds survive as shortcuts. Modals are kept for things that are
genuinely modal — election results, censure motions, confirmations.

**Done when:**
- Every panel that opened with a keypress before opens as a tab, showing the same
  figures, refreshing on the same monthly tick.
- No panel floats over the map any more, and no full-rect holder blocks input.
- The top bar's figures update every tick without opening anything.
- The existing panel tests still pass, unmodified where possible.

`feat: dashboard shell with top bar and tab rail`

> [!note] Install `frontend-design` before this one
> `npx skills add anthropics/skills@frontend-design -g -y`. It is web-oriented,
> so its hierarchy, density and spacing principles transfer to Godot `Control`
> and its concrete output does not.

### U3 — Tab content and hierarchy

**Goal:** density with hierarchy, not a wall of numbers.

**Scope:** per-tab content pass. The Overview tab is the hierarchy answer: not
every figure, but government standing, months to the next election, the two
highest-salience issues with their satisfaction, the worst-trending figure, and
recent deltas. A theme resource, so panel styling stops being a `StyleBoxFlat`
built by hand in two places.

**Done when:**
- Overview answers "what matters most right now" without the player opening
  another tab.
- No tab is a flat list of every field its system owns.
- Panel styling comes from one theme, not from per-panel overrides.

### U4 — Decision deltas

**Goal:** you can tell what your last decision actually did.

**Scope:** committing a budget change or passing a law surfaces its effect
immediately — `approval −3%, deficit +€2B` — and appends to a recent-effects list
on Overview. Cheap, because `Budget.project()` and `GameState.history[]` already
compute both sides of the comparison.

**Done when:**
- Every player command produces a visible delta within one tick of committing it.
- The delta matches what the history entries show a month later.

### V1.1b–e

Not broken into scope and done-when lists until U2–U4 are done, because the shape
of each depends on the frame they will be displayed in. Content is in
[docs/tiers/v1.md](docs/tiers/v1.md); the model built so far is
[[government-model]].

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
| U2 Dashboard shell | **Yes** | Opus 5 to plan, Sonnet 5 to build | High → Medium | The frame every later UI session builds inside, and the last cheap moment to get the navigation model right. The re-hosting itself is mechanical. |
| U3 Tab content | **Light** | Opus 5 | Medium | "What matters most right now" is a design judgement with no obviously right answer; the rest is layout. |
| U4 Decision deltas | **No** | Sonnet 5 | Low | Small and fully specified. The numbers already exist on both sides. |
| V1.1b Party discipline | **Yes** | Opus 5 | High | A model decision coupled to the existing coalition arithmetic, with no obviously right answer — the S5 class. |
| V1.1c Dissolution | **Light** | Opus 5 to plan, Sonnet 5 to build | Medium | Reads the schedule schema [[electoral-systems]] already settled; the gamble's payoff curve is the real decision. |
| V1.1d Cabinet | **Yes** | Opus 5 to plan, Sonnet 5 to build | High → Medium | Ministers are a schema that departments, opinion and events all read — S1 class. |
| V1.1e Upper house | **Light** | Sonnet 5 | Medium | A second chamber is the existing vote resolution run twice with different composition. |

Every V1.2+ block gets a plan, on Opus 5. By then there is enough built that
changes ripple.

> [!tip] These are starting points
> If a session marked Sonnet stalls — repeated failed attempts, a bug that will
> not localise — escalate to Opus rather than grinding. The cost of one wrong
> model choice is minutes; the cost of grinding is a session.

> [!note] The effort column has been wrong before, in one direction
> S7 was written High → Low and built at Medium. The tell each time is the same:
> the estimate counted the headline artefact (fifteen law templates) and not the
> wiring around it (vote resolution, four effect channels, a third UI surface,
> two tests). When in doubt, count the surfaces the session has to touch, not the
> feature it is named after. See [[decision-log]].

## Session handoff

Every session runs in a **fresh chat**. Context from building S3 is dead weight
when starting S4, and a long session degrades before it ends.

That only works if the handoff is written down, so **the last thing every session
does, after the commit, is output a copy-ready prompt for the next one.** Not a
summary — a prompt, in a code block, ready to paste into a new chat with nothing
to edit.

It must contain:

- Which session, and the instruction to do that one only.
- Which docs to read first.
- The plan / model / effort row from the table above, and the instruction to
  challenge it if it looks wrong.
- Anything the previous session learned that is **not** written in a doc or a
  commit — a gotcha, a rejected approach, a version pin. If it turns out to be
  load-bearing, it belongs in a doc instead, so write it there and link it.
- The instruction to verify against that session's done-when list before claiming
  done.

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
| **V1.2 Political systems** | System templates as data, constitutional amendment, monarchy ↔ republic transitions, additional playable nations |
| **V1.3 Diplomacy and trade** | Relations, diplomatic actions, trade agreements, tariffs, sanctions, EU-shaped bloc, nation AI foreign policy |
| **V1.4 Companies** | Named fictional firms, subsidies, regulation, nationalisation, privatisation, bond markets |
| **V1.5 Society** | Media, scandals, unions, strikes, protests, corruption, demographics, migration, inequality |
| **V1.6 Economic depth** | Inflation, business cycle, tax brackets, sectoral investment, infrastructure |
| **V1.7 Campaigns** | Campaign phase, binding promises, electoral system choice, referendums |
| **V1.8 Events** | Data-defined events with preconditions, choices, consequences — last, on purpose |

### Two dashboard tabs waiting on a model

Neither exists, and neither gets a tab until it has something behind it. Recorded
here so the omission is a decision rather than an oversight.

| Tab | Blocked on | Today |
|---|---|---|
| **Military** | No military model of any kind exists | One `defence` spending line, under Budget |
| **Demographics** | V1.5 — ageing, migration, inequality | One field, `population`, under Economy |

Beyond V1: [docs/tiers/someday.md](docs/tiers/someday.md). Not scheduled.
