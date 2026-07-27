---
title: Scope
tags:
  - scope
  - moc
---

# Scope

The scope document for Nation Simulator. This note is the hub: the broad idea space lives in the brainstorm notes, and the cuts live in the tier notes.

## What the game is

A single-player geopolitics and nation-management game. You are the ruler of a real nation. You pass laws, manage political parties, set the national budget, fight elections, change the political system, negotiate with other nations, and deal with private companies as economic actors.

Genre reference: Geopolitical Simulator. A reference point, not a target to clone.

## Fixed constraints

These are settled and everything else is designed around them.

| Constraint | Value |
|---|---|
| Platform | PC only — Windows, Linux, macOS. No console or mobile, ever. |
| Players | Single-player only. No multiplayer, no netcode, no server. |
| Time model | Real-time with pause and speed control. |
| Presentation | 2D map plus dense UI panels. No 3D. |
| First playable nation | France. |
| Playable nations, eventually | **All of them.** France-only is an alpha cut, not the design target. |
| World at MVP | France plus nine European AI neighbours. |
| Engine | Godot 4.x, GDScript — see [[engine-decision]]. |
| Content rule | Real nations, invented people, companies, and parties — see [[fictionalization]]. |

> [!important] France-only is temporary, and that changes what is acceptable now
> Every nation in the game is meant to become playable. [[v1|V1.2]] adds the
> first few; the end state is all of them, at whatever roster the game ships
> with.
>
> This is a constraint on **today's** code, not a note about the future. A
> shortcut that works because there is exactly one player nation is debt with a
> known due date, and the cheap version is worth taking only after checking that
> it generalises. It is the same rule [[engine-decision]] already states as
> "there is never an `if nation_id == "FRA"` anywhere" — which nation the player
> holds is data, read through `GameState.player()`, never a constant or a branch.
>
> The ten authored electoral systems, formation methods and censure rules already
> exist partly for this reason: they were built per-nation when a France-only
> game would not have needed them.

## Step 1 — Brainstorm

The candidate mechanic space, deliberately unfiltered. These lists are long on purpose; a mechanic being listed is not a commitment to build it.

- [[mechanics-governance]] — elections, legislature, executive, constitution and political systems
- [[mechanics-economy]] — public finance, real economy, private companies, monetary policy
- [[mechanics-foreign-policy]] — bilateral relations, trade, blocs, coercion and conflict
- [[mechanics-society]] — public opinion, media, labour and unrest, institutions, population and services

## Step 2 — The cuts

- **[[mvp]]** — the smallest version that is actually a game. One nation, one term, one way to lose.
- **[[out-of-scope-mvp]]** — the explicit exclusion list, with the reason for each cut written down.
- **[[v1]]** — what gets built once the MVP loop works, in the order it gets built.
- **[[someday]]** — the parking lot. Explicitly not part of near-term planning.
- **[[declined]]** — considered and decided against, with the reason and the condition that would reopen each. Stronger than the parking lot.

## The MVP in one sentence

> You are the President of France. You have five years, a budget, an assembly that does not have to agree with you, and a population that is watching. Survive the next election.

Full definition and done-when criteria in [[mvp]].

## The load-bearing cut

The original pitch names trade deals and diplomacy as core features. They are **not in the MVP**.

Neighbouring nations exist at MVP — they have real starting statistics, their economies evolve, and their trade affects French growth. But they do not negotiate. Interactive diplomacy needs an AI capable of evaluating and countering offers, which is a subsystem comparable in size to the entire domestic loop, and the domestic loop has to be proven enjoyable before a second one is stacked on it.

Diplomacy is block 3 of [[v1]] — planned, sequenced, and expected. It is deferred, not abandoned. If this cut is wrong, it is the one worth arguing about, because reversing it substantially changes the [[ROADMAP]].

## Related decisions

- [[engine-decision]] — Godot 4, GDScript, and why not Unity or Unreal
- [[data-architecture]] — static content versus live state, and why there is no database
- [[data-sources]] — which open datasets seed the content, and under what licenses
- [[ROADMAP]] — the session-by-session build order

---

Related: [[index]]
