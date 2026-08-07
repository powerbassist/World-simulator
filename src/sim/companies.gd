extends RefCounted

## The private-companies model: named firms partitioning a sector, a standing
## subsidy as the player's first verb, and the two channels through which a firm
## reaches the national economy. Built at V1.4a, the first session of the V1.4
## block. The model and every constant's rationale is docs/companies-model.md;
## src/sim/companies_constants.gd is the values.
##
## V1.4b ADDS A SECOND WRITER AND NO SECOND CHANNEL. A regulation is a law, so it
## reaches effects.company through Legislature.apply() and an assembly division
## rather than through execute() below; what it writes is ns.regulation_burden, a
## per-SECTOR signed register this file only ever reads. Both prices land in the two
## channels V1.4a already built. Nothing here writes `share` but a subsidy: share
## movement is the subsidy's persistent channel and a second writer of it would be
## two answers to the question of who is winning the sector.
##
## TAKES A LOADER, where trade.gd, coercion.gd and defence.gd take none. That is
## not a slip: a firm's authored share and headcount ARE its baseline, so keeping
## a copy on NationState would be the same fact in two places -- the duplication
## data/people/ was built to remove, and the one tools/coercion_probe.gd cut when
## it deleted `tariff_rate_pct`. The live register carries what MOVED and nothing
## that did not. Budget.project() already passes a loader, so the projection runs
## the real model forward on a copy and gets the real answer.
##
## Preloads its constants and nothing else from src/sim/. A leaf.
##
## FIRMS ARE LOAD-BEARING ON GDP, and the shape is what makes that safe.
## Economy._apply_growth_to_sectors() reconciles the three sectors against the
## month's GDP target exactly, and a firm layer of free-floating absolutes beside
## it would be a second claim on the same quantity. So a firm holds a SHARE of its
## sector and its output is read through that share -- the partition is exact by
## construction and there is no second reconciliation anywhere. What reaches the
## economy is two DEVIATION terms, both of which read exactly 0.0 until a verb
## moves something, which is trade.gd's baseline idiom and V1.3f's inert-act
## property in a new place.

const K = preload("res://src/sim/companies_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")


## Seeds the live register from content: every firm starts at its authored share
## with no subsidy. Called from GameState._build_nation(), Defence.init_nation()'s
## slot.
##
## A nation with no data/companies/<ID>.json gets an EMPTY register, and that is a
## supported state rather than a hole. Its sectors are simply unpartitioned, which
## is exactly what every nation looked like before this session -- so the seven
## nations that are not yet playable run the model they always ran, and V1.4a's
## bit-identity claim covers them for free.
## Takes the nation's own company list rather than the loader, the way
## GameState._build_nation() already takes `party_list`: at build time the caller
## has the list in hand and the nation does not exist yet, so asking a loader to
## look it up by an id that is being assigned on the line above would be the wider
## dependency for the narrower job.
static func init_nation(ns, company_list: Array) -> void:
	ns.companies = {}
	ns.subsidy_bill_pct_gdp = 0.0
	ns.firm_impulse_pct = 0.0
	ns.firm_jobs_offset_pct = 0.0
	for company in company_list:
		ns.companies[company.id] = {"share": company.share, "subsidy": 0.0}


## Runs after Diplomacy and Defence in src/ui/main.gd's order, and Budget.project()
## runs it in the same slot. The two cached prices therefore lag the economy by a
## month, exactly as Defence's two do and for the reason main.gd's own comment
## gives: they lag together rather than one of them lagging alone.
static func tick_month(state, loader) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		var ns = state.nations[id]
		_tick_shares(ns, loader)
		_recompute_prices(ns, loader)


# --- Content -------------------------------------------------------------------

static func firms_of(loader, nation_id: String) -> Array:
	if loader == null:
		return []
	return loader.companies.get(nation_id, [])


## The firms of one nation in one sector, in authored order. The draw below is
## pro-rata by share, so order changes nothing -- but the panel reads this too,
## and there authored order is the order the player sees.
static func firms_in_sector(loader, nation_id: String, sector: String) -> Array:
	var out: Array = []
	for company in firms_of(loader, nation_id):
		if company.sector == sector:
			out.append(company)
	return out


# --- Reading one firm ----------------------------------------------------------

static func share_of(ns, company_id: String) -> float:
	var entry = ns.companies.get(company_id)
	return float(entry.get("share", 0.0)) if entry != null else 0.0


static func subsidy_of(ns, company_id: String) -> float:
	var entry = ns.companies.get(company_id)
	return float(entry.get("subsidy", 0.0)) if entry != null else 0.0


