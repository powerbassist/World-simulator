extends SceneTree

## Headless test: godot --headless --script res://tests/test_firm_sheet.gd
## Non-zero exit on any failure.
##
## V5.3 screen 5, slice 2: a sector tab's firm sheet and its verbs. What this pins:
##
##   - THE SHEET shows the selected firm; a closure's Answer selects its firm, and the
##     sheet carries the closure's answers and the region line (ClosureRegion.move).
##   - AID AS THE PLAYER WEIGHS IT: the subsidy's row says its EUR a job and its share of
##     a tax point (CompaniesAid.per_year over the firm's jobs and one point of income
##     tax); its focused strip says the jobs it moves (CompaniesAid.net_jobs) and its
##     blocs scaled by the firm's credit factor.
##   - THE SHEET ACTS: the subsidy's Go grants it through the shared commands and emits
##     acted (main's decision delta).
##   - THE PROGRAMME as a finance-bill row: a stop picked on the slider shows its price and
##     "Put it in the finance bill"; the press tables the row; the typed box snaps.
##   - THE RIGHT CLICK lists each verb with its price, the call to the chief and the map.

const Companies = preload("res://src/sim/companies.gd")
const CompaniesAid = preload("res://src/sim/companies_aid.gd")
const Closures = preload("res://src/sim/closures.gd")
const ClosureRegion = preload("res://src/sim/closure_region.gd")
const AidWords = preload("res://src/ui/aid_words.gd")
const SectorProgramme = preload("res://src/ui/sector_programme.gd")
const FinanceRows = preload("res://src/sim/finance_rows.gd")
const Num = preload("res://src/ui/num.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0
var _major
var _acted := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_stage()
			_main._windows.open("sector_industry")
		4:
			_check_default_and_closure()
			_check_aid_words()
			_focus_subsidy()
		6:
			_check_focused_strip()
			_press_subsidy_go()
		8:
			_check_granted()
			_pick_programme(1)
		10:
			_check_programme_strip()
			_table_programme()
		12:
			_check_tabled()
			_check_typed_box_snaps()
			_check_menu()
		14:
			# The scene goes a frame before the quit: its text shapes are freed, not leaked.
			_main.queue_free()
		16:
			_finish()
			return true
	return false


func _stage() -> void:
	var state = _main._state
	var ns = state.player()
	for company in Companies.majors_of(_main._loader, ns.id):
		if String(company.sector) == "industry":
			_major = company
			break
	Closures._announce(ns, _major, ns.companies[_major.id], 0.2, _main._loader.closure_rule, state.year * 12 + state.month)
	_panel = _main._sector_panels["industry"]
	_panel.acted.connect(func(_b, _l) -> void: _acted += 1)


## The waiting firm is the default; its closure is filed on the sheet with the region line.
func _check_default_and_closure() -> void:
	var ns = _main._state.player()
	if _panel._selected(ns) != _major:
		_fail("the sheet opens on %s, not the firm whose closure waits" % (_panel._selected(ns).id if _panel._selected(ns) != null else "nothing"))
	var answers := _with_meta(_panel._sheet, "closure_answer")
	if answers.is_empty():
		_fail("the sheet carries no closure answers")
	var region := _with_meta(_panel._sheet, "closure_region")
	var move: Dictionary = ClosureRegion.move(_main._state, ns, Closures.announced(ns, _major.id))
	if region.is_empty():
		_fail("the sheet's closure has no region line (move: %s)" % move)
	else:
		# Before, then after (QA's T2 on #381): the order is the sentence's meaning.
		var arrow := "%s %% → %s %%" % [Num.f(float(move["before_pct"]), 1), Num.f(float(move["after_pct"]), 1)]
		if not String(region[0].text).contains(arrow):
			_fail("the region line '%s' does not read '%s'" % [region[0].text, arrow])


## The subsidy's caption: the sim's per-year price over the firm's jobs, and over one point
## of income tax, printed on the sheet.
func _check_aid_words() -> void:
	var ns = _main._state.player()
	var action = _action("industrial_subsidy")
	var expected := AidWords.caption(_main._state, _main._loader, ns, _major, action)
	var per_year := CompaniesAid.per_year(ns, _major, 0.6)
	var point := float(_main._loader.taxes["income"]["base_share"]) * float(ns.gdp_eur_bn) / 100.0
	if not expected.contains(Num.f(per_year / point, 2)):
		_fail("the aid caption '%s' does not carry %s of a tax point" % [expected, Num.f(per_year / point, 2)])
	if not _text_of(_panel._sheet).contains(expected):
		_fail("the sheet does not print the subsidy's caption '%s'" % expected)


func _focus_subsidy() -> void:
	for button in _panel._sheet.find_children("*", "Button", true, false):
		if String(button.get_meta("action_id", "")) == "industrial_subsidy":
			button.pressed.emit()
			return
	_fail("no subsidy row on the sheet")


## The focused aid says the jobs it moves (net_jobs) and books its blocs times the credit.
func _check_focused_strip() -> void:
	var ns = _main._state.player()
	var action = _action("industrial_subsidy")
	var lines := _with_meta(_panel._sheet, "net_jobs")
	var expected := AidWords.net_jobs_line(_main._state, _main._loader, ns, _major, action)
	if lines.is_empty() or String(lines[0].text) != expected or expected == "":
		_fail("the focused subsidy does not say the jobs it moves: '%s'" % expected)
	elif not lines[0].is_visible_in_tree():
		_fail("the net jobs line is built but not shown with the subsidy focused")
	# The figures against the sim's, signed (QA's T3 on #381): gained +, lost at rivals -.
	var moved: Dictionary = CompaniesAid.net_jobs(_main._state, ns, _main._loader, action, _major)
	for pair in [["+", float(moved["gained"])], ["−", float(moved["lost_at_rivals"])]]:
		var figure: String = String(pair[0]) + CompanyVerb.thousands(absf(roundf(float(pair[1]) / 100.0) * 100.0))
		if float(pair[1]) >= 100.0 and not expected.contains(figure):
			_fail("the net jobs line '%s' does not carry %s" % [expected, figure])
	# The factor execute() would book (granted_credit), not the live read (pass 2 on #390).
	var factor := CompaniesAid.granted_credit(_main._state, ns, _main._loader, action, String(_major.id))
	var scaled := AidWords.offsets(_main._state, _main._loader, ns, _major, action)
	var raw: Dictionary = action.effects["bloc_offset"]
	for bloc in raw:
		if absf(float(scaled[bloc]) - float(raw[bloc]) * factor) > 1e-9:
			_fail("the %s offset reads %s, not %s x %s" % [bloc, scaled[bloc], raw[bloc], factor])


func _press_subsidy_go() -> void:
	for button in _panel._sheet.find_children("*", "Button", true, false):
		if button.has_meta("go") and button.is_visible_in_tree():
			button.pressed.emit()
			return
	_fail("no visible Go under the focused subsidy")


func _check_granted() -> void:
	var ns = _main._state.player()
	if Companies.subsidy_of(ns, _major.id) <= 0.0:
		_fail("the sheet's Go did not grant the subsidy")
	if _acted != 1:
		_fail("the grant emitted acted %d times" % _acted)
	# The withdrawal's blocs as the press books them (QA's T1 on #381): the grant kept its
	# credit on the entry, and a preview on a copy books exactly what the strip prints.
	var withdraw = _action("withdraw_support")
	var shown := AidWords.offsets(_main._state, _main._loader, ns, _major, withdraw)
	var copy = Companies.preview(_main._state, ns, _main._loader.company_actions, withdraw, String(_major.id), _main._loader)[0]
	for bloc in withdraw.effects["bloc_offset"]:
		var booked := float(copy.bloc_offset.get(bloc, 0.0)) - float(ns.bloc_offset.get(bloc, 0.0))
		if absf(booked - float(shown[bloc])) > 1e-6:
			_fail("withdraw's %s: the strip says %s, the press books %s" % [bloc, shown[bloc], booked])


func _pick_programme(stop: int) -> void:
	for node in _panel.find_children("*", "HSlider", true, false):
		if String(node.get_meta("programme", "")) == "industry":
			node.value = stop
			return
	_fail("no programme slider on the industry tab")


func _check_programme_strip() -> void:
	if _with_meta(_panel, "table_programme").is_empty():
		_fail("a programme stop picked shows no 'Put it in the finance bill'")


func _table_programme() -> void:
	var buttons := _with_meta(_panel, "table_programme")
	if not buttons.is_empty():
		buttons[0].pressed.emit()


func _check_tabled() -> void:
	var ns = _main._state.player()
	var list := SectorProgramme.stops(_main._loader, "industry")
	var tabled := String(ns.tabled_bill.get("finance", {}).get(FinanceRows.PROGRAMMES, {}).get("industry", ""))
	if tabled != String(list[1]["action"].id):
		_fail("the finance bill holds '%s' for industry, expected %s (refusal: %s)" % [tabled, list[1]["action"].id, _panel._last_refusal])
	if not _text_of(_panel).contains(String(_main.tr("In the finance bill: %s, voted at the month's end.")).split(":")[0]):
		_fail("the tab does not say the programme is in the finance bill")


## The typed price snaps to the nearest stop.
func _check_typed_box_snaps() -> void:
	var ns = _main._state.player()
	var list := SectorProgramme.stops(_main._loader, "industry")
	var top := SectorProgramme.price(_main._state, _main._loader, ns, list, "industry", list.size() - 1)
	for node in _panel.find_children("*", "SpinBox", true, false):
		if String(node.get_meta("programme_box", "")) == "industry":
			node.value = top * 0.97
			if _panel._prog_pick != list.size() - 1:
				_fail("typing %s bn a year picked stop %d, not the top" % [top * 0.97, _panel._prog_pick])
			return
	_fail("no typed box on the programme row")


func _check_menu() -> void:
	# A right click on a major's NAME opens the plate (QA's play of #381: only the face did).
	var plate = preload("res://src/ui/verb_plate.gd").of(_panel)
	plate.hide()
	for button in _panel.find_children("*", "Button", true, false):
		if String(button.get_meta("firm", "")) == String(_major.id):
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_RIGHT
			click.pressed = true
			button.gui_input.emit(click)
	if plate == null or not plate.visible:
		_fail("a right click on %s's name opens no plate" % _major.company_name)
	elif plate != null:
		plate.hide()
	var ns = _main._state.player()
	var items: Array = _panel.menu_items(_major)
	var texts := []
	for item in items:
		texts.append(String(item["text"]))
	var joined := "\n".join(texts)
	for action in Companies.available(_main._state, ns, _main._loader.company_actions, String(_major.id), _main._loader):
		if not joined.contains(String(action.action_name)) and not joined.contains(_main.tr(String(action.action_name))):
			_fail("the right click does not list %s" % action.id)
	if not joined.contains(_main._loader.person_name(String(_major.chief_id))):
		_fail("the right click does not offer to call the chief")
	if not joined.contains(_main.tr("Show on the map")):
		_fail("the right click does not offer the map")
	# A verb's item selects the firm and focuses that verb on the sheet (GLM's gap 8).
	for item in items:
		if String(item["text"]).contains(String(_action("industrial_subsidy").action_name)):
			_panel._firm_id = ""
			item["call"].call()
			if _panel._firm_id != String(_major.id) or _panel._focus_verb != "industrial_subsidy":
				_fail("the menu's subsidy picked firm '%s', verb '%s'" % [_panel._firm_id, _panel._focus_verb])
	# An arrow's nudge moves one stop; a typed price snaps to the nearest.
	var prices := [0.0, 2.5, 4.6]
	if SectorProgramme.snap_stop(prices, 1, 2.51, 0.01) != 2 or SectorProgramme.snap_stop(prices, 1, 2.49, 0.01) != 0:
		_fail("a one-step nudge does not move to the next stop")
	if SectorProgramme.snap_stop(prices, 0, 4.0, 0.01) != 2:
		_fail("a typed 4.0 does not snap to the nearest stop")


func _action(id: String):
	for a in _main._loader.company_actions:
		if String(a.id) == id:
			return a
	return null


func _with_meta(node: Node, key: String) -> Array:
	var out: Array = []
	for child in node.find_children("*", "", true, false):
		if child.has_meta(key):
			out.append(child)
	return out


func _text_of(node: Node) -> String:
	var parts: Array[String] = []
	for child in node.find_children("*", "", true, false):
		if child is Label or child is Button:
			parts.append(String(child.text))
		elif child is RichTextLabel:
			parts.append(child.get_parsed_text())
	return "\n".join(parts)


func _fail(msg: String) -> void:
	_failures.append(msg)
	push_error("FAIL " + msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_firm_sheet: PASS")
		quit(0)
	else:
		print("test_firm_sheet: %d failure(s)" % _failures.size())
		quit(1)
