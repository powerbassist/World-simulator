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
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const FinanceEditor = preload("res://src/ui/finance_editor.gd")
const TaxesLoader = preload("res://src/core/loaders/taxes_loader.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")
const FinanceLever = preload("res://src/ui/finance_lever.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []
var _loader
var _state
var _panel
var _frame := 0
var _main
var _window_was := Vector2i.ZERO


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
			# Wider than its minimum, as the docked page is: the bars share the slack (pass 2 T5 on #443).
			_panel.size = Vector2(1500, 900)
		3:
			# First, while the rows built at setup are laid out (a later check rebuilds them within the frame).
			_check_header_bars_on_the_row_scale()
			_check_the_books()
			_check_the_picture()
			_check_the_rows()
			_check_the_foot()
			_check_the_kind_captions()
			_check_the_colours_and_order()
			_check_a_bar_is_a_lever()
			_check_a_fold_opens_and_redraws()
			_check_the_stamp_and_the_forecast_redraw()
			# Pass 2 on #443.
			_check_a_drag_prices_its_own_row()
			_check_back_to_today_off_the_grid()
			_check_the_rail_hears_the_page_dirty()
			_check_the_amendment_steps()
			# QA's MO / MD on #359: end to end through the game's own wiring.
			_main = load("res://src/ui/main.tscn").instantiate()
			root.add_child(_main)
		4:
			# The docked page at 115 %: laid out a frame before the clip check reads it (QA's T1 on #366: the scroll bar's
			# gap took 8 px from the books' columns and "Other spending" read "Other spend...").
			UiTheme.set_text_scale(1.15)
			_panel.theme = UiTheme.build()  # the game's fonts: a bare panel measures the engine default
			# VAT at vote: its row is locked while Income tax beside it opens (gate-443 T11).
			_state.player().tabled_bill = {"law_id": "finance:2026", "vote_year": 2026, "vote_month": 1, "vote_day": 31, "finance": {"tax_rates_pct": {"vat": 1.0}}}
			_panel._stamp = ""
			_panel._dirty = true
			_panel._process(0.0)
			# The narrowest the page can be laid out: every column at its minimum, which is where a name is cut.
			_panel.size = Vector2(_panel.get_combined_minimum_size().x, 820)
		5:
			_check_no_name_is_clipped_at_115()
			_check_names_at_one_x()
			_check_the_withdraw_is_a_ghost()
			# QA's RECORD on #443: the caption floor keeps the bars on one scale on the narrowest page, rail open.
			_check_header_bars_on_the_row_scale()
			_check_no_sheet_on_a_hidden_page()
			_state.player().tabled_bill = {}
			_panel._stamp = ""
			UiTheme.set_text_scale(1.0)
			_panel.theme = null
			_panel._dirty = true
			_panel._process(0.0)
		6:
			_main._windows.open("finances")
		8:
			_check_the_rail_is_the_domains_aside()
			# A draft on Books and a programme placed on Register: two next steps, one filled button a screen.
			var page = _main._windows.content("finances")
			var draft = page.shared_draft()
			draft.set_value(FinanceDraft.SPENDING, "health", draft.live(FinanceDraft.SPENDING, "health") + 1.0)
			page._on_structure_changed()
			_main._windows.open("register")
		10:
			# Every region's units taken off: the button stays, disabled ("Place at least one unit.").
			var register = _main._windows.content("register")
			register._placed = {}
			register._dirty = true
		27:
			# Pass 2 T11 on #443: Register's button is filled but disabled with nothing placed: not the next step, so the
			# rail's verb keeps the fill.
			var put := _register_primary()
			if put == null or not put.disabled:
				_fail("premise: Register shows no disabled filled button with nothing placed")
			_check_one_filled_button("register", true)
			# Pass 2 T4 on #443: the rail's Review beside Register opens the bill's sheet, which lies over Books.
			var review := _main._windows.content("finances").rail().find_child("Review", true, false) as Button
			if review == null or not review.is_visible_in_tree():
				_fail("premise: the rail offers no Review beside Register")
			else:
				review.pressed.emit()
		28:
			var books = _main._windows.content("finances")
			if not _main._windows.is_open("finances") or not books._sheet.is_visible_in_tree():
				_fail("Review the bill beside Register showed no sheet (Books open %s)" % _main._windows.is_open("finances"))
			books._close_sheet()
			_main._windows.content("register")._fill(true)
			_main._windows.content("register")._dirty = true
			_main._windows.open("register")
		45:
			# The rail looks at the page a quarter of a second at a time: the placed unit lit Register's button.
			_check_one_filled_button("register", false)
			_main._windows.open("programmes")
		47:
			_check_one_filled_button("programmes", true)
			_main._windows.open("finances")
		49:
			_check_one_filled_button("finances", true)
			_start_a_long_bill()
		55:
			_check_a_long_bill_keeps_its_verbs()
			# Pass 2 T12 on #443: a page a probe placed (fit_within) keeps the band it was given while the dock is up.
			_main._windows.frame("finances").fit_within(Vector2(900, 600))
		59:
			var placed: Control = _main._windows.frame("finances")
			if not placed.size.is_equal_approx(Vector2(900, 600)):
				_fail("a page placed by fit_within at 900 x 600 is %s with the dock up" % placed.size)
			_main._windows.open("finances")
			_main._windows.content("finances").shared_draft().revert()
			_main._state.player().tabled_bill = {"law_id": "finance:2026", "vote_year": 2026, "vote_month": 1, "vote_day": 31, "finance": {"tax_rates_pct": {"vat": 1.0}}}
			_main._windows.frame("finances")._content.mark_dirty()
			_main._windows.frame("finances")._content._stamp = ""
		62:
			_press_open_the_bill_through_main()
		64:
			if not _main._windows.is_open("legislature"):
				_fail("Open the bill, pressed on the Finances tab, did not open the Bills tab")
			# R1, the parent's ruling on #443: the folded line's chevron puts the inbox away, which shows the whole rail.
			_main._windows.open("finances")
			_main._hud.inbox.slide_in()
		67:
			var rail: Control = _main._windows.content("finances").rail()
			var unfold := rail.find_child("Unfold", true, false) as Button
			if not rail.is_folded() or unfold == null or not unfold.is_visible_in_tree():
				_fail("premise: with the inbox in, no folded rail with its chevron (folded %s)" % rail.is_folded())
			else:
				unfold.grab_focus()
				unfold.pressed.emit()
		70:
			_check_the_chevron_put_the_inbox_away()
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


## G3 S4, Books in C: one table, spending first, and every row's bar on ONE money scale -- two rows' bars stand in the
## ratio of their money a year (the stacks' "one scale" rule, carried to the rows); the sentence still says the books.
func _check_the_picture() -> void:
	var book := FinanceBooks.read(_state)
	if _panel._spending_box.get_index() > _panel._revenue_box.get_index() or _panel._spending_box.get_parent() != _panel._revenue_box.get_parent():
		_fail("the table is not one column with spending first")
	var levers: Dictionary = _panel._ctx["levers"]
	var health: Array = levers.get("spending_pct_gdp:health", [])
	var vat: Array = levers.get("tax_rates_pct:vat", [])
	if health.is_empty() or vat.is_empty():
		_fail("health or VAT has no lever")
		return
	var health_bn := 0.0
	for line in book["lines"]:
		if String(line["key"]) == "health":
			health_bn = float(line["bn"])
	var vat_bn := 0.0
	for group in book["groups"]:
		for kind in group["kinds"]:
			if String(kind["id"]) == "vat":
				vat_bn = float(kind["yield_bn"])
	var h: float = health[0].ring_x() - health[0].PAD
	var v: float = vat[0].ring_x() - vat[0].PAD
	if absf(h / v - health_bn / vat_bn) > 0.01:
		_fail("health's bar and VAT's stand %.3f to 1, their money %.3f to 1" % [h / v, health_bn / vat_bn])
	var text := _text_of(_panel._lead)
	for figure in [str(int(round(float(book["revenue_bn"])))), str(int(round(float(book["spending_bn"])))), str(int(round(float(book["deficit_bn"]))))]:
		if not text.contains(figure):
			_fail("the sentence does not say %s: '%s'" % [figure, text])


func _check_the_rows() -> void:
	var text := _text_of(_panel._revenue_box) + _text_of(_panel._spending_box)
	if text.count("not set here") != 3:
		_fail("the parts no row sets (other revenue, debt service, other spending) say so %d times" % text.count("not set here"))
	if not text.contains("Not in force, creatable in"):
		_fail("the kinds not in force are not named with the month they can be created")
	if not text.contains("0.67"):
		_fail("fuel duty's 0.67 does not print as it is")


func _check_the_foot() -> void:
	if _panel._foot._withdraw.visible or _panel._foot._open.visible:
		_fail("the rail offers a bill with none before the Assembly")
	_state.player().tabled_bill = {"law_id": "finance:2026", "vote_year": 2026, "vote_month": 1, "vote_day": 31, "finance": {"tax_rates_pct": {"vat": 1.0}}}
	_panel._stamp = ""
	_panel._dirty = true
	_panel._process(0.0)
	if not _panel._foot.visible or _panel.primary_action() == null:
		_fail("a finance bill before the Assembly is not said at the foot")
	_state.player().tabled_bill = {}


## GLM's test-gap list (reviewed against the tree), carried to the table: a bar's colour follows its line or its
## group, never its rank, and two groups never share one.
## G3 S4: a closed row's bar is its lever. Moving it writes the draft (clamped to the row's reach), the row's balance
## and the rail follow, and nothing is rebuilt under the hand (the same lever after the repaint: QA's B1 on #363); a
## draft moved from elsewhere (the editor's box, a Go) moves the bar's dot.
func _check_a_bar_is_a_lever() -> void:
	var draft = _panel.shared_draft()
	var levers: Dictionary = _panel._ctx["levers"]
	var vat = levers["tax_rates_pct:vat"][0]
	var live: float = draft.live(FinanceDraft.TAX, "vat")
	vat.value = live + vat.step * 2.0
	_panel._process(0.0)
	if not draft.is_moved(FinanceDraft.TAX, "vat") or not is_equal_approx(draft.value(FinanceDraft.TAX, "vat"), live + vat.step * 2.0):
		_fail("moving VAT's bar did not reach the draft: %s" % draft.value(FinanceDraft.TAX, "vat"))
	if _panel._ctx["levers"]["tax_rates_pct:vat"][0] != vat:
		_fail("a bar's move rebuilt the rows under the hand")
	var balance: Label = _panel._ctx["balances"]["tax_rates_pct:vat"][0]
	if balance.text == "":
		_fail("a moved row shows no balance")
	if not _panel._foot._count.text.to_lower().contains("1 change"):
		_fail("the rail does not count the bar's move: '%s'" % _panel._foot._count.text)
	# Past the row's reach: clamped as the box clamps. A spending line's track runs 0 to 30 % of GDP, its reach 5 points
	# either side of today, so a bar dragged to its end must stop at the reach.
	var health = levers["spending_pct_gdp:health"][0]
	health.value = health.max_value
	var hi: float = float(FinanceEditor.span(_state.player(), draft, FinanceDraft.SPENDING, "health")["hi"])
	if draft.value(FinanceDraft.SPENDING, "health") > hi + 1e-6 or hi >= health.max_value:
		_fail("a bar dragged to its end wrote %s past the reach %s" % [draft.value(FinanceDraft.SPENDING, "health"), hi])
	draft.set_value(FinanceDraft.SPENDING, "health", draft.live(FinanceDraft.SPENDING, "health") + 1.0)
	_panel._on_moved()
	_panel._process(0.0)
	if not is_equal_approx(health.value, draft.value(FinanceDraft.SPENDING, "health")) or not health.is_moved():
		_fail("a draft moved from elsewhere left health's dot at %s" % health.value)
	draft.revert()
	_panel._on_structure_changed()
	_panel._process(0.0)
	if _panel._ctx["balances"]["tax_rates_pct:vat"][0].text != "":
		_fail("a reverted row keeps its balance")


func _check_the_colours_and_order() -> void:
	var book := FinanceBooks.read(_state)
	var levers: Dictionary = _panel._ctx["levers"]
	for line in book["lines"]:
		var lever: Array = levers.get("spending_pct_gdp:" + String(line["key"]), [])
		if lever.is_empty() or lever[0]._color != FinanceRows.line_color(String(line["key"])):
			_fail("line %s is not drawn in its own colour" % line["key"])
	for group in book["groups"]:
		for kind in group["kinds"]:
			var lever: Array = levers.get("tax_rates_pct:" + String(kind["id"]), [])
			if lever.is_empty() or lever[0]._color != FinanceRows.group_color(String(group["id"])):
				_fail("kind %s is not drawn in its group's colour" % kind["id"])
	if FinanceRows.group_color(TaxesLoader.GROUPS[0]) == FinanceRows.group_color(TaxesLoader.GROUPS[1]):
		_fail("two groups share a colour")
	# Decision 5 (gate T2 on #443): no bar wears the hue nearest the accent -- France's blue is skipped.
	var skipped: Color = ChartStyle.CATEGORICAL[0]
	for cell in levers.values():
		if cell[0]._color == skipped:
			_fail("a bar wears the accent's own hue under France")
			break
	if _panel._ctx["balances"].is_empty():
		_fail("premise: no balance cells")


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
	if _panel._foot._withdraw.visible:
		_fail("premise: the rail holds a bill with none tabled")
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


## Gate-443 T11: a name in a list keeps TEXT, at one left edge. A row at vote (locked) and a row that opens read
## alike; the caption ("At vote") and the locked bar carry the state. Taxes: the rows share their indent.
func _check_names_at_one_x() -> void:
	var names: Array = _panel._revenue_box.find_children("RowName", "", true, false)
	var locked: Array = names.filter(func(n) -> bool: return n is Label)
	var open: Array = names.filter(func(n) -> bool: return n is Button)
	if locked.is_empty() or open.is_empty():
		_fail("premise: %d locked and %d openable tax names with VAT at vote" % [locked.size(), open.size()])
		return
	var first: Control = open[0]
	for node in names:
		var name: Control = node
		var text_x := name.global_position.x + name.get_theme_stylebox("normal").get_margin(SIDE_LEFT)
		var first_x := first.global_position.x + first.get_theme_stylebox("normal").get_margin(SIDE_LEFT)
		if absf(text_x - first_x) > 0.5:
			_fail("'%s' starts its text at x %.1f, '%s' at %.1f: not one edge" % [name.text, text_x, first.text, first_x])
		if not name.get_theme_color("font_color").is_equal_approx(UiTheme.TEXT):
			_fail("'%s' is drawn in %s, not TEXT" % [name.text, name.get_theme_color("font_color").to_html(false)])


## Gate-443 T12: "Withdraw the bill" is a ghost like its neighbours, never bare bold text.
func _check_the_withdraw_is_a_ghost() -> void:
	var withdraw: Button = _panel._foot._withdraw
	if not withdraw.visible:
		_fail("premise: no Withdraw with a bill at vote")
	if withdraw.flat or withdraw.theme_type_variation != UiTheme.GHOST:
		_fail("Withdraw the bill is %s (flat %s), not a ghost" % [withdraw.theme_type_variation, withdraw.flat])


## QA's RECORD on #443: Review cannot put the bill's sheet on a page that stays hidden (a scene owns the screen and
## Books could not open): no sheet.
func _check_no_sheet_on_a_hidden_page() -> void:
	_panel.hide()
	_panel._open_sheet()
	if _panel._sheet.visible:
		_fail("the bill's sheet opened on a hidden page")
		_panel._sheet.hide()
	_panel.show()


## G3 S4: the bill's rail is the Finances domain's aside, shown beside the page and folded while the inbox shows
## (the table keeps its width), on every Finances tab.
func _check_the_rail_is_the_domains_aside() -> void:
	var page = _main._windows.content("finances")
	var rail: Control = page.rail()
	if _main._windows.aside() != rail or not rail.is_visible_in_tree():
		_fail("the bill's rail is not the aside shown beside Books")
		return
	var inbox: Control = _main.get_tree().get_first_node_in_group("inbox") as Control
	var inbox_shows: bool = inbox != null and inbox.is_visible_in_tree()
	if rail.is_folded() != inbox_shows:
		_fail("the rail is folded %s with the inbox showing %s" % [rail.is_folded(), inbox_shows])
	# Folded (gate T1 on #443) the rail is one line across the top, the page under it at the full width; open, it stands at
	# the right and the page ends short of it.
	var page_frame: Control = _main._windows.frame("finances")
	var page_box := page_frame.get_global_rect()
	var rail_box := rail.get_global_rect()
	if rail.is_folded():
		if page_box.position.y < rail_box.end.y + UiTheme.GAP_PANE - 0.5 or absf(rail_box.size.x - page_box.size.x) > 0.5:
			_fail("the folded rail is not one line over the page: rail %s, page %s" % [rail_box, page_box])
		if rail_box.size.y > 80.0 * UiTheme.text_scale():
			_fail("the folded rail is %s px tall, not one line" % rail_box.size.y)
		if not rail._strip.is_ancestor_of(rail.find_child("Table", true, false)):
			_fail("the folded rail's verbs are not on its line")
	elif page_box.end.x > rail_box.position.x - UiTheme.GAP_PANE + 0.5:
		_fail("the page runs under the rail: page ends %s, rail starts %s" % [page_box.end.x, rail_box.position.x])


## R1: pressed, the chevron slides the inbox away, the rail opens beside the page, and the keyboard lands on the rail's
## first verb (the chevron went with the line it was on).
func _check_the_chevron_put_the_inbox_away() -> void:
	var rail: Control = _main._windows.content("finances").rail()
	if _main._hud.inbox.is_visible_in_tree() or rail.is_folded():
		_fail("the chevron left the inbox showing %s, the rail folded %s" % [_main._hud.inbox.is_visible_in_tree(), rail.is_folded()])
	var held: Control = _main.get_viewport().gui_get_focus_owner()
	if held == null or not rail.is_ancestor_of(held) or not held.is_visible_in_tree():
		_fail("after the chevron the keyboard is on %s, not on the open rail" % [held])


## The parent's ruling (2026-11-22): one filled button a screen, the screen's next step. Register's own PRIMARY leads
## and the rail's verb is plain; on Building and Books the rail's verb is the filled one.
func _check_one_filled_button(tab: String, rail_leads: bool) -> void:
	var rail: Control = _main._windows.content("finances").rail()
	if _main._windows.aside() != rail or not rail.is_visible_in_tree():
		_fail("the rail is not beside the %s tab" % tab)
		return
	var filled := []
	for root_node in [_main._windows.content(tab), rail]:
		for b in (root_node as Node).find_children("*", "Button", true, false):
			if (b as Button).is_visible_in_tree() and not (b as Button).disabled and (b as Button).theme_type_variation == UiTheme.PRIMARY:
				filled.append((b as Button).text)
	if filled.size() != 1:
		_fail("the %s tab shows %d filled buttons: %s" % [tab, filled.size(), filled])
	var table := rail.find_child("Table", true, false) as Button
	if table == null or not table.is_visible_in_tree():
		_fail("premise: the rail's Table is not up on %s" % tab)
	elif (table.theme_type_variation == UiTheme.PRIMARY) != rail_leads:
		_fail("on %s the rail's Table is %s, wanted it filled %s" % [tab, table.theme_type_variation, rail_leads])


func _register_primary() -> Button:
	for b in _main._windows.content("register").find_children("*", "Button", true, false):  # i18n: ok a class name
		if (b as Button).theme_type_variation == UiTheme.PRIMARY and (b as Button).is_visible_in_tree():
			return b
	return null


## Pass 2 T3 on #443: twelve changes at text 115, the rail open (the inbox put away): its verbs stay on screen.
func _start_a_long_bill() -> void:
	# The author's screen, not the headless default (taller: twelve changes fitted with room to spare).
	_window_was = root.size
	root.size = Vector2i(1920, 1080)
	var inbox = _main._hud.inbox
	inbox.slide_out()
	inbox.hide()
	UiTheme.set_text_scale(1.15)
	UiTheme.rebuild(_main)
	var page = _main._windows.content("finances")
	var draft = page.shared_draft()
	var ns = _main._state.player()
	for line in ns.spending_pct_gdp:
		draft.set_value(FinanceDraft.SPENDING, String(line), float(ns.spending_pct_gdp[line]) + 0.5)
	for kind in ns.tax_rates_pct:
		if draft.count() >= 12:
			break
		if float(ns.tax_rates_pct[kind]) > 0.5:
			draft.set_value(FinanceDraft.TAX, String(kind), float(ns.tax_rates_pct[kind]) + 0.5)
	page._on_structure_changed()


func _check_a_long_bill_keeps_its_verbs() -> void:
	var page = _main._windows.content("finances")
	var rail: Control = page.rail()
	var table := rail.find_child("Table", true, false) as Button
	var body: Rect2 = _main._windows._body.get_global_rect()
	if page.shared_draft().count() < 12 or rail.is_folded():
		_fail("premise: %d changes, the rail folded %s" % [page.shared_draft().count(), rail.is_folded()])
	elif table == null or not table.is_visible_in_tree():
		_fail("a twelve-change bill shows no Table the bill")
	elif table.get_global_rect().end.y > body.end.y + 0.5 or rail.get_global_rect().end.y > body.end.y + 0.5:
		_fail("a twelve-change bill at 115 %% puts its verbs at %s, past the workspace's foot %s (rail %s)" % [
			table.get_global_rect(), body.end.y, rail.get_global_rect()])
	# The waterfall and the changes scroll in what is left, never squeezed to nothing.
	var scroll := rail._fall.get_parent().get_parent() as ScrollContainer
	if scroll == null or not scroll.is_ancestor_of(rail._changes):
		_fail("the waterfall and the changes are not in one scroll")
	elif scroll.size.y < 160.0 or scroll.get_v_scroll_bar().max_value <= scroll.size.y:
		_fail("a twelve-change bill's scroll is %s px tall over %s of content: nothing to scroll or no room" % [
			scroll.size.y, scroll.get_v_scroll_bar().max_value])
	UiTheme.set_text_scale(1.0)
	UiTheme.rebuild(_main)
	root.size = _window_was
	page.shared_draft().revert()
	page._on_structure_changed()


func _press_open_the_bill_through_main() -> void:
	var page = _main._windows.frame("finances")._content
	var button = page.primary_action()
	if button == null:
		_fail("a finance bill is tabled and the Finances tab offers no way to open it")
		return
	if _main._windows.is_open("legislature"):
		_fail("premise: the Bills tab is already the open one")
	button.pressed.emit()


## Pass 2 T5 on #443: a part no rate sets (Debt service, Other spending) draws its bar like a line's, on the one money
## scale: the same left x and the same length, so the same billions draw the same pixels.
func _check_header_bars_on_the_row_scale() -> void:
	var row_bar: Control = _panel._ctx["levers"]["spending_pct_gdp:health"][0]
	var headers := []
	for bar in _panel._spending_box.find_children("*", "HSlider", true, false):  # i18n: ok a class name
		if not _is_row_lever(bar):
			headers.append(bar)
	if headers.size() < 2:
		_fail("premise: %d header bars under spending, wanted Debt service and Other spending" % headers.size())
		return
	var a := row_bar.get_global_rect()
	# A tax's row is indented under its group, its bar is not: the one scale holds across the two sections too.
	headers.append(_panel._ctx["levers"]["tax_rates_pct:vat"][0])
	# The column head over the bars ("DRAG") stands where they start.
	for label in _panel._spending_box.find_children("*", "Label", true, false):  # i18n: ok a class name
		if (label as Label).text == Strings.t("Drag").to_upper():
			if absf((label as Control).global_position.x - row_bar.global_position.x) > 0.5:
				_fail("the bars' column head starts at %s, the bars at %s" % [(label as Control).global_position.x, row_bar.global_position.x])
	for bar in headers:
		var b := (bar as Control).get_global_rect()
		if absf(b.position.x - a.position.x) > 0.5 or absf(b.size.x - a.size.x) > 0.5:
			_fail("a bar spans %s, a line's %s: not one money scale" % [b, a])


func _is_row_lever(bar: Node) -> bool:
	for cell in (_panel._ctx["levers"] as Dictionary).values():
		if cell[0] == bar:
			return true
	return false


## Pass 2 T7 on #443 (as #429 pass 2 T2): a drag with eight rows drafted prices the dragged row once a step, never the
## seven others again (a 12-entry FIFO evicted them on the drag's own entries: a stutter at eight rows).
func _check_a_drag_prices_its_own_row() -> void:
	var counting := PreviewCount.new()
	counting.setup(_state)
	var kept = _panel._price
	_panel._price = counting
	var draft = _panel.shared_draft()
	_panel._foot.setup(_state, _loader, draft, counting)
	var ns = _state.player()
	for line in ns.spending_pct_gdp:
		draft.set_value(FinanceDraft.SPENDING, String(line), float(ns.spending_pct_gdp[line]) + 0.5)
	for kind in ns.tax_rates_pct:
		if draft.count() >= 8:
			break
		if float(ns.tax_rates_pct[kind]) > 1.0 and String(kind) != "vat":
			draft.set_value(FinanceDraft.TAX, String(kind), float(ns.tax_rates_pct[kind]) + 1.0)
	_panel._on_structure_changed()
	_panel._process(0.0)
	_panel._process(0.0)
	var vat = _panel._ctx["levers"]["tax_rates_pct:vat"][0]
	var live: float = draft.live(FinanceDraft.TAX, "vat")
	vat.value = live + vat.step
	_panel._process(0.0)
	var before: int = counting.previews
	var steps := 10
	for i in steps:
		vat.value = live + vat.step * float(i + 2)
		_panel._process(0.0)
	var per_step := float(counting.previews - before) / float(steps)
	print("a drag with %d rows drafted: %.1f previews a step" % [draft.count(), per_step])
	if draft.count() < 8:
		_fail("premise: only %d rows drafted" % draft.count())
	if per_step > 3.0:
		_fail("a drag step with %d rows drafted ran %.1f previews: the other rows are priced again" % [draft.count(), per_step])
	draft.revert()
	_panel._price = kept
	_panel._foot.setup(_state, _loader, draft, kept)
	_panel._on_structure_changed()
	_panel._process(0.0)


## Pass 2 T9 on #443: a rate today off the bar's grid; a press lands on the grid, and the hand let go on the grid point
## nearest today puts the row back to "no change" (it stayed drafted as a 0.03 change).
func _check_back_to_today_off_the_grid() -> void:
	var ns = _state.player()
	var draft = _panel.shared_draft()
	var was := float(ns.spending_pct_gdp["health"])
	ns.spending_pct_gdp["health"] = was + 0.03
	_panel.mark_dirty()
	_panel._process(0.0)
	var health = _panel._ctx["levers"]["spending_pct_gdp:health"][0]
	var home: float = snappedf(was + 0.03 - health.min_value, health.step) + health.min_value
	health.value = home + health.step  # a press a step away, then the drag back to the grid point by today
	health.value = home
	_panel._process(0.0)
	if not draft.is_moved(FinanceDraft.SPENDING, "health"):
		_fail("premise: the grid point by an off-grid today is not a draft move")
	health.released.emit()
	_panel._process(0.0)
	if draft.is_moved(FinanceDraft.SPENDING, "health"):
		_fail("the hand let go by today on an off-grid row left it drafted at %s (today %s)" % [
			draft.value(FinanceDraft.SPENDING, "health"), draft.live(FinanceDraft.SPENDING, "health")])
	ns.spending_pct_gdp["health"] = was
	draft.revert()
	_panel.mark_dirty()
	_panel._process(0.0)


## Pass 2 T10 on #443: a change behind the page (an event's choice while paused) reaches the rail, which on Register,
## Building and Public works repaints itself only when its stamp is cleared.
func _check_the_rail_hears_the_page_dirty() -> void:
	var foot = _panel._foot
	foot.refresh(_state, _loader, _panel.shared_draft(), _panel._price)
	if foot._stamp == "":
		_fail("premise: the rail has no stamp after a refresh")
	_panel.mark_dirty()
	if foot._stamp != "":
		_fail("the page marked dirty did not pass it to the rail")


## Pass 2 T6 on #443: an amendment's waterfall: the bill already tabled is its own step ahead of the draft's rows, and
## the residual step holds only what the rows miss together.
func _check_the_amendment_steps() -> void:
	var ns = _state.player()
	var draft = _panel.shared_draft()
	var kept: Dictionary = ns.tabled_bill.duplicate(true)
	ns.tabled_bill = {"law_id": "finance:2026", "vote_year": 2026, "vote_month": 1, "vote_day": 31, "finance": {"tax_rates_pct": {"vat": 1.0}}}
	draft.set_value(FinanceDraft.SPENDING, "health", draft.live(FinanceDraft.SPENDING, "health") + 1.0)
	_panel._price.reset()
	_panel._foot.refresh(_state, _loader, draft, _panel._price)
	var steps: Array = (_panel._foot._chart._rows as Array).filter(func(r: Dictionary) -> bool: return String(r["kind"]) == "step")
	if steps.size() < 2:
		_fail("an amendment's waterfall has %d steps, wanted the tabled bill's and the row's" % steps.size())
	else:
		var first := float(steps[0]["delta"])
		# VAT up a point narrows the deficit by billions: the first step is that bill's money.
		if first > -1.0:
			_fail("the amendment's first step is %s bn, not the tabled VAT rise's" % first)
		var residual := Strings.t("Together, and what the rows alone miss")
		for step in steps:
			if String(step["label"]) == residual and absf(float(step["delta"])) > 1.0:
				_fail("the tabled bill's money still lands in the residual step: %s" % step)
	ns.tabled_bill = kept
	draft.revert()
	_panel._price.reset()
	_panel.mark_dirty()
	_panel._process(0.0)


## Counts the previews a price runs (a miss of its kept answers): what a drag costs, whichever surface asks.
class PreviewCount extends "res://src/ui/finance_price.gd":
	var previews := 0

	func after(pending: Dictionary) -> Dictionary:
		_check()
		if not _kept.has(var_to_str(pending)):
			previews += 1
		return super.after(pending)

	func after_bill(bill: Dictionary) -> Dictionary:
		_check()
		if not _kept.has("bill:" + var_to_str(bill)):
			previews += 1
		return super.after_bill(bill)


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


## QA on #433: a kind row's caption is who pays, "At vote" while its rate is at the vote and
## "Creation" while a new kind is drafted; the "Paid by" hover is on each of them.
func _check_the_kind_captions() -> void:
	var ns = _state.player()
	var vat_id := FinanceRows.row_id(FinanceDraft.TAX, "vat")
	_state.player().tabled_bill = {"law_id": "finance:2026", "vote_year": 2026, "vote_month": 1, "vote_day": 31, "finance": {"tax_rates_pct": {"vat": 1.0}}}
	_panel._stamp = ""
	_panel._dirty = true
	_panel._process(0.0)
	_expect_caption(vat_id, tr("At vote"))
	_state.player().tabled_bill = {}
	# A kind not in force, drafted in the autumn (the month the nation's bill opens).
	var held_month: int = _state.month
	_state.month = int(_loader.nations[ns.id].finance_autumn_month)
	var kind := ""
	for group in _panel._book["groups"]:
		if not (group["not_in_force"] as Array).is_empty():
			kind = String(group["not_in_force"][0])
			break
	if kind == "":
		_fail("premise: no kind is out of force to draft")
	else:
		_panel._draft.set_create(kind, 1.0)
		_panel._stamp = ""
		_panel._dirty = true
		_panel._process(0.0)
		_expect_caption(FinanceRows.row_id(FinanceDraft.TAX, kind), tr("Creation"))
		_panel._draft.clear_create(kind)
	_state.month = held_month
	_panel._stamp = ""
	_panel._dirty = true
	_panel._process(0.0)


func _expect_caption(id: String, word: String) -> void:
	var cells: Dictionary = _panel._ctx["cells"]
	if not cells.has(id):
		_fail("premise: no kind row for %s" % id)
		return
	var row: Control = (cells[id][0] as Control).get_parent()
	if not String(row.tooltip_text).begins_with("Paid by:"):
		_fail("%s: the row has no 'Paid by' hover: '%s'" % [id, row.tooltip_text])
	var said := false
	for node in row.get_children():
		if node is Label and (node as Label).text == word:
			said = true
	if not said:
		_fail("%s: the caption does not read '%s'" % [id, word])
