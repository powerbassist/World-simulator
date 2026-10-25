extends SceneTree

## Headless probe: godot --headless --path "<repo>" --script res://tools/lever_probe.gd -- --json=PATH
## Dev-only, never ships. Run it isolated (APPDATA="$(mktemp -d)").
##
## V5.2b b2, the audience's bands (docs/design/bands-v5.2.md B4 and B5), measured
## on a France game run through src/sim/world_month.gd for WARM_MONTHS idle
## months -- the game's own month, never a copy (tests/test_world_month.gd fails
## a copy) -- so standing and approval are a played game's, not a new one's. The
## odds are LeverOdds.odds(), the function the scene reads, on cells built here.
## Two regimes, declared with their bands before the first run:
##
##   L1 BY KNOWLEDGE BAND. Every France person but the president, at each band's
##      midpoint (0.165, 0.5, 0.835), rapport 0, below friend, both asks. The
##      player picks the offered lever with the highest SHOWN midpoint; the row is
##      the mean TRUE odds of that pick.
##      B4: 0.30-0.50 stranger, 0.45-0.65 acquaintance, 0.60-0.80 known, each band
##      at least 0.08 above the one before; the printed width at least 0.30 for a
##      stranger and at most 0.10 for the known; the truth inside 100 %. And,
##      through the real commands (Levers.open, one topic, Levers.close),
##      audiences from a stranger to an acquaintance 2-5, to known at least 8.
##   L2 THE GRID. People x the three bands x {below friend, friend} x {aligned,
##      against}. In each cell, each offered lever's NET VALUE is
##          odds * gain - sum(weight[register] * expected spend[register])
##      with the exchange weights below, declared before the run, in units of one
##      ask won: gain 1.0 (flatter GAIN_FLATTER, its effect is small and does not
##      hold); a grudge point 1.0; a rapport point 0.5 (half: rapport moves later
##      odds, a grudge moves acts); a commitment 0.15 (a date the president must
##      keep or be caught); a step down of a bond 0.30.
##      B5: no Pareto-dominated pair (one lever at least as likely to work AND no
##      costlier on every register in every cell both are offered); no lever best
##      in more than 40 % of the cells it is offered in; every lever best in at
##      least 5 % of them (friendship's denominator is the friend half).
##   L2 WITH THE PHONE (b3). The same grid x the channel {audience, phone}, the
##      band's own grid: a phone cell reads Phone.odds() -- the audience's minus
##      CALL_ODDS_PENALTY, not offered under ODDS_MIN + it -- at the same spends.
##      The three B5 rows above again over both channels (a lever not offered by
##      phone leaves that cell out of its denominator, as friendship's half does),
##      and B5's channel row: in every cell a lever is offered by phone, the
##      audience's odds at least 0.10 above the call's. "L2" stays the audience's
##      alone, so b2's numbers read on.
##   L2 WITH THE SHADOWS (V5.2c, `-- --shadows=PATH`, PATH a shadows_probe JSON).
##      The audience grid with four more rows, each at its EXPECTED cost (B5's
##      amendment): bargain in backroom and in aid (no open spend; P(exposed by
##      month 60) for its evidence kind, S1's per-currency rate from PATH, times the
##      mean over the routes that reach the kind of the armed scandal's price --
##      its arrival plus its cheapest answer, lever_weights.scandal_price); argue
##      with a lie (Lies.catch_chance at the cell's listener and the president, times
##      the reveal); promise a date with a lie (its commitment plus the full reveal,
##      the date inside the term). Each at its raised odds, re-clamped -- and, since
##      a caught lie fails the attempt (#170's call 5), persuading only uncaught:
##      worth (1 - P(caught)) x (p + LIE_ODDS) less its shadow. The rows:
##      0 dominated pairs with the shadow rows in; no row best in more than 40 % of
##      its cells; bargain in any currency together at most 40 %; each honest lever
##      at least 5 %; each shadow row reported.
##
## NOT HERE, and why:
##   - B5's answers row (book, delegate, decline, unanswered: none best in more
##     than half the requests) needs the price of a diary day, which no band
##     states. The lapse half holds by construction -- a lapse costs exactly a
##     decline (tests/test_audiences.gd pins it per request) -- and the rest is a
##     call for the bands' owner.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Levers = preload("res://src/sim/levers.gd")
const LeverOdds = preload("res://src/sim/lever_odds.gd")
const K = preload("res://src/sim/lever_constants.gd")
const PK = preload("res://src/sim/president_constants.gd")
const President = preload("res://src/sim/president.gd")
const Characters = preload("res://src/sim/characters.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const Phone = preload("res://src/sim/phone.gd")
const Events = preload("res://src/sim/events.gd")
const Lies = preload("res://src/sim/lies.gd")
const SC = preload("res://src/sim/shadow_constants.gd")

const PLAYER := "FRA"
const WARM_MONTHS := 12
const BANDS := {"stranger": 0.165, "acquaintance": 0.5, "known": 0.835}
const LW = preload("res://tools/lever_weights.gd")

var _loader


func _init() -> void:
	var json_path := ""
	var shadows_path := ""
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--json="):
			json_path = String(arg).substr(7)
		elif String(arg).begins_with("--shadows="):
			shadows_path = String(arg).substr(10)
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("lever_probe: data did not load: %s" % [_loader.errors])
		quit(1)
		return
	var state = GameState.new_game(_loader, PLAYER)
	for i in range(WARM_MONTHS):
		state.year = 2026 + i / 12
		state.month = i % 12 + 1
		state.day = 1
		WorldMonth.tick_month(state, _loader)
	var ns = state.player()
	var people: Array = []
	for person in _loader.people[PLAYER]:
		if person.id != President.leader_id(ns):
			people.append(person)
	var out := {"schema": 1, "warm_months": WARM_MONTHS, "approval": float(ns.overall_approval_pct),
		"weights": LW.WEIGHTS, "gain_flatter": LW.GAIN_FLATTER}
	out["L1"] = _l1(ns, people)
	out["L2"] = _l2(ns, people, ["audience"])
	out["L2_with_phone"] = _l2(ns, people, ["audience", "phone"])
	out["bands"] = _bands(out)
	if shadows_path != "":
		var rates: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(shadows_path))["summary"]["S1"]["exposed_by_60"]
		out["L2_shadows"] = _l2_shadows(ns, people, rates)
		for band in out["L2_shadows"]["bands"]:
			out["bands"][band] = out["L2_shadows"]["bands"][band]
	_print(out)
	if json_path != "":
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, " ", true) + "\n")
		f.close()
	quit(0)


