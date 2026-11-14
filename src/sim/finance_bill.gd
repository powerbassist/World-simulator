extends RefCounted

## The finance bill (docs/design/finance-bill.md; the author's call 1 for screen 4,
## the parent's go of 2026-11-14). Pending budget and tax changes are one bill: the
## player TABLES it into the month's slot (ns.tabled_bill, so the one-bill rule of
## V5.2 b+ R2 covers it), it divides as the first step of the close that ends the
## month (Division.divide branches here), and a carried bill applies there, before
## that close's Economy and Budget read it.
##
## THE BILL IS DELTAS, {"tax_rates_pct": {key: points}, "spending_pct_gdp": {key: points},
## "tax_progressivity": index}: applied on top of the live register at the division, so a
## rate a law or an event moved after the tabling keeps that move (apply_effects' rule).
##
## THE READING (section 3): a party reads the bill as a law, spatial_support() at the
## bill's position (finance_bill_law.gd), and a coalition partner adds the CENSURE's whip
## (its live discipline, less disaffection), because every European parliament treats the
## budget as a matter of confidence. The law's own whip is too weak for it: under it
## Germany and Britain fail even an unchanged budget at the start.
##
## No political price at passage (the opinion model already prices each line), no
## second chamber (the lower house has the last word on money in all four playable
## nations; Italy's Senate is a recorded reduction), no court (reach 0), no cooldown
## on a defeat: the slot and the rebels are its price.

