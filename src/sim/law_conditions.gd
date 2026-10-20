extends RefCounted

## The law precondition reader: a {field, op, value} triple against a nation's own
## state. Moved whole out of legislature.gd at V5.0d -- it reads nothing of the
## legislature, and the size ratchet asked for a split -- and still reached through
## Legislature.preconditions_met() / read_field(), the surface every caller names.

const OrgsK = preload("res://src/sim/orgs_constants.gd")


## Public since V1.8: an event carries the same {field, op, value} triple against the
## same whitelist, so it evaluates them through the same function rather than through a
## copy. The list legislature_constants.gd and read_field() already spell out twice does
## not need a third reader spelling it out a fourth time.
static func preconditions_met(ns, conditions: Array) -> bool:
	for cond in conditions:
		var actual: float = read_field(ns, cond["field"])
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


static func read_field(ns, field: String) -> float:
	match field:
		"debt_to_gdp_pct": return ns.debt_to_gdp_pct()
		"unemployment_pct": return ns.unemployment_pct
		"deficit_pct_gdp": return ns.deficit_pct_gdp
		"overall_approval_pct": return ns.overall_approval_pct
		"growth_annual_pct": return ns.growth_annual_pct
		"terms_served": return float(ns.terms_served)
		"unrest_pct": return ns.unrest_pct
		"co2e_per_capita_t": return ns.co2e_per_capita_t
		"eu_member": return 1.0 if ns.orgs.has(OrgsK.UNION_ORG_ID) else 0.0
		# V1.5c added the unrest_pct entry and legislature_constants.PRECONDITION_FIELDS in
		# two separate edits, and the suite caught the gap between them: the whitelist
		# admits a field and this match decides what it means, so THE LIST EXISTS TWICE
		# and a session can add half of it. Not merged here -- src/core/law.gd validates
		# against the constant at LOAD time and this runs per frame, so the constant has
		# to be a plain array -- but recorded, because the next field added will hit it.
		_:
			push_error("legislature: unknown precondition field '%s'" % field)
			return 0.0
