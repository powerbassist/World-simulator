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

---

Related: [[index]] · [[ROADMAP]]
