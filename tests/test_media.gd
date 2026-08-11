extends SceneTree

## V1.5d. Outlets, framing as a per-bloc salience gain, and press freedom as the fourth
## register on the sixth effect channel. Model: docs/media-model.md.
##
## The load-bearing assertions here are the ones about what does NOT happen:
##
##   - the size-weighted MEAN gain is SALIENCE_GAIN in every state, which is the whole
##     licence for this session to change what the electorate notices without
##     re-baselining a constant measured at S10. It is a property of the mean anchor,
##     so it is asserted rather than hoped for;
##   - the seven nations with no data/outlets/ file read EXACTLY SALIENCE_GAIN forever,
##     exact equality and not is_zero_approx -- V1.4a's standard, and what lets the
##     whole register go live without moving a model nobody asked to move;
##   - total censorship flattens every bloc to EXACTLY SALIENCE_GAIN, which is what
##     makes censorship a decision rather than a free win: it damps a hostile press and
##     an appreciative one alike;
##   - src/sim/media.gd names neither opinion.gd nor foreign_policy.gd, asserted by
##     reading the file -- the first would be a cycle and the second would drag the
##     diplomacy stack into the monthly opinion tick;
##   - Unrest.hardship() passes the UNFRAMED gain, asserted by reading unrest.gd,
##     because that is where this session's real anti-double-count lives;
##   - `press_freedom` has exactly one writer and it is Legislature.apply();
##   - both directions of the clamp are REACHABLE from authored content, which is what
##     stops a symmetric clamp being half decorative.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Media = preload("res://src/sim/media.gd")
const K = preload("res://src/sim/media_constants.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Legislature = preload("res://src/sim/legislature.gd")

const PLAYER := "FRA"
const AUTHORED := ["FRA", "DEU", "GBR"]

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_seeded_at_baseline()
	_check_unauthored_nations_exact()
	_check_mean_is_preserved()
	_check_censorship_flattens()
	_check_clamp_slack()
	_check_weights_stay_on_the_simplex()
	_check_no_authored_alignment()
	_check_preloads()
	_check_hardship_is_unframed()
	_check_single_writer()
	_check_both_directions_reachable()
	_check_press_reaches_unrest()
	_finish()


## Every nation seeds at the unframed baseline, exactly, before a tick has run.
## Media.init_nation() deliberately does NOT derive the gain -- that belongs to
## tick_month(), and computing it in two places would be two writers.
func _check_seeded_at_baseline() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	for id in state.nations:
		var ns = state.nations[id]
		for bloc in OK.BLOC_KEYS:
			var g: float = float(ns.framing_gain.get(bloc, -1.0))
			if g != OK.SALIENCE_GAIN:
				_fail("%s/%s seeds at %s, not SALIENCE_GAIN exactly" % [id, bloc, str(g)])


## The seven nations with no data/outlets/<ID>.json keep the opinion model they have run
## since S10, bit for bit, for a full run. EXACT equality: an approximate check here
## would let a rounding drift through and the whole point of the empty-register property
## is that there is nothing to round.
func _check_unauthored_nations_exact() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	for i in range(168):
		Media.tick_month(state, _loader)
	for id in state.nations:
		if AUTHORED.has(id):
			continue
		var ns = state.nations[id]
		for bloc in OK.BLOC_KEYS:
			var g: float = float(ns.framing_gain.get(bloc, -1.0))
			if g != OK.SALIENCE_GAIN:
				_fail("%s has no outlets file but %s reads %s after 168 months" % [id, bloc, str(g)])


## THE PROPERTY THE MEAN ANCHOR EXISTS FOR. sum_b BLOC_SIZE[b] * gain[b] == SALIENCE_GAIN
## in every state, because the deviation is measured against that very mean. It is what
## lets framing move what each bloc notices while leaving the national calibration alone.
##
## A tight epsilon rather than exact equality, and the distinction is honest: the identity
## is exact in real arithmetic and the sum of six products in floating point is not.
func _check_mean_is_preserved() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	for i in range(168):
		Media.tick_month(state, _loader)
		for id in state.nations:
			var ns = state.nations[id]
			var mean := 0.0
			for bloc in OK.BLOC_KEYS:
				mean += float(OK.BLOC_SIZE[bloc]) * float(ns.framing_gain.get(bloc, 0.0))
			if absf(mean - OK.SALIENCE_GAIN) > 0.000001:
				_fail("%s month %d: size-weighted mean gain is %s, not SALIENCE_GAIN" % [
					id, i, str(mean)
				])
				return


## press_freedom at -MAX flattens every bloc to exactly SALIENCE_GAIN. Total censorship
## erases the media landscape and leaves the national average -- which HELPS the blocs
## reading hostile papers and HURTS the blocs reading friendly ones, and is why
## censorship is not strictly dominated on the framing axis before its unrest price is
## counted at all.
func _check_censorship_flattens() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	for id in AUTHORED:
		if not state.nations.has(id):
			continue
		var ns = state.nations[id]
		ns.press_freedom = -K.PRESS_FREEDOM_MAX
	Media.tick_month(state, _loader)
	for id in AUTHORED:
		if not state.nations.has(id):
			continue
		var ns = state.nations[id]
		for bloc in OK.BLOC_KEYS:
			var g: float = float(ns.framing_gain.get(bloc, -1.0))
			if g != OK.SALIENCE_GAIN:
				_fail("%s/%s under total censorship reads %s, not SALIENCE_GAIN exactly" % [
					id, bloc, str(g)
				])


## FRAMING_GAIN_MIN must be SLACK at the ordinary press, or the clamp is setting the
## number -- the failure this project has named five times. It is slack by 2.009.
##
## AND IT IS REACHED AT A SATURATED FREE PRESS, WHICH IS PINNED RATHER THAN HIDDEN.
## press_freedom = +1.0 doubles the spread in both directions, so the bloc whose paper is
## friendliest to the government arrives at a gain of exactly zero: its readers stop
## amplifying bad news at all. That is DEFINITIONAL saturation and not a guard rail doing
## a constant's work -- unrest_pct's ceiling of 100 has the same character, "approached
## only under a player deliberately maximising it" -- and it takes repeated liberalising
## laws to get there. Asserted in both directions so a later session that changes the
## floor, the beta or the press scaling has to come and look at it.
func _check_clamp_slack() -> void:
	if _lowest_gain(0.0) <= K.FRAMING_GAIN_MIN:
		_fail("framing gain reaches the floor at the ORDINARY press -- the clamp is setting the number")
	if _lowest_gain(K.PRESS_FREEDOM_MAX) > K.FRAMING_GAIN_MIN:
		_fail("a saturated FREE press no longer saturates the gain floor -- the recorded endpoint moved")


func _lowest_gain(press: float) -> float:
	var state = GameState.new_game(_loader, PLAYER)
	var lowest := 1000.0
	for i in range(168):
		for id in AUTHORED:
			if not state.nations.has(id):
				continue
			state.nations[id].press_freedom = press
		Media.tick_month(state, _loader)
		for id in AUTHORED:
			if not state.nations.has(id):
				continue
			for bloc in OK.BLOC_KEYS:
				lowest = minf(lowest, float(state.nations[id].framing_gain.get(bloc, 0.0)))
	return lowest


## The simplex survives a framed gain. salience_weights() renormalises, and the ONE
## branch that does not is the non-positive-total early return -- which is what
## FRAMING_GAIN_MIN exists to keep unreachable. Checked at the floor as well as at the
## authored value, because the floor is the state where it would break.
func _check_weights_stay_on_the_simplex() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	var sat: Dictionary = Opinion.issue_satisfaction(ns)
	for gain in [K.FRAMING_GAIN_MIN, 1.0, OK.SALIENCE_GAIN, 40.0]:
		for bloc in OK.BLOC_KEYS:
			var w: Dictionary = Opinion.salience_weights(OK.BLOC_SALIENCE_BASE[bloc], sat, gain)
			var total := 0.0
			for issue in w:
				total += float(w[issue])
			if absf(total - 1.0) > 0.000001:
				_fail("gain %s bloc %s: weights sum to %s, off the simplex" % [
					str(gain), bloc, str(total)
				])


## No outlet may author its own alignment. The whole point of deriving it is that the
## press turns on you when your GOVERNMENT changes, so an authored one would be a second
## writer of a quantity that has to stay derived -- src/core/company.gd's absent-owner
## refusal in a third register.
func _check_no_authored_alignment() -> void:
	for id in AUTHORED:
		var text := FileAccess.get_file_as_string("res://data/outlets/%s.json" % id)
		if text.is_empty():
			_fail("data/outlets/%s.json is missing" % id)
			continue
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			_fail("data/outlets/%s.json did not parse" % id)
			continue
		for entry in parsed.get("outlets", []):
			for banned in ["alignment", "hostility", "bias", "stance", "leaning"]:
				if entry.has(banned):
					_fail("%s: outlet '%s' authors '%s' -- alignment is derived, never written" % [
						id, str(entry.get("id", "?")), banned
					])


## media.gd's preload list, read off the file. Two names must never appear:
## opinion.gd, because opinion.gd reads this file's output off NationState and a reverse
## edge is a cycle; and foreign_policy.gd, whose _position_alignment() is four identical
## lines but which preloads trade.gd which preloads coercion.gd -- an edge that would
## drag the whole diplomacy stack into the monthly opinion tick.
func _check_preloads() -> void:
	var text := FileAccess.get_file_as_string("res://src/sim/media.gd")
	if text.is_empty():
		_fail("could not read src/sim/media.gd")
		return
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("const "):
			continue
		if trimmed.contains("preload(\"res://src/sim/opinion.gd\")"):
			_fail("media.gd preloads opinion.gd -- that is a cycle, the gain is read off NationState")
		if trimmed.contains("foreign_policy"):
			_fail("media.gd preloads foreign_policy.gd -- it pulls trade.gd and coercion.gd into the opinion tick")


## THE SESSION'S REAL ANTI-DOUBLE-COUNT, asserted by reading the file. If hardship()
## took the framed gain, press_freedom would reach the grievance target twice -- once
## here and once through PRESS_UNREST_BETA -- which is the same act, the same landing
## site and the same units. It is refused in a signature rather than at load because it
## is one register reaching one number twice through code, not two keys on one law.
func _check_hardship_is_unframed() -> void:
	var text := FileAccess.get_file_as_string("res://src/sim/unrest.gd")
	if text.is_empty():
		_fail("could not read src/sim/unrest.gd")
		return
	if text.contains("Media") or text.contains("media.gd"):
		_fail("unrest.gd names Media -- the grievance term must not see the framed gain")
	if not text.contains("OpinionK.SALIENCE_GAIN"):
		_fail("unrest.gd's salience_weights() call does not state OpinionK.SALIENCE_GAIN explicitly")


## `press_freedom` has exactly one writer, and it is Legislature.apply(). Read off the
## files, the idiom people-model.md, calendar-model.md and society-model.md all use for
## a property no runtime check expresses.
func _check_single_writer() -> void:
	for path in ["res://src/sim/media.gd", "res://src/sim/unrest.gd", "res://src/sim/opinion.gd"]:
		var text := FileAccess.get_file_as_string(path)
		if text.contains("ns.press_freedom ="):
			_fail("%s writes ns.press_freedom -- Legislature.apply() is the only writer" % path)


## Both directions of the symmetric clamp must be reachable from authored content, or
## half of it is decoration. society_constants.CORRUPTION_MAX's check, transferred.
func _check_both_directions_reachable() -> void:
	var raises := false
	var lowers := false
	for law in _loader.laws:
		var society: Dictionary = law.effects.get("society", {})
		if not society.has("press_freedom"):
			continue
		if float(society["press_freedom"]) > 0.0:
			raises = true
		elif float(society["press_freedom"]) < 0.0:
			lowers = true
	if not raises:
		_fail("no law raises press_freedom -- the positive half of the clamp is unreachable in play")
	if not lowers:
		_fail("no law lowers press_freedom -- the censorship half is unreachable in play")


## The second of press freedom's two prices: a censored press raises the grievance
## stock. This is V1.5d's answer to "a dial with legitimacy costs", and the reason no
## legitimacy quantity was invented -- so it has to be live rather than argued.
func _check_press_reaches_unrest() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	var quiet := Unrest.unrest_target(ns)
	ns.press_freedom = -K.PRESS_FREEDOM_MAX
	var censored := Unrest.unrest_target(ns)
	if censored <= quiet:
		_fail("total censorship does not raise the grievance target (%s -> %s)" % [
			str(quiet), str(censored)
		])
	ns.press_freedom = K.PRESS_FREEDOM_MAX
	var freed := Unrest.unrest_target(ns)
	if freed > quiet:
		_fail("a freer press raises the grievance target (%s -> %s) -- the sign is inverted" % [
			str(quiet), str(freed)
		])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_media: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	print("test_media: %d failure(s)" % _failures.size())
	quit(1)
