extends SceneTree

## D14 (A'): the three content memos the forecast speedups added, pinned on the
## property each one's soundness rests on. All three answer from memory a
## question whose answer is a pure function of loader content, and each must
## still notice when it is asked about DIFFERENT content:
##
##   - Companies.majors_of() (companies_roster.gd) is remembered per nation
##     against the roster array and its size, and hands out a copy: a caller
##     appending to the result cannot write into the memo, a firm appended to
##     the loaded roster (test_companies_tiers does) is seen, and another
##     loader's roster is never answered from this one's;
##   - Industry._maps_of() is remembered per nation against the region list: a
##     different loader's list is a miss;
##   - Network._same_graph() remembers the last pair of graphs it PROVED equal,
##     by identity -- an equal deep copy (Budget.project()'s) is the same graph,
##     and a copy that differs in one edge is not, though its size is the same.
##
## The equality of the floats these memos serve is proven elsewhere (the
## 24-month projection dump and the balance table, cmp-identical to the base in
## the PR); this file pins that no memo can answer for the wrong content.

const DataLoader = preload("res://src/core/data_loader.gd")
const Companies = preload("res://src/sim/companies.gd")
const Company = preload("res://src/core/company.gd")
const Industry = preload("res://src/sim/industry.gd")
const Network = preload("res://src/sim/network.gd")

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
	else:
		_check_majors_memo()
		_check_region_maps_memo()
		_check_graph_pair()
	_finish()


func _check_majors_memo() -> void:
	var count := Companies.majors_of(_loader, "FRA").size()
	if count == 0:
		_fail("FRA has no majors -- the memo pins below would test nothing")
		return
	# A remembered answer handed out must be a copy: append to a HIT's result.
	var hit: Array = Companies.majors_of(_loader, "FRA")
	hit.append("not a firm")
	if Companies.majors_of(_loader, "FRA").size() != count:
		_fail("appending to majors_of()'s result wrote into the memo")
	# Another loader's roster OF THE SAME SIZE (so the size alone cannot tell
	# them apart): the real roster with its first major swapped for a body firm.
	var errs: Array[String] = []
	var roster: Array = (_loader.companies["FRA"] as Array).duplicate()
	for i in roster.size():
		if Companies.is_major(roster[i]):
			roster[i] = Company.from_dict({
				"id": "FRA_memo_probe", "name": "Memo probe", "sector": "industry",
				"share": 0.05, "headcount": 1000, "city": "FRI_paris", "tier": "body",
			}, 0, "test", errs)
			break
	var stub := DataLoader.new()
	stub.companies["FRA"] = roster
	Companies.majors_of(_loader, "FRA")
	if Companies.majors_of(stub, "FRA").size() != count - 1:
		_fail("majors_of() answered another loader's roster from the memo")
	# A major appended to the loaded roster after it was remembered is seen.
	Companies.majors_of(_loader, "FRA")
	_loader.companies["FRA"].append(Company.from_dict({
		"id": "FRA_memo_late", "name": "Late major", "sector": "industry",
		"share": 0.01, "headcount": 1000, "city": "FRI_paris", "tier": "major",
	}, 0, "test", errs))
	if Companies.majors_of(_loader, "FRA").size() != count + 1:
		_fail("a major appended to the loaded roster was not seen by majors_of()")
	_loader.companies["FRA"].pop_back()


func _check_region_maps_memo() -> void:
	var real: Array = Industry._maps_of(_loader, "FRA")
	if (real[0] as Dictionary).is_empty():
		_fail("FRA has no city -> region map -- the memo pin below would test nothing")
		return
	var stub := DataLoader.new()
	stub.regions["FRA"] = []
	var other: Array = Industry._maps_of(stub, "FRA")
	if not (other[0] as Dictionary).is_empty() or not (other[1] as Dictionary).is_empty():
		_fail("Industry._maps_of() answered another loader's regions from the memo")


func _check_graph_pair() -> void:
	var real: Dictionary = _loader.region_graph
	var copy: Dictionary = real.duplicate(true)
	if not Network._same_graph(copy, real):
		_fail("an equal deep copy of the graph is not the same graph")
	if not (is_same(Network._equal_a, copy) and is_same(Network._equal_b, real)):
		_fail("the proven pair was not remembered by identity")
	var edges: Array = copy["edges"]
	if edges.is_empty():
		_fail("the graph has no edges -- the pin below would test nothing")
		return
	var changed: Dictionary = copy.duplicate(true)
	var edge: Array = (changed["edges"] as Array)[0]
	edge[2] = float(edge[2]) + 1.0
	if changed.size() != real.size() or Network._same_graph(changed, real):
		_fail("a graph differing in one edge's km was taken for the same graph")
	if Network._same_graph(changed, copy):
		_fail("a remembered pair answered for a graph outside it")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_content_memos: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		quit(1)
