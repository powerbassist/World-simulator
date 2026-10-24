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
  22 game months in about 27 real minutes: the save `ABOBA.json` holds the game
  date 2027-11-08 and was written 27 minutes after the session's log began
  ([[v5.2-spec]], "the baseline", which cites both). So a
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
| Requests arriving in the inbox, per 60 months, in an **idle** term (the player answers nothing, so every request lapses into a decline) | **24 to 48** |
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
- **The idle term declines everything by lapse** (the author's call,
  2026-10-21). So the band also checks that declined people go on asking: a
  request trigger that falls silent once a person holds a grudge would fail
  B1 here, in the very regime the play gate's first minutes look like.
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

### B1 amendment (2026-10-24): no silent year, and a per-game seed

Declared before Systems adds the seed and runs it (QA's pre-gate B, CALL 2, in
`.superpowers/sdd/v5.2-pregate-b-report.md`).

**Why (MEASURED, QA, on a played run, not an idle A1 term: answers, a
reshuffle and a re-election):** domestic arrivals were 21 in months 1–20, then
**1 in months 21–38**. No gate was closed. The draw `Cycle.unit_pair(person_id,
"audience_request", month)` has no per-game seed, so every France game draws
the same sparse months. B1 counted per 60 months and floored only months 1–20,
so the band passed while the author would meet a silent year.

**The rows** (an idle term, `audience_probe` A1, read over **20 seeds**):

