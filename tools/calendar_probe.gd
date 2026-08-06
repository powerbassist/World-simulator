extends SceneTree

## Calendar probe: godot --headless --script res://tools/calendar_probe.gd
##
## U6a's named measurement, and the one that is allowed to DELETE this session's
## only tuned constant. Five tables, and three of them run before src/sim/calendar.gd
## exists at all, because they are reads over state the game already carries --
## the same split tools/bloc_probe.gd used for its own table (a).
##
##   (P1) THE MENU WIDTH. How many acts does a month actually offer? If the median
##        month offers fewer wants than the budget buys, the budget cannot bind at
##        ANY value and the currency is cut. Measured at the MONTH-24 landscape as
##        well as at new-game, because V1.3f's AGENDA_ACT_MIN sweep measured the
##        static table, found 0.05, and shipped a world that went silent by month
##        24 -- the same error made here would find a menu that only new games have.
##
##   (P2) THE BIND RATE -- THE HEADLINE, AND THE KILL SWITCH. Under a greedy
##        player, in what fraction of months is the BUDGET the binding constraint
##        rather than a cooldown or a precondition? Accepted only inside
##        [BIND_BAND_MIN, BIND_BAND_MAX]. Below it the currency is decorative;
##        above it the calendar is "you get three acts a month" in a costume.
##        Outside the band the constant is DELETED, not left unused -- the
##        treatment V1.3e gave AGREEMENT_ACCEPT_MIN and SUPPORT_SIGMA.
##
##   (P3) ORTHOGONALITY. V1.3c cut an authored tariff_rate_pct once revenue came
##        back exactly linear in it: one intensity written twice. A day cost that
##        tracks an act's existing domestic price is that error again. Prints the
##        |bloc_offset| spread across the fourteen verbs, and what a cost DERIVED
##        from cooldown_months would look like -- the derivation the plan rejects,
##        so the rejection is measured rather than asserted.
##
##   (P4) REACHABILITY. Under a per-kind table the classic dominance sweep has no
##        per-verb variance to sweep, so the real risk changes shape: a kind
##        priced above the budget is unreachable FOREVER, which is V1.3c's
##        strictly-dominated severity with the sign flipped. Checks every kind is
##        affordable, alone and in the plausible pairs.
##
##   (P5) FIXED-DATE DENSITY. U6a's headline is that the president can finally see
##        their own year. If most months carry no dated event the grid is
##        decoration -- and the mitigation is CONTENT (surface cooldown expiries
##        as dates), not a constant, which is V1.3d's common_defence_floor
##        correction in a new place.
##
## Not a test. tests/test_calendar.gd asserts the invariants; this prints the
## spread a human reads. Kept in tools/ and excluded from run_tests.sh, same as
## balance_probe.gd, bloc_probe.gd, coercion_probe.gd and foreign_policy_probe.gd.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Defence = preload("res://src/sim/defence.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Elections = preload("res://src/sim/elections.gd")
const OK_C = preload("res://src/sim/opinion_constants.gd")

const PLAYER := "FRA"
const START_YEAR := 2026

## Fourteen years, the horizon tools/balance_probe.gd uses, because P1's whole
## point is that a fourteen-year landscape is not the new-game one.
const MONTHS := 168

## V1.3f's lesson, made a constant rather than a comment: the static table is not
## the state the game is played in. Everything reported "late" ignores the first
## two years.
const SETTLE_MONTHS := 24

## The band P2 is judged against, fixed here BEFORE the sweep runs so the numbers
## can falsify the currency rather than be fitted to it.
const BIND_BAND_MIN := 0.25
const BIND_BAND_MAX := 0.75

## The candidate per-kind day costs. Authored here rather than in
## src/sim/calendar_constants.gd because that file does not exist yet: the probe
## SETS the table, it does not validate one. A diplomatic act is a trip, a law is
## a parliamentary campaign, a reshuffle is a weekend of phone calls that costs
## the least time and the most politically -- the inversion P3 is looking for.
const CANDIDATE_COST := {
	"diplomatic": 6,
	"law": 4,
	"reshuffle": 2,
}

## Swept against the band. The upper end is deliberately past anything plausible
## so the table shows where binding STOPS, not just where it starts.
const BUDGET_SWEEP := [4, 6, 8, 10, 12, 14, 18, 24]

