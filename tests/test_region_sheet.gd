extends SceneTree

## Headless test: godot --headless --script res://tests/test_region_sheet.gd
## Non-zero exit on any failure.
##
## Screen 6, Regions (Gameplay's regions brief, sections 3 and 5b; the regions card's
## rulings): an opened region is ONE sheet, the same whatever leads the room beside it.
##   - its 12 months against the nation's, from the region's own sample (region_history),
##     hidden until the sample holds two months;
##   - who speaks for it: the regional figure whose want names the region, and the points
##     their voice is worth if a fund opens (BlocVoice: CK.SPEAK_SHARE of their briefing,
##     on its blocs, at the approval span); a region nobody wants says so;
##   - the fund's strip carries the other regions' loss (RegionFunds.estimate's
##     `others_eur_bn`) and the figure's voice;
##   - the sector priority has left the screen (the ruling), and so has the share chart;
##   - the domain is called Regions.
## Driven through the real controls a frame apart (AGENTS.md: a Control built but not
## shown fails silently).

const Regions = preload("res://src/sim/regions.gd")
const RegionFunds = preload("res://src/sim/region_funds.gd")
const Characters = preload("res://src/sim/characters.gd")
const CK = preload("res://src/sim/character_act_constants.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const RegionRead = preload("res://src/sim/region_read.gd")
const Migration = preload("res://src/sim/migration.gd")
const Domains = preload("res://src/ui/domains.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

## A region a figure wants, and one nobody wants (France's data: Delcour wants FRE).
const WANTED := "FRE"
const UNWANTED := "FRB"

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_panel = _main._windows.content("region")
			_check_domain()
			_main._windows.open("region")
		4:
			_check_no_chart()
			_check_worst_first()
			_press(_region_button(WANTED))
		6:
			_check_trend_hidden()
			_check_voice(WANTED)
			_check_strip(WANTED)
			_check_no_priority()
			_seed_history()
			_panel.mark_dirty()
		8:
			_check_trend()
			_check_happening()
			_make_hostile()
			_panel.mark_dirty()
		10:
			_check_hostile()
			_press(_region_button(UNWANTED))
		12:
			_check_nobody()
			_main.queue_free()
		14:
			_finish()
			return true
	return false


func _check_domain() -> void:
	var domain := Domains.domain_of("region")
	if Domains.title(domain) != Strings.t("Regions"):
		_fail("the regions tab sits in a domain titled '%s', not Regions" % Domains.title(domain))


func _check_no_chart() -> void:
	if "_chart" in _panel and _panel._chart != null:
		_fail("the share-of-output chart is still on the tab")


## The rows run worst first, by the problem's own ratio (Regions.problem: the worse of
## jobless and output per head against the nation), every region once.
func _check_worst_first() -> void:
	var ns = _main._state.player()
	var regions: Array = _main._loader.regions.get(ns.id, [])
	var access: Dictionary = Regions.accessibility_for(ns, regions, _main._state.region_graph)
	var sited: Dictionary = _main._state.project_sited_pct.get(ns.id, {})
	var ratio := {}
	for region in regions:
		ratio[String(region.region_name)] = float(Regions.problem(ns, regions, region.id, access, sited, Migration.region_share(ns, region.id))["ratio"])
	var shown: Array = []
	for b in _panel.find_children("*", "Button", true, false):
		if b.toggle_mode and ratio.has((b as Button).text) and b.is_visible_in_tree():
			shown.append(float(ratio[(b as Button).text]))
	if shown.size() != regions.size():
		_fail("%d region rows for %d regions" % [shown.size(), regions.size()])
		return
	for i in range(1, shown.size()):
		if shown[i] > shown[i - 1] + 1e-9:
			_fail("the rows are not worst first: ratio %.3f after %.3f" % [shown[i], shown[i - 1]])
			return


func _check_no_priority() -> void:
	for node in _panel.find_children("*", "", true, false):
		if node.has_meta("priority") or node is OptionButton:
			_fail("the sector priority is still on the sheet (%s)" % node.name)
			return


## Before the sample holds two months there is no change to say, and nothing is said.
func _check_trend_hidden() -> void:
	var line = _with_meta("trend")
	if line != null:
		_fail("the 12-month line shows with %d months held: '%s'" % [_held(), line.text])


func _check_voice(region_id: String) -> void:
	var ns = _main._state.player()
	var person = _wanter(region_id)
	if person == null:
		_fail("premise: nobody in France wants a fund in %s" % region_id)
		return
	var points: float = -CK.SPEAK_SHARE * Characters.brief_magnitude(person, float(ns.person_standing.get(person.id, 0.0))) * OK.APPROVAL_SPAN
	var line = _with_meta("voice")
	if line == null:
		_fail("opened %s: no line says who speaks for it" % region_id)
		return
	var text := _text_of(line)
	if not text.contains(person.person_name) or not text.contains(Num.f(points, 1)):
		_fail("voice line '%s' does not name %s and +%s points" % [text, person.person_name, Num.f(points, 1)])


func _check_nobody() -> void:
	var line = _with_meta("voice")
	if line == null or _text_of(line) != Strings.t("Nobody speaks for this region."):
		_fail("opened %s: the voice line reads '%s'" % [UNWANTED, _text_of(line) if line != null else "<none>"])


func _check_strip(region_id: String) -> void:
	var ns = _main._state.player()
	var est: Dictionary = RegionFunds.estimate(_main._state, ns, _main._loader, region_id,
		float(_panel._fund_share), int(_panel._fund_years))
	var strip = null
	for node in _panel.find_children("*", "", true, false):
		if node.get_script() == EffectsStrip and (node as Control).is_visible_in_tree():
			strip = node
	if strip == null:
		_fail("opened %s: no fund strip" % region_id)
		return
	var text := _text_under(strip)
	var others := Num.f(absf(float(est["others_eur_bn"])), EffectsStrip.MONEY_PLACES)
	if not text.contains(others):
		_fail("fund strip '%s' does not carry the other regions' loss (%s bn)" % [text, others])
	var person = _wanter(region_id)
	if person != null and not text.contains(person.person_name):
		_fail("fund strip '%s' does not say %s speaks" % [text, person.person_name])


## Twelve months written by hand: the region falls from 9.1 to 8.8, every other region
## by 0.1. The line says the region's change and the nation's, weighted by people.
func _seed_history() -> void:
	var ns = _main._state.player()
	for region in _main._loader.regions.get(ns.id, []):
		var drop := 0.3 if String(region.id) == WANTED else 0.1
		var series: Array = []
		for i in 12:
			series.append(9.1 - drop * float(i) / 11.0)
		# The wanted region loses 25 people a month: 300 in the sample, over MIGRATION_SHOWN.
		var moved: Array = []
		for i in 12:
			moved.append(-25.0 if String(region.id) == WANTED else 0.0)
		ns.region_history[String(region.id)] = {"unemployment": series, "gdp_per_head": [], "migration": moved}


func _check_trend() -> void:
	var line = _with_meta("trend")
	if line == null:
		_fail("12 months held: no 12-month line")
		return
	var text := _text_of(line)
	if not text.contains(Num.fs(-0.3, 1)):
		_fail("12-month line '%s' does not say the region's -0.3" % text)
	# The nation's change: every region's, weighted by its people.
	var ns = _main._state.player()
	var sum := 0.0
	var weight := 0.0
	for region in _main._loader.regions.get(ns.id, []):
		var w := Migration.region_share(ns, region.id)
		sum += (-0.3 if String(region.id) == WANTED else -0.1) * w
		weight += w
	if not text.contains(Num.fs(sum / weight, 1) + " "):
		_fail("12-month line '%s' does not say the nation's %s" % [text, Num.fs(sum / weight, 1)])


## People leaving, and where unrest lands when the site is this region.
func _check_happening() -> void:
	var text := _text_under(_panel)
	if not text.contains(Strings.tn("%s people left for other regions in %d month.", "%s people left for other regions in %d months.", 12) % ["300", 12]):
		_fail("the sheet does not say 300 people left in 12 months: '%s'" % text)
	var site: Dictionary = RegionRead.unrest_site(_main._state, _main._state.player())
	if String(site.get("region_id", "")) == WANTED and not text.contains(String(site["city_name"])):
		_fail("the unrest site is %s, in %s, and the sheet does not name it" % [site["city_name"], WANTED])


## A figure at the briefing's grudge threshold does not speak: the sheet says so and the
## strip does not count the voice.
func _make_hostile() -> void:
	var person = _wanter(WANTED)
	_main._state.player().person_grudges[person.id] = CK.GRUDGE_BRIEF_THRESHOLD


func _check_hostile() -> void:
	var person = _wanter(WANTED)
	var line = _with_meta("voice")
	var want := Strings.t("%s wants a development fund here, but bears you a grudge and would not speak for you.") % person.person_name
	if line == null or _text_of(line).strip_edges() != want:
		_fail("hostile figure: the voice line reads '%s'" % (_text_of(line) if line != null else "<none>"))
	for node in _panel.find_children("*", "", true, false):
		if node.get_script() == EffectsStrip and (node as Control).is_visible_in_tree() and _text_under(node).contains(person.person_name):
			_fail("hostile figure: the strip still counts %s's voice" % person.person_name)


# -- helpers --

func _wanter(region_id: String):
	for person in _main._loader.people.get(_main._state.player().id, []):
		for want in person.wants:
			if String(want["object"]) == "region:" + region_id:
				return person
	return null


func _held() -> int:
	for id in _main._state.player().region_history:
		return (_main._state.player().region_history[id]["unemployment"] as Array).size()
	return 0


func _region_button(region_id: String):
	var name := ""
	for region in _main._loader.regions.get(_main._state.player().id, []):
		if String(region.id) == region_id:
			name = String(region.region_name)
	for b in _panel.find_children("*", "Button", true, false):
		if b.toggle_mode and (b as Button).text == name and b.is_visible_in_tree():
			return b
	return null


func _with_meta(key: String):
	for node in _panel.find_children("*", "", true, false):
		if node.has_meta(key) and (node as Control).is_visible_in_tree():
			return node
	return null


func _text_of(node) -> String:
	if node is Label:
		return (node as Label).text
	if node is RichTextLabel:
		return (node as RichTextLabel).get_parsed_text()
	return _text_under(node)


func _press(button) -> void:
	if button == null:
		_fail("frame %d: the control to press is not on screen" % _frame)
		return
	(button as Button).pressed.emit()


func _text_under(node: Node) -> String:
	var out := ""
	for label in node.find_children("*", "Label", true, false):
		out += (label as Label).text + " "
	for rich in node.find_children("*", "RichTextLabel", true, false):
		out += (rich as RichTextLabel).get_parsed_text() + " "
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_region_sheet: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
