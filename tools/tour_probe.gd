extends SceneTree

## V2.6b2's step-0 gate, run BEFORE any src/ edit. The question it answers is the one
## docs/siting-model.md section 11 handed over: reach-per-day makes the capital
## strictly dominant, and the per-region saturation counter is the only honest
## breaker -- so does the counter actually reorder the player's best tour, or does
## the capital still win every month? If it survives every feasible saturation
## strength, the session stops and writes the finding; it builds nothing.
##
## Run: godot --headless --script res://tools/tour_probe.gd
##
## ============================================================================
## THE MODEL, PRE-COMMITTED BEFORE THE SWEEP
## ============================================================================
##
## A meeting month in region r reaches, before saturation, the region's principal
## city share of the nation divided by the journey's travel days -- the reach-per-day
## form section 11 measured (Paris 0.0314 in one day against Marseille 0.0129 over
## three). The fresh factor is normalised mean-one in POPULATION weights, the same
## idiom Siting.normalised() served V2.6b1: the average MEETING delivers the authored
## rate, so V1.7a's calibration survives and only the choice varies it.
##
## Two saturation FORMS are measured, because the draft plan committed one and the
## recorded prose commits another, and the difference is the whole answer:
##
##   FORM A (the draft): saturation is an unbounded accumulator. One meeting month
##     adds A units; the discount is 1/(1+sat); sat decays on a half-life of D
##     months. A is swept here to find whether ANY accrual reorders the tour, and
##     what such an accrual would be CLAIMING: a second meeting reaches 1/(1+A) of
##     fresh, so A = 12 says one month of campaigning spoke to 92 % of the region.
##
##   FORM B (the prose): "whoever has already been spoken to has already been spoken
##     to" is a FRACTION. One meeting month speaks to the region's whole attention:
##     spoken is clamped at 1.0; the discount is (1 - spoken); spoken decays on a
##     half-life of D months. One tuned constant, D, and the discount is bounded in
##     [0, 1] by construction -- no clamp to set wrong, V1.6a's argument.
##
## Month order: the offer is read on the saturation state as the tour arrives
## (decays and accruals of earlier months only), then the meeting accrues, then
## every region decays. Clause (ii) reads the first-visited region's offer after
## the window's last decay, on its actual history.
##
## ============================================================================
## THE TOUR, AND WHY GREEDY IS OPTIMAL
## ============================================================================
##
## One meeting month at a time (campaign_count <= 1 is content), one region per
## month, the window CAMPAIGN_WINDOW_MONTHS long. A region's offer depends only on
## its OWN visit history, so the window's total is a sum of independent per-month
## terms and the month-by-month arg-max is exactly the optimal tour -- an exchange
## argument, not a heuristic. The baseline is CAMPING: the capital every month,
## under the same saturation machinery.
##
## ============================================================================
## THE CLAUSES, FIXED BEFORE THE SWEEP, BOTH IN FACTOR UNITS
## ============================================================================
##
##   (i) REORDER -- the tour must leave the capital. Binary: the optimal tour
##       visits >= 2 distinct regions AND beats camping on the window's total.
##       Continuous slack for the maximin: the month-2 marginal, (best other offer
##       - capital offer) / best other offer -- the first decision the counter
##       has to win.
##   (ii) RETURN -- the decay must not be a burn-list: a region visited once and
##       never again offers >= 0.5 of its fresh factor after the window's remaining
##       months of PURE decay. A property of the half-life alone (form B:
##       1 - 0.5^((W-1)/D) >= 0.5, i.e. D <= W; form A: 1/(1 + A * 0.5^((W-1)/D))).
##
##   *** THE LITERAL CLAUSE WAS MEASURED AND REPLACED, AND THE REASON IS A FINDING.
##   *** The draft read (ii) on the tour's ACTUAL history -- the capital's offer at
##   window end on what really happened. Measured, that clause is incompatible with
##   (i) at ANY saturation strength, because the fresh margin is 7.4x (T2): recovery
##   to 0.5 of fresh returns the capital an offer (2.37 * 0.5 = 1.19) that beats the
##   best other site (0.32) on its own -- so a tour that satisfies the literal (ii)
##   never left in the first place. The literal clause was a DOMINANCE clause
##   wearing a recovery clause's clothes, the same failure V1.5c recorded when a
##   band's two clauses were inconsistent rather than badly tuned -- except here the
##   inconsistency is structural (any margin above ~2x) rather than numerical. The
##   reformulated (ii) measures the DECAY's timescale, decoupled from the tour, and
##   cannot be gamed by how the tour is played.
##
## A candidate passes on BOTH. Selection is maximin relative slack, V1.7a's own
## tiebreaker. The KILL SWITCH: no candidate of either form passes clause (i).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const K = preload("res://src/sim/campaign_constants.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")