## V1.4b. The accumulated regulatory burden on one sector, signed. Written only by
## Legislature.apply(); this module reads it and never writes it, which is the same
## one-way arrangement `law_structural_offset_pct` already has with economy.gd.
static func regulation_burden_of(ns, sector: String) -> float:
	return float(ns.regulation_burden.get(sector, 0.0))


## Revenue, EUR bn/yr. DERIVED and never stored: the sector total is the economy's
## number and the share is the firm's, so a stored revenue would be a third record
## of a product of two things that already exist.
static func output_eur_bn(ns, company) -> float:
	return share_of(ns, company.id) * float(ns.sector_output.get(company.sector, 0.0))


## Jobs, live.
##
## SCALES WITH SHARE AND NOT WITH THE SECTOR'S OUTPUT, and that is the load-bearing
## modelling call in this file. Read off the level, a firm would hire every month
## the economy grew -- which would make the jobs deviation below non-zero in every
## run that has ever been played, destroy V1.4a's bit-identity claim, and, worse,
## be a second answer to a question the macro model already answers. Aggregate
## employment is Okun's law in Economy._update_unemployment(). V1.4b's burden term
## does not weaken this: it reads no sector_output either.
##
## V1.4b WIDENS THIS CHANNEL'S CHARTER, and that is written down rather than
## slipped in. V1.4a's claim was that a firm layer adds REALLOCATION and nothing
## else -- two firms of equal share employ different numbers of people, so moving
## share between them creates or destroys jobs on net. A sector burden is a LEVEL
## effect on top of that: it sheds staff without moving a single share. The channel
## now says two things, and the second one is why V1.4b is not
## docs/tiers/v1.md section 6's sector lever wearing a firm's name -- jobs-per-share
## is firm content, and no lever pointed at a sector can express it.
static func headcount(ns, company) -> float:
	if company.share <= 0.0:
		return 0.0
	var reallocated: float = company.headcount * share_of(ns, company.id) / company.share
	# Signed, so a deregulation law lets the same firms carry more staff. Floored at
	# zero rather than trusted to the burden clamp: a later session raising
	# REGULATION_JOBS_BETA past 1/REGULATION_BURDEN_MAX would otherwise produce a
	# negative headcount and a positive employment effect from a rule that closed
	# the sector.
	var compliance: float = maxf(
		1.0 - K.REGULATION_JOBS_BETA * regulation_burden_of(ns, company.sector), 0.0
	)
	return reallocated * compliance


# --- The share partition -------------------------------------------------------

## A subsidised firm takes share from its NAMED RIVALS in the same sector, pro-rata
## by their current share, and never from the unnamed residual. That is what makes
## the sum of a sector's named shares invariant under every lever rather than
## merely renormalised afterwards -- and it is why a later session naming a seventh
## firm can take its share out of the residual and move no existing number.
##
## Every draw is computed against the shares as they stood at the start of the
## month and applied afterwards, so the result does not depend on the order firms
## are walked in. Same discipline as Economy.tick_month()'s pre-pass over the trade
## weight table, and it exists here for the same reason: two subsidised firms in
## one sector would otherwise see different rivals depending on who moved first.
static func _tick_shares(ns, loader) -> void:
	for sector in EK.SECTOR_TREND.keys():
		var firms := firms_in_sector(loader, ns.id, sector)
		if firms.size() < 2:
			# Zero firms: the sector is unpartitioned, which is every sector of every
			# nation with no companies file. One firm cannot come out of a validated
			# file at all -- DataLoader._validate_companies() refuses it, because a
			# firm with no rival is a sector lever wearing a company's name.
			continue

		var before := {}
		for company in firms:
			before[company.id] = share_of(ns, company.id)

		var deltas := {}
		for company in firms:
			deltas[company.id] = 0.0

		for company in firms:
			var intensity := subsidy_of(ns, company.id)
			if intensity <= 0.0:
				continue

			# What the rivals can actually give, each down to half of its own AUTHORED
			# share and no further. Capping the WANT by the supply rather than
			# clamping the rivals afterwards is what keeps the sector's named sum
			# exact -- what one firm gains, the others lose, to the last bit.
			#
			# Relative to the rival's authored position rather than to a flat floor,
			# which is the correction tools/companies_probe.gd table (b) forced: under
			# a flat floor three different values of SHARE_SHIFT_PER_MONTH produced
			# the identical five-year outcome, because the floor and not the rate was
			# setting where the share ended up.
			var available := 0.0
			for rival in firms:
				if rival.id == company.id:
					continue
				available += maxf(
					float(before[rival.id]) - K.RIVAL_FLOOR_FRACTION * rival.share, 0.0
				)
			if available <= 0.0:
				continue

			var gain: float = minf(
				K.SHARE_SHIFT_PER_MONTH * intensity,
				minf(available, maxf(K.SHARE_MAX - float(before[company.id]), 0.0))
			)
			if gain <= 0.0:
				continue

			deltas[company.id] = float(deltas[company.id]) + gain
			for rival in firms:
				if rival.id == company.id:
					continue
				var supply: float = maxf(
					float(before[rival.id]) - K.RIVAL_FLOOR_FRACTION * rival.share, 0.0
				)
				deltas[rival.id] = float(deltas[rival.id]) - gain * supply / available

		for company in firms:
			var entry: Dictionary = ns.companies[company.id]
			entry["share"] = float(before[company.id]) + float(deltas[company.id])


