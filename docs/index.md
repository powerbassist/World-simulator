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
- [[data-sources]] — which open datasets seed the content, under which licenses
- [[fictionalization]] — real nations, invented people, companies and parties
- [[tooling]] — Godot version, MCP setup, machine prerequisites

## Scope tiers

- [[mvp]] — France, one term, one way to lose
- [[v1]] — what gets built once the MVP works
- [[someday]] — the parking lot, not scheduled
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
