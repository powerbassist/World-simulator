extends RefCounted

## V5.0b: one of DataLoader's per-content loaders. data/companies/: the firm register per nation and the partition checks against the sectors.
##
## Static functions over the loader they fill: DataLoader.load_all() is the one
## orchestrator (a few test entry points delegate here too), every register lives on the loader
## (its public surface did not move), and each function here is the body that
## used to be DataLoader._<name>() verbatim (now <ThisLoader>.<name>), its members read
## through `loader.`.

const CompaniesK = preload("res://src/sim/companies_constants.gd")
const Company = preload("res://src/core/company.gd")


## One data/companies/<NATION>.json per nation, {"companies": [...]}, the same
## shape as data/people/*.json. See docs/companies-model.md.
##
## AN ABSENT FILE IS NOT AN ERROR, where an absent people file is. Every nation
## needs a leader; only a nation somebody can play needs firms, because only a
## player can subsidise one and CompaniesLoader.validate_companies() below refuses content
## nothing can reach. A nation with no file has unpartitioned sectors, which is
## what all ten had before this session -- so the seven that are not yet playable
## keep running the model they always ran.
static func load_companies(loader, nation_id: String, companies_dir: String) -> void:
	var fname := "%s.json" % nation_id
	var path := companies_dir.path_join(fname)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		loader.companies[nation_id] = []
		return

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("companies")) != TYPE_ARRAY:
		loader.errors.append("%s: invalid companies file, expected {\"companies\": [...]}" % fname)
		loader.companies[nation_id] = []
		return

	var raw_list: Array = parsed["companies"]
	if typeof(parsed.get("body", [])) != TYPE_ARRAY:
		loader.errors.append("%s: body must be an array" % fname)
	else:
		raw_list.append_array(parsed["body"])
	var parsed_companies: Array = []
	var per_file_errors: Array[String] = []
	var seen_ids := {}

	for i in raw_list.size():
		var entry = raw_list[i]
		if typeof(entry) != TYPE_DICTIONARY:
			per_file_errors.append("%s: companies[%d] is not an object" % [fname, i])
			continue
		var company = Company.from_dict(entry, i, fname, per_file_errors)
		# Legacy files are allowed to omit tier until A3 regenerates body/chief content.
		if not entry.has("tier") and parsed.has("body"):
			per_file_errors.append("%s: companies[%d] missing tier" % [fname, i])
		elif not entry.has("tier"):
			company.tier = "major"
		if entry.has("tier") and String(entry["tier"]) not in ["major", "body"]:
			per_file_errors.append("%s: companies[%d] tier must be major or body" % [fname, i])
		if company.id == "":
			continue

		# The prefix rule people-model.md argues for, applied to a second register
		# and for a weaker reason honestly stated: a company id is read inside a
		# nation's context today, the way a party id is. It is namespaced anyway
		# because the register is keyed by it in a save and on an appointment entry
		# a later session may well book -- and re-namespacing after that happens is
		# the migration U6b had to perform on three fields.
		if not company.id.begins_with("%s_" % nation_id):
			per_file_errors.append(
				"%s: company id '%s' must begin with '%s_'" % [fname, company.id, nation_id]
			)
		if seen_ids.has(company.id):
			per_file_errors.append("%s: duplicate company id '%s'" % [fname, company.id])
		seen_ids[company.id] = true
		parsed_companies.append(company)

	loader.errors.append_array(per_file_errors)
	loader.companies[nation_id] = parsed_companies


## The cross-file half, and both checks are about content that cannot do anything.
##
## A sector's named shares summing past 1.0 is a partition claiming more than the
## sector holds. A sector holding exactly ONE named firm is subtler and is the
## check worth having: a lone firm has no rival to take share from, so a subsidy
## pointed at it moves nothing at all and the player pays a real bill for it. That
## is docs/tiers/v1.md section 6's "sectoral investment -- a lever pointed at a
## sector" wearing a firm's name, and refusing it at load is what keeps V1.4's
## subsidy and V1.6's sector lever distinguishable. (V4.7a narrowed this: the
## check counts majors AND body, while the share pool is majors-only -- a
## sector with one major plus body passes here and its lone major still has no
## pool rival. The loader cannot express the majors-only form against body
## content, so the invariant is pinned in tests/test_companies_tiers.gd
## instead, where the tier split is visible.)
static func validate_companies(loader) -> void:
	for nation_id in loader.companies.keys():
		var by_sector := {}
		for company in loader.companies[nation_id]:
			if company.sector == "":
				continue
			if not by_sector.has(company.sector):
				by_sector[company.sector] = []
			by_sector[company.sector].append(company)

		# The nation's people, for chief resolution -- built once per nation
		# rather than per firm, the programme-ids idiom PeopleLoader.validate_people uses.
		# id -> person, because the chief check needs the KIND, not just the id.
		var people_by_id := {}
		for person in loader.people.get(nation_id, []):
			people_by_id[person.id] = person

		for company in loader.companies[nation_id]:
			if company.tier == "body" and company.share > CompaniesK.BODY_SHARE_MAX:
				loader.errors.append("companies/%s.json: body firm '%s' share exceeds BODY_SHARE_MAX (%.2f)" % [nation_id, company.id, CompaniesK.BODY_SHARE_MAX])
			# V4.7a chiefs: a major carries a named chief (a person of kind
			# "executive" in this nation's people file), a body firm carries
			# none -- the body is acted upon and nobody fronts it. The id
			# resolves cross-register here, the party_id pattern: the loader
			# has both halves in hand, and a bogus ref is a load error rather
			# than a dangling edge the panel discovers mid-session.
			if company.tier == "major" and company.chief_id == "":
				loader.errors.append("companies/%s.json: major '%s' carries no chief_id -- a champion with no face is the count-is-the-design rule half-built" % [nation_id, company.id])
			if company.tier == "body" and company.chief_id != "":
				loader.errors.append("companies/%s.json: body firm '%s' carries a chief_id -- the body has no faces" % [nation_id, company.id])
			if company.chief_id != "":
				var chief = people_by_id.get(company.chief_id)
				if chief == null:
					loader.errors.append("companies/%s.json: firm '%s' chief '%s' is not a person of this nation" % [nation_id, company.id, company.chief_id])
				elif chief.kind != "executive":
					loader.errors.append("companies/%s.json: firm '%s' chief '%s' is kind '%s', not an executive" % [nation_id, company.id, company.chief_id, chief.kind])

		for sector in by_sector.keys():
			var group: Array = by_sector[sector]
			if group.size() < 2:
				loader.errors.append(
					"companies/%s.json: sector '%s' has one named firm ('%s') -- a firm with no rival cannot gain share from anybody, so a subsidy pointed at it is a sector lever with a company's name on it"
					% [nation_id, sector, group[0].id]
				)
			var total := 0.0
			for company in group:
				total += company.share
			if total > 1.0 + 0.000001:
				loader.errors.append(
					"companies/%s.json: sector '%s' shares sum to %s, above 1.0 -- the named firms would hold more than the sector does"
					% [nation_id, sector, str(total)]
				)
