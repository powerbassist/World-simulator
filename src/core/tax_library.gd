extends RefCounted

## V5.3 e: the tax library as one nation reads it (docs/design/finance-bill.md section 9).
##
## `ns.tax_library` holds EVERY kind of data/taxes/ in library order, each row with this
## nation's effective base_share (its override, else the library's). It is content: not
## saved, attached at new game and re-attached at load from the loader the game runs
## with, as GameState.region_graph is. It sits on the nation rather than only on the
## state because every fiscal reader is static and takes a nation (Budget.apply_pending,
## Opinion.issue_satisfaction), and threading the state through each would be a signature
## change at forty sites for a read of static content.
##
## A kind is IN FORCE when the nation's `tax_rates_pct` carries its key; absent, it is
## not, and only the autumn finance bill puts it in force or takes it out (section 5).

const OpinionK = preload("res://src/sim/opinion_constants.gd")


## Every kind, with this nation's overrides applied. A row is copied only when an
## override changes it, so the common case shares the library's own dictionaries.
static func for_nation(taxes: Dictionary, overrides: Dictionary) -> Dictionary:
	var out := {}
	for id in taxes:
		var row: Dictionary = taxes[id]
		if overrides.has(id):
			row = row.duplicate(true)
			row["base_share"] = float(overrides[id])
		out[id] = row
	return out


## The new-game half: the start register and the library, from the nation's file.
static func attach(ns, n, taxes: Dictionary) -> void:
	ns.tax_rates_pct = n.tax_rates_pct.duplicate(true)
	ns.start_tax_rates_pct = ns.tax_rates_pct.duplicate(true)
	ns.tax_library = for_nation(taxes, n.tax_base_share)


## The load half. "" when every nation's kinds in force exist in the library this build
## ships; otherwise the reason the save is refused: a rate with no model behind it reads
## as nothing in revenue, which is the bump rule's "reads as something wrong".
static func reattach(state, loader) -> String:
	for id in state.nations:
		var ns = state.nations[id]
		for key in ns.tax_rates_pct:
			if not loader.taxes.has(key):
				return "%s levies the tax '%s', which this build's data/taxes/ does not define" % [id, key]
		var n = loader.nations.get(id)
		ns.tax_library = for_nation(loader.taxes, n.tax_base_share if n != null else {})
	return ""


## The kinds in force, in library order.
static func in_force(ns) -> Array:
	var ids: Array = []
	for id in ns.tax_library:
		if ns.tax_rates_pct.has(id):
			ids.append(id)
	return ids


## How this nation's kinds differ from the core salience table for one bloc, as
## Opinion.salience_weights() reads it: a core tax issue NOT in force maps to 0.0 (no
## issue, no weight), and a kind in force the core table has no slot for maps to its own
## library weight, carried outside the normalised sum. The parent's ruling 2 (2026-11-14):
## a tax created or abolished costs or frees approval through its own issue only, and
## never re-weights the bloc's other issues. Empty for a nation levying exactly today's
## five, which is every nation the data ships: the weights are then bit-identical.
static func salience_patch(ns, bloc: String) -> Dictionary:
	var patch := {}
	var core: Dictionary = OpinionK.BLOC_SALIENCE_BASE[bloc]
	for id in ns.tax_library:
		var issue := "tax_%s" % id
		if not ns.tax_rates_pct.has(id):
			if core.has(issue):
				patch[issue] = 0.0
		elif not core.has(issue):
			var weight := float((ns.tax_library[id]["bloc_salience"] as Dictionary).get(bloc, 0.0))
			if weight > 0.0:
				patch[issue] = weight
	return patch
