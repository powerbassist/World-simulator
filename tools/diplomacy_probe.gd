extends SceneTree

## Diplomacy envelope probe: godot --headless --script res://tools/diplomacy_probe.gd
##
## V1.3a's named measurement, run BEFORE any action content was authored -- which
## is the whole point of it. An action whose bloc effect is invisible against
## src/ui/poll_noise.gd is a decorative verb, and finding that after the content
## exists is finding it too late. Same discipline docs/scenario-model.md,
## docs/amendment-model.md and docs/dissolution-model.md each used.
##
## Two tables, because two different things can be wrong:
##
##   1. REACHABLE RANGE. Under DRIFT_RATE, how far from its resting value can a
##      player actually push a pair, and how long does it take to come back?
##      If the answer is "barely at all", no action's `relations` precondition
##      can ever bite, and the plan named that in advance as a MODEL decision --
##      the drift constant, or relations as a rate rather than a level -- not a
##      tuning call.
##
##   2. DOMESTIC VISIBILITY. A bloc offset moves an approval TARGET, and
##      opinion.gd walks approval toward that target at INERTIA_RATE. Poll noise
##      is +-NOISE_MAX_PCT. So: which offset magnitudes produce a move a player
##      can actually read off the polling panel, and how much smaller is the
##      move in the overall roll-up than in the bloc that was hit?
##
## Deliberately sweeps SYNTHETIC magnitudes rather than data/diplomatic-actions/
## content: at the time this first ran there was no content, because the content
## is what the numbers below are for.
##
## Not a test. tests/test_diplomacy.gd asserts the invariants; this prints the
## spread a human reads. Kept in tools/ and excluded from run_tests.sh, same as
## balance_probe.gd and scenario_probe.gd.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Relations = preload("res://src/core/relations.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")

const PLAYER := "FRA"
const START_YEAR := 2026

## One term of pushing, then one term of letting go. Long enough that the
## push reaches its equilibrium and the recovery is measured rather than
## extrapolated.
const PUSH_MONTHS := 60
const RELEASE_MONTHS := 120

## Domestic visibility runs over a year: an effect that has not shown up in
## twelve months has not shown up.
const OPINION_MONTHS := 12

## The pairs worth sweeping: one at each end of the derived resting range.
## DEU is EU + border (the ceiling), GBR is neither (the floor).
const PAIRS := [["FRA", "DEU"], ["FRA", "GBR"]]

const DELTAS := [3.0, 5.0, 8.0, 12.0]
const COOLDOWNS := [6, 12, 24]

const OFFSETS := [0.02, 0.04, 0.06, 0.08, 0.12]


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	_resting_table(loader)
	_range_table(loader)
	_decay_table(loader)
	_opinion_table(loader)
	quit(0)


## What the derivation actually produces across the whole roster, printed first
## because every number in the two tables below is relative to one of these.
func _resting_table(loader) -> void:
	print("\n########## derived resting values ##########")
	print("base %.1f  +eu %.1f  +border %.1f  drift %.3f/month" % [
		DK.REST_BASE, DK.EU_CO_MEMBER_BONUS, DK.SHARED_BORDER_BONUS, DK.DRIFT_RATE,
	])
	print("%-10s %8s %8s %8s   %s" % ["pair", "resting", "both eu", "border", "note"])
	print("-".repeat(64))

	var lowest := 999.0
	var highest := -999.0
	for pair in Relations.all_pairs(loader.nations.keys()):
		var a = loader.nations[pair[0]]
		var b = loader.nations[pair[1]]
		var value := Diplomacy.resting(a, b)
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
		print("%-10s %8.1f %8s %8s" % [
			Relations.key(pair[0], pair[1]), value,
			"yes" if (a.eu_member and b.eu_member) else "no",
			"yes" if a.neighbours.has(b.id) else "no",
		])
	print("-".repeat(64))
	print("spread across the roster: %.1f to %.1f (%.1f points)" % [lowest, highest, highest - lowest])


