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
##      fires after the month's tick in day order; an audience held with no lever settles as
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
##   A2F (`-- --b5-answers`, V5.2b b2.1; b2.2 reads #119's player model) B5's
##      ANSWERS ROW over A2's machine: every request of months 1-B5_ARRIVALS_UPTO,
##      its cell taken at arrival (knowledge, rapport, relationship, aligned,
##      standing, approval), g its refusal grudge, the snub. bands-v5.2.md "The
##      first read, and the player model the row reads": each request scored TWICE,
##      equal weight -- "will serve" (K = 1) and "won't serve" (K = 0); the run's
##      own K is reported, never read. In tools/lever_weights.gd's units:
##        Refuse (decline = unanswered, one answer) = -(g + 0.5 x 0.1);
##        Delegate = -(0.25 g + 0.5 x snub) + (K=1: 0.5 x 0.10 | K=0: -(0.75 g +
##               0.08 + 0.5 x 0.2));
##        Book = the best offered lever's three-attempt net under that intent: A -
##               s(1 + q + q^2) + q^3 x Refuse - DIARY_DAY + 0.5 x 0.10 (received) +
##               KV(0.05 (1 - k)), A = 1 - q^3, q = 1 - p, s the weighted spend, the
##               agreement at 1 as the row's table declares (flatter too);
##               promise_date adds A x 0.5 x 0.25 at K=1 (kept in person) and
##               subtracts A x (0.5 x 0.5 + 0.15 x intake + KV(0.5 k')) at K=0 (the
##               lie at its date, k' = k + 0.05 (1 - k));
##        KV(dk) = dk x KNOW_SLOPE x 3q^2 x ENCOUNTERS, the knowledge valued
##        (the arithmetic is tools/lever_weights.gd's, checked on the declared legs).
##      B5: book <= 50 % of all cases; within "will serve" book >= 5 % and delegate
##      >= 5 %; within "won't serve" refuse >= 5 % (a tie counts for each answer it
##      ties). For information: the same at a declared mix (each request at the
##      three band midpoints, a third each). Off by default, so A1-A3's table
##      stays comparable.
##
## SEEDS (`-- --seeds=1-20`, pre-gate B, CALL 2; bands-v5.2.md's B1 amendment, #128).
##      A1, A2 and A3 again under each per-game draw seed (President.seed_draws),
##      the seed-0 table above untouched. Per seed: the fewest arrivals in any
##      12-month window of A1's term (49 sliding windows), B1's rows (A1), B2's (A2)
##      and B3's act rows (A1, A3). The bands: every window >= 1 in at least 19 of 20
##      seeds, >= 2 in at least 16 of 20, the first request by month 3 in all of
##      them (the guarantee), and every other row in at least 18 of 20.
##
## VISITORS (b3) ARE COUNTED APART. A visiting head's request waits in a place of its
## own (MAX_PENDING_FOREIGN), outside the domestic lane B1-B3 were declared on, so
## every band field above counts this nation's people only; `visitors` reports the
## heads' requests beside them. Since b3 the diary fires AFTER the month's tick, the
## game's order: before, a head the player visited read as a head visiting France.
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
const Removal = preload("res://src/sim/removal.gd")
const CabinetK = preload("res://src/sim/cabinet_constants.gd")

const LeverOdds = preload("res://src/sim/lever_odds.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const LW = preload("res://tools/lever_weights.gd")
const President = preload("res://src/sim/president.gd")
const Characters = preload("res://src/sim/characters.gd")
const Phone = preload("res://src/sim/phone.gd")

const PLAYER := "FRA"
const MONTHS := 60
const B5_ARRIVALS_UPTO := 60
const B5_MONTHS := B5_ARRIVALS_UPTO + 1 + CalK.BOOKING_HORIZON_MONTHS
const NAMED_GRUDGE := 0.05
## B5's answers row: the declared mix's knowledge, a third each (information).
const B5_MIX := [0.165, 0.5, 0.835]

var _loader


func _init() -> void:
	var json_path := ""
	var b5 := false
	var seeds: Array = []
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--json="):
			json_path = String(arg).substr(7)
		elif String(arg) == "--b5-answers":
			b5 = true
		elif String(arg).begins_with("--seeds="):
			var span := String(arg).substr(8).split("-")
			seeds = range(int(span[0]), int(span[span.size() - 1]) + 1)
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
		var shares: Dictionary = out["b5_answers"]["shares"]
		out["bands"]["B5_answers_book_at_most_50pct"] = float(shares["all"]["book"]) <= 0.50
		out["bands"]["B5_answers_will_serve_book_5pct"] = float(shares["will_serve"]["book"]) >= 0.05
		out["bands"]["B5_answers_will_serve_delegate_5pct"] = float(shares["will_serve"]["delegate"]) >= 0.05
		out["bands"]["B5_answers_wont_serve_refuse_5pct"] = float(shares["wont_serve"]["refuse"]) >= 0.05
	if not seeds.is_empty():
		out["b1_seeds"] = _b1_seeds(seeds)
		for band in out["b1_seeds"]["bands"]:
			out["bands"][band] = out["b1_seeds"]["bands"][band]
	_print(out)
	if json_path != "":
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, " ", true) + "\n")
		f.close()
	quit(0)


