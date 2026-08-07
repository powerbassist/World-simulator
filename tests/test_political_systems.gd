extends SceneTree

## Headless test: godot --headless --script res://tests/test_political_systems.gd
## Non-zero exit on any failure.
##
## V1.2b: political system templates, the head of state, and term limits. See
## docs/political-systems.md. Two questions this file asks that test_data.gd's
## generic per-field checks do not: is the template load-bearing (a nation
## whose flat fields disagree with its own template must fail to load), and
## does every nation land on the institutional shape the roster audit found
## (docs/tiers/v1.md §2)?

const DataLoader = preload("res://src/core/data_loader.gd")
const Nation = preload("res://src/core/nation.gd")
const PoliticalSystem = preload("res://src/core/political_system.gd")

## What the roster audit found -- see the plan's institutional dump, reproduced
## in docs/political-systems.md.
const EXPECTED_SYSTEM := {
	"FRA": "semi_presidential_republic",
	"DEU": "parliamentary_republic", "ITA": "parliamentary_republic", "AUT": "parliamentary_republic",
	"GBR": "constitutional_monarchy", "ESP": "constitutional_monarchy", "BEL": "constitutional_monarchy",
	"NLD": "constitutional_monarchy", "LUX": "constitutional_monarchy",
	"CHE": "directorial_republic",
}

const EXPECTED_HEAD_OF_STATE_KIND := {
	"FRA": "executive_president",
	"DEU": "elected_president", "ITA": "elected_president", "AUT": "elected_president",
	"GBR": "hereditary_monarch", "ESP": "hereditary_monarch", "BEL": "hereditary_monarch",
	"NLD": "hereditary_monarch", "LUX": "hereditary_monarch",
	"CHE": "collegial",
}

const EXPECTED_LOSE_CONDITION := {
	"FRA": "executive_election_defeat",
	"DEU": "party_not_largest", "ITA": "party_not_largest", "AUT": "party_not_largest",
	"GBR": "party_not_largest", "ESP": "party_not_largest", "BEL": "party_not_largest",
	"NLD": "party_not_largest", "LUX": "party_not_largest",
	"CHE": "never",
}

## V1.2c: each nation's real amendment threshold -- see docs/amendment-model.md.
## ESP is three_fifths, not two_thirds: Art. 167's ordinary revision path is
## 3/5 of each chamber; only Art. 168's rare total-revision path is 2/3.
const EXPECTED_AMENDMENT_RULE := {
	"FRA": "three_fifths",
	"DEU": "two_thirds", "ITA": "two_thirds", "AUT": "two_thirds",
	"GBR": "ordinary_law", "ESP": "three_fifths", "BEL": "two_thirds",
	"NLD": "two_thirds", "LUX": "three_quarters",
	"CHE": "referendum_required",
}

## V1.2d: whether each nation's own constitution permits changing its
## political system at all -- see docs/transition-model.md. France, Germany
## and Italy each entrench the republican form; Austria's rests on the
## Habsburg Law rather than a clean eternity clause. Switzerland is moot (no
## transition content names directorial_republic).
const EXPECTED_PERMITS_SYSTEM_CHANGE := {
	"FRA": false, "DEU": false, "ITA": false, "AUT": false,
	"GBR": true, "ESP": true, "BEL": true, "NLD": true, "LUX": true,
	"CHE": false,
}


