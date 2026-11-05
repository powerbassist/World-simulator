extends SceneTree

## Headless test: godot --headless --script res://tests/test_region_priority.gd
## Non-zero exit on any failure.
##
## V5.3 a, docs/design/v5.3-ab.md 3.3 (a) 1, the priority half (#267): the opened
## region carries a sector priority as a verb -- pick a sector, read its strip (the
## sector's quantity here and elsewhere, the region's unemployment now and with the
## priority, the term and its renewal, no money), press "Put first here". Every rule
## the sim keeps (at most two per region, one region per sector, a term renewable
## once, then a rest) is read BEFORE the press: a refused pick greys the verb and the
## sim's line says why, and a resting sector says when it is free again. Never a dead
## click: the verb is there, greyed, with its reason.
##
## Driven through the real controls a frame apart (AGENTS.md: a Control built but
## not shown fails silently).

const Regions = preload("res://src/sim/regions.gd")
const Sectors = preload("res://src/sim/sectors.gd")
const DK = preload("res://src/sim/domains_constants.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const BudgetSectors = preload("res://src/ui/budget_sectors.gd")
const DateText = preload("res://src/ui/date_text.gd")
const RegionPriority = preload("res://src/ui/region_priority.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0
var _regions: Array = []
## Three [line, sector_id] picks, distinct sectors.
var _picks: Array = []
## [region, [line, sector]] whose strip moves both unemployment pairs as printed.
var _moving: Array = []


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
			for line in _main._loader.domains:
				for s in Sectors.sectors_of(_main._loader, String(line)):
					if _picks.size() < 3:
						_picks.append([String(line), String(s["id"])])
			if _regions.size() < 2 or _picks.size() < 3:
				_fail("premise: France needs two regions with output and three sectors (%d, %d)" % [_regions.size(), _picks.size()])
				_finish()
				return false
			for p in _picks:
				var est: Dictionary = Sectors.priority_estimate(_main._state, ns, _main._loader, p[0], p[1], _regions[0].id)
				if not bool(est.get("ok", false)):
					_fail("premise: a priority for %s on %s is refused: %s" % [p[1], _regions[0].id, est])
			_main._windows.open("region")
		4:
			_press(_region_button(_regions[0]))
		6:
			_pick(_picks[0])
		7:
			_check_strip(_regions[0], _picks[0])
			_press(_with_meta("priority_go"))
		9:
			_check_held(_regions[0], _picks[0], DK.PRIORITY_MONTHS)
			# A second priority on the same region, through the sim: the region is then at
			# its cap of two.
			var r: Dictionary = Sectors.set_priority(_main._state, _main._state.player(), _main._loader,
				_picks[1][0], _picks[1][1], _regions[0].id)
			if not bool(r.get("ok", false)):
				_fail("premise: a second priority on %s refused: %s" % [_regions[0].id, r])
			_panel.mark_dirty()
		11:
			_pick(_picks[2])
		12:
			_check_refused(Strings.t("This region already holds as many priorities as it can."), false)
			# QA's TAKE 1 (c) on #284: a non-first pick survives a rebuild.
			_panel.mark_dirty()
		14:
			var option = _with_meta("priority_sector")
			var kept := "%s|%s" % [_picks[2][0], _picks[2][1]]
			if option == null or String(option.get_item_metadata((option as OptionButton).selected)) != kept:
				_fail("rebuild: the picker no longer holds %s" % kept)
			_check_refused(Strings.t("This region already holds as many priorities as it can."), false)
			_pick(_picks[0])
		15:
			# The region's own priority: the verb renews it, once.
			var go = _with_meta("priority_go")
			if go == null or go.disabled or (go as Button).text != Strings.t("Renew here"):
				_fail("renew: the held sector's verb is not a live 'Renew here' (%s)" % [_describe(go)])
			_press(go)
		17:
			var row: Dictionary = _main._state.player().sector_priorities.get(_picks[0][1], {})
			if int(row.get("renewals", 0)) != 1:
				_fail("Renew pressed: the priority's renewals are %s, expected 1" % row.get("renewals", "<none>"))
			# QA's TAKE 1 (a): the held row says it can no longer be renewed.
			var end = _clear_button(_picks[0][1])
			var name := RegionPriority._name(_main._loader, _picks[0][0], _picks[0][1])
			var months := int(row.get("months_left", 0))
			var said := Strings.tn("%s first here, %d month left, not renewable.", "%s first here, %d months left, not renewable.", months) % [name, months]
			if end == null or not (end.get_meta("held_label") as Label).text.contains(said):
				_fail("renewed: the held row does not say '%s' (%s)" % [said, (end.get_meta("held_label") as Label).text if end != null else "<none>"])
			_pick(_picks[0])
		18:
			_check_refused(Strings.t("This priority was renewed once already: it ends with this term."), false)
			_press(_clear_button(_picks[0][1]))
		20:
			if Sectors.priority_of(_main._state.player(), _picks[0][1]) != "":
				_fail("End pressed: %s still has its priority" % _picks[0][1])
			_pick(_picks[0])
		21:
			_check_refused(Strings.t("This region held this priority lately and must wait before taking it again."), true)
			# Another region takes a sector the first one holds: the strip says from whom.
			_press(_region_button(_regions[1]))
		23:
			_pick(_picks[1])
		24:
			_check_strip(_regions[1], _picks[1])
			var text := _text_under(_strip())
			if not text.contains(String(_regions[0].region_name)):
				_fail("replace: the strip for a sector %s holds does not name it ('%s')" % [_regions[0].region_name, text])
			# The world moves under a drawn verb (a month ends, the panel not yet rebuilt):
			# the region reaches its cap through the sim, then the press. It must say why
			# rather than do nothing.
			var ns = _main._state.player()
			for p in [_picks[0], _picks[2]]:
				Sectors.set_priority(_main._state, ns, _main._loader, p[0], p[1], _regions[1].id)
			_press(_with_meta("priority_go"))
			# Read in the same frame: a rebuild would grey it anyway, later.
			if Sectors.priority_of(_main._state.player(), _picks[1][1]) != String(_regions[0].id):
				_fail("stale press: %s moved off %s although the region was at its cap" % [_picks[1][1], _regions[0].id])
			_check_refused(Strings.t("This region already holds as many priorities as it can."), false)
			# QA's TAKE 1 (b): a pick whose unemployment figures differ as printed, so an
			# order or a swap in the sentence shows.
			_find_a_moving_pick()
			if _moving.is_empty():
				_finish()
				return false
			_press(_region_button(_moving[0]))
		26:
			_pick(_moving[1])
		27:
			_check_unemployment(_moving[0], _moving[1])
			_finish()
	return false


## The region and pick whose estimate moves both unemployment pairs the most, as
## printed: [region, [line, sector]].
func _find_a_moving_pick() -> void:
	var ns = _main._state.player()
	var best := 0.0
	for region in _regions:
		for line in _main._loader.domains:
			for s in Sectors.sectors_of(_main._loader, String(line)):
				var est: Dictionary = Sectors.priority_estimate(_main._state, ns, _main._loader, String(line), String(s["id"]), region.id)
				if not bool(est.get("ok", false)):
					continue
				var here := float(est["unemployment_now"]) - float(est["unemployment_after"])
				var there := float(est["others_unemployment_after"]) - float(est["others_unemployment_now"])
				if Num.f(float(est["unemployment_now"]), 1) == Num.f(float(est["unemployment_after"]), 1) 						or Num.f(float(est["others_unemployment_now"]), 1) == Num.f(float(est["others_unemployment_after"]), 1):
					continue
				if here + there > best:
					best = here + there
					_moving = [region, [String(line), String(s["id"])]]
	if _moving.is_empty():
		_fail("premise: no region and sector moves both unemployment pairs as printed")


## The unemployment sentence whole and in order: here now, here with the priority,
## the other regions now, then after (QA's TAKE 1 (b): a swap must not pass).
func _check_unemployment(region, pick: Array) -> void:
	var est: Dictionary = Sectors.priority_estimate(_main._state, _main._state.player(), _main._loader, pick[0], pick[1], region.id)
	var want: String = Strings.t("Unemployment here: %s %% now, %s %% with the priority; other regions %s %% -> %s %%.") % [
		Num.f(float(est["unemployment_now"]), 1), Num.f(float(est["unemployment_after"]), 1),
		Num.f(float(est["others_unemployment_now"]), 1), Num.f(float(est["others_unemployment_after"]), 1)]
	var text := _text_under(_strip())
	if not text.contains(want):
		_fail("priority strip on %s, %s: '%s' does not read '%s'" % [region.id, pick[1], text, want])


## The strip reads Sectors.priority_estimate() for the pick the control holds.
func _check_strip(region, pick: Array) -> void:
	var ns = _main._state.player()
	var est: Dictionary = Sectors.priority_estimate(_main._state, ns, _main._loader, pick[0], pick[1], region.id)
	var strip = _strip()
	if strip == null:
		_fail("opened %s, %s picked: no priority strip on screen" % [region.id, pick[1]])
		return
	if absf(float(strip.money_bn)) > 0.0:
		_fail("priority strip: money %s bn, a priority costs nothing" % strip.money_bn)
	var text := _text_under(strip)
	for want in [BudgetSectors.quantity_text(float(est["region_after"])), BudgetSectors.quantity_text(float(est["others_after"])),
			Num.f(float(est["unemployment_now"]), 1), Num.f(float(est["unemployment_after"]), 1)]:
		if not text.contains(want):
			_fail("priority strip: '%s' does not carry %s (the sim's estimate)" % [text, want])
	var go = _with_meta("priority_go")
	if go == null or go.disabled:
		_fail("priority: no live verb for a pick the sim accepts (%s)" % [_describe(go)])
	var refusal = _with_meta("priority_refusal")
	if refusal != null:
		_fail("priority: a refusal line shows for a pick the sim accepts ('%s')" % refusal.text)


## The pick the sim refuses: the verb is there and greyed, the sim's line under it.
func _check_refused(want: String, resting: bool) -> void:
	var go = _with_meta("priority_go")
	if go == null:
		_fail("refused ('%s'): the verb is gone rather than greyed" % want)
		return
	if not go.disabled:
		_fail("refused ('%s'): the verb is live" % want)
	var line = _with_meta("priority_refusal")
	if line == null or (line as Label).text != want:
		_fail("refused: no visible line says '%s' (%s)" % [want, line.text if line != null else "<none>"])
	if _strip() != null:
		_fail("refused ('%s'): a strip still prices a pick the sim refuses" % want)
	var free_line = _with_meta("priority_free")
	if not resting:
		if free_line != null:
			_fail("refused ('%s'): a 'free again' line shows for a sector that is not resting" % want)
		return
	var ns = _main._state.player()
	var free := int((ns.sector_priority_rest.get(_picks[0][1], {}) as Dictionary).get(_regions[0].id, 0))
	var date := DateText.month_year((free - 1) % 12 + 1, (free - 1) / 12)
	if free_line == null or not (free_line as Label).text.contains(date):
		_fail("resting: no line says when the sector is free again (%s; %s)" % [date, free_line.text if free_line != null else "<none>"])


## The region's held priority: its sector, months left, and an End beside it.
func _check_held(region, pick: Array, months: int) -> void:
	if Sectors.priority_of(_main._state.player(), pick[1]) != String(region.id):
		_fail("verb pressed: %s is not first in %s" % [pick[1], region.id])
		return
	var end = _clear_button(pick[1])
	if end == null:
		_fail("held: the priority on %s shows no End on its region" % pick[1])
		return
	var line: Label = end.get_meta("held_label")
	if line == null or not line.is_visible_in_tree() or not line.text.contains(str(months)):
		_fail("held: the line beside End does not say %d months left (%s)" % [months, line.text if line != null else "<none>"])
		return
	# What End costs, read before the press: the sector's rest in this region.
	var rest := Strings.tn("Ending it rests the sector here %d month.", "Ending it rests the sector here %d months.",
		DK.PRIORITY_REST_MONTHS) % DK.PRIORITY_REST_MONTHS
	if not line.text.contains(rest):
		_fail("held: the line beside End does not say what End costs ('%s' not in '%s')" % [rest, line.text])


# -- helpers --

## Pick a [line, sector] in the verb's control, as the player does.
func _pick(pick: Array) -> void:
	var option = _with_meta("priority_sector")
	if option == null:
		_fail("frame %d: no sector picker on the opened region" % _frame)
		return
	var key := "%s|%s" % [pick[0], pick[1]]
	for i in (option as OptionButton).item_count:
		if String(option.get_item_metadata(i)) == key:
			option.select(i)
			option.item_selected.emit(i)
			return
	_fail("frame %d: the picker has no %s" % [_frame, key])


func _strip():
	for node in _panel.find_children("*", "", true, false):
		if node.get_script() == EffectsStrip and node.has_meta("priority") and (node as Control).is_visible_in_tree():
			return node
	return null


func _clear_button(sector_id: String):
	for node in _panel.find_children("*", "Button", true, false):
		if String(node.get_meta("priority_clear", "")) == sector_id and (node as Control).is_visible_in_tree():
			return node
	return null


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


func _describe(go) -> String:
	if go == null:
		return "<none>"
	return "'%s', disabled %s" % [(go as Button).text, go.disabled]


func _press(button) -> void:
	if button == null:
		_fail("frame %d: the control to press is not on screen" % _frame)
		return
	(button as Button).pressed.emit()


func _text_under(node: Node) -> String:
	var out := ""
	if node == null:
		return out
	for label in node.find_children("*", "Label", true, false):
		out += (label as Label).text + " "
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_region_priority: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
