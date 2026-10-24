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
##   A4 PHONE FIRST (V5.2b b3; bands-v5.2.md B5's channel row as amended in #119):
##      A2's machine, but each month every open request (pending or booked) is
##      phoned once first -- the offered phone lever with the highest SHOWN midpoint,
##      the way L1's player reads the card -- and only what the phone does not answer
##      is booked. B5 (channel): B2's audiences row still holds -- 12-30 held in 60
##      months, >= 4 in months 1-20.
##   A3 DECLINE EVERYTHING on arrival. B3's act row again, under explicit declines,
##      and the per-request price beside A1's lapse (tests/test_audiences.gd pins
##      the equality per request; this reports the means).
##   A2F (`-- --b5-answers`, V5.2b b2.1) B5's ANSWERS ROW: A2's machine run
##      B5_MONTHS, so every request of months 1-B5_ARRIVALS_UPTO is followed to its
##      due month (answered the month after it arrives, due BOOKING_HORIZON_MONTHS
##      on). Per request, bands-v5.2.md "B5 amendment"'s net values, in
##      tools/lever_weights.gd's units, the diary day at its DIARY_DAY:
##        Book = (1 - q^3) - s(1 + q + q^2) - q^3 x Decline's cost - DIARY_DAY, for
##               the lever with the best single attempt in the person's cell at
##               arrival (p its odds, q = 1 - p, s its spend);
##        Delegate = -(0.25 g + 0.5 x snub) + (0.5 x 0.10 kept | -(0.75 g + 0.08 +
##               0.5 x 0.2) broken), kept = the want served at the due month;
##        Decline = Unanswered = -(g + 0.5 x 0.1), g the refusal grudge at arrival.
##      B5: no answer the best in more than 50 % of requests (a tie counts for
##      each answer it ties). Off by default, so A1-A3's table stays comparable.
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

const LeverOdds = preload("res://src/sim/lever_odds.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const LW = preload("res://tools/lever_weights.gd")
const President = preload("res://src/sim/president.gd")
const Phone = preload("res://src/sim/phone.gd")

const PLAYER := "FRA"
const MONTHS := 60
const B5_ARRIVALS_UPTO := 60
const B5_MONTHS := B5_ARRIVALS_UPTO + 1 + CalK.BOOKING_HORIZON_MONTHS
const NAMED_GRUDGE := 0.05

var _loader


func _init() -> void:
	var json_path := ""
	var b5 := false
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--json="):
			json_path = String(arg).substr(7)
		elif String(arg) == "--b5-answers":
			b5 = true
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("audience_probe: data did not load: %s" % [_loader.errors])
		quit(1)
		return
	var out := {"schema": 1, "months": MONTHS, "regimes": {}}
	for regime in ["A1", "A2", "A3", "A4"]:
		out["regimes"][regime] = _run(regime)
	out["bands"] = _bands(out["regimes"])
	if b5:
		out["b5_answers"] = _b5_answers(_run("A2F", B5_MONTHS)["b5_requests"])
		out["bands"]["B5_answers_none_over_50pct"] = float(out["b5_answers"]["top_share"]) <= 0.50
	_print(out)
	if json_path != "":
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, " ", true) + "\n")
		f.close()
	quit(0)


