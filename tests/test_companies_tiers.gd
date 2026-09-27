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
	_finish()


func _test_tiers() -> void:
	if _loader.companies["FRA"].size() != 6:
		_fail("FRA should hold exactly its six majors, got %d" % _loader.companies["FRA"].size())
	for nation_id in _loader.companies.keys():
		for company in _loader.companies[nation_id]:
			if not Companies.is_major(company):
				_fail("legacy firm %s does not read as major" % company.id)
		if not Companies.body_of(_loader, nation_id).is_empty():
			_fail("%s has body firms before A3 generates any" % nation_id)


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
