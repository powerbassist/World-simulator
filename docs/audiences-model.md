---
title: Audiences Model
tags:
  - decision
  - people
---

# Audiences Model

People ask to see the president. V5.2b's first half, the request: who asks, when,
what the three answers cost, and why a request left unanswered is a decline. The
second half, the audience itself (the levers, the odds and their fog), is b2's.
The design is [[v5.2-spec]] "An audience request (V5.2b)"; the bands are
[[bands-v5.2]] B1-B3; the registers it prices on are [[people-model]] §14.1 (grudge,
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
2. **Invitations.** A programme entry that went live this month calls the people
   whose wants name it (sponsors and opposers), outside the hazard.
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
| **Book** | one of the `OFFERED_DATES` (2) days the person offers, inside the window, if the diary can place it ([[calendar-model]] §12: one thing at a time) | the audience: the scene, and `KNOW_AUDIENCE` (0.12) knowledge whatever is said |
| **Delegate** | `DELEGATE_GRUDGE_SHARE` (0.25) of a decline's grudge; a snub (`DELEGATE_SNUB_RAPPORT`) for a `vain` person or an office want | the request answered, most of the grudge avoided, no diary day, no knowledge |
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

Related: [[people-model]] · [[calendar-model]] · [[v5.2-spec]] · [[bands-v5.2]] ·
[[decision-surfaces]] · [[programme-model]]