func _l1(ns, people: Array) -> Dictionary:
	var means := {}
	var inside := 0
	var ranges := 0
	for band in BANDS:
		var k: float = BANDS[band]
		var total := 0.0
		var n := 0
		for person in people:
			for aligned in [true, false]:
				var cell := _cell(ns, person, k, "acquaintance", aligned)
				var best := ""
				var best_mid := -1.0
				for lever in K.LEVERS:
					var p := LeverOdds.odds(person, lever, cell)
					if p < 0.0:
						continue
					var r: Vector2 = LeverOdds.shown_range(person.id, lever, p, k)
					ranges += 1
					if p >= r.x - 0.000001 and p <= r.y + 0.000001:
						inside += 1
					if (r.x + r.y) * 0.5 > best_mid:
						best_mid = (r.x + r.y) * 0.5
						best = lever
				total += LeverOdds.odds(person, best, cell)
				n += 1
		means[band] = total / float(n)
	var steps := _interactions(people)
	return {
		"mean_picked": means,
		"width_stranger_edge": LeverOdds.fog_width(PK.KNOWLEDGE_ACQUAINTANCE - 0.001),
		"width_known_edge": LeverOdds.fog_width(PK.KNOWLEDGE_KNOWN),
		"inside_share": float(inside) / float(ranges),
		"to_acquaintance": steps["to_acquaintance"],
		"to_known": steps["to_known"],
	}


