extends RefCounted

## Where a national quantity happens -- V2.6b1. Model: docs/siting-model.md.
##
## THE CONTRACT V2.9 READS. docs/tiers/v2.md section 9 books "sited disasters -- an
## event with a place, which V1.8's schema cannot express", and this file is what
## "a place" means after this session: a REGION ID, chosen as the arg-max of the
## caller's own weights times the caller's own signal, derived on every read and
## stored nowhere. A caller supplies two Dictionaries and gets back a string.
##
## A TRUE LEAF -- it preloads NOTHING. src/sim/regions.gd preloads two constants
## files and calls itself a leaf; this preloads none, because the whole point is
## that unrest, a disaster and anything later can call it without any of them
## knowing about each other. It takes plain Dictionaries rather than a register or
## a NationState for the same reason: U6a's Calendar.due() shape taken one step
## further, where even the register's SHAPE is the caller's business.
##
## NO RANDOMNESS. V1.8's rule and V1.6a's before it: site() is arg-max and pick()
## takes its draw as an argument, so the one deterministic draw in the simulation
## stays in cycle.gd and there is not a second one here. A save reloaded on the
## month a demonstration happened receives the same demonstration in the same place.
##
## WHY margin() AND signal_moves_site() ARE PUBLIC SURFACE, and this is the file's
## sharpest sentence: V2.6b's ROADMAP row claimed both its halves "decide WHERE by
## reading V2.6a's live shares", and the step-0 measurement showed the site is a
## CONSTANT STRING for the whole game in all three playable nations -- FRA's winner
## leads by 71.3 % under the level form and 78.1 % under the deviation form, while
## migration's entire fourteen-year budget is 0.0164 share points, about 9 %
## relative. The shares are third-order behind static content. Nothing in this
## project had a way to ASK that question, so the row could assert a live read that
## is arithmetically static and no check could contradict it. These two functions
## turn it into a probe column, per nation, forever -- and any later session siting
## anything owes its own margin() before it claims a place moves.
## See docs/siting-model.md sections 2 and 3.


## `values` rescaled so that their `weights`-weighted mean is EXACTLY 1.0.
##
## The anti-rescale primitive, and it exists because a multiplier whose mean is not
## one is a silent retune of whatever constant it multiplies. V1.6e shipped a flat
## bill that gave services a 63:1 advantage over agriculture for identical money;
## the same failure in a multiplier is harder to see, because every individual
## factor looks reasonable. Callers assert the property rather than trusting it --
## tests/test_siting.gd checks it at 1e-12, the sum-to-zero idiom
## Trade.sector_shift(), Regions.trend_deviation_pct() and Migration.share_delta()
## each already use.
##
## An empty or zero-weight input returns the values untouched: there is no mean to
## normalise against, and inventing one would be a number no data produced.
static func normalised(values: Dictionary, weights: Dictionary) -> Dictionary:
	var weighted: float = 0.0
	var total: float = 0.0
	var ids: Array = values.keys()
	ids.sort()
	for id in ids:
		var w: float = float(weights.get(id, 0.0))
		weighted += w * float(values[id])
		total += w
	if total <= 0.0 or weighted <= 0.0:
		return values.duplicate()
	var mean: float = weighted / total
	var out: Dictionary = {}
	for id in ids:
		out[id] = float(values[id]) / mean
	return out


## How far each value stands ABOVE its own weighted mean, and absent for everything
## at or below it.
##
## THE ZERO-MEAN IDIOM, FOURTH INSTANCE, and here it is a selector rather than a
## conservation law. Scoring on the level instead puts the demonstration wherever
## the most people are, which is a fact about population and not about grievance:
## measured, the level form sites France in Ile-de-France and the deviation form in
## Hauts-de-France, which is where France's unemployment actually is. Recorded in
## docs/siting-model.md section 3 with both tables, because the choice between them
## FLIPS THE SIGN of the price built on top.
##
## RETURNS {} WHEN NOTHING EXCEEDS THE MEAN, and that empty answer is a REAL answer
## rather than a missing one. Britain's twelve regions carry unemployment_rel
## exactly 1.0 -- V2.5 section 8's ITL1 index proxy, the same construction that gave
## V2.6a `moved 0.000` -- so nothing is above its own mean and Britain has NO SITE.
## Luxembourg is one region and cannot differ from itself. Both bounds fall out as
## arithmetic here rather than as a branch anywhere, which is what V2.6a's own two
## bounds did and the reason they were worth recording rather than special-casing.
static func excess(values: Dictionary, weights: Dictionary) -> Dictionary:
	var weighted: float = 0.0
	var total: float = 0.0
	var ids: Array = values.keys()
	ids.sort()
	for id in ids:
		var w: float = float(weights.get(id, 0.0))
		weighted += w * float(values[id])
		total += w
	if total <= 0.0:
		return {}
	var mean: float = weighted / total
	var out: Dictionary = {}
	for id in ids:
		var over: float = float(values[id]) - mean
		if over > 0.0:
			out[id] = over
	return out


## The place: arg-max of `weights[id] * signals[id]`.
##
## TIES BROKEN BY SORTED ID, so a Dictionary's insertion order can never reach a
## result -- Migration._tick_nation()'s frozen-snapshot discipline applied to a
## choice rather than to a sum, and the reason every loop in this file sorts first.
##
## "" WHEN EVERY SCORE IS <= 0.0, which is the no-site answer excess() produces for
## Britain and Luxembourg. A caller must handle it; concentration() and the price
## built on it read exactly 1.0 there, so a no-site nation is unpriced rather than
## specially cased.
static func site(weights: Dictionary, signals: Dictionary) -> String:
	var best: String = ""
	var best_score: float = 0.0
	var ids: Array = signals.keys()
	ids.sort()
	for id in ids:
		var score: float = float(weights.get(id, 0.0)) * float(signals[id])
		if score > best_score:
			best_score = score
			best = String(id)
	return best


