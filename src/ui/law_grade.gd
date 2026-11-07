extends RefCounted

## The grade picker at the proposal: V5.3 b, docs/design/v5.3-ab.md 2.2 and 4.4, the author's
## "forty lycees and four hundred must not divide alike". A row with a size (Law.magnitude)
## opens with a chip per grade and the picked one's strip: what it books a year, who it moves,
## and what the size does to the division against the bill at its own size. A row with no size
## shows nothing.
##
## THE ROW GOES TO THE SIM, NEVER THE GRADED COPY. Legislature.propose takes the row and the
## scale and grades once, and Division.divide re-grades from the row at the tabled scale. The
## copy here is for reading only. The pick is the list's (LawList.grades), so it holds through
## a refresh and the briefing's round trip, and it is a display pick until Propose.
##
## One row of chips and the picked chip's strip, as a counter's are (counter_chips.gd): the
## player learns one shape. The spec's "side by side" is the strip's third line, the picked
## size's yes against the bill's own, since five strips will not fit the detail's column.

const LK = preload("res://src/sim/legislature_constants.gd")
const LawMagnitude = preload("res://src/core/law_magnitude.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Budget = preload("res://src/sim/budget.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

const CHIP_META := "grade"
const STRIP_META := "grade_strip"
## Where the forecast stands in a catalogue row (law_list.gd _row).
const BAR_COLUMN := 3


## "400 lycees": the row's size at a grade, with no decimal when it has none.
static func size_text(law, scale: float) -> String:
	var value := float(law.magnitude["value"]) * scale
	return "%s %s" % [Num.f(value, 0 if is_equal_approx(value, roundf(value)) else 1), Strings.law_unit(law)]


## A bill as the page reads it at a grade. The tabled bill stays the row: forecast_counts reads
## its grade itself, and a graded copy would read twice graded.
static func read(ns, law, scale: float):
	return law if String(ns.tabled_bill.get("law_id", "")) == String(law.id) else LawMagnitude.scaled(law, scale)


## A chip's press: the pick, the bill's bar in its row, the detail, the focus back on the chip.
static func pick(list, law, step: float) -> void:
	list.grades[String(law.id)] = step
	var row: Node = list._rows.get_child(list._rows.get_child_count() - list._shown.size() + list._shown.find(law))
	var bar: Control = row.get_child(BAR_COLUMN)
	var redrawn: Control = list._forecast_bar(list._ns, list._party_list, law, list.BAR_WIDTH)
	row.remove_child(bar)
	bar.queue_free()
	row.add_child(redrawn)
	row.move_child(redrawn, BAR_COLUMN)
	list.select(String(law.id))
	for chip in list._detail.find_children("*", "Button", true, false):  # i18n: ok a class name
		if chip.has_meta(CHIP_META) and is_equal_approx(float(chip.get_meta(CHIP_META)), step):
			chip.grab_focus()


## The chips and the strip, for an open bill with a size; a tabled one says its size.
static func build(list, box: Control, ns, law) -> void:
	if law.magnitude.is_empty():
		return
	if String(ns.tabled_bill.get("law_id", "")) == String(law.id):
		PanelKit.line(box, Strings.t("Before the Assembly at %s.") % size_text(law, float(ns.tabled_bill.get("scale", 1.0))), PanelKit.Tone.PLAIN)
		return
	var picked: float = list.grade(law)
	var row := PanelKit.buttons(box)
	PanelKit.plain_line(row, Strings.t("Size"), PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_OFF
	var group := ButtonGroup.new()
	for step in LK.GRADE_STEPS:
		var chip := PanelKit.sized(Button.new())
		chip.text = size_text(law, float(step))
		chip.toggle_mode = true
		chip.button_group = group
		chip.button_pressed = is_equal_approx(float(step), picked)
		chip.set_meta(CHIP_META, float(step))
		# Deferred: the pick rebuilds the detail, and a button may not free itself in its own press.
		chip.pressed.connect(pick.bind(list, law, float(step)), CONNECT_DEFERRED)
		row.add_child(chip)
	var strip := EffectsStrip.new()
	strip.set_meta(STRIP_META, true)
	box.add_child(strip)
	var bill = read(ns, law, picked)
	var bn := money_bn(list._panel._state, list._panel._loader, bill)
	strip.show_lines(Strings.t("Balance a year, if it passes"), EffectsStrip.sum_text(bn), bn,
		EffectsStrip.who_text(bill.effects.get("bloc_offset", {})), _against_own_size(list, ns, law, bill, picked))


## What the bill books a year at this grade, on a copy: the applier's own road, so the strip
## cannot read a bill otherwise than the sim then books it. The Tax Code's strip reads a copy
## the same way (EffectsStrip.books). A tax row has no yield without the economy, and this
## reads one: LawMagnitude.net_cost_pct_gdp does not.
static func money_bn(state, loader, bill) -> float:
	var sim = state.duplicate_state()
	var ns = sim.player()
	Budget.recompute(sim, ns)
	var before := {"deficit_pct_gdp": ns.deficit_pct_gdp, "gdp_eur_bn": ns.gdp_eur_bn}
	Legislature.apply_effects(sim, ns, bill.effects, loader)
	Budget.recompute(sim, ns)
	return EffectsStrip.balance_bn(before, {"deficit_pct_gdp": ns.deficit_pct_gdp, "gdp_eur_bn": ns.gdp_eur_bn})


## "At this size 134 for; at 40 lycees 311." Nothing at the bill's own size.
static func _against_own_size(list, ns, law, bill, picked: float) -> String:
	if picked == 1.0:
		return ""
	var panel = list._panel
	var parties: Array = panel._loader.parties.get(ns.id, [])
	var band: float = panel.forecast_band(ns, law.id)
	return Strings.t("%d for at this size, %d at %s.") % [int(panel.forecast_counts(ns, parties, bill, band)["yes"]),
		int(panel.forecast_counts(ns, parties, law, band)["yes"]), size_text(law, 1.0)]
