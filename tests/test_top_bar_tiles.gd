extends SceneTree

## Headless test: godot --headless --script res://tests/test_top_bar_tiles.gd
## Non-zero exit on any failure.
##
## Gate 3, G3-10 (the author: "info top bar lacks useful data, i dont know if i got positive
## or negative flux"), and his pick of the top bar pictures, "A : tuiles avec courbes": every
## standing figure is a tile -- its value, its change over Trends' window in words with a
## glyph and a tone, and an 18-month curve where history carries one; the money figure is
## euros a month named "Deficit" or "Surplus"; unrest and the majority are meters against
## their thresholds. Built the way main.gd builds the bar (the script, _ready, the theme).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Budget = preload("res://src/sim/budget.gd")
const Government = preload("res://src/sim/government.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")
const StripSeries = preload("res://src/ui/strip_series.gd")
const TopBar = preload("res://src/ui/top_bar.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Num = preload("res://src/ui/num.gd")
const StripChanges = preload("res://src/ui/strip_changes.gd")
const ChiefCaption = preload("res://src/ui/chief_caption.gd")
const TitleBar = preload("res://src/ui/title_bar.gd")

const SHORT_LINE := "The situation is manageable, barely. It will need your signature."
const LONG_LINE := "The situation is manageable, barely, and it will need your signature before the end of the month, or the assembly will take it out of your hands entirely."
## [text scale, the remark]: the remark in the strip at both sizes, short and past two lines.
## The last stage is past the text sizes the menu offers, so the remark has to fold a tile there.
const STAGES := [[1.0, SHORT_LINE], [1.15, SHORT_LINE], [1.15, LONG_LINE], [1.0, LONG_LINE], [1.6, LONG_LINE]]

var _failures: Array[String] = []
var _loader
var _bar
var _frame := 0
var _caption
var _stage := 0
var _wait := 0
var _folds_shown := 0
var _guard_bar
var _guard_step := 0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	root.size = Vector2i(1920, 1080)
	_bar = load("res://src/ui/top_bar.gd").new()
	_bar.theme = UiTheme.build()
	root.add_child(_bar)
	# Where the shell puts it: right of the 232 px sidebar, the screen's width.
	_bar.position = Vector2(232, TitleBar.HEIGHT)
	_bar.size = Vector2(1920 - 232, TopBar.BAR_HEIGHT)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > 2:
		return _caption_stages()
	if _frame == 1:
		_caption = ChiefCaption.new()  # docked once the bar has run its _ready, as the hud does
		_bar.dock_caption(_caption)
	if _frame < 2:
		return false
	# Before the chief has said anything: the docked remark asks for no room at all.
	if _bar._slot.get_combined_minimum_size().x != 0.0:
		_fail("before any remark the slot asks for %.0f px (the gap before the remark shows)" % _bar._slot.get_combined_minimum_size().x)
	_check_the_money_is_euros_a_month_in_words()
	_check_no_history_draws_no_curve()
	_check_the_curves_and_the_changes()
	_check_the_meters()
	_check_the_tiles_fit_their_slot()
	_check_the_money_curve_is_signed()
	_check_the_tiles_align()
	_check_the_real_strip_fits()
	_check_a_missing_field_is_skipped()
	_check_the_money_threshold_scales()
	_check_curve_and_meter_keep_the_tip()
	_check_a_curve_is_rebuilt_only_on_change()
	_check_an_unmoved_figure_says_steady()
	_check_inflation_has_a_curve()
	_check_tiles_are_divided_by_a_hairline()
	return _caption_stages()


func _state():
	var state = GameState.new_game(_loader, "FRA")
	state.year = 2027
	state.month = 7
	return state


## 18 months of history, the deficit (% of GDP) going from `from` to `to`, unemployment
## from 7.5 to 7.0: the sim's own snapshot, so the series read real keys.
func _with_history(state, from: float, to: float):
	var ns = state.player()
	for i in StripSeries.MONTHS:
		var t := float(i) / float(StripSeries.MONTHS - 1)
		ns.deficit_pct_gdp = lerpf(from, to, t)
		ns.unemployment_pct = lerpf(7.5, 7.0, t)
		state.append_history(Budget.snapshot(state))
	return state


func _check_the_money_is_euros_a_month_in_words() -> void:
	var state = _state()
	var ns = state.player()
	ns.deficit_pct_gdp = 5.3
	_bar.refresh(state, null, _loader)
	var want := Num.f(5.3 / 100.0 * ns.gdp_eur_bn / 12.0, 1)
	var value := String(_bar._figure_values["deficit"].text)
	if not value.begins_with(want) or not ("bn" in value and "€" in value):
		_fail("the money figure reads '%s', not %s bn € a month" % [value, want])
	if String(_bar._figure_captions["deficit"].text) != "DEFICIT, THIS MONTH":
		_fail("a deficit is captioned '%s'" % _bar._figure_captions["deficit"].text)
	ns.deficit_pct_gdp = -1.2
	_bar.refresh(state, null, _loader)
	if String(_bar._figure_captions["deficit"].text) != "SURPLUS, THIS MONTH":
		_fail("a surplus is captioned '%s'" % _bar._figure_captions["deficit"].text)
	var shown := String(_bar._figure_values["deficit"].text)
	if shown.begins_with("-") or shown.begins_with("−") or shown.begins_with("+"):
		_fail("the money figure carries a sign the word already says: '%s'" % shown)


func _check_no_history_draws_no_curve() -> void:
	_bar.refresh(_state(), null, _loader)
	for id in StripSeries.IDS:
		var spark: Control = _bar.spark_of(id)
		if spark != null and spark.visible:
			_fail("%s: a curve is drawn with no history" % id)


func _check_the_curves_and_the_changes() -> void:
	var state = _with_history(_state(), 4.4, 5.3)
	_bar.refresh(state, null, _loader)
	for id in StripSeries.IDS:
		var spark: Control = _bar.spark_of(id)
		if spark == null or not spark.visible:
			_fail("%s: 18 months of history and no curve" % id)
		elif StripSeries.values(id, state).size() != StripSeries.MONTHS:
			_fail("%s: the curve holds %d months, not %d" % [id, StripSeries.values(id, state).size(), StripSeries.MONTHS])
	var money: Label = _bar._changes["deficit"]
	if not money.visible or not ("worse" in money.text and "bn" in money.text and "▼" in money.text):
		_fail("a growing deficit's change reads '%s' (visible %s), not ▼ … bn worse" % [money.text, money.visible])
	elif money.theme_type_variation != UiTheme.BAD_TEXT:
		_fail("a growing deficit's change is not in the bad tone")
	var jobs: Label = _bar._changes["unemployment"]
	if not jobs.visible or not ("better" in jobs.text and "▼" in jobs.text):
		_fail("falling unemployment's change reads '%s', not ▼ … better" % jobs.text)
	elif jobs.theme_type_variation != UiTheme.GOOD_TEXT:
		_fail("falling unemployment's change is not in the good tone")


func _check_the_meters() -> void:
	var state = _state()
	var ns = state.player()
	ns.unrest_pct = 9.0
	_bar.refresh(state, null, _loader)
	var unrest = _bar.meter_of("unrest")
	if unrest == null or not unrest.visible:
		_fail("unrest has no meter")
	elif unrest.value != 9.0 or unrest.top != 100.0 or unrest.mark != UnrestK.UNREST_THRESHOLD_PCT:
		_fail("the unrest meter reads %s of %s marked at %s" % [unrest.value, unrest.top, unrest.mark])
	var seats = _bar.meter_of("assembly")
	if seats == null or not seats.visible:
		_fail("the majority has no meter")
	elif seats.value != float(ns.coalition_seats) or seats.top != float(ns.assembly_seats) \
			or seats.mark != float(Government.majority_seats(ns) + 1):
		_fail("the majority meter reads %s of %s marked at %s" % [seats.value, seats.top, seats.mark])


## The tiles stand in the strip's slot at the largest text size too.
func _check_the_tiles_fit_their_slot() -> void:
	var state = _with_history(_state(), 4.4, 5.3)
	for scale in [1.0, 1.15]:
		UiTheme.set_text_scale(scale)
		_bar.theme = UiTheme.build()
		_bar.refresh(state, null, _loader)
		var h: float = _bar.get_combined_minimum_size().y
		if h > TopBar.BAR_HEIGHT:
			_fail("at text %d %% the tiles need %.0f px; the slot is %d" % [roundi(scale * 100), h, TopBar.BAR_HEIGHT])
	UiTheme.set_text_scale(1.0)
	_bar.theme = UiTheme.build()


## #418 pass 2, the parent's rule: the money's curve is the signed balance, zero line drawn.
func _check_the_money_curve_is_signed() -> void:
	var state = _with_history(_state(), 4.4, 5.3)
	for v in StripSeries.values("deficit", state):
		if v >= 0.0:
			_fail("a deficit's curve holds %s: the curve is the signed balance, a deficit below zero" % v)
			break
	_bar.refresh(state, null, _loader)
	var spark = _bar.spark_of("deficit")
	if spark == null or not bool(spark._zero):
		_fail("the money's curve draws no zero line")


## Gate H6: every tile has the same rows, so the tiles stand aligned whatever they hold.
func _check_the_tiles_align() -> void:
	for state in [_state(), _with_history(_state(), 4.4, 5.3)]:
		_bar.refresh(state, null, _loader)
		var heights := {}
		for id in _bar._boxes.keys():
			var box: Control = _bar._boxes[id]
			if box.visible and box.get_parent() == _bar._figures:
				heights[roundi(box.get_combined_minimum_size().y)] = id
		if heights.size() > 1:
			_fail("the tiles stand at %d heights: %s" % [heights.size(), heights])


## The refreshed strip itself (curves, words, notes, meters) fits beside the chips.
func _check_the_real_strip_fits() -> void:
	var state = _with_history(_state(), 4.4, 5.3)
	for scale in [1.0, 1.15]:
		UiTheme.set_text_scale(scale)
		_bar.theme = UiTheme.build()
		_bar.refresh(state, null, _loader)
		var slot: float = 1920.0 - 232.0 - TopBar.LEFT_GUTTER * 2 - _bar.get_theme_stylebox("panel").get_minimum_size().x
		var used: float = _bar._figures.get_combined_minimum_size().x + _bar._chips_width()
		if used > slot + 0.5:
			_fail("at text %d %% the refreshed strip needs %.0f px of a %.0f px slot" % [roundi(scale * 100), used, slot])
	UiTheme.set_text_scale(1.0)
	_bar.theme = UiTheme.build()


## An older save's month without the field is left out of the curve, never drawn as 0.
func _check_a_missing_field_is_skipped() -> void:
	var state = _with_history(_state(), 4.4, 5.3)
	(state.history[3] as Dictionary).erase("deficit_pct_gdp")
	(state.history[4] as Dictionary).erase("unemployment_pct")
	if StripSeries.values("deficit", state).size() != StripSeries.MONTHS - 1:
		_fail("a month without the deficit is not left out of the money's curve")
	if StripSeries.values("unemployment", state).size() != StripSeries.MONTHS - 1:
		_fail("a month without unemployment is not left out of its curve")
	# An older save's history has no inflation_pct at all: every month is skipped, no curve, no zero.
	for entry in state.history:
		(entry as Dictionary).erase("inflation_pct")
	if StripSeries.values("inflation", state).size() != 0:
		_fail("a history with no inflation_pct draws a curve instead of skipping every month")


## The money's "noticed" bar is a share of the nation's own month of GDP.
func _check_the_money_threshold_scales() -> void:
	var fra = _with_history(_state(), 4.4, 5.3)
	var pol = GameState.new_game(_loader, "POL")
	for i in 3:
		pol.append_history(Budget.snapshot(pol))
	var a: float = StripChanges._noticed_bn(fra)
	var b: float = StripChanges._noticed_bn(pol)
	if not (a > 0.0 and b > 0.0 and b < a):
		_fail("the money's noticed bar does not follow the economy: France %s bn, Poland %s bn" % [a, b])


## Hovering the curve or the meter keeps the tile's tip (#418 pass 2).
func _check_curve_and_meter_keep_the_tip() -> void:
	var state = _with_history(_state(), 4.4, 5.3)
	_bar.refresh(state, null, _loader)
	for node in [_bar.spark_of("unemployment"), _bar.meter_of("unrest")]:
		if node == null:
			_fail("premise: no curve or meter to hover")
			continue
		if node.mouse_filter == Control.MOUSE_FILTER_IGNORE or node.mouse_entered.get_connections().is_empty():
			_fail("%s is not a hover target: the tip drops over it" % node)


func _check_a_curve_is_rebuilt_only_on_change() -> void:
	var state = _with_history(_state(), 4.4, 5.3)
	_bar.refresh(state, null, _loader)
	var first = _bar.spark_of("gdp")
	_bar.refresh(state, null, _loader)
	if _bar.spark_of("gdp") != first:
		_fail("a day with no new month rebuilt the curve")
	state.append_history(Budget.snapshot(state))
	_bar.refresh(state, null, _loader)
	if _bar.spark_of("gdp") == first:
		_fail("a new month did not redraw the curve")


## Top bar A: a figure that has not moved says so ("= steady"), not nothing; no history yet says nothing.
func _check_an_unmoved_figure_says_steady() -> void:
	var state = _state()
	for i in StripSeries.MONTHS:
		state.append_history(Budget.snapshot(state))
	_bar.refresh(state, null, _loader)
	for id in ["deficit", "gdp", "unemployment", "inflation"]:
		var c := StripChanges.change(id, state)
		if c.is_empty() or String(c["text"]) != tr("= steady"):
			_fail("%s did not move and its change reads %s, not '= steady'" % [id, c])
		var label: Label = _bar._changes[id]
		if not label.visible or label.text != tr("= steady"):
			_fail("%s: the tile's change row reads '%s', not '= steady'" % [id, label.text])
	if not StripChanges.change("gdp", GameState.new_game(_loader, "FRA")).is_empty():
		_fail("a game with no history says '= steady' instead of nothing")


## Top bar A: inflation has its 18-month curve like the other three figures with history.
func _check_inflation_has_a_curve() -> void:
	var state = _state()
	var ns = state.player()
	for i in StripSeries.MONTHS:
		ns.inflation_pct = 1.5 + 0.05 * i
		state.append_history(Budget.snapshot(state))
	if not StripSeries.IDS.has("inflation"):
		_fail("inflation is not among the figures with a curve")
	_bar.refresh(state, null, _loader)
	var spark = _bar.spark_of("inflation")
	if spark == null or not spark.visible:
		_fail("inflation: 18 months of history and no curve")


## Top bar A: a 1 px hairline stands between neighbouring tiles.
func _check_tiles_are_divided_by_a_hairline() -> void:
	_bar.refresh(_with_history(_state(), 4.4, 5.3), null, _loader)
	var shown := 0
	for child in _bar._figures.get_children():
		if child.visible and child != _bar._more:
			shown += 1
	if _bar.divider_xs().size() != shown - 1:
		_fail("%d tiles are shown and %d hairlines stand between them" % [shown, _bar.divider_xs().size()])


## Top bar A, redone at #422 pass 2: the chief's remark is a child of the bar's own row, so it is
## inside the strip and over no tile or chip a few frames after it is said (the deferred layout
## is what the first version lost), at text 100 and 115, a long line included. One stage per
## call, frames apart.
func _caption_stages() -> bool:
	if _stage >= STAGES.size():
		if _guard_step < 3:
			_guard_step += 1
			_stage_guard()
			return false
		if _bar._caption_width() != 0.0:
			_fail("a silent chief still keeps %.0f px of the strip" % _bar._caption_width())
		if _bar._slot.get_combined_minimum_size().x != 0.0:
			_fail("a silent chief's slot still asks for %.0f px (the gap before the remark stayed)" % _bar._slot.get_combined_minimum_size().x)
		_finish()
		return true
	var stage: Array = STAGES[_stage]
	if _wait == 0:
		UiTheme.set_text_scale(float(stage[0]))
		_bar.theme = UiTheme.build()
		_bar.refresh(_with_history(_state(), 4.4, 5.3), null, _loader)
		_caption.say(String(stage[1]), null, 60.0)
	_wait += 1
	var label := "text %d %%, %s remark" % [roundi(float(stage[0]) * 100), "long" if stage[1] == LONG_LINE else "short"]
	if _wait == 4:
		_check_the_shown_remark(label, stage)
		_folds_shown = _bar.folded_ids().size()
		_caption.clear()
	if _wait < 8:
		return false
	# Silent again for a few frames: the tiles the remark folded are back.
	if float(stage[0]) > 1.15:
		if _folds_shown == 0:
			_fail("%s: premise: the remark folded no tile, so its room is not measured" % label)
		elif _bar.folded_ids().size() >= _folds_shown:
			_fail("%s: %d tiles folded with the remark, %d once it went: the tiles did not get the room back" % [label, _folds_shown, _bar.folded_ids().size()])
	_wait = 0
	_stage += 1
	UiTheme.set_text_scale(1.0)
	_bar.theme = UiTheme.build()
	return false


## The remark a few frames after it is said: inside the strip, over no tile or chip, the strip
## no taller, the tiles folded to leave it room, the hairlines drawn, the tooltip only when cut.
func _check_the_shown_remark(label: String, stage: Array) -> void:
	var rect: Rect2 = _caption.get_global_rect()
	var bar_rect := Rect2(_bar.global_position, Vector2(_bar.size.x, TopBar.BAR_HEIGHT))
	if not _caption.visible:
		_fail("%s: the remark is not shown" % label)
	# Past the offered text sizes the strip's height is not promised; that stage measures the fold only.
	if float(stage[0]) <= 1.15 and not bar_rect.encloses(rect):
		_fail("%s: the remark %s is not inside the strip %s: it covers what sits under it" % [label, rect, bar_rect])
	if float(stage[0]) <= 1.15 and _bar.get_combined_minimum_size().y > TopBar.BAR_HEIGHT:
		_fail("%s: the remark made the strip %.0f px tall, past its %d" % [label, _bar.get_combined_minimum_size().y, TopBar.BAR_HEIGHT])
	for id in _bar._boxes.keys():
		var box: Control = _bar._boxes[id]
		if box.visible and rect.intersects(box.get_global_rect()):
			_fail("%s: the remark %s overlaps a tile or chip %s" % [label, rect, box.get_global_rect()])
	# The tooltip is the whole line exactly when it is cut at two lines (chief_caption.gd). At the
	# offered sizes the long line may fit; the stage past them (1.6) is where it is cut, so
	# that stage must be, or the cut path is not exercised.
	var cut: bool = _caption._line.get_line_count() > ChiefCaption.MAX_LINES
	if stage[1] == LONG_LINE:
		if float(stage[0]) > 1.15 and not cut:
			_fail("%s: premise: the long line is not cut at two lines, so the tooltip is not exercised" % label)
		if _caption.tooltip_text != (LONG_LINE if cut else ""):
			_fail("%s: the tooltip is '%s' for a line %s" % [label, _caption.tooltip_text, "cut at two lines" if cut else "shown whole"])
	if stage[1] == SHORT_LINE and float(stage[0]) == 1.0 and not _caption.tooltip_text.is_empty():
		_fail("%s: a line shown whole repeats itself as a tooltip" % label)
	var slot: float = 1920.0 - 232.0 - TopBar.LEFT_GUTTER * 2 - TopBar.FIGURE_GAP / 2 - _bar.get_theme_stylebox("panel").get_minimum_size().x
	var used: float = _bar._figures.get_combined_minimum_size().x + _bar._caption_width() + _bar._chips_width()
	if used > slot + 0.5:
		_fail("%s: tiles, remark and chips need %.0f px of a %.0f px strip: the tiles did not fold for the remark" % [label, used, slot])
	if _bar._drawn_dividers == 0 or _bar._drawn_dividers != _bar.divider_xs().size():
		_fail("%s: %d hairlines drawn for %d gaps between tiles" % [label, _bar._drawn_dividers, _bar.divider_xs().size()])

## A remark shown on a bar that then leaves the tree (a load, back to the menu): the deferred
## refit lands outside the tree and must do nothing, not print an error the runner fails on.
func _stage_guard() -> void:
	match _guard_step:
		1:
			_guard_bar = load("res://src/ui/top_bar.gd").new()
			_guard_bar.theme = UiTheme.build()
			root.add_child(_guard_bar)
		2:
			var caption = ChiefCaption.new()
			_guard_bar.dock_caption(caption)
			caption.say(SHORT_LINE, null, 60.0)
			root.remove_child(_guard_bar)  # the deferred refit runs after this, out of the tree
		3:
			_guard_bar.free()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	for f in _failures:
		printerr("FAIL: %s" % f)
	if _failures.is_empty():
		print("test_top_bar_tiles: passed")
	quit(1 if not _failures.is_empty() else 0)
