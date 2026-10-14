extends RefCounted

## The statute book's composition machine: the player drafts a bill out of
## named effect channels, the machine prices it politically and parks it for
## a drafting period, and the finished bill enters the nation's own register
## as a law like any other -- proposed, voted, failable, repealable.
##
## The preload ledger, companies.gd's post-PR-47 form: SK (its own constants),
## Law, legislature.gd (the repeal gate and the division's applier --
## legislature cannot preload this file back, so the legality scan rebuilds
## composed laws off the core Law factory, never through here),
## economy_constants, companies_constants, Cycle, election_constants, and --
## V4.2's ultra review, the second chamber on a carried bill -- chambers.gd
## and chambers_constants.gd. NOT a leaf, and not pretending to be one.
## One writer of ns.draft_bills, ns.custom_laws and ns.assembly_bills, all
## reset in Legislature.init_nation(); on a suspensive hold it parks beside
## propose() into ns.held_bills. No rand() anywhere -- the countdown is
## a counter, the derived price a pure function of the spec, a draft's id is
## arithmetic, and the assembly's hazards draw on Cycle.unit over the
## absolute month (the events.gd discipline) -- so two identical states draft
## identically, the same discipline as economy.gd and legislature.gd.
##
## The model, and the justification for every constant, is
## docs/legislature-model.md.

