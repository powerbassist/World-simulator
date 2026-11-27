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
## `has_method("mark_dirty")` and needs no hierarchy to find them, and AGENTS.md
## lists abstract base classes among the things this project does without.
##
## Colours come from `theme_type_variation` and never from an override, which is
## what tests/test_ui_theme.gd enforces. Separations stay here because they are
## this grammar's layout rather than any one panel's.

const UiTheme = preload("res://src/ui/ui_theme.gd")
## The direction vocabulary's home -- progress_fraction() reads it so the kit
## and the content cannot disagree about what "up" means.
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const Num = preload("res://src/ui/num.gd")
const Labels = preload("res://src/ui/labels.gd")
const Strings = preload("res://src/ui/strings.gd")
const TermText = preload("res://src/ui/term_text.gd")
const MeterBar = preload("res://src/ui/meter_bar.gd")
const Icon = preload("res://src/ui/icon.gd")
const Frost = preload("res://src/ui/frost.gd")

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

## Between two buttons of one row of verbs, across and between its lines.
const BUTTON_SEPARATION := 6
## The width a caption-and-value row takes (the void audit of 2026-11-16, shape 3: in a 1 240 px
## page a caption sat at the left and its value 1 000 px away at the right, and the eye could not
## join them). A row fills its host up to this, or up to its stack's widest row; never the page.
const ROW_MEASURE := 440.0
## On a row: the measure it asked for. On a stack: its rows already share one (`_share_measure`).
const MEASURE_META := &"row_measure"
const MEASURED_META := &"rows_measured"
## On a ledger: the ledgers it shares a caption column with (`ledger()`'s `align`).
const ALIGNED_META := &"ledgers_aligned"

## `delta()` will go this far looking for a decimal place that shows movement
## before it gives up and prints the zero honestly. Four is past every unit in
## this game -- a percentage point, a share of GDP, a poll point -- and stops
## the search being unbounded on a figure that really is zero.
const DELTA_MAX_PLACES := 4

## G3's button classes (g3-spec.md section 1), at text size 100 and times the text size: a
## button is one of four widths and one of three heights, never its label's width. Layout,
## so they live here beside sized() and _share_measure(), not in the theme.
enum Size { S, M, L, XL }
const BTN_W := {Size.S: 80, Size.M: 120, Size.L: 168, Size.XL: 232}
const BTN_W_ICON := 36
const BTN_H_ROW := 28
const BTN_H := 36
const BTN_H_MAIN := 44
## The class a button was given; a group's buttons all carry the same one.
const CLASS_META := &"button_class"
const OWN_MIN_META := &"button_own_min"
## same_class()'s group, so a layout test can find buttons that share a class without a flow;
## a flow's own re-sort (_share_class) leaves them to that group's class (G3 S3).
const CLASS_GROUP_META := &"button_class_group"


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
	# A section for N1: a term is marked at its first line in it (term_text.gd).
	body.set_meta(TermText.SECTION_META, {})
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
##
## V5.1-d3, the sweep: a line that MARKS a term or a person ([g=id]word[/g],
## [p=id]Name[/p]) is drawn by rich() -- a TermText, the one place a mark renders --
## and any other line stays the Label it was, so the ~300 sites that mark nothing
## are untouched (a RichTextLabel reports its height differently, and every fit and
## fold test measures these). That makes the result a Control: a site that needs a
## Label (a ticker whose text changes, a row that takes clicks, a tooltip's lines)
## calls plain_line(). A Button's text or a tooltip never goes through either; a
## mark in a string headed there is dropped by TermText.plain().
static func line(parent: Control, text: String, tone := Tone.DIM) -> Control:
	if TermText.has_marks(text):
		return rich(parent, text, tone)
	return plain_line(parent, text, tone)


## line() as it was before d3: always a Label, so its text can be set again.
static func plain_line(parent: Control, text: String, tone := Tone.DIM) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.theme_type_variation = _variation(tone, "")
	parent.add_child(label)
	return label


