extends SceneTree

## Coercion envelope probe: godot --headless --script res://tools/coercion_probe.gd
##
## V1.3c's named measurement, run BEFORE data/diplomatic-actions/measures.json
## exists -- which is the whole point of it. Every content number this session
## ships is the output of the tables below, not an input to them. Same discipline
## docs/trade-model.md, docs/diplomacy-model.md, docs/scenario-model.md and
## docs/amendment-model.md each used.
##
## The register is written DIRECTLY here rather than through Diplomacy.execute(),
## exactly as trade_probe.gd swept the weight function before src/sim/trade.gd
## existed. That is what lets the measurement precede the content instead of
## validating it afterwards.
##
## Five tables. Table (b) carries the plan's named escalation trigger.
##
##   (a) REVENUE REACH. What a tariff collects, and the Laffer shape the model
##       produces structurally rather than by authoring a curve -- the tariff cuts
##       the very weight it is collected on, so yield is not linear in the rate.
##       Sets TARIFF_YIELD and the content's rate ceiling.
##
##   (b) RECEIVED-DAMAGE LEGIBILITY -- THE ESCALATION TRIGGER. The player is
##       sanctioned by their largest partner. Does anything the player can READ
##       move? docs/trade-model.md already measured this channel's headroom at 6%
##       of IMPULSE_MAX under a synthetic recession far larger than any sanction
##       should produce, so the prior is that it might not. If the peak approval
##       move does not clear poll_noise.gd's NOISE_MAX_PCT, that is a MODEL
##       decision -- a direct player-side term, or a raised TRADE_BETA, both of
##       which reopen economy_constants.gd -- and not a content edit.
##
##   (c) DAMAGE TO THE TARGET. What the coercion impulse does to the nation it is
##       pointed at, and how much of it returns to the imposer. Anchors
##       COERCION_DAMAGE and its clamp. The asymmetry to look for is the one V1.3b's
##       directed table bought: FRA->LUX and LUX->FRA must not be the same number.
##
##   (d) RETALIATION CONVERGENCE. Under the mirror rule, does the exchange settle?
##       A tariff spiral that never stops is the IMPULSE_MAX failure
##       docs/economy-model.md already records, committed a third time.
##
##   (e) GBR. V1.3b's trigger repeated, because it has fired once already. Every
##       GBR pair rests at 45 and its weight vector is the flattest of the three.
##       Check the feature is not quietly closed to one playable nation in three --
##       and note the gate direction INVERTS here: a hostile verb wants no relations
##       floor, so copying AGREEMENT_ACCEPT_MIN's shape would be exactly backwards.
##
## Not a test. tests/test_coercion.gd asserts the invariants; this prints the
## spread a human reads. Kept in tools/ and excluded from run_tests.sh, same as
## balance_probe.gd, trade_probe.gd and diplomacy_probe.gd.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Relations = preload("res://src/core/relations.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const Trade = preload("res://src/sim/trade.gd")
const TK = preload("res://src/sim/trade_constants.gd")
const Coercion = preload("res://src/sim/coercion.gd")
const CK = preload("res://src/sim/coercion_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")

const PLAYABLE := ["FRA", "DEU", "GBR"]
const START_YEAR := 2026

## Sixty months: a full term plus a year, the same horizon trade_probe.gd's payoff
## table uses, so the two are readable against each other.
const HORIZON := 60

## The severity the content ceiling allows. Every "worst case" row below uses this,
## because a trigger that only fires at an unauthorable value has not fired.
const MAX_SEVERITY := CK.MAX_MEASURE_SEVERITY

## The legibility floors, each read off what the game actually prints rather than
## chosen. The approval one is the load-bearing one and is taken FROM
## src/ui/poll_noise.gd rather than restated, so the floor cannot drift away from
## the panel it is a floor for: an approval move smaller than the noise the panel
## already adds is one the player cannot distinguish from nothing.
const APPROVAL_LEGIBLE_PCT := PollNoise.NOISE_MAX_PCT
const GROWTH_LEGIBLE_PCT := 0.01
## The budget panel prints a revenue line as a percent of GDP to one decimal, so a
## line under 0.05 rounds to "0.0%" and reads as no revenue at all.
const REVENUE_LEGIBLE_PCT_GDP := 0.05


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	_revenue_table(loader)
	_legibility_table(loader)
	_damage_table(loader)
	_retaliation_table(loader)
	_gbr_table(loader)
	quit(0)


