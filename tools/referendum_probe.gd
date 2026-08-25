extends SceneTree

## Referendum probe: godot --headless --script res://tools/referendum_probe.gd
##
## V1.7c's named measurement. Six tables, and the first two run before either
## constant matters at all, because the popular vote SHIPS NO CONSTANT: it is
## Elections.vote_share() with two options over tables written at S5 and S6. What
## the probe has to establish is that the arithmetic is a live mechanic rather than
## a foregone conclusion, and only then what the two register constants should be.
##
##   (R1) THE ANCHOR AND THE LANDSCAPE -- and the KILL SWITCH. Where the status quo
##        sits, what each authored amendment scores per bloc, and the national
##        yes-share across a sweep of approval. Accepted only if at least one
##        amendment is WINNABLE at a reachable approval and at least one is
##        LOSABLE. If every referendum fails everywhere the escalation is declared
##        in src/sim/referendum_constants.gd and it is a STATUS_QUO_PULL, not a
##        raised INCUMBENT_SWING -- that constant is measured for the election and
##        raising it would re-baseline every election this project has ever run.
##
##   (R2) THE APPROVAL RULER. What ONE point of approval is worth in points of
##        yes-share. Every band below is written in this unit rather than in an
##        invented one -- docs/campaign-model.md's V1.7a correction, where clause
##        (i) was a number picked because it sounded like a margin and the table
##        never said whether it was the right ruler.
##
##   (R3) THE DELAY BAND. A referendum resolved the month it is called is an
##        instant vote wearing a countdown. Band (i): the median drift in yes-share
##        over N months, in a played run, must exceed R2's ruler -- the world must
##        move at least as much as one point of approval would. Band (ii): a
##        referendum called in the first playable term must resolve inside it, and
##        that term is 16 months. Tiebreaker: MAXIMIN SLACK over the feasible
##        region, V1.7a's, because the interior of a passing LIST is a statement
##        about the grid and V1.5b's finding is that a grid must never choose.
##
##   (R4) THE OFFSET BAND. What one result is worth in points of overall approval.
##        Two-sided: at least 1.0 point, so the country's answer is readable in
##        figures that print exactly; at most the +-3.0 poll floor, so a single
##        referendum is a rebuke rather than a run ended. Two-sided means the
##        MIDPOINT selects -- V1.5c's rule, and V1.5d's note that neither edge
##        governs when the response is a smooth crossing. Clause (ii) checks the
##        worst reachable STACK leaves BLOC_OFFSET_MAX slack, so the clamp is a
##        guard rail rather than the thing setting the number.
##
##   (R5) WITHDRAWAL DOMINANCE. Withdrawing charges exactly what losing charges and
##        sets the same cooldown, so holding the vote weakly dominates it by
##        construction. What the probe adds is that the dominance is STRICT
##        somewhere rather than vacuous: it needs P(win) > 0 in reachable play.
##
##   (R6) REACHABILITY, and it is V1.3f's error guarded against rather than
##        recorded. The verb has to be reachable in a PLAYED run -- not in a static
##        new-game table, and not in a run whose government has already been thrown
##        out. Counts calls and resolutions over fourteen years under a real budget.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Media = preload("res://src/sim/media.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Defence = preload("res://src/sim/defence.gd")
const Companies = preload("res://src/sim/companies.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const Demography = preload("res://src/sim/demography.gd")
const Society = preload("res://src/sim/society.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Elections = preload("res://src/sim/elections.gd")

const Referendum = preload("res://src/sim/referendum.gd")
const K = preload("res://src/sim/referendum_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const ElectionK = preload("res://src/sim/election_constants.gd")
const LegislatureK = preload("res://src/sim/legislature_constants.gd")

const PLAYER := "FRA"
const START_YEAR := 2026
const MONTHS := 168

## The first playable term. France's presidential election is May 2027 against a
## January 2026 start -- docs/electoral-systems.md -- so a referendum called on
## day one has this many months to resolve in.
const FIRST_TERM_MONTHS := 16

## Bands, fixed here BEFORE any sweep so the numbers can falsify the design rather
## than be fitted to it.
const OFFSET_BAND_MIN_PTS := 1.0
const OFFSET_BAND_MAX_PTS := 3.0

const DELAY_SWEEP := [1, 2, 3, 4, 6, 8, 10, 11, 12, 13, 14, 16, 18, 20, 24]
const OFFSET_SWEEP := [0.04, 0.06, 0.08, 0.10, 0.12, 0.15, 0.20, 0.25, 0.30]
const APPROVAL_SWEEP := [30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 65.0]
const PULL_SWEEP := [0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00, 1.05, 1.10]

## A budget a government can actually hold office under, so R6 measures a player
## who is still in power -- tools/balance_probe.gd's `managed`.
const MANAGED := {
	"tax_rates_pct": {"income": 0.5},
	"spending_pct_gdp": {"health": 0.2},
}


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	var reach := _reachable_approval(loader)
	var ruler := _landscape_table(loader, reach)
	_pull_table(loader, reach)
	var drift := _delay_table(loader, ruler)
	_offset_table(loader, drift)
	_reachability_table(loader)
	quit(0)


## The approval a French president can actually hold over fourteen years under a
## budget they can stay in office on. Measured FIRST, because every band below that
## mentions approval has to be written inside it -- table R1's first kill switch swept
## 30 to 65, cleared, and was measuring approvals no reachable government has.
func _reachable_approval(loader) -> Dictionary:
	var state = GameState.new_game(loader, PLAYER)
	Budget.commit(state, _pending(state.player(), MANAGED))
	var lo := 999.0
	var hi := -999.0
	for i in range(MONTHS):
		_tick(state, loader, i)
		var a: float = state.player().overall_approval_pct
		lo = minf(lo, a)
		hi = maxf(hi, a)
	print("")
	print("(R0) THE REACHABLE APPROVAL RANGE, under `managed`, over %d months" % MONTHS)
	print("  %.1f to %.1f -- every approval band below is written INSIDE this" % [lo, hi])
	return {"lo": lo, "hi": hi}


# --- (R1) and (R2) --------------------------------------------------------------

## Returns the approval ruler: points of yes-share per point of approval.
func _landscape_table(loader, reach: Dictionary) -> float:
	var anchor := Referendum.status_quo_position()
	print("")
	print("(R1) THE ANCHOR AND THE LANDSCAPE")
	print("  status quo, size-weighted mean of BLOC_IDEAL: economic %+.3f  social %+.3f" % [
		anchor["economic"], anchor["social"]
	])
	print("  DERIVED, not authored -- no constant decides where NO sits.")

	var state = GameState.new_game(loader, PLAYER)
	var ns = state.player()

	var amendments := []
	for law in loader.laws:
		if law.constitutional:
			amendments.append(law)

	print("")
	print("  per-bloc yes share at neutral approval (%.1f), by amendment:" % OpinionK.APPROVAL_NEUTRAL)
	var header := "    %-34s" % "amendment"
	for bloc in OpinionK.BLOC_KEYS:
		header += " %10s" % bloc
	header += " %10s" % "NATIONAL"
	print(header)

	_set_approval(ns, OpinionK.APPROVAL_NEUTRAL)
	for law in amendments:
		var row := "    %-34s" % law.id
		for bloc in OpinionK.BLOC_KEYS:
			row += " %10.3f" % Referendum.bloc_yes(ns, bloc, law.position)
		row += " %10.3f" % Referendum.yes_share(ns, law.position)
		print(row)

	print("")
	print("  national yes share against approval:")
	var head2 := "    %-34s" % "amendment"
	for a in APPROVAL_SWEEP:
		head2 += " %8.0f" % a
	print(head2)

	var winnable := 0
	var losable := 0
	for law in amendments:
		var row := "    %-34s" % law.id
		var any_win := false
		var any_lose := false
		for a in APPROVAL_SWEEP:
			_set_approval(ns, a)
			row += " %8.3f" % Referendum.yes_share(ns, law.position)
		# ...and the kill switch is read only INSIDE the reachable range, which is the
		# correction R0 exists to make. Read over the whole sweep it clears on
		# approvals no government in this game can hold.
		for a in [reach["lo"], (float(reach["lo"]) + float(reach["hi"])) / 2.0, reach["hi"]]:
			_set_approval(ns, float(a))
			if Referendum.yes_share(ns, law.position) > K.REFERENDUM_MAJORITY:
				any_win = true
			else:
				any_lose = true
		print(row)
		if any_win:
			winnable += 1
		if any_lose:
			losable += 1

	print("")
	print("  KILL SWITCH, read inside the reachable range [%.1f, %.1f]:" % [reach["lo"], reach["hi"]])
	print("  %d of %d amendments winnable, %d losable -- %s" % [
		winnable, amendments.size(), losable,
		"CLEARED" if winnable > 0 and losable > 0 else "FIRED, escalate to STATUS_QUO_PULL"
	])

	# (R2). Measured on the amendment nearest the 50 % line, because a ruler read on
	# a foregone conclusion measures the tails of a logistic rather than the slope
	# that decides anything.
	var pivot = amendments[0]
	var best := 1.0
	for law in amendments:
		_set_approval(ns, OpinionK.APPROVAL_NEUTRAL)
		var d: float = absf(Referendum.yes_share(ns, law.position) - K.REFERENDUM_MAJORITY)
		if d < best:
			best = d
			pivot = law

	_set_approval(ns, OpinionK.APPROVAL_NEUTRAL)
	var at_50 := Referendum.yes_share(ns, pivot.position)
	_set_approval(ns, OpinionK.APPROVAL_NEUTRAL + 1.0)
	var at_51 := Referendum.yes_share(ns, pivot.position)
	var ruler: float = absf(at_51 - at_50) * 100.0

	print("")
	print("(R2) THE APPROVAL RULER, read on the pivot amendment '%s'" % pivot.id)
	print("  one point of approval is worth %.4f points of yes share" % ruler)
	return ruler


func _set_approval(ns, value: float) -> void:
	for bloc in OpinionK.BLOC_KEYS:
		ns.bloc_approval[bloc] = value


# --- (R2b) ----------------------------------------------------------------------

## Sweeps STATUS_QUO_PULL by EMULATION rather than by rescaling from the shipped
## constant, because a probe cannot change a `const` at runtime and
## docs/inflation-model.md's V1.6b correction is that a table rescaled from the shipped
## value MOVES when the shipped value moves. Everything here recomputes from scratch.
func _pull_table(loader, reach: Dictionary) -> void:
	var state = GameState.new_game(loader, PLAYER)
	var ns = state.player()

	# The reachable amendment: the one this nation's own assembly will actually send to
	# the country, which is a different question from which one polls best.
	var party_list: Array = loader.parties.get(PLAYER, [])
	var law = null
	for candidate in Legislature.available(ns, loader.laws):
		if not Legislature.can_put_to_referendum(ns, candidate):
			continue
		var r := Legislature.resolve_vote(ns, party_list, candidate, true)
		if bool(r["passed"]):
			law = candidate
			break

	print("")
	print("(R2b) STATUS_QUO_PULL -- the declared escalation, fired by R0 against R1")
	if law == null:
		print("  NO amendment clears this assembly on route B -- the verb is unreachable and")
		print("  no value of the pull can rescue it. The fix would be CONTENT, not this constant.")
		return
	print("  measured on '%s', the one amendment FRA's assembly sends to the country" % law.id)
	print("  band: the crossover approval must lie strictly inside [%.1f, %.1f]" % [reach["lo"], reach["hi"]])
	print("    %8s %14s %10s" % ["pull", "crossover", "inside?"])

	var mid: float = (float(reach["lo"]) + float(reach["hi"])) / 2.0
	var best := -1.0
	var best_gap := 999.0
	for pull in PULL_SWEEP:
		var cross := _crossover(ns, law.position, float(pull))
		var inside: bool = cross > float(reach["lo"]) and cross < float(reach["hi"])
		print("    %8.2f %14s %10s" % [
			pull, "never" if cross < 0.0 else "%.2f" % cross, "yes" if inside else "no"
		])
		if inside and absf(cross - mid) < best_gap:
			best_gap = absf(cross - mid)
			best = float(pull)
	if best < 0.0:
		print("  NO CANDIDATE PUTS THE CROSSOVER INSIDE THE RANGE.")
		return
	print("  NEAREST THE MIDDLE (%.1f) selects STATUS_QUO_PULL = %.2f; shipped %.2f" % [
		mid, best, K.STATUS_QUO_PULL
	])
	if best == float(PULL_SWEEP[0]) or best == float(PULL_SWEEP[PULL_SWEEP.size() - 1]):
		print("  NOTE: the answer sits at an endpoint of the swept range -- V1.5b's suspect.")


## The approval at which this proposal crosses REFERENDUM_MAJORITY under a candidate
## pull; -1.0 if it never does. Bisection, so the answer does not come off a grid.
func _crossover(ns, position: Dictionary, pull: float) -> float:
	if _emulated_share(ns, position, pull, 100.0) <= K.REFERENDUM_MAJORITY:
		return -1.0
	if _emulated_share(ns, position, pull, 0.0) > K.REFERENDUM_MAJORITY:
		return 0.0
	var lo := 0.0
	var hi := 100.0
	for _i in range(40):
		var mid := (lo + hi) / 2.0
		if _emulated_share(ns, position, pull, mid) > K.REFERENDUM_MAJORITY:
			hi = mid
		else:
			lo = mid
	return (lo + hi) / 2.0


## Referendum.yes_share() recomputed from scratch at a candidate pull and a flat
## approval. Duplicated deliberately: calling the shipped function would read the
## shipped constant, which is the thing being swept.
func _emulated_share(ns, position: Dictionary, pull: float, approval: float) -> float:
	var anchor := Referendum.status_quo_position()
	var total := 0.0
	var weight_total := 0.0
	for bloc in OpinionK.BLOC_KEYS:
		var ideal: Dictionary = ElectionK.BLOC_IDEAL[bloc]
		var yes_w := _affinity(position, ideal)
		var no_w := _affinity(anchor, ideal) * pull
		var swing: float = clampf(
			(approval - OpinionK.APPROVAL_NEUTRAL) / OpinionK.APPROVAL_NEUTRAL, -1.0, 1.0
		)
		yes_w *= (1.0 + ElectionK.INCUMBENT_SWING * swing)
		var w: float = float(OpinionK.BLOC_SIZE[bloc]) * float(ElectionK.BLOC_TURNOUT[bloc])
		weight_total += w
		if yes_w + no_w > 0.0:
			total += w * (yes_w / (yes_w + no_w))
	return 0.0 if weight_total <= 0.0 else total / weight_total


func _affinity(a: Dictionary, b: Dictionary) -> float:
	var de: float = float(a.get("economic", 0.0)) - float(b["economic"])
	var ds: float = float(a.get("social", 0.0)) - float(b["social"])
	return exp(-pow(sqrt(de * de + ds * ds) / ElectionK.AFFINITY_SIGMA, 2.0))


# --- (R3) -----------------------------------------------------------------------

## Returns delay -> median absolute drift in points of yes-share.
func _delay_table(loader, ruler: float) -> Dictionary:
	var state = GameState.new_game(loader, PLAYER)
	var ns = state.player()
	Budget.commit(state, _pending(ns, MANAGED))

	# One amendment, sampled every month of a played run. Which one does not matter
	# for a DRIFT measurement: what is being measured is how far the world moves,
	# and every question moves with the same approval.
	var law = null
	for candidate in loader.laws:
		if candidate.constitutional:
			law = candidate
			break

	var series: Array = []
	for i in range(MONTHS):
		_tick(state, loader, i)
		series.append(Referendum.yes_share(state.player(), law.position) * 100.0)

	print("")
	print("(R3) THE DELAY BAND")
	print("  band (i)  median |drift| over N months must exceed the R2 ruler, %.4f pts" % ruler)
	print("  band (ii) N must be <= %d, the first playable term" % FIRST_TERM_MONTHS)
	print("    %6s %12s %12s %8s %8s" % ["N", "median drift", "max drift", "(i)", "(ii)"])

	var drift := {}
	var passing: Array = []
	for n in DELAY_SWEEP:
		var deltas: Array = []
		for t in range(series.size() - n):
			deltas.append(absf(float(series[t + n]) - float(series[t])))
		deltas.sort()
		var median: float = 0.0 if deltas.is_empty() else float(deltas[deltas.size() / 2])
		var worst: float = 0.0 if deltas.is_empty() else float(deltas[deltas.size() - 1])
		drift[n] = median
		var ok_i := median > ruler
		var ok_ii: bool = n <= FIRST_TERM_MONTHS
		if ok_i and ok_ii:
			passing.append(n)
		print("    %6d %12.4f %12.4f %8s %8s" % [
			n, median, worst, "pass" if ok_i else "FAIL", "pass" if ok_ii else "FAIL"
		])

	if passing.is_empty():
		print("  NO CANDIDATE PASSES -- the delay buys nothing measurable and the register is a costume.")
		return drift

	# Maximin slack: the candidate furthest from whichever band edge it is nearest,
	# both edges expressed as a fraction of their own span.
	var best: int = passing[0]
	var best_slack := -1.0
	for n in passing:
		var slack_i: float = (float(drift[n]) - ruler) / maxf(ruler, 0.0001)
		var slack_ii: float = float(FIRST_TERM_MONTHS - n) / float(FIRST_TERM_MONTHS)
		var slack: float = minf(slack_i, slack_ii)
		if slack > best_slack:
			best_slack = slack
			best = n
	print("  passing: %s" % [passing])
	print("  MAXIMIN SLACK selects REFERENDUM_DELAY_MONTHS = %d (slack %.3f); shipped %d" % [
		best, best_slack, K.REFERENDUM_DELAY_MONTHS
	])
	if passing[0] == DELAY_SWEEP[0] or passing[passing.size() - 1] == DELAY_SWEEP[DELAY_SWEEP.size() - 1]:
		print("  NOTE: the passing set touches an endpoint of the swept range -- V1.5b's suspect, not a result.")
	return drift


# --- (R4) -----------------------------------------------------------------------

func _offset_table(loader, _drift: Dictionary) -> void:
	print("")
	print("(R4) THE OFFSET BAND")
	print("  band (i) one result must move overall approval by [%.1f, %.1f] points" % [
		OFFSET_BAND_MIN_PTS, OFFSET_BAND_MAX_PTS
	])
	print("  band (ii) the worst reachable stack must leave BLOC_OFFSET_MAX = %.2f slack" % LegislatureK.BLOC_OFFSET_MAX)

	# How many results a fourteen-year run can reach: each costs the delay plus the
	# loser's cooldown, and both electoral acts author 24.
	var per_result: int = K.REFERENDUM_DELAY_MONTHS + 24
	var reachable: int = int(MONTHS / maxi(per_result, 1))
	print("  a fourteen-year run reaches at most %d results (%d months each)" % [reachable, per_result])
	print("    %8s %14s %14s %8s %8s" % ["offset", "approval move", "worst stack", "(i)", "(ii)"])

	var passing: Array = []
	for offset in OFFSET_SWEEP:
		var state = GameState.new_game(loader, PLAYER)
		var ns = state.player()
		var before: float = ns.overall_approval_pct
		for bloc in OpinionK.BLOC_KEYS:
			ns.bloc_offset[bloc] = clampf(
				float(ns.bloc_offset.get(bloc, 0.0)) - float(offset),
				LegislatureK.BLOC_OFFSET_MIN, LegislatureK.BLOC_OFFSET_MAX
			)
		Opinion.tick_month(state)
		var move: float = absf(ns.overall_approval_pct - before)
		var stack: float = float(offset) * float(reachable)
		var ok_i := move >= OFFSET_BAND_MIN_PTS and move <= OFFSET_BAND_MAX_PTS
		var ok_ii: bool = stack < LegislatureK.BLOC_OFFSET_MAX
		if ok_i and ok_ii:
			passing.append(offset)
		print("    %8.3f %14.4f %14.4f %8s %8s" % [
			offset, move, stack, "pass" if ok_i else "FAIL", "pass" if ok_ii else "FAIL"
		])

	if passing.is_empty():
		print("  NO CANDIDATE PASSES.")
		return
	print("  passing on the grid: %s" % [passing])

	# CLOSED FORM, and the grid is only there to show it is one. The approval
	# response is exactly linear in the offset -- every row above is move = slope x
	# offset to four decimals -- so the feasible interval is solved rather than read
	# off a swept row. docs/sector-model.md's V1.6e correction: two of three
	# constants there were closed form and the first run still reported the widest
	# passing GRID ROW as the interval.
	var slope: float = _approval_slope(loader)
	var lo: float = OFFSET_BAND_MIN_PTS / slope
	var hi_i: float = OFFSET_BAND_MAX_PTS / slope
	var hi_ii: float = LegislatureK.BLOC_OFFSET_MAX / float(maxi(reachable, 1))
	var hi: float = minf(hi_i, hi_ii)
	print("  slope: %.4f points of approval per point of offset" % slope)
	print("  band (i) gives [%.4f, %.4f]; band (ii) gives < %.4f" % [lo, hi_i, hi_ii])
	print("  feasible [%.4f, %.4f], and it is band (%s) that binds above" % [
		lo, hi, "ii" if hi_ii < hi_i else "i"
	])
	print("  MIDPOINT selects REFERENDUM_RESULT_OFFSET = %.4f; shipped %.4f" % [
		(lo + hi) / 2.0, K.REFERENDUM_RESULT_OFFSET
	])


## Points of overall approval per point of bloc_offset. Measured rather than
## assumed, at two offsets, and the two must agree or the response is not linear
## and the closed form above is not available.
func _approval_slope(loader) -> float:
	var a := _approval_move(loader, 0.05)
	var b := _approval_move(loader, 0.20)
	var slope_a: float = a / 0.05
	var slope_b: float = b / 0.20
	if absf(slope_a - slope_b) > 0.001:
		print("  WARNING: the response is NOT linear (%.4f vs %.4f) -- the closed form does not hold" % [slope_a, slope_b])
	return slope_a


func _approval_move(loader, offset: float) -> float:
	var state = GameState.new_game(loader, PLAYER)
	var ns = state.player()
	var before: float = ns.overall_approval_pct
	for bloc in OpinionK.BLOC_KEYS:
		ns.bloc_offset[bloc] = clampf(
			float(ns.bloc_offset.get(bloc, 0.0)) - offset,
			LegislatureK.BLOC_OFFSET_MIN, LegislatureK.BLOC_OFFSET_MAX
		)
	Opinion.tick_month(state)
	return absf(ns.overall_approval_pct - before)


# --- (R6) -----------------------------------------------------------------------

func _reachability_table(loader) -> void:
	print("")
	print("(R5) WITHDRAWAL DOMINANCE and (R6) REACHABILITY")

	var state = GameState.new_game(loader, PLAYER)
	var ns = state.player()
	Budget.commit(state, _pending(ns, MANAGED))

	var called := 0
	var carried := 0
	var lost := 0
	var offered_months := 0
	var rational_months := 0
	var approval_min := 999.0
	var approval_max := -999.0

	# A RATIONAL player, not a greedy one. The first version called a referendum
	# every month it was legal, lost 24 of 25 and drove its own approval down with
	# every loss -- which measures a player nobody is rather than whether the verb
	# can be won. V1.3f's error in its other costume: the state measured was
	# reachable, and the BEHAVIOUR was not.
	for i in range(MONTHS):
		var player = state.player()
		approval_min = minf(approval_min, player.overall_approval_pct)
		approval_max = maxf(approval_max, player.overall_approval_pct)
		if not Referendum.is_pending(player):
			var choice = _first_referendable(loader, player)
			if choice != null:
				offered_months += 1
				if Referendum.yes_share(player, choice.position) > K.REFERENDUM_MAJORITY:
					rational_months += 1
					var result := Legislature.propose(state, loader, choice, false, true)
					if bool(result.get("referendum_called", false)):
						called += 1
		var before_pending := Referendum.is_pending(state.player())
		_tick(state, loader, i)
		var after = state.player()
		if before_pending and not Referendum.is_pending(after):
			if bool(after.last_referendum_result.get("passed", false)):
				carried += 1
			else:
				lost += 1

	print("  overall approval over the run: %.1f to %.1f" % [approval_min, approval_max])
	print("  months a referendum was legally offerable: %d of %d" % [offered_months, MONTHS])
	print("  months calling one was RATIONAL (yes share already over the bar): %d" % rational_months)
	print("  called %d, carried %d, lost %d" % [called, carried, lost])
	if called == 0:
		print("  THE VERB IS UNREACHABLE IN A PLAYED RUN -- V1.3f's error, and it fired.")
	var wins := carried
	print("  withdrawal is a GUARANTEED loss at the same price, so holding weakly dominates;")
	print("  the dominance is STRICT wherever P(win) > 0, which is %s here." % [
		"true" if wins > 0 else "FALSE -- then the verb is dominated and the price is wrong"
	])


# --- harness --------------------------------------------------------------------

func _first_referendable(loader, ns):
	for law in Legislature.available(ns, loader.laws):
		if Legislature.can_put_to_referendum(ns, law):
			return law
	return null


func _pending(ns, delta: Dictionary) -> Dictionary:
	var out := {}
	for channel in delta:
		var merged := {}
		var live: Dictionary = ns.tax_rates_pct if channel == "tax_rates_pct" else ns.spending_pct_gdp
		for key in live:
			merged[key] = live[key]
		for key in delta[channel]:
			merged[key] = float(merged.get(key, 0.0)) + float(delta[channel][key])
		out[channel] = merged
	return out


## tools/balance_probe.gd's order, which is src/ui/main.gd's.
func _tick(state, loader, i: int) -> void:
	state.month = (i + 1) % 12 + 1
	state.year = START_YEAR + (i + 1) / 12

	Economy.tick_month(state)
	Budget.tick_month(state)
	Bloc.tick_month(state, loader)
	Inflation.tick_month(state)
	Media.tick_month(state, loader)
	Opinion.tick_month(state)
	var entry := Budget.snapshot(state)
	entry.merge(Opinion.snapshot(state))
	state.append_history(entry)
	Discipline.tick_month(state, loader)
	Legislature.tick_month(state, loader)
	Dissolution.tick_month(state)
	Diplomacy.tick_month(state, loader)
	Defence.tick_month(state)
	Companies.tick_month(state, loader)
	Investment.tick_month(state)
	Projects.tick_month(state, loader)
	Campaign.tick_month(state, loader)
	Pledges.tick_month(state, loader)
	Demography.tick_month(state)
	Society.tick_month(state)
	Unrest.tick_month(state)
	Cabinet.tick_month(state, loader)
	Elections.tick_month(state, loader)