# --- The two channels into the economy ------------------------------------------

## Points of GDP per year. Read by Budget.recompute() as a computed spending line,
## NOT as a sixth entry in economy_constants.SPENDING_KEYS -- that list is keyed
## 1:1 to cabinet portfolios, so a sixth line is a sixth minister, and
## docs/tiers/v1.md section 6 rules it out. V1.3c's tariff revenue and V1.3g's
## deployment bill both took this route first.
static func subsidy_bill_pct_gdp(ns) -> float:
	var bill := 0.0
	for company_id in ns.companies.keys():
		bill += K.SUBSIDY_COST_PCT_GDP * subsidy_of(ns, String(company_id))
	return minf(bill, K.SUBSIDY_BILL_MAX_PCT_GDP)


## The fifth additive term in the growth equation, %/yr. Scaled by the firm's own
## weight in the economy, which is what makes WHICH FIRM a decision rather than a
## label: subsidising a national champion moves the country, subsidising a
## mid-sized rival mostly moves the rival.
##
## V1.4b's burden runs through the SAME TERM with the opposite sign, rather than
## through a second impulse beside it. One quantity read at two existing sites is
## docs/coercion-model.md's "one verb, two prices"; a second growth impulse would
## be a second machine wearing that phrase, with its own field, clamp and cached
## price to keep in step with this one. A subsidy and a regulation on the same
## sector therefore net off, which is the honest answer -- the player paid for one
## and the assembly passed the other.
##
## THE BURDEN READS ONLY THE NAMED FIRMS, and that is structural rather than a
## rounding choice. A sector that is a quarter named is a quarter as regulable,
## because the unnamed residual is not in the register and this model does not
## reach it. That bound is what separates the term from a lever pointed at
## sector_output, which is docs/tiers/v1.md section 6's and not this session's.
##
## Exactly 0.0 for every nation in every month with no subsidy standing and no
## burden on any sector.
static func firm_impulse_pct(ns, loader) -> float:
	if ns.gdp_eur_bn <= 0.0:
		return 0.0
	var subsidised := 0.0
	var burdened := 0.0
	for company in firms_of(loader, ns.id):
		var intensity := subsidy_of(ns, company.id)
		var burden := regulation_burden_of(ns, company.sector)
		if intensity == 0.0 and burden == 0.0:
			continue
		# Read through the LIVE share, so a subsidy that grew a firm also raises what
		# regulating its sector costs. That interaction is the point of running both
		# verbs against one register rather than two.
		var gdp_share: float = output_eur_bn(ns, company) / ns.gdp_eur_bn
		subsidised += intensity * gdp_share / K.GDP_SHARE_REFERENCE
		burdened += burden * gdp_share / K.GDP_SHARE_REFERENCE
	return clampf(
		K.SUBSIDY_GROWTH_BETA * subsidised - K.REGULATION_GROWTH_BETA * burdened,
		-K.FIRM_IMPULSE_MAX_PCT, K.FIRM_IMPULSE_MAX_PCT
	)


## Points ADDED to structural unemployment by the firm layer -- negative when the
## register has net hired. Read by Economy._update_unemployment() beside
## `law_structural_offset_pct`, whose shape this is.
##
## Exactly 0.0 while every firm sits at its authored share AND no sector carries a
## burden -- which is every month of every run in which no subsidy has ever been
## paid and no `business` law has ever passed. V1.4b widened that condition; see
## headcount() for why the widening is the session's whole case.
static func firm_jobs_offset_pct(ns, loader) -> float:
	var labour_force: float = ns.population * K.LABOUR_FORCE_SHARE
	if labour_force <= 0.0:
		return 0.0

	var net_jobs := 0.0
	for company in firms_of(loader, ns.id):
		net_jobs += headcount(ns, company) - company.headcount
	if net_jobs == 0.0:
		return 0.0

	return clampf(
		-100.0 * net_jobs / labour_force, -K.FIRM_JOBS_MAX_PCT, K.FIRM_JOBS_MAX_PCT
	)


