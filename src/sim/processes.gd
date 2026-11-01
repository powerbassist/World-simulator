extends RefCounted

## V5.3 a (docs/design/v5.3-ab.md 2.3 and 3.2; bands A3, A4) -- the ownership and
## structure verbs as PROCESSES. A decision that changes who owns a firm or what it
## is takes time and can be stopped: the press (or, for the two verbs the law
## reserves, the adopted bill -- bills.gd) opens a row on `ns.processes`, and that
## month changes no state share, no failure flag and no debt (A3). Each stage ends
## on its month; the price is FIXED at the start from the value then and a seeded
## rate inside the range the strip shows, so the realised price always falls in it
## (A4: the range is the truth's fog, never a guess).
##
##   minority_stake        negotiation (2) -> the transfer: the stake at value x
##                         (1 + a 5-15 % premium); half the bloc move at the offer,
##                         half at the transfer.
##   full_nationalisation  offer (2) -> the transfer, paid then at value x (1 + a
##                         15-30 % premium), half the bloc move at the bill, half at
##                         the transfer -> transition (12) -> control: the state
##                         share is written at its END, so the dividend (which reads
##                         the share) starts after the transition with no new rule.
##   break_up              investigation (9-12, seeded) -> the ruling: the legal
##                         costs, and the break-up ordered with the odds the strip
##                         showed (rising with the firm's share) or the firm cleared
##                         -> remedy (6) -> the split, 70 % of the share to the rivals.
##   privatisation         sale (6) -> the windfall at value x (1 - a 0-15 % discount,
##                         larger the deeper the downturn at the sale).
##
## The firm's own arm stays ONE copy, Companies.execute(): _land() runs it at the
## stage's end and puts the debt and the bloc offsets back, because this file books
## the price and the bloc moves on its own timetable. A firm that fails, or changes
## hands, mid-process voids it: what was spent stays spent. Stopping is a verb with
## its own price (stop_price): a U-turn on a public stage, a break fee of 10 % of the
## premium after the vote, the legal fees spent in an investigation; nothing can be
## stopped after a transfer or a ruling. Every number is companies_constants.gd's.

