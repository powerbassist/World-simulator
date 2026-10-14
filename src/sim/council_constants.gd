extends RefCounted

## The contested council's numbers, V4.5a. Model: docs/orgs-model.md, "V4.5 --
## the council, contested". Every value below is PROVISIONAL: V4.5b's
## tools/council_probe.gd bands them against the C1-C5 clauses that section
## declared before any of this ran. The comment on each says where it STARTS
## and why, which is what the sweep moves it from.
##
## Not in data/ for opinion_constants.gd's reason: these are the rules of the
## institution, and content is what the institution is asked to decide.

## Decision classes. QMR is V1.3d's cast-seat tally, untouched. UNANIMITY is the
## treaty class: any vote against vetoes, abstention does not -- the real
## Council's constructive abstention, and what keeps the player's third option
## meaning something once a veto exists.
const DECISION_QMR := "qmr"
const DECISION_UNANIMITY := "unanimity"
const DECISION_RULES := [DECISION_QMR, DECISION_UNANIMITY]

## The ask a bargain carries. Spelled exactly as orgs.gd's VOTE_FOR and
## VOTE_AGAINST, which council.gd cannot preload (orgs.gd preloads council.gd,
## so the reverse is a cycle); tests/test_council.gd pins the equality.
const ASK_FOR := "for"
const ASK_AGAINST := "against"
const ASKS := [ASK_FOR, ASK_AGAINST]

## Presidency term bounds for an authored `presidency.months`. Zero would divide
## by zero in the rotation; past two years a chair outlasts every proposal
## interval and the "rotation" is a monarchy.
const MIN_PRESIDENCY_MONTHS := 1
const MAX_PRESIDENCY_MONTHS := 24

## A sponsor's drive when its head of government does not resolve to a person:
## the register's midpoint, so an unresolved face neither shouts nor whispers.
const SPONSOR_DRIVE_DEFAULT := 0.5

## Lobbying. A sponsor at full drive (ambition 1.0) can close a gap of 0.25 on
## the appraisal scale -- above SUPPORT_THRESHOLD's own 0.15 so a keen sponsor
## can turn a member who is mildly AGAINST, below the ideology term's ceiling so
## no amount of wanting turns a member the proposal actually hurts. The margin
## makes "exactly its gap" survive float rounding.
const LOBBY_SWING_PER_DRIVE := 0.25
const LOBBY_MARGIN := 0.01
## 20 relations per point of swing: turning the widest reachable gap (0.25) costs
## 5 relations, a third of an open_embassy's lifetime gain -- a sponsor can lobby
## three or four members a division before it has spent what a year of drift
## repays (DRIFT_RATE 0.02 on a ~15-point displacement).
const LOBBY_RELATIONS_PER_SWING := 20.0

## How a sponsor answers a human member's vote, scaled by drive. The snub is
## larger than the thanks: being opposed is remembered longer than being backed,
## the grudge-over-gratitude asymmetry characters_constants.gd already prices.
const SPONSOR_THANKS := 6.0
const SPONSOR_SNUB := 8.0

## Favour: the cheapest currency in kind (relations, which drift back) and the
## weakest swing. The floor refuses a favour from a member that owes you none --
## below resting relations nobody is doing you favours.
##
## The COST is measured (V4.5b1 T5, tools/council_probe.gd C2, band: a player
## who bargains every deciding division ends the term >= 5 points below one who
## never does, with the members he bargained). At 6 the gap was 0.19: of two
## favours struck on ITA (months 18 and 54), DRIFT_RATE took 35 % of the price
## back by month 60 and the rest went to ITA's own AI agenda, which in the
## bargaining player's diverged world settled a dispute with FRA at month 53
## (+10.1) -- a ~7.2-point offset present at every cost swept. The gap is about
## linear in the price (4: -2.44, 6: 0.19, 8: 3.35, 10: 5.97, 11: 7.29, 12: 8.60,
## 14: 11.23), crossing the band near 9.3; 12 sits inside the passing region,
## not on its edge. It now costs more than TABLE_RELATIONS_COST (8), whose
## comment assumes the reverse -- left for the author, not moved here.
## FAVOUR_SWING was swept x{0.5..1.5}: at 0.075 no favour reaches the one
## single-member flip on offer (ITA's 0.091 gap) and the player pays in aid
## (gap -7.70); from 0.1125 up nothing changes. It stays at 0.15.
const FAVOUR_SWING := 0.15
const FAVOUR_RELATIONS_COST := 12.0
const FAVOUR_MIN_RELATIONS := 50.0

