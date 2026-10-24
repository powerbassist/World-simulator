---
title: Nation Simulator — Index
tags:
  - moc
---

# Nation Simulator

Design vault for a single-player geopolitics and nation-management game. You rule a real nation: pass laws, manage parties, set the budget, fight elections, change the political system, negotiate with other nations, and contend with private companies.

> [!note] Vault root
> Open **the project root** as the Obsidian vault, not `docs/` — the vault config (`.obsidian/`) lives at the root.

## Start here

- [[scope]] — what the game is, what gets built, what does not
- [[mvp]] — the smallest version that is actually a game

## Decisions

- [[engine-decision]] — Godot 4 + GDScript, and why not Unity or Unreal
- [[data-architecture]] — static content vs live state, and why there is no database
- [[tick-order]] — the month's steps in the one order the game runs them, and the data → core → sim → ui layers drawn (generated, checked)
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
- [[orgs-model]] — the org register (V3.2): membership as data, one register per council, the composition rule, accession and withdrawal as fights
- [[foreign-policy-model]] — why the other nine answer as they do, and how they choose a target and a verb unprompted
- [[summits-model]] — the scene a meeting becomes: a state visit lands, a scene is drawn, the player talks, one choice is priced (V2.4b)
- [[agency-model]] — the competence-credit channel: how running the country *well*, not *differently*, reaches a voter (V4.0)
- [[programme-model]] — the government's programme: an agenda the player chooses at term start, judged on what it was for (V4.1)
- [[defence-model]] — capability derived from sustained spending, defensive pacts, and the alliance obligation that bills you at home
- [[calendar-model]] — the president's diary: dated state put on a timeline, optional booking, and the currency a probe deleted
- [[audiences-model]] — people ask to see the president: the request lane, its own trigger, book / delegate / decline, and a lapse that is a decline (V5.2b)
- [[people-model]] — the named-individual register: one record per person, ids in state, and the minister bench a probe cut before it was authored
- [[companies-model]] — named firms as a partition of a sector, subsidies as the first verb pointed at something that is not a nation, and the two channels that read exactly zero until the player acts
- [[society-model]] — service quality as a stock the project had already built three times under other names, corruption as the factor that decides what a spending line buys, and the double count that had to be resolved rather than avoided
- [[unrest-model]] — the grievance stock and the unions that act on it, an inequality statistic nothing the player can move, and the output-only price its own probe refuted
- [[demography-model]] — ageing at a measured rate, the dependency ratio it produces, and what that ratio puts pressure on (V1.5b)
- [[natural-change-model]] — births minus deaths per region, a measured rate that moves the population shares (V2.6)
- [[media-model]] — outlets with leanings, framing as a per-bloc salience gain on a machine `opinion.gd` had been running since S10, and press freedom priced in a legitimacy quantity that turned out to already exist
- [[tax-model]] — five taxes and brackets, the wealth tax that is not on the other four's rate scale, and the tripwire that could not fire
- [[sector-model]] — sectoral investment: a capital stock on the sector's own trend rate, why `sector_output` had no room for a second writer, and why the lever buys output and no jobs
- [[commodities-model]] — the commodity economy: world prices, per-nation commodity state, and the content in `data/commodities/` (V4.6)
- [[energy-model]] — power plants as a per-nation register, a build countdown, a computed spending line and a derived mix (V2.8)
- [[climate-model]] — an emissions read over the energy mix, two sited disasters on the event schema, and a fifth org (V3.5)
- [[projects-model]] — infrastructure projects: a dated commitment that bills while it builds and pays once when it opens, why the diary needed no second scheduler, and why the bill is not the cost
- [[campaign-model]] — the campaign phase: money spent on TURNOUT rather than on opinion, why the row's other two nouns were already answered, and why maximising your own vote share is not the same as winning
- [[pledge-model]] — campaign promises: why the trust price needed no new quantity, why a promise is judged EVERY MONTH rather than at the end of the term, and the difference between a bet on the world and a self-imposed constraint
- [[referendum-model]] — the referendum as a second ratification stage rather than a bypass, the electoral system as an ORDINARY law, and the kill switch that was sweeping approvals no player can reach
- [[upper-house-model]] — the second chamber: the assembly you used to have, voting
  without your whip
