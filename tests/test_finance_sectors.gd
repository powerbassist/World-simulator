extends SceneTree

## Headless test: godot --headless --script res://tests/test_finance_sectors.gd
## Non-zero exit on any failure.
##
## V5.3 Finances slice 5 (docs/design/v5.3-ab.md 3.1, #255/#258, re-homed from the Budget tab): a spending row of the
## Books opens its sectors under its editor -- a bar per sector with its quantity, and the quantified verb, move a share
## between two of them, with its strip: no money (a pure reallocation), both quantities before and after, and what the
## move does to the line's channel (Sectors.factor), read off Sectors.move_share() on a copy of the state. A move the sim
## refuses (a sector under its floor) greys Move and prints the sim's line.
##
## A MOVE IS A ROW OF THE DRAFT BUT NOT OF THE BILL (Gameplay's ruling): the footer says so ("Apply the moves", or one
## more line beside "Table the changes"), the move books at once on the footer's verb, a refused tabling books it all
## the same, and Discard drops it. A slipping line is marked on its closed row and answers with one raise chip that
## writes the editor's own draft.
##
## Driven through the real controls a frame apart.

const Sectors = preload("res://src/sim/sectors.gd")
const SectorWarnings = preload("res://src/sim/sector_warnings.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")

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
			_main._windows.open("finances")
			_panel = _main._windows.frame("finances")._content
			_panel.open_row(FinanceDraft.SPENDING, LINE)
		4:
			_check_tile()
			_pick("hospitals", "prevention", 0.02)
		6:
			_check_strip("hospitals", "prevention", 0.02)
			_press(_with_meta("move", "move"))
		8:
			_check_drafted("hospitals", "prevention", 0.02)
			_check_moves_alone_footer()
			_check_forecast_carries(1, false)
			_press(_panel._foot.get_node("Table"))
		10:
			_check_moved("hospitals", "prevention", 0.02)
			if _panel._draft.has_moves():
				_fail("Apply the moves: the booked move is still in the draft")
			if not _inbox_text().contains(Strings.tn("Share move applied", "Share moves applied", 1).to_lower()):
				_fail("Apply the moves: no card says the move was applied (%s)" % _inbox_text())
			_pick("prevention", "hospitals", 0.05)
		12:
			_check_refused()
			_pick("hospitals", "primary_care", 0.01)
		14:
			_press(_with_meta("move", "move"))
		16:
			_press(_panel._foot.get_node("Discard"))
		18:
			_check_moved("hospitals", "prevention", 0.02)
			if _panel._draft.has_moves():
				_fail("Discard: the drafted move is still in the draft")
			# Prevention stands at about 0.051: a first draft takes it to 0.021.
			_pick("prevention", "hospitals", 0.03)
		20:
			_press(_with_meta("move", "move"))
		22:
			# QA's E5: 0.02 more is fine on the live share, under the floor on the draft.
			_pick("prevention", "hospitals", 0.02)
		24:
			_check_refused()
			# A lever AND a move drafted: the footer tables the lever and says the move applies now.
			var ns = _main._state.player()
			_panel._draft.set_value(FinanceDraft.SPENDING, LINE, float(ns.spending_pct_gdp[LINE]) + 1.0)
			_panel._paint_due = true
		26:
			_check_rows_and_moves_footer()
			_check_forecast_carries(1, true)
			_check_a_refused_tabling_books_the_move()
		28:
			_check_a_warned_line()
		30:
			_press(_with_meta("raise_line", LINE))
		32:
			_check_the_raise_is_the_editors_draft()
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
		var raw := Sectors.quantity(ns, loader, LINE, id)
		var q := Num.f(raw, 2 if absf(raw) < 10.0 else 1)
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
		var raw := Sectors.quantity(cns, loader, LINE, id)
		var after := Num.f(raw, 2 if absf(raw) < 10.0 else 1)
		if not text.contains(after):
			_fail("strip: '%s' does not carry %s after the move (%s)" % [text, id, after])
	if strip.money_label.text != EffectsStrip.cost_text(0.0):
		_fail("strip: a reallocation reads '%s', it moves no money" % strip.money_label.text)
	# The channel's figure, sign included (QA's B4 on #278): the copy's factor over the live one's.
	var ns = _main._state.player()
	var change := 100.0 * (Sectors.factor(cns, LINE) / Sectors.factor(ns, LINE) - 1.0)
	if not text.contains(": %s %%." % Num.fs(change, 1)):
		_fail("strip: '%s' does not carry the channel's change %s %%" % [text, Num.fs(change, 1)])