const PLAYER := "FRA"
const WINDOW := K.CAMPAIGN_WINDOW_MONTHS
const RECOVERY_FLOOR := 0.5

const D_GRID_B := [1.0, 2.0, 3.0, 4.0, 4.25, 4.5, 4.75, 5.0, 5.25, 5.5, 5.75, 6.0, 6.25, 6.5, 6.75, 7.0, 7.25, 7.5, 8.0, 9.0, 10.0, 12.0, 16.0, 99.0]
const A_GRID := [1.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 16.0]
const D_GRID_A := [1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 99.0]

var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [_loader.errors])
		quit(1)
		return

	print("=== V2.6b2 tour probe (step 0, before any src/ edit) ===")
	print("window %d months, recovery floor %.2f, reach-per-day at %d km/day" % [
		WINDOW, RECOVERY_FLOOR, int(DK.TRAVEL_KM_PER_DAY),
	])

	var tables := {}
	for nation_id in _nation_ids():
		tables[nation_id] = _factor_table(nation_id)

	_table_travel(tables[PLAYER])
	_table_dominance(tables)
	_table_form_b(tables[PLAYER])
	_table_form_a(tables[PLAYER])
	_verdict(tables[PLAYER])
	quit(0)


# --- the register -----------------------------------------------------------------

func _nation_ids() -> Array:
	var out: Array = []
	for id in _loader.nations:
		out.append(String(id))
	out.sort()
	return out


## One row per region: the principal city (largest share IN the region, picked
## explicitly rather than trusting authored order), travel days from the capital,
## the city's nation population share off the live V2.6a registers, and the fresh
## reach-per-day factor normalised mean-one in population weights. Sorted by id.
func _factor_table(nation_id: String) -> Array:
	var state = GameState.new_game(_loader, nation_id)
	var ns = state.player()
	var nation = _loader.nations.get(nation_id)
	var capital_name := String(nation.capital) if nation != null else ""
	var capital_lonlat = _capital_lonlat(nation_id)
	var rows: Array = []
	var raw: Dictionary = {}
	var weights: Dictionary = {}
	for region in _loader.regions.get(nation_id, []):
		var principal = _principal_city(region)
		if principal == null:
			push_error("tour_probe: region %s of %s has no cities" % [region.id, nation_id])
			continue
		var days := _travel_days(capital_lonlat, principal.lonlat)
		var share: float = float(ns.region_pop_share.get(region.id, float(region.share))) \
			* float(ns.city_pop_share.get(principal.id, float(principal.share)))
		raw[String(region.id)] = share / float(days)
		weights[String(region.id)] = share
		rows.append({
			"region_id": String(region.id),
			"region_name": String(region.region_name),
			"city_name": String(principal.city_name),
			"days": days,
			"share": share,
			"is_capital": String(principal.city_name) == capital_name,
		})
	var mean := 0.0
	var weight_sum := 0.0
	for rid in raw:
		mean += float(raw[rid])
		weight_sum += 1.0
	mean = mean / weight_sum if weight_sum > 0.0 else 1.0
	for row in rows:
		row["fresh"] = float(raw[row["region_id"]]) / mean
	rows.sort_custom(func(a, b): return String(a["region_id"]) < String(b["region_id"]))
	return rows


