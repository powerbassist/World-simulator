extends SceneTree

## Headless test: godot --headless --script res://tests/test_sectors_overview.gd
## Non-zero exit on any failure.
##
## V5.3 rework pass, Sectors overview C ("the economy's shape", the author's pick): the
## overview opens on one lead sentence, the share of output as bars, growth a year as a
## dot plot against the economy's own line, and three sector cards (output, share, jobs
## at named firms, an 18-month curve, the biggest employers, one "Open <sector>"). Every
## figure is checked against the sim's own reader, so a card that drew a stale or a
## swapped number fails here. The per-sector firm cards stay off the overview unless a
## Needs you row routed the player to a firm (sectors_shell.open_firm).

const Companies = preload("res://src/sim/companies.gd")
const Economy = preload("res://src/sim/economy.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const SectorNeeds = preload("res://src/ui/sector_needs.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")
const SectorRead = preload("res://src/ui/sector_read.gd")
const Closures = preload("res://src/sim/closures.gd")
const SectorsShell = preload("res://src/ui/sectors_shell.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0
var _routed := {}


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_panel = _main._companies_panel
			_main._windows.open("companies")
		4:
			_check_shape()
			_check_quiet_world()
			_stage_a_busy_world()
		6:
			_check_busy_world()
			# Pass 2 T7: a dot is a way in, as the card's Open is.
			var dots = _node_with_meta("overview", "growth")
			if dots == null:
				_fail("no growth dot plot to click")
			else:
				dots.picked.emit("services")
		8:
			if not _main._windows.is_open("sector_services"):
				_fail("a click on the Services dot did not open the Services tab")
			_route_to_a_firm()
		11:
			_check_routed_firm_first()
			# Pass 1: once the firm's question is answered, the route and its "waiting" heading go.
			var ns = _main._state.player()
			(ns.companies[_routed["id"]] as Dictionary).erase("closure")
			_panel.mark_dirty()
		13:
			if _node_with_meta("routed_heading", _routed["sector"]) != null:
				_fail("routed: the 'waiting' heading stays after the firm's question is gone")
			_press(_with_meta("open_tab", "sector_industry"))
		15:
			if not _main._windows.is_open("sector_industry"):
				_fail("Open Industry did not open the Industry tab")
			_finish()
	return false


func _check_shape() -> void:
	var ns = _main._state.player()
	var sectors: Array = EK.SECTOR_TREND.keys()
	var total := 0.0
	for s in sectors:
		total += float(ns.sector_output.get(s, 0.0))
	# The lead names the sector with the largest share.
	var top := String(sectors[0])
	for s in sectors:
		if float(ns.sector_output.get(s, 0.0)) > float(ns.sector_output.get(top, 0.0)):
			top = String(s)
	var lead: Label = _panel._title
	if not lead.text.contains(Labels.sector(top)):
		_fail("lead '%s' does not name the largest sector %s" % [lead.text, Labels.sector(top)])

	# ... and the one furthest under the nation's trend.
	var lag := String(sectors[0])
	for s in sectors:
		if Economy.sector_trend_pct(_main._state, ns, String(s)) < Economy.sector_trend_pct(_main._state, ns, lag):
			lag = String(s)
	if not lead.text.contains(Labels.sector(lag)):
		_fail("lead '%s' does not name the slowest sector %s" % [lead.text, Labels.sector(lag)])
	var counts: Dictionary = SectorNeeds.counts(_main._state, _main._loader, ns)
	var waiting_rows := []
	for i in sectors.size():
		if int(counts.get(SectorNeeds.tab_of(String(sectors[i])), 0)) > 0:
			waiting_rows.append(i)

	# Share of output: one bar per sector, its value the sector's share in per cent.
	var share = _node_with_meta("overview", "share")
	if share == null:
		_fail("no share-of-output chart")
	else:
		var rows: Array = share._rows
		if rows.size() != sectors.size():
			_fail("share chart has %d rows, %d sectors" % [rows.size(), sectors.size()])
		for i in mini(rows.size(), sectors.size()):
			var want := 100.0 * float(ns.sector_output.get(sectors[i], 0.0)) / total
			if absf(float(rows[i]["value"]) - want) > 0.05:
				_fail("share of %s drawn %.2f, sim %.2f" % [sectors[i], float(rows[i]["value"]), want])

		if share._marked != waiting_rows:
			_fail("share chart marks rows %s, the waiting sectors are %s" % [share._marked, waiting_rows])

	# A verdict chip per sector, in the sim's words.
	var text_all := _text_under(_panel)
	for s in sectors:
		var words := SectorRead.verdict_words(SectorRead.verdict(Economy.sector_trend_pct(_main._state, ns, String(s)) - float(ns.trend_annual_pct)))
		if not text_all.contains("%s: %s" % [Labels.sector(String(s)), words]):
			_fail("no verdict chip '%s: %s'" % [Labels.sector(String(s)), words])

	# Growth a year: a dot per sector at Economy.sector_trend_pct, the economy's line at the nation's trend.
	var dots = _node_with_meta("overview", "growth")
	if dots == null:
		_fail("no growth dot plot")
	else:
		var data: Array = dots.data()
		for i in mini(data.size(), sectors.size()):
			var want := Economy.sector_trend_pct(_main._state, ns, String(sectors[i]))
			if absf(float(data[i]["after"]) - want) > 1e-6:
				_fail("growth of %s drawn %.3f, sim %.3f" % [sectors[i], float(data[i]["after"]), want])
		if absf(float(dots._reference) - float(ns.trend_annual_pct)) > 1e-6:
			_fail("the economy's line sits at %.3f, the nation's trend is %.3f" % [float(dots._reference), float(ns.trend_annual_pct)])

	# Three cards: output, the biggest employer by headcount, one Open, and the decision chip iff something waits.
	for s in sectors:
		var card = _node_with_meta("sector_card", String(s))
		if card == null:
			_fail("no card for %s" % s)
			continue
		var text := _text_under(card)
		var output := Num.f(float(ns.sector_output.get(s, 0.0)), 0)
		if not text.contains(output):
			_fail("%s card does not print its output %s bn: '%s'" % [s, output, text])
		var jobs := 0.0
		var firms: Array = Companies.firms_in_sector(_main._loader, ns.id, String(s))
		for company in firms:
			jobs += Companies.headcount(ns, company)
		if not text.contains(CompanyVerb.thousands(jobs)):
			_fail("%s card does not print its jobs %s: '%s'" % [s, CompanyVerb.thousands(jobs), text])
		var biggest = null
		for company in firms:
			if biggest == null or Companies.headcount(ns, company) > Companies.headcount(ns, biggest):
				biggest = company
		var employers = _node_with_meta("employers", String(s))
		if biggest != null and (employers == null or employers._rows.is_empty()
				or String(employers._rows[0]["label"]) != String(biggest.company_name)):
			_fail("%s card does not rank its biggest employer %s first" % [s, biggest.company_name])
		if employers != null and employers._rows.size() != mini(firms.size(), 4):
			_fail("%s card ranks %d employers, expected %d" % [s, employers._rows.size(), mini(firms.size(), 4)])
		if _with_meta("open_tab", SectorNeeds.tab_of(String(s))) == null:
			_fail("%s card has no Open button" % s)
		var waiting := int(counts.get(SectorNeeds.tab_of(String(s)), 0)) > 0
		if (_node_with_meta("decision_chip", String(s)) != null) != waiting:
			_fail("%s card's decision chip shown=%s, waiting=%s" % [s, not waiting, waiting])
		if _main._state.history.size() >= 2 and _node_with_meta("sector_curve", String(s)) == null:
			_fail("%s card has no output curve" % s)
	if not _visible_buttons_with_meta("company_id").is_empty():
		_fail("a firm's Act is on the overview without a route to it")


## Pass 2 on #427, the fresh game: the fold mark has its button, the trend is called a trend, and the lead names a
## lagging sector only when one lags.
func _check_quiet_world() -> void:
	var primary = _panel.primary_action()
	if primary == null or not primary.has_meta("open_tab"):
		_fail("primary_action() finds no Open button: the fold mark never shows")
	var text_all := _text_under(_panel)
	if text_all.contains("Growth a year") or not text_all.contains("Trend a year"):
		_fail("the dot plot is not titled 'Trend a year' as the sector tab is")
	var ns = _main._state.player()
	var lags := false
	for s in EK.SECTOR_TREND.keys():
		if SectorRead.head(_main._state, _main._loader, ns, String(s))["verdict"] in ["behind", "slower"]:
			lags = true
	if _panel._title.text.contains("Slowest") != lags:
		_fail("the lead names a slowest sector (%s) though a sector lags is %s" % [_panel._title.text, lags])


## A burden on Industry, a failed Services major, closures announced in two sectors.
func _stage_a_busy_world() -> void:
	var state = _main._state
	var ns = state.player()
	ns.regulation_burden["industry"] = 0.3
	# Every Services firm fails: a sorted list would put one failed firm last, a whole failed sector shows it.
	for company in Companies.firms_in_sector(_main._loader, ns.id, "services"):
		if not ns.companies.has(company.id):
			ns.companies[company.id] = {}
		ns.companies[company.id]["failed"] = true
	for sector in ["agriculture", "industry"]:
		for company in Companies.majors_of(_main._loader, ns.id):
			if String(company.sector) == sector and ns.companies.has(company.id):
				Closures._announce(ns, company, ns.companies[company.id], 0.2, _main._loader.closure_rule, state.year * 12 + state.month)
				break
	_panel.mark_dirty()


func _check_busy_world() -> void:
	var ns = _main._state.player()
	var sectors: Array = EK.SECTOR_TREND.keys()
	var card = _node_with_meta("sector_card", "industry")
	var burden := Strings.t("Regulated: %s") % Num.fs(0.3, 2)
	if card == null or not _text_under(card).contains(burden):
		_fail("the Industry card does not carry its burden '%s'" % burden)
	var gone = _node_with_meta("employers", "services")
	if gone != null and not gone._rows.is_empty():
		_fail("failed firms are ranked among the biggest employers: %s" % [gone._rows])
	var employers = _node_with_meta("employers", "industry")
	if employers != null:
		if not employers._rows.is_empty():
			var v := float(employers._rows[0]["value"])
			if employers.value_text(0) != CompanyVerb.thousands(v):
				_fail("employer figure '%s', the jobs figure's format is '%s'" % [employers.value_text(0), CompanyVerb.thousands(v)])
	var counts: Dictionary = SectorNeeds.counts(_main._state, _main._loader, ns)
	var share = _node_with_meta("overview", "share")
	var waiting := 0
	for i in sectors.size():
		var waits := int(counts.get(SectorNeeds.tab_of(String(sectors[i])), 0)) > 0
		if waits:
			waiting += 1
		if share != null and waits != (share.bar_color(i) == UiTheme.WARN):
			_fail("share bar %s drawn %s, waiting %s (a decision is the WARN tone, every waiting sector)" % [sectors[i], share.bar_color(i), waits])
		if share != null and share.bar_color(i) == UiTheme.accent():
			_fail("share bar %s wears the accent: status is a fixed tone" % sectors[i])
	if waiting < 2:
		_fail("setup: %d sectors wait, expected 2" % waiting)
	var dots = _node_with_meta("overview", "growth")
	if dots != null:
		for r in dots.data():
			if bool(r.get("selected", false)):
				_fail("the dot plot marks %s in the accent as waiting" % r["id"])


## Pass 2 T4: Needs you > Answer lands on the firm's card, first, under a heading, its verb focused.
func _route_to_a_firm() -> void:
	var ns = _main._state.player()
	for company in Companies.majors_of(_main._loader, ns.id):
		if String(company.sector) == "industry":
			_routed = {"sector": "industry", "id": String(company.id)}
			break
	SectorsShell.open_firm(_routed["sector"], _routed["id"], _main)


func _check_routed_firm_first() -> void:
	var body: Control = _panel._body
	var first_card := -1
	var first_chart := -1
	for i in body.get_child_count():
		var child := body.get_child(i)
		if child.is_queued_for_deletion():
			continue
		if first_chart < 0 and child.find_children("*", "ChartBars", true, false).size() + int(child is HBoxContainer and child.get_child_count() > 0 and child.get_child(0).find_children("*", "", true, false).any(func(n): return n.has_meta("overview"))) > 0:
			first_chart = i
		if first_card < 0 and not child.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("company_id") and String(b.get_meta("company_id")) == _routed["id"]).is_empty():
			first_card = i
	if first_card < 0:
		_fail("routed: the firm's card is not on the overview")
	elif first_chart >= 0 and first_card > first_chart:
		_fail("routed: the firm's card (child %d) lands under the charts (child %d)" % [first_card, first_chart])
	if _node_with_meta("routed_heading", _routed["sector"]) == null:
		_fail("routed: no heading over the firm's card")
	# A mouse route takes no keyboard focus (Space is the pause key): the page opens at the top, where the card sits.
	var focus = _panel.get_viewport().gui_get_focus_owner()
	if focus != null and _panel.is_ancestor_of(focus):
		_fail("routed: a route gave code focus to %s" % focus)
	if _panel._scroll.scroll_vertical != 0:
		_fail("routed: the page is scrolled to %d, the card sits at the top" % _panel._scroll.scroll_vertical)


func _node_with_meta(key: String, value: String):
	for node in _panel.find_children("*", "", true, false):
		if node.has_meta(key) and String(node.get_meta(key)) == value and (node as Control).is_visible_in_tree():
			return node
	return null


func _with_meta(key: String, value: String):
	for b in _visible_buttons_with_meta(key):
		if String(b.get_meta(key)) == value:
			return b
	return null


func _visible_buttons_with_meta(key: String) -> Array:
	var out := []
	for b in _panel.find_children("*", "Button", true, false):
		if b.has_meta(key) and (b as Control).is_visible_in_tree():
			out.append(b)
	return out


func _press(button) -> void:
	if button == null:
		_fail("frame %d: the control to press is not on screen" % _frame)
		return
	(button as Button).pressed.emit()


func _text_under(node: Node) -> String:
	var out := ""
	for label in node.find_children("*", "Label", true, false):
		out += (label as Label).text + " "
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_sectors_overview: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		quit(1)
