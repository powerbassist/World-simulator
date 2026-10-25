---
title: Shadows Model
tags:
  - decision
  - people
---

# Shadows Model

V5.2c, the shadows: corruption offered and taken in the author's four currencies,
the affair, lies and their detection, and exposure through four routes, landing
as scandal events on the desk. The design is [[v5.2-spec]] ("Corruption, in the
author's four currencies", "Lies and their detection", conflicts C3, C4, C7, C8);
the bands are [[bands-v5.2]] B6, B7 and B8; every number is in
`src/sim/shadow_constants.gd`. The played nation only: the AI nations carry no
shadows (spec C12).

## 1. Evidence, and the one writer

Every corrupt act and every month of an affair leaves a row on
`NationState.exposure_evidence`: `{kind, person_id, size, month, leader_id}`.
`leader_id` is the president who left it; a row from before V5.2c names nobody
and reads as the sitting president's. `src/sim/president.gd` is the only writer:

- `leave_evidence` appends a row (an act);
- `grow_evidence` adds to the sitting president's open row of that kind and
  person, else appends one (the affair's monthly share) -- a predecessor's row is
  never grown;
- `expose_evidence` moves a row to `NationState.exposures` with its route and
  month, and refuses a route that cannot reach the row's kind.

Nothing else reads the evidence: it changes nothing in the world until it is
found. That is what lets `tools/shadows_probe.gd` price one act in four currencies
from one run (section 6).

## 2. The four currencies

| Currency | How it is spent | Evidence kind | Who can find it |
|---|---|---|---|
| Personal wealth | an offer from an executive or a press owner, accepted | `personal_wealth` | the press, the courts, a turned person |
| Party money | an offer from an executive to the governing party, accepted | `party_money` | the auditors, a turned person |
| Diverted budget | the bargain's `aid` currency | `diverted_budget` | the courts, the auditors, a turned person |
| Favours | the bargain's `backroom` currency | `favour` | a turned person |

- **Offers** ride on a request: `src/sim/offers.gd` draws, as the request
  arrives, whether it comes with money and in which currency, on a salt of its
  own (no other draw moves). In the scene the president takes it
  (`Shadows.accept_offer`: paid, the request served, an attempt spent, evidence
  left) or refuses it (`Shadows.refuse_offer`: the offerer's rapport only). Party
  money goes to `ns.incumbent_party_id`, the payer C6's campaigns draw on.
- **The corrupt bargain currencies** raise the bargain's odds
  (`CURRENCY_ODDS`) and pay in evidence instead of an open spend. Aid writes no
  fiscal line: EUR millions against a budget of hundreds of billions.
- **The phone offers neither**, and takes no lie: the lighter channel. Levers
  asks for the shadows with a flag that defaults to off, so a new channel gets
  none unless it asks.

## 3. Exposure

`src/sim/exposure.gd`, once a month in the Audiences step, after the judge and
the bond rule. Per route, in the order press, courts, auditors, turned:

`hazard = clampf(RATE[route] x reach x modifier, 0, HAZARD_MAX)`

- **reach** is the summed `size x EVIDENCE_WEIGHT[kind]` of the sitting
  president's rows the route can reach. A turned person reaches only rows whose
  person is now a rival or an enemy and still covered.
- **modifier:** the press rises with the share of hostile press owners (rapport
  below 0, or a grudge at the brief gate); the courts read judicial independence
  on its 0-100 scale, divided by 100, so a captured court prosecutes nobody
  (spec C7); the auditors and a turned person, 1.
- **A hit** moves the heaviest reachable row to `exposures` and arms its scandal
  for next month through `Events.arm`, the chain door, which waits on a full
  desk. Content's nine `on_action: "exposure"` events answer the eleven
  (route, kind) pairs. A pair with no event is still exposed, with event_id "".
- **The price is the scandal's**: its choices write corruption, approval and the
  blocs through the applier, never from a scene (spec C4).

## 4. The affair and the bonds

- **The affair** needs a married president, a person they have a spark with (a
  fixed seeded draw per pair: chemistry does not re-roll) who is close (rapport
  above +0.30). It accrues `affair` evidence each month it lasts. Ending it costs
  the lover's regard, `AFFAIR_END_RAPPORT`, which from close makes a rival.
  Flirting is a topic for anyone covered but the spouse; an unmarried president
  may flirt and begins no affair.
- **The bond rule** (the B6 amendment): a person whose rapport is below -0.30 is a
  rival; a rival at the 0.45 grudge is an enemy; the bond clears the month the
  condition fails, with no hysteresis, so the bond follows the word the card
  shows. Never over an affair. Every cut compares through `src/core/cut.gd`, the
  one helper R11's feeling words also call: three declines from 0 sum to
  -0.30000000000000004 and are still not a rival.

## 5. Lies

A lie on argue or a promised date raises that attempt's odds by `LIE_ODDS`. The
listener's reading skill against the president's (both `social_skill`) decides
whether it is caught there and then: `0.33 + 0.75 x (listener - president)`,
clamped to [0.02, 0.95], on a roll of its own. The catch does not undo the
attempt's roll: B5's amendment prices a lie at P(caught) x the reveal.

- **Caught**, the price is `Lies.reveal`: b2's broken-promise price (rapport
  -0.5, knowledge halved, a 0.15 grudge), in one function, so a caught lie and a
  broken date are never priced two ways. A promise caught as a lie is withdrawn,
  so its date prices nothing again.
- **A promise not caught** carries `lie: true` on its commitment row and is
  revealed at its date with no roll, served or not (B8's third row).
- **An uncaught lie leaves no evidence**: its risk is the catch and the date.
