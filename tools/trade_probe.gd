extends SceneTree

## Trade envelope probe: godot --headless --script res://tools/trade_probe.gd
##
## V1.3b's named measurement, run BEFORE trade_constants.gd exists -- which is the
## whole point of it. The constants this session ships are the output of the sweep
## below, not an input to it. Same discipline docs/diplomacy-model.md,
## docs/scenario-model.md and docs/amendment-model.md each used.
##
## Phase 0 runs two tables, each answering one named escalation trigger from the
## plan. Both triggers are GBR-shaped, and neither is a tuning call.
##
##   (a0) DIFFERENTIATION. The session's headline claim is that external demand
##        becomes PER-PARTNER rather than one GDP-weighted aggregate. GBR is in no
##        EU pair and its `neighbours` list is empty, so under a multiplicative
##        gravity every tie bonus is constant across all nine of its partners and
##        CANCELS UNDER NORMALISATION. At GRAVITY_EXPONENT = 1.0 its derived vector
##        is then identically the old aggregate, and the feature is a no-op for one
##        playable nation in three. This table measures that as an L1 distance and
##        sweeps for a parameterisation that avoids it.
##
##   (a2) REACHABILITY. Every GBR pair rests at exactly 45.0, the floor of
##        docs/diplomacy-model.md's four-tier table, and that doc already records
##        that bilateral_treaty's gate at 70 is "effectively closed to Britain". An
##        AGREEMENT_ACCEPT_MIN set near there closes the whole session to GBR --
##        docs/amendment-model.md's Germany two-thirds failure, repeated. This
##        table measures what each playable nation can actually reach with the
##        verbs already shipped.
##
## Not a test. tests/test_trade.gd asserts the invariants; this prints the spread a
## human reads. Kept in tools/ and excluded from run_tests.sh, same as
## balance_probe.gd, scenario_probe.gd and diplomacy_probe.gd.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Relations = preload("res://src/core/relations.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const Trade = preload("res://src/sim/trade.gd")
const TK = preload("res://src/sim/trade_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")

const PLAYABLE := ["FRA", "DEU", "GBR"]
const START_YEAR := 2026

## Table (b)'s synthetic shock, and table (c)'s horizon.
const RECESSION_PCT := -3.0
const RECESSION_MONTHS := 24
const PAYOFF_MONTHS := 60

## The three legibility floors, each read off what the game actually prints.
## The economy panel renders a sector share as "%.0f%%", so a composition move
## under about half a point never changes a digit -- the same class of finding
## docs/diplomacy-model.md records for a bloc offset below the poll-noise floor.
const SECTOR_LEGIBLE_PP := 0.5
const GROWTH_LEGIBLE_PCT := 0.01
const TREND_LEGIBLE_PCT := 0.01

## The sweep. `span` is the relations term's coefficient; `eu` and `border` are the
## gravity's own tie bonuses.
##
## Note the redundancy the sweep exists to expose: a pair's RESTING relations value
## is itself derived from EU co-membership and a shared border, so at new-game the
## relations term and the two gravity bonuses encode exactly the same two facts.
## They decouple only once a pair moves off its resting value. A row with
## eu = border = 0 is therefore a real candidate, not a degenerate one -- it says
## the ties should be carried once, by relations, rather than twice.
const EXPONENTS := [0.5, 0.6, 0.7, 0.85, 1.0]
const SPANS := [0.5, 1.0, 2.0]
const BONUSES := [[0.0, 0.0], [0.25, 0.35], [0.5, 1.2]]

## The plan's named failure for (a0): a playable nation whose derived vector is
## within this L1 distance of the old GDP-only aggregate has not been given a
## per-partner anything. L1 between two normalised vectors runs 0 to 2.
const NO_OP_L1 := 0.05

## (a2) sweeps the same horizon diplomacy_probe.gd used, so the two tables'
## "reachable" figures mean the same thing.
const PUSH_MONTHS := 60

