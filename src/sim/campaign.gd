extends RefCounted

## The campaign phase: a window before the vote in which the president can spend
## money to change WHO TURNS OUT. Built at V1.7a, the first session of the V1.7 block.
##
## The model and every number's rationale is docs/campaign-model.md;
## src/sim/campaign_constants.gd is the bounds and data/campaign-actions/ is the
## content -- which is where the price and the reach live, because this file ships no
## constant for either.
##
## ============================================================================
## THE ROW ASKED FOR THREE THINGS AND TWO WERE ALREADY ANSWERED
## ============================================================================
## docs/tiers/v1.md section 7's first bullet is "a window before the vote, spending
## TIME and MONEY on MESSAGING". Counted against what is built:
##
##   TIME does not exist, and it was DELETED rather than never built.
##     docs/calendar-model.md's U6a swept a monthly budget of the player's days
##     against a band fixed before the sweep and found the band structurally
##     unreachable: the median month offers 27 legal acts asking 124 days, so every
##     budget from 4 to 24 bound in 100 % of months. A ceiling that always binds is a
##     cap, not an allocation. The reason carried forward is not about calendars --
##     available() returns what is LEGAL and nothing models what the player WANTS, so
##     any ceiling priced against legality always binds -- and it applies here
##     unchanged. This file prices a campaign in money alone.
##
##   MESSAGING is docs/media-model.md's, and that bullet says so itself: "V1.5d may
##     build the peacetime half; if it does, this bullet READS it rather than
##     rebuilding it." V1.5d built it and cut the campaign-time twin in the same
##     session, on the ground that messaging which damps hostile framing IS
##     press_freedom's positive direction with a different label -- one accumulator,
##     two writers. So this file writes nothing on ns.framing_gain and nothing on
##     ns.press_freedom, and tests/test_campaign.gd reads this source and fails if
##     either name appears in it.
##
##   MONEY is what is left, and its TARGET had to be found.
##
## ============================================================================
## THE TARGET IS TURNOUT, AND IT IS THE ONE QUANTITY WITH NO WRITER
## ============================================================================
## election_constants.BLOC_TURNOUT is read in exactly two places, both inside
## Elections.vote_share(), and nothing in this project has ever written it. That makes
## a live per-bloc offset a FIRST writer with no double count to resolve -- which
## neither of the other two candidates could claim:
##
##   approval. Elections.vote_share()'s `pull` term already reads ns.bloc_approval, and
##     approval IS the term's record. A campaign term there is a second writer of the
##     one quantity the whole game is judged on, and it would make the last six months
##     worth more than the first fifty-four.
##   framing. Refused above, by V1.5d.
##
## And the distinction is the honest one rather than a convenience: a campaign does not
## change what people think of your record -- the record is the record, and V1.5d's
## press decides how loudly it is heard. It changes who bothers to vote on it.
##
## ============================================================================
## LOG-ODDS, SO THE TURNOUT IS BOUNDED BY CONSTRUCTION
## ============================================================================
## Mobilisation is a shift in the LOG-ODDS of a bloc turning out, not a multiplier on
## its rate. Two things fall out that nobody authored:
##
##   1. turnout_of() is strictly inside (0, 1) for every finite mobilisation, so there
##      is no clamp on turnout anywhere and no value of MOBILISATION_MAX that could
##      produce a share above one. docs/cycle-model.md's V1.6a argument: a bound with
##      no number to set wrong is stronger than a clamp.
##   2. The SAME effort moves a low-turnout bloc further than a high-turnout one. At
##      +0.60, students go 0.450 -> 0.599 (+14.9 points) and pensioners 0.820 -> 0.892
##      (+7.2). There is more room to mobilise students than pensioners, and the model
##      says so without a table -- which is the arithmetic doing what
##      docs/election-model.md's BLOC_TURNOUT comment only asserts.
##
## ============================================================================
## THE WINDOW IS A LEVEL READ AND THE CLEAR IS ITS OTHER HALF
## ============================================================================
## is_open() compares the clock against ns.next_executive_year / _month. There is no
## "the campaign has opened" flag, no scheduler and no hook in elections.gd:
## docs/defence-model.md's V1.3g rule, that nothing in this project ever lifts a flag
## it has set, so an obligation which opens itself must also close itself.
##
## The register clears the month the window closes, which is the month AFTER the vote,
## because Elections.tick_month() pushes next_executive_* five years forward on a win.
## That is why this file needs no call from elections.gd at all -- the one edge that
## would have needed one is read as a level instead. A legislative or European
## election landing inside the run-up READS the mobilisation and does not clear it,
## which is correct: a mobilised electorate votes in whatever election is held.
##
## THE EXECUTIVE VOTE AND NOT THE LEGISLATIVE ONE, and Elections.init_nation() is what
## makes that one read rather than two: where there is no separately elected executive
## it already points next_executive_* at the legislative date. So France campaigns for
## the presidency and Germany for the Bundestag with no branch here.
##
## ============================================================================
## AN EFFORT IS A STANDING RATE WITH A DEADLINE, AND THAT IS WHAT KILLS THE
## STRICTLY-DOMINATED SHAPE
## ============================================================================
## The first design made an act a one-off purchase billed for one month. Under it,
## acting LATE is strictly better -- same mobilisation, less time paying for it -- and
## this project has killed that shape six times (V1.3c's severities, V1.3d's fourth
## rule, U6a's booking, V1.4c's dividend, V1.5d's censorship, V1.6e's flat bill).
##
## So an effort accrues its mobilisation EVERY MONTH it runs and bills EVERY MONTH it
## runs. Start early and you buy more and pay more; start late and you buy less and pay
## less. Linear in months on both sides, and neither end dominates.
##
## ============================================================================
## V2.6b2 -- THE EFFORT NAMES A REGION, AND THE TOUR IS THE DECISION
## ============================================================================
## A running effort holds its meeting in ONE region the player names at start, and the
## month's mobilisation is scaled by that site's reach-per-day factor: the region's
## principal city share of the nation divided by the journey's travel days, normalised
## mean-one in the principal cities' own population weights (the average MEETING
## delivers the authored rate, so V1.7a's calibration survives and only the choice
## varies it), times (1 - spoken), where spoken is the region's saturation -- the
## fraction of its attention previous meeting months already hold. One meeting month
## speaks to a region's whole attention; the fraction decays on
## SATURATION_HALF_LIFE_MONTHS. campaign_constants.gd's comment carries the band and
## both clauses; docs/campaign-model.md section 18 carries the tables;
## tools/tour_probe.gd is what measured them.
##
## THE SITE IS THE PLAYER'S, AND THIS FILE DOES NOT SELECT IT. That is the whole
## difference from unrest's sited demonstration (docs/siting-model.md): the grievance's
## place is a derived report read through Siting.site(); a campaign meeting's place is
## a verb whose failure mode is dominance, and dominance is broken by the player's own
## tour -- the reach-per-day form without the saturation counter is the
## strictly-dominated shape this project has killed twelve times, and WITH the counter
## the optimal tour leaves the capital (measured, not asserted). Siting.site() is not
## called here and must never be.
##
## Preloads its constants, opinion_constants, election_constants and
## diplomacy_constants only. A leaf: no elections.gd (which reads this register rather
## than being called by it), no media.gd, no opinion.gd -- and no siting.gd, whose
## selection machinery this verb exists to refuse.

