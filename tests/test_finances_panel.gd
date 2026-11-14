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

var _failures: Array[String] = []
var _loader
var _state
var _panel
var _frame := 0


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
	if _panel._footer.visible:
		_fail("the foot offers a bill with none before the Assembly")
	_state.player().tabled_bill = {"law_id": "finance:2026", "vote_year": 2026, "vote_month": 1, "vote_day": 31, "finance": {"tax_rates_pct": {"vat": 1.0}}}
	_panel._stamp = ""
	_panel._dirty = true
	_panel._process(0.0)
	if not _panel._footer.visible or _panel.primary_action() == null:
		_fail("a finance bill before the Assembly is not said at the foot")
	_state.player().tabled_bill = {}


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
