extends RefCounted

## Infrastructure projects: a discrete, dated, expensive commitment that bills every
## month it is under construction and pays once, permanently, when it finishes.
## Built at V1.6f, the sixth session of the V1.6 block and the last one in it.
##
## The model and every number's rationale is docs/projects-model.md;
## src/sim/projects_constants.gd is the bounds and data/project-actions/ is the
## content -- which is where the cost, the duration and the payoff live, because
## this file ships no constant for any of the three.
##
## ============================================================================
## THE FOUR BOUNDARY CHECKS, SETTLED BEFORE ANY BAND WAS WRITTEN
## ============================================================================
## docs/credit-model.md's rule: a band is a test of SIZE, not of legitimacy. V1.6e
## found docs/tiers/v1.md section 6's named landing site structurally unavailable and
## would not have if it had banded first.
##
## (B1) IS GameState.appointments THIS SCHEDULER UNDER ANOTHER NAME? NO.
##      src/sim/calendar.gd is a register of DEFERRED COMMANDS: due() fires an entry
##      once, main.gd runs a verb that already exists, Calendar.cancel() is free and
##      leaves no trace, and identity is verb_key() -- verb-shaped, one in flight per
##      verb. A project is a COMMITMENT IN FLIGHT: it bills every month, it can be
##      abandoned part-built, and half a motorway is not free. calendar.gd also
##      preloads no other system BY DESIGN (docs/cabinet-model.md's orchestrator
##      rule, asserted by tests/test_calendar.gd reading the file), and a scheduler
##      that owned a bill and a payoff would be exactly what that rule forbids.
##
##      WHAT IS REUSED IS THE SURFACE, AND IT COST NOTHING. Calendar.fixed_dates()
##      gains one row per project under construction, so the diary shows completion
##      dates for free -- which is what U6a exists for -- and it needs no preload,
##      because that function reads plain fields off NationState.
##
##      AND THE REGISTER COUNTS MONTHS REMAINING, NOT DATES. Every other countdown in
##      this project already does (diplo_cooldown_months, dissolution_lockout_remaining,
##      bloc.months_to_next), and Calendar._fixed_in() already converts one into a
##      date. So this file does NO DATE ARITHMETIC AT ALL and cannot disagree with the
##      clock about when a thing lands.
##
## (B2) IS THE PAYOFF A SECOND economy_constants.INFRA_BETA? NO -- AND IT IS NOT A
##      THIRD TREND TERM EITHER, WHICH IS THE SHARPER HALF.
##      Against src/core/law.gd's criterion for the three existing anti-double-count
##      pairs -- same act, same landing site AND same units:
##
##        act          INFRA_BETA reads a player-set SPENDING RATE
##                     this reads a DISCRETE DATED COMMITMENT
##        landing site the target of Economy._update_potential_shift()   [same]
##        units        points of GDP of annual spending
##                     a completed lump, in points of trend
##
##      One of three, so not a pair. And the shape already exists:
##      ns.law_potential_target_pct is a permanent accumulator with its own bound,
##      added to that same target, written by Legislature.apply() when a law passes.
##      A completed project is that shape exactly -- a one-time act producing a
##      permanent addend -- so this is the SIXTH writer of that target rather than a
##      new quantity reaching trend.
##
##      That is why economy_constants.SHIFT_MAX_PCT's comment, which V1.6e had to
##      amend, needs no second amendment: the quantity that touches Economy.trend_pct()
##      is still `potential_shift_pct` and still carries exactly one bound.
##
## (B3) IS "SLOW" ALREADY SPENT? YES, HALF OF IT, AND THE BAND IS WRITTEN ON THE
##      COMBINED FIGURE BECAUSE OF IT. economy_constants.SHIFT_ADJUST is a five-year
##      lag on that target, so a build of N months followed by a five-year lag is two
##      answers to docs/brainstorm/mechanics-economy.md's one word. tools/projects_probe.gd
##      bands the t90 from COMMIT TO FULL PAYOFF, never the build alone, and its named
##      escalation trigger is that if no build length puts the payoff inside two terms
##      the response is to shorten the BUILD -- never SHIFT_ADJUST, which would
##      re-baseline every economy constant measured since S4.
##
## (B4) IS THERE AN EMPLOYMENT TERM TO PRICE? NO, AND NOT BY PROHIBITION.
##      V1.6e's finding one step further out: the payoff raises TREND,
##      Economy._update_unemployment() reads Okun on `growth - trend`, and
##      structural_unemployment_pct reads only the income-tax wedge,
##      law_structural_offset_pct and firm_jobs_offset_pct. A term that raises trend
##      has no permanent employment channel available to it, so there is nothing to
##      band. tests/test_projects.gd pins it bit-identically and reads this file to
##      fail if it ever reaches the employment path.
##
## ============================================================================
## A PROGRAMME YOU CAN STOP; A PROJECT YOU CAN ONLY ABANDON
## ============================================================================
## That is the sharpest difference from V1.6e's sectoral investment and it needs no
## constant. A withdrawn programme leaves 63 % of its capital standing a year later,
## measured; an abandoned project leaves NOTHING -- the money is spent, the payoff is
## zero, and the register forgets the build ever started. There is no partial credit
## because there is no partial motorway in this model, and inventing one would be a
## second stock beside V1.6e's.
##
## THE REGISTER NEVER FORGETS A FINISHED PROJECT, which is what makes `once` and a
## cooldown both unnecessary: `project_started` is a permanent gate, so the content
## needs no flag for it and src/core/project_action.gd carries neither field.
##
## TAKES THE LOADER, WHERE src/sim/investment.gd does not. V1.6e's register is keyed
## by the three sectors economy_constants.SECTOR_TREND fixes and the capital stock IS
## the whole of the state; here the cost and the payoff are AUTHORED, so the register
## carries exactly two keys and the tick has to look the rest up. That is
## src/sim/companies.gd's split, and it is why tests/test_projects.gd asserts a saved
## entry carries no content.
##
## Preloads its constants only. A leaf.

