---
title: Calendar Model
tags:
  - decision
  - ui
  - simulation
---

# Calendar Model

The president's diary, as built in [[ROADMAP|U6a]]. Dated state the game has
carried since the MVP, put on a timeline for the first time — plus optional
booking of the verbs that already exist.

Same standard as [[government-model]], [[bloc-model]] and [[defence-model]]: a
**game model**, judged on whether the player's decisions produce a legible,
attributable political outcome. Where realism and legibility conflict,
legibility wins, and the trade is noted.

## 1. What U6 was, and why it split

The ROADMAP's U6 row is one line — *"an appointment is a scheduling skin over
the verbs that already exist… what it does need is the roster"* — and counted
cold it is **~40 surfaces and four machines**: a content roster, a scheduler at a
new tick resolution, a scarce-time model, and a calendar grid. Above V1.3d's ~39,
the largest ever held in one session.

Split on **machine count**, the trigger [[foreign-policy-model|V1.3e]]
established. **U6a** is the diary and the scheduling skin; **U6b** is the
named-individual roster [[cabinet-model|V1.1d]] deferred. The cut follows
U5b → U5c exactly: defer the half carrying the unmade content decision.

### Two things in the row are wrong, recorded rather than inherited

**"No new effect channel" and "politicians, celebrities, journalists, business,
foreign leaders" conflict.** A foreign leader is the face of a nation
`data/nations/` already ships and a party leader the face of a party
`data/parties/` already ships, so meeting one is `state_visit` in a hat. A
journalist has no target that exists — meeting one **is** a new effect channel.
U6b authors political faces only; journalists, celebrities and business wait for
[[v1]] §4 and §5, which already say they inherit the roster.

**The tier table had no U6 row** — ninth consecutive instance of the missing-row
failure V1.3b recorded.

## 2. The session's headline is legibility, and the reason is a measurement

Every observable in this project is **piecewise-constant across a month**.
Nothing in `src/sim/` reads a day; `clock.gd` has emitted `day_advanced` since the
MVP and only the top bar has ever listened. So 14 March and 22 March are
indistinguishable in every quantity except the label, and **booking as a
*replacement* for acting is strictly worse than acting** — a deferral that buys
nothing, which is the dominance failure [[coercion-model|V1.3c]] and
[[bloc-model|V1.3d]] each shipped and had to be taught by a probe.

U6a is therefore judged on the **diary** first. Election day, the European
election, the presidential term, the council's next proposal and its pending
vote, the dissolution lockout, and every diplomatic and legislative cooldown
expiry are all live dated state today with **no surface anywhere that puts them
on a timeline**. The player reads them as scattered "in 4 months" captions on
five different panels, or not at all.

Booking rides on top, and is **optional**: every verb keeps its act-now button.
`tests/test_calendar.gd` asserts that a booking moves nothing at the moment it is
made, which is what keeps it optional rather than a cost.

## 3. The currency was measured and CUT

`tools/calendar_probe.gd`, with the band fixed **before** the sweep ran so the
numbers could falsify the currency rather than be fitted to it.

The design was a scarce monthly budget of the player's days — a state visit, a
law proposal and a reshuffle each drawing on one pool, so a month becomes an
allocation problem. `Budget.commit()`, `Bloc.cast_vote()` and
`Dissolution.dissolve()` were excluded deliberately: the core loop, a duty, and a
verb with its own lockout.

### (P1) The menu width

| Window | Wants | Median | Min | Raw (action, target) pairs | Days asked |
|---|---|---|---|---|---|
| Months 1–24 | 27.00 | 27 | 27 | 84.1 | 124.0 |
| Months 25–168 | 27.00 | 27 | 27 | 84.8 | 124.0 |

A *want* is one act per partner plus every available law plus a reshuffle. The
raw column is every legal pair, printed so the reading that throws 57 of them
away is visible rather than assumed.

### (P2) The bind rate — the kill switch

Accepted only inside **[25 %, 75 %]**. Below, decorative; above, "you get three
acts a month" wearing a calendar.

| Budget | 4 | 6 | 8 | 10 | 12 | 14 | 18 | 24 |
|---|---|---|---|---|---|---|---|---|
| Bind rate, late | 100 % | 100 % | 100 % | 100 % | 100 % | 100 % | 100 % | 100 % |
| Acts / month | 1.00 | 2.00 | 2.00 | 3.00 | 3.00 | 4.00 | 5.00 | 6.00 |
| Dropped / month | 26.0 | 24.3 | 24.3 | 19.2 | 19.2 | 17.9 | 16.1 | 14.7 |