func _principal_city(region) -> Variant:
	var best: Variant = null
	for city in region.cities:
		if best == null or float(city.share) > float(best.share):
			best = city
	return best


func _capital_lonlat(nation_id: String) -> Variant:
	var nation = _loader.nations.get(nation_id)
	if nation == null:
		return null
	var wanted := String(nation.capital)
	for region in _loader.regions.get(nation_id, []):
		for city in region.cities:
			if String(city.city_name) == wanted:
				return city.lonlat
	return null


func _capital_id(rows: Array) -> String:
	for row in rows:
		if bool(row["is_capital"]):
			return String(row["region_id"])
	return ""


## The same pricing Diplomacy.travel_days() applies to capitals, applied to a
## region's principal city. Quoted here rather than preloaded: the probe is
## dev-only, and src/sim/campaign.gd must stay a leaf that preloads constants.
func _travel_days(from_lonlat, to_lonlat) -> int:
	if from_lonlat == null or to_lonlat == null:
		return int(DK.TRAVEL_DAYS_MAX)
	var km := _haversine_km(from_lonlat, to_lonlat)
	return clampi(int(ceil(km / DK.TRAVEL_KM_PER_DAY)), int(DK.TRAVEL_DAYS_MIN), int(DK.TRAVEL_DAYS_MAX))


func _haversine_km(a: Vector2, b: Vector2) -> float:
	const EARTH_RADIUS_KM := 6371.0
	var lon1 := deg_to_rad(a.x)
	var lat1 := deg_to_rad(a.y)
	var lon2 := deg_to_rad(b.x)
	var lat2 := deg_to_rad(b.y)
	var dlat := lat2 - lat1
	var dlon := lon2 - lon1
	var h := sin(dlat * 0.5) * sin(dlat * 0.5) \
		+ cos(lat1) * cos(lat2) * sin(dlon * 0.5) * sin(dlon * 0.5)
	return 2.0 * EARTH_RADIUS_KM * asin(minf(1.0, sqrt(h)))


# --- the tour ----------------------------------------------------------------------

## One stateless simulation: greedy tour, or camping when force_capital. A == null
## is form B; otherwise form A with accrual A. Returns the window total, the site
## order, and the month-2 marginal. Clause (ii) is NOT measured here: it is a
## property of the half-life alone (see _recovery), decoupled from the tour.
func _simulate(rows: Array, D: float, A: Variant, force_capital: bool) -> Dictionary:
	var capital_id := _capital_id(rows)
	var sat := {}
	var total := 0.0
	var order: Array = []
	var m2 := {"capital": -1.0, "other": -1.0}

	for month in WINDOW:
		var chosen := ""
		if force_capital:
			chosen = capital_id
		else:
			var best_offer := -1.0
			for row in rows:
				var rid := String(row["region_id"])
				var offer: float = float(row["fresh"]) * _discount(sat, rid, A)
				if offer > best_offer or (is_equal_approx(offer, best_offer) and chosen != "" and rid < chosen):
					best_offer = offer
					chosen = rid
		var chosen_fresh := 1.0
		for row in rows:
			if String(row["region_id"]) == chosen:
				chosen_fresh = float(row["fresh"])
		total += chosen_fresh * _discount(sat, chosen, A)
		order.append(chosen)
		if month == 1:
			m2["capital"] = _fresh_of(rows, capital_id) * _discount(sat, capital_id, A)
			for row in rows:
				var rid := String(row["region_id"])
				if rid == capital_id:
					continue
				m2["other"] = maxf(m2["other"], float(row["fresh"]) * _discount(sat, rid, A))
		sat[chosen] = _accrue(float(sat.get(chosen, 0.0)), A)
		for rid in sat:
			sat[rid] = float(sat[rid]) * pow(0.5, 1.0 / D)

	return {"total": total, "order": order, "m2": m2}


