extends RefCounted

## Sectoral investment: state money pointed at one of the three sectors, an
## accumulated capital stock, and the one channel through which it reaches the
## economy. Built at V1.6e, the fifth session of the V1.6 block and the block's
## only new player verb.
##
## The model and every constant's rationale is docs/sector-model.md;
## src/sim/investment_constants.gd is the values.
##
## THE LANDING SITE IS THE SECTOR'S OWN TREND RATE, NOT `sector_output`, and
## docs/tiers/v1.md section 6 asks for the second. It cannot have it:
## Economy._apply_growth_to_sectors() reconciles the three sectors against the
## month's GDP target EXACTLY, so an absolute injection into sector_output is
## cancelled by the cyclical residual inside the same tick and survives only as a
## composition change. What has room is the rate -- the slot Trade.sector_shift()
## already occupies -- and the difference between the two is the whole of why this
## is a lever rather than a reallocation:
##
##     A TRADE SHIFT MUST SUM TO ZERO. AN INVESTMENT SHIFT MUST NOT.
##
## sector_trend_shift() is therefore read at TWO sites in economy.gd, and both are
## required. Inside _apply_growth_to_sectors() it moves each sector's own rate;
## inside trend_pct() it is added SHARE-WEIGHTED, which is what makes `after_trend`
## exactly the nation's trend and stops the residual eating the level effect. A
## term added to only the first would move the mix and nothing else.
##
## IT MOVES POTENTIAL, WHERE V1.6a's CYCLE DELIBERATELY DOES NOT. Trend enters
## `potential_gdp_eur_bn *= monthly_factor(trend)`, so investment raises the level
## the economy is heading for. A business cycle is by definition output AROUND
## potential; public investment is a change to potential itself. The two terms are
## on opposite sides of that distinction and that is the cleanest statement of what
## each one is.
##
## THERE IS NO EMPLOYMENT TERM, and the row states that as a prohibition where it
## is a CONSEQUENCE. V1.4b earned its jobs price because jobs-per-share is FIRM
## content and no sector lever can express it -- but this model goes further:
## Economy._update_unemployment() reads Okun on `growth - trend`, and structural
## unemployment reads only the income-tax wedge, `law_structural_offset_pct` and
## `firm_jobs_offset_pct`. A term that raises TREND therefore has no permanent
## employment effect available to it at all. There is a transitional one -- a
## rising potential opens a negative output gap, GAP_CLOSE pushes growth above
## trend, and Okun bites while it closes -- and it closes.
##
##     SECTORAL INVESTMENT BUYS OUTPUT AND, IN THE LONG RUN, NO JOBS.
##
## Recorded rather than smoothed, and tests/test_sectors.gd asserts this file
## writes nothing on the employment path.
##
## IT REACHES THE WHOLE SECTOR, INCLUDING THE UNNAMED RESIDUAL, and that is the line
## docs/tiers/v1.md section 6 says this bullet must not cross. V1.4b's regulation reads
## only the NAMED firms, so a sector a quarter named is a quarter as regulable --
## docs/companies-model.md records that as a structural bound rather than a rounding
## error, and it is one of the two things that keep a sector burden from being this
## lever with a minus sign. sector_trend_shift() reads `ns.sector_output` and nothing
## else, so a nation with no data/companies/ file can still be invested in, and
## tests/test_sectors.gd measures it by emptying the register outright.
##
## The other of the two is the jobs price, and this file does not have one -- see above.
## Both differences hold, which is what the row asked for.
##
## TAKES NO LOADER for the tick, where companies.gd does. A firm's baseline is
## authored content, so that register needs the loader to read it; a sector's
## register is keyed by the three sector names economy_constants.SECTOR_TREND
## already fixes, and the capital stock IS the whole of the state. Only the verb
## reads content, and only the verb takes the action list.
##
## Preloads its constants and economy_constants.gd. A leaf.

const K = preload("res://src/sim/investment_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")


