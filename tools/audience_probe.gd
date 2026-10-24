extends SceneTree

## Headless probe: godot --headless --path "<repo>" --script res://tools/audience_probe.gd -- --json=PATH
## Dev-only, never ships. Run it isolated (APPDATA="$(mktemp -d)").
##
## V5.2b, the requests' bands (docs/design/bands-v5.2.md B1, B2, B3), measured on
## a France game run through src/sim/world_month.gd -- the game's own month,
## never a copy (tests/test_world_month.gd fails a copy). Three regimes, declared
## with their bands before the first run:
##
##   A1 IDLE. Nothing answered: every request lapses into a decline.
##      B1: 24-48 arrivals in 60 months; the first by month 3; >= 8 in months
##      1-20; >= 12 distinct people; no one person over 25 % of them.
##      B3: >= 1 act (brief, resign, defect, challenge) by a person refused before
##      it by month 60; >= 1 refused person whose grudge the card names (>= 0.05,
##      the top bar's own threshold) by month 20.
##   A2 BOOK EVERYTHING. day_probe.gd's (D2) greedy packer fills the diary first
##      each month -- every available state visit, warmest first, then a law, then
##      a reshuffle, each at the 15th and scanned outward -- and then every waiting
##      request is booked on its first free offered day; an unplaceable one is
##      delegated, its card checked for the other two answers. The month's diary
##      fires at month end in day order; an audience held with no lever settles as
##      a refusal (the levers are V5.2b's second half).
##      B2: 20-50 % of requests unplaceable; 12-30 audiences held in 60 months
##      and >= 4 in months 1-20; 100 % of unplaceable requests offer delegate and
##      decline.
##   A3 DECLINE EVERYTHING on arrival. B3's act row again, under explicit declines,
##      and the per-request price beside A1's lapse (tests/test_audiences.gd pins
##      the equality per request; this reports the means).
##
## Months are numbered from 1, the first month the game ticks (January 2026).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalK = preload("res://src/sim/calendar_constants.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const CabinetK = preload("res://src/sim/cabinet_constants.gd")

const PLAYER := "FRA"
const MONTHS := 60
const NAMED_GRUDGE := 0.05

var _loader


func _init() -> void:
	var json_path := ""
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--json="):
			json_path = String(arg).substr(7)
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("audience_probe: data did not load: %s" % [_loader.errors])
		quit(1)
		return
	var out := {"schema": 1, "months": MONTHS, "regimes": {}}
	for regime in ["A1", "A2", "A3"]:
		out["regimes"][regime] = _run(regime)
	out["bands"] = _bands(out["regimes"])
	_print(out)
	if json_path != "":
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, " ", true) + "\n")
		f.close()
	quit(0)


