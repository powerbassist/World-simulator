extends SceneTree

## Headless test: godot --headless --script res://tests/test_panel_kit.gd
## Non-zero exit on any failure.
##
## V2.1a's panel system: the primitives, the derived dirty sweep, and the fold
## contract measured against the real panels.
##
## Every assertion here is about an EDGE rather than about a happy path. The
## three bugs the kit exists to prevent were all edges -- a missing key, a
## precision too coarse for its own quantity, two columns measured apart -- and a
## test that only checked that `row()` makes a row would have passed with all
## three of them still in.
##
## Driven a frame at a time with an explicitly sized host, which is the finding
## step 0 of this session paid for: tests/test_nation_panel.gd records that a
## fold cannot be seen headless, and it is measurable after all. See the fold
## section below.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## U5a's usable band -- the height past which a window grows through the bottom
## furniture. tests/test_nation_panel.gd's own constant.
const USABLE_BAND := Vector2(1840, 886)

var _failures: Array[String] = []
var _main
var _host: Control
var _frame := 0
var _fold_rows: Array[String] = []


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)

	_host = Control.new()
	root.add_child(_host)
	_host.size = Vector2(1920, 1080)
	UiTheme.apply(_host)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false

	if _frame == 2:
		_check_missing_key_is_not_a_zero()
		_check_delta_never_prints_a_false_zero()
		_check_tone_reads_the_convention_and_not_the_sign()
		_check_no_panel_builds_its_own_row_any_more()
		_check_no_hand_written_panel_list()
		_check_the_dirty_sweep_is_derived()
		_build_kit_samples()
		_fit_every_window_to_the_band()
		return false

	# One frame for the layout to land. An autowrapping Label reports the height
	# it needed at its PREVIOUS width, so nothing measured here is honest until a
	# frame has passed since the width was imposed.
	if _frame == 3:
		return false

	_check_the_kit_uses_variations_and_not_overrides()
	_check_a_ledger_is_one_measurement()
	_check_the_fold_is_visible_to_this_harness()
	_check_a_panel_reports_the_height_it_draws()
	_report_the_fold_contract()
	_finish()
	return false


# -- The three bugs -------------------------------------------------------------

## V1.6d. `Budget.snapshot()` never carried `gini_effective`, budget_panel.gd read
## it with `.get(key, 0.0)`, and the row printed a confident 0.00 against a live
## 31.80. The distinction the kit has to hold is between a figure that is ZERO and
## a figure that is ABSENT, and a default of 0.0 destroys it.
func _check_missing_key_is_not_a_zero() -> void:
	var snap := {"present": 31.80, "known_absent": null}

	# The next call pushes an error ON PURPOSE -- that is the whole mechanism. Said
	# out loud so a green suite carrying an ERROR line does not read as a failure.
	print("test_panel_kit: the ERROR below is the assertion, not a fault")
	## expects-error: panel_kit: no 'gini_effective' in this snapshot
	var missing := PanelKit.figure_text(snap, "gini_effective")
	if missing != PanelKit.MISSING:
		_fail("a key that is not in the snapshot printed '%s' rather than an em dash" % missing)
	if missing.contains("0"):
		_fail("a missing key printed a digit: '%s'" % missing)

	if PanelKit.figure_text(snap, "known_absent") != PanelKit.MISSING:
		_fail("an explicit null did not print an em dash")

	if PanelKit.figure_text(snap, "present") != "31.80":
		_fail("a present figure did not format: '%s'" % PanelKit.figure_text(snap, "present"))

	# And the one that would have hidden the bug: a snapshot that DOES carry a
	# real zero must print the zero, not the dash.
	if PanelKit.figure_text({"zero": 0.0}, "zero") != "0.00":
		_fail("a genuine zero printed as absent")