const Companies = preload("res://src/sim/companies.gd")
const K = preload("res://src/sim/companies_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const Asks = preload("res://src/sim/process_asks.gd")
const Drag = preload("res://src/sim/process_drag.gd")

## The verbs that run as processes, by action id, and their first stage.
const FIRST_STAGE := {
	"minority_stake": "negotiation", "full_nationalisation": "offer",
	"break_up": "investigation", "privatisation": "sale",
}
## The firm verbs a live process on the same firm refuses: every change of owner
## or structure, the foreign bid's allow included.
const BLOCKED_OPS := ["nationalise", "privatise", "break_up", "allow_bid"]
const BUSY := "A process is already under way on this firm."
const SETTLED := "This firm settled with the competition authority; its commitments stand."
const OPEN := "open"


static func is_process(action) -> bool:
	return action != null and FIRST_STAGE.has(String(action.id))


## The open row on this firm, or {}.
static func live(ns, company_id: String) -> Dictionary:
	for row in ns.processes:
		if String(row["company_id"]) == company_id and String(row["status"]) == OPEN:
			return row
	return {}


## Every process still running, oldest first, as copies for a panel to read.
static func rows(ns) -> Array:
	var out: Array = []
	for row in ns.processes:
		if String(row["status"]) == OPEN:
			out.append((row as Dictionary).duplicate(true))
	return out


## Whether a live process on this firm refuses `action` (the panel greys it with BUSY).
static func blocks(ns, company_id: String, action) -> bool:
	if action == null or live(ns, company_id).is_empty():
		return false
	return BLOCKED_OPS.has(String((action.effects.get("company", {}) as Dictionary).get("op", "")))


## Why the register refuses `action` on this firm now, "" when it does not: a live
## process (BUSY), or the same verb settled on it within the last
## PROCESS_SETTLED_COOLDOWN_MONTHS (SETTLED: a settlement leaves the firm intact, so
## an immediate second referral would collect the fine again -- pass 1 on #248; the
## parent's call: a cooldown, not a bar for ever). The panel greys the verb with this
## line before the press (A5).
static func refusal(state, ns, company_id: String, action) -> String:
	if blocks(ns, company_id, action):
		return BUSY
	var now := _now(state)
	for row in ns.processes:
		if action != null and String(row["company_id"]) == company_id and String(row["action_id"]) == String(action.id) \
				and String(row["status"]) == "settled" and now - int(row["closed"]) < K.PROCESS_SETTLED_COOLDOWN_MONTHS:
			return SETTLED
	return ""


## The strip's figures for a process verb on this firm now: its stages, the
## duration range in months, the price range on the debt (signed: a windfall is
## negative) and, for a break-up, the ruling's odds with the range shown.
static func estimate(state, ns, loader, action, company_id: String) -> Dictionary:
	var company = _company(ns, loader, company_id)
	if company == null or not is_process(action):
		return {}
	var value := Companies.value_eur_bn(ns, company)
	var held := Companies.state_share_of(ns, company_id)
	var stake := float((action.effects.get("company", {}) as Dictionary).get("stake", 1.0))
	match String(action.id):
		"minority_stake":
			var base := (stake - held) * value
			return {"base_eur_bn": base, "price_lo": base * (1.0 + K.PROCESS_STAKE_PREMIUM.x),
				"price_hi": base * (1.0 + K.PROCESS_STAKE_PREMIUM.y),
				"months_lo": K.PROCESS_STAKE_MONTHS, "months_hi": K.PROCESS_STAKE_MONTHS}
		"full_nationalisation":
			var base := (stake - held) * value
			var months := K.PROCESS_OFFER_MONTHS + K.PROCESS_TRANSITION_MONTHS
			# The transition's cost in output (process_drag.gd), shown before the press: the
			# share of a year of the firm's output its management turnover loses.
			return {"base_eur_bn": base, "price_lo": base * (1.0 + K.PROCESS_NATIONALISE_PREMIUM.x),
				"price_hi": base * (1.0 + K.PROCESS_NATIONALISE_PREMIUM.y), "months_lo": months, "months_hi": months,
				"output_loss_eur_bn": Drag.loss_eur_bn(ns, company)}
		"privatisation":
			var base := held * value
			# A sale may be held once for a new bid (process_asks.gd), so it can run
			# one hold longer than its six months.
			return {"base_eur_bn": base, "price_lo": -base, "price_hi": -base * (1.0 - K.PROCESS_PRIVATISE_DISCOUNT.y),
				"months_lo": K.PROCESS_SALE_MONTHS, "months_hi": K.PROCESS_SALE_MONTHS + K.PROCESS_HOLD_MONTHS}
		"break_up":
			var odds := odds_for(Companies.share_of_company(ns, company))
			# The truth's fog, as the prices are (parent pass 2 on #244): a fixed-width
			# window with the truth seeded inside it, so its midpoint does not give it away.
			var u := Cycle.unit("process|odds|%s" % company_id, _now(state))
			var lo := clampf(odds - 2.0 * K.PROCESS_ODDS_FOG * u, 0.0, 1.0 - 2.0 * K.PROCESS_ODDS_FOG)
			return {"base_eur_bn": 0.0, "price_lo": K.PROCESS_LEGAL_COST_EUR_BN, "price_hi": K.PROCESS_LEGAL_COST_EUR_BN,
				"months_lo": K.PROCESS_INVESTIGATION_MONTHS.x,
				"months_hi": K.PROCESS_INVESTIGATION_MONTHS.y + K.PROCESS_REMEDY_MONTHS,
				"odds": odds, "odds_lo": lo, "odds_hi": lo + 2.0 * K.PROCESS_ODDS_FOG}
	return {}


## The authority's odds of ordering the break-up, rising with the firm's share
## between the spec's two points (about 50 % at a 10 % share, 85 % at 30 %).
static func odds_for(share: float) -> float:
	var t := clampf((share - K.PROCESS_ODDS_SHARE.x) / (K.PROCESS_ODDS_SHARE.y - K.PROCESS_ODDS_SHARE.x), 0.0, 1.0)
	return lerpf(K.PROCESS_ODDS.x, K.PROCESS_ODDS.y, t)


## Open the process: the same door and refusals as Companies.execute(), plus one
## process per firm. Nothing of the firm, the debt or the state share moves now.
static func start(state, ns, loader, action, company_id: String, by_law := false) -> Dictionary:
	if not is_process(action) or not Companies.available(state, ns, loader.company_actions, company_id, loader, by_law).has(action):
		return _refused(ns, action, company_id, "")
	var why := BUSY if not live(ns, company_id).is_empty() else refusal(state, ns, company_id, action)
	if why == "":
		why = Companies.refusal_reason(state, ns, action, company_id, loader)
	if why != "":
		return _refused(ns, action, company_id, why)
	var est := estimate(state, ns, loader, action, company_id)
	var now := _now(state)
	# The register's length makes the id (and so the seeds) unique even when a
	# process is stopped and the same verb reopened on the same firm that month.
	var id := "%s|%s|%d|%d" % [action.id, company_id, now, ns.processes.size()]
	var unit := Cycle.unit("process|%s" % id, now)
	var stage := String(FIRST_STAGE[action.id])
	var row := {
		"id": id, "action_id": String(action.id),
		"company_id": company_id, "status": OPEN, "stage": stage, "started": now, "closed": -1,
		"base_eur_bn": float(est["base_eur_bn"]), "rate": 0.0, "paid_eur_bn": 0.0,
		"price_lo": float(est["price_lo"]), "price_hi": float(est["price_hi"]),
		"months_lo": int(est["months_lo"]), "months_hi": int(est["months_hi"]),
		"owner": String((ns.companies[company_id] as Dictionary).get("owner", "")),
	}
	var months := 0
	match stage:
		"negotiation":
			months = K.PROCESS_STAKE_MONTHS
			row["rate"] = lerpf(K.PROCESS_STAKE_PREMIUM.x, K.PROCESS_STAKE_PREMIUM.y, unit)
		"offer":
			months = K.PROCESS_OFFER_MONTHS
			row["rate"] = lerpf(K.PROCESS_NATIONALISE_PREMIUM.x, K.PROCESS_NATIONALISE_PREMIUM.y, unit)
		"sale":
			months = K.PROCESS_SALE_MONTHS
		"investigation":
			var span := K.PROCESS_INVESTIGATION_MONTHS.y - K.PROCESS_INVESTIGATION_MONTHS.x
			months = K.PROCESS_INVESTIGATION_MONTHS.x + mini(int(unit * float(span + 1)), span)
			row["odds"] = float(est["odds"])
			row["odds_lo"] = float(est["odds_lo"])
			row["odds_hi"] = float(est["odds_hi"])
	_stage(row, stage, months)
	# Half the bloc move lands at the public start (the offer, the bill); a
	# break-up's lands whole at a ruling for it.
	if stage != "investigation":
		_blocs(ns, action.effects.get("bloc_offset", {}), K.PROCESS_BLOC_AT_START)
	ns.processes.append(row)
	return {"action_id": String(action.id), "company_id": company_id, "applied": true, "refused": false,
		"process_id": String(row["id"])}


## The firm panel's one door for a pressed verb: an ownership or structure verb
## opens its process, any other lands at once through Companies.execute(). Named
## execute so test_result_tone_lint sees the panel that calls it run a command.
static func execute(state, ns, loader, action, company_id: String) -> Dictionary:
	if is_process(action):
		return start(state, ns, loader, action, company_id)
	return Companies.execute(state, ns, loader.company_actions, action, company_id, loader)


## The asks waiting for an answer (process_asks.gd), oldest first, as copies.
static func asks(ns) -> Array:
	var out: Array = []
	for row in ns.processes:
		if String(row["status"]) == OPEN and not (row.get("ask", {}) as Dictionary).is_empty() and not row.has("answer"):
			out.append((row as Dictionary).duplicate(true))
	return out


## Answer a process's ask. Walking away and stopping are the stop verb, at once;
## the other answers land at the stage's end.
static func answer(state, ns, loader, process_id: String, answer_id: String) -> Dictionary:
	var row := _find(ns, process_id)
	if row.is_empty() or String(row["status"]) != OPEN or (row.get("ask", {}) as Dictionary).is_empty() or row.has("answer"):
		return {"ok": false, "reason": "Nothing here is waiting for an answer."}
	if Asks.answer_of(row, answer_id).is_empty():
		return {"ok": false, "reason": "That is not one of the answers."}
	if answer_id == "walk" or answer_id == "stop":
		# Recorded only once the stop has run, so a refused stop leaves the ask waiting.
		var price := stop(state, ns, loader, process_id)
		if bool(price["ok"]):
			row["answer"] = answer_id
		return price
	row["answer"] = answer_id
	return {"ok": true}


## What stopping costs now: {ok, debt_eur_bn, bloc_offset} or {ok: false, reason}.
static func stop_price(state, ns, loader, process_id: String) -> Dictionary:
	var row := _find(ns, process_id)
	if row.is_empty() or String(row["status"]) != OPEN:
		return {"ok": false, "reason": "This process is no longer running."}
	var action = _action(loader, String(row["action_id"]))
	match String(row["stage"]):
		"negotiation", "sale":
			return {"ok": true, "debt_eur_bn": 0.0, "bloc_offset": Asks.uturn(action)}
		"offer":
			var premium := float(row["base_eur_bn"]) * float(row["rate"])
			return {"ok": true, "debt_eur_bn": K.PROCESS_BREAK_FEE * premium, "bloc_offset": Asks.uturn(action)}
		"investigation":
			# The ruling is drawn with its ask, a month before the stage ends
			# (process_asks.gd); once it is drawn the process is past stopping, as
			# after any ruling (pass 1 on #248: else a known ruling could be dodged).
			if not row.has("ruled"):
				var total := int(row["stage_months"])
				var spent := float(total - int(row["months_left"])) / float(maxi(total, 1))
				return {"ok": true, "debt_eur_bn": K.PROCESS_LEGAL_COST_EUR_BN * spent, "bloc_offset": {}}
	return {"ok": false, "reason": "Past this stage the process cannot be stopped."}


static func stop(state, ns, loader, process_id: String) -> Dictionary:
	var price := stop_price(state, ns, loader, process_id)
	if not bool(price["ok"]):
		return price
	var row := _find(ns, process_id)
	_pay(ns, row, float(price["debt_eur_bn"]))
	_blocs(ns, price["bloc_offset"], 1.0)
	_close(state, row, "stopped")
	return price


## Each nation's running processes, a month on. WorldMonth runs this just before
## Companies, so a transfer this month is priced this month (the dividend's own
## one-month lag unchanged). A nation with nothing in progress costs one loop.
static func tick_month(state, loader) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		var ns = state.nations[id]
		for row in ns.processes:
			if String(row["status"]) == OPEN:
				_tick_row(state, ns, loader, row)
		ns.process_drag_pct = Drag.drag(ns, loader)


static func _tick_row(state, ns, loader, row: Dictionary) -> void:
	var entry: Dictionary = ns.companies.get(String(row["company_id"]), {})
	if entry.is_empty() or bool(entry.get("failed", false)) or String(entry.get("owner", "")) != String(row["owner"]):
		# After the transfer the state owns the firm (parent pass 2 on #244): a failure
		# in the transition hands it control now and never voids what was paid.
		if String(row["stage"]) == "transition" and not entry.is_empty():
			var terms: Dictionary = _action(loader, String(row["action_id"])).effects.get("company", {})
			entry["state_share"] = float(terms.get("stake", 1.0))
			_close(state, row, "done")
			return
		_close(state, row, "void")
		return
	row["months_left"] = int(row["months_left"]) - 1
	if int(row["months_left"]) > 1:
		return
	var action = _action(loader, String(row["action_id"]))
	# The stage's ask, posted in its last month and due when it ends (process_asks.gd).
	if int(row["months_left"]) == 1:
		Asks.post(ns, row, action, _now(state), _company(ns, loader, String(row["company_id"])))
		return
	var half := 1.0 - K.PROCESS_BLOC_AT_START
	match String(row["stage"]):
		"negotiation":
			if _land(state, ns, loader, action, row):
				_pay(ns, row, float(row["base_eur_bn"]) * (1.0 + float(row["rate"])))
				_blocs(ns, action.effects.get("bloc_offset", {}), half)
				_close(state, row, "done")
		"offer":
			_pay(ns, row, float(row["base_eur_bn"]) * (1.0 + float(row["rate"])))
			_blocs(ns, action.effects.get("bloc_offset", {}), half)
			_stage(row, "transition", K.PROCESS_TRANSITION_MONTHS)
		"transition":
			if _land(state, ns, loader, action, row):
				_close(state, row, "done")
		"sale":
			# The bid's discount was set when it was posted: the price shown is booked.
			# A sale saved before the asks (#248) and loaded in its last month was never
			# posted, so it is priced here, at the cycle's discount now (QA on #248).
			if not row.has("ask") and not bool(row.get("held", false)):
				row["rate"] = Asks.discount(ns)
			if Asks.chosen(row) == "hold":
				row["held"] = true
				_stage(row, "sale", K.PROCESS_HOLD_MONTHS)
				return
			if _land(state, ns, loader, action, row):
				_pay(ns, row, -float(row["base_eur_bn"]) * (1.0 - float(row["rate"])))
				_blocs(ns, action.effects.get("bloc_offset", {}), half)
				_close(state, row, "done")
		"investigation":
			_pay(ns, row, K.PROCESS_LEGAL_COST_EUR_BN)
			# A referral saved before the asks (#248) and loaded in its last month was
			# never ruled: the ruling is drawn here, on the same seed (QA on #248).
			if not row.has("ruled"):
				row["ruled"] = Asks.rule(row, _now(state))
			# A firm that no longer qualifies (its share under the gate, no rival
			# left to absorb it) is not ordered broken up: the blocs pay nothing
			# for a remedy the arm would refuse. The fees stay paid.
			var why := Companies.refusal_reason(state, ns, action, String(row["company_id"]), loader)
			if not Companies.available(state, ns, loader.company_actions, String(row["company_id"]), loader).has(action) or why != "":
				row["reason"] = why
				_close(state, row, "refused")
			elif not bool(row.get("ruled", false)):
				_close(state, row, "cleared")
			elif Asks.chosen(row) == "settle":
				var settle: Dictionary = Asks.answer_of(row, "settle")
				_pay(ns, row, float(settle["debt_eur_bn"]))
				_blocs(ns, settle["bloc_offset"], 1.0)
				_close(state, row, "settled")
			else:
				_blocs(ns, action.effects.get("bloc_offset", {}), 1.0)
				_stage(row, "remedy", K.PROCESS_REMEDY_MONTHS)
		"remedy":
			if _land(state, ns, loader, action, row):
				_close(state, row, "done")
			else:
				# The firm drifted under the gate in the remedy's months, so the
				# break-up never happens; the ruling's bloc move goes with it.
				_blocs(ns, action.effects.get("bloc_offset", {}), -1.0)


## The firm's arm, once: Companies.execute() at the stage's end, with the debt and
## the bloc offsets it writes put back (this file books both on its own timetable).
## A refusal closes the row: the firm no longer qualifies (its share fell under the
## gate, no rival is left to absorb it), and what was spent stays spent.
static func _land(state, ns, loader, action, row: Dictionary) -> bool:
	var debt := float(ns.debt_eur_bn)
	var offsets: Dictionary = (ns.bloc_offset as Dictionary).duplicate()
	var result: Dictionary = Companies.execute(state, ns, loader.company_actions, action,
		String(row["company_id"]), loader, action.requires_law)
	ns.debt_eur_bn = debt
	ns.bloc_offset.clear()
	ns.bloc_offset.merge(offsets)
	if not bool(result.get("applied", false)):
		row["reason"] = String(result.get("reason", ""))
		_close(state, row, "refused")
		return false
	return true


static func _stage(row: Dictionary, stage: String, months: int) -> void:
	row.erase("ask")
	row.erase("answer")
	row["stage"] = stage
	row["months_left"] = months
	row["stage_months"] = months


static func _close(state, row: Dictionary, status: String) -> void:
	row["status"] = status
	row["closed"] = _now(state)


static func _pay(ns, row: Dictionary, amount: float) -> void:
	ns.debt_eur_bn += amount
	row["paid_eur_bn"] = float(row["paid_eur_bn"]) + amount


## Clamped, as every writer of the register is (Companies.execute's comment).
static func _blocs(ns, offsets: Dictionary, share: float) -> void:
	for bloc in offsets:
		ns.bloc_offset[bloc] = clampf(float(ns.bloc_offset.get(bloc, 0.0)) + share * float(offsets[bloc]),
			LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX)


static func _refused(ns, action, company_id: String, reason: String) -> Dictionary:
	var refused := {"action_id": String(action.id) if action != null else "", "company_id": company_id,
		"applied": false, "refused": true}
	if reason != "":
		refused["reason"] = reason
	ns.last_company_result = refused
	return refused


static func _find(ns, process_id: String) -> Dictionary:
	for row in ns.processes:
		if String(row["id"]) == process_id:
			return row
	return {}


static func _action(loader, action_id: String):
	for action in loader.company_actions:
		if String(action.id) == action_id:
			return action
	return null


static func _company(ns, loader, company_id: String):
	for company in Companies.firms_of(loader, ns.id):
		if String(company.id) == company_id:
			return company
	return null


static func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)