const K = preload("res://src/sim/projects_constants.gd")

## The two keys a register entry may carry. Kept as a constant rather than as a
## comment because tests/test_projects.gd asserts against it and V1.6e's own test
## pinned the same property one session earlier: a later session caching a cost, a
## payoff or a start date in the save turns that assertion red and has to say why.
const ENTRY_KEYS := ["months_left", "done"]


## Seeds the live register: nothing begun and nothing built.
##
## Every nation gets the fields rather than only the player, Investment.init_nation()'s
## call: what keeps the nine inert is that nothing ever executes an action for them,
## and tests/test_projects.gd pins that there is no AI agenda term for this verb --
## docs/defence-model.md's honest limitation and V1.6e's, recorded a third time.
static func init_nation(ns) -> void:
	ns.projects = {}
	ns.project_potential_target_pct = 0.0
	ns.project_bill_pct_gdp = 0.0


## Runs in src/ui/main.gd's order beside Investment, and Budget.project() runs it in
## the same slot. The bill therefore lags the economy by a month exactly as the
## subsidy bill, the deployment bill, the bloc transfer and the investment bill do,
## and for the reason budget.gd's comment gives: `deficit_pct_gdp` is one of this
## verb's own precondition fields, so a bill that widened the deficit inside the month
## would close a loop.
##
## Advance, then complete, then price -- in that order, so a project that finishes
## this month stops billing this month. The alternative charges a president for a road
## that opened.
static func tick_month(state, loader) -> void:
	var terms := _terms_by_project(loader)
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		var ns = state.nations[id]
		_advance(ns, terms)
		ns.project_bill_pct_gdp = bill_pct_gdp(ns, loader)
	# V2.7. WHERE THE PAYOFF SITS, derived rather than stored: the region id is
	# never serialised (tests/test_save_load.gd pins its absence -- a save that
	# carried it could disagree with data/nations/ about where the rail spine is),
	# so the map is rebuilt here from ns.projects, the authored terms and the
	# geometry, once per tick. Economy and Migration read it NEXT month, which is
	# the same one-month lag the national channel already has: a project completed
	# in this function writes project_potential_target_pct now and economy's
	# potential converges toward it from next month on. Budget.project() and the
	# load path rebuild the same map from the same data -- Projects.sited_map().
	state.project_sited_pct = sited_map(state, loader)


## nation id -> {region id -> points of growth per year}, the RAW sited payoffs of
## every completed project. regions.gd does the zero-meaning -- the subtraction
## that keeps the national total untouched is the same rule the mix and network
## terms follow, and it lives where the readers it protects are.
static func sited_map(state, loader) -> Dictionary:
	var out: Dictionary = {}
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		var pct: Dictionary = sited_pct(state.nations[id], loader)
		# Nations hosting nothing are ABSENT rather than present-and-empty, so a
		# fresh state's {} and a re-derived one are structurally equal -- the same
		# property tests/test_save_load.gd's round-trip walk enforces on every
		# field, and the reason a serialised register would be worse than none.
		if not pct.is_empty():
			out[id] = pct
	return out