## Read off the sweep, and the values src/sim/trade_constants.gd then ships. The
## exponent is set by GBR: it is the only lever that moves GBR's vector at all, and
## 0.70 puts it at 0.174 against the aggregate rather than 0.084 at 0.85, which is
## uncomfortably close to the 0.05 failure line for a nation whose distance is a
## pure function of this one number.
const CHOSEN_EXPONENT := 0.70
const CHOSEN_SPAN := 2.00
const CHOSEN_EU := 0.50
const CHOSEN_BORDER := 1.20


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	var state = GameState.new_game(loader, "FRA")
	if not state.errors.is_empty():
		printerr("new_game: %s" % [state.errors])
		quit(1)
		return

	_aggregate_table(state, loader)
	_sweep_table(state, loader)
	_detail_table(state, loader)
	_reach_table(loader)
	_transmission_table(loader)
	_payoff_table(loader)
	quit(0)


## What the channel does today, printed first because every L1 below is measured
## against this vector. `neighbour_weighted_growth()` weights purely by GDP, so the
## implied weight on partner B is gdp_B over the sum of the other nine.
func _aggregate_table(state, loader) -> void:
	print("\n########## the vector V1.3b replaces ##########")
	print("Economy.neighbour_weighted_growth() weights purely by GDP. For a viewer A")
	print("the implied weight on partner B is gdp_B / sum of the other nine.")
	print("")
	print("%-6s %12s   %s" % ["nation", "gdp eur bn", "eu / neighbours"])
	print("-".repeat(72))
	var ids: Array = loader.nations.keys()
	ids.sort()
	for id in ids:
		var n = loader.nations[id]
		var ns = state.nations[id]
		print("%-6s %12.0f   %-4s %s" % [
			id, ns.gdp_eur_bn, "eu" if n.eu_member else "--", str(n.neighbours),
		])
	print("-".repeat(72))
	print("GBR is the binding case: not in the EU, and its neighbours list is empty.")
	print("Both facts are correct -- and both make every tie bonus CONSTANT across")
	print("its nine partners, so both cancel when the vector is normalised.")


## Table (a0). One row per parameterisation, judged on two numbers: how far each
## playable nation's vector sits from the aggregate it replaces, and how far the
## nations' vectors sit from each other. A parameterisation that scores well on the
## first and badly on the second has given every nation the same new vector, which
## is a different way of shipping nothing.
func _sweep_table(state, loader) -> void:
	print("\n\n########## (a0) differentiation sweep ##########")
	print("L1 distance between normalised weight vectors; 0 means identical, 2 is the max.")
	print("'vs aggregate' is each playable nation against the GDP-only vector above.")
	print("'cross' is the mean L1 between the three playable nations' vectors, over")
	print("their common partners, renormalised -- how differently two nations trade.")
	print("A row fails if ANY playable nation reads under %.2f against the aggregate." % NO_OP_L1)
	print("")
	print("%5s %6s %6s %8s   %7s %7s %7s   %7s   %s" % [
		"exp", "span", "eu", "border", "FRA", "DEU", "GBR", "cross", "verdict",
	])
	print("-".repeat(88))

	for exponent in EXPONENTS:
		for span in SPANS:
			for bonus in BONUSES:
				_sweep_one(state, loader, exponent, span, float(bonus[0]), float(bonus[1]))
		print("-".repeat(88))

	print("The exponent is the lever that works: it compresses the ~50x GDP spread")
	print("and lets the ties matter. The bonuses alone cannot reorder a 50x spread,")
	print("and for GBR they cannot do anything at all.")


func _sweep_one(state, loader, exponent: float, span: float, eu: float, border: float) -> void:
	var vectors := {}
	var ids: Array = loader.nations.keys()
	ids.sort()
	for id in ids:
		vectors[id] = _weights(state, loader, id, exponent, span, eu, border)

	var worst := 99.0
	var cells: Array = []
	for id in PLAYABLE:
		var d := _l1(vectors[id], _aggregate_weights(state, id))
		worst = minf(worst, d)
		cells.append(d)

	var cross := 0.0
	var pairs := 0
	for i in PLAYABLE.size():
		for j in range(i + 1, PLAYABLE.size()):
			cross += _l1_common(vectors[PLAYABLE[i]], vectors[PLAYABLE[j]], PLAYABLE[i], PLAYABLE[j])
			pairs += 1
	if pairs > 0:
		cross /= float(pairs)

	print("%5.2f %6.2f %6.2f %8.2f   %7.3f %7.3f %7.3f   %7.3f   %s" % [
		exponent, span, eu, border, cells[0], cells[1], cells[2], cross,
		"NO-OP for a playable nation" if worst < NO_OP_L1 else "differentiated",
	])