func _run(regime: String) -> Dictionary:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	var arrivals: Array = []      # [month, person_id]
	var refused_at := {}          # person_id -> first month refused
	var acts_by_refused: Array = []
	var named_by_20 := 0
	var unplaceable := 0
	var unplaceable_offered := 0
	var booked := 0
	var held: Array = []          # months
	var decline_grudge := 0.0
	var declines := 0
	var peak := {}                # person_id -> highest grudge seen after a refusal
	for i in range(MONTHS):
		var month := i + 1
		state.year = 2026 + i / 12
		state.month = i % 12 + 1
		state.day = 1
		var fire: Array = []
		if regime == "A2":
			fire = _pack(state)
		for row in Audiences.pending(ns):
			var id := String(row["id"])
			if regime == "A3":
				var r: Dictionary = Audiences.decline(state, ns, _loader, id)
				decline_grudge += float(r["price"]["grudge"])
				declines += 1
				refused_at[String(row["person_id"])] = refused_at.get(String(row["person_id"]), month)
			elif regime == "A2":
				var placed := false
				for d in Audiences.offered_dates(state, ns, id):
					if bool(d["free"]) and bool(Audiences.book(state, ns, _loader, id, d)["ok"]):
						placed = true
						booked += 1
						break
				if not placed:
					unplaceable += 1
					var answers: Dictionary = Audiences.answers(state, ns, _loader, id)
					if bool(answers["delegate"]["ok"]) and bool(answers["decline"]["ok"]):
						unplaceable_offered += 1
					Audiences.delegate(state, ns, _loader, id)
		if regime == "A2":
			_fire_month(state, fire, held, month, refused_at)
		var report: Dictionary = WorldMonth.tick_month(state, _loader)
		for row in report["audience_requests"]["arrived"]:
			arrivals.append([month, String(row["person_id"])])
		for row in report["audience_requests"]["lapsed"]:
			refused_at[String(row["person_id"])] = refused_at.get(String(row["person_id"]), month)
		for act in report.get("character_acts", []):
			var pid := String(act["person_id"])
			if refused_at.has(pid) and int(refused_at[pid]) <= month:
				acts_by_refused.append([month, pid, String(act["act"])])
		for pid in refused_at:
			peak[pid] = maxf(float(peak.get(pid, 0.0)), float(ns.person_grudges.get(pid, 0.0)))
		if month == 20:
			for pid in refused_at:
				if float(ns.person_grudges.get(pid, 0.0)) >= NAMED_GRUDGE:
					named_by_20 += 1
	var per_person := {}
	for a in arrivals:
		per_person[a[1]] = int(per_person.get(a[1], 0)) + 1
	var top := 0
	for pid in per_person:
		top = maxi(top, int(per_person[pid]))
	var first := -1
	var by_20 := 0
	for a in arrivals:
		if first < 0:
			first = int(a[0])
		if int(a[0]) <= 20:
			by_20 += 1
	var held_by_20 := 0
	for m in held:
		if int(m) <= 20:
			held_by_20 += 1
	return {
		"arrivals": arrivals.size(),
		"first_month": first,
		"arrivals_m1_20": by_20,
		"distinct_people": per_person.size(),
		"top_person_share": float(top) / maxf(1.0, float(arrivals.size())),
		"acts_by_refused": acts_by_refused,
		"named_grudges_m20": named_by_20,
		"booked": booked,
		"unplaceable": unplaceable,
		"unplaceable_share": float(unplaceable) / maxf(1.0, float(booked + unplaceable)),
		"unplaceable_offered_share": float(unplaceable_offered) / maxf(1.0, float(unplaceable)),
		"held": held.size(),
		"held_m1_20": held_by_20,
		"mean_decline_grudge": decline_grudge / maxf(1.0, float(declines)),
		"refused_peak_grudges": _top(peak, per_person),
	}


## The five refused people whose grudge climbed highest, for the act row's
## reading: [person, peak grudge, requests made, traits].
func _top(peak: Dictionary, per_person: Dictionary) -> Array:
	var ids: Array = peak.keys()
	ids.sort_custom(func(a, b): return float(peak[a]) > float(peak[b]))
	var out: Array = []
	for pid in ids.slice(0, 5):
		var person = _loader.person_by_id.get(pid)
		out.append([pid, snappedf(float(peak[pid]), 0.001), int(per_person.get(pid, 0)), person.traits if person != null else []])
	return out


## day_probe.gd's (D2) packer for one month: visits warmest first, a law, a
## reshuffle, each at the 15th then scanned outward. Returns the entries to fire
## at month end (fired then, not now, so they occupy the diary all month -- the
## measuring-the-wrong-state error day_probe records).
func _pack(state) -> Array:
	var wants: Array = []
	var ids: Array = _loader.nations.keys()
	ids.sort()
	var visit = _action("state_visit")
	for id in ids:
		if String(id) != PLAYER and Diplomacy.available(state, _loader.diplomatic_actions, PLAYER, String(id)).has(visit):
			wants.append(String(id))
	wants.sort_custom(func(a, b): return Diplomacy.score(state, PLAYER, a) > Diplomacy.score(state, PLAYER, b))
	var laws := Legislature.available(state.player(), _loader.laws)
	if not laws.is_empty():
		wants.append("law:" + String(laws[0].id))
	if state.player().coalition_party_ids.size() > 0:
		wants.append("reshuffle")
	var fire: Array = []
	var dim := Calendar.days_in_month(state.year, state.month)
	for want in wants:
		var entry: Dictionary
		if want.begins_with("law:"):
			entry = Calendar.make_entry(CalK.KIND_LAW, state.year, state.month, 15, "", "", want.substr(4))
		elif want == "reshuffle":
			entry = Calendar.make_entry(CalK.KIND_RESHUFFLE, state.year, state.month, 15, "", "", "",
				String(CabinetK.PORTFOLIO_KEYS[0]), String(state.player().coalition_party_ids[0]))
		else:
			entry = Calendar.make_entry(CalK.KIND_DIPLOMATIC, state.year, state.month, 15,
				"state_visit", want, "", "", "", "", Diplomacy.travel_days(_loader, PLAYER, want))
		var days: Array = [15]
		for d in range(1, dim + 1):
			if d != 15:
				days.append(d)
		for d in days:
			entry["day"] = d
			if bool(Calendar.book(state, entry)["ok"]):
				fire.append(entry.duplicate(true))
				break
	return fire


