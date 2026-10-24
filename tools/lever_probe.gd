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
##
## NOT HERE, and why:
##   - B5's channel row (a call at least 0.10 below an audience) is b3's: the
##     phone is not built (Levers.phone).
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

const PLAYER := "FRA"
const WARM_MONTHS := 12
const BANDS := {"stranger": 0.165, "acquaintance": 0.5, "known": 0.835}
const GAIN := 1.0
const GAIN_FLATTER := 0.7
const WEIGHTS := {"grudge": 1.0, "rapport": 0.5, "commitment": 0.15, "bond": 0.30}

var _loader


func _init() -> void:
	var json_path := ""
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--json="):
			json_path = String(arg).substr(7)
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
		"weights": WEIGHTS, "gain_flatter": GAIN_FLATTER}
	out["L1"] = _l1(ns, people)
	out["L2"] = _l2(ns, people)
	out["bands"] = _bands(out)
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


func _l2(ns, people: Array) -> Dictionary:
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
	for person in people:
		for band in BANDS:
			for rel in ["acquaintance", "friend"]:
				for aligned in [true, false]:
					var cell := _cell(ns, person, BANDS[band], rel, aligned)
					var odds := {}
					var cost := {}
					var top := ""
					var top_value := -INF
					for lever in K.LEVERS:
						var p := LeverOdds.odds(person, lever, cell)
						if p < 0.0:
							continue
						odds[lever] = p
						cost[lever] = _spend(person, lever, p)
						offered[lever] += 1
						var value := p * (GAIN_FLATTER if lever == "flatter" else GAIN)
						for r in cost[lever]:
							value -= float(WEIGHTS[r]) * float(cost[lever][r])
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
	return {"best_share": shares, "offered_cells": offered, "dominated_pairs": pairs}


## The expected spend of one attempt, per register (the levers table, paid win or
## lose; flatter's backfire only on a failure).
func _spend(person, lever: String, p: float) -> Dictionary:
	match lever:
		"bargain":
			return {"rapport": K.BARGAIN_FAVOUR_RAPPORT}
		"promise_date":
			return {"commitment": 1.0}
		"pressure":
			return {"rapport": K.PRESSURE_RAPPORT, "grudge": K.PRESSURE_GRUDGE * Characters.grudge_intake(person)}
		"flatter":
			if person.traits.has("principled") and float(person.social_skill) > K.FLATTER_BACKFIRE_SKILL:
				return {"rapport": (1.0 - p) * K.FLATTER_BACKFIRE_RAPPORT}
		"friendship":
			return {"bond": 1.0}
	return {}


func _no_costlier(a: Dictionary, b: Dictionary) -> bool:
	for r in WEIGHTS:
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
	}


func _print(out: Dictionary) -> void:
	var l1: Dictionary = out["L1"]
	var l2: Dictionary = out["L2"]
	print("=== LEVER PROBE (FRA, warmed %d months, approval %.1f) ===" % [WARM_MONTHS, out["approval"]])
	print("L1 mean picked %s | widths %.3f / %.3f | inside %.3f | to acquaintance %s, to known %s" % [
		l1["mean_picked"], l1["width_stranger_edge"], l1["width_known_edge"], l1["inside_share"],
		l1["to_acquaintance"], l1["to_known"]])
	print("L2 best share %s | dominated pairs %s" % [l2["best_share"], l2["dominated_pairs"]])
	for band in out["bands"]:
		print("%-28s %s" % [band, "PASS" if out["bands"][band] else "FAIL"])