## Seeds the live register: every sector starts with no programme and no capital.
## Called from GameState._build_nation(), in Companies.init_nation()'s slot.
##
## Every nation gets all three entries rather than only the player, unlike
## data/companies/, because the three sectors are model constants rather than
## content -- there is no file that could be absent. What keeps the nine inert is
## that nothing ever writes an intensity for them.
static func init_nation(ns) -> void:
	ns.sector_investment = {}
	for sector in EK.SECTOR_TREND.keys():
		ns.sector_investment[sector] = {"intensity": 0.0, "capital": 0.0}
	ns.investment_bill_pct_gdp = 0.0


## Runs in src/ui/main.gd's order beside Companies, and Budget.project() runs it in
## the same slot. The bill therefore lags the economy by a month exactly as the
## subsidy bill, the deployment bill and the bloc transfer do, and for the reason
## budget.gd's comment gives: `deficit_pct_gdp` is one of this verb's own
## precondition fields, so a bill that widened the deficit inside the month would
## close a loop.
static func tick_month(state) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		var ns = state.nations[id]
		_tick_capital(ns)
		ns.investment_bill_pct_gdp = bill_pct_gdp(ns)


# --- Reading one sector ---------------------------------------------------------

static func intensity_of(ns, sector: String) -> float:
	var entry = ns.sector_investment.get(sector)
	return float(entry.get("intensity", 0.0)) if entry != null else 0.0


static func capital_of(ns, sector: String) -> float:
	var entry = ns.sector_investment.get(sector)
	return float(entry.get("capital", 0.0)) if entry != null else 0.0


static func programme_count(ns) -> int:
	var n := 0
	for sector in ns.sector_investment.keys():
		if intensity_of(ns, String(sector)) > 0.0:
			n += 1
	return n


# --- The stock ------------------------------------------------------------------

## A first-order lag toward the standing intensity, normalised so full intensity
## converges on exactly 1.0.
##
## BOUNDED BY CONSTRUCTION rather than by a clamp, which is V1.6a's property in a
## second place: intensity is bounded by MAX_INVESTMENT_INTENSITY at load, the lag
## is a convex combination, so capital can never leave [0, 1] and there is no value
## anybody can set wrong. A clamp here would be a guard rail guarding arithmetic.
##
## _update_potential_shift()'s shape and deliberately NOT Society.capability_step()'s:
## that one converges on a target the player sets with a SLIDER every month, where
## this converges on a standing commitment made once by a verb.
static func _tick_capital(ns) -> void:
	for sector in ns.sector_investment.keys():
		var entry: Dictionary = ns.sector_investment[sector]
		var target := float(entry.get("intensity", 0.0))
		var capital := float(entry.get("capital", 0.0))
		entry["capital"] = capital + (target - capital) * K.CAPITAL_CONVERGENCE / 12.0


# --- The channel into the economy ------------------------------------------------

## Points added to each sector's own annual trend growth. Read by economy.gd at the
## two sites this file's header names.
##
## SCALED AS A SET when the national bound binds, never clipped per sector: the two
## readers must agree exactly, and clipping one sector's entry after the weighted
## sum has been taken would leave trend_pct() and _apply_growth_to_sectors() with
## different numbers. Scaling preserves the mix and only shortens the vector.
##
## Reads EXACTLY 0.0 for every sector of every nation in every month in which no
## investment action has ever executed. That is not an accident of the arithmetic
## -- it is the property tests/test_sectors.gd asserts with exact equality, and the
## reason the balance harness can go bit-identical across every existing regime
## with this whole layer live. firm_impulse_pct()'s property one block later.
static func sector_trend_shift(ns) -> Dictionary:
	var out := {}
	var weighted := 0.0
	var gdp: float = ns.gdp_eur_bn
	for sector in EK.SECTOR_TREND.keys():
		var shift: float = K.SECTOR_TREND_BETA * capital_of(ns, sector)
		out[sector] = shift
		if gdp > 0.0:
			weighted += shift * float(ns.sector_output.get(sector, 0.0)) / gdp

	var magnitude: float = absf(weighted)
	if magnitude > K.SECTOR_TREND_MAX_PCT:
		var scale: float = K.SECTOR_TREND_MAX_PCT / magnitude
		for sector in out.keys():
			out[sector] = float(out[sector]) * scale
	return out


