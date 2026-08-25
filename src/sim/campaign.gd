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
## Preloads its constants and opinion_constants only. A leaf: no elections.gd (which
## reads this register rather than being called by it), no media.gd, no opinion.gd.

const K = preload("res://src/sim/campaign_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const ElectionK = preload("res://src/sim/election_constants.gd")


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
	ns.campaign_bill_pct_gdp = 0.0


## Accrue, then price -- or clear, if the run-up is over.
##
## Runs in src/ui/main.gd's order after Budget.tick_month() and before
## Elections.tick_month(), and Budget.project() runs it in the same slot. The bill
## therefore lags the economy by a month exactly as the subsidy bill, the deployment
## bill, the bloc transfer, the investment bill and the project bill do, and for the
## reason budget.gd's comment gives: `deficit_pct_gdp` is one of this verb's own
## precondition fields, so a bill that widened the deficit inside the month would
## close a loop.
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
		if not is_open(state, ns):
			_clear(ns)
			continue
		_accrue(ns, terms)
		ns.campaign_bill_pct_gdp = bill_pct_gdp(ns, loader)


## One month of every running effort, onto the accumulator. Sorted, because a
## Dictionary's key order is insertion order and two runs that reached the same state
## by different routes must tick alike.
static func _accrue(ns, terms: Dictionary) -> void:
	var running: Array = ns.campaign_running.duplicate()
	running.sort()
	for eid in running:
		var mobilisation: Dictionary = terms.get(String(eid), {}).get("mobilisation", {})
		var blocs: Array = mobilisation.keys()
		blocs.sort()
		for bloc in blocs:
			ns.campaign_mobilisation[bloc] = clampf(
				float(ns.campaign_mobilisation.get(bloc, 0.0)) + float(mobilisation[bloc]),
				-K.MOBILISATION_MAX, K.MOBILISATION_MAX
			)


## The run-up is over. Everything goes: the efforts are out of the field, the
## mobilisation is spent at the ballot box, and the bill stops.
##
## Assigned rather than cleared in place, because NationState.copy() duplicates these
## and a shared reference surviving a Budget.project() would let a projection write
## the live register -- docs/tax-model.md section 11's live bug, avoided by shape.
static func _clear(ns) -> void:
	ns.campaign_running = []
	ns.campaign_started = []
	ns.campaign_mobilisation = {}
	ns.campaign_bill_pct_gdp = 0.0


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


# --- The bill -------------------------------------------------------------------------

## Points of GDP per year, the sum of every running effort's own authored cost. Read by
## Budget.recompute() as a computed spending line, NOT as a sixth entry in
## economy_constants.SPENDING_KEYS -- that list is keyed 1:1 to cabinet portfolios, so a
## sixth line is a sixth minister, and docs/tiers/v1.md section 6 rules it out. The
## SIXTH line to take this route, after V1.3d's bloc transfer, V1.3g's deployment bill,
## V1.4a's subsidy bill, V1.6e's investment bill and V1.6f's project bill.
##
## THE SECOND BILL IN THIS PROJECT THAT STOPS, and it stops harder than V1.6f's. A
## project's bill ends when the work does, on a date the player chose by choosing the
## project. This one ends on a date the constitution chose, and the player cannot move
## it -- which is why the decision it poses is about TIMING and the project's is about
## SIZE.
##
## NOT SCALED BY ANYTHING. V1.6e's bill had to be scaled by the sector's share of GDP
## because one flat fee bought a 63:1 spread across three sectors. It does not transfer:
## here the price and the reach are BOTH authored per effort, so there is no shared
## constant that could make one row dominate another by arithmetic rather than by
## choice. tools/campaign_probe.gd checks that no authored effort is dominated rather
## than assuming it.
static func bill_pct_gdp(ns, loader) -> float:
	var terms := _terms_by_effort(loader)
	var bill := 0.0
	for eid in running(ns):
		bill += float(terms.get(eid, {}).get("cost_pct_gdp", 0.0))
	return bill


## effort id -> the authored {cost_pct_gdp, mobilisation, effort_name} of its `start`
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
static func execute(state, ns, all_actions: Array, action) -> Dictionary:
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

	match campaign_op:
		"start":
			ns.campaign_running.append(eid)
			ns.campaign_started.append(eid)
		"stop":
			ns.campaign_running.erase(eid)

	for bloc_id in action.effects.get("bloc_offset", {}).keys():
		ns.bloc_offset[bloc_id] = (
			float(ns.bloc_offset.get(bloc_id, 0.0))
			+ float(action.effects["bloc_offset"][bloc_id])
		)

	var result := {
		"action_id": action.id,
		"action_name": action.action_name,
		"effort_id": eid,
		"op": campaign_op,
		"applied": true,
		"refused": false,
		"months_left": months_to_election(state, ns),
	}
	ns.last_campaign_result = result
	return result