## The chosen parameterisation, read off the sweep above and then printed in full
## so docs/trade-model.md quotes a table rather than an assertion. Also the place
## the inherited size asymmetry is checked: LUX->FRA against FRA->LUX is the pair
## a symmetric relations key could not express, and this is where it lands.
func _detail_table(state, loader) -> void:
	print("\n\n########## the chosen vector, in full ##########")
	print("read off the sweep, then shipped -- printed here from src/sim/trade.gd itself.")
	print("exponent %.2f  span %.2f  eu %.2f  border %.2f" % [
		TK.GRAVITY_EXPONENT, TK.INTENSITY_SPAN, TK.EU_TRADE_BONUS, TK.BORDER_TRADE_BONUS,
	])
	print("")

	var ids: Array = loader.nations.keys()
	ids.sort()

	var header := "%-6s" % "actor"
	for id in ids:
		header += "%7s" % id
	print(header)
	print("-".repeat(76))

	# The real module, not the sweep's parameterised copy: this table has to prove
	# that the constants src/sim/trade_constants.gd ships produce the numbers
	# docs/trade-model.md quotes. The copy above exists only because the sweep
	# varies values that are `const` in the shipped file.
	var vectors := {}
	for actor_id in ids:
		var w := Trade.weights(state, actor_id)
		vectors[actor_id] = w
		var row := "%-6s" % actor_id
		for id in ids:
			row += "%7s" % ("     ." if id == actor_id else "%.3f" % float(w[id]))
		print(row)
	print("-".repeat(76))

	print("")
	print("directed asymmetry -- the input V1.3a dropped, appearing where it belongs:")
	print("%-14s %8s %8s %8s" % ["pair", "A->B", "B->A", "ratio"])
	for pair in [["LUX", "FRA"], ["LUX", "DEU"], ["BEL", "DEU"], ["AUT", "DEU"], ["FRA", "DEU"]]:
		var ab: float = float(vectors[pair[0]][pair[1]])
		var ba: float = float(vectors[pair[1]][pair[0]])
		print("%-14s %8.3f %8.3f %8.1fx" % [
			"%s -> %s" % [pair[0], pair[1]], ab, ba, ab / ba if ba > 0.0 else 0.0,
		])
	print("")
	print("A symmetric pair key has one number and no side to attach a size")
	print("disparity to. A normalised directed weight has two, and the disparity")
	print("is the ratio between them. See docs/diplomacy-model.md section 2.")


## The candidate weight function, exactly as src/sim/trade.gd will compute it:
## partner GDP under an exponent, times the tie bonuses, times the relations term.
## Normalised, so it is a mix and carries no level.
func _weights(state, loader, actor_id: String, exponent: float, span: float, eu: float, border: float) -> Dictionary:
	var a = loader.nations[actor_id]
	var raw := {}
	var total := 0.0
	for id in loader.nations.keys():
		if id == actor_id:
			continue
		var b = loader.nations[id]
		var value: float = pow(state.nations[id].gdp_eur_bn, exponent)
		if a.eu_member and b.eu_member:
			value *= 1.0 + eu
		if a.neighbours.has(id):
			value *= 1.0 + border
		var relations: float = Diplomacy.score(state, actor_id, id)
		value *= maxf(0.0, 1.0 + span * (relations - DK.REST_BASE) / 100.0)
		raw[id] = value
		total += value
	if total <= 0.0:
		return raw
	for id in raw.keys():
		raw[id] = float(raw[id]) / total
	return raw


