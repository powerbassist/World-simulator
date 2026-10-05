---
title: Summits Model
tags:
  - decision
  - ui
  - diplomacy
---

# Summits Model

The scene a meeting becomes. V2.4b, chained off [[calendar-model]] §12's
meeting arrival: a state visit lands, `Summits.draw()` picks a scene, the
orchestrator opens it, the player talks, one choice is priced. Judged on the
same standard as the rest of the tier — legibility first, and no new machine
where an existing shape serves.

## 1. The adoption, and the gate that preceded it

`dialogue_manager` (Nathan Hoad, 3.10.5, MIT) was parked in the editor since
before U5a, named in AGENTS.md's Gotchas as the one obvious future adoption.
V2.4b took it, and the **step 0 was a gate, not a build**: the addon had to
instantiate and compile a dialogue under `godot --headless --script` —
`tools/run_tests.sh`'s own regime — before any content was authored. It passed.
An adoption that cannot run where the tests run would have broken the suite it
joined the moment it was committed.

The price, paid knowingly and recorded where AGENTS.md prices it:

- `addons/dialogue_manager/` committed whole — 790 KB, 122 files — the
  `.gitignore`'s second exception, with the reason beside it: this is a **game
  runtime** dependency, not tooling; a fresh clone without it is a broken game,
  not a warning.
- `DialogueManager` in the **committed** `project.godot` `[autoload]` — the
  project's **first stated exception to the no-autoloads rule**. The commit also
  cleaned the per-machine `MCPRuntimeServer` line out of the committed tree,
  which had crept into HEAD.
- Summits compile their scenes through the addon at draw time and walk them
  through `get_next_dialogue_line()` at play time, so the autoload is
  load-bearing in shipped builds, not decoration for the editor.

## 2. What a summit is

**Ephemeral.** No register, no history, no serialised state at all: the scene
happens once at arrival, its choice applies through
`Legislature.apply_effects()` — the applier the law and the event choice
already share — and what it changed is already in the channels it changed.
`tests/test_summits.gd` pins the absence (`SAVE_VERSION` stays 27; `to_dict()`
carries no summit key) rather than trusting the comment. Ephemerality is the
design, not an economy: a record of dinners is derivable from the state the
dinners changed, and a register that nothing reads is V1.3e's tuned constant in
a new costume.

**Drawn, not authored into an outcome.** `Summits.draw()` picks from the
partner's pool on `Cycle.unit()` over (nation id, meeting stamp) — the event
hazard's determinism, so a replayed arrival produces the same dinner. The
meeting register's own stamp is the index, which is why a RE-visit can draw a
different scene from nothing being stored. A nation with no pool draws nothing:
a meeting without a scene is the ordinary state visit, not an error.

## 3. The sidecar contract

One summit is two files: `<NATION>_<id>.dialogue` (the scene, addon syntax)
and `<NATION>_<id>.json` (the sidecar that names it and prices its responses).
The join is the response LABEL, and the loader enforces it loudly:

- every response offered in the dialogue has an effects entry — `{}` is legal
  and means *lands nowhere, deliberately* (a mid-scene fork whose outcome is
  only reached later);
- every effects entry names a response the dialogue actually offers — a price
  with no choice behind it is content that can never run;
- every channel is one of `SHARED_EFFECT_CHANNELS` — a summit lands where a
  law and an event choice can, and nothing else. Pair state is out, for
  events-model's own reason: relations has one writer with an ACTOR behind it,
  and a conversation over venison is not one.

The compiles at draw time, so the loader stores text; the content test
compiles every shipped scene headlessly, which is where a syntax error is
caught while it can still name its file.

## 4. The interrupt reversal, for the flagged class only

`interrupt: true` is one boolean on the event schema's closed key list —
absent in a version-27 save reads false, which is the truth about that save.
`announce()` copies it into the pending register, and `main.gd`'s
`_enforce_interrupt()` — called from BOTH the month tick and the load path —
pauses the clock and opens Dispatches when it reads true. The two callers are
the point: a save made mid-crisis and reloaded is still mid-crisis, and the
**reload re-raise** is the same code path rather than a second one. The pause
gates on the flag, asserted at source: every event WITHOUT it pauses nothing,
and events-model's non-modal argument survives everywhere but the flagged
class — the case the argument does not cover, an event nobody could reasonably
choose to ignore.

The shipped member is `blackout_night`: a grid failure with `respond_months:
1`, which is the flag's whole meaning compressed — the clock would not have
reached the deadline anyway.

## 5. The re-run

Predicted bit-identical on "no regime books a visit" — right about the
summits, wrong about the event. `blackout_night` is a HAZARD, not a verb: it
draws on the precondition (debt ≥ 95 %) that most managed regimes hold, and
its default applies `bloc_offset` whether or not the player answers. Roughly
990 of the probe's output lines wobble, **every one of them a margin or a last
digit**: every censure still holds, every election keeps its verdict. V1.8's
re-run moved for the same reason — an event that can fire is content the
harness cannot hold still, and that is the harness working.

## 6. What is deliberately not built

**Multi-beat branching with mutations and conditions.** The addon handles
them; the shipped content uses none. The balloon walks whatever the scene
contains, so content may grow without the panel changing — but the first
mutating summit should come with a thought about what a mutation means when
the scene is ephemeral and the effects are the sidecar's.

**Summits for the nine.** Their state visits stamp the meeting register and
open no scene — the player is not there, and a conversation nobody reads is a
card nobody asked for. `data/summits/` keys by partner; the seven
non-playable nations have no pool, and nobody else's arrivals draw.

**A summit history surface.** §2's argument one level up: the nation panel
already reads the relations and cooldowns a summit changed.

---

Related: [[index]] · [[calendar-model]] · [[events-model]] ·
[[diplomacy-model]] · [[v2]]