## V5.1-d1b2 (G9). A person's name, marked for a rich line: hovered it shows their
## card, clicked it pins it (term_text.gd, person_tip.gd). A name with no person
## behind it is just the name.
static func person(person_id: String, name: String) -> String:
	return name if person_id.is_empty() or name.is_empty() else "[p=%s]%s[/p]" % [person_id, name]  # i18n: ok markup


## V5.1-c. line()'s twin for prose that can mark a glossary term ([g=id]word[/g],
## docs/design/glossary-tooltips.md): a TermText, the one place a term is marked,
## wearing the same tone. The inbox's body and the event text use it in c; d moves
## line() itself over.
static func rich(parent: Control, text: String, tone := Tone.DIM) -> RichTextLabel:
	var label := TermText.new()
	label.theme_type_variation = _rich_variation(tone)
	parent.add_child(label)
	label.set_marked(text)
	return label


## A panel's frame: a margin on all four sides and the one column the panel builds
## into. The same seven lines opened nearly every panel's _ready (V5.2-0a moved
## them here when three panels at their size ratchet each needed room for charts).
static func padded(owner: Control, margin_px: int, separation: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, margin_px)
	owner.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	margin.add_child(column)
	return column


## A row of verbs that wraps onto a second line rather than widening its window.
## A flow container's minimum width is its widest button, not the sum of them: a
## firm's seven actions in French were one 1302 px row, and the Companies window
## grew past the screen's edge to hold it (QA on #49).
##
## G3: the row is also a GROUP (the spec's button_group): its buttons share the class the
## longest label needs in the language shown, re-read before every sort, so a label that
## grows in French steps the whole group up a class together.
static func buttons(parent: Control) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", BUTTON_SEPARATION)
	flow.add_theme_constant_override("v_separation", BUTTON_SEPARATION)
	flow.pre_sort_children.connect(_share_class.bind(flow))
	parent.add_child(flow)
	return flow


## One button of a class: its width the class's, its height BTN_H (BTN_H_MAIN for a screen's
## one action, BTN_H_ROW inside a table row), both times the text size.
static func button(text: String, size := Size.M, height := BTN_H) -> Button:
	var b := Button.new()
	b.text = text  # i18n: row-ok the caller passes shown text
	_classed(b, size, height)
	b.set_meta(OWN_MIN_META, b.custom_minimum_size)  # its own class holds inside a group too
	return sized(b)


## The narrowest class that holds `width_px` at the text size in force; XL past it (a label
## too long for XL is a copy problem, not a fifth class).
static func class_for(width_px: float) -> Size:
	for size in [Size.S, Size.M, Size.L]:
		if width_px <= BTN_W[size] * UiTheme.text_scale():
			return size
	return Size.XL


## The class is a floor over what the caller asked for (OWN_MIN_META, read the first time):
## a group re-classes on every sort, and must not wipe a width or height a caller set.
static func _classed(b: Button, size: Size, height: int) -> void:
	if not b.has_meta(OWN_MIN_META):
		b.set_meta(OWN_MIN_META, b.custom_minimum_size)
	b.set_meta(CLASS_META, size)
	var want := Vector2(roundf(BTN_W[size] * UiTheme.text_scale()), roundf(height * UiTheme.text_scale())).max(b.get_meta(OWN_MIN_META))
	if b.custom_minimum_size != want:
		b.custom_minimum_size = want


static func _share_class(flow: Container) -> void:
	var group: Array[Button] = []
	for child in flow.get_children():
		# A verb same_class() put in a wider group keeps that group's class (G3 S3 pass 2).
		if _is_verb(child) and not (child as Button).has_meta(CLASS_GROUP_META):
			group.append(child as Button)
	var widest := 0.0
	for b in group:
		if b.visible:
			widest = maxf(widest, b.get_minimum_size().x)  # the label's own, not the class
	var size := class_for(widest)
	for b in group:
		_classed(b, size, BTN_H)


## A worded verb in the plain, primary or ghost look. An icon button keeps BTN_W_ICON's square,
## a sub-row, cluster or segment is a list entry and a toggle is a chip, not a verb: a class
## would re-lay them.
static func _is_verb(node: Node) -> bool:
	if not node is Button:
		return false
	var b := node as Button
	# A toggle is a chip, which keeps its label's width (spec decision 6); a flat button is a link.
	return b.text != "" and not b.toggle_mode and not b.flat and String(b.theme_type_variation) in ["", UiTheme.PRIMARY, UiTheme.GHOST]


