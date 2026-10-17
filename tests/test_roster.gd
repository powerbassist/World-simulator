extends SceneTree

## V4.11. The roster's grade is DERIVED -- src/core/roster.gd. Three grades and
## no stored field: a nation file says playable or simulated through its one
## bool, and an outline is anything the world register carries.

const DataLoader = preload("res://src/core/data_loader.gd")
const Roster = preload("res://src/core/roster.gd")

var _failures: Array[String] = []


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])

	_check_grades(loader)
	_check_no_id_in_both(loader)
	_check_playable_is_the_only_flag()

	if _failures.is_empty():
		print("test_roster: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _check_grades(loader) -> void:
	var cases := {"FRA": "playable", "MLT": "simulated", "USA": "outline", "ZZZ": ""}
	for id in cases:
		var got: String = Roster.grade(loader, id)
		if got != cases[id]:
			_fail("%s should read '%s', got '%s'" % [id, cases[id], got])


## A nation drawn from both files is outlined twice and tinted over its own
## coastline (import_data.build_world's docstring) -- and would carry two grades.
func _check_no_id_in_both(loader) -> void:
	for id in loader.nations.keys():
		if loader.world_features.has(id):
			_fail("'%s' is both a nation file and a world outline" % id)


## The grade folds nothing because there is nothing else to fold: a second
## roster flag on Nation is the two-half-fields failure the V4.11 handoff
## forbids. Mutation-checked: adding `var grade` to nation.gd fails here.
func _check_playable_is_the_only_flag() -> void:
	var text := FileAccess.get_file_as_string("res://src/core/nation.gd")
	for banned in ["var grade", "var simulated", "var is_outline"]:
		if text.contains(banned):
			_fail("nation.gd declares '%s' -- the grade is derived (src/core/roster.gd)" % banned)


func _fail(message: String) -> void:
	_failures.append(message)