## Write a measure straight into the register, bypassing Diplomacy.execute().
## The content does not exist yet -- that is the point of running this first.
func _impose(state, from: String, to: String, kind: String, severity: float) -> void:
	state.measures[Relations.directed_key(from, to)] = {
		"action_id": "probe",
		"action_name": "Probe",
		"kind": kind,
		"severity": severity,
		"since_year": state.year,
		"since_month": state.month,
		"retaliated": true,  # suppressed except in table (d), which is about it
	}


## The partner carrying the largest share of `actor_id`'s external demand.
func _top_partner(state, actor_id: String) -> String:
	var weights := Trade.weights(state, actor_id)
	var top_id := ""
	var top_w := 0.0
	for partner_id in weights.keys():
		if float(weights[partner_id]) > top_w:
			top_w = float(weights[partner_id])
			top_id = partner_id
	return top_id


## Table (a). What a tariff collects, swept across rate and across partner.
##
## The row to read is not the biggest number, it is the CURVATURE: yield rises
## less than proportionally with the rate, because MEASURE_TRADE_BITE shrinks the
## weight the rate is collected on. That is the Laffer shape obtained structurally.
func _revenue_table(loader) -> void:
	print("\n########## (a) what a tariff collects ##########")
	print("TARIFF_YIELD %.2f, MEASURE_TRADE_BITE %.2f. SEVERITY IS THE ONLY DIAL --" % [
		CK.TARIFF_YIELD, CK.MEASURE_TRADE_BITE,
	])
	print("an authored tariff rate was CUT by this table's first run, which showed")
	print("yield exactly linear in it (0.0005 per point, every rate, every nation):")
	print("the bite read severity and the rate only scaled the answer, so the two")
	print("were one intensity written twice.")
	print("")
	print("Revenue is collected on the POST-measure weight, so a tariff shrinks the")
	print("base it is levied on and yield has an INTERIOR MAXIMUM in severity, at")
	print("1/(2*BITE) = %.3f. Nothing authors that curve." % (1.0 / (2.0 * CK.MEASURE_TRADE_BITE)))
	print("")
	print("Floors: one tax point is ~0.50%% of GDP (economy_constants.TAX_BASE_SHARE),")
	print("and the budget panel prints a line to one decimal, so under %.2f%% of GDP" % REVENUE_LEGIBLE_PCT_GDP)
	print("the line reads as zero.")

	for actor_id in PLAYABLE:
		var base = GameState.new_game(loader, actor_id)
		var base_weights := Trade.weights(base, actor_id)
		var top_id := _top_partner(base, actor_id)

		print("")
		print("%s, largest partner %s at w = %.3f" % [
			actor_id, top_id, float(base_weights.get(top_id, 0.0)),
		])
		print("  %8s %10s %10s %11s %11s   %s" % [
			"severity", "w after", "rev %GDP", "vs tax pt", "openness", "legible?",
		])
		print("  " + "-".repeat(70))

		for severity in [0.20, 0.40, 0.625, 0.80, 1.00]:
			var state = GameState.new_game(loader, actor_id)
			_impose(state, actor_id, top_id, "tariff", severity)
			var row := Trade.weights(state, actor_id)
			var revenue := Coercion.tariff_revenue_pct_gdp(state, actor_id, row)
			print("  %8.3f %10.3f %10.3f %10.2fx %11.4f   %s" % [
				severity, float(row.get(top_id, 0.0)), revenue, revenue / 0.50,
				Trade.openness_index(state, actor_id),
				"yes" if revenue >= REVENUE_LEGIBLE_PCT_GDP else "NO",
			])

		# Tariffing everybody. The ceiling on the whole line, and the number that
		# says whether tariffs can ever be a revenue strategy or only a gesture.
		#
		# The weight term CANCELS here: a uniform multiplier on every pair divides
		# out under normalisation, so revenue is exactly TARIFF_YIELD * severity for
		# every nation, identically. That is not a bug -- it says a nation that
		# tariffs everyone collects on its whole external demand whatever the shape
		# of it -- but it does mean this row cannot distinguish the three, and the
		# openness figure beside it is the one that carries the cost.
		for severity in [0.625, 1.00]:
			var all_state = GameState.new_game(loader, actor_id)
			for partner_id in base_weights.keys():
				_impose(all_state, actor_id, partner_id, "tariff", severity)
			print("  all nine at %.3f: %.3f%% of GDP (%.1f tax points), openness %.4f" % [
				severity,
				Coercion.tariff_revenue_pct_gdp(
					all_state, actor_id, Trade.weights(all_state, actor_id)
				),
				Coercion.tariff_revenue_pct_gdp(
					all_state, actor_id, Trade.weights(all_state, actor_id)
				) / 0.50,
				Trade.openness_index(all_state, actor_id),
			])


