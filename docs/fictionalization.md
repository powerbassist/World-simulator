---
title: Fictionalization Rule
tags:
  - convention
  - content
---

# Fictionalization Rule

The single content rule that governs every document, every data file, and every line of dialogue in this project.

## The rule

**Nations are real. People, companies, and political parties are invented.**

France is France. It has France's borders, France's population, France's neighbours, France's seat on the UN Security Council, and France's real starting economy. The player recognises the country they are playing.

Everything inside that country that has a *name attached to a person or an organisation* is fictional. The President of France in this game is **Daniel Moucron**. The oil major headquartered in La Défense is **Tatol**. The governing centrist party is **Renouveau Civique**. None of these exist.

## Why the split

Real nations give the game its hook — the player wants to run *France*, not Ruritania. Fictional people and organisations give three things back:

1. **Freedom to balance.** A fictional party can be tuned to whatever ideology slot the simulation needs without anyone arguing that the real one wouldn't do that.
2. **No dating.** Real leaders leave office. A game shipped with a 2026 cabinet is stale in 2027. Fictional leaders never go out of date.
3. **No portrayal problem.** Simulating a named living person's approval collapse, corruption scandal, or ousting is a liability the game gains nothing from.

## What counts as what

| Category | Treatment | Example |
|---|---|---|
| Country name, borders, flag, capital | Real | France, Paris, the Hexagon |
| Population, GDP, debt, unemployment | Real, rounded — see [[data-sources]] | ~68M people, ~110% debt-to-GDP |
| Institutions by *role* | Real | National Assembly, Senate, Constitutional Council |
| Institutions by *proper name* | Real if the name is structural, invented if it's a brand | "National Assembly" stays; a specific newspaper does not |
| Heads of state and government | **Invented** | Daniel Moucron |
| Ministers, party leaders, opposition figures | **Invented** | — |
| Political parties | **Invented**, in real ideological slots | Front Souverainiste |
| Companies | **Invented** | Tatol |
| Cities, regions, rivers | Real | Lyon, Occitanie, the Rhône |

## Naming conventions

**People** — every person lives in `data/people/<NATION>.json` as an `{id, name}` record, and nothing else in `data/` spells a person's name out; see [[people-model]]. The id is `<NATION>_<surname>`, ASCII-folded by the nation's own convention (`Müller → DEU_mueller`), with a nobiliary particle kept because it belongs to the surname (`Van Craen → BEL_van_craen`) and a regnal name slugged whole because it has none (`Baudouin III → BEL_baudouin_iii`). Two people sharing a surname inside one nation take the forename initial. No surname is reused across the ten, so a `check_names.sh` hit is always traceable to one file.

Use names that sound native to the nation. French leaders get French names, German leaders get German names. Avoid names of currently serving or recently serving officeholders anywhere in the world, and avoid names of internationally famous figures generally.

**Parties** — build from real political vocabulary, but never reproduce a real party's actual name or its common abbreviation. The name should telegraph the ideology slot so a player can read the assembly at a glance.

**Companies** — the near-miss style is fine and intentional: *Tatol* for a French oil major reads as a deliberate wink rather than a mistake. Keep the sector legible. Do not reuse a real company's actual name, logo, slogan, or trademarked styling.

## Worked examples — France

Leader: **Daniel Moucron**, President of the Republic.

Parties, six slots covering the usable spectrum:

| Party | Ideology slot |
|---|---|
| Renouveau Civique | Centrist liberal |
| Union Conservatrice | Centre-right |
| Parti Social Uni | Social democratic |
| Alliance Verte | Green |
| Front Souverainiste | Nationalist right |
| Gauche Populaire | Left populist |

Companies, for the [[v1]] economic layer:

| Company | Sector |
|---|---|
| Tatol | Oil and gas |
| Sarbius | Aerospace |
| Vialtel | Telecoms |
| Bancorde | Banking |

## Enforcement

This is checkable, so it gets checked. A banned-names list lives alongside the project and is grepped over the whole repository before any milestone commit: real heads of state and government, real party names and abbreviations, and real company names for every nation in scope. Zero hits, or the content is wrong.

**`tools/check_names.sh` iterates `git ls-files`, so it cannot see an untracked file.** U6b added `data/people/` and the first run of the check over it passed with zero hits and zero files scanned. Any session authoring a NEW content directory must `git add` before the check means anything — the largest exposure this check has ever had was, for one run, not being checked at all.

The check is cheap now and gets expensive to retrofit once there are hundreds of data files, which is exactly why it starts at [[ROADMAP|session S2]].

---

Related: [[index]] · [[data-sources]] · [[data-architecture]] · [[scope]]