const K = preload("res://src/sim/campaign_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const ElectionK = preload("res://src/sim/election_constants.gd")
## The travel rate and clamps only. The pricing is this file's own -- a campaign
## meeting prices capital-to-principal-city, a journey Diplomacy.travel_days() has no
## shape for -- so the formula is repeated here rather than borrowed, with the rate
## still owned by the one constants file. (The alternative, a shared geo leaf, would
## need tests/test_campaign.gd's leaf check widened past `_constants.gd` preloads;
## eight lines of haversine is the cheaper contract to keep.)
const DK = preload("res://src/sim/diplomacy_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
## V5.1-0d (G1): which city is the capital, the map's and the diary's one rule. A
## src/core reader rather than a system, so the leaf check lets it through.
const Capital = preload("res://src/core/capital.gd")


## Seeds the live register: nothing in the field and nobody mobilised.
##
## Every nation gets the fields rather than only the player, Projects.init_nation()'s
## call: what keeps the nine inert is that nothing ever executes an action for them,
## and tests/test_campaign.gd pins that there is no AI agenda term for this verb --
## docs/defence-model.md's honest limitation, recorded a fourth time.
static func init_nation(ns) -> void:
	ns.campaign_running = []
	ns.campaign_started = []
	ns.campaign_mobilisation = {}
	ns.campaign_sites = {}
	ns.campaign_saturation = {}


## Accrue -- or clear, if the run-up is over.
##
## Runs in WorldMonth's order after Budget and before Elections, and Budget.project()
## runs it in the same slot. V5.2 C6 retired the state's campaign bill (the party pays,
## docs/design/v5.2-c6-party-campaigns.md section 8), so nothing here reaches the
## budget any more.
##
## Running BEFORE Elections is what makes the month of the vote count: is_open() is
## true at zero months to go, so the last month of effort is accrued and read by the
## vote it was bought for.
static func tick_month(state, loader) -> void:
	var terms := _terms_by_effort(loader)
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		var ns = state.nations[id]
		_decay(ns)
		if not is_open(state, ns):
			_clear(ns)
			continue
		_accrue(ns, terms, loader)


## One month of forgetting, for every nation whether or not anything is in the field.
## The spoken-to memory is attention, not campaign state: it persists across windows,
## so a region worked in the last run-up is still partly spoken-to at the start of the
## next one, and the nine carry an empty register forever (nothing ever speaks to them).
static func _decay(ns) -> void:
	if ns.campaign_saturation.is_empty():
		return
	var rate := pow(0.5, 1.0 / K.SATURATION_HALF_LIFE_MONTHS)
	for rid in ns.campaign_saturation:
		ns.campaign_saturation[rid] = float(ns.campaign_saturation[rid]) * rate


## One month of every running effort, onto the accumulator, AT ITS SITE. The month's
## offer is read on the saturation state as the tour arrives -- earlier months' accruals
## and decays only -- then the meeting speaks (+1.0, clamped), so a second consecutive
## month in the same region reaches (1 - 1.0) = nothing and the tour must move. The
## factor is exactly 1.0 for an effort with no site -- the version-29 save's absent-read,
## and what keeps a site-less accrual bit-identical to the pre-V2.6b2 model.
##
## Sorted, because a Dictionary's key order is insertion order and two runs that reached
## the same state by different routes must tick alike.
static func _accrue(ns, terms: Dictionary, loader) -> void:
	var running: Array = ns.campaign_running.duplicate()
	running.sort()
	for eid in running:
		var site := site_of(ns, String(eid))
		var factor := 1.0
		if site != "":
			factor = factor_of(ns, loader, site)
			ns.campaign_saturation[site] = minf(1.0, float(ns.campaign_saturation.get(site, 0.0)) + 1.0)
		var mobilisation: Dictionary = terms.get(String(eid), {}).get("mobilisation", {})
		var blocs: Array = mobilisation.keys()
		blocs.sort()
		for bloc in blocs:
			ns.campaign_mobilisation[bloc] = clampf(
				float(ns.campaign_mobilisation.get(bloc, 0.0)) + float(mobilisation[bloc]) * factor,
				-K.MOBILISATION_MAX, K.MOBILISATION_MAX
			)


## The run-up is over. Everything goes: the efforts are out of the field and the
## mobilisation is spent at the ballot box.
##
## Assigned rather than cleared in place, because NationState.copy() duplicates these
## and a shared reference surviving a Budget.project() would let a projection write
## the live register -- docs/tax-model.md section 11's live bug, avoided by shape.
static func _clear(ns) -> void:
	ns.campaign_running = []
	ns.campaign_started = []
	ns.campaign_mobilisation = {}
	ns.campaign_sites = {}
	## campaign_saturation is deliberately NOT cleared: it is attention, not campaign
	## state, and it decays on its own half-life whether or not a run-up is on.


# --- The site -------------------------------------------------------------------------

## Where each effort's meetings are held: effort id -> region id. Written at start,
## erased at stop, and cleared with everything else when the window closes. The save
## carries it because a running effort with no site would silently fall back to the
## old national reach and the panel would lie about where the president is.
static func site_of(ns, effort_id: String) -> String:
	return String(ns.campaign_sites.get(effort_id, ""))


## The region's spoken-to attention, in [0, 1]. Absent reads 0.0 -- the truth about
## every region nothing has spoken to yet, and about every pre-V2.6b2 save.
static func spoken(ns, region_id: String) -> float:
	return clampf(float(ns.campaign_saturation.get(region_id, 0.0)), 0.0, 1.0)


## The acting nation's regions, in authored order -- the importer writes them
## descending by population, so a picker that lists them in file order lists them
## biggest first. Sorted ids for anything the test reads.
static func region_ids(ns, loader) -> Array:
	var out: Array = []
	for region in loader.regions.get(ns.id, []):
		out.append(String(region.id))
	return out


## The region's principal city -- the largest share IN the region, picked explicitly
## rather than trusting authored order. Ties go to the authored order, which is the
## register's own ranking discipline.
static func principal_city(loader, ns, region_id: String) -> Variant:
	for region in loader.regions.get(ns.id, []):
		if String(region.id) != region_id:
			continue
		var best: Variant = null
		for city in region.cities:
			if best == null or float(city.share) > float(best.share):
				best = city
		return best
	return null


static func site_city_name(loader, ns, region_id: String) -> String:
	var city = principal_city(loader, ns, region_id)
	return String(city.city_name) if city != null else ""


## Days the journey from the capital to the region's principal city occupies -- the
## same pricing Diplomacy.travel_days() applies between capitals, applied inside one
## nation. The formula is quoted rather than borrowed (see the DK preload note).
static func travel_days_to(ns, loader, region_id: String) -> int:
	var from_lonlat = _capital_lonlat(loader, ns.id)
	var city = principal_city(loader, ns, region_id)
	if from_lonlat == null or city == null:
		return int(DK.TRAVEL_DAYS_MAX)
	var km := _haversine_km(from_lonlat, city.lonlat)
	return clampi(int(ceil(km / DK.TRAVEL_KM_PER_DAY)), int(DK.TRAVEL_DAYS_MIN), int(DK.TRAVEL_DAYS_MAX))


## The site's reach factor for ONE month: fresh reach-per-day times the unspoken
## fraction of the region's attention. Exactly 1.0 for the site-less case, and the
## fresh half is mean-one in UNIFORM weights over the nation's regions, so the
## average CHOICE delivers the authored rate and only the choice varies it -- the
## property tests/test_campaign.gd asserts to 1e-12.
static func factor_of(ns, loader, region_id: String) -> float:
	return fresh_factor(ns, loader, region_id) * (1.0 - spoken(ns, region_id))


## Share of the nation / travel days, normalised mean-one in UNIFORM weights over
## the nation's regions: the player's menu is regions, so the authored rate is what a
## TYPICAL CHOICE delivers. The population-weighted form was built first -- V2.6b1's
## Siting.normalised() idiom, the average voter's meeting -- and it measured the
## calibration band EMPTY: with the capital at x2.37, the tour clauses and V1.7a's
## lower edge are jointly infeasible in every saturation strength and every window the
## emulator can express (tools/campaign_probe.gd's table (d), worst move 0.176 against
## a 0.3415 edge). Uniform puts the capital at x6.63 and the band refits at [1, 10].
## The idiom does not transfer, and the reason is worth stating: V2.6b1's output price
## is lost WHERE THE PEOPLE ARE, so population weights anchor it; reach is delivered
## WHERE THE PLAYER GOES, so the choice distribution anchors it. The cost, recorded:
## the population-weighted mean of the factor under uniform sits near 1.4, so a
## touring campaign runs hotter than V1.7a's expected price and the window pays for it
## by shrinking to 6.
static func fresh_factor(ns, loader, region_id: String) -> float:
	var weighted := 0.0
	var weight_sum := 0.0
	var fresh := 0.0
	var found := false
	var from_lonlat = _capital_lonlat(loader, ns.id)
	for region in loader.regions.get(ns.id, []):
		var city = null
		for candidate in region.cities:
			if city == null or float(candidate.share) > float(city.share):
				city = candidate
		if city == null:
			continue
		var share: float = float(ns.region_pop_share[String(region.id)]) \
			* float(ns.city_pop_share[String(city.id)])
		var days := int(DK.TRAVEL_DAYS_MAX)
		if from_lonlat != null:
			days = clampi(int(ceil(_haversine_km(from_lonlat, city.lonlat) / DK.TRAVEL_KM_PER_DAY)),
				int(DK.TRAVEL_DAYS_MIN), int(DK.TRAVEL_DAYS_MAX))
		var value := share / float(days)
		weighted += value * 1.0
		weight_sum += 1.0
		if String(region.id) == region_id:
			fresh = value
			found = true
	if not found or weight_sum <= 0.0:
		return 1.0
	return fresh / (weighted / weight_sum)


static func _capital_lonlat(loader, nation_id: String) -> Variant:
	return Capital.lonlat(loader, nation_id)


## Great-circle distance in kilometres, Diplomacy._haversine_km()'s formula quoted
## (see the DK preload note above for why it is not preloaded from there).
static func _haversine_km(a: Vector2, b: Vector2) -> float:
	const EARTH_RADIUS_KM := 6371.0
	var lon1 := deg_to_rad(a.x)
	var lat1 := deg_to_rad(a.y)
	var lon2 := deg_to_rad(b.x)
	var lat2 := deg_to_rad(b.y)
	var dlat := lat2 - lat1
	var dlon := lon2 - lon1
	var h := sin(dlat * 0.5) * sin(dlat * 0.5) \
		+ cos(lat1) * cos(lat2) * sin(dlon * 0.5) * sin(dlon * 0.5)
	return 2.0 * EARTH_RADIUS_KM * asin(minf(1.0, sqrt(h)))


# --- The window ------------------------------------------------------------------

## Months from now until the vote that decides the player's office. Negative is
## impossible in a live game -- Elections.tick_month() moves the date forward the
## month it resolves -- but is returned honestly rather than clamped, because a probe
## driving state by hand can reach it.
static func months_to_election(state, ns) -> int:
	if ns.next_executive_year <= 0:
		return -1
	return (ns.next_executive_year - state.year) * 12 + (ns.next_executive_month - state.month)


## True inside the run-up, INCLUSIVE of the month of the vote.
##
## A pure comparison against the clock. See the header: there is no flag, so there is
## nothing that can disagree with this.
static func is_open(state, ns) -> bool:
	var months := months_to_election(state, ns)
	return months >= 0 and months <= K.CAMPAIGN_WINDOW_MONTHS


# --- What the vote reads ------------------------------------------------------------

## A bloc's turnout with the campaign applied: election_constants.BLOC_TURNOUT shifted
## by this nation's accumulated mobilisation, in log-odds.
##
## STRICTLY INSIDE (0, 1) FOR EVERY FINITE SHIFT, so Elections.vote_share() needs no
## clamp and this file ships no turnout bound. See the header.
##
## Reads EXACTLY the authored constant at mobilisation 0.0 -- not approximately, but
## bit-for-bit, because the branch returns before any arithmetic happens. That is what
## keeps the nine non-playing nations and every existing test bit-identical, and
## tests/test_campaign.gd asserts it with exact equality rather than is_equal_approx.
static func turnout_of(ns, bloc: String) -> float:
	var base: float = float(ElectionK.BLOC_TURNOUT[bloc])
	var shift: float = float(ns.campaign_mobilisation.get(bloc, 0.0))
	if shift == 0.0:
		return base
	var odds: float = base / (1.0 - base)
	var shifted: float = odds * exp(shift)
	return shifted / (1.0 + shifted)


## How far this nation's campaign has pulled turnout apart, in points, for the readout.
## Zero for a nation that has not campaigned, which is why the ledger row is silent at
## zero rather than printing permanent furniture -- docs/society-model.md section 11's
## discipline.
static func turnout_spread(ns) -> float:
	var worst := 0.0
	for bloc in OpinionK.BLOC_KEYS:
		worst = maxf(worst, absf(turnout_of(ns, bloc) - float(ElectionK.BLOC_TURNOUT[bloc])))
	return worst


# --- Reading the register ------------------------------------------------------------

static func is_running(ns, effort_id: String) -> bool:
	return ns.campaign_running.has(effort_id)


## True once this effort has been in the field at any point in the CURRENT run-up,
## whether or not it still is. Cleared with everything else when the window closes,
## so the next run-up starts from a clean ladder.
static func has_started(ns, effort_id: String) -> bool:
	return ns.campaign_started.has(effort_id)


## Effort ids in the field, sorted, for the panel. Sorted rather than in insertion
## order so two saves of the same state draw the same list.
static func running(ns) -> Array:
	var out: Array = []
	for eid in ns.campaign_running:
		out.append(String(eid))
	out.sort()
	return out


static func running_count(ns) -> int:
	return ns.campaign_running.size()


# --- The terms -------------------------------------------------------------------------

## effort id -> the authored {cost_eur_per_k_pop_month, mobilisation, effort_name} of its `start`
## action. Built from the loader on every call rather than cached on NationState,
## because caching it would put content in the save -- the property
## tests/test_campaign.gd pins, and V1.4a's, V1.6e's and V1.6f's tests before it.
static func _terms_by_effort(loader) -> Dictionary:
	var out := {}
	if loader == null:
		return out
	for action in loader.campaign_actions:
		var terms: Dictionary = action.effects.get("campaign", {})
		if String(terms.get("op", "")) != "start":
			continue
		out[String(terms.get("effort_id", ""))] = terms
	return out


## The authored facts about one effort, for the panel and the probe. Empty if the id
## names no `start` action.
static func terms_of(loader, effort_id: String) -> Dictionary:
	return _terms_by_effort(loader).get(effort_id, {})


## The NOUN, not the action name. Projects.name_of()'s reason: an action name is an
## imperative, which is right on the button that starts it and wrong everywhere the
## thing itself is named.
static func name_of(loader, effort_id: String) -> String:
	return String(terms_of(loader, effort_id).get("effort_name", effort_id))


# --- The verb --------------------------------------------------------------------------

## Which actions may be used right now. Projects.available()'s shape.
##
## REFUSES EVERYTHING OUTSIDE THE WINDOW, structurally, before any content is
## consulted. That is why campaign_constants.PRECONDITION_FIELDS has no `campaign_open`
## entry: whether the run-up has begun is a property of the clock and not an authorial
## choice, so a content file that had to remember it would be a file that could forget
## it. Projects.available()'s argument for checking op legality in code.
static func available(state, ns, all_actions: Array) -> Array:
	var out: Array = []
	if not is_open(state, ns):
		return out
	for action in all_actions:
		if action.id == "":
			continue
		if not _op_legal(ns, action):
			continue
		if _preconditions_met(state, ns, action):
			out.append(action)
	return out


## AN EFFORT GETS ONE RUN PER WINDOW, so `start` reads the SPENT register and not only
## the running one. Stopping does not hand the effort back.
##
## Without that second read, start/stop/start inside a single month re-paid the
## action's authored `bloc_offset` on every cycle: the offset is a PERMANENT
## accumulator charged at the press, while the bill is charged over the running set
## once a month, so the loop cost nothing and elapsed no time. On start_town_halls --
## the only effort in the ladder whose offset is positive -- that farmed rural
## approval to legislature_constants.BLOC_OFFSET_MAX in about thirty presses. The
## strictly-dominated shape this project has killed eight times, arriving for once as
## a free REWARD rather than an avoided cost.
##
## Fixed here rather than by making the offset accrue monthly, which is a different
## model: docs/campaign-model.md's constants were selected against a press-time
## offset, so moving it would re-baseline the balance harness. What is given up is
## pausing an effort to save its bill and resuming it later -- and that was never a
## decision the window poses, because the bill is linear in months and the register
## is not: pausing already keeps what it bought, so a resumable effort is strictly
## cheaper than a continuous one for the same reach.
static func _op_legal(ns, action) -> bool:
	var terms: Dictionary = action.effects.get("campaign", {})
	var eid := String(terms.get("effort_id", ""))
	match String(terms.get("op", "")):
		"start": return not is_running(ns, eid) and not has_started(ns, eid)
		"stop": return is_running(ns, eid)
		_: return false


static func _preconditions_met(state, ns, action) -> bool:
	for cond in action.preconditions:
		var actual: float = _read_field(state, ns, cond["field"])
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


## Every field here is the acting nation's own state, which is the one way this list
## differs from Projects._read_field(): a project action asks about the project it
## names, and a campaign effort has nothing to ask about itself that _op_legal() has
## not already settled.
static func _read_field(state, ns, field: String) -> float:
	match field:
		"months_to_election": return float(months_to_election(state, ns))
		"campaign_count": return float(running_count(ns))
		"deficit_pct_gdp": return ns.deficit_pct_gdp
		"debt_to_gdp_pct": return ns.debt_to_gdp_pct()
		"unemployment_pct": return ns.unemployment_pct
		"overall_approval_pct": return ns.overall_approval_pct
		_:
			push_error("campaign: unknown precondition field '%s'" % field)
			return 0.0


## The player command: put an effort into the field or take it out, pay the domestic
## price, and record the result for the panel to read. Projects.execute()'s shape.
##
## IT DOES NOT GO THROUGH Budget.commit(), AND THAT IS DELIBERATE RATHER THAN
## CONVENIENT -- V1.6e's and V1.6f's escape from docs/tax-model.md section 11's live
## bug, inherited whole. budget_panel.gd refreshes from a `_pending` captured in
## setup(), so anything committing a budget outside that panel's own sliders leaves it
## stale and offering to undo the commit. Writing an own register and letting the cost
## arrive as a computed line means this verb cannot meet that bug at all.
##
## Refuses rather than half-applies when the action is not currently available, so a UI
## offering a stale button cannot produce the effect the window exists to prevent.
##
## A STOPPED EFFORT KEEPS WHAT IT BOUGHT. The money is spent and the voters it reached
## are reached; what stops is the bill and the accrual. That is src/sim/investment.gd's
## `withdraw` rather than src/sim/projects.gd's `abandon`, and the difference is the
## model: half a motorway is worth nothing and half a campaign is worth half a
## campaign.
static func execute(state, ns, all_actions: Array, action, region_id := "") -> Dictionary:
	var terms: Dictionary = action.effects.get("campaign", {})
	var eid := String(terms.get("effort_id", ""))
	var campaign_op := String(terms.get("op", ""))

	if not available(state, ns, all_actions).has(action):
		var refused := {
			"action_id": action.id,
			"effort_id": eid,
			"applied": false,
			"refused": true,
		}
		ns.last_campaign_result = refused
		return refused

	## A start MUST name the region its meetings are held in, and the region must be
	## the acting nation's own -- validated against the live V2.6a register, whose
	## keys are exactly this nation's region ids, so no second roster exists to drift.
	## A UI that lost its picker cannot silently run a place-less campaign; the refusal
	## is the panel's disabled button made loud.
	if campaign_op == "start":
		var reason := ""
		if region_id == "":
			reason = "choose where the meetings are held"
		elif not ns.region_pop_share.has(region_id):
			reason = "no such region in this nation"
		if reason != "":
			var refused := {
				"action_id": action.id,
				"effort_id": eid,
				"op": campaign_op,
				"applied": false,
				"refused": true,
				"reason": reason,
			}
			ns.last_campaign_result = refused
			return refused

	match campaign_op:
		"start":
			ns.campaign_running.append(eid)
			ns.campaign_started.append(eid)
			ns.campaign_sites[eid] = region_id
		"stop":
			ns.campaign_running.erase(eid)
			ns.campaign_sites.erase(eid)

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
		"effort_id": eid,
		"op": campaign_op,
		"applied": true,
		"refused": false,
		"months_left": months_to_election(state, ns),
		"region_id": region_id if campaign_op == "start" else String(ns.campaign_sites.get(eid, "")),
	}
	ns.last_campaign_result = result
	return result
