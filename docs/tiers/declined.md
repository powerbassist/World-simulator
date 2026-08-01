---
title: Declined
tags:
  - tier
  - scope
---

# Declined

> [!warning] Stronger than [[someday]]
> [[someday]] is a parking lot — good ideas that are simply not scheduled.
> This page is different: each entry was **considered and decided against**,
> with a reason. Re-proposing one costs an argument, not just a slot in the
> queue.

Every entry names what would **reopen** it, because a decision with no route
back is a prohibition, and none of these are prohibitions. If the reopening
condition arrives, the entry moves; until it does, a session that starts
building one is off-plan.

## Tourism as a sector or a revenue line

**Declined.** Tourism is inside `services`, which is one of the three sectors
[[economy-model]] already models.

Two reasons, and the second is the load-bearing one:

- No open dataset splits it out. [[data-sources]] seeds sector shares from World
  Bank value-added indicators (`NV.AGR`, `NV.IND`, `NV.SRV`) and there is no
  fourth series. Splitting means hand-authoring a share **per nation**, and
  [[scope|every nation becomes playable]] — so the authoring cost multiplies by
  the whole roster, forever, not by one.
- No mechanic would read it. The levers that make tourism interesting elsewhere
  — visa policy, exchange rates, cultural attractions, a reputation score
  visible to foreign publics — are all absent, and the first two are
  [[someday]] for independent reasons (France is in the eurozone).

**What would reopen it:** a scheduled mechanic that needs a sector to be visibly
hurt by a *diplomatic* rupture rather than an economic one, and that cannot be
expressed against `services`. Even then the S4 route applies first — split it as
a hand-tuned constant against a concrete model, never as a placeholder invented
before one exists.

## Energy as a fourth sector

**Declined at S4**, recorded here so the decision is findable from the tier docs
rather than only from [[decision-log]].

The roadmap originally said four sectors, the fourth being energy split out of
industry. [[data-sources]] then established that no open dataset provides the
split, and no mechanic distinguishes energy from industry — energy mix policy is
[[someday]].

**What would reopen it:** an energy-mix model concrete enough to say what the
split would *do*. Then industry splits by a hand-tuned constant, against that
model.

> [!note] The general rule these two share
> **Sector count scales with the nation roster; tax count does not.** Sector
> shares are per-nation content; tax parameters live in
> `src/sim/economy_constants.gd`, are authored once, and scale with nothing.
> That asymmetry is why [[v1|V1.6]] can name a target of five taxes while the
> sector count stays at three permanently.

## Difficulty and intensity as global multipliers

**Declined in that form.** A difficulty slider that scales tuned constants —
hostility, opinion sensitivity, economic volatility — is the standard answer and
is the wrong one here.

Every balance number in this project is **measured**, not asserted:
`tools/balance_probe.gd` and S10's ten regimes, V1.1b's discipline sweep, V1.1c's
57-seat dissolution spread, V1.1d's competence spread. A multiplier on top
invalidates each of those measurements and multiplies every future probe run by
the number of settings. The cost is not the slider; it is that the project's own
method stops working.

**Accepted instead: start scenarios**, in [[v1|V1.2]]. Vary the *starting state*
— debt, seat composition, approval, coalition — which is data, changes no tuned
constant, and needs no re-measurement because the simulation being measured is
unchanged. A political-system template plus a start state is already what makes
one nation play differently from another, so this is the same machinery pointed
at the same nation twice.

`src/ui/settings_panel.gd` says a screen of dead toggles advertises scope that
does not exist. Its "there is no difficulty" comment stays true on purpose.

**What would reopen it:** playtesting showing the difficulty *range* start
scenarios can reach is too narrow — that a scenario cannot be authored hard
enough or gentle enough. That is an empirical finding, not a preference, and
nothing weaker counts.

> [!note] Measured at [[ROADMAP|V1.2e]], and it did not fire
> The falsifier above was run rather than left standing, by
> `tools/scenario_probe.gd`, before any scenario content was finalised. Across
> the three playable nations the authorable envelope spans a **~40-point
> approval range** (50 → 10 by month 60, and two nations lose an election they
> otherwise hold), a **~120pp debt range**, and an amendment ceiling that moves
> by ±0.06 — enough to **flip reachability in both directions** (France loses a
> reachable amendment, Britain gains one). Not a narrow band.
>
> One axis nearly did fire, at design time rather than in play: an authored
> approval written only to `bloc_approval` decays back to neutral on a
> ~2.4-month half-life and is gone inside a game year, because every
> satisfaction term is a delta against the nation's own start. It is held at
> its target through the existing `bloc_offset` channel instead. Had that
> gone unnoticed, a third of this feature would have been decorative. See
> [[scenario-model]].