## What this layer adds to the NATION'S trend, %/yr -- the share-weighted sum of
## the three shifts above. Split out rather than recomputed at the call site,
## because two copies of a weighted sum is one formula with two writers, which is
## the discipline `share`, `state_share`, `regulation_burden` and `gini_index` are
## each held to.
static func national_trend_shift_pct(ns) -> float:
	if ns.gdp_eur_bn <= 0.0:
		return 0.0
	var shifts := sector_trend_shift(ns)
	var total := 0.0
	for sector in shifts.keys():
		total += float(shifts[sector]) * float(ns.sector_output.get(sector, 0.0)) / ns.gdp_eur_bn
	return total


## Points of GDP per year. Read by Budget.recompute() as a computed spending line,
## NOT as a sixth entry in economy_constants.SPENDING_KEYS -- that list is keyed
## 1:1 to cabinet portfolios, so a sixth line is a sixth minister, and
## docs/tiers/v1.md section 6 rules it out. The fourth line to take this route,
## after V1.3d's bloc transfer, V1.3g's deployment bill and V1.4a's subsidy bill.
##
## Priced on the STANDING INTENSITY and not on the accumulated capital, which is
## the honest way round: the money is what the treasury pays each month, and the
## capital is what it has bought. A bill priced on the stock would keep charging
## for something already built and would make a withdrawal cost more than it saves
## for years.
##
## *** SCALED BY THE SECTOR'S OWN SHARE OF GDP, AND THAT IS THE PROBE'S CORRECTION
## RATHER THAN THE ORIGINAL DESIGN. *** The first version charged a flat fee whatever
## the sector, and tools/investment_probe.gd table (e) measured what that bought:
## backing French services moves growth 0.4865 points and backing French agriculture
## moves it 0.0077 -- a spread of sixty-three to one against an identical price. Same
## money, less of everything: the strictly-dominated shape this project has now caught
## six times, and the first time it has appeared in a PRICE rather than in an effect.
##
## The fix moves the model and adds NO CONSTANT, which is
## companies_constants.RIVAL_FLOOR_FRACTION's correction in a new place. What it costs
## to move a sector is proportional to how much sector there is, so the return per euro
## is the same wherever it is spent and WHICH SECTOR goes back to being a question about
## composition and politics -- which is what a lever pointed at a sector is for.
##
## It also DELETED a constant. The three shares sum to exactly 1.0 by
## Economy._apply_growth_to_sectors()'s own reconciliation, so the whole bill is bounded
## above by INVESTMENT_COST_PCT_GDP itself -- every sector at full intensity is one
## sector's worth of the economy. A clamp on top of that would be a guard rail guarding
## arithmetic, so INVESTMENT_BILL_MAX_PCT_GDP was deleted rather than left unused:
## U6a's treatment of the day budget, and the capital stock's own
## bounded-by-construction property one function up.
static func bill_pct_gdp(ns) -> float:
	if ns.gdp_eur_bn <= 0.0:
		return 0.0
	var bill := 0.0
	for sector in ns.sector_investment.keys():
		var share: float = float(ns.sector_output.get(sector, 0.0)) / ns.gdp_eur_bn
		bill += K.INVESTMENT_COST_PCT_GDP * intensity_of(ns, String(sector)) * share
	return bill


# --- The verb --------------------------------------------------------------------

## Which actions may be used right now. Companies.available()'s shape, minus the
## company id: an investment action names its own sector, so there is no target to
## pass. No cooldown, for the reason a subsidy has none -- a programme is STANDING
## state, so `investment_active` gates it directly and a cooldown register beside
## that would be two gates on one fact.
static func available(state, ns, all_actions: Array) -> Array:
	var out: Array = []
	for action in all_actions:
		if action.id == "":
			continue
		if _preconditions_met(state, ns, action):
			out.append(action)
	return out


