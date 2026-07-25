---
title: MVP
tags:
  - tier
  - scope
---

# MVP — Hard Definition

> [!important] The one-sentence test
> **You are the President of France. You have five years, a budget, an assembly that does not have to agree with you, and a population that is watching. Survive the next election.**
>
> If a feature is not needed to make that sentence true and playable, it is not in the MVP.

This is the smallest version that is genuinely a game rather than a simulation toy: it has a loop, a clock, meaningful choices with delayed consequences, and a way to lose.

## The loop

1. Time runs — day by day, pausable, speed-controllable.
2. Numbers move: economy grows or shrinks, unemployment shifts, debt accumulates.
3. Voter blocs react to the numbers and to what you did.
4. You act: change the budget, propose a law, let the assembly vote.
5. Polling tells you, imperfectly, how it is going.
6. Election. You keep the job or you do not.

Steps 1–5 repeat continuously. Step 6 is the wall the whole game is aimed at.

## What is in

### World
- **France, playable.** One nation the player controls.
- **Nine AI neighbours** as data and economic context: Germany, Italy, Spain, Belgium, Netherlands, Luxembourg, Switzerland, United Kingdom, Austria. They have real starting statistics and their economies evolve, which affects French trade and growth. They do not negotiate — see [[out-of-scope-mvp]].

### Time
- Real-time clock with **pause and three speeds**.
- Daily tick for the clock, **monthly resolution** for economic and opinion updates. Anything faster is churn the model cannot justify.

### Economy
- Aggregate sectors: agriculture, industry, services. No open dataset splits energy
  out of industry (see [[data-sources]]) — if S4's model wants an energy lever, it
  splits industry as a hand-tuned constant against a concrete model, not a guess made
  before the model exists.
- GDP, growth, unemployment.
- Passive trade with neighbours as a growth input.

### Budget
- Spending lines: health, education, defence, pensions, infrastructure, debt service.
- Tax levers: income tax, corporate tax, VAT.
- Deficit, accumulated debt, and debt service crowding out other spending.
- A budget screen where changes show their projected effect before you commit.

### Politics
- Six fictional parties per [[fictionalization]], positioned on an ideology slot.
- An assembly with seats distributed between them.
- **Laws** defined as data templates: preconditions, effects, and which ideology slots support or oppose. The player proposes; the assembly votes; passage applies the effects.
- Fixed five-year term.

### Society
- Overall approval rating.
- Voter blocs — workers, business owners, pensioners, students, rural, urban — each with their own approval and their own issue priorities.
- Issue salience, so fixing something nobody cares about buys nothing.
- Opinion inertia, so no single act saves or sinks you.

### Election and lose condition
- General election at the end of the term.
- Vote share computed from bloc approval, bloc size, turnout weighting, and party positions.
- **Lose:** you are voted out. The run ends with a summary of the term.
- **Win:** re-election. The game continues into the next term. There is no final victory at MVP; staying in power *is* the progress condition.

### Presentation
- 2D map of Europe, nations coloured, clickable, showing a data panel.
- Panel-driven UI for budget, laws, parties, polling.

### Persistence
- Save and load. Versioned save format from the first commit.

## Done-when

The MVP is finished when all of the following are true. Evidence was gathered in
the [[ROADMAP|S10]] balance pass; every claim below is a check that runs in
`./tools/run_tests.sh`, not a playtest impression. The trajectories the tuning
was done against come from `tools/balance_probe.gd`, which plays fourteen
simulated years — the inherited term plus two full ones — under ten fixed budget
regimes.

- [x] **A full five-year term is playable start to finish without a crash or a softlock.**
  `tests/test_game_loop.gd` drives the real clock through the real main scene.
  `tests/test_balance.gd` plays 168 months and resolves three national elections
  (June 2029, 2034, 2039), asserting `terms_served ≥ 3` at the end.
- [x] **The player can lose, and losing is attributable to their decisions rather than to noise.**
  Seven of the ten probe regimes lose their first election; the two viable ones
  and one mediocre one hold. There is no randomness anywhere in the sim — polling
  noise is display-only — so a result is reproducible from state, which
  `tests/test_elections.gd` asserts. Attribution names a *different* number per
  failure: profligacy on `public_finances` (salience 0.57, satisfaction −1.00),
  austerity on `health` and `pensions`, a tax squeeze on `jobs` and the tax lines,
  abolishing spending on `health`, `pensions` and `education`.
  `tests/test_balance.gd` asserts two different bad budgets are blamed on two
  different issues, and that each is named because its satisfaction is negative.
- [x] **Passing a law visibly changes at least one economic and one opinion number over the following months.**
  `tests/test_legislature.gd::_check_passed_law_moves_economy_and_opinion` passes
  `carbon_levy` against a do-nothing control and requires both the deficit and
  rural approval to diverge from it.
- [x] **Ignoring the budget for a full term produces a visibly worse outcome than managing it.**
  Over 168 months, never touching the budget ends at debt 163.1 % of GDP,
  approval 48.2, 203/577 seats, on a monotonically decaying approval curve. The
  managed budget — cut defence, fund it with VAT, leave health, education and
  pensions alone — ends at debt 121.3 %, approval 49.7, 212 seats, with the debt
  ratio *stable* rather than climbing. `tests/test_balance.gd` asserts managed
  beats ignored on all three.
- [x] **A save reloaded mid-term produces identical state.**
  `tests/test_save_load.gd`.
- [x] **A ten-year playthrough (two terms) runs with no value diverging to infinity or pinning at zero.**
  `tests/test_balance.gd` checks every headline scalar, every sector and every
  bloc approval *each month* for non-finite values, non-positive GDP and
  population, and — stricter than the checklist asks — for any value resting on
  one of the model's guard clamps. All ten probe regimes report clean.
- [ ] **The banned-names grep from [[fictionalization]] returns nothing.**
  Still failing, on two S2 substring false positives: `BEL.json`'s invented
  "Sociale Vooruitgang" matches the banned "Vooruit", and `GBR.json`'s invented
  "Ecology Alliance" matches "Ecolo". Both authored names are fictional; the
  check's matcher is not word-boundary aware. Pre-existing debt, queued
  separately, deliberately **not** fixed inside S10 — the fix belongs in
  `tools/check_names.sh`, not in the balance constants.

## Deliberately absent

The full exclusion list, with reasoning, is [[out-of-scope-mvp]]. The headline omissions: no interactive diplomacy, no companies, no changing the political system, no war, no media, no corruption.

---

Related: [[scope]] · [[v1]] · [[someday]] · [[out-of-scope-mvp]] · [[ROADMAP]]