## Audiences with one topic each, through the real commands on a fresh game, until
## each person is known: {to_acquaintance: [min, max], to_known: [min, max]}.
func _interactions(people: Array) -> Dictionary:
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	state.day = 1
	var ns = state.player()
	var acq := [999, -1]
	var known := [999, -1]
	for person in people:
		var to_acq := -1
		var to_known := -1
		for n in range(1, 40):
			var row := {"id": "%s|probe%d" % [person.id, n], "person_id": person.id, "object": "programme:none",
				"stance": "sponsor", "arrived_month": 0, "deadline_month": 99999, "status": AK.STATUS_BOOKED,
				"date": {"year": 2026, "month": 1, "day": 1}, "resolved_month": -1}
			ns.audience_requests.append(row)
			var s: Dictionary = Levers.open(state, ns, _loader, String(row["id"]))
			Levers.talk(state, ns, _loader, s, "opinion")
			Levers.close(state, ns, _loader, s)
			var k := President.knowledge(ns, person.id)
			if to_acq < 0 and k >= PK.KNOWLEDGE_ACQUAINTANCE:
				to_acq = n
			if k >= PK.KNOWLEDGE_KNOWN:
				to_known = n
				break
		acq = [mini(acq[0], to_acq), maxi(acq[1], to_acq)]
		known = [mini(known[0], to_known), maxi(known[1], to_known)]
	return {"to_acquaintance": acq, "to_known": known}


func _l2(ns, people: Array, channels: Array) -> Dictionary:
	var best := {}
	var offered := {}
	var dominated := {}
	# Pareto: never worse in any shared cell AND strictly better in at least one --
	# two levers equal everywhere dominate neither.
	var strictly := {}
	for a in K.LEVERS:
		best[a] = 0
		offered[a] = 0
		for b in K.LEVERS:
			if a != b:
				dominated["%s>%s" % [a, b]] = true
				strictly["%s>%s" % [a, b]] = false
	var phone_cells := 0
	var gap_min := INF
	for person in people:
		for band in BANDS:
			for rel in ["acquaintance", "friend"]:
				for aligned in [true, false]:
					for channel in channels:
						var cell := _cell(ns, person, BANDS[band], rel, aligned)
						var odds := {}
						var cost := {}
						var top := ""
						var top_value := -INF
						for lever in K.LEVERS:
							var p := LeverOdds.odds(person, lever, cell) if channel == "audience" else Phone.odds(person, lever, cell)
							if p < 0.0:
								continue
							if channel == "phone":
								phone_cells += 1
								gap_min = minf(gap_min, LeverOdds.odds(person, lever, cell) - p)
							odds[lever] = p
							cost[lever] = LW.spend(person, lever, p)
							offered[lever] += 1
							var value := LW.net(person, lever, p)
							if value > top_value:
								top_value = value
								top = lever
						best[top] += 1
						for key in dominated:
							var pair: PackedStringArray = String(key).split(">")
							if not odds.has(pair[0]) or not odds.has(pair[1]):
								continue
							if float(odds[pair[0]]) < float(odds[pair[1]]) or not _no_costlier(cost[pair[0]], cost[pair[1]]):
								dominated[key] = false
							elif float(odds[pair[0]]) > float(odds[pair[1]]) or not _no_costlier(cost[pair[1]], cost[pair[0]]):
								strictly[key] = true
	var shares := {}
	for lever in K.LEVERS:
		shares[lever] = float(best[lever]) / float(maxi(1, offered[lever]))
	var pairs: Array = []
	for key in dominated:
		if dominated[key] and strictly[key]:
			pairs.append(key)
	var out := {"best_share": shares, "offered_cells": offered, "dominated_pairs": pairs}
	if channels.has("phone"):
		out["phone_lever_cells"] = phone_cells
		out["phone_gap_min"] = gap_min
	return out