## The vector the channel uses today, from the viewer's side: GDP share of the
## other nine.
func _aggregate_weights(state, actor_id: String) -> Dictionary:
	var raw := {}
	var total := 0.0
	for id in state.nations.keys():
		if id == actor_id:
			continue
		var value: float = state.nations[id].gdp_eur_bn
		raw[id] = value
		total += value
	if total <= 0.0:
		return raw
	for id in raw.keys():
		raw[id] = float(raw[id]) / total
	return raw


func _l1(a: Dictionary, b: Dictionary) -> float:
	var sum := 0.0
	for id in a.keys():
		sum += absf(float(a[id]) - float(b.get(id, 0.0)))
	return sum


## Two nations' vectors are over different partner sets -- each includes the other
## and excludes itself. Compared over the eight they share, renormalised, so the
## figure is "do they trade differently" and not "they are not the same nation".
func _l1_common(a: Dictionary, b: Dictionary, a_id: String, b_id: String) -> float:
	var keys: Array = []
	for id in a.keys():
		if id != b_id and b.has(id):
			keys.append(id)
	var sum_a := 0.0
	var sum_b := 0.0
	for id in keys:
		sum_a += float(a[id])
		sum_b += float(b[id])
	if sum_a <= 0.0 or sum_b <= 0.0:
		return 0.0
	var out := 0.0
	for id in keys:
		out += absf(float(a[id]) / sum_a - float(b[id]) / sum_b)
	return out


## Table (a2). What relations can a playable nation actually reach, from each of
## its own resting tiers, using only the verbs data/diplomatic-actions/ already
## ships? An AGREEMENT_ACCEPT_MIN above a nation's ceiling closes the feature to it.
func _reach_table(loader) -> void:
	print("\n\n########## (a2) reachable relations, per playable nation ##########")
	print("%d months of the strongest positive verb at its own legal cadence, from" % PUSH_MONTHS)
	print("each pair's derived resting value. The ceiling is what an")
	print("AGREEMENT_ACCEPT_MIN has to sit under for the feature to exist there.")
	print("")

	var positives: Array = []
	for action in loader.diplomatic_actions:
		if float(action.effects.get("relations", 0.0)) > 0.0:
			positives.append(action)

	print("positive verbs shipped: %s" % [_verb_summary(positives)])
	print("")
	print("%-6s %-6s %8s %10s %10s   %s" % [
		"actor", "target", "resting", "best verb", "reached", "note",
	])
	print("-".repeat(76))

	for actor_id in PLAYABLE:
		var best_seen := -1.0
		var worst_seen := 999.0
		for target_id in loader.nations.keys():
			if target_id == actor_id:
				continue
			var row := _reach_one(loader, actor_id, target_id, positives)
			best_seen = maxf(best_seen, float(row["reached"]))
			worst_seen = minf(worst_seen, float(row["reached"]))
			print("%-6s %-6s %8.1f %10s %10.1f   %s" % [
				actor_id, target_id, float(row["resting"]), row["verb"], float(row["reached"]),
				row["note"],
			])
		print("%-6s ceiling across its nine partners: %.1f   floor: %.1f" % [
			actor_id, best_seen, worst_seen,
		])
		print("-".repeat(76))

	print("The floor row is the one that decides AGREEMENT_ACCEPT_MIN: a gate above a")
	print("nation's floor makes the agreement available against some partners and not")
	print("others, which is the point. A gate above its CEILING makes the session")
	print("unreachable for that nation, which is the escalation.")


