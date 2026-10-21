---
title: V5.2 bands — declared before the build
tags:
  - design
  - bands
---

# V5.2 bands — declared before the build

The player-outcome bands that judge V5.2, written **before** anything is built,
as the project's rule requires ([[people-model]] §14.6: "Written before the probe
ran (the project law)"). The design they judge is [[v5.2-spec]]. Each band names
what it measures, the probe that will measure it, and what a failure looks like.

These bands are not the balance re-baseline. Systems still predicts and measures
the 51-regime table for each of its PRs; V5.2's gate needs both ([[v5]], V5.2
done-when and gate).

**Nothing here is measured yet.** The numbers are declarations. Each one gives
its reason, labelled **MEASURED**, **INFERRED** or **OPINION** as in
[[v5.2-spec]].

## The bands answer the tier's four questions

V5's test, in the author's chair after thirty minutes: "can the player name
someone who asked them for something, say what refusing cost, point at something
they built and where, and say what they do not know and why" ([[v5]], head).

| Question | Bands |
|---|---|
| Q1 — someone who asked you for something | B1 requests, B2 booking load |
| Q2 — what refusing cost | B3 refusal priced |
| Q3 — something you built, and where | none: V5.3 and V5.4 own it |
| Q4 — what you do not know, and why | B4 lever odds by knowledge band, and the range widths |
| (the block's own) | B5 no dominant lever; B6 corruption exposure; B7 affair exposure; B8 lies caught |

## The frame: a play gate sees a third of a term

- **INFERRED (save and log timestamps):** the author's V5.0 session covered about
  22 game months in about 27 real minutes ([[v5.2-spec]], "the baseline"). So a
  30-minute play gate sees roughly the first 20 months of a 60-month term.
- Every per-term band below therefore carries a **first-20-months** corollary,
  because a band met only in years four and five is a band the play gate never
  sees.
- All bands are for a **France** game unless stated: the default nation, and
  the one whose numbers are known (61 people, 53 with a want; **MEASURED**, data
  read).

## B1 — Requests reach the player (Q1)

| | Declared |
|---|---|
| Requests arriving in the inbox, per 60 months, in an **idle** term (the player answers nothing) | **24 to 48** |
| First request | **by month 3** |
| Requests in months 1–20 | **at least 8** |
| Distinct people asking, per term | **at least 12**; no one person more than 25 % of the requests |

- **Why these numbers (OPINION, with INFERRED arithmetic):** at the author's
  pace of about 74 seconds a game month, 24 a term is one request every
  2.5 months, or about one every three minutes of play, and about 8 in a play
  gate. Below that, Q1 is luck. The ceiling of 48 (0.8 a month) plus the desk's
  12 events a term (**MEASURED**, `docs/someday.md`, "Open author calls", the ticked **Re-run `events_probe` E4/E5** item) makes about one thing
  asked of the player each game month, roughly once a minute and a quarter of
  play. More than that is a flood.
- **Counted at arrival in the inbox, not at generation**, so a request the desk
  drops is a miss ([[v5.2-spec]], pre-mortem cause 2).
- **Measured on an idle term**, because the want ladder's edge trigger fires 0
  acts in an idle term by design ([[people-model]] §14.6, P1), and a request
  generator that rides it would pass a managed run and fail the play gate.
- **Probe:** `tools/audience_probe.gd`, regime A1 (idle FRA, 60 months, through
  `WorldMonth.tick_month()` and its step hook, never a copy of the tick order).
- **Failure looks like:** fewer than 24, or a first request after month 3 (the
  V5.0 silence again); more than 48 (an inbox the player cannot read); one or two
  people asking for everything (a cast of two).

## B2 — The diary makes time scarce, and does not become a wall (Q1)

| | Declared |
|---|---|
| Share of requests a player who books every one cannot place inside the request's window | **20 % to 50 %** |
| **Audiences held per term** by that player (the done-when's "audiences per term") | **12 to 30**, and **at least 4** in months 1–20 |
| Requests that offer delegation and decline when the diary cannot place them | **100 %** |

- **Why (MEASURED anchor):** the V2.4a diary already measured 35 % of wants
  unplaceable with visits, a law and a reshuffle against a greedy packer
  ([[calendar-model]] §12). Audiences add load, so the band brackets that figure.
- **Why the audiences held (INFERRED arithmetic):** B1's 24 to 48 requests,
  less B2's 20 % to 50 % unplaceable, leaves roughly 12 to 38 a booking player
  can hold; the ceiling of 30 keeps the diary from being all audiences. At least
  4 in the first 20 months means a play gate contains several scenes, not one.
- **Probe:** `tools/audience_probe.gd`, regime A2 (book every request with the
  calendar probe's greedy packer).
- **Failure looks like:** fewer than 12 audiences held (the scenes are rare
  even for a player who wants them); under 20 % unplaceable (time is not scarce,
  and delegation is never needed); over 50 % (the diary is the wall, the R5 complaint "cannot register
  anything" in a new place); any unplaceable request without delegation and
  decline on its card (a dead end).

## B3 — Refusing costs something the player can see (Q2)

| | Declared |
|---|---|
| Declines and failed levers that write a non-zero change to the person's grudge, loyalty or rapport, **shown on the person's card** | **100 %** |
| A decline-everything term: acts (brief, resign, defect, challenge) by a person the player declined, by month 60 | **at least 1** |
| Same, by month 20 | **at least 1** visible consequence on a card (a grudge level named in words) |
| Decline-everything against idle: the change in the 2027 executive vote share | **at most 0.02** |

- **Why the ceiling (MEASURED anchor):** the hands-off France run holds the 2027
  election by a margin of 0.034 (QA's accepted base table
  `.superpowers/sdd/qa/base-4d2ce395.json`, the V5.1-0d re-baseline the author
  accepted: regime `hands_off`, FRA 2027-05, `margin` 0.0343). A ceiling of 0.02 keeps refusals alone from deciding
  the election: refusing costs relationships, and the relationships cost votes
  later, through the acts.
- **Probe:** `tools/audience_probe.gd`, regime A3 (decline every request
  explicitly), against A1. The card half is a UI check: a proposed
  `tests/test_playability.gd` entry (below).
- **Failure looks like:** a decline that changes no register, or one that
  changes a register no surface shows (Q2 unanswerable); no act in a
  decline-everything term (refusing is free); a swing above 0.02 (refusing is
  ruinous on its own).

## B4 — Knowing someone matters, and the fog is shown (Q4)

Knowledge bands: **stranger** `[0, 0.33)`, **acquaintance** `[0.33, 0.67)`,
**known** `[0.67, 1]`.

| | Stranger | Acquaintance | Known |
|---|---|---|---|
| Mean success of the lever the player would pick from what is shown | **0.30–0.50** | **0.45–0.65** | **0.60–0.80** |
| Width of the printed odds range | **at least 0.30** | between | **at most 0.10** |

| | Declared |
|---|---|
| Mean success rises from each band to the next by | **at least 0.08** |
| The true odds fall inside the printed range | **100 %** (the range never lies) |
| Interactions from stranger to acquaintance | **2 to 5** audiences that include another topic |
| Interactions to known | **at least 8** |

- **Why (OPINION):** the upper bound of 0.80 for a person the president knows
  well keeps the game unsolved. At least 8 interactions to know someone means a
  term cannot know all of France's 61 people (**MEASURED**), so the player
  chooses whom to learn. "Never lies" is the fog call taken by the author
  ([[v5]]: "fog is shown, never silent").
- **Probe:** `tools/lever_probe.gd`, regime L1 (every France person, each
  knowledge band, the lever picked by the shown odds).
- **Failure looks like:** the same success in every band (knowing people is
  worthless); above 0.85 for the known (a solved game); a range a stranger
  cannot choose from because every lever shows the same wide range (the
  V5.0 Q4 answer "je ne sais pas"); a true value outside its printed range.

## B5 — No lever dominates

The grid: France's 61 people with their authored traits × the three knowledge
bands × relationship (below friend, friend or closer) × the ask (aligned with a
want, against one) × the channel (audience, phone call).

| | Declared |
|---|---|
| Pairs of levers where one is at least as good on success **and** no costlier on every register, in every cell (Pareto dominance) | **0** |
| Share of cells in which one lever has the best net value | **at most 40 %** for any lever |
| Share of cells in which each lever has the best net value | **at least 5 %** for every lever |
| A phone call's odds against an audience's, same lever, same cell | **at least 0.10 lower** |
| The answers to a request — book, delegate, decline, and leaving it unanswered — any one of them the best net value over all requests | **at most 50 %** of requests |

- **Net value** is success × the ask's gain minus the expected cost, in the
  registers the lever spends. The probe's header states the exchange weights
  **before** the run, the way the events probe's E2/E3 were declared.
- **Why (OPINION):** 0 dominated pairs is the standard the author chose for the
  events in the same block ([[v5-reflection]] D15: "re-tune to 0 dominated
  pairs"). 40 % keeps one lever from being the default; 5 % keeps each lever
  from being dead content.
- **Probe:** `tools/lever_probe.gd`, regime L2.
- **Failure looks like:** one lever best in most cells (the player stops
  reading people and presses it); a lever never best (dead); calls as good as
  audiences (the diary becomes optional); leaving requests unanswered the best
  answer to most of them (the player learns never to open the inbox). The last
  depends on [[v5.2-spec]]'s question 3: if an unanswered request costs nothing,
  this row is expected to fail, and that is the argument for option (a).

## B6 — Corruption is tempting, and it is found out

Over 200 seeded runs (salts), France, otherwise idle.

| Regime | Declared |
|---|---|
| Corruption offers reaching the president per term | **2 to 6** |
| **Once:** one corrupt act at month 6, any currency — exposed by month 60 | **10 % to 30 %** of runs |
| **Always:** every offer accepted — exposed by month 60 | **at least 80 %** of runs |
| **Always:** median months to the first exposure | **at most 24** |
| Exposure odds by currency, for the same act size | **favours < party money < personal wealth < diverted budget** |
| Exposures by route in the "always" regime | **each route at least 20 %**: the press and the courts |

- **Why (OPINION):** one bribe in a term should usually stay hidden, or
  corruption is never worth trying; a habit should almost always be found, and
  inside the first two years, so the play gate can see it. The order of the
  currencies is the order of the evidence each leaves ([[v5.2-spec]], the
  currencies table).
- **Probe:** `tools/shadows_probe.gd`, regimes S1 (once) and S2 (always).
- **Failure looks like:** "always" exposed under 80 % (corruption is free);
  "once" exposed over 30 % (never worth it); the order broken (one currency
  dominates the others); one route carrying nearly every exposure (the courts'
  half of "exposure through the press and the courts" is a new trigger,
  [[v5.2-spec]] C7, and the easiest to leave unbuilt).

## B7 — The affair is dangerous

| | Declared |
|---|---|
| An affair kept for 24 months — exposed by month 60, over 200 seeded runs | **25 % to 50 %** |

- **Why (OPINION):** the author asked for a "secret, dangerous affair if the
  president is married" ([[v5-reflection]] §0). Below 25 % it is not dangerous;
  above 50 % it is not secret.
- **Probe:** `tools/shadows_probe.gd`, regime S3.
- **Failure looks like:** exposure outside the band.

## B8 — Lies are caught by people who read well

| | Declared |
|---|---|
| A lie to a listener with reading skill **above 0.67**, against a president of middling deceiving skill — caught | **40 % to 70 %** |
| The same, a listener **below 0.33** — caught | **5 % to 20 %** |
| A broken dated promise — revealed at its date | **100 %**, with no roll |

- **Why (OPINION):** social skill must matter both ways, as the author asked
  ("whether you catch a lie", [[v5-reflection]] §0, Social skill), and a promise
  with a date is a lie the calendar keeps.
- **Probe:** `tools/shadows_probe.gd`, regime S4.
- **Failure looks like:** the same catch rate at both skills (skill is
  decorative); a broken date that is not revealed.

## Invariants (pass or fail, not bands)

- **I1 — Determinism.** Two identical states produce the same requests, the same
  rolls and the same exposures. No `rand()`; rolls are seeded over the ids, the
  month and a salt ([[v5]], "Chance is seeded"). The precedent is
  [[people-model]] §14.6, P5, pinned by a two-identical-states check.
- **I2 — The save table holds.** Every new register reads correctly when
  absent ("never met"), so no `SAVE_VERSION` bump ([[v5]], V5.2 done-when). The
  `absent_ok` verdict per register is proposed in [[v5.2-spec]];
  `tests/test_nation_fields.gd` pins the false set.
- **I3 — A scene holds the clock** while it is open ([[v5-reflection]] T11).
- **I4 — Inertness, as an expectation.** The AI nations book no audiences, so
  the balance table should not move unless an unanswered request counts as a
  decline ([[v5.2-spec]], question 3). Systems writes the prediction.

## The probes, declared

| Probe | Regimes | Bands |
|---|---|---|
| `tools/audience_probe.gd` | A1 idle, A2 book everything, A3 decline everything | B1, B2, B3 |
| `tools/lever_probe.gd` | L1 by knowledge band, L2 the grid | B4, B5 |
| `tools/shadows_probe.gd` | S1 once, S2 always, S3 affair, S4 lies | B6, B7, B8 |

Each one drives `WorldMonth.tick_month()` through its step hook
(`tests/test_world_month.gd` fails a copy of the tick order), runs isolated, and
writes a JSON table the way `tools/balance_probe.gd -- --json=PATH` does, so
the verdicts are diffable. The probes are Systems' to write; their names and
regimes are fixed here so the build cannot choose its own test.

## Proposed `tests/test_playability.gd` entries

- **`_check_idle_term_first_request`** — a new France game, no input: a request
  reaches the inbox by month 3 (B1's first cut, fast enough for the suite).
- **`_check_decline_shows_its_price`** — decline a request: the person's card
  names the change in words (B3's card half).

## What could not be verified

- No band here is measured; the probes do not exist yet.
- The author's pace comes from one session's timestamps, with boot and menus
  included.
- The share of personal-category events in the desk's 12 a term was not
  measured.
