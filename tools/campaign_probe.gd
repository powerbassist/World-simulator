extends SceneTree

## V1.7a's headless sweep. CAMPAIGN_WINDOW_MONTHS -- the one tuned constant in
## src/sim/campaign_constants.gd -- and every number in data/campaign-actions/ is set
## from a table below rather than guessed and defended afterwards.
##
## Run: godot --headless --script res://tools/campaign_probe.gd
##
## *** THE BANDS AND THE TIEBREAKERS ARE BOTH PRE-COMMITTED. *** Nine corrections to
## that discipline are inherited rather than rediscovered:
##
##   V1.4c  fix the TIEBREAKER as well as the band.
##   V1.5a  a tiebreaker must strictly ORDER the survivors; a clause that passes at
##          every candidate is a BOUND, not a selector.
##   V1.5b  its answer must not MOVE when the candidate range is widened. A value
##          sitting at an endpoint of the swept range is a suspect, not a result.
##   V1.5c  a nearest-to-X tiebreaker is only as good as the grid's RESOLUTION.
##   V1.5d  when the model edge is a smooth CROSSING rather than a plateau, neither
##          edge selects and the interior governs.
##   V1.6a  where something outside the model measures the same quantity, prefer a FIT
##          to a band: a band edge moves under widening, a fit converges.
##   V1.6c  check each term against the MODEL'S OWN BOUNDARY before the band.
##   V1.6d  a band that passes at every candidate with the identical measurement is
##          measuring a CLAMP. Say so and replace it.
##   V1.6e  where an edge is closed form, SOLVE IT; the grid is a legibility column.
##
## *** THE CANDIDATE IS EMULATED EXACTLY AND NOT RESCALED, and here that costs
## nothing. *** V1.6b's correction was that a probe cannot change a `const` at runtime,
## so a table that rescales the shipped value has the shipped value inside its own
## answer. CAMPAIGN_WINDOW_MONTHS gates exactly one thing -- how many months before the
## vote an effort may be put in the field -- so a run that starts efforts `d` months
## out and accrues for `d` months IS the model under every window of `d` or more. The
## sweep is therefore over `d`, and the constant is read off the table rather than
## displaced into it. _force_start() is the one place that goes round the verb, and it
## goes round only Campaign.available()'s window check.
##
## ============================================================================
## THE BOUNDARY CHECKS, SETTLED BEFORE ANY BAND WAS WRITTEN
## ============================================================================
##
##   (B1) IS THIS V1.5d's MESSAGING MACHINE UNDER ANOTHER NAME? NO, and it must not be.
##        docs/media-model.md section 2 CUT government messaging because damping hostile
##        framing is press_freedom's positive direction with a different label -- one
##        accumulator, two writers. Table (a) checks that a full campaign leaves
##        ns.framing_gain and ns.press_freedom bit-identical, so the refusal is a
##        measurement rather than a claim about which files were edited.
##
##   (B2) IS TURNOUT REALLY UNWRITTEN? Table (b) checks the property the whole session
##        rests on: with no campaign, Campaign.turnout_of() returns
##        election_constants.BLOC_TURNOUT bit-for-bit, so every nation that does not
##        campaign runs the model it ran before.
##
##   (B3) IS LATE STRICTLY BETTER? The first design billed a one-off, under which
##        acting late dominated. Table (d) prints the move and the price against `d`
##        and checks that BOTH rise -- if the move plateaus while the price keeps
##        rising, late dominates again and the finding is that the accumulator is
##        saturating, which is a clamp setting the number.
##
##   (B4) IS THE CLAMP SETTING THE NUMBER? MOBILISATION_MAX is a declared guard rail.
##        Table (f) reports it against the worst reachable stack. If the peak sits ON
##        it, the content is not the lever -- docs/economy-model.md's IMPULSE_MAX
##        finding, caught seven times now.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Media = preload("res://src/sim/media.gd")
const Demography = preload("res://src/sim/demography.gd")
const Society = preload("res://src/sim/society.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Defence = preload("res://src/sim/defence.gd")
const Companies = preload("res://src/sim/companies.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Elections = preload("res://src/sim/elections.gd")
const ElectionK = preload("res://src/sim/election_constants.gd")
const K = preload("res://src/sim/campaign_constants.gd")

const PLAYER := "FRA"
const START_YEAR := 2026

## One presidential term, in months. The (iii) clause below is written against it.
const TERM_MONTHS := 60

## V1.6d's measured tax swing and V1.6e's / V1.6f's shipped costs, quoted rather than
## recomputed: each is a published measurement of another session's model, and
## recomputing one here would be a number with two writers.
const TAX_SWING_PTS := 4.62
const INVESTMENT_COST_PTS := 0.8161
const PROJECT_STACK_PTS := 0.36

const POLL_FLOOR_PTS := 3.0

## (i), (ii) and (iii): the pre-committed edges, in one place so the tables cannot
## quietly disagree with the header.
##
## (i)   WORTH, AND IT IS MEASURED RATHER THAN INVENTED. The first version of this
##       clause was a bare "at least 0.50 points of vote share", picked because it
##       sounded like a margin -- and the probe refused every candidate against it
##       without ever saying whether 0.50 was the right ruler. It was not. The honest
##       anchor is what the model ALREADY prices vote share in: approval. A full
##       run-up must be worth
##
##         at least  what ONE point of approval is worth   -- below that, governing
##                                                            swamps it and it is
##                                                            decorative;
##         at most   what POLL_FLOOR_PTS is worth          -- above that a campaign
##                                                            substitutes for the
##                                                            record, and a president
##                                                            could buy back a term
##                                                            they had lost.
##
##       Both edges are measured in table (c4) rather than declared, which is V1.6a's
##       rule: where something outside this model measures the same quantity, prefer an
##       anchor to a band. POLL_FLOOR_PTS is the upper edge because a swing smaller than
##       the published polls can resolve is exactly the swing a campaign may own -- the
##       player has spent the term reading blurred figures, and the campaign is what
##       decides the race those figures could not call.
## (ii)  AFFORDABILITY. The peak the campaign adds to deficit_pct_gdp must fit what
##       V1.6d, V1.6e and V1.6f left of opinion_constants.DEFICIT_SCALE_PP.
## (iii) PROPORTION. The run-up may not exceed a fifth of a presidential term. Past
##       that, "campaigning" is a second name for governing and the timing decision
##       the lever exists to pose stops being one.
const WINDOW_MAX_MONTHS := 12

## Legibility column, never a selector. The window is read off where the bands cross.
const D_CANDIDATES := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16]

var _loader

## Measured in table (c4) before any sweep reads them.
var _move_min := 0.0
var _move_max := 0.0
var _gap_min := 0.0
var _gap_max := 0.0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [_loader.errors])
		quit(1)
		return

	print("=== V1.7a campaign probe ===")
	print("shipped: CAMPAIGN_WINDOW_MONTHS %d  MOBILISATION_MAX %.2f  cost ceiling %.1f EUR per 1 000 a month  rate ceiling %.2f" % [
		K.CAMPAIGN_WINDOW_MONTHS, K.MOBILISATION_MAX,
		K.MAX_CAMPAIGN_COST_EUR_PER_K_POP_MONTH, K.MAX_MOBILISATION_PER_MONTH,
	])
	print("headroom: DEFICIT_SCALE_PP %.4f - taxes %.4f - investment %.4f - projects %.4f = %.4f" % [
		OpinionK.DEFICIT_SCALE_PP, TAX_SWING_PTS, INVESTMENT_COST_PTS, PROJECT_STACK_PTS, _headroom(),
	])
	_table_a_no_framing()
	_table_b_bit_identity()
	_table_c_room()
	_table_c2_ceiling()
	_table_c3_electorate()
	_table_c4_anchor()
	_table_d_window()
	_table_e_dominance()
	_table_f_guard_rail()
	_table_g_kill_switch()
	_table_h_share_is_not_winning()
	quit(0)