static func sited_pct(ns, loader) -> Dictionary:
	var out: Dictionary = {}
	for pid in completed(ns):
		var payoff := float(terms_of(loader, String(pid)).get("potential_growth_pct", 0.0))
		if payoff == 0.0:
			continue
		var region_id := site_region(loader, ns.id, String(pid))
		if region_id == "":
			continue
		out[region_id] = float(out.get(region_id, 0.0)) + payoff
	return out


## The region a project's AUTHORED coordinate falls in, or "". Derived on every
## read -- Siting.site()'s rule, and the reason SAVE_VERSION does not move for the
## sited payoff. Hole-aware: a cast over outer rings alone would file Vienna,
## Brussels and Berlin under their hosts, because an enclave's own polygon sits
## inside its host's outer ring and only the host's hole ring says whose it is.
static func site_region(loader, nation_id: String, project_id: String) -> String:
	var cached: Dictionary = _site_cache.get(nation_id, {})
	if cached.has(project_id):
		return String(cached[project_id])
	var region_id := _site_region_uncached(loader, nation_id, project_id)
	cached[project_id] = region_id
	_site_cache[nation_id] = cached
	return region_id

## Content-derived and immutable: the authored coordinate and the committed
## geometry cannot change during a run, so one lookup per (nation, project) is a
## cache and not a second answer.
static var _site_cache: Dictionary = {}


static func _site_region_uncached(loader, nation_id: String, project_id: String) -> String:
	var n = loader.nations.get(nation_id)
	if n == null:
		return ""
	var site = n.project_sites.get(project_id)
	if site == null:
		return ""
	var lon: float = float((site as Vector2).x)
	var lat: float = float((site as Vector2).y)
	var ids: Array = loader.region_rings.keys()
	ids.sort()
	for region_id in ids:
		if _region_contains(loader.region_rings[region_id], lon, lat):
			return String(region_id)
	return ""


## Inside the outer ring of some polygon and inside NONE of its holes. Odd-even
## over every ring of a MultiPolygon is the importer's _point_in_polygon(), stated
## again here because src/ reads it as data and never imports the tool.
static func _region_contains(polygons: Array, lon: float, lat: float) -> bool:
	for polygon in polygons:
		var rings: Array = polygon
		if rings.is_empty():
			continue
		if not _in_ring(rings[0], lon, lat):
			continue
		var holed := true
		for i in range(1, rings.size()):
			if _in_ring(rings[i], lon, lat):
				holed = false
				break
		if holed:
			return true
	return false


static func _in_ring(ring: PackedVector2Array, lon: float, lat: float) -> bool:
	var inside := false
	var n := ring.size()
	if n < 3:
		return false
	var j := n - 1
	for i in n:
		var xi := ring[i].x
		var yi := ring[i].y
		var xj := ring[j].x
		var yj := ring[j].y
		if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
			inside = not inside
		j = i
	return inside


## One month of construction on every project still building, then completion for any
## that ran out. Sorted, because a Dictionary's key order is insertion order and two
## runs that reached the same state by different routes must tick alike.
static func _advance(ns, terms: Dictionary) -> void:
	var keys: Array = ns.projects.keys()
	keys.sort()
	for pid in keys:
		var entry: Dictionary = ns.projects[pid]
		if bool(entry.get("done", false)):
			continue
		var left := int(entry.get("months_left", 0)) - 1
		entry["months_left"] = maxi(left, 0)
		if left > 0:
			continue
		entry["done"] = true
		# The payoff, and the ONE place this module writes anything the economy
		# reads. A completed project is a permanent addend to the target
		# Economy._update_potential_shift() converges toward -- see (B2) above --
		# so it is clamped here on the accumulator exactly as Legislature.apply()
		# clamps law_potential_target_pct, and nothing downstream needs a second bound.
		var payoff := float(terms.get(String(pid), {}).get("potential_growth_pct", 0.0))
		ns.project_potential_target_pct = clampf(
			ns.project_potential_target_pct + payoff,
			-K.PROJECT_POTENTIAL_MAX_PCT, K.PROJECT_POTENTIAL_MAX_PCT
		)


# --- Reading the register --------------------------------------------------------

