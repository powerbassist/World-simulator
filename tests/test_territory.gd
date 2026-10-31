extends SceneTree

## Headless test: godot --headless --script res://tests/test_territory.gd
## Non-zero exit on any failure.
##
## V5.3-0 (b), Territory (R13, the author's call 6): ONE tab where the player's
## decisions land.
##   - one row per region, its name a button, the player's site count beside it;
##   - a real click (press and release frames apart) opens the region: its figures,
##     the player's sites each with a Go that opens the tab acting on it, its
##     largest cities;
##   - a city opens in place with a way back; the map's cross opens the same view;
##   - the City tab is gone from the Territory domain.

const Click = preload("res://tests/click.gd")
const Domains = preload("res://src/ui/domains.gd")

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0
var _target: Control
var _region_id := ""
var _city_id := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_panel = _main._region_panel
			_stage_plant()
			_main._windows.open("region")
		6:
			_check_rows()
			_target = _region_button(_region_id)
			_press(true)
		9:
			_press(false)
		12:
			_check_opened()
			_target = _button_named("Go")
			_press(true)
		15:
			_press(false)
		18:
			if not _main._windows.frame("energy").visible:
				_fail("a site's Go did not open the Energy tab")
			_main._windows.open("region")
		21:
			_target = _button_named(_city_name())
			_press(true)
		24:
			_press(false)
		27:
			_check_city()
			_main._windows.close_all()
			_main._map_view.city_clicked.emit(_city_id)
		30:
			if not _main._windows.frame("region").visible or not _text(_panel._body).to_upper().contains("NAMED EMPLOYERS"):
				_fail("the map's cross did not open the city in Territory")
			if Domains.tabs("territory", _main._windows.panel_ids()) != ["region"]:
				_fail("Territory still has more than one tab: %s" % [Domains.tabs("territory", _main._windows.panel_ids())])
			_finish()
			return true
	return false


## A plant of the player's in the third region: a site the row counts and the
## opened region lists.
func _stage_plant() -> void:
	var ns = _main._state.player()
	var regions: Array = _main._loader.regions.get(ns.id, [])
	_region_id = String(regions[2].id)
	var source_id := String(_main._loader.energy_sources.keys()[0])
	ns.plants["%s#1" % source_id] = {"source_id": source_id, "region_id": _region_id, "lon": 0.0, "lat": 0.0}
	_panel.mark_dirty()


func _check_rows() -> void:
	var ns = _main._state.player()
	var count: int = (_main._loader.regions.get(ns.id, []) as Array).size()
	var buttons := 0
	for region in _main._loader.regions.get(ns.id, []):
		if _region_button(String(region.id)) != null:
			buttons += 1
	if buttons != count:
		_fail("%d region rows for %d regions" % [buttons, count])
	var row: Control = _region_button(_region_id).get_parent()
	if not _text(row).split("\n").has("1"):
		_fail("the region with the player's plant does not count one site: %s" % _text(row).replace("\n", " | "))


func _check_opened() -> void:
	var text := _text(_panel._body)
	for word in ["People", "Main sector", "Your sites here", "Largest cities"]:
		if not text.to_upper().contains(word.to_upper()):
			_fail("the opened region does not show '%s'" % word)
	if _button_named("Go") == null:
		_fail("the player's site has no Go")


func _check_city() -> void:
	if not _panel._back_button.visible or not _text(_panel._body).to_upper().contains("NAMED EMPLOYERS"):
		_fail("a city button did not open the city in place")
	if _panel._title.text != _city_name():
		_fail("the city view is titled '%s'" % _panel._title.text)
	_city_id = _panel._city_id


func _city_name() -> String:
	var ns = _main._state.player()
	for region in _main._loader.regions.get(ns.id, []):
		if String(region.id) == _region_id:
			return String(_panel._cities_by_size(ns, region)[0].city_name)
	return ""


func _region_button(region_id: String) -> Button:
	var ns = _main._state.player()
	for region in _main._loader.regions.get(ns.id, []):
		if String(region.id) == region_id:
			return _button_named(String(region.region_name))
	return null


func _button_named(text: String) -> Button:
	for b in _panel._body.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Button).is_visible_in_tree():
			return b
	return null


func _text(node: Node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += String(node.text) + "\n"
	elif node is RichTextLabel:
		out += (node as RichTextLabel).get_parsed_text() + "\n"
	for child in node.get_children():
		out += _text(child)
	return out


func _press(down: bool) -> void:
	if _target == null:
		_fail("no control to click at frame %d" % _frame)
		return
	Click.half(_main.get_viewport(), _target, down)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_territory: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
