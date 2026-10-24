extends RefCounted

## Audience requests (V5.2b): the trigger, the window and the price. The model
## is docs/audiences-model.md; the bands that judge these numbers are
## docs/design/bands-v5.2.md B1-B3, and tools/audience_probe.gd measures them.
## Every number below is an INITIAL value declared before the probe ran; the
## probe's record in the model doc says where each one landed and why.

## The monthly chance that a person with a want the government does not serve
## asks to see the president, scaled by (0.5 + standing): the weighty ask more.
## B1 wants 24-48 requests a term on an idle France; about forty of France's
## sixty-one carry an unserved want at a new game, and 36 / 60 months over
## forty askers is 0.015 -- doubled here for the cooldown, which idles each
## asker most months.
const REQUEST_HAZARD := 0.025

## One person asks at most once in this many months. B1 caps any one person at
## 25 % of a term's requests: at eight months a person asks at most 8 times in
## 60, under a quarter of a 36-request term.
const REQUEST_COOLDOWN_MONTHS := 8

## The months a request waits in the lane before it lapses into a decline (the
## author's answer 3, 2026-10-21). Two: long enough to fit the diary around it,
## short enough that ignoring the lane is an answer the person hears.
const REQUEST_WINDOW_MONTHS := 2

## The lane's ceiling, held in the sim so the inbox can never drop one: a
## request that would be a fifth waits for a free place next month.
const MAX_PENDING := 4

## Resolved rows the lane remembers, for the person card's history.
const RESOLVED_KEPT_MONTHS := 12

## How many days a person offers inside the window. Scarcity is occupancy (the
## diary's U6a / V2.4a rule), so an offered day the diary has taken is a day
## lost; B2 wants 20-50 % of requests unplaceable for a player who books all.
const OFFERED_DATES := 2

## The price of a refusal, on the registers people-model 14.1 names plus a's
## rapport. 0.18 is nine months of a standing want's denial pulse (0.02): a
## refusal to your face is felt more than a policy that drifts. MEASURED
## (tools/audience_probe.gd, 2026-10-24), against B3's act row: 0.12 and 0.16
## left every refused person under the brief gate (0.45) for 60 months -- the
## highest peaked at 0.30 -- so refusing everything cost no act at all; 0.18 is
## the smallest that crosses it, through two principled people refused twice,
## with the first brief at month 22 idle (20 declining) -- after France's 2027
## vote, so a refusal prices the relationship and does not decide that election
## on its own; 0.2 doubled the briefs. A single refusal never crosses alone.
const DECLINE_GRUDGE := 0.18
const DECLINE_LOYALTY := 0.0
const DECLINE_RAPPORT := -0.1

## Delegation (spec): a minister answers, most of the grudge avoided, no
## knowledge gained; a vain person or one who wanted an office is snubbed.
const DELEGATE_GRUDGE_SHARE := 0.25
const DELEGATE_SNUB_RAPPORT := -0.05

## What holding an audience teaches the president about the person: a stranger
## becomes an acquaintance in about three (B4: 2-5 interactions).
const KNOW_AUDIENCE := 0.12

const STATUS_PENDING := "pending"
const STATUS_BOOKED := "booked"
const STATUS_HELD := "held"
const STATUS_DELEGATED := "delegated"
const STATUS_DECLINED := "declined"
const STATUS_LAPSED := "lapsed"
const STATUS_SETTLED := "settled"
const STATUS_PROMISED := "promised"

## The open statuses: a request in the lane or in the diary.
const OPEN := [STATUS_PENDING, STATUS_BOOKED]

const SALT_REQUEST := "audience_request"
const SALT_DATE := "audience_date"
