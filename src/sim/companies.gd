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
## channels V1.4a already built. `share`'s writers are a ledger, not an accident:
## through V1.4b/c it was execute()'s subsidy arm alone -- a second writer would be
## two answers to the question of who is winning the sector -- and V4.7b widened
## the ledger in kind rather than in breach: rescue restores the authored share,
## break_up redistributes to rivals, and the autonomy machine (industry.gd, whose
## own header keeps its writers) drifts it monthly. A writer not named here or
## there is a defect.
##
## V1.4c ADDS A THIRD WRITER AND A THIRD CHANNEL, and the writers stay one apiece:
##
##     share             <- execute() (subsidy, rescue, break_up) + industry.gd  per firm
##     subsidy           <- execute()'s ops + industry.gd's failure commit (the
##                         support stops with the production it supported)  per firm
##     state_share       <- execute(), ownership ops      per firm
##     regulation_burden <- Legislature.apply()           per SECTOR
##
## The third channel is a computed REVENUE line, where V1.4a's was a computed
## spending line -- the second on this side of the budget after V1.3c's tariffs, and
## the fifth computed line overall. A dividend is a yield on OUTPUT and not on
## profit, because there is no margin, profit or productivity quantity anywhere in
## src/sim/ and half-inventing one is the trap docs/companies-model.md section 13
## refused in advance.
##
## The purchase and the windfall are NOT a fourth channel. They write ns.debt_eur_bn
## -- a capital transaction is a balance-sheet swap and not income, every existing
## budget line is a standing rate, and a one-off on the revenue side would close a
## loop through `deficit_pct_gdp`, which is a company action's own precondition
## field. Writing the debt stock instead buys three built machines for free: the
## interest is priced by Budget.recompute(), the level is read by the bloc's own
## `debt_to_gdp_pct` rule, and it has been serialised since the MVP.
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
const Demography = preload("res://src/sim/demography.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Relations = preload("res://src/core/relations.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const Cycle = preload("res://src/sim/cycle.gd")


## Seeds the live register from content: every MAJOR starts at its authored share
## with no subsidy. Called from GameState._build_nation(), Defence.init_nation()'s
## slot.
##
## V4.7a: body-tier firms are NOT seeded -- the register carries what MOVED and
## nothing that did not, and nothing writes a body entry at all: the body is
## inert by design (industry.gd's header, pinned as BODY SILENCE), and the
## reads (share_of_company, output_eur_bn, headcount) fall back to the authored
## content for an absent entry, which is what makes the sparse shape safe and
## keeps a ~2,500-firm register out of every save.
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
	ns.dividend_revenue_pct_gdp = 0.0
	for company in company_list:
		if not is_major(company):
			continue
		ns.companies[company.id] = {
			"share": company.share, "subsidy": 0.0, "state_share": 0.0
		}


## Runs after Diplomacy and Defence in src/ui/main.gd's order, and Budget.project()
## runs it in the same slot. The two cached prices therefore lag the economy by a
## month, exactly as Defence's two do and for the reason main.gd's own comment
## gives: they lag together rather than one of them lagging alone.
static func tick_month(state, loader) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		var ns = state.nations[id]
		_seed_missing_majors(ns, loader)
		_tick_shares(ns, loader)
		_recompute_prices(ns, loader)


## V4.7a, the PR-46 ultra review's headline finding: the load path restores the
## register from the payload ALONE (from_dict never sees the loader), and a save
## written before this block shipped carries "companies": {} for the 25 nations
## that had no companies file -- while this build's content gives each ~12
## majors. Without this seed, the first monthly tick after loading such a save
## raises a missing-key error per unseeded nation, every month, with no repair
## path (the verbs' register-membership gate refuses too). The fix is the V4.6
## commodity register's own shape: a LAZY seed at the tick, majors only, at the
## authored share -- which is the truth about those firms in any save that
## predates them (no verb ever touched them, so there is no verb state to lose).
## Body firms stay unseeded: their reads fall back to authored content and
## nothing moves one -- the body is inert by design, and a later block's body
## market is where entries would begin. Idempotent by construction -- a second
## run finds every major present and writes nothing.
static func _seed_missing_majors(ns, loader) -> void:
	for company in majors_of(loader, ns.id):
		if not ns.companies.has(company.id):
			ns.companies[company.id] = {
				"share": company.share, "subsidy": 0.0, "state_share": 0.0
			}


# --- Content -------------------------------------------------------------------

static func firms_of(loader, nation_id: String) -> Array:
	if loader == null:
		return []
	return loader.companies.get(nation_id, [])


static func majors_of(loader, nation_id: String) -> Array:
	var out: Array = []
	for company in firms_of(loader, nation_id):
		if is_major(company): out.append(company)
	return out


static func body_of(loader, nation_id: String) -> Array:
	var out: Array = []
	for company in firms_of(loader, nation_id):
		if not is_major(company): out.append(company)
	return out


static func is_major(company) -> bool:
	# Company.tier defaults "major" (from_dict sets it only when the field is
	# present), so the legacy files read as majors through the typed default.
	return String(company.tier) == "major"


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


static func share_of_company(ns, company) -> float:
	var entry = ns.companies.get(company.id)
	return float(entry.get("share", company.share)) if entry != null else float(company.share)


static func subsidy_of(ns, company_id: String) -> float:
	var entry = ns.companies.get(company_id)
	return float(entry.get("subsidy", 0.0)) if entry != null else 0.0


## V1.4c. How much of the firm the state holds, 0.0 to 1.0. Written only by the
## ownership ops in execute(); a `business` law cannot reach it, because
## src/core/law.gd's _extract_company() names a sector and a burden and refuses any
## third key -- the same refusal that keeps every register here to the writers its
## header ledger names.
static func state_share_of(ns, company_id: String) -> float:
	var entry = ns.companies.get(company_id)
	return float(entry.get("state_share", 0.0)) if entry != null else 0.0


## V1.4b. The accumulated regulatory burden on one sector, signed. Written only by
## Legislature.apply(); this module reads it and never writes it, which is the same
## one-way arrangement `law_structural_offset_pct` already has with economy.gd.
static func regulation_burden_of(ns, sector: String) -> float:
	return float(ns.regulation_burden.get(sector, 0.0))


## Revenue, EUR bn/yr. DERIVED and never stored: the sector total is the economy's
## number and the share is the firm's, so a stored revenue would be a third record
## of a product of two things that already exist.
static func output_eur_bn(ns, company) -> float:
	return share_of_company(ns, company) * float(ns.sector_output.get(company.sector, 0.0))


## V1.4c. What the whole firm is worth, EUR bn. DERIVED for revenue's own reason:
## an authored valuation on a firm would be a third record of a product of two
## things that already exist, and the one a content edit would silently disagree
## with.
##
## Read through the LIVE share, so a subsidy that grew a firm also raises what
## nationalising it costs -- firm_impulse_pct()'s interaction, in a third place.
static func value_eur_bn(ns, company) -> float:
	return output_eur_bn(ns, company) * K.PRICE_TO_OUTPUT


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
##
## V1.4c PUTS THE ONE THING OWNERSHIP CONTROLS HERE, and it is a factor on the
## existing compliance term rather than a machine of its own. The ROADMAP row
## promised "a permanent loss of control" and a grep found that ownership controlled
## nothing: a subsidy already works on any firm whoever owns it, and a regulation
## targets the sector. So what a state holding buys is that the firm does not shed
## staff to meet a rule -- the state absorbs the compliance cost instead of the
## payroll doing it. V1.4b's own "one quantity, two prices" discipline, one quantity
## later.
##
## THE SHIELD IS SIGNED, which is what stops it being free: a state-owned firm in a
## DEREGULATED sector also gives up the hiring the deregulation would have brought.
## Both directions are asserted in tests/test_companies.gd, because a shield that
## only ever helps is the strictly-dominated shape three probes have already caught.
static func headcount(ns, company) -> float:
	if company.share <= 0.0:
		return 0.0
	# V4.7b: a failed firm employs nobody. The flag's writers are the ledger
	# industry.gd's header keeps -- the machine commits failures, execute()
	# commits rescues and break-ups -- and this read is the payroll's own
	# arithmetic on the register both systems already meet in.
	if bool(ns.companies.get(company.id, {}).get("failed", false)):
		return 0.0
	# The RATIO is computed first, deliberately: (h * s) / s is not exactly h
	# for every float pair -- the A3 roster's generated headcounts found the
	# unlucky ones, and the residue showed up as a 1e-18 drift in
	# firm_jobs_offset_pct on nations whose only sin was unlucky digits. s / s
	# is exactly 1.0 in IEEE for every finite nonzero s, so this form holds the
	# file's own invariant -- the deviation channels read EXACTLY 0.0 while
	# every firm sits at its authored share -- by construction rather than by
	# bit luck.
	var reallocated: float = company.headcount * (share_of_company(ns, company) / company.share)
	# Signed, so a deregulation law lets the same firms carry more staff. Floored at
	# zero rather than trusted to the burden clamp: a later session raising
	# REGULATION_JOBS_BETA past 1/REGULATION_BURDEN_MAX would otherwise produce a
	# negative headcount and a positive employment effect from a rule that closed
	# the sector.
	var exposure: float = 1.0 - state_share_of(ns, company.id)
	var compliance: float = maxf(
		1.0 - K.REGULATION_JOBS_BETA * regulation_burden_of(ns, company.sector) * exposure, 0.0
	)
	return reallocated * compliance


## Jobs domiciled in one city -- V2.2a, and the only thing making Company.city
## load-bearing before V2.2b draws it. U6c's rule that a coordinate nothing reads
## carries no information, applied to a domicile.
##
## It lives here rather than on src/core/region.gd because it reads headcount(), and a
## core value type preloading a sim system would invert data -> sim -> ui. The city
## register knows nothing about firms; the firm register names its city; and this
## function is the one place the two meet.
##
## Reads LIVE headcount, so a subsidy that has moved a firm's share has already moved
## its city's payroll -- which is what makes this a query about the running game rather
## than a second reading of the content.
static func headcount_in_city(ns, loader, city_id: String) -> float:
	var total := 0.0
	for company in firms_of(loader, ns.id):
		# The LIVE city -- a V4.7b relocation writes the override and the
		# payroll moves with it. The authored city stays content in data/.
		var entry: Dictionary = ns.companies.get(company.id, {})
		var live_city: String = String(entry.get("city", company.city))
		if live_city == city_id:
			total += headcount(ns, company)
	return total

# --- The share partition -------------------------------------------------------

## A subsidised firm takes share from its NAMED RIVALS in the same sector, pro-rata
## by their current share, and never from the unnamed residual. That is what keeps
## this pool's transfers renormalisation-free -- and why a later session naming a
## seventh firm can take its share out of the residual and move no existing number.
## The pool is the INVARIANCE'S SCOPE, not the whole file: since V4.7b the failure
## commit moves a named share to the residual and the rescue RE-AUTHORS the firm's
## CONTENT share (the drifted live share does not survive the death), moving the
## named sum by (authored - live) per rescue; break_up's split conserves the sum
## by its own pro-rata form. The header ledger names the writers.
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
			continue

		# MAJORS ONLY, snapshot and deltas alike: the pool is the verb plane
		# (see the block comment above), and walking the ~80 body firms per
		# sector to compute deltas nothing can write is the A3 review's Minor
		# 7. SECTOR-SCOPED, deliberately not majors_of(ns.id): this loop runs
		# once per sector, and a nation-wide list would subsidise the same
		# firm once per sector and let one sector's subsidy drain another's
		# majors -- the bug the conservation test caught within a tick of the
		# refactor.
		var majors: Array = []
		for company in firms:
			# A failed firm is OUT of the pool: its share is 0.0 and stays 0.0.
			# With a retained subsidy it would otherwise regrow share from its
			# rivals' spare every month -- output through the live share,
			# headcount 0 through the failed flag, one register read two ways
			# (the pass-2 ultra's second Important). A rescued firm re-enters
			# here: the flag clears and the next tick prices it alive again.
			# The flag is read as the raw register fact this file's other reads
			# use -- is_failed() is industry.gd's read, and a sim module
			# preloading its sibling machine for one predicate inverts the
			# two-writers arrangement.
			if is_major(company) and not bool(ns.companies.get(company.id, {}).get("failed", false)):
				majors.append(company)
		var before := {}
		for company in majors:
			before[company.id] = share_of_company(ns, company)

		var deltas := {}
		for company in majors:
			deltas[company.id] = 0.0

		# TWO PASSES, because one pass cannot hold both properties this function needs.
		#
		# Every want is measured against `before` alone, which is what keeps the result
		# independent of the order firms are walked in -- the property the docstring
		# above states and the reason the snapshot exists at all. Reading a running
		# position instead (the V2.8 review's first attempt at the floor bug) fixed the
		# floor and silently bought it with that property: whoever moved first drained
		# the supply and whoever moved second could find nothing left.
		#
		# The floor is held by SCALING instead. A rival C ends below its floor exactly
		# when sum_i(gain_i / available_i) exceeds 1, because C gives up
		# supply_C * gain_i / available_i to each gainer i and supply_C is the whole of
		# what it has above the floor. So the wants are computed, that ratio is taken,
		# and if it exceeds 1 every want is scaled by its reciprocal. One subsidised
		# firm is the ratio <= 1 case and is untouched, which is every game so far.
		var wants := {}
		var pools := {}
		var claim := 0.0
		# A3: majors-only rivals, and the body is OUTSIDE the pool entirely --
		# it neither gives nor receives. Two reasons, the second decisive: the
		# pool is the verb channel's budget, and body rivals in it would grow
		# the drainable supply with the body tier's size (ten rivals vs
		# thirty), so a subsidised major's reachable share -- and the step-0
		# probe's measured escalator -- would depend on how many body firms
		# were generated. V1.4's balance calculus was calibrated against the
		# majors' own pool; keeping it that way preserves that calibration
		# under the roster's growth. And the tier doc's own shape says the
		# same: the body aggregates into the residual, static content that
		# neither drains nor feeds the verb plane -- no code path moves a
		# body firm's share (the body is inert by design, BODY SILENCE and
		# pinned); a later block's body market would write the register
		# directly rather than through this pool.
		if majors.size() < 1:
			continue  # no majors to subsidise: no verb can fire

		for company in majors:
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
			for rival in majors:
				if rival.id == company.id:
					continue
				available += maxf(
					float(before[rival.id]) - K.RIVAL_FLOOR_FRACTION * rival.share, 0.0
				)
			if available <= 0.0:
				continue

			var want: float = minf(
				K.SHARE_SHIFT_PER_MONTH * intensity,
				minf(available, maxf(K.SHARE_MAX - float(before[company.id]), 0.0))
			)
			if want <= 0.0:
				continue
			wants[company.id] = want
			pools[company.id] = available
			claim += want / available

		var scale: float = 1.0 / claim if claim > 1.0 else 1.0

		for company in majors:
			if not wants.has(company.id):
				continue
			var gain: float = float(wants[company.id]) * scale
			var available: float = float(pools[company.id])
			deltas[company.id] = float(deltas[company.id]) + gain
			for rival in majors:
				if rival.id == company.id:
					continue
				var supply: float = maxf(
					float(before[rival.id]) - K.RIVAL_FLOOR_FRACTION * rival.share, 0.0
				)
				deltas[rival.id] = float(deltas[rival.id]) - gain * supply / available

		# Majors only, because the pool only ever moved majors (A3's amended
		# design): every major holds an entry -- init_nation seeds a fresh game
		# and _seed_missing_majors repairs a loaded pre-7a save -- so a plain
		# indexed write is honest. The A1-era get-or-create here was the spillover
		# path for body rivals and is DELETED -- under the majors-only pool
		# no code path reaches it, and nothing moves a body firm's share
		# anyway: the body is inert by design (BODY SILENCE, pinned), and a
		# later block's body market would write the register directly, not
		# through this pool.
		for company in majors:
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
## rounding choice. (V1.4b authored this when named coverage sat near a
## quarter; V4.7a's two-tier register took every sector to 0.85-0.97 named, so
## the proportionality bound now binds near its ceiling -- the ~4x channel
## scale-up that put the extreme regimes ON the impulse clamp is recorded at
## test_balance.gd's assertions, and the re-tune is B4's declared-band sweep.
## A sector that is a quarter named is a quarter as regulable,
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
## burden AND no firm has failed. V1.4b widened that condition by the law; V4.7b
## widened it by the world: the autonomy machine fails ~0.55 firms/nation per
## idle 168-month run with no subsidy and no law standing, and a failed firm
## employs nobody -- the machine-caused non-zero this channel prices is the
## B4 re-run's largest moved channel, not a bug. See headcount().
##
## V1.5b: the denominator is now Demography.labour_force(), per nation and measured,
## where it was population x one flat 0.45. That re-baselines the jobs figures
## docs/companies-model.md reports -- the roster spans Italy 0.423 to the Netherlands
## 0.551 -- so V1.4a's measured 0.229/0.010 spread was re-measured rather than left to
## drift silently. It also means this term MOVES with the age structure: an ageing
## nation's labour force shrinks as a share of its population, so the same firm shedding
## the same jobs costs more points of unemployment later in a run than at the start.
static func firm_jobs_offset_pct(ns, loader) -> float:
	var labour_force: float = Demography.labour_force(ns)
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


## V1.4c's line, points of GDP per year. A computed REVENUE line -- the second on
## that side of the budget after V1.3c's tariffs, and the fifth computed line
## overall -- read by Budget.recompute() and not a fourth entry in
## economy_constants.TAX_KEYS. A dividend has no rate, no base share and no erosion
## curve; it is a yield on output the state happens to own.
##
## THE YIELD IS ON OUTPUT AND NOT ON PROFIT, which is the call
## docs/companies-model.md section 13 made a session in advance: there is no margin,
## profit or productivity quantity anywhere in src/sim/, and a half-invented one
## here would have to be either read or contradicted by everything downstream.
##
## Exactly 0.0 for every nation in every month in which the state holds nothing,
## which is every month of every run V1.4a's and V1.4b's bit-identity claims cover.
static func dividend_revenue_pct_gdp(ns, loader) -> float:
	if ns.gdp_eur_bn <= 0.0:
		return 0.0
	var paid := 0.0
	for company in firms_of(loader, ns.id):
		var held := state_share_of(ns, company.id)
		if held <= 0.0:
			continue
		paid += held * output_eur_bn(ns, company) * K.DIVIDEND_YIELD
	if paid == 0.0:
		return 0.0
	return minf(100.0 * paid / ns.gdp_eur_bn, K.DIVIDEND_MAX_PCT_GDP)


## All four cached onto NationState once a month and read from there, for the
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
	ns.dividend_revenue_pct_gdp = dividend_revenue_pct_gdp(ns, loader)


# --- The verb ------------------------------------------------------------------

## Which actions may be used against this firm right now. Diplomacy.available()'s
## shape, minus the cooldown: a subsidy is a STANDING STATE rather than an event,
## so `subsidy_active` gates it directly and a cooldown register would be a second
## gate on the same fact.
##
## V4.7a: the TIER gate lives here, in 7a and not with the B2 verbs. The
## step-0 probe's finding is that a body firm's share channel is ABSOLUTE -- a
## 0.01 firm drains the same pool as a 0.14 major and ends the term at 0.13 --
## so no verb targets a body firm, whatever its register state. The gate is
## DEFENCE IN DEPTH rather than the last line: the pool is majors-only and no
## code path writes a body entry -- the body is inert by design (BODY SILENCE,
## pinned) -- but if a later block's body market writes one, its existence
## must not make the tier a verb target. The gate stands for the register the
## design does not yet have.
static func available(state, ns, all_actions: Array, company_id: String, loader) -> Array:
	var out: Array = []
	if not ns.companies.has(company_id):
		return out
	# The id must be a LOADER major, not merely a register key: an orphan
	# entry (a save written before a content edit removed or renamed the
	# firm) would otherwise reach the failed gate and be offered a rescue
	# whose restore loop no-ops at value 0 -- a free rescue on a phantom.
	var in_loader := false
	for company in firms_of(loader, ns.id):
		if company.id == company_id:
			in_loader = true
			if not is_major(company):
				return out
			break
	if not in_loader:
		return out
	# The failed gate: a failed firm answers one door -- the rescue, inside its
	# window. Before this gate the dead register's preconditions were vacuously
	# true (`subsidy_active == 0`, the failure having cleared the subsidy), so
	# plain subsidise and nationalise were offered on a corpse, and a rescue
	# clicked on a COMMITTED failure fell through execute()'s window arm to
	# plain subsidise -- the zombie the pass-2 ultra traced: output through a
	# share the subsidy pool regrew, headcount 0 through the flag, one
	# register read two ways. The gate names the verb because the rescue's
	# AUTHORED preconditions cannot demand `failing` without losing its V1.4
	# healthy-firm form; it is the same id dispatch execute()'s bailout arm
	# already runs, and execute() refuses through here, so the door and the
	# arm cannot disagree.
	var failed_entry: Dictionary = ns.companies.get(company_id, {})
	if bool(failed_entry.get("failed", false)):
		# DISPATCH ON THE ACTION ID, one of two copies (execute()'s bailout
		# arm is the other; the failing-firms section is the UI's): a
		# deliberate rule-1 bend, recorded -- the rescue's AUTHORED
		# preconditions cannot demand `failing` without losing its V1.4
		# healthy-firm form, so the door names the verb. Renaming the id in
		# data/ needs the same rename here and in the tests, which pin it.
		if int(failed_entry.get("rescue_months_left", 0)) > 0:
			for action in all_actions:
				if String(action.id) == "strategic_rescue":
					out.append(action)
					break
		return out
	for action in all_actions:
		if action.id == "":
			continue
		if _preconditions_met(state, ns, action, company_id, loader):
			out.append(action)
	return out


static func _preconditions_met(state, ns, action, company_id: String, loader) -> bool:
	for cond in action.preconditions:
		var actual: float = _read_field(state, ns, cond["field"], company_id, loader)
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
static func _read_field(state, ns, field: String, company_id: String, loader) -> float:
	match field:
		"subsidy_active": return 1.0 if subsidy_of(ns, company_id) > 0.0 else 0.0
		"subsidy_count": return float(subsidised_count(ns))
		"state_owned": return 1.0 if state_share_of(ns, company_id) > 0.0 else 0.0
		"state_owned_count": return float(state_owned_count(ns))
		"deficit_pct_gdp": return ns.deficit_pct_gdp
		"debt_to_gdp_pct": return ns.debt_to_gdp_pct()
		"unemployment_pct": return ns.unemployment_pct
		"overall_approval_pct": return ns.overall_approval_pct
		# V4.7b: the autonomy machine's state. A failing firm is one inside its
		# rescue window (the flag with time left, not a committed failure); the
		# live share needs the loader firm for its authored fallback.
		"bid_pending":
			return 1.0 if String(ns.companies.get(company_id, {}).get("bid_bidder", "")) != "" else 0.0
		"failing":
			var fentry: Dictionary = ns.companies.get(company_id, {})
			return 1.0 if (bool(fentry.get("failed", false)) and int(fentry.get("rescue_months_left", 0)) > 0) else 0.0
		"courted":
			# The courtship flag: 1.0 from the moment the verb fires until a
			# bid is ANSWERED -- the gate that keeps a courtship from being
			# re-bought click by click.
			return float(ns.companies.get(company_id, {}).get("courted", 0.0))
		"firm_share":
			for company in firms_of(loader, ns.id):
				if company.id == company_id:
					return share_of_company(ns, company)
			return 0.0
		_:
			push_error("companies: unknown precondition field '%s'" % field)
			return 0.0


static func subsidised_count(ns) -> int:
	var n := 0
	for company_id in ns.companies.keys():
		if subsidy_of(ns, String(company_id)) > 0.0:
			n += 1
	return n


static func state_owned_count(ns) -> int:
	var n := 0
	for company_id in ns.companies.keys():
		if state_share_of(ns, String(company_id)) > 0.0:
			n += 1
	return n


## The player command: set or clear the standing subsidy, pay the domestic price,
## and record the result for the panel to read. Diplomacy.execute()'s shape and
## Legislature.propose()'s contract -- returns the result rather than mutating a
## panel.
##
## Refuses rather than half-applies when the action is not currently available, so
## a UI offering a stale button cannot produce the effect the precondition exists
## to prevent.
##
## THERE IS STILL NO COUNTERPARTY GATE, and V1.4c INHERITS that stopgap rather than
## discharging it. V1.4a declared none; V1.4b declared one, because a regulation is
## imposed and a firm that cannot relocate, exit, lobby or close is a visible
## absence. Nationalisation is the state acting ON a firm, not a firm acting: the
## price below is derived rather than negotiated and there is nobody to say no. What
## would discharge it is a firm interest model, which is a session and not a
## constant. Parked in docs/someday.md; the half V1.4c does answer is that a
## regulated firm now has one outcome other than arithmetic -- see headcount().
##
## Takes the loader, last, as every content-reading function in this file does. It
## is required rather than defaulted: a null loader would silently value every firm
## at zero and hand the player a free nationalisation.
static func execute(state, ns, all_actions: Array, action, company_id: String, loader) -> Dictionary:
	if not available(state, ns, all_actions, company_id, loader).has(action):
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
	var held_before := float(entry.get("state_share", 0.0))
	var price := 0.0

	# V4.7b: A RESCUE ON A FAILING MAJOR IS A BAILOUT AND THE STANDING SUPPORT
	# TOGETHER -- the window's whole meaning, and NOT a resurrection. Gated on
	# the WINDOW, not the flag alone: a committed failure (window 0) stays
	# committed -- the card copy promises "past it the collapse is committed" --
	# and a broken-up major (failed with a closed window) is never resurrected
	# while its rivals keep the absorbed split. The flag clears, the share is
	# RE-AUTHORED from content -- deliberately the authored position, not the
	# drifted live share the failure zeroed, so a rescue moves the sector's
	# named sum by (authored - live) whenever the machine's drift had moved
	# the firm: the firm returns to its content position, and the drift it
	# accumulated does not survive its death (pinned at that value in
	# test_industry). The window closes, and the treasury pays
	# the firm's value -- balance-sheet swap, the same capital-transaction
	# rule the ownership ops run under. The arm does not return: the ordinary
	# subsidise below then starts the recurring support on top of the one-off
	# capital price -- the failure cleared the subsidy, and the rescue is what
	# re-authors it. On a healthy firm the rescue is that subsidy alone, V1.4's
	# meaning kept.
	if action.id == "strategic_rescue" and bool(entry.get("failed", false)) and int(entry.get("rescue_months_left", 0)) > 0:
		entry["failed"] = false
		entry["rescue_months_left"] = 0
		# The failure commit's mechanical subsidy clear stamped the withdrawal
		# memory (shadow > 0, live 0), and the hazard's withdrawn term would
		# then double a firm the bailout just re-authorised full support for --
		# the state "pulled support" is false here, the state IS the support.
		# The memory resets with the rescue; a REAL withdrawal stamps again on
		# its own (the pass-6 fleet's merged find).
		entry["subsidy_lapsed_month"] = -1
		for company in firms_of(loader, ns.id):
			if company.id == company_id:
				entry["share"] = company.share
				break
		price = K.RESCUE_BAILOUT_PRICE_SHARE * _value_of(ns, loader, company_id)

	match String(terms.get("op", "")):
		"subsidise":
			entry["subsidy"] = float(terms.get("intensity", 0.0))
			# Re-support resets the withdrawal memory -- the rescue arm's own
			# principle ("the state IS the support") at the ordinary verb: a
			# withdraw-then-re-subsidise left the firm at a doubled failure
			# hazard for the window's remainder while fully subsidised, the
			# two re-support paths disagreeing about one memory (the pass-9
			# fleet's find). A withdrawal leaves the stamp standing; that is
			# the term's real work.
			if float(terms.get("intensity", 0.0)) > 0.0:
				entry["subsidy_lapsed_month"] = -1
		"withdraw": entry["subsidy"] = 0.0
		"block_bid":
			var bidder: String = String(entry.get("bid_bidder", ""))
			entry["bid_bidder"] = ""
			entry["bid_price_eur_bn"] = 0.0
			entry["bid_months_left"] = 0
			entry["courted"] = 0.0
			if bidder != "":
				_pulse_relations(state, ns.id, bidder.split("|")[0], K.BID_BLOCK_RELATIONS_PULSE)
		"allow_bid":
			var parts := String(entry.get("bid_bidder", "")).split("|")
			if parts.size() > 0 and String(parts[0]) != "":
				entry["owner"] = String(parts[0])
				_pulse_relations(state, ns.id, String(parts[0]), K.BID_ALLOW_RELATIONS_PULSE)
			entry["bid_bidder"] = ""
			entry["bid_price_eur_bn"] = 0.0
			entry["bid_months_left"] = 0
			entry["courted"] = 0.0
		"court":
			# The flag the bid hazard reads (industry.gd multiplies the yearly
			# hazard for a courted firm). Written only here; cleared by an
			# ANSWERED bid (allow/block clear it with the bid) and by DEATH --
			# the failure commit and break_up end the courtship, the pass-9
			# rule that a resurrected firm returns without the standing x5.
			# Exposure is re-bought only by courting again (takeover.json's
			# courted == 0 gate).
			entry["courted"] = 1.0
		"appoint_board":
			# V4.7b: the SOE chair -- a deterministic draw from the nation's
			# unseated executives (Cycle, no rand; an unseated executive is
			# one no register entry names as its chair). A face and a name on
			# the firm row, not a lever: the executive's own act channel is
			# V4.2's lobbying. A second appointment replaces the first, and
			# the verb REFUSES when no unseated executive remains -- clearing
			# the standing chair would be an appointment that removed a face
			# while still pricing the blocs, patronage backwards (the ultra's
			# find; the exhausted pool is the draw's own bound).
			var unseated: Array = []
			# The seated scan counts only LOADER majors' chairs: an orphan
			# entry (a save written before a content edit removed the firm)
			# is unactionable -- no verb reaches it, so its chair would drain
			# the appointable pool forever, the pass-8 defect re-entering
			# through the one register walk left unskipped (the pass-9
			# fleet's find).
			var loader_majors := {}
			for company in majors_of(loader, ns.id):
				loader_majors[company.id] = true
			for person in loader.people.get(ns.id, []):
				if String(person.kind) != "executive":
					continue
				var seated := false
				for other_id in ns.companies.keys():
					if not loader_majors.has(other_id):
						continue
					if String(ns.companies[other_id].get("board_chair", "")) == String(person.id):
						seated = true
						break
				if not seated:
					unseated.append(String(person.id))
			if unseated.is_empty():
				var refused_chair := {
					"action_id": action.id,
					"company_id": company_id,
					"applied": false,
					"refused": true,
					"reason": "every executive already holds a chair",
				}
				ns.last_company_result = refused_chair
				return refused_chair
			unseated.sort()
			var pick_index := int(Cycle.unit(
				"companies|%s|chair" % company_id, int(state.year) * 12 + int(state.month))
				* float(unseated.size()))
			entry["board_chair"] = unseated[pick_index % unseated.size()]
		"break_up":
			# The sector's OTHER MAJORS absorb the share -- the why is the
			# block below. No new firm ids are minted, because a register
			# entry with no authored content cannot price a payroll (the
			# reads fall back to the loader's firm object, and a minted id
			# has none). The major marks failed with a closed window:
			# committed, not rescuable -- a dissolved firm does not come
			# back. Its jobs read 0 through the failed branch.
			var split_share: float = share_of_company(ns, _firm_of(ns, loader, company_id))
			# The split goes to the sector's OTHER MAJORS, pro-rata by live
			# share -- its rivals divide the market. The first draft split to
			# the body tier and the pin caught it: pro-rata body receipts push
			# body firms past BODY_SHARE_MAX, the exact escalation the tier
			# boundary exists to make impossible. Majors-only keeps every
			# invariant: body unchanged, sum conserved, no new ids.
			var major_absorber := 0.0
			for other in majors_of(loader, ns.id):
				if other.id != company_id and other.sector == _sector_of_id(ns, loader, company_id) and not bool(ns.companies.get(other.id, {}).get("failed", false)):
					major_absorber += share_of_company(ns, other)
			if major_absorber <= 0.0:
				# A sector whose only major is the target has no absorber:
				# the split would silently fall to the residual -- the verb
				# as a sector lever wearing a firm's name. Refused, and the
				# refusal is the panel's to show.
				var refused_split := {
					"action_id": action.id,
					"company_id": company_id,
					"applied": false,
					"refused": true,
					"reason": "no other major in the sector can absorb the split",
				}
				ns.last_company_result = refused_split
				return refused_split
			if major_absorber > 0.0:
				for other in majors_of(loader, ns.id):
					if other.id == company_id or other.sector != _sector_of_id(ns, loader, company_id) or bool(ns.companies.get(other.id, {}).get("failed", false)):
						continue
					var other_entry: Dictionary = ns.companies.get(other.id, {})
					if other_entry.is_empty():
						continue
					other_entry["share"] = float(other_entry.get("share", other.share)) + split_share * (share_of_company(ns, other) / major_absorber)
			entry["failed"] = true
			entry["rescue_months_left"] = 0
			entry["share"] = 0.0
			# The failure commit's own rule: a dissolved firm's support stops.
			# It employs nobody to support, and a subsidy standing here would
			# bill on for nothing. And its foreign interest dies with it -- the
			# pass-4 fix ran in industry.gd's failure commit only, leaving
			# break_up (whose precondition has no bid gate, so the verbs are
			# co-offered) serving a ghost bid to the panel and the pending
			# mark for the window's remainder (the pass-5 merged find). A
			# dissolved firm's courtship is dead with it.
			entry["subsidy"] = 0.0
			entry["bid_bidder"] = ""
			entry["bid_price_eur_bn"] = 0.0
			entry["bid_months_left"] = 0
			entry["courted"] = 0.0
			# The seat dies with the firm -- industry.gd's failure commit runs
			# the same clear, for the same pool-drain reason.
			entry["board_chair"] = ""
		"nationalise":
			var stake := float(terms.get("stake", 0.0))
			price = (stake - held_before) * _value_of(ns, loader, company_id)
			entry["state_share"] = stake
		"privatise":
			price = -held_before * _value_of(ns, loader, company_id)
			entry["state_share"] = 0.0

	# A CAPITAL TRANSACTION IS A BALANCE-SHEET SWAP, not income, and this is the one
	# place in the project that writes the debt stock outside Budget.tick_month().
	# Three things follow for free and none of them needed building: the interest on
	# it is priced by Budget.recompute() at DEBT_REAL_RATE_PCT, the level is read by
	# the bloc's own `debt_to_gdp_pct` rule, and it has been serialised since the MVP.
	#
	# It also moves `deficit_pct_gdp` by exactly zero in the month it happens, which
	# matters rather than being tidy: the deficit is a company action's own
	# precondition field, so a one-off on the revenue side would close the loop the
	# subsidy bill's one-month lag exists to avoid.
	ns.debt_eur_bn += price

	for bloc_id in action.effects.get("bloc_offset", {}).keys():
		# CLAMPED, like every other writer of this register (legislature.gd,
		# diplomacy.gd, government.gd, pledges.gd, referendum.gd). Written bare until
		# the V2.8 review, so an offset already at the bound could be pushed past it --
		# and _op_legal()'s own comment reasons about the exploit it fixed in terms of
		# BLOC_OFFSET_MAX, i.e. it assumes a bound this line did not enforce.
		ns.bloc_offset[bloc_id] = clampf(
			float(ns.bloc_offset.get(bloc_id, 0.0))
			+ float(action.effects["bloc_offset"][bloc_id]),
			LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX
		)

	var result := {
		"action_id": action.id,
		"action_name": action.action_name,
		"company_id": company_id,
		"applied": true,
		"refused": false,
		"subsidy_before": before,
		"subsidy_after": float(entry["subsidy"]),
		"state_share_before": held_before,
		"state_share_after": float(entry["state_share"]),
		"price_eur_bn": price,
	}
	ns.last_company_result = result
	return result


## V4.7b: the ONE relations writer outside diplomacy.gd, for the one company
## verb that HAS a counterparty -- a foreign state's takeover offer, answered.
## Through Relations.adjust at diplomacy's own bounds [0, 100]: a relations
## register readable from 0 has no use for a minus, and the first draft's
## hardcoded [-100, 100] could write below the readable floor.
static func _pulse_relations(state, acting_nation: String, other_nation: String, delta: float) -> void:
	if other_nation == "" or other_nation == acting_nation:
		return
	Relations.adjust(state, acting_nation, other_nation, delta,
		DK.RELATIONS_MIN, DK.RELATIONS_MAX)


static func _firm_of(ns, loader, company_id: String):
	for company in firms_of(loader, ns.id):
		if company.id == company_id:
			return company
	return null


static func _sector_of_id(ns, loader, company_id: String) -> String:
	var firm = _firm_of(ns, loader, company_id)
	return String(firm.sector) if firm != null else ""


static func _value_of(ns, loader, company_id: String) -> float:
	for company in firms_of(loader, ns.id):
		if company.id == company_id:
			return value_eur_bn(ns, company)
	return 0.0
