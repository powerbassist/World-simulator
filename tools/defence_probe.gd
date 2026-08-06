extends SceneTree

## Defence envelope probe:
##   godot --headless --script res://tools/defence_probe.gd
##
## V1.3g's named measurement, run before any constant in
## src/sim/defence_constants.gd was set to its shipped value and before a single
## verb was authored in data/diplomatic-actions/defence.json. That ordering is
## tools/coercion_probe.gd's, and it is what cut the authored `tariff_rate_pct`:
## a constant set before the measurement is a number the measurement is then read
## to justify.
##
##   (a) CAPABILITY EQUILIBRIUM. The ten nations' authored defence spending spans
##       1.1 to 2.0 points of GDP -- a 1.8x spread. Does the cost function resolve
##       it above rounding, or is capability nine nations that behave alike, which
##       is docs/trade-model.md's GRAVITY_EXPONENT = 1.0 finding in a third place?
##
##   (b) CAPABILITY_CONVERGENCE. BOTH BOUNDS ARE FAILURES. Too slow and a stock
##       that has not visibly moved inside a five-year term is a lever the player
##       cannot pull -- docs/scenario-model.md's decorative-axis failure. Too fast
##       and capability tracks spending closely enough to BE the spending line
##       under a second name, and every reader could have read spending_pct_gdp.
##
##   (c) THE DEPLOYMENT COST, against two anchors already in the tree: one point of
##       VAT is 0.53 points of GDP, and bloc_constants.CONTRIBUTION_BASE_PCT_GDP is
##       what an EU member already pays in.
##
##   (d) THE OBLIGED STACK -- ESCALATION TRIGGER 1. Fourteen years with the agenda
##       live, the player in pacts with its largest partners. If the reachable bill
##       sits ON DEPLOYMENT_BILL_MAX_PCT_GDP then the clamp and not the model is
##       setting the number, which is economy_constants.IMPULSE_MAX's failure in
##       its fifth place. The answer to that is not a larger clamp.
##
##   (e) THE OPINION COST -- ESCALATION TRIGGER 3. Against poll_noise.gd's
##       NOISE_MAX_PCT of 3.0 points, with all six bloc rows and their authored
##       `defence` salience printed rather than assumed. Two sub-checks that are
##       easy to skip and both fire: what Cabinet.effectiveness() would have done
##       had the load been run through it, and the count at which _scaled()'s clamp
##       makes further deployments FREE.
##
##   (f) DEPLOYMENT_OBLIGED_MULT. The ratio at which an obliged commitment is
##       distinguishable from a chosen one IN THE HEADLINE. Below it the multiplier
##       is decorative -- docs/diplomacy-model.md's own finding about a split price.
##
## Not a test. tests/test_defence.gd asserts the invariants this probe is used to
## FIND; this prints tables a human reads while setting constants. Kept in tools/
## and excluded from run_tests.sh, same as every probe before it -- which is why it
## must be run by hand before a commit. V1.3e lost thirty balance runs to exactly
## that exclusion.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Defence = preload("res://src/sim/defence.gd")
const K = preload("res://src/sim/defence_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const CabinetK = preload("res://src/sim/cabinet_constants.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const Coercion = preload("res://src/sim/coercion.gd")
const CoercionK = preload("res://src/sim/coercion_constants.gd")
const FP = preload("res://src/sim/foreign_policy.gd")
const FPK = preload("res://src/sim/foreign_policy_constants.gd")
const Trade = preload("res://src/sim/trade.gd")
const RK = preload("res://src/core/relations.gd")
const BlocK = preload("res://src/sim/bloc_constants.gd")

## poll_noise.gd's NOISE_MAX_PCT: below this a headline move is not a move.
const NOISE_FLOOR_PCT := 3.0

## One point of VAT, as a share of GDP -- economy_constants.TAX_BASE_SHARE["vat"].
## The anchor the deployment cost is read against: a commitment nobody can feel is
## decorative, and one that costs more than the largest tax lever is not thin.
const VAT_POINT_PCT_GDP := 0.25

const MONTHS := 168
const START_YEAR := 2026


## A pact is always signed by a verb in the real game, and data/diplomatic-actions/
## has none yet because this probe runs first. Rather than teach Defence.sign_pact()
## to accept a null action -- leniency in src/ that only a tool would ever use --
## the probe brings its own stub with the two fields the register copies.
class StubAction:
	var id: String = "probe_pact"
	var action_name: String = "Probe Pact"


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	_equilibrium_table(loader)
	_convergence_sweep()
	_cost_table(loader)
	_obliged_stack_table(loader)
	_opinion_table(loader)
	_obliged_multiplier_table(loader)
	# Pass two: run AFTER data/diplomatic-actions/defence.json exists, because both
	# tables score the shipped verbs rather than synthetic ones.
	_pact_acceptance_table(loader)
	_pact_desire_table(loader)
	_pact_saturation_table(loader)
	quit(0)


# --- (g) Pact acceptance ------------------------------------------------------

## All ninety ordered pairs against PACT_ACCEPT_MIN, at four points in a run.
##
## Two failures to catch, and both have precedent. GBR CAN NEVER ALLY is V1.3e's
## finding, which has now fired five times: Britain is in no EU pair and borders
## nothing, so every absolutely-anchored term it has sits at the floor. And
## SATURATION is the opposite failure -- 45 pacts is a world where everyone is
## allied to everyone, which carries exactly as much information as none.
func _pact_acceptance_table(loader) -> void:
	print("\n########## (g) pact acceptance over all 90 ordered pairs ##########")
	print("PACT_ACCEPT_MIN = %.2f. Weights: stake %.2f, amity %.2f, capability %.2f." % [
		FPK.PACT_ACCEPT_MIN, FPK.PACT_STAKE_WEIGHT,
		FPK.PACT_AMITY_WEIGHT, FPK.PACT_CAPABILITY_WEIGHT,
	])
	print("`accepts` is ordered pairs where the TARGET would sign; 90 means saturated.")
	print("")
	print("  %8s %10s %8s %8s %s" % ["month", "accepts", "of 90", "GBR-in", "GBR asking"])

	for months in [0, 24, 60, 168]:
		var state = _run_world(loader, months)
		var ids: Array = state.nations.keys()
		ids.sort()

		var accepts := 0
		var gbr_in := 0
		var gbr_asking := 0
		for a_id in ids:
			for b_id in ids:
				if a_id == b_id:
					continue
				if not FP.would_accept_pact(state, String(a_id), String(b_id)):
					continue
				accepts += 1
				if String(a_id) == "GBR" or String(b_id) == "GBR":
					gbr_in += 1
				if String(a_id) == "GBR":
					gbr_asking += 1

		print("  %8d %10d %8d %8d %8d" % [months, accepts, 90, gbr_in, gbr_asking])

	print("")
	print("  GBR-in at 0 for every row is escalation trigger 2's second half: Britain")
	print("  structurally unable to ally is V1.3e's finding a sixth time.")
	print("  accepts at 90 is the opposite failure -- a register carrying no information.")

	print("")
	print("  PACT_ACCEPT_MIN swept at month 24, against both failures at once:")
	print("  %8s %10s %8s %10s %s" % ["bar", "accepts", "GBR-in", "GBR asks", ""])

	var swept = _run_world(loader, 24)
	var ids2: Array = swept.nations.keys()
	ids2.sort()
	# Scored once; the bar is only a threshold over the same numbers.
	var scores: Array = []
	for a_id in ids2:
		for b_id in ids2:
			if a_id == b_id:
				continue
			scores.append([
				String(a_id), String(b_id),
				FP.pact_accept_score(swept, String(a_id), String(b_id)),
			])

	for bar in [0.60, 0.80, 1.00, 1.20, 1.40, 1.60]:
		var accepts := 0
		var gbr_in := 0
		var gbr_asks := 0
		for row in scores:
			if float(row[2]) < float(bar):
				continue
			accepts += 1
			if String(row[0]) == "GBR" or String(row[1]) == "GBR":
				gbr_in += 1
			if String(row[0]) == "GBR":
				gbr_asks += 1
		var flag := ""
		if gbr_asks > 0 and accepts < 45:
			flag = "  <-- Britain can ally, register still informative"
		print("  %8.2f %10d %8d %10d %s" % [bar, accepts, gbr_in, gbr_asks, flag])


## The world running with nothing that ends a run under it, so the four rows above
## are the same game read at four ages. Opinion and Elections are left out for
## tools/foreign_policy_probe.gd's reason: they change the government and would make
## the later rows measure a different nation.
func _run_world(loader, months: int):
	var state = GameState.new_game(loader, "FRA")
	for i in range(months):
		state.month = i % 12 + 1
		state.year = START_YEAR + i / 12
		Economy.tick_month(state)
		Bloc.tick_month(state, loader)
		Diplomacy.tick_month(state, loader)
		Defence.tick_month(state)
	return state


# --- (h) Does the agenda reach for a pact? ------------------------------------

## desire_from() for the shipped pact verbs against AGENDA_ACT_MIN.
##
## The brake this is checking. _act_intensity() reads effects.relations and
## effects.measure.severity ONLY, so a sign verb authored at +7 relations scores
## like a state visit while carrying a permanent contingent liability the score
## cannot see. At new-game every pair sits at amity 0 and `deepen` is the only open
## term, which is the hardest case: if the nine all sign on their first turn, the
## register saturates at 45 and the feature is gone.
func _pact_desire_table(loader) -> void:
	print("\n########## (h) desire for the pact verbs, against AGENDA_ACT_MIN ##########")
	print("AGENDA_ACT_MIN = %.3f. `best other` is the top non-pact verb for the pair," % FPK.AGENDA_ACT_MIN)
	print("so `wins` counts pairs where signing OUTRANKS everything else on offer.")
	print("")
	print("  %-14s %10s %10s %10s %8s" % ["verb", "max", "mean", "over bar", "wins"])

	var state = GameState.new_game(loader, "FRA")
	var ids: Array = state.nations.keys()
	ids.sort()

	var pact_ids := ["defence_pact", "abandon_pact", "deploy_forces", "withdraw_forces"]
	for verb_id in pact_ids:
		var action = _action_by_id(loader, verb_id)
		if action == null:
			print("  %-14s  (not in data/diplomatic-actions/)" % verb_id)
			continue

		var top := -999.0
		var total := 0.0
		var n := 0
		var over := 0
		var wins := 0
		for a_id in ids:
			for b_id in ids:
				if a_id == b_id:
					continue
				var terms := FP.target_terms(state, String(a_id), String(b_id))
				var score_v := FP.desire_from(terms, action.effects)
				top = maxf(top, score_v)
				total += score_v
				n += 1
				if score_v > FPK.AGENDA_ACT_MIN:
					over += 1
				var best_other := -999.0
				for other in loader.diplomatic_actions:
					if pact_ids.has(other.id):
						continue
					best_other = maxf(best_other, FP.desire_from(terms, other.effects))
				if score_v > best_other:
					wins += 1

		print("  %-14s %10.4f %10.4f %10d %8d" % [
			verb_id, top, total / maxf(float(n), 1.0), over, wins
		])

	print("")
	print("  `wins` at 90 means every nation signs with everybody on its first turn.")

	# WHY, measured rather than asserted. If one verb takes all ninety pairs, the
	# pact's problem is not the pact's price.
	print("")
	print("  Which verb actually wins each of the 90 pairs, and its authored price:")
	var winners := {}
	for a_id in ids:
		for b_id in ids:
			if a_id == b_id:
				continue
			var terms := FP.target_terms(state, String(a_id), String(b_id))
			var best_id := ""
			var best := -999.0
			for action in loader.diplomatic_actions:
				var score_v := FP.desire_from(terms, action.effects)
				if score_v > best:
					best = score_v
					best_id = action.id
			winners[best_id] = int(winners.get(best_id, 0)) + 1

	for verb_id in winners.keys():
		var action = _action_by_id(loader, verb_id)
		var price := 0.0
		for v in (action.effects.get("bloc_offset", {}) as Dictionary).values():
			price += absf(float(v))
		print("    %-18s wins %3d   relations %+.1f   domestic price %.3f" % [
			verb_id, int(winners[verb_id]), float(action.effects.get("relations", 0.0)), price,
		])


func _action_by_id(loader, action_id: String):
	for action in loader.diplomatic_actions:
		if action.id == action_id:
			return action
	return null


## What the register actually holds after fourteen years of the agenda running with
## the verbs available. The claim (h) can only argue, measured.
func _pact_saturation_table(loader) -> void:
	print("\n########## (h2) the pact register after fourteen years ##########")
	print("`pacts` is of 45 unordered pairs; `deploys` of 90 ordered ones.")
	print("")
	print("  %8s %8s %10s %10s %s" % ["month", "pacts", "of 45", "deploys", "busiest nation"])

	for months in [24, 60, 168]:
		var state = _run_world(loader, months)
		var busiest := ""
		var busiest_n := 0
		var ids: Array = state.nations.keys()
		ids.sort()
		for id in ids:
			var n := Defence.pact_count(state, String(id))
			if n > busiest_n:
				busiest_n = n
				busiest = String(id)
		print("  %8d %8d %10d %10d   %s %d" % [
			months, state.pacts.size(), 45, state.deployments.size(), busiest, busiest_n,
		])

	print("")
	print("  A count at or near 45 is the saturation failure. A count of 0 at month 168")
	print("  is the opposite one: content the agenda never reaches, which is")
	print("  AGENDA_ACT_MIN measured against the wrong state -- V1.3f's fourth correction.")


# --- (a) Capability equilibrium ----------------------------------------------

func _equilibrium_table(loader) -> void:
	print("\n########## (a) capability equilibrium, and whether the ten separate ##########")
	print("Authored defence spending is the ONLY input. CAPABILITY_REFERENCE = %.2f." % K.CAPABILITY_REFERENCE)
	print("`ratio` is clamped to [%.2f, %.2f]; `cost` is one deployment, %% of GDP/yr." % [
		K.DEPLOYMENT_COST_MIN_RATIO, K.DEPLOYMENT_COST_MAX_RATIO
	])
	print("")
	print("  %-5s %8s %8s %8s %10s" % ["id", "def%GDP", "capab", "ratio", "cost%GDP"])

	var state = GameState.new_game(loader, "FRA")
	var ids: Array = state.nations.keys()
	ids.sort()

	var lo := 999.0
	var hi := -999.0
	for id in ids:
		var ns = state.nations[id]
		var cap := float(ns.military_capability)
		var ratio := Defence.capability_ratio(ns)
		var cost := Defence.deployment_cost_pct_gdp(ns)
		lo = minf(lo, cost)
		hi = maxf(hi, cost)
		print("  %-5s %8.2f %8.3f %8.3f %10.4f" % [id, Defence.capability_target(ns), cap, ratio, cost])

	print("")
	print("  cost span %.4f .. %.4f  =  %.2fx" % [lo, hi, hi / maxf(lo, 0.0001)])
	print("  READ: a span at 1.00x means capability is one number written ten times.")


# --- (b) CAPABILITY_CONVERGENCE ----------------------------------------------

func _convergence_sweep() -> void:
	print("\n########## (b) CAPABILITY_CONVERGENCE: both bounds are failures ##########")
	print("France moved 2.0 -> 4.0 points of GDP in month 0 and held there.")
	print("`half` is months to close half the gap; a term is 60 months.")
	print("")
	print("  %8s %8s %8s %8s %8s" % ["conv", "half", "@12mo", "@60mo", "@168mo"])

	for conv in [0.005, 0.01, 0.02, 0.04, 0.08]:
		var cap := 2.0
		var target := 4.0
		var half := -1
		var at12 := 0.0
		var at60 := 0.0
		for m in range(MONTHS):
			cap += float(conv) * (target - cap)
			if half < 0 and cap >= 3.0:
				half = m + 1
			if m == 11:
				at12 = cap
			if m == 59:
				at60 = cap
		print("  %8.3f %8d %8.2f %8.2f %8.2f" % [conv, half, at12, at60, cap])

	print("")
	print("  TOO SLOW: half-life past ~60 means a player cannot move it inside a term.")
	print("  TOO FAST: @12mo already at target means capability IS spending_pct_gdp.")


# --- (c) The deployment cost --------------------------------------------------

func _cost_table(loader) -> void:
	print("\n########## (c) one deployment's cost, against two anchors ##########")
	print("Anchors: one VAT point = %.2f %% of GDP; bloc contribution base = %.2f %% of GDP." % [
		VAT_POINT_PCT_GDP, BlocK.CONTRIBUTION_BASE_PCT_GDP
	])
	print("DEPLOYMENT_COST_PCT_GDP = %.3f, bill clamp = %.2f." % [
		K.DEPLOYMENT_COST_PCT_GDP, K.DEPLOYMENT_BILL_MAX_PCT_GDP
	])
	print("")
	print("  %-5s %8s %10s %10s %12s %12s" % ["id", "capab", "cost%GDP", "vat pts", "1 deploy bn", "4 deploy bn"])

	var state = GameState.new_game(loader, "FRA")
	for id in ["FRA", "DEU", "LUX"]:
		var ns = state.nations[id]
		var cost := Defence.deployment_cost_pct_gdp(ns)
		var bn := cost * float(ns.gdp_eur_bn) / 100.0
		print("  %-5s %8.3f %10.4f %10.2f %12.1f %12.1f" % [
			id, ns.military_capability, cost, cost / VAT_POINT_PCT_GDP, bn, bn * 4.0
		])

	print("")
	print("  Capability swept for FRA, holding everything else:")
	print("  %8s %8s %10s %10s" % ["def%GDP", "capab", "ratio", "cost%GDP"])
	var fra = state.nations["FRA"]
	var saved := float(fra.military_capability)
	for cap in [1.1, 1.5, 2.0, 3.0, 4.0, 6.0]:
		fra.military_capability = float(cap)
		print("  %8.1f %8.2f %10.3f %10.4f" % [
			cap, cap, Defence.capability_ratio(fra), Defence.deployment_cost_pct_gdp(fra)
		])
	fra.military_capability = saved


# --- (d) The obliged stack ----------------------------------------------------

func _obliged_stack_table(loader) -> void:
	print("\n########## (d) THE OBLIGED STACK -- escalation trigger 1 ##########")
	print("Fourteen years, agenda AND council live, player in pacts with `who`.")
	print("")
	print("> THE PROBE'S FIRST CORRECTION, and it is a finding about the world rather")
	print("> than about this session: THE NINE NEVER COERCE EACH OTHER. Over 168 months")
	print("> with the agenda running and no player, `state.measures` stays EMPTY and all")
	print("> 24 recorded acts are state_visit -- V1.3f's agenda is friendly by revealed")
	print("> preference. So the only AI-driven source of a measure in the whole project")
	print("> is the council's common_external_tariff, which is exactly the V1.3d feature")
	print("> V1.3d's own re-run never fired and V1.3f's did. Bloc.tick_month() is")
	print("> therefore LOAD-BEARING for this table; without it the obligation is")
	print("> unreachable and the measurement says zero for the wrong reason.")
	print("")
	print("`who`: top = largest trade partners; outside = the non-members the council's")
	print("external tariff can actually reach. `retals` counts live retaliated measures.")
	print("")
	print("  %-5s %-8s %6s %8s %8s %10s %10s %6s %7s" % [
		"id", "who", "pacts", "maxDep", "endDep", "maxBill", "endBill", "meas", "retals",
	])

	for player_id in ["FRA", "DEU", "GBR"]:
		for who in ["top2", "top5", "outside"]:
			var state = GameState.new_game(loader, player_id)
			var ns = state.nations[player_id]

			var partners := _partners_for(state, player_id, who)
			for partner_id in partners:
				Defence.sign_pact(state, player_id, String(partner_id), StubAction.new())

			var max_dep := 0
			var max_bill := 0.0
			for i in range(MONTHS):
				state.month = i % 12 + 1
				state.year = START_YEAR + i / 12
				Economy.tick_month(state)
				Budget.tick_month(state)
				# The council, and the whole reason this table is not all zeros.
				Bloc.tick_month(state, loader)
				Diplomacy.tick_month(state, loader)
				Defence.tick_month(state)

				var count := Defence.deployment_count(state, player_id)
				max_dep = maxi(max_dep, count)
				max_bill = maxf(max_bill, float(ns.deployment_bill_pct_gdp))

			var retals := 0
			for terms in state.measures.values():
				if bool(terms.get("retaliated", false)):
					retals += 1

			print("  %-5s %-8s %6d %8d %8d %10.3f %10.3f %6d %7d" % [
				player_id, who, partners.size(), max_dep,
				Defence.deployment_count(state, player_id),
				max_bill, ns.deployment_bill_pct_gdp, state.measures.size(), retals,
			])

	print("")
	print("  TRIGGER 1 FIRES if maxBill sits on the clamp (%.2f)." % K.DEPLOYMENT_BILL_MAX_PCT_GDP)
	print("  A SECOND failure is visible here too: all-zero `maxDep` on every row would")
	print("  mean the obligation is unreachable in ordinary play, and an alliance whose")
	print("  obligation never arrives is the decorative axis this session exists to avoid.")


## The pacts a player would plausibly hold. Two shapes, because the trade-weighted
## answer and the reachable-obligation answer are different questions: the largest
## partners are who you WANT an alliance with, and the nations outside the bloc are
## who the council's external tariff can actually reach.
func _partners_for(state, player_id: String, who: String) -> Array:
	if who == "outside":
		var out: Array = []
		var ids: Array = state.nations.keys()
		ids.sort()
		for id in ids:
			if String(id) != player_id and not state.nations[id].eu_member:
				out.append(String(id))
		return out
	return _top_partners(state, player_id, 2 if who == "top2" else 5)


func _top_partners(state, actor_id: String, n: int) -> Array:
	var row := Trade.weights(state, actor_id)
	var pairs: Array = []
	for partner_id in row.keys():
		pairs.append([String(partner_id), float(row[partner_id])])
	pairs.sort_custom(func(a, b): return a[1] > b[1])
	var out: Array = []
	for i in range(mini(n, pairs.size())):
		out.append(pairs[i][0])
	return out


# --- (e) The opinion cost -----------------------------------------------------

func _opinion_table(loader) -> void:
	print("\n########## (e) THE OPINION COST -- escalation trigger 3 ##########")
	print("DEPLOYMENT_OPINION_CHOSEN = %.3f, OBLIGED_MULT = %.2f, noise floor %.1f points." % [
		K.DEPLOYMENT_OPINION_CHOSEN, K.DEPLOYMENT_OBLIGED_MULT, NOISE_FLOOR_PCT
	])
	print("Thirty-six months of the real Opinion chain, control vs treatment.")
	print("")

	print("  authored `defence` salience per bloc (BLOC_SALIENCE_BASE):")
	var bloc_line := "   "
	for bloc_key in OpinionK.BLOC_SALIENCE_BASE.keys():
		bloc_line += " %s %.2f " % [
			String(bloc_key).substr(0, 4),
			float(OpinionK.BLOC_SALIENCE_BASE[bloc_key].get("defence", 0.0)),
		]
	print(bloc_line)
	print("")

	print("> THE PROBE'S SECOND CORRECTION: THE HEADLINE IS THE WRONG STATISTIC HERE,")
	print("> and the salience row above says so before any number is read. `defence` is")
	print("> weighted 0.00 by five blocs of six and 0.12 by rural alone, so a deployment")
	print("> price CANNOT move overall_approval_pct past the noise floor no matter how")
	print("> large it is -- raising the constant until it did would be tuning against an")
	print("> arithmetic impossibility. This is docs/diplomacy-model.md's own measured")
	print("> finding ('a domestic price hitting fewer than all six blocs is legible on")
	print("> the polling panel and never in the headline') reached a second time from")
	print("> the other direction. The test is the SALIENT BLOC's row against 3.0.")
	print("")

	var base := _settled_approval(loader, 0, false)
	print("  %-8s %8s %7s %8s %9s %8s %8s %9s %s" % [
		"deploys", "kind", "bill", "deficit", "headline", "d(head)", "rural", "d(rural)", "",
	])
	print("  %-8d %8s %7.3f %8.2f %9.2f %8.2f %8.2f %9.2f" % [
		0, "-", base["bill"], base["deficit"], base["overall"], 0.0, base["rural"], 0.0,
	])

	for count in [1, 2, 4, 6]:
		for obliged in [false, true]:
			var run := _settled_approval(loader, count, obliged)
			var d_head: float = float(run["overall"]) - float(base["overall"])
			var d_rural: float = float(run["rural"]) - float(base["rural"])
			var flag := ""
			if absf(d_head) >= NOISE_FLOOR_PCT:
				flag = "  <-- CLEARS in the headline"
			elif absf(d_rural) >= NOISE_FLOOR_PCT:
				flag = "  <-- CLEARS on rural"
			print("  %-8d %8s %7.3f %8.2f %9.2f %8.2f %8.2f %9.2f%s" % [
				count, "obliged" if obliged else "chosen", run["bill"], run["deficit"],
				run["overall"], d_head, run["rural"], d_rural, flag,
			])

	print("")
	print("  SATURATION: `load` is what deployment_opinion_load() returns; _scaled()")
	print("  clamps satisfaction to [-1, +1], so past the count where the `defence` row")
	print("  reaches -1.00 every further deployment is FREE.")
	print("  %-10s %8s %10s" % ["deploys", "load", "sat[def]"])
	for count in [1, 2, 4, 6, 8, 12]:
		var run := _settled_approval(loader, count, true)
		print("  %-10d %8.3f %10.3f" % [count, run["load"], run["sat_defence"]])

	print("")
	var eff := _effectiveness_span(loader)
	print("  Cabinet.effectiveness(FRA, 'defence') spans %.3f .. %.3f in reachable play." % [
		eff[0], eff[1]
	])
	print("  The load is subtracted AFTER it. Run THROUGH it the price would scale by")
	print("  exactly that span, so a competent minister would cancel this session.")


## Thirty-six months of Economy/Budget/Opinion with `count` deployments held open
## on the player. Defence.tick_month() is deliberately NOT run: its reconciler
## would close an obliged deployment with no measure behind it, and what this table
## measures is the price of a GIVEN load, not whether the load is reachable --
## which is (d)'s job. The load itself is computed by the real function.
func _settled_approval(loader, count: int, obliged: bool) -> Dictionary:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.nations["FRA"]

	var ids: Array = state.nations.keys()
	ids.sort()
	var opened := 0
	for ally_id in ids:
		if opened >= count or String(ally_id) == "FRA":
			continue
		Defence.sign_pact(state, "FRA", String(ally_id), StubAction.new())
		Defence.open_deployment(
			state, "FRA", String(ally_id),
			K.DEPLOYMENT_OBLIGED if obliged else K.DEPLOYMENT_CHOSEN, null,
		)
		opened += 1

	for i in range(36):
		state.month = i % 12 + 1
		state.year = START_YEAR + i / 12
		# BOTH prices, written before Budget reads them, which is the order the real
		# chain produces: Defence.tick_month() runs at the end of a month and Budget
		# picks the bill up at the start of the next. Setting only the opinion load
		# measured half the price and was the probe's third correction -- the bill
		# widens the deficit, and `public_finances` is weighted by all six blocs
		# where `defence` is weighted by one.
		ns.deployment_bill_pct_gdp = Defence.deployment_bill_pct_gdp(state, ns)
		ns.deployment_opinion_load = Defence.deployment_opinion_load(state, ns)
		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)

	var worst := ""
	var worst_v := 999.0
	for bloc_key in ns.bloc_approval.keys():
		if float(ns.bloc_approval[bloc_key]) < worst_v:
			worst_v = float(ns.bloc_approval[bloc_key])
			worst = String(bloc_key)

	return {
		"overall": ns.overall_approval_pct,
		"worst": "%s %d" % [worst.substr(0, 8), int(worst_v)],
		# The only bloc that weights `defence` at all. Named rather than derived so
		# the table breaks loudly if S5's salience row is ever re-authored.
		"rural": float(ns.bloc_approval.get("rural", 0.0)),
		"load": ns.deployment_opinion_load,
		"sat_defence": float(Opinion.issue_satisfaction(ns).get("defence", 0.0)),
		"bill": ns.deployment_bill_pct_gdp,
		"deficit": ns.deficit_pct_gdp,
	}


