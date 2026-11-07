extends RefCounted

## V5.3 a, the plant closures (src/sim/closures.gd). The rule's thresholds are data
## (data/industry/closures.json, Content's); these are the decision's own timings.

## Months the player has to answer, from the announcement: the closure is posted
## after the month's tick and lands at the tick ANSWER_MONTHS later, so two months of
## play see it, the second its deadline.
const ANSWER_MONTHS := 2
## The bounds on the month's chance (Closures.chance; the rule's own numbers are data).
## The fall's term stops at this many reference falls, which a major's worst fall reaches
## only now and then since the share steps became relative to the firm (a sector's mean
## when past the threshold is 6 to 10 %, its worst of a decade 10 to 19 %). The economy's
## term stays inside these, so the worst slump does not make a closure certain and the
## best boom does not rule one out. Stand-ins (Systems), for the author's table.
const FALL_TERM_MAX := 1.5
const ECONOMY_TERM_MIN := 0.2
const ECONOMY_TERM_MAX := 3.0

## The buyer search (the spec's "a 3-month process with a seeded chance"), and the
## chance it finds one. A stand-in, shown on the answer as it is.
const BUYER_MONTHS := 3
const BUYER_CHANCE := 0.5

## The buyer's price (the parent's TAKE 1 on #251, B5's rule that no answer is
## dominated): finding a buyer was free, so it beat letting the plant close in every
## case. Now the state covers the plant's losses while the search runs -- this share
## of a year of the plant's output, for BUYER_MONTHS, paid at the answer -- and adds a
## sweetener to the buyer's price, this share of the plant's value, paid only when a
## buyer is found. Close stays the cheapest answer and a rescue the surest; the buyer
## sits between them. Stand-ins, shown on the strip as they are.
const BUYER_SEARCH_LOSS := 0.25
const BUYER_SWEETENER := 0.20
## The buyer's strength when the player counters its sweetener (Negotiate PR 2;
## Negotiation.odds' -1..1): full, the closing plant needs the buyer more than the
## buyer needs it (negotiation.gd's own reading). At the stand-in odds it accepts the
## three counters at 55, 35 and 15 % (the parent accepted them).
const BUYER_LEVERAGE := 1.0

## The plant rescue (QA's call on #270, the parent's ruling): a rescue is priced on the
## PLANT, not on the firm's subsidy verbs, whose bill read EUR 5 to 9 bn a year to keep
## a 720-job plant. The state pays this much a year for each job the closure would
## cut -- about a worker's yearly labour cost, an order of magnitude rather than a
## sourced figure -- for RESCUE_MONTHS, a Budget line of its own, and the plant is
## watched afresh after it. Stand-ins: over the term a job kept costs EUR 180,000,
## inside the EUR 90,000 to 950,000 QA found for a job a buyer keeps.
const RESCUE_EUR_PER_JOB_YEAR := 60000.0
const RESCUE_MONTHS := 36
