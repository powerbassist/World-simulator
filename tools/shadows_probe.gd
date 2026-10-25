extends SceneTree

## Headless probe: godot --headless --path "<repo>" --script res://tools/shadows_probe.gd -- --json=PATH
##   [--seeds=A-B] [--regimes=S1,S2,S2c,S3,S4] [--exact=N] [--trace]
##   or -- --summarize=MERGED.json --json=PATH (the bands over rows another run wrote;
##   tools/shadows_parallel.py shards the seeds and calls this to merge).
## Dev-only, never ships. Run it isolated (APPDATA="$(mktemp -d)").
##
## V5.2c, the shadows' bands (docs/design/bands-v5.2.md B6, B7, B8), on a France
## game run through src/sim/world_month.gd -- the game's own month, never a copy --
## for MONTHS months per seed. Five regimes:
##
##   S1 ONCE, per currency. Idle (requests lapse) but for one act: the first request
##      pending at ACT_MONTH is booked, held and settled on its day (Audiences.hold,
##      Audiences.settle). The act's evidence is NOT written: each of the four
##      currencies is a hypothetical row -- the counterpart, the act month and the
##      president of that month, frozen -- appended inside the Audiences step's
##      after-hook, priced with Exposure.hazard and rolled with Exposure.roll (the
##      machine's own functions), then removed. EXACT until the first exposure,
##      because the only other reader of exposure_evidence (c1c: Audiences, which
##      charges a crossed accomplice a broken word) never fires on the counterpart:
##      after the act S1 books each of their requests on its first free day and
##      settles it there (the c1c amendment), so one run per seed answers all four
##      currencies. The act is a settled audience, and since c1c's rule 2 a corrupt
##      win pays no grudge relief either, so the settle is the bargain's own price.
##      `--exact=N` re-runs the first N seeds with the real row written at the act
##      and compares first-exposure months (0 mismatches is the evidence).
##   S2 ALWAYS. Every request booked on its first free day (else delegated); in each
##      audience an offer is accepted, else bargains in backroom and aid in turn
##      until one wins or the attempts run out.
##   S2c CROSSED (#170's call 2, Gameplay #171). S2, but every request from a person
##      who holds evidence on the sitting president is declined: the turned route is
##      how crossing an accomplice comes back, and S2 never crosses anyone.
##   S3 AFFAIR. Idle; at ACT_MONTH the first person the president has a spark with
##      is brought just past close (the probe's setup: a courtship it does not
##      model) and the affair begins; it ends at AFFAIR_END_MONTH.
##   S4 LIES. S2's booking; in each audience a lie on argue, then, if attempts
##      remain and nothing was won, a lie on a promised date. B8 reads the catch by
##      the gap between the listener's reading and the president's (#170's call 3).
##
## `--trace` adds S1's (seed, currency, month, route, roll, pressure) rows: any RATE
## vector re-prices them as roll < min(RATE x pressure, HAZARD_MAX) in Python.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalK = preload("res://src/sim/calendar_constants.gd")
const Exposure = preload("res://src/sim/exposure.gd")
const Levers = preload("res://src/sim/levers.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const Lies = preload("res://src/sim/lies.gd")
const President = preload("res://src/sim/president.gd")
const Shadows = preload("res://src/sim/shadows.gd")
const SC = preload("res://src/sim/shadow_constants.gd")
const Cut = preload("res://src/core/cut.gd")

const PLAYER := "FRA"
const MONTHS := 60
const ACT_MONTH := 6
const AFFAIR_END_MONTH := 30
const CURRENCIES := ["favour", "party_money", "personal_wealth", "diverted_budget"]
const REGIMES := ["S1", "S2", "S2c", "S3", "S4"]
## B8 by gap (listener's social skill less the president's), the 1e-9 cut rule.
const GAP_HIGH := 0.14
const GAP_LOW := -0.10

var _loader
var _trace := false
var _bargains := 0


func _init() -> void:
	var json_path := ""
	var seeds: Array = range(0, 200)
	var regimes: Array = REGIMES.duplicate()
	var exact := 0
	var merged := ""
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--json="):
			json_path = a.substr(7)
		elif a.begins_with("--seeds="):
			var span := a.substr(8).split("-")
			seeds = range(int(span[0]), int(span[span.size() - 1]) + 1)
		elif a.begins_with("--regimes="):
			regimes = Array(a.substr(10).split(","))
		elif a.begins_with("--exact="):
			exact = int(a.substr(8))
		elif a == "--trace":
			_trace = true
		elif a.begins_with("--summarize="):
			merged = a.substr(12)
	var out := {}
	if merged != "":
		var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(merged))["rows"]
		out = {"summary": _summarize(rows)}
	else:
		_loader = DataLoader.new()
		_loader.load_all()
		var rows: Array = []
		for regime in regimes:
			for s in seeds:
				rows.append(_run(String(regime), int(s)))
		if regimes.has("S1"):
			for s in seeds.slice(0, exact):
				rows.append(_exact_check(int(s), rows))
		out = {"rows": rows, "summary": _summarize(rows)}
	_print(out["summary"])
	if json_path != "":
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, " "))
		f.close()
	quit(0)


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _visitor(pid: String) -> bool:
	return not pid.begins_with("%s_" % PLAYER)