## P5 runs a playing player, and needs a budget to play under before P2 has
## chosen one. Mid-sweep: the density it reports is the shape of the curve, not
## a figure to three decimals, and a mid budget cannot flatter it much either way.
const DENSITY_BUDGET := 12


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	_menu_width_table(loader)
	_orthogonality_table(loader)
	_fixed_date_table(loader)
	_bind_rate_table(loader)
	_reachability_table()
	quit(0)


## main.gd's _on_month_elapsed() order, Defence included. bloc_probe.gd's own
## _tick() predates V1.3g and omits it; a probe measuring what a month OFFERS
## cannot afford to run a different month from the game.
func _tick(state, loader, i: int) -> void:
	state.month = (i + 1) % 12 + 1
	state.year = START_YEAR + (i + 1) / 12

	Economy.tick_month(state)
	Budget.tick_month(state)
	Bloc.tick_month(state, loader)
	Opinion.tick_month(state)
	var entry := Budget.snapshot(state)
	entry.merge(Opinion.snapshot(state))
	state.append_history(entry)
	Discipline.tick_month(state, loader)
	Legislature.tick_month(state)
	Dissolution.tick_month(state)
	Diplomacy.tick_month(state, loader)
	Defence.tick_month(state)
	Cabinet.tick_month(state, loader)
	Elections.tick_month(state, loader)


## A month's WANTS, as a list of {kind, cost, ...} -- one act per partner rather
## than every legal act against every partner, because a player does not impose
## tariffs on Luxembourg and lift them in the same month. The raw availability
## count is printed alongside so the doc can show both readings.
func _wants(state, loader) -> Array:
	var out := []
	var ns = state.player()
	var targets: Array = state.nations.keys()
	targets.sort()
	for target_id in targets:
		if target_id == PLAYER:
			continue
		var acts := Diplomacy.available(state, loader.diplomatic_actions, PLAYER, target_id)
		if not acts.is_empty():
			out.append({
				"kind": "diplomatic",
				"cost": int(CANDIDATE_COST["diplomatic"]),
				"action": acts[0],
				"target": target_id,
			})

	for law in Legislature.available(ns, loader.laws):
		out.append({"kind": "law", "cost": int(CANDIDATE_COST["law"]), "law": law})

	# A reshuffle is always legal while a coalition exists, so it is exactly one
	# want per month rather than one per (portfolio, party) pair -- a player
	# reshuffles the cabinet, they do not reshuffle it five times.
	if not ns.coalition_party_ids.is_empty():
		out.append({"kind": "reshuffle", "cost": int(CANDIDATE_COST["reshuffle"])})

	return out


func _raw_available(state, loader) -> int:
	var total := 0
	var ns = state.player()
	for target_id in state.nations.keys():
		if target_id == PLAYER:
			continue
		total += Diplomacy.available(state, loader.diplomatic_actions, PLAYER, target_id).size()
	total += Legislature.available(ns, loader.laws).size()
	return total


## (P1) -----------------------------------------------------------------------
func _menu_width_table(loader) -> void:
	print("\n########## (P1) the menu width ##########")
	print("What a month OFFERS a player who has done nothing. If the median month")
	print("offers fewer wants than the budget buys, no budget can bind and the")
	print("currency is cut. Reported early (months 1-%d) and late, because" % SETTLE_MONTHS)
	print("V1.3f's sweep read the static table and shipped a silent world.")
	print("")

	var state = GameState.new_game(loader, PLAYER)
	var early: Array[int] = []
	var late: Array[int] = []
	var early_raw: Array[int] = []
	var late_raw: Array[int] = []
	var early_days: Array[int] = []
	var late_days: Array[int] = []

	for i in range(MONTHS):
		_tick(state, loader, i)
		var wants := _wants(state, loader)
		var raw := _raw_available(state, loader)
		var days := 0
		for w in wants:
			days += int(w["cost"])
		if i < SETTLE_MONTHS:
			early.append(wants.size())
			early_raw.append(raw)
			early_days.append(days)
		else:
			late.append(wants.size())
			late_raw.append(raw)
			late_days.append(days)

	print("%-8s %8s %8s %8s %10s %10s" % ["window", "wants", "median", "min", "raw acts", "days asked"])
	print("-".repeat(58))
	print("%-8s %8.2f %8d %8d %10.1f %10.1f" % [
		"early", _mean(early), _median(early), early.min(), _mean(early_raw), _mean(early_days),
	])
	print("%-8s %8.2f %8d %8d %10.1f %10.1f" % [
		"late", _mean(late), _median(late), late.min(), _mean(late_raw), _mean(late_days),
	])
	print("")
	print("A want is one act per partner plus every available law plus a reshuffle.")
	print("`raw acts` is every legal (action, target) pair, printed so the doc can")
	print("show what the one-per-partner reading throws away.")

	var cheapest: int = int(CANDIDATE_COST.values().min())
	if _median(late) * cheapest <= cheapest:
		print("")
		print("KILL SWITCH: the late median month offers %d want(s). The budget" % _median(late))
		print("cannot bind at any value above the cheapest act. Currency is cut.")


