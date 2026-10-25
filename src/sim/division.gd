extends RefCounted

## V5.2 b+ R2 -- the division of the player's tabled bill. Legislature.propose()
## TABLES a bill (the author, gate b: "laws passed or rejected instantly"); it
## divides here, as the FIRST step of the close that ends the month
## (src/sim/world_month.gd), so a bill tabled mid-month still applies before that
## close's Economy, Opinion and Elections, as it did when it divided at the press.
## The design: docs/design/v5.2-bplus-spec.md "R2".
##
## WHY A FILE OF ITS OWN: this is the tail propose() used to run at once -- the
## division, the second chamber, the referendum call, the court, the cooldown and
## the rebellions' price -- moved, not rewritten, and legislature.gd is at its size
## ratchet. It preloads Legislature and Legislature does not preload it, so the
## move is no cycle. Article 49.3 stays in legislature.gd: adoption without a vote
## is not tabled.

const Legislature = preload("res://src/sim/legislature.gd")
const Bills = preload("res://src/sim/bills.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Referendum = preload("res://src/sim/referendum.gd")
const ReferendumK = preload("res://src/sim/referendum_constants.gd")
const Chambers = preload("res://src/sim/chambers.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")


## The tabled bill divides: its result is written to ns.last_law_result, as
## propose() wrote it, and returned; the register is cleared. {} when nothing is
## tabled. A law no longer open at the close (applied in between, or an ownership
## bill no longer offered) divides nothing and reads refused `unavailable`, the
## legality propose() checked at the press read again at the vote -- the guard
## against applying one law twice.
static func divide(state, loader) -> Dictionary:
	var ns = state.player()
	if ns == null or ns.tabled_bill.is_empty():
		return {}
	var tabled: Dictionary = ns.tabled_bill
	ns.tabled_bill = {}
	var party_list: Array = loader.parties.get(ns.id, [])
	var law = Legislature.open_law(state, ns, loader, String(tabled.get("law_id", "")))
	if law == null:
		return Legislature.refused(ns, String(tabled.get("law_id", "")), "", "unavailable")

	var route := Legislature.takes_route(ns, law, bool(tabled.get("referendum", false)))
	# propose() refused a route with a vote in flight; read again at the vote, so a
	# question announced in between is never overwritten (the V1.7c finding).
	if route and Referendum.is_pending(ns):
		return Legislature.refused(ns, law.id, law.majority, "referendum_in_flight")

	var result := Legislature.resolve_vote(ns, party_list, law, route)
	var by_id := {}
	for party in party_list:
		by_id[party.id] = party

	# V1.1e. THE SECOND CHAMBER, between the division and everything after it, and
	# that position is Art. 89's rather than a convenience: a French revision bill must
	# pass BOTH CHAMBERS in identical terms and only then goes to the country or to
	# Congress. Luxembourg's block is absent and Chambers.power_over() returns
	# VERDICT_NONE for it, so a unicameral nation needs no branch here.
	var power: String = Chambers.power_over(ns, law)
	if result["passed"] and power != ChambersK.VERDICT_NONE:
		var upper := Legislature.resolve_upper(ns, party_list, law)
		result["upper_chamber"] = ns.upper_chamber_name
		result["upper_power"] = power
		result["upper_passed"] = upper["passed"]
		result["upper_yes_seats"] = upper["yes_seats"]
		result["upper_no_seats"] = upper["no_seats"]
		result["upper_abstain_seats"] = upper["abstain_seats"]
		result["upper_seats_total"] = upper["seats_total"]
		if not upper["passed"]:
			result["passed"] = false
			if power == ChambersK.VERDICT_ABSOLUTE:
				result["blocked_by_upper"] = true
				if law.cooldown_months > 0:
					ns.law_cooldown_months[law.id] = law.cooldown_months
			else:
				# HELD, not defeated: no cooldown, because the bill has not been beaten
				# and is still in flight. tick_month() passes it when the hold runs
				# out. The origin rides the entry (the ultra pass-2 shape): "player"
				# is what makes the release charge the override price -- the
				# government's own insistence is the thing being priced.
				result["held_by_upper"] = true
				result["held_months"] = ChambersK.UPPER_HOLD_MONTHS
				ns.held_bills[law.id] = {"months": ChambersK.UPPER_HOLD_MONTHS, "origin": "player"}
			Discipline.penalise_rebellions(ns, result["party_rebels"], by_id)
			ns.last_law_result = result
			return result

	if result["passed"] and route:
		# The chamber said yes; the country has not been asked yet. Nothing is
		# applied, no `once` flag is set and no cooldown is written -- the law is IN
		# FLIGHT, which is a third outcome this function did not have before.
		Referendum.announce(ns, law.id, law.position)
		result["passed"] = false
		result["referendum_called"] = true
		result["referendum_months"] = ReferendumK.REFERENDUM_DELAY_MONTHS
	elif result["passed"]:
		# V1.1e. THE COURT, the last stage before the bill takes effect. It may set
		# result["passed"] back to false and write the cooldown itself.
		Legislature.review_and_apply_after_division(state, ns, law, loader, result)
	elif law.cooldown_months > 0:
		ns.law_cooldown_months[law.id] = law.cooldown_months

	# A whip that failed fails more easily next time, whichever way the bill went.
	# Applied here rather than in resolve_vote(), which stays a pure function of
	# state so the forecast can call it as often as it likes.
	Discipline.penalise_rebellions(ns, result["party_rebels"], by_id)

	ns.last_law_result = result
	return result


## The tabled bill's division as it would fall on `ns` now -- resolve_vote(), pure --
## or {} with nothing tabled. `ns` may be a copy: Removal.price() reads its forecast
## before and after a dismissal's discipline step on one (the Budget.project() pattern).
static func forecast(state, ns, loader) -> Dictionary:
	if ns.tabled_bill.is_empty():
		return {}
	var law = Legislature.open_law(state, ns, loader, String(ns.tabled_bill.get("law_id", "")))
	if law == null:
		return {}
	return Legislature.resolve_vote(ns, loader.parties.get(ns.id, []), law,
		Legislature.takes_route(ns, law, bool(ns.tabled_bill.get("referendum", false))))