## One seed of one regime. `real_kind` (the exact check) writes S1's act as a real
## evidence row of that kind instead of rolling the hypothetical four.
func _run(regime: String, s: int, real_kind := "") -> Dictionary:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	if s != 0:
		President.seed_draws(state, s)
	var r := {"regime": regime, "seed": s, "offers_arrived": 0, "offerer_requests": 0, "exposures": [], "leader_changed_month": -1, "crossed": 0}
	var first_leader := President.leader_id(ns)
	var act := {}          # S1: {month, person_id, leader_id} once the act is done (filled in place: the hook holds it)
	var booked := ""       # S1: the act's request, once booked
	var hits := {}         # S1: currency -> {month, route}
	var trace: Array = []
	var lies: Array = []   # S4: [listener skill, caught]
	var promise_lies := 0
	var revealed_at_date := 0
	var hook := func(step: String, after: bool, _report: Dictionary) -> void:
		if step == "Audiences" and after and regime == "S1" and not act.is_empty() and real_kind == "":
			_roll_hypothetical(state, ns, act, hits, trace)
	for i in range(MONTHS):
		var month := i + 1
		state.year = 2026 + i / 12
		state.month = i % 12 + 1
		state.day = 1
		if regime == "S2" or regime == "S2c" or regime == "S4":
			r["crossed"] += _book(state, ns, regime == "S2c")
		elif regime == "S1" and booked == "" and month >= ACT_MONTH:
			booked = _book_one(state, ns)
		elif regime == "S1" and not act.is_empty():
			_book_person(state, ns, String(act["person_id"]))
		var report: Dictionary = WorldMonth.tick_month(state, _loader, hook)
		for row in report["audience_requests"]["arrived"]:
			if not (row.get("offer", {}) as Dictionary).is_empty():
				r["offers_arrived"] += 1
			var asker = _loader.person_by_id.get(String(row["person_id"]))
			if asker != null and SC.OFFER_KINDS.has(String(asker.kind)):
				r["offerer_requests"] += 1
		for row in report.get("exposures", []):
			(r["exposures"] as Array).append({"month": month, "route": String(row["route"]), "kind": String(row["kind"])})
		for row in report["commitments"]["broken"]:
			if bool(row.get("lie", false)):
				revealed_at_date += 1
		if President.leader_id(ns) != first_leader and int(r["leader_changed_month"]) < 0:
			r["leader_changed_month"] = month
		match regime:
			"S1":
				if act.is_empty() and booked != "":
					act.merge(_fire_act(state, ns, month, booked, real_kind))
				elif not act.is_empty():
					_serve_person(state, ns, String(act["person_id"]))
			"S2", "S2c", "S4":
				_fire(state, ns, regime, lies)
			"S3":
				_affair(state, ns, month, r)
		state.day = 1
	if regime == "S1":
		r["act"] = act
		r["hits"] = hits
		if _trace:
			r["trace"] = trace
	if regime == "S4":
		r["lies"] = lies
		r["president_skill"] = float(_loader.person_by_id[first_leader].social_skill)
		for l in lies:
			if String(l[2]) == "promise_date" and not bool(l[1]) and int(l[3]) <= MONTHS:
				promise_lies += 1
		r["promise_lies_uncaught"] = promise_lies
		r["revealed_at_date"] = revealed_at_date
	return r