func _run(regime: String, months := MONTHS) -> Dictionary:
	var book_all := regime == "A2" or regime == "A2F" or regime == "A4"
	var calls := 0
	var answered_by_phone := 0
	var b5_requests: Array = []
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
	for i in range(months):
		var month := i + 1
		state.year = 2026 + i / 12
		state.month = i % 12 + 1
		state.day = 1
		var fire: Array = []
		if book_all:
			fire = _pack(state)
		if regime == "A4":
			for row in ns.audience_requests.duplicate():
				if AK.OPEN.has(String(row.get("status", ""))):
					var call := _phone_first(state, ns, String(row["person_id"]))
					calls += 1 if bool(call.get("ok", false)) else 0
					answered_by_phone += 1 if bool(call.get("success", false)) else 0
		for row in Audiences.pending(ns):
			var id := String(row["id"])
			if regime == "A3":
				var r: Dictionary = Audiences.decline(state, ns, _loader, id)
				decline_grudge += float(r["price"]["grudge"])
				declines += 1
				refused_at[String(row["person_id"])] = refused_at.get(String(row["person_id"]), month)
			elif book_all:
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
		if book_all:
			_fire_month(state, fire, held, month, refused_at)
		var report: Dictionary = WorldMonth.tick_month(state, _loader)
		for row in report["audience_requests"]["arrived"]:
			arrivals.append([month, String(row["person_id"])])
			if regime == "A2F" and month <= B5_ARRIVALS_UPTO:
				b5_requests.append(_b5_capture(ns, row, month))
		for r in b5_requests:
			if int(r["due_loop_month"]) == month:
				r["kept"] = bool(ns.person_want_state.get("%s|%s" % [r["person_id"], r["object"]], false))
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
	var result := {
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
	if regime == "A4":
		result["calls"] = calls
		result["answered_by_phone"] = answered_by_phone
	# Only A2F carries its rows, so A1-A3's table stays byte-comparable.
	if regime == "A2F":
		result["b5_requests"] = b5_requests
	return result


## One arriving request, as B5's answers row reads it: the person's cell, the
## refusal grudge g and the snub now; whether the want is served is read at the
## due month (the answer the month after arrival, plus the diary's horizon).
func _b5_capture(ns, row: Dictionary, month: int) -> Dictionary:
	var pid := String(row["person_id"])
	var person = _loader.person_by_id[pid]
	var cell := {
		"knowledge": President.knowledge(ns, pid),
		"rapport": President.rapport(ns, pid),
		"relationship": President.relationship(ns, pid),
		"aligned": bool(ns.person_want_state.get("%s|%s" % [pid, String(row["object"])], false)),
		"standing": float(ns.person_standing.get(pid, LK.STANDING_NEUTRAL)),
		"approval": float(ns.overall_approval_pct),
	}
	var best := ""
	var best_net := -INF
	for lever in LK.LEVERS:
		var p := LeverOdds.odds(person, lever, cell)
		if p >= 0.0 and LW.net(person, lever, p) > best_net:
			best_net = LW.net(person, lever, p)
			best = lever
	var p := LeverOdds.odds(person, best, cell)
	var snub: bool = person.traits.has("vain") or String(row["object"]).begins_with("office:")
	return {
		"person_id": pid, "object": String(row["object"]), "arrival_month": month,
		"due_loop_month": month + 1 + CalK.BOOKING_HORIZON_MONTHS,
		"band": President.knowledge_band(ns, pid), "lever": best, "p": p,
		"s": LW.cost(LW.spend(person, best, p)),
		"g": float(Audiences.decline_price(ns, _loader, String(row["id"]))["grudge"]),
		"snub": -AK.DELEGATE_SNUB_RAPPORT if snub else 0.0,
		"kept": false,
	}


## bands-v5.2.md "B5 amendment"'s net values per request, and each answer's
## share of the requests it is the best answer to.
func _b5_answers(requests: Array) -> Dictionary:
	var best := {"book": 0, "delegate": 0, "decline": 0, "unanswered": 0}
	var r_w := float(LW.WEIGHTS["rapport"])
	for r in requests:
		var p := float(r["p"])
		var q := 1.0 - p
		var g := float(r["g"])
		var decline := -(g + r_w * -AK.DECLINE_RAPPORT)
		var book := (1.0 - q * q * q) - float(r["s"]) * (1.0 + q + q * q) + q * q * q * decline - LW.DIARY_DAY
		var deferred := 1.0 - AK.DELEGATE_GRUDGE_SHARE
		var delegate := -(AK.DELEGATE_GRUDGE_SHARE * g + r_w * float(r["snub"]))
		if bool(r["kept"]):
			delegate += r_w * LK.PROMISE_KEPT_RAPPORT
		else:
			delegate -= deferred * g + LK.IOU_BETRAYAL_GRUDGE + r_w * LK.IOU_BETRAYAL_RAPPORT
		var values := {"book": book, "delegate": delegate, "decline": decline, "unanswered": decline}
		var top := maxf(maxf(book, delegate), decline)
		for answer in values:
			if float(values[answer]) >= top - 0.000000001:
				best[answer] += 1
		r["values"] = values
	var n := maxi(1, requests.size())
	var shares := {}
	var top_share := 0.0
	for answer in best:
		shares[answer] = float(best[answer]) / float(n)
		top_share = maxf(top_share, float(shares[answer]))
	return {"requests": requests.size(), "best_share": shares, "top_share": top_share, "diary_day": LW.DIARY_DAY, "rows": requests}


## A4's call: the offered phone lever with the highest shown midpoint (a promise
## names the nearest month it may), or no call when none is offered.
func _phone_first(state, ns, pid: String) -> Dictionary:
	var best := ""
	var best_mid := -1.0
	for row in Phone.options(state, ns, _loader, pid)["levers"]:
		var mid := (float(row["odds_lo"]) + float(row["odds_hi"])) / 2.0
		if bool(row["offered"]) and mid > best_mid:
			best_mid = mid
			best = String(row["lever"])
	if best == "":
		return {}
	var now := int(state.year) * 12 + int(state.month)
	return Phone.dial(state, ns, _loader, pid, best, {"due_month": now + LK.PROMISE_MIN_MONTHS})


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
		"B5_channel_A4_held_12_30": int(r["A4"]["held"]) >= 12 and int(r["A4"]["held"]) <= 30,
		"B5_channel_A4_held_4_by_m20": int(r["A4"]["held_m1_20"]) >= 4,
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
		if r.has("calls"):
			print("   phoned first: %d calls, %d requests answered by phone" % [r["calls"], r["answered_by_phone"]])
	if out.has("b5_answers"):
		print("A2F B5 answers over %d requests (day %.2f): best share %s" % [out["b5_answers"]["requests"], out["b5_answers"]["diary_day"], out["b5_answers"]["best_share"]])
	for band in out["bands"]:
		print("%-32s %s" % [band, "PASS" if out["bands"][band] else "FAIL"])
