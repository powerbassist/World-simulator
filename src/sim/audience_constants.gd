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

## The hazard's scale is (this + standing): a person with no standing still asks
## at half the rate, the weightiest at one and a half times it.
const REQUEST_STANDING_FLOOR := 0.5

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
## b3: a visiting head's request waits in a place of its own (one at a time), so a
## head of state never queues behind a mayor and never pushes one out -- the
## domestic lane, and the bands measured on it, are untouched by visitors.
const MAX_PENDING_FOREIGN := 1

## Resolved rows the lane remembers, for the person card's history.
const RESOLVED_KEPT_MONTHS := 12

## Pre-gate B, the month-3 guarantee (B1's amendment): the lane month by which the
## nation's own people have asked at least once, the draw failing. 3 is B1's own
## "the first by month 3", now held in every game rather than most.
const FIRST_REQUEST_BY_MONTH := 3

## V5.3 B7, the quiet-month call's person branch (docs/design/v5.3-b7-density.md; the
## author's call 2, 2026-11-10): a month with nothing arrived calls the guarantee's
## best candidate, unless this many people already asked in the last
## QUIET_ASKS_MONTHS months (every lane, read off audience_asked_month) -- then the
## month goes to a minor event instead. Nine a year sits at B1's ceiling of 48
## requests a term, so the call does not push the lane past its flood line.
const QUIET_ASKS_MAX := 9
const QUIET_ASKS_MONTHS := 12

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
## b2.2 (bands-v5.2.md "The in-person gains", the parent's decision 2): being
## received earns what a refusal to the face costs, whatever is said -- the mirror
## of DECLINE_RAPPORT, written when the audience is held.
const RECEIVED_RAPPORT := 0.1

## Delegation (spec): a minister answers, most of the grudge avoided, no
## knowledge gained; a vain person or one who wanted an office is snubbed.
const DELEGATE_GRUDGE_SHARE := 0.25
const DELEGATE_SNUB_RAPPORT := -0.05

## V5.3-0 gate: the chance a minister keeps a delegated word the world has not
## served (src/sim/delegation.gd), linear in the cabinet's two means and clamped:
##   BASE + PER_EFFECTIVENESS x (effectiveness - 1) + PER_LOYALTY x (loyalty - NEUTRAL)
## Declared from the INPUTS the base run measured (tools/delegation_probe.gd at
## 1d3d7485, before any tip run): a France cabinet in office reads effectiveness
## 0.89 and loyalty 0.72-0.74 in its first two years, so it keeps 0.65 - 0.11 +
## 0.23 = about 0.77 of the words it can keep -- "usually kept" by a cabinet in
## office (the parent's band, about two in three overall once the impossible
## objects are counted). A full vacancy (effectiveness 0.5, loyalty 0) sits at the
## floor; loyalty 0.2 (an unpopular government's coalition) at about 0.24; a slope
## of 1 on each makes the Government panel's 10 points of effectiveness worth 10
## points of odds, the plainest reading of "a competent, loyal minister".
const DELEGATE_KEPT_BASE := 0.65
const DELEGATE_KEPT_PER_EFFECTIVENESS := 1.0
const DELEGATE_KEPT_PER_LOYALTY := 1.0
## Cabinet.loyalty's midpoint: a coalition neither bound to the government nor
## leaving it.
const DELEGATE_LOYALTY_NEUTRAL := 0.5
## Never certain, never hopeless while a minister can act: a seated cabinet always
## leaves a word some chance either way.
const DELEGATE_KEPT_MIN := 0.05
const DELEGATE_KEPT_MAX := 0.95
## Why no minister can deliver the object (Delegation.impossible): an office (only
## the president names), a measure (only the president lifts), and the president's
## own programme opposed (only the president drops it).
const DELEGATE_WHY_OFFICE := "office"
const DELEGATE_WHY_MEASURE := "measure"
const DELEGATE_WHY_PROGRAMME := "own_programme"
## A plant is the president's to rescue, and a development fund the president's to open.
const DELEGATE_WHY_FIRM := "firm"
const DELEGATE_WHY_REGION := "region"
## The parent's call on #235, no rapport farm. A word only the minister kept (the
## want still unserved) earns the president half of a served word's +0.10
## (lever_constants DELEGATED_KEPT_RAPPORT): the minister takes the other half of
## the credit. And the want it answered is HEARD for a year: its person does not
## ask about it again for this many months after the verdict -- measured at
## 3b2728d1, 226 of 636 such words were re-asked and re-delegated within 12 months.
## 12 is the judged register's memory (president_constants JUDGED_KEPT_MONTHS),
## which heard() reads; test_levers pins the order.
const DELEGATE_MINISTER_RAPPORT := 0.05
const DELEGATE_HEARD_MONTHS := 12

## What holding an audience teaches the president about the person, times what is
## left to learn (1 - knowledge). V5.2b b2 moved it from a linear 0.12, on which
## six audiences alone made a person "known" and B4's "at least 8" could not
## hold: at 0.05 with one topic (lever_constants KNOW_TOPIC 0.07) each audience
## keeps 0.95 * 0.93 of the unknown, so a stranger is an acquaintance after 4
## and known after 9 (B4: 2-5, and at least 8).
const KNOW_AUDIENCE := 0.05

## b3, the meetings (src/sim/meetings.gd): a state visit or a summit teaches what an
## audience's hold does, on the same curve, and leaves a topic's warmth (lever
## constants RAPPORT_TOPIC) -- a courtesy, not a friendship.
const KNOW_MEETING := KNOW_AUDIENCE
const RAPPORT_MEETING := 0.04

const STATUS_PENDING := "pending"
const STATUS_BOOKED := "booked"
const STATUS_HELD := "held"
const STATUS_DELEGATED := "delegated"
const STATUS_DECLINED := "declined"
const STATUS_LAPSED := "lapsed"
const STATUS_SETTLED := "settled"
const STATUS_PROMISED := "promised"
## A chief's request whose closure stopped waiting for an answer: unpriced (AudienceLane).
const STATUS_OVERTAKEN := "overtaken"
## A chief's request names the firm: `firm:<company id>` (AudienceTriggers.chiefs).
const FIRM_PREFIX := "firm:"

## The open statuses: a request in the lane or in the diary.
const OPEN := [STATUS_PENDING, STATUS_BOOKED]

const SALT_REQUEST := "audience_request"
const SALT_DATE := "audience_date"
const SALT_DELEGATION := "delegation"