## Book every pending request on its first free offered day, else delegate it.
## The diary fires after the month's tick. `cross` (S2c): a request from someone
## holding evidence on the sitting president is declined instead.
func _book(state, ns, cross := false) -> int:
	var crossed := 0
	for row in Audiences.pending(ns):
		var id := String(row["id"])
		if cross and _holds_evidence(ns, String(row["person_id"])):
			Audiences.decline(state, ns, _loader, id)
			crossed += 1
			continue
		if not _book_on_first_day(state, ns, id):
			Audiences.delegate(state, ns, _loader, id)
	return crossed


## S1: the first pending request of this nation's people booked, its id; "" if none
## could be placed this month (the next month tries again).
func _book_one(state, ns) -> String:
	for row in Audiences.pending(ns):
		if not _visitor(String(row["person_id"])) and _book_on_first_day(state, ns, String(row["id"])):
			return String(row["id"])
	return ""


## c1c's S1 amendment (bands-v5.2.md "c1c", rule 1): after the act its counterpart
## is never crossed, so the once band measures one hidden act and not a president who
## bribes someone and then ignores them, and `--exact` stays exact. Each of their
## requests is booked on its first free day ...
func _book_person(state, ns, pid: String) -> void:
	for row in Audiences.pending(ns):
		if String(row["person_id"]) == pid:
			_book_on_first_day(state, ns, String(row["id"]))


## ... and held and settled on that day, as the act was.
func _serve_person(state, ns, pid: String) -> void:
	for e in _due(state):
		if String(e["target_id"]) != pid:
			continue
		var id := String(e["action_id"])
		state.day = int(e["day"])
		Calendar.resolve(state, Calendar.verb_key(e), true)
		if bool(Audiences.hold(state, ns, _loader, id)["ok"]):
			Audiences.settle(state, ns, _loader, id, AK.STATUS_SETTLED)


func _holds_evidence(ns, pid: String) -> bool:
	for row in ns.exposure_evidence:
		if String(row.get("person_id", "")) == pid and President.evidence_leader(ns, row) == President.leader_id(ns):
			return true
	return false


func _book_on_first_day(state, ns, id: String) -> bool:
	for d in Audiences.offered_dates(state, ns, id):
		if bool(d["free"]) and bool(Audiences.book(state, ns, _loader, id, d)["ok"]):
			return true
	return false


## The month's audiences, in day order: what each regime does in the room.
func _due(state) -> Array:
	var dim := Calendar.days_in_month(state.year, state.month)
	var due: Array = []
	for e in Calendar.due(state, state.year, state.month, dim):
		if String(e["kind"]) == CalK.KIND_AUDIENCE:
			due.append(e.duplicate(true))
	due.sort_custom(func(a, b): return int(a.get("day", 0)) < int(b.get("day", 0)))
	return due


## S1's act: the booked audience held and settled on its day. {} until it fires.
func _fire_act(state, ns, month: int, booked: String, real_kind: String) -> Dictionary:
	for e in _due(state):
		var id := String(e["action_id"])
		if id != booked:
			continue
		var pid := String(e["target_id"])
		state.day = int(e["day"])
		Calendar.resolve(state, Calendar.verb_key(e), true)
		if not bool(Audiences.hold(state, ns, _loader, id)["ok"]):
			continue
		Audiences.settle(state, ns, _loader, id, AK.STATUS_SETTLED)
		if real_kind != "":
			President.leave_evidence(state, ns, _loader, real_kind, pid, SC.ACT_EVIDENCE)
		return {"month": month, "person_id": pid, "leader_id": President.leader_id(ns)}
	return {}