func _run(regime: String, months := MONTHS, draw_seed := 0) -> Dictionary:
	var book_all := regime == "A2" or regime == "A2F" or regime == "A4"
	var calls := 0
	var answered_by_phone := 0
	var b5_requests: Array = []
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	if draw_seed != 0:
		President.seed_draws(state, draw_seed)
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
	var visitors := {"arrivals": 0, "booked": 0, "unplaceable": 0, "held": 0}
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
			var visitor := _visitor(String(row["person_id"]))
			if regime == "A3":
				var r: Dictionary = Audiences.decline(state, ns, _loader, id)
				if not visitor:
					decline_grudge += float(r["price"]["grudge"])
					declines += 1
					refused_at[String(row["person_id"])] = refused_at.get(String(row["person_id"]), month)
			elif book_all:
				var placed := false
				for d in Audiences.offered_dates(state, ns, id):
					if bool(d["free"]) and bool(Audiences.book(state, ns, _loader, id, d)["ok"]):
						placed = true
						if visitor:
							visitors["booked"] += 1
						else:
							booked += 1
						break
				if not placed:
					var answers: Dictionary = Audiences.answers(state, ns, _loader, id)
					if visitor:
						visitors["unplaceable"] += 1
					else:
						unplaceable += 1
						if bool(answers["delegate"]["ok"]) and bool(answers["decline"]["ok"]):
							unplaceable_offered += 1
					Audiences.delegate(state, ns, _loader, id)
		# The game's order (b3): the month's tick, then its days -- main.gd sets the
		# month and ticks before the diary's days run, as balance_probe's day loop
		# does. The diary used to fire before the tick, which read the player's own
		# visits as heads visiting France once visitors existed.
		var report: Dictionary = WorldMonth.tick_month(state, _loader)
		if book_all:
			_fire_month(state, fire, held, month, refused_at, visitors)
		for row in report["audience_requests"]["arrived"]:
			if _visitor(String(row["person_id"])):
				visitors["arrivals"] += 1
				continue
			arrivals.append([month, String(row["person_id"])])
			if regime == "A2F" and month <= B5_ARRIVALS_UPTO:
				b5_requests.append(_b5_capture(ns, row, month))
		for r in b5_requests:
			if int(r["due_loop_month"]) == month:
				r["kept"] = bool(ns.person_want_state.get("%s|%s" % [r["person_id"], r["object"]], false))
		for row in report["audience_requests"]["lapsed"]:
			if not _visitor(String(row["person_id"])):
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
	result["visitors"] = visitors
	if regime == "A4":
		result["calls"] = calls
		result["answered_by_phone"] = answered_by_phone
	# Only a seeded run carries its months, and only A2F its rows, so the seed-0
	# A1-A3 table stays byte-comparable.
	if draw_seed != 0:
		result["arrival_months"] = arrivals.map(func(a) -> int: return int(a[0]))
	if regime == "A2F":
		result["b5_requests"] = b5_requests
	return result


## One arriving request, as B5's answers row reads it: the person's cell, the
## refusal grudge g and the snub, all at arrival. Whether the want was served at
## the due month is kept for information only (#119: the run's own K is not read).
func _b5_capture(ns, row: Dictionary, month: int) -> Dictionary:
	var pid := String(row["person_id"])
	var person = _loader.person_by_id[pid]
	var snub: bool = person.traits.has("vain") or String(row["object"]).begins_with("office:")
	return {
		"person_id": pid, "object": String(row["object"]), "arrival_month": month,
		"due_loop_month": month + 1 + CalK.BOOKING_HORIZON_MONTHS,
		"band": President.knowledge_band(ns, pid),
		"cell": {
			"knowledge": President.knowledge(ns, pid),
			"rapport": President.rapport(ns, pid),
			"relationship": President.relationship(ns, pid),
			"aligned": bool(ns.person_want_state.get("%s|%s" % [pid, String(row["object"])], false)),
			"standing": float(ns.person_standing.get(pid, LK.STANDING_NEUTRAL)),
			"approval": float(ns.overall_approval_pct),
		},
		"g": float(Audiences.decline_price(ns, _loader, String(row["id"]))["grudge"]),
		"snub": -AK.DELEGATE_SNUB_RAPPORT if snub else 0.0,
		"kept": false,
	}