**The band is not mis-tuned, it is structurally unreachable.** The median month
asks 124 days, so any budget below 124 binds in every month of a fourteen-year
run. There is no value of the constant that produces an allocation rather than a
cap.

The currency is **deleted, not left unused** — the treatment
[[foreign-policy-model|V1.3e]] gave `AGREEMENT_ACCEPT_MIN` and `SUPPORT_SIGMA`,
because a tuned constant nothing reads is a number a later session finds and
reasons from. **`src/sim/calendar_constants.gd` contains no tuned constant**, and
U6a is the first session in a long run with none.

The honest reason it could not work is worth carrying to whoever revisits it:
`Diplomacy.available()` and `Legislature.available()` return what is **legal**,
and nothing in this game yet models what the player **wants**. A ceiling priced
against legality always binds. A ceiling priced against appetite needs an
appetite model, which is a session rather than a constant.

### (P3) Orthogonality

Named in advance from [[coercion-model|V1.3c]]'s cut `tariff_rate_pct`: a day
cost that tracks an act's existing domestic price is one intensity written twice.

| Quantity | Spread across the fourteen verbs |
|---|---|
| `∑\|bloc_offset\|` | 0.000 (`state_visit`) to 0.540 (`settle_dispute`) |
| `cooldown_months` | **2 distinct values**: 12 and 24 |
| r(`\|bloc_offset\|`, `cooldown_months`) | 0.201 |

**The obvious derivation is measured dead.** A day cost read off `cooldown_months`
would give **two prices for fourteen verbs** — `trade.gd`'s
`GRAVITY_EXPONENT = 1.0` finding and V1.3e's clustered `coalition_position` in a
third place. Recorded because it is the first thing a later session will reach
for.

### (P4) Reachability

Under a per-kind table there is no per-verb variance to sweep, so the risk
changes shape: a kind priced above the budget is unreachable **forever**. At
budget 4 the diplomatic kind is unreachable; at 6 and above all three are
affordable alone. Moot once the currency was cut, kept because it is the check
V1.3c and V1.3d each had to be taught by a bug.

### (P5) Fixed-date density, and the correction it needed

**52 of 168 months carry a dated event — 31.0 %**, mean 0.36 events per month.

| Source | Months |
|---|---|
| `cooldown` | 24 |
| `council_vote` | 24 |
| `council_proposal` | 8 |
| `election` | 2 |
| `ep_election` | 2 |
| `dissolution` | 0 |

**The first run of this table was wrong twice, both times V1.3f's error —
measuring the wrong state.** It read a player who never acts, so no cooldown ever
existed to expire and much the densest source reported exactly **0**; and it
counted *after* the tick, so an election had already pushed its own next date
forward and 168 months showed **one**. Corrected to a playing player, read
pre-tick: 19.6 % → 31.0 %.

## 4. The sparseness is front-loaded, and the panel test found the sharp version

31 % over fourteen years hides the fact that matters. Measured directly on a new
game:

| | |
|---|---|
| Presidential election | 16 months out |
| Council's first proposal | 18 months out |
| Legislative and European elections | 41 months out |
| Cooldowns | none — they do not exist until the player has acted |
| **Events inside a twelve-month horizon** | **0** |

So the page every player sees first is exactly the page with nothing on it. The
plan pre-committed the response to a thin diary as **content or shape, not a
constant**, and widening `BOOKING_HORIZON_MONTHS` would have been the constant —
it also bounds booking, so a horizon long enough to catch a four-year-out
election would let the player book a state visit into the next term.

Three shape decisions instead:

1. **A twelve-month strip, not a month's page.** A sparse month reads as sparse
   inside a visible year rather than as an empty screen.
2. **A `later` footer**, listing the nearest `LATER_SHOWN` dates beyond the
   horizon. This is what stops a new game's diary opening blank.
3. **A `Next:` line outside the scroll**, because the footer sits under thirteen
   em dashes and answering "what is coming" should not require scrolling past the
   evidence that nothing is.

## 5. The scheduler never learns what it schedules