## S1: each currency not yet found, as a frozen row, rolled exactly as the machine
## rolls a lone row -- routes in order, the first hit its exposure. Tracing keeps
## rolling past the hit, so a lower RATE can be re-priced from the same rows.
func _roll_hypothetical(state, ns, act: Dictionary, hits: Dictionary, trace: Array) -> void:
	var now := _now(state)
	for kind in CURRENCIES:
		if hits.has(kind) and not _trace:
			continue
		var row := {"kind": kind, "person_id": act["person_id"], "size": SC.ACT_EVIDENCE,
			"month": int(act["month"]), "leader_id": act["leader_id"]}
		ns.exposure_evidence.append(row)
		for route in SC.ROUTES:
			var x := Exposure.pressure(state, ns, _loader, route)
			if x <= 0.0:
				continue
			var u := Exposure.roll(ns, route, now)
			if _trace:
				trace.append([kind, now, route, u, x])
			if not hits.has(kind) and u < Exposure.hazard(state, ns, _loader, route):
				hits[kind] = {"month": now - 2026 * 12, "route": route}
				if not _trace:
					break
		ns.exposure_evidence.pop_back()


## S2 and S4: every audience due this month, held and played.
func _fire(state, ns, regime: String, lies: Array) -> void:
	for e in _due(state):
		state.day = int(e["day"])
		var session: Dictionary = Levers.open(state, ns, _loader, String(e["action_id"]))
		Calendar.resolve(state, Calendar.verb_key(e), true)
		if session.is_empty():
			continue
		var person = _loader.person_by_id.get(String(session["person_id"]))
		if regime == "S2" or regime == "S2c":
			if not Shadows.offer(ns, session).is_empty():
				Shadows.accept_offer(state, ns, _loader, session)
			while String(session["won"]) == "" and int(session["attempts_left"]) > 0:
				var currency: String = LK.CURRENCY_BACKROOM if _bargains % 2 == 0 else LK.CURRENCY_AID
				_bargains += 1
				if not bool(Levers.attempt(state, ns, _loader, session, "bargain", {"currency": currency}).get("ok", false)):
					break
		else:
			var president_skill := float(_loader.person_by_id[President.leader_id(ns)].social_skill)
			var r: Dictionary = Levers.attempt(state, ns, _loader, session, "argue", {"lie": true})
			if bool(r.get("ok", false)) and person != null:
				lies.append([float(person.social_skill), bool(r.get("caught", false)), "argue", 0, president_skill])
			if String(session["won"]) == "" and int(session["attempts_left"]) > 0:
				var due := _now(state) + LK.PROMISE_MIN_MONTHS
				r = Levers.attempt(state, ns, _loader, session, "promise_date", {"lie": true, "due_month": due})
				if bool(r.get("ok", false)) and person != null:
					# The loop month the date falls in, so a date past the run is not counted.
					lies.append([float(person.social_skill), bool(r.get("caught", false)), "promise_date", due - (2026 * 12), president_skill])
		Levers.close(state, ns, _loader, session)


## S3: the affair begun at ACT_MONTH with the first person there is a spark with,
## ended at AFFAIR_END_MONTH.
func _affair(state, ns, month: int, r: Dictionary) -> void:
	if month == ACT_MONTH:
		var leader = _loader.person_by_id[President.leader_id(ns)]
		for person in _loader.people[PLAYER]:
			var pid := String(person.id)
			if pid == String(leader.id) or pid == String(leader.spouse_id) or not Shadows.spark(ns, pid):
				continue
			President.adjust_rapport(state, ns, _loader, pid, SC.AFFAIR_RAPPORT_MIN + 0.01 - President.rapport(ns, pid))
			if bool(Shadows.begin_affair(state, ns, _loader, pid).get("ok", false)):
				r["lover"] = pid
				break
	elif month == AFFAIR_END_MONTH and r.has("lover"):
		Shadows.end_affair(state, ns, _loader, String(r["lover"]))