## V1.6b. `%+.1f` was copied from the neighbouring row onto `press_stance`, whose
## whole reachable range is 0.145 points, so the readout printed `+0.0` against a
## live figure for a whole session. The row was not wrong about the number -- it
## was wrong about how many places that number lives in.
func _check_delta_never_prints_a_false_zero() -> void:
	var small := PanelKit.delta(0.045)
	if small.contains("0.0") and not small.contains("0.04"):
		_fail("a live 0.045 printed as '%s', which is V1.6b exactly" % small)
	if not small.begins_with("+"):
		_fail("a positive movement lost its sign: '%s'" % small)

	# The press-stance figure that started it, at its own reachable size.
	var stance := PanelKit.delta(0.145, " pts")
	if stance.contains("+0.0 ") or stance == "+0.0 pts":
		_fail("the quantity V1.6b was about still prints as '%s'" % stance)
	if not stance.ends_with(" pts"):
		_fail("the unit was dropped: '%s'" % stance)

	# A number that really is zero prints as zero at the asked precision. The
	# rule is "do not lie", not "always find a digit".
	if PanelKit.delta(0.0) != "+0.0":
		_fail("a true zero printed as '%s' rather than +0.0" % PanelKit.delta(0.0))

	# And a figure comfortably inside the asked precision is left alone.
	if PanelKit.delta(-2.4) != "-2.4":
		_fail("an ordinary movement was re-precisioned to '%s'" % PanelKit.delta(-2.4))


## The convention is the caller's. A falling deficit and a falling approval are
## both negative and only one of them is good news, which is why trends.gd carries
## `worse_when_rising` per figure and the kit refuses to guess.
func _check_tone_reads_the_convention_and_not_the_sign() -> void:
	if PanelKit.tone_for(1.0, true) != PanelKit.Tone.BAD:
		_fail("a rise in a figure that is worse when rising did not read as bad news")
	if PanelKit.tone_for(1.0, false) != PanelKit.Tone.GOOD:
		_fail("a rise in a figure that is better when rising did not read as good news")
	if PanelKit.tone_for(0.0, true) != PanelKit.Tone.PLAIN:
		_fail("a figure that did not move was coloured anyway")


# -- The migration ---------------------------------------------------------------

## No panel builds its own rows any more -- V2.1b, where V2.1a named three paths.
##
## Derived from the directory rather than from a list, for the reason this session's
## other checks are: a list of nineteen panel files is a sixth hand-written list, and
## the one thing this project's record says about such a list is that it drifts.
##
## Two claims, and they catch different things. A panel that still DEFINES one of the
## kit's shapes is a panel where the next session picks the wrong one -- that is the
## check V2.1a wrote. A panel that never NAMES PanelKit is one that quietly kept
## building rows inline, which the first check structurally cannot see, and four of
## the nineteen were exactly that: law, calendar, election and polling had no private
## helper at all and twenty-seven raw Labels between them.
##
## `_right()` and `_add_row()` are deliberately NOT banned. They build a CELL inside
## somebody else's GridContainer -- government's party table carries per-cell tooltips
## and colours, which a ledger cannot -- and every kit primitive that draws prose
## autowraps, so a kit call in a fixed grid column reports a one-word minimum width and
## lets the column collapse. The kit owns whole rows and whole tables; a cell inside
## another grid is the panel's own.
func _check_no_panel_builds_its_own_row_any_more() -> void:
	var banned := ["func _header(", "func _heading(", "func _row(", "func _line(",
		"func _figure(", "func _caption(", "func _add_line(", "func _note(",
		"func _build_column("]
	var checked := 0
	for path in _gd_files("res://src/ui"):
		if not path.ends_with("_panel.gd"):
			continue
		checked += 1
		var source := _read(path)
		if source.is_empty():
			_fail("could not read %s" % path)
			continue
		for name in banned:
			if source.contains(name):
				_fail("%s still carries its own `%s`" % [path, name])
		if not source.contains("PanelKit"):
			_fail("%s builds its rows without the kit" % path)
	if checked < 19:
		_fail("only %d panel files were scanned, and there are nineteen" % checked)


# -- The registry ----------------------------------------------------------------

