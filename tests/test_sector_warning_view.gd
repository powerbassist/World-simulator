extends SceneTree

## Headless test: godot --headless --script res://tests/test_sector_warning_view.gd
## Non-zero exit on any failure.
##
## V5.3 a + b, band B7, #288's reads, on the Books' opened spending row since Finances slice 5: a warned sector carries a
## mark and its reason (the sim's), its trend draws, its unit says it is adjusted for need, and the row answers with the
## answer that exists: ONE raise chip for the line (the editor's own slider moved to the figure that restores the worst
## sector, as far as the slider reaches), a move only while a sector can pay, aimed as a Go aims it. A crossing ranks in
## the briefing and, on a month with none, folds into one note.
##
## Driven through the real controls a frame apart (AGENTS.md: a Control built but not shown fails silently).

const Sectors = preload("res://src/sim/sectors.gd")
const SectorWarnings = preload("res://src/sim/sector_warnings.gd")
const SectorWarningView = preload("res://src/ui/sector_warning_view.gd")
const FinanceSectors = preload("res://src/ui/finance_sectors.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
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
var _gdp_base := 0.0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_main._windows.open("finances")
			_panel = _main._windows.frame("finances")._content
			_check_quiet_unit()
			_stage_all_warned()
			_open_row()
		4:
			_check_all_warned()
			_check_the_chip()
			_stage_no_payer()
			_open_row()
		6:
			_check_no_payer()
			_stage_one_cut()
			_open_row()
		8:
			_check_one_cut()
			_check_floor_cannot_pay()
			_check_arrival()
			_check_note_wired()
			_finish()
	return false


## The page rebuilt around the open row: a Go's focus on the slider would keep the rows, so the test lets go of it.
func _open_row() -> void:
	_panel.get_viewport().gui_release_focus()
	_panel.mark_dirty()
	_panel.open_row(FinanceDraft.SPENDING, LINE)
	_panel._process(0.0)


## Before any drift: the unit says it is adjusted for need, and nothing is marked.
func _check_quiet_unit() -> void:
	var s: Dictionary = Sectors.sectors_of(_main._loader, LINE)[0]
	var ns = _main._state.player()
	if SectorWarningView.warned(ns, _main._loader, LINE).size() != 0:
		_fail("premise: a sector warns on day one")
	if FinanceSectors.unit_text(s) != Strings.t("%s, need-adjusted") % Strings.row("domains", String(s["id"]), "quantity.unit", String(s["quantity"]["unit"])):
		_fail("unit: '%s' does not say it is adjusted for need" % FinanceSectors.unit_text(s))


## Money per head well below the drift's base: every sector of every line warns, by income.
func _stage_all_warned() -> void:
	var ns = _main._state.player()
	_gdp_base = float(ns.gdp_eur_bn) / float(ns.population)
	ns.sector_drift["base_gdp_per_head"] = _gdp_base * 2.0
	# One sample on a second sector: a trend needs two.
	ns.sector_drift["history"] = {"hospitals": [5.3, 5.2, 5.1, 5.0], "prevention": [5.0]}


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
	var row_name: Button = null
	for b in _panel._spending_box.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(Strings.t("Health")):
			row_name = b
	if row_name == null or not row_name.text.contains("(!)"):
		_fail("mark: the closed row does not say a sector is slipping (%s)" % [row_name.text if row_name != null else "<none>"])
	var name_label := _sector_label("hospitals")
	if name_label == null or not name_label.text.contains("(!)"):
		_fail("mark: the warned row is not marked (%s)" % [name_label.text if name_label != null else "<none>"])
	var spark := 0
	for node in _panel._spending_box.find_children("*", "", true, false):
		if node.get_script() == ChartLine:
			spark += 1
	if spark != 1:
		_fail("trend: %d sparklines, one sector has a history" % spark)
	# Each reason once, whatever the number of sectors it names.
	var lines := 0
	for node in _panel._spending_box.find_children("*", "Label", true, false):
		if String(node.get_meta("sector_warning", "")) == SectorWarnings.REASON_INCOME and not _gone(node):
			lines += 1
	if lines != 1:
		_fail("mark: the reason is said %d times" % lines)
	# The parent's ruling: every sector warned, the sim still accepts a move: move AND raise.
	var move = _with_meta("move", "move")
	if move == null or move.disabled:
		_fail("verb: every sector warned, and the move the sim accepts is not live")
	if _text_under(_panel._spending_box).contains(Strings.t("No sector of this line can pay.")):
		_fail("verb: 'cannot pay' said where the sim accepts a move")


## The raise is one chip: the largest restore of those warned, as far as the editor's slider reaches, and it writes the draft.
func _check_the_chip() -> void:
	var ns = _main._state.player()
	var why := SectorWarningView.warned(ns, _main._loader, LINE)
	var most := 0.0
	for id in why:
		most = maxf(most, SectorWarnings.restore_pct_gdp(ns, _main._loader, LINE, String(id)))
	var live := float(ns.spending_pct_gdp[LINE])
	var target := minf(live + most, _panel._editor._hi)
	var chip = _with_meta("raise_line", LINE)
	if chip == null or chip.disabled:
		_fail("raise: no live chip")
		return
	var want: String = Strings.t("Raise to %s %%") % Num.f(target, 1)
	if (chip as Button).text != want:
		_fail("raise: the chip reads '%s', the largest restore inside the slider's reach is '%s'" % [(chip as Button).text, want])
	(chip as Button).pressed.emit()
	if absf(_panel._draft.value(FinanceDraft.SPENDING, LINE) - target) > 0.001:
		_fail("raise: the shared draft holds %s, the chip named %s" % [_panel._draft.value(FinanceDraft.SPENDING, LINE), target])
	_panel._draft.revert()


## Every sector at the move's floor: the one place "cannot pay" is true. No verb; the raise
## still stands beside the sentence.
func _stage_no_payer() -> void:
	var ns = _main._state.player()
	ns.sector_drift["base_gdp_per_head"] = _gdp_base * 2.0
	var shares := {}
	for s in Sectors.sectors_of(_main._loader, LINE):
		shares[String(s["id"])] = DK.MIN_SHARE
	ns.sector_shares[LINE] = shares


func _check_no_payer() -> void:
	var ns = _main._state.player()
	if not _text_under(_panel._spending_box).contains(Strings.t("No sector of this line can pay.")):
		_fail("no payer: nothing says no sector can pay ('%s')" % _text_under(_panel._spending_box))
	if _with_meta("move", "move") != null:
		_fail("no payer: a move is offered that the sim refuses")
	if _with_meta("raise_line", LINE) == null:
		_fail("no payer: the raise is gone")
	ns.sector_shares.erase(LINE)


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


func _check_one_cut() -> void:
	var ns = _main._state.player()
	var why := SectorWarningView.warned(ns, _main._loader, LINE)
	if why.get("hospitals", "") != SectorWarnings.REASON_CUT:
		_fail("premise: hospitals is not warned for a cut (%s)" % [why])
		return
	if _with_meta("sector_warning", SectorWarnings.REASON_CUT) == null:
		_fail("mark: the cut's reason is not on the row")
	if _with_meta("move", "move") == null:
		_fail("verb: a sector can pay, and no move is offered")
	if _with_meta("raise_line", LINE) == null:
		_fail("verb: a move does not replace the raise")
	# The Go's aim: the move points at the warned sector, from one that can pay, and the row opens.
	var from := SectorWarningView.donor(ns, _main._loader, LINE, Sectors.sectors_of(_main._loader, LINE), why, "hospitals")
	_panel._draft.pick = {}
	FinanceSectors.aim(_panel, SectorWarningView.subject_of(LINE, "hospitals"))
	var pick: Dictionary = _panel._draft.pick
	if from == "" or pick.get("to", "") != "hospitals" or pick.get("from", "") != from or _panel._open_id != "spending_pct_gdp:" + LINE:
		_fail("aim: the move reads %s -> %s on '%s', a donor is %s" % [pick.get("from", ""), pick.get("to", ""), _panel._open_id, from])


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
	for node in _panel._spending_box.find_children("*", "Label", true, false):
		if node.has_meta("sector") and String(node.get_meta("sector")) == id and not _gone(node):
			return node
	return null


func _with_meta(key: String, value: String):
	for node in _panel._spending_box.find_children("*", "", true, false):
		if node.has_meta(key) and str(node.get_meta(key)) == value and (node as Control).is_visible_in_tree():
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
