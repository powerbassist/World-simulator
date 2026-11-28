extends Control

## A total walked step by step -- ChartKit.waterfall (G3 S4, the Books page in C: "the deficit is a waterfall").
## The first row is where it stands today, then each change a floating bar from the running total to where the
## change takes it, then the total after them all. One row a bar, its name at the left and its figure at the
## right, signed for a step: the reader is never left to add the steps in the head. Zero is a line down the whole
## chart, behind the bars (the author, 2026-11-28): a baseline is a data mark, not a divider.
##
## Tones (dataviz: status colours carry state, never identity): the two totals are the neutral bar; a step that
## makes the total WORSE is BAD and one that makes it better GOOD (worse_up says which way is worse: the finance
## balance passes false). A dashed connector joins each bar's end to the next bar's start. The colour is never alone:
## every step prints its sign.
##
## With a fold_under, two or more steps smaller than it are ONE row, their sum (the author, 2026-11-28); pressed, it
## shows each of them under it, and pressed again folds. The reader's choice lasts as long as the chart.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Num = preload("res://src/ui/num.gd")
const Strings = preload("res://src/ui/strings.gd")

const LABEL_W := 130.0
const FIGURE_W := 56.0
const BAR_H := 12.0
const ROW_GAP := 1.7
## How far the folded steps' names stand in under their row (at text 100).
const FOLD_INDENT := 14.0

var _rows: Array = []   # [{label, from, to, kind}] kind: "total" or "step"
var _given: Array = []  # setup's own [start, steps, end], laid out again by a press on the fold
var _fold_under := 0.0
var _fold_row := -1
var _unfolded := false
var _fold: LinkButton
var _lo := 0.0
var _hi := 1.0
var _label_w := LABEL_W
var _worse_up := true
var _total_places := 0
var _step_places := 1
var _step_text := Callable()


## `start` and `end` {label, value, figure?} (`figure` is the total's shown text, its value otherwise);
## `steps` [{label, value, keep?}] each a signed change (`keep`: never folded). opts: label_w (at text 100),
## worse_up (true when a rise is bad news, the default; false for a balance), total_places, step_places, and
## step_text (a signed change as the caller words it, unit included; step_places otherwise), fold_under (steps
## smaller than this fold into one row, two at least; none by default).
func setup(start: Dictionary, steps: Array, end: Dictionary, opts := {}) -> void:
	_label_w = float(opts.get("label_w", LABEL_W))
	_worse_up = bool(opts.get("worse_up", true))
	_total_places = int(opts.get("total_places", 0))
	_step_places = int(opts.get("step_places", 1))
	_step_text = opts.get("step_text", Callable())
	_fold_under = float(opts.get("fold_under", 0.0))
	_given = [start, steps, end]
	tooltip_text = " "  # _get_tooltip names the row under the pointer
	_lay()


## The rows from what setup() was given, the fold open or shut as the reader left it.
func _lay() -> void:
	var start: Dictionary = _given[0]
	var end: Dictionary = _given[2]
	var small: Array = _given[1].filter(_is_small)
	_fold_row = -1
	_rows = [{"label": String(start["label"]), "from": 0.0, "to": float(start["value"]), "kind": "total", "figure": String(start.get("figure", ""))}]  # i18n: row-ok chart data, the caller's shown text
	var at := float(start["value"])
	for step in _given[1]:
		if small.size() < 2 or not _is_small(step):
			at = _add_step(String(step["label"]), at, float(step["value"]))  # i18n: row-ok chart data, the caller's shown text
		elif _fold_row < 0:
			at = _add_fold(small, at)
	_rows.append({"label": String(end["label"]), "from": 0.0, "to": float(end["value"]), "kind": "total", "figure": String(end.get("figure", ""))})  # i18n: row-ok chart data, the caller's shown text
	_lo = 0.0
	_hi = 0.0
	for row in _rows:
		_lo = minf(_lo, minf(float(row["from"]), float(row["to"])))
		_hi = maxf(_hi, maxf(float(row["from"]), float(row["to"])))
	if _hi - _lo < 1e-6:
		_hi = _lo + 1.0
	custom_minimum_size = Vector2(0.0, row_height() * _rows.size())
	_place_fold()
	queue_redraw()


func _is_small(step: Dictionary) -> bool:
	return not bool(step.get("keep", false)) and absf(float(step["value"])) < _fold_under


## One step's row from `at`; returns where it takes the running total.
func _add_step(named: String, at: float, delta: float, indent := 0.0) -> float:
	_rows.append({"label": named, "from": at, "to": at + delta, "kind": "step", "delta": delta, "indent": indent})
	return at + delta


## The small steps as one row at the first one's place, and under it, unfolded, each walking from where it starts.
func _add_fold(small: Array, at: float) -> float:
	var sum := 0.0
	for step in small:
		sum += float(step["value"])
	var named := Strings.tn("%d small change", "%d small changes", small.size()) % small.size()
	_fold_row = _rows.size()
	var after := _add_step(("▾ " if _unfolded else "▸ ") + named, at, sum)
	if _unfolded:
		for step in small:
			at = _add_step(String(step["label"]), at, float(step["value"]), FOLD_INDENT)  # i18n: row-ok chart data, the caller's shown text
	return after