## Table 1. Push a pair with a repeated action, then stop and watch it come back.
## Runs the real Diplomacy.tick_month() rather than solving the geometric series,
## so the clamp and the integer cooldown are in the answer.
func _range_table(loader) -> void:
	print("\n\n########## 1. reachable range ##########")
	print("%d months of repeated use at maximum legal cadence, then %d months of nothing" % [
		PUSH_MONTHS, RELEASE_MONTHS,
	])
	print("%-10s %7s %5s %8s %8s %8s   %s" % [
		"pair", "delta", "cd", "resting", "reached", "moved", "months back within %.0f" % DK.RESTING_EPSILON,
	])
	print("-".repeat(80))

	for pair in PAIRS:
		for delta in DELTAS:
			for cooldown in COOLDOWNS:
				_sweep_one(loader, pair[0], pair[1], delta, cooldown)
				_sweep_one(loader, pair[0], pair[1], -delta, cooldown)
		print("-".repeat(80))


func _sweep_one(loader, a_id: String, b_id: String, delta: float, cooldown: int) -> void:
	var state = GameState.new_game(loader, PLAYER)
	if not state.errors.is_empty():
		printerr("  new_game: %s" % [state.errors])
		return

	var start := Diplomacy.score(state, a_id, b_id)
	var since := 0
	for i in range(PUSH_MONTHS):
		if since <= 0:
			Relations.adjust(state, a_id, b_id, delta, DK.RELATIONS_MIN, DK.RELATIONS_MAX)
			since = cooldown
		since -= 1
		Diplomacy.tick_month(state, loader)

	var reached := Diplomacy.score(state, a_id, b_id)

	var recovered := -1
	for i in range(RELEASE_MONTHS):
		Diplomacy.tick_month(state, loader)
		if absf(Diplomacy.score(state, a_id, b_id) - start) <= DK.RESTING_EPSILON:
			recovered = i + 1
			break

	print("%-10s %+7.1f %5d %8.1f %8.1f %+8.1f   %s" % [
		Relations.key(a_id, b_id), delta, cooldown, start, reached, reached - start,
		str(recovered) if recovered >= 0 else "> %d" % RELEASE_MONTHS,
	])


## Table 1b, added after the first run of table 1 measured the wrong thing for
## the question DRIFT_RATE actually has to answer.
##
## Table 1 sweeps sustained use and then asks how long the pair takes to return
## within one point of resting. From a displacement of twenty points that is
## four-plus half-lives by construction, so almost every row read "> 120" and
## the table looked like it was saying the drift does nothing. It is not: what
## it is saying is that a five-year CAMPAIGN leaves a mark that outlasts the
## player's term, which is a defensible thing for the model to say and not what
## the constant needs to justify.
##
## The number that justifies it is this one: how much of ONE action survives?
## If a single act is still fully present at the next election it is permanent
## state wearing a drift label.
func _decay_table(loader) -> void:
	print("\n\n########## 1b. what survives of a SINGLE action ##########")
	print("one use, then nothing. fraction of the original move still present.")
	print("%-10s %7s %9s %9s %9s %9s" % ["pair", "delta", "@12mo", "@36mo", "@60mo", "half-life"])
	print("-".repeat(60))

	for pair in PAIRS:
		for delta in DELTAS:
			var state = GameState.new_game(loader, PLAYER)
			var start := Diplomacy.score(state, pair[0], pair[1])
			Relations.adjust(state, pair[0], pair[1], delta, DK.RELATIONS_MIN, DK.RELATIONS_MAX)

			var retained := {12: 0.0, 36: 0.0, 60: 0.0}
			var half_life := -1
			for i in range(60):
				Diplomacy.tick_month(state, loader)
				var left: float = (Diplomacy.score(state, pair[0], pair[1]) - start) / delta
				if half_life < 0 and left <= 0.5:
					half_life = i + 1
				if retained.has(i + 1):
					retained[i + 1] = left

			print("%-10s %+7.1f %8.0f%% %8.0f%% %8.0f%% %9s" % [
				Relations.key(pair[0], pair[1]), delta,
				retained[12] * 100.0, retained[36] * 100.0, retained[60] * 100.0,
				"%d mo" % half_life if half_life > 0 else "> 60 mo",
			])
	print("-".repeat(60))


