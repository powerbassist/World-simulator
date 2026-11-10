extends SceneTree

## Headless test: godot --headless --script res://tests/test_region_fund.gd
## Non-zero exit on any failure.
##
## V5.3 a + b, docs/design/v5.3-ab.md 3.3 (a), the fund half (#263): the opened
## region names its ONE problem first (Regions.problem(), its worst figure against
## the nation), then the development fund as a verb with its strip -- the money a
## year, the blocs it moves, the region's unemployment now and with the fund
## (RegionFunds.estimate()) -- and a Go. At the cap of open funds the Go is greyed
## and the sim's line says why, before any press (A5's grammar). A running fund
## shows on its region with a Stop. The Budget's table carries the fund's bill on a
## line of its own (region_fund_bill_pct_gdp), not on the public works line.
##
## The fund's strip is the one without the "priority" meta: the sector priority
## (region_priority.gd) draws its own strip under it.
##
## Driven through the real controls a frame apart (AGENTS.md: a Control built but
## not shown fails silently).

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Regions = preload("res://src/sim/regions.gd")
const RegionFunds = preload("res://src/sim/region_funds.gd")
const Migration = preload("res://src/sim/migration.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const Labels = preload("res://src/ui/labels.gd")

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0
var _regions: Array = []


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_panel = _main._windows.content("region")
			var ns = _main._state.player()
			for region in _main._loader.regions.get(ns.id, []):
				if Regions.output_eur_bn(ns, region.id) > 0.0:
					_regions.append(region)
			if _regions.size() < 4:
				_fail("premise: France needs four regions with output, has %d" % _regions.size())
				_finish()
				return false
			_main._windows.open("region")
		4:
			_press(_region_button(_regions[0]))
		6:
			_check_problem(_regions[0])
			_check_strip(_regions[0])
			_press(_with_meta("go"))
		8:
			_check_started(_regions[0])
			_check_budget_row()
			_fill_to_the_cap()
			_press(_region_button(_regions[0]))
		10:
			_press(_region_button(_regions[3]))
		12:
			_check_cap()
			_move_a_sum()
		14:
			_check_redrawn()
			_press(_region_button(_regions[3]))
			_press(_region_button(_regions[1]))
		16:
			_press(_with_meta("fund_id"))
		18:
			_check_stopped(_regions[1])
			_finish()
	return false


## The opened region's first line: its worst figure against the nation, the sim's.
func _check_problem(region) -> void:
	var ns = _main._state.player()
	var list: Array = _main._loader.regions.get(ns.id, [])
	var access: Dictionary = Regions.accessibility_for(ns, list, _main._state.region_graph)
	var sites: Dictionary = _main._state.project_sited_pct.get(ns.id, {})
	var p: Dictionary = Regions.problem(ns, list, region.id, access, sites, Migration.region_share(ns, region.id))
	var label = _with_meta("problem")
	if label == null:
		_fail("opened %s: no problem line" % region.id)
		return
	var want := Num.f(float(p["value"]), 1) if String(p["kind"]) == "unemployment" else Num.f(100.0 * float(p["value"]), 0)
	if not (label as Label).text.contains(want):
		_fail("opened %s: the problem line reads '%s', the sim's figure is %s (%s)" % [region.id, label.text, want, p["kind"]])
	# First: nothing of the opened box stands above it.
	var box: Node = label.get_parent()
	if box.get_child(0) != label:
		_fail("opened %s: the problem line is not the opened region's first line" % region.id)


## The fund's strip reads RegionFunds.estimate() at the sums the controls hold.
func _check_strip(region) -> void:
	var ns = _main._state.player()
	var strip = null
	for node in _panel.find_children("*", "", true, false):
		if node.get_script() == EffectsStrip and not node.has_meta("priority") and (node as Control).is_visible_in_tree():
			strip = node
	if strip == null:
		_fail("opened %s: no fund strip on screen" % region.id)
		return
	var share := float(_panel._fund_share)
	var years := int(_panel._fund_years)
	var est: Dictionary = RegionFunds.estimate(_main._state, ns, _main._loader, region.id, share, years)
	var eur := float(est.get("eur_bn_per_year", 0.0))
	if eur <= 0.0 or absf(float(strip.money_bn) + eur) > 0.0001:
		_fail("fund strip: money %s bn, the fund costs %s bn a year" % [strip.money_bn, eur])
	var text := _text_under(strip)
	if not text.contains(Num.f(float(est["unemployment_after"]), 1)):
		_fail("fund strip: '%s' does not carry the unemployment with the fund (%s)" % [text, Num.f(float(est["unemployment_after"]), 1)])
	# Each sum on its own line, its value with its unit (QA's TAKE 1).
	var eur_slider = _with_meta("fund_share")
	var years_slider = _with_meta("fund_years")
	if eur_slider == null or years_slider == null or eur_slider.get_parent() == years_slider.get_parent():
		_fail("fund: the two sums share one line (or one is missing)")
	else:
		var eur_text: String = (eur_slider.get_meta("value_label") as Label).text
		var years_text: String = (years_slider.get_meta("value_label") as Label).text
		# #316's ask: the money beside the slider too, the sim's estimate at its level.
		if eur_text != Strings.t("%s %% of the region's output: %s a year") % [Num.f(share, 1), Strings.t("%s bn") % Num.f(eur, EffectsStrip.MONEY_PLACES)]:
			_fail("fund: the yearly sum reads '%s', not the share and the sim's %s bn" % [eur_text, Num.f(eur, 2)])
		if years_text != Strings.tn("%d year", "%d years", years) % years:
			_fail("fund: the years read '%s'" % years_text)
	var go = _with_meta("go")
	if go == null or go.disabled:
		_fail("fund: no live Go for a region with no fund under the cap")


func _check_started(region) -> void:
	var funds := RegionFunds.open_funds(_main._state.player())
	if funds.size() != 1 or String(funds[0]["region_id"]) != String(region.id):
		_fail("Go pressed: %d funds open, expected one on %s" % [funds.size(), region.id])
		return
	_check_since(funds[0])
	var stop = _with_meta("fund_id")
	if stop == null:
		_fail("Go pressed: the running fund shows no Stop on its region")
		return
	# What Stop costs, beside it: every bloc the fund pleased is named (QA's TAKE 2).
	var who: Label = stop.get_meta("who_label") if stop.has_meta("who_label") else null
	for bloc in funds[0]["bloc_offset"]:
		if float(funds[0]["bloc_offset"][bloc]) > 0.0:
			if who == null or not who.is_visible_in_tree() or not who.text.contains(Labels.bloc(String(bloc))):
				_fail("Stop: the line beside it does not name %s, a bloc stopping angers (%s)" % [bloc, who.text if who != null else "<none>"])


## The snapshot: the row says the figure it began at against the figure now, both the
## sim's; a row from before the key says nothing rather than a wrong change.
func _check_since(_copy: Dictionary) -> void:
	var ns = _main._state.player()
	# The register's own row: open_funds() hands out copies, and this stage must write.
	var row: Dictionary = ns.region_funds[0]
	var at := float(row.get("unemployment_at_start", -1.0))
	if at < 0.0:
		_fail("snapshot: the opened row has no start figure")
		return
	var said = _live_since()
	var want: String = Strings.t("Unemployment here since it began: %s -> %s %%.") % [Num.f(at, 1),
		Num.f(RegionFunds.unemployment_here(_main._state, ns, String(row["region_id"])), 1)]
	if said == null or (said as Label).text != want:
		_fail("snapshot: the row reads '%s', not '%s'" % [said.text if said != null else "<none>", want])
	row["unemployment_at_start"] = 40.0
	_panel._refresh()
	said = _live_since()
	if said == null or not (said as Label).text.contains(Num.f(40.0, 1)):
		_fail("snapshot: the row does not read the row's own figure (%s)" % [said.text if said != null else "<none>"])
	row.erase("unemployment_at_start")
	_panel._refresh()
	if _live_since() != null:
		_fail("snapshot: a row with no start figure still says a change ('%s')" % _live_since().text)
	row["unemployment_at_start"] = at


## The line on the panel as drawn now: a rebuild leaves the old box queued for a frame.
func _live_since():
	for node in _panel.find_children("*", "Label", true, false):
		var gone := false
		var up: Node = node
		while up != null and not gone:
			gone = up.is_queued_for_deletion()
			up = up.get_parent()
		if node.has_meta("fund_since") and not gone:
			return node
	return null


## The Budget's table: the fund's bill on its own line once the month has booked it.
func _check_budget_row() -> void:
	RegionFunds.tick_month(_main._state)
	var budget = _main._budget_panel
	budget.mark_dirty()
	budget._refresh()
	var cells: Array = budget._figures.get("region_funds", [])
	if cells.is_empty() or String(cells[0]) == "—":
		_fail("budget: no regional fund line with a fund running (%s)" % [cells])


## Two more funds elsewhere: three are open, the cap.
func _fill_to_the_cap() -> void:
	var ns = _main._state.player()
	var low: float = float(RegionFunds.limits(_main._loader)["share_pct"][0])
	for i in [1, 2]:
		var r: Dictionary = RegionFunds.start(_main._state, ns, _main._loader, _regions[i].id, low, 1)
		if not bool(r.get("ok", false)):
			_fail("premise: a fund on %s refused: %s" % [_regions[i].id, r])
	_panel.mark_dirty()


func _check_cap() -> void:
	var go = _with_meta("go")
	if go == null:
		_fail("at the cap: the fund's Go is gone rather than greyed")
		return
	if not go.disabled:
		_fail("at the cap: the fund's Go is live with three funds open")
	var line = _with_meta("refusal")
	var want := Strings.t("The most development funds that can run at once are already running.")
	if line == null or not (line as Control).is_visible_in_tree() or (line as Label).text != want:
		_fail("at the cap: no visible line says why (%s)" % [line.text if line != null else "<none>"])


## A drag on the yearly sum redraws the strip at the new sum (no rebuild).
func _move_a_sum() -> void:
	# Below the cap again, so the strip is drawn: the opened region's own fund aside,
	# stop one of the others.
	var ns = _main._state.player()
	for row in RegionFunds.open_funds(ns):
		if String(row["region_id"]) == String(_regions[2].id):
			RegionFunds.stop(_main._state, ns, String(row["id"]))
	_panel.mark_dirty()


func _check_redrawn() -> void:
	var slider = _with_meta("fund_share")
	if slider == null:
		_fail("redraw: no yearly-sum control on the opened region")
		return
	var top: float = (slider as HSlider).max_value
	(slider as HSlider).value = top
	var strip = null
	for node in _panel.find_children("*", "", true, false):
		if node.get_script() == EffectsStrip and not node.has_meta("priority") and (node as Control).is_visible_in_tree():
			strip = node
	var est: Dictionary = RegionFunds.estimate(_main._state, _main._state.player(), _main._loader, _panel._open_region, top, int(_panel._fund_years))
	var eur := float(est.get("eur_bn_per_year", 0.0))
	if strip == null or eur <= 0.0 or absf(float(strip.money_bn) + eur) > 0.0001:
		_fail("redraw: the strip did not follow the level to %s %%, %s bn (%s)" % [top, eur, strip.money_bn if strip != null else "<none>"])
	# The track is drawn (the frame on #316: the engine default left a lone dot on
	# graphite): a bar with height, visibly off the panel behind it.
	var track: StyleBox = (slider as HSlider).get_theme_stylebox("slider")
	var hull: Color = UiTheme.HULL
	if not (track is StyleBoxFlat) or track.get_minimum_size().y < 4.0 			or absf((track as StyleBoxFlat).bg_color.get_luminance() - hull.get_luminance()) < 0.05:
		_fail("fund: the slider's track does not show on the panel (%s)" % track)
	# The money beside the slider follows the drag too (#316's ask), at the new level.
	var beside: String = ((slider as HSlider).get_meta("value_label") as Label).text
	var money := Strings.t("%s bn") % Num.f(eur, EffectsStrip.MONEY_PLACES)
	if not beside.contains(money):
		_fail("redraw: the money beside the slider did not follow the level to %s %%: '%s', the sim's %s" % [top, beside, money])


## Stop on a running fund closes it, and the row said whom it angers before.
func _check_stopped(region) -> void:
	for row in RegionFunds.open_funds(_main._state.player()):
		if String(row["region_id"]) == String(region.id):
			_fail("Stop pressed: the fund on %s still runs" % region.id)


# -- helpers --

func _region_button(region):
	for b in _panel.find_children("*", "Button", true, false):
		if b.toggle_mode and (b as Button).text == String(region.region_name) and b.is_visible_in_tree():
			return b
	return null


func _with_meta(key: String):
	for node in _panel.find_children("*", "", true, false):
		if node.has_meta(key) and (node as Control).is_visible_in_tree():
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
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_region_fund: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