## The most repeated bug on this project's record, made impossible rather than
## remembered. Three files kept a hand-written list of the same fourteen panel
## names -- main.gd, tools/screenshot.gd and tests/test_shell.gd -- and each was
## written by copying the last. `_people_panel` was missing from main.gd's from
## U6b until V1.4a; `_projects_panel` and `_campaign_panel` were missing from
## screenshot.gd's from V1.6f and V1.7a until V1.8; test_shell.gd's held seven of
## fourteen right up to this session.
##
## So: no file may name three or more panel variables in one place. Two is a
## legitimate pair; three is a list, and a list drifts.
func _check_no_hand_written_panel_list() -> void:
	for path in _gd_files("res://src/ui") + _gd_files("res://tools"):
		if path.ends_with("test_panel_kit.gd"):
			continue
		var source := _read(path)
		var worst := 0
		var worst_line := ""
		# Both bracket shapes. tools/screenshot.gd's fifth list was a DICTIONARY of
		# window id -> member name, so a scanner that only looked at arrays would
		# have reported this file clean while it held the longest list of the five.
		for opener in [["[", "]"], ["{", "}"]]:
			for chunk in source.split(opener[0]):
				var head: String = chunk.split(opener[1])[0]
				if head.length() > 600:
					continue
				var count := 0
				for name in _panel_variable_names():
					if head.contains(name):
						count += 1
				if count > worst:
					worst = count
					worst_line = head.strip_edges().substr(0, 120)
		if worst >= 3:
			_fail("%s names %d panels in one literal -- that is a list, and the registry already knows them: %s"
				% [path, worst, worst_line])


func _panel_variable_names() -> Array[String]:
	var out: Array[String] = []
	for id in _main._windows.panel_ids():
		out.append("_%s_panel" % id)
	# The variable names main.gd actually uses, where they differ from the window id.
	out.append_array(["_overview_panel", "_economy_panel", "_budget_panel", "_polling_panel",
		"_law_panel", "_nation_panel", "_government_panel", "_bloc_panel", "_calendar_panel",
		"_people_panel", "_companies_panel", "_projects_panel", "_campaign_panel",
		"_events_panel", "_region_panel", "_city_panel"])
	return out


## The sweep reaches every registered panel, and it reaches them THROUGH the
## registry rather than through anybody's list. Asserted as a mutation: every
## panel's dirty flag is cleared by hand, one call is made, and every one of them
## must have come back.
func _check_the_dirty_sweep_is_derived() -> void:
	var windows = _main._windows
	var panels: Array = windows.panels()
	if panels.size() < 14:
		_fail("the registry holds only %d panels" % panels.size())

	var dirtyable: Array = []
	for panel in panels:
		if panel.has_method("mark_dirty") and "_dirty" in panel:
			panel._dirty = false
			dirtyable.append(panel)

	windows.mark_all_dirty()

	for panel in dirtyable:
		if not panel._dirty:
			_fail("%s was not reached by the derived sweep" % panel.get_script().resource_path)


# -- The primitives themselves ----------------------------------------------------

var _sample_root: VBoxContainer
var _sample_ledger: GridContainer


func _build_kit_samples() -> void:
	_sample_root = VBoxContainer.new()
	_sample_root.custom_minimum_size = Vector2(600, 0)
	_host.add_child(_sample_root)

	var body := PanelKit.section(_sample_root, "public finances")
	PanelKit.row(body, "Debt", "125.2% of GDP")
	PanelKit.row(body, "Deficit", "-2.86%", PanelKit.Tone.BAD)
	PanelKit.figure(body, "7.67%", "unemployment")
	PanelKit.line(body, "A long enough sentence that it has to wrap somewhere inside the six hundred pixels this sample column has been given, which is the only way to find out whether it wraps at all.")
	PanelKit.heading(_sample_root, "available")

	# One short value and one very long one in the same column: the shape that
	# ran budget_panel's proposed column off the window edge at V1.6f.
	_sample_ledger = PanelKit.ledger(_sample_root, [
		["Health", "0.19%", "0.19% (6 bn) (1 building)"],
		["Defence", "2.00%", "2.0%"],
		["Education", "0.50%", "0.5%"],
	])


