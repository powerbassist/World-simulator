---
title: Audiences Model
tags:
  - decision
  - people
---

# Audiences Model

People ask to see the president. V5.2b's first half (sections 1-4), the request:
who asks, when, what the three answers cost, and why a request left unanswered is a
decline. Its second half (sections 5-8), the audience itself: the levers, the odds and
their fog, the topics, and the promises judged at their date. b3 (sections 9-11) adds
the phone, the heads met on a visit, and the asks a reshuffle invites. The design is
[[v5.2-spec]] "An audience request (V5.2b)" and "The influence levers"; the bands are
[[bands-v5.2]] B1-B5; the registers it prices on are [[people-model]] §14.1 (grudge,
loyalty) and §14.9 (rapport, knowledge).

## 1. The request is the lane

`ns.audience_requests` is the REQUESTS lane the inbox shows, row for row
(`Audiences.pending()`), and the sim caps it at `MAX_PENDING` (4). So a request is
counted where the player meets it, which is what B1 asks, and nothing between the
register and the card can drop one: the spec's pre-mortem cause 2 is closed by
construction rather than by a lane rule in the UI. A request never holds the clock
([[decision-surfaces]], the author's answer 2); the clock cluster shows
`Audiences.waiting_count()`.

A row: `{id, person_id, object, stance, arrived_month, deadline_month, status,
date, resolved_month}`, months absolute. Status: pending, booked, held, delegated,
declined, lapsed, settled, promised. Both registers are `absent_ok`: before V5.2b
nobody asked, which is what absent reads.

## 2. Its own trigger

The want ladder's edge trigger fires nothing in an idle term by design
([[people-model]] §14.6, P1), so a request does not ride it. Each month, after
Characters (`WorldMonth`'s "Audiences" step):

1. **Overdue requests lapse.** Pending past its window, or booked or held in an
   earlier month and never closed (a no-show): each costs a decline, once.
2. **Invitations** (`src/sim/audience_triggers.gd`, section 11). A programme entry
   that went live this month calls the people whose wants name it (sponsors and
   opposers), and the month after the player's reshuffle every unserved office want
   is invited -- both outside the hazard, under the lane's rules.
3. **The seeded ask.** A person of the played nation, not the president, off a
   `REQUEST_COOLDOWN_MONTHS` (8) cooldown, with no open request and a want the
   government does not serve (`Characters.want_served()`, the edge trigger's own
   read), asks with probability `REQUEST_HAZARD x (0.5 + standing)`, drawn from
   `Cycle.unit_pair(person, "audience_request", month)`. A grudge silences no one:
   the declined go on asking.
4. Resolved rows older than `RESOLVED_KEPT_MONTHS` (12) are pruned.

## 3. The three answers, and the lapse

| Answer | Costs | What it buys |
|---|---|---|
| **Book** | one of the `OFFERED_DATES` (2) days the person offers, inside the window, if the diary can place it ([[calendar-model]] §12: one thing at a time) | the audience: the scene (section 5), and `KNOW_AUDIENCE` (0.05) times what is left to learn, whatever is said |
| **Delegate** | `DELEGATE_GRUDGE_SHARE` (0.25) of a decline's grudge; a snub (`DELEGATE_SNUB_RAPPORT`) for a `vain` person or an office want | the request answered, most of the grudge avoided, no diary day, no knowledge -- and since b2.1 a minister's word that the want is served within `BOOKING_HORIZON_MONTHS` (12), judged at that date (section 7) |
| **Decline** | `DECLINE_GRUDGE` (0.18, x the trait intake: loyal 0.5, principled 2) and `DECLINE_RAPPORT` (-0.1) | the days, and no commitment |
| *(lapse)* | exactly a decline (the author's answer 3, 2026-10-21) | nothing |

The price goes through the registers' own doors: `Characters.price_refusal()`
(characters.gd stays the one writer of grudges and loyalty) and
`President.adjust_rapport()`. `Audiences.decline_price()` is what the card names
before the player answers (B3), read through the same `Characters.refusal_grudge()`
the price pays.

**A refusal brings a person to the leak, never past it.** A refusal lifts a grudge no
higher than `GRUDGE_REFUSAL_CEILING` -- the brief gate (0.45) plus one month's decay and
one brief's relief (0.47) -- so it can cause one brief, and the rungs above the brief
(defect, challenge) stay the wants' own. Measured: without the ceiling, a principled
person refused once sat 0.25 over the gate and leaked a brief every month for a year,
and the balance table's idle-on-requests regimes lost France's 2032 vote in 28 of 41
regimes (section 4).

**An act's cost fades** (the author's call on this PR, verbatim "Le cout s'efface").
The `bloc_offset` a character act writes -- a brief, a resignation, a defection, a
challenge, V4.3's acts included -- now decays with a half-life of
`ACT_OFFSET_HALF_LIFE_MONTHS` (24): `NationState.act_bloc_offset` holds the acts' share,
recorded as what the acts actually wrote, and each month it shrinks by 0.5^(1/24) and
gives the difference back. Laws, events, the programme and campaigns stay permanent.
Before V5.2b the idle term fired no act, and a permanent price did no harm; once
refused audiences feed the ladder, fourteen years of permanent briefs pinned the
workers' and students' offsets on their clamp (`tests/test_balance.gd`). **Both halves
are needed, measured:** with the fade and no refusal ceiling, test_balance still hit
the clamp, because a refusal's monthly leak comes in bursts; with both, it passes.

**Scarcity is occupancy, never a ceiling.** The diary refuses a day already
taken (the U6a / V2.4a rule); the person offers two days; a request whose two days
are both taken cannot be booked, and its card offers delegation and decline.

## 4. The bands, measured (2026-10-24)

`tools/audience_probe.gd` -- A1 idle, A2 book everything (day_probe's D2 packer fills
the diary first), A3 decline everything -- France, 60 months through
`WorldMonth.tick_month()`; bands declared in its header before the first run.

| Band | Declared | Measured |
|---|---|---|
| B1 arrivals, idle | 24-48 | 36 |
| B1 first request | by month 3 | month 1 |
| B1 months 1-20 | >= 8 | 19 |
| B1 people / top share | >= 12 / <= 25 % | 23 / 11 % |
| B2 unplaceable, booking player | 20-50 % | 31 % |
| B2 audiences held / by month 20 | 12-30 / >= 4 | 24 / 13 |
| B2 unplaceable cards offering the other two | 100 % | 100 % |
| B3 act by a refused person, by month 60 | >= 1 | 2 idle, 4 declining (briefs; 7 and 9 before the ceiling) |
| B3 a named grudge by month 20 | >= 1 | 12 |

**The one constant the probe moved:** `DECLINE_GRUDGE`, 0.12 -> 0.18 (measured before
the ceiling; with it, the act rows read 2 idle and 4 declining, one brief per crossing). At 0.12 and 0.16
no refused person reached the brief gate (0.45) in 60 months -- the highest peaked
at 0.30 -- so refusing everything cost no act at all, B3's failure. 0.18 is the
smallest that crosses it: two principled people refused twice brief, the first at
month 22 idle (20 declining), after France's 2027 vote. 0.2 doubled the briefs. The
hazard, cooldown, window, cap and offered days met B1 and B2 at their declared
starting values.

The balance re-baseline this moves -- every request in every regime lapses -- is in
the PR that shipped it, measured against the prediction written before the run.

## 5. The audience (b2)

The booked day comes and the diary opens the scene: `Levers.open()` holds the request
and returns a **session**, a Dictionary the scene holds and hands back on every call. It
is never saved ([[summits-model]] §2, spec C11); what it changes lands in the registers.
The session offers **three attempts** (the author's answer 2), each a lever or a topic. A
scene left open past its month is section 3's no-show, priced as one decline.

| Lever | Odds (clamped to [0.05, 0.95], + 0.20 x rapport) | Spends, win or lose |
|---|---|---|
| **Argue** | 0.08 + 0.62 x knowledge, +-0.15 for an ask aligned with the want or against it, stubborn -0.14 | nothing |
| **Bargain** | 0.28 + 0.25 x knowledge, pragmatic +0.22, principled -0.22 | a favour (rapport -0.10), or a vote trade (an IOU due in 12 months) |
| **Promise a date** | 0.30 + 0.25 x knowledge, ambitious +0.22, -0.30 x (skill - 0.5) x 2 above a middling reader | a dated promise 3 to 24 months out (section 7) |
| **Pressure** | 0.48 + 0.25 x knowledge, -0.50 x (standing - 0.5), +0.20 x (approval - 50) / 50, networked -0.16, stubborn -0.12 | rapport -0.06 and a grudge pulse of 0.04 |
| **Flatter** | 0.48 + 0.20 x knowledge - 0.40 x skill, vain +0.40 | nothing; a failure on a principled reader above a middling one (skill 0.5) costs rapport -0.08 |
| **Friendship** | a friend or a close person only: 0.60 + 0.25 x knowledge, close +0.10 | the bond, a step down |

- **Why argue is so weak at first.** Argue costs nothing, so it Pareto-dominates any
  priced lever that never beats its odds. Its strength is knowledge, picking the right
  argument (the dominance matrix: "low odds without knowledge"), so it is a known
  person's lever, not a stranger's.
- **What a success buys:** the request settles without the decline price, loyalty
  +0.05 and a grudge's relief of 0.05, through `Characters.price_refusal()`. A flatter
  buys only the settle: its effect is small and does not hold. After a success the
  remaining attempts are topics only.
- **No success,** and closing is a decline, priced once through `Audiences.settle()`.
  A success stamps the request with its agreement (`Audiences.agree`, b2.1). So a scene
  the UI never closed ends as that agreement at the month's end, not as a no-show.
- **The roll** is `Cycle.unit_pair` over the request, the lever and the attempt index,
  and the month (I1).
- **Aid is not in b2.** A budget line of its own, a register and a draining tick are a
  later block's; the bargain refuses it.

**The other topics** each spend one attempt and buy knowledge and rapport, never a vote:

- family and opinion: `KNOW_TOPIC` 0.07 and rapport +0.04;
- dinner, once an audience: 0.10 and +0.08;
- gossip about a named third person: the president's knowledge of THAT person, 0.05
  (spec C1: every edge starts at the president);
- flirting: listed, not offered; the affair is V5.2c's (B7).

## 6. The fog, and knowing someone

The scene never shows the true odds. `Levers.offered()` prints a range around them:

- 0.36 wide below the acquaintance edge (0.33), narrowing linearly to 0.08 at the known
  edge (0.67);
- placed by a seeded offset, so the truth is always inside and not always centred (a
  centred range would print the answer). The offset is re-drawn at every 0.01 of
  knowledge (b2.1, QA's R1 on #113). With one offset for every width, two readings
  either side of a topic gave the truth back exactly; now they can only intersect;
- shifted back inside [0, 1], never narrowed.

A trait shows once knowledge passes its seeded reveal point, between a tenth of the
known edge and the edge itself. So a stranger sees none and a known person all; a trait
never shows wrong.

**Every knowledge gain has diminishing returns**: `amount x (1 - knowledge)`, the
audience's own `KNOW_AUDIENCE` and every topic alike.

- On b1's linear 0.12, six audiences alone made a person "known", which B4's "at least
  8" forbids.
- At 0.05 with one topic an audience, each audience keeps 0.95 x 0.93 of what is left
  to learn. A stranger becomes an acquaintance after 4 audiences and known after 9.
- So a term cannot come to know all of France's 61 people, and the player chooses whom
  to learn.

## 7. Promises and IOUs

A promise names a date the president controls. A vote trade is an IOU due 12 months on.
Both are a's `ns.commitments`, written by `President.commit()`.

`Levers.tick_month()`, run in the month's Audiences step after the lane, on the same
meters, judges each one due, once, with no roll:

| | The person's want served at the date | Not served |
|---|---|---|
| **Promise** | kept: rapport +0.10 | **a lie revealed**: rapport -0.5, knowledge halved, a grudge pulse of 0.15 |
| **IOU** | paid | **a betrayal**: rapport -0.2, a grudge pulse of 0.08; knowledge stands, since no lie was told |
| **Delegated** (b2.1) | kept: rapport +0.10 | the deferred 0.75 of the decline's grudge lands, plus the IOU's betrayal; not a lie, since the president did not give their own word |

`President.take_commitments_due()` takes each judged row off the register, so none is
judged twice, and a row loaded from a save is judged at its date like any other.

- Each judged row is remembered with its verdict in `ns.commitments_judged` (b2.1),
  read by `President.judged_commitments()` and forgotten after 12 months. So the Diary
  still shows a promise kept or a lie revealed after the month's report is gone. The
  register is `absent_ok`: an older save had judged nothing.
- **The author's call (2026-10-24), verbatim: "Oui, parole donnée".** A promise binds
  win or lose, so the president who promised a date and was not believed still owes
  it. A
person who has defected or left office meanwhile is judged on the same want. No balance
regime makes a promise, so the tick has nothing to do there.

## 8. The levers' bands, measured (2026-10-24)

`tools/lever_probe.gd` runs on a France game warmed 12 idle months through
`WorldMonth.tick_month()` (approval 48.8). Its exchange weights were declared in its
header before the first run, in asks won: gain 1.0 (flatter 0.7), a grudge point 1.0, a
rapport point 0.5, a commitment 0.15, a bond step 0.30.

| Band | Declared | Measured |
|---|---|---|
| B4 the picked lever's success: stranger / acquaintance / known | 0.30-0.50 / 0.45-0.65 / 0.60-0.80, rising >= 0.08 | 0.471 / 0.586 / 0.701 |
| B4 the printed width: stranger / known | >= 0.30 / <= 0.10 | 0.36 / 0.08 |
| B4 the truth inside the range | 100 % | 100 % |
| B4 audiences with a topic: to acquaintance / to known | 2-5 / >= 8 | 4 / 9 |
| B5 Pareto-dominated pairs | 0 | 0 |
| B5 best net value, any lever | <= 40 % | bargain 30.3 % (argue 26.0, friendship 18.6 of its half, pressure 18.3, promise 10.0) |
| B5 best net value, every lever | >= 5 % | flatter 6.1 % |

- **Where the constants came from.** They were the starting values, tuned in a
  prototype over France's 61 people before the probe existed. The probe met every row
  with them, so none was moved.
- **Flatter has the thinnest margin.** It is best only for the vain who read poorly and
  whom no other lever suits.
- **Not measured here:**
  - B5's channel row (a call at least 0.10 below an audience): section 9.
  - B5's answers row (book, delegate, decline, unanswered): it needs a diary day's price,
    which no band states. Its lapse half holds by construction: a lapse costs exactly a
    decline.

## 9. The phone (b3)

`src/sim/phone.gd`: `Phone.options(state, ns, loader, person_id)` is the call card --
`{why_not, request_id, levers, topics}`, each lever row `Levers.lever_row()`'s shape --
and `Phone.dial(state, ns, loader, person_id, lever_or_topic, args)` makes the call,
`{ok, error, success, spent, effects}`. (Not `call`: a static `call` overrides
`Object.call()`.)

| | A call | Against an audience |
|---|---|---|
| Costs | no diary day; one call per person per month (`ns.phone_calls`, `absent_ok`) | an offered day the diary can place |
| A lever | one attempt, on the person's **open request** (pending or booked); none open, no lever | three attempts, on the booked request |
| Odds | the audience's on the same cell **minus `CALL_ODDS_PENALTY` (0.10)**; not offered where that falls under 0.05 ("too long a shot for a call") | the cell's |
| A win | the request answered (`Audiences.answer`: settled, or promised), the win's relief and loyalty, **no knowledge** (a call is not a hold), a booked day given back | settled at close, plus `KNOW_AUDIENCE` at the hold |
| A loss | the request stays open: book, delegate and decline stand | after the third, a decline |
| A topic | family, opinion or gossip, at the audience's values; not dinner ("a dinner needs an evening") | any, three at most |

- **The same matrix at lower odds** ([[v5.2-spec]], the dominance matrix). Because a
  lever too long a shot is not offered by phone, every offered call is exactly 0.10
  below the audience and never clamped: B5's channel row holds by construction.
- **The fog reads the audience's seed**, so a call's range is the audience's shifted by
  0.10 and reading both narrows nothing.
- **The roll is the phone's own**, `Cycle.unit_pair(person, "phone:<lever>", month)`:
  a failed call predicts no audience attempt.
- **One rule, two channels.** The spend (`Levers.pay`), the win's relief and the flatter
  backfire (`Levers.outcome`) and a topic's lesson (`Levers.teach`) are shared, so the
  phone cannot drift from the audience. A refused call writes nothing and spends no
  month. **Not built:** taking an incoming call.

**Measured (2026-10-24, b3):**
- `lever_probe`'s L2 over both channels (the band's own grid, with per-channel
  denominators):
  - Pareto-dominated pairs: 0.
  - Best net value: bargain 30.4 %, argue 28.7 %, friendship 18.6 % (of its half),
    pressure 18.3 %, promise 10.0 %, flatter 7.2 %.
  - 3 768 phone lever cells, each exactly 0.10 below its audience (invariant I5, pinned
    by `tests/test_phone.gd`).
- `audience_probe` A4 (phone every open request once a month, then book): 48 calls,
  14 requests answered by phone, 13 audiences held (8 in months 1-20). That is inside
  B2's 12-30 and at least 4. The bands had expected a miss: two calls per request
  answer about half on a stranger mix, but a call needs an offered lever, and the
  person must be reachable that month.

## 10. The meetings (b3)

`src/sim/meetings.gd`, first in the WorldMonth "Audiences" step: a pair of the played
nation stamped in `GameState.met_months` in the month that just ended -- a state visit
either way, or a summit, which is a state visit with a scene -- teaches the other
nation's head (`President.leader_id()`): `KNOW_MEETING` (0.05, the audience's hold, on
the same curve) and `RAPPORT_MEETING` (0.04). The report names them
(`report["meetings"]`).

- **It reads Diplomacy's stamp, a month late on purpose.** The player's visit lands on a
  day of the month, the AI's in the month's Diplomacy step; both read `now - 1` at the
  next tick, so each meeting is met once and no register is added. A pair stamped again
  the very next month is met once for the two.
- The summit's scene stays [[summits-model]]'s pure read and `main.gd`'s applier: a
  scene and a plain visit teach alike. Nothing in a vote reads knowledge or rapport, so
  the balance table cannot move through this section.

## 11. The triggers (b3)

`src/sim/audience_triggers.gd` names who is invited to ask before the seeded ask runs,
as `[person, want]` pairs; `Audiences` keeps the lane's rules (the cooldown, one open
request each, the caps) and writes the request, so an invitation is a candidate, not a
card.

1. **A programme entry gone live** (b1's rule, moved here verbatim): each person's first
   want naming it.
2. **The month after the player's reshuffle** (the [[v5.2-spec]] pre-mortem's third
   trigger): the unserved wanters of the portfolio that changed hands.
   `Cabinet.assign()` stamps `ns.reshuffle_month` and `ns.reshuffle_portfolio`
   (`absent_ok`) only when the portfolio goes to another party. A no-op assign and a
   government seated by an election or a formation (`Cabinet.seat()`) stamp nothing,
   and a portfolio reshuffle never moves the premiership.
3. **A visiting head under a measure of the played nation** (the author's answer,
   2026-10-24, "Lever une mesure française"): the head of a nation that state-visited
   the played nation this tick asks for the measure on their nation to be lifted
   (object `measure:<directed key>`), only when one stands. It waits in a place of its
   own (`MAX_PENDING_FOREIGN`, 1), outside the domestic lane and its bands. A refusal
   costs **rapport only**: grudge and loyalty are this nation's people's, so
   `Characters.price_refusal()` writes nothing for a foreign head. A promise or a
   delegation to lift is judged on the measure at its date.

- **The G7 hook.** `Audiences.invite(state, ns, loader, person_id, object, stance)` is a
  door into the lane under its rules, for V5.3c's builder: a private firm's chief
  executive on a `price:<project>` object. Nothing in b3 calls it.
- **Spec C10, decided at b3:** an office want is about the party's seat, which is what
  `Characters.want_served()` judges for a portfolio. The request promises no
  person-level appointment.
- **Why the reshuffle rule is narrow.** The first build invited every unserved office
  want at every assign. `audience_probe` A2 books a reshuffle every month (mostly
  no-ops), and re-invited the same four people all term: B2's held row failed (35 held
  against 12-30). A no-op moves nobody's office.

**Measured (2026-10-24, b3):**
- The balance table: identical in every regime. The two `*_cabinet_shorted` regimes
  hand over a portfolio nobody in France wants.
- `audience_probe`:
  - A1 and A3: identical to b2.1 on every band field. Beside them, 5 visitor requests
    in 60 months (Albania's and Switzerland's heads, under measures France applies
    through an org's external measure).
  - A2 holds no visitor in the game's order (the diary after the tick).

Related: [[people-model]] · [[calendar-model]] · [[v5.2-spec]] · [[bands-v5.2]] ·
[[decision-surfaces]] · [[programme-model]] · [[summits-model]]
