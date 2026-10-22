extends SceneTree

## V2.1a step 0. Run: godot --headless --script res://tools/fold_probe.gd
##
## ONE QUESTION, asked before a line of the fold contract was written: **can a
## headless harness see a fold at all?** The plan declared both branches in
## advance -- if it can, the contract is a real test; if it cannot, the contract
## is the runtime mark plus a screenshot-pass assertion and the model doc says so.
##
## tests/test_nation_panel.gd records that it cannot, and records it in enough
## detail to be worth re-testing rather than believing:
##
##     "Two of the panel's labels autowrap, and inside a single-frame headless
##      harness the layout never runs, so an autowrapped label reports the height
##      it would need at ONE WORD PER LINE: 1312px against a true ~700, which
##      reads as a 500px fold that does not exist. ... So a fold is a thing this
##      suite structurally cannot see."
##
## **THE ANSWER IS THAT IT CAN, AND THE OBSERVATION WAS RIGHT WHILE THE DIAGNOSIS
## WAS WRONG.** The layout does run: table (a) shows every panel's `size` equal to
## its own combined minimum, so a sort happened. What an autowrapping Label is
## missing is not TIME but a **width**, and table (b) is the mechanism -- it
## reports the height it needed at the width it had BEFORE the current one, so a
## read in the same call as the write measures the previous state. Table (c) sets
## the width on one frame and reads on the next and the numbers are honest: 1, 2,
## 2, 3, 4 lines as the column narrows, every height an exact multiple of the line.
##
## So the rule is one sentence, and tests/test_panel_kit.gd and
## tests/test_workspace.gd are both staged around it: **impose a width, let a
## frame pass, then read.** Which is what a multi-frame harness does anyway --
## test_nation_panel.gd runs two frames and imposes nothing, and that is the whole
## of why it could not see one.
##
## Measures and prints. Asserts nothing; the assertions live in the two tests.

const UiTheme = preload("res://src/ui/ui_theme.gd")

## U5a's usable band -- the height past which a window grows through the bottom
## furniture and its last row becomes unreachable.
const USABLE_BAND_PX := 886.0

## Long enough to wrap several times at a panel's width and once at a window's.
const SENTENCE := "Germany would refuse a treaty of friendship at present, because the relationship has not recovered from the tariff imposed on its exports last year and the assembly there is in no mood to be seen conceding anything to Paris."

const WIDTHS: Array[float] = [1840.0, 900.0, 600.0, 420.0, 300.0]

var _main
var _host: Control
var _label: Label
var _frame := 0
var _first_min := {}
var _step := 0
var _paired: Array[String] = []


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)

	_host = Control.new()
	root.add_child(_host)
	_host.size = Vector2(1920, 1080)
	UiTheme.apply(_host)

	_label = Label.new()
	_label.text = SENTENCE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host.add_child(_label)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false

	if _frame == 2:
		for id in _main._windows._frames.keys():
			_main._windows.open(id)
		_main._windows.close_all()
		for id in _main._windows._frames.keys():
			var panel := _content_of(id)
			if panel != null:
				_first_min[id] = panel.get_combined_minimum_size()
		return false

	if _frame < 12:
		return false

	# Table (c): one width set per frame, read on the frame after the one that set
	# it. This is the experiment the whole session turned on.
	if _step < WIDTHS.size():
		var w: float = WIDTHS[_step]
		if _frame % 2 == 0:
			_label.custom_minimum_size = Vector2(w, 0)
			_label.size = Vector2(w, 0)
		else:
			var height := _label.get_combined_minimum_size().y
			var lines := _label.get_line_count()
			_paired.append("  width %6.0f -> minimum height %6.0f, %d lines, %.0f per line" % [
				w, height, lines, height / maxf(1.0, float(lines)),
			])
			_step += 1
		return false

	_table_a()
	_table_b()
	_table_c()
	quit(0)
	return true


func _content_of(id: String) -> Control:
	var frame = _main._windows.frame(id)
	if frame == null or frame._content == null:
		return null
	return frame._content


## (a) Does a deferred re-sort ever land, and does any panel report taller than
## the band it has to fit in?
func _table_a() -> void:
	print("")
	print("=== (a) the fourteen registered panels, ten frames apart ===")
	print("%-14s %10s %10s %10s %10s" % ["panel", "min@f2", "min@f12", "size.y", "over band"])

	var moved := 0
	var over := 0
	var total := 0
	for id in _main._windows._frames.keys():
		var panel := _content_of(id)
		if panel == null:
			continue
		total += 1
		var early: Vector2 = _first_min.get(id, Vector2.ZERO)
		var late := panel.get_combined_minimum_size()
		if absf(late.y - early.y) > 1.0:
			moved += 1
		var flag := ""
		if late.y > USABLE_BAND_PX:
			flag = "YES"
			over += 1
		print("%-14s %10.0f %10.0f %10.0f %10s   w=%.0f" % [id, early.y, late.y, panel.size.y, flag, late.x])

	print("")
	print("minimum height changed between the two reads: %d of %d" % [moved, total])
	print("reported taller than U5a's %.0fpx band:        %d of %d" % [USABLE_BAND_PX, over, total])
	print("size.y equal to the minimum for all of them is what says a layout DID run.")


## (b) The lie. Every width set and read inside one call, which is what a
## single-frame harness does.
func _table_b() -> void:
	print("")
	print("=== (b) width set and read in the SAME call -- the trap ===")
	print("%-30s %10s %7s" % ["state", "min.y", "lines"])
	_label.custom_minimum_size = Vector2.ZERO
	_label.size = Vector2(0, 0)
	print("%-30s %10.0f %7d" % [
		"no width imposed at all", _label.get_combined_minimum_size().y, _label.get_line_count(),
	])
	for w in WIDTHS:
		_label.custom_minimum_size = Vector2(w, 0)
		_label.size = Vector2(w, 0)
		print("%-30s %10.0f %7d" % [
			"width %.0f, read immediately" % w,
			_label.get_combined_minimum_size().y,
			_label.get_line_count(),
		])
	print("")
	print("Each height is the answer for the PREVIOUS row's width -- the cache lags one")
	print("invalidation. get_line_count() is current; get_combined_minimum_size() is not.")
	print("With no width at all the label reports one word per line, which is where")
	print("test_nation_panel.gd's 1312px against a true ~700 came from.")


## (c) The truth. Width set on one frame, read on the next.
func _table_c() -> void:
	print("")
	print("=== (c) width set one frame and read the NEXT ===")
	for row in _paired:
		print(row)
	print("")
	print("Monotone in the width, and every height an exact multiple of its own line")
	print("height. THE FOLD IS MEASURABLE HEADLESS. The rule: impose a width, let a")
	print("frame pass, then read.")
