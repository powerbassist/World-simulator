extends SceneTree

## Headless test: godot --headless --script res://tests/test_sector_warning_view.gd
## Non-zero exit on any failure.
##
## V5.3 a + b, band B7, #288's reads on the Budget's tile: a warned sector carries a mark
## and its reason (the sim's), its trend draws, its unit says it is adjusted for need, and
## the tile offers the answer that exists: one raise for the line, priced by the Budget's
## own books (B1: what Commit books), a move only while a sector can pay. A crossing ranks
## in the briefing and, on a month with none, folds into one note.
##
## Driven through the real controls a frame apart (AGENTS.md: a Control built but not shown
## fails silently).

const Sectors = preload("res://src/sim/sectors.gd")
const SectorWarnings = preload("res://src/sim/sector_warnings.gd")
const SectorWarningView = preload("res://src/ui/sector_warning_view.gd")
const BudgetSectors = preload("res://src/ui/budget_sectors.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const ChartLine = preload("res://src/ui/chart_line.gd")
const Priorities = preload("res://src/ui/priorities.gd")
const PK = preload("res://src/ui/priorities_constants.gd")
const DK = preload("res://src/sim/domains_constants.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const Budget = preload("res://src/sim/budget.gd")
const PriorityWords = preload("res://src/ui/priority_words.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

const LINE := "health"

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0
var _price := 0.0
var _target := 0.0
var _gdp_base := 0.0
var _most := 0.0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_panel = _main._budget_panel
			_main._windows.open("budget")
			_check_quiet_unit()
			_stage_all_warned()
			_press(_with_meta("line", LINE))
		4:
			_check_all_warned()
			_press(_with_meta("raise_line", LINE))
		6:
			_check_drafted()
			_check_span_spent()
			_panel._on_revert(false)
		8:
			_drag_the_lever()
		10:
			_check_price_on_a_draft()
			_panel._on_revert(false)
			_stage_uneven_needs()
		12:
			_check_uncapped()
			_press(_with_meta("raise_line", LINE))
		14:
			_check_marks(false, "a drafted restore")
			_check_largest_restored()
			_panel._on_revert(false)
		16:
			_check_marks(true, "Revert")
			_stage_no_payer()
		18:
			_check_no_payer()
			_stage_one_cut()
		20:
			_check_one_cut()
			_press(_with_meta("line", LINE))
		22:
			# Off the donor: only opening the tile may aim it. _check_one_cut already aimed.
			_panel._move_from = "hospitals"
			_panel._move_to = "primary_care"
			_press(_with_meta("line", LINE))
		24:
			_check_toggle_aims()
			_check_floor_cannot_pay()
			_check_arrival()
			_check_note_wired()
			_finish()
	return false


## Before any drift: the unit says it is adjusted for need, and nothing is marked.
func _check_quiet_unit() -> void:
	var s: Dictionary = Sectors.sectors_of(_main._loader, LINE)[0]
	var ns = _main._state.player()
	if SectorWarningView.warned(ns, _main._loader, LINE).size() != 0:
		_fail("premise: a sector warns on day one")
	if BudgetSectors.unit_text(s) != Strings.t("%s, need-adjusted") % Strings.row("domains", String(s["id"]), "quantity.unit", String(s["quantity"]["unit"])):
		_fail("unit: '%s' does not say it is adjusted for need" % BudgetSectors.unit_text(s))


## Money per head well below the drift's base: every sector of every line warns, by income.
func _stage_all_warned() -> void:
	var ns = _main._state.player()
	_gdp_base = float(ns.gdp_eur_bn) / float(ns.population)
	ns.sector_drift["base_gdp_per_head"] = _gdp_base * 2.0
	# One sample on a second sector: a trend needs two.
	ns.sector_drift["history"] = {"hospitals": [5.3, 5.2, 5.1, 5.0], "prevention": [5.0]}
	_panel.mark_dirty()


func _check_all_warned() -> void:
	var ns = _main._state.player()
	var why := SectorWarningView.warned(ns, _main._loader, LINE)
	if why.size() != Sectors.sectors_of(_main._loader, LINE).size():
		_fail("premise: %d of the line's sectors warn" % why.size())
	var said = _with_meta("sector_warning", SectorWarnings.REASON_INCOME)
	if said == null or not (said as Label).text.contains(Strings.t(SectorWarnings.REASON_INCOME)):
		_fail("mark: no line says the sim's reason (%s)" % [said.text if said != null else "<none>"])
	elif not (said as Label).text.contains(Strings.row("domains", "hospitals", "name", "Hospitals")):
		_fail("mark: the reason does not name the sector ('%s')" % said.text)
	else:
		var tone: Variant = said.get_theme_color("font_color") if said.has_theme_color_override("font_color") else null
		if tone != ResultTone.TINT[ResultTone.RISKY]:
			_fail("mark: the reason wears %s" % tone)
	var toggle = _with_meta("line", LINE)
	if toggle == null or not (toggle as Button).text.contains("(!)"):
		_fail("mark: the line's toggle does not say a sector is slipping (%s)" % [toggle.text if toggle != null else "<none>"])
	var name_label := _sector_label("hospitals")
	if name_label == null or not name_label.text.contains("(!)"):
		_fail("mark: the warned row is not marked (%s)" % [name_label.text if name_label != null else "<none>"])
	var spark := 0
	for node in _panel._sector_box.find_children("*", "", true, false):
		if node.get_script() == ChartLine:
			spark += 1
	if spark != 1:
		_fail("trend: %d sparklines, one sector has a history" % spark)
	# Each reason once, whatever the number of sectors it names.
	var lines := 0
	for node in _panel._sector_box.find_children("*", "Label", true, false):
		if String(node.get_meta("sector_warning", "")) == SectorWarnings.REASON_INCOME and not _gone(node):
			lines += 1
	if lines != 1:
		_fail("mark: the reason is said %d times" % lines)
	# The parent's ruling: every sector warned, the sim still accepts a move: move AND raise.
	var move = _with_meta("move", "move")
	if move == null or move.disabled:
		_fail("verb: every sector warned, and the move the sim accepts is not live")
	if _text_under(_panel._sector_box).contains(Strings.t("No sector of this line can pay.")):
		_fail("verb: 'cannot pay' said where the sim accepts a move")
	# The donor is warned too, and its strip says so: that is the tradeoff.
	var from := SectorWarningView.name_of(_main._loader, LINE, String(_panel._move_from))
	var slipping: String = Strings.t("Slipping too: %s.") % from
	var strips := []
	for node in _panel._sector_box.find_children("*", "", true, false):
		if node.has_meta("sectors") and not _gone(node):
			strips.append(_text_under(node))
	if strips.size() != 1 or not String(strips[0]).contains(slipping):
		_fail("verb: the move's strip does not say its donor is slipping (%s): %s" % [slipping, strips])
	var go = _with_meta("raise_line", LINE)
	if go == null or go.disabled:
		_fail("verb: no live raise")
		return
	var strip = _raise_strip()
	if strip == null:
		_fail("verb: no strip prices the raise")
		return
	_price = float(strip.money_bn)
	if _price >= 0.0:
		_fail("verb: the raise reads as no cost (%s)" % _price)
	if not (strip.money_label as Label).text.contains(EffectsStrip.money_text(_price)):
		_fail("verb: the strip's money reads '%s'" % strip.money_label.text)
	var most := 0.0
	for id in why:
		most = maxf(most, SectorWarnings.restore_pct_gdp(ns, _main._loader, LINE, String(id)))
	var drafted := float(ns.spending_pct_gdp[LINE])
	_target = minf(drafted + most, _panel.lever_span(LINE).y)
	# This stage is capped by the span: the words must not claim the figures come back.
	var capped: String = Strings.t("Up %s points of GDP, part of the way; the rest takes a second Commit.") % Num.f(_target - drafted, 1)
	if not _text_under(strip).contains(capped):
		_fail("verb: the capped raise does not say so ('%s')" % _text_under(strip))


## Drafted, not booked: the lever moved, the Budget's own figure is the strip's price (B1).
func _check_drafted() -> void:
	var ns = _main._state.player()
	if absf(float(_panel._pending["spending_pct_gdp"][LINE]) - _target) > 0.0001 or absf(float(_panel._sliders[LINE].value) - _target) > 0.2:
		_fail("raise: the lever reads %s, the raise is %s" % [_panel._pending["spending_pct_gdp"][LINE], _target])
	if absf(float(ns.spending_pct_gdp[LINE]) - _target) < 0.0001:
		_fail("raise: booked at the press, not drafted")
	if absf(float(_panel._effects.get(LINE, 0.0)) - _price) > 0.005:
		_fail("raise: priced %s, the lever's own figure is %s" % [_price, _panel._effects.get(LINE, 0.0)])


## The capped raise drafted, the sectors still warned: the tile says why no verb is left.
func _check_span_spent() -> void:
	if _with_meta("raise_line", LINE) != null:
		_fail("span: a raise is offered past the span")
	if not _text_under(_panel._sector_box).contains(Strings.t("This line can rise no further in this Commit.")):
		_fail("span: nothing says the line can rise no further ('%s')" % _text_under(_panel._sector_box))


## A lever dragged by hand, a point up, the sectors still warned.
func _drag_the_lever() -> void:
	var live := float(_main._state.player().spending_pct_gdp[LINE])
	_panel._on_lever_changed(live + 1.0, LINE)


## The strip prices what the raise adds to the draft, in step with the points it says.
func _check_price_on_a_draft() -> void:
	var state = _main._state
	var ns = state.player()
	var strip = _raise_strip()
	if strip == null:
		_fail("draft: no raise left on a dragged lever")
		return
	var live := float(ns.spending_pct_gdp[LINE])
	var alone := func(value: float) -> Dictionary:
		var spending: Dictionary = ns.spending_pct_gdp.duplicate()
		spending[LINE] = value
		return {"spending_pct_gdp": spending}
	var want := EffectsStrip.balance_bn(Budget.preview(state, alone.call(live + 1.0)), Budget.preview(state, alone.call(_target)))
	if absf(float(strip.money_bn) - want) > 0.05:
		_fail("draft: the raise reads %s on a dragged lever, it adds %s" % [strip.money_bn, want])
	if not _text_under(strip).contains(Num.f(_target - (live + 1.0), 1)):
		_fail("draft: the points do not count from the draft ('%s')" % _text_under(strip))


## A smaller fall with one sector's share moved away: a restore inside the span, and not
## the same for each sector warned (they share a need rate, so a share is what parts them).
func _stage_uneven_needs() -> void:
	var ns = _main._state.player()
	ns.sector_drift["base_gdp_per_head"] = _gdp_base * 1.1
	Sectors.move_share(ns, _main._loader, LINE, "hospitals", "primary_care", 0.05)
	_panel.mark_dirty()


func _check_uncapped() -> void:
	var ns = _main._state.player()
	var why := SectorWarningView.warned(ns, _main._loader, LINE)
	_most = 0.0
	var least := INF
	for id in why:
		var restore := SectorWarnings.restore_pct_gdp(ns, _main._loader, LINE, String(id))
		_most = maxf(_most, restore)
		least = minf(least, restore)
	if why.size() < 2 or _most - least < 0.01:
		_fail("premise: the warned sectors' restores do not differ (%d warned, %s to %s)" % [why.size(), least, _most])
	var drafted := float(ns.spending_pct_gdp[LINE])
	if drafted + _most >= _panel.lever_span(LINE).y:
		_fail("premise: the restore is capped by the span")
	var said: String = Strings.t("Up %s points of GDP restores the figures; its other sectors gain too.") % Num.f(_most, 1)
	if not _text_under(_raise_strip()).contains(said):
		_fail("verb: an uncapped raise does not say it restores ('%s')" % _text_under(_raise_strip()))


## The largest restore, not the smallest: every warned sector comes back.
func _check_largest_restored() -> void:
	var ns = _main._state.player()
	var want := float(ns.spending_pct_gdp[LINE]) + _most
	if absf(float(_panel._pending["spending_pct_gdp"][LINE]) - want) > 0.0001:
		_fail("raise: the lever reads %s, the largest restore is %s" % [_panel._pending["spending_pct_gdp"][LINE], want])


## The marks follow the draft, on the toggle and on the row, and come back with Revert.
func _check_marks(marked: bool, when: String) -> void:
	var ns = _main._state.player()
	if SectorWarningView.warned(ns, _main._loader, LINE).is_empty():
		_fail("premise: the live nation is not warned (%s)" % when)
	var toggle = _with_meta("line", LINE)
	if toggle == null or (toggle as Button).text.contains("(!)") != marked:
		_fail("mark: after %s the toggle reads '%s'" % [when, toggle.text if toggle != null else "<none>"])
	var row := _sector_label("hospitals")
	if row == null or row.text.contains("(!)") != marked:
		_fail("mark: after %s the row reads '%s'" % [when, row.text if row != null else "<none>"])


## Every sector at the move's floor: the one place "cannot pay" is true. No verb; the raise
## still stands beside the sentence.
func _stage_no_payer() -> void:
	var ns = _main._state.player()
	ns.sector_drift["base_gdp_per_head"] = _gdp_base * 2.0
	var shares := {}
	for s in Sectors.sectors_of(_main._loader, LINE):
		shares[String(s["id"])] = DK.MIN_SHARE
	ns.sector_shares[LINE] = shares
	_panel.mark_dirty()


func _check_no_payer() -> void:
	var ns = _main._state.player()
	if not _text_under(_panel._sector_box).contains(Strings.t("No sector of this line can pay.")):
		_fail("no payer: nothing says no sector can pay ('%s')" % _text_under(_panel._sector_box))
	if _with_meta("move", "move") != null:
		_fail("no payer: a move is offered that the sim refuses")
	if _with_meta("raise_line", LINE) == null:
		_fail("no payer: the raise is gone")
	ns.sector_shares.erase(LINE)


## Opened by its toggle, the move aims as a Go does: from a sector that can pay.
func _check_toggle_aims() -> void:
	var ns = _main._state.player()
	var why := SectorWarningView.warned(ns, _main._loader, LINE)
	var from := SectorWarningView.donor(ns, _main._loader, LINE, Sectors.sectors_of(_main._loader, LINE), why, "hospitals")
	if _panel._open_line != LINE or _panel._move_to != "hospitals" or _panel._move_from != from:
		_fail("toggle: the move reads %s -> %s on '%s', the warned sector is hospitals and a donor %s" % [_panel._move_from, _panel._move_to, _panel._open_line, from])
	# The donor it picked is not warned, so its strip does not call it slipping.
	if from == "" or _text_under(_panel._sector_box).contains(Strings.t("Slipping too: %s.") % SectorWarningView.name_of(_main._loader, LINE, from)):
		_fail("verb: an un-warned donor is said to be slipping ('%s')" % from)


## A sector at the floor is no donor, un-warned or not (the sim's refusal).
func _check_floor_cannot_pay() -> void:
	var loader = _main._loader
	var copy = _main._state.player().duplicate_state()
	var sectors: Array = Sectors.sectors_of(loader, LINE)
	var why := {}
	for s in sectors:
		if String(s["id"]) != "prevention":
			why[String(s["id"])] = "x"
	if SectorWarningView.donor(copy, loader, LINE, sectors, why, "hospitals") != "prevention":
		_fail("donor: the one un-warned sector above its floor does not pay")
	while bool(Sectors.move_share(copy, loader, LINE, "prevention", "hospitals", 0.01).get("ok", false)):
		pass
	if SectorWarningView.donor(copy, loader, LINE, sectors, why, "hospitals") != "":
		_fail("donor: a sector at its floor pays")


## One sector cut far below the rest: its reason is the cut, others can pay it.
func _stage_one_cut() -> void:
	var ns = _main._state.player()
	ns.sector_drift["base_gdp_per_head"] = _gdp_base
	for i in 8:
		Sectors.move_share(ns, _main._loader, LINE, "hospitals", "prevention", 0.1)
	_panel.mark_dirty()


func _check_one_cut() -> void:
	var ns = _main._state.player()
	var why := SectorWarningView.warned(ns, _main._loader, LINE)
	if why.get("hospitals", "") != SectorWarnings.REASON_CUT:
		_fail("premise: hospitals is not warned for a cut (%s)" % [why])
		return
	if _with_meta("sector_warning", SectorWarnings.REASON_CUT) == null:
		_fail("mark: the cut's reason is not on the tile")
	if _with_meta("move", "move") == null:
		_fail("verb: a sector can pay, and no move is offered")
	if _with_meta("raise_line", LINE) == null:
		_fail("verb: a move does not replace the raise")
	# The Go's aim: the move points at the warned sector, from one that can pay.
	var from := SectorWarningView.donor(ns, _main._loader, LINE, Sectors.sectors_of(_main._loader, LINE), why, "hospitals")
	SectorWarningView.aim(_panel, SectorWarningView.subject_of(LINE, "hospitals"))
	if from == "" or _panel._move_to != "hospitals" or _panel._move_from != from or _panel._open_line != LINE:
		_fail("aim: the move reads %s -> %s on %s, a donor is %s" % [_panel._move_from, _panel._move_to, _panel._open_line, from])


## A crossing this month: it ranks among the priorities, and folds into one note.
func _check_arrival() -> void:
	var state = _main._state
	var ns = state.player()
	var now: int = state.year * 12 + state.month
	var warnings: Dictionary = ns.sector_drift.get_or_add("warnings", {})
	warnings["hospitals"] = {"entered": now, "left": -1}
	warnings["prevention"] = {"entered": now, "left": -1}
	var ranked: Array = Priorities.rank(state, _main._loader, {"held_events": [], "programme_held": false})["lines"]
	var found := {}
	for line in ranked:
		if String(line["kind"]) == "sector":
			found = line
	if found.is_empty():
		_fail("arrival: a crossing is not among the three priorities (%s)" % [ranked.map(func(l): return l["kind"])])
		return
	if int(found["more"]) != 1:
		_fail("arrival: two crossings do not fold into one line (+%s)" % found["more"])
	# The parent's call on #290: 6.0 at a trend's onset, so a crossing outranks a slow trend.
	if absf(float(found["w"]) * float(found["u"]) - 6.0 * 0.7) > 0.0001:
		_fail("arrival: a crossing weighs %s x %s" % [found["w"], found["u"]])
	if not PK.KINDS.has("sector"):
		_fail("arrival: 'sector' is not a kind")
	if not PriorityWords.title(found, state, _main._loader).contains(Strings.row("domains", "hospitals", "name", "Hospitals")) \
			and not PriorityWords.title(found, state, _main._loader).contains(Strings.row("domains", "prevention", "name", "Prevention")):
		_fail("arrival: the line does not name a sector ('%s')" % PriorityWords.title(found, state, _main._loader))
	var cards := SectorWarningView.note_cards(ns, _main._loader, now)
	if cards.size() != 1 or not String(cards[0]["body"]).contains(Strings.row("domains", "hospitals", "name", "Hospitals")) \
			or not String(cards[0]["body"]).contains(Strings.row("domains", "prevention", "name", "Prevention")):
		_fail("arrival: not one note naming the sectors (%s)" % [cards])
	if not SectorWarningView.note_cards(ns, _main._loader, now + 1).is_empty():
		_fail("arrival: the note comes again the month after")


## The crossings are always said: a line on the card, or a note when the card ranked them
## out or is not shown at all.
func _check_note_wired() -> void:
	var state = _main._state
	var ns = state.player()
	var now: int = state.year * 12 + state.month
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	var title := Strings.t("Sectors slipping").to_upper()
	var standing := [Priorities._standing("budget", "balance"), Priorities._standing("unrest", "unrest")]
	var open_with := func(lines: Array) -> void:
		# A new state re-ranks and would throw these lines away (_will_show).
		game["state_id"] = state.get_instance_id()
		game["pending"] = {"month": now, "lines": lines, "memory": {}, "also_due": []}
		BriefingDriver.open(_main, {})
		BriefingDriver.close(_main)
	open_with.call(standing + [Priorities._standing("majority", "seats")])
	if not _shows(_main._hud.inbox, title):
		_fail("note: a crossing the briefing ranked out does not reach the inbox")
	for id in (_main._hud.inbox._notes as Dictionary).keys():
		_main._hud.inbox.dismiss(id)
	open_with.call(standing + [Priorities._cand("sector", "health|hospitals", -1, 6.0, 1.0, now, false)])
	if _shows_live(_main._hud.inbox, title):
		_fail("note: a crossing on the card is said again in the inbox")
	ns.in_government = false
	BriefingDriver.open(_main, {})
	ns.in_government = true
	if not _shows_live(_main._hud.inbox, title):
		_fail("note: a month with no briefing does not put the crossings in the inbox")


func _shows_live(node: Node, text: String) -> bool:
	for label in node.find_children("*", "Label", true, false):
		if (label as Label).text == text and not _gone(label):
			return true
	return false


func _shows(node: Node, text: String) -> bool:
	for label in node.find_children("*", "Label", true, false):
		if (label as Label).text == text:
			return true
	return false


# -- helpers --

func _sector_label(id: String) -> Label:
	for node in _panel._sector_box.find_children("*", "Label", true, false):
		if String(node.get_meta("sector", "")) == id and not _gone(node):
			return node
	return null


func _raise_strip():
	for node in _panel._sector_box.find_children("*", "", true, false):
		if node.has_meta("raise_strip") and not _gone(node):
			return node
	return null


func _with_meta(key: String, value: String):
	for node in _panel.find_children("*", "", true, false):
		if node.has_meta(key) and String(node.get_meta(key)) == value and not _gone(node) and (node as Control).is_visible_in_tree():
			return node
	return null


func _gone(node: Node) -> bool:
	var up: Node = node
	while up != null:
		if up.is_queued_for_deletion():
			return true
		up = up.get_parent()
	return false


func _press(button) -> void:
	if button == null:
		_fail("frame %d: the control to press is not on screen" % _frame)
		return
	(button as Button).pressed.emit()


func _text_under(node: Node) -> String:
	var out := ""
	for label in node.find_children("*", "Label", true, false):
		if not _gone(label):
			out += (label as Label).text + " "
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_sector_warning_view: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