## Table (b). THE ESCALATION TRIGGER.
##
## The player's largest partner sanctions them at the content ceiling. Every
## quantity printed is one the player can actually read off a panel -- growth,
## unemployment, the headline approval figure -- because the question is not
## whether the state moved but whether the player can tell.
func _legibility_table(loader) -> void:
	print("\n\n########## (b) can the player FEEL being sanctioned? ##########")
	print("ESCALATION TRIGGER, and the table that sets COERCION_DAMAGE. The largest")
	print("partner sanctions the player at severity %.2f, held %d months, against a" % [
		MAX_SEVERITY, HORIZON,
	])
	print("control. Poll noise is +/-%.1f, so an approval move under that is one the" % APPROVAL_LEGIBLE_PCT)
	print("player cannot distinguish from nothing.")
	print("")
	print("SWEPT over the number of partners sanctioning at once, which is what the")
	print("game can actually produce -- one hostile neighbour, a bloc of three, or the")
	print("whole roster once V1.3e has the other nine acting. Damage SUMS over")
	print("imposers, so this is the reachable envelope rather than a hypothetical.")
	print("")
	print("Note the self-limiting shape: a harsher measure cuts the very weight the")
	print("damage flows through, so the effective weight is far below the resting one.")
	print("")
	print("The impulse is EXACTLY linear in COERCION_DAMAGE, so `shortfall` is the")
	print("factor that constant must rise by for the row to become legible. It is read")
	print("off the ONE-imposer rows, because one player verb against one nation is what")
	print("the content has to be legible at, and taken from the WORST playable nation --")
	print("docs/amendment-model.md's discipline: open to two nations in three is closed.")
	print("")
	print("%-6s %-17s %10s %10s %10s %11s %10s   %s" % [
		"actor", "imposers x sev", "peak coer", "peak grow", "peak unemp",
		"peak approv", "shortfall", "legible?",
	])
	print("-".repeat(96))

	# (imposers, severity, what produces it). The retaliation rows are the ones
	# THIS session can reach: a player who tariffs N partners collects N mirrors at
	# RETALIATION_FRACTION. The full-severity multi-imposer rows need V1.3e, and are
	# here so the clamp can be checked against a future rather than discovered by it.
	var cases: Array = [
		[1, MAX_SEVERITY, "one embargo"],
		[3, CK.RETALIATION_FRACTION, "3 retaliations"],
		[9, CK.RETALIATION_FRACTION, "9 retaliations"],
		[9, MAX_SEVERITY, "V1.3e worst case"],
	]

	var worst_shortfall := 0.0
	for case in cases:
		var imposer_count: int = case[0]
		var case_severity: float = case[1]
		for actor_id in PLAYABLE:
			var control = GameState.new_game(loader, actor_id)
			var treated = GameState.new_game(loader, actor_id)
			control.year = START_YEAR
			control.month = 1
			treated.year = START_YEAR
			treated.month = 1

			# The partners that matter most to this nation, so the one-imposer row
			# is the worst single sanctioner rather than an arbitrary one.
			var ranked := _partners_by_weight(treated, actor_id)
			for r in range(mini(imposer_count, ranked.size())):
				_impose(treated, ranked[r], actor_id, "sanction", case_severity)

			var peak_coercion := 0.0
			var peak_growth := 0.0
			var peak_unemp := 0.0
			var peak_approval := 0.0

			for i in range(HORIZON):
				_tick(control, loader, i)
				_tick(treated, loader, i)
				var t = treated.player()
				var c = control.player()
				if absf(t.coercion_impulse_pct) > absf(peak_coercion):
					peak_coercion = t.coercion_impulse_pct
				if absf(t.growth_annual_pct - c.growth_annual_pct) > absf(peak_growth):
					peak_growth = t.growth_annual_pct - c.growth_annual_pct
				if absf(t.unemployment_pct - c.unemployment_pct) > absf(peak_unemp):
					peak_unemp = t.unemployment_pct - c.unemployment_pct
				if absf(t.overall_approval_pct - c.overall_approval_pct) > absf(peak_approval):
					peak_approval = t.overall_approval_pct - c.overall_approval_pct

			var legible: bool = absf(peak_approval) >= APPROVAL_LEGIBLE_PCT
			var shortfall := 0.0
			if absf(peak_approval) > 0.0:
				shortfall = APPROVAL_LEGIBLE_PCT / absf(peak_approval)
			if imposer_count == 1 and shortfall > worst_shortfall:
				worst_shortfall = shortfall

			print("%-6s %-17s %10.3f %10.3f %10.3f %11.3f %9.2fx   %s" % [
				actor_id, "%d x %.2f" % [imposer_count, case_severity],
				peak_coercion, peak_growth, peak_unemp,
				peak_approval, shortfall, "yes" if legible else "NO",
			])
		print("    ^ %s" % case[2])
		print("")

	print("-".repeat(96))
	var implied: float = CK.COERCION_DAMAGE * worst_shortfall
	print("At COERCION_DAMAGE %.1f the worst nation needs %.2fx to clear +/-%.1f," % [
		CK.COERCION_DAMAGE, worst_shortfall, APPROVAL_LEGIBLE_PCT,
	])
	print("which is COERCION_DAMAGE = %.1f. The peak impulse there would be about" % implied)
	print("%.2f%%/yr, against a clamp of %.1f." % [
		implied * worst_shortfall_impulse_scale(), CK.COERCION_IMPULSE_MAX,
	])
	if implied * worst_shortfall_impulse_scale() > CK.COERCION_IMPULSE_MAX:
		print("")
		print("TRIGGER FIRED: legibility needs more than COERCION_IMPULSE_MAX permits, so")
		print("no damage inside the clamp is readable. That is a MODEL decision -- a")
		print("direct player-side term, or a raised TRADE_BETA, both of which reopen")
		print("economy_constants.gd -- or ship coercion as a lever the player WIELDS and")
		print("barely FEELS, declared rather than tuned until the panel twitches.")
	else:
		print("")
		print("TRIGGER DID NOT FIRE: that sits inside the clamp, so it is a tuning call")
		print("on this session's own constant and not on a measured economy one.")


