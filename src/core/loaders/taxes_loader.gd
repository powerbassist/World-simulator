extends RefCounted

## V5.3 e: the tax library (docs/design/finance-bill.md section 9). One file per kind
## under data/taxes/<id>.json, each kind's model written once; a nation only says which
## kinds it has in force (the keys of its fiscal.tax_rates_pct) and at what rate, and
## MAY override a kind's base_share for a kind it has in force (the parent's ruling
## 2026-11-14, so a kind whose yield follows each nation's own base still passes the
## yield check on one shared row).
##
## Every row is refused whole on a bad field, never skipped: a kind the loader dropped
## would leave a nation's listed rate with no model behind it, which revenue reads as
## nothing -- the silent half-tax V4.2's computed-line rule exists to prevent.

const Budget = preload("res://src/sim/budget.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

## LIBRARY ORDER IS DATA. Every revenue and opinion sum runs in dictionary order, so
## today's five load first and in today's order (economy_constants' old TAX_KEYS), and
## new kinds follow by file name: that keeps the five's float arithmetic bit-identical
## the day a sixth kind exists (section 9.1).
const FIRST := ["income", "corporate", "vat", "capital_gains", "wealth"]

## The ledger writes a tax as `tax|<id>`, so an id is the pipe-free shape the ledger
## parses (section 9.1).
static var _id_regex := RegEx.create_from_string("^[a-z0-9_]{2,24}$")


static func load_taxes(loader, dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		loader.errors.append("%s: directory not found" % dir)
		return
	var files: Array[String] = []
	for f in da.get_files():
		if String(f).ends_with(".json"):
			files.append(String(f))
	files.sort()
	var rows := {}
	for fname in files:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(fname)))
		if typeof(parsed) != TYPE_DICTIONARY:
			loader.errors.append("taxes/%s: missing or invalid JSON" % fname)
			continue
		var errors: Array[String] = []
		# No duplicate-id check: parse_row refuses a file not named after its kind, and
		# one directory cannot hold two files of one name.
		var row := parse_row(parsed, "taxes/" + fname, errors)
		loader.errors.append_array(errors)
		if errors.is_empty():
			rows[String(row["id"])] = row
	for id in FIRST:
		if rows.has(id):
			loader.taxes[id] = rows[id]
	for id in rows:
		if not loader.taxes.has(id):
			loader.taxes[id] = rows[id]


## One kind, validated. Public so tests/test_tax_library.gd feeds it a bad row with no
## file on disk (the parse_line idiom of domains_loader). {} with errors on a refusal.
static func parse_row(d: Dictionary, fname: String, errors: Array[String]) -> Dictionary:
	var before := errors.size()
	var id := String(d.get("id", ""))
	if _id_regex.search(id) == null:
		errors.append("%s: id '%s' must match [a-z0-9_]{2,24} (the ledger's tax|<id> rule)" % [fname, id])
	elif Budget.COMPUTED_REVENUE_LINES.has(id):
		errors.append("%s: id '%s' is a computed revenue line; a tax there would be overwritten every month" % [fname, id])
	elif fname.get_file().get_basename() != id:
		errors.append("%s: holds kind '%s'; one file per kind, named after it" % [fname, id])
	for key in ["name", "summary", "rate_meaning"]:
		if typeof(d.get(key)) != TYPE_STRING or String(d[key]).strip_edges() == "":
			errors.append("%s: '%s' must be a non-empty string" % [fname, key])
	# Strictly positive where the model divides or multiplies a yield by the field: a zero
	# base is a kind that yields nothing, a zero reference or scale a division by zero.
	for key in ["base_share", "zero_ref_pct", "opinion_scale_pp"]:
		if not _is_num(d.get(key)) or float(d[key]) <= 0.0:
			errors.append("%s: '%s' must be a number above 0" % [fname, key])
	for key in ["erosion", "demand_multiplier"]:
		if not _is_num(d.get(key)) or float(d[key]) < 0.0:
			errors.append("%s: '%s' must be a number of 0 or more" % [fname, key])
	if typeof(d.get("progressive")) != TYPE_BOOL:
		errors.append("%s: 'progressive' must be true or false" % fname)
	var span = d.get("rate_range_pct")
	if typeof(span) != TYPE_ARRAY or (span as Array).size() != 2 or not _is_num(span[0]) \
			or not _is_num(span[1]) or float(span[0]) < 0.0 or float(span[1]) <= float(span[0]):
		errors.append("%s: 'rate_range_pct' must be [low, high] with 0 <= low < high" % fname)
	_check_salience(d, id, fname, errors)
	_check_anchor(d.get("finance_anchor"), fname, errors)
	if errors.size() > before:
		return {}
	var row := d.duplicate(true)
	row["rate_range_pct"] = [float(span[0]), float(span[1])]
	return row


