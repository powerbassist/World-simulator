extends SceneTree

## Headless test: godot --headless --script res://tests/test_orgs.gd
## Non-zero exit on any failure.
##
## V3.2, the org register. Model: docs/orgs-model.md.
##
## PART 1 (Task 1) -- the content type and the loader:
##   - The four authored orgs load cleanly and the register is sorted.
##   - eu carries the values the two co-member constants held before the
##     register existed; its member set and seats equal what
##     data/eu_parliament.json used to hold.
##   - A malformed org file is a loud load error, never a silent partial.
##   - Every proposal names a loaded org, and the per-org agendas preserve
##     flat-file order -- the agenda IS file order, and a reorder here would
##     be a silent change to what every council votes on and when.
##
## PART 2 (Tasks 2-3) -- membership as live state, the generalised machine,
## and the composition rule.
##
## PART 3 (Task 7) -- accession and withdrawal.

const DataLoader = preload("res://src/core/data_loader.gd")
const Org = preload("res://src/core/org.gd")

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_register_loads()
	_check_eu_absorbed_the_old_sources()
	_check_malformed_orgs_refused()
	_check_proposals_name_orgs()
	_finish()


func _fail(msg: String) -> void:
	_failures.append(msg)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_orgs: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("  FAIL: %s" % f)
	printerr("test_orgs: %d failure(s)" % _failures.size())
	quit(1)


# --- Part 1 -----------------------------------------------------------------------

func _check_register_loads() -> void:
	var ids: Array = []
	for org in _loader.orgs:
		ids.append(org.id)
	_ok(ids == ["eu", "eurozone", "nato", "schengen"], "register ids sorted, got %s" % [ids])
	for org in _loader.orgs:
		_ok(org.name != "", "%s carries a name" % org.id)
		for member_id in org.members.keys():
			_ok(_loader.nations.has(member_id), "%s member '%s' is on the roster" % [org.id, member_id])
	var parl := 0
	for org in _loader.orgs:
		if not org.parliament.is_empty():
			parl += 1
	_ok(parl == 1, "exactly one org carries a parliament, got %d" % parl)


func _check_eu_absorbed_the_old_sources() -> void:
	var eu = _loader.orgs_by_id.get("eu", null)
	_ok(eu != null, "eu is loaded")
	if eu == null:
		return

	# The member set data/eu_parliament.json held, seats included.
	var expected := {
		"FRA": 81, "DEU": 96, "ITA": 76, "ESP": 61,
		"NLD": 31, "BEL": 22, "AUT": 20, "LUX": 6,
	}
	_ok(eu.members.size() == expected.size(), "eu carries 8 members, got %d" % eu.members.size())
	for id in expected.keys():
		_ok(eu.is_member(id), "eu has %s" % id)
		_ok(eu.ep_seats(id) == expected[id], "eu %s holds %d seats, got %d" % [id, expected[id], eu.ep_seats(id)])
	_ok(not eu.is_member("GBR") and not eu.is_member("CHE"), "eu excludes the two neighbours")
	_ok(eu.parliament.get("next_election", {}).get("year", 0) == 2029, "eu EP clock reads 2029")
	_ok(eu.council and eu.net_transfers, "eu carries the council and the transfer machinery")

	# The two co-member prices, moved UNCHANGED from the constants. These were
	# measured values, not authored ones -- a drift here is a silent re-tune of
	# every resting relation and every gravity weight in the game.
	_ok(is_equal_approx(eu.relations_bonus, 15.0), "eu relations_bonus is the old EU_CO_MEMBER_BONUS")
	_ok(is_equal_approx(eu.trade_bonus, 0.50), "eu trade_bonus is the old EU_TRADE_BONUS")

	# The register's real content: who is in what, and the one cross-cutting
	# fact the hardcoded object could not hold -- GBR is NATO, CHE is Schengen,
	# AUT is EU but not NATO.
	var nato = _loader.orgs_by_id["nato"]
	var schengen = _loader.orgs_by_id["schengen"]
	_ok(nato.is_member("GBR") and not schengen.is_member("GBR"), "GBR is NATO and not Schengen")
	_ok(schengen.is_member("CHE") and not _loader.orgs_by_id["eurozone"].is_member("CHE"), "CHE is Schengen, not the euro")
	_ok(not nato.is_member("AUT"), "AUT stays out of NATO")


func _check_malformed_orgs_refused() -> void:
	var errs: Array[String] = []
	var bad = Org.from_dict({"id": "", "members": {}}, "bad.json", errs)
	_ok(bad.id == "" and not errs.is_empty(), "an org with no id is refused")

	errs = []
	Org.from_dict({"id": "x", "members": {"FRA": {}}}, "bad2.json", errs)
	_ok(not errs.is_empty(), "an org whose members lack ids is refused")

	errs = []
	Org.from_dict({"id": "x", "name": "X", "members": {"FRA": { "ep_seats": 5 }}, "parliament": {"next_election": {"year": 2029, "month": 6}, "term_years": 5}}, "bad3.json", errs)
	_ok(errs.is_empty(), "a parliament org whose members carry seats is accepted")

	errs = []
	Org.from_dict({"id": "x", "name": "X", "members": {"FRA": {}}}, "bad4.json", errs)
	_ok(errs.is_empty(), "a non-parliament org with bare member entries is accepted")

	errs = []
	Org.from_dict({"id": "x", "name": "X", "members": {"FRA": {}}, "parliament": {"next_election": {"year": 2029, "month": 6}, "term_years": 5}}, "bad5.json", errs)
	_ok(not errs.is_empty(), "a parliament org whose members lack seats is refused")


func _check_proposals_name_orgs() -> void:
	var per_org := {}
	for p in _loader.bloc_proposals:
		_ok(p.org_id != "", "proposal '%s' names an org" % p.id)
		_ok(_loader.orgs_by_id.has(p.org_id), "proposal '%s' names a LOADED org" % p.id)
		per_org = {}
	for p in _loader.bloc_proposals:
		per_org[p.org_id] = int(per_org.get(p.org_id, 0)) + 1
	_ok(int(per_org.get("eu", 0)) == 7, "eu carries 7 proposals before track (b) moves the floor, got %d" % int(per_org.get("eu", 0)))

	# File order IS the agenda. The eu list must be fiscal.json's proposals then
	# union_policy.json's, in authored order -- a reorder would silently change
	# what every council brings forward and when, which is exactly the class of
	# change the bit-identity run is watching for.
	var eu_agenda: Array = _loader.org_proposals.get("eu", [])
	var eu_ids: Array = []
	for p in eu_agenda:
		eu_ids.append(p.id)
	_ok(eu_ids == ["stability_pact", "debt_reduction_rule", "minimum_corporate_rate", "cohesion_fund", "recovery_facility", "common_defence_floor", "common_external_tariff"],
		"eu agenda preserves flat-file order, got %s" % [eu_ids])