## The exact check: seed `s` re-run once per currency with the real row written at
## the act, its first real exposure compared with S1's hypothetical one.
func _exact_check(s: int, rows: Array) -> Dictionary:
	var hyp := {}
	for row in rows:
		if String(row["regime"]) == "S1" and int(row["seed"]) == s:
			hyp = row["hits"]
	var out := {"regime": "S1_exact", "seed": s, "mismatches": []}
	for kind in CURRENCIES:
		var real := _run("S1", s, kind)
		var first := {}
		for e in real["exposures"]:
			if String(e["kind"]) == kind:
				first = {"month": int(e["month"]), "route": String(e["route"])}
				break
		var expect: Dictionary = hyp.get(kind, {})
		if JSON.stringify(first) != JSON.stringify(expect):
			(out["mismatches"] as Array).append({"kind": kind, "real": first, "hypothetical": expect})
	return out


## The bands over every row given -- the one place their arithmetic lives, so a
## merged run (tools/shadows_parallel.py) and a single run read the same numbers.
func _summarize(rows: Array) -> Dictionary:
	var by := {}
	for row in rows:
		var key := String(row["regime"])
		if not by.has(key):
			by[key] = []
		(by[key] as Array).append(row)
	var out := {"bands": {}}
	if by.has("S1"):
		var s1: Array = by["S1"]
		var rates := {}
		var routes := {}
		for kind in CURRENCIES:
			var found := 0
			for row in s1:
				if (row["hits"] as Dictionary).has(kind):
					found += 1
					var route := String(row["hits"][kind]["route"])
					routes["%s:%s" % [kind, route]] = int(routes.get("%s:%s" % [kind, route], 0)) + 1
			rates[kind] = float(found) / maxf(1.0, float(s1.size()))
		var pooled := 0.0
		for kind in CURRENCIES:
			pooled += float(rates[kind]) / CURRENCIES.size()
		var offers := 0
		var offerers := 0
		var changed := 0
		for row in s1:
			offers += int(row["offers_arrived"])
			offerers += int(row["offerer_requests"])
			changed += 1 if int(row["leader_changed_month"]) > 0 else 0
		out["S1"] = {"seeds": s1.size(), "exposed_by_60": rates, "pooled": pooled, "routes": routes,
			"offers_per_term": float(offers) / maxf(1.0, float(s1.size())), "leader_changed_seeds": changed,
			"offerer_requests_per_term": float(offerers) / maxf(1.0, float(s1.size()))}
		out["bands"]["B6_once_10_30"] = pooled >= 0.10 and pooled <= 0.30
		for kind in CURRENCIES:
			if kind == "favour":
				# #170's call 1 (Gameplay #171): a favour is found, less often than party money.
				out["bands"]["B6_once_favour_above_0_below_party_money"] = float(rates[kind]) > 0.0 and float(rates[kind]) < float(rates["party_money"])
				continue
			out["bands"]["B6_once_%s_10_30" % kind] = float(rates[kind]) >= 0.10 and float(rates[kind]) <= 0.30
		out["bands"]["B6_order"] = rates["favour"] < rates["party_money"] and rates["party_money"] < rates["personal_wealth"] \
			and rates["personal_wealth"] < rates["diverted_budget"]
		var per_term := float(out["S1"]["offers_per_term"])
		out["bands"]["B6_offers_2_6"] = per_term >= 2.0 and per_term <= 6.0
	if by.has("S1_exact"):
		var bad := 0
		for row in by["S1_exact"]:
			bad += (row["mismatches"] as Array).size()
		out["S1_exact"] = {"seeds": (by["S1_exact"] as Array).size(), "mismatches": bad}
	for regime in ["S2", "S2c"]:
		if not by.has(regime):
			continue
		var s2: Array = by[regime]
		var firsts: Array = []
		var routes := {}
		var total := 0
		var offers := 0
		var crossed := 0
		for row in s2:
			offers += int(row["offers_arrived"])
			crossed += int(row.get("crossed", 0))
			var ex: Array = row["exposures"]
			firsts.append(int(ex[0]["month"]) if not ex.is_empty() else MONTHS + 1)
			for e in ex:
				routes[String(e["route"])] = int(routes.get(String(e["route"]), 0)) + 1
				total += 1
		firsts.sort()
		var exposed := firsts.filter(func(m): return int(m) <= MONTHS).size()
		var median := int(firsts[firsts.size() / 2]) if not firsts.is_empty() else -1
		var shares := {}
		for route in SC.ROUTES:
			shares[route] = float(routes.get(route, 0)) / maxf(1.0, float(total))
		out[regime] = {"seeds": s2.size(), "exposed_by_60": float(exposed) / maxf(1.0, float(s2.size())),
			"median_first": median, "route_shares": shares, "exposures": total,
			"offers_per_term": float(offers) / maxf(1.0, float(s2.size())),
			"crossed_per_run": float(crossed) / maxf(1.0, float(s2.size()))}
		if regime == "S2c":
			# #170's call 2: the turned route, measured where someone is crossed.
			out["bands"]["B6_S2c_route_turned_10"] = float(shares["turned"]) >= 0.10
			continue
		out["bands"]["B6_always_80"] = float(out["S2"]["exposed_by_60"]) >= 0.80
		out["bands"]["B6_always_median_24"] = median >= 0 and median <= 24
		# Turned in S2 is reported, not gated (call 2): S2 never crosses anyone.
		for route in ["press", "courts", "auditors"]:
			out["bands"]["B6_route_%s_10" % route] = float(shares[route]) >= 0.10
	if by.has("S3"):
		var s3: Array = by["S3"]
		var found := 0
		var lovers := 0
		for row in s3:
			lovers += 1 if row.has("lover") else 0
			for e in row["exposures"]:
				if String(e["kind"]) == "affair":
					found += 1
					break
		var rate := float(found) / maxf(1.0, float(lovers))
		out["S3"] = {"seeds": s3.size(), "affairs": lovers, "exposed_by_60": rate}
		out["bands"]["B7_affair_25_50"] = rate >= 0.25 and rate <= 0.50
	if by.has("S4"):
		var hi := [0, 0]
		var lo := [0, 0]
		var mid := [0, 0]
		var skills := {}
		var uncaught := 0
		var revealed := 0
		for row in by["S4"]:
			for l in row["lies"]:
				var gap := float(l[0]) - float(l[4] if l.size() > 4 else row["president_skill"])
				var band: Array = hi if Cut.at_or_above(gap, GAP_HIGH) else (lo if Cut.at_or_below(gap, GAP_LOW) else mid)
				band[0] += 1
				band[1] += 1 if bool(l[1]) else 0
			skills[str(row["president_skill"])] = true
			uncaught += int(row["promise_lies_uncaught"])
			revealed += int(row["revealed_at_date"])
		var hi_rate := float(hi[1]) / maxf(1.0, float(hi[0]))
		var lo_rate := float(lo[1]) / maxf(1.0, float(lo[0]))
		var mid_rate := float(mid[1]) / maxf(1.0, float(mid[0]))
		out["S4"] = {"gap_high": {"lies": hi[0], "caught": hi_rate}, "gap_low": {"lies": lo[0], "caught": lo_rate},
			"gap_middle": {"lies": mid[0], "caught": mid_rate},
			"promise_lies_uncaught": uncaught, "revealed_at_date": revealed, "president_skills": skills.keys()}
		# #170's call 3: by the gap (listener less president), at +0.14 and -0.10.
		out["bands"]["B8_gap_high_40_70"] = hi[0] > 0 and hi_rate >= 0.40 and hi_rate <= 0.70
		out["bands"]["B8_gap_low_15_30"] = lo[0] > 0 and lo_rate >= 0.15 and lo_rate <= 0.30
		out["bands"]["B8_gap_middle_between"] = mid[0] > 0 and mid_rate > lo_rate and mid_rate < hi_rate
		out["bands"]["B8_gap_high_minus_low_20"] = hi[0] > 0 and lo[0] > 0 and hi_rate - lo_rate >= 0.20
		out["bands"]["B8_dates_100"] = uncaught > 0 and revealed == uncaught
	return out


func _print(summary: Dictionary) -> void:
	for key in summary:
		if key != "bands":
			print("%s: %s" % [key, JSON.stringify(summary[key])])
	for band in summary["bands"]:
		print("%-28s %s" % [band, "PASS" if bool(summary["bands"][band]) else "MISS"])