## Every bloc named is a real bloc with a weight of 0 or more, every payer has a weight,
## and a kind the core salience table already carries (today's five) carries exactly
## the table's row. The five's weights stay INSIDE opinion_constants.BLOC_SALIENCE_BASE,
## interleaved with the other issues in an order the float sums depend on; the library
## row is their mirror for the panel, and a mirror that disagrees would show the player
## blocs the model does not charge.
static func _check_salience(d: Dictionary, id: String, fname: String, errors: Array[String]) -> void:
	var salience = d.get("bloc_salience")
	if typeof(salience) != TYPE_DICTIONARY:
		errors.append("%s: 'bloc_salience' must be an object of bloc weights" % fname)
		return
	for bloc in salience:
		if not OpinionK.BLOC_KEYS.has(bloc) or not _is_num(salience[bloc]) or float(salience[bloc]) < 0.0:
			errors.append("%s: bloc_salience.%s must name a bloc and weigh 0 or more" % [fname, bloc])
	var payers = d.get("who_pays")
	if typeof(payers) != TYPE_ARRAY:
		errors.append("%s: 'who_pays' must be a list of blocs" % fname)
	else:
		for bloc in payers:
			if not (salience as Dictionary).has(bloc):
				errors.append("%s: who_pays names '%s' with no bloc_salience weight" % [fname, bloc])
	var issue := "tax_%s" % id
	for bloc in OpinionK.BLOC_KEYS:
		var core: Dictionary = OpinionK.BLOC_SALIENCE_BASE[bloc]
		if core.has(issue) != salience.has(bloc) or (core.has(issue) and float(core[issue]) != float(salience[bloc])):
			if _core_kind(issue):
				errors.append("%s: bloc_salience.%s differs from opinion_constants' core row for %s" % [fname, bloc, issue])


static func _core_kind(issue: String) -> bool:
	for bloc in OpinionK.BLOC_KEYS:
		if (OpinionK.BLOC_SALIENCE_BASE[bloc] as Dictionary).has(issue):
			return true
	return false


static func _check_anchor(anchor, fname: String, errors: Array[String]) -> void:
	if typeof(anchor) != TYPE_DICTIONARY:
		errors.append("%s: 'finance_anchor' must be {up, down}" % fname)
		return
	for side in ["up", "down"]:
		var pos = anchor.get(side)
		if typeof(pos) != TYPE_DICTIONARY or not _is_num(pos.get("economic")) or not _is_num(pos.get("social")):
			errors.append("%s: finance_anchor.%s must carry numeric economic and social" % [fname, side])


static func _is_num(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## The nation half of a nation file's fiscal block, called from Nation.from_dict(): the
## kinds in force and their rates, the base_share overrides, and the autumn month of
## the finance bill. Parsed here, checked against the library in validate_nations()
## once every file is read.
static func read_nation(n, d: Dictionary, fiscal: Dictionary, filename: String, errors: Array[String]) -> void:
	var rates = fiscal.get("tax_rates_pct")
	var shares = fiscal.get("tax_base_share", {})
	var bill = (d.get("government", {}) as Dictionary).get("finance_bill", {})
	if typeof(rates) != TYPE_DICTIONARY or typeof(shares) != TYPE_DICTIONARY or typeof(bill) != TYPE_DICTIONARY:
		errors.append("%s: fiscal.tax_rates_pct, fiscal.tax_base_share and government.finance_bill must be objects" % filename)
		return
	for key in rates:
		if not _is_num(rates[key]):
			errors.append("%s: fiscal.tax_rates_pct.%s must be a number" % [filename, key])
		else:
			n.tax_rates_pct[key] = float(rates[key])
	for key in shares:
		n.tax_base_share[key] = float(shares[key]) if _is_num(shares[key]) else -1.0
	var month = bill.get("autumn_month", 0)
	n.finance_autumn_month = int(month) if _is_num(month) else -1


## Each nation against the library: a kind in force exists, sits inside its range and
## loads in library order; an override names a kind in force and is above 0; the autumn
## month is a month or absent; and the kinds in force explain no more than the nation's
## real revenue, since a negative residual would be revenue from nowhere (section 9.3).
static func validate_nations(loader) -> void:
	for id in loader.nations:
		var n = loader.nations[id]
		var ordered := {}
		var modelled := 0.0
		for key in n.tax_rates_pct:
			if not loader.taxes.has(key):
				loader.errors.append("%s: fiscal.tax_rates_pct.%s is not a kind in data/taxes/" % [id, key])
		for key in loader.taxes:
			if not n.tax_rates_pct.has(key):
				continue
			var span: Array = loader.taxes[key]["rate_range_pct"]
			var rate := float(n.tax_rates_pct[key])
			if rate < float(span[0]) or rate > float(span[1]):
				loader.errors.append("%s: fiscal.tax_rates_pct.%s = %s outside the kind's range %s" % [id, key, rate, span])
			ordered[key] = rate
			modelled += float(n.tax_base_share.get(key, loader.taxes[key]["base_share"])) * rate
		n.tax_rates_pct = ordered
		for key in n.tax_base_share:
			if not ordered.has(key) or float(n.tax_base_share[key]) <= 0.0:
				loader.errors.append("%s: fiscal.tax_base_share.%s must override a kind in force with a share above 0" % [id, key])
		if n.finance_autumn_month < 0 or n.finance_autumn_month > 12:
			loader.errors.append("%s: government.finance_bill.autumn_month must be a month, 1 to 12" % id)
		if modelled > n.tax_revenue_pct_gdp:
			loader.errors.append("%s: the kinds in force yield %.2f%% of GDP at start, above the %.2f%% the nation collects" % [id, modelled, n.tax_revenue_pct_gdp])