## A button over the folded row, so a press or Enter opens it; the chart itself still draws the row.
func _place_fold() -> void:
	if _fold_row >= 0 and _fold == null:
		# A LinkButton: no stylebox padding, so it is the row's own height; its focus box still draws.
		_fold = LinkButton.new()
		_fold.name = "FoldRow"
		_fold.underline = LinkButton.UNDERLINE_MODE_NEVER
		_fold.focus_mode = Control.FOCUS_ALL
		_fold.pressed.connect(func() -> void:
			_unfolded = not _unfolded
			_lay())
		add_child(_fold)
		resized.connect(_place_fold)
	if _fold == null:
		return
	_fold.visible = _fold_row >= 0
	if _fold_row < 0:
		return
	_fold.position = Vector2(0.0, _fold_row * row_height())
	_fold.size = Vector2(size.x, row_height())
	_fold.tooltip_text = _get_tooltip(_fold.position)


func _fs() -> int:
	return roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())


func row_height() -> float:
	return ceilf(_fs() * ROW_GAP)


func _area() -> Vector2:
	var left := _label_w * UiTheme.text_scale()
	return Vector2(left, maxf(size.x - FIGURE_W * UiTheme.text_scale() - left, 1.0))


func x_of(value: float) -> float:
	var area := _area()
	return area.x + (value - _lo) / (_hi - _lo) * area.y


func bar_rect(i: int) -> Rect2:
	var row: Dictionary = _rows[i]
	var a := x_of(minf(float(row["from"]), float(row["to"])))
	var b := x_of(maxf(float(row["from"]), float(row["to"])))
	var h := row_height()
	return Rect2(a, i * h + (h - BAR_H) * 0.5, maxf(b - a, 1.0), BAR_H)


## The zero line: 1 px, the chart's whole height.
func zero_rect() -> Rect2:
	return Rect2(floorf(x_of(0.0)), 0.0, 1.0, row_height() * _rows.size())


func bar_color(i: int) -> Color:
	var row: Dictionary = _rows[i]
	if String(row["kind"]) == "total":
		return UiTheme.NEUTRAL_BAR
	var up := float(row["to"]) > float(row["from"])
	return UiTheme.BAD if up == _worse_up else UiTheme.GOOD


func row_count() -> int:
	return _rows.size()


func label(i: int) -> String:
	return String(_rows[i]["label"])  # i18n: row-ok chart data, the caller's shown text


func figure(i: int) -> String:
	var row: Dictionary = _rows[i]
	if String(row["kind"]) == "total":
		return String(row["figure"]) if String(row["figure"]) != "" else Num.f(float(row["to"]), _total_places)  # i18n: row-ok chart data
	# The step's own value, not to - from: a running sum's float error must not flip the last digit.
	var delta := float(row["delta"])
	if _step_text.is_valid():
		return String(_step_text.call(delta))
	if absf(delta) < 0.5 * pow(10.0, -_step_places):
		return Num.f(0.0, _step_places)  # never "-0.0"
	return Num.fs(delta, _step_places)


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := _fs()
	var h := row_height()
	var label_w := _label_w * UiTheme.text_scale() - 8.0
	draw_rect(zero_rect(), UiTheme.TEXT_DIM)  # first, so every bar draws over it
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var bar := bar_rect(i)
		var base := i * h + (h + fs * 0.7) * 0.5
		var total := String(row["kind"]) == "total"
		var indent := float(row.get("indent", 0.0)) * UiTheme.text_scale()
		draw_string(font, Vector2(indent, base), fit(font, String(row["label"]), label_w - indent, fs), HORIZONTAL_ALIGNMENT_LEFT, label_w - indent, fs,  # i18n: row-ok chart data, the caller's shown text
			UiTheme.TEXT if total else UiTheme.TEXT_DIM, TextServer.JUSTIFICATION_NONE)
		draw_rect(bar, bar_color(i))
		draw_string(font, Vector2(bar.end.x + 6.0, base), figure(i), HORIZONTAL_ALIGNMENT_LEFT, FIGURE_W * UiTheme.text_scale(), fs, UiTheme.TEXT)
		if i + 1 < _rows.size():
			# The connector: from where this bar leaves the running total to the next bar's row.
			# An open fold hands on from its start: its own steps are the walk.
			var x := x_of(float(row["from"] if _unfolded and i == _fold_row else row["to"]))
			draw_dashed_line(Vector2(x, bar.end.y), Vector2(x, (i + 1) * h + (h - BAR_H) * 0.5), UiTheme.LINE_STRONG, 1.0, 3.0)


## `text` cut to `width` with an ellipsis: draw_string neither clips nor trims, so a long change ran over its bar.
static func fit(font: Font, text: String, width: float, fs: int) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
		return text
	var cut := text
	while cut.length() > 1 and font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		cut = cut.left(cut.length() - 1)
	return cut.strip_edges() + "…"


func _get_tooltip(at: Vector2) -> String:
	var i := clampi(int(at.y / row_height()), 0, _rows.size() - 1)
	return "%s: %s" % [String(_rows[i]["label"]), figure(i)]  # i18n: row-ok chart data
