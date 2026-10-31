---
title: Decision surfaces — what stops the game, and what waits
tags:
  - design
  - ui
---

# Decision surfaces — what stops the game, and what waits

The author asked (2026-10-22): "for events like state visits and events, we need
pop-up to take decisions no?". The question underneath is which arrivals deserve
to stop the game, and how the player finds the others. This note inventories every
surface that exists, measures what reaches a France player who answers nothing,
and proposes a triage with an interruption budget.

Labels as in [[v5.0-replay]]: **MEASURED**, **INFERRED**, **OPINION**. Source lines
are as of `main` at `52f286c2`.

## The author's answers (2026-10-22)

The four calls below, and one more the parent added, went to the author
through the parent session's question tool. The picks are verbatim, with what
each settles.

1. **The interruption budget:** "Au plus 4 + 6 par an (Recommandé)". At most
   4 uninvited modal stops and 6 holding cards a year; notes never hold; scenes
   the player books do not count.
2. **V5.2's requests:** "Carte qui ne bloque pas (Recommandé)". A request is a
   card that never holds the clock, and its lapse is a decline.
3. **A foreign leader's visit:** "Une note (Recommandé)". One note a month at
   most, and a request card from V5.2 when the visitor wants something.
4. **The minor decision's last-month stop:** "Garder (Recommandé)". The lapse
   guard stays.
5. **The AI's visit cadence (about 26 a year to France):** "Oui, maintenant
   (Recommandé)". Systems makes the rate real now, with a declared re-baseline.