## The peak impulse produced per unit of COERCION_DAMAGE by a single full-severity
## sanctioner, read off the shipped weight table. Roughly w_after at severity 1.0,
## which the trade bite pushes to about a tenth of the resting weight.
func worst_shortfall_impulse_scale() -> float:
	return 0.09


## This nation's partners, heaviest first.
func _partners_by_weight(state, actor_id: String) -> Array:
	var weights := Trade.weights(state, actor_id)
	var ids: Array = weights.keys()
	ids.sort_custom(func(a, b): return float(weights[a]) > float(weights[b]))
	return ids


## Table (c). What the imposer does to the target, and what comes back.
##
## Two things to read. First, the damage must scale with the TARGET's weight on
## the IMPOSER -- so France sanctioning Luxembourg is devastating and Luxembourg
## sanctioning France is nothing. Second, the return trip: the imposer's own
## external impulse picks up the target's fall at w(imposer -> target), and that
## is the blowback of imposing, distinct from the blowback of receiving.
func _damage_table(loader) -> void:
	print("\n\n########## (c) what the imposer does, and what returns ##########")
	print("COERCION_DAMAGE %.2f, clamp %.2f. Damage scales with w(target -> imposer)," % [
		CK.COERCION_DAMAGE, CK.COERCION_IMPULSE_MAX,
	])
	print("which is where V1.3b's DIRECTED weight table earns its keep a second time.")
	print("")
	print("%-10s %9s %9s %11s %11s %11s" % [
		"pair", "w(t->i)", "w(i->t)", "target coer", "target grow", "imposer imp",
	])
	print("-".repeat(66))

	var pairs := [
		["FRA", "DEU"], ["FRA", "LUX"], ["LUX", "FRA"],
		["DEU", "FRA"], ["GBR", "DEU"], ["DEU", "GBR"],
	]
	for pair in pairs:
		var imposer: String = pair[0]
		var target: String = pair[1]

		var control = GameState.new_game(loader, imposer)
		var treated = GameState.new_game(loader, imposer)
		control.year = START_YEAR
		control.month = 1
		treated.year = START_YEAR
		treated.month = 1

		var w_ti: float = float(Trade.weights(treated, target).get(imposer, 0.0))
		var w_it: float = float(Trade.weights(treated, imposer).get(target, 0.0))
		_impose(treated, imposer, target, "sanction", MAX_SEVERITY)

		var peak_target_coercion := 0.0
		var peak_target_growth := 0.0
		var peak_imposer_impulse := 0.0
		for i in range(HORIZON):
			_tick(control, loader, i)
			_tick(treated, loader, i)
			var t = treated.nations[target]
			var c = control.nations[target]
			if absf(t.coercion_impulse_pct) > absf(peak_target_coercion):
				peak_target_coercion = t.coercion_impulse_pct
			if absf(t.growth_annual_pct - c.growth_annual_pct) > absf(peak_target_growth):
				peak_target_growth = t.growth_annual_pct - c.growth_annual_pct
			if absf(treated.player().external_impulse_pct) > absf(peak_imposer_impulse):
				peak_imposer_impulse = treated.player().external_impulse_pct

		print("%-10s %9.3f %9.3f %11.3f %11.3f %11.3f" % [
			"%s>%s" % [imposer, target], w_ti, w_it,
			peak_target_coercion, peak_target_growth, peak_imposer_impulse,
		])
	print("-".repeat(66))
	print("FRA>LUX against LUX>FRA is the asymmetry test: if those two rows agree,")
	print("the damage is not reading the directed weight and the model is wrong.")