## Aid: money on the org's transfer line. 0.05 % of GDP for a year is ~1.4 bn
## for France -- a real side-payment, a fifth of FRA's standing net contribution
## (0.277 %), small enough to spend more than once a term. Swing between the
## favour's and the vote trade's: money talks, but less than a promise.
const AID_SWING := 0.20
const AID_PCT_GDP := 0.05
const AID_MONTHS := 12

## Vote trade: the strongest swing, because it is the dearest price -- the next
## division the creditor sponsors, the player must back it whatever it is. Five
## years before an unpaid IOU lapses: one term, so a debt can outlive the
## government that took it on and come due for its successor.
const IOU_SWING := 0.30
const IOU_EXPIRY_MONTHS := 60
const IOU_BETRAYAL := 15.0

## Tabling: what the chair charges to put the player's proposal first. Above a
## favour (the chair gives up its own pick, not just a vote), below a betrayal.
const TABLE_RELATIONS_COST := 8.0

## Ratification. Five months: long enough to fit a division between monthly ticks
## and a busy assembly, and strictly inside PROPOSAL_INTERVAL_MONTHS (6, one file
## per presidency) so a treaty's window closes before the next division -- carried
## at opening + 3, expired at opening + 8, next division at opening + 9 -- and two
## treaties are never ratifying in one council at once -- pinned by
## tests/test_council.gd. It was 6 against an 18-month interval; the interval
## moved to the presidency's semester on 2026-10-15 and this followed it.
const RATIFY_WINDOW_MONTHS := 5
## Killing a treaty everyone else signed costs more with its sponsor (scaled by
## drive) than with the bystanders, and the bystanders are many.
const RATIFY_FAIL_SPONSOR := 12.0
const RATIFY_FAIL_MEMBER := 2.0

const CURRENCY_FAVOUR := "favour"
const CURRENCY_AID := "aid"
const CURRENCY_VOTE_TRADE := "vote_trade"
const CURRENCIES := [CURRENCY_FAVOUR, CURRENCY_AID, CURRENCY_VOTE_TRADE]

## Ratification states per nation inside a register's `ratifying` entry.
const RATIFY_PENDING := "pending"
const RATIFY_DONE := "ratified"

## The vote-reason keys this block adds beside foreign_policy.gd's five. Kept
## here, not in FP.VOTE_REASON_KEYS, because FP's keys name terms of the
## appraisal and these name what was done TO the appraisal -- or, for the
## sponsor, why the appraisal was never asked.
const REASON_LOBBIED := "lobbied"
const REASON_BARGAINED := "bargained"
const REASON_SPONSOR := "sponsor"

## The AI chair's agenda power, bounded (author's call, 2026-10-14): it opens
## its most-supported proposal among the next CHAIR_WINDOW eligible ones in
## rotation order, and the rotation advances one step per opening whatever it
## picks. Three: a semester chair shapes the next file or two, not the whole
## book -- unbounded, a chair re-opened its favourite every term it sat and a
## proposal no chair ranked first never opened (V4.5a's final review, #4).
## Swept {2, 3, 4} against C6 (every proposal opens once in 168 months) at
## V4.5b1 T5: eu leaves 3 / 5 / 4 of its 20 never opened, so no window passes
## and 3 stays -- the eu has 27 openings for 20 proposals, and the five it
## misses sat in a chair's window 3-6 times each and lost every time. Never at
## the MAX_RULES_IN_FORCE cap. A BOUND in docs/orgs-model.md, not a tuning.
const CHAIR_WINDOW := 3

## The years an authored presidency anchor may name. Validation bounds, kept
## here so the loader holds no bare number.
const MIN_ANCHOR_YEAR := 2000
const MAX_ANCHOR_YEAR := 2100