Where they land: the "requests waiting" mark goes to d2 (the parent's routing).
The budget (1) and the request rule (2) are folded into [[v5.2-spec]] at V5.2's
plan gate, not now.

## The author's calls, first

Each has the recommendation first.

1. **The interruption budget.**
   (a) *Recommended:* at most **4 uninvited modal stops a year** (an election
   result, an interrupt crisis), at most **6 holding cards a year** (a major
   decision, a minor one in its last month), and notes never hold the clock.
   Scenes the player books (a summit, a V5.2 audience) do not count: the player
   asked for them.
   (b) Every arrival that asks for a decision opens a modal pop-up.
2. **V5.2's requests: do they hold the clock?**
   (a) *Recommended:* no. A request is a card in the REQUESTS lane that waits;
   if its window passes, it is a decline (the author's answer of 2026-10-21,
   [[v5.2-spec]], "The author's answers", 3). The clock shows that requests are
   waiting, and never stops for one.
   (b) Yes, in its last month, like a quiet event. At B1's 24-48 requests a term
   ([[bands-v5.2]]), that is 5 to 10 more stops a year.
3. **A foreign leader's state visit to the player.**
   (a) *Recommended:* a note, one per month at most (the rolling note in PR #70).
   From V5.2, a visitor who wants something sends a request card instead.
   (b) A modal to receive each visitor.
4. **A minor decision's last-month stop (the lapse guard).**
   (a) *Recommended:* keep it. "Ça doit se passer comme dans la vraie vie"
   (the author, 2026-10-21, on P12): a minister brings you the file before the
   deadline, whether or not you asked.
   (b) Drop it, and let minor decisions default without a stop.

## The finding in one paragraph

**The game already stops for every event decision.** A major or critical
arrival pauses the clock and slides the inbox in; a minor one holds the clock in
its last month (the lapse guard). What the author meets instead is **scarcity
and noise**: in 24 idle months, 6 event decisions reached France against 53 state
visits to France, and the visits ask nothing (MEASURED, below). So the answer to
"we need pop-up to take decisions" is not more pop-ups. It is more decisions
worth stopping for (V5.2's people, V5.3's grand plans, the author's G5) and less
noise around them.

## The surfaces that exist today

| Surface | Trigger | Holds the clock? | If never answered | Where |
|---|---|---|---|---|
| **Interrupt crisis** | an event whose content carries `interrupt: true` (1 of 102 events, MEASURED) | yes, until answered, and slides the inbox in | cannot pass unanswered: the answer is the hold's only release | `src/ui/main.gd:1933` `_enforce_interrupt`; `:1953` `_hold_for_decision` |
| **Major or critical event card** (severity 2-3) | arrival on the desk | yes, on arrival (the default PAUSE band is 2), and slides the inbox in | defaults when its window runs out (1-6 months), with a "Decided for you" note | `main.gd:1422` `_card_events`; `src/ui/message_settings.gd:51` `DEFAULTS`; `src/sim/events.gd:308` `_tick_countdowns` |
| **Minor event card** (severity 1) | arrival on the desk | not on arrival; **yes in its last month** (the lapse guard), with its card | as above | `main.gd:1545` `_guard_lapses` |
| **"Decided for you"** | a decision defaulted | no | a note | `main.gd:1464` |
| **Election result** | a vote resolved | yes, until the player moves on | cannot pass unread | `main.gd:1282` |
| **Summit scene** | the player's own state visit, when the partner has a scene pool | **no, today**: `_open_summit` opens the window at the SCENE layer without pausing, and since d1a a pause by hand is refused under a scene, so the clock runs on (QA saw a summit open on 5 January at speed 3 and the clock reach 1 October under it). PR #70's TAKE 5 makes it hold | the player is in it | `main.gd:1740` `_open_summit`; [[summits-model]] |
| **Programme offer** | the first day of a term | yes, until chosen or declined | the offer lapses when the clock first runs | `main.gd:2029` `_enforce_term_start_programme`; [[programme-model]] |
| **Programme conclusions** | delivered, missed or overtaken | no | notes | `main.gd:2111` |
| **Foreign acts to the player** (state visits, sanctions, treaties) | an AI nation acts on France | no | notes, grouped by action per month | `src/ui/world_news.gd:88` `card_foreign_acts` |
| **Acts between two other nations** | an AI acts on a third | no | off by default | same; [[v5.0-replay]] P11 |
| **Unrest and character acts** | a strike, a brief, a defection | no | notes | `world_news.gd:172`, `:200` |
| **Consequence card** | the month close that measures an answer | no | a note | PR #69 (G10) |

- **The inbox has three lanes** (`src/ui/inbox.gd`, `DECISIONS`, `REQUESTS`,
  `NOTES`): decisions, V5.2's requests (empty until V5.2), and the rest.

## The measurement

`tools/decision_surfaces_probe.gd` is committed because V5.2 adds requests to the
same inbox, and the budget must be re-measured then. It drives
`WorldMonth.tick_month()` with its reads in the step hook, runs isolated, and
answers nothing. The run: France, 24 months (the rows run from February 2026
to January 2028, as `tools/balance_probe.gd`'s do), default
settings, `main` at `52f286c2`.

**MEASURED, over 24 months:**

| Count | Total | Per year |
|---|---|---|
| Event arrivals: interrupt | 0 | 0 |
| Event arrivals: major or critical (holds on arrival) | 1 | 0.5 |
| Event arrivals: minor (holds in its last month) | 5 | 2.5 |
| Decisions that defaulted, unanswered | 4 (2 more still on the desk at month 24) | 2 |
| Election results | 1 (2027-05) | 0.5 |
| Foreign acts aimed at France | 54 | 27 |
| of which state visits | 53 | 26.5 |
| Months with at least one visit (one grouped note each) | 20 of 24 | 10 |
| Acts between two other nations (not shown by default) | 22 | 11 |

- **The event rate agrees with the record:** 3 a year here, against 12 per
  five-year term in E4 (`docs/someday.md`, "Open author calls", the ticked
  **Re-run `events_probe` E4/E5** item). (MEASURED)
- **The visit count agrees with QA's play:** 8 notes in 9 months, against 10 a
  year here. It also agrees with the record that the AI aims about 95 % of its
  state visits at the player (the V5 ledger, the plan-gate note on V5.1-0d's
  attribution). (MEASURED)
- **Plausibly never seen: 0 at the default settings (INFERRED).** Every
  decision that defaulted was a held one, a major on arrival or a minor in its
  last month, so a player sees it unless they unpause past the hold.
- **The stops a France player meets: about 3.5 a year** (3 event decisions plus
  half an election), against about 10 notes a year from visits alone. At speed
  3 a year runs in about 52 seconds (`src/core/clock.gd:12`, 7 days a second),
  so this is one stop every 15 seconds of running at speed 3. At the author's
  pace of about 74 seconds a game month ([[bands-v5.2]], "The frame"), it is one
  stop every 4.2 minutes (a year is 12 × 74 = 888 seconds).

## The triage

| Arrival kind | Surface | Holds? | Budget (OPINION) | Why |
|---|---|---|---|---|
| Election result | **MODAL** | yes | counts toward the 4 | the term's verdict, which cannot be read late |
| Interrupt crisis | **MODAL** | yes, until answered | counts toward the 4 | content that says "until answered" (1 event in 102) |
| Summit, or a V5.2 audience the player booked | **MODAL** (a scene) | yes, while open | outside the budget | the player asked for it ([[v5-reflection]] T11: "A scene holds the clock while it is open") |
| Major or critical event | **CARD**, holds on arrival | yes | counts toward the 6 | a crisis is a crisis: the minister calls now |
| Minor event | **CARD**, quiet; holds in its last month | last month only | counts toward the 6 | "comme dans la vraie vie": the file comes back before the deadline |
| V5.2 request (an audience asked for) | **CARD** in REQUESTS | never | none; B1 bounds the rate | a lapse is a decline (the author's call), so silence is priced; a stop per request would add 5-10 a year (call 2) |
| A visit, an act or a treaty aimed at the player | **NOTE** | never | one note per kind per month | news, not a question; PR #70 rolls visits into one note |
| A decision's result, or a default | **NOTE** | never | one per answer | G10's "peu de retour des conséquences": the consequence card (PR #69) answers it |
| Acts between others | **NOTE**, off by default | never | none | the author's call at V5.1-0c |

- **The budget is per year at the default settings, and the probe measures
  it.** Today France meets 0.5 modal stops and 3 holding cards a year, well
  inside 4 and 6. **OPINION:** the room is there on purpose. V5.2's people and
  V5.3's graded decisions (G5) will add decisions, and the budget is what keeps
  them from turning speed 3 into a slideshow.

## The monthly briefing's measurement (V5.3-0)

[[v5.3-0-readability]] adds a briefing that holds the clock every month, an
exception the author chose outside the 4 + 6 budget. `--briefing` on the same
probe measures bands RF1, RF2, RF4 and RF9 for the four playable nations over
120 months, idle and in an active regime (every card answered with its first
non-default choice, every request delegated). A run stops at a defeat. The
holds are derived from the registers at the default settings, in the spec's
hold order (the probe's header lists the rule). The ranking, the situation and
the music band are Interface's own functions (`src/ui/priorities.gd`,
`src/ui/music_band.gd`), loaded at run time and never copied.

```bash
APPDATA="$(mktemp -d)" godot --headless --path . --script res://tools/decision_surfaces_probe.gd -- --briefing [--nations=DEU,FRA,GBR,POL] [--regime=idle|active|both] [--months=120] [--json=PATH]
```

**MEASURED** (2026-10-31): the probe at `28fb25d2` with Interface's
`interface/v5.3-0a-briefing` @ `8686d48e` merged in, `main` at `59d1a0d6`.

| Run | Months | Briefing / yr | Modal / yr | Cards / yr | Stops at 2 dismissals or fewer | RF1 | RF2 repeats, overlap | Bed changes / month |
|---|---:|---:|---:|---:|---:|---|---|---:|
| DEU idle | 37 | 11.7 | 0.3 | 1.9 | 97 % | pass | 3 %, 0.91 | 0.17 |
| DEU active | 37 | 11.7 | 0.3 | 1.0 | 100 % | pass | 0 %, 1.09 | 0.11 |
| FRA idle | 76 | 11.8 | 0.5 | 2.8 | 96 % | pass | 7 %, 1.00 | 0.16 |
| FRA active | 76 | 11.8 | 0.5 | 1.7 | 99 % | pass | 2 %, 0.71 | 0.16 |
| GBR idle | 120 | 12.0 | 0.3 | 2.0 | 98 % | pass | 2 %, 0.95 | 0.17 |
| GBR active | 120 | 12.0 | 0.3 | 1.4 | 98 % | pass | 2 %, 0.90 | 0.13 |
| POL idle | 69 | 11.8 | 0.5 | 2.1 | 99 % | pass | 7 %, 1.14 | 0.16 |
| POL active | 69 | 11.8 | 0.5 | 1.2 | 99 % | pass | 0 %, 0.81 | 0.04 |

- **RF4 passes everywhere.** The briefing is 12 a year, less in a year a defeat
  ends the game. Outside it, the holds stay inside the 4 + 6 budget, and a stop
  takes 3 dismissals at most 3 times in a run, 13 times over all eight runs.
  Eight of the 13 are a won election's month, where the result, the briefing
  and the term's programme offer meet. The other five are the briefing plus
  two cards.
- **RF2 fails once, and the ranking is not wrong to.** France idle, May 2029:
  two held cards and the EP election one month away (score 9.0) took the three
  lines. The request lapsing that month (6.4) was in April's briefing but not
  in its last month. The band as written calls that a failure; whether a
  crowded month may skip a request shown the month before is Interface's and
  Gameplay's call, not the probe's.
- **RF9 passes, and the music is almost always `tense`** (51 to 102 months out
  of 68 to 120), because a held card or a near weighty line is in most months'
  three. The bed changes rarely, so RF9 holds, but the calm bed is seldom heard.
- **Not seen in any run:** the `bill` kind, since neither regime tables a bill
  and no division ran. RF2's "every kind that qualifies appears" is reported,
  not gated, until `rank()` returns the kinds that qualified.
- **Defeats end three runs early** (DEU at month 37, FRA at 76, POL at 69),
  and they fall in the same month in both regimes: the active regime is no
  stronger at the ballot box.

## The state-visit outcome

There are two kinds of visit, and they want different surfaces.

- **A foreign leader visits France:** a **NOTE**, one per month at most (PR
  #70's rolling note). The visit asks nothing today. From V5.2, a visiting head
  of state is a person the president meets ([[v5.2-spec]], "The author's
  answers", 1), and a visitor with a want sends a **request card** instead.
  - **The cadence is the problem, not the surface.** 26.5 visits a year at one
    country is not "comme dans la vraie vie". The AI's targeting was recorded as
    a V5.2/V5.4 question at V5.1-0d (the V5 ledger, as above); a real rate is
    Systems' change, with a predicted re-baseline.
- **The president visits abroad:** a **MODAL scene** when the partner has a
  summit pool ([[summits-model]] §2), since the player booked it; otherwise a
  **NOTE** with the relations change, through the consequence card's path.

## What d can take, and what is V5.2's or V5.3's

| Change | Where | Size (OPINION) |
|---|---|---|
| The rolling state-visit note | d, already in PR #70 | done |
| The consequence card | d, merged as PR #69 | done |
| A "requests waiting" mark on the clock cluster, so a lane that never holds is still found | d, Interface | S |
| The budget re-measured after each block that adds an arrival kind | each block's gate, with this probe | S |
| Requests as cards that never hold, whose lapse is a decline | V5.2b (Interface and Systems) | in V5.2's plan |
| A visiting leader's want becomes a request | V5.2b | in V5.2's plan |
| The AI's state-visit rate made real | Systems, V5.2 or V5.4 | M, with a re-baseline |
| More decisions worth stopping for (grand plans, graded decisions) | V5.3 b and c (the author's G5) | in V5.3's plan |

**OPINION:** none of this needs a new pop-up. The modal set stays as it is, the
decision cards already stop the clock, and the work is the volume: fewer notes
that ask nothing, and more decisions that matter.

## What could not be verified

- The probe measures the sim's half. Which arrival pauses, cards or holds in its
  last month is read from `main.gd` and `message_settings.gd` at the default
  settings, not observed in a running window.
- The probe counts an arrival as an id on the desk after the Events step that
  was not on it before, so an event that defaults and re-arrives in the same
  month is missed. Today's cooldowns make that rare; none occurred in this run
  as far as the counts show (6 arrivals, 4 defaults, 2 left on the desk).
- One run, one nation, one seed (the hazard is deterministic). Other nations,
  and a player who acts, would see other counts.
- "Plausibly never seen: 0" assumes the player does not unpause past a hold.