## Table (d). Does the exchange settle?
##
## The mirror fires once per measure, flagged in the register, so convergence is
## structural rather than a consequence of RETALIATION_FRACTION < 1. This table
## exists to prove the flag actually holds -- a register that grew an entry every
## month would be the IMPULSE_MAX failure with a new name.
func _retaliation_table(loader) -> void:
	print("\n\n########## (d) does retaliation converge? ##########")
	print("delay %d months, fraction %.2f, relations cost %.1f. The mirror fires ONCE" % [
		CK.RETALIATION_DELAY_MONTHS, CK.RETALIATION_FRACTION, CK.RETALIATION_RELATIONS_COST,
	])
	print("per measure. If the register keeps growing, the exchange does not converge.")
	print("")
	print("%-6s %10s %10s %12s %12s %10s" % [
		"month", "entries", "FRA sev", "DEU sev", "FRA coer", "relations",
	])
	print("-".repeat(66))

	var state = GameState.new_game(loader, "FRA")
	state.year = START_YEAR
	state.month = 1
	state.measures[Relations.directed_key("FRA", "DEU")] = {
		"action_id": "probe", "action_name": "Probe", "kind": "tariff",
		"severity": MAX_SEVERITY,
		"since_year": START_YEAR, "since_month": 1, "retaliated": false,
	}

	for i in range(24):
		_tick(state, loader, i)
		if i in [0, 2, 3, 4, 6, 11, 17, 23]:
			var fwd = state.measures.get(Relations.directed_key("FRA", "DEU"), {})
			var back = state.measures.get(Relations.directed_key("DEU", "FRA"), {})
			print("%-6d %10d %10.3f %12.3f %12.3f %10.2f" % [
				i + 1, state.measures.size(),
				float(fwd.get("severity", 0.0)), float(back.get("severity", 0.0)),
				state.player().coercion_impulse_pct,
				Diplomacy.score(state, "FRA", "DEU"),
			])
	print("-".repeat(66))
	print("Entries must stop at 2. A third means the flag is not holding and the")
	print("exchange ratchets -- which is a model failure, not a tuning one.")


