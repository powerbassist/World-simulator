extends RefCounted

## The primitives every panel builds its body out of -- V2.1a.
##
## Before this, twenty-five panels each invented their own rows: nine of them
## carried twenty-six private `_header` / `_line` / `_row` / `_figure` /
## `_caption` helpers between them, most of them byte-identical and none of them
## agreeing on the edges. Three shipped bugs came out of that and all three are
## edge cases rather than typos, which is why the answer is a shared primitive
## and not another round of per-panel fixes:
##
## * **V1.6b** -- a `%+.1f` copied from the neighbouring row onto a quantity whose
##   whole reachable range is 0.145 points, so a live figure printed `+0.0`.
##   Killed by `delta()`, which widens its own precision until the number it
##   prints is not a lie.
## * **V1.6d** -- `Budget.snapshot()` never carried `gini_effective`, the panel
##   read it with `.get(key, 0.0)`, and the row printed a confident **0.00**
##   against a live 31.80. Killed by `figure_text()`, for which a missing key is
##   an em dash and an error, never a zero.
## * **V1.6f** -- two value columns each sizing to their own widest row until one
##   extra clause pushed the pair past the window edge. Killed by `ledger()`,
##   where the columns are one grid and therefore one measurement.
##
## Static, stateless, `extends RefCounted` -- `trends.gd` and `ui_theme.gd`'s
## shape. Deliberately **not** a base class the panels extend: all nineteen
## already `extends PanelContainer`, the dirty sweep is duck-typed on
## `has_method("mark_dirty")` and needs no hierarchy to find them, and CLAUDE.md
## lists abstract base classes among the things this project does without.
##
## Colours come from `theme_type_variation` and never from an override, which is
## what tests/test_ui_theme.gd enforces. Separations stay here because they are
## this grammar's layout rather than any one panel's.

const UiTheme = preload("res://src/ui/ui_theme.gd")

## What a panel prints when it does not know. An em dash is not a small number:
## it says the figure is absent, where `0.00` says the figure is zero, and the
## difference is the whole of V1.6d.
const MISSING := "—"

## A row's colour, chosen by what the number MEANS rather than by its sign --
## a falling deficit and a falling approval are both negative and only one of
## them is good news. The caller knows which; this does not.
enum Tone { PLAIN, GOOD, BAD, DIM }

## Between a heading and its body, and between two rows of one body. Two
## constants rather than one because a section break has to read as a break.
const SECTION_SEPARATION := 6
const ROW_SEPARATION := 3

## Between a row's caption and its value. Wide enough that a long caption and a
## short value do not read as one string.
const COLUMN_SEPARATION := 12

## `delta()` will go this far looking for a decimal place that shows movement
## before it gives up and prints the zero honestly. Four is past every unit in
## this game -- a percentage point, a share of GDP, a poll point -- and stops
## the search being unbounded on a figure that really is zero.
const DELTA_MAX_PLACES := 4


# -- Structure ----------------------------------------------------------------

## A titled group: the tracked uppercase heading, and the box the rows go in.
## Returns the BODY rather than the group, because every caller wants to add to
## the body and none of them wants the heading back.
static func section(parent: Control, heading: String) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_theme_constant_override("separation", SECTION_SEPARATION)
	parent.add_child(group)

	var label := Label.new()
	label.text = heading.to_upper()
	label.theme_type_variation = UiTheme.HEADING
	group.add_child(label)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", ROW_SEPARATION)
	group.add_child(body)
	return body


