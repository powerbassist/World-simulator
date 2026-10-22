extends SceneTree

## Interest-model envelope probe:
##   godot --headless --script res://tools/foreign_policy_probe.gd
##
## V1.3e's named measurement, run before any constant in
## src/sim/foreign_policy_constants.gd was set to its shipped value.
##
##   (a) THE SPREAD -- THE ESCALATION TRIGGER. tools/bloc_probe.gd table (d)
##       prints the eight non-player members' coalition_position and they are
##       CLUSTERED: economic spans -0.54..+0.33, social -0.50..+0.63. An interest
##       function resting on that gives nine nations that behave alike, which is
##       docs/trade-model.md's GRAVITY_EXPONENT = 1.0 finding in a new place --
##       one playable nation received a per-partner model that was arithmetically
##       the aggregate it replaced, measured at L1 0.000.
##
##       So: for each of the four decisions this model replaces, how far apart are
##       the nine answers? The trigger fires if the cross-nation L1 distance sits
##       below the 0.05 line tools/trade_probe.gd already calls a no-op. If it
##       fires, the response is a MODEL decision -- add a material input, or cut
##       the ideology term further -- and not a tuning one.
##
##   (b) GBR, THE FOURTH TIME. Britain is in no EU pair, borders nothing in the
##       roster, rests at 45 with all nine, pays no bloc transfer and sits on no
##       council. Every ABSOLUTE term it has is at the floor. V1.3b's trigger
##       fired on exactly this shape and V1.3c's inverted; this table asks whether
##       normalising stake per viewer answers it structurally, or whether Britain
##       gets a foreign policy of pure indifference.
##
##   (c) THE COUNCIL RE-SWEEP. V1.3d set SUPPORT_SIGMA = 0.90 and MOVED
##       common_defence_floor's authored position, because clustered ideology could
##       not spread the tallies. The Gaussian is gone and the scale underneath the
##       threshold is signed, so V1.3d's three-column test has to be re-run: some
##       proposals carry without the player, some are theirs to decide, some are
##       lost whatever they do.
##
##   (d) THE CLAMP V1.3c SAID THIS SESSION WOULD REACH. docs/coercion-model.md
##       labels 9 x 1.00 "V1.3e's worst case" and says outright that
##       COERCION_IMPULSE_MAX "binds only once V1.3e gives the other nine agency".
##       With retaliation DECIDED rather than fixed, does anything reach 6.0?
##
## Not a test. tests/test_foreign_policy.gd asserts the invariants; this prints the
## spread a human reads. Kept in tools/ and excluded from run_tests.sh, same as
## balance_probe.gd, bloc_probe.gd, coercion_probe.gd and trade_probe.gd.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const FP = preload("res://src/sim/foreign_policy.gd")
const K = preload("res://src/sim/foreign_policy_constants.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const BK = preload("res://src/sim/bloc_constants.gd")
const Coercion = preload("res://src/sim/coercion.gd")
const CK = preload("res://src/sim/coercion_constants.gd")
const Trade = preload("res://src/sim/trade.gd")
const RK = preload("res://src/core/relations.gd")
const Economy = preload("res://src/sim/economy.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")

## The line tools/trade_probe.gd calls a no-op: below this L1 distance, two
## vectors are the same vector for any purpose the player could read.
const NO_OP_L1 := 0.05

const PLAYABLE := ["FRA", "DEU", "GBR"]

## V1.3f, escalation trigger 1. Acts aimed at the player over fourteen years,
## below which the feature is invisible to that nation. Two rather than one: a
## single act in fourteen years is indistinguishable from an accident.
const REACH_FLOOR := 2

## V1.3f, escalation trigger 2. Share of the ninety directed pairs that may carry
## a live measure at year 14 before the world counts as seized up.
const SATURATION_CEILING := 0.33


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	_spread_table(loader)
	_gbr_table(loader)
	_council_table(loader)
	_clamp_table(loader)
	# V1.3f.
	_agenda_bar_sweep(loader)
	_agenda_domestic_sweep(loader)
	_agenda_shape_table(loader)
	_agenda_run_table(loader)
	_agenda_reach_table(loader)
	_agenda_rank_diagnostic(loader)
	_agenda_saturation_table(loader)
	_agenda_clamp_table(loader)
	_agenda_provoked_table(loader)
	quit(0)


# --- V1.3f: the agenda --------------------------------------------------------------

## Run a fresh game forward `months` with nothing but the systems the agenda needs,
## and hand back the state. Deliberately NOT the full main.gd chain: this measures
## the agenda, and Opinion/Elections would end runs and change the player under it.
func _run_agenda(loader, player_id: String, months: int):
	var state = GameState.new_game(loader, player_id)
	for i in range(months):
		state.month = i % 12 + 1
		state.year = 2026 + i / 12
		Economy.tick_month(state)
		Diplomacy.tick_month(state, loader)
	return state


## Table (d2). AGENDA_ACT_MIN, swept against the real content.
##
## Scored over every ordered pair with the actions data/diplomatic-actions/ actually
## ships, so the bar is set against the verbs the game has rather than against four
## synthetic ones. What the sweep has to find is a bar where the three playable
## nations are all ACTED ON -- Britain included, which is escalation trigger 1 and
## the fifth time this block has been constrained from one side by GBR.
##
## Read at new-game: every pair is at rest, `deepen` is the only open opportunity,
## and that is the hardest case for the bar precisely because it is the quietest
## state the game is ever in.
func _agenda_bar_sweep(loader) -> void:
	print("\n########## (d2) V1.3f: sweeping AGENDA_ACT_MIN against the shipped content ##########")
	print("Best available desire per ordered pair at new-game, over the %d actions in" % loader.diplomatic_actions.size())
	print("data/diplomatic-actions/. `on X` counts how many of the nine could act on X.")
	print("")

	var state = GameState.new_game(loader, "FRA")
	var ids: Array = state.nations.keys()
	ids.sort()

	# best[actor][target] -> score, computed once and re-read at every bar.
	var best := {}
	for a_id in ids:
		best[a_id] = {}
		for b_id in ids:
			if a_id == b_id:
				continue
			var terms := FP.target_terms(state, a_id, String(b_id))
			var top := -999.0
			for action in loader.diplomatic_actions:
				top = maxf(top, FP.desire_from(terms, action.effects))
			best[a_id][b_id] = top

	var header := "  %-6s %8s %8s" % ["bar", "pairs", "of 90"]
	for p in PLAYABLE:
		header += " %7s" % ("on " + p)
	print(header)
	print("  " + "-".repeat(header.length() - 2))

	for bar in [0.00, 0.02, 0.05, 0.10, 0.20, 0.30, 0.50]:
		var live := 0
		var on_player := {}
		for p in PLAYABLE:
			on_player[p] = 0
		for a_id in ids:
			for b_id in ids:
				if a_id == b_id:
					continue
				if float(best[a_id][b_id]) <= bar:
					continue
				live += 1
				if on_player.has(b_id):
					on_player[b_id] = int(on_player[b_id]) + 1
		var line := "  %-6.2f %8d %8s" % [bar, live, "%.0f%%" % (100.0 * live / 90.0)]
		for p in PLAYABLE:
			line += " %7d" % on_player[p]
		print(line)

	print("")
	print("  The GBR column is the constraint. A bar that leaves it at 0 ships a")
	print("  feature one playable nation in three cannot see -- escalation trigger 1.")
	print("")
	print("  Best desire anyone has against each nation, at rest:")
	for b_id in ids:
		var top := -999.0
		var top_actor := ""
		for a_id in ids:
			if a_id == b_id:
				continue
			if float(best[a_id][b_id]) > top:
				top = float(best[a_id][b_id])
				top_actor = String(a_id)
		print("    on %-4s  %.4f  (by %s)" % [b_id, top, top_actor])


## Table (d3). AGENDA_DOMESTIC_WEIGHT, swept on WHICH VERB a nation reaches for.
##
## The constant answers a failure the first model shape did not price at all: with
## only hostile acts costed, the agenda always picked the LARGEST friendly verb,
## because `deepen` scales with the act's own size and a friendly act carried no
## cost of any kind. `settle_dispute` -- the content's climbdown, six blocs at
## -0.09 -- became the ordinary act of every government in Europe.
##
## Swept on the choice rather than on a total, because the choice is what went
## wrong. Recomputed here rather than read from the constant, so the whole column
## is visible instead of only the shipped row.
func _agenda_domestic_sweep(loader) -> void:
	print("\n########## (d3) V1.3f: sweeping AGENDA_DOMESTIC_WEIGHT on verb choice ##########")
	print("Which friendly verb each nation picks against its MOST important partner,")
	print("at new-game. Domestic price is the action's own authored |bloc_offset| sum:")
	print("  state_visit 0.00   bilateral_treaty 0.20   settle_dispute 0.54")
	print("")

	var state = GameState.new_game(loader, "FRA")
	var ids: Array = state.nations.keys()
	ids.sort()

	print("  %-8s %-18s %s" % ["weight", "picked by most", "per-nation picks"])
	print("  " + "-".repeat(70))

	for weight in [0.00, 0.25, 0.50, 0.75, 1.00, 2.00, 4.00]:
		var picks := {}
		for a_id in ids:
			# The actor's largest-stake partner, which is where the biggest verb is
			# most tempting and therefore where the failure shows first.
			var best_partner := ""
			var best_stake := -1.0
			for b_id in ids:
				if a_id == b_id:
					continue
				var s: float = FP.stake(state, String(a_id), String(b_id))
				if s > best_stake:
					best_stake = s
					best_partner = String(b_id)

			var terms := FP.target_terms(state, String(a_id), best_partner)
			var top := K.AGENDA_ACT_MIN
			var top_id := "(nothing)"
			# Availability-filtered, or the table offers verbs the game would never
			# put on the list -- lift_sanctions with no sanctions in force.
			for action in Diplomacy.available(state, loader.diplomatic_actions, String(a_id), best_partner):
				# desire_from() minus the shipped domestic term, plus this row's.
				var base: float = FP.desire_from(terms, action.effects)
				var priced: float = base + (K.AGENDA_DOMESTIC_WEIGHT - weight) * _domestic_price(action.effects)
				if priced > top:
					top = priced
					top_id = action.id
			picks[top_id] = int(picks.get(top_id, 0)) + 1

		var keys: Array = picks.keys()
		keys.sort()
		var winner := ""
		var most := -1
		var detail := ""
		for k in keys:
			detail += "%s x%d  " % [k, picks[k]]
			if int(picks[k]) > most:
				most = int(picks[k])
				winner = String(k)
		print("  %-8.2f %-18s %s" % [weight, winner, detail])

	print("")
	print("  Above the row where settle_dispute stops winning, the concession must")
	print("  still be REACHABLE for a soured pair, or it is unreachable content --")
	print("  docs/amendment-model.md's German two-thirds. Checked in table (f).")


## The same magnitude ForeignPolicy._act_domestic_price() reads, duplicated here
## because that one is private. Kept identical deliberately; if they diverge this
## sweep is measuring a model the game does not run.
func _domestic_price(effects: Dictionary) -> float:
	var total := 0.0
	for value in (effects.get("bloc_offset", {}) as Dictionary).values():
		total += absf(float(value))
	return total


## Table (e). What the model WANTS, before anything has happened.
##
## The three properties V1.3f claims fall out of the arithmetic rather than being
## authored. Each is a place the model is wrong if it does not hold, so they are
## printed as measurements rather than asserted as beliefs.
func _agenda_shape_table(loader) -> void:
	print("\n########## (e) V1.3f: what the agenda wants at new-game ##########")
	print("Every pair sits exactly at rest, so amity is 0.0 for all 45 and the warmth")
	print("term VANISHES. The first acts of a game are therefore decided by interest,")
	print("cost and risk alone -- the world opens material and turns political only")
	print("once somebody has acted. Bar is AGENDA_ACT_MIN %.2f." % K.AGENDA_ACT_MIN)
	print("")

	var state = GameState.new_game(loader, "FRA")
	var ids: Array = state.nations.keys()
	ids.sort()

	var verbs := {
		"state_visit": {"relations": 5.0},
		"condemnation": {"relations": -8.0},
		"tariffs": {"relations": -10.0, "measure": {"op": "impose", "kind": "tariff", "severity": 0.625}},
		"sanctions": {"relations": -18.0, "measure": {"op": "impose", "kind": "sanction", "severity": 1.0}},
	}
	var verb_names: Array = ["state_visit", "condemnation", "tariffs", "sanctions"]

	print("  PROPERTY 1: is a fresh world net-cooperative? Best verb per ordered pair.")
	var friendly := 0
	var hostile := 0
	var nothing := 0
	for a_id in ids:
		for b_id in ids:
			if a_id == b_id:
				continue
			var terms := FP.target_terms(state, a_id, b_id)
			var best_name := ""
			var best := K.AGENDA_ACT_MIN
			for name in verb_names:
				var v: float = FP.desire_from(terms, verbs[name])
				if v > best:
					best = v
					best_name = name
			if best_name == "":
				nothing += 1
			elif best_name == "state_visit":
				friendly += 1
			else:
				hostile += 1
	print("    friendly %d   hostile %d   below the bar %d   (of 90 ordered pairs)" % [
		friendly, hostile, nothing,
	])
	if hostile > friendly:
		print("    >>> a fresh world opens HOSTILE. Cost and risk are not restraining;")
		print("    >>> this is a model reading, not a bar to raise.")
	print("")

	print("  PROPERTY 2: does a small nation decline to sanction a large one?")
	print("  Sanctions score, both directions of the sharpest pair in the roster:")
	for pair in [["FRA", "LUX"], ["LUX", "FRA"], ["DEU", "LUX"], ["LUX", "DEU"]]:
		var t := FP.target_terms(state, pair[0], pair[1])
		print("    %s -> %-4s  sanctions %+.3f   exposure %.2f   risk %.3f" % [
			pair[0], pair[1], FP.desire_from(t, verbs["sanctions"]),
			float(t["exposure"]), float(t["risk"]),
		])
	print("")

	print("  PROPERTY 3: GBR -- the freest actor, and the least deterred against?")
	print("  Mean hostile score BY each playable nation and AGAINST it:")
	for id in PLAYABLE:
		var by_sum := 0.0
		var against_sum := 0.0
		var n := 0
		for other in ids:
			if other == id:
				continue
			by_sum += FP.desire_from(FP.target_terms(state, id, String(other)), verbs["tariffs"])
			against_sum += FP.desire_from(FP.target_terms(state, String(other), id), verbs["tariffs"])
			n += 1
		print("    %-4s  by it %+.3f   against it %+.3f" % [id, by_sum / n, against_sum / n])


## Table (f). What the agenda actually DOES over a played run.
func _agenda_run_table(loader) -> void:
	print("\n########## (f) V1.3f: fourteen years of the agenda ##########")
	print("168 months, Economy + Diplomacy only. Interval %d months, bar %.2f." % [
		K.AGENDA_INTERVAL_MONTHS, K.AGENDA_ACT_MIN,
	])
	print("")

	var state = _run_agenda(loader, "FRA", 168)

	var by_actor := {}
	var by_verb := {}
	var by_reason := {}
	for act in state.foreign_acts:
		by_actor[act["actor_id"]] = int(by_actor.get(act["actor_id"], 0)) + 1
		by_verb[act["action_id"]] = int(by_verb.get(act["action_id"], 0)) + 1
		by_reason[act["reason"]] = int(by_reason.get(act["reason"], 0)) + 1

	print("  NOTE: foreign_acts is capped at AGENDA_ACTS_KEPT = %d, so the counts below" % K.AGENDA_ACTS_KEPT)
	print("  are the TAIL of the run, not its total. Live registers are the whole state.")
	print("")
	print("  verbs used (last %d acts):" % state.foreign_acts.size())
	var verb_keys: Array = by_verb.keys()
	verb_keys.sort()
	for v in verb_keys:
		print("    %-24s %d" % [v, by_verb[v]])
	print("")
	print("  reasons given:")
	var reason_keys: Array = by_reason.keys()
	reason_keys.sort()
	for r in reason_keys:
		print("    %-12s %d" % [r, by_reason[r]])
	print("")
	print("  live state after 168 months:")
	print("    agreements %d of 45 pairs" % state.agreements.size())
	print("    measures   %d of 90 directed pairs" % state.measures.size())


## Every act of a run, not just the tail AGENDA_ACTS_KEPT leaves in the ring.
##
## Collected by reading entries stamped with the month just ticked, which is why
## the record carries year and month at all: the cap would otherwise make a
## fourteen-year count unmeasurable.
func _collect_acts(loader, player_id: String, months: int) -> Array:
	var state = GameState.new_game(loader, player_id)
	var out: Array = []
	for i in range(months):
		state.month = i % 12 + 1
		state.year = 2026 + i / 12
		Economy.tick_month(state)
		Diplomacy.tick_month(state, loader)
		for act in state.foreign_acts:
			if int(act["year"]) == state.year and int(act["month"]) == state.month:
				out.append(act)
			else:
				break
	return out


## Table (g). ESCALATION TRIGGER 1 -- GBR, the fifth time.
##
## The agenda must not special-case the player: docs/engine-decision.md rule 1
## forbids `if nation_id == "FRA"` outright, so how much of the world's foreign
## policy points at YOU has to fall out of stake. FRA and DEU are large and
## depended on; Britain is in no EU pair, borders nothing and is nobody's largest
## partner. If the nine never act on a GBR player, the feature is invisible to one
## playable nation in three -- V1.3b's trigger, V1.3c's, V1.3e's, again.
func _agenda_reach_table(loader) -> void:
	print("\n########## (g) V1.3f: does the world act on YOU? -- ESCALATION TRIGGER 1 ##########")
	print("Fourteen years per playable nation. The floor is %d acts aimed at the player:" % REACH_FLOOR)
	print("below it the session shipped a simulation the player cannot see.")
	print("")

	var fired: Array = []
	for player_id in PLAYABLE:
		var acts := _collect_acts(loader, player_id, 168)
		var at_player := 0
		var first_term := 0
		var by_verb := {}
		for act in acts:
			if String(act["target_id"]) != player_id:
				continue
			at_player += 1
			# A player who sees nothing before their first election has, as far as
			# they are concerned, been shipped no feature at all. Sixty months is the
			# French term, and the shortest horizon that matters.
			if int(act["year"]) < 2031:
				first_term += 1
			by_verb[act["action_id"]] = int(by_verb.get(act["action_id"], 0)) + 1

		var detail := ""
		var vk: Array = by_verb.keys()
		vk.sort()
		for v in vk:
			detail += "%s x%d  " % [v, by_verb[v]]
		print("  %-4s  %3d acts in the world, %2d aimed at the player (%d in the first term)   %s" % [
			player_id, acts.size(), at_player, first_term, detail,
		])
		if at_player < REACH_FLOOR:
			fired.append(player_id)

	print("")
	if fired.is_empty():
		print("Trigger did NOT fire: every playable nation is acted on.")
	else:
		print(">>> TRIGGER FIRED for %s." % [fired])
		print(">>> This is a MODEL decision, not a tuning one. stake() is normalised per")
		print(">>> ACTOR, so nobody's stake in Britain is large -- lowering AGENDA_ACT_MIN")
		print(">>> would saturate the other two rather than fix this one.")


## Table (j). Does the OTHER half of the agenda exist?
##
## An unplayed run produces only `state_visit`, and that is the model working
## rather than failing: amity is exactly 0.0 at new-game for all forty-five pairs,
## so `mend` and `punish` are both closed and only `deepen` is open. A world nobody
## has provoked has nothing to be angry about.
##
## But "correct by construction" is exactly how dead code gets shipped, so this
## sours a pair by hand -- the player doing what a player does -- and asks whether
## the two closed opportunities actually open.
func _agenda_provoked_table(loader) -> void:
	print("\n########## (j) V1.3f: does the hostile half of the agenda exist? ##########")
	print("An unplayed world only ever deepens ties, because amity is 0.0 everywhere")
	print("and `mend`/`punish` are shut. Here the pair is soured by hand first.")
	print("")

	for displacement in [-10.0, -25.0, -40.0]:
		var state = GameState.new_game(loader, "FRA")
		var key := RK.key("FRA", "DEU")
		state.relations[key] = maxf(DK.RELATIONS_MIN, float(state.relations[key]) + displacement)

		var terms := FP.target_terms(state, "DEU", "FRA")
		var best := -99.0
		var best_id := "(nothing)"
		var line := ""
		for action in loader.diplomatic_actions:
			var v: float = FP.desire_from(terms, action.effects)
			if v > K.AGENDA_ACT_MIN:
				line += "%s %.3f  " % [action.id, v]
			if v > best:
				best = v
				best_id = action.id
		print("  FRA|DEU at %+.0f (amity %+.2f) -- DEU's answer: %s (%.3f)" % [
			displacement, float(terms["amity"]), best_id, best,
		])
		if line != "":
			print("      above the bar: %s" % line)

	print("")
	print("  WHO CAN AFFORD TO BE HOSTILE. Every ordered pair driven to full grievance")
	print("  (amity -1.0), impose verbs only -- the two that are actually available at")
	print("  new-game. A pair is listed if a hostile act beats AGENDA_ACT_MIN.")
	print("")
	var probe_state = GameState.new_game(loader, "FRA")
	var ids2: Array = probe_state.nations.keys()
	ids2.sort()
	for pair_key in probe_state.relations.keys():
		probe_state.relations[pair_key] = maxf(DK.RELATIONS_MIN, float(probe_state.relations[pair_key]) - 30.0)

	var hostile_pairs := 0
	var by_actor := {}
	for a_id in ids2:
		for b_id in ids2:
			if a_id == b_id:
				continue
			var t := FP.target_terms(probe_state, String(a_id), String(b_id))
			var top := K.AGENDA_ACT_MIN
			var top_id := ""
			for action in loader.diplomatic_actions:
				if (action.effects.get("measure", {}) as Dictionary).get("op", "") != "impose":
					continue
				var v: float = FP.desire_from(t, action.effects)
				if v > top:
					top = v
					top_id = action.id
			if top_id != "":
				hostile_pairs += 1
				by_actor[a_id] = int(by_actor.get(a_id, 0)) + 1
	print("    %d of 90 ordered pairs can mount a hostile act when fully soured" % hostile_pairs)
	var ak: Array = by_actor.keys()
	ak.sort()
	for a in ak:
		print("      %-4s can coerce %d of its nine" % [a, by_actor[a]])
	if hostile_pairs == 0:
		print("      >>> NOBODY can. The coercion half of the agenda is dead code.")

	print("")
	print("  And over a run, from a soured start:")
	var state2 = GameState.new_game(loader, "FRA")
	for id in state2.nations.keys():
		if id == "FRA":
			continue
		state2.relations[RK.key("FRA", String(id))] = 20.0
	var seen := {}
	for i in range(120):
		state2.month = i % 12 + 1
		state2.year = 2026 + i / 12
		Economy.tick_month(state2)
		Diplomacy.tick_month(state2, loader)
		for act in state2.foreign_acts:
			if int(act["year"]) == state2.year and int(act["month"]) == state2.month:
				seen[act["action_id"]] = int(seen.get(act["action_id"], 0)) + 1
			else:
				break
	var keys: Array = seen.keys()
	keys.sort()
	for k in keys:
		print("    %-24s %d" % [k, seen[k]])
	print("    measures in force at the end: %d" % state2.measures.size())


## Table (g2). WHY Britain is never picked -- the diagnostic behind trigger 1.
##
## Trigger 1 says the response is a model decision. This is what that decision has
## to be made against: not whether GBR clears AGENDA_ACT_MIN, which it does, but
## where it RANKS while it does.
func _agenda_rank_diagnostic(loader) -> void:
	print("\n########## (g2) V1.3f: why is Britain never picked? ##########")
	print("A GBR game. Every other nation's desire against every target, at three")
	print("points in the run, best verb per target. `*` marks the pick that turn.")
	print("")

	var state = GameState.new_game(loader, "GBR")
	var ids: Array = state.nations.keys()
	ids.sort()

	for month in range(0, 61):
		if month == 0 or month == 24 or month == 60:
			print("  --- month %d ---" % month)
			for a_id in ["ITA", "NLD", "ESP"]:
				var line := "    %-4s: " % a_id
				var top := -99.0
				var top_id := ""
				var scores := {}
				for b_id in ids:
					if b_id == a_id:
						continue
					var terms := FP.target_terms(state, String(a_id), String(b_id))
					var best := -99.0
					for action in loader.diplomatic_actions:
						best = maxf(best, FP.desire_from(terms, action.effects))
					scores[b_id] = best
					if best > top:
						top = best
						top_id = String(b_id)
				for b_id in ids:
					if b_id == a_id:
						continue
					line += "%s%s %.3f  " % [
						"*" if b_id == top_id else " ", b_id, scores[b_id],
					]
				print(line)
			print("")
		if month == 60:
			break
		state.month = month % 12 + 1
		state.year = 2026 + month / 12
		Economy.tick_month(state)
		Diplomacy.tick_month(state, loader)


## Table (h). ESCALATION TRIGGER 2 -- saturation.
##
## An agenda that only ever escalates is a ratchet the drift cannot clear, which is
## docs/economy-model.md's IMPULSE_MAX failure with a new name. Measured as the
## share of the ninety directed pairs carrying a live measure at year 14, and as
## whether relations have collapsed onto a clamp.
func _agenda_saturation_table(loader) -> void:
	print("\n########## (h) V1.3f: has the world seized up? -- ESCALATION TRIGGER 2 ##########")
	print("At year 14. Ceiling is %d%% of the 90 directed pairs under measure." % int(SATURATION_CEILING * 100.0))
	print("")

	var fired := false
	for player_id in PLAYABLE:
		var state = _run_agenda(loader, player_id, 168)

		var lo := 999.0
		var hi := -999.0
		var total := 0.0
		var pinned := 0
		for pair_key in state.relations.keys():
			var v := float(state.relations[pair_key])
			lo = minf(lo, v)
			hi = maxf(hi, v)
			total += v
			if v <= DK.RELATIONS_MIN + 0.01 or v >= DK.RELATIONS_MAX - 0.01:
				pinned += 1

		var share: float = float(state.measures.size()) / 90.0
		print("  %-4s  measures %2d/90 (%.0f%%)   agreements %2d/45   relations %.1f..%.1f mean %.1f   pinned %d" % [
			player_id, state.measures.size(), share * 100.0,
			state.agreements.size(), lo, hi, total / 45.0, pinned,
		])
		if share > SATURATION_CEILING or pinned > 0:
			fired = true

	print("")
	if not fired:
		print("Trigger did NOT fire: the world is still moving at year 14.")
	else:
		print(">>> TRIGGER FIRED. The agenda is a ratchet. The response is that")
		print(">>> DE-ESCALATION must score -- the four lift_* verbs already exist and the")
		print(">>> model has to want them -- rather than a smaller AGENDA_ACT_MIN.")


## Table (i). ESCALATION TRIGGER 3 -- the clamp, in REACHABLE play.
##
## docs/coercion-model.md records COERCION_IMPULSE_MAX being found binding in
## reachable play at 4.0 and raised to 6.0; V1.3e then measured a synthetic
## nine-attacker worst case at -4.287 and called it unreached. That was a
## CONSTRUCTED worst case. This one is a game nobody played.
##
## The failure being watched for is the one docs/economy-model.md records for
## IMPULSE_MAX and V1.3c repeated: a clamp rather than the model setting the
## growth rate.
func _agenda_clamp_table(loader) -> void:
	print("\n########## (i) V1.3f: is the coercion clamp binding? -- ESCALATION TRIGGER 3 ##########")
	print("Worst monthly coercion impulse over 168 unplayed months, against")
	print("COERCION_IMPULSE_MAX = %.2f." % CK.COERCION_IMPULSE_MAX)
	print("")

	var fired := false
	for player_id in PLAYABLE:
		var state = GameState.new_game(loader, player_id)
		var worst := 0.0
		var worst_id := ""
		for i in range(168):
			state.month = i % 12 + 1
			state.year = 2026 + i / 12
			Economy.tick_month(state)
			Diplomacy.tick_month(state, loader)
			for id in state.nations.keys():
				var v: float = absf(state.nations[id].coercion_impulse_pct)
				if v > worst:
					worst = v
					worst_id = String(id)
		print("  %-4s player: worst impulse %.3f on %s   (%.0f%% of the clamp)" % [
			player_id, worst, worst_id, 100.0 * worst / CK.COERCION_IMPULSE_MAX,
		])
		if worst >= CK.COERCION_IMPULSE_MAX - 0.001:
			fired = true

	print("")
	if not fired:
		print("Trigger did NOT fire: the clamp has headroom in reachable play.")
	else:
		print(">>> TRIGGER FIRED: the clamp, not the model, is setting the growth rate.")
		print(">>> docs/economy-model.md's IMPULSE_MAX failure, a fourth time.")


## Table (a). THE ESCALATION TRIGGER.
func _spread_table(loader) -> void:
	print("\n########## (a) do the nine actually differ? -- ESCALATION TRIGGER ##########")
	print("Cross-nation L1 between stake vectors. Below %.2f the vectors are the same" % NO_OP_L1)
	print("vector and the session shipped nothing -- docs/trade-model.md's GBR-at-0.000")
	print("finding, in a new place. Ideology weight %.2f against dependence %.2f." % [
		K.STAKE_IDEOLOGY_WEIGHT, K.STAKE_DEPENDENCE_WEIGHT,
	])
	print("")

	var state = GameState.new_game(loader, "FRA")
	var ids: Array = state.nations.keys()
	ids.sort()

	var vectors := {}
	for id in ids:
		vectors[id] = FP.stake_vector(state, id)

	print("Stake vectors at new-game (history term is zero for all 45 pairs by")
	print("construction -- every pair sits exactly at rest until somebody acts):")
	print("")
	var header := "%-6s" % "actor"
	for id in ids:
		header += "%7s" % id
	print(header)
	print("-".repeat(header.length()))
	for a in ids:
		var line := "%-6s" % a
		for b in ids:
			if a == b:
				line += "%7s" % "."
			else:
				line += "%7.3f" % float(vectors[a].get(b, 0.0))
		print(line)

	# Every unordered pair of ACTORS, comparing their views of the eight nations
	# they both see. The self-slot is skipped on both sides, which is what makes
	# this a comparison of foreign policies rather than of dictionary shapes.
	var worst := 999.0
	var best := 0.0
	var total := 0.0
	var count := 0
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a: String = ids[i]
			var b: String = ids[j]
			var l1 := 0.0
			for c in ids:
				if c == a or c == b:
					continue
				l1 += absf(float(vectors[a].get(c, 0.0)) - float(vectors[b].get(c, 0.0)))
			worst = minf(worst, l1)
			best = maxf(best, l1)
			total += l1
			count += 1

	print("")
	print("cross-nation L1 over %d actor pairs:  min %.3f   mean %.3f   max %.3f" % [
		count, worst, total / maxf(1.0, float(count)), best,
	])
	if worst < NO_OP_L1:
		print("")
		print(">>> TRIGGER FIRED: two nations' foreign policies are within %.3f." % NO_OP_L1)
		print(">>> This is a MODEL decision, not a tuning one. Add a material input or")
		print(">>> cut the ideology term; do NOT reach for a weight.")
	else:
		print("")
		print("Trigger did NOT fire: the closest two nations sit %.1fx the no-op line." % (worst / NO_OP_L1))

	_decision_spread(state, ids)


## The same question asked of the three decisions that are not the stake vector
## itself. A spread in stake that does not reach the answers is a spread in
## nothing.
func _decision_spread(state, ids: Array) -> void:
	print("")
	print("Does the spread REACH the decisions? Same state, one question each.")
	print("")

	print("  Retaliation fraction, if FRA imposed severity 1.00 on each (ceiling %.2f):" % CK.RETALIATION_FRACTION)
	var frac_min := 9.0
	var frac_max := 0.0
	for id in ids:
		if id == "FRA":
			continue
		var f: float = FP.retaliation_fraction(state, "FRA", id, CK.RETALIATION_FRACTION)
		frac_min = minf(frac_min, f)
		frac_max = maxf(frac_max, f)
		var answers: String = "answers" if f * 1.0 >= CK.RETALIATION_MIN_SEVERITY else "DOES NOT ANSWER"
		print("    %-4s  %.3f   %s" % [id, f, answers])
	print("    spread %.3f -> %.3f" % [frac_min, frac_max])

	print("")
	print("  ...and the same nine answering LUX, the smallest actor in the roster:")
	for id in ["FRA", "DEU", "GBR"]:
		var f: float = FP.retaliation_fraction(state, "LUX", id, CK.RETALIATION_FRACTION)
		print("    LUX>%-4s answered at %.3f" % [id, f])
	print("")
	print("  The asymmetry this exists for, both directions of one pair:")
	var fra_on_lux: float = FP.retaliation_fraction(state, "FRA", "LUX", CK.RETALIATION_FRACTION)
	var lux_on_fra: float = FP.retaliation_fraction(state, "LUX", "FRA", CK.RETALIATION_FRACTION)
	print("    FRA tariffs LUX -> LUX answers at %.3f" % fra_on_lux)
	print("    LUX tariffs FRA -> FRA answers at %.3f" % lux_on_fra)
	if fra_on_lux > 0.0:
		print("    ratio %.1fx" % (lux_on_fra / fra_on_lux))

	print("")
	print("  Accept score for a standard %.2f-multiplier deal proposed by FRA" % 1.35)
	print("  (bar is ACCEPT_MIN %.2f):" % K.ACCEPT_MIN)
	var terms := {"weight_multiplier": 1.35}
	for id in ids:
		if id == "FRA":
			continue
		var s: float = FP.accept_score(state, "FRA", id, terms)
		print("    %-4s  %+.3f   %s" % [id, s, "signs" if s >= K.ACCEPT_MIN else "refuses"])


## Table (b). GBR, and whether normalisation answers it.
func _gbr_table(loader) -> void:
	print("\n\n########## (b) GBR, the fourth time ##########")
	print("No EU pair, no border in the roster, every pair resting at 45.0, no bloc")
	print("transfer, no council seat. Every ABSOLUTE term Britain has is at the floor.")
	print("V1.3b's trigger fired on this shape; V1.3c's inverted on it.")
	print("")

	var state = GameState.new_game(loader, "GBR")
	var terms := {"weight_multiplier": 1.35}

	print("%-6s %10s %10s %10s   %s" % ["actor", "max stake", "min stake", "max-min", "signs, of 9"])
	print("-".repeat(58))
	for actor in PLAYABLE:
		var vector: Dictionary = FP.stake_vector(state, actor)
		var hi := 0.0
		var lo := 9.0
		var signs := 0
		for id in vector.keys():
			hi = maxf(hi, float(vector[id]))
			lo = minf(lo, float(vector[id]))
			if FP.accept_score(state, actor, String(id), terms) >= K.ACCEPT_MIN:
				signs += 1
		print("%-6s %10.3f %10.3f %10.3f   %d" % [actor, hi, lo, hi - lo, signs])

	print("")
	print("An even share is %.3f. A nation whose max and min both sit on it has no" % FP.even_share(state, "GBR"))
	print("foreign policy at all -- that is the inert reading this table exists to catch.")
	_accept_sweep(loader)

	print("")
	print("GBR's own vector, and its answers:")
	var gbr: Dictionary = FP.stake_vector(state, "GBR")
	var partners: Array = gbr.keys()
	partners.sort()
	for id in partners:
		var s: float = FP.accept_score(state, "GBR", String(id), terms)
		var f: float = FP.retaliation_fraction(state, String(id), "GBR", CK.RETALIATION_FRACTION)
		print("  GBR->%-4s stake %.3f (%.2fx even)  accept %+.3f %-8s  answers %s at %.3f" % [
			id, float(gbr[id]), float(gbr[id]) / FP.even_share(state, "GBR"), s,
			"signs" if s >= K.ACCEPT_MIN else "refuses", id, f,
		])


## The sweep that sets ACCEPT_MIN, and the one the first run of table (b) demanded.
##
## Two failures to avoid at once, and they pull in opposite directions:
##   TOO LOW  -- every partner signs with everybody, the gate is decorative, and
##               an agreement's difficulty is carried by nothing at all.
##   TOO HIGH -- one playable nation in three cannot sign anything, which is
##               docs/trade-model.md's own GBR trigger and docs/amendment-model.md's
##               unreachable German two-thirds.
##
## The shipped value has to leave all three playable nations able to sign SOME
## partners and not ALL of them at rest, and it has to leave the ones they cannot
## reach REACHABLE by relations work rather than closed. `+10` is one
## settle_dispute, the strongest single positive verb in the content.
func _accept_sweep(loader) -> void:
	print("")
	print("ACCEPT_MIN sweep. `rest` is partners who sign at new-game; `+10` is after")
	print("one settle_dispute on every pair. Want: neither 0 nor 9 at rest, and +10")
	print("strictly above rest -- a gate that relations work can actually open.")
	print("")
	var header := "%10s" % "ACCEPT_MIN"
	for actor in PLAYABLE:
		header += "%14s" % ("%s rest/+10" % actor)
	print(header)
	print("-".repeat(header.length()))

	var terms := {"weight_multiplier": 1.35}
	for bar in [0.00, 0.30, 0.60, 0.90, 1.20, 1.50, 1.80, 2.10]:
		var line := "%10.2f" % bar
		for actor in PLAYABLE:
			var at_rest := 0
			var lifted := 0
			var state = GameState.new_game(loader, actor)
			for id in state.nations.keys():
				if id == actor:
					continue
				if FP.accept_score(state, actor, String(id), terms) >= bar:
					at_rest += 1
			# Every pair the actor is in, lifted by one settle_dispute's +10.
			for id in state.nations.keys():
				if id == actor:
					continue
				var k := RK.key(actor, String(id))
				state.relations[k] = float(state.relations[k]) + 10.0
			for id in state.nations.keys():
				if id == actor:
					continue
				if FP.accept_score(state, actor, String(id), terms) >= bar:
					lifted += 1
			line += "%14s" % ("%d / %d" % [at_rest, lifted])
		var mark: String = "   <-- shipped" if is_equal_approx(bar, K.ACCEPT_MIN) else ""
		print(line + mark)


## Table (c). V1.3d's three-column test, re-run against the new scale.
func _council_table(loader) -> void:
	print("\n\n########## (c) the council re-sweep ##########")
	print("V1.3d's own test, re-run: a council the player always wins is a rubber stamp")
	print("and one it always loses is a scripted event. SUPPORT_THRESHOLD is swept")
	print("because the scale beneath it changed sign -- V1.3d's Gaussian was (0, 1].")
	print("")

	var state = GameState.new_game(loader, "FRA")
	# v3.2a folded bloc.gd into orgs.gd: the council is the "eu" org's, and its
	# proposals are the ones that org tables.
	var members: Array = Orgs.members(state, "eu")
	var proposals: Array = loader.bloc_proposals.filter(func(p) -> bool: return p.org_id == "eu")
	var seats_total := 0
	for id in members:
		seats_total += Orgs.ep_seats(state, loader, id)
	var player_seats: int = Orgs.ep_seats(state, loader, "FRA")

	print("France holds %d of %d member seats. %.0f%% of seats CAST carries." % [
		player_seats, seats_total, BK.PASS_SEAT_FRACTION * 100.0,
	])
	print("")
	# Two criteria, swept together rather than one after the other. V1.3d swept only
	# the first and its abstention property came out of the shipped content by luck;
	# a threshold that balances the three columns and leaves abstention
	# indistinguishable from opposition has shipped a vote option with two outcomes.
	var bar_full_s: float = BK.PASS_SEAT_FRACTION * float(seats_total)
	var bar_abstain_s: float = BK.PASS_SEAT_FRACTION * float(seats_total - player_seats)
	print("`abstain` counts proposals where the other eight land in [%.0f, %.0f)," % [bar_abstain_s, bar_full_s])
	print("which is the only place abstaining and opposing differ.")
	print("")
	print("%10s %10s %14s %12s %10s" % ["threshold", "carried", "player decides", "lost anyway", "abstain"])
	print("-".repeat(60))

	for threshold in [-0.20, -0.10, 0.00, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.40]:
		var carried := 0
		var decides := 0
		var lost := 0
		var abstain_hits := 0
		for p in proposals:
			var others_for := 0
			for id in members:
				if id == "FRA":
					continue
				if Orgs.support(state, state.nations[id], p) >= threshold:
					others_for += Orgs.ep_seats(state, loader, id)
			if float(others_for) >= bar_abstain_s and float(others_for) < bar_full_s:
				abstain_hits += 1
			# The threshold is a share of the seats CAST. There is no abstention
			# among the eight, so every one of them casts and the denominator is the
			# whole council whichever way the player votes -- it shrinks only when
			# the PLAYER abstains, which is the constructive abstention V1.3d built.
			var passes_against: bool = float(others_for) >= BK.PASS_SEAT_FRACTION * float(seats_total)
			var passes_for: bool = float(others_for + player_seats) >= BK.PASS_SEAT_FRACTION * float(seats_total)
			if passes_against:
				carried += 1
			elif passes_for:
				decides += 1
			else:
				lost += 1
		var mark: String = "  <-- shipped" if is_equal_approx(threshold, BK.SUPPORT_THRESHOLD) else ""
		print("%10.2f %10d %14d %12d %10d%s" % [threshold, carried, decides, lost, abstain_hits, mark])

	# Constructive abstention has a WINDOW, and V1.3d never printed it. Abstaining
	# removes the player from the denominator, so it differs from opposing only
	# when the other eight land between the two bars below. A council in which no
	# proposal lands there has three vote options and two outcomes.
	var bar_full: float = BK.PASS_SEAT_FRACTION * float(seats_total)
	var bar_abstain: float = BK.PASS_SEAT_FRACTION * float(seats_total - player_seats)
	print("")
	print("Constructive abstention needs the other eight to land in [%.0f, %.0f)." % [bar_abstain, bar_full])
	print("Below it, nothing France does helps; above it, it carries whatever France does.")
	print("")
	print("%-26s %10s   %s" % ["proposal", "others for", "in the window?"])
	print("-".repeat(56))
	for p in proposals:
		var others_for := 0
		for id in members:
			if id == "FRA":
				continue
			if Orgs.support(state, state.nations[id], p) >= BK.SUPPORT_THRESHOLD:
				others_for += Orgs.ep_seats(state, loader, id)
		var inside: bool = float(others_for) >= bar_abstain and float(others_for) < bar_full
		print("%-26s %10d   %s" % [p.id, others_for, "YES" if inside else "no"])

	print("")
	print("Per-member appraisal at the shipped threshold %.2f, which is what V1.3d" % BK.SUPPORT_THRESHOLD)
	print("could not print: the SAME proposal priced by each member's own books.")
	for p in proposals:
		print("")
		print("  %s (transfer %+.2f%% GDP, constraint %s)" % [
			p.id, p.transfer_pct_gdp,
			"none" if p.constraint.is_empty() else String(p.constraint["field"]),
		])
		for id in members:
			var s: float = Orgs.support(state, state.nations[id], p)
			print("    %-4s %+.3f  %-18s %s" % [
				id, s, Orgs.vote_reason(state, state.nations[id], p),
				"FOR" if s >= BK.SUPPORT_THRESHOLD else "against",
			])


## Table (d). The clamp V1.3c booked to this session.
func _clamp_table(loader) -> void:
	print("\n\n########## (d) does decided retaliation reach the clamp? ##########")
	print("docs/coercion-model.md: 9 x 1.00 is \"V1.3e's worst case\" and the clamp")
	print("\"binds only once V1.3e gives the other nine agency\". COERCION_IMPULSE_MAX")
	print("is %.2f. A guard rail setting the growth rate is the failure this model" % CK.COERCION_IMPULSE_MAX)
	print("exists to avoid, and docs/economy-model.md records it committed three times.")
	print("")
	print("%-6s %12s %14s %12s   %s" % ["actor", "answers", "sum severity", "impulse", "on the clamp?"])
	print("-".repeat(66))

	for actor in PLAYABLE:
		var state = GameState.new_game(loader, actor)

		# The worst thing the player can do: full severity against all nine, every
		# one of which then decides for itself how hard to answer.
		for id in state.nations.keys():
			if id == actor:
				continue
			state.measures[RK.directed_key(actor, String(id))] = {
				"action_id": "probe", "action_name": "Probe", "kind": "sanction",
				"severity": CK.MAX_MEASURE_SEVERITY,
				"since_year": state.year, "since_month": state.month, "retaliated": true,
			}

		var answers := 0
		var total := 0.0
		for id in state.nations.keys():
			if id == actor:
				continue
			var f: float = FP.retaliation_fraction(state, actor, String(id), CK.RETALIATION_FRACTION)
			var severity: float = CK.MAX_MEASURE_SEVERITY * f
			if severity < CK.RETALIATION_MIN_SEVERITY:
				continue
			answers += 1
			total += severity
			state.measures[RK.directed_key(String(id), actor)] = {
				"action_id": "retaliation", "action_name": "Retaliation", "kind": "sanction",
				"severity": severity,
				"since_year": state.year, "since_month": state.month, "retaliated": true,
			}

		var ns = state.nations[actor]
		var impulse: float = Coercion.impulse(
			state, ns, Trade.weights_before_measures(state, actor)
		)
		var on_clamp: bool = absf(absf(impulse) - CK.COERCION_IMPULSE_MAX) < 0.001
		print("%-6s %12d %14.3f %12.3f   %s" % [
			actor, answers, total, impulse, "YES -- RAISE IT" if on_clamp else "no",
		])

	print("")
	print("V1.3c measured 9 x 1.00 at exactly -6.000, ON the clamp, against a fixed")
	print("mirror that answered every time. The question here is whether a DECIDED")
	print("answer still gets there -- a target that declines to answer contributes")
	print("nothing, and the small dependent nations are exactly the ones that decline.")
