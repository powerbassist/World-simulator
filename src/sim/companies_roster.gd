extends RefCounted

## The roster reads -- which firms content names for a nation, and which of them
## the share pool may move. Split out of companies.gd at D14 (A'), when the
## speedups below met that file's size baseline; companies.gd keeps the public
## names and delegates here, so no caller moved.
##
## A leaf: it reads the loader's lists and, for the pool, one fact of the live
## register (the failed flag), and preloads nothing from src/sim.


static func firms_of(loader, nation_id: String) -> Array:
	if loader == null:
		return []
	return loader.companies.get(nation_id, [])


## D14 (A'): the filtered list is remembered per nation against the roster ARRAY it
## came from (is_same) and that array's size, and handed out as a copy.
## companies.gd's seeding and industry.gd's machine each asked for it per nation
## per month, and Industry._bids() for every nation per bid: ~200 ms of a forecast
## refresh in a scan of ~95 firms for ~6 majors. Content is never mutated; the size
## covers the one fixture that appends a firm to a loaded roster
## (test_companies_tiers), and the copy keeps a caller that sorts or appends from
## writing into the memo.
static var _majors_memo: Dictionary = {}

static func majors_of(loader, nation_id: String) -> Array:
	var firms: Array = firms_of(loader, nation_id)
	var hit = _majors_memo.get(nation_id)
	if hit != null and is_same(hit[0], firms) and int(hit[1]) == firms.size():
		return (hit[2] as Array).duplicate()
	var out: Array = []
	for company in firms:
		if is_major(company): out.append(company)
	_majors_memo[nation_id] = [firms, firms.size(), out.duplicate()]
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


static func firms_in_sector(loader, nation_id: String, sector: String) -> Array:
	var out: Array = []
	for company in firms_of(loader, nation_id):
		if company.sector == sector:
			out.append(company)
	return out


## Companies._tick_shares()'s pool in ONE pass over the roster, where
## firms_in_sector() made one per sector (D14 (A')): [sector -> firm count,
## sector -> live majors in roster order] -- the lists the per-sector scans built.
## The failed flags read up front are the ones the sector loop would read: it
## writes shares, never a flag.
static func share_pool(ns, loader) -> Array:
	var counts := {}
	var live_majors := {}
	for company in firms_of(loader, ns.id):
		counts[company.sector] = int(counts.get(company.sector, 0)) + 1
		# A failed firm is OUT of the pool: its share is 0.0 and stays 0.0.
		# With a retained subsidy it would otherwise regrow share from its
		# rivals' spare every month -- output through the live share,
		# headcount 0 through the failed flag, one register read two ways
		# (the pass-2 ultra's second Important). A rescued firm re-enters
		# here: the flag clears and the next tick prices it alive again.
		# The flag is read as the raw register fact companies.gd's other
		# reads use -- industry.gd's reader is private to the machine,
		# and a sim module preloading its sibling machine for one
		# predicate inverts the two-writers arrangement.
		if not is_major(company):
			continue
		var entry = ns.companies.get(company.id)
		if entry == null or not bool(entry.get("failed", false)):
			if not live_majors.has(company.sector):
				live_majors[company.sector] = []
			live_majors[company.sector].append(company)
	return [counts, live_majors]
