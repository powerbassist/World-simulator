---
title: Decision Log
tags:
  - decision
  - process
---

# Decision Log

Corrections made *during* a session that changed what the [[ROADMAP]] said before
it. Kept out of the roadmap itself so that document stays forward-looking, and
kept at all because the pattern is the useful part: it shows which kinds of
estimate this project gets wrong, and in which direction.

Each entry names what the plan said, what was built instead, and where the full
argument lives. The models themselves are in the model notes — this is a record
of the *changes of mind*, not a second copy of the design.

## S4 — three economic sectors, not four

The roadmap said four sectors, the fourth being energy split out of industry.
[[data-sources]] then established that no open dataset provides the split, and no
MVP mechanic distinguishes energy from industry — energy mix is [[someday]] tier.

Corrected rather than honoured. If a later model wants an energy lever it splits
industry as a hand-tuned constant, against a concrete model instead of a
placeholder invented before one existed. Model: [[economy-model]].

## S6 — real per-nation election timing, not a five-year timer

Added on instruction partway through S6's plan. Each nation's term length,
election date and electoral system are real and authored, and European Parliament
elections exist alongside national ones.

This invalidated the roadmap's own reasoning for the session. "Light plan… seat
allocation is bookkeeping" assumed one term length and one allocation rule. Ten
real systems plus the EP made the schedule-and-system shape an S1-class **schema**
decision instead, since S7 laws, V1.1 coalitions and V1.2 political systems all
read it. Full argument: [[electoral-systems]]; the vote-share model is
[[election-model]].

## S7 — effort revised up, and two design calls

Effort was written High → Low. Planning at High held; the build was corrected to
**Medium**. It was not only the fifteen law templates: it was vote resolution,
four effect channels wired into three existing tick formulas, a third UI surface,
and two new headless tests — the same class of work S6 got Medium for.

Two calls made in the same session:

- Per-ideology-slot law support reads the **same two-axis space**
  [[election-model]] already puts every party on, rather than inventing a second
  vocabulary.
- The vote forecast is deliberately **blurred**, not exact. A party inside a band
  wider than the real vote's own threshold shows as Undecided — a display-layer
  trick with no sim-side randomness, the same shape [[opinion-model|polling noise]]
  and [[election-model|no election-day noise]] both argue for in their own cases.

Full argument: [[legislature-model]].

## V1.1a — two findings from planning government formation

- **The player's term was modelled as the Assembly's**, which made the first
  playable term 41 months instead of 16. Corrected in [[electoral-systems]].
- **A France-honest formation model necessarily contains the motion de censure**,
  because there is no investiture vote in France. So government formation and half
  of the confidence-vote work could not be separated into different sessions.

Full model: [[government-model]], including the honest note that the current
balance produces majorities stable enough that neither cohabitation nor censure
fires in a played game.

## U1 — the roadmap had no UI track at all

Found in the post-V1.1a audit. `ROADMAP.md` contained zero UI or UX work across
the entire MVP and V1 — presentation was assumed to fall out of each feature
session. What that produced by V1.1a: no main menu, no pause menu, no route out
of a running game, seven floating overlays each bound to a single keypress, a
five-line `Label` for a HUD, and no theme.

Two consequences, both acted on:

- The roadmap now runs **two interleaved tracks**, S (simulation) and U (UI), so
  presentation is schedulable rather than invisible.
- Four U blocks were scheduled ahead of the remaining V1.1 sub-projects, on the
  argument that every system session currently ends by bolting on one more
  overlay and one more keybind, so the rework only gets more expensive.

The same audit found two defects worth recording because both had been shipped
and neither was noticed: `SaveManager.save_game()` wrote straight to the live save
file, and the banned-names check had been failing since S2 on two substring false
positives caused by a missing `-w`. An always-red check is one nobody reads.

## U2 — effort corrected High → High at plan time, not mid-session

The roadmap wrote U2 as High → Medium. Corrected before any code was written,
by counting surfaces instead of the headline artefact: top bar, rail, dock host,
seven tab hosts, two new panels (Overview, Economy), a map re-host, a nation-panel
re-host, a modal layer that stays for four panels, seven keybinds retargeted plus
three added, focus order, and a new shell test. Eleven surfaces behind one line
in the roadmap table.

