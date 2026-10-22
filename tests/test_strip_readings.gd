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
const WindowManager = preload("res://src/ui/window_manager.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Government = preload("res://src/sim/government.gd")
const StripChildren = preload("res://src/ui/strip_children.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

## Zero is a true level for these, not an absence: nobody angry, nobody moved.
const ZERO_IS_A_LEVEL := ["unrest"]

const SCREEN_WIDTH := 1920.0

## Level-1 lines that open a child once every child is staged: the three approval
## issues, then debt, coalition, programme entries, the desk, the rules, the
## shortage. A count, so a register edit that quietly drops a child_id fails.
const EXPECTED_CHILD_LINES := 9

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
	_check_tip_is_derived_from_lines()
	_check_every_input_is_live()
	_check_absence_reads_as_a_dash()
	_check_alerts_name_real_windows()
	_check_the_strip_fits()
	_check_every_child_resolves()
	_check_child_inputs_are_live()
	_check_a_missing_history_reads_as_a_dash_at_level_two()
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
		for key in ["text", "tip", "visible", "alert_window", "lines"]:
			if not r.has(key):
				_fail("'%s' returned no '%s'" % [id, key])
				return
		if bool(r["visible"]) and (String(r["text"]).is_empty() or String(r["tip"]).is_empty()):
			_fail("'%s' is visible with text '%s' and tip '%s'" % [id, r["text"], r["tip"]])
	if not _bar._figure_values.has(StripReadings.ORDER[0]):
		_fail("the bar built no figure for '%s' -- it is not drawing the register" % StripReadings.ORDER[0])


## V4.8b. A reading's tip is its level-1 lines joined: one source for the tooltip,
## so the popup (which draws the lines) and the plain tip (which the walker and
## tip_of read) cannot say two things.
func _check_tip_is_derived_from_lines() -> void:
	var state = _new_state()
	for id in StripReadings.ORDER:
		var r: Dictionary = StripReadings.read(id, state, _loader)
		var texts: Array[String] = []
		for line in (r["lines"] as Array):
			texts.append(String(line["text"]))
		if String(r["tip"]) != "\n".join(texts):
			_fail("'%s' tip is not its lines joined -- two sources for one tooltip" % id)


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
	_stage_every_alert(state)

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
	if not _bar.tip_of("unrest").contains("Economy (E)"):
		_fail("the unrest alert does not name its window and key: '%s'" % _bar.tip_of("unrest"))
	# The assembly margin is seats beyond the BARE majority (more than
	# majority_seats): exactly majority_seats is one short and must read "-1".
	ns.is_minority = false
	ns.coalition_seats = Government.majority_seats(ns)
	var margin_text := String(StripReadings.read("assembly", state, _loader)["text"])
	if margin_text != "-1":
		_fail("a coalition of exactly majority_seats reads '%s', not '-1' -- it is one seat short" % margin_text)


## Every alert the register can raise, staged on one state.
func _stage_every_alert(state) -> void:
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


## The alerts plus the three things only a child needs: a running programme entry,
## a council rule that binds, and (FRA's new game already seats a coalition).
func _stage_every_child(state) -> void:
	_stage_every_alert(state)
	var ns = state.player()
	ns.programme.append({
		"entry_id": String(_loader.programme[0]["id"]), "chosen_term": 0, "months_live": 0,
		"status": "active", "concluded_term": -1, "concluded_term_month": -1,
	})
	for org_id in Orgs.council_ids(state):
		if ns.orgs.has(org_id):
			state.orgs[org_id]["rules"]["walker_rule"] = {
				"name": "Walker rule", "field": "deficit_pct_gdp", "op": "<=",
				"value": -50.0, "severity": 1.0, "tolerance": 1.0,
			}
			break


## Level 2: every child_id a level-1 line carries must resolve to a real
## breakdown, and every issue the game can rank must have one -- a new issue
## added to ISSUE_LABEL without a child fails here, not in a playtest.
func _check_every_child_resolves() -> void:
	var state = _new_state()
	_stage_every_child(state)
	var seen := 0
	for id in StripReadings.ORDER:
		var r: Dictionary = StripReadings.read(id, state, _loader)
		for line in (r["lines"] as Array):
			var cid := String(line["child_id"])
			if cid.is_empty():
				continue
			seen += 1
			var c: Dictionary = StripChildren.child(id, cid, state, _loader)
			if c.is_empty() or (c["lines"] as Array).is_empty() or String(c["title"]).is_empty():
				_fail("'%s' line '%s' opens child '%s', which resolves to nothing" % [id, line["text"], cid])
	if seen != EXPECTED_CHILD_LINES:
		_fail("%d child lines appeared, %d expected" % [seen, EXPECTED_CHILD_LINES])
	for issue in OpinionK.ISSUE_LABEL.keys():
		if StripChildren.child("approval", "issue:%s" % issue, state, _loader).is_empty():
			_fail("issue '%s' has no level-2 breakdown" % issue)
	# The baseline each issue is priced against, named truthfully: growth is priced
	# against the nation's trend, not where it began (the review caught "at the start").
	var growth: Dictionary = StripChildren.child("approval", "issue:growth", state, _loader)
	if not String((growth["lines"] as Array)[0]).contains("trend"):
		_fail("the growth breakdown does not say it is priced against the trend: %s" % [growth["lines"]])
	var jobs: Dictionary = StripChildren.child("approval", "issue:jobs", state, _loader)
	if not String((jobs["lines"] as Array)[0]).contains("at the start"):
		_fail("the jobs breakdown does not say it is priced against the start: %s" % [jobs["lines"]])
	if not StripChildren.child("approval", "no-such-child", state, _loader).is_empty():
		_fail("an unknown child id resolved -- the lookup is a catch-all")
	if not StripChildren.child("gdp", "debt", state, _loader).is_empty():
		_fail("a child resolved under the wrong reading -- the lookup ignores the reading id")


## The children are read from the state, never typed: perturb the input a child
## reports and require the child to move (the level-1 walker's shape).
func _check_child_inputs_are_live() -> void:
	var state = _new_state()
	_stage_every_child(state)
	var ns = state.player()
	var probes := [
		# Line 0 only: the satisfaction line below it moves with the same input and
		# would hide a hard-coded operands line (the mutation check caught exactly that).
		["approval", "issue:jobs", "unemployment_pct", 4.0, 0],
		["deficit", "debt", "debt_eur_bn", 900.0],
		["desk", "queue", "event_queue", null],
		["commodities", "short", "commodity_state", null],
		["assembly", "coalition", "coalition_party_ids", null],
	]
	for probe in probes:
		var before := _child_key(probe, state)
		var field: String = probe[2]
		match field:
			"event_queue":
				ns.event_queue.append({"event_id": "walker_two", "severity": 1})
			"commodity_state":
				var good_id := String(_loader.commodity_goods.keys()[0])
				ns.commodity_state["demand"][good_id] = 100.0
				ns.commodity_state["output"][good_id] = 10.0
			"coalition_party_ids":
				ns.seats_by_party["walker_party"] = 7
				ns.coalition_party_ids.append("walker_party")
			_:
				ns.set(field, float(ns.get(field)) + float(probe[3]))
		var after := _child_key(probe, state)
		if before == after:
			_fail("child '%s/%s' did not move when '%s' changed -- it is not read from it" % [probe[0], probe[1], field])


func _child_key(probe: Array, state) -> String:
	var c: Dictionary = StripChildren.child(probe[0], probe[1], state, _loader)
	if probe.size() > 4:
		return String((c["lines"] as Array)[int(probe[4])])
	return JSON.stringify(c)


## A new game has no history: the debt path's older rows are a dash, not 0.0.
func _check_a_missing_history_reads_as_a_dash_at_level_two() -> void:
	var state = _new_state()
	var c: Dictionary = StripChildren.child("deficit", "debt", state, _loader)
	var dashes := 0
	for line in (c["lines"] as Array):
		if String(line).ends_with("—"):
			dashes += 1
	if dashes != StripChildren.DEBT_PATH_MONTHS.size():
		_fail("the debt path prints %d dashes with no history, expected %d: %s" % [
			dashes, StripChildren.DEBT_PATH_MONTHS.size(), c["lines"]])


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
	# The height half: the stacked figures must sit above the dock's top (V5.1-c2.2;
	# the floating frames' TOP_MARGIN before it), or the strip covers the tabs.
	var height: float = _bar.get_combined_minimum_size().y
	if height > WindowManager.DOCK_TOP:
		_fail("the strip is %.0f px tall; the dock starts at %.0f" % [height, WindowManager.DOCK_TOP])
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
