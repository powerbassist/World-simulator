extends SceneTree

## Judiciary probe: godot --headless --script res://tools/judiciary_probe.gd
##
## V1.1e's named measurement for the court. Five tables, and J0 runs before either
## constant matters, because the VERDICT ships no authored quantity: a law's reach is the
## largest fraction of any effect clamp it uses, and every one of those clamps was set by
## an earlier session for its own reasons.
##
##   (J0) THE REACH DISTRIBUTION AND THE REACHABLE INDEPENDENCE RANGE, measured before a
##        threshold exists. docs/referendum-model.md's V1.7c finding is that a kill switch
##        sweeping a range the player cannot reach is not a kill switch -- its table R1
##        swept approval 30 to 65 and cleared, and table R6 then measured what a French
##        president can actually hold and found the verb winnable only outside it. So this
##        table measures what rule of law can actually BE before anything is banded on it.
##
##   (J1) JUDICIAL_TOLERANCE. Five clauses, all written on the CONTENT rather than on a
##        count -- docs/campaign-model.md's V1.7a correction, where the first clause was a
##        number that sounded like a margin and every candidate failed it.
##
##   (J2) JUDICIAL_UNREST_BETA. What capturing the courts costs in legitimacy, which
##        docs/media-model.md located at V1.5d: legitimacy is willingness to accept your
##        rule OUTSIDE the ballot box, so it is the grievance, and unrest_constants'
##        UNREST_BLOCS are exactly who marches over a captured court.
##
##   (J3) THE KILL SWITCH, and it is named on a SPECIFIC regime rather than on "some
##        reachable regime" -- docs/credit-model.md tightened its own clause for exactly
##        that reason. A run that passes the whole court-weakening ladder and then the laws
##        it unlocks must NOT end better than a control on approval AND on the deficit. If
##        it does, capturing the courts is free and the price is decorative.
##
##   (J4) THE ROSTER, printed rather than banded: what each of the ten tolerates, and how
##        many of the reviewable laws each blocks.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Media = preload("res://src/sim/media.gd")
const Opinion = preload("res://src/sim/opinion.gd")
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
const Events = preload("res://src/sim/events.gd")

const Judiciary = preload("res://src/sim/judiciary.gd")
const JK = preload("res://src/sim/judiciary_constants.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")

const PLAYER := "FRA"
const START_YEAR := 2026
const MONTHS := 168
const TERM_MONTHS := 60

## The authored court-weakening ladder, and the strengthening rung beside it. Named here
## rather than searched for, because J3's kill switch has to run them in order and a
## content edit that removes one should turn this red rather than quietly measure less.
const WEAKEN := ["judicial_appointments_reform", "court_jurisdiction_limits", "judicial_tenure_act"]
const STRENGTHEN := "judicial_independence_act"

## The two authored approximations of "Emergency powers", which mechanics-governance.md
## tiers Someday. Clause (i) of J1 is written on these: a constitutional court that does
## not stop emergency powers is not one.
const EMERGENCY := ["emergency_procurement_powers", "emergency_broadcasting_powers"]

const TOLERANCE_SWEEP_MIN := 0.200
const TOLERANCE_SWEEP_MAX := 0.600
const TOLERANCE_STEP := 0.001

const BETA_SWEEP := [0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.40, 0.50, 0.75, 1.00]

const MANAGED_DELTA := {
	"spending_pct_gdp": {"defence": -1.4},
	"tax_rates_pct": {"vat": 3.0},
}


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	var reviewable := _reach_table(loader)
	_tolerance_table(loader, reviewable)
	_beta_table(loader)
	_kill_switch(loader)
	_roster_table(loader, reviewable)
	quit(0)


static func _managed(ns) -> Dictionary:
	var out := {}
	for channel in MANAGED_DELTA:
		var lines := {}
		var live: Dictionary = ns.spending_pct_gdp if channel == "spending_pct_gdp" else ns.tax_rates_pct
		for key in MANAGED_DELTA[channel]:
			lines[key] = maxf(0.0, float(live.get(key, 0.0)) + float(MANAGED_DELTA[channel][key]))
		out[channel] = lines
	return out


# ---------------------------------------------------------------------------
# (J0) The reach distribution and the reachable independence range
# ---------------------------------------------------------------------------

