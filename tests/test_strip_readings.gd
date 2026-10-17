extends SceneTree

## Headless test: godot --headless --script res://tests/test_strip_readings.gd
## Non-zero exit on any failure.
##
## V4.8a. The tooltip walker -- the silent-failure class a screenshot cannot see.
## Every strip reading is a register entry (src/ui/strip_readings.gd) whose
## text and tip must be READ from the state, never typed:
##
##   - every reading resolves to the four keys, and a visible reading says
##     something in both its figure and its tip;
##   - every input a reading declares in INPUTS is live: perturb that field and the
##     reading must move -- a tip that stopped reading its input (a hard-coded
##     figure, a renamed field) fails here;
##   - absence reads as a dash: a fresh game has no history, so every six-month
##     change is "—", never a confident "0.0 pp", and no figure prints a bare 0
##     where it means "nothing";
##   - an alert names a window main.gd really registers;
##   - the strip fits a 1920 screen with every reading showing.
##
## The bar is built the way main.gd builds it (the script, _ready and all): a
## Control outside the tree has not run _ready() -- docs/engine-decision.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")
const WindowFrame = preload("res://src/ui/window_frame.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Government = preload("res://src/sim/government.gd")

## Zero is a true level for these, not an absence: nobody angry, nobody moved.
const ZERO_IS_A_LEVEL := ["unrest", "people"]

const SCREEN_WIDTH := 1920.0

var _failures: Array[String] = []
var _loader
var _bar
var _frame := 0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_bar = load("res://src/ui/top_bar.gd").new()
	# The game's theme, as main.gd applies it: without it the labels measure in
	# the engine's default font and the width and height checks pass on a strip
	# smaller than the one that ships (they did, 2026-10-17: 44 px here, 50 drawn).
	_bar.theme = UiTheme.build()
	root.add_child(_bar)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the bar's _ready() run
	_check_every_reading_resolves()
	_check_every_input_is_live()
	_check_absence_reads_as_a_dash()
	_check_alerts_name_real_windows()
	_check_the_strip_fits()
	_finish()
	return false


func _new_state():
	var state = GameState.new_game(_loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game reported %s" % [state.errors])
	return state


func _check_every_reading_resolves() -> void:
	var state = _new_state()
	for id in StripReadings.ORDER:
		if not StripReadings.CAPTIONS.has(id):
			_fail("'%s' has no caption" % id)
		var r: Dictionary = StripReadings.read(id, state, _loader)
		for key in ["text", "tip", "visible", "alert_window"]:
			if not r.has(key):
				_fail("'%s' returned no '%s'" % [id, key])
				return
		if bool(r["visible"]) and (String(r["text"]).is_empty() or String(r["tip"]).is_empty()):
			_fail("'%s' is visible with text '%s' and tip '%s'" % [id, r["text"], r["tip"]])
	if not _bar._figure_values.has(StripReadings.ORDER[0]):
		_fail("the bar built no figure for '%s' -- it is not drawing the register" % StripReadings.ORDER[0])


## The walker proper: perturb each declared input and require the reading to move.
func _check_every_input_is_live() -> void:
	for id in StripReadings.INPUTS.keys():
		if not StripReadings.ORDER.has(id):
			_fail("INPUTS names '%s', which is not on the strip" % id)
		for field in StripReadings.INPUTS[id]:
			var state = _new_state()
			var ns = state.player()
			if not (field in ns):
				_fail("'%s' declares input '%s', which NationState does not have" % [id, field])
				continue
			var before := _reads(id, state)
			var value = ns.get(field)
			if value is Array:
				(value as Array).append({"event_id": "walker", "severity": 3})
			elif value is int:
				ns.set(field, value + 11)
			else:
				ns.set(field, float(value) + 7.3)
			if _reads(id, state) == before:
				_fail("'%s' did not move when its input '%s' changed -- the reading is not read from it" % [id, field])


func _reads(id: String, state) -> String:
	var r: Dictionary = StripReadings.read(id, state, _loader)
	return "%s|%s|%s" % [r["text"], r["tip"], r["alert_window"]]


## A new game has no history, so every six-month change is unknown, not zero.
func _check_absence_reads_as_a_dash() -> void:
	var state = _new_state()
	if not state.history.is_empty():
		_fail("a new game already carries %d history entries -- the fixture moved" % state.history.size())
	for id in ["approval", "deficit", "gdp", "unemployment"]:
		var tip := String(StripReadings.read(id, state, _loader)["tip"])
		if not tip.contains("—"):
			_fail("'%s' has no history and its tip reads '%s' -- an unknown change must be a dash" % [id, tip])
		if tip.contains("0.0 pp"):
			_fail("'%s' prints a confident '0.0 pp' with no history: '%s'" % [id, tip])
	var bare_zero := RegEx.create_from_string("^[+-]?0(\\.0+)?%?$")
	for id in StripReadings.ORDER:
		if ZERO_IS_A_LEVEL.has(id):
			continue
		var r: Dictionary = StripReadings.read(id, state, _loader)
		if bool(r["visible"]) and bare_zero.search(String(r["text"])) != null:
			_fail("'%s' prints a bare '%s' -- an absence must read as a dash" % [id, r["text"]])


## Stage every alert the register can raise, then require each named window to be
## one main.gd registers -- read off main.gd's own register() calls, so a renamed
## window fails here rather than as an alert pointing nowhere.
func _check_alerts_name_real_windows() -> void:
	var registered := {}
	var src := FileAccess.get_file_as_string("res://src/ui/main.gd")
	for m in RegEx.create_from_string("_windows\\.register\\(\"([a-z_]+)\"").search_all(src):
		registered[m.get_string(1)] = true
	if registered.is_empty():
		_fail("read no window ids out of main.gd -- the scan moved")
		return

	var state = _new_state()
	var ns = state.player()
	ns.unrest_pct = UnrestK.UNREST_THRESHOLD_PCT + 1.0
	ns.is_minority = true
	ns.event_queue.append({"event_id": "walker", "severity": 3})
	var staged_treaty := false
	for org_id in Orgs.council_ids(state):
		if ns.orgs.has(org_id):
			state.orgs[org_id]["ratifying"] = {
				"name": "Walker treaty", "months_left": 2,
				"nations": {ns.id: CouncilK.RATIFY_PENDING},
			}
			staged_treaty = true
			break
	if not staged_treaty:
		_fail("FRA sits on no council -- the Europe alert cannot be staged")
	# A good nobody covers: demand with nothing made and nothing bought.
	var good_id := String(_loader.commodity_goods.keys()[0])
	ns.commodity_state = {"demand": {good_id: 100.0}, "output": {good_id: 0.0}, "trade": {good_id: 0.0}}

	var alerting := 0
	for id in StripReadings.ORDER:
		var window := String(StripReadings.read(id, state, _loader)["alert_window"])
		if window.is_empty():
			continue
		alerting += 1
		if not registered.has(window):
			_fail("'%s' alerts toward '%s', which main.gd registers no window for" % [id, window])
	# unrest, assembly, desk, europe, commodities -- every alert the register has.
	if alerting < 5:
		_fail("only %d of 5 staged alerts fired" % alerting)

	# The bar turns an alerting figure to the alert tone and names the window.
	_bar.window_hints["economy"] = "Economy (E)"
	_bar.refresh(state, null, _loader)
	var unrest: Label = _bar._figure_values["unrest"]
	if unrest.theme_type_variation != "FigureAlert":
		_fail("an alerting unrest reading is drawn as '%s', not the alert tone" % unrest.theme_type_variation)
	if not String(unrest.tooltip_text).contains("Economy (E)"):
		_fail("the unrest alert does not name its window and key: '%s'" % unrest.tooltip_text)
	# The assembly margin is seats beyond the BARE majority (more than
	# majority_seats): exactly majority_seats is one short and must read "-1".
	ns.is_minority = false
	ns.coalition_seats = Government.majority_seats(ns)
	var margin_text := String(StripReadings.read("assembly", state, _loader)["text"])
	if margin_text != "-1":
		_fail("a coalition of exactly majority_seats reads '%s', not '-1' -- it is one seat short" % margin_text)


## Every reading showing at once must fit a 1920 screen beside the tools, each at
## the WIDEST text it can realistically print -- not whatever a staged state
## happens to say (a bare new_game has no date, so its vote countdown reads five
## digits no game shows). The longest commodity name is read off the loader, so
## a content edit that adds a longer one re-measures here.
func _check_the_strip_fits() -> void:
	var longest := ""
	for good_id in _loader.commodity_goods.keys():
		var n := String(_loader.commodity_goods[good_id].name)
		if n.length() > longest.length():
			longest = n
	var widest := {
		"approval": "100% ▼", "deficit": "-10.50%", "gdp": "12345 Bn ▲",
		"unemployment": "12.34%", "inflation": "10.5%", "unrest": "100",
		"assembly": "+123", "election": "60 mo", "programme": "100%",
		"desk": "12 pending", "europe": "Treaty: 12m", "commodities": "%s 18%%" % longest,
		"people": "1595",
	}
	for id in StripReadings.ORDER:
		if not widest.has(id):
			_fail("'%s' has no widest text -- the width check cannot measure it" % id)
			continue
		var value: Label = _bar._figure_values[id]
		value.get_parent().visible = true
		value.text = widest[id]
		value.theme_type_variation = "FigureAlert"
	var programme: Label = _bar._figure_captions["programme"]
	programme.text = "A PROGRAMME NAME FAR LONGER THAN ANY STRIP COULD HOLD"
	# The height half: the stacked figures must sit inside the frames' TOP_MARGIN,
	# or every window loses band height (the 826px fold arithmetic).
	var height: float = _bar.get_combined_minimum_size().y
	if height > WindowFrame.TOP_MARGIN:
		_fail("the strip is %.0f px tall; windows start at %.0f" % [height, WindowFrame.TOP_MARGIN])
	var figures: float = _bar._figures.get_combined_minimum_size().x
	var tools: float = _bar._tools.get_combined_minimum_size().x
	if figures + tools > SCREEN_WIDTH:
		_fail("the strip needs %.0f px (figures %.0f + tools %.0f) on a %.0f px screen" % [
			figures + tools, figures, tools, SCREEN_WIDTH])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_strip_readings: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
