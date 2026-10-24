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
| A phone call's odds against an audience's, same lever, same cell | **at least 0.10 lower** |
| The answers to a request — book, delegate, decline, and leaving it unanswered — any one of them the best net value over all requests, a diary day priced at 0.95 of one ask won, on the real three-attempt audience ("B5 amendment" below) | **at most 50 %** of requests |

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
  answer to most of them (the player learns never to open the inbox). Since the
  author's call of 2026-10-21 (an unanswered request is a decline once its window
  passes), this row is expected to pass: leaving a request unanswered is a
  decline that arrives later, so it can be the best answer only where declining
  is. A failure here now means the lapse is priced below the decline (B3).

### B5 amendment (2026-10-24): the price of a diary day

Declared before `audience_probe` or `lever_probe` reads anything for this row, at
the parent's request (Systems' PR #113, call 2). The answers row above needs a
diary day's price, and no band stated one. This subsection states it, with its
reason. It is declared, not read off a run.

**The price: 0.95 of one ask won, per diary day.** An audience takes one day
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
| Book | (1 − q³) × 1, the chance of an agreement in three attempts; minus s × (1 + q + q²), the expected spends; minus q³ × Decline's cost, the settle when no agreement comes; minus **0.95** |
| Delegate | minus (0.25 × the refusal grudge, plus 0.5 × the snub rapport for a `vain` person or an office want), then delegation's commitment at its due month: plus 0.5 × 0.10 if kept, minus (0.75 × the refusal grudge + 0.08 + 0.5 × 0.2) if broken ("Delegation's commitment" below). The first part is `Audiences.delegate` as built: `DELEGATE_GRUDGE_SHARE` 0.25, `DELEGATE_SNUB_RAPPORT` -0.05 |
| Decline | minus (the refusal grudge, plus 0.5 × 0.1 rapport). This is `decline_price`: `DECLINE_GRUDGE` 0.18 through `Characters.refusal_grudge`, and `DECLINE_RAPPORT` -0.1 |
| Unanswered | equal to Decline by construction (a lapse costs exactly a decline; `tests/test_audiences.gd` pins it per request) |

The best answer for a request is the one with the highest net value. The row is
unchanged: **no answer is the best in more than 50 % of requests.**

**Why 0.95 (OPINION, derived from DECLARED bands, not from a run, on the same
three-attempt audience):**

- The spec's trade-off table says booking is best "when the person carries a
  want the player can serve or needs served", and delegation is best when "the
  person matters but not personally" ([[v5.2-spec]], "An audience request"). The
  day's price is set so that this sentence is true for the middle person.
- B4 declares the picked lever's single-attempt success by knowledge band. The
  midpoints are 0.40 for a stranger, 0.55 for an acquaintance and 0.70 for the
  known.
- Delegation's base cost is 0.25 × 0.18 + 0.5 × 0.05 ≈ 0.07 at most, before
  traits. Decline's base cost is 0.18 + 0.05 = 0.23.
- **The acquaintance as the indifferent case, spends left out:** at p = 0.55,
  q³ = 0.091, so booking is worth 0.909 − 0.091 × 0.23 = 0.888 before the day.
  Indifference with delegation needs 0.888 − D = −0.07, which gives D ≈ 0.96.
  On the 0.05 grid that is **0.95**.
- **On the same basis:**
  - the known (p = 0.70): 0.973 − 0.006 − 0.95 = +0.017, against −0.07, so
    booking pays;
  - a stranger (p = 0.40): 0.784 − 0.050 − 0.95 = −0.216, against −0.07, so
    delegation wins;
  - the diary goes to the people the president knows or needs, and the
    ministers take the rest.
- **Three attempts flatten the curve.** The known's margin over delegation is
  0.087 and the stranger's deficit is 0.146. A person's traits and relationship
  move p enough to cross that, so the row is a real choice, not a sort by
  knowledge band (INFERRED).
- **Two leans, stated and not corrected:**
  - The spends (s, left out of the derivation) lower the booking value, which
    leans the row toward delegation.
  - The knowledge an audience teaches is not priced, which leans it the same
    way. On PR #113 the gain is `President.learn_from`'s 0.05 × (1 −
    knowledge) per audience; on main's b1 it is `KNOW_AUDIENCE` 0.12.
  - The derivation sets indifference against delegation's immediate cost
    (-0.07). It was written before delegation's commitment (below) existed.
    With the commitment, delegation is about 0 when the want is kept and about
    -0.36 when it is broken (-0.39 with a snub, at base g). The price stays as declared; it is not
    re-derived for the commitment.
  - The 0.95 is kept, not re-derived, once the run has read anything. A miss
    with delegation over 50 % is the likely failure, and it is reported as a
    design result.

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
  delegation costs 0.045 − 0.05 ≈ 0 at base g. That beats both booking (−0.06
  for an acquaintance at 0.95) and decline (−0.23). That is the case the spec
  calls "the person matters but not personally".
- **Neither answer dominates the other any longer.** Which one is best depends
  on whether the want is served, so decline has cells of its own.

**The stop rule:**

1. The row is read once, at 0.95, on the build that has delegation's
   commitment.
2. If booking or delegation is the best answer in more than 50 % of requests,
   the price is **not** re-tuned to the run. It is the author's call:
   - re-price delegation's commitment, with a new reason declared before a
     new read;
   - change the price, with a new reason declared before a new read;
   - accept the result.

**Probe:** the per-request net values above, over `tools/audience_probe.gd`
regime A2's requests, each delegated commitment followed to its due month. Each request's cell is the person's ACTUAL state in the
month it arrives: their knowledge band, their relationship (below friend, or
friend or closer), and whether the ask is aligned with one of their wants. The
lever values come from `tools/lever_probe.gd` L2's computation for that cell.
Which file runs it is Systems' choice, as long as the weights and the price are
the ones declared here.

**Failure looks like:**

- **Delegation best in most requests:** people ask, and the player never meets
  them. The diary empties of scenes, and the soul V5.2 exists to add stays with
  the ministers.
- **Booking best in most:** the diary is the wall, and B2's R5 complaint
  returns.
- **Decline never best:** a dead answer.

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
- **I4 — The re-baseline is predicted, not discovered.** Since the author's call
  of 2026-10-21, an unanswered request is a decline, so the 51-regime table
  may move on the played nation's rows, and the campaign regimes also through
  party money ([[v5.2-spec]], "The re-baseline: the table WILL move", which
  lists the rows that cannot move). Systems writes the predicted re-baseline before the run, measures
  it, and the author accepts it before the merge; B3's ceiling bounds it. The AI
  nations book no audiences and receive no requests.

## The probes, declared

| Probe | Regimes | Bands |
|---|---|---|
| `tools/audience_probe.gd` | A1 idle, A2 book everything, A3 decline everything | B1, B2, B3 (all but the 2027 rows) |
| `tools/balance_probe.gd` (exists) + `tools/balance_diff.py` | `hands_off` at the build tip against the accepted base | B3's 2027 verdict and margin |
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