## What V1.6d's, V1.6e's and V1.6f's lines left of the deficit issue's whole span.
func _headroom() -> float:
	# THE FIRST VERSION DIVIDED THE TAX SWING BY 100 and reported 4.7777 points of
	# headroom where there are 0.2039. Every quantity on this line is already in points
	# of GDP of deficit -- docs/projects-model.md quotes the same three -- so the
	# conversion was inventing room the budget does not have, and table (d)'s clause
	# (ii) passed at every candidate because of it. A band that passes everywhere is a
	# BOUND, V1.5a; here it was not even that, it was an arithmetic error wearing one.
	return OpinionK.DEFICIT_SCALE_PP - TAX_SWING_PTS - INVESTMENT_COST_PTS - PROJECT_STACK_PTS


# --- (a) B1: the machine that must NOT move -------------------------------------------

## docs/media-model.md's cut, checked rather than claimed. A full run-up must leave the
## framing landscape and the press-freedom stance exactly where it found them.
func _table_a_no_framing() -> void:
	print("\n(a) B1 -- a campaign must not touch V1.5d's framing machine")
	var control := _run(0, [])
	var campaign := _run(K.CAMPAIGN_WINDOW_MONTHS, ["broadcast", "digital_push"])

	var worst := 0.0
	for bloc in OpinionK.BLOC_KEYS:
		worst = maxf(worst, absf(
			float(campaign["framing"].get(bloc, 0.0)) - float(control["framing"].get(bloc, 0.0))
		))
	print("  max |framing_gain| difference over six blocs: %.12f" % worst)
	print("  press_freedom control %.12f  campaign %.12f" % [control["press_freedom"], campaign["press_freedom"]])
	print("  VERDICT: %s" % ("PASS -- untouched" if worst == 0.0 and control["press_freedom"] == campaign["press_freedom"] else "FAIL -- the campaign reached the framing machine"))


# --- (b) B2: turnout is unwritten until it is written ----------------------------------

func _table_b_bit_identity() -> void:
	print("\n(b) B2 -- with no campaign, turnout_of() IS election_constants.BLOC_TURNOUT")
	var state = _new_state()
	var ns = state.player()
	var ok := true
	for bloc in OpinionK.BLOC_KEYS:
		var got: float = Campaign.turnout_of(ns, bloc)
		var want: float = float(ElectionK.BLOC_TURNOUT[bloc])
		if got != want:
			ok = false
		print("  %-11s authored %.6f  read %.6f  %s" % [bloc, want, got, "exact" if got == want else "DIFFERS"])
	print("  VERDICT: %s" % ("PASS -- bit-identical" if ok else "FAIL"))


# --- (c) how much room each bloc has ---------------------------------------------------

