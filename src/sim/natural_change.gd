extends RefCounted

## Natural change -- V2.6c, the third flow on the population-share registers.
## Model: docs/natural-change-model.md.
##
## BIRTHS AND DEATHS ARE PER-HEAD BIOLOGY HAPPENING WHERE THE PEOPLE ARE, and that
## sentence is the anchor decision. The flow moves each region's share of its nation
## by the region's MEASURED natural-change rate against the nation's live-share-
## weighted mean, `ds_i = s_i * (nc_i - mean) / 12`, so the named regions
## redistribute the differential around themselves and the sum telescopes to exactly
## zero in the weights the deltas use -- Migration.share_delta()'s invariant, Trade
## .sector_shift()'s and Regions.trend_deviation_pct()'s, at the same register those
## three already hold.
##
## THE ANCHOR LESSON CUTS BOTH WAYS, and this file is on the V2.6b1 side of the line.
## V2.6b2 moved campaign reach OFF population weighting because reach is delivered
## where the PLAYER goes; output is lost where the people are (V2.6b1), and births
## happen where the people are too. A uniform mean-one anchor here would be the
## campaign error mirrored: it would claim a region's birth rate tells its people
## nothing about where births happen. The mean is in LIVE shares, recomputed every
## month against the snapshot the deltas use, which is also what makes the flow
## self-damping -- a region growing by natural change raises the mean it is measured
## against, exactly Harris-Todaro's negative feedback with the mechanism replaced.
##
## THE NATIONAL TOTAL IS NOT THIS FILE'S BUSINESS, and that is the conservation law
## the block split on. Internal migration is zero-sum nationally and so is this
## redistribution; actual births and deaths are not zero-sum, and they are already
## inside Economy's measured `pop_growth_pct` compound -- the PARTITION decision,
## V1.4a's idiom: the national figure stays the measured one and the regions divide
## it, rather than the national number being re-based from regional rates. The
## unnamed residual (extra-regio and rural) implicitly grows at the national rate;
## authoring it a rate of its own would be a number nobody measured.
##
## A PURE LEAF, STRICTER THAN SITING.GD: no preloads at all, no NationState, no
## writes. The caller freezes the shares and the rates into dictionaries -- the
## snapshot discipline migration.gd's own comment states -- and applies what comes
## back, so migration.gd stays the single writer to the registers and
## tests/test_geography.gd's one-reader scan never hears this file's name. The rate
## reaches the caller through Regions.natural_change_pct(), the wrapper
## unemployment_rel already travels behind, so no file outside regions.gd names the
## field.


## The one expression. `rate_pct_yr` and `mean_rate_pct_yr` are per cent per year,
## the register's own convention beside `pop_growth_pct`; the /1200 is the per-cent
## conversion and the month, one denominator rather than two so the expression
## cannot be half-converted. Signed both ways -- a region below the mean sheds share
## to the ones above it. Migration.share_delta() is the same shape with the tuned
## rate in the first slot and an economic pull in the second; this file cannot
## preload migration.gd without inverting the leaf, so the correspondence lives in
## this comment and tests/test_natural_change.gd holds both to their documented
## signs.
static func share_delta(share: float, rate_pct_yr: float, mean_rate_pct_yr: float) -> float:
	return share * (rate_pct_yr - mean_rate_pct_yr) / 1200.0


## The mean of the rates in the SAME share weights the deltas apply, taken over the
## named regions -- not over the nation, because the named set is what the flow may
## move and the residual has no rate of its own (the comment above). The sum of the
## deltas telescopes to exactly zero against THIS number in THESE weights, which is
## why it is computed from the same snapshot rather than read back after applying.
static func named_mean(shares: Dictionary, rates: Dictionary) -> float:
	var weighted: float = 0.0
	var total: float = 0.0
	for id in shares.keys():
		var s: float = float(shares[id])
		weighted += s * float(rates[id])
		total += s
	if total <= 0.0:
		return 0.0
	return weighted / total


## Every named region's delta for one month. The caller freezes `shares` and
## `rates` -- keyed by region id -- out of start-of-step state, and the returned
## dictionary carries one delta per key, conservation exact because the mean is
## taken in the same weights the deltas multiply. A missing key in `rates` is a
## runtime error rather than a silent zero: the register guarantees the field, and
## a rate that quietly reads as "births exactly offset deaths" is a confident claim
## nobody measured -- region.gd's own reason for refusing the absent field.
##
## FEWER THAN TWO NAMED REGIONS RETURNS EMPTY, and that is Luxembourg's bound made
## arithmetic rather than a special case: one region cannot differ from its own
## mean, and doing the arithmetic anyway would spend float precision on a
## guaranteed no-op -- migration.gd's reason at the city level, one level up.
static func deltas(shares: Dictionary, rates: Dictionary) -> Dictionary:
	if shares.size() < 2:
		return {}
	var mean: float = named_mean(shares, rates)
	var out: Dictionary = {}
	for id in shares.keys():
		out[id] = share_delta(float(shares[id]), float(rates[id]), mean)
	return out
