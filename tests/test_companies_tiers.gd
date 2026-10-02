extends SceneTree

## V4.7a Task A1: the two-tier register foundation.
## Model: docs/superpowers/plans/2026-09-27-v4.7-industry.md (Task A1); the
## step-0 finding that forced the tier gate is recorded in the plan and in
## reports/industry_step0_probe.txt -- a subsidy's share channel is absolute,
## not scale-aware, so body firms must never be verb targets and never ride
## the major pool. The load-bearing pins here:
##
##   - the register's SHAPE: every nation carries majors and a body list (A3
##     generated 317 majors + 2,420 body across 29 nations (the PR-46
##     review's finding 19, corrected at the pass-13 fleet's carried
##     find); the A1-era "26
##     firms, empty body" pin is history, corrected at the PR-46 review);
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
		_test_old_save_ticks_clean()
		_test_from_dict_does_not_alias_companies()
		_test_from_dict_roundtrips_the_register()
		_test_machine_keys_roundtrip()
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
	# A sector carrying exactly ONE major can never gain share: the pool's
	# rivals are majors only, so a subsidy pointed at a lone major finds
	# available == 0 and is refused -- a sector lever wearing a firm's name.
	# The loader's own >= 2 rule counts majors+body, so it cannot express
	# this; the pin lives here.
	for nation_id in _loader.companies.keys():
		var majors_by_sector := {}
		for company in Companies.majors_of(_loader, nation_id):
			majors_by_sector[company.sector] = int(majors_by_sector.get(company.sector, 0)) + 1
		for sector in majors_by_sector.keys():
			if int(majors_by_sector[sector]) < 2:
				_fail("%s sector '%s' carries one major -- no pool rival, no verb" % [nation_id, sector])


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


## The PR-46 ultra review's headline finding, pinned: a save written before
## 7a (SAVE_VERSION 37, register empty for the 25 nations that then had no
## companies file) must LOAD and TICK without error. The repair is
## _seed_missing_majors at the first tick; without it the share loop's indexed
## write raised a missing-key error per unseeded nation, every month, and the
## verbs' membership gate kept every firm of those nations permanently
## verb-dead. The leg builds the old shape by hand (seeded for the four
## legacy nations, {} for the rest), round-trips it through the real
## from_dict, and ticks.
func _test_old_save_ticks_clean() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var legacy_ids := ["FRA", "DEU", "GBR", "POL"]
	for nation_id in state.nations.keys():
		if legacy_ids.has(String(nation_id)):
			continue
		state.nations[nation_id].companies = {}
	var payload: Dictionary = state.to_dict()
	var loaded = GameState.from_dict(payload)
	var unseeded := 0
	for nation_id in loaded.nations.keys():
		if not legacy_ids.has(String(nation_id)) and loaded.nations[nation_id].companies.is_empty():
			unseeded += 1
	if unseeded < 20:
		_fail("the old-save fixture did not build (%d empty registers)" % unseeded)
		return
	# One firms tick over the whole loaded state: the pre-fix build raised
	# here -- 25 missing-key errors, one per unseeded nation, and no repair.
	Companies.tick_month(loaded, _loader)
	# Post-tick: every nation with content majors holds them all.
	var short := 0
	for nation_id in loaded.nations.keys():
		var ns = loaded.nations[nation_id]
		var majors := Companies.majors_of(_loader, String(nation_id))
		for company in majors:
			if not ns.companies.has(company.id):
				short += 1
	if short > 0:
		_fail("%d content majors missing from the register after the lazy-seed tick" % short)
	# And a major of a formerly-empty nation can act: the membership gate reads.
	var ita = loaded.nations["ITA"]
	if Companies.majors_of(_loader, "ITA").size() > 0 and Companies.available(loaded, ita, _loader.company_actions, String(Companies.majors_of(_loader, "ITA")[0].id), _loader).is_empty():
		_fail("a lazy-seeded major was refused every verb -- the membership gate did not see the repair")


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