static func is_started(ns, project_id: String) -> bool:
	return ns.projects.has(project_id)


static func is_done(ns, project_id: String) -> bool:
	var entry = ns.projects.get(project_id)
	return entry != null and bool(entry.get("done", false))


static func is_building(ns, project_id: String) -> bool:
	return is_started(ns, project_id) and not is_done(ns, project_id)


static func months_left(ns, project_id: String) -> int:
	var entry = ns.projects.get(project_id)
	return int(entry.get("months_left", 0)) if entry != null else 0


## How many are under construction right now. The number the content gates on, and
## the reason projects_constants.gd ships no concurrency constant: the ceiling is
## authored per action, which makes it content.
static func building_count(ns) -> int:
	var n := 0
	for pid in ns.projects.keys():
		if is_building(ns, String(pid)):
			n += 1
	return n


## Project ids under construction, sorted, for the panel and for
## Calendar.fixed_dates(). Sorted rather than in insertion order so two saves of the
## same state draw the same list.
static func building(ns) -> Array:
	var out: Array = []
	for pid in ns.projects.keys():
		if is_building(ns, String(pid)):
			out.append(String(pid))
	out.sort()
	return out


static func completed(ns) -> Array:
	var out: Array = []
	for pid in ns.projects.keys():
		if is_done(ns, String(pid)):
			out.append(String(pid))
	out.sort()
	return out


# --- The bill ---------------------------------------------------------------------

## Points of GDP per year, the sum of every building project's own authored cost.
## Read by Budget.recompute() as a computed spending line, NOT as a sixth entry in
## economy_constants.SPENDING_KEYS -- that list is keyed 1:1 to cabinet portfolios, so
## a sixth line is a sixth minister, and docs/tiers/v1.md section 6 rules it out. The
## FIFTH line to take this route, after V1.3d's bloc transfer, V1.3g's deployment
## bill, V1.4a's subsidy bill and V1.6e's investment bill.
##
## NOT SCALED BY ANYTHING, where V1.6e's bill had to be scaled by the sector's share
## of GDP. That correction was for the strictly-dominated shape: one flat fee bought
## a 63:1 spread across three sectors, so the same money bought less of everything.
## It does not transfer, because here the price and the payoff are BOTH authored per
## project and the probe bands the ladder against each other -- there is no shared
## constant that could make one row dominate another by arithmetic rather than by
## choice. tools/projects_probe.gd checks that no authored project is dominated
## rather than assuming it, which is the same test read from the content side.
##
## A FLOW AND NOT A STOCK, and that call decides whether it moves `deficit_pct_gdp`
## inside the month. V1.4c writes debt_eur_bn directly because buying equity swaps
## cash for a SELLABLE ASSET and a capital transaction is not income. Building a road
## is spending: there is nothing at the end of it the treasury can sell, so it is a
## standing rate on the budget for as long as the work lasts and it stops when the
## work does.
static func bill_pct_gdp(ns, loader) -> float:
	var terms := _terms_by_project(loader)
	var bill := 0.0
	for pid in building(ns):
		bill += float(terms.get(pid, {}).get("cost_pct_gdp", 0.0))
	return bill


## project id -> the authored {build_months, cost_pct_gdp, potential_growth_pct} of
## its `start` action. Built from the loader on every call rather than cached on
## NationState, because caching it would put content in the save -- the property
## tests/test_projects.gd pins with ENTRY_KEYS.
static func _terms_by_project(loader) -> Dictionary:
	var out := {}
	if loader == null:
		return out
	for action in loader.project_actions:
		var terms: Dictionary = action.effects.get("project", {})
		if String(terms.get("op", "")) != "start":
			continue
		out[String(terms.get("project_id", ""))] = terms
	return out


## The authored facts about one project, for the panel and the probe. Empty if the
## id names no `start` action.
static func terms_of(loader, project_id: String) -> Dictionary:
	return _terms_by_project(loader).get(project_id, {})


## The NOUN, not the action name. An action name is an imperative -- "Build the
## High-Speed Rail Spine" -- which is right on the button that starts it and wrong
## everywhere the thing itself is named, and the fifteenth screenshot pass found it in
## the diary reading "Opens: Build the High-Speed Rail Spine". Two surfaces, two strings,
## both authored.
static func name_of(loader, project_id: String) -> String:
	var terms := terms_of(loader, project_id)
	return String(terms.get("project_name", project_id))


# --- The verb ---------------------------------------------------------------------