## Clause (ii): one meeting's saturation, faded by the window's remaining months of
## pure decay, must leave at least RECOVERY_FLOOR of the fresh factor. A property
## of (D, A) alone -- no tour history involved.
func _recovery(D: float, A: Variant) -> float:
	var sat := _accrue(0.0, A)
	for month in WINDOW - 1:
		sat = float(sat) * pow(0.5, 1.0 / D)
	return _discount({"x": sat}, "x", A)


func _discount(sat: Dictionary, rid: String, A: Variant) -> float:
	if A == null:
		return 1.0 - float(sat.get(rid, 0.0))
	return 1.0 / (1.0 + float(sat.get(rid, 0.0)))


func _accrue(current: float, A: Variant) -> float:
	if A == null:
		return minf(1.0, current + 1.0)
	return current + float(A)


func _fresh_of(rows: Array, rid: String) -> float:
	for row in rows:
		if String(row["region_id"]) == rid:
			return float(row["fresh"])
	return 0.0


# --- tables ------------------------------------------------------------------------

func _table_travel(rows: Array) -> void:
	print("")
	print("--- T1  %s: principal cities, travel from the capital, fresh reach-per-day" % PLAYER)
	for row in rows:
		print("  %-24s %-14s %d day%s  share %.4f  fresh x%.2f%s" % [
			row["region_name"], row["city_name"], row["days"],
			"" if int(row["days"]) == 1 else "s", row["share"], row["fresh"],
			"  <- capital" if bool(row["is_capital"]) else "",
		])


func _table_dominance(tables: Dictionary) -> void:
	print("")
	print("--- T2  dominance BEFORE saturation: the capital against the best other")
	for nation_id in tables:
		var rows: Array = tables[nation_id]
		if rows.is_empty():
			continue
		var capital_id := _capital_id(rows)
		if capital_id == "":
			print("  %s  no capital region found" % nation_id)
			continue
		var capital_fresh := _fresh_of(rows, capital_id)
		var other := 0.0
		for row in rows:
			if String(row["region_id"]) != capital_id:
				other = maxf(other, float(row["fresh"]))
		var margin := 0.0
		if other > 0.0:
			margin = capital_fresh / other - 1.0
		print("  %s  capital x%.2f  best other x%.2f  margin %+.0f%%  regions %d" % [
			nation_id, capital_fresh, other, margin * 100.0, rows.size(),
		])


func _table_form_b(rows: Array) -> void:
	print("")
	print("--- T3  FORM B (fraction spoken: one meeting month = the region's whole attention)")
	print("      %-6s %-9s %-9s %-6s %-9s %-9s %s" % [
		"D", "tour", "camp", "dist", "cl (i)", "cl (ii)", "verdict",
	])
	for D in D_GRID_B:
		_print_row("%.1f" % float(D), _simulate(rows, float(D), null, false),
			_simulate(rows, float(D), null, true)["total"], float(D), null)


func _table_form_a(rows: Array) -> void:
	print("")
	print("--- T4  FORM A (unbounded accumulator, the draft: sat += A, discount 1/(1+sat))")
	for A in A_GRID:
		for D in D_GRID_A:
			_print_row("%.1f/%.1f" % [float(A), float(D)], _simulate(rows, float(D), float(A), false),
				_simulate(rows, float(D), float(A), true)["total"], float(D), float(A))