| | Declared |
|---|---|
| Every 12-month window of the 60-month run (France's first term, 16 months, and part of the second; 49 sliding windows) holds at least **1** arrival | in at least **95 %** of seeds (19 of 20) |
| Every 12-month window holds at least **2** arrivals | in at least **80 %** of seeds (16 of 20) |
| The first request by month 3, by the guarantee below | **100 %** of seeds, and of every played nation |
| B1's other existing rows (24 to 48 a term, at least 8 in months 1–20, at least 12 people, no one over 25 %), each read per seed | each in at least **90 %** of seeds (18 of 20) |
| B2's rows (`audience_probe` A2) and B3's act rows (A1 and A3), each read per seed over the same 20 seeds | each in at least **90 %** of seeds (18 of 20) |

**The guarantee (the parent's decision, 2026-10-24, on QA's call).** Q1,
"someone asked you something", is the tier's gate question, and the author plays
one game. A one-in-twenty miss could land on the gate, so the first request is
guaranteed by a stated mechanism, not left to sampling luck:

- If the draw has brought no request by the end of month 2, then in month 3 one
  candidate asks, about their unserved want.
  - **The candidates are the draw's own:** people for whom `Audiences._may_ask()`
    holds (not the leader, past the 8-month cooldown, no open request) and who
    carry a want that is not served (the draw's `_unserved`). A want of any
    kind counts, programme stances included. A request asks; whether the
    president can serve it now is the player's answer, not the trigger's.
  - **The one who asks** is the candidate with the highest standing, the
    hazard's own weight (0.5 + standing). Ties go to id order, so the choice is
    deterministic (I1). No want carries a weight of its own, so the want asked
    about is the one `_unserved` returns, as in the draw.
  - **No candidate:** the guarantee needs at least one, so its 100 % holds by
    mechanism only while the set is non-empty in month 3. Systems' test checks
    it for each of the four playable nations at a forced empty draw. A nation
    with no candidate would read as a miss on this row, and it is reported to
    the author, not hidden by a fallback.
- It fires at most once a game, only in month 3, and only when the draw gave
  nothing.
- **Re-baseline (INFERRED, before Systems' run):** at seed 0, France's first
  request arrives in month 2 (MEASURED by QA: February 2026), so the guarantee
  does not fire, and the France regimes stay ZERO. The one other played run,
  `managed_abolishes_the_monarchy` (GBR), may fire it; if it does, its rows
  move. That is predicted here, and the author accepts it.

**Why these numbers (OPINION, with INFERRED arithmetic on a model of the draw):**

- I simulated a Poisson arrival process (only a monthly rate enters it), 60
  months and the 49 sliding windows, 4 000 trials per cell. It gives the share of
  games whose emptiest year still holds N arrivals:

  | Rate | A term | N ≥ 1 | N ≥ 2 | N ≥ 3 |
  |---|---|---|---|---|
  | 0.4 a month | 24, B1's floor | 87 % | 51 % | 18 % |
  | 0.5 a month | 30 | 95 % | 77 % | 43 % |
  | 0.6 a month | 36, B1's middle | 98 % | 90 % | 69 % |

- **The model's limits:** it leaves out the game's gates (an 8-month cooldown
  per person, at most 4 pending, a standing floor) and the invitation triggers
  (a programme going live at a term's start, the month after a reshuffle),
  which bunch arrivals at term starts outside the hazard. So the real process
  may be more regular or more clumped. The percentages show the order of magnitude;
  they are not measurements of the game.
- **Sampling noise:** with 20 seeds, a process that truly meets 98 % (B1's
  middle rate, N ≥ 1) passes the 19-of-20 row with probability 0.94. One that
  meets 90 % (N ≥ 2) passes the 16-of-20 row with probability 0.96. One that
  meets exactly 95 % passes only 0.74 of the time. A miss by a single seed is
  therefore reported as such, beside the per-seed minimums, when it goes to the
  author.
- **A floor of 3 a year is not declared:** even at B1's middle rate, the
  draw's luck would fail it in a third of games. The design would not be what
  decided it.
- **What the declared floors do:** they rule out QA's silent year (one arrival
  in eighteen months) in nearly every game.
- **They also bind B1's lower end.** A term near 24 a term fails them
  (INFERRED). That is intended: B1's floor with clustered months is exactly
  the silent year. The window rows ask for a rate of at least about 0.5 a
  month, spread across the term.

**The seed's re-baseline, expected before the run:**

- **`balance_probe` and the 51-regime table: ZERO**, provided seed 0
  reproduces today's draw exactly. The seed enters the salt only when it is
  non-zero, so `cmp` against the accepted table is identical. The balance
  regimes run at seed 0. A table that moves means seed 0 is not today's draw,
  and that is a bug to fix, not a re-baseline to accept.
- **`audience_probe`: it moves, by design**, because it now reads 20 seeds
  instead of one draw. Every B1–B3 row it reads is read per seed against
  the 90 % rows above. B3's 2027 rows stay on `balance_probe` at seed 0, and
  B3's per-request price equality (`tests/test_audiences.gd`) is
  seed-independent. Neither moves.
- **The game:** a new game draws a fresh seed, and a save carries it. An
  older save without a seed reads seed 0 (today's draw), which is absent-ok,
  so no `SAVE_VERSION` bump.

**Probe:** `tools/audience_probe.gd` A1 over seeds 1–20, with the 49 windows'
minimum per seed. **Stop rule:** one run. A miss goes to the author, and the
floors are not re-tuned to the run.

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
| A request left unanswered past its window costs at least what an explicit decline of the same request costs | **100 %** of requests |
| The hands-off France run, every request lapsing into a decline (the author's call of 2026-10-21), against the accepted table with no requests: the **2027 executive verdict** | **unchanged** (HELD stays HELD) |
| The same comparison: the change in the **2027 margin** | **at most 0.017** in absolute value |

- **Why the margin and not the vote share (MEASURED anchor):** the hands-off
  France run holds the 2027 election by a margin of 0.034 (QA's accepted base
  table `.superpowers/sdd/qa/base-4d2ce395.json`, the V5.1-0d re-baseline the
  author accepted: regime `hands_off`, FRA 2027-05, `margin` 0.0343). A first
  draft bounded the vote share at 0.02, which does not protect that margin: a
  share the incumbent loses to the runner-up moves the margin by twice as much,
  so a 0.018 loss would flip the election inside the band (QA's finding). The
  band therefore bounds the margin itself, at half the anchor, so even the
  worst case leaves the incumbent ahead, and states the verdict outright so a
  reading of the number cannot hide a flip. Refusing costs relationships, and
  the relationships cost votes later, through the acts; it must not decide the
  election on its own.
- **Why the comparison is idle against the accepted base (the author's call,
  2026-10-21):** an unanswered request is a decline once its window passes
  ([[v5.2-spec]], "The author's answers", 3). An idle term therefore declines
  everything by lapse, so the band compares it with the table before V5.2.
  **This row is also the bound on the re-baseline** that Systems predicts and
  the author accepts at build time.
- **Probe, the path that already works:** `tools/balance_probe.gd -- --json=PATH`
  at the build tip, regime `hands_off`, against `base-4d2ce395.json` (or the
  base Systems names at build time), compared with
  `python tools/balance_diff.py base.json tip.json`. The table already carries
  `verdict`, `vote_share` and `margin`, and `balance_diff.py` reports a FLIP or
  a MARGIN move. The lapse-against-decline row is `tools/audience_probe.gd`'s:
  regime A3 (decline every request explicitly) against A1 (every request
  lapses). The card half is a UI check: a proposed `tests/test_playability.gd`
  entry (below).
- **Failure looks like:** a decline that changes no register, or one that
  changes a register no surface shows (Q2 unanswerable); no act in a
  decline-everything term (refusing is free); a 2027 flip or a margin move
  above 0.017 (refusing is ruinous on its own); a lapse cheaper than a decline
  (ignoring becomes the best answer).

### B3 amendment (2026-10-24): the cost fades

Declared before Systems' run, at Systems' request. The author's call, verbatim:
"Le coût s'efface". The `bloc_offset` that a character act writes (brief, resign,
defect, challenge: V4.3's acts, and V5.2b's through them) now fades, with a
half-life of about 24 months. In Systems' words: a leak hurts the next vote, then
it is forgotten. Everything but acts stays permanent: laws, events, the
programme, campaigns, referendum results (`REFERENDUM_RESULT_OFFSET`) and the
second chamber's overrides. Only acts fade, the old V4.3 acts as well as the
new ones.

**Why (MEASURED, Systems' run of PR #104, `.superpowers/sdd/qa/tip-104-e32c19cb.json`
against `base-19ff21fc.json`):** with a permanent accumulator, the refusal
grudges #104 feeds into briefs:

- saturate workers and students at the clamp in `tests/test_balance.gd`'s
  168-month MANAGED runs (Systems' report);
- flip France's 2032 executive from HELD to LOST in 28 of the 41 regimes that
  reach it;
- move the 2029 legislative margin by a mean of -0.0164 (worst -0.0181), with
  the government's standing unchanged in 41 of 41;
- leave 2027 untouched: every one of the 50 rows has a margin delta of 0.0000.

**The rows:**

| | Declared |
|---|---|
| The fade's half-life (the constant) | **24 months**, inside a band of **[22, 30]** |
| One act, then no further act: the fraction of that act's price left at H months, then at 2H, H the shipped constant inside [22, 30] | **50 %, then 25 %**, each to within 1 point; never past zero |
| The act-written part of `bloc_offset`, in offset points, any bloc, any month, every `tests/test_balance.gd` MANAGED regime, over the months the player is in office (while `in_government` holds: to an executive loss, the term limit, or month 168; see "Correction: the read window" below) | **at most 0.50** in absolute value |
| The same runs: a bloc's whole `bloc_offset` at ±1.00 that was not at it in the same run at `19ff21fc` (the main behind `base-19ff21fc.json`, before #104), read over the same months as the tip run (Systems runs it once as the base; see "Correction: the read window" below) | **none** |
| The 2027 executive (B3's rows above) | **unchanged:** verdict held, \|Δ margin\| ≤ 0.017 |
| The 2029 legislative, every regime with a FRA 2029 row (41): the government's standing (`majority` / `MINORITY` / `COHABITATION`) | **unchanged** in every row |
| The same rows: the change in the 2029 margin | **at most 0.017** in absolute value, every row |
| The 2032 executive, every regime with a FRA 2032 row (41): the change in the margin | **at most 0.017** in absolute value, every row |
| The 2034 legislative, every regime with a FRA 2034 row (28): the standing and the margin | **reported**, not banded. A 2034 row exists only where 2032 held (the 28 base rows are exactly the 28 that hold 2032), so each 2032 flip removes one, and `balance_diff.py` prints it as "ONLY base" |
| The one non-FRA played run, `managed_abolishes_the_monarchy` (GBR, national votes 2029, 2034, 2039): the verdict | **unchanged** in all three (HELD stays HELD); the margins are reported |

**The comparison base.** Every row above that compares two tables compares the
build tip (#104 with the fade) against **`base-19ff21fc.json`**, the accepted
table from before requests existed, with `python tools/balance_diff.py`. B3's
2027 rows already work this way. The comparison must not be against
`tip-104-e32c19cb.json`: against #104's permanent cost, every delta reads
positive and says nothing about what declining everything costs. Report the mean
and the flips beside each row. The rows bound each row's move, not the mean.

**Why 22 to 30 months (OPINION, derived from MEASURED spacings):**

- France's votes in the base table are 25 months apart (2027-05 to 2029-06) and
  35 months apart (2029-06 to 2032-05), so the vote after next comes about 60
  months after an act.
- "Hurts the next vote": at least 0.33 of the price must remain at the
  longest gap to the next vote, 35 months. That needs H ≥ 35 · ln 2 / ln(1/0.33),
  so H ≥ 21.9, and the band's lower end, 22, keeps 0.332.
- "Then it is forgotten": at most a quarter may remain at the vote after next,
  60 months. That needs H ≤ 30. The 60 months hold for an act just after a
  vote. An act just before a vote meets the vote after next 25 to 36 months
  later, with 35 to 49 % left at H = 24, so "forgotten" is true of early-term
  acts, and a late-term act still reaches two votes (INFERRED from the same
  arithmetic).
- The author's 24 sits inside the band. The band is the stop rule's room, not a
  licence to tune.

**Why 0.50 for the act share, and not the clamp:**

- A band that measures a clamp measures nothing. This is the correction V1.6d
  and V1.6e both made, recorded in `src/sim/chambers_constants.gd:204-213`
  (`d6c74b23`).
- The permanent channels (laws, events, the programme, campaigns) may still
  approach ±1.00 over fourteen years, as U0's thirteen overrides did. So the row
  bounds the act register alone, at half the clamp. The other half of the room
  is left to everything that does not fade.
- At the measured 10.0 approval points per point of offset
  ([[referendum-model]], `REFERENDUM_RESULT_OFFSET`'s row, measured on the approval
  response), 0.50 is about 5 points of approval held by acts alone (INFERRED: a
  unit conversion, not a run).
- P4, the existing readability bound (total approval movement from acts within
  ±3.0 points a year, `src/sim/character_act_constants.gd:195-197`), still binds
  and is not redeclared here.

**Why 0.017 at 2029 and 2032, by row (OPINION):**

- The fade exists so that the vote after next costs no more than B3 already lets
  the next one cost. So the bound is B3's own 0.017, half the hands-off 2027
  margin.
- **The 2032 base is knife-edge (MEASURED, `base-19ff21fc.json`):** 28 regimes
  hold 2032, every one of them by less than 0.029, and the hands-off run already
  loses it (margin -0.0072).
- **"No flips" is rejected:** a 2032 row held by 0.0023 cannot honestly be
  guaranteed against any refusal cost.
- **A doubled bound (0.034) is rejected too:** no held 2032 margin exceeds it, so
  it would permit every flip.
- **What 0.017 holds:** at 0.017 per row, seven regimes must stay HELD, since
  their base margins (0.0184 to 0.0289) exceed the bound:
  - `managed_keeps_its_word`
  - `managed_imposes_tariffs`
  - `public_works`
  - `managed_then_build`
  - `managed_settles`
  - `managed_answers_hard`
  - `managed_answers_softly`
- **What it lets flip:** the other 21 held rows are coin tosses that may flip
  inside the bound. Each flip is reported by regime and goes to the author's
  acceptance of the re-baseline (invariant I4), not to a new call.
- **GBR, the one non-FRA played run (MEASURED):** its base margins are wide
  (0.142, 0.1612, 0.116). Under #104's permanent cost, 2029 did not move, 2034
  fell to 0.1029 and 2039 flipped to LOST (-0.0907), the hardest move in the
  table. With margins that wide, the verdict discriminates where FRA 2032's
  does not, so the row is B3's own "must not decide the election on its own":
  HELD stays HELD.
- **2029:** the margin row nearly held even under the permanent cost (worst
  0.0181). The standing row is the verdict that matters there, because a
  legislative election cannot remove the president. The incumbent's seats are
  reported beside it (#104: -6 to -16, mean -14.7) and not banded.

**No prediction of what 24 months yields (INFERRED):** under the permanent cost,
the margin moved about 5.7 times as much between 2029 and 2032 for twice the
time. The growth is not linear, so a closed-form estimate of the faded run would
be invented, and none is given. The run decides.

**The stop rule, fixed before the first run:**

1. Run at H = 24.
2. If a row misses, one re-run at the short end of the band, H = 22.
3. If a row still misses, it is the author's call, not a third patch. The
   options:
   - a half-life below the band;
   - smaller act prices (`PRICE_BRIEF` -0.25 and the others,
     `src/sim/character_act_constants.gd:199-202`);
   - accepting the loss as the price of declining everything.

**B3's act row stays** ("at least 1 act by month 60" in a decline-everything
term):

- It is what makes refusing visible, and dropping it fails Q2.
- Systems reports that it needs `DECLINE_GRUDGE` at 0.18 (in #104): at 0.12,
  nobody the player refused reaches the brief gate
  (`GRUDGE_BRIEF_THRESHOLD` 0.45, `src/sim/character_act_constants.gd:191`).
- The grudge keeps its own decay. The fade touches only the price an act writes.
- So "a refusal is answered by an act" and "the act does not decide the vote
  after next" hold together only with the fade. That is the design argument for
  the mechanic.

**Probes:**

- `tools/balance_probe.gd -- --json=PATH` at the tip, then
  `balance_diff.py base-19ff21fc.json tip.json`, for the 2027, 2029 and 2032
  rows.
- `tests/test_balance.gd`'s MANAGED runs, reading the act register monthly, for
  the act-share and clamp rows.
- A new unit test, proposed below, for the half-life row.

**Failure looks like:**

- an act share past 0.50, or a bloc on the clamp it did not reach before #104
  (the fade is not fading);
- a seven-regime 2032 flip, or any row past 0.017 (declining everything still
  decides the vote after next);
- a 2029 standing change;
- a GBR verdict flip in `managed_abolishes_the_monarchy`;
- a half-life that is not 50 % at H months (the constant is wrong).

### B3 amendment, measured, and the author's call (2026-10-24)

**The author's call** (step 3 of the stop rule, through the parent's question
tool), verbatim: "Accepter : il perd 2032". H = 22 still missed, so the 2032
losses are accepted as the price of declining every request for six years. The
half-life that ships is **H = 24**. The amendment's rows above stay as declared;
this subsection records what they measured and what the author accepted.

**Measured** (MEASURED; QA's re-score of Systems' runs against `base-19ff21fc.json`):

- At H = 24: Systems' `bal_b1_fade.json` at `f2653c3a`, which is cmp-identical to
  QA's own run of PR #104 at `dadbdf68`.
- At H = 22: Systems' `bal_b1_fade22.json`.
- The act-share and clamp rows: an instrumented `tests/test_balance.gd`, not
  committed.
- Sources: `.superpowers/sdd/v5.2b-fade-bands-result.md` and `qa-report.md`,
  sections "PR #104 @ dadbdf68" and "PR #104 @ c92f0846".

| Row | H = 24 | H = 22 | Status |
|---|---|---|---|
| Half-life, one act: 50 % at H, 25 % at 2H | PASS (`test_characters`) | — | holds; QA RECORD: the test pins the literals 24 and 48, not the shipped constant (Systems' to fix) |
| 2027 executive: verdict and \|Δ margin\| ≤ 0.017 | PASS, all 50 rows unchanged | PASS | holds |
| 2029 standing unchanged | PASS, majority in 41 of 41 | PASS | holds |
| 2029 \|Δ margin\| ≤ 0.017 | PASS: mean -0.0102, worst -0.0112; incumbent seats -4 to -10 | PASS: worst -0.0108 | holds |
| 2032 \|Δ margin\| ≤ 0.017 | MISS: 41 of 41 past; smallest move -0.0271, mean -0.0478, worst -0.1154 | MISS: smallest -0.0257, mean -0.0460 | **accepted** by the author's call |
| The seven regimes stay HELD in 2032 | MISS: all seven LOST (tip margins -0.0035 to -0.0195) | MISS | **accepted** |
| 2032 flips | 28, HELD to LOST | the same 28 | **accepted** |
| 2034 legislative (reported) | the 28 rows are gone: no 2034 vote follows a 2032 loss | the same | reported |
| GBR `managed_abolishes_the_monarchy` verdict unchanged | MISS: 2039 HELD to LOST (0.116 to -0.0157); 2034 held (0.1612 to 0.1416); 2029 unchanged | MISS: 2039 LOST at -0.0104 | **open**: waits for Systems' explanation of the -0.13 move |
| Act-written part of `bloc_offset` ≤ 0.50 | MISS: -0.592 in every FRA run, -0.615 in the GBR ten-year run; all nine other instrumented runs breach (termed-out, subsidised, regulated, redistributive, nuclear, nationalised, gas, dissolution, captured-court) | MISS: -0.576 (FRA), -0.594 (GBR) | see below |
| No new clamp | MISS: runs 1 and 18 (workers, students, 2032-08), run 16 (students, 2029-11) | MISS | see below |

**The two health rows.** The author's words did not name the act-share ceiling
or the no-new-clamp row. The author's second answer settles them: they are NOT
accepted, and the brief price is cut so that both come back inside their bands
("B3 amendment, the brief price" below).

Both were read from an instrumented `test_balance` that kept `_play`'s default
`stop_on_loss = true` for most runs (runs 1 and 18 played past the 2032-05 loss,
which is where they clamp), not the declared runs to month 168. QA notes that this
leaves the misses standing: a longer run can only add to a breach, and the base
runs that held 2032 reached month 168 without these clamps. A future price change
is measured over the read window ("Correction: the read window" below).

Both rows stay bands, and they gate the run at the new price.

**What the half-life changed** (MEASURED, from the two runs): almost nothing.
The 2032 mean moved -0.0478 at H = 24 and -0.0460 at H = 22. The 2032 harm comes
(INFERRED, Systems' reading; no run attributes the cost by year) from briefs in
the term's years four to six, which no half-life near two years
clears before that vote. For those briefs 2032 is the NEXT vote, not the vote
after next, so the fade's purpose ('forgotten by the vote after next') is not
what failed. What the fade did do: the 2029 cost fell from #104's mean -0.0164
to -0.0102, and against #104's permanent cost every one of the 83 rows that
changed past tolerance moved up (MEASURED, against `tip-104-e32c19cb.json`). What it cannot do is make a
president who answers no one for six years safe in 2032. The author chose that
this is the honest price.

**Prediction against result** (MEASURED, QA): Systems predicted 0 to 15 flips in
2032 and a mean between -0.005 and -0.05. The mean landed inside that range;
the flip count, 28, did not.

**The re-baseline.** Accepting the loss makes `bal_b1_fade.json`
(= `tip-104-dadbdf68.json`) the candidate table for the next sim PR to compare
against, as invariant I4 requires. The acceptance is not complete until Systems
explains GBR 2039's -0.13 move and the parent records the author's word on it.
If that explanation changes the sim, the table is re-measured and accepted again.

### B3 amendment, the brief price (2026-10-24)

The author made two calls on 2026-10-24, through the parent's question tool.
Both are quoted verbatim, and this subsection declares the rows for the run that
follows them, before Systems runs it.

1. **"Accepter : il perd 2032"**: a president who declines every request for six
   years may lose 2032.
2. **"Fuite 40 % moins chère"**: this is Gameplay's option A. A brief's price
   (`PRICE_BRIEF`, `src/sim/character_act_constants.gd:202` on main; `:226` at #104's head) goes from **-0.25
   to -0.15**. The other act prices are unchanged (resign -0.8, defect -0.5,
   challenge -0.6).

The half-life stays at **H = 24**. The re-run at H = 22 moved the 2032 mean only
from -0.0478 to -0.0460 (MEASURED, the subsection above).

**What the two answers settle.** The 2032 rows are accepted (answer 1). The two
health rows are not, and they gate again: the price exists to bring them back
inside the band (answer 2). The 2032 row becomes reported; the 2034 row was
reported already.

| Row, at the new price, against `base-19ff21fc.json` | Declared |
|---|---|
| The half-life, one act: 50 % at H, 25 % at 2H | **unchanged**, a band |
| The act-written part of `bloc_offset`, in offset points, any bloc, any month, every `tests/test_balance.gd` MANAGED regime, over the months the player is in office | **at most 0.50**, a band |
| The same runs: a bloc's whole `bloc_offset` at ±1.00 that was not at it in the same run at `19ff21fc`, read over the same months | **none**, a band |
| The 2027 executive | **unchanged** (B3's rows), a band |
| The 2029 legislative: the standing, and \|Δ margin\| ≤ 0.017 in every row | **unchanged**, a band |
| B3's act row: at least 1 act by month 60 in a decline-everything term | **unchanged**, a band |
| The 2032 executive: the margins and the flips | **reported**; they go to the author's acceptance (invariant I4) |
| The 2034 legislative rows | **reported** |
| GBR, `managed_abolishes_the_monarchy` (2029, 2034, 2039): the verdicts and the margins | **reported**, and **shown to the author before #104 merges** |
| P4 (approval movement from acts within ±3.0 points a year) | still binds |

**Correction: the read window (2026-10-24, before the run at the new price).**
This replaces the earlier wording "played to month 168 with
`stop_on_loss = false`" (QA's TAKE 3 on PR #109). It is a correction, and the
band values do not change:

- **The window:** the act-share row and the clamp row read only the months the
  player is in office, in base and tip alike: while `in_government` holds
  (`tests/test_balance.gd:279-284`). Office ends at an executive loss or at the
  term limit: a France run that holds 2032 is termed out at 2037-05, and
  `main.gd:697-700` then sends the player to the menu. A run that is never
  out of office is read to month 168. This is `_play`'s default
  `stop_on_loss = true`.
- **The base comparison:** a tip run is compared with its base run over the same
  months. A clamp the base reaches only after the tip run's last month does not
  excuse the tip. A clamp the tip would reach after it leaves office does not
  count against it.

**The reason:**

- The game ends when the president leaves office, whether by a lost election or
  by the term limit. Months after that are a world the player never sees, where
  out-of-office acts burst; a band that measures them judges a sim the game does
  not run. This is the AGENTS.md lesson "green is not measured", read from the
  other side.
- QA measured the old wording's cost (MEASURED, QA's call 2 to the parent):
  - 17 of the 18 runs clamp, every one of them after the 2032 loss, in months the
    game never plays.
  - Two clamps the base also reaches come years earlier at the tip: run 16
    (students, 2029-11 at the tip, 2036-10 in the base) and run 9 (workers,
    2031-08). Under the new window these count as NEW clamps at the old price,
    which is the point of the window.
  - "Same length" therefore compared a tip that clamps only in unplayed months
    with a base that clamps in played ones.
- QA's TAKE 3 asked that the base and tip runs cover the same span. Comparing
  over the same months keeps that.

**Why the health rows can come back (INFERRED):**

- A brief's count comes from grudges crossing `GRUDGE_BRIEF_THRESHOLD`, not from
  its price, so cutting the price leaves the number of briefs where it was.
- The new clamps are on workers and students, which are `BRIEF_BLOCS`, the blocs
  a brief lands on.
- If briefs carry most of the act-written part, a price at 0.6 of the old one
  takes the measured peaks (-0.592 for FRA, -0.615 for GBR) to about -0.36. That
  is inside 0.50 with room to spare.
- Resignations, defections and challenges keep their price. Where they carry a
  large part of the peak, the share falls less than that.
- No figure is predicted for 2032. Its growth is not linear (the subsection
  above), and it is now reported rather than banded.

**Why 2029 stays a band.** It passed at the old price (worst -0.0112, MEASURED).
A cheaper brief makes each brief cost less, and its count comes from grudges, not
from its price (INFERRED, the same argument as above). A second-order path
remains possible: a different approval path can change other events and the
requests behind grudges. So a 2029 miss at the new price is explained before
#104 merges, either as such a path or as a bug.

**Why 2032 and GBR are reported, not banded.** The author has accepted the 2032
loss as the price of declining everything (answer 1). GBR's 2039 move (-0.13 at
the old price) still waits for Systems' explanation. The parent shows it to the
author with the measured table before #104 merges, so it is reported here
instead of banded.

**The stop rule for this run, fixed before it:**

1. Run once at -0.15.
2. If the act-share row or the clamp row misses, it is the author's call again,
   not a third patch. The options:
   - a smaller price again, and by how much;
   - accepting the health misses.
3. If a 2027 or 2029 row misses, stop and report it to the parent before
   anything else. It is not expected to happen. #104 does not merge until it is
   explained (see "Why 2029 stays a band"), and the author accepts it or a fix
   lands.

**Probes:**

- `tools/balance_probe.gd` at the tip, then
  `balance_diff.py base-19ff21fc.json tip.json`. This covers the 2027, 2029 and
  2032 rows, the 2034 rows and the GBR rows.
- The instrumented `tests/test_balance.gd` reads, over the read window above
  (`_play`'s default `stop_on_loss = true`), for the act-share row and the clamp
  row.
- `tools/audience_probe.gd`, for B3's act row.

### B3 brief price, measured and accepted (2026-10-24)

The run at -0.15 (MEASURED, Systems' PR #104 at `97079bec`, against this section's
rows at `2078b63d`). Sources: `.superpowers/sdd/systems-104-brief015/` and
`band_rows.txt`. The table is `bal_b1_brief015.json`, byte-identical to QA's
`qa/tip-104-2027e227.json`.

| Row | Measured | Status |
|---|---|---|
| Half-life | `test_characters` passes | PASS |
| Act-written part of `bloc_offset` ≤ 0.50, months in office | max 0.355 (2031-08, workers) | PASS |
| No new clamp, months in office | one: run 16 (the captured court), students, from 2029-11 | MISS, **accepted** |
| 2027 executive | 50 of 50 rows, delta 0.0000 | PASS |
| 2029 legislative | standing unchanged in 41 of 41; mean -0.0061, worst -0.0067 | PASS |
| B3's act row | `audience_probe` 12 of 12 | PASS |
| 2032 executive (reported) | 25 of the 28 held rows flip to LOST; mean -0.0272, worst -0.1135 | **accepted** |
| GBR 2039 (reported) | HELD, 0.116 to 0.089 | **accepted** |

**The author's calls**, verbatim, through the parent's question tool:

1. **"Accepter ce cas".** The one clamp miss is accepted as a named exception.
   - It is run 16, the captured court, on students from 2029-11.
   - There the base alone already holds students at -0.79, which leaves 0.209 of
     headroom. A brief's full share in that run is 0.356 (MEASURED, read from
     workers, who carry the same price and never clamp).
   - The permanent channels, not the acts, own most of that room.
   - Clearing it would have taken a price of about -0.08 in every run (INFERRED,
     Systems' scaling). That is a third of V4.3's price, and it would make a
     brief nearly invisible.
   - The no-new-clamp row stays a band for every other run, and for any later
     price.
2. **"Oui, fusionner".** The re-baseline is accepted: `bal_b1_brief015.json` is
   the table the next sim PR compares against (invariant I4).

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

### B4 amendment (2026-10-24): the shown window only narrows

Declared before Systems builds it (QA's pre-gate B, RECORD 6).

**Why (MEASURED, QA):** Turcy's Promise read 47–83 % before a friendly topic
("Their opinion", rapport +0.04, knowledge +0.07) and 32–68 % after. The width
stayed at 36 points, and the window fell by 15 points while the true odds can
only have risen. `src/sim/lever_odds.gd`'s `shown_range` re-draws the fog offset
at each knowledge step (the fix for QA's R1 on #113, so that two readings at
different widths could not be solved for the truth). The re-draw also lets
the window jump anywhere, including downward.

**The rule:** between two readings of the same person and lever, the window
measured from the true odds is nested.

- With p the true odds and [lo, hi] the shown window, then from an old reading
  to a new one: lo_new − p_new ≥ lo_old − p_old, and hi_new − p_new ≤
  hi_old − p_old.
- **The window moves with the truth and only shrinks around it.** A friendly
  topic that raises the odds raises the window; one that teaches knowledge
  narrows it.
- **It still never lies:** the truth stays inside, 100 %.
- **The new offset is seeded inside the old one.** The new window is a seeded
  sub-window of the old window (shifted by Δp) that still contains p. Repeated
  readings therefore only intersect. No pair of readings recovers the truth,
  because the latest window is all a player can learn. That keeps #113's
  honesty, which was the reason for the re-draw.
- **Stateless, as the code is today (a proposal, Systems' choice):** the window
  at knowledge step n is computed from step 0 forward. Step 0 is the stranger's
  seeded window. Each step's window is a seeded sub-window of the previous
  one, of the next width, and it contains p. So no register is needed.

**The rows:**

| | Declared |
|---|---|
| Two readings, the same person and lever, knowledge not lower: the window measured from the truth is nested (both inequalities above) | **100 %** |
| After a topic that raised the true odds by Δp: the shown window's lower edge rises by at least Δp (lo_new − lo_old ≥ Δp, which follows from the nesting; QA's Turcy case breaks it) | **100 %** |
| The truth inside the window | **100 %** (unchanged) |

- **The edges:** a shifted window that would leave [0, 1] is moved back
  inside, as `shown_range` does today, and never narrowed for it. The nested
  inequality is then read only on the side away from the edge. The truth
  stays inside either way.
- **One known leak, accepted:** the window's shift reveals the change in the
  true odds between two readings. The scene's "What changed" line already names
  the rapport and knowledge change, so this adds little.
- **Probe:** a unit test over `shown_range` (Systems'), checking every person
  and lever across knowledge steps, at fixed and rising p.
- **Failure looks like:** a window that falls after a friendly topic (QA's
  Turcy case), or one that widens.

## B5 — No lever dominates

The grid: France's 61 people with their authored traits × the three knowledge
bands × relationship (below friend, friend or closer) × the ask (aligned with a
want, against one) × the channel (audience, phone call).

| | Declared |
|---|---|
| Pairs of levers where one is at least as good on success **and** no costlier on every register, in every cell (Pareto dominance) | **0** |
| Share of cells in which one lever has the best net value | **at most 40 %** for any lever |
| Share of cells in which each lever has the best net value | **at least 5 %** for every lever |
| The denominator of both shares, per lever | the cells **in which that lever is offered**: the whole grid for five levers, and only the friend-or-closer half for appeal to friendship, which is not offered below friend |
| The channel (amended 2026-10-24, see below): audiences held by a player who phones every open request once a month before booking (`audience_probe` regime A4) | **B2's audiences row still holds**: 12 to 30 held a term, at least 4 in months 1–20 |
| The answers to a request — book, delegate, refuse (decline and unanswered, one answer by the tie rule) — scored under the declared player model ("B5 amendment" below: two intents per request, a diary day at 1.05 of one ask won, the real three-attempt audience) | book **at most 50 %** of all scored cases; within "will serve", book and delegate **each at least 5 %**; within "won't serve", refuse **at least 5 %** |

- **Net value** is success × the ask's gain minus the expected cost, in the
  registers the lever spends. The probe's header states the exchange weights
  **before** the run, the way the events probe's E2/E3 were declared.
- **Why (OPINION):** 0 dominated pairs is the standard the author chose for the
  events in the same block ([[v5-reflection]] D15: "re-tune to 0 dominated
  pairs"). 40 % keeps one lever from being the default; 5 % keeps each lever
  from being dead content.
- **Probe:** `tools/lever_probe.gd`, regime L2.
- **Failure looks like:** one lever best in most cells (the player stops
  reading people and presses it); a lever never best (dead); a player who phones
  first holds fewer audiences than B2 asks (the diary becomes optional); leaving requests unanswered the best
  answer to most of them (the player learns never to open the inbox). Since the
  author's call of 2026-10-21 (an unanswered request is a decline once its window
  passes), this row is expected to pass: leaving a request unanswered is a
  decline that arrives later, so it can be the best answer only where declining
  is. A failure here now means the lapse is priced below the decline (B3).
- **The channel row, amended (2026-10-24, before b3 is built).**
  - **Why the old row was replaced:** "a call at least 0.10 below an audience"
    holds by construction once the phone subtracts exactly 0.10 and withholds a
    lever under 0.15 (Systems' b3 plan, call C). A row that holds by
    construction measures nothing, so the offset moves to the invariants (I5),
    where a test pins it.
  - **What the row now measures** is what the old row's failure line was
    about: whether calls make the diary optional. A call costs no diary day,
    and a failed call leaves the request open. One call per person per month
    across a two-month window gives two rolls per request. So the row reads
    B2's own audiences row for a player who phones every open request first
    and books what the phone does not answer. B2's numbers are declared, and
    nothing new is invented.
  - **Expected (INFERRED, from the formulas, not run):** the chance a request
    is answered by phone over two calls is 1 − (1 − (p − 0.10))². At B4's
    midpoints, that is 0.51 for a stranger, 0.70 for an acquaintance and 0.84
    for the known. On A2's stranger-heavy mix, about half the audiences would
    go to the phone, so B2's floor of 12 is likely to fail. That would make
    the phone too strong as planned. The read decides, and a miss goes to the
    author.
  - **L2's denominators with the phone:** phone cells enter L2's 40 % and 5 %
    shares. Each lever's denominator is the cells, in each channel, where that
    lever is offered: a lever withheld by phone under 0.15 is not counted
    there. This is friendship's rule, applied to the floor.

### B5 amendment (2026-10-24): the price of a diary day

Declared before `audience_probe` or `lever_probe` reads anything for this row, at
the parent's request (Systems' PR #113, call 2). The answers row above needs a
diary day's price, and no band stated one. This subsection states it, with its
reason. It is declared, not read off a run.

**The price: 1.05 of one ask won, per diary day.** An audience takes one day
(`Audiences._entry`, `src/sim/audiences.gd:347-349` at `2c3262ea`, no travel
days). The unit is `tools/lever_probe.gd`'s: one ask won = 1.0, a grudge point
1.0, a rapport point 0.5 (its header, declared before its run).

**The audience the row reads is the real one** (PR #113's `src/sim/levers.gd`):

- up to `ATTEMPTS` = 3 lever attempts (`lever_constants.gd:15`);
- the same lever may be tried again, with a fresh roll each time (the attempt
  index is in the roll's salt);
- the audience stops at the first agreement ("they have already agreed");
- every attempt pays its lever's spend, win or lose;
- an audience that ends without an agreement settles as a refusal
  (`Levers.close`).

The player is modelled as repeating the lever with the best single-attempt net
value in the person's cell, and spending no attempt on a topic.

**Each answer's net value for one request, in those units.** In the Book row, p
is that lever's single-attempt odds, s its spend in the weights, and q = 1 − p.

| Answer | Net value |
|---|---|
| Book | (1 − q³) × 1, the chance of an agreement in three attempts; minus s × (1 + q + q²), the expected spends; minus q³ × Decline's cost, the settle when no agreement comes; plus the in-person gains ("The in-person gains" below: being received, the knowledge gained, and, when the want is served, the promise kept in person); minus **1.05** |
| Delegate | minus (0.25 × the refusal grudge, plus 0.5 × the snub rapport for a `vain` person or an office want), then delegation's commitment at its due month: plus 0.5 × 0.10 if kept, minus (0.75 × the refusal grudge + 0.08 + 0.5 × 0.2) if broken ("Delegation's commitment" below). The first part is `Audiences.delegate` as built: `DELEGATE_GRUDGE_SHARE` 0.25, `DELEGATE_SNUB_RAPPORT` -0.05 |
| Decline | minus (the refusal grudge, plus 0.5 × 0.1 rapport). This is `decline_price`: `DECLINE_GRUDGE` 0.18 through `Characters.refusal_grudge`, and `DECLINE_RAPPORT` -0.1 |
| Unanswered | equal to Decline by construction (a lapse costs exactly a decline; `tests/test_audiences.gd` pins it per request) |

The best answer for a request is the one with the highest net value. The row is
unchanged: **no answer is the best in more than 50 % of requests.**

**The tie rule** (declared with the price): Decline and Unanswered cost the same
by construction, so they tie whenever either is best. For the share they count
as ONE answer, "refuse". The row therefore reads: **none of book, delegate and
refuse is the best in more than 50 % of requests.** Without the rule, a tie
would either count twice or let the inbox's silence pass as its own answer.

**Why 1.05 (OPINION, derived from DECLARED bands, not from a run, on the same
three-attempt audience, against delegation WITH its commitment).** The book
values in this block come before the in-person gains. "The in-person gains"
below re-checks 1.05 with them, and that check is the declared expectation.

- The spec's trade-off table says booking is best "when the person carries a
  want the player can serve or needs served", and delegation is best when "the
  person matters but not personally" ([[v5.2-spec]], "An audience request"). The
  day's price is set so that this sentence is true for the middle person.
- B4 declares the picked lever's single-attempt success by knowledge band. The
  midpoints are 0.40 for a stranger, 0.55 for an acquaintance and 0.70 for the
  known.
- **Delegation's expected cost, with its commitment ("Delegation's commitment"
  below), at base g = 0.18 and no snub:**
  - at delegation: −0.045;
  - kept (want served by the due date): +0.05;
  - broken: −(0.135 + 0.08 + 0.10) = −0.315.
- **For the middle person, the derivation takes a coin, P(kept) = 0.5 (OPINION).**
  The middle person's want is neither one the player will surely serve nor one
  they oppose; the run decides each real case. That gives −0.045 + 0.025 −
  0.158 = **−0.178**.
- Decline's base cost is 0.18 + 0.05 = 0.23.
- **The acquaintance as the indifferent case, spends left out:** at p = 0.55,
  q³ = 0.091, so booking is worth 0.909 − 0.091 × 0.23 = 0.888 before the day.
  Indifference with delegation needs 0.888 − D = −0.178, which gives D ≈ 1.07.
  On the 0.05 grid that is **1.05**.
- **On the same basis:**
  - the known (p = 0.70): 0.973 − 0.006 − 1.05 = −0.083, against −0.178, so
    booking pays by 0.094;
  - a stranger (p = 0.40): 0.784 − 0.050 − 1.05 = −0.316, against −0.178, so
    delegation wins by 0.138;
  - the diary goes to the people the president knows or needs, and the
    ministers take the rest.
- **A day priced above one ask won is deliberate.** The day is the scarcest
  thing the president has (B2 declares 20 % to 50 % of requests unplaceable for
  a player who books them all). A three-attempt audience is close to a sure
  agreement (0.91 for an acquaintance), so a day must cost about that much for
  the ministers to take anyone.
- **Where decline wins:** for an opposed want (P(kept) = 0), delegation costs
  −0.36, below decline's −0.23. A booked acquaintance (−0.16) still beats
  both, so decline is best for an opposed want from a person the player does
  not know well enough to turn.
- **Three attempts flatten the curve.** The known's margin and the stranger's
  deficit are both about 0.1. A person's traits, relationship and want move p
  and P(kept) enough to cross that, so the row is a real choice, not a sort by
  knowledge band (INFERRED).
- **Two leans, stated and not corrected:**
  - The spends (s, left out of the derivation) lower the booking value, which
    leans the row toward delegation.
  - The knowledge an audience teaches is not priced, which leans it the same
    way. On PR #113 the gain is `President.learn_from`'s 0.05 × (1 −
    knowledge) per audience; on main's b1 it is `KNOW_AUDIENCE` 0.12.
- **This replaces the first price, 0.95.** That price was derived against
  delegation's immediate cost alone (−0.07), before the commitment existed.
  QA's RECORD on PR #115 asked for the re-derivation, and the parent asked for
  it before the row is read. The 1.05 is declared before any read, and it is
  kept, not re-derived, once the run has read anything. A miss with delegation
  over 50 % is the likely failure, and it is reported as a design result.

**Found before the run (INFERRED, read from the code at `2c3262ea`):** as first
built, decline is never the best answer.

- With these weights, delegation costs 0.25 g plus at most 0.025, while decline
  costs g plus 0.05, for every refusal grudge g > 0.
- Delegation therefore Pareto-dominates decline, and leaving a request
  unanswered with it. A decline that is never best is the B5 failure "a lever
  never best (dead)" in the answers' column.
- The spec gives delegation "a fixed, middling outcome", and gives decline the
  gain "no commitment made" ([[v5.2-spec]], "An audience request"). As built,
  delegation carries neither, so the signed design is not yet in the code.
- **The parent's decision (2026-10-24): build the spec as written.** Systems
  builds the commitment below in a small PR after #113, before this row is
  read. The row is not read on the first build.

**Delegation's commitment** (declared here, before Systems builds it):

- **The shape:** to delegate is to have a minister answer in the president's
  name. The minister commits that the person's want will be served by a due
  date. This is a row in the commitments register (V5.2a), kind `delegated`,
  for the person and the request's object.
  - It is due **12 months** after the delegation. That is
    `BOOKING_HORIZON_MONTHS`: the delegate cannot promise past what the
    president can see (OPINION).
- **At delegation (unchanged):** 0.25 × the refusal grudge, the snub for a
  `vain` person or an office want, and no knowledge.
- **At the due month, kept** if the want is served then: rapport +0.10. That is
  the price a kept promise already carries (#113's commitments).
- **At the due month, broken** if the want is not served:
  - the remaining 0.75 × the refusal grudge lands, the share delegation
    deferred, not avoided;
  - plus the unpaid-IOU betrayal: rapport -0.2 and a grudge pulse of 0.08
    (#113's existing primitive).
  - It is not a lie revealed (rapport -0.5, knowledge halved): the president did
    not give their own word.
- **What it makes delegation:** a conditional deferral, which is the spec's
  "middling outcome". It is cheap when the want will be served anyway, and
  dearer than an honest no when it will not.

**Delegate's net value (the table's row above, spelled out):**

- At delegation: minus (0.25 g + 0.5 × the snub).
- At the due month, kept: plus 0.5 × 0.10.
- At the due month, broken: minus (0.75 g + 0.08 + 0.5 × 0.2).
- Kept or broken is the run's own outcome: whether the person's want is served
  at the due month in the run, whichever answer the regime actually gave that
  request. The answers are compared counterfactually, per request. Decline is
  unchanged.

**Why decline is then the best answer for an opposed want or a trap (OPINION,
from the prices above):**

- **An opposed want** is one the player will not serve, because it runs against
  the programme or a law they keep. A delegated promise to serve it is broken
  at its date, so delegation costs g + 0.18 (+ the snub), against decline's
  g + 0.05. Decline wins by 0.13. Booking still wins where the audience can
  turn the person (B4 and B5's levers).
- **A trap** (a corrupt offer, V5.2c) is a commitment to the deal itself, made in
  the president's name. Proposed for c's bands: the exposure register reads a
  delegated commitment as the president's own, so delegating a trap carries
  c's exposure risk, and decline is the safe answer. c declares that price.
- **A want the player will serve anyway, from a person not worth a day:**
  delegation costs 0.045 − 0.05 ≈ 0 at base g. That beats decline (−0.23), and
  beats booking a stranger (−0.13 with the in-person gains below). That is the
  case the spec calls "the person matters but not personally". An acquaintance
  books instead (leg A below).
- **Neither answer dominates the other any longer.** Which one is best depends
  on whether the want is served, so decline has cells of its own.

**Red-team before the read** (GLM 5.3 drafted the attack, at the author's
2026-10-24 instruction; every claim below was re-derived here and is labelled):

- **Where each answer wins, BEFORE the in-person gains** (MEASURED arithmetic
  on the declared formulas, D = 1.05, spends left out). Here K = P(kept). This
  is the table that prompted decision 2. "The in-person gains" below supersedes
  it.

  | g | p | K = 0 | K = 0.5 | K = 1 |
  |---|---|---|---|---|
  | 0.18 | 0.40 | refuse (−0.23) | delegate (−0.178) | delegate (+0.005) |
  | 0.18 | 0.55 | book (−0.162) | book (−0.162) | delegate |
  | 0.18 | 0.70 | book (−0.083) | book | delegate |
  | 0.36 (principled) | 0.40 | book (−0.355) | delegate (−0.29) | delegate (−0.04) |
  | 0.36 | 0.55 to 0.95 | book | book | delegate |

- **No answer is dominated.** Each one has cells of its own.
- **Refuse never wins for a principled person.** Booking even a stranger
  (−0.355) beats refusing (−0.41). This agrees with the spec's Decline row,
  which is worst "when the person is principled (grudge ×2)", so it is the
  design, not a defect.
- **Delegation won every K = 1 cell, at any p**, before the in-person gains
  were priced. With D above one ask won and Book flat in K, a minister's kept
  promise (about 0) beat any audience (at most −0.05). That ran against the
  spec's Book row. The parent's decision (2026-10-24, decision 2) is to build
  the spec as written: the in-person gains are priced below, and the spec's
  wording stays.
- **Traps:** the model carries no trap price, so it cannot say where refuse wins
  against a trap. c declares that price (the proposal above).
- **Likely result (INFERRED):** the row turns on the realized K. In
  `audience_probe` A2, the player serves no wants by policy, so K is mostly
  low, and book and refuse should split most requests.

**The in-person gains** (the parent's decision 2, 2026-10-24; declared before
the read). The spec's Book row names what an audience buys: "the scene: levers,
topics, knowledge gained". The 1.05 left those gains unpriced. Each one is
priced from a primitive that already exists:

| Gain | Price | From | Slope in K | Built? |
|---|---|---|---|---|
| **Being received** | rapport **+0.10** when the audience is held, whatever is said (value 0.05) | the mirror of `DECLINE_RAPPORT` −0.1 (`src/sim/audience_constants.gd:55`): a refusal to your face costs 0.1, and being heard earns the same | flat | **no**: Systems writes it at `Audiences.hold` |
| **Knowledge gained** | `President.learn_from`'s 0.05 × (1 − k), valued at B4's slope (0.448 odds per knowledge unit, from B4's declared midpoints) × 3q², the person's own three-attempt sensitivity (1.08 for a stranger, 0.61 for an acquaintance, 0.27 for the known) × 2 further encounters with the person this term (OPINION, from B1's 24–48 requests from at least 12 people) | as built on #113 | flat | yes |
| **A promise kept in person** | rapport **+0.25** when a promise the president made in the audience (`promise_date`, outcome `promised`) is judged kept (value 0.125, times the chance A of an agreement) | 2.5 × the minister's kept +0.10 (delegation's commitment). The broken side already carries that ratio: a lie revealed costs rapport −0.5 against the IOU betrayal's −0.2 (`lever_constants.gd:141-145` at `dde0a133`). | **carries K** | **no**: Systems raises `PROMISE_KEPT_RAPPORT` from 0.10 to 0.25 for kind `promise`; a delegated commitment keeps +0.10 |

The knowledge values (INFERRED arithmetic) are 0.040 for a stranger, 0.014 for
an acquaintance and 0.002 for the known. A RECORD from QA: the book value's
full sensitivity to p also carries the settle term, 3q² × 1.23. With it, leg A
needs D ≤ 1.063 and leg C needs D ≥ 1.064, so the window is empty and leg C
misses by 0.014 at 1.05. The 1.05 stands as declared, and the band reads the
probe's cells, not these midpoints: small, and largest for the person the
president knows least, as expected. **Only the kept
promise carries K.** That is why it is the one gain that can hold K = 1:
delegation's value moves 0.365 across K, and a flat gain only shifts the point
where delegation overtakes.

**The partition the spec asks for** (four legs, written before any number was
chosen):

- **A.** At K = 1, an acquaintance books, beating delegation.
- **B.** At K = 1, a stranger delegates, beating booking.
- **C.** At K = 0, a stranger is refused, beating both.
- **D.** At K = 0, an acquaintance books, beating refusal.

**Solved at base g and the B4 midpoints** (the arithmetic is MEASURED, re-derived
here; the values are OPINION, as declared):

| Leg | Book | The rival | Holds at 1.05? | Bound on D |
|---|---|---|---|---|
| A | +0.015 | delegate +0.005 | yes, by 0.010 | D ≤ 1.060 |
| B | −0.127 | delegate +0.005 | yes, by 0.132 | D ≥ 0.918 |
| C | −0.225 | refuse −0.23 | **no, by 0.005** | D ≥ 1.055 |
| D | −0.098 | refuse −0.23 | yes, by 0.132 | D ≤ 1.182 |

- **The window for D is [1.055, 1.060], 0.005 wide, and the declared 1.05 lies
  just outside it.** Leg C misses by 0.005: at the stranger midpoint, with an
  opposed want, booking (−0.225) edges out refusal (−0.23). That is a tie in
  practice. At base g, refusal wins for strangers with p below 0.40.
- **The price stands at 1.05, as declared.** Moving it to about 1.06 to fit a
  0.005 window would be tuning to the derivation's own midpoints, which is
  what declaring before the read forbids. The miss leans toward booking, the
  answer V5.2 exists to make win.
- **The window is narrow, and that is a structural fact, not a tuning target.**
  The stranger and the acquaintance differ by only about 0.15 in book value on
  B4's midpoints, and refusal's edge is within 0.005 of the stranger's book value. In real requests,
  traits, relationship and standing move p and g by more than that, so the row
  is decided case by case.
- **Legs A and C are the thin ones.** A first draft valued knowledge at the
  acquaintance's sensitivity for everyone, and passed leg C by 0.013. With each
  person's own sensitivity, leg C misses (review pass 1). Leg A fails without being received
  (−0.035 against +0.005), and it fails if the promise kept in person stays at
  the minister's +0.10 (−0.053). Both gains are therefore needed. Neither can be
  dropped to save a build.
- **The known person books at every K** (−0.031 at K = 0, +0.030 at K = 0.5
  with the kept promise carrying K, and +0.090 at K = 1). That is the spec's "book the people you know". Delegation and refusal
  win only for people the president does not know well, which is the spec's
  "the person matters but not personally".
- **Side effects:**
  - `lever_probe`'s B4 and B5 grids price a commitment as a spend (0.15) and
    never read the kept reward, so the higher kept price does not move them
    (INFERRED).
  - The balance regimes hold no audiences, so the table does not move either
    (INFERRED; Systems confirms with the re-baseline).
- **GLM 5.3 drafted the attack on these numbers** (the author's instruction).
  Every value, bound and sensitivity above was recomputed here before it was
  written down.

**The first read, and the player model the row reads (2026-10-24, declared
before the re-read).**

*The timeline, stated plainly:*

1. The price 1.05 was declared, and its re-derivation merged with #116.
2. GLM's red-team, re-derived here, found that delegation won every request
   whose want the player will serve, against the spec's Book row. The parent
   decided to price the in-person gains (decision 2) on that red-team call,
   before any result arrived.
3. Before this declaration landed, Systems read the row once at 1.05
   (MEASURED: `.superpowers/sdd/systems-b21/b5_answers_rows.txt`). Over 37
   requests, decline was best in 83.8 %, book in 13.5 % and delegate in 2.7 %.
   All 37 were strangers (A2 uses no lever and no topic). One of the 37 wants
   was served by its due date.
4. That read is a band-definition gap, not a miss. The derivation assumed a
   coin, P(kept) = 0.5, while the probe's world is a passive player who serves
   one want in 37. The row's player model and the derivation's disagree.
   This subsection closes the gap. No shares were computed on the first
   read's rows before this was written.

*The player model the row reads:*

- **Two intents, equal weight.** Each request is scored twice: once as
  "will serve" (K = 1, the commitment kept, and the promise made in person
  kept) and once as "won't serve" (K = 0). Each case weighs one half, so the
  population is 2 × N. The run's own K is not used, because the passive
  probe's serve rate is not a player the band means. The equal weight is the
  derivation's own coin, now stated for the read as well.
- **Knowledge mix: the run's actual one.** Each person is scored at their
  knowledge at the request month in A2. MEASURED at this build: 37 of 37
  strangers. That matches the game: B1's people ask two to four times a term,
  so most requests come from people the president barely knows. A second
  table at a declared mix (a third each of stranger, acquaintance and known)
  is reported beside it, for information only. The band reads the first.
- **The cells as the probe builds them:** the person's levers, their odds p
  and spends s, and their grudge g, all from the run. The spends are included
  (the derivation left them out, a lean it stated). Being received and the
  knowledge value are included in every booked case.
- **The promise's basis is the game's.** The kept-promise gain is paid only
  when the winning lever is `promise_date`; every other lever settles with no
  commitment (`src/sim/levers.gd`, `close`). At K = 0, an agreement won on
  `promise_date` is a dated promise broken at its date, with no roll: the lie
  revealed costs rapport −0.5, a grudge pulse of 0.15, and half the person's
  knowledge, valued with the knowledge formula above.
- **The player picks the lever per intent.** In each case the player takes
  the offered lever with the best three-attempt net value under that intent.
  At K = 1, `promise_date`'s net includes its kept gain (0.125 × A). At K = 0,
  it includes the lie's price. So a player who will serve may promise, and a
  player who won't does not.
- **Ties:** decline and unanswered count as one answer, "refuse" (the tie
  rule).

*Expected (INFERRED, from the legs, not from the first read's rows):*

- A stranger-heavy population sends "won't serve" mostly to refuse, and
  "will serve" mostly to delegate. Strangers with high odds (a vain person
  open to flattery, for example) book.
- **What the model does to a single cap (MEASURED arithmetic, QA's TAKE 1).**
  At K = 1, delegate minus refuse = 0.75 g + 0.10 − 0.5 × snub, which is at
  least 0.075. At K = 0, refuse minus delegate = 0.13 + 0.5 × snub, at least
  0.13. So refuse wins only "won't serve" cases and delegate only "will serve"
  ones. A 50 % cap can never fail on either. The world decision 2 was meant to
  prevent (book 0, delegate 50, refuse 50) would PASS a single cap.
- **So the row carries floors within each intent** (declared with the model,
  before the re-read; see the row in B5's table). Within each intent only two
  answers compete:
  - within "will serve": book at least 5 % (decision 2's failure, book dead)
    and delegate at least 5 % (delegation dead);
  - within "won't serve": refuse at least 5 % (decline dead);
  - overall: book at most 50 % (the diary is the wall).
  - The 5 % is B5's own no-dead-lever floor (OPINION, the same reason: every
    answer earns its place in at least one case in twenty). No book floor is
    set within "won't serve": on a stranger-heavy mix, refusal is the spec's
    answer there.
- **Expected (INFERRED):** "won't serve" goes mostly to refuse, and "will
  serve" mostly to delegate on a stranger mix. Book's floor within "will
  serve" turns on `promise_date`: leg A holds only where the acquaintance's
  best lever is `promise_date` with its kept gain (QA: otherwise book −0.0985
  against delegate +0.005). The read decides.

*After the re-read:* the row is re-read once, on the build with delegation's
commitment and both in-person gains. A miss goes to the author, with no
further re-declaration (the parent's rule, 2026-10-24).

**The stop rule:**

1. The row is re-read once, at 1.05, under the player model above, on the
   build that has delegation's commitment AND the in-person gains (being
   received; the promise kept in person).
2. If book is best in more than 50 % of the scored cases, or any within-intent
   floor is missed,
   the price is **not** re-tuned to the run, and the band is not re-declared.
   It is the author's call:
   - re-price delegation's commitment;
   - change the price;
   - accept the result.

**Probe:** the per-request net values above, over `tools/audience_probe.gd`
regime A2's requests, each scored under both intents as the player model
above declares (the run's own K is not read). Each request's cell is the person's ACTUAL state in the
month it arrives: their knowledge band, their relationship (below friend, or
friend or closer), and whether the ask is aligned with one of their wants. The
lever values come from `tools/lever_probe.gd` L2's computation for that cell.
Which file runs it is Systems' choice, as long as the weights and the price are
the ones declared here.

**Failure looks like:**

- **Book under 5 % within "will serve":** people ask, the player would grant
  their wants, and still never meets them. The diary empties of scenes, and the
  soul V5.2 exists to add stays with the ministers (decision 2's failure).
- **Book over 50 % overall:** the diary is the wall, and B2's R5 complaint
  returns.
- **Delegate under 5 % within "will serve":** a dead answer.
- **Refuse under 5 % within "won't serve":** a dead answer.

### B5's re-read, measured and accepted (2026-10-24)

The single re-read under the player model above (MEASURED, Systems; rows in
`.superpowers/sdd/systems-b22/b5_answers_rows_b22.txt`):

| Row | Measured | Floor |
|---|---|---|
| Book within "will serve", strangers (the run's own mix) | **0 %** | at least 5 % |
| Book within "will serve", the declared one-third mix (information) | 7.2 % | — |
| Book over all cases | 18.9 % | at most 50 % |
| Refuse within "won't serve" | 62.2 % | at least 5 % |

- **The author's call, verbatim: "Accepter tel quel".** The within-intent book
  floor misses on the run's stranger mix, and it is accepted as it stands.
- **What the author accepted:** the diary is for people the player knows or
  must turn, and the ministers take the yeses to strangers. That was this
  note's own earlier reading (the red-team before the read), now accepted after
  the measurement.
- **Since then (#122, a sim fix):** a promise can no longer stack within one
  audience.

### #131 over seeds 1–20, accepted (2026-10-24)

Systems' #131 read the seeded bands over seeds 1–20 (MEASURED, #131's PR body):

- B2's audiences held went above 30 in 6 of 20 seeds (31 to 39, the busy seeds),
  against 18 of 20 required;
- B2's unplaceable share fell below 20 % in 4 of 20 seeds (0.13 to 0.17);
- B5's phone-first channel row (A4) read 11 at seed 0, under 12, because
  RECORD 10 removed one requester.

**The author's call, verbatim: "Accepter les trois".** All three misses are
accepted as they stand.

## B6 — Corruption is tempting, and it is found out

Over 200 seeded runs (salts), France, otherwise idle.

| Regime | Declared |
|---|---|
| Corruption offers reaching the president per term | **2 to 6** |
| **Once:** one corrupt act at month 6, any currency — exposed by month 60 | **10 % to 30 %** of runs |
| **Always:** every offer accepted — exposed by month 60 | **at least 80 %** of runs |
| **Always:** median months to the first exposure | **at most 24** |
| Exposure odds by currency, for the same act size | **favours < party money < personal wealth < diverted budget** |
| Exposures by route in the "always" regime | **each of the four routes at least 10 %**: the press, the courts, the auditors, a turned person ([[v5.2-spec]], the currencies table) |

- **Why (OPINION):** one bribe in a term should usually stay hidden, or
  corruption is never worth trying; a habit should almost always be found, and
  inside the first two years, so the play gate can see it. The order of the
  currencies is the order of the evidence each leaves ([[v5.2-spec]], the
  currencies table).
- **Probe:** `tools/shadows_probe.gd`, regimes S1 (once) and S2 (always).
- **Failure looks like:** "always" exposed under 80 % (corruption is free);
  "once" exposed over 30 % (never worth it); the order broken (one currency
  dominates the others); a route that never fires (the courts' half of
  "exposure through the press and the courts" is a new trigger,
  [[v5.2-spec]] C7, and the easiest to leave unbuilt; a turned person needs the
  relationship register to reach rival or enemy).

### B5 amendment (2026-10-24, before c1 is built): the shadows enter the grid

Systems' c1 plan (`.superpowers/sdd/v5.2c-plan.md`, "Calls", call 1) adds two
corrupt bargain currencies, `backroom` (evidence `favour`) and `aid` (evidence
`diverted_budget`), each with an odds bonus, and a lie variant on argue and
promise a date (`LIE_ODDS`). Declared before `lever_probe` L2 reads them.

- **They enter B5's grid as four rows of their own:** bargain (backroom),
  bargain (aid), argue (lie), promise a date (lie). Each is scored at its
  **expected cost**, beside what it spends openly:
  - **A corrupt currency:** P(exposed) × the exposure's price. P(exposed) is
    `shadows_probe` S1's exposed-by-month-60 rate for that currency, at the
    evidence size the lever writes; Systems reports S1 **per currency** for
    this (B6 reads it over all currencies). The price is the mean, over the
    scandal events that route arms, of each event's cheapest choice under
    the probe's exchange weights, since the player picks the cheapest answer.
    So `shadows_probe` runs before `lever_probe` L2, and L2's header states
    both numbers before its run.
  - **A lie on argue:** P(caught) × the reveal's price. P(caught) is
    `Lies.catch_chance()` at the cell's listener skill and the president's;
    the price is `Lies.reveal()`'s (`LIE_RAPPORT` 0.5, `LIE_GRUDGE` 0.15 at
    `lever_constants.gd:162-164`, and the knowledge kept) under the same
    weights.
  - **A lie on promise a date:** caught now at the same P; if not caught, the
    date reveals it with certainty (B8's third row). So the expected cost is
    the full reveal price whenever the date falls inside the term, and
    P(caught) × the price only when it falls after the term ends.
- **Denominators:** each shadow row counts only the cells where it is offered.
  The phone offers none (the c1 plan's call 8), so no phone cell counts for
  them, which is friendship's rule again.
- **The rows, with the shadows in:**

| | Declared |
|---|---|
| Pareto-dominated pairs, the four shadow rows included | **0** |
| Best net value, any row, a shadow row included | **at most 40 %** of its cells |
| Best net value, bargain in any currency taken together | **at most 40 %** |
| Best net value, each of the **six honest levers**, measured with the shadows in the grid | **at least 5 %** (unchanged) |
| Best net value, each shadow row | **reported**, no floor |

- **Why (OPINION):**
  - Pricing at the expected cost is what keeps the check honest. Scored at their
    open cost alone, a bribe and a lie would be "better odds for nothing", the
    Pareto row would flag them by construction, and the check would measure the
    pricing rather than the game.
  - The 40 % ceiling applies to each shadow row and to bargain as a whole,
    because a player who always bribes is the failure this block most needs to
    catch.
  - The honest floors stay, measured with the shadows in the grid: the shadows
    must not make an honest lever dead.
  - A shadow row has no floor. Corruption is a temptation, not required
    content. B6 already measures that offers reach the president (2 to 6 a
    term).
- **Failure looks like:** a shadow row best in more than 40 % of its cells (the
  player learns to cheat by default); bargain, all currencies together, over
  40 %; an honest lever under 5 % once the shadows are in (crowded out); a
  dominated pair (a shadow priced below its honest twin on every register).
- **Not in the grid:** accepting an offer. It is the person's proposal, not a
  lever the president picks, and B6 bands it.

### B6 amendment (2026-10-24, before c1 is built): rival and enemy on R11's cuts

The c1 plan's bond rule writes `rival` and `enemy` from rapport, with interim
thresholds −0.5 and −0.8 and a hysteresis to clear (call 2). They are aligned
with R11's feeling bands ([[v5.2-bplus-spec]], R11), so the game has one
ladder, not two.

| Bond | Declared | R11's word at that point |
|---|---|---|
| `rival` | rapport **< −0.30** | *cold*, `[−1, −0.30)`: the same closed side, so a person is a rival exactly when the card says *cold* |
| `enemy` | a rival **and** grudge **≥ 0.45** | *hostile, may leak*, `[0.45, 0.60)` and above; 0.45 is `GRUDGE_BRIEF_THRESHOLD` (`character_act_constants.gd:191`) |
| cleared | the condition fails at the month's check | the word changes in the same month |

- **No hysteresis (OPINION).** With one, the card could read *wary* while the
  bond still says rival. Rapport does not decay, so nothing makes it flicker
  but the player's own acts. The grudge decays slowly (0.008 a month), and an
  enemy turns back into a rival in the same month the grudge word drops from
  *hostile* to *resentful*.
- **Why enemy reads the grudge (OPINION):** R11 has no rapport cut below −0.30,
  and a new one would be the second ladder this amendment exists to avoid. The
  grudge cut at 0.45 is the word that already promises a leak, and a turned
  person is the route where "a rival or an enemy talks" ([[v5.2-spec]], the
  currencies table).
- **Reach (INFERRED, from the constants):**
  - A decline costs 0.10 rapport (`DECLINE_RAPPORT`, `audience_constants.gd:64`),
    so from 0 the fourth decline makes a rival (−0.30 itself is still *wary*).
    That holds only under the comparison rule below: in doubles, three declines
    from 0 sum to −0.30000000000000004, under the cut (QA, on 71009167).
  - One caught lie or broken date costs 0.50 (`LIE_RAPPORT`), so from anything
    under +0.20 it makes a rival at once.
  - At the interim −0.5 it took five declines; at −0.8, eight.
  - So the turned route opens sooner than the plan assumed. `shadows_probe` S2
    sets the `RATE`s after this, and B6's "each route at least 10 %" is read at
    these thresholds.
- **One comparison for every cut (declared):** a register value within
  **1e-9** of a cut counts as ON the cut, and the cut's declared bracket
  decides its side. For R11's words and for these bonds alike, in one shared
  helper that Systems and Interface both call: "below a cut" is
  `value < cut - 1e-9`, "at or above" is `value >= cut - 1e-9`. So exact sums of
  the authored steps land on the declared side: three declines read −0.30,
  *wary*, not a rival. A tolerance and not a rounding of the value, because
  `snappedf()` multiplies back by a step that is not exact in binary and can
  miss the cut's own double by one unit. The stored and saved value is
  unchanged. 1e-9 is far below every authored step (the smallest is the grudge
  decay, 0.008 a month) and far above a double's error at these magnitudes
  (about 1e-16).
- **Failure looks like:** a person shown *cold* who is not a rival, or a rival
  shown *wary* or warmer (the two ladders disagree); the turned route under
  10 % in S2 because no one reaches rival (it should not, at these cuts).

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

## B9 — Campaigns are paid by the party (C6, declared 2026-10-24)

The design is [[v5.2-c6-party-campaigns]]: the efforts re-priced per inhabitant,
paid monthly from the governing party's money, a public-funding income with
running costs equal to the start funding, and the state line
`campaign_bill_pct_gdp` retired. Declared before Systems' run. The base is the
author-accepted base current when C6 is built (today
`.superpowers/sdd/qa/base-b3ede2e3.json`).

| Row | Declared |
|---|---|
| **B9.1** France's ceiling splits the menu: of the 10 allowed pairs, the number that fit a full 10-month window under EUR 22.509 m | **3 to 7** (5 at the declared prices) |
| **B9.2** Every regime except `managed_campaigns_early`, `_late` and `_tour`, against the base | **identical** on every column the base already has (every election row, every run row); B9.4's new money column is new, not a move |
| **B9.3** The three campaign regimes, France: flips against the base | **0** |
| **B9.3** The same, 2027 vote share, `early` and `late` | **Δ in [0, +0.005]**, and the margin does not fall |
| **B9.3** The same, 2027 for `tour`, and 2029 and 2032 for all three | **\|Δ\| ≤ 0.005** |
| **B9.4** France's governing party's money in `hands_off` | **exactly 48.0 until the first legislative election (2029-06)**, then moved only by net funding, and inside [0, 96] over the run |

- **Why B9.1 (OPINION):** the ceiling is what makes the campaign a choice in
  France. If every pair fits a full window, the ceiling is decorative; if
  almost none does, there is one answer.
- **Why B9.2 (INFERRED):** no regime but the three campaigns spends party
  money, and no vote reads it. Running costs equal the start funding, so the net
  income is exactly zero until an election changes a party's shares, and after
  that it still writes only party money. A moved row means party money leaked
  into something a vote reads.
- **Why B9.3, and the prediction (INFERRED):** the mobilisation is unchanged
  (the same efforts, the same accrual); what goes is the deficit the bill added
  in the months before the vote. So 2027 should rise or stay, provided the
  harness's own pair fits. The probe's hook runs at the Elections step, after
  that month's Campaign step (`tools/balance_probe.gd:950-953`; the order is
  `src/sim/world_month.gd`'s `STEPS`), and `Campaign.execute()` only appends to
  `campaign_running`, without accruing. So `early` (`campaign_month` 8, the
  loop's index 7, September 2026) pays and accrues October 2026 to May 2027:
  **8 months**. Over 8 months, 8 of the 10 pairs fit the ceiling; only town halls
  with broadcast (EUR 22.9 m) and digital push with broadcast (EUR 25.8 m) do
  not. `late` (month 14, March 2027) pays **2 months**, April and May, and every
  pair fits. `tour` changes pair at month 12 (January 2027), so its total is
  Systems' to compute. (Corrected by QA's round on 400541da: an earlier draft
  said 9 or 10 and 3 or 4 months. This is the same hook-inside-the-tick fact as
  #132's first TAKE.) If the
  harness's pair does not fit, it overspends under the soft ceiling (decided,
  [[v5.2-c6-party-campaigns]] "The decisions"), which writes party-money
  evidence: Systems reports the evidence, and an exposure that moves 2029 or
  2032 through B6's hazard is reported, not failed.
  The campaign added +0.0009 (`tour`) to +0.0026 (`late`) of vote share in 2027
  over `managed` (the base: 0.2629; `early` 0.2648, `late` 0.2655, `tour`
  0.2638), with the fiscal hit inside it, so 0.005 bounds the fiscal half with
  room.
- **Why B9.4 (INFERRED):** it pins the running-cost rule. Money that moves
  before an election means running costs differ from the start funding; money
  below zero in a regime that never campaigns means the income is mis-shared.
  **Expected: France's first legislative election can cut the purse even when
  the incumbent gains seats.** Before it, both shares are the authored 0.28; in
  the base `hands_off` 2029 row the incumbent takes 0.2408 of the vote and 178
  of 577 seats (0.3085), so the net income becomes 32.25 × (0.2408 − 0.28) +
  34.19 × (0.3085 − 0.28) = about −0.29 m a year (INFERRED). A small drop after
  that election is the rule working, not a failure.
- **Clause (ii) of `tools/campaign_probe.gd` retires.** It measured the
  campaign's deficit against what was left of `DEFICIT_SCALE_PP`
  ([[campaign-model]] §7b); there is no deficit now, and B9.1 takes its place as
  the affordability clause. Clauses (i) (worth one point of approval, at most
  the poll floor) and (iii) (at most a fifth of a term) read the mobilisation
  and the window, which C6 does not touch: no re-run needed.
- **Reported, not gated:** where the money binds for the other three playable
  nations ([[v5.2-c6-party-campaigns]], section 7), once Content has sourced
  their ceilings and pots.
- **Probes:** `tools/campaign_probe.gd` (B9.1, a table replacing clause (ii));
  `tools/balance_probe.gd` + `tools/balance_diff.py` (B9.2, B9.3), with the
  governing party's money added to each election row for B9.4.
- **Failure looks like:** a regime other than the three campaigns moves; a 2027
  campaign row falls with the harness's pair under the ceiling; a flip; money
  that moves before 2029-06 in `hands_off`.

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
- **I5 — A call's odds are an audience's less 0.10** (b3; moved here from B5's
  channel row, 2026-10-24). Same lever, same cell, exactly 0.10 lower. A lever
  whose audience odds are under `ODDS_MIN` + 0.10 = 0.15 is not offered by
  phone. `tests/test_phone.gd` pins both.
- **I4 — The re-baseline is predicted, not discovered.** Since the author's call
  of 2026-10-21, an unanswered request is a decline, so the 51-regime table
  may move on the played nation's rows, and the campaign regimes also through
  party money ([[v5.2-spec]], "The re-baseline: the table WILL move", which
  lists the rows that cannot move; for the campaign regimes B9 now declares the
  move, the state line being retired by [[v5.2-c6-party-campaigns]]). Systems writes the predicted re-baseline before the run, measures
  it, and the author accepts it before the merge; B3's ceiling bounds it. The AI
  nations book no audiences and receive no requests.

## The probes, declared

| Probe | Regimes | Bands |
|---|---|---|
| `tools/audience_probe.gd` | A1 idle, A2 book everything, A3 decline everything, A4 phone first then book (b3) | B1, B2, B3 (all but the 2027 rows), B5's channel row |
| `tools/balance_probe.gd` (exists) + `tools/balance_diff.py` | `hands_off` at the build tip against the accepted base | B3's 2027 verdict and margin |
| `tools/lever_probe.gd` | L1 by knowledge band, L2 the grid | B4, B5 |
| `tools/shadows_probe.gd` | S1 once, S2 always, S3 affair, S4 lies | B6, B7, B8 |
| `tools/campaign_probe.gd` (exists) + `tools/balance_probe.gd` | the ceiling table; `managed_campaigns_*` and every other regime against the base | B9 |

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

## Proposed register tests (Systems)

- **`_check_act_price_fades`** (B3 amendment, 2026-10-24) — one act, then no
  further act: the fraction of that act's price left is 50 % at H months and
  25 % at 2H (H the shipped constant, inside [22, 30]), each to within 1 point,
  and never crosses zero. For
  Systems' register tests (`tests/test_characters.gd` or beside the register),
  not the playability file.

## What could not be verified

- No band here is measured; the probes do not exist yet.
- The author's pace comes from one session's timestamps, with boot and menus
  included.
- The share of personal-category events in the desk's 12 a term was not
  measured.
