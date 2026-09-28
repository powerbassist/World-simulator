extends SceneTree

## V4.7a Task A1: the two-tier register foundation.
## Model: docs/superpowers/plans/2026-09-27-v4.7-industry.md (Task A1); the
## step-0 finding that forced the tier gate is recorded in the plan and in
## reports/industry_step0_probe.txt -- a subsidy's share channel is absolute,
## not scale-aware, so body firms must never be verb targets and never ride
## the major pool. The load-bearing pins here:
##
##   - the 26 shipped firms are majors and every nation's body list is empty
##     until A3 generates it;
##   - a firm with no register entry reads its AUTHORED share (the
##     sparse-register fallback) and an unknown id reads 0.0 -- the fallback
##     is what makes body entries sparse safe;
##   - from_dict rebuilds each register entry into fresh dictionaries. The
##     V1.4 shape assigned the payload dictionary outright, which is the
##     aliasing defect commodities-model.md section 6 records: two states
##     sharing one register. The mutation below passes only if the rebuild
##     is real;
##   - and the rebuild is LOSSLESS: a round trip through to_dict/from_dict
##     reproduces the register exactly, so the alias fix cannot silently
##     become a data fix.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Companies = preload("res://src/sim/companies.gd")
const NationState = preload("res://src/core/nation_state.gd")
const CompaniesK = preload("res://src/sim/companies_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
	else:
		_test_tiers()
		_test_sparse_reads()
		_test_from_dict_does_not_alias_companies()
		_test_from_dict_roundtrips_the_register()
		_test_tier_gate_refuses_body_verbs()
		_test_register_scale()
		_test_body_bands()
		_test_body_touched_roundtrip()
	_finish()


func _test_tiers() -> void:
	# A3 grew the register: FRA now holds its majors PLUS a body list, so the
	# A1 pin (exactly six majors, empty body) is now the majors count alone.
	var fra_majors := Companies.majors_of(_loader, "FRA")
	if fra_majors.size() != 6:
		_fail("FRA should hold exactly its six majors, got %d" % fra_majors.size())
	for nation_id in _loader.companies.keys():
		if _loader.companies[nation_id].is_empty():
			_fail("%s holds no firms at all -- A3 generates every nation's register" % nation_id)
		for company in _loader.companies[nation_id]:
			if not [ "major", "body" ].has(String(company.tier)):
				_fail("firm %s carries tier '%s'" % [company.id, company.tier])


func _test_sparse_reads() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.nations["FRA"]
	# A firm with no register entry reads its authored share through
	# share_of_company -- the signature that carries the firm in hand, which is
	# what output_eur_bn and headcount read through. No body firm exists yet
	# (A3 generates them), so the fallback is exercised on a MAJOR whose entry
	# was cleared -- same code path, no dependence on A3.
	var company = null
	for c in _loader.companies["FRA"]:
		if c.id == "FRA_aurignac":
			company = c
	var authored: float = ns.companies["FRA_aurignac"]["share"]
	ns.companies.erase("FRA_aurignac")
	if not is_equal_approx(Companies.share_of_company(ns, company), authored):
		_fail("sparse register did not fall back to the authored share")
	if not is_equal_approx(Companies.output_eur_bn(ns, company),
			authored * float(ns.sector_output.get(company.sector, 0.0))):
		_fail("output_eur_bn did not fall back to the authored share")
	# And an id that exists nowhere reads 0.0, never an error.
	if Companies.share_of(ns, "FRA_body_nonexistent") != 0.0:
		_fail("unknown firm id did not read as zero")


func _test_from_dict_does_not_alias_companies() -> void:
	var a = GameState.new_game(_loader, "FRA")
	var nation_payload: Dictionary = a.to_dict()["nations"]["FRA"]
	var c = NationState.from_dict(nation_payload)
	c.companies["FRA_aurignac"]["share"] = 0.99
	if is_equal_approx(a.nations["FRA"].companies.get("FRA_aurignac", {}).get("share", 0.0), 0.99):
		_fail("from_dict aliased the companies register")
	# The other direction: mutating the ORIGINAL after load must not reach the
	# loaded state either -- the direction a future nested entry value would
	# break first.
	a.nations["FRA"].companies["FRA_aurignac"]["share"] = 0.5
	if is_equal_approx(float(c.companies.get("FRA_aurignac", {}).get("share", 0.0)), 0.5):
		_fail("the original aliased the loaded state's register")


func _test_from_dict_roundtrips_the_register() -> void:
	var a = GameState.new_game(_loader, "FRA")
	var nation_payload: Dictionary = a.to_dict()["nations"]["FRA"]
	var c = NationState.from_dict(nation_payload)
	if c.companies.size() != a.nations["FRA"].companies.size():
		_fail("round trip changed the register's size (%d vs %d)" % [
			c.companies.size(), a.nations["FRA"].companies.size()])
	for company_id in a.nations["FRA"].companies.keys():
		var before: Dictionary = a.nations["FRA"].companies[company_id]
		var after: Dictionary = c.companies.get(company_id, {})
		if before.size() != after.size():
			_fail("%s: round trip changed the entry's key count" % company_id)
			continue
		for key in before.keys():
			if not after.has(key) or not is_equal_approx(float(before[key]), float(after[key])):
				_fail("%s.%s did not round trip (%s vs %s)" % [
					company_id, key, str(before.get(key)), str(after.get(key))])


func _test_tier_gate_refuses_body_verbs() -> void:
	# The step-0 escalator's permanent form: available() refuses a body-tier
	# firm whatever its register state. Register membership alone stopped
	# gating this the moment spillover began seeding body rivals (the
	# get-or-create in _tick_shares) -- only the tier read stops it, so the
	# pin seeds the entry a spillover would write and demands the refusal.
	var Company = preload("res://src/core/company.gd")
	var errs: Array[String] = []
	_loader.companies["FRA"].append(Company.from_dict({
		"id": "FRA_gatebody", "name": "Gatebody", "sector": "industry",
		"share": 0.025, "headcount": 20000, "city": "FRI_paris", "tier": "body",
	}, 0, "test", errs))
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.nations["FRA"]
	ns.companies["FRA_gatebody"] = {"share": 0.025, "subsidy": 0.0, "state_share": 0.0}
	if not Companies.available(state, ns, _loader.company_actions, "FRA_gatebody", _loader).is_empty():
		_fail("a body-tier firm with a seeded register entry passed available()")
	# And the same call for a major still returns verbs -- the gate is the
	# tier, not the firm's register state.
	if Companies.available(state, ns, _loader.company_actions, "FRA_aurignac", _loader).is_empty():
		_fail("a major was refused every verb -- the gate over-reached")


## A3's register-scale pins. The loader already refuses the reference failures
## (a bad city id, an unresolved chief) -- these pin the COUNTS and the bands,
## because "the file loads" says nothing about whether the register is the
## size the block planned or a hollow shell that passes every rule.
func _test_register_scale() -> void:
	var total := 0
	for nation_id in _loader.nations.keys():
		var firms: Array = _loader.companies.get(nation_id, [])
		var majors := Companies.majors_of(_loader, nation_id)
		var body := Companies.body_of(_loader, nation_id)
		total += firms.size()
		if firms.is_empty():
			_fail("%s has no companies file -- A3 generates all 29" % nation_id)
			continue
		# 10-15 majors a nation: the majors are hand-curated content, and a
		# nation under ten has no sector with a plausible champion ladder, while
		# one over fifteen is a body list wearing the tier the verbs read.
		# FRA/DEU/GBR/POL keep their AUTHORED majors (6/6/6/8, A2's curated
		# set) -- the band scopes to the 25 nations A3 authored.
		var authored := [ "FRA", "DEU", "GBR", "POL" ].has(nation_id)
		if not authored and (majors.size() < 10 or majors.size() > 15):
			_fail("%s carries %d majors, outside [10, 15]" % [nation_id, majors.size()])
		if body.size() < CompaniesK.BODY_MIN_PER_NATION:
			_fail("%s carries %d body firms, under BODY_MIN_PER_NATION (%d)" % [
				nation_id, body.size(), CompaniesK.BODY_MIN_PER_NATION])
		# The chiefs: every major of EVERY nation carries a resolving executive
		# chief (the loader refuses a dangling ref; this pins the COUNT of the
		# 25 nations A3 authored, where a whole missing people append would
		# otherwise fail only at the loader's error list).
		var people := {}
		for person in _loader.people.get(nation_id, []):
			people[person.id] = person
		var chiefed := 0
		for major in majors:
			if people.has(major.chief_id) and people[major.chief_id].kind == "executive":
				chiefed += 1
		if chiefed != majors.size():
			_fail("%s: %d of %d majors carry a resolving executive chief" % [
				nation_id, chiefed, majors.size()])
		# Every sector must be represented by BOTH tiers or by neither naming
		# anything -- the loader's two-named-firms floor plus the coverage band
		# below mean a sector named at all is named by majors and body alike.
	if total < 2700 or total > 3100:
		_fail("register holds %d firms, outside [2700, 3100]" % total)


## A3's body bands -- the brief's step-1 declarations, each pinned here so a
## generator change that moves a band fails the suite rather than shipping a
## register nobody re-measured.
func _test_body_bands() -> void:
	for nation_id in _loader.nations.keys():
		var body := Companies.body_of(_loader, nation_id)
		if body.is_empty():
			continue
		# Body share ceiling, per firm.
		for company in body:
			if company.share > CompaniesK.BODY_SHARE_MAX:
				_fail("%s body firm %s share %.4f over BODY_SHARE_MAX" % [
					nation_id, company.id, company.share])
			if company.share < CompaniesK.MIN_BODY_SHARE:
				_fail("%s body firm %s share %.5f under MIN_BODY_SHARE" % [
					nation_id, company.id, company.share])
			if company.headcount < 500.0 or company.headcount > 25000.0:
				_fail("%s body firm %s headcount %.0f outside [500, 25000]" % [
					nation_id, company.id, company.headcount])
		# Per-sector named coverage over both tiers: [0.85, 0.97], summed.
		var by_sector := {}
		for company in _loader.companies.get(nation_id, []):
			by_sector[company.sector] = float(by_sector.get(company.sector, 0.0)) + company.share
		for sector in by_sector.keys():
			var named: float = by_sector[sector]
			if named > 1.0 + 0.000001:
				_fail("%s sector %s named share %.4f above 1.0" % [nation_id, sector, named])
			if named < CompaniesK.BODY_COVERAGE_MIN - 0.000001 or named > CompaniesK.BODY_COVERAGE_MAX + 0.000001:
				_fail("%s sector %s named coverage %.4f outside [%.2f, %.2f]" % [
					nation_id, sector, named,
					CompaniesK.BODY_COVERAGE_MIN, CompaniesK.BODY_COVERAGE_MAX])
		# Body sector mix follows the nation's own sector_output weights --
		# SERVICES holds the most body firms in every nation (it is the
		# largest sector everywhere on the roster) and no sector is empty.
		# The full count ordering is NOT pinned: counts follow the need left
		# under the coverage target once the majors' own stake is subtracted,
		# and POL's authored majors already cover 0.45 of industry against
		# 0.14 of services -- its industry body is rightly the smallest.
		var body_by_sector := {}
		for company in body:
			body_by_sector[company.sector] = int(body_by_sector.get(company.sector, 0)) + 1
		if int(body_by_sector.get("services", 0)) <= int(body_by_sector.get("industry", 0)):
			_fail("%s body counts (%s): services does not hold the most firms" % [
				nation_id, str(body_by_sector)])
		for sector in [ "agriculture", "industry", "services" ]:
			if int(body_by_sector.get(sector, 0)) == 0:
				_fail("%s body holds no %s firms at all" % [nation_id, sector])
		# Payroll concentration: the largest city by body payroll holds
		# [0.25, 0.50] of the nation's body jobs -- V2.2a's measured finding.
		# The band's largest city is the register's own largest BY POPULATION
		# (the city the generator targets), not max-of-any: with only two
		# cities a partition is [x, 1-x] and one side must exceed 0.50 -- a
		# two-city nation cannot express the band, so nations whose body draws
		# on fewer than three cities are exempt (LUX and MLT hold one each).
		var payroll_by_city := {}
		var payroll_total := 0.0
		for company in body:
			payroll_by_city[company.city] = float(payroll_by_city.get(company.city, 0.0)) + company.headcount
			payroll_total += company.headcount
		if payroll_by_city.size() >= 3:
			var biggest_city := ""
			var biggest_pop := -1.0
			for region in _loader.regions.get(nation_id, []):
				for city in region.cities:
					if city.share > biggest_pop:
						biggest_pop = city.share
						biggest_city = city.id
			var share := float(payroll_by_city.get(biggest_city, 0.0)) / payroll_total \
					if payroll_total > 0.0 else 0.0
			if share < CompaniesK.BODY_PAYROLL_CONCENTRATION_MIN - 0.0001 \
					or share > CompaniesK.BODY_PAYROLL_CONCENTRATION_MAX + 0.0001:
				_fail("%s largest-city body payroll share %.3f outside [%.2f, %.2f]" % [
					nation_id, share,
					CompaniesK.BODY_PAYROLL_CONCENTRATION_MIN,
					CompaniesK.BODY_PAYROLL_CONCENTRATION_MAX])


## The sparse register's save leg. A body entry exists in the register ONLY
## once something has touched it; A3's majors-only pool means a subsidy
## spillover never does (the body is outside the verb plane -- only B-phase
## acts fail or buy a body firm), so this leg seeds the entry the way a B-phase
## act will, round-trips, and demands the touched body entry survive with its
## live share. A dropped key would silently revert the firm to its authored
## share -- the drift the sparse design exists to avoid paying for on firms
## nobody has touched, whoever the writer turns out to be.
func _test_body_touched_roundtrip() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.nations["FRA"]
	var body = Companies.body_of(_loader, "FRA")[0]
	var authored: float = body.share
	var touched_share: float = authored * 0.5
	ns.companies[body.id] = {
		"share": touched_share, "subsidy": 0.0, "state_share": 0.0
	}
	var payload: Dictionary = state.to_dict()["nations"]["FRA"]
	var rebuilt = NationState.from_dict(payload)
	if not rebuilt.companies.has(body.id):
		_fail("round trip dropped the body-touched entry %s" % body.id)
		return
	if absf(float(rebuilt.companies[body.id]["share"]) - touched_share) > 0.000001:
		_fail("body entry %s round-tripped %.6f against %.6f" % [
			body.id, float(rebuilt.companies[body.id]["share"]), touched_share])
	# And the untouched register is genuinely sparse: no body firm holds an
	# entry in a fresh state, which is what makes this leg's seeded entry the
	# interesting case rather than the ordinary one.
	var fresh = GameState.new_game(_loader, "FRA")
	if not fresh.nations["FRA"].companies.has(body.id):
		return
	_fail("an untouched body firm held a register entry -- the sparse design leaked")


func _loader_company(company_id: String):
	for nation_id in _loader.companies.keys():
		for company in _loader.companies[nation_id]:
			if String(company.id) == company_id:
				return company
	return null


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_companies_tiers: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		quit(1)