## Table 2. One bloc offset, applied once, measured against a no-action control
## running the same twelve months. Two figures per row because they answer
## different questions: the bloc figure is what the polling panel's per-bloc
## rows show, the overall figure is what the top bar shows -- and an action that
## hits two of six blocs moves the second far less than the first.
func _opinion_table(loader) -> void:
	print("\n\n########## 2. domestic visibility ##########")
	print("poll noise is +-%.1f points (src/ui/poll_noise.gd), so a month-to-month" % PollNoise.NOISE_MAX_PCT)
	print("swing of up to %.1f points is noise alone. inertia %.2f/month." % [
		PollNoise.NOISE_MAX_PCT * 2.0, K.INERTIA_RATE,
	])
	print("target arithmetic: approval target = %.0f + %.0f * (score + offset)," % [
		K.APPROVAL_NEUTRAL, K.APPROVAL_SPAN,
	])
	print("so an offset of %.4f moves a bloc's target exactly %.1f points." % [
		PollNoise.NOISE_MAX_PCT / K.APPROVAL_SPAN, PollNoise.NOISE_MAX_PCT,
	])
	print("")
	print("%-8s %7s %9s %9s %9s %9s   %s" % [
		"offset", "blocs", "bloc@1", "bloc@3", "bloc@12", "all@12", "verdict at 12 months",
	])
	print("-".repeat(84))

	for offset in OFFSETS:
		_opinion_one(loader, offset, K.BLOC_KEYS.size())
		_opinion_one(loader, offset, 2)
	print("-".repeat(84))
	print("verdict compares the OVERALL move against +-%.1f: a figure the top bar" % PollNoise.NOISE_MAX_PCT)
	print("cannot distinguish from a quiet month is a decorative verb.")


func _opinion_one(loader, offset: float, bloc_count: int) -> void:
	var control = GameState.new_game(loader, PLAYER)
	var treated = GameState.new_game(loader, PLAYER)
	if not treated.errors.is_empty():
		printerr("  new_game: %s" % [treated.errors])
		return

	var touched: Array = []
	for i in range(mini(bloc_count, K.BLOC_KEYS.size())):
		touched.append(K.BLOC_KEYS[i])

	var tns = treated.player()
	for bloc in touched:
		tns.bloc_offset[bloc] = float(tns.bloc_offset.get(bloc, 0.0)) + offset

	var cns = control.player()
	var bloc_at := {1: 0.0, 3: 0.0, 12: 0.0}
	var overall_12 := 0.0

	for i in range(OPINION_MONTHS):
		_tick(control, loader, i)
		_tick(treated, loader, i)
		var month := i + 1
		if bloc_at.has(month):
			var sum_t := 0.0
			var sum_c := 0.0
			for bloc in touched:
				sum_t += float(tns.bloc_approval.get(bloc, 0.0))
				sum_c += float(cns.bloc_approval.get(bloc, 0.0))
			bloc_at[month] = (sum_t - sum_c) / float(touched.size())
		if month == OPINION_MONTHS:
			overall_12 = tns.overall_approval_pct - cns.overall_approval_pct

	var visible: bool = absf(overall_12) > PollNoise.NOISE_MAX_PCT
	print("%-8.3f %7d %+9.2f %+9.2f %+9.2f %+9.2f   %s" % [
		offset, touched.size(), bloc_at[1], bloc_at[3], bloc_at[12], overall_12,
		"visible" if visible else "LOST IN NOISE",
	])


## The real monthly chain, in main.gd's order. Elections included: a twelve-month
## run from 2026 reaches none of the scheduled ones, but leaving it out would
## make this a different simulation from the one the game runs.
func _tick(state, loader, i: int) -> void:
	var month: int = (i + 1) % 12 + 1
	var year: int = START_YEAR + (i + 1) / 12
	state.year = year
	state.month = month

	Economy.tick_month(state)
	Budget.tick_month(state)
	Opinion.tick_month(state)
	var entry := Budget.snapshot(state)
	entry.merge(Opinion.snapshot(state))
	state.append_history(entry)
	Discipline.tick_month(state, loader)
	Legislature.tick_month(state)
	Dissolution.tick_month(state)
	Diplomacy.tick_month(state, loader)
	Cabinet.tick_month(state, loader)
	Elections.tick_month(state, loader)
