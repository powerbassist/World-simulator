extends RefCounted

## The roster reads -- which firms content names for a nation. Split out of
## companies.gd at D14 (A'), when the majors memo below met that file's size
## baseline; companies.gd keeps the public names and delegates here, so no
## caller moved.
##
## A leaf: it reads the loader's lists and nothing else, and preloads nothing
## from src/sim.


static func firms_of(loader, nation_id: String) -> Array:
	if loader == null:
		return []
	return loader.companies.get(nation_id, [])


## D14 (A'): the filtered list is remembered per nation against the roster ARRAY it
## came from (is_same) and that array's size, and handed out as a copy.
## companies.gd's seeding and industry.gd's machine each asked for it per nation
## per month, and Industry._bids() for every nation per bid: ~190 ms of a forecast
## refresh measured (the seeding 112 -> 20 ms, the machine's own read 103 -> 7) in a
## scan of ~95 firms for ~6 majors. Content is never mutated; the size
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