## G3: a SHEET -- one job, opaque, its heading in tracked capitals. Returns the body, as
## section() does.
static func sheet(parent: Control, title := "") -> VBoxContainer:
	var plate := PanelContainer.new()
	plate.theme_type_variation = UiTheme.PLATE
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(plate)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", SECTION_SEPARATION)
	plate.add_child(body)
	if title != "":
		heading(body, title)
	return body


## G3: dresses a chrome container as a glass pane -- UiTheme.PANE and the blur behind it
## (frost.gd). Call it first in the pane's _ready(), before its content. Three panes only: the
## sidebar, the top strip and the time bar (G3 S1); the inbox and the workspace are sheets.
static func pane(panel: PanelContainer) -> PanelContainer:
	panel.theme_type_variation = UiTheme.PANE
	panel.add_child(Frost.new())
	return panel


## G3 S1: a toggle -- a chip, a fold, a picked row -- wears the accent fill while ON (PICKED). A
## plain button held down does not (#436 RECORD, the press flash), so a toggle opts in here;
## test_button_sizes fails a toggle left on the plain look.
## A FLAT toggle (a fold, a picked name) becomes a borderless one, PICKED_ROW: a flat Button draws
## no box, so ON read as OFF, and PICKED's label -- the fill's own, dark under a yellow accent --
## vanished on the bare sheet (#439 pass 2 T6, T7: Design's ruling, a ground and never a hue).
static func toggle(button: Button) -> Button:
	button.toggle_mode = true
	button.theme_type_variation = UiTheme.PICKED_ROW if button.flat else UiTheme.PICKED
	button.flat = false
	return button


## T5 (#400 pass 2): the rows of one stack take one width, the widest row's or the measure, so their
## values line up in a language or a text size where one caption outgrows the measure. Read before
## each sort of the stack: a row's own minimum is its text's, which a refresh changes.
static func _share_measure(stack: Container) -> void:
	var width := 0.0
	for child in stack.get_children():
		if child is Control and (child as Control).visible and child.has_meta(MEASURE_META):
			width = maxf(width, maxf(float(child.get_meta(MEASURE_META)), (child as Control).get_minimum_size().x))
	for child in stack.get_children():
		if child is Control and child.has_meta(MEASURE_META) and (child as Control).custom_maximum_size.x != width:
			(child as Control).custom_maximum_size.x = width


## An action button the size of its label. A Button added straight to a vertical
## box FILLS the box's width -- the V5.1 gate's "le boutton est super large": Dissolve
## and every energy order were 1 200 px slabs. Shrinking to the start keeps it a
## button; in a row or a flow it changes nothing. `test_button_sizes` opens every
## window and fails the one that forgot.
static func sized(button: Button) -> Button:
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return button


## Buttons that answer one question share one width, the widest one's (the author, 2026-11-21:
## "les boutons qui change de taille selon la taille du texte me parait incongru"). After the
## buttons are in the tree with their text, so the theme's font measures them.
static func same_width(buttons: Array) -> void:
	var widest := 0.0
	for b in buttons:
		(b as Control).custom_minimum_size.x = 0.0
		widest = maxf(widest, (b as Control).get_combined_minimum_size().x)
	for b in buttons:
		(b as Control).custom_minimum_size.x = widest


## G3 S2: buttons that answer one question but sit in different rows (the Diary's matrix: See
## them, Call, Delegate, Decline) take ONE class, the one their longest label needs -- a group
## without a flow. Re-read on every call from each button's own minimum, so a redraw with other
## labels steps the class up or down (RECORD H10 on same_width: no stale width survives).
## `height` BTN_H, or BTN_H_ROW for buttons inside a table's rows. A size the caller set before
## the first call is kept as a floor (OWN_MIN_META, _classed()'s contract).
static func same_class(buttons: Array, height := BTN_H) -> void:
	var widest := 0.0
	for b in buttons:
		if not (b as Button).has_meta(OWN_MIN_META):
			(b as Button).set_meta(OWN_MIN_META, (b as Button).custom_minimum_size)
		(b as Button).custom_minimum_size = (b as Button).get_meta(OWN_MIN_META)
		widest = maxf(widest, (b as Button).get_combined_minimum_size().x)
	var size := class_for(widest)
	for b in buttons:
		_classed(b, size, height)
		(b as Button).set_meta(CLASS_GROUP_META, (buttons[0] as Object).get_instance_id())


