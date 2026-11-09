extends RefCounted

## V5.3 b (docs/design/v5.3-ab.md 4.4, the parent's ruling on B4): how big a law is, and a
## grade chosen at the proposal. Forty lycees and four hundred must not divide alike, and
## must not cost alike. A magnitude is optional data on a row: {value, reference, unit},
## read as data and never per law id.
##
## A grade multiplies the law's BUDGET effects and its magnitude, linearly, on a copy. Its
## other effects (a bloc's offset, society, a sector's burden, growth, unemployment) follow it
## DOWN and not up, by the parent's second ruling: four hundred lycees cost ten times forty and
## move a bloc as forty do, and four lycees cost and move a tenth. The first ruling left them
## whole both ways, which made a bill graded down a dominant line: a tenth of the cost, all of
## the effect. Institutional terms are set values, not quantities, and stay.

const LK = preload("res://src/sim/legislature_constants.gd")

const FIELDS := ["value", "reference", "unit"]
## Optional: the largest size, in the row's own unit, the law may be tabled at. A row whose
## grades run past what the quantity can be (200 % of the seats) names its ceiling here.
const CEILING := "max"
## The effects a grade multiplies: per line or per tax, and the one scalar.
const BUDGET_MAPS := ["spending_pct_gdp", "tax_rates_pct"]
const BUDGET_SCALAR := "other_revenue_pct_gdp"
## The effects that follow a grade below 1 only.
const OTHER_MAPS := ["bloc_offset", "society"]
const OTHER_SCALARS := ["structural_unemployment_pct", "potential_growth_pct"]


## A row's magnitude, {} when it has none. `max` is optional. A constitutional law has none: a grade has no
## road on one (propose() refuses it on the referendum route, and an amendment's terms are
## not a quantity).
static func parse(d: Dictionary, law_id: String, constitutional: bool, filename: String, errors: Array[String]) -> Dictionary:
	if not d.has("magnitude"):
		return {}
	var m = d["magnitude"]
	var bad := "%s: law '%s' field 'magnitude' must be {value > 0, reference > 0, unit, optional max >= reference}" % [filename, law_id]
	if constitutional:
		errors.append("%s: law '%s' is constitutional and takes no magnitude" % [filename, law_id])
		return {}
	if typeof(m) != TYPE_DICTIONARY or not (m as Dictionary).has_all(FIELDS) 			or (m as Dictionary).size() != FIELDS.size() + (1 if (m as Dictionary).has(CEILING) else 0):
		errors.append(bad)
		return {}
	if not typeof(m["value"]) in [TYPE_FLOAT, TYPE_INT] or not typeof(m["reference"]) in [TYPE_FLOAT, TYPE_INT] \
			or typeof(m["unit"]) != TYPE_STRING or float(m["value"]) <= 0.0 or float(m["reference"]) <= 0.0 or String(m["unit"]) == "":
		errors.append(bad)
		return {}
	var out := {"value": float(m["value"]), "reference": float(m["reference"]), "unit": String(m["unit"])}
	if m.has(CEILING):
		if not typeof(m[CEILING]) in [TYPE_FLOAT, TYPE_INT] or float(m[CEILING]) < float(m["reference"]):
			errors.append(bad)
			return {}
		out[CEILING] = float(m[CEILING])
	return out


## How many times its reference size the law now is; 1 for a law with no magnitude.
static func ratio(law) -> float:
	if law.magnitude.is_empty():
		return 1.0
	return float(law.magnitude["value"]) / float(law.magnitude["reference"])


## Whether this law may be tabled at this grade: it has a size, the grade is inside the
## bounds, the size is at or under the row's ceiling, and it does not go to the country (a referendum settles by the law's id).
static func may_grade(law, scale: float, referendum: bool) -> bool:
	if law.magnitude.is_empty() or referendum or scale < LK.GRADE_SCALE_MIN or scale > LK.GRADE_SCALE_MAX:
		return false
	return not law.magnitude.has(CEILING) or float(law.magnitude["value"]) * scale <= float(law.magnitude[CEILING]) + 0.000001


## The grades the picker offers on a row: the legal ones, minus a chip whose size would read
## "0.0" (below half a tenth of its unit). The row's own size is always there.
static func offered(law) -> Array:
	var out := []
	for step in LK.GRADE_STEPS:
		if is_equal_approx(float(step), 1.0) or (may_grade(law, float(step), false) and float(law.magnitude["value"]) * float(step) >= 0.05):
			out.append(float(step))
	return out


## The law at a grade: the same object at 1, so an ungraded road pays for no copy and is
## the same law, byte for byte, and at a row with no size, which a saved grade can outlive
## across a content edit. Never touches the loader's row.
static func scaled(law, scale: float):
	if scale == 1.0 or law.magnitude.is_empty():
		return law
	var out = copy(law)
	out.magnitude["value"] = float(law.magnitude["value"]) * scale
	for key in BUDGET_MAPS:
		for line in (out.effects.get(key, {}) as Dictionary):
			out.effects[key][line] = float(out.effects[key][line]) * scale
	if out.effects.has(BUDGET_SCALAR):
		out.effects[BUDGET_SCALAR] = float(out.effects[BUDGET_SCALAR]) * scale
	if scale < 1.0:
		for key in OTHER_MAPS:
			for line in (out.effects.get(key, {}) as Dictionary):
				out.effects[key][line] = float(out.effects[key][line]) * scale
		for key in OTHER_SCALARS:
			if out.effects.has(key):
				out.effects[key] = float(out.effects[key]) * scale
		if out.effects.has("company"):
			out.effects["company"]["burden"] = float(out.effects["company"]["burden"]) * scale
	return out


static func copy(law):
	var out = law.get_script().new()
	for property in law.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.set(property["name"], law.get(property["name"]))
	out.effects = law.effects.duplicate(true)
	out.magnitude = law.magnitude.duplicate(true)
	return out


## What the law costs the budget, % of GDP, at its grade: spending less other revenue, at
## least 0. A tax rate has no yield without the economy, so a rate is not counted: the
## limit of this reading, and a tax bill reads no cost term.
static func net_cost_pct_gdp(law) -> float:
	var cost := -float(law.effects.get(BUDGET_SCALAR, 0.0))
	for line in (law.effects.get("spending_pct_gdp", {}) as Dictionary):
		cost += float(law.effects["spending_pct_gdp"][line])
	return maxf(0.0, cost)