func _reach_table(loader) -> Array:
	print("")
	print("(J0) REACH, measured before a threshold exists")
	print("")

	var ordinary: Array = []
	var reviewable: Array = []
	for law in loader.laws:
		if law.constitutional:
			continue
		ordinary.append(law)
		if law.reach > 0.0:
			reviewable.append(law)
	reviewable.sort_custom(func(a, b): return a.reach > b.reach)

	print("  %-34s %s" % ["law", "reach"])
	for law in reviewable:
		print("  %-34s %.3f" % [law.id, law.reach])
	print("")
	print("  %d ordinary laws, %d with a reach above zero." % [ordinary.size(), reviewable.size()])
	print("  %d reach EXACTLY 0.000 and are structurally unreviewable -- every electoral" % [
		ordinary.size() - reviewable.size()])
	print("  reform Act, every tax law, and `regional_devolution`, which is the one a real")
	print("  court would most certainly hear. Recorded as a bound rather than patched: the")
	print("  alternative is an authored score, which is what this approach exists to avoid.")

	print("")
	print("  reachable rule of law, France: start %.1f, floor after the whole ladder %.1f," % [
		_start_independence(loader), _start_independence(loader) - 9.0])
	print("  ceiling with the strengthening Act %.1f. Every band below is written inside" % [
		_start_independence(loader) + 3.0])
	print("  that range -- V1.7c's finding that a kill switch sweeping an unreachable range")
	print("  is not a kill switch.")
	return reviewable


func _start_independence(loader) -> float:
	var state = GameState.new_game(loader, PLAYER)
	return state.player().judicial_independence


# ---------------------------------------------------------------------------
# (J1) JUDICIAL_TOLERANCE
# ---------------------------------------------------------------------------

func _tolerance_table(loader, reviewable: Array) -> void:
	print("")
	print("(J1) JUDICIAL_TOLERANCE -- five clauses, all written on the content")
	print("")
	print("   (i)   France's court must block BOTH emergency-powers laws at new game.")
	print("   (ii)  Germany must still pass a MAJORITY of ordinary laws.")
	print("   (iii) A full capture must unlock both, or the key does not work.")
	print("   (iv)  A full capture must leave something blocked, or it is a master key.")
	print("   (v)   Every rung of the ladder must be passable at the independence it is")
	print("         reached at, or the ladder has no first step.")
	print("")

	var state = GameState.new_game(loader, PLAYER)
	var fra: float = state.player().judicial_independence
	var deu: float = _independence_of(loader, "DEU")
	var ordinary: Array = []
	for law in loader.laws:
		if not law.constitutional:
			ordinary.append(law)

	var step: float = 0.0
	for law in loader.laws:
		if law.id == WEAKEN[0]:
			step = absf(float(law.effects.get("society", {}).get("judicial_independence", 0.0)))
	var capture: float = step * float(WEAKEN.size())

	var passing: Array = []
	var candidate := TOLERANCE_SWEEP_MIN
	while candidate <= TOLERANCE_SWEEP_MAX + 1e-9:
		if _clauses_hold(candidate, fra, deu, capture, step, ordinary, reviewable):
			passing.append(candidate)
		candidate += TOLERANCE_STEP

	print("  %-9s %-9s %-9s %-9s %-9s %s" % [
		"dial", "tolFRA", "FRA blk", "DEU blk", "capFRA", "clauses"])
	var shown := [0.250, 0.300, 0.320, 0.330, 0.345, 0.360, 0.370, 0.400, 0.450, 0.500]
	for value in shown:
		var tf := _tol(fra, value)
		var tc := _tol(fra - capture, value)
		var td := _tol(deu, value)
		print("  %-9.3f %-9.4f %-9d %-9d %-9d %s" % [
			value, tf,
			_blocked(reviewable, tf), _blocked(reviewable, td), _blocked(reviewable, tc),
			"PASS" if _clauses_hold(value, fra, deu, capture, step, ordinary, reviewable) else "",
		])

	print("")
	if passing.is_empty():
		print("  ** NO CANDIDATE PASSES.")
		return
	var lo: float = passing[0]
	var hi: float = passing[passing.size() - 1]
	print("  passing [%.3f, %.3f] on a %.3f grid swept over [%.3f, %.3f], %d points wide." % [
		lo, hi, TOLERANCE_STEP, TOLERANCE_SWEEP_MIN, TOLERANCE_SWEEP_MAX, passing.size()])
	print("  Both edges are the MODEL'S: neither is the grid's. Midpoint %.3f, interior to" % [
		(lo + hi) / 2.0])
	print("  the passing set AND to the swept range -- V1.5b's diagnostic that a value at an")
	print("  endpoint of the sweep is a suspect rather than a result.")
	print("  SHIPPED: %.3f" % JK.JUDICIAL_TOLERANCE)


