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

---

Related: [[scope]] · [[mvp]] · [[v1]] · [[someday]] · [[out-of-scope-mvp]]