Same tell [[ROADMAP|the roadmap's own effort note]] already names for S7: the
estimate counted the thing the session is named after and not the wiring around
it. This is the second time the same pattern has produced a wrong effort call —
worth watching for at every future plan-first session, not just re-deriving from
scratch each time.

## U3 — the surface count that held, and three calls it forced

The roadmap wrote U3 as Light / Opus / Medium. Counted at plan time, as U2's
entry says to: two panel rewrites, one theme at two scene roots plus a top-bar
variation and a rail-button variation, four modals losing their hand-built
`StyleBoxFlat`, a new trend helper reading `history`, and three test files.
Roughly nine surfaces — the first plan-first session in three where the roadmap's
own estimate survived the count. **Medium was right.** The counting is still
worth doing; what it caught this time is that the estimate was fine.

It only held because of a scope call taken with it. The done-when line reads "no
tab is a flat list of every field its system owns", which literally means seven
tabs. Politics, Society, Legislature and Budget already group their content under
headings and grids — they are dense, not flat — so U3 rewrote **Overview and
Economy only**. Reading the line as "all seven" would have tripled the surfaces
and reproduced the S7 and U2 mistake from the opposite direction: not
underestimating the wiring, but inflating the scope to match a sentence.

Two smaller calls:

- **The theme is `src/ui/ui_theme.gd`, not a `.tres`.** A Theme resource is the
  engine-idiomatic answer and was rejected: it diffs badly, can only really be
  edited through the editor, and the repo has no other `.tres`. Built in code it
  matches the rule that panels are built in code, and a palette change is a
  one-line diff. What actually mattered was not the format but that a `Theme`
  assigned to a Control propagates to every descendant — that propagation is why
  one assignment per scene root replaces three hand-built styles.
- **Approval deltas are poll-against-poll.** `history` stores the true
  `overall_approval_pct`, so the obvious six-month delta would have quietly
  contradicted the polled figure printed beside it and leaked the real number's
  movement. `Trends.approval_delta()` runs both ends through `PollNoise`, and
  `tests/test_overview_panel.gd` advances months until the two round differently
  before asserting, so the check cannot pass by coincidence.

One thing found and **not** fixed, because it is a simulation question and U3
changed no simulation: on a fresh French game `ns.term_months` says 60 while
`next_election_*` is 41 months out, so an honest Overview would print "month 0 of
60" next to "41 months until the vote". The term-progress line was dropped rather
than shown. Whichever of the two figures is wrong belongs to a V1.1 session.

## V1.1b — the effort column held, and a term the plan did not contain

The roadmap wrote V1.1b as Plan / Opus / High. Counted at plan time as U2's entry
says to: two new `src/sim/` files, one `NationState` field across three
serialisation sites, a `SAVE_VERSION` bump, two readers plus a censure split in
`government.gd`, a support extraction plus a vote split plus two erosion sites in
`legislature.gd`, three readings in `law_panel.gd`, a column and two lines in
`government_panel.gd`, effective-majority reporting in the balance probe, one new
test and five updated, one new doc and six updated. Eleven surfaces. **High was
right** — the second plan-first session running where the estimate survived the
count, which is worth recording as much as the misses were.

The change of mind was inside the model, not the estimate.

**`hostility()` needed a term nobody had noticed was missing.** The session was
scoped to make discipline live and divisions seat-level, and the balance goal
agreed at plan time was to make the censure branch [[government-model]] records
as unreachable actually fire. Building it revealed that it could not: measured on
the authored French roster, the three governing parties sit 0.26, 0.32 and 0.36
from the coalition's agreed position, so their raw hostility is near −0.8 apiece,
and subtracting discipline only pushes it further down. **Eroding discipline from
0.85 to the floor moved the censure tally by zero seats** — 259 of 289 at every
value. The formation search builds coalitions out of parties that agree with the
government, so distance can never turn one against it.

Discipline had no route into the censure arithmetic at all. The fix is
`DISAFFECTION`: cohesion asks whether a party likes the *policy*, disaffection
asks whether its members want to be standing next to this government at the next
election, and only the second explains why coalitions collapse under unpopular
leaders. Gated on `(1 − discipline)` so it stays a discipline term rather than a
second parallel channel, and zero at or above neutral approval so the V1.1a
balance is untouched. Full argument, and the probe table it was tuned against,
in [[discipline-model]].

Worth generalising: **the tell was that a number refused to move, and the probe
was the thing that said so.** The plan's balance goal was written from a reading
of the model rather than from a measurement of it, and the reading was wrong. A
balance goal in a future plan should name the measurement that would confirm it.

One scope call taken with it: **no whip or concession command.** Rebellion's
counterplay is the lever set that already exists — which bills you propose, who
is in the coalition, and whether you force. Adding a costed command to suppress a
rebellion in the same session that invented rebellion would have been tuning two
things against each other with neither yet measured.

---

Related: [[index]] · [[ROADMAP]]
