extends RefCounted

## The business cycle -- V1.6a, the first session of the V1.6 block. Booms and
## recessions arriving whether or not the player deserves them. The model and every
## constant's rationale is docs/cycle-model.md; src/sim/cycle_constants.gd is the
## values.
##
## THIS FILE HAS NO tick_month() AND THAT IS THE SESSION'S STRUCTURAL CALL. It is a
## pure read -- Cycle.impulse_pct(ns, year, month) is a function of its arguments and
## nothing else -- and Economy.tick_month() writes ns.cycle_impulse_pct from it in the
## same pre-pass that writes ns.coercion_impulse_pct from Coercion.impulse(). That is
## an existing idiom rather than a new one, and it buys the thing V1.5d paid for:
## `tools/balance_probe.gd` and `tests/test_balance.gd` never called
## Media.tick_month(), so both harnesses ran the pre-session model and their agreement
## was about nothing. Every harness in this project already calls Economy.tick_month().
## A system that CANNOT be forgotten is worth more than one that is remembered, and
## tests/test_cycle.gd reads src/sim/cycle.gd and fails if a tick_month() appears.
##
## NO RANDOMNESS, WHICH IS WHAT "ARRIVING WHETHER OR NOT DESERVED" ACTUALLY NEEDS.
## docs/economy-model.md forbids randf() outright -- determinism is what makes
## Budget.project() exactly equal to what subsequently happens, which is an MVP
## done-when condition, and project() runs the real model on duplicate_state(). So
## the cycle is a pure function of (nation id, absolute month), which is
## src/ui/poll_noise.gd's answer to the same problem from the other side. The
## property the row asks for is ATTRIBUTION -- voters punish you for a downturn you
## did not cause -- and attribution survives a cycle the player can see coming.
## Surprise was never the mechanic; blame is.
##
## THE HASH BELOW IS A SECOND COPY OF poll_noise.gd's AND IS DELIBERATELY NOT SHARED.
## That file's header states, as an architectural claim, that nothing in src/sim/
## references it because the simulation contains no randomness at all. A preload here
## would make that sentence false while changing no behaviour, and the sentence is
## load-bearing: one of these is a RENDER-TIME device that must never touch the model,
## the other is model state. Twelve duplicated lines is the cheaper of the two costs.
##
## WRITES NOTHING. `cycle_impulse_pct` has exactly one writer and it is
## Economy.tick_month(), the discipline `share`, `state_share`, `regulation_burden`,
## `migration_stance`, `settlement_stance` and `gini_index` all hold to.
## tests/test_cycle.gd asserts it by reading this file.

const K = preload("res://src/sim/cycle_constants.gd")

const _U32 := 0xFFFFFFFF


## The cycle's contribution to a nation's annualised growth this month, in points.
##
## EXACTLY 0.0 AT NEW GAME FOR ALL TEN NATIONS, by construction rather than by
## arrangement: every term is `sin(2*PI*t/P)` with no phase offset, so t = 0 makes
## each one exactly zero. That matters more here than the same claim did for the firm
## register, because it is not about a bit-identical re-run -- this session's is
## predicted not to be -- but about the data files. `imported.unemployment_pct` says
## France starts at 7.4 and `SECTOR_TREND` says it grows at 1.31; a cycle that started
## mid-slump would hand the player an opening month its own content denies.
##
## The ten diverge IMMEDIATELY nonetheless, because the sign of each term is drawn
## from the hash: month 1 finds some nations rising and others falling, which a shared
## zero phase with no signs could not do.
##
## `year` and `month` against a CONSTANT epoch rather than a stored reference month,
## and that is not a stylistic choice -- see CYCLE_EPOCH_YEAR, which records the
## harness trap it exists to survive.
static func impulse_pct(ns, year: int, month: int) -> float:
	var t: float = float(
		_absolute_month(year, month)
		- _absolute_month(K.CYCLE_EPOCH_YEAR, K.CYCLE_EPOCH_MONTH)
	)
	var rel: float = float(ns.cycle_amplitude_rel)
	if rel <= 0.0 or is_zero_approx(K.CYCLE_AMPLITUDE_PCT):
		return 0.0

	# Variance shares, not weights: sqrt(s) and sqrt(1-s) keep the sum's standard
	# deviation at exactly 1.0 for every value of the share, so CYCLE_COMMON_SHARE
	# controls only how much of the cycle crosses borders and never how big it is.
	# Plain s and 1-s would shrink the total by up to 30 % in the middle of the range
	# and hand the sweep two coupled constants -- the three-way weight table
	# docs/bloc-model.md's rule severities warn about, in miniature.
	var s: float = clampf(K.CYCLE_COMMON_SHARE, 0.0, 1.0)
	var common: float = _wave(K.CYCLE_COMMON_SEED, t)
	var own: float = _wave(ns.id, t)

	return K.CYCLE_AMPLITUDE_PCT * rel * (sqrt(s) * common + sqrt(1.0 - s) * own)