## Per-nation voter-bloc weights

**Declined at V1.2a**, when the named trigger — a second playable nation —
actually fired. Re-examined rather than restated: `opinion_constants.gd`'s
`BLOC_SIZE`, `BLOC_SALIENCE_BASE` and, by the same argument,
`election_constants.gd`'s `BLOC_TURNOUT` and `BLOC_IDEAL`, stay one global
table rather than becoming per-nation `data/` content.

Three reasons:

- **No source.** Per-nation salience is roughly 660 hand-invented numbers, with
  nothing in [[data-sources]] to author them from. Sourced-but-wrong is worse
  than honestly a model parameter — it reads as authority the numbers don't
  have.
- **Every tuned constant in [[opinion-model]] was measured against this one
  shared table.** `SALIENCE_GAIN = 5.0`, `DEFICIT_SCALE_PP = 6.0`, the whole
  `public_finances` row — `tools/balance_probe.gd` found each of these against
  a single bloc table. Ten tables means ten measurements, or nine tuned
  constants asserted rather than found.
- **A measurement, not an assumption, says the shared table isn't hiding the
  problem it looks like it might.** `balance_probe.gd`, parameterised by
  nation at V1.2a, ran the identical relative `managed` budget — cut defence,
  raise VAT, by the same percentage-point deltas from each nation's own start
  — against France and Germany. Germany's government lost its majority at its
  February 2029 legislative election; France held one through every election
  of the same fourteen-year run. That divergence comes entirely from
  authored, already-per-nation content: `chancellor_election` /
  `constructive_absolute` censure against `presidential_appointment` /
  `absolute_members`, a 5% `pr_national` threshold against `two_round`'s 0%,
  and two different party rosters — with the bloc table completely untouched.
  Two nations already play differently without it.

**What would reopen it:** a real source for per-nation bloc *size* specifically
— World Bank/Eurostat urban-share, 65+-share and tertiary-enrolment series
exist and could source `BLOC_SIZE` without inventing salience alongside it —
or a playtesting finding that two nations under the same relative policy feel
interchangeable, which the measurement above argues against but a third and
fourth playable nation could still show.

## LimboAI for nation AI foreign policy

**Declined at the [[ROADMAP|V1.3 decomposition]]**, when the plugin was
installed and evaluated for [[v1|V1.3e]] rather than dismissed unexamined.
LimboAI is behavior trees and hierarchical state machines for Godot 4, and it
is on disk at `addons/limboai/` (v1.8.0).

Four reasons, and the last two are the load-bearing ones:

- **Wrong problem shape.** Its own README describes the target as agents
  "characters, enemies" — per-frame reactive behaviour. V1.3e's problem is nine
  nations scoring an action list *once a month* from a numeric interest
  function. That is the same shape as `government.gd`'s coalition search and
  `legislature.gd`'s vote resolution, both of which are already plain scored
  search in `src/sim/` with no framework under them.
- **Engine version.** v1.8.0 states support for Godot **4.6**; this project
  pins **4.7.1**. A C++ GDExtension against a newer engine is a
  binary-compatibility bet, and the plugin is not currently enabled in
  `project.godot`.
- **It breaks [[engine-decision|Rule 2]].** Its runtime is Node/Resource-based
  and expects a Node agent. `src/sim/` is `RefCounted` with no scene tree *by
  rule*, and the test of that rule is a full ten-year run headless — which is
  also how `tools/run_tests.sh` runs.
- **It breaks the `.gitignore` contract.** `addons/*` is ignored with one
  documented exception, and `src/` may reference an addon file **only if that
  file is committed**. Using LimboAI from the simulation means committing
  per-platform native binaries for every export target — precisely the cost the
  exception's comment exists to refuse.

**What would reopen it:** V1.3e turning out to need *interruptible multi-month
plans* per nation — a negotiation a nation enters, suspends, abandons and
resumes across many ticks, where the resumption point is real state — **and** a
hand-rolled state machine in `src/sim/` crossing the few-hundred-line tripwire
[[engine-decision|Rule 3]] uses to say a file is doing two jobs. A monthly
re-score from current state needs neither, and that is the design V1.3e starts
from.

---

Related: [[scope]] · [[mvp]] · [[v1]] · [[someday]] · [[out-of-scope-mvp]]