## The row under #119's player model: the run's mix (the band) and the declared
## mix (information), each a share table over both intents.
func _b5_answers(requests: Array) -> Dictionary:
	var kept := 0
	for r in requests:
		kept += 1 if bool(r["kept"]) else 0
	var out := _b5_table(requests, false)
	out["mix_info"] = _b5_table(requests, true)
	out["requests"] = requests.size()
	out["diary_day"] = LW.DIARY_DAY
	out["realized_kept_share"] = float(kept) / maxf(1.0, float(requests.size()))
	out["rows"] = requests
	return out


## {shares: {all, will_serve, wont_serve}: {book, delegate, refuse}} -- each the
## share of that set's cases the answer is best in (a tie counts for each).
func _b5_table(requests: Array, mix: bool) -> Dictionary:
	var best := {"will_serve": {"book": 0.0, "delegate": 0.0, "refuse": 0.0}, "wont_serve": {"book": 0.0, "delegate": 0.0, "refuse": 0.0}}
	var cases := {"will_serve": 0.0, "wont_serve": 0.0}
	var levers := {}
	for r in requests:
		var person = _loader.person_by_id[String(r["person_id"])]
		var ks: Array = B5_MIX if mix else [float(r["cell"]["knowledge"])]
		var w := 1.0 / float(ks.size())
		for k in ks:
			var cell: Dictionary = (r["cell"] as Dictionary).duplicate()
			cell["knowledge"] = float(k)
			for intent in ["will_serve", "wont_serve"]:
				var v := _b5_values(person, cell, float(r["g"]), float(r["snub"]), intent == "will_serve")
				cases[intent] += w
				var top := maxf(maxf(float(v["book"]), float(v["delegate"])), float(v["refuse"]))
				for answer in ["book", "delegate", "refuse"]:
					if float(v[answer]) >= top - 0.000000001:
						best[intent][answer] += w
				if not mix:
					r[intent] = v
					levers[v["lever"]] = int(levers.get(v["lever"], 0)) + 1
	var shares := {"all": {}}
	for intent in ["will_serve", "wont_serve"]:
		shares[intent] = {}
		for answer in ["book", "delegate", "refuse"]:
			shares[intent][answer] = float(best[intent][answer]) / maxf(1.0, float(cases[intent]))
	for answer in ["book", "delegate", "refuse"]:
		shares["all"][answer] = (float(best["will_serve"][answer]) + float(best["wont_serve"][answer])) / maxf(1.0, float(cases["will_serve"]) + float(cases["wont_serve"]))
	var out := {"shares": shares, "cases": float(cases["will_serve"]) + float(cases["wont_serve"])}
	if not mix:
		out["book_levers"] = levers  # Book's best lever in every case, whether or not Book was the best answer
	return out


## One case's three answers, as bands-v5.2.md's table and player model declare
## them; book is the best offered lever's three-attempt net under the intent.
func _b5_values(person, cell: Dictionary, g: float, snub: float, serve: bool) -> Dictionary:
	var k := float(cell["knowledge"])
	var book := -INF
	var pick := ""
	for lever in LK.LEVERS:
		var p := LeverOdds.odds(person, lever, cell)
		if p < 0.0:
			continue
		var v := LW.book_value(p, LW.cost(LW.spend(person, lever, p)), g, k, serve, lever == "promise_date", Characters.grudge_intake(person))
		if v > book:
			book = v
			pick = lever
	return {"book": book, "delegate": LW.delegate_value(g, snub, serve), "refuse": LW.refuse_value(g), "lever": pick}


## A visiting head (b3), not one of this nation's people.
func _visitor(pid: String) -> bool:
	return not pid.begins_with("%s_" % PLAYER)


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
func _fire_month(state, fire: Array, held: Array, month: int, refused_at: Dictionary, visitors: Dictionary) -> void:
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
				Removal.reassign(state, _loader, String(e["portfolio"]), String(e["party_id"]))
			CalK.KIND_AUDIENCE:
				var id := String(e["action_id"])
				if bool(Audiences.hold(state, ns, _loader, id)["ok"]):
					var pid := String(e["target_id"])
					Audiences.settle(state, ns, _loader, id, AK.STATUS_DECLINED)
					if _visitor(pid):
						visitors["held"] += 1
					else:
						held.append(month)
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