func _reach_one(loader, actor_id: String, target_id: String, positives: Array) -> Dictionary:
	var best_verb := "-"
	var best_reached := -1.0
	var resting := 0.0

	for action in positives:
		var state = GameState.new_game(loader, actor_id)
		resting = Diplomacy.score(state, actor_id, target_id)
		var since := 0
		for i in range(PUSH_MONTHS):
			if since <= 0:
				# The precondition is deliberately bypassed: this measures the
				# envelope of the verb, and a gate is what the number is FOR.
				Relations.adjust(
					state, actor_id, target_id, float(action.effects["relations"]),
					DK.RELATIONS_MIN, DK.RELATIONS_MAX
				)
				since = action.cooldown_months
			since -= 1
			Diplomacy.tick_month(state, loader)
		var reached := Diplomacy.score(state, actor_id, target_id)
		if reached > best_reached:
			best_reached = reached
			best_verb = action.id

	return {
		"resting": resting,
		"verb": best_verb,
		"reached": best_reached,
		"note": "spam ceiling",
	}


## Table (b). What the transmission channel does when something finally moves it.
##
## DECLARED SYNTHETIC. Nothing in the shipped game produces this: the nine AI
## nations have no budget and take no shocks, so every partner sits at its own
## new-game growth forever and the term is ~0 by construction. V1.3c's tariffs and
## sanctions are the first thing that perturbs a partner. This table exists so the
## machinery is measured before the session that drives it, and so the headroom
## against the two growth clamps is known rather than assumed.
func _transmission_table(loader) -> void:
	print("\n\n########## (b) transmission, under a SYNTHETIC partner recession ##########")
	print("DEU forced to %.1f%%/yr for %d months. Nothing in the shipped game does" % [
		RECESSION_PCT, RECESSION_MONTHS,
	])
	print("this -- the nine AI nations take no shocks. V1.3c is the first session")
	print("that perturbs a partner, and this is the machinery it will drive.")
	print("")
	print("%-6s %8s %10s %10s %10s   %s" % [
		"actor", "w(DEU)", "peak imp", "vs IMP_MAX", "peak grow", "legible at the panel's %+.2f?",
	])
	print("-".repeat(84))

	for actor_id in PLAYABLE:
		var state = GameState.new_game(loader, actor_id)
		var weight: float = float(Trade.weights(state, actor_id).get("DEU", 0.0))

		var peak_impulse := 0.0
		var peak_growth_gap := 0.0
		var control = GameState.new_game(loader, actor_id)

		for i in range(RECESSION_MONTHS + 24):
			Economy.tick_month(state)
			Economy.tick_month(control)
			if absf(state.player().external_impulse_pct) > absf(peak_impulse):
				peak_impulse = state.player().external_impulse_pct
			var gap: float = state.player().growth_annual_pct - control.player().growth_annual_pct
			if absf(gap) > absf(peak_growth_gap):
				peak_growth_gap = gap
			# Held after the tick, so next month's impulse reads it. Growth is
			# recomputed from scratch each month, so this is a clean override
			# rather than an accumulating one.
			if i < RECESSION_MONTHS:
				state.nations["DEU"].growth_annual_pct = RECESSION_PCT

		print("%-6s %8.3f %10.3f %9.0f%% %10.3f   %s" % [
			actor_id, weight, peak_impulse,
			100.0 * absf(peak_impulse) / EK.IMPULSE_MAX_PCT, peak_growth_gap,
			"yes" if absf(peak_growth_gap) >= GROWTH_LEGIBLE_PCT else "NO",
		])
	print("-".repeat(84))
	print("The clamps must stay unreachable: IMPULSE_MAX is %.1f and GROWTH_MAX %.1f." % [
		EK.IMPULSE_MAX_PCT, EK.GROWTH_MAX_PCT,
	])