static func _preconditions_met(state, ns, action) -> bool:
	var sector := String(action.effects.get("investment", {}).get("sector", ""))
	for cond in action.preconditions:
		var actual: float = _read_field(state, ns, cond["field"], sector)
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


## `investment_active` is about the sector the action names; everything else is the
## acting nation's own state. Companies._read_field()'s split, and it is here for
## the same reason: a precondition list mixes both freely and the content should not
## have to know which kind a field is.
static func _read_field(state, ns, field: String, sector: String) -> float:
	match field:
		"investment_active": return 1.0 if intensity_of(ns, sector) > 0.0 else 0.0
		"investment_count": return float(programme_count(ns))
		"deficit_pct_gdp": return ns.deficit_pct_gdp
		"debt_to_gdp_pct": return ns.debt_to_gdp_pct()
		"unemployment_pct": return ns.unemployment_pct
		"overall_approval_pct": return ns.overall_approval_pct
		_:
			push_error("investment: unknown precondition field '%s'" % field)
			return 0.0


## The player command: set or clear the standing programme, pay the domestic price,
## and record the result for the panel to read. Companies.execute()'s shape.
##
## IT DOES NOT GO THROUGH Budget.commit(), AND THAT IS DELIBERATE RATHER THAN
## CONVENIENT. docs/tax-model.md section 11 records a live bug: budget_panel.gd
## refreshes from a `_pending` captured in setup(), so anything that commits a
## budget outside that panel's own sliders leaves it stale and offering to undo the
## commit. The obvious alternative shape for this lever -- three more sliders on the
## budget panel -- walks straight into it. Writing an own register and letting the
## cost arrive as a computed line means this verb cannot meet that bug at all.
##
## Refuses rather than half-applies when the action is not currently available, so
## a UI offering a stale button cannot produce the effect the precondition exists to
## prevent.
static func execute(state, ns, all_actions: Array, action) -> Dictionary:
	var sector := String(action.effects.get("investment", {}).get("sector", ""))
	if not available(state, ns, all_actions).has(action) or not ns.sector_investment.has(sector):
		var refused := {
			"action_id": action.id,
			"sector": sector,
			"applied": false,
			"refused": true,
		}
		ns.last_investment_result = refused
		return refused

	var terms: Dictionary = action.effects.get("investment", {})
	var entry: Dictionary = ns.sector_investment[sector]
	var before := float(entry.get("intensity", 0.0))

	match String(terms.get("op", "")):
		"invest": entry["intensity"] = float(terms.get("intensity", 0.0))
		"withdraw": entry["intensity"] = 0.0

	for bloc_id in action.effects.get("bloc_offset", {}).keys():
		# NOT clamped here, and that is a constraint rather than an oversight: this
		# file is a LEAF, its test pins the exact set of preloads it may have, and
		# legislature_constants.gd -- where BLOC_OFFSET_MIN/MAX live -- is not in it.
		# Clamping locally would mean either breaking that property or writing the
		# bound down a second time, and a second copy of a bound is how the two stop
		# agreeing. The V2.8 review clamped the three writers that CAN reach the
		# constant (campaign.gd, companies.gd, energy.gd); closing these two wants the
		# bound moved to a home all five can see, which is a change with a blast radius
		# rather than a line.
		ns.bloc_offset[bloc_id] = (
			float(ns.bloc_offset.get(bloc_id, 0.0))
			+ float(action.effects["bloc_offset"][bloc_id])
		)

	var result := {
		"action_id": action.id,
		"action_name": action.action_name,
		"sector": sector,
		"applied": true,
		"refused": false,
		"intensity_before": before,
		"intensity_after": float(entry["intensity"]),
		"capital": float(entry.get("capital", 0.0)),
	}
	ns.last_investment_result = result
	return result
