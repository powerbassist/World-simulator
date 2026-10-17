extends SceneTree

## V4.11c. The outline readout's text: a pure function of the loader, so the
## numbers a player reads on the map are pinned without a scene tree.

const DataLoader = preload("res://src/core/data_loader.gd")
const MapOutlines = preload("res://src/ui/map_outlines.gd")

var _failures: Array[String] = []


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])
	_check_every_outline_reads(loader)
	_check_the_top_supplier_leads(loader)
	_check_an_outline_with_nothing(loader)
	if _failures.is_empty():
		print("test_map_outlines: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


## Every outline gets a name and a profile line, and the profile leads with the
## grade and names at most TOP_GOODS goods (one "%" each).
func _check_every_outline_reads(loader) -> void:
	for id in loader.outlines.keys():
		if MapOutlines.name_of(loader, id) == "":
			_fail("%s has no name" % id)
		var profile := MapOutlines.profile_of(loader, id)
		if not profile.begins_with("Outline"):
			_fail("%s profile does not lead with its grade: %s" % [id, profile])
		if profile.count("%") > MapOutlines.TOP_GOODS:
			_fail("%s names more than %d goods: %s" % [id, MapOutlines.TOP_GOODS, profile])
		if profile.find(" 0%") >= 0:
			_fail("%s prints a zero share: %s" % [id, profile])


## The good an outline makes the largest world share of is the first one named --
## found from the data, not a hard-coded country.
func _check_the_top_supplier_leads(loader) -> void:
	var best_id := ""
	var best_good := ""
	var best := 0.0
	for good_id in loader.commodity_endowments.keys():
		for producer in loader.commodity_endowments[good_id].keys():
			var s := float(loader.commodity_endowments[good_id][producer])
			if loader.outlines.has(producer) and s > best:
				best = s
				best_id = producer
				best_good = good_id
	if best_id == "":
		_fail("no outline produces anything -- the endowment register is empty")
		return
	var profile := MapOutlines.profile_of(loader, best_id)
	var first_name := String(loader.commodity_goods[best_good].get("name", best_good))
	var at := profile.find(first_name)
	if at < 0 or at > profile.find("%"):
		_fail("%s's profile does not lead with %s: %s" % [best_id, first_name, profile])


## An outline the sources give no production says so rather than printing nothing.
func _check_an_outline_with_nothing(loader) -> void:
	for id in loader.outlines.keys():
		var any := false
		for good_id in loader.commodity_endowments.keys():
			if float(loader.commodity_endowments[good_id].get(id, 0.0)) > 0.0:
				any = true
				break
		if not any:
			var profile := MapOutlines.profile_of(loader, id)
			if profile.find("No recorded production") < 0:
				_fail("%s has no production but reads: %s" % [id, profile])
			return
	_fail("fixture moved: every outline produces something -- pick another check")


func _fail(message: String) -> void:
	_failures.append(message)