## Which actions may be used right now. Investment.available()'s shape, minus the
## sector: a project action names its own project, so there is no target to pass.
##
## The op's own legality is checked here rather than left to the content, because
## "you may not abandon what you have not begun" and "you may not begin what is
## finished" are properties of the register and not authorial choices. A content file
## still has to say `project_started == 0` if it wants a gate a player can read on the
## button; this is what stops execute() half-applying if it does not.
static func available(state, ns, all_actions: Array) -> Array:
	var out: Array = []
	for action in all_actions:
		if action.id == "":
			continue
		if not _op_legal(ns, action):
			continue
		if _preconditions_met(state, ns, action):
			out.append(action)
	return out


static func _op_legal(ns, action) -> bool:
	var terms: Dictionary = action.effects.get("project", {})
	var pid := String(terms.get("project_id", ""))
	match String(terms.get("op", "")):
		"start": return not is_started(ns, pid)
		"abandon": return is_building(ns, pid)
		_: return false


static func _preconditions_met(state, ns, action) -> bool:
	var pid := String(action.effects.get("project", {}).get("project_id", ""))
	for cond in action.preconditions:
		var actual: float = _read_field(state, ns, cond["field"], pid)
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


## `project_started` and `project_done` are about the project the action NAMES;
## everything else is the acting nation's own state. Investment._read_field()'s split,
## and it is here for the same reason: a precondition list mixes both freely and the
## content should not have to know which kind a field is.
static func _read_field(state, ns, field: String, project_id: String) -> float:
	match field:
		"project_started": return 1.0 if is_started(ns, project_id) else 0.0
		"project_done": return 1.0 if is_done(ns, project_id) else 0.0
		"project_count": return float(building_count(ns))
		"deficit_pct_gdp": return ns.deficit_pct_gdp
		"debt_to_gdp_pct": return ns.debt_to_gdp_pct()
		"unemployment_pct": return ns.unemployment_pct
		"overall_approval_pct": return ns.overall_approval_pct
		_:
			push_error("projects: unknown precondition field '%s'" % field)
			return 0.0


## The player command: begin or abandon a named project, pay the domestic price, and
## record the result for the panel to read. Investment.execute()'s shape.
##
## IT DOES NOT GO THROUGH Budget.commit(), AND THAT IS DELIBERATE RATHER THAN
## CONVENIENT -- V1.6e's escape from docs/tax-model.md section 11's live bug,
## inherited whole. budget_panel.gd refreshes from a `_pending` captured in setup(),
## so anything committing a budget outside that panel's own sliders leaves it stale
## and offering to undo the commit. Writing an own register and letting the cost
## arrive as a computed line means this verb cannot meet that bug at all.
##
## Refuses rather than half-applies when the action is not currently available, so a
## UI offering a stale button cannot produce the effect the precondition exists to
## prevent.
##
## AN ABANDONED PROJECT IS ERASED FROM THE REGISTER RATHER THAN MARKED. The money is
## already spent and cannot come back; what must not survive is a `project_started`
## that reads true forever, because that would make abandonment a way to lock a
## project out of a later term. Calendar.cancel()'s own reasoning -- an act the player
## thought better of leaves no trace -- reached from the opposite direction, since
## here the trace that matters is the one in the budget the player has already paid.
static func execute(state, ns, all_actions: Array, action) -> Dictionary:
	var terms: Dictionary = action.effects.get("project", {})
	var pid := String(terms.get("project_id", ""))
	var project_op := String(terms.get("op", ""))

	if not available(state, ns, all_actions).has(action):
		var refused := {
			"action_id": action.id,
			"project_id": pid,
			"applied": false,
			"refused": true,
		}
		ns.last_project_result = refused
		return refused

	match project_op:
		"start":
			ns.projects[pid] = {
				"months_left": int(terms.get("build_months", 0)),
				"done": false,
			}
		"abandon":
			ns.projects.erase(pid)

	for bloc_id in action.effects.get("bloc_offset", {}).keys():
		ns.bloc_offset[bloc_id] = (
			float(ns.bloc_offset.get(bloc_id, 0.0))
			+ float(action.effects["bloc_offset"][bloc_id])
		)

	var result := {
		"action_id": action.id,
		"action_name": action.action_name,
		"project_id": pid,
		"op": project_op,
		"applied": true,
		"refused": false,
		"months_left": months_left(ns, pid),
	}
	ns.last_project_result = result
	return result
