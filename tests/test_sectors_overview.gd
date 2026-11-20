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
			_panel = _main._companies_panel
			_main._windows.open("companies")
		4:
			_check_shape()
			_press(_with_meta("open_tab", "sector_industry"))
		6:
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
	var counts: Dictionary = SectorNeeds.counts(_main._state, _main._loader, ns)
	for s in sectors:
		var card = _node_with_meta("sector_card", String(s))
		if card == null:
			_fail("no card for %s" % s)
			continue
		var text := _text_under(card)
		var output := Num.f(float(ns.sector_output.get(s, 0.0)), 0)
		if not text.contains(output):
			_fail("%s card does not print its output %s bn: '%s'" % [s, output, text])
		var biggest = null
		for company in Companies.firms_in_sector(_main._loader, ns.id, String(s)):
			if biggest == null or Companies.headcount(ns, company) > Companies.headcount(ns, biggest):
				biggest = company
		var employers = _node_with_meta("employers", String(s))
		if biggest != null and (employers == null or employers._rows.is_empty()
				or String(employers._rows[0]["label"]) != String(biggest.company_name)):
			_fail("%s card does not rank its biggest employer %s first" % [s, biggest.company_name])
		if _with_meta("open_tab", SectorNeeds.tab_of(String(s))) == null:
			_fail("%s card has no Open button" % s)
		var waiting := int(counts.get(SectorNeeds.tab_of(String(s)), 0)) > 0
		if (_node_with_meta("decision_chip", String(s)) != null) != waiting:
			_fail("%s card's decision chip shown=%s, waiting=%s" % [s, not waiting, waiting])
		if _main._state.history.size() >= 2 and _node_with_meta("sector_curve", String(s)) == null:
			_fail("%s card has no output curve" % s)
	if not _visible_buttons_with_meta("company_id").is_empty():
		_fail("a firm's Act is on the overview without a route to it")


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