func _clauses_hold(dial: float, fra: float, deu: float, capture: float, step: float,
		ordinary: Array, reviewable: Array) -> bool:
	var tf := _tol(fra, dial)
	var tc := _tol(fra - capture, dial)
	var td := _tol(deu, dial)

	for law in reviewable:
		if EMERGENCY.has(law.id):
			if law.reach <= tf:
				return false      # (i)
			if law.reach > tc:
				return false      # (iii)

	var deu_passes := 0
	for law in ordinary:
		if law.reach <= td:
			deu_passes += 1
	if float(deu_passes) <= float(ordinary.size()) / 2.0:
		return false              # (ii)

	if _blocked(reviewable, tc) < 1:
		return false              # (iv)

	for rung in range(WEAKEN.size()):
		if step / JK.INDEPENDENCE_LAW_MAX > _tol(fra - step * float(rung), dial):
			return false          # (v)
	return true


func _tol(independence: float, dial: float) -> float:
	if independence <= 1.0:
		return 1.0
	return clampf(dial * JK.ROSTER_MEAN_RULE_OF_LAW / independence, 0.0, 1.0)


func _blocked(reviewable: Array, tolerance: float) -> int:
	var count := 0
	for law in reviewable:
		if law.reach > tolerance:
			count += 1
	return count


func _independence_of(loader, nation_id: String) -> float:
	var state = GameState.new_game(loader, PLAYER)
	return state.nations[nation_id].judicial_independence


# ---------------------------------------------------------------------------
# (J2) JUDICIAL_UNREST_BETA
# ---------------------------------------------------------------------------

func _beta_table(loader) -> void:
	print("")
	print("(J2) JUDICIAL_UNREST_BETA -- what a captured court costs in legitimacy")
	print("")
	print("  Band (i)  the whole ladder must move the grievance at least as much as ONE")
	print("            point of press freedom does at PRESS_UNREST_BETA = %.1f, which is the" % UnrestK.PRESS_UNREST_BETA)
	print("            sibling ruler rather than an invented one.")
	print("  Band (ii) it must NOT on its own carry a calm country over")
	print("            UNREST_THRESHOLD_PCT = %.1f. A judicial reform that starts a general" % UnrestK.UNREST_THRESHOLD_PCT)
	print("            strike is docs/unrest-model.md's machine wearing this label.")
	print("")
	print("  %-8s %-13s %-13s %s" % ["beta", "grievance +", "peak unrest", "clauses"])

	var quiet := _capture_run(loader, 0.0)
	var passing: Array = []
	for beta in BETA_SWEEP:
		var run := _capture_run(loader, beta)
		var lift: float = float(run["peak"]) - float(quiet["peak"])
		var legible: bool = lift >= UnrestK.PRESS_UNREST_BETA * 0.125
		var safe: bool = float(run["peak"]) < UnrestK.UNREST_THRESHOLD_PCT
		var row := "  %-8.2f %-13.4f %-13.4f %s%s" % [
			beta, lift, run["peak"], "Y" if legible else "n", "Y" if safe else "n"]
		if legible and safe:
			row += "  PASS"
			passing.append(beta)
		print(row)

	print("")
	if passing.is_empty():
		print("  ** NO CANDIDATE PASSES. Set by argument as a ratio against PRESS_UNREST_BETA")
		print("     and say so -- docs/unrest-model.md's UNREST_COOLDOWN_MONTHS.")
		return
	print("  passing %s, midpoint %.3f" % [
		passing, (float(passing[0]) + float(passing[passing.size() - 1])) / 2.0])
	print("  SHIPPED: %.2f" % JK.JUDICIAL_UNREST_BETA)


## The whole ladder passed in the first three months, then a term of governing. Returns
## the peak grievance. The beta is EMULATED rather than set, because a probe cannot change
## a `const` at runtime -- V1.6b's correction.
func _capture_run(loader, beta: float) -> Dictionary:
	var state = GameState.new_game(loader, PLAYER)
	Budget.commit(state, _managed(state.player()))
	var ns = state.player()
	var peak := 0.0
	for i in range(TERM_MONTHS):
		if i < WEAKEN.size():
			var law = _law(loader, WEAKEN[i])
			if law != null:
				Legislature.apply(state, ns, law, loader)
		_tick(state, loader, i)
		# The shipped term is already inside ns.unrest_pct; re-price the deviation at the
		# candidate by adding the difference, which is exact because the term is linear.
		var extra: float = -Judiciary.independence_deviation(ns) * (beta - JK.JUDICIAL_UNREST_BETA)
		peak = maxf(peak, ns.unrest_pct + extra)
	return {"peak": peak}


