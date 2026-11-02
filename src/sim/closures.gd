extends RefCounted

## V5.3 a (docs/design/v5.3-ab.md 3.2, "New Industry decisions") -- a plant closure
## announced, the industry supply band B7 lacked. When a major's output has fallen
## by more than the rule's `fall` over its `window_months`, the firm announces a
## closure in its LIVE city (Companies.live_city_of), and the player answers:
##
##   close (default)  the plant shuts: the firm's live share falls by the rule's
##                    `cut` (to the unnamed residual, which employs nobody), so its
##                    payroll in its city falls with it (Companies.headcount reads the
##                    live share), and the rule's bloc offsets land;
##   buyer            a search of BUYER_MONTHS; on its seed (BUYER_CHANCE) a buyer
##                    takes the plant and nothing is lost, else the plant shuts. It
##                    has a price: the plant's losses for the search, paid at the
##                    answer, and a sweetener on the buyer's price, paid at the sale;
##   rescue           the PLANT is kept for RESCUE_MONTHS, the state paying
##                    RESCUE_EUR_PER_JOB_YEAR for each job the closure would cut,
##                    a Budget line (`rescue_bill_pct_gdp`, the parent's call 4 on
##                    #277) for the term (QA's call on #270, the parent's
##                    ruling: priced on the plant, not on the firm's subsidy verbs,
##                    whose bill read EUR 5-9 bn a year for a 720-job plant). It
##                    announces nothing during its term and is watched afresh after
##                    it (a new window, no cooldown: the term was the wait).
##
## Unanswered, the closure lands at its due month. The rule's numbers are data
## (data/industry/closures.json, loader.closure_rule), never per firm.
##
## THE PLAYER'S NATION ONLY: a closure is a decision arrival, and a nation nobody
## leads cannot answer one. One announcement a month at most, the worst fall first;
## a firm in a process (processes.gd) does not announce, and a firm whose closure
## ended waits `cooldown_months` (longer than a window and an answer, and its output
## history is cleared at the announcement and at the cut, so a closure's own cut is
## never the next fall).
##
## The record's place is `city_id` (not `city`: the firm entry's `city` is the
## industry machine's relocation key, single-writer by tests/test_industry.gd).
##
## THE STATE IS THE FIRM'S: `closure` (the record, kept after it ends for the
## cooldown and the panel) and `closure_watch` (the last window + 1 outputs) on the
## firm's ns.companies entry, written by this file alone, which also writes the
## entry's `share` when a plant shuts. The register is deep-copied by the field
## table, so no NationState field and no SAVE bump: an absent key reads "no closure,
## no history yet", the truth for every older save.

