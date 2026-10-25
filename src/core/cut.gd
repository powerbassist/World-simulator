extends RefCounted

## One comparison for every cut on a register -- docs/design/bands-v5.2.md, the B6
## amendment (2026-10-24). A value within TOLERANCE of a cut counts as ON the cut,
## and the cut's declared bracket decides its side: three declines from 0 sum to
## -0.30000000000000004 in doubles and must read -0.30, which is still "wary", not
## a rival. A tolerance, not a rounding: snappedf() multiplies back by a step that
## is not exact in binary.
##
## In src/core because both sides read it: the sim's bonds and the exposure
## machine's hostile press (src/sim), and R11's feeling words (src/ui). The one
## copy is the point -- a second would let the card say "cold" while the bond says
## nothing.

const TOLERANCE := 1e-9


## A cut whose LOWER side is closed, [cut, ...): cold's -0.30, the grudge cuts.
static func below(value: float, cut: float) -> bool:
	return value < cut - TOLERANCE


static func at_or_above(value: float, cut: float) -> bool:
	return value >= cut - TOLERANCE


## A cut whose UPPER side is closed, (..., cut]: rapport's +0.05 and +0.30,
## loyalty's +0.10 and +0.40.
static func above(value: float, cut: float) -> bool:
	return value > cut + TOLERANCE


static func at_or_below(value: float, cut: float) -> bool:
	return value <= cut + TOLERANCE