## The property nobody authored: the same log-odds shift is worth more to a bloc with
## more room. Printed before any band, because it is what decides which efforts are
## worth authoring at all.
func _table_c_room() -> void:
	print("\n(c) room -- what one unit of mobilisation is worth, by bloc")
	print("  %-11s %8s %8s %8s %8s" % ["bloc", "base", "+0.20", "+0.40", "+0.60"])
	var state = _new_state()
	var ns = state.player()
	for bloc in OpinionK.BLOC_KEYS:
		var row := "  %-11s %8.3f" % [bloc, float(ElectionK.BLOC_TURNOUT[bloc])]
		for shift in [0.20, 0.40, 0.60]:
			ns.campaign_mobilisation[bloc] = shift
			row += " %8.3f" % Campaign.turnout_of(ns, bloc)
		ns.campaign_mobilisation.erase(bloc)
		print(row)


# --- (c2) THE FEASIBILITY ARITHMETIC, COMPUTED BEFORE ANY SWEEP -----------------------

## docs/media-model.md section 5's discipline, and the first run of this probe is what
## proved it was needed: table (d) swept a window against a band without ever asking
## whether the band was REACHABLE, and every row failed by the same margin -- which is
## the signature of an arithmetic impossibility rather than a mis-tuned constant.
##
## PERFECT TARGETING. Every bloc is pushed to +cap if it is better than average for the
## incumbent and to -cap if it is worse, which is the best any content could ever do at
## that cap. If the move at MOBILISATION_MAX is under (i), no ladder and no window can
## reach it and the finding is structural.
func _table_c2_ceiling() -> void:
	print("
(c2) the arithmetic ceiling -- PERFECT targeting, before any sweep")
	var state = _new_state()
	var ns = state.player()
	var party_list: Array = _loader.parties.get(PLAYER, [])
	var base := Elections.vote_share(ns, party_list, ns.incumbent_party_id)
	var base_share: float = float(base.get(ns.incumbent_party_id, 0.0))

	var sign := _helpful_signs(ns, party_list)
	print("  helpful blocs: %s" % str(sign))
	print("  %8s %10s %10s" % ["cap", "share", "move"])
	for cap in [0.20, 0.40, 0.60, 1.00, 1.50, 2.00, 3.00]:
		for bloc in OpinionK.BLOC_KEYS:
			ns.campaign_mobilisation[bloc] = cap * float(sign[bloc])
		var got := Elections.vote_share(ns, party_list, ns.incumbent_party_id)
		var move: float = (float(got.get(ns.incumbent_party_id, 0.0)) - base_share) * 100.0
		print("  %8.2f %10.4f %10.4f%s" % [
			cap, float(got.get(ns.incumbent_party_id, 0.0)), move,
			"   <- clears (i)" if move >= _move_min else "",
		])
	ns.campaign_mobilisation = {}


## +1 where mobilising a bloc helps the incumbent and -1 where it hurts. Derived from
## the model rather than authored: a bloc helps exactly when the incumbent's share
## INSIDE it is above their national share, which is what reweighting the mix rewards.
func _helpful_signs(ns, party_list: Array) -> Dictionary:
	var base := Elections.vote_share(ns, party_list, ns.incumbent_party_id)
	var base_share: float = float(base.get(ns.incumbent_party_id, 0.0))
	var out := {}
	for bloc in OpinionK.BLOC_KEYS:
		ns.campaign_mobilisation = {bloc: 0.30}
		var got := Elections.vote_share(ns, party_list, ns.incumbent_party_id)
		out[bloc] = 1.0 if float(got.get(ns.incumbent_party_id, 0.0)) >= base_share else -1.0
	ns.campaign_mobilisation = {}
	return out


# --- (c3) whose electorate is it -------------------------------------------------------

## What a president is actually looking at when they choose an effort: how much of each
## bloc is theirs, against how much of the country is. The sign of every entry in (c2)
## falls straight out of this column and nothing authored it.
func _table_c3_electorate() -> void:
	print("
(c3) the incumbent's electorate, bloc by bloc")
	var state = _new_state()
	var ns = state.player()
	var party_list: Array = _loader.parties.get(PLAYER, [])
	var base := Elections.vote_share(ns, party_list, ns.incumbent_party_id)
	var national: float = float(base.get(ns.incumbent_party_id, 0.0))
	print("  incumbent %s, national share %.4f" % [ns.incumbent_party_id, national])
	print("  %-11s %8s %8s %10s %10s" % ["bloc", "size", "turnout", "move+0.30", "verdict"])
	for bloc in OpinionK.BLOC_KEYS:
		ns.campaign_mobilisation = {bloc: 0.30}
		var got := Elections.vote_share(ns, party_list, ns.incumbent_party_id)
		var move: float = (float(got.get(ns.incumbent_party_id, 0.0)) - national) * 100.0
		print("  %-11s %8.2f %8.2f %10.4f %10s" % [
			bloc, float(OpinionK.BLOC_SIZE[bloc]), float(ElectionK.BLOC_TURNOUT[bloc]),
			move, "theirs" if move >= 0.0 else "not theirs",
		])
	ns.campaign_mobilisation = {}


# --- (c4) THE ANCHOR -----------------------------------------------------------------

## What a point of approval is worth in vote share, so clause (i) has a ruler the model
## already owns instead of one this file invented.
##
## Displaces every bloc's approval by a fixed number of points and reads the vote share
## the same way the election does. Approval is the only other thing that moves
## Elections.vote_share() at all -- through the `pull` term -- so it is the only
## available comparison, and that is what makes it the right one rather than merely a
## convenient one.
func _table_c4_anchor() -> void:
	print("\n(c4) the anchor -- what vote share is worth, in points of approval")
	var state = _new_state()
	var ns = state.player()
	var party_list: Array = _loader.parties.get(PLAYER, [])
	var base := Elections.vote_share(ns, party_list, ns.incumbent_party_id)
	var base_share: float = float(base.get(ns.incumbent_party_id, 0.0))

	var base_gap: float = _gap_of(base, ns.incumbent_party_id)

	# BOTH OBJECTIVES, because table (h) shows they disagree. The share edge is what
	# clause (i) is written on and the gap edge is what actually decides the election, so
	# an anchor measured on one alone would leave the other unbanded -- which is
	# docs/tax-model.md's "measuring the wrong state" with the quantity swapped for the
	# objective.
	var truth: Dictionary = ns.bloc_approval.duplicate()
	print("  %8s %10s %10s %10s" % ["approval", "share", "d-share", "d-gap"])
	var moves := {}
	var gaps := {}
	for pts in [1.0, 2.0, POLL_FLOOR_PTS, 5.0]:
		for bloc in OpinionK.BLOC_KEYS:
			ns.bloc_approval[bloc] = float(truth.get(bloc, 50.0)) + pts
		var got := Elections.vote_share(ns, party_list, ns.incumbent_party_id)
		var move: float = (float(got.get(ns.incumbent_party_id, 0.0)) - base_share) * 100.0
		var gap_move: float = (_gap_of(got, ns.incumbent_party_id) - base_gap) * 100.0
		moves[pts] = move
		gaps[pts] = gap_move
		print("  %+8.1f %10.4f %10.4f %10.4f" % [
			pts, float(got.get(ns.incumbent_party_id, 0.0)), move, gap_move,
		])
	ns.bloc_approval = truth

	_move_min = float(moves[1.0])
	_move_max = float(moves[POLL_FLOOR_PTS])
	_gap_min = float(gaps[1.0])
	_gap_max = float(gaps[POLL_FLOOR_PTS])
	print("  clause (i) on SHARE: between %.4f and %.4f points" % [_move_min, _move_max])
	print("  clause (i) on GAP:   between %.4f and %.4f points" % [_gap_min, _gap_max])


## The incumbent's lead over the best other party. The quantity a plurality verdict
## actually turns on -- docs/election-model.md's "win = the incumbent party is the
## largest by seats".
func _gap_of(shares: Dictionary, incumbent: String) -> float:
	var mine: float = float(shares.get(incumbent, 0.0))
	var best_other := 0.0
	for pid in shares:
		if String(pid) != incumbent:
			best_other = maxf(best_other, float(shares[pid]))
	return mine - best_other


# --- (d) THE WINDOW AND THE LADDER, RESOLVED TOGETHER ------------------------------------

## *** TWO FREE VARIABLES AGAINST ONE BAND, WHICH IS V1.6f's ESCALATION TRIGGER 2 IN A
## NEW PLACE. *** That session found one uniform multiplier could not satisfy two
## clauses because the free variable was the ladder's SPREAD rather than its scale.
## Here the two free variables are the WINDOW and the ladder's uniform RATE SCALE, and
## they are resolved in the order this project resolves such things: the one with a
## unique solution is FITTED, and the one with a one-sided feasible set is taken at its
## smallest passing value.
##
##   THE RATE SCALE IS A FIT, not a band. For any window, the move is monotone in the
##   scale, so there is exactly one scale that puts the best affordable pair on
##   _move_min. V1.6a's rule: a band edge moves under widening and refinement, a
##   fit converges. Bisected below.
##
##   THE WINDOW IS THE SMALLEST PASSING, and the ordering is derived rather than
##   preferred. With the scale fitted, every window delivers the SAME move by
##   construction -- so a longer one buys nothing and costs strictly more, because the
##   bill runs for more months and the debt it adds is proportional to them. What stops
##   the answer being 1 is a CONTENT CEILING: a short window needs a per-month rate
##   above campaign_constants.MAX_MOBILISATION_PER_MONTH. The feasible set is therefore
##   one-sided in `d`, and V1.5b's corrected rule for a one-sided minimum is smallest
##   passing -- which is also what makes the answer interior to the grid rather than an
##   endpoint of it.
##
## THE PAIR IS MEASURED AND NOT ASSUMED, which the first run of this probe got wrong.
## It hard-coded broadcast + digital_push as "the widest reach" and every row came back
## NEGATIVE, because table (c3) says pensioners and rural are not this incumbent's
## voters and broadcast is aimed at exactly those two. Which pair helps is a fact about
## WHO THE PRESIDENT IS, so it is swept.
func _table_d_window() -> void:
	print("\n(d) the window, with the ladder FIXED as authored")
	var control := _run(0, [])
	print("  control: incumbent %.4f  largest %s  peak deficit %.4f" % [
		control["incumbent_share"], control["largest"], control["peak_deficit"],
	])
	print("  %4s %10s %10s %10s %10s %8s %8s  %s" % [
		"d", "move", "fitscale", "peak", "d-deficit", "bill", "pass", "best pair",
	])
	# V2.6b2: the rail clause reads the run's own MEASURED accumulator peak, not the
	# rate x d formula -- under siting the two disagree in both directions (the formula
	# misses month 1's full-fresh spike at a x6.63 capital and overstates the faded
	# tail). _max_stack_rate() stays for its other readers.
	var stack_rate := _max_stack_rate()
	var passing: Array = []
	var slacks: Array = []
	for d in D_CANDIDATES:
		if d > K.CAMPAIGN_WINDOW_MONTHS:
			# THE FIRST RUN OF THIS PROBE GOT THIS WRONG AND THE TABLE SHOWED IT. The
			# header claimed `d` emulates any window of `d` or more; it does not, because
			# Campaign.tick_month() CLEARS the register on a level read of the shipped
			# constant, so every row above it was a campaign wiped on the next tick and
			# reported a zero bill beside a non-zero move. Refused rather than printed:
			# raise the constant and re-run, which is V1.6b's "set the constant once and
			# re-run" applied to an integer.
			print("  %4d  not emulable at CAMPAIGN_WINDOW_MONTHS = %d -- raise it and re-run" % [
				d, K.CAMPAIGN_WINDOW_MONTHS,
			])
			continue
		var best := _best_pair(d, control)
		var pair: Array = best["pair"]
		var move: float = float(best["move"])
		var r := _run(d, pair)
		var max_stack: float = stack_rate * float(d)
		var peak: float = float(r["peak_mobilisation"])
		var d_deficit: float = r["peak_deficit"] - control["peak_deficit"]
		var ok_low: bool = move >= _move_min
		var ok_high: bool = move <= _move_max
		var ok_stack: bool = peak <= K.MOBILISATION_MAX
		var ok_deficit: bool = d_deficit <= _headroom()
		var ok_prop: bool = d <= WINDOW_MAX_MONTHS
		var ok: bool = ok_low and ok_high and ok_stack and ok_deficit and ok_prop
		if ok:
			passing.append(d)
			slacks.append({
				"d": d,
				"low": (move - _move_min) / _move_min,
				"stack": (K.MOBILISATION_MAX - peak) / K.MOBILISATION_MAX,
			})
		print("  %4d %10.4f %10.4f %10.4f %10.4f %8.4f %8s  %s" % [
			d, move, _fit_scale(d, pair, control), peak, d_deficit, _pair_cost(pair),
			("yes" if ok else "no(%s%s%s%s%s)" % [
				"" if ok_low else "lo", "" if ok_high else "hi", "" if ok_stack else "s",
				"" if ok_deficit else "d", "" if ok_prop else "p",
			]),
			str(pair),
		])
	if passing.is_empty():
		print("  NO CANDIDATE PASSES -- record the bound, do not retune DEFICIT_SCALE_PP")
	else:
		# *** THE INTERIOR IS TAKEN BY MAXIMIN SLACK, NOT BY LIST POSITION, and that is
		# this session's own addition to the tiebreaker rules. *** V1.5d established that
		# where two model criteria bound a quantity from opposite sides neither edge
		# selects and the interior governs -- but "the interior" of a passing LIST is a
		# statement about the grid, and V1.5b's whole finding was that a grid must never
		# choose. The interior of the FEASIBLE REGION is well defined without one: take
		# the candidate whose worst relative slack against the two binding criteria is
		# largest. It is stable under refinement (the slacks are continuous in `d`),
		# stable under widening (a candidate outside the region has negative slack), and
		# it degrades correctly -- if one criterion is far looser than the other it
		# returns the edge of the tighter one, which is what a bound SHOULD do.
		var best_d: int = passing[0]
		var best_slack := -1.0
		for entry in slacks:
			var worst: float = minf(float(entry["low"]), float(entry["stack"]))
			print("    d=%d  lower-edge slack %.1f %%  guard-rail slack %.1f %%  -> min %.1f %%" % [
				int(entry["d"]), float(entry["low"]) * 100.0, float(entry["stack"]) * 100.0, worst * 100.0,
			])
			if worst > best_slack:
				best_slack = worst
				best_d = int(entry["d"])
		print("  passing: %s  -> MAXIMIN SLACK selects %d (%.1f %%)" % [str(passing), best_d, best_slack * 100.0])
		print("  fitscale column: the uniform ladder scale that would put the best pair")
		print("    EXACTLY on the lower edge. A value under 1.0 means the AUTHORED ladder")
		print("    clears it by (1/scale - 1); a value over 1.0 means it falls short.")


## Every unordered pair of efforts the concurrency gate allows, measured, best first.
func _best_pair(d: int, control: Dictionary) -> Dictionary:
	var ids: Array = _starts().keys()
	ids.sort()
	var best: Array = []
	var best_move := -1e9
	for i in ids.size():
		for j in ids.size():
			if i >= j:
				continue
			var pair: Array = [ids[i], ids[j]]
			var r := _run(d, pair)
			var move: float = (r["incumbent_share"] - control["incumbent_share"]) * 100.0
			if move > best_move:
				best_move = move
				best = pair
	return {"pair": best, "move": best_move}


## The unique uniform scale on the authored mobilisation rates that puts `pair` on
## _move_min over `d` months. Bisected because the response is monotone in the
## scale and has no closed form -- the log-odds shift and the simplex renormalisation
## do not compose into one. Returns -1.0 if nothing inside the search reaches it, which
## is a finding rather than a failure.
func _fit_scale(d: int, pair: Array, control: Dictionary) -> float:
	var lo := 0.0
	var hi := 40.0
	if _move(d, pair, hi, control) < _move_min:
		return -1.0
	for _i in range(28):
		var mid: float = (lo + hi) * 0.5
		if _move(d, pair, mid, control) < _move_min:
			lo = mid
		else:
			hi = mid
	return hi


func _move(d: int, pair: Array, scale: float, control: Dictionary) -> float:
	var r := _run(d, pair, scale)
	return (r["incumbent_share"] - control["incumbent_share"]) * 100.0


func _max_authored_rate() -> float:
	var starts := _starts()
	var worst := 0.0
	for eid in starts:
		for bloc in starts[eid].get("mobilisation", {}):
			worst = maxf(worst, absf(float(starts[eid]["mobilisation"][bloc])))
	return worst


## The worst per-month rate two efforts can put on one bloc, before any scale.
func _max_stack_rate() -> float:
	var starts := _starts()
	var ids: Array = starts.keys()
	ids.sort()
	var worst := 0.0
	for i in ids.size():
		for j in ids.size():
			if i >= j:
				continue
			for bloc in OpinionK.BLOC_KEYS:
				worst = maxf(worst, absf(
					float(starts[ids[i]].get("mobilisation", {}).get(bloc, 0.0))
					+ float(starts[ids[j]].get("mobilisation", {}).get(bloc, 0.0))
				))
	return worst


func _pair_cost(pair: Array) -> float:
	var starts := _starts()
	var total := 0.0
	for eid in pair:
		total += float(starts.get(String(eid), {}).get("cost_eur_per_k_pop_month", 0.0))
	return total


# --- (e) dominance ----------------------------------------------------------------------

## No authored effort may be dominated: cheaper AND reaching at least as much of every
## bloc. The five are meant to be incomparable, and this is where that is checked
## rather than asserted -- V1.6f's standing test, and V1.6e's correction that produced
## it.
func _table_e_dominance() -> void:
	print("\n(e) dominance -- no effort may be cheaper and reach more")
	var starts := _starts()
	var ids: Array = starts.keys()
	ids.sort()
	var dominated := 0
	for a in ids:
		for b in ids:
			if a == b:
				continue
			var ta: Dictionary = starts[a]
			var tb: Dictionary = starts[b]
			if float(ta["cost_eur_per_k_pop_month"]) > float(tb["cost_eur_per_k_pop_month"]):
				continue
			var covers := true
			var strictly := float(ta["cost_eur_per_k_pop_month"]) < float(tb["cost_eur_per_k_pop_month"])
			for bloc in OpinionK.BLOC_KEYS:
				var ma: float = float(ta.get("mobilisation", {}).get(bloc, 0.0))
				var mb: float = float(tb.get("mobilisation", {}).get(bloc, 0.0))
				if ma < mb:
					covers = false
					break
				if ma > mb:
					strictly = true
			if covers and strictly:
				dominated += 1
				print("  '%s' DOMINATES '%s'" % [a, b])
	print("  dominated pairs: %d" % dominated)
	print("  ladder:")
	for eid in ids:
		var t: Dictionary = starts[eid]
		print("    %-14s %5.1f EUR per 1 000 a month  %s" % [eid, float(t["cost_eur_per_k_pop_month"]), str(t.get("mobilisation", {}))])


# --- (f) the guard rail -------------------------------------------------------------------

## MOBILISATION_MAX against the worst stack the content can reach, given the
## concurrency gate the content itself carries. A guard rail that BINDS is setting the
## number rather than guarding it.
func _table_f_guard_rail() -> void:
	print("\n(f) MOBILISATION_MAX %.2f -- guard rail, declared not a selector" % K.MOBILISATION_MAX)
	var starts := _starts()
	var ids: Array = starts.keys()
	ids.sort()
	var worst := 0.0
	var worst_where := ""
	for i in ids.size():
		for j in ids.size():
			if i >= j:
				continue
			for bloc in OpinionK.BLOC_KEYS:
				var rate: float = (
					float(starts[ids[i]].get("mobilisation", {}).get(bloc, 0.0))
					+ float(starts[ids[j]].get("mobilisation", {}).get(bloc, 0.0))
				)
				var reach: float = absf(rate) * float(K.CAMPAIGN_WINDOW_MONTHS)
				if reach > worst:
					worst = reach
					worst_where = "%s + %s on %s" % [ids[i], ids[j], bloc]
	print("  worst reachable stack over a full window: %.4f (%s)" % [worst, worst_where])
	print("  VERDICT: %s" % (
		"SLACK by %.4f -- the content is the lever" % (K.MOBILISATION_MAX - worst)
		if worst < K.MOBILISATION_MAX
		else "BINDING -- the clamp is setting the number, not the content"
	))

	var dearest := 0.0
	var dearest_pair := ""
	var starts2 := _starts()
	for i in ids.size():
		for j in ids.size():
			if i >= j:
				continue
			var sum: float = (
				float(starts2[ids[i]].get("cost_eur_per_k_pop_month", 0.0))
				+ float(starts2[ids[j]].get("cost_eur_per_k_pop_month", 0.0))
			)
			if sum > dearest:
				dearest = sum
				dearest_pair = "%s + %s" % [ids[i], ids[j]]
	print("  dearest pair the concurrency gate allows: %.1f EUR per 1 000 a month (%s)" % [dearest, dearest_pair])
	print("  against the headroom %.4f: %s" % [
		_headroom(),
		"INSIDE by %.4f" % (_headroom() - dearest) if dearest <= _headroom() else "OVER by %.4f" % (dearest - _headroom()),
	])


# --- (g) the kill switch -------------------------------------------------------------------

## Two bounds, and both must hold. A campaign that cannot turn a close election is
## decorative; one that can turn a rout is the strictly-dominated shape, because then
## nothing else a president does in five years matters as much as the last six months.
func _table_g_kill_switch() -> void:
	print("\n(g) kill switch -- decides the close, cannot rescue the rout")
	var control := _run(0, [])
	var best := _best_pair(K.CAMPAIGN_WINDOW_MONTHS, control)
	var full := _run(K.CAMPAIGN_WINDOW_MONTHS, best["pair"])
	var move: float = (full["incumbent_share"] - control["incumbent_share"]) * 100.0
	print("  full run-up move: %+.4f points of vote share" % move)
	print("  control gap to the runner-up: %+.4f points" % (control["gap"] * 100.0))
	print("  campaign gap to the runner-up: %+.4f points" % (full["gap"] * 100.0))
	print("  decides a race closer than %.4f points" % move)
	print("  worth, in points of approval: between %.4f (1 pt) and %.4f (%.1f pts)" % [
		_move_min, _move_max, POLL_FLOOR_PTS,
	])
	print("  VERDICT (lower): %s" % ("PASS" if move >= _move_min else "FAIL -- decorative, governing swamps it"))
	print("  VERDICT (upper): %s" % (
		"PASS -- a campaign cannot substitute for the record" if move <= _move_max
		else "FAIL -- worth more than the poll floor, so the last months buy back the term"
	))


# --- (h) share is not winning --------------------------------------------------------

## *** MAXIMISING YOUR OWN VOTE SHARE IS NOT THE SAME AS WINNING, AND NOBODY AUTHORED
## THAT. *** Table (g)'s best-on-share pair raises the incumbent by +0.42 points and
## NARROWS their lead over the runner-up, because mobilising a bloc lifts every party
## that bloc likes -- and the parties nearest you in ideology space are exactly the ones
## sharing your voters. Elections.vote_share() renormalises per bloc, so turnout is a
## rising tide inside a bloc rather than a transfer between parties.
##
## The consequence for a player is real: under a plurality verdict -- which is every
## verdict in this game, docs/election-model.md's "win = the incumbent party is the
## largest by seats" -- the quantity to maximise is the GAP, and the pair that maximises
## it is not always the pair that maximises the share. Measured here rather than
## asserted, and recorded in docs/campaign-model.md rather than fixed, because it is a
## property of the vote-share model and not a defect in this one.
func _table_h_share_is_not_winning() -> void:
	print("\n(h) share is not winning -- every pair, on both objectives")
	var control := _run(0, [])
	var ids: Array = _starts().keys()
	ids.sort()
	print("  %-30s %10s %10s" % ["pair", "d-share", "d-gap"])
	var best_share := -1e9
	var best_share_pair := ""
	var best_gap := -1e9
	var best_gap_pair := ""
	for i in ids.size():
		for j in ids.size():
			if i >= j:
				continue
			var r := _run(K.CAMPAIGN_WINDOW_MONTHS, [ids[i], ids[j]])
			var d_share: float = (r["incumbent_share"] - control["incumbent_share"]) * 100.0
			var d_gap: float = (r["gap"] - control["gap"]) * 100.0
			if d_share > best_share:
				best_share = d_share
				best_share_pair = "%s + %s" % [ids[i], ids[j]]
			if d_gap > best_gap:
				best_gap = d_gap
				best_gap_pair = "%s + %s" % [ids[i], ids[j]]
			print("  %-30s %10.4f %10.4f" % ["%s + %s" % [ids[i], ids[j]], d_share, d_gap])
	print("  best on SHARE: %-28s %+.4f" % [best_share_pair, best_share])
	print("  best on GAP:   %-28s %+.4f" % [best_gap_pair, best_gap])
	print("  VERDICT: %s" % (
		"the two objectives AGREE for this incumbent"
		if best_share_pair == best_gap_pair
		else "the two objectives DISAGREE -- winning is the gap, and it is not the share"
	))
	print("  clause (i) on the GAP: between %.4f and %.4f" % [_gap_min, _gap_max])
	print("  best gap move %.4f -- %s / %s" % [
		best_gap,
		"lower PASS" if best_gap >= _gap_min else "lower FAIL",
		"upper PASS" if best_gap <= _gap_max else "upper FAIL -- the campaign outruns the record",
	])


# --- the harness ------------------------------------------------------------------------

## The arg-max fresh site. Recomputed per run rather than cached, and priced through
## Campaign's own factor so the sweep and the game cannot disagree about which region
## is the peak.
## The nation's regions, freshest first -- the tour order the player's best play
## follows. Recomputed per run; priced through Campaign's own factor.
func _ranked_sites(ns) -> Array:
	var scored := []
	for rid in ns.region_pop_share:
		scored.append({"id": String(rid), "fresh": Campaign.fresh_factor(ns, _loader, String(rid))})
	scored.sort_custom(func(a, b): return float(a["fresh"]) > float(b["fresh"]))
	var out := []
	for entry in scored:
		out.append(String(entry["id"]))
	return out


func _best_site(ns) -> String:
	var best := ""
	var best_factor := -1.0
	for rid in ns.region_pop_share:
		var f: float = Campaign.fresh_factor(ns, _loader, String(rid))
		if f > best_factor or (is_equal_approx(f, best_factor) and best != "" and String(rid) < best):
			best_factor = f
			best = String(rid)
	return best


## effort id -> its authored `start` terms.
func _starts() -> Dictionary:
	var out := {}
	for action in _loader.campaign_actions:
		var t: Dictionary = action.effects.get("campaign", {})
		if String(t.get("op", "")) != "start":
			continue
		out[String(t.get("effort_id", ""))] = t
	return out


func _new_state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = START_YEAR
	state.month = 1
	return state


## Round Campaign.available()'s WINDOW CHECK and nothing else, so a candidate window is
## emulated exactly rather than rescaled from the shipped one. The bloc_offset is
## applied here too, because it is part of what the effort costs and a table that
## dropped it would measure a campaign nobody resents.
func _force_start(ns, action, site := "") -> void:
	var terms: Dictionary = action.effects.get("campaign", {})
	var eid := String(terms.get("effort_id", ""))
	ns.campaign_running.append(eid)
	# V2.6b2: the site rides the start, exactly as Campaign.execute() writes it. An
	# empty site keeps the pre-V2.6b2 factor-1.0 model, which is the control column.
	if site != "":
		ns.campaign_sites[eid] = site
	for bloc_id in action.effects.get("bloc_offset", {}).keys():
		ns.bloc_offset[bloc_id] = (
			float(ns.bloc_offset.get(bloc_id, 0.0))
			+ float(action.effects["bloc_offset"][bloc_id])
		)


func _action_for(effort_id: String) -> Variant:
	for action in _loader.campaign_actions:
		var t: Dictionary = action.effects.get("campaign", {})
		if String(t.get("op", "")) == "start" and String(t.get("effort_id", "")) == effort_id:
			return action
	return null


## Run from the start of the game to the month of the executive election, putting
## `efforts` into the field exactly `d` months before it. Returns what the vote sees,
## what the treasury paid, and the two registers table (a) checks.
## `scale` multiplies every authored mobilisation rate, which is how table (d) fits
## the ladder EXACTLY rather than rescaling a measured headline -- V1.6b's correction.
func _run(d: int, efforts: Array, scale: float = 1.0, site := "") -> Dictionary:
	var state = _new_state()
	var ns = state.player()
	var party_list: Array = _loader.parties.get(PLAYER, [])

	# The scale is applied to the LOADED CONTENT and restored afterwards, so a candidate
	# ladder runs through the real Campaign.tick_month() rather than being approximated
	# here. A probe that reimplemented the accrual would be the model with two writers.
	var restore := {}
	if scale != 1.0:
		for action in _loader.campaign_actions:
			var t: Dictionary = action.effects.get("campaign", {})
			if not t.has("mobilisation"):
				continue
			restore[action] = t["mobilisation"].duplicate()
			var scaled := {}
			for bloc in t["mobilisation"]:
				scaled[bloc] = float(t["mobilisation"][bloc]) * scale
			t["mobilisation"] = scaled

	var peak_deficit := 0.0
	var peak_mobilisation := 0.0
	var started := d <= 0

	while true:
		var to_go: int = Campaign.months_to_election(state, ns)
		if not started and to_go <= d:
			# V2.6b2: the sweep plays the player's BEST tour, not a camp -- each started
			# effort takes the next-ranked fresh site, because two efforts on one region
			# double-saturate it and measure a strategy the saturation counter exists to
			# prevent. An explicit `site` still pins every effort to one region, which is
			# the camping control column.
			var sites: Array = _ranked_sites(ns)
			var next_site := 0
			for eid in efforts:
				var action = _action_for(String(eid))
				if action == null:
					continue
				var use_site := site
				if use_site == "" and next_site < sites.size():
					use_site = String(sites[next_site])
					next_site += 1
				_force_start(ns, action, use_site)
			started = true

		if to_go <= 0:
			break

		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		_tick(state, ns)

		peak_deficit = maxf(peak_deficit, ns.deficit_pct_gdp)
		for bloc in OpinionK.BLOC_KEYS:
			peak_mobilisation = maxf(peak_mobilisation, absf(float(ns.campaign_mobilisation.get(bloc, 0.0))))

	var shares := Elections.vote_share(ns, party_list, ns.incumbent_party_id)
	var mine: float = float(shares.get(ns.incumbent_party_id, 0.0))
	var best_other := 0.0
	var largest := ""
	var largest_share := -1.0
	for pid in shares:
		var s: float = float(shares[pid])
		if s > largest_share:
			largest_share = s
			largest = String(pid)
		if String(pid) != ns.incumbent_party_id:
			best_other = maxf(best_other, s)

	for action in restore:
		action.effects["campaign"]["mobilisation"] = restore[action]

	return {
		"incumbent_share": mine,
		"largest": largest,
		"gap": mine - best_other,
		"peak_deficit": peak_deficit,
		"peak_mobilisation": peak_mobilisation,
		"framing": ns.framing_gain.duplicate(true),
		"press_freedom": ns.press_freedom,
	}


## One month, in main.gd's order.
func _tick(state, ns) -> void:
	Economy.tick_month(state)
	Budget.tick_month(state)
	Orgs.tick_month(state, _loader)
	Inflation.tick_month(state)
	Media.tick_month(state, _loader)
	Opinion.tick_month(state)
	Defence.tick_month(state)
	Companies.tick_month(state, _loader)
	Investment.tick_month(state)
	Projects.tick_month(state, _loader)
	Campaign.tick_month(state, _loader)
	Demography.tick_month(state)
	Society.tick_month(state)
	Unrest.tick_month(state)
	Cabinet.tick_month(state, _loader)
	if ns == null:
		return
