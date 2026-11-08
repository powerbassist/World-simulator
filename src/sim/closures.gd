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
##   negotiate_5/10/15  the buyer's search with the sweetener cut by 5, 10 or 15 %
##                    (Negotiate, the parent's calls 3 and 4; negotiation.gd). A buyer
##                    found answers the counter on its own seed, at full strength
##                    (the plant needs it more than it needs the plant): accepted, it
##                    buys at the cut sweetener; walked, it leaves and the plant shuts;
##                    back (the parent's ruling (b)), it returns at the OLD sweetener
##                    and the player is asked once more, for a month (`offered`): sell
##                    at it, the default at the due month, or close now;
##   rescue           the PLANT is kept for RESCUE_MONTHS, the state paying
##                    RESCUE_EUR_PER_JOB_YEAR for each job the closure would cut,
##                    a Budget line (`rescue_bill_pct_gdp`, the parent's call 4 on
##                    #277) for the term (QA's call on #270, the parent's
##                    ruling: priced on the plant, not on the firm's subsidy verbs,
##                    whose bill read EUR 5-9 bn a year for a 720-job plant). The
##                    firm announces nothing during its term and is watched afresh
##                    after it (a new window, no cooldown: the term was the wait). It
##                    saves its plant and does not silence the sector (the parent's
##                    ruling on #294: at one plant's price, a player who always
##                    rescued stopped every plant in the game shutting): the sector's
##                    clock runs from the announcement, so a sibling may announce after
##                    the cooldown, and a second rescue is a second price.
##
## Unanswered, the closure lands at its due month. The rule's numbers are data
## (data/industry/closures.json, loader.closure_rule), never per firm.
##
## THE PLAYER'S NATION ONLY: a closure is a decision arrival, and a nation nobody
## leads cannot answer one. The rule fires per SECTOR (the parent's ruling on the majors
## PR): fired per major, each real major added added closures (FRA 14 -> 39 a decade). A
## sector falls when one of its majors has lost `fall` of its output over the window;
## the majors' summed output was tried first and measured dead (0 to 2 a decade at 2 to
## 4 %, 5 at 0.6 %): what falls 4 % in six months is a firm losing share to its rivals,
## which the sum nets out. One fall closes one plant, at one of the majors past the
## threshold, weighted by its jobs (not one in a process). One announcement a month at
## most, the worst fall first.
##
## THE RATE IS A CHANCE THAT READS THE ECONOMY (the author's call on #286). A firm past
## `fall` is nearly always there, so a closure waiting only on `cooldown_months` fired
## every 26 months in a boom and in a slump alike: a timer, which no policy could move.
## Now a falling sector closes a plant in a month with chance() on its own seed, more in
## a slump and in a sector whose worst major fell further. `cooldown_months` is only a
## floor (longer than a window and an answer, so a closure's own cut is never the next
## fall), and tests/test_closures.gd fails if the rate stops reading the economy. The
## output gap is the read: it is what a slump IS in this model (src/sim/cycle.gd), and a
## policy reaches it. The record keeps what fell and the gap, for the card's reason.
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
const Economy = preload("res://src/sim/economy.gd")
const Processes = preload("res://src/sim/processes.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const K = preload("res://src/sim/closures_constants.gd")
const Characters = preload("res://src/sim/characters.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const NK = preload("res://src/sim/companies_constants.gd")
const Negotiation = preload("res://src/sim/negotiation.gd")

const ANNOUNCED := "announced"
const SEARCHING := "searching"
const RESCUING := "rescuing"
const OFFERED := "offered"


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
	# Every major's window, the falls past the threshold gathered by sector: the rule
	# fires per sector, or each real major added would add closures.
	var falling := {}
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
		if h.size() <= int(rule["window_months"]) or float(h[0]) <= 0.0:
			continue
		var fall := (float(h[0]) - float(h[h.size() - 1])) / float(h[0])
		if fall > float(rule["fall"]) and Processes.live(ns, String(company.id)).is_empty() \
				and String((entry.get("closure", {}) as Dictionary).get("status", "")) != RESCUING:
			if not falling.has(company.sector):
				falling[company.sector] = {"worst": 0.0, "firms": []}
			falling[company.sector]["worst"] = maxf(float(falling[company.sector]["worst"]), fall)
			(falling[company.sector]["firms"] as Array).append([company, fall])
	# The month's one announcement: the worst fall among the sectors that may announce
	# and whose chance came up. The seed is the nation's, the sector's and the month's,
	# so two runs of one game differ only by what the chance reads.
	var worst := ""
	var gap := Economy.output_gap_pct(ns)
	for sector in falling:
		var fall := float(falling[sector]["worst"])
		if _sector_may_announce(ns, majors, sector, rule, now) \
				and Cycle.unit("closure|fire|%s|%s" % [String(ns.id), sector], now) < chance(rule, fall, gap) \
				and (worst == "" or fall > float(falling[worst]["worst"])):
			worst = sector
	if worst != "":
		var pick: Array = _pick(ns, falling[worst]["firms"], worst, now)
		_announce(ns, pick[0], ns.companies[pick[0].id], float(pick[1]), rule, now)


## The month's chance that a falling sector closes a plant: `monthly_chance` at the
## rule's `reference_fall` with the economy at its potential, moved by the two reads,
## each bounded (closures_constants.gd). Below 1.0 always, and above 0 in the best of
## booms: a plant can still close.
static func chance(rule: Dictionary, worst_fall: float, gap_pct: float) -> float:
	var fall_term := clampf(worst_fall / float(rule["reference_fall"]), 0.0, K.FALL_TERM_MAX)
	var economy_term := clampf(1.0 - float(rule["gap_slope"]) * gap_pct, K.ECONOMY_TERM_MIN, K.ECONOMY_TERM_MAX)
	return minf(float(rule["monthly_chance"]) * fall_term * economy_term, 1.0)


## This firm's closure while it waits for a first answer, or {}: the record itself, read only.
static func announced(ns, company_id: String) -> Dictionary:
	var row: Dictionary = (ns.companies.get(company_id, {}) as Dictionary).get("closure", {})
	return row if String(row.get("status", "")) == ANNOUNCED else {}


## The closures waiting for an answer or a buyer, as copies for a panel to read.
static func open(ns) -> Array:
	var out: Array = []
	for company_id in ns.companies:
		var row: Dictionary = (ns.companies[company_id] as Dictionary).get("closure", {})
		if [ANNOUNCED, SEARCHING, OFFERED].has(String(row.get("status", ""))):
			out.append(row.duplicate(true))
	return out


## What this month did to the closures the player countered, said for that month only
## (the parent's ruling on #285, #280's for a process: a result is otherwise silent).
## One line per row: {id, company_id, city_id, jobs, outcome, month, sweetener_eur_bn},
## with outcome one of
##   accepted  the buyer took the counter and bought; sweetener_eur_bn is the cut one;
##   back      the buyer came back at its old sweetener and asks once more;
##   sold      that buyer bought, at the old sweetener;
##   walked    the buyer left over the counter, and the plant closed;
##   no_buyer  the search found nobody, so the counter was never answered: it closed;
##   closed    the player closed the plant rather than sell to the buyer that came back;
##   void      the firm failed during the search.
## sweetener_eur_bn is 0 for the last four, nothing having been paid to a buyer.
static func closed_last_month(state, ns) -> Array:
	var now := _now(state)
	var out: Array = []
	for company_id in ns.companies:
		var row: Dictionary = (ns.companies[company_id] as Dictionary).get("closure", {})
		if not row.has("countered"):
			continue
		var outcome := _said(row, now)
		if outcome != "":
			var paid := {"accepted": float(row["sweetener_eur_bn"]), "back": float(row["back_sweetener_eur_bn"]), "sold": float(row["back_sweetener_eur_bn"])}
			out.append({"id": String(row["id"]), "company_id": String(company_id), "city_id": String(row["city_id"]),
				"jobs": float(row["jobs"]), "outcome": outcome, "month": now, "sweetener_eur_bn": float(paid.get(outcome, 0.0))})
	return out


static func _said(row: Dictionary, now: int) -> String:
	var record: Dictionary = row.get("negotiation", {})
	var drawn := String(record["outcome"]) if int(record.get("month", -1)) == now else ""
	if int(row["ended"]) != now:
		return drawn
	match String(row["status"]):
		"sold":
			return "accepted" if drawn == "accepted" else "sold"
		"closed":
			if drawn == "walked":
				return drawn
			return "no_buyer" if record.is_empty() else "closed"
	return String(row["status"])


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
## (close | buyer | negotiate | rescue), `jobs_lost` if it ends in the cut,
## `bloc_offset`, the money on the debt (`debt_eur_bn` once: 0 to close, the buyer's
## search; the rescue's `debt_eur_bn_per_year` for its `months`, `total_eur_bn` in all,
## ending in month `ends`), and a buyer's `chance`, `months` and `sweetener_eur_bn`
## (paid only at a sale). A counter (_counters) adds `counter`, `back_sweetener_eur_bn`,
## `months_hi`, the range shown (`odds_lo`, `odds_hi`; `odds` is the draw's, never
## shown) and `walk`. A buyer that came back (OFFERED) asks close or buyer at the old
## sweetener. [] when nothing is waiting for an answer.
static func answers(state, ns, loader, closure_id: String) -> Array:
	var found := _find(ns, loader, closure_id)
	var status := String(found["row"]["status"]) if not found.is_empty() else ""
	if status != ANNOUNCED and status != OFFERED:
		return []
	var row: Dictionary = found["row"]
	# A re-ask is answered once, as every ask is (pass 1 on this PR): the answer stands.
	if status == OFFERED and row.has("answer"):
		return []
	var close := {"id": "close", "kind": "close", "jobs_lost": float(row["jobs"]), "debt_eur_bn": 0.0,
		"bloc_offset": _plant_offsets(loader.closure_rule, row)}
	if status == OFFERED:
		return [close, {"id": "buyer", "kind": "buyer", "jobs_lost": float(row["jobs"]), "bloc_offset": {},
			"chance": 1.0, "months": 1, "debt_eur_bn": 0.0, "sweetener_eur_bn": float(row["back_sweetener_eur_bn"])}]
	var buyer := {"id": "buyer", "kind": "buyer", "jobs_lost": float(row["jobs"]), "bloc_offset": {},
		"chance": K.BUYER_CHANCE, "months": K.BUYER_MONTHS,
		"debt_eur_bn": _search_eur_bn(ns, found["company"], loader.closure_rule),
		"sweetener_eur_bn": _sweetener_eur_bn(ns, found["company"], loader.closure_rule)}
	var out: Array = [close, buyer]
	out.append_array(_counters(row, buyer))
	var yearly := _rescue_eur_bn_per_year(row)
	out.append({"id": "rescue", "kind": "rescue", "jobs_lost": 0.0, "bloc_offset": {},
		"debt_eur_bn_per_year": yearly, "months": K.RESCUE_MONTHS,
		"total_eur_bn": yearly * float(K.RESCUE_MONTHS) / 12.0, "ends": _now(state) + K.RESCUE_MONTHS})
	return out


## The buyer's three counters (negotiation.gd; the parent's calls 3 and 4): the
## buyer's search with the sweetener cut by the counter, the old one kept for a buyer
## that comes back (a month more, `months_hi`), and the buyer's odds at full strength,
## BUYER_LEVERAGE (closures_constants.gd), in the range fixed on the announcement's month, so it does not
## move while the answer waits.
static func _counters(row: Dictionary, buyer: Dictionary) -> Array:
	var out: Array = []
	for c in NK.NEGOTIATE_COUNTERS:
		var id := "negotiate_%d" % roundi(100.0 * float(c))
		var p := Negotiation.odds(float(c), K.BUYER_LEVERAGE)
		var band := Negotiation.shown(p, Negotiation.key(row, id), int(row["announced"]))
		var a := buyer.duplicate(true)
		a.merge({"id": id, "kind": "negotiate", "counter": float(c), "months_hi": K.BUYER_MONTHS + 1,
			"sweetener_eur_bn": float(buyer["sweetener_eur_bn"]) * (1.0 - float(c)), "back_sweetener_eur_bn": float(buyer["sweetener_eur_bn"]),
			"odds": p, "odds_lo": band.x, "odds_hi": band.y, "walk": NK.NEGOTIATE_WALK}, true)
		out.append(a)
	return out


## The player's answer, one of answers(): close lands at once; buyer or a counter
## starts the search, paying its losses now and fixing the sweetener paid at a sale;
## rescue starts the plant's term; a buyer that came back sells at the due month, as
## its default. {ok} or {ok: false, reason}.
static func answer(state, ns, loader, closure_id: String, answer_id: String) -> Dictionary:
	var offered := answers(state, ns, loader, closure_id)
	if offered.is_empty():
		return {"ok": false, "reason": "Nothing here is waiting for an answer."}
	var picked := {}
	for a in offered:
		if String(a["id"]) == answer_id:
			picked = a
	if picked.is_empty():
		return {"ok": false, "reason": "That is not one of the answers."}
	var found := _find(ns, loader, closure_id)
	var row: Dictionary = found["row"]
	var now := _now(state)
	row["answer"] = answer_id
	match String(picked["kind"]):
		"close":
			_cut(ns, found["company"], found["entry"], row, loader.closure_rule, now)
		"buyer", "negotiate":
			if String(row["status"]) == OFFERED:
				return {"ok": true}
			row["status"] = SEARCHING
			row["months_left"] = K.BUYER_MONTHS
			# The price the strip showed: the search's losses now, the sweetener fixed now
			# and paid only at a sale (a counter's, with the old one kept for a return).
			ns.debt_eur_bn += float(picked["debt_eur_bn"])
			row["sweetener_eur_bn"] = float(picked["sweetener_eur_bn"])
			if picked.has("counter"):
				row["countered"] = float(picked["counter"])
				row["back_sweetener_eur_bn"] = float(picked["back_sweetener_eur_bn"])
				row["odds"] = float(picked["odds"])
		"rescue":
			row["status"] = RESCUING
			row["months_left"] = K.RESCUE_MONTHS
			row["ends"] = now + K.RESCUE_MONTHS
			row["rescue_eur_bn_per_year"] = _rescue_eur_bn_per_year(row)
	return {"ok": true}


# --- The machine ----------------------------------------------------------------------

static func _resolve(ns, company, rule: Dictionary, now: int) -> void:
	var entry: Dictionary = ns.companies.get(company.id, {})
	var row: Dictionary = entry.get("closure", {})
	var status := String(row.get("status", ""))
	if status != ANNOUNCED and status != SEARCHING and status != OFFERED:
		return
	# A firm that failed meanwhile has nothing left to close.
	if _gone(entry):
		_end(row, "void", now)
	elif status == ANNOUNCED and now >= int(row["due"]):
		_cut(ns, company, entry, row, rule, now)
	elif status == OFFERED and now >= int(row["due"]):
		# A buyer that came back sells at the old sweetener unless the player closed.
		ns.debt_eur_bn += float(row["back_sweetener_eur_bn"])
		_end(row, "sold", now)
	elif status == SEARCHING:
		row["months_left"] = int(row["months_left"]) - 1
		if int(row["months_left"]) > 0:
			return
		if Cycle.unit("closure|%s|buyer" % String(row["id"]), now) >= K.BUYER_CHANCE:
			_cut(ns, company, entry, row, rule, now)
			return
		match _answer_counter(row, now):
			"back":
				# The parent's ruling (b): the buyer returns at the OLD sweetener and the
				# player is asked once more, for a month: sell at it (the default) or close.
				row["status"] = OFFERED
				row["offered"] = now
				row["due"] = now + 1
				row.erase("answer")
			"walked":
				_cut(ns, company, entry, row, rule, now)
			_:
				ns.debt_eur_bn += float(row.get("sweetener_eur_bn", 0.0))
				_end(row, "sold", now)


## The found buyer's answer to the player's counter, drawn on the counter's own seed
## (negotiation.gd) and recorded on the row; "" for a plain buyer (no counter, no draw:
## a closure nobody countered draws exactly what it drew before).
static func _answer_counter(row: Dictionary, now: int) -> String:
	if not row.has("countered"):
		return ""
	var outcome := Negotiation.draw(float(row["odds"]), Negotiation.key(row, String(row["answer"])), now)
	row["negotiation"] = {"answer": String(row["answer"]), "outcome": outcome, "month": now}
	return outcome


## Whether the sector may announce: none of its plants waits for an answer, a buyer or a
## re-ask, whose rows' `ended` is -1, so the cooldown test alone would pass them (QA's MUST
## at the merge with main); and none of its closures ended within `cooldown_months`. A
## rescue's clock runs from its announcement, its end being three years off (the header).
static func _sector_may_announce(ns, majors: Array, sector: String, rule: Dictionary, now: int) -> bool:
	for company in majors:
		if company.sector != sector:
			continue
		var row: Dictionary = (ns.companies.get(company.id, {}) as Dictionary).get("closure", {})
		# A void row is a firm that failed, no plant that closed: nothing to wait out. A
		# rescue's term was the wait: its plant is watched afresh on the next full window.
		if row.is_empty() or ["void", "rescued"].has(String(row["status"])):
			continue
		var since := int(row["announced"]) if String(row["status"]) == RESCUING else int(row["ended"])
		if [ANNOUNCED, SEARCHING, OFFERED].has(String(row["status"])) or now - since < int(rule["cooldown_months"]):
			return false
	return true


## The major a sector's fall closes a plant of, as [company, its fall]: one of those past
## the threshold, weighted by its jobs, on the sector's seed this month (stateless:
## Cycle.unit consumes no stream).
static func _pick(ns, firms: Array, sector: String, now: int) -> Array:
	var total := 0.0
	for firm in firms:
		total += Companies.headcount(ns, firm[0])
	var at := Cycle.unit("closure|pick|%s" % sector, now) * total
	for firm in firms:
		at -= Companies.headcount(ns, firm[0])
		if at < 0.0:
			return firm
	return firms[firms.size() - 1]


## A landed closure's bloc moves, for the strip and the cut: the rule's `bloc_offset` is
## the move of a plant of `reference_jobs`, scaled by this plant's jobs.
static func _plant_offsets(rule: Dictionary, row: Dictionary) -> Dictionary:
	var out := {}
	for bloc in rule["bloc_offset"]:
		out[bloc] = float(rule["bloc_offset"][bloc]) * float(row["jobs"]) / float(rule["reference_jobs"])
	return out


static func _announce(ns, company, entry: Dictionary, fall: float, rule: Dictionary, now: int) -> void:
	entry["closure"] = {
		"id": "%s|%d" % [String(company.id), now], "company_id": String(company.id),
		"city_id": Companies.live_city_of(ns, company), "status": ANNOUNCED, "announced": now,
		"due": now + K.ANSWER_MONTHS, "ended": -1, "fall": fall, "window_months": int(rule["window_months"]),
		"gap_pct": Economy.output_gap_pct(ns),
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
	var offsets := _plant_offsets(rule, row)
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