## All three cached onto NationState once a month and read from there, for the
## reason Defence._recompute_prices() gives: budget.gd and economy.gd calling this
## module directly is an edge each, and both would have to grow a loader argument
## that economy.gd's twenty-eight call sites do not have.
##
## NOT gated on has_budget, where Defence's prices are. The gate there is about a
## nation that cannot pay a bill; here the register is empty for every nation that
## cannot pay one, so the guard would be a second expression of a condition the
## content already enforces -- and it would hide a bug rather than prevent one if a
## later session lets the nine hold firms.
static func _recompute_prices(ns, loader) -> void:
	ns.subsidy_bill_pct_gdp = subsidy_bill_pct_gdp(ns)
	ns.firm_impulse_pct = firm_impulse_pct(ns, loader)
	ns.firm_jobs_offset_pct = firm_jobs_offset_pct(ns, loader)


# --- The verb ------------------------------------------------------------------

## Which actions may be used against this firm right now. Diplomacy.available()'s
## shape, minus the cooldown: a subsidy is a STANDING STATE rather than an event,
## so `subsidy_active` gates it directly and a cooldown register would be a second
## gate on the same fact.
static func available(state, ns, all_actions: Array, company_id: String) -> Array:
	var out: Array = []
	if not ns.companies.has(company_id):
		return out
	for action in all_actions:
		if action.id == "":
			continue
		if _preconditions_met(state, ns, action, company_id):
			out.append(action)
	return out


static func _preconditions_met(state, ns, action, company_id: String) -> bool:
	for cond in action.preconditions:
		var actual: float = _read_field(state, ns, cond["field"], company_id)
		var value: float = cond["value"]
		var ok: bool
		match cond["op"]:
			"<": ok = actual < value
			"<=": ok = actual <= value
			">": ok = actual > value
			">=": ok = actual >= value
			"==": ok = is_equal_approx(actual, value)
			_: ok = false
		if not ok:
			return false
	return true


## `subsidy_active` is about the firm the action is pointed at; everything else is
## the acting nation's own state. Diplomacy._read_field()'s split, and it is here
## for the same reason: a precondition list mixes both freely and the content
## should not have to know which kind a field is.
static func _read_field(state, ns, field: String, company_id: String) -> float:
	match field:
		"subsidy_active": return 1.0 if subsidy_of(ns, company_id) > 0.0 else 0.0
		"subsidy_count": return float(subsidised_count(ns))
		"deficit_pct_gdp": return ns.deficit_pct_gdp
		"debt_to_gdp_pct": return ns.debt_to_gdp_pct()
		"unemployment_pct": return ns.unemployment_pct
		"overall_approval_pct": return ns.overall_approval_pct
		_:
			push_error("companies: unknown precondition field '%s'" % field)
			return 0.0


static func subsidised_count(ns) -> int:
	var n := 0
	for company_id in ns.companies.keys():
		if subsidy_of(ns, String(company_id)) > 0.0:
			n += 1
	return n


## The player command: set or clear the standing subsidy, pay the domestic price,
## and record the result for the panel to read. Diplomacy.execute()'s shape and
## Legislature.propose()'s contract -- returns the result rather than mutating a
## panel.
##
## Refuses rather than half-applies when the action is not currently available, so
## a UI offering a stale button cannot produce the effect the precondition exists
## to prevent. There is no counterparty gate: a firm has no interest model, and
## whether one should is V1.4c's question rather than a stopgap this session is
## declaring -- nothing here is standing in for a decision a later session makes.
static func execute(state, ns, all_actions: Array, action, company_id: String) -> Dictionary:
	if not available(state, ns, all_actions, company_id).has(action):
		var refused := {
			"action_id": action.id,
			"company_id": company_id,
			"applied": false,
			"refused": true,
		}
		ns.last_company_result = refused
		return refused

	var terms: Dictionary = action.effects.get("company", {})
	var entry: Dictionary = ns.companies[company_id]
	var before := float(entry.get("subsidy", 0.0))

	match String(terms.get("op", "")):
		"subsidise": entry["subsidy"] = float(terms.get("intensity", 0.0))
		"withdraw": entry["subsidy"] = 0.0

	for bloc_id in action.effects.get("bloc_offset", {}).keys():
		ns.bloc_offset[bloc_id] = (
			float(ns.bloc_offset.get(bloc_id, 0.0))
			+ float(action.effects["bloc_offset"][bloc_id])
		)

	var result := {
		"action_id": action.id,
		"action_name": action.action_name,
		"company_id": company_id,
		"applied": true,
		"refused": false,
		"subsidy_before": before,
		"subsidy_after": float(entry["subsidy"]),
	}
	ns.last_company_result = result
	return result