- [[judiciary-model]] — the court, rule of law, and a lock with a key you can buy
- [[panel-system]] — the row primitives twenty-five panels stopped writing for themselves, the sweep derived from the window registry, and the fold a headless harness turned out to be able to see
- [[events-model]] — events as OCCASIONS rather than mechanics, why the schema is the law channel and not the union of ten, the deterministic hazard, and the accumulation bound that a per-decision band could not see
- [[event-art-plan]] — the V4.4 event art: plates reused by category and severity, the recipe, and the licence trail
- [[geography-model]] — regions and cities as a two-level partition of population, why the NUTS level is per nation, and the population cut that had to be measured three times because GeoNames files boroughs as cities
- [[siting-model]] — the contract by which a national quantity acquires a place (V2.6b1)
- [[map-platform-model]] — the map as a platform: the frame budget a profile measured, and the playtest finding it refuted (V3.1)
- [[region-economy-model]] — national GDP as the sum of the regions, the zero-mean mix deviation that keeps the aggregate honest, and Britain's recorded absence of any regional divergence
- [[network-model]] — the 112 regions on a transport graph: adjacency derived, eight authored sea links, an output-weighted accessibility index, and the beta sweep whose band turned out to have one edge
- [[migration-model]] — the two population partitions made live: a zero-sum flow on expected income and named employers, the rate measured from Europe's own regional drift, and the two nations that structurally cannot move
- [[data-sources]] — which open datasets seed the content, under which licenses
- [[fictionalization]] — real nations, invented people, companies and parties
- [[portrait-attribution]] — the Wikimedia Commons photographs behind the generated portraits, credited as their licences require
- [[localisation]] — English as the msgid, the French tables, the key scheme for text in data/, the lint and the fit sweep
- [[glossary-fr]] — the recurring French terms and typography every translation PR uses
- [[tooling]] — Godot version, MCP setup, machine prerequisites
- [[test-suite-model]] — one execution core for the gate: parallel workers, exclusive lane, per-check sharding byte-identical to the monolithic run, and the cockpit that reads it
- [[decision-log]] — corrections made mid-session that changed the plan, and why
- [[playability-audit]] — the first pass that tried to PLAY the game: nine defects, five that break a playthrough, and the register kept as assertions that turn red when fixed
- [[v5.0-replay]] — the V5.0 play gate's twenty complaints checked against main, and the author's 10-minute replay script
- [[glossary-tooltips]] — the instructive layer: 48 ranked terms with definitions tied to their models, underlined terms with tooltips that nest and lock, the noise rules and the proof
- [[v5.1-gate-triage]] — the V5.1 play gate's design items (G2, G5, G7, G10, G11, G14, Q1, Q2, Q4): what d can take cheaply, what V5.2 and V5.3 own, and the author's calls
- [[decision-surfaces]] — every surface that asks the player something, measured over 24 idle months, with a triage and an interruption budget

## Scope tiers

- [[mvp]] — France, one term, one way to lose
- [[v1]] — what gets built once the MVP works. Complete; nothing left in it
- [[v2]] — the world becomes visible and located: geography, faces, a calendar that costs something, motion
- [[v3]] — Europe, whole: the map as a platform, the alliance system, the EU-27 roster, roads and climate. Signed 2026-09-06; V3.0–V3.7 built, V3.7's portrait generation left incomplete by the author's call (2026-09-14)
- [[v4]] — the world wants things: agency settled, a player agenda, characters, events at scale, industry, the reading surface. Signed 2026-09-13; closed 2026-10-18, twelve blocks merged
- [[v5]] — the world talks back: the audit, a new shell and charter, people who talk, decisions in real units, the real network. Signed 2026-10-19; V5.0 closed 2026-10-20, V5.1 (the shell) in progress, each block's state in [[tiers/v5]]
- [[v5-reflection]] — what V4 left and what the author asked for: load-bearing debts, design tensions, three candidate themes with verdicts
- [[v5.2-spec]] — V5.2's design: every audience, lever and shadow decision with its trade-off, the dominance matrix, the conflicts with earlier rulings, a pre-mortem
- [[bands-v5.2]] — V5.2's player-outcome bands, declared before the build, each with its probe and what a failure looks like
- [[v5.2-legibility]] — V5.2-0b's text diet: every workspace tab's prose measured, what to cut, move to the glossary or chart, and a per-tab prose budget
- [[history]] — the per-block record of what each version built, measured and refused (moved out of AGENTS.md at V4.4's close)
- [[someday]] — deferred engineering issues, each with the trigger that would reopen it
- [[tiers/someday|someday (ideas)]] — the parking lot for design ideas, not scheduled
- [[declined]] — considered and decided against, with what would reopen each
- [[out-of-scope-mvp]] — the explicit exclusion list, with reasons

## Working notes

- [[vault]] — how this vault is set up: excluded folders, what each plugin is for, the templates
- [[vault-dashboard]] — live views over the docs (Dataview) and the open author calls (Tasks)
- [[architecture.excalidraw|architecture]] — the `data → sim → ui` rule as a drawing
- [[shell]] — the BUREAU shell as a canvas (map, workspace, HUD, screen stack) and the sidebar's domains and tabs, generated from `domains.gd`
- [[2026-09-07-v3.3-roster-eu27]] — the one committed build plan (the others are gitignored scratch)

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
