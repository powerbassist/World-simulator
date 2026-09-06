extends SceneTree

## Headless test: godot --headless --script res://tests/test_electoral_systems.gd
## Non-zero exit on any failure.
##
## Seat allocation is where an off-by-one lives. Checked in isolation from the
## vote-share model — every method here is handed a vote-share Dictionary
## directly, the same contract elections.gd calls it through.

const DataLoader = preload("res://src/core/data_loader.gd")
const ElectoralSystems = preload("res://src/sim/electoral_systems.gd")
const K = preload("res://src/sim/election_constants.gd")

var _failures: Array[String] = []
var _loader: DataLoader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_seats_sum_and_bounds()
	_check_threshold_excludes()
	_check_dhondt_worked_example()
	_check_power_law_amplifies_and_preserves_order()
	_check_parallel_equals_its_components()
	_check_all_real_nation_configs()
	_check_eu_config()

	_finish()


## For every method, at a spread of vote-share inputs: seats sum to the assembly
## size exactly, and nobody gets negative seats.
func _check_seats_sum_and_bounds() -> void:
	var shares_sets := [
		{"a": 0.5, "b": 0.3, "c": 0.2},
		{"a": 0.34, "b": 0.33, "c": 0.33},
		{"a": 0.9, "b": 0.06, "c": 0.04},
		{"a": 0.01, "b": 0.01, "c": 0.98},
	]
	var seat_counts := [1, 5, 60, 150, 577]

	for system in ElectoralSystems.SYSTEM_KEYS:
		for shares in shares_sets:
			for seats in seat_counts:
				var result := ElectoralSystems.allocate(system, shares, seats, 0.0)
				var total := 0
				for party in result:
					var s: int = int(result[party])
					if s < 0:
						_fail("%s: %s got negative seats %d (shares %s, seats %d)" % [system, party, s, shares, seats])
					total += s
				if total != seats:
					_fail("%s: seats sum to %d, expected %d (shares %s)" % [system, total, seats, shares])


## A party below threshold_pct must win zero seats under either PR method.
func _check_threshold_excludes() -> void:
	var shares := {"big": 0.90, "tiny": 0.04, "medium": 0.06}
	for system in ["pr_dhondt", "pr_national"]:
		var result := ElectoralSystems.allocate(system, shares, 100, 5.0)
		if int(result.get("tiny", 0)) != 0:
			_fail("%s: party under threshold won %d seats" % [system, result["tiny"]])
		var total := 0
		for v in result.values():
			total += int(v)
		if total != 100:
			_fail("%s: seats sum to %d with a threshold applied, expected 100" % [system, total])


## The textbook D'Hondt example (Wikipedia "D'Hondt method"): four parties,
## votes 100000/80000/30000/20000, eight seats, known result A4 B3 C1 D0.
func _check_dhondt_worked_example() -> void:
	var total := 100000.0 + 80000.0 + 30000.0 + 20000.0
	var shares := {
		"a": 100000.0 / total,
		"b": 80000.0 / total,
		"c": 30000.0 / total,
		"d": 20000.0 / total,
	}
	var result := ElectoralSystems.pr_dhondt(shares, 8, 0.0)
	var expected := {"a": 4, "b": 3, "c": 1, "d": 0}
	for party in expected:
		if int(result.get(party, -1)) != int(expected[party]):
			_fail("D'Hondt worked example: %s got %d seats, expected %d" % [party, result.get(party, -1), expected[party]])


## FPTP amplifies the leader beyond its vote share and never reorders the field
## — no party with fewer votes than another can win more seats.
func _check_power_law_amplifies_and_preserves_order() -> void:
	var shares := {"a": 0.40, "b": 0.35, "c": 0.25}
	var result := ElectoralSystems.allocate("fptp", shares, 650, 0.0)

	var seat_share_a := float(result["a"]) / 650.0
	if seat_share_a <= shares["a"]:
		_fail("fptp: leader's seat share %.3f did not exceed its vote share %.3f" % [seat_share_a, shares["a"]])

	if not (int(result["a"]) >= int(result["b"]) and int(result["b"]) >= int(result["c"])):
		_fail("fptp: seat order %s did not preserve vote order a>b>c" % [result])


## The parallel method is exactly the sum of a PR allocation over its seat share
## of the total and a power-law allocation over the remainder — checked by
## reproducing that computation independently rather than by re-deriving the
## method's own formula.
func _check_parallel_equals_its_components() -> void:
	var shares := {"a": 0.45, "b": 0.30, "c": 0.15, "d": 0.10}
	var seats := 400
	var threshold := 3.0

	var result := ElectoralSystems.allocate("parallel", shares, seats, threshold)

	var pr_seats: int = int(round(float(seats) * K.PARALLEL_PR_WEIGHT))
	var maj_seats: int = seats - pr_seats
	var expected_pr := ElectoralSystems.pr_national(shares, pr_seats, threshold)
	var expected_maj := ElectoralSystems.allocate("fptp", shares, maj_seats, 0.0)

	for party in shares:
		var expected: int = int(expected_pr.get(party, 0)) + int(expected_maj.get(party, 0))
		if int(result.get(party, -1)) != expected:
			_fail("parallel: %s got %d, expected %d (pr %d + majoritarian %d)" % [
				party, result.get(party, -1), expected, expected_pr.get(party, 0), expected_maj.get(party, 0)
			])


## Load the real, authored configuration for all ten nations and confirm each
## allocates a full, valid chamber — the check that catches a nation whose
## system string or threshold doesn't actually run.
func _check_all_real_nation_configs() -> void:
	for id in _loader.nations.keys():
		var n = _loader.nations[id]
		var parties: Array = _loader.parties.get(id, [])
		if parties.is_empty():
			_fail("%s: no parties loaded, cannot exercise its electoral system" % id)
			continue

		var shares := {}
		for party in parties:
			shares[party.id] = party.seat_share

		var result := ElectoralSystems.allocate(n.election_system, shares, n.assembly_seats, n.election_threshold_pct)
		var total := 0
		for v in result.values():
			total += int(v)
		if total != n.assembly_seats:
			_fail("%s (%s): allocated %d seats, expected %d" % [id, n.election_system, total, n.assembly_seats])
		for v in result.values():
			if int(v) < 0:
				_fail("%s: negative seat count in real config" % id)


## Same check for the European Parliament allocation each EU member runs.
func _check_eu_config() -> void:
	# V3.2: the parliament is the one org whose content carries one.
	var parliament = null
	for org in _loader.orgs:
		if not org.parliament.is_empty():
			parliament = org
			break
	if parliament == null:
		_failures.append("no org carries a parliament to allocate EP seats with")
		return
	for id in parliament.members.keys():
		var parties: Array = _loader.parties.get(id, [])
		if parties.is_empty():
			continue
		var shares := {}
		for party in parties:
			shares[party.id] = party.seat_share
		var seats: int = parliament.ep_seats(id)
		var result := ElectoralSystems.pr_national(shares, seats, 0.0)
		var total := 0
		for v in result.values():
			total += int(v)
		if total != seats:
			_fail("EU %s: allocated %d MEP seats, expected %d" % [id, total, seats])


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_electoral_systems: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
