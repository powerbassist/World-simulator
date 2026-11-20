extends SceneTree

## Headless test: godot --headless --script res://tests/test_finances_panel.gd
## Non-zero exit on any failure.
##
## V5.3 screen 4, the Finances page (direction A). The picture is a claim and the rows are its
## controls, so pinned here: the sentence says the state's own figures; the two stacks stand in
## the proportion of the books and the spending stack stands taller by the deficit; the groups and
## "other revenue" add up to the revenue, the lines, the service and "other spending" to the
## spending; a kind at rate 0 is never folded and a small one is; what no row sets says so; the
## kinds not in force are named with the month they can be created; and the first tab of the
## Finances domain opens it.

const FinanceBooks = preload("res://src/ui/finance_books.gd")
const GameState = preload("res://src/core/game_state.gd")
const FinancesPanel = preload("res://src/ui/finances_panel.gd")
const FinanceStacks = preload("res://src/ui/finance_stacks.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const TaxesLoader = preload("res://src/core/loaders/taxes_loader.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

var _failures: Array[String] = []
var _loader
var _state
var _panel
var _frame := 0
var _main


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_state = GameState.new_game(_loader, "FRA")
	_panel = FinancesPanel.new()
	root.add_child(_panel)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_panel.setup(_state, _loader)
			_panel.show()
		3:
			_check_the_books()
			_check_the_picture()
			_check_the_rows()
			_check_the_foot()
			_check_the_colours_and_order()
			_check_the_surplus_has_no_bad_mark()
			_check_a_fold_opens_and_redraws()
			_check_the_stamp_and_the_forecast_redraw()
			# QA's MO / MD on #359: end to end through the game's own wiring.
			_main = load("res://src/ui/main.tscn").instantiate()
			root.add_child(_main)
		4:
			# The docked page at 115 %: laid out a frame before the clip check reads it (QA's T1 on #366: the scroll bar's
			# gap took 8 px from the books' columns and "Other spending" read "Other spend...").
			UiTheme.set_text_scale(1.15)
			_panel.theme = UiTheme.build()  # the game's fonts: a bare panel measures the engine default
			_panel._dirty = true
			_panel._process(0.0)
			# The narrowest the page can be laid out: every column at its minimum, which is where a name is cut.
			_panel.size = Vector2(_panel.get_combined_minimum_size().x, 820)
		5:
			_check_no_name_is_clipped_at_115()
			UiTheme.set_text_scale(1.0)
			_panel.theme = null
			_panel._dirty = true
			_panel._process(0.0)
		6:
			_main._windows.open("finances")
		9:
			_main._state.player().tabled_bill = {"law_id": "finance:2026", "vote_year": 2026, "vote_month": 1, "vote_day": 31, "finance": {"tax_rates_pct": {"vat": 1.0}}}
			_main._windows.frame("finances")._content.mark_dirty()
			_main._windows.frame("finances")._content._stamp = ""
		12:
			_press_open_the_bill_through_main()
		14:
			if not _main._windows.is_open("legislature"):
				_fail("Open the bill, pressed on the Finances tab, did not open the Bills tab")
			_finish()
	return false


func _check_the_books() -> void:
	var book := FinanceBooks.read(_state)
	var taxed := 0.0
	var folded_big := []
	var zero_folded := []
	for group in book["groups"]:
		taxed += float(group["total"])
		var in_group := 0.0
		for kind in group["kinds"] + group["folded"]:
			in_group += float(kind["yield_bn"])
		if absf(in_group - float(group["total"])) > 1e-6:
			_fail("group %s: its kinds add to %.3f, its total says %.3f" % [group["id"], in_group, group["total"]])
		for kind in group["folded"]:
			if float(kind["yield_bn"]) >= FinanceBooks.FOLD_BN:
				folded_big.append(kind["id"])
			if float(kind["rate"]) == 0.0:
				zero_folded.append(kind["id"])
	if absf(taxed + float(book["other_revenue_bn"]) - float(book["revenue_bn"])) > 1e-6:
		_fail("the groups and other revenue do not add up to the revenue")
	var lines := 0.0
	for line in book["lines"]:
		lines += float(line["bn"])
	if absf(lines + float(book["service_bn"]) + float(book["other_spending_bn"]) - float(book["spending_bn"])) > 1e-6:
		_fail("the lines, the service and other spending do not add up to the spending")
	if not folded_big.is_empty():
		_fail("a kind over the fold floor was folded: %s" % [folded_big])
	if not zero_folded.is_empty():
		_fail("a kind at rate 0 was folded away: %s" % [zero_folded])
	if absf(float(book["deficit_bn"]) - (float(book["spending_bn"]) - float(book["revenue_bn"]))) > 1e-6:
		_fail("the deficit is not spending less revenue")
	var wealth_seen := false
	for group in book["groups"]:
		for kind in group["kinds"]:
			wealth_seen = wealth_seen or String(kind["id"]) == "wealth"
	if not wealth_seen and _state.player().tax_rates_pct.has("wealth"):
		_fail("the wealth tax, in force at 0, is not in sight")


func _text_of(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text + "\n"
	elif node is Button:
		out += (node as Button).text + "\n"
	elif node is RichTextLabel:
		out += (node as RichTextLabel).get_parsed_text() + "\n"
	for child in node.get_children():
		out += _text_of(child)
	return out


func _check_the_picture() -> void:
	var book := FinanceBooks.read(_state)
	var heights: Dictionary = _panel._stacks.heights()
	var want_ratio := float(book["revenue_bn"]) / float(book["spending_bn"])
	var ratio := float(heights["revenue"]) / float(heights["spending"])
	if absf(ratio - want_ratio) > 0.002:
		_fail("the stacks stand in the ratio %.4f, the books say %.4f" % [ratio, want_ratio])
	if not (float(heights["spending"]) > float(heights["revenue"])) and float(book["deficit_bn"]) > 0.0:
		_fail("a deficit does not show as the spending stack standing taller")
	var text := _text_of(_panel._lead)
	for figure in [str(int(round(float(book["revenue_bn"])))), str(int(round(float(book["spending_bn"])))), str(int(round(float(book["deficit_bn"]))))]:
		if not text.contains(figure):
			_fail("the sentence does not say %s: '%s'" % [figure, text])
	# One scale for both, whichever stands taller: a surplus has revenue on top.
	var surplus := FinanceStacks.new()
	root.add_child(surplus)
	surplus.setup([{"label": "in", "value": 100.0, "color": Color.WHITE}], [{"label": "out", "value": 80.0, "color": Color.WHITE}], -20.0)
	var sh: Dictionary = surplus.heights()
	if absf(float(sh["spending"]) / float(sh["revenue"]) - 0.8) > 1e-6:
		_fail("a surplus draws its stacks on two scales: %s" % [sh])
	surplus.queue_free()
	if not _text_of(_panel._stacks).contains("Deficit"):
		_fail("the deficit's mark has no word beside it")


func _check_the_rows() -> void:
	var text := _text_of(_panel._revenue_box) + _text_of(_panel._spending_box)
	if text.count("not set here") != 3:
		_fail("the parts no row sets (other revenue, debt service, other spending) say so %d times" % text.count("not set here"))
	if not text.contains("Not in force, creatable in"):
		_fail("the kinds not in force are not named with the month they can be created")
	if not text.contains("0.67"):
		_fail("fuel duty's 0.67 does not print as it is")


func _check_the_foot() -> void:
	if _panel._foot.visible:
		_fail("the foot offers a bill with none before the Assembly")
	_state.player().tabled_bill = {"law_id": "finance:2026", "vote_year": 2026, "vote_month": 1, "vote_day": 31, "finance": {"tax_rates_pct": {"vat": 1.0}}}
	_panel._stamp = ""
	_panel._dirty = true
	_panel._process(0.0)
	if not _panel._foot.visible or _panel.primary_action() == null:
		_fail("a finance bill before the Assembly is not said at the foot")
	_state.player().tabled_bill = {}


## GLM's test-gap list (reviewed against the tree): a part's colour follows the part, not its rank, and
## the spending stack lists its lines largest first.
func _check_the_colours_and_order() -> void:
	var book := FinanceBooks.read(_state)
	var parts: Array = _panel._revenue_parts()
	for group in book["groups"]:
		var found := parts.filter(func(p) -> bool: return String(p["label"]) == FinanceRows.group_name(String(group["id"])))
		if found.is_empty() or found[0]["color"] != FinanceRows.group_color(String(group["id"])):
			_fail("group %s is not drawn in its own colour" % group["id"])
	if FinanceRows.group_color(TaxesLoader.GROUPS[0]) == FinanceRows.group_color(TaxesLoader.GROUPS[1]):
		_fail("two groups share a colour")
	var spend: Array = _panel._spending_parts()
	var lines := spend.slice(0, 5)
	for i in range(1, lines.size()):
		if float(lines[i]["value"]) > float(lines[i - 1]["value"]):
			_fail("the spending stack's lines are not largest first")


## A surplus has no deficit mark: the word is hidden, the figure stays.
func _check_the_surplus_has_no_bad_mark() -> void:
	var surplus := FinanceStacks.new()
	root.add_child(surplus)
	surplus.setup([{"label": "in", "value": 100.0, "color": Color.WHITE}], [{"label": "out", "value": 80.0, "color": Color.WHITE}], -20.0)
	if surplus._word.visible or not surplus._figure.visible or surplus._word.text != "Surplus":
		_fail("a surplus draws the deficit's word or loses its figure")
	surplus.queue_free()


## A press on a group's fold line shows its folded kinds at once (no wait for the day to turn).
func _check_a_fold_opens_and_redraws() -> void:
	var book := FinanceBooks.read(_state)
	var folded_group = null
	for group in book["groups"]:
		if not (group["folded"] as Array).is_empty():
			folded_group = group
			break
	if folded_group == null:
		_fail("premise: France folds no kind")
		return
	var name_of := String(_state.player().tax_library[String(folded_group["folded"][0]["id"])]["name"])
	if _text_of(_panel._revenue_box).contains(name_of):
		_fail("premise: a folded kind is already shown: %s" % name_of)
	var fold: Button = null
	for b in _panel._revenue_box.find_children("*", "Button", true, false):
		if (b as Button).text.contains("other kind"):
			fold = b
			break
	if fold == null:
		_fail("a group with folded kinds offers no fold line")
		return
	fold.pressed.emit()
	_panel._process(0.0)
	if not _text_of(_panel._revenue_box).contains(name_of):
		_fail("a press on the fold line did not show %s" % name_of)
	_panel._open_groups.clear()
	_panel._dirty = true
	_panel._process(0.0)


## The page re-reads when the slot changes (not only when a test resets the stamp), and the forecast's
## `settled` repaints its figures in place (never a rebuild).
func _check_the_stamp_and_the_forecast_redraw() -> void:
	_panel._process(0.0)
	if _panel._foot.visible:
		_fail("premise: the foot is up with no bill")
	_state.player().tabled_bill = {"law_id": "finance:2026", "vote_year": 2026, "vote_month": 1, "vote_day": 31, "finance": {"tax_rates_pct": {"vat": 1.0}}}
	_panel._dirty = true
	_panel._process(0.0)
	if not _panel._foot.visible:
		_fail("the page did not re-read when a bill was tabled")
	var heard := []
	_panel.go_requested.connect(func(window_id: String) -> void: heard.append(window_id), CONNECT_ONE_SHOT)
	_panel.primary_action().pressed.emit()
	if heard != ["legislature"]:
		_fail("Open the bill asked for %s, not the Bills tab" % [heard])
	_state.player().tabled_bill = {}
	_panel._dirty = false
	_panel._paint_due = false
	_panel._forecast.settled.emit()
	if not _panel._paint_due:
		_fail("the forecast's settled signal does not repaint the page")
	if _panel._dirty:
		_fail("the forecast's settled signal rebuilds the rows (it would drop a slider being held)")
	_panel._process(0.0)


## No header or row name on the books is cut to an ellipsis at 115 % text: a Label that clips and whose text is wider
## than the box it was given says "Other spend...". The names are what the page is read by; the figures and notes
## around them may be tighter.
func _check_no_name_is_clipped_at_115() -> void:
	var clipped := []
	for box in [_panel._revenue_box, _panel._spending_box]:
		for node in box.find_children("*", "", true, false):
			if not (node is Label or node is Button):
				continue
			var label = node
			if not label.is_visible_in_tree() or not label.clip_text or label.text == "":
				continue
			# A who-pays caption is a note that may be tighter than the names, and then it is the row's
			# hover (picked by its role, never by what its text looks like).
			if label.has_meta("who_pays"):
				var row: Control = label.get_parent()
				if not String(row.tooltip_text).begins_with("Paid by:"):
					_fail("a who-pays caption on a row with no 'Paid by' hover: %s" % label.text)
				continue
			# The label's own measure of its text, as it would draw it (variation fonts and tracking included).
			label.clip_text = false
			label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
			var need: float = label.get_minimum_size().x
			label.clip_text = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			if need > label.size.x + 0.5:
				clipped.append("%s (%.0f of %.0f px)" % [label.text, need, label.size.x])
	if not clipped.is_empty():
		_fail("at 115 %% the books clip: %s" % ", ".join(clipped))


func _press_open_the_bill_through_main() -> void:
	var page = _main._windows.frame("finances")._content
	var button = page.primary_action()
	if button == null:
		_fail("a finance bill is tabled and the Finances tab offers no way to open it")
		return
	if _main._windows.is_open("legislature"):
		_fail("premise: the Bills tab is already the open one")
	button.pressed.emit()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_finances_panel: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