`Calendar.due(state, y, m, d)` returns due bookings **as data**. `main.gd` fires
the verb. `src/sim/calendar.gd` preloads **nothing** but its own constants, and
`tests/test_calendar.gd` asserts that by reading the file rather than leaving it
to a comment.

There is no preload *cycle* here — nothing would ever need to reach back into
`Calendar` — so six preloads would compile. The bar is [[cabinet-model]]'s rather
than the compiler's: *composing two systems' effects is the orchestrator's job,
not one system reaching into another.* `diplomacy.gd` preloads downward because it
**owns** those effects; a scheduler owns none of them and would become the widest
dependency in `src/sim/` while having the narrowest job.

`main.gd` already preloaded `Diplomacy`, `Legislature` and `Cabinet`, so the
dispatcher added **zero** new dependencies, and it is the shape already in that
file twice — `_card_obligations()` and `_card_foreign_acts()`, where sim writes a
record and the orchestrator composes.

Two consequences taken deliberately: an entry stores **ids only**, never object
references, which is also what makes it serialisable; and the `match` in `main.gd`
is a fixed small set of system verbs, the same class as `_act_reason_text()`'s
wording map, so [[engine-decision|Rule 1]] holds.

### The effect baseline moved to arrival

`main.gd`'s `_queue_effect()` snapshots a command's baseline at the button press
and measures it against the next history entry — U4's decision delta. A booking
commits nothing in the month it is made, so measured from the press a deferred
act would report the movements of a month in which it did not happen; and
`_pending_effects` is documented as not persisted, so a save across a booking
would lose a press-time baseline entirely. The dispatcher takes it instead.

### Two ordering facts, decided rather than inherited

- **`clock.gd` emits `month_elapsed` before `day_advanced`.** On the 1st of a
  month the whole monthly pipeline has already run when the day handler fires, so
  an appointment booked for the 1st acts **after** that month's tick — the month
  begins, and then the president spends it.
- **`due()` reads `<=`, not `==`.** A save reloaded past a date, or a clock
  stepped more than a day, must still fire the booking. An appointment that can
  be stranded forever is a command the player issued and the game silently ate.

## 6. `SAVE_VERSION` stays 13, and the assertion is worth more than a bump

- **`appointments` earns no bump.** Absent it reads as "nothing booked", correct
  for every version-13 save because those games could not book one —
  [[coercion-model|`measures`]]' case exactly, down to being player-created state
  derivable from nothing.
- **`day` is not serialised at all.** `save_manager.gd` already writes `clock.day`
  at the payload's top level; `GameState.day` is a mirror, the same S9 call
  `year`/`month` carry, and a copy in `to_dict()` would be two records of one fact
  that can disagree.
- **The field that *would* have earned a bump was never written.** A
  `days_spent_this_month` counter reads 0 when absent, so a player eight days into
  a month reloads with all of them back — a save-scum exploit. The probe cut the
  currency it counted before any of it existed.

`tests/test_save_load.gd` asserts the version is **still 13**, that a booking and
its unread `person_id` round-trip, that an absent register reads as an empty
diary, and that `to_dict()` does **not** carry `day`. That last one pins the
one-record property, so a later session folding the day into the state's own
dictionary turns it red and has to come and say why.

### The entry declares `person_id` now, absent and unread

U6b keys appointments on named individuals. An entry keyed only on
`(kind, action_id, target_id)` would be re-keyed then, bumping `SAVE_VERSION`
twice. The slot is carried from this session, written by nobody — the additive
escape hatch V1.3c named in advance for `measures` and then took without touching
relations or agreements.

## 7. Constants

`src/sim/calendar_constants.gd`. **None of these was swept.** Each is a bound —
a limit that keeps a register finite or a refusal legible.

| Constant | Value | Why |
|---|---|---|
| `BOOKING_HORIZON_MONTHS` | 12 | The strip the panel draws, so horizon and surface agree by construction: the player can book anything they can see and nothing they cannot. |
| `RESOLVED_KEPT_MONTHS` | 12 | Matches the horizon — a resolved act stays visible for exactly as long as its own page is reachable. |
| `LATER_SHOWN` | 4 | A footer, not a second strip. The nearest few are what make a new game's diary non-empty; the twentieth cooldown three years out is noise. |
| `MAX_APPOINTMENTS` | 288 | A guard rail on save size, not a play limit. The cap **refuses** rather than dropping, so a click never silently does nothing. |

