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
const Elections = preload("res://src/sim/elections.gd")

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
	ns.last_referendum_result = {"law_id": "single_term_reform", "passed": false, "withdrawn": false}
	if not LawVerdict.word(result, ns).contains("REFUSED"):
		_fail("a referendum the country refused reads '%s'" % LawVerdict.word(result, ns))
	# QA on #69: the same law put to the country AGAIN while an older answer is on
	# record is in flight -- the old answer is not this vote's word.
	ns.referendum_pending = {"law_id": "single_term_reform"}
	if LawVerdict.word(result, ns) != "PUT TO THE COUNTRY":
		_fail("a vote still in flight reads its predecessor's outcome: '%s'" % LawVerdict.word(result, ns))
	ns.referendum_pending = {}
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


## Read off the drawn plate (QA on #69: it grepped the source).
func _check_executive_wording() -> void:
	var ns = _main._state.player()
	var result: Dictionary = Elections.resolve_executive(ns, _main._loader.parties.get(ns.id, []), 2027, 5)
	result["incumbent_largest"] = true
	var panel = _main._election_panel
	panel.show_results([result])
	var text := _text_of(panel)
	if not text.contains("first in the vote with"):
		_fail("the executive verdict does not say the share was first in the vote: %s" % text)
	if text.contains("of the vote."):
		_fail("the executive verdict still reads as a share that carried the office")
	panel.hide()


## V5.1-d1b3, the parent's call on QA's #69 finding: the ±5 span stays (the author
## approved it), but the knob reads as the LEVEL -- Education 5.5 and Pensions 14.5
## must not sit in one place -- the span's ends are marked on the track, and a drag
## past one stops there with a cue, not silently.
func _check_lever_span() -> void:
	var panel = _main._budget_panel
	_main._windows.open("budget")
	panel._process(0.0)
	var ns = _main._state.player()
	var ratios := {}
	for key in panel._sliders:
		var slider: HSlider = panel._sliders[key]
		var live: float = float(ns.spending_pct_gdp.get(key, 0.0))
		if slider.min_value != 0.0 or slider.max_value != float(panel.LEVER_MAX[key]):
			_fail("the %s lever's track is [%.1f, %.1f], not the line's whole range" % [key, slider.min_value, slider.max_value])
		ratios[key] = slider.ratio
		var span: Vector2 = panel.lever_span(key)
		if not is_equal_approx(span.x, maxf(0.0, live - panel.LEVER_SPAN)) or not is_equal_approx(span.y, minf(float(panel.LEVER_MAX[key]), live + panel.LEVER_SPAN)):
			_fail("the %s lever's span is %s around %.1f" % [key, span, live])
	if ratios.has("education") and ratios.has("pensions") and is_equal_approx(float(ratios["education"]), float(ratios["pensions"])):
		_fail("Education and Pensions knobs sit in one place: the knob does not read the level")
	var health: HSlider = panel._sliders["health"]
	var top: float = panel.lever_span("health").y
	health.value = top + 4.0
	if not is_equal_approx(health.value, top):
		_fail("a drag past the span's end went to %.1f, not the end %.1f" % [health.value, top])
	if not panel.lever_cued("health"):
		_fail("a drag past the span's end stopped silently: no cue")
	panel._on_revert()
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