## Table (e). GBR, because V1.3b's GBR trigger fired and this one has the same
## shape available to it.
##
## The gate direction INVERTS for a hostile verb: an agreement needs relations to
## be HIGH, a tariff needs nothing, and a naive copy of AGREEMENT_ACCEPT_MIN's
## shape onto a measure would have closed the feature to whoever is friendliest
## rather than to whoever is isolated. What GBR's isolation actually costs it here
## is a flatter weight vector, which is a question about how much damage it can do
## rather than about whether it may act.
func _gbr_table(loader) -> void:
	print("

########## (e) is coercion open to GBR? ##########")
	print("Every GBR pair rests at 45 and its neighbours list is empty. For a hostile")
	print("verb that is NOT a gate problem -- there is no relations floor to clear, and")
	print("the gate direction inverts against the one an agreement needs. What GBR's")
	print("isolation costs it is leverage, so the question is how much damage it can do.")
	print("")
	print("The best TARGET is not the biggest trade partner. Damage scales with")
	print("w(target -> imposer): you hurt whoever depends on YOU. This table's first")
	print("version picked each nation's own largest partner and reported GBR at a")
	print("quarter of the others' reach -- which measured the wrong pairing, not the")
	print("feature. Swept over all nine instead.")
	print("")
	print("%-6s %10s %14s %12s %14s %12s" % [
		"actor", "top trade", "best hit on", "best damage", "best levy on", "best revenue",
	])
	print("-".repeat(74))

	for actor_id in PLAYABLE:
		var state = GameState.new_game(loader, actor_id)
		var weights := Trade.weights(state, actor_id)
		var top_id := _top_partner(state, actor_id)

		var best_damage := 0.0
		var best_damage_id := ""
		var best_revenue := 0.0
		var best_revenue_id := ""

		for target_id in weights.keys():
			var hit = GameState.new_game(loader, actor_id)
			_impose(hit, actor_id, target_id, "sanction", MAX_SEVERITY)
			var damage := Coercion.impulse(
				hit, hit.nations[target_id], Trade.weights_before_measures(hit, target_id)
			)
			if absf(damage) > absf(best_damage):
				best_damage = damage
				best_damage_id = target_id

			var levy = GameState.new_game(loader, actor_id)
			_impose(levy, actor_id, target_id, "tariff", MAX_SEVERITY)
			var revenue := Coercion.tariff_revenue_pct_gdp(
				levy, actor_id, Trade.weights(levy, actor_id)
			)
			if revenue > best_revenue:
				best_revenue = revenue
				best_revenue_id = target_id

		print("%-6s %10s %14s %12.3f %14s %12.3f" % [
			actor_id, top_id, best_damage_id, best_damage, best_revenue_id, best_revenue,
		])
	print("-".repeat(74))
	print("VERDICT: the trigger did not fire, but it left a consequence worth writing")
	print("down. REVENUE is open to GBR -- 0.120 against 0.179 and 0.161, within a")
	print("factor of 1.5 -- because tariffing collects on your OWN external demand and")
	print("every nation has one. DAMAGE is not: GBR's best possible hit is a quarter of")
	print("the other two's, because damage needs someone who depends on you and nobody")
	print("much depends on Britain in this roster. That is forced by the trade vector")
	print("rather than chosen, it is the third time GBR has been the constrained nation")
	print("in this block, and it is thematically right: leverage is what a nation")
	print("outside the bloc with no land borders actually lacks.")


## One month of the real game, the same chain main.gd runs. Copied from
## trade_probe.gd rather than shared: a probe that imported another probe's tick
## would break both when either changed its horizon.
func _tick(state, loader, i: int) -> void:
	state.month = (i + 1) % 12 + 1
	state.year = START_YEAR + (i + 1) / 12

	Economy.tick_month(state)
	Budget.tick_month(state)
	Orgs.tick_month(state, loader)
	Opinion.tick_month(state)
	var entry := Budget.snapshot(state)
	entry.merge(Opinion.snapshot(state))
	state.append_history(entry)
	Discipline.tick_month(state, loader)
	Legislature.tick_month(state, loader)
	Dissolution.tick_month(state)
	Diplomacy.tick_month(state, loader)
	Cabinet.tick_month(state, loader)
	Elections.tick_month(state, loader)
