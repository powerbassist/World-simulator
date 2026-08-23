---
title: Nation Simulator — Index
tags:
  - moc
---

# Nation Simulator

Design vault for a single-player geopolitics and nation-management game. You rule a real nation: pass laws, manage parties, set the budget, fight elections, change the political system, negotiate with other nations, and contend with private companies.

> [!note] Vault root
> Open **the project root** as the Obsidian vault, not `docs/`. `ROADMAP.md` lives at the root, and links to it only resolve from there.

## Start here

- [[scope]] — what the game is, what gets built, what does not
- [[ROADMAP]] — session-by-session build order
- [[mvp]] — the smallest version that is actually a game

## Decisions

- [[engine-decision]] — Godot 4 + GDScript, and why not Unity or Unreal
- [[data-architecture]] — static content vs live state, and why there is no database
- [[economy-model]] — the economy and budget formulas, and why nothing diverges
- [[cycle-model]] — the business cycle: a deterministic shock, measured off thirty-four years of growth
- [[inflation-model]] — inflation as a stock on the unemployment gap, and the thirteenth issue
- [[credit-model]] — the bond yield as a spread over a constant that has been flat since the MVP, and the rating that reads it
- [[opinion-model]] — voter blocs, salience, approval inertia, and polling noise
- [[election-model]] — vote share, turnout weighting, attribution, and no election-day noise
- [[electoral-systems]] — the ten real electoral systems, every date's source, and what each reduction throws away
- [[legislature-model]] — law templates, ideology-space vote resolution, and effect channels
- [[government-model]] — government formation per nation, coalitions as a point in ideology space, and the censure arithmetic
- [[discipline-model]] — party discipline as live state, what erodes it, and seat-level rebellions
- [[dissolution-model]] — dissolution and snap elections, the rule as data, and what the gamble costs
- [[cabinet-model]] — cabinet portfolios, competence as derived effectiveness, and shortfall-driven resignation
- [[political-systems]] — political system templates as a constraint not a defaults table, the head of state, and enforced term limits
- [[amendment-model]] — constitutional amendment as a law with a per-nation threshold, and the channel that sets rather than nudges an institution
- [[transition-model]] — monarchy ↔ republic as the amendment mechanism pointed at `system_id`, checked against the target
- [[scenario-model]] — start scenarios as the answer to difficulty, the three authored axes, and the measured envelope
- [[diplomacy-model]] — pair-keyed relations, symmetric and derived, their drift, and the player's diplomatic verbs
- [[trade-model]] — the directed trade weight, per-partner external demand, bilateral agreements, and why relations move the mix and never the level
- [[coercion-model]] — tariffs and sanctions on the first directed state: what a measure collects, what it destroys, who answers, and the Laffer curve nothing authors
- [[bloc-model]] — the supranational bloc: proposals, the council, rules in force, transfers, and the twelfth opinion issue
- [[foreign-policy-model]] — why the other nine answer as they do, and how they choose a target and a verb unprompted
- [[defence-model]] — capability derived from sustained spending, defensive pacts, and the alliance obligation that bills you at home
- [[calendar-model]] — the president's diary: dated state put on a timeline, optional booking, and the currency a probe deleted
- [[people-model]] — the named-individual register: one record per person, ids in state, and the minister bench a probe cut before it was authored
- [[companies-model]] — named firms as a partition of a sector, subsidies as the first verb pointed at something that is not a nation, and the two channels that read exactly zero until the player acts
- [[society-model]] — service quality as a stock the project had already built three times under other names, corruption as the factor that decides what a spending line buys, and the double count that had to be resolved rather than avoided
- [[unrest-model]] — the grievance stock and the unions that act on it, an inequality statistic nothing the player can move, and the output-only price its own probe refuted
- [[media-model]] — outlets with leanings, framing as a per-bloc salience gain on a machine `opinion.gd` had been running since S10, and press freedom priced in a legitimacy quantity that turned out to already exist
- [[tax-model]] — five taxes and brackets, the wealth tax that is not on the other four's rate scale, and the tripwire that could not fire
- [[sector-model]] — sectoral investment: a capital stock on the sector's own trend rate, why `sector_output` had no room for a second writer, and why the lever buys output and no jobs
- [[projects-model]] — infrastructure projects: a dated commitment that bills while it builds and pays once when it opens, why the diary needed no second scheduler, and why the bill is not the cost
- [[campaign-model]] — the campaign phase: money spent on TURNOUT rather than on opinion, why the row's other two nouns were already answered, and why maximising your own vote share is not the same as winning
- [[data-sources]] — which open datasets seed the content, under which licenses
- [[fictionalization]] — real nations, invented people, companies and parties
- [[tooling]] — Godot version, MCP setup, machine prerequisites
- [[decision-log]] — corrections made mid-session that changed the plan, and why
- [[playability-audit]] — the first pass that tried to PLAY the game: nine defects, five that break a playthrough, and the register kept as assertions that turn red when fixed

## Scope tiers

- [[mvp]] — France, one term, one way to lose
- [[v1]] — what gets built once the MVP works
- [[someday]] — the parking lot, not scheduled
- [[declined]] — considered and decided against, with what would reopen each
- [[out-of-scope-mvp]] — the explicit exclusion list, with reasons

## Brainstorm

The unfiltered candidate mechanic space. Long on purpose.

- [[mechanics-governance]]
- [[mechanics-economy]]
- [[mechanics-foreign-policy]]
- [[mechanics-society]]

## The short version

| | |
|---|---|
| Platform | PC only — Windows, Linux, macOS |
| Players | Single-player |
| Engine | Godot 4.x, GDScript with static typing |
| Time | Real-time, pausable, three speeds |
| View | 2D map + dense UI panels |
| MVP world | France playable, nine European AI neighbours |
| MVP lose condition | Voted out of office |
| Content | Real nations. Invented people, companies, parties. |
| Storage | JSON content files, JSON saves, no database |