const SHADOW_ROWS := ["bargain_backroom", "bargain_aid", "argue_lie", "promise_date_lie"]


## L2 with the shadows: the honest six as L2 has them, plus SHADOW_ROWS at their
## expected cost, in a register of their own ("shadow", in asks) beside the spends.
func _l2_shadows(ns, people: Array, rates: Dictionary) -> Dictionary:
	var price := {}
	for kind in ["favour", "diverted_budget"]:
		var total := 0.0
		var n := 0
		for route in SC.ROUTES:
			var ev = Events.exposure_event(_loader, route, kind) if SC.ROUTE_KINDS[route].has(kind) else null
			if ev != null:
				total += LW.scandal_price(ev)
				n += 1
		price[kind] = total / maxf(1.0, float(n))
	var expected := {"bargain_backroom": float(rates["favour"]) * float(price["favour"]),
		"bargain_aid": float(rates["diverted_budget"]) * float(price["diverted_budget"])}
	var names: Array = K.LEVERS + SHADOW_ROWS
	var best := {}
	var offered := {}
	var dominated := {}
	var strictly := {}
	for a in names:
		best[a] = 0
		offered[a] = 0
		for b in names:
			if a != b:
				dominated["%s>%s" % [a, b]] = true
				strictly["%s>%s" % [a, b]] = false
	var bargain_cells := 0
	var bargain_best := 0
	# c1c rule 3's rows: per lie row, the cells it is offered in and leads its honest
	# lever on odds; argue's value lead, with whether every such listener reads below
	# the president (the lie pays only against a poorer reader).
	var lie_cells := {"argue_lie": 0, "promise_date_lie": 0}
	var lie_odds_lead := {"argue_lie": 0, "promise_date_lie": 0}
	var argue_value_lead := 0
	var argue_lead_readers_below := true
	var leader = _loader.person_by_id[President.leader_id(ns)]
	for person in people:
		for band in BANDS:
			for rel in ["acquaintance", "friend"]:
				for aligned in [true, false]:
					var cell := _cell(ns, person, BANDS[band], rel, aligned)
					var odds := {}
					var cost := {}
					var value := {}
					for lever in K.LEVERS:
						var p := LeverOdds.odds(person, lever, cell)
						if p < 0.0:
							continue
						odds[lever] = p
						cost[lever] = LW.spend(person, lever, p)
						value[lever] = LW.net(person, lever, p)
					if odds.has("bargain"):
						bargain_cells += 1
						for row in ["bargain_backroom", "bargain_aid"]:
							var cur: String = K.CURRENCY_BACKROOM if row == "bargain_backroom" else K.CURRENCY_AID
							var p := clampf(float(odds["bargain"]) + float(SC.CURRENCY_ODDS[cur]), K.ODDS_MIN, K.ODDS_MAX)
							odds[row] = p
							cost[row] = {"shadow": expected[row]}
							# c1c rule 2: a bribe buys the act, not the person -- a corrupt win
							# is valued as flatter's, which also does not hold.
							value[row] = p * LW.GAIN_FLATTER - float(expected[row])
					for base in ["argue", "promise_date"]:
						if not odds.has(base):
							continue
						var row := "%s_lie" % base
						var p := clampf(float(odds[base]) + SC.LIE_ODDS, K.ODDS_MIN, K.ODDS_MAX)
						var reveal := LW.reveal_price(person, BANDS[band], 1.0 - p)
						var caught := Lies.catch_chance(float(person.social_skill), float(leader.social_skill))
						var shadow: float = reveal if base == "promise_date" else caught * reveal
						var spent: Dictionary = LW.spend(person, base, p).duplicate()
						spent["shadow"] = shadow
						# A caught lie fails the attempt: it persuades only uncaught.
						odds[row] = (1.0 - caught) * p
						cost[row] = spent
						value[row] = float(odds[row]) * LW.GAIN - LW.cost(LW.spend(person, base, p)) - shadow
						lie_cells[row] += 1
						if float(odds[row]) > float(odds[base]):
							lie_odds_lead[row] += 1
						if base == "argue" and float(value[row]) > float(value[base]):
							argue_value_lead += 1
							if not (float(person.social_skill) < float(leader.social_skill)):
								argue_lead_readers_below = false
					var top := ""
					var top_value := -INF
					for name in names:
						if not odds.has(name):
							continue
						offered[name] += 1
						if float(value[name]) > top_value:
							top_value = float(value[name])
							top = name
					best[top] += 1
					if top == "bargain" or top == "bargain_backroom" or top == "bargain_aid":
						bargain_best += 1
					for key in dominated:
						var pair: PackedStringArray = String(key).split(">")
						if not odds.has(pair[0]) or not odds.has(pair[1]):
							continue
						if float(odds[pair[0]]) < float(odds[pair[1]]) or not _no_costlier_shadow(cost[pair[0]], cost[pair[1]]):
							dominated[key] = false
						elif float(odds[pair[0]]) > float(odds[pair[1]]) or not _no_costlier_shadow(cost[pair[1]], cost[pair[0]]):
							strictly[key] = true
	var shares := {}
	for name in names:
		shares[name] = float(best[name]) / float(maxi(1, offered[name]))
	var pairs: Array = []
	for key in dominated:
		if dominated[key] and strictly[key]:
			pairs.append(key)
	var top_share := 0.0
	var honest_floor := 1.0
	for name in names:
		top_share = maxf(top_share, float(shares[name]))
		if K.LEVERS.has(name):
			honest_floor = minf(honest_floor, float(shares[name]))
	var bargain_share := float(bargain_best) / float(maxi(1, bargain_cells))
	var lie_lead_share := {}
	var lie_floor := 1.0
	for row in lie_cells:
		lie_lead_share[row] = float(lie_odds_lead[row]) / float(maxi(1, lie_cells[row]))
		lie_floor = minf(lie_floor, float(lie_lead_share[row]))
	return {"rates": rates, "scandal_price": price, "expected_cost": expected, "best_share": shares,
		"offered_cells": offered, "dominated_pairs": pairs, "bargain_share": bargain_share,
		"lie_odds_lead_share": lie_lead_share, "argue_lie_value_lead_cells": argue_value_lead,
		"bands": {
			"B5_shadows_no_dominated_pair": pairs.is_empty(),
			"B5_shadows_none_best_over_40pct": top_share <= 0.40,
			"B5_shadows_bargain_together_40pct": bargain_share <= 0.40,
			"B5_shadows_honest_each_best_5pct": honest_floor >= 0.05,
			# c1c rule 3 (declared on #182): the lie pays only in its corner.
			"B5_lie_argue_value_corner": argue_value_lead >= 1 and argue_lead_readers_below,
			"B5_lie_leads_odds_5pct": lie_floor >= 0.05,
		}}