## A section heading with no body of its own, for a panel that puts its rows
## straight into one running column. `projects_panel`'s `_header()` and
## `people_panel`'s, which were the same six lines twice.
static func heading(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = UiTheme.MICRO
	parent.add_child(label)
	return label


# -- Content ------------------------------------------------------------------

## A wrapping sentence.
##
## AUTOWRAP_WORD rather than WORD_SMART, and the choice was measured rather than
## taken on taste. The panels disagreed -- twenty-eight WORD against eleven
## WORD_SMART -- and step 0's probe says why it matters beyond appearance: the
## economy panel's own reported minimum height is **928px under WORD and 2602px
## under WORD_SMART**, on identical content at an identical width, because
## WORD_SMART takes far more break opportunities when it is asked to measure
## against a width it has not been given yet. A panel that claims to need 2602px
## for 928px of prose is a panel the fold contract would read a fold into that is
## not there. So the quieter mode is also the honest one.
##
## `Tone.PLAIN` means the panel's own BODY text and sets no variation at all,
## which is `row()`'s existing convention arriving here at V2.1b. It had to: the
## default is DIM and every V2.1a caller wanted it, but government_panel and
## nation_panel built forty-five plain body lines between them, and a primitive
## that could only print small and dim would have silently shrunk and dimmed the
## two panels this project's record names most often. Prose that really is
## secondary keeps the default.
static func line(parent: Control, text: String, tone := Tone.DIM) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.theme_type_variation = _variation(tone, "")
	parent.add_child(label)
	return label


## Caption left, value right, the value carrying the tone. The single commonest
## shape in this interface: eleven panels build it, and until now each built it
## itself.
static func row(parent: Control, left: String, right: String, tone := Tone.PLAIN) -> HBoxContainer:
	var line_box := HBoxContainer.new()
	line_box.add_theme_constant_override("separation", COLUMN_SEPARATION)

	var key := Label.new()
	key.text = left
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.theme_type_variation = UiTheme.CAPTION
	line_box.add_child(key)

	var value := Label.new()
	value.text = right
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if tone != Tone.PLAIN:
		value.theme_type_variation = _variation(tone, "")
	line_box.add_child(value)

	parent.add_child(line_box)
	return line_box


## A large number with its caption underneath. The caption goes below rather
## than above because the eye lands on the figure first and the caption is what
## it needs second -- U5a's arrangement, kept.
##
## The caption wraps, added at V2.1b and measured rather than tidied: the
## overview panel's GOVERNMENT column is about 110px wide, and V1.5a already paid
## for a caption that could not wrap there by having two of them run to eight
## lines. A caption that cannot wrap does not overflow, it widens its column.
static func figure(parent: Control, value: String, caption: String, tone := Tone.PLAIN) -> VBoxContainer:
	var box := VBoxContainer.new()

	var big := Label.new()
	big.text = value
	big.theme_type_variation = UiTheme.FIGURE if tone == Tone.PLAIN else _variation(tone, UiTheme.FIGURE)
	box.add_child(big)

	var sub := Label.new()
	sub.text = caption
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub.theme_type_variation = UiTheme.FIGURE_LABEL
	box.add_child(sub)

	parent.add_child(box)
	return box


## An aligned table. Every row is [caption, value] or [caption, value, value],
## and because they share one GridContainer the value columns are ONE
## measurement rather than one each.
##
## That is V1.6f as a primitive. The budget panel's proposed column ran off the
## window edge because it and the current column each sized independently to
## their own widest row, so one extra clause on one row of one column widened the
## pair past the frame -- and the number was right the whole time, which is what
## made it hard to see. A grid cannot do that: it has one width per column and
## the panel's own minimum carries it, where the fold contract can find it.
static func ledger(parent: Control, rows: Array) -> GridContainer:
	var columns := 2
	for entry in rows:
		columns = maxi(columns, (entry as Array).size())

	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", COLUMN_SEPARATION)
	grid.add_theme_constant_override("v_separation", ROW_SEPARATION)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for entry in rows:
		var cells: Array = entry
		for i in range(columns):
			var label := Label.new()
			label.text = str(cells[i]) if i < cells.size() else ""
			if i == 0:
				label.theme_type_variation = UiTheme.CAPTION
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			else:
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(label)

	parent.add_child(grid)
	return grid


# -- Formatting ---------------------------------------------------------------

## Read a figure out of a snapshot. **A key that is not there is an em dash and
## an error, never a zero.**
##
## `Budget.snapshot()` never carried `gini_effective`, `budget_panel.gd` read it
## with `.get(key, 0.0)`, and the row printed a confident `0.00` against a live
## 31.80 for a whole session. A default that hides a missing key is worse than a
## crash, because a crash gets fixed and a plausible number gets quoted. An
## explicit `null` in the dictionary means the same thing and is not an error --
## that is a snapshot saying "not applicable", which several legitimately do.
static func figure_text(source: Dictionary, key: String, format := "%.2f") -> String:
	if not source.has(key):
		push_error("panel_kit: no '%s' in this snapshot; printing an em dash rather than a zero" % key)
		return MISSING
	var value = source[key]
	if value == null:
		return MISSING
	return format % value


## A signed movement, at whatever precision is needed to show that it moved.
##
## `%+.1f` was copied from the neighbouring row onto `press_stance`, whose whole
## reachable range is 0.145 points, so the readout printed `+0.0` against a live
## figure for a session. The row was not wrong about the number; it was wrong
## about how many places that number lives in. So the precision is not a decision
## the caller has to get right -- this widens it until the digits are not all
## zero, and stops at `places` if the value really is zero.
##
## `unit` is appended verbatim, so a caller passing " pts" gets "+0.42 pts" and
## one passing "%" gets "+0.42%".
static func delta(value: float, unit := "", places := 1) -> String:
	var used := places
	while used < DELTA_MAX_PLACES and not is_zero_approx(value):
		if absf(value) >= 0.5 * pow(10.0, -float(used)):
			break
		used += 1
	return ("%+." + str(used) + "f%s") % [value, unit]


## Which way a movement reads. The convention is the caller's, because the same
## sign is good news for approval and bad news for unemployment -- `trends.gd`
## carries that per figure and this does not guess.
static func tone_for(value: float, worse_when_rising: bool) -> Tone:
	if is_zero_approx(value):
		return Tone.PLAIN
	var bad := (value > 0.0) == worse_when_rising
	return Tone.BAD if bad else Tone.GOOD


static func _variation(tone: Tone, fallback: String) -> String:
	match tone:
		Tone.GOOD:
			return UiTheme.GOOD_TEXT
		Tone.BAD:
			return UiTheme.BAD_TEXT
		Tone.DIM:
			return UiTheme.CAPTION
		_:
			return fallback