const SK = preload("res://src/sim/statute_constants.gd")
const Law = preload("res://src/core/law.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const C = preload("res://src/sim/economy_constants.gd")
const CK = preload("res://src/sim/companies_constants.gd")
## T6. The two draws the assembly's own life needs: the hazard hash, and
## SLOT_POSITION for the party-fit pick (the same table elections.gd positions
## every party on -- no parallel ideology vocabulary, legislature.gd's own rule).
const Cycle = preload("res://src/sim/cycle.gd")
const EK = preload("res://src/sim/election_constants.gd")
## The ultra pass-1 finding: a carried assembly bill walks the SAME pipeline
## propose()'s ordinary route walks -- second chamber, then court. Both are
## leaves; neither knows this file exists.
const Chambers = preload("res://src/sim/chambers.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")
## The ultra pass-2 discipline finding: the assembly's own division sheds
## rebels exactly as propose()'s does, and the cost is applied by the mutating
## caller. discipline.gd is a leaf -- it preloads only its constants and
## opinion_constants -- so this preload runs no cycle.
const Discipline = preload("res://src/sim/discipline.gd")
## The birth gate reads COMPUTED_REVENUE_LINES from it (the pass-15 reserved
## names); budget.gd preloads this file back (its projection runs the assembly's
## own tick -- the pass-1 finding) -- the engine tolerates the cycle; the
## ledger header below records the shape.
const Budget = preload("res://src/sim/budget.gd")

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

## The new-tax key charset, [a-z0-9_] with length 2..24. THE PIPE GATE, the
## ultra pass-2 finding: the ledger encodes a tax channel as "tax|<key>" and
## recovers the sub-key with split("|"), so a key containing "|" corrupts the
## record -- a birth keyed "carbon|tax" snapshots "tax|carbon|tax", the repeal
## subtracts under the mis-split "carbon" while the live rate keeps yielding,
## and the act is permanently un-repealable while its repeal reported carried
## (worse: a key like "vat|one" mis-splits onto an AUTHORED lever and moves it
## silently). Closed at the draft gate -- the one check the free-text field
## cannot get past -- rather than at the encoding, which every legal key
## already survives. Same pattern idiom as nation.gd's id regex.
static var _tax_key_pattern := RegEx.create_from_string("^[a-z0-9_]{2,24}$")


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
		# THE PIPE GATE (see _tax_key_pattern above): the refusal names the rule,
		# because a player told only "invalid" would rightly try again with the
		# same characters in another order.
		if _tax_key_pattern.search(tax_key) == null:
			return _refuse("A tax key is 2 to 24 lowercase letters, digits and underscores -- other characters would corrupt the ledger's records.")
		if C.TAX_KEYS.has(tax_key):
			return _refuse("That tax key already exists in the tax code.")
		# THE RESERVED LINE NAMES (the ultra pass-15 finding): "other",
		# "tariffs" and "dividends" are not tax keys -- they are the computed
		# revenue lines Budget.recompute() WRITES OVER the modelled dict after
		# revenue_lines() returns, so a born tax carrying one would yield into
		# a dict slot the next recompute replaces with an unrelated national
		# quantity: the levy prices approval and demand and collects nothing,
		# the silent half-tax the register's bump argument exists to prevent.
		if Budget.COMPUTED_REVENUE_LINES.has(tax_key):
			return _refuse("'%s' is a reserved revenue-line name -- the books overwrite it with a computed line, so a tax born there would collect nothing." % tax_key)
		# One key, one birth, across the key's WHOLE life: the params register
		# is the authorising record, and a second bill proposing the same key
		# would re-price a base and erosion the first birth already put on the
		# books -- two answers to one question. The ultra pass-3 finding was
		# that the gate read only the LANDED register (ns.custom_taxes, written
		# at passage), so two parked drafts could carry one key, both compose,
		# and the second passage fire _register_new_tax's "impossible" error
		# while its rate still landed -- so the parked carriers are gated too:
		# a draft still counting down and a composed bill not yet proposed,
		# whose saved birth params carry the key inside new_tax.
		if ns.custom_taxes.has(tax_key) or _tax_key_carried(ns, tax_key) != "":
			return _refuse("'%s' is already drafted or enacted -- one key, one birth." % tax_key)
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


## The parked half of one-key-one-birth: "" when no draft or composed law on
## the register carries `key`, else the id that carries it. The caller has
## already checked ns.custom_taxes (the landed register); this walks the two
## in-flight carriers -- a draft's own new_tax and a composed law's saved
## birth params, whose to_save_dict holds the key inside new_tax.
static func _tax_key_carried(ns, key: String) -> String:
	for draft_id in ns.draft_bills:
		var entry: Dictionary = ns.draft_bills[draft_id]
		if String(entry.get("new_tax", {}).get("key", "")) == key:
			return String(draft_id)
	for law_id in ns.custom_laws:
		var saved: Dictionary = ns.custom_laws[law_id]
		if String(saved.get("new_tax", {}).get("key", "")) == key:
			return String(law_id)
	return ""


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
## ns.poll_purchases, and a second one-off capital writer outside
## Budget.tick_month() beside the companies.gd bailout -- the same discipline,
## restated here because the next sim author will meet this register before
## that comment:
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
## `loader` carries what the assembly needs: loader.laws is the backbench's
## candidate pool, loader.parties the chamber the divisions are resolved
## against, loader.companies the majors whose chiefs lobby.
static func tick_month(state, loader) -> void:
	for ns in state.nations.values():
		if not ns.has_budget:
			continue
		_tick_drafts(ns)
		_tick_assembly(state, ns, loader)


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


# --- V4.2 T6: the assembly's own life -------------------------------------------

## The in-tray counts down, the bills whose time is up divide, and the
## backbench (and the chiefs) table what is next. The order is the drafts'
## own V2.8 lesson twice over: countdown BEFORE division, so a bill tabled at
## PMB_MONTHS_TO_VOTE divides on exactly the tick it was quoted; division
## BEFORE generation, so a bill tabled this month keeps its full window
## rather than losing a month to the same pass that tabled it.
static func _tick_assembly(state, ns, loader) -> void:
	_resolve_due(state, ns, loader)
	_generate(ns, loader, _abs_month(state))


## The absolute month, the index every Cycle draw in this file keys on -- the
## same absolute-month discipline industry.gd's hazards keep, and what makes
## a replay of the same months produce the same bills.
static func _abs_month(state) -> int:
	return int(state.year) * 12 + int(state.month)


## The in-tray counts down; a bill at 0 divides. The entry is erased at the
## division -- the in-tray is bills IN FLIGHT, and the result's record is
## ns.last_law_result under its assembly marker, not a second copy here.
static func _resolve_due(state, ns, loader) -> void:
	var due: Array = []
	for bill_id in ns.assembly_bills:
		var entry: Dictionary = ns.assembly_bills[bill_id]
		var left := int(entry.get("months_left", 0)) - 1
		if left > 0:
			entry["months_left"] = left
		else:
			due.append(bill_id)
	for bill_id in due:
		_divide(state, ns, loader, String(bill_id))


## THE DIVISION. The assembly proposes and the assembly decides: resolve_vote()
## runs with the entry's endorse bonus through its DEFAULTED support_bonus
## parameter (the plan's constraint -- the signature owns about twenty-five
## call sites -- and its sanctioned reading, since a statute-side wrapper
## would have re-mirrored the loop and the majority match verbatim). A CARRIED
## bill then walks the SAME pipeline propose()'s ordinary route walks, in the
## same order: the second chamber between the division and everything after it
## (Chambers.power_over -> resolve_upper, an absolute refusal killing the bill
## with the authored cooldown, a suspensive one parking it into ns.held_bills
## for the release path to apply through the court), then the court through
## Legislature.review_and_apply_after_division(). The pool filters to AUTHORED
## laws only, so the held-bill release's loader lookup always finds what this
## function parked. Failure writes the authored cooldown exactly as
## propose()'s own failure path does -- a failed division faces neither the
## chamber nor the court, because there is nothing yet for either to review.
## propose()'s _by_id, two lines local: the underscore is that file's own
## boundary, and a cross-file call through it would be a convention this
## project keeps by never crossing.
static func _party_by_id(party_list: Array) -> Dictionary:
	var by_id := {}
	for party in party_list:
		by_id[party.id] = party
	return by_id


static func _divide(state, ns, loader, bill_id: String) -> void:
	var entry: Dictionary = ns.assembly_bills.get(bill_id, {})
	ns.assembly_bills.erase(bill_id)
	if entry.is_empty():
		return
	var law = _law_by_id(loader, String(entry.get("law_id", "")))
	if law == null:
		# Loud, not silent: the pool is authored content and the in-tray is
		# serialised state, so a ghost id means a save crossed a content edit.
		push_error("statute: assembly bill '%s' names law '%s', which the loader does not know" %
			[bill_id, String(entry.get("law_id", ""))])
		return
	var party_list: Array = loader.parties.get(ns.id, [])
	var result: Dictionary = Legislature.resolve_vote(
		ns, party_list, law, false, float(entry.get("endorse_bonus", 0.0)))
	result["assembly_bill"] = true
	result["bill_id"] = bill_id
	# The DIVISION'S OWN MONTH, not the reader's: main.gd's card memory keys
	# on this stamp, so a quiet month that merely finds the result still on
	# the register cannot re-announce a division that happened once.
	result["assembly_division_month"] = _abs_month(state)
	if String(entry.get("backer_firm", "")) != "":
		result["backer_firm"] = String(entry["backer_firm"])
		result["backer_chief"] = String(entry.get("backer_chief", ""))
	# THE REBELLION CHARGE, on both paths -- placed before the passed branch so
	# a held bill and a fall-through bill are priced alike, propose()'s own rule
	# ("whichever way the bill went"). resolve_vote() stays a pure function; the
	# cost is applied by the mutating caller, and this division is one -- the
	# ultra pass-2 finding was that the assembly's route skipped it while the
	# player's route charged, so the identical division cost two different
	# disciplines. The endorsement bonus is what makes rebels ordinary here: it
	# drags a party's line onto a bill its own members do not back, and the
	# strain that split measures is exactly this charge's subject.
	Discipline.penalise_rebellions(ns, result["party_rebels"], _party_by_id(party_list))
	if bool(result.get("passed", false)):
		var power: String = Chambers.power_over(ns, law)
		if power != ChambersK.VERDICT_NONE:
			var upper: Dictionary = Legislature.resolve_upper(ns, party_list, law)
			result["upper_chamber"] = ns.upper_chamber_name
			result["upper_power"] = power
			result["upper_passed"] = upper["passed"]
			result["upper_yes_seats"] = upper["yes_seats"]
			result["upper_no_seats"] = upper["no_seats"]
			result["upper_abstain_seats"] = upper["abstain_seats"]
			result["upper_seats_total"] = upper["seats_total"]
			if not bool(upper["passed"]):
				result["passed"] = false
				if power == ChambersK.VERDICT_ABSOLUTE:
					result["blocked_by_upper"] = true
					if law.cooldown_months > 0:
						ns.law_cooldown_months[law.id] = law.cooldown_months
				else:
					# HELD, not defeated: propose()'s own reading, and the
					# release in Legislature.tick_month() applies the bill
					# through the court when the hold runs out -- no second
					# division, no command from anyone. The origin rides the
					# entry (the ultra pass-2 shape): the release charges the
					# override price only when the GOVERNMENT insisted, and
					# nobody insisted on a private member's bill.
					result["held_by_upper"] = true
					result["held_months"] = ChambersK.UPPER_HOLD_MONTHS
					ns.held_bills[law.id] = {"months": ChambersK.UPPER_HOLD_MONTHS, "origin": "assembly"}
				ns.last_law_result = result
				return
		# No upper chamber, or the chamber carried it: the court, the pipeline's
		# last stage, exactly as propose()'s ordinary route runs it.
		Legislature.review_and_apply_after_division(state, ns, law, loader, result)
		# The member_bill_passed hook's own stamp (nation_state.gd): only a
		# division that came into force -- the court can still strike it, which
		# flips passed -- and last_law_result below is overwritten by the next
		# division of the month, so the hook cannot read it from there.
		if bool(result.get("passed", false)):
			ns.assembly_bill_passed_month = _abs_month(state)
	elif law.cooldown_months > 0:
		ns.law_cooldown_months[law.id] = law.cooldown_months
	ns.last_law_result = result


## Two hazards, one bill a month: the chiefs' lobby draw first (the rarer and
## the more specific ask), the plain backbench draw only in the months the
## lobby did not spend. A fired lobby whose ask cannot be built -- no
## burden-easing law to name -- falls through to a plain backbench bill, per
## the plan; a month with no burdened sector or no major to sign never draws
## at all and belongs to the plain hazard.
static func _generate(ns, loader, month: int) -> void:
	if _lobby(ns, loader, month):
		return
	if Cycle.unit("statute|pmb|%s" % ns.id, month) < SK.PMB_HAZARD_MONTHLY:
		_table_bill(ns, loader, month)


## The chiefs' verb. A sector's regulation burden above the floor is a cost a
## major is actually paying, and buying relief through a backbencher's bill is
## what a chief is for. Returns whether the month was spent -- the plain draw
## runs only when it was not.
static func _lobby(ns, loader, month: int) -> bool:
	var sector := _burdened_sector(ns)
	if sector == "":
		return false
	var firm = _biggest_major(ns, loader, sector)
	if firm == null:
		return false
	if Cycle.unit("statute|lobby|%s" % ns.id, month) >= SK.LOBBY_HAZARD_MONTHLY:
		return false
	var law = _burden_easing_law(ns, loader, sector, month)
	if law == null:
		_table_bill(ns, loader, month)
		return true
	_table_bill(ns, loader, month, String(firm.id), String(firm.chief_id), law)
	return true


## One bill onto the in-tray. `law` is null for a plain backbench bill, which
## picks by fit: the candidate whose position sits nearest the sponsoring
## party's own slot -- the assembly proposing what its members actually
## believe, deterministic like every division. The bill tabled, the endorse
## bonus is born at zero: the president's stand is a choice, not a default.
static func _table_bill(ns, loader, month: int, backer_firm := "", backer_chief := "", law = null) -> void:
	var pool := _candidate_pool(ns, loader)
	if pool.is_empty():
		return
	if law == null:
		var sponsor = _sponsor_party(ns, loader, month)
		if sponsor == null:
			return
		law = _nearest(pool, sponsor)
	# T2's idiom, mirrored: append-only size() over the absolute month. Two
	# bills tabled in one month differ by size(); the month index strictly
	# increases across a run, so a size() reused in a later month still cannot
	# repeat an earlier id -- which is what makes erasing resolved entries
	# safe where draft_bills must never be erased.
	var bill_id := "pmb_%d" % (ns.assembly_bills.size() + month)
	ns.assembly_bills[bill_id] = {
		"law_id": law.id,
		"months_left": SK.PMB_MONTHS_TO_VOTE,
		"backer_firm": backer_firm,
		"backer_chief": backer_chief,
		"endorse_bonus": 0.0,
	}


## The laws the assembly's backbench may table: Legislature.available()'s own
## gates (preconditions met, not a passed once-law, not on cooldown, not
## held, the system's own rules), which is also what keeps the pool from
## disagreeing with the player's legality scan -- both read the same
## available(). Minus the two classes an assembly bill must never carry: a
## constitutional amendment (the assembly alone does not ratify those) and an
## institutional setting (T1's repeal gate -- an assembly bill must be
## repealable, and a setting has no inverse delta). Authored laws only: the
## backbench does not re-table the player's own compositions.
static func _candidate_pool(ns, loader) -> Array:
	var out: Array = []
	for law in Legislature.available(ns, loader.laws):
		if law.constitutional or law.effects.has("institutional"):
			continue
		out.append(law)
	return out


## The sponsor, drawn over the seats-weighted party list: a backbench bill's
## author reads off the chamber the player can see, not off an even pool the
## chamber does not resemble. Cumulative walk in authored order -- the
## deterministic pick industry.gd's bidder draw makes, over weights.
static func _sponsor_party(ns, loader, month: int):
	var party_list: Array = loader.parties.get(ns.id, [])
	var total := 0
	for party in party_list:
		total += int(ns.seats_by_party.get(party.id, 0))
	if total <= 0:
		return null
	var pick: float = Cycle.unit("statute|pmb_sponsor|%s" % ns.id, month) * float(total)
	var walked := 0
	for party in party_list:
		walked += int(ns.seats_by_party.get(party.id, 0))
		if float(walked) > pick:
			return party
	return party_list[party_list.size() - 1]


## Ideological distance on the ONE two-axis space every support line reads,
## the same expression spatial_support() runs -- squared-distance order is
## what _nearest() needs, the sigma it lacks is not in the pick's way.
static func _distance(law, sponsor) -> float:
	var pos: Dictionary = EK.SLOT_POSITION.get(sponsor.ideology_slot, {"economic": 0.0, "social": 0.0})
	var d_econ: float = float(pos["economic"]) - float(law.position.get("economic", 0.0))
	var d_social: float = float(pos["social"]) - float(law.position.get("social", 0.0))
	return d_econ * d_econ + d_social * d_social


## The party-fit pick, ties to the pool's authored order (strict <, so the
## first law at the winning distance wins and the pick never depends on dict
## iteration order).
static func _nearest(pool: Array, sponsor):
	var best = pool[0]
	var best_d := _distance(best, sponsor)
	for law in pool:
		var d := _distance(law, sponsor)
		if d < best_d:
			best = law
			best_d = d
	return best


## The sector a chief would buy relief for: the FIRST burden above the floor
## in sorted order -- sorted, because dict order is insertion order and the
## ask would otherwise depend on the order laws happened to pass in.
static func _burdened_sector(ns) -> String:
	var sectors: Array = ns.regulation_burden.keys()
	sectors.sort()
	for sector in sectors:
		if float(ns.regulation_burden[sector]) > SK.LOBBY_BURDEN_FLOOR:
			return String(sector)
	return ""


## The chief who signs the ask: the sector's BIGGEST major, ties to authored
## order (strict >) -- the firm with the most payroll at stake lobbies first,
## and the pick never depends on the loader's file order. THE LIVENESS GATE,
## the ultra pass-2 finding: the pick reads the LIVE share off the firm
## register (industry.gd's `entry.get("share", company.share)` idiom) and
## skips the dead -- a failed firm has no payroll at stake and its chief signs
## for nothing. An untouched firm has no register entry and reads its authored
## share, which is what alive means for a sparse register.
static func _biggest_major(ns, loader, sector: String):
	var best = null
	var best_share := 0.0
	for company in loader.companies.get(ns.id, []):
		if String(company.tier) != "major" or String(company.sector) != sector:
			continue
		if String(company.chief_id) == "":
			continue
		var entry: Dictionary = ns.companies.get(company.id, {})
		if bool(entry.get("failed", false)):
			continue
		var share := float(entry.get("share", company.share))
		if share <= 0.0:
			continue
		if best == null or share > best_share:
			best = company
			best_share = share
	return best


## The burden-easing law the lobby names: the nearest-position negative-burden
## law for the sector, from the SAME candidate pool the backbench draws (a
## lobby cannot name a bill the assembly could not table), fitted to the same
## seats-weighted sponsor draw -- the chief lobbies a member, and the member
## tables what fits. Shipped content carries several easing laws per sector
## (four for industry, three for services), so the pick is a real choice;
## _nearest() breaks ties by authored order, which keeps it deterministic.
static func _burden_easing_law(ns, loader, sector: String, month: int):
	var easing: Array = []
	for law in _candidate_pool(ns, loader):
		if not law.effects.has(COMPANY_CHANNEL):
			continue
		var company: Dictionary = law.effects[COMPANY_CHANNEL]
		if String(company.get("sector", "")) != sector or float(company.get("burden", 0.0)) >= 0.0:
			continue
		easing.append(law)
	if easing.is_empty():
		return null
	var sponsor = _sponsor_party(ns, loader, month)
	if sponsor == null:
		return easing[0]
	return _nearest(easing, sponsor)


## The player's public stand on a private member's bill. The endorse bonus
## moves onto the in-tray entry, where the bill's OWN division reads it a
## month later; the endorsement's political price lands THROUGH THE ONE
## APPLIER immediately, because the endorsement is the news and the vote is
## not. One endorsement per bill -- a second stand is refused, the price is
## per stand, and a re-priced stand would be two charges for one act.
static func endorse(state, ns, loader, bill_id: String) -> Dictionary:
	var entry: Dictionary = ns.assembly_bills.get(bill_id, {})
	if entry.is_empty():
		return {"ok": false, "refusal": "There is no such bill before the assembly.", "bill_id": ""}
	if float(entry.get("endorse_bonus", 0.0)) != 0.0:
		return {"ok": false, "refusal": "The bill carries the president's endorsement already.", "bill_id": String(bill_id)}
	# Exact-zero reads on purpose: the register writes the bonus itself, so
	# 0.0 is exactly "never endorsed" and no tolerance question exists.
	entry["endorse_bonus"] = SK.PMB_ENDORSE_SUPPORT
	Legislature.apply_effects(state, ns, {"bloc_offset": Dictionary(SK.PMB_ENDORSE_PRICE).duplicate(true)}, loader)
	return {"ok": true, "refusal": "", "bill_id": String(bill_id), "endorse_bonus": SK.PMB_ENDORSE_SUPPORT}


## The live bills the player has not yet taken a stand on -- pending.gd's
## legislature mark reads this, by that file's own test: an unendorsed bill
## awaits THE PLAYER, an endorsed one awaits only the calendar.
static func awaiting_endorsement(ns) -> Array:
	var out: Array = []
	for bill_id in ns.assembly_bills:
		if float(ns.assembly_bills[bill_id].get("endorse_bonus", 0.0)) == 0.0:
			out.append(ns.assembly_bills[bill_id])
	return out


## The authored law behind an in-tray id -- the division's lookup, null when
## the loader does not know the id (a save crossed a content edit).
static func _law_by_id(loader, law_id: String):
	if loader == null or law_id == "":
		return null
	for law in loader.laws:
		if law.id == law_id:
			return law
	return null