## The month happens: the packer's acts and the month's audiences, in day order.
func _fire_month(state, fire: Array, held: Array, month: int, refused_at: Dictionary) -> void:
	var ns = state.player()
	var dim := Calendar.days_in_month(state.year, state.month)
	for e in Calendar.due(state, state.year, state.month, dim):
		if String(e["kind"]) == CalK.KIND_AUDIENCE:
			fire.append(e.duplicate(true))
	fire.sort_custom(func(a, b): return int(a.get("day", 0)) < int(b.get("day", 0)))
	for e in fire:
		match String(e["kind"]):
			CalK.KIND_DIPLOMATIC:
				Diplomacy.execute(state, _loader.diplomatic_actions, _action("state_visit"), PLAYER, String(e["target_id"]))
			CalK.KIND_LAW:
				for law in _loader.laws:
					if String(law.id) == String(e["law_id"]):
						Legislature.propose(state, _loader, law)
						break
			CalK.KIND_RESHUFFLE:
				var party_list: Array = _loader.parties.get(PLAYER, [])
				if Cabinet.can_assign(ns, String(e["portfolio"]), String(e["party_id"])):
					Cabinet.assign(state, String(e["portfolio"]), String(e["party_id"]), party_list)
			CalK.KIND_AUDIENCE:
				var id := String(e["action_id"])
				if bool(Audiences.hold(state, ns, _loader, id)["ok"]):
					held.append(month)
					Audiences.settle(state, ns, _loader, id, AK.STATUS_DECLINED)
					var pid := String(e["target_id"])
					refused_at[pid] = refused_at.get(pid, month)
		Calendar.resolve(state, Calendar.verb_key(e), true)


func _action(id: String):
	for action in _loader.diplomatic_actions:
		if String(action.id) == id:
			return action
	return null


func _bands(r: Dictionary) -> Dictionary:
	var a1: Dictionary = r["A1"]
	var a2: Dictionary = r["A2"]
	var a3: Dictionary = r["A3"]
	return {
		"B1_arrivals_24_48": int(a1["arrivals"]) >= 24 and int(a1["arrivals"]) <= 48,
		"B1_first_by_month_3": int(a1["first_month"]) >= 1 and int(a1["first_month"]) <= 3,
		"B1_at_least_8_in_m1_20": int(a1["arrivals_m1_20"]) >= 8,
		"B1_at_least_12_people": int(a1["distinct_people"]) >= 12,
		"B1_no_one_over_25pct": float(a1["top_person_share"]) <= 0.25,
		"B2_unplaceable_20_50pct": float(a2["unplaceable_share"]) >= 0.20 and float(a2["unplaceable_share"]) <= 0.50,
		"B2_held_12_30": int(a2["held"]) >= 12 and int(a2["held"]) <= 30,
		"B2_held_4_by_m20": int(a2["held_m1_20"]) >= 4,
		"B2_unplaceable_offer_100pct": int(a2["unplaceable"]) == 0 or float(a2["unplaceable_offered_share"]) == 1.0,
		"B3_act_by_refused_m60_A1": (a1["acts_by_refused"] as Array).size() >= 1,
		"B3_act_by_refused_m60_A3": (a3["acts_by_refused"] as Array).size() >= 1,
		"B3_named_grudge_m20_A1": int(a1["named_grudges_m20"]) >= 1,
	}


func _print(out: Dictionary) -> void:
	print("=== AUDIENCE PROBE (FRA, %d months) ===" % MONTHS)
	for regime in out["regimes"]:
		var r: Dictionary = out["regimes"][regime]
		print("%s arrivals %d first %d m1-20 %d people %d top %.2f | booked %d unplaceable %d (%.2f, offered %.2f) held %d (m1-20 %d) | acts by refused %d named m20 %d | decline grudge %.3f" % [
			regime, r["arrivals"], r["first_month"], r["arrivals_m1_20"], r["distinct_people"], r["top_person_share"],
			r["booked"], r["unplaceable"], r["unplaceable_share"], r["unplaceable_offered_share"], r["held"], r["held_m1_20"],
			(r["acts_by_refused"] as Array).size(), r["named_grudges_m20"], r["mean_decline_grudge"]])
		print("   highest refused grudges: %s" % [r["refused_peak_grudges"]])
	for band in out["bands"]:
		print("%-32s %s" % [band, "PASS" if out["bands"][band] else "FAIL"])