## Caption left, value right, the value carrying the tone. The single commonest
## shape in this interface: eleven panels build it, and until now each built it
## itself.
##
## `measure` is the row's width (ROW_MEASURE), a cap and not a floor (#400 pass 2, T3: a 440 px floor
## put a sideways bar under the Regions rows in a 438 px host); 0 keeps the row as wide as its host,
## for a card built narrower than the measure (a 260 px person card, a 300 px effects strip).
static func row(parent: Control, left: String, right: String, tone := Tone.PLAIN, measure := ROW_MEASURE) -> HBoxContainer:
	var line_box := HBoxContainer.new()
	line_box.add_theme_constant_override("separation", COLUMN_SEPARATION)
	if measure > 0.0:
		line_box.custom_maximum_size.x = measure
		line_box.set_meta(MEASURE_META, measure)
		if parent is Container and not parent.has_meta(MEASURED_META):
			parent.set_meta(MEASURED_META, true)
			(parent as Container).pre_sort_children.connect(_share_measure.bind(parent))

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


## G3 kit card (R1): what a tile keeps between its edge and its content, on the four sides. It lives
## here and not in the theme's TilePanel box, because slim tiles and row grounds share that box (a
## picked row padded 12 px would shift against its neighbours).
const TILE_PAD := 12


## A tile that pads itself: a TilePanel (or `variation`) holding a MarginContainer of TILE_PAD. Put its
## content in `tile_body(tile)`; the caller adds the tile where it goes. A tile for content that is
## more than a figure; a figure alone is `figure_tile`.
static func padded_tile(variation: String = UiTheme.TILE_PANEL) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.theme_type_variation = variation
	var inset := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		inset.add_theme_constant_override(side, TILE_PAD)
	tile.add_child(inset)
	return tile


## Where a padded tile's content goes.
static func tile_body(tile: PanelContainer) -> MarginContainer:
	return tile.get_child(0) as MarginContainer