## AGENTS.md's styling rule since U3, restated for the kit: colours and the type
## scale come from ui_theme.gd through theme_type_variation, never from an
## override. A kit that reached for add_theme_color_override() would put the
## violation in twenty-five panels at once.
func _check_the_kit_uses_variations_and_not_overrides() -> void:
	for node in _walk(_sample_root):
		if not node is Label:
			continue
		var label: Label = node
		if label.has_theme_color_override("font_color"):
			_fail("a kit label carries a colour override: '%s'" % label.text)
		if label.has_theme_font_size_override("font_size"):
			_fail("a kit label carries a font size override: '%s'" % label.text)

	# And the section heading really is a heading rather than a plain label with
	# a bigger number typed into it.
	var headings := 0
	for node in _walk(_sample_root):
		if node is Label and node.theme_type_variation == UiTheme.HEADING:
			headings += 1
	if headings != 1:
		_fail("section() produced %d headings, expected 1" % headings)


## V1.6f as an assertion. Two value columns that each size to their own widest row
## can drift apart; one grid cannot, because a GridContainer has one width per
## column by construction. What is checked is the consequence: every cell in a
## column starts at the same x.
func _check_a_ledger_is_one_measurement() -> void:
	if _sample_ledger == null or _sample_ledger.get_child_count() < 9:
		_fail("the sample ledger did not build")
		return

	var columns: int = _sample_ledger.columns
	for column in range(columns):
		var first_x := -1.0
		for r in range(3):
			var cell: Control = _sample_ledger.get_child(r * columns + column)
			if first_x < 0.0:
				first_x = cell.position.x
			elif absf(cell.position.x - first_x) > 0.5:
				_fail("ledger column %d starts at %.0f on row 0 and %.0f on row %d"
					% [column, first_x, cell.position.x, r])
				break


# -- The fold ---------------------------------------------------------------------

func _fit_every_window_to_the_band() -> void:
	# The diplomacy panel builds no verbs until it has been pointed at a nation,
	# and it is the panel this contract is named after: all eight of its actions
	# fell below the fold at V1.3e and the same panel paid again at V1.3g.
	_main._nation_panel.show_nation("DEU")
	_main._nation_panel.mark_dirty()
	_main._nation_panel._process(0.0)

	for id in _main._windows.panel_ids():
		var frame = _main._windows.frame(id)
		frame.show()
		frame.fit_within(USABLE_BAND)


## Step 0's finding, pinned so it cannot quietly stop being true.
##
## tests/test_nation_panel.gd records that a fold is "a thing this suite
## structurally cannot see", measured in a harness that runs two frames and
## imposes no width. It is visible after all, and the rule is narrow enough to be
## worth writing down: an autowrapping Label reports the height it needed at its
## PREVIOUS width, so the number is honest one frame after the width was set and
## garbage in the same frame. Set the width, let a frame pass, then read.
func _check_the_fold_is_visible_to_this_harness() -> void:
	var label := Label.new()
	label.text = "A sentence long enough to need several lines once it has a width to wrap against, and exactly one line once it has the whole band."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host.add_child(label)

	label.custom_minimum_size = Vector2(200, 0)
	label.size = Vector2(200, 0)
	var narrow := label.get_line_count()
	label.custom_minimum_size = Vector2(1840, 0)
	label.size = Vector2(1840, 0)
	var wide := label.get_line_count()

	if narrow <= wide:
		_fail("a label wrapped to %d lines at 200px and %d at 1840px -- the layout is not running, and the fold contract below means nothing"
			% [narrow, wide])
	label.queue_free()


