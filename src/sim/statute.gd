extends RefCounted

## The statute book's composition machine: the player drafts a bill out of
## named effect channels, the machine prices it politically and parks it for
## a drafting period, and the finished bill enters the nation's own register
## as a law like any other -- proposed, voted, failable, repealable.
##
## A leaf: preloads its constants, Law, and legislature.gd (for the repeal
## gate only -- legislature cannot preload this file back, so the legality
## scan rebuilds composed laws off the core Law factory, never through here).
## One writer of ns.draft_bills and ns.custom_laws, both reset in
## Legislature.init_nation(). No rand() anywhere -- the countdown is a
## counter, the derived price a pure function of the spec, and a draft's id
## is arithmetic -- so two identical states draft identically, the same
## discipline as economy.gd and legislature.gd.
##
## NOT wired into main.gd yet: this task's tick_month counts drafts down
## only. The PMB and lobbying machines land with their task and bring the
## main.gd call with them; the test drives tick_month directly.
##
## The model, and the justification for every constant, is
## docs/legislature-model.md.

const SK = preload("res://src/sim/statute_constants.gd")
const Law = preload("res://src/core/law.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const C = preload("res://src/sim/economy_constants.gd")
const CK = preload("res://src/sim/companies_constants.gd")

## The channels a spec may name. The keyed channels carry {sub_key: value},
## the scalars a bare float, company its {sector, burden} shape and society
## its terms -- exactly the shapes law.gd's loader accepts, because the
## composed law passes through the ONE applier at passage. bloc_offset and
## institutional are not here on purpose: the price is what the machine
## derives, and a setting is never composed (T1's repeal gate would refuse
## the bill at birth -- an unrepealable act).
const KEYED_CHANNELS := ["tax_rates_pct", "spending_pct_gdp"]
const SCALAR_CHANNELS := ["structural_unemployment_pct", "potential_growth_pct", "other_revenue_pct_gdp"]
const SOCIETY_CHANNEL := "society"
const COMPANY_CHANNEL := "company"


## The player command: validate the spec, price it, park it. Refused specs
## mutate nothing -- every check runs before the first write.
##
## `loader` is required rather than defaulted, apply()'s reason one file over:
## a repeal spec is gated through Legislature.repeal_target_legal(), whose
## target lookup needs it. A defaulted loader would let a repeal of an
## institutional law draft clean and then half-remove the act at passage --
## the exact defect the gate exists to refuse. (The plan's interface had
## draft(state, ns, spec); the loader joined the signature at implementation,
## the plan's own pre-authorised-adjustment clause.)
##
## Returns {ok, refusal, draft_id, size, months, price}. On a refusal only
## `ok` and `refusal` carry anything.
static func draft(state, ns, loader, spec: Dictionary) -> Dictionary:
	var bill_name := String(spec.get("name", ""))
	if bill_name == "":
		return _refuse("A bill needs a name.")

	var pos: Dictionary = spec.get("position", {})
	if typeof(pos) != TYPE_DICTIONARY or not pos.has("economic") or not pos.has("social"):
		return _refuse("The bill needs a position on both axes.")
	var econ := float(pos.get("economic", 0.0))
	var social := float(pos.get("social", 0.0))
	if econ < -1.0 or econ > 1.0 or social < -1.0 or social > 1.0:
		return _refuse("The bill's position must sit inside [-1, 1] on both axes.")

	var channels: Dictionary = spec.get("channels", {})
	if typeof(channels) != TYPE_DICTIONARY:
		return _refuse("The bill's channels must be named as an object.")
	var repeals := String(spec.get("repeals", ""))
	# A BIRTH is a lever too: a bill that only proposes a new tax names
	# something, so it passes the emptiness gate on its new_tax alone (T4).
	# Guarded before the typed bind -- a non-dict payload must refuse, not
	# crash the assignment.
	var new_tax_raw: Variant = spec.get("new_tax", {})
	if typeof(new_tax_raw) != TYPE_DICTIONARY:
		return _refuse("A new tax names its params as an object.")
	var new_tax: Dictionary = new_tax_raw
	if channels.is_empty() and repeals == "" and new_tax.is_empty():
		return _refuse("A bill names at least one channel, a law to repeal, or a tax to birth.")

	var refusal := _validate_channels(channels)
	if refusal != "":
		return _refuse(refusal)

	if repeals != "" and not Legislature.repeal_target_legal(ns, loader, repeals):
		return _refuse("That law cannot be repealed -- the book records no repealable contribution from it, or it sets something no subtraction can remove.")

	if not new_tax.is_empty():
		# V4.2 T4. The birth gate. The collision refusal is T2's and stands;
		# the T2 interim refusal of VALID specs is gone -- the params register
		# is wired (Budget.revenue_lines/_erosion/commit take it, opinion
		# prices the key, apply() registers the params at passage), so an
		# accepted spec is a tax, not a silent drop.
		if String(new_tax.get("key", "")) == "":
			return _refuse("A new tax names a key.")
		var tax_key := String(new_tax["key"])
		if C.TAX_KEYS.has(tax_key):
			return _refuse("That tax key already exists in the tax code.")
		# One key, one birth: the params register is the authorising record,
		# and a second bill proposing the same key would re-price a base and
		# erosion the first passage already put on the books -- two answers to
		# one question.
		if ns.custom_taxes.has(tax_key):
			return _refuse("'%s' is already a tax key -- one key, one birth." % tax_key)
		var tax_refusal := _validate_new_tax(new_tax)
		if tax_refusal != "":
			return _refuse(tax_refusal)

	var size := _size_of(channels)
	if size > SK.DRAFT_SIZE_MAX:
		return _refuse("The drafting budget does not stretch that far (size %.2f of %.2f)." % [size, SK.DRAFT_SIZE_MAX])

	var price := _derived_price(channels)
	# The repeal's negated ledger is frozen here as the RECORD of what the
	# player was shown, not as the mechanism: at passage T1 subtracts the
	# target's LIVE ledger, and a frozen copy riding the effects would apply
	# a second time.
	var negated := {}
	if repeals != "":
		for channel in Legislature.ledger_of(ns, repeals):
			var slot: Dictionary = Legislature.ledger_of(ns, repeals)[channel]
			var negated_slot := {}
			for sub_key in slot:
				negated_slot[sub_key] = -float(slot[sub_key])
			negated[channel] = negated_slot

	var months := SK.DRAFT_MONTHS_BASE + int(ceil(size * SK.DRAFT_MONTHS_PER_SIZE))
	# The plan's id scheme, verbatim. Append-only draft_bills is what makes it
	# collision-free: two drafts in one month differ by size(), and entries
	# are never erased, so size() never repeats against an earlier id.
	var draft_id := "draft_%d" % (ns.draft_bills.size() + int(state.year) * 12 + int(state.month))
	ns.draft_bills[draft_id] = {
		"name": bill_name,
		"position": {"economic": econ, "social": social},
		"channels": channels.duplicate(true),
		"new_tax": new_tax.duplicate(true),
		"repeals": repeals,
		"negated": negated,
		"size": size,
		"price": price,
		"months_left": months,
	}
	return {"ok": true, "refusal": "", "draft_id": draft_id, "size": size, "months": months, "price": price}


static func _refuse(message: String) -> Dictionary:
	return {"ok": false, "refusal": message, "draft_id": "", "size": 0.0, "months": 0, "price": {}}


## Shape validation, one refusal at a time -- unknown channel, unknown
## sub-key, zero movement, the society terms' own maxima, the company shape,
## and law.gd's three anti-double-count pairs. A composed bill must be
## composeable from what the loader would accept, or passage would run
## effects the schema exists to refuse.
static func _validate_channels(channels: Dictionary) -> String:
	var known: Array = KEYED_CHANNELS + SCALAR_CHANNELS + [SOCIETY_CHANNEL, COMPANY_CHANNEL]
	for channel in channels:
		if not known.has(channel):
			return "'%s' is not a channel a composed bill may name." % channel

	for channel in KEYED_CHANNELS:
		if not channels.has(channel):
			continue
		var keys: Array = C.TAX_KEYS if channel == "tax_rates_pct" else C.SPENDING_KEYS
		var table: Dictionary = channels[channel]
		if typeof(table) != TYPE_DICTIONARY or table.is_empty():
			return "The bill's %s must name at least one key." % channel
		for key in table:
			if not keys.has(key):
				return "'%s' is not a recognised %s key." % [key, channel]
			if not _numeric_nonzero(table[key]):
				return "A lever that moves nothing is not a lever (%s %s)." % [channel, key]

	for channel in SCALAR_CHANNELS:
		if channels.has(channel) and not _numeric_nonzero(channels[channel]):
			return "A lever that moves nothing is not a lever (%s)." % channel

	if channels.has(COMPANY_CHANNEL):
		var company: Dictionary = channels[COMPANY_CHANNEL]
		if typeof(company) != TYPE_DICTIONARY or not company.has("sector") or not company.has("burden"):
			return "A sector burden names one sector and a burden."
		if not C.SECTOR_TREND.has(String(company["sector"])):
			return "'%s' is not a recognised sector." % company["sector"]
		if not _numeric_nonzero(company["burden"]):
			return "A burden that binds nobody is not a burden."
		if absf(float(company["burden"])) > CK.REGULATION_BURDEN_MAX:
			return "That burden exceeds what one act may impose on a sector."

	if channels.has(SOCIETY_CHANNEL):
		var society: Dictionary = channels[SOCIETY_CHANNEL]
		if typeof(society) != TYPE_DICTIONARY or society.is_empty():
			return "The bill's society terms must name at least one."
		for term in society:
			if not Law.SOCIETY_TERMS.has(term):
				return "'%s' is not a recognised society term." % term
			if not _numeric_nonzero(society[term]):
				return "A reform that changes nothing is not a reform (%s)." % term
			if absf(float(society[term])) > float(Law.SOCIETY_TERMS[term]):
				return "society.%s exceeds what one act may move." % term

	# law.gd's three anti-double-count refusals, at the machine: the same act
	# priced twice through two channels is a load error there and a silent
	# double-count here.
	if channels.has(COMPANY_CHANNEL) and channels.has("structural_unemployment_pct"):
		return "One story per bill: a sector burden already reaches structural unemployment through the firm register."
	if channels.has(SOCIETY_CHANNEL) and channels.has("spending_pct_gdp") \
			and channels[SOCIETY_CHANNEL].has("corruption"):
		return "One story per bill: a corruption stance already reaches the spending issues through the quality stock."
	if channels.has(SOCIETY_CHANNEL) and channels.has("structural_unemployment_pct") \
			and channels[SOCIETY_CHANNEL].has("migration"):
		return "One story per bill: a migration stance already reaches structural unemployment through the labour force."

	return ""


static func _numeric_nonzero(value) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return float(value) != 0.0


## The params of a proposed tax key, bounded where the authored tables bound
## theirs -- SK.NEW_TAX_* carries the numbers and their whys. A birth that
## passed this gate has a curve the shared _erosion() can run: a positive base
## to price, a live coefficient, and a birth rate that doubles as the erosion
## reference, so the curve always has something to divide by.
static func _validate_new_tax(new_tax: Dictionary) -> String:
	if String(new_tax.get("name", "")).strip_edges() == "":
		return "A tax needs a name to be argued about."
	if not _numeric_nonzero(new_tax.get("base_share", null)):
		return "A new tax names a base share of GDP."
	if not _numeric_nonzero(new_tax.get("erosion", null)):
		return "A new tax names an erosion for its base."
	if not _numeric_nonzero(new_tax.get("rate", null)):
		return "A new tax is born at a rate -- the rate is its erosion reference, so a zero rate has no curve."
	if float(new_tax["base_share"]) < 0.0:
		return "A negative base share is not a base -- the register prices what a levy sits on."
	if float(new_tax["erosion"]) < 0.0:
		return "A negative erosion is not an erosion -- it would steepen the curve where every authored coefficient softens it."
	if float(new_tax["rate"]) < 0.0:
		return "A negative birth rate is not a rate -- the rate is the curve's reference, so it must be positive."
	if float(new_tax["base_share"]) > SK.NEW_TAX_BASE_SHARE_MAX:
		return "That base exceeds anything the tax code prices (a net-wealth stock, 4.00 of GDP, is the ceiling)."
	if float(new_tax["erosion"]) > SK.NEW_TAX_EROSION_MAX:
		return "That erosion would clamp the curve flat above the birth rate."
	if float(new_tax["rate"]) > SK.NEW_TAX_RATE_MAX:
		return "A rate above %d points is not a rate." % int(SK.NEW_TAX_RATE_MAX)
	# The two caps above bound their fields independently; the revenue formula
	# reads the PRODUCT. Without this gate base 4.0 x rate 100 = 400 % of GDP
	# in revenue from one bill -- nothing else in the birth gate brakes it.
	if float(new_tax["base_share"]) * float(new_tax["rate"]) > SK.NEW_TAX_YIELD_CEILING:
		return "That base times that rate would yield %.1f of GDP -- the most the revenue model prices is %.1f (the wealth tax's own 4.0 x 3.0)." \
			% [float(new_tax["base_share"]) * float(new_tax["rate"]), SK.NEW_TAX_YIELD_CEILING]
	return ""


## The budget arithmetic: |value| x CHANNEL_COST, summed over everything the
## spec names. bloc_offset is absent by construction -- the player never
## writes political prices directly.
static func _size_of(channels: Dictionary) -> float:
	var total := 0.0
	for channel in KEYED_CHANNELS:
		for key in channels.get(channel, {}):
			total += absf(float(channels[channel][key])) * float(SK.CHANNEL_COST[channel])
	for channel in SCALAR_CHANNELS:
		if channels.has(channel):
			total += absf(float(channels[channel])) * float(SK.CHANNEL_COST[channel])
	if channels.has(COMPANY_CHANNEL):
		total += absf(float(channels[COMPANY_CHANNEL]["burden"])) * float(SK.CHANNEL_COST[COMPANY_CHANNEL])
	for term in channels.get(SOCIETY_CHANNEL, {}):
		total += absf(float(channels[SOCIETY_CHANNEL][term])) * float(SK.CHANNEL_COST[SOCIETY_CHANNEL])
	return total


## The derived political price, from SK.CHANNEL_PRICE: per channel, per bloc,
## value x per-unit. Exact-zero sums are dropped, so a single-channel draft
## always prices at least the blocs its table row names -- the all-upside
## guard.
static func _derived_price(channels: Dictionary) -> Dictionary:
	var price := {}
	for key in channels.get("tax_rates_pct", {}):
		_price_blend(price, SK.CHANNEL_PRICE["tax_rates_pct"].get(key, {}), float(channels["tax_rates_pct"][key]))
	for key in channels.get("spending_pct_gdp", {}):
		var rows: Dictionary = SK.CHANNEL_PRICE["spending_pct_gdp"].get(key, {})
		var value := float(channels["spending_pct_gdp"][key])
		var row: Dictionary = rows.get("rise", {}) if value > 0.0 else rows.get("cut", {})
		_price_blend(price, row, absf(value))
	for channel in SCALAR_CHANNELS:
		if channels.has(channel):
			_price_blend(price, SK.CHANNEL_PRICE[channel], float(channels[channel]))
	if channels.has(COMPANY_CHANNEL):
		_price_blend(price, SK.CHANNEL_PRICE[COMPANY_CHANNEL], float(channels[COMPANY_CHANNEL]["burden"]))
	for term in channels.get(SOCIETY_CHANNEL, {}):
		_price_blend(price, SK.CHANNEL_PRICE[SOCIETY_CHANNEL].get(term, {}), float(channels[SOCIETY_CHANNEL][term]))
	return price


static func _price_blend(price: Dictionary, row: Dictionary, units: float) -> void:
	for bloc in row:
		var total := float(price.get(bloc, 0.0)) + float(row[bloc]) * units
		if total == 0.0:
			# Exact-zero erasure only -- is_equal_approx's absolute floor
			# would drop real small prices (the V4.7 lesson).
			price.erase(bloc)
		else:
			price[bloc] = total


## Every composed law on the register, rebuilt as Law objects -- the list the
## legality scan and the law panel concatenate onto loader.laws, so a
## composed law is a law like any other.
static func custom_laws(ns) -> Array:
	return Law.composed_register(ns)


## V4.2 T5. Commission a poll on one bill. The ONE writer of
## ns.poll_purchases, and the one place outside Budget.tick_month() that
## moves the debt stock on the player's behalf -- the companies.gd bailout's
## exact discipline, restated here because the next sim author will meet this
## register before that comment:
##
## A POLL FEE IS A ONE-OFF PURCHASE, not income. The cost lands on the debt
## STOCK (`debt_eur_bn`) through the GDP level, and it moves
## `deficit_pct_gdp` by exactly zero in the month it happens -- the deficit is
## a precondition field, and a one-off on the revenue side would close the
## loop the subsidy bill's one-month lag exists to avoid. The interest on it
## is priced by Budget.recompute() at the real rate from the next tick, like
## any other debt.
##
## The purchase is recorded per bill AND per kind, once and for good: the
## poll's whole point is the FIXED-FORECAST rule -- the surfaces show one
## published figure and never re-roll it -- so a second commission of the same
## kind would be a re-roll of a number the player already bought, and it is
## refused. `bill_key` is the law id for an authored bill and the draft id for
## a composed one (the draft becomes that law, so a poll bought in drafting
## still names the bill after passage).
##
## READS the register here and nowhere else in src/sim/: it remembers money,
## not display, and the surfaces reach it directly (tests/test_statute_surfaces.gd
## scans the directory for the single-writer pin).
static func buy_poll(state, ns, bill_key: String, kind: String) -> Dictionary:
	if not SK.POLL_COSTS.has(kind):
		return {"ok": false, "refused": true, "refusal": "There is no such poll.", "cost_eur_bn": 0.0}
	if String(bill_key) == "":
		return {"ok": false, "refused": true, "refusal": "A poll is commissioned on a named bill.", "cost_eur_bn": 0.0}
	var bought: Dictionary = ns.poll_purchases.get(bill_key, {})
	if bought.has(kind):
		var when := int(bought[kind].get("month", 0))
		return {"ok": false, "refused": true,
			"refusal": "That poll was commissioned already (month %d) -- the figures it bought are fixed." % when,
			"cost_eur_bn": 0.0}
	var cost := float(ns.gdp_eur_bn) * float(SK.POLL_COSTS[kind]) / 100.0
	if not ns.poll_purchases.has(bill_key):
		ns.poll_purchases[bill_key] = {}
	ns.poll_purchases[bill_key][kind] = {
		"month": int(state.year) * 12 + int(state.month),
		"cost": cost,
	}
	ns.debt_eur_bn += cost
	return {"ok": true, "refused": false, "refusal": "", "kind": kind,
		"bill_key": String(bill_key), "cost_eur_bn": cost}


## The in-tray read: the drafts still counting down. Settled entries stay
## parked at months_left 0 (the id scheme reads size(), so entries are never
## erased) and are filtered here instead.
static func drafts(ns) -> Array:
	var out: Array = []
	for draft_id in ns.draft_bills:
		var entry: Dictionary = ns.draft_bills[draft_id]
		if int(entry.get("months_left", 0)) > 0:
			out.append(entry)
	return out


## Monthly tick. THE PLAYER NATION ONLY: has_budget is the standing refusal
## of AI nations legislating, the same gate legislature.tick_month() reads.
##
## `loader` is the plan's contract and is unused while the tick counts drafts
## only -- T6's assembly bills resolve divisions against loader.parties, and
## the parameter is in place so no call site moves when it does.
static func tick_month(state, loader) -> void:
	for ns in state.nations.values():
		if not ns.has_budget:
			continue
		_tick_drafts(ns)


## Count every parked draft down, and compose the ones whose time is up.
## Counting down BEFORE composing, so a draft composed this month was priced
## and parked for exactly the months it was quoted (the V2.8 cooldown lesson:
## ordered the other way round, every bill would arrive one month short).
static func _tick_drafts(ns) -> void:
	var due: Array = []
	for draft_id in ns.draft_bills:
		var entry: Dictionary = ns.draft_bills[draft_id]
		var left := int(entry.get("months_left", 0))
		if left <= 0:
			continue
		left -= 1
		entry["months_left"] = left
		if left <= 0:
			due.append(draft_id)
	for draft_id in due:
		_compose(ns, String(draft_id))


## The draft becomes a law. effects = channels + derived price -- the player
## wrote the channels, the machine wrote the price, and the merged dictionary
## is what the ONE applier reads at passage. A BIRTH's rate rides the ordinary
## tax_rates_pct channel so the one applier routes it: apply_effects() ADDS
## each value to the current rate, and at birth the rate is 0.0 (one key, one
## birth guarantees no earlier writer), so the add lands the bill's rate
## exactly. The params travel on the Law itself in the register's own shape;
## Legislature.apply() registers them BEFORE apply_effects() runs, so
## commit() sees a keyed tax and not a pending rate with nothing behind it.
## The register holds the save form (to_save_dict), never a live Law: it
## round-trips through JSON and is rebuilt on read.
static func _compose(ns, draft_id: String) -> void:
	var entry: Dictionary = ns.draft_bills.get(draft_id, {})
	if entry.is_empty():
		return
	var channels: Dictionary = entry.get("channels", {})
	var effects: Dictionary = Dictionary(channels).duplicate(true)
	var tax_entry := {}
	var new_tax: Dictionary = entry.get("new_tax", {})
	if not new_tax.is_empty():
		var rates: Dictionary = effects.get("tax_rates_pct", {})
		rates[String(new_tax["key"])] = float(new_tax.get("rate", 0.0))
		effects["tax_rates_pct"] = rates
		tax_entry = {
			"key": String(new_tax["key"]),
			"name": String(new_tax.get("name", "")),
			"base_share": float(new_tax.get("base_share", 0.0)),
			"erosion": float(new_tax.get("erosion", 0.0)),
			"ref_pct": float(new_tax.get("rate", 0.0)),
		}
	var price: Dictionary = entry.get("price", {})
	if not price.is_empty():
		effects["bloc_offset"] = Dictionary(price).duplicate(true)
	# Untyped on purpose: composed_from_dict() carries no return annotation
	# (from_dict's shape -- self-typing a fresh factory hits the class-cache
	# gotcha), so := cannot infer here.
	var law = Law.composed_from_dict({
		"id": draft_id,
		"name": String(entry.get("name", "")),
		"theme": _theme_of(effects),
		"summary": "",
		"position": entry.get("position", {}),
		"majority": "simple",
		"cooldown_months": SK.DRAFT_COOLDOWN_MONTHS,
		"once": false,
		"effects": effects,
		"new_tax": tax_entry,
		"repeals": String(entry.get("repeals", "")),
		"origin": "player",
	})
	ns.custom_laws[law.id] = law.to_save_dict()


## The display theme of a composed bill, derived from its effect channels --
## a runtime-built law has no authored theme, and the panel reads one. Called
## with the MERGED effects (a birth's rate is already in tax_rates_pct, so a
## new-tax bill reads tax without its own branch), which for a channels-only
## bill is the channels dictionary unchanged -- bloc_offset is present but
## named by no check below. The mapping is the vocabulary THEME_KEYS already
## fixes: tax levers are tax, stances are social, sector burdens are business,
## a pure repeal amends the statute book itself (institutional), and the
## spending/scalar levers -- the budget-and-labour story -- take labour.
static func _theme_of(effects: Dictionary) -> String:
	if effects.has("tax_rates_pct") or effects.has("other_revenue_pct_gdp"):
		return "tax"
	if effects.has(SOCIETY_CHANNEL):
		return "social"
	if effects.has(COMPANY_CHANNEL):
		return "business"
	if effects.is_empty():
		return "institutional"
	return "labour"
