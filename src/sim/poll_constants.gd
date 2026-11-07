extends RefCounted

## V5.3 b, band B3 (docs/design/v5.3-ab.md 4.2): a poll on any measure.

## What each tier buys: the spec's margins per bloc and delays, the dearest the slowest. The
## prices are STAND-INS, sized by Systems as the spec asks: V4.2's EUR 50 k and 150 k were
## symbolic, and a price must show on a strip that reads bn at two decimals. A flat fee, as
## statute_constants' is, against the state's money.
const TIERS := {
	"quick": {"cost_eur_bn": 0.01, "margin": 6.0, "weeks": 2},
	"standard": {"cost_eur_bn": 0.03, "margin": 3.0, "weeks": 4},
	"deep": {"cost_eur_bn": 0.06, "margin": 1.5, "weeks": 6},
}
## How far the printed centre may stand from the truth, as a share of the margin. Under 1, so
## the range always brackets the truth: the band, by construction.
const NOISE_SHARE := 0.8
## A tax change as a measure: `tax:<key>:up` or `tax:<key>:down`. It has no law's position, so
## each way stands here: a rise reads left of centre, a cut right. A STAND-IN.
const TAX_PREFIX := "tax:"
const TAX_POSITION := {
	"up": {"economic": -0.4, "social": 0.0},
	"down": {"economic": 0.4, "social": 0.0},
}
