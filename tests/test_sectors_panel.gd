extends SceneTree

## Headless test: godot --headless --script res://tests/test_sectors_panel.gd
## Non-zero exit on any failure.
##
## V5.3 screen 5, slice 1 (the author's pick C, "les produits"): the Sectors domain.
## Its tabs are the overview (the window id "companies", today's verbs until slice 2)
## and one read-only tab per modelled sector. What this pins:
##
##   - THE SHELL. The domain holds the four tabs in order; Commodities is retired (no
##     window, no row); a tab that needs you carries its count, the sidebar row the
##     total, and both are one reader's (SectorNeeds), so they cannot disagree.
##   - THE HEAD. The verdict is a rule over the sector's trend against the nation's,
##     both sides of each edge; the lead sentence and the four figures are the sim's.
##   - WHAT IT MAKES. A row per good the sector makes, the majors' products among
##     them; the price change reads the ring as it is held (0, 1 and 12 months); a
##     good short of demand says so on its row, and the strip's Go lands on that tab.
##   - NEEDS YOU. A closure on a major is a row on its sector's tab, and its Go opens
##     the overview with that firm opened -- the answer's home until slice 2.
##
## Driven a frame at a time through the real main scene (AGENTS.md: a Control out of
## the tree is half-dead).

const Domains = preload("res://src/ui/domains.gd")
const Companies = preload("res://src/sim/companies.gd")
const Closures = preload("res://src/sim/closures.gd")
const Pending = preload("res://src/ui/pending.gd")
const SectorNeeds = preload("res://src/ui/sector_needs.gd")
const SectorRead = preload("res://src/ui/sector_read.gd")
const SectorGoods = preload("res://src/ui/sector_goods.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")
const Economy = preload("res://src/sim/economy.gd")

const TABS := ["companies", "sector_agriculture", "sector_industry", "sector_services"]

var _failures: Array[String] = []
var _main
var _frame := 0
var _major
var _second
var _panel


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_check_shell()
			_check_verdict_rule()
			_check_price_change()
			_stage_closure()
			_main._windows.open("sector_industry")
		5:
			_check_industry_tab()
			_check_tab_marks()
			_press_chip()
		7:
			_check_chip_filter()
			_press_go()
		9:
			_check_go_landed()
			_check_shortage()
			_clear_closure()
		11:
			_check_marks_cleared()
			# The scene goes a frame before the quit: its text shapes are freed, not leaked.
			_main.queue_free()
		13:
			_finish()
			return true
	return false


func _check_shell() -> void:
	if Domains.domain_of("companies") != "sectors":
		_fail("the overview is in domain '%s', not 'sectors'" % Domains.domain_of("companies"))
	var tabs: Array = Domains.tabs("sectors", _main._windows.panel_ids())
	if tabs != TABS:
		_fail("the Sectors domain shows %s, expected %s" % [tabs, TABS])
	if _main._windows.panel_ids().has("commodities") or Domains.domain_of("commodities") != "":
		_fail("Commodities is still a window or a row: it retires into the sector tabs")
	if _main._windows.title("companies") != "Overview":
		_fail("the overview tab is titled '%s'" % _main._windows.title("companies"))
	for sector in ["agriculture", "industry", "services"]:
		if SectorNeeds.tab_of(sector) != "sector_" + sector:
			_fail("SectorNeeds.tab_of(%s) is '%s'" % [sector, SectorNeeds.tab_of(sector)])


## Each edge on both sides: the gap is the sector's trend less the nation's, in points.
func _check_verdict_rule() -> void:
	var cases := [[-1.1, "behind"], [-SectorRead.BEHIND, "slower"], [-0.3, "slower"],
		[-SectorRead.PACE, "pace"], [0.0, "pace"], [SectorRead.PACE, "pace"], [0.6, "ahead"]]
	for c in cases:
		var got: String = SectorRead.verdict(float(c[0]))
		if got != String(c[1]):
			_fail("verdict(%s) is '%s', expected '%s'" % [c[0], got, c[1]])


## The ring holds 0 to 12 months: under two there is no change to read.
func _check_price_change() -> void:
	if not is_nan(SectorGoods.price_change([])):
		_fail("an empty ring reads a price change")
	if not is_nan(SectorGoods.price_change([100.0])):
		_fail("one month reads a price change")
	var ring: Array = []
	for i in 12:
		ring.append(100.0 + i)
	if absf(SectorGoods.price_change(ring) - 11.0) > 1e-6:
		_fail("twelve months 100 -> 111 read %s %%, expected 11 %%" % SectorGoods.price_change(ring))