## G3: a figure on a tile (the side sheet's, a sector tab's head, the firm sheet). The caption
## does not wrap: a tile is at least its caption's width, so it never runs under the next. Its box is
## `tile_body(tile).get_child(0)`.
static func figure_tile(parent: Control, value: String, caption: String) -> PanelContainer:
	var plate := padded_tile()
	parent.add_child(plate)
	(figure(tile_body(plate), value, caption).get_child(1) as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
	return plate


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


## An aligned table. Every row is [caption, value] or [caption, value, value, ...],
## and because they share one GridContainer the value columns are ONE
## measurement rather than one each.
##
## That is V1.6f as a primitive. The budget panel's proposed column ran off the
## window edge because it and the current column each sized independently to
## their own widest row, so one extra clause on one row of one column widened the
## pair past the frame -- and the number was right the whole time, which is what
## made it hard to see. A grid cannot do that: it has one width per column and
## the panel's own minimum carries it, where the fold contract can find it.
##
## `align`: a ledger this one shares its caption column with (#400 pass 2, T5), for two ledgers in
## sibling sections whose values should start at one x -- Society's blocs and issues.
static func ledger(parent: Control, rows: Array, align: GridContainer = null) -> GridContainer:
	var columns := 2
	for entry in rows:
		columns = maxi(columns, (entry as Array).size())

	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", COLUMN_SEPARATION)
	grid.add_theme_constant_override("v_separation", ROW_SEPARATION)
	# As wide as its columns, not the page (the void pass): the values sit beside their captions.
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	for entry in rows:
		var cells: Array = entry
		for i in range(columns):
			var label := Label.new()
			# V5.3 a + b: a cell may carry its tone as [text, Tone] -- the Budget's
			# change column, toned on the balance's sign.
			var cell = cells[i] if i < cells.size() else ""
			label.text = str(cell[0]) if cell is Array else str(cell)
			if cell is Array:
				label.theme_type_variation = _variation(cell[1], "")
			if i == 0:
				label.theme_type_variation = UiTheme.CAPTION
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			else:
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(label)

	parent.add_child(grid)
	if align != null:
		var group: Array = align.get_meta(ALIGNED_META, [align])
		group.append(grid)
		for member in group:
			(member as Control).set_meta(ALIGNED_META, group)
			if not (member as GridContainer).pre_sort_children.is_connected(_share_captions):
				(member as GridContainer).pre_sort_children.connect(_share_captions.bind(member))
	return grid


## The aligned ledgers' caption columns are as wide as the widest caption of any of them.
static func _share_captions(grid: GridContainer) -> void:
	var group: Array = (grid.get_meta(ALIGNED_META, []) as Array).filter(func(g) -> bool: return is_instance_valid(g))
	var width := 0.0
	for member in group:
		for i in range(0, (member as Node).get_child_count(), (member as GridContainer).columns):
			width = maxf(width, ((member as Node).get_child(i) as Control).get_minimum_size().x)
	for member in group:
		var head := (member as Node).get_child(0) as Control
		if head != null and head.custom_minimum_size.x != width:
			head.custom_minimum_size.x = width


# -- Formatting ---------------------------------------------------------------

## Read a figure out of a snapshot. **A key that is not there is an em dash and
## an error, never a zero.**
##
## `Budget.snapshot()` never carried `gini_effective`, the Budget tab (retired at Finances slice 5) read it
## with `.get(key, 0.0)`, and the row printed a confident `0.00` against a live
## 31.80 for a whole session. A default that hides a missing key is worse than a
## crash, because a crash gets fixed and a plausible number gets quoted. An
## explicit `null` in the dictionary means the same thing and is not an error --
## that is a snapshot saying "not applicable", which several legitimately do.
static func figure_text(source: Dictionary, key: String, places := 2) -> String:
	if not source.has(key):
		push_error("panel_kit: no '%s' in this snapshot; printing an em dash rather than a zero" % key)
		return MISSING
	var value = source[key]
	if value == null:
		return MISSING
	return Num.f(float(value), places)


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


## A population figure at the scale this game prints them: capitals and regions
## in millions to one decimal, everything else in thousands. V2.2b: two panels
## and the map's city hover-label print the same register through the same
## formatter, so they cannot disagree about a rounding no reader could reconcile
## -- figure_text()'s reason, one quantity smaller.
static func pop_text(pop: float) -> String:
	if pop >= 1_000_000.0:
		return "%s M" % Num.f((pop / 1_000_000.0), 1)
	return "%.0f k" % (pop / 1_000.0)


## The 0..1 fraction a programme's progress bar draws -- V4.1. The register
## stores no progress and no start reference (docs/programme-model.md §2: a
## stored progress value could disagree with the live figure it reads, and then
## the panel lies), so the goal is the only scale there is: the fraction is the
## current figure against the goal, taken so the bar completes exactly when the
## goal is met -- `up` fills as the figure climbs to it, `down` as it falls to
## it. One arithmetic here rather than one per surface, pop_text()'s rule: the
## Agenda window, the top-bar strip and the Overview cannot draw three answers
## to one read. The direction vocabulary is the constants file's own and the
## loader refuses an entry outside it. Clamped, and zero rather than NAN on a
## zero denominator -- a goal of zero (balance the books) has no ratio to give.
static func progress_fraction(current: float, goal: float, direction: String) -> float:
	var fills_upward: bool = direction == String(ProgrammeK.PROGRESS_DIRECTIONS[0])
	var frac := 0.0
	if fills_upward:
		if not is_zero_approx(goal):
			frac = current / goal
	elif not is_zero_approx(current):
		frac = goal / current
	return clampf(frac, 0.0, 1.0)


## Which way a movement reads. The convention is the caller's, because the same
## sign is good news for approval and bad news for unemployment -- `trends.gd`
## carries that per figure and this does not guess.
static func tone_for(value: float, worse_when_rising: bool) -> Tone:
	if is_zero_approx(value):
		return Tone.PLAIN
	var bad := (value > 0.0) == worse_when_rising
	return Tone.BAD if bad else Tone.GOOD


static func _rich_variation(tone: Tone) -> String:
	match tone:
		Tone.GOOD:
			return UiTheme.RICH_GOOD
		Tone.BAD:
			return UiTheme.RICH_BAD
		Tone.DIM:
			return UiTheme.RICH_CAPTION
		_:
			return ""


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


## V5.3 (gate 3, top bar A): `value` of `top` as a thin meter with a tick at `mark`, its
## threshold (meter_bar.gd). The caller prints the figure and names the mark in words.
static func meter(parent: Control, value: float, top: float, mark: float) -> Control:
	var bar := MeterBar.new()
	# Decoration by default; a host that hangs a tip on its figure makes it a hover target.
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	bar.setup(value, top, mark)
	return bar


## V5.3 c' (the bureau audit's item 1): a chip -- a bordered caption-size plate with a glyph
## beside its words. `variation` is UiTheme.CHIP or a tone (CHIP_GOOD / CHIP_WARN / CHIP_BAD):
## the tone is on the border and the glyph, the words stay in the text tone, so a state is
## never told by colour alone. `glyph` names a Material Symbol under assets/icons/material/
## ("" for none), read as SVG text (Icon.load_icon), never load()ed.
static func chip(parent: Control, text: String, variation := UiTheme.CHIP, glyph := "") -> PanelContainer:
	var plate := PanelContainer.new()
	plate.theme_type_variation = variation
	# The chip takes its column's width and its words wrap: at the former 130 % or in French a long chip
	# folds onto a second line rather than running past the column.
	plate.size_flags_horizontal = Control.SIZE_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	plate.add_child(row)
	if glyph != "":
		var tones := {UiTheme.CHIP_GOOD: UiTheme.GOOD, UiTheme.CHIP_WARN: UiTheme.WARN, UiTheme.CHIP_BAD: UiTheme.BAD}
		var picture := TextureRect.new()
		var px := roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())
		# A Material Symbols name, or a whole path for a glyph of our own (the hourglass of a deadline).
		var path := glyph if glyph.begins_with("res://") else "res://assets/icons/material/%s.svg" % glyph
		picture.texture = Icon.load_icon(path, tones.get(variation, UiTheme.TEXT_DIM), px)
		picture.set_meta("glyph", path)
		picture.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		picture.custom_minimum_size = Vector2(px, px)
		row.add_child(picture)
	var words := Label.new()
	words.theme_type_variation = UiTheme.CHIP_TEXT
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.text = text
	row.add_child(words)
	parent.add_child(plate)
	return plate


## V5.3 c' (the bureau audit's item 5): a segmented control -- one choice among a few, side by
## side, grouped so one is down. `options` are [{id, label}] (labels already shown text);
## `on_pick` is called with the picked id. The picked segment is a raised control on the ground.
static func segmented(parent: Control, options: Array, selected: String, on_pick: Callable) -> HBoxContainer:
	# G3: the segments sit on a tile ground, 3px inside it.
	var ground := PanelContainer.new()
	ground.theme_type_variation = UiTheme.TILE_PANEL
	ground.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var inset := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		inset.add_theme_constant_override(side, 3)
	ground.add_child(inset)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	inset.add_child(row)
	var group := ButtonGroup.new()
	for o in options:
		var b := Button.new()
		b.theme_type_variation = UiTheme.SEGMENT
		b.toggle_mode = true
		b.button_group = group
		b.text = String(o["label"])  # i18n: row-ok the caller passes shown text
		b.button_pressed = String(o["id"]) == selected
		b.set_meta("segment", String(o["id"]))
		var id := String(o["id"])
		b.pressed.connect(func() -> void: on_pick.call(id))
		row.add_child(b)
	parent.add_child(ground)
	return row