const Companies = preload("res://src/sim/companies.gd")
const Processes = preload("res://src/sim/processes.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const K = preload("res://src/sim/closures_constants.gd")
const Characters = preload("res://src/sim/characters.gd")
const LK = preload("res://src/sim/legislature_constants.gd")

const ANNOUNCED := "announced"
const SEARCHING := "searching"
const RESCUING := "rescuing"


static func tick_month(state, loader) -> void:
	var rule: Dictionary = loader.closure_rule
	var ns = state.player()
	if rule.is_empty() or ns == null:
		return
	var now := _now(state)
	tick_rescues(state)
	var majors: Array = Companies.majors_of(loader, ns.id)
	for company in majors:
		_resolve(ns, company, rule, now)
	# The month's one announcement: the worst fall past the threshold.
	var worst = null
	var worst_fall := float(rule["fall"])
	for company in majors:
		var entry: Dictionary = ns.companies.get(company.id, {})
		if entry.is_empty() or _gone(entry):
			# A failed firm's history stops with it: a rescue months later starts a
			# fresh window rather than comparing across the months it was gone.
			entry.erase("closure_watch")
			continue
		var h: Array = entry.get("closure_watch", [])
		h.append(Companies.output_eur_bn(ns, company))
		while h.size() > int(rule["window_months"]) + 1:
			h.pop_front()
		entry["closure_watch"] = h
		if h.size() <= int(rule["window_months"]) or float(h[0]) <= 0.0 or not _may_announce(ns, company, entry, rule, now):
			continue
		var fall := (float(h[0]) - float(h[h.size() - 1])) / float(h[0])
		if fall > worst_fall:
			worst = company
			worst_fall = fall
	if worst != null:
		_announce(ns, worst, ns.companies[worst.id], worst_fall, rule, now)


## The closures waiting for an answer or a buyer, as copies for a panel to read.
static func open(ns) -> Array:
	var out: Array = []
	for company_id in ns.companies:
		var row: Dictionary = (ns.companies[company_id] as Dictionary).get("closure", {})
		if [ANNOUNCED, SEARCHING].has(String(row.get("status", ""))):
			out.append(row.duplicate(true))
	return out


## The plant rescues running, as copies for a panel to read: each closure record
## with its `months_left`, `ends` (the month it ends), `rescue_eur_bn_per_year` and
## `eur_bn_per_month` (the In progress strip's row, the parent's call 4 on #277).
static func rescues(ns) -> Array:
	var out: Array = []
	for company_id in ns.companies:
		var row: Dictionary = (ns.companies[company_id] as Dictionary).get("closure", {})
		if String(row.get("status", "")) == RESCUING:
			var copy := row.duplicate(true)
			copy["eur_bn_per_month"] = float(row["rescue_eur_bn_per_year"]) / 12.0
			out.append(copy)
	return out


## The rescues' month (the parent's call 4 on #277): each running term counts down,
## and their yearly price as a percent of GDP is the Budget line
## `ns.rescue_bill_pct_gdp`, billed a month behind as every computed line is, so the
## cost is on the debt path the Budget shows. Budget.project() runs this alone, so a
## forecast books the bill while a term runs and drops it when the term ends. A
## firm that failed meanwhile has nothing left to rescue (QA's TAKE 1 on #277).
static func tick_rescues(state) -> void:
	var ns = state.player()
	if ns == null:
		return
	var now := _now(state)
	var bill := 0.0
	for company_id in ns.companies:
		var entry: Dictionary = ns.companies[company_id]
		var row: Dictionary = entry.get("closure", {})
		if String(row.get("status", "")) != RESCUING:
			continue
		if _gone(entry):
			_end(row, "void", now)
			continue
		if float(ns.gdp_eur_bn) > 0.0:
			bill += 100.0 * float(row["rescue_eur_bn_per_year"]) / float(ns.gdp_eur_bn)
		row["months_left"] = int(row["months_left"]) - 1
		if int(row["months_left"]) <= 0:
			# At its end the plant is watched afresh.
			entry.erase("closure_watch")
			_end(row, "rescued", now)
	ns.rescue_bill_pct_gdp = bill


## An announced closure's answers, each with its figures for the strip: `kind`
## (close | buyer | rescue), `jobs_lost` if it ends in the cut, `bloc_offset`, the
## money on the debt (`debt_eur_bn` once: 0 to close, the buyer's search; the
## rescue's `debt_eur_bn_per_year` for its `months`, `total_eur_bn` in all, ending in
## month `ends`), and a buyer's `chance`, `months` and `sweetener_eur_bn` (paid only
## at a sale). [] when nothing is waiting for an answer.
static func answers(state, ns, loader, closure_id: String) -> Array:
	var found := _find(ns, loader, closure_id)
	if found.is_empty() or String(found["row"]["status"]) != ANNOUNCED:
		return []
	var row: Dictionary = found["row"]
	var out: Array = [
		{"id": "close", "kind": "close", "jobs_lost": float(row["jobs"]), "debt_eur_bn": 0.0,
			"bloc_offset": (loader.closure_rule["bloc_offset"] as Dictionary).duplicate()},
		{"id": "buyer", "kind": "buyer", "jobs_lost": float(row["jobs"]), "bloc_offset": {},
			"chance": K.BUYER_CHANCE, "months": K.BUYER_MONTHS,
			"debt_eur_bn": _search_eur_bn(ns, found["company"], loader.closure_rule),
			"sweetener_eur_bn": _sweetener_eur_bn(ns, found["company"], loader.closure_rule)},
	]
	var yearly := _rescue_eur_bn_per_year(row)
	out.append({"id": "rescue", "kind": "rescue", "jobs_lost": 0.0, "bloc_offset": {},
		"debt_eur_bn_per_year": yearly, "months": K.RESCUE_MONTHS,
		"total_eur_bn": yearly * float(K.RESCUE_MONTHS) / 12.0, "ends": _now(state) + K.RESCUE_MONTHS})
	return out


## The player's answer: close lands at once, buyer starts the search, rescue starts
## the plant's term. {ok} or {ok: false, reason}.
static func answer(state, ns, loader, closure_id: String, answer_id: String) -> Dictionary:
	var found := _find(ns, loader, closure_id)
	if found.is_empty() or String(found["row"]["status"]) != ANNOUNCED:
		return {"ok": false, "reason": "Nothing here is waiting for an answer."}
	var row: Dictionary = found["row"]
	var company = found["company"]
	var now := _now(state)
	if answer_id == "close":
		row["answer"] = answer_id
		_cut(ns, company, found["entry"], row, loader.closure_rule, now)
		return {"ok": true}
	if answer_id == "buyer":
		row["answer"] = answer_id
		row["status"] = SEARCHING
		row["months_left"] = K.BUYER_MONTHS
		# The price the strip showed: the search's losses now, the sweetener fixed now
		# and paid only at a sale.
		ns.debt_eur_bn += _search_eur_bn(ns, company, loader.closure_rule)
		row["sweetener_eur_bn"] = _sweetener_eur_bn(ns, company, loader.closure_rule)
		return {"ok": true}
	if answer_id == "rescue":
		row["answer"] = answer_id
		row["status"] = RESCUING
		row["months_left"] = K.RESCUE_MONTHS
		row["ends"] = now + K.RESCUE_MONTHS
		row["rescue_eur_bn_per_year"] = _rescue_eur_bn_per_year(row)
		return {"ok": true}
	return {"ok": false, "reason": "That is not one of the answers."}


# --- The machine ----------------------------------------------------------------------

static func _resolve(ns, company, rule: Dictionary, now: int) -> void:
	var entry: Dictionary = ns.companies.get(company.id, {})
	var row: Dictionary = entry.get("closure", {})
	var status := String(row.get("status", ""))
	if status != ANNOUNCED and status != SEARCHING:
		return
	# A firm that failed meanwhile has nothing left to close.
	if _gone(entry):
		_end(row, "void", now)
	elif status == ANNOUNCED and now >= int(row["due"]):
		_cut(ns, company, entry, row, rule, now)
	elif status == SEARCHING:
		row["months_left"] = int(row["months_left"]) - 1
		if int(row["months_left"]) > 0:
			return
		if Cycle.unit("closure|%s|buyer" % String(row["id"]), now) < K.BUYER_CHANCE:
			ns.debt_eur_bn += float(row.get("sweetener_eur_bn", 0.0))
			_end(row, "sold", now)
		else:
			_cut(ns, company, entry, row, rule, now)


static func _may_announce(ns, company, entry: Dictionary, rule: Dictionary, now: int) -> bool:
	if not Processes.live(ns, String(company.id)).is_empty():
		return false
	var row: Dictionary = entry.get("closure", {})
	if row.is_empty():
		return true
	if [ANNOUNCED, SEARCHING, RESCUING].has(String(row["status"])):
		return false
	# A rescue's term was the wait: its plant is re-evaluated on the next full window.
	if String(row["status"]) == "rescued":
		return true
	return now - int(row["ended"]) >= int(rule["cooldown_months"])


static func _announce(ns, company, entry: Dictionary, fall: float, rule: Dictionary, now: int) -> void:
	entry["closure"] = {
		"id": "%s|%d" % [String(company.id), now], "company_id": String(company.id),
		"city_id": Companies.live_city_of(ns, company), "status": ANNOUNCED, "announced": now,
		"due": now + K.ANSWER_MONTHS, "ended": -1, "fall": fall,
		"jobs": Companies.headcount(ns, company) * float(rule["cut"]),
	}
	entry.erase("closure_watch")


## The plant shuts: the live share falls by the cut (to the unnamed residual, the
## failure commit's own move, so the payroll in the firm's city falls with it), and
## the rule's bloc offsets land, clamped as every writer of the register is. The move
## is an act, not a standing condition (the parent's TAKE 2 on #251): what it wrote is
## booked through Characters.book_act_offsets on the share that fades (#104's
## half-life), as every act's offset is.
static func _cut(ns, company, entry: Dictionary, row: Dictionary, rule: Dictionary, now: int) -> void:
	entry["share"] = Companies.share_of_company(ns, company) * (1.0 - float(rule["cut"]))
	# The record names where the jobs went: a relocation since the announcement
	# moved the payroll the cut removes.
	row["city_id"] = Companies.live_city_of(ns, company)
	var offsets: Dictionary = rule["bloc_offset"]
	var before: Dictionary = (ns.bloc_offset as Dictionary).duplicate()
	for bloc in offsets:
		ns.bloc_offset[bloc] = clampf(float(ns.bloc_offset.get(bloc, 0.0)) + float(offsets[bloc]),
			LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX)
	Characters.book_act_offsets(ns, before)
	entry.erase("closure_watch")
	_end(row, "closed", now)


## The plant's losses the state covers while a buyer is sought: BUYER_SEARCH_LOSS of
## a year of the plant's output (the cut's share of the firm's), for the search months.
static func _search_eur_bn(ns, company, rule: Dictionary) -> float:
	return K.BUYER_SEARCH_LOSS * Companies.output_eur_bn(ns, company) * float(rule["cut"]) * float(K.BUYER_MONTHS) / 12.0


## The rescue's yearly price: RESCUE_EUR_PER_JOB_YEAR for each job the closure would cut.
static func _rescue_eur_bn_per_year(row: Dictionary) -> float:
	return float(row["jobs"]) * K.RESCUE_EUR_PER_JOB_YEAR / 1e9


## The sweetener on the buyer's price: BUYER_SWEETENER of the plant's value.
static func _sweetener_eur_bn(ns, company, rule: Dictionary) -> float:
	return K.BUYER_SWEETENER * Companies.value_eur_bn(ns, company) * float(rule["cut"])


static func _end(row: Dictionary, status: String, now: int) -> void:
	row["status"] = status
	row["ended"] = now


static func _gone(entry: Dictionary) -> bool:
	return bool(entry.get("failed", false)) or float(entry.get("share", 1.0)) <= 0.0


## {row, entry, company} for a closure id, {} when no major holds it.
static func _find(ns, loader, closure_id: String) -> Dictionary:
	for company in Companies.majors_of(loader, ns.id):
		var entry: Dictionary = ns.companies.get(company.id, {})
		var row: Dictionary = entry.get("closure", {})
		if not row.is_empty() and String(row["id"]) == closure_id:
			return {"row": row, "entry": entry, "company": company}
	return {}


static func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)
