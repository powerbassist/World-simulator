extends RefCounted

## V5.3 a, the plant closures (src/sim/closures.gd). The rule's thresholds are data
## (data/industry/closures.json, Content's); these are the decision's own timings.

## Months the player has to answer, from the announcement: the closure is posted
## after the month's tick and lands at the tick ANSWER_MONTHS later, so two months of
## play see it, the second its deadline.
const ANSWER_MONTHS := 2
## The buyer search (the spec's "a 3-month process with a seeded chance"), and the
## chance it finds one. A stand-in, shown on the answer as it is.
const BUYER_MONTHS := 3
const BUYER_CHANCE := 0.5