## Every score, sorted descending and by id within a tie, as [[score, id], ...].
## Private to margin() and pick(); kept apart so site() stays the cheap read the
## monthly tick makes.
static func _ranked(weights: Dictionary, signals: Dictionary) -> Array:
	var rows: Array = []
	var ids: Array = signals.keys()
	ids.sort()
	for id in ids:
		rows.append([float(weights.get(id, 0.0)) * float(signals[id]), String(id)])
	rows.sort_custom(_score_before)
	return rows


static func _score_before(a: Array, b: Array) -> bool:
	if float(a[0]) != float(b[0]):
		return float(a[0]) > float(b[0])
	return String(a[1]) < String(b[1])


## THE DEGENERACY DETECTOR: the winner's score over the runner-up's, minus one.
##
## The number that says whether a site carries information. 0.781 for France means
## the runner-up would have to gain 78 % to take the place, against a migration
## budget worth about 9 % over fourteen years -- so France's demonstration is in
## Hauts-de-France in month 1 and in month 168 and in every month between, and a
## model doc claiming the site "reads the live shares" is describing an input the
## output cannot see. INF when there is exactly one scoring region (Luxembourg),
## 0.0 when there is no site at all (Britain): three different degeneracies, three
## different values, none of them a crash.
##
## A later session siting anything owes its own margin() before claiming a place
## moves. That is the whole reason this is public surface.
static func margin(weights: Dictionary, signals: Dictionary) -> float:
	var rows: Array = _ranked(weights, signals)
	if rows.is_empty() or float(rows[0][0]) <= 0.0:
		return 0.0
	if rows.size() < 2 or float(rows[1][0]) <= 0.0:
		return INF
	return float(rows[0][0]) / float(rows[1][0]) - 1.0


## Does the signal choose the place, or do the weights choose it on their own?
##
## Compares site(weights, signals) against site(weights, ones). False means the
## signal is decoration: the arg-max of the weights alone would have named the same
## place, so the model may as well not have read the signal. Britain is the case
## this was written for -- its "signal" is a flat 1.0 across twelve regions, so
## under the LEVEL form it is population share wearing a signal's clothes, and this
## function says so in a boolean rather than in a paragraph.
static func signal_moves_site(weights: Dictionary, signals: Dictionary) -> bool:
	var ones: Dictionary = {}
	for id in signals:
		ones[id] = 1.0
	return site(weights, signals) != site(weights, ones)


## The site's weight over the weight-weighted mean weight: how concentrated the
## place is against an average place in the same nation.
##
## EXACTLY 1.0 FOR A NO-SITE NATION, which is what would make Britain's and
## Luxembourg's bounds arithmetic rather than a branch for any price built on it. A
## reader taking the raw weight would be taking a share of a nation, which is not
## comparable between a nation of three regions and one of twenty-one; the ratio is.
##
## NOTHING PRICES THIS TODAY, AND THAT IS A MEASURED RESULT RATHER THAN AN OVERSIGHT.
## V2.6b1 designed a visibility price on it, fixed two clauses before sweeping, and
## found the interval EMPTY: a term big enough to move the panel that prints it has
## to be a third of the entire unrest opinion price and 2.25x what settling the
## strike is worth. The constant was deleted rather than left unused --
## src/sim/unrest.gd's opinion_load() carries the numbers. So this function is a
## DIAGNOSTIC, read by tools/siting_probe.gd and by the readout, in the same
## position as margin(): it says what a place is worth, and the session's finding is
## that saying it is all this quantity can honestly do.
##
## Measured at the shipped sites (docs/siting-model.md section 3): FRA 0.897,
## DEU 1.863, ITA 1.138, GBR 1.000, LUX 1.000 -- BELOW one for France, because the
## place with the excess unemployment is a small place, and nothing authored that.
static func concentration(weights: Dictionary, site_id: String) -> float:
	if site_id == "":
		return 1.0
	var squared: float = 0.0
	var total: float = 0.0
	var ids: Array = weights.keys()
	ids.sort()
	for id in ids:
		var w: float = float(weights[id])
		squared += w * w
		total += w
	if squared <= 0.0 or total <= 0.0:
		return 1.0
	var mean: float = squared / total
	if mean <= 0.0:
		return 1.0
	return float(weights.get(site_id, 0.0)) / mean


## A weighted pick over the same scores, for a caller that supplies its own draw in
## [0, 1). NOT USED BY V2.6b1 -- unrest takes arg-max, because a demonstration is
## organised where the grievance is rather than drawn from a hat.
##
## It is here for V2.9, whose own row is the reason this file is a contract rather
## than three private helpers in unrest.gd: a disaster is NOT always in the biggest
## place, and arg-max structurally cannot express that. The draw is an ARGUMENT so
## the determinism rule holds at the call site -- Events.hazard_passes() derives its
## own from (nation id, event id, absolute month) through Cycle.unit(), and a sited
## disaster would pass that same number here rather than reaching for an RNG this
## file refuses to own.
##
## Same tie rule and same ordering as site(), so the two cannot disagree about
## which id a score belongs to.
static func pick(weights: Dictionary, signals: Dictionary, u: float) -> String:
	var rows: Array = _ranked(weights, signals)
	var total: float = 0.0
	for row in rows:
		if float(row[0]) > 0.0:
			total += float(row[0])
	if total <= 0.0:
		return ""
	var cut: float = clampf(u, 0.0, 1.0) * total
	var seen: float = 0.0
	for row in rows:
		var score: float = float(row[0])
		if score <= 0.0:
			continue
		seen += score
		if seen >= cut:
			return String(row[1])
	return String(rows[0][1])