## V2.1b's step 0, pinned so it cannot quietly stop being true.
##
## docs/panel-system.md section 7 handed this session two numbers and the claim that
## `get_combined_minimum_size()` is not the truth in either direction -- economy
## reporting 928px for roughly 500px of prose, people reporting 520 and rendering
## about 550. Both were STALE READS: a panel that has never been shown has never been
## laid out at the width it will really have, so its minimum is the answer for a width
## nothing draws. That is this file's own step-0 finding (the minimum-size cache lags
## one invalidation) one level up, applied to the panel instead of to the Label.
##
## Shown and fitted and a frame later, every panel reports its drawn extent to the
## pixel -- fourteen of fourteen -- so no correction shipped and the grow-to-the-band
## heuristic V2.1a deleted was right to be deleted. What is asserted is the property
## that made that true: the reported minimum is the drawn height.
func _check_a_panel_reports_the_height_it_draws() -> void:
	for id in _main._windows.panel_ids():
		var panel: Control = _main._windows.frame(id)._content
		var reported := panel.get_combined_minimum_size().y
		var drawn := _drawn_extent(panel, panel.global_position.y)
		if absf(reported - drawn) > 1.0:
			_fail("%s reports %.0fpx and draws %.0fpx -- a window sized from that leaves %.0fpx of the difference somewhere"
				% [id, reported, drawn, absf(reported - drawn)])


## The bottom of the lowest thing the panel draws, NOT descending into a scroll of
## its own: what is below the fold of an inner ScrollContainer is scrollable rather
## than clipped, and counting it reported legislature 3070px short of itself.
func _drawn_extent(node: Node, top: float) -> float:
	var out := 0.0
	if node is Control and node.visible:
		var c: Control = node
		out = c.global_position.y + c.size.y - top
	if node is ScrollContainer:
		return out
	for child in node.get_children():
		out = maxf(out, _drawn_extent(child, top))
	return out


## THE CONTRACT, ENFORCED -- V2.1b, where V2.1a measured it and said why it could
## not yet assert it.
##
## V2.1a printed this table and failed only on the machinery, because turning it red
## with a panel still folded would have forced a redesign that session was not scoped
## for. Every panel that offers a verb now clears the fold, so it is a failure.
##
## The one that did not was politics, at 39px, and the fix is the contract's own:
## V1.3g proved height alone does not fix a fold -- that panel holds 945px of content
## against an 826px band, so no height exists that would have done it -- and moving
## the verbs above the readout fixes it structurally, at any body size. See
## government_panel._ready().
##
## Three panels report no verb at month 1: bloc has no proposal before the council,
## campaign is outside the run-up and events has nothing pending. That is honest
## rather than a gap in the check -- the panel really has nothing to press -- and the
## screenshot pass reaches all three through --bloc, --campaign and --event, which
## set exactly those states.
func _report_the_fold_contract() -> void:
	for id in _main._windows.panel_ids():
		var frame = _main._windows.frame(id)
		var panel = frame._content
		if not panel.has_method("primary_action"):
			continue
		var action = panel.primary_action()
		if action == null:
			_fold_rows.append("%-12s no verb offered right now" % id)
			continue

		if frame.primary_action_below_fold():
			_fail("%s offers a verb below the fold, and height will not fix it -- move it above the readout" % id)

		var below: bool = frame.primary_action_below_fold()
		_fold_rows.append("%-12s action bottom %5.0f, band %5.0f  %s" % [
			id,
			action.global_position.y + action.size.y - frame._scroll.global_position.y,
			frame._scroll.size.y,
			"BELOW THE FOLD" if below else "reachable",
		])

		frame._process(0.0)
		var expected: String = UiTheme.PLATE_FOLDED if below else UiTheme.PLATE
		if frame.theme_type_variation != expected:
			_fail("%s reports below_fold=%s and wears '%s'" % [id, below, frame.theme_type_variation])


# -- Plumbing ---------------------------------------------------------------------

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return "" if file == null else file.get_as_text()


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, name])
	return out


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	print("test_panel_kit: the fold contract, measured at %s" % str(USABLE_BAND))
	for row in _fold_rows:
		print("  " + row)

	if _failures.is_empty():
		print("test_panel_kit: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