## _no_costlier over the spends and the shadow register (expected asks).
func _no_costlier_shadow(a: Dictionary, b: Dictionary) -> bool:
	if float(a.get("shadow", 0.0)) > float(b.get("shadow", 0.0)) + 0.000000001:
		return false
	return _no_costlier(a, b)


func _no_costlier(a: Dictionary, b: Dictionary) -> bool:
	for r in LW.WEIGHTS:
		if float(a.get(r, 0.0)) > float(b.get(r, 0.0)) + 0.000000001:
			return false
	return true


func _cell(ns, person, k: float, rel: String, aligned: bool) -> Dictionary:
	return {"knowledge": k, "rapport": 0.0, "relationship": rel, "aligned": aligned,
		"standing": float(ns.person_standing.get(person.id, 0.5)), "approval": float(ns.overall_approval_pct)}


func _bands(out: Dictionary) -> Dictionary:
	var l1: Dictionary = out["L1"]
	var m: Dictionary = l1["mean_picked"]
	var l2: Dictionary = out["L2"]
	var shares: Dictionary = l2["best_share"]
	var top := 0.0
	var floor_ := 1.0
	for lever in shares:
		top = maxf(top, float(shares[lever]))
		floor_ = minf(floor_, float(shares[lever]))
	var l2p: Dictionary = out["L2_with_phone"]
	var top_p := 0.0
	var floor_p := 1.0
	for lever in l2p["best_share"]:
		top_p = maxf(top_p, float(l2p["best_share"][lever]))
		floor_p = minf(floor_p, float(l2p["best_share"][lever]))
	return {
		"B4_stranger_30_50": float(m["stranger"]) >= 0.30 and float(m["stranger"]) <= 0.50,
		"B4_acquaintance_45_65": float(m["acquaintance"]) >= 0.45 and float(m["acquaintance"]) <= 0.65,
		"B4_known_60_80": float(m["known"]) >= 0.60 and float(m["known"]) <= 0.80,
		"B4_rises_0.08": float(m["acquaintance"]) - float(m["stranger"]) >= 0.08 and float(m["known"]) - float(m["acquaintance"]) >= 0.08,
		"B4_width_stranger_0.30": float(l1["width_stranger_edge"]) >= 0.30,
		"B4_width_known_0.10": float(l1["width_known_edge"]) <= 0.10,
		"B4_truth_inside_100pct": float(l1["inside_share"]) == 1.0,
		"B4_acquaintance_in_2_5": int(l1["to_acquaintance"][0]) >= 2 and int(l1["to_acquaintance"][1]) <= 5,
		"B4_known_in_8_plus": int(l1["to_known"][0]) >= 8,
		"B5_no_dominated_pair": (l2["dominated_pairs"] as Array).is_empty(),
		"B5_none_best_over_40pct": top <= 0.40,
		"B5_each_best_5pct": floor_ >= 0.05,
		"B5_with_phone_no_dominated_pair": (l2p["dominated_pairs"] as Array).is_empty(),
		"B5_with_phone_none_best_over_40pct": top_p <= 0.40,
		"B5_with_phone_each_best_5pct": floor_p >= 0.05,
		"B5_phone_at_least_0.10_below": int(l2p["phone_lever_cells"]) > 0 and float(l2p["phone_gap_min"]) >= 0.10 - 0.000000001,
	}


