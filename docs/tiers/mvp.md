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

The MVP is finished when all of the following are true:

- [ ] A full five-year term is playable start to finish without a crash or a softlock.
- [ ] The player can lose, and losing is attributable to their decisions rather than to noise.
- [ ] Passing a law visibly changes at least one economic and one opinion number over the following months.
- [ ] Ignoring the budget for a full term produces a visibly worse outcome than managing it.
- [ ] A save reloaded mid-term produces identical state.
- [ ] A ten-year playthrough (two terms) runs with no value diverging to infinity or pinning at zero.
- [ ] The banned-names grep from [[fictionalization]] returns nothing.

## Deliberately absent

The full exclusion list, with reasoning, is [[out-of-scope-mvp]]. The headline omissions: no interactive diplomacy, no companies, no changing the political system, no war, no media, no corruption.

---

Related: [[scope]] · [[v1]] · [[someday]] · [[out-of-scope-mvp]] · [[ROADMAP]]
