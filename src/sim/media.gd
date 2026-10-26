extends RefCounted

## Media and framing — V1.5d, the fourth and last session of the V1.5 block.
##
## THE MACHINE THIS FILE FEEDS ALREADY EXISTED. opinion.gd's salience_weights() has
## amplified bad news at a global SALIENCE_GAIN since S10: amplification with no source.
## docs/tiers/v1.md section 5's first bullet asks for outlets that "frame the player's
## actions", and framing is not a new machine — it is the SOURCE of one this project has
## been running for six blocks. So this file writes no accumulator, adds no opinion issue
## and invents no quantity; it makes one existing scalar into six, and the six average
## back to the one. See docs/media-model.md.
##
## WHAT AN OUTLET DOES, IN ONE PARAGRAPH. Every outlet names one audience bloc and sits
## somewhere in the same two-axis ideology space parties, laws and bloc proposals all
## live in. Its hostility is its DISTANCE from the government's own coalition_position —
## derived, never authored, which is why the press turns on you when your government
## re-forms. A bloc's hostility is its outlets' reach-weighted sum, and the bloc's gain
## moves with that hostility MEASURED AGAINST THE NATIONAL MEAN.
##
## THE MEAN ANCHOR IS THE SESSION'S ONE MODEL CORRECTION, and it was forced by a
## measurement taken before a line of this file was written. The design was anchored on
## the nation's own press stance at new game — start_service_quality's idiom, the one
## this project reaches for by reflex. tools/media_probe.gd table (A) refuted it: over
## 168 months France's coalition_position travels 0.044 where Germany's travels 0.600
## and Britain's 0.870, because France holds a majority through every election. That put
## the constant at about 16 for Britain and about 250 for FRANCE, which is the nation
## the game is about — docs/foreign-policy-model.md's globally-anchored amity, in a new
## place.
##
## Anchoring on the size-weighted mean buys four things a start anchor could not:
##
##   1. sum_b BLOC_SIZE[b] * dev[b] is EXACTLY 0, so the size-weighted mean gain is
##      exactly SALIENCE_GAIN and every opinion constant measured since S10 keeps its
##      calibration. A property, not an approximation — tests/test_media.gd asserts it
##      with exact equality.
##   2. The channel is driven by the SPREAD of authored outlet positions rather than by
##      government travel, so France works. Travel still moves the whole landscape for
##      Germany and Britain, which is the story the row wants; it is simply no longer
##      the only driver.
##   3. A FRIENDLY press gets a channel. Under a start anchor it could not have one:
##      severity is clampf(-sat, 0, 1), so good news is already at zero and any lowering
##      of the gain was a free win — censorship would have been strictly dominated on
##      the framing axis, the shape this project has killed five times. Mean-anchored, a
##      friendly press puts a bloc BELOW baseline, which is a real thing to lose.
##   4. press_freedom = -1 flattens every bloc to exactly SALIENCE_GAIN. Total
##      censorship erases the media landscape and leaves the national average: it helps
##      the blocs reading hostile papers and HURTS the blocs reading friendly ones. That
##      is what makes censorship a decision rather than a free win, before the unrest
##      price is counted at all.
##
## PRELOADS TWO CONSTANT FILES AND NOTHING ELSE, and the exclusions are load-bearing.
## Not opinion.gd, because opinion.gd reads this file's output off NationState and a
## reverse edge would be a cycle. Not foreign_policy.gd for its _position_alignment(),
## even though the four lines are identical: that file preloads trade.gd which preloads
## coercion.gd, and this one is read from inside the monthly opinion tick, so the edge
## would drag the whole diplomacy stack in behind it. The distance is copied and
## MAX_POSITION_DISTANCE is declared locally, for the reason foreign_policy.gd gives
## about its own copy — the number is geometry, not a tuning.
## tests/test_media.gd reads this file and fails if either name appears in it.

const K = preload("res://src/sim/opinion_constants.gd")
const MK = preload("res://src/sim/media_constants.gd")


## Seed every bloc's gain at the unframed baseline.
##
## THERE IS NO REFERENCE CAPTURED HERE, and that absence is the design rather than an
## omission. Every stock this block shipped captured one — start_service_quality at
## V1.5a, start_young_share at V1.5b, start_gini_index at V1.5c — because each measures
## a deviation from where the nation began. This one measures a deviation from where the
## nation's other blocs are RIGHT NOW, which is recomputed from content and from a
## coalition_position the save already carries. That is what keeps SAVE_VERSION at 18,
## and tests/test_save_load.gd pins the absence so a later session storing a baseline
## has to come and say why.
##
## Called after Government.init_nation(), NOT beside the other init_nation() calls.
## coalition_position is NEUTRAL_POSITION until Government.form() runs, so a gain
## computed any earlier would measure every outlet's distance to the origin — and while
## this function does not read it, tick_month() does, so the ordering is asserted where
## it can be checked rather than left to a comment. Society.init_nation()'s constraint
## one session on.
static func init_nation(ns) -> void:
	var gains := {}
	for bloc in K.BLOC_KEYS:
		gains[bloc] = K.SALIENCE_GAIN
	ns.framing_gain = gains