func _print(out: Dictionary) -> void:
	var l1: Dictionary = out["L1"]
	var l2: Dictionary = out["L2"]
	print("=== LEVER PROBE (FRA, warmed %d months, approval %.1f) ===" % [WARM_MONTHS, out["approval"]])
	print("L1 mean picked %s | widths %.3f / %.3f | inside %.3f | to acquaintance %s, to known %s" % [
		l1["mean_picked"], l1["width_stranger_edge"], l1["width_known_edge"], l1["inside_share"],
		l1["to_acquaintance"], l1["to_known"]])
	print("L2 best share %s | dominated pairs %s" % [l2["best_share"], l2["dominated_pairs"]])
	var l2p: Dictionary = out["L2_with_phone"]
	print("L2 with the phone: best share %s | dominated pairs %s | phone lever cells %d, smallest gap %.4f" % [
		l2p["best_share"], l2p["dominated_pairs"], l2p["phone_lever_cells"], l2p["phone_gap_min"]])
	if out.has("L2_shadows"):
		var l2s: Dictionary = out["L2_shadows"]
		print("L2 with the shadows: rates %s | scandal price %s | expected %s" % [l2s["rates"], l2s["scandal_price"], l2s["expected_cost"]])
		print("  best share %s | bargain together %.3f | dominated pairs %s" % [l2s["best_share"], l2s["bargain_share"], l2s["dominated_pairs"]])
		print("  lie leads on odds %s | argue lie leads argue on value in %d cells" % [l2s["lie_odds_lead_share"], l2s["argue_lie_value_lead_cells"]])
	for band in out["bands"]:
		print("%-28s %s" % [band, "PASS" if out["bands"][band] else "FAIL"])
