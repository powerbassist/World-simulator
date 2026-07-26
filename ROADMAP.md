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

MVP done-when checklist: [docs/tiers/mvp.md](docs/tiers/mvp.md). All boxes ticked.

---

## Next

| # | Track | Block | Depends on |
|---|---|---|---|
| **V1.1c** | Sim | Dissolution and snap elections | V1.1a, V1.1b |
| **V1.1d** | Sim | Cabinet and ministers | V1.1a |
| **V1.1e** | Sim | Upper house and judiciary | — |

V1.1f referendums is deferred toward V1.7, which brings campaigns.

### V1.1c–e

Not broken into scope and done-when lists until the block before each is done,
because the shape of each depends on what the previous one turns out to need.
Content is in [docs/tiers/v1.md](docs/tiers/v1.md); the models built so far are
[[government-model]] and [[discipline-model]].

Two things V1.1b left on the table, both recorded rather than quietly carried:

- **`INCUMBENT_SWING`.** Discipline erosion made the censure branch fire, but no
  regime that *wins* its presidential election ever gets unpopular enough to
  reach it — so censure is live for the sixteen months before May 2027 and not
  after. Sustained low-approval survival is an [[election-model]] question, and
  it is the same lever cohabitation has been waiting on since V1.1a.
- **`ns.term_months` says 60 while the first election is 41 months out**, found in
  the U3 audit and still unfixed. Whichever figure is wrong, it belongs to a
  V1.1 session; V1.1b did not need it, because discipline's election-proximity
  term reads `next_election_year/month` directly.

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