func _init() -> void:
	var failures: Array[String] = []

	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		failures.append("expected zero errors loading real data, got: %s" % [loader.errors])

	if loader.political_systems.size() != 4:
		failures.append("expected 4 political-system templates, loaded %d" % loader.political_systems.size())

	for id in EXPECTED_SYSTEM.keys():
		if not loader.nations.has(id):
			failures.append("%s not loaded" % id)
			continue
		var n: Nation = loader.nations[id]

		if n.system_id != EXPECTED_SYSTEM[id]:
			failures.append("%s: system_id is '%s', expected '%s'" % [id, n.system_id, EXPECTED_SYSTEM[id]])
		if n.head_of_state_kind != EXPECTED_HEAD_OF_STATE_KIND[id]:
			failures.append("%s: head_of_state_kind is '%s', expected '%s'" % [id, n.head_of_state_kind, EXPECTED_HEAD_OF_STATE_KIND[id]])
		if n.amendment_rule != EXPECTED_AMENDMENT_RULE[id]:
			failures.append("%s: amendment_rule is '%s', expected '%s'" % [id, n.amendment_rule, EXPECTED_AMENDMENT_RULE[id]])
		if n.head_of_state_person_id == "":
			failures.append("%s: head_of_state has no name" % id)

		var system: PoliticalSystem = loader.political_systems.get(n.system_id)
		if system != null and system.lose_condition != EXPECTED_LOSE_CONDITION[id]:
			failures.append("%s: system '%s' lose_condition is '%s', expected '%s'" % [id, n.system_id, system.lose_condition, EXPECTED_LOSE_CONDITION[id]])
		if system != null and not system.allowed_head_of_state_kinds.has(n.head_of_state_kind):
			failures.append("%s: head_of_state_kind '%s' is not in system '%s''s allowed_head_of_state_kinds %s" % [id, n.head_of_state_kind, n.system_id, system.allowed_head_of_state_kinds])
		if n.permits_system_change != EXPECTED_PERMITS_SYSTEM_CHANGE[id]:
			failures.append("%s: permits_system_change is %s, expected %s" % [id, n.permits_system_change, EXPECTED_PERMITS_SYSTEM_CHANGE[id]])

		# elected_president is the only kind with a clock of its own; every
		# other kind must not carry one -- present-only-if-required, the same
		# rule `executive` enforces. See nation.gd's from_dict().
		if n.head_of_state_kind == "elected_president":
			if n.head_of_state_term_years <= 0:
				failures.append("%s: elected_president has no term_years" % id)
			if n.head_of_state_next_year <= 0:
				failures.append("%s: elected_president has no next election year" % id)
		else:
			if n.head_of_state_term_years != 0 or n.head_of_state_next_year != 0:
				failures.append("%s: head_of_state_kind '%s' should carry no term clock but has one" % [id, n.head_of_state_kind])

		# Only France's template permits a term limit, and only France sets one.
		if id == "FRA" and n.term_limit != 2:
			failures.append("FRA: term_limit is %d, expected 2" % n.term_limit)
		elif id != "FRA" and n.term_limit != 0:
			failures.append("%s: term_limit is %d, expected 0" % [id, n.term_limit])

	# The template is a constraint, not decoration: a nation whose flat
	# formation.method disagrees with its own declared system must fail to
	# load, naming the nation and the field. See political_system.gd's header.
	var fixture_text := FileAccess.get_file_as_string("res://tests/fixtures/nation_bad_formation_method.json")
	var fixture_dict = JSON.parse_string(fixture_text)
	var fixture_errors: Array[String] = []
	var bad_nation = Nation.from_dict(fixture_dict, "FRA.json", fixture_errors)
	if not fixture_errors.is_empty():
		failures.append("corrupt fixture failed Nation.from_dict() before reaching the template check: %s" % [fixture_errors])
	else:
		var cross_errors: Array[String] = []
		loader.errors = cross_errors
		loader._validate_political_system(bad_nation)
		var named_method := false
		for e in cross_errors:
			if e.find("coalition_negotiation") != -1 and e.find("semi_presidential_republic") != -1:
				named_method = true
		if not named_method:
			failures.append("a nation whose formation.method disagrees with its own system did not fail, or did not name both: %s" % [cross_errors])

	if failures.is_empty():
		print("test_political_systems: all checks passed")
		quit(0)
	else:
		for f in failures:
			printerr(f)
		quit(1)