## (P3) -----------------------------------------------------------------------
func _orthogonality_table(loader) -> void:
	print("\n\n########## (P3) orthogonality ##########")
	print("V1.3c cut an authored tariff_rate_pct once revenue came back exactly")
	print("linear in it -- one intensity written twice. A day cost that tracks an")
	print("act's domestic price is that error again.")
	print("")
	print("%-22s %10s %10s %8s" % ["action", "|bloc_off|", "cooldown", "days"])
	print("-".repeat(54))

	var offsets: Array[float] = []
	var cooldowns: Array[float] = []
	for action in loader.diplomatic_actions:
		var offset := 0.0
		var raw = action.effects.get("bloc_offset", {})
		if typeof(raw) == TYPE_DICTIONARY:
			for b in raw.keys():
				offset += absf(float(raw[b]))
		offsets.append(offset)
		cooldowns.append(float(action.cooldown_months))
		print("%-22s %10.3f %10d %8d" % [
			action.id, offset, action.cooldown_months, int(CANDIDATE_COST["diplomatic"]),
		])

	print("")
	print("cooldown_months spread: %s" % [_distinct(cooldowns)])
	print("|bloc_offset| spread:   %.3f to %.3f" % [offsets.min(), offsets.max()])
	print("r(|bloc_offset|, cooldown_months) = %.3f" % _pearson(offsets, cooldowns))
	print("")
	print("The kind table gives all fourteen the same cost, so r(days, price) is")
	print("undefined by construction -- there is no per-verb variance to correlate.")
	print("That is the point rather than a dodge: days bound HOW MANY acts a month")
	print("holds, and the domestic price still decides WHICH, so the two axes")
	print("cannot be one intensity written twice. What the table above has to")
	print("show for that to be honest is a WIDE |bloc_offset| spread -- if the")
	print("verbs were flat on price too, a flat day cost would make them")
	print("interchangeable and the choice would be arithmetic.")
	if _distinct(cooldowns).size() <= 2:
		print("")
		print("AND the derivation the plan rejects is measured dead here:")
		print("cooldown_months takes %d distinct values across fourteen verbs, so a" % _distinct(cooldowns).size())
		print("cost read off it would give %d prices for fourteen acts -- trade.gd's" % _distinct(cooldowns).size())
		print("GRAVITY_EXPONENT = 1.0 finding and V1.3e's clustered")
		print("coalition_position in a third place.")


## (P5) -----------------------------------------------------------------------
func _fixed_date_table(loader) -> void:
	print("\n\n########## (P5) fixed-date density ##########")
	print("U6a's headline. Election day, the council's next proposal and its")
	print("pending vote, the dissolution lockout, and every cooldown expiry are")
	print("live dated state today with no surface that puts them on a timeline.")
	print("If most months carry none, the grid is decoration -- and the fix is")
	print("content, not a constant.")
	print("")

	# Measured under a PLAYING player, and read BEFORE the tick. Both halves were
	# wrong on the first run and both are V1.3f's error -- measuring the wrong
	# state. A player who never acts sets no cooldown, so the largest source of
	# dated events read exactly 0; and counting after the tick reads an election
	# that has already pushed its own next date forward, so 168 months showed one.
	# A calendar panel lists what falls in the month it is ABOUT to be, which is
	# the pre-tick reading.
	var state = GameState.new_game(loader, PLAYER)
	var months_with_any := 0
	var total_events := 0
	var by_source := {
		"election": 0, "ep_election": 0, "council_proposal": 0,
		"council_vote": 0, "dissolution": 0, "cooldown": 0,
	}

	for i in range(MONTHS):
		state.month = (i + 1) % 12 + 1
		state.year = START_YEAR + (i + 1) / 12
		var counts := _fixed_events(state)
		var here := 0
		for k in counts.keys():
			by_source[k] += int(counts[k])
			here += int(counts[k])
		total_events += here
		if here > 0:
			months_with_any += 1

		_tick(state, loader, i)
		var wants := _wants(state, loader)
		wants.sort_custom(func(a, b): return int(a["cost"]) < int(b["cost"]))
		var spent := 0
		for w in wants:
			var cost := int(w["cost"])
			if spent + cost > DENSITY_BUDGET:
				continue
			spent += cost
			_take(state, loader, w)

	var density := float(months_with_any) / float(MONTHS)
	print("months carrying at least one dated event: %d / %d  (%.1f%%)" % [
		months_with_any, MONTHS, density * 100.0,
	])
	print("mean events per month: %.2f" % (float(total_events) / float(MONTHS)))
	print("")
	print("%-18s %8s" % ["source", "months"])
	print("-".repeat(28))
	var keys: Array = by_source.keys()
	keys.sort()
	for k in keys:
		print("%-18s %8d" % [k, by_source[k]])

	if density < 0.5:
		print("")
		print("THIN: under half of months carry a dated event. The mitigation is")
		print("content -- surface more of what is already dated -- not a constant.")