func _print_row(label: String, tour: Dictionary, camp: float, D: float, A: Variant) -> void:
	var distinct := {}
	for rid in tour["order"]:
		distinct[rid] = true
	var reorders: bool = distinct.size() >= 2 and float(tour["total"]) > camp
	var slack_i := 0.0
	if float(tour["m2"]["other"]) > 0.0:
		slack_i = (float(tour["m2"]["other"]) - float(tour["m2"]["capital"])) / float(tour["m2"]["other"])
	var slack_ii: float = (_recovery(D, A) - RECOVERY_FLOOR) / RECOVERY_FLOOR
	var passes: bool = reorders and slack_i > 0.0 and slack_ii >= 0.0
	print("      %-9s %-9.3f %-9.3f %-6d %+9.1f%% %+9.1f%% %s" % [
		label, tour["total"], camp, distinct.size(), slack_i * 100.0, slack_ii * 100.0,
		"PASS" if passes else ("reorder" if reorders else "-"),
	])


func _verdict(rows: Array) -> void:
	print("")
	print("--- T5  verdict")
	var survivors := []
	for D in D_GRID_B:
		var tour := _simulate(rows, float(D), null, false)
		var camp: float = _simulate(rows, float(D), null, true)["total"]
		var distinct := {}
		for rid in tour["order"]:
			distinct[rid] = true
		var slack_i := 0.0
		if float(tour["m2"]["other"]) > 0.0:
			slack_i = (float(tour["m2"]["other"]) - float(tour["m2"]["capital"])) / float(tour["m2"]["other"])
		var slack_ii: float = (_recovery(float(D), null) - RECOVERY_FLOOR) / RECOVERY_FLOOR
		if distinct.size() >= 2 and float(tour["total"]) > camp and slack_i > 0.0 and slack_ii >= 0.0:
			survivors.append({
				"D": float(D), "min_slack": minf(slack_i, slack_ii),
				"slack_i": slack_i, "slack_ii": slack_ii,
			})
	if survivors.is_empty():
		print("  FORM B: no candidate reorders the tour and recovers. KILL SWITCH.")
	else:
		survivors.sort_custom(func(a, b): return float(a["min_slack"]) > float(b["min_slack"]))
		print("  FORM B survivors: %d of %d candidates" % [survivors.size(), D_GRID_B.size()])
		for s in survivors.slice(0, 5):
			print("    D %.1f  clause (i) %+.1f%%  clause (ii) %+.1f%%  min %+.1f%%" % [
				s["D"], s["slack_i"] * 100.0, s["slack_ii"] * 100.0, s["min_slack"] * 100.0,
			])
		print("  FORM B maximin: D = %.1f" % float(survivors[0]["D"]))

	var a_survivors := []
	for A in A_GRID:
		for D in D_GRID_A:
			var tour := _simulate(rows, float(D), float(A), false)
			var camp: float = _simulate(rows, float(D), float(A), true)["total"]
			var distinct := {}
			for rid in tour["order"]:
				distinct[rid] = true
			var slack_i := 0.0
			if float(tour["m2"]["other"]) > 0.0:
				slack_i = (float(tour["m2"]["other"]) - float(tour["m2"]["capital"])) / float(tour["m2"]["other"])
			var slack_ii: float = (_recovery(float(D), float(A)) - RECOVERY_FLOOR) / RECOVERY_FLOOR
			if distinct.size() >= 2 and float(tour["total"]) > camp and slack_i > 0.0 and slack_ii >= 0.0:
				a_survivors.append({"A": float(A), "D": float(D), "min_slack": minf(slack_i, slack_ii)})
	if a_survivors.is_empty():
		print("  FORM A: no (A, D) corner passes both clauses.")
	else:
		a_survivors.sort_custom(func(a, b): return float(a["min_slack"]) > float(b["min_slack"]))
		print("  FORM A corners that pass (%d):" % a_survivors.size())
		for s in a_survivors.slice(0, 6):
			print("    A %.0f  D %.1f  min slack %+.1f%%  (claims one month spoke to %.0f%% of the region)" % [
				s["A"], s["D"], s["min_slack"] * 100.0, (1.0 - 1.0 / (1.0 + float(s["A"]))) * 100.0,
			])
