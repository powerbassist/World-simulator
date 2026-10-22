extends SceneTree

## Headless test: godot --headless --script res://tests/test_dead_ends.gd
## Non-zero exit on any failure.
##
## V5.1-d1b, QA's pre-gate C items (qa-report.md, "PRE-GATE playthrough"):
##   - after "Call it off" the Legislature's header still read "PUT TO THE
##     COUNTRY": the verdict reads the referendum's own outcome once it is gone;
##   - the strip cut the programme's name ("THE THREE PER ..."): the reading is
##     captioned PROGRAMME, the name in its tip;
##   - the programme plate said "Your value: —" on day 1: a dash says nothing,
##     so the line is left out;
##   - "Re-elected on 25.1 % of the vote": the executive is the first-round
##     leader, and the sentence says so rather than reading like a majority;
##   - the Health lever moved 5.3 % of GDP in 38 px: a lever spans five points
##     either side of the committed value, re-centred at each commit;
##   - the Overview printed "-0.00" in red: a service delivery that rounds to
##     nothing is not a line.

const LawVerdict = preload("res://src/ui/law_verdict.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")
const GlossaryLive = preload("res://src/ui/glossary_live.gd")
const SocietyK = preload("res://src/sim/society_constants.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_check_called_off_is_not_put_to_the_country()
	_check_programme_caption()
	_check_no_dash_value()
	_check_executive_wording()
	_check_lever_span()
	_check_no_signed_zero_service()
	_finish()
	return true


func _check_called_off_is_not_put_to_the_country() -> void:
	var ns = _main._state.player()
	var result := {"law_id": "single_term_reform", "passed": true, "referendum_called": true}
	ns.last_referendum_result = {"law_id": "single_term_reform", "passed": false, "withdrawn": true}
	var word: String = LawVerdict.word(result, ns)
	if word == "PUT TO THE COUNTRY" or not word.contains("CALLED OFF"):
		_fail("a referendum called off reads '%s'" % word)
	ns.last_referendum_result = {"law_id": "single_term_reform", "passed": true, "withdrawn": false}
	if not LawVerdict.word(result, ns).contains("CARRIED"):
		_fail("a referendum the country carried reads '%s'" % LawVerdict.word(result, ns))
	ns.last_referendum_result = {}


func _check_programme_caption() -> void:
	var ns = _main._state.player()
	ns.programme.append({
		"entry_id": String(_main._loader.programme[0]["id"]), "chosen_term": int(ns.terms_served), "months_live": 0,
		"status": "active", "concluded_term": -1, "concluded_term_month": -1,
	})
	var r: Dictionary = StripReadings.read("programme", _main._state, _main._loader)
	if r.has("caption"):
		_fail("the programme reading is captioned with its name '%s', which the strip cuts" % r["caption"])
	ns.programme.pop_back()


func _check_no_dash_value() -> void:
	var value: String = GlossaryLive.value("programme_progress", _main._state, _main._loader)
	if value == "—":
		_fail("the programme plate's live value is a dash on a day with no programme")


func _check_executive_wording() -> void:
	var source := FileAccess.get_file_as_string("res://src/ui/election_panel.gd")
	if source.contains("holds the office on %s%% of the vote."):
		_fail("the executive verdict still reads as a share that carried the office")


func _check_lever_span() -> void:
	var panel = _main._budget_panel
	_main._windows.open("budget")
	panel._process(0.0)
	var ns = _main._state.player()
	for key in panel._sliders:
		var slider: HSlider = panel._sliders[key]
		var live: float = float(ns.spending_pct_gdp.get(key, 0.0))
		if slider.max_value - slider.min_value > 2.0 * panel.LEVER_SPAN + 0.001:
			_fail("the %s lever spans %.1f points of GDP; a lever spans %.1f either side" % [key, slider.max_value - slider.min_value, panel.LEVER_SPAN])
		if live < slider.min_value or live > slider.max_value:
			_fail("the %s lever's span [%.1f, %.1f] misses its value %.1f" % [key, slider.min_value, slider.max_value, live])
	_main._windows.close_all()


func _check_no_signed_zero_service() -> void:
	var ns = _main._state.player()
	var key: String = SocietyK.QUALITY_KEYS[0]
	ns.service_quality[key] = float(ns.start_service_quality.get(key, 0.0)) - 0.001
	var panel = _main._overview_panel
	_main._windows.open("overview")
	panel.mark_dirty()
	panel._process(0.0)
	if _text_of(panel).contains("-0.00"):
		_fail("the Overview prints a signed zero: a delivery that rounds to nothing")
	ns.service_quality[key] = float(ns.start_service_quality.get(key, 0.0))
	_main._windows.close_all()


func _text_of(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + "\n"
	elif node is RichTextLabel:
		out += node.get_parsed_text() + "\n"
	for child in node.get_children():
		out += _text_of(child)
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_dead_ends: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