## Months since year 0. src/ui/poll_noise.gd's `poll_id()` in the other units, and
## the same reason: an integer that increases by one per step and never wraps.
static func _absolute_month(year: int, month: int) -> int:
	return year * 12 + month


## Where the ten sit relative to potential this month, for a probe or a panel that
## wants the wave without the amplitude. Returns the unit wave, standard deviation
## 1.0, so a table of it is comparable across nations of different volatility.
static func unit_wave(ns, year: int, month: int) -> float:
	if is_zero_approx(K.CYCLE_AMPLITUDE_PCT) or float(ns.cycle_amplitude_rel) <= 0.0:
		return 0.0
	return impulse_pct(ns, year, month) / (K.CYCLE_AMPLITUDE_PCT * float(ns.cycle_amplitude_rel))


## A unit-standard-deviation wave for one seed. Three sines, one drawn from each of
## CYCLE_PERIOD_BANDS, each with a hashed sign and NO phase offset.
##
## The normalisation is analytic and not fitted: N unit sines at incommensurate
## periods have standard deviation sqrt(N/2), so dividing by it gives exactly 1.0 and
## `CYCLE_AMPLITUDE_PCT` is then the wave's standard deviation in the units its name
## claims. tests/test_cycle.gd measures it over a long run rather than trusting this
## comment.
static func _wave(seed_key: String, t: float) -> float:
	var total := 0.0
	for k in range(K.CYCLE_TERMS):
		var band: Array = K.CYCLE_PERIOD_BANDS[k]
		var lo: int = int(band[0])
		var hi: int = int(band[1])
		# Period drawn per (seed, term) so two nations sharing one period still differ
		# in the other two, and separated bands so the three can never collapse into a
		# near-single frequency for an unlucky draw.
		var period: float = float(lo) + unit(seed_key, k * 2) * float(hi - lo)
		var sign_bit: float = 1.0 if unit(seed_key, k * 2 + 1) < 0.5 else -1.0
		total += sign_bit * sin(TAU * t / period)
	return total / sqrt(float(K.CYCLE_TERMS) / 2.0)


## Deterministic uniform in [0, 1) from a string seed and an integer index.
## splitmix32's finaliser over an FNV-1a of the key, which is src/ui/poll_noise.gd's
## `_unit()` with the arguments the other way round -- see this file's header for why
## the two are not shared.
##
## PUBLIC SINCE V1.8, AND THE THIRD COPY IS THE ONE THAT WAS REFUSED. This file's
## header justifies duplicating poll_noise.gd's hash on a BOUNDARY -- one of the two is
## a render-time device that must never touch the model -- and that argument does not
## transfer to a second file inside src/sim/. src/sim/events.gd draws its hazard from
## here rather than carrying a third copy, so there is exactly one deterministic draw in
## the simulation and one outside it. tests/test_events.gd reads that file and fails if
## a splitmix constant appears in it.
static func unit(seed_key: String, index: int) -> float:
	var z: int = (_key_seed(seed_key) + index * 0x9E3779B1) & _U32
	z = (z + 0x9E3779B9) & _U32
	z = ((z ^ (z >> 16)) * 0x21F0AAAD) & _U32
	z = ((z ^ (z >> 15)) * 0x735A2D97) & _U32
	z = (z ^ (z >> 15)) & _U32
	return float(z & 0xFFFFFF) / float(0x1000000)


static func _key_seed(key: String) -> int:
	var h: int = 2166136261
	for i in key.length():
		h = (h ^ key.unicode_at(i)) & _U32
		h = (h * 16777619) & _U32
	return h