func _effectiveness_span(loader) -> Array:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.nations["FRA"]
	var here := Cabinet.effectiveness(ns, "defence")
	# The vacant end is the cabinet model's own floor for a portfolio nobody holds;
	# the other end is a fully competent minister at 1.0.
	return [minf(here, CabinetK.VACANT_EFFECTIVENESS), maxf(here, 1.0)]


# --- (f) DEPLOYMENT_OBLIGED_MULT ---------------------------------------------

func _obliged_multiplier_table(loader) -> void:
	print("\n########## (f) DEPLOYMENT_OBLIGED_MULT: is obliged legible as different? ##########")
	print("Same deployment count, chosen vs obliged, at several multipliers. The gap has")
	print("to clear %.1f points or the distinction exists only in the register." % NOISE_FLOOR_PCT)
	print("")
	print("Read on the rural row for table (e)'s reason. `reach` marks the stack table")
	print("(d) actually produces in fourteen years -- a gap at a count nobody reaches is")
	print("a distinction the player never sees.")
	print("")
	print("  %8s %9s %9s %8s %7s %s" % ["deploys", "rur chos", "rur obl", "gap", "reach", ""])

	for count in [1, 2, 4]:
		var chosen := _settled_approval(loader, count, false)
		var obliged := _settled_approval(loader, count, true)
		var gap: float = float(chosen["rural"]) - float(obliged["rural"])
		var flag := "  <-- CLEARS" if absf(gap) >= NOISE_FLOOR_PCT else ""
		print("  %8d %9.2f %9.2f %8.2f %7s %s" % [
			count, chosen["rural"], obliged["rural"], gap,
			"yes" if count <= 2 else "no", flag,
		])

	print("")
	print("  NOTE: the multiplier itself is a constant this table cannot sweep without")
	print("  re-running the module. What it measures is whether the SHIPPED value is")
	print("  legible; a gap under the floor is read as 'raise it or delete it'.")