## The eleven V4.7b machine keys, round-tripped VERBATIM -- the save half of
## the register contract the LIVE_KEYS allowlist only opens. The generic leg
## above runs on a fresh register (three float keys), so a typed cast or a
## filtered copy in from_dict's rebuild for the machine's strings and flags
## passed the suite silently until this leg (the pass-9 fleet's find).
func _test_machine_keys_roundtrip() -> void:
	var a = GameState.new_game(_loader, "FRA")
	var major = Companies.majors_of(_loader, "FRA")[0]
	a.nations["FRA"].companies[major.id] = {
		"share": 0.123, "subsidy": 0.5, "state_share": 0.25,
		"city": "FRI_bordeaux", "failed": true, "rescue_months_left": 4,
		"bid_bidder": "DEU|deuscher_hof", "bid_price_eur_bn": 12.5, "bid_months_left": 2,
		"subsidy_shadow": 0.6, "subsidy_lapsed_month": 37,
		"owner": "DEU", "courted": 1.0, "board_chair": "staged_chair"}
	var payload: Dictionary = a.to_dict()["nations"]["FRA"]
	var c = NationState.from_dict(payload)
	var before: Dictionary = a.nations["FRA"].companies[major.id]
	var after: Dictionary = c.companies.get(major.id, {})
	for key in before.keys():
		var expected = before[key]
		if not after.has(key):
			_fail("%s: the round trip dropped the machine key '%s'" % [major.id, key])
			continue
		var got = after[key]
		if expected is String:
			if String(got) != String(expected):
				_fail("%s.%s: '%s' vs '%s'" % [major.id, key, str(got), str(expected)])
		elif expected is bool:
			if bool(got) != bool(expected):
				_fail("%s.%s: %s vs %s" % [major.id, key, str(got), str(expected)])
		else:
			if not is_equal_approx(float(got), float(expected)):
				_fail("%s.%s: %s vs %s" % [major.id, key, str(got), str(expected)])


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
		# The band's largest city is the register's own largest BY NATIONAL
		# POPULATION (city share of region x region share of nation) -- the
		# A3 review's Critical 3: region-local share alone made city-state
		# regions (Ceuta, Logrono) outrank the real metropolis in six nations,
		# and two of them landed OVER the ceiling while the exemption hid
		# them. A register with ONE city has no partition to express at all
		# (LUX, MLT -- its whole payroll is its one city) and is exempt; a
		# register with two or more is measured, whatever its size.
		var payroll_by_city := {}
		var payroll_total := 0.0
		for company in body:
			payroll_by_city[company.city] = float(payroll_by_city.get(company.city, 0.0)) + company.headcount
			payroll_total += company.headcount
		var register_cities := 0
		var biggest_city := ""
		var biggest_pop := -1.0
		for region in _loader.regions.get(nation_id, []):
			for city in region.cities:
				register_cities += 1
				var national_pop: float = city.share * region.share
				if national_pop > biggest_pop:
					biggest_pop = national_pop
					biggest_city = city.id
		if register_cities >= 2:
			var share := float(payroll_by_city.get(biggest_city, 0.0)) / payroll_total \
					if payroll_total > 0.0 else 0.0
			if share < CompaniesK.BODY_PAYROLL_CONCENTRATION_MIN - 0.0001 \
					or share > CompaniesK.BODY_PAYROLL_CONCENTRATION_MAX + 0.0001:
				_fail("%s largest-city body payroll share %.3f outside [%.2f, %.2f]" % [
					nation_id, share,
					CompaniesK.BODY_PAYROLL_CONCENTRATION_MIN,
					CompaniesK.BODY_PAYROLL_CONCENTRATION_MAX])


## The sparse register's save leg. No code path writes a body entry (the body
## is inert by design -- BODY SILENCE pinned; a later block's body market is
## where entries would begin), so this leg hand-seeds the entry such a writer
## would create, round-trips, and demands the touched body entry survive with
## its live share. A dropped key would silently revert the firm to its authored
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