func _stage_closure() -> void:
	var state = _main._state
	var ns = state.player()
	for company in Companies.majors_of(_main._loader, ns.id):
		if String(company.sector) == "industry":
			_major = company
			break
	if _major == null:
		_fail("no industry major to stage a closure on")
		return
	Closures._announce(ns, _major, ns.companies[_major.id], 0.2, _main._loader.closure_rule, state.year * 12 + state.month)
	var counts: Dictionary = SectorNeeds.counts(state, _main._loader, ns)
	if int(counts.get("sector_industry", 0)) != 1 or int(counts.get("sector_agriculture", 0)) != 0:
		_fail("one closure in industry counts %s" % counts)
	var ids: Array = Pending.window_ids(state, _main._loader)
	if ids.count("companies") != 1:
		_fail("the pending ids carry 'companies' %d times for one item" % ids.count("companies"))
	# A second item, in another sector (QA's T1 on #378): ONE id per item, so the
	# Sectors row counts the items, 2, not the window, 1.
	for company in Companies.majors_of(_main._loader, ns.id):
		if String(company.sector) == "agriculture":
			_second = company
			break
	Closures._announce(ns, _second, ns.companies[_second.id], 0.2, _main._loader.closure_rule, state.year * 12 + state.month)
	ids = Pending.window_ids(state, _main._loader)
	if ids.count("companies") != 2:
		_fail("two items carry 'companies' %d times in the pending ids" % ids.count("companies"))
	preload("res://src/ui/sectors_shell.gd").show_pending(_main)
	var pill: Label = _main._hud.sidebar._pills.get("sectors")
	if pill == null or pill.text != "2" or not pill.visible:
		_fail("the Sectors row reads '%s' for two waiting items" % (pill.text if pill != null else "none"))


func _check_industry_tab() -> void:
	_panel = _main._sector_panels.get("industry")
	if _panel == null or not _panel.is_visible_in_tree():
		_fail("the industry tab is not shown")
		return
	var ns = _main._state.player()
	var text := _text_of(_panel)
	var gap: float = float(Economy.sector_trend_pct(_main._state, ns, "industry")) - float(ns.trend_annual_pct)
	var words: String = SectorRead.verdict_words(SectorRead.verdict(gap))
	if not text.contains(words):
		_fail("the head does not carry the verdict '%s'" % words)
	if not text.contains(_main.tr("Needs you").to_upper()):
		_fail("no Needs you section with a closure staged")
	if not text.contains(_major.company_name):
		_fail("the tab does not name %s" % _major.company_name)
	for good_id in _major.products:
		var good = _main._loader.commodity_goods.get(good_id)
		if good != null and not text.contains(String(good.name)):
			_fail("what industry makes does not list %s, a major's product" % good.name)
	for company in Companies.majors_of(_main._loader, ns.id):
		if String(company.sector) == "industry" and not text.contains(company.company_name):
			_fail("the majors do not list %s" % company.company_name)
	for row in SectorGoods.rows(_main._state, _main._loader, ns, "industry"):
		if SectorGoods.sector_of_good(_main._loader, String(row["good_id"])) != "industry":
			_fail("industry lists %s, a good of another sector" % row["good_id"])


func _check_tab_marks() -> void:
	var tab := _tab_button("sector_industry")
	if tab == null:
		_fail("no tab button for sector_industry")
	elif not tab.text.contains("1") or tab.icon == null:
		_fail("the industry tab carries no hourglass and count: '%s'" % tab.text)
	var quiet := _tab_button("sector_services")
	if quiet != null and quiet.icon != null:
		_fail("the services tab carries an hourglass with nothing waiting")
	if not _main._hud.sidebar.pending_domains().has("sectors"):
		_fail("the sidebar's Sectors row carries no count")


## A good's chip filters the table to its row; the other rows leave the grid.
var _chip_good := ""


func _press_chip() -> void:
	var rows: Array = SectorGoods.rows(_main._state, _main._loader, _main._state.player(), "industry")
	if rows.size() < 2:
		_fail("industry shows %d goods, too few to filter" % rows.size())
		return
	_chip_good = String(rows[1]["good_id"])
	for button in _panel.find_children("*", "Button", true, false):
		if button.has_meta("good") and String(button.get_meta("good")) == _chip_good:
			button.pressed.emit()
			return
	_fail("no chip for %s" % _chip_good)