## A move is a draft: the live shares stand, the tile's bars read the draft.
func _check_drafted(from_id: String, to_id: String, amount: float) -> void:
	var ns = _main._state.player()
	var start := {}
	for sector in Sectors.sectors_of(_main._loader, LINE):
		start[String(sector["id"])] = float(sector["start"]["FRA"]["share"])
	var live := Sectors.shares(ns, _main._loader, LINE)
	if absf(float(live[from_id]) - float(start[from_id])) > 0.0001:
		_fail("drafted: the live share moved before the footer's verb (%s)" % live)
	var row = _with_meta("sector", to_id)
	var bar = row.get_meta("bar") if row != null else null
	if bar == null or absf(float(bar.value) - 100.0 * (float(start[to_id]) + amount)) > 0.001:
		_fail("drafted: the %s bar reads %s, the draft is %s" % [to_id, bar.value if bar != null else "<none>", 100.0 * (float(start[to_id]) + amount)])


func _check_moved(from_id: String, to_id: String, amount: float) -> void:
	var ns = _main._state.player()
	var start := {}
	for sector in Sectors.sectors_of(_main._loader, LINE):
		start[String(sector["id"])] = float(sector["start"]["FRA"]["share"])
	var now := Sectors.shares(ns, _main._loader, LINE)
	if absf(float(now[from_id]) - (float(start[from_id]) - amount)) > 0.0001 or absf(float(now[to_id]) - (float(start[to_id]) + amount)) > 0.0001:
		_fail("booked: shares %s, expected %s -%s and %s +%s" % [now, from_id, amount, to_id, amount])


## Prevention under its floor: Move greyed, the sim's line under it.
func _check_refused() -> void:
	var move: Button = _with_meta("move", "move")
	if move == null or not move.disabled:
		_fail("refused: Move is live for a move under the sector's floor")
	var line = _with_meta("refusal", "refusal")
	if line == null or not (line as Control).is_visible_in_tree() or (line as Label).text != Strings.t("A sector cannot fall under its floor."):
		_fail("refused: no visible line says why (%s)" % [line.text if line != null else "<none>"])


## The footer with only a move drafted: the verb's word, and the sentence saying it applies now, with no vote.
func _check_moves_alone_footer() -> void:
	var table: Button = _panel._foot.get_node("Table")
	if not table.visible or table.text != Strings.t("Apply the moves"):
		_fail("moves alone: the footer verb reads '%s' (visible %s), not 'Apply the moves'" % [table.text, table.visible])
	var said: String = _panel._foot._text.text
	if not said.contains(Strings.tn("%d share move takes effect now, with no vote.", "%d share moves take effect now, with no vote.", 1) % 1):
		_fail("moves alone: the footer does not say the move takes effect now (%s)" % said)
	if not _panel._draft.is_empty() or _panel._draft.bill() != {}:
		_fail("moves alone: the move leaked into the bill (%s)" % [_panel._draft.bill()])
	if _panel._foot.get_node("Review").visible:
		_fail("moves alone: a bill to review is offered with no bill")


## Rows and a move: the bill's verb, and the extra line that says how many apply now and when the rest is voted.
func _check_rows_and_moves_footer() -> void:
	var table: Button = _panel._foot.get_node("Table")
	if table.text != Strings.t("Table the changes"):
		_fail("rows and a move: the footer verb reads '%s'" % table.text)
	var said: String = _panel._foot._text.text
	if not said.contains("share move applies now; the rest is voted on"):
		_fail("rows and a move: the footer does not say the move applies now (%s)" % said)
	if (_panel._draft.bill().get("spending_pct_gdp", {}) as Dictionary).size() != 1 or _panel._draft.bill().has("moves"):
		_fail("rows and a move: the bill is not the one rate row (%s)" % [_panel._draft.bill()])


## The forecast's want carries the drafted moves, with the lever when there is one.
func _check_forecast_carries(moves: int, with_rate: bool) -> void:
	_panel._process(0.0)
	var wanted: Dictionary = _panel._forecast._want
	if (wanted.get("_share_moves", []) as Array).size() != moves:
		_fail("forecast: the proposed projection does not carry the drafted move (%s)" % [wanted.keys()])
	if with_rate and not wanted.has("spending_pct_gdp"):
		_fail("forecast: the lever is missing from the proposed projection (%s)" % [wanted.keys()])