## Table (c). What one agreement is worth, against a control running the same
## months with nothing signed. Three floors, each named before the run:
##
##   1. The trend gain must be non-zero and readable by sixty months, or the
##      openness channel is decorative.
##   2. It must be SMALLER than a budget commit of comparable domestic cost --
##      a treaty should not out-earn fiscal policy.
##   3. The sector move must clear the economy panel's own rounding, which prints
##      a share as "%.0f%%". That is a floor of about half a point, and it is the
##      same class of finding docs/diplomacy-model.md records for a bloc offset
##      below the poll-noise floor: an effect the player cannot read is a
##      decorative effect however real it is in the state.
func _payoff_table(loader) -> void:
	print("\n\n########## (c) what one agreement is worth ##########")
	print("FRA signs 'industrial_compact' with DEU at month 0, against a control.")
	print("openness beta %.2f, panel prints a sector share as %%.0f%%%% so the floor" % TK.TRADE_OPENNESS_BETA)
	print("for a legible composition move is about %.1f points." % SECTOR_LEGIBLE_PP)
	print("")

	var control = GameState.new_game(loader, "FRA")
	var treated = GameState.new_game(loader, "FRA")
	treated.year = START_YEAR
	treated.month = 1

	var action = null
	for candidate in loader.diplomatic_actions:
		if String(candidate.effects.get("agreement", {}).get("op", "")) == "enter":
			action = candidate
	if action == null:
		print("  no 'enter' agreement action is authored -- nothing to measure")
		return

	var signed := Diplomacy.execute(treated, loader.diplomatic_actions, action, "FRA", "DEU")
	if not signed["applied"]:
		print("  '%s' was refused against DEU: %s" % [
			action.id, "partner declined" if signed.get("refused_by_partner", false) else "precondition or cooldown",
		])
		return

	print("signed '%s': openness %.4f, weight on DEU %.3f -> %.3f" % [
		action.id, Trade.openness_index(treated, "FRA"),
		float(Trade.weights(control, "FRA").get("DEU", 0.0)),
		float(Trade.weights(treated, "FRA").get("DEU", 0.0)),
	])
	print("")
	print("%8s %10s %10s %10s %10s %10s" % [
		"month", "d trend", "d GDP %", "d agri pp", "d ind pp", "d serv pp",
	])
	print("-".repeat(64))

	for i in range(PAYOFF_MONTHS):
		_tick(control, loader, i)
		_tick(treated, loader, i)
		var month := i + 1
		if month == 12 or month == 36 or month == 60:
			_payoff_row(month, control.player(), treated.player())
	print("-".repeat(64))

	var t = treated.player()
	var c = control.player()
	print("verdict: trend %+.3f (floor: non-zero and readable) -- %s" % [
		t.trend_annual_pct - c.trend_annual_pct,
		"clears" if absf(t.trend_annual_pct - c.trend_annual_pct) >= TREND_LEGIBLE_PCT else "BELOW FLOOR",
	])
	var worst := 0.0
	for key in c.sector_output.keys():
		var move: float = (
			100.0 * float(t.sector_output[key]) / t.gdp_eur_bn
			- 100.0 * float(c.sector_output[key]) / c.gdp_eur_bn
		)
		worst = maxf(worst, absf(move))
	print("         largest sector move %.2f pp (floor %.1f) -- %s" % [
		worst, SECTOR_LEGIBLE_PP,
		"clears" if worst >= SECTOR_LEGIBLE_PP else "BELOW THE PANEL'S ROUNDING",
	])


func _payoff_row(month: int, c, t) -> void:
	var shares: Array = []
	for key in ["agriculture", "industry", "services"]:
		shares.append(
			100.0 * float(t.sector_output[key]) / t.gdp_eur_bn
			- 100.0 * float(c.sector_output[key]) / c.gdp_eur_bn
		)
	print("%8d %+10.3f %+10.3f %+10.2f %+10.2f %+10.2f" % [
		month,
		t.trend_annual_pct - c.trend_annual_pct,
		100.0 * (t.gdp_eur_bn - c.gdp_eur_bn) / c.gdp_eur_bn,
		shares[0], shares[1], shares[2],
	])


## The real monthly chain, in main.gd's order.
func _tick(state, loader, i: int) -> void:
	var month: int = (i + 1) % 12 + 1
	var year: int = START_YEAR + (i + 1) / 12
	state.year = year
	state.month = month

	Economy.tick_month(state)
	Budget.tick_month(state)
	Bloc.tick_month(state, loader)
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


func _verb_summary(actions: Array) -> String:
	var parts: Array = []
	for action in actions:
		parts.append("%s %+.0f/%dmo" % [
			action.id, float(action.effects["relations"]), action.cooldown_months,
		])
	return ", ".join(parts)
