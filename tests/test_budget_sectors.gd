extends SceneTree

## Headless test: godot --headless --script res://tests/test_budget_sectors.gd
## Non-zero exit on any failure.
##
## V5.3 a + b, docs/design/v5.3-ab.md 3.1 "What the player reads before acting" (#255,
## #258): each spending line of the Budget opens as a tile -- the line's total, its
## sectors as bars with their quantity -- and the quantified verb, move a share
## between two sectors of the line, with its strip: no money (a pure reallocation),
## both quantities before and after, and what the move does to the line's channel
## (Sectors.factor), read off Sectors.move_share() on a copy of the state. A move the
## sim refuses (a sector under its floor) greys Move and prints the sim's line.
##
## Driven through the real controls a frame apart.

const Sectors = preload("res://src/sim/sectors.gd")
const DK = preload("res://src/sim/domains_constants.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

const LINE := "health"

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_panel = _main._budget_panel
			_main._windows.open("budget")
		4:
			_press(_with_meta("line", LINE))
		6:
			_check_tile()
			_pick("hospitals", "prevention", 0.02)
		8:
			_check_strip("hospitals", "prevention", 0.02)
			_press(_with_meta("move", "move"))
		10:
			_check_moved("hospitals", "prevention", 0.02)
			_pick("prevention", "hospitals", 0.05)
		12:
			_check_refused()
			_finish()
	return false


## The tile: one bar per sector, each with its share and its quantity, the sim's.
func _check_tile() -> void:
	var ns = _main._state.player()
	var loader = _main._loader
	var shares := Sectors.shares(ns, loader, LINE)
	for sector in Sectors.sectors_of(loader, LINE):
		var id := String(sector["id"])
		var row = _with_meta("sector", id)
		if row == null:
			_fail("tile: no row for %s" % id)
			continue
		var text := _text_under(row.get_parent())
		var q := Num.f(Sectors.quantity(ns, loader, LINE, id), 2)
		if not text.contains(q):
			_fail("tile %s: '%s' does not carry its quantity %s" % [id, text, q])
		var bar = row.get_meta("bar")
		if bar == null or absf(float(bar.value) - 100.0 * float(shares[id])) > 0.001:
			_fail("tile %s: the bar reads %s, the share is %s" % [id, bar.value if bar != null else "<none>", shares[id]])


func _pick(from_id: String, to_id: String, amount: float) -> void:
	var from: OptionButton = _with_meta("from", "from")
	var to: OptionButton = _with_meta("to", "to")
	var slider: HSlider = _with_meta("amount", "amount")
	if from == null or to == null or slider == null:
		_fail("verb: the from, to and amount controls are not all on screen")
		return
	_select(from, from_id)
	_select(to, to_id)
	slider.value = amount


func _select(option: OptionButton, id: String) -> void:
	for i in option.item_count:
		if String(option.get_item_metadata(i)) == id:
			option.select(i)
			option.item_selected.emit(i)
			return
	_fail("verb: no '%s' in a sector picker" % id)


## The strip reads Sectors.move_share() on a copy: both quantities after the move.
func _check_strip(from_id: String, to_id: String, amount: float) -> void:
	var copy = _main._state.duplicate_state()
	var cns = copy.player()
	var loader = _main._loader
	var r: Dictionary = Sectors.move_share(cns, loader, LINE, from_id, to_id, amount)
	if not bool(r.get("ok", false)):
		_fail("premise: the move %s -> %s refused: %s" % [from_id, to_id, r])
		return
	var strip = null
	for node in _panel.find_children("*", "", true, false):
		if node.get_script() == EffectsStrip and (node as Control).is_visible_in_tree() and node.has_meta("sectors"):
			strip = node
	if strip == null:
		_fail("strip: no sector-move strip on screen")
		return
	var text := _text_under(strip)
	for id in [from_id, to_id]:
		var after := Num.f(Sectors.quantity(cns, loader, LINE, id), 2)
		if not text.contains(after):
			_fail("strip: '%s' does not carry %s after the move (%s)" % [text, id, after])
	if strip.money_label.text != EffectsStrip.cost_text(0.0):
		_fail("strip: a reallocation reads '%s', it moves no money" % strip.money_label.text)


func _check_moved(from_id: String, to_id: String, amount: float) -> void:
	var ns = _main._state.player()
	var start := {}
	for sector in Sectors.sectors_of(_main._loader, LINE):
		start[String(sector["id"])] = float(sector["start"]["FRA"]["share"])
	var now := Sectors.shares(ns, _main._loader, LINE)
	if absf(float(now[from_id]) - (float(start[from_id]) - amount)) > 0.0001 or absf(float(now[to_id]) - (float(start[to_id]) + amount)) > 0.0001:
		_fail("Move pressed: shares %s, expected %s -%s and %s +%s" % [now, from_id, amount, to_id, amount])


## Prevention under its floor: Move greyed, the sim's line under it.
func _check_refused() -> void:
	var move: Button = _with_meta("move", "move")
	if move == null or not move.disabled:
		_fail("refused: Move is live for a move under the sector's floor")
	var line = _with_meta("refusal", "refusal")
	if line == null or not (line as Control).is_visible_in_tree() or (line as Label).text != Strings.t("A sector cannot fall under its floor."):
		_fail("refused: no visible line says why (%s)" % [line.text if line != null else "<none>"])


# -- helpers --

func _with_meta(key: String, value: String):
	for node in _panel.find_children("*", "", true, false):
		if node.has_meta(key) and str(node.get_meta(key)) == value and (node as Control).is_visible_in_tree():
			return node
	return null


func _press(button) -> void:
	if button == null:
		_fail("frame %d: the control to press is not on screen" % _frame)
		return
	(button as Button).pressed.emit()


func _text_under(node: Node) -> String:
	var out := ""
	for label in node.find_children("*", "Label", true, false):
		out += (label as Label).text + " "
	if node is Label:
		out += (node as Label).text
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_budget_sectors: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