## Everything the game already knows a date for, counted for the month the state
## is currently in. Reads plain fields; calls no system, so it cannot drift from
## what src/sim/calendar.gd's own fixed_dates() will read.
func _fixed_events(state) -> Dictionary:
	var ns = state.player()
	var out := {
		"election": 0, "ep_election": 0, "council_proposal": 0,
		"council_vote": 0, "dissolution": 0, "cooldown": 0,
	}

	if ns.next_election_year == state.year and ns.next_election_month == state.month:
		out["election"] = 1
	if ns.next_ep_election_year == state.year and ns.next_ep_election_month == state.month:
		out["ep_election"] = 1

	var bloc: Dictionary = state.bloc
	if int(bloc.get("months_to_next", 99)) <= 1:
		out["council_proposal"] = 1
	var pending = bloc.get("pending", {})
	if typeof(pending) == TYPE_DICTIONARY and not pending.is_empty():
		out["council_vote"] = 1

	if ns.dissolution_lockout_remaining == 1:
		out["dissolution"] = 1

	var expiring := 0
	for k in ns.diplo_cooldown_months.keys():
		if int(ns.diplo_cooldown_months[k]) == 1:
			expiring += 1
	for k in ns.law_cooldown_months.keys():
		if int(ns.law_cooldown_months[k]) == 1:
			expiring += 1
	out["cooldown"] = 1 if expiring > 0 else 0

	return out


## (P2) -----------------------------------------------------------------------
func _bind_rate_table(loader) -> void:
	print("\n\n########## (P2) the bind rate -- the kill switch ##########")
	print("A greedy player takes what the month offers, cheapest kind first, until")
	print("the days run out. The budget BINDS in a month when it -- rather than a")
	print("cooldown or a precondition -- is what stopped them. Accepted only")
	print("inside [%.0f%%, %.0f%%]." % [BIND_BAND_MIN * 100.0, BIND_BAND_MAX * 100.0])
	print("")
	print("Costs swept against: %s" % [CANDIDATE_COST])
	print("")
	print("%-8s %10s %10s %10s %10s %8s" % [
		"budget", "bind late", "bind all", "acts/mo", "dropped", "verdict",
	])
	print("-".repeat(62))

	var accepted: Array[int] = []
	for budget in BUDGET_SWEEP:
		var r := _run_greedy(loader, budget)
		var verdict := "ok"
		if r["bind_late"] < BIND_BAND_MIN:
			verdict = "thin"
		elif r["bind_late"] > BIND_BAND_MAX:
			verdict = "THROTTLE"
		else:
			accepted.append(budget)
		print("%-8d %9.1f%% %9.1f%% %10.2f %10.2f %8s" % [
			budget, r["bind_late"] * 100.0, r["bind_all"] * 100.0,
			r["acts_per_month"], r["dropped_per_month"], verdict,
		])

	print("")
	if accepted.is_empty():
		print("KILL SWITCH FIRED. No budget in the sweep binds inside the band.")
		print("The currency is DELETED rather than left unused -- V1.3e's treatment")
		print("of AGREEMENT_ACCEPT_MIN and SUPPORT_SIGMA. U6a ships on the diary,")
		print("and CLAUDE.md records the first session in a long run with no new")
		print("tuned constant, and why.")
	else:
		print("Band cleared at: %s" % [accepted])
		print("DAYS_PER_MONTH_BUDGET takes the value nearest the middle of the band,")
		print("not the lowest that clears -- a constant sitting on its own boundary")
		print("is one a later content session walks off.")