func _law(loader, law_id: String):
	for law in loader.laws:
		if law.id == law_id:
			return law
	return null


# ---------------------------------------------------------------------------
# (J3) The kill switch
# ---------------------------------------------------------------------------

func _kill_switch(loader) -> void:
	print("")
	print("(J3) KILL SWITCH -- capturing the courts must not be free")
	print("")
	print("  Named on a SPECIFIC pair of runs rather than on `some reachable regime`,")
	print("  which is the clause docs/credit-model.md tightened on its own record. Both")
	print("  runs hold the same budget for a full term; one passes the ladder and then")
	print("  everything the capture unlocks, the other governs and passes nothing.")
	print("")

	var control := _career(loader, false)
	var captured := _career(loader, true)
	print("  %-12s %-11s %-11s %-11s %s" % ["run", "approval", "deficit", "unrest", "laws in force"])
	print("  %-12s %-11.4f %-11.4f %-11.4f %d" % [
		"control", control["approval"], control["deficit"], control["unrest"], control["passed"]])
	print("  %-12s %-11.4f %-11.4f %-11.4f %d" % [
		"captured", captured["approval"], captured["deficit"], captured["unrest"], captured["passed"]])
	print("")
	var better_approval: bool = captured["approval"] > control["approval"]
	var better_deficit: bool = captured["deficit"] < control["deficit"]
	if better_approval and better_deficit:
		print("  ** FIRED: capturing the courts ends better on approval AND on the deficit.")
	else:
		print("  CLEARED: capture ends %s on approval and %s on the deficit." % [
			"better" if better_approval else "worse",
			"better" if better_deficit else "worse"])
		print("  It buys %d extra laws in force and pays for them." % [
			int(captured["passed"]) - int(control["passed"])])


func _career(loader, capture: bool) -> Dictionary:
	var state = GameState.new_game(loader, PLAYER)
	Budget.commit(state, _managed(state.player()))
	var ns = state.player()
	var party_list: Array = loader.parties.get(PLAYER, [])
	var passed := 0

	for i in range(TERM_MONTHS):
		if capture and i < WEAKEN.size():
			var rung = _law(loader, WEAKEN[i])
			if rung != null and bool(Legislature.propose(state, loader, rung)["passed"]):
				passed += 1
		elif capture:
			# Everything the capture unlocks, one a month, biggest reach first.
			var best = null
			for law in Legislature.available(ns, loader.laws):
				if law.constitutional or law.reach <= 0.0:
					continue
				if Judiciary.strikes_down(ns, law):
					continue
				if not bool(Legislature.resolve_vote(ns, party_list, law, false)["passed"]):
					continue
				if best == null or law.reach > best.reach:
					best = law
			if best != null and bool(Legislature.propose(state, loader, best)["passed"]):
				passed += 1
		_tick(state, loader, i)

	return {
		"approval": ns.overall_approval_pct,
		"deficit": ns.deficit_pct_gdp,
		"unrest": ns.unrest_pct,
		"passed": passed,
	}


# ---------------------------------------------------------------------------
# (J4) The roster
# ---------------------------------------------------------------------------

func _roster_table(loader, reviewable: Array) -> void:
	print("")
	print("(J4) THE ROSTER -- printed rather than banded")
	print("")
	print("  %-5s %-7s %-16s %-9s %s" % ["id", "score", "review", "tolerance", "blocks"])
	var state = GameState.new_game(loader, PLAYER)
	var rows: Array = []
	for ns in state.nations.values():
		rows.append([ns.judicial_independence, ns.id, ns.judicial_review])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for row in rows:
		var tolerance := _tol(float(row[0]), JK.JUDICIAL_TOLERANCE)
		var blocks: String = "-- (no review)" if String(row[2]) == JK.REVIEW_NONE \
			else str(_blocked(reviewable, tolerance))
		print("  %-5s %-7.1f %-16s %-9.4f %s" % [row[1], row[0], row[2], tolerance, blocks])
	print("")
	print("  Britain's score is computed and never read, because its review rule is `none`.")
	print("  That IS parliamentary sovereignty. The Netherlands and Switzerland say the same")
	print("  by two other doctrines -- Art. 120 Grondwet and Art. 190 Cst.")


# ---------------------------------------------------------------------------

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
	Events.tick_month(state, loader)
	Cabinet.tick_month(state, loader)
	Elections.tick_month(state, loader)