const Budget = preload("res://src/sim/budget.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Government = preload("res://src/sim/government.gd")
const GK = preload("res://src/sim/government_constants.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const DK = preload("res://src/sim/discipline_constants.gd")
const DivisionTerms = preload("res://src/sim/division_terms.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const FrontPage = preload("res://src/sim/front_page.gd")
const ForcePrice = preload("res://src/sim/force_price.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const TaxK = preload("res://src/sim/tax_constants.gd")

const CHANNELS := ["tax_rates_pct", "spending_pct_gdp"]
const PROGRESSIVITY := "tax_progressivity"


## The panels' absolute pending values (Budget.commit's shape) as a bill of deltas
## against the live register. A key left where it stands is dropped; {} if nothing moved.
static func from_pending(ns, pending: Dictionary) -> Dictionary:
	var bill := {}
	for channel in CHANNELS:
		var register: Dictionary = ns.tax_rates_pct if channel == "tax_rates_pct" else ns.spending_pct_gdp
		var rows := {}
		for key in pending.get(channel, {}):
			var delta := float(pending[channel][key]) - float(register.get(key, 0.0))
			if delta != 0.0:
				rows[key] = delta
		if not rows.is_empty():
			bill[channel] = rows
	if pending.has(PROGRESSIVITY):
		var step := float(pending[PROGRESSIVITY]) - float(ns.tax_progressivity)
		if step != 0.0:
			bill[PROGRESSIVITY] = step
	return bill


## The player's command. Tables `bill` into the month's slot, or amends the finance bill
## already there (per key, the newer delta replaces). `force` engages Article 49.3 where
## the formation rule allows it, free of the ordinary cooldown; the bill still waits for
## the close. Refusals write nothing and carry the flag that names them.
static func table(state, loader, bill: Dictionary, force := false) -> Dictionary:
	var ns = state.player()
	if bill.is_empty():
		return {"tabled": false, "refused": true, "empty": true}
	var held: Dictionary = ns.tabled_bill
	if not held.is_empty() and not FinanceBillLaw.is_finance(String(held.get("law_id", ""))):
		return {"tabled": false, "refused": true, "already_tabled": true}
	if force and ns.formation_method != GK.FORCE_FORMATION:
		return {"tabled": false, "refused": true, "forced": true}
	var merged: Dictionary = (held.get("finance", {}) as Dictionary).duplicate(true)
	for channel in CHANNELS:
		if bill.has(channel):
			var rows: Dictionary = merged.get(channel, {})
			for key in bill[channel]:
				rows[key] = float(bill[channel][key])
			merged[channel] = rows
	if bill.has(PROGRESSIVITY):
		merged[PROGRESSIVITY] = float(bill[PROGRESSIVITY])
	var id := String(held.get("law_id", "")) if not held.is_empty() else FinanceBillLaw.id_for(state)
	ns.tabled_bill = {
		"law_id": id, "finance": merged, "forced": force or bool(held.get("forced", false)),
		"vote_year": int(state.year), "vote_month": int(state.month),
		"vote_day": Calendar.days_in_month(int(state.year), int(state.month)),
	}
	var tabling: Dictionary = ns.tabled_bill.duplicate(true)
	tabling["tabled"] = true
	# A forced bill is never divided: no vote to forecast (Division.forecast's rule).
	tabling["forecast"] = {} if bool(ns.tabled_bill["forced"]) else resolve(ns, loader.parties.get(ns.id, []), FinanceBillLaw.tabled(ns))
	return tabling


## The division as it would fall on `ns` now: pure, the forecast and the division both
## read it. resolve_vote()'s shape, plus `finance`.
static func resolve(ns, party_list: Array, law) -> Dictionary:
	var yes := 0
	var no := 0
	var abstain := 0
	var votes := {}
	var support := {}
	var rebels_by := {}
	var pledged_by := {}
	var unpopular := Discipline.unpopularity(ns)
	for party in party_list:
		var lean := Legislature.spatial_support(ns, party, law)
		var s := lean
		var own := lean
		if ns.coalition_party_ids.has(party.id):
			var d := Discipline.of(ns, party)
			s += d - DK.DISAFFECTION * unpopular * (1.0 - d)
			own -= DK.DISAFFECTION * unpopular
		s = clampf(s, -1.0, 1.0)
		own = clampf(own, -1.0, 1.0)
		support[party.id] = s
		var line := Legislature.vote_of(s)
		var rebel_line := Legislature.vote_of(own)
		var rebels := Discipline.rebel_seats(ns, party, s, own) if rebel_line != line else 0
		if rebels > 0:
			rebels_by[party.id] = rebels
		var pledged := DivisionTerms.pledged_seats(ns, party, law)
		if pledged > 0:
			pledged_by[party.id] = pledged
		var tally := DivisionTerms.seats_of(line, rebel_line, int(ns.seats_by_party.get(party.id, 0)), rebels, pledged,
			DivisionTerms.swayed_share(ns, party, law, false), DivisionTerms.swayed_share(ns, party, law, true))
		yes += int(tally[0])
		no += int(tally[1])
		abstain += int(tally[2])
		votes[party.id] = line
	var result := {
		"law_id": law.id, "passed": DivisionTerms.passed(ns, law, yes, no, false), "finance": true,
		"majority": law.majority, "referendum_route": false,
		"yes_seats": yes, "no_seats": no, "abstain_seats": abstain, "seats_total": ns.assembly_seats,
		"party_votes": votes, "party_support": support, "party_rebels": rebels_by,
	}
	if not pledged_by.is_empty():
		result["party_pledged"] = pledged_by
	return result


## The tabled finance bill divides (Division.divide's branch; the register is already
## cleared by the caller). Forced: adopted with no vote, the censure first, applied only
## if it fails. Otherwise the reading above, its rebels charged, applied if carried.
static func divide(state, loader, ns, tabled: Dictionary) -> Dictionary:
	var party_list: Array = loader.parties.get(ns.id, [])
	var law = FinanceBillLaw.law(ns, tabled)
	var bill: Dictionary = tabled.get("finance", {})
	var result: Dictionary
	if bool(tabled.get("forced", false)):
		result = {
			"law_id": law.id, "passed": false, "finance": true, "forced": true, "majority": law.majority,
			"yes_seats": 0, "no_seats": 0, "abstain_seats": 0, "seats_total": ns.assembly_seats,
			"party_votes": {}, "party_support": {}, "party_rebels": {},
		}
		DivisionTerms.judge_pledges(ns, law, int(state.year) * 12 + int(state.month), true)
		var censure := ForcePrice.charge(ns, party_list)
		result["censure"] = censure
		result["passed"] = not bool(censure["carried"])
	else:
		result = resolve(ns, party_list, law)
		DivisionTerms.judge_pledges(ns, law, int(state.year) * 12 + int(state.month))
		var by_id := {}
		for party in party_list:
			by_id[party.id] = party
		Discipline.penalise_rebellions(ns, result["party_rebels"], by_id)
	if result["passed"]:
		Budget.apply_pending(ns, _absolute(ns, bill))
		Budget.recompute(state, ns)
	result["finance_bill"] = bill.duplicate(true)
	ns.last_law_result = result
	if bool(result.get("forced", false)):
		FrontPage.note_forced(state, ns, result)
	return result


## The bill's deltas on top of the live register: Budget.apply_pending's shape. The
## schedule is clamped to its band here, as the panel's control clamps it.
static func _absolute(ns, bill: Dictionary) -> Dictionary:
	var pending := {}
	for channel in CHANNELS:
		if bill.has(channel):
			var register: Dictionary = ns.tax_rates_pct if channel == "tax_rates_pct" else ns.spending_pct_gdp
			var rows := {}
			for key in bill[channel]:
				rows[key] = float(register.get(key, 0.0)) + float(bill[channel][key])
			pending[channel] = rows
	if bill.has(PROGRESSIVITY):
		pending[PROGRESSIVITY] = clampf(float(ns.tax_progressivity) + float(bill[PROGRESSIVITY]),
			TaxK.PROGRESSIVITY_MIN, TaxK.PROGRESSIVITY_MAX)
	return pending
