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
const Bloc = preload("res://src/sim/bloc.gd")
const BK = preload("res://src/sim/bloc_constants.gd")
const Coercion = preload("res://src/sim/coercion.gd")
const CK = preload("res://src/sim/coercion_constants.gd")
const Trade = preload("res://src/sim/trade.gd")
const RK = preload("res://src/core/relations.gd")

## The line tools/trade_probe.gd calls a no-op: below this L1 distance, two
## vectors are the same vector for any purpose the player could read.
const NO_OP_L1 := 0.05

const PLAYABLE := ["FRA", "DEU", "GBR"]


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
	quit(0)


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
	print("An even share is %.3f. A nation whose max and min both sit on it has no" % K.EVEN_SHARE)
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
			id, float(gbr[id]), float(gbr[id]) / K.EVEN_SHARE, s,
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
	var members: Array = Bloc.members(state, loader)
	var seats_total := 0
	for id in members:
		seats_total += loader.eu.ep_seats(id)
	var player_seats: int = loader.eu.ep_seats("FRA")

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
		for p in loader.bloc_proposals:
			var others_for := 0
			for id in members:
				if id == "FRA":
					continue
				if Bloc.support(state, state.nations[id], p) >= threshold:
					others_for += loader.eu.ep_seats(id)
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
	for p in loader.bloc_proposals:
		var others_for := 0
		for id in members:
			if id == "FRA":
				continue
			if Bloc.support(state, state.nations[id], p) >= BK.SUPPORT_THRESHOLD:
				others_for += loader.eu.ep_seats(id)
		var inside: bool = float(others_for) >= bar_abstain and float(others_for) < bar_full
		print("%-26s %10d   %s" % [p.id, others_for, "YES" if inside else "no"])

	print("")
	print("Per-member appraisal at the shipped threshold %.2f, which is what V1.3d" % BK.SUPPORT_THRESHOLD)
	print("could not print: the SAME proposal priced by each member's own books.")
	for p in loader.bloc_proposals:
		print("")
		print("  %s (transfer %+.2f%% GDP, constraint %s)" % [
			p.id, p.transfer_pct_gdp,
			"none" if p.constraint.is_empty() else String(p.constraint["field"]),
		])
		for id in members:
			var s: float = Bloc.support(state, state.nations[id], p)
			print("    %-4s %+.3f  %-18s %s" % [
				id, s, Bloc.vote_reason(state, state.nations[id], p),
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