## 8. Why nothing diverges

| Quantity | Bound |
|---|---|
| `state.appointments` | `MAX_APPOINTMENTS` by an explicit refusal, and pruned every month of resolved entries older than `RESOLVED_KEPT_MONTHS`. The only accumulator here, and the only one that needed one. |
| A booking's identity | Derived from its verb, so at most one of each is ever in flight — `refusal_reason()` refuses the second. No id counter, hence no field whose absent value collides after a reload. |
| An entry's effect | Exactly the command it defers. No new effect channel, so every bound in [[economy-model]], [[opinion-model]] and [[diplomacy-model]] applies unchanged. |
| A resolved entry | Never fires again — `due()` filters on status, so a kept appointment cannot re-run every day forever. |
| A stranded entry | Impossible: `due()` reads `<=`. |

The argument is not the evidence. `tests/test_calendar.gd` checks the no-preload
property, every refusal reason, that booking commits nothing, that an
appointment overshot by a year still fires, that a resolved one does not, that
pruning spares unfired bookings however old, that the cap refuses rather than
drops, that a cancelled booking leaves no trace and a resolved one cannot be
cancelled, and that a cooldown expiry is dated by the number of months the
cooldown actually carries. `tests/test_calendar_panel.gd` covers the strip, the
`later` footer, the always-visible next line, and that a refusal is printed.

## 9. The balance re-run, and the day loop the harness never had

**All thirteen existing regimes are bit-identical**, which is
[[trade-model|V1.3b]]'s and [[coercion-model|V1.3c]]'s argument: a booking is a
verb, and no budget regime issues one. A **fourteenth** regime was still needed,
for the reason V1.3g's thirteenth was.

But this one exists for a second reason the others did not have.
`tools/balance_probe.gd` and `tests/test_balance.gd` are **month loops with no
clock** — this project's balance harness has never once called
`advance_one_day()` — so a diary firing on a day was structurally invisible to
all thirteen, and their coming back bit-identical would have meant nothing rather
than something. The day loop now runs for **every** regime, not only the one that
books: a dispatch that only ever executes under the regime designed to exercise it
is not a dispatch anybody has tested. With an empty register it is one
`is_empty()` check, which is why the thirteen are unchanged.

## 10. Where it sits

```
clock.month_elapsed        (emitted FIRST on a rollover)
  → Economy … Bloc … Opinion … Discipline … Legislature … Dissolution
  → Diplomacy … Defence … Cabinet … Elections
  → Calendar.tick_month(state)        prunes resolved entries

clock.day_advanced         (emitted SECOND)
  → state.day = day                   the mirror
  → Calendar.due(state, y, m, d)      returns entries as DATA
  → main.gd fires the verb            Diplomacy / Legislature / Cabinet
  → Calendar.resolve(state, key, ok)  records what happened
  → _queue_effect(label, before)      the U4 baseline, taken HERE not at the press
  → message_stack.push(...)           a kept appointment earns a card
```

## 11. What is deliberately not built

**Booking on the verb panels.** The plan had `nation_panel.gd`, `law_panel.gd` and
`government_panel.gd` book instead of execute. Every verb row in those files is an
HBox holding an **autowrapping** summary label beside one button: a second button
narrows the label, the wrap grows the row, and `nation_panel.gd` is at 860px
against U5a's ~886 ceiling having paid for that fold twice already (V1.3e,
V1.3g). Booking lives on the diary alone, which is also truer to the verb — you
open your diary to schedule something. Discovery is the State cluster's Diary
entry.

**A cost for booking.** §3. The slot is open for a session that models what a
player wants rather than what is legal.

**Rescheduling.** Cancel and re-book. A drag-and-drop move is a surface decision
worth making once the diary has been played with, not before.

**AI diaries.** The nine act through `_tick_agenda()`'s own scheduler
(`diplo_months_to_act`), which is a countdown rather than a date. Giving them
appointments would be a second scheduler answering the same question — the
divergence this project's registers exist to prevent.

---

Related: [[index]] · [[engine-decision]] · [[cabinet-model]] ·
[[foreign-policy-model]] · [[coercion-model]] · [[bloc-model]] ·
[[defence-model]] · [[v1]] · [[ROADMAP]]