## Rewrite every nation's per-bloc gain from the live register.
##
## Runs BEFORE Opinion.tick_month(), which is the opposite of where Society and Unrest
## sit and for a reason that is about what is being read rather than about precedence.
## Those two write a load opinion consumes NEXT month, deliberately, to break a loop
## that runs through approval. This file reads coalition_position, which Elections and
## Government write AFTER Opinion in the same tick — so reading it here is already
## reading last month's government, and the loop
##
##     approval -> censure -> re-formation -> framing -> approval
##
## is broken structurally rather than by being careful. Sixth time that argument has
## been made in this project and the first where the lag comes for free.
static func tick_month(state, loader) -> void:
	for id in state.nations:
		var ns = state.nations[id]
		var outlet_list: Array = loader.outlets.get(id, [])
		ns.framing_gain = framing_gains(ns, outlet_list)


## The whole model, in one pure function over one nation.
##
## Returns a gain per bloc. With no outlets every entry is exactly SALIENCE_GAIN — not
## approximately, EXACTLY, because raw and mean are both 0.0 and the arithmetic below
## multiplies SALIENCE_GAIN by (1 + beta * 0.0). That is what lets the seven
## non-playable nations keep the opinion model they have run since S10 bit for bit, and
## it is companies-model.md's read-exactly-0.0 property in a fourth register.
static func framing_gains(ns, outlet_list: Array) -> Dictionary:
	var raw := {}
	for bloc in K.BLOC_KEYS:
		raw[bloc] = 0.0

	for outlet in outlet_list:
		if not raw.has(outlet.audience):
			continue
		# Hostility is the NEGATIVE of alignment, so a paper standing where the
		# government stands damps its readers' gain and one standing across the room
		# raises it.
		raw[outlet.audience] = float(raw[outlet.audience]) + outlet.reach * -_alignment(
			outlet.position, ns.coalition_position
		)

	# The anchor. Size-weighted so that the mean gain is preserved against the figure
	# opinion.gd's approval is actually built from -- an unweighted mean over six blocs
	# would preserve the wrong average and quietly move the headline.
	var mean := 0.0
	for bloc in K.BLOC_KEYS:
		mean += float(K.BLOC_SIZE[bloc]) * float(raw[bloc])

	var gains := {}
	for bloc in K.BLOC_KEYS:
		# A bloc with no outlet at all lands at -mean: no papers, no amplification, so
		# it sits BELOW the national average rather than at it. That is what makes
		# `reach` load-bearing instead of cosmetic, and GBR's students row is authored
		# empty so a real game exercises it.
		var dev: float = (1.0 + ns.press_freedom) * (float(raw[bloc]) - mean)
		gains[bloc] = maxf(
			MK.FRAMING_GAIN_MIN, K.SALIENCE_GAIN * (1.0 + MK.FRAMING_BETA * dev)
		)
	return gains


## What the overview prints, and the one number a player can act on: how far this
## nation's press has pulled its blocs apart, as a signed spread around the baseline.
##
## Zero for a nation with no outlets and zero under total censorship, which is why the
## readout is SILENT at zero rather than printing a permanent "press normal" row --
## society-model.md section 11's discipline, and the failure it names four times.
static func press_spread(ns) -> float:
	var worst := 0.0
	for bloc in K.BLOC_KEYS:
		var g: float = float(ns.framing_gain.get(bloc, K.SALIENCE_GAIN))
		worst = maxf(worst, absf(g - K.SALIENCE_GAIN))
	return worst


## 1.0 where the two positions coincide, -1.0 at opposite corners of the space.
##
## Copied from foreign_policy.gd rather than shared, and the header says why. The x2 is
## what puts the result on [-1, +1] instead of [0, 1]: an outlet is not merely
## un-aligned at the far corner, it is opposed, and a hostility that could never go
## negative would give a friendly press no channel -- which is the defect the mean
## anchor exists to fix, arriving a second time through the alignment term.
## V5.2d. An outlet's alignment with the nation's government, the reader the
## front page needs (src/sim/front_page.gd cuts it into tones): exposed here so
## the press has ONE alignment, never a copy of _alignment below.
static func outlet_alignment(outlet, ns) -> float:
	return _alignment(outlet.position, ns.coalition_position)


static func _alignment(a: Dictionary, b: Dictionary) -> float:
	var de: float = float(a.get("economic", 0.0)) - float(b.get("economic", 0.0))
	var ds: float = float(a.get("social", 0.0)) - float(b.get("social", 0.0))
	var dist := sqrt(de * de + ds * ds)
	return 1.0 - 2.0 * dist / MK.MAX_POSITION_DISTANCE