func _check_chip_filter() -> void:
	var rows: Array = SectorGoods.rows(_main._state, _main._loader, _main._state.player(), "industry")
	var grid := _goods_grid()
	if grid == null or rows.size() < 2:
		_fail("no goods table to filter")
		return
	var text := _text_of(grid)
	if not text.contains(String(rows[1]["name"])) or text.contains(String(rows[0]["name"]) + "
"):
		_fail("the chip for %s did not filter the table to its row: %s" % [_chip_good, text])
	for button in _panel.find_children("*", "Button", true, false):
		if button.has_meta("good") and String(button.get_meta("good")) == "":
			button.pressed.emit()


func _goods_grid() -> GridContainer:
	for node in _panel.find_children("*", "GridContainer", true, false):
		if (node as GridContainer).columns == 4:
			return node
	return null


func _press_go() -> void:
	for button in _panel.find_children("*", "Button", true, false):
		if button.has_meta("go_firm") and String(button.get_meta("go_firm")) == String(_major.id):
			button.pressed.emit()
			return
	_fail("the needs-you row has no Go for %s" % _major.id)


## Slice 2: a closure's Answer selects its firm on the tab's sheet, where it is answered;
## the overview's route (go_firm) stays for a bid, a failing major or an ask, and still
## opens the firm there.
func _check_go_landed() -> void:
	if not _main._windows.is_open("sector_industry") or _panel._firm_id != String(_major.id):
		_fail("a closure's Answer selected '%s' on the sheet, not %s" % [_panel._firm_id, _major.id])
	preload("res://src/ui/sectors_shell.gd").open_firm("industry", String(_major.id), _main)
	var companies = _main._companies_panel
	# G3 S3: the route picks the firm's timeline row, if it has one; the overview has no firm card.
	if not _main._windows.is_open("companies") or not companies._pick_firm in ["", String(_major.id)]:
		_fail("go_firm opened the overview on firm '%s', not %s" % [companies._pick_firm, _major.id])


## A good covered under the line says so on its sector's row, and the strip's Go aims
## at that tab, not at a retired window.
func _check_shortage() -> void:
	var state = _main._state
	var ns = state.player()
	var rows: Array = SectorGoods.rows(state, _main._loader, ns, "industry")
	if rows.is_empty():
		_fail("industry makes nothing")
		return
	# The LAST row goes short: a short good sorts first, so the strip's Go finds its row.
	var good_id := String(rows[-1]["good_id"])
	var cs: Dictionary = ns.commodity_state
	var keep: Dictionary = cs.duplicate(true)
	for gid in cs["demand"].keys():
		cs["demand"][gid] = 0.0
	cs["demand"][good_id] = 100.0
	cs["output"][good_id] = 100.0 * SectorGoods.SHORTAGE_COVERAGE - 1.0
	cs["trade"][good_id] = 0.0
	_main._windows.open("sector_industry")
	_panel.mark_dirty()
	_panel._refresh()
	var after: Array = SectorGoods.rows(state, _main._loader, ns, "industry")
	if String(after[0]["good_id"]) != good_id:
		_fail("a short good sorts at %s, not first" % after[0]["good_id"])
	if not _text_of(_panel).contains(_main.tr("short")):
		_fail("a good under the shortage line does not say 'short' on its row")
	var reading: Dictionary = StripReadings._commodities(ns, _main._loader)
	if String(reading.get("alert_window", "")) != "sector_industry":
		_fail("the supplies reading's Go aims at '%s'" % reading.get("alert_window", ""))
	cs["demand"] = keep["demand"]
	cs["output"] = keep["output"]
	cs["trade"] = keep["trade"]


## The answer lands (the closure leaves the register): main's own refresh path clears
## the tab's hourglass and count, and the sidebar's.
func _clear_closure() -> void:
	(_main._state.player().companies[_major.id] as Dictionary).erase("closure")
	(_main._state.player().companies[_second.id] as Dictionary).erase("closure")
	_main._update_top_bar()
	_main._windows.open("sector_industry")


func _check_marks_cleared() -> void:
	var tab := _tab_button("sector_industry")
	if tab == null or tab.icon != null or tab.text.contains("1"):
		_fail("the industry tab still carries a mark after the answer: '%s'" % (tab.text if tab != null else "none"))
	if _main._hud.sidebar.pending_domains().has("sectors"):
		_fail("the sidebar's Sectors row still counts after the answer")


func _tab_button(tab_id: String) -> Button:
	for button in _main._windows._tab_row.get_children():
		if String(button.get_meta("tab", "")) == tab_id:
			return button
	return null


func _text_of(node: Node) -> String:
	var parts: Array[String] = []
	for child in node.find_children("*", "", true, false):
		if child is Label or child is Button:
			parts.append(String(child.text))
		elif child is RichTextLabel:
			parts.append(child.get_parsed_text())
		elif child.has_method("get_parsed_text"):
			parts.append(child.get_parsed_text())
	return "\n".join(parts)


func _fail(msg: String) -> void:
	_failures.append(msg)
	push_error("FAIL " + msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_sectors_panel: PASS")
		quit(0)
	else:
		print("test_sectors_panel: %d failure(s)" % _failures.size())
		quit(1)