## B1's amendment over `seeds`: A1 under each, the emptiest 12-month window and the
## five B1 rows per seed, and the share of seeds each row holds in.
func _b1_seeds(seeds: Array) -> Dictionary:
	var rows := {}
	var per_seed := []
	var ge1 := 0
	var ge2 := 0
	for s in seeds:
		var a1 := _run("A1", MONTHS, int(s))
		var a2 := _run("A2", MONTHS, int(s))
		var a3 := _run("A3", MONTHS, int(s))
		var months: Array = a1["arrival_months"]
		var fewest := 1 << 30
		for start in range(1, MONTHS - 11 + 1):
			var n := 0
			for m in months:
				if int(m) >= start and int(m) <= start + 11:
					n += 1
			fewest = mini(fewest, n)
		ge1 += 1 if fewest >= 1 else 0
		ge2 += 1 if fewest >= 2 else 0
		# _bands() reads A4 too; A1 stands in, and its B5 rows are not kept.
		var all := _bands({"A1": a1, "A2": a2, "A3": a3, "A4": a1})
		var b1 := {}
		for band in all:
			if not String(band).begins_with("B5_"):
				b1[band] = all[band]
				rows[band] = int(rows.get(band, 0)) + (1 if b1[band] else 0)
		per_seed.append({"seed": int(s), "arrivals": int(a1["arrivals"]), "fewest_in_12": fewest,
			"first_month": int(a1["first_month"]), "m1_20": int(a1["arrivals_m1_20"]),
			"people": int(a1["distinct_people"]), "top_share": float(a1["top_person_share"]),
			"a2_held": int(a2["held"]), "a2_held_m1_20": int(a2["held_m1_20"]),
			"a2_unplaceable_share": float(a2["unplaceable_share"]), "a2_arrivals": int(a2["arrivals"]),
			"acts_by_refused_a1": (a1["acts_by_refused"] as Array).size(),
			"acts_by_refused_a3": (a3["acts_by_refused"] as Array).size(), "b1": b1})
	var n_seeds := seeds.size()
	var bands := {
		"B1_seeds_window_ge1_95pct": ge1 * 20 >= 19 * n_seeds,
		"B1_seeds_window_ge2_80pct": ge2 * 20 >= 16 * n_seeds,
	}
	for band in rows:
		if band == "B1_first_by_month_3":
			bands["B1_first_by_month_3_seeds_100pct"] = int(rows[band]) == n_seeds
		else:
			bands["%s_seeds_90pct" % band] = int(rows[band]) * 20 >= 18 * n_seeds
	return {"seeds": n_seeds, "window_ge1": ge1, "window_ge2": ge2, "rows_held": rows, "per_seed": per_seed, "bands": bands}


func _print(out: Dictionary) -> void:
	print("=== AUDIENCE PROBE (FRA, %d months) ===" % MONTHS)
	for regime in out["regimes"]:
		var r: Dictionary = out["regimes"][regime]
		print("%s arrivals %d first %d m1-20 %d people %d top %.2f | booked %d unplaceable %d (%.2f, offered %.2f) held %d (m1-20 %d) | acts by refused %d named m20 %d | decline grudge %.3f" % [
			regime, r["arrivals"], r["first_month"], r["arrivals_m1_20"], r["distinct_people"], r["top_person_share"],
			r["booked"], r["unplaceable"], r["unplaceable_share"], r["unplaceable_offered_share"], r["held"], r["held_m1_20"],
			(r["acts_by_refused"] as Array).size(), r["named_grudges_m20"], r["mean_decline_grudge"]])
		print("   highest refused grudges: %s" % [r["refused_peak_grudges"]])
		print("   visitors (apart from the bands): %s" % [r["visitors"]])
		if r.has("calls"):
			print("   phoned first: %d calls, %d requests answered by phone" % [r["calls"], r["answered_by_phone"]])
	if out.has("b5_answers"):
		var b5: Dictionary = out["b5_answers"]
		print("A2F B5 answers over %d requests x 2 intents (day %.2f, realized kept %.3f): %s | Book's best lever per case, won or not: %s" % [
			b5["requests"], b5["diary_day"], b5["realized_kept_share"], b5["shares"], b5["book_levers"]])
		print("   declared mix (information): %s" % [b5["mix_info"]["shares"]])
	if out.has("b1_seeds"):
		var b: Dictionary = out["b1_seeds"]
		print("A1 over %d seeds: emptiest 12-month window >= 1 in %d, >= 2 in %d; B1 rows held %s" % [
			b["seeds"], b["window_ge1"], b["window_ge2"], b["rows_held"]])
		for row in b["per_seed"]:
			print("   seed %2d: arrivals %d, emptiest year %d, first %d, m1-20 %d, people %d, top %.2f | A2 arrivals %d held %d (m1-20 %d) unplaceable %.2f | acts by refused A1 %d A3 %d" % [
				row["seed"], row["arrivals"], row["fewest_in_12"], row["first_month"], row["m1_20"], row["people"], row["top_share"],
				row["a2_arrivals"], row["a2_held"], row["a2_held_m1_20"], row["a2_unplaceable_share"],
				row["acts_by_refused_a1"], row["acts_by_refused_a3"]])
	for band in out["bands"]:
		print("%-32s %s" % [band, "PASS" if out["bands"][band] else "FAIL"])