## One greedy 168-month run at a given budget. Returns the bind rate over all
## months and over the late window, plus what the ceiling actually cost.
func _run_greedy(loader, budget: int) -> Dictionary:
	var state = GameState.new_game(loader, PLAYER)
	var bound_all := 0
	var bound_late := 0
	var late_months := 0
	var acts := 0
	var dropped := 0

	for i in range(MONTHS):
		_tick(state, loader, i)
		var wants := _wants(state, loader)
		wants.sort_custom(func(a, b): return int(a["cost"]) < int(b["cost"]))

		var spent := 0
		var taken := 0
		var refused := 0
		for w in wants:
			var cost := int(w["cost"])
			if spent + cost > budget:
				refused += 1
				continue
			spent += cost
			taken += 1
			_take(state, loader, w)

		acts += taken
		dropped += refused
		# The budget BOUND only if something legal was refused for want of days.
		# A month where the player wanted three things and could afford three was
		# limited by the menu, not by the ceiling -- that distinction is the whole
		# measurement, and conflating them is how a throttle reads as a decision.
		if refused > 0:
			bound_all += 1
			if i >= SETTLE_MONTHS:
				bound_late += 1
		if i >= SETTLE_MONTHS:
			late_months += 1

	return {
		"bind_all": float(bound_all) / float(MONTHS),
		"bind_late": float(bound_late) / float(maxi(late_months, 1)),
		"acts_per_month": float(acts) / float(MONTHS),
		"dropped_per_month": float(dropped) / float(MONTHS),
	}


func _take(state, loader, want: Dictionary) -> void:
	match String(want["kind"]):
		"diplomatic":
			Diplomacy.execute(
				state, loader.diplomatic_actions, want["action"], PLAYER, String(want["target"])
			)
		"law":
			Legislature.propose(state, loader, want["law"])
		"reshuffle":
			var ns = state.player()
			var party_list: Array = loader.parties.get(PLAYER, [])
			var portfolio := String(ns.cabinet.keys()[0])
			var party_id := String(ns.coalition_party_ids[0])
			if Cabinet.can_assign(ns, portfolio, party_id):
				Cabinet.assign(state, portfolio, party_id, party_list)


## (P4) -----------------------------------------------------------------------
func _reachability_table() -> void:
	print("\n\n########## (P4) reachability ##########")
	print("A per-kind table has no per-verb variance, so the classic dominance")
	print("sweep has nothing to sweep. The risk changes shape instead: a kind")
	print("priced above the budget is unreachable FOREVER, which is V1.3c's")
	print("strictly-dominated severity with the sign flipped.")
	print("")
	print("%-8s %s" % ["budget", "kinds affordable alone / in the cheapest pair"])
	print("-".repeat(62))

	var kinds: Array = CANDIDATE_COST.keys()
	kinds.sort()
	for budget in BUDGET_SWEEP:
		var alone: Array[String] = []
		var unreachable: Array[String] = []
		for k in kinds:
			if int(CANDIDATE_COST[k]) <= budget:
				alone.append(String(k))
			else:
				unreachable.append(String(k))
		var cheapest: int = int(CANDIDATE_COST.values().min())
		var pairs := 0
		for k in kinds:
			if int(CANDIDATE_COST[k]) + cheapest <= budget:
				pairs += 1
		var flag := ""
		if not unreachable.is_empty():
			flag = "   UNREACHABLE: %s" % [unreachable]
		print("%-8d %d / %d%s" % [budget, alone.size(), pairs, flag])

	print("")
	print("A budget that leaves any kind unreachable is refused whatever P2 says:")
	print("a verb the player can never afford is content with no caller.")


## Small helpers. Kept local rather than lifted into src/ -- a probe's arithmetic
## is not the game's.
func _mean(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var total := 0.0
	for x in xs:
		total += float(x)
	return total / float(xs.size())


func _median(xs: Array) -> int:
	if xs.is_empty():
		return 0
	var sorted := xs.duplicate()
	sorted.sort()
	return int(sorted[sorted.size() / 2])


func _distinct(xs: Array) -> Array:
	var out := []
	for x in xs:
		if not out.has(x):
			out.append(x)
	out.sort()
	return out


func _pearson(a: Array, b: Array) -> float:
	if a.size() != b.size() or a.size() < 2:
		return 0.0
	var ma := _mean(a)
	var mb := _mean(b)
	var num := 0.0
	var da := 0.0
	var db := 0.0
	for i in range(a.size()):
		var x := float(a[i]) - ma
		var y := float(b[i]) - mb
		num += x * y
		da += x * x
		db += y * y
	if is_zero_approx(da) or is_zero_approx(db):
		return 0.0
	return num / sqrt(da * db)