## Another bill holds the slot: tabling is refused, and the move is booked all the same, the card saying so.
func _check_a_refused_tabling_books_the_move() -> void:
	var ns = _main._state.player()
	var before := Sectors.shares(ns, _main._loader, LINE)
	# A tax put in force outside the autumn month is a bill tabling refuses.
	_panel._draft.set_create("plastic_packaging_tax", 0.6)
	var moves: Array = _panel._draft.moves()
	_panel._on_table()
	var after := Sectors.shares(ns, _main._loader, LINE)
	var m: Dictionary = moves[0]
	if absf(float(after[m["to"]]) - float(before[m["to"]]) - float(m["amount"])) > 0.0001:
		_fail("refused tabling: the move was not booked (%s -> %s)" % [before, after])
	if _panel._draft.has_moves():
		_fail("refused tabling: the booked move stays in the draft")
	if _panel._draft.is_empty():
		_fail("refused tabling: the rows should stay for the player to table again")
	if not _inbox_text().contains("applied all the same"):
		_fail("refused tabling: the card does not say the move was applied (%s)" % _inbox_text())
	if not ns.tabled_bill.is_empty():
		_fail("refused tabling: a bill was tabled all the same (%s)" % [ns.tabled_bill])
	_panel._draft.revert()


## A line with a sector slipping: marked while closed, its reason once and one raise chip once open.
func _check_a_warned_line() -> void:
	# The open row's slider holds the keyboard after a Go: the page keeps its rows then, so the test lets go of it.
	_panel.get_viewport().gui_release_focus()
	var ns = _main._state.player()
	ns.sector_drift["base_gdp_per_head"] = float(ns.gdp_eur_bn) / float(ns.population) * 1.5
	_panel.mark_dirty()
	_panel._open_id = ""
	_panel._process(0.0)
	var name: Button = null
	for b in _panel._spending_box.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(Strings.t("Health")):
			name = b
	if name == null or not name.text.contains("(!)"):
		_fail("mark: the closed Health row is not marked (%s)" % [name.text if name != null else "<none>"])
	_panel.open_row(FinanceDraft.SPENDING, LINE)
	_panel._process(0.0)
	var said := false
	for label in _panel._spending_box.find_children("*", "Label", true, false):
		if label.has_meta("sector_warning") and (label as Label).text.contains(Strings.t(SectorWarnings.REASON_INCOME)):
			said = true
	if not said:
		_fail("reason: no line says the sim's reason why a sector slips")
	var chip = _with_meta("raise_line", LINE)
	if chip == null:
		_fail("raise: no chip on the opened slipping line")
		return
	if not (chip as Button).text.begins_with(Strings.t("Raise to %s %%").split("%s")[0]):
		_fail("raise: the chip reads '%s'" % (chip as Button).text)
	if not ActsOn.acts_on(chip, "health|hospitals"):
		_fail("raise: the chip is not tagged for the sector's Go")


## The chip is the editor's own slider moved: the shared draft holds the row above where it stood.
func _check_the_raise_is_the_editors_draft() -> void:
	var live := float(_main._state.player().spending_pct_gdp[LINE])
	if not _panel._draft.is_moved(FinanceDraft.SPENDING, LINE) or _panel._draft.value(FinanceDraft.SPENDING, LINE) <= live:
		_fail("raise: the chip did not raise the row in the shared draft (%s against %s)" % [_panel._draft.value(FinanceDraft.SPENDING, LINE), live])
	var slider: HSlider = _panel._editor._slider
	if absf(slider.value - _panel._draft.value(FinanceDraft.SPENDING, LINE)) > 0.001:
		_fail("raise: the editor's slider reads %s, the draft %s" % [slider.value, _panel._draft.value(FinanceDraft.SPENDING, LINE)])


# -- helpers --

func _inbox_text() -> String:
	var out := ""
	for label in _main._hud.inbox.find_children("*", "Label", true, false):
		out += (label as Label).text + " "
	for body in _main._hud.inbox.find_children("*", "RichTextLabel", true, false):  # the inbox body is a rich line
		out += (body as RichTextLabel).get_parsed_text() + " "
	return out.to_lower()  # card titles are set in capitals


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
		print("test_finance_sectors: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
