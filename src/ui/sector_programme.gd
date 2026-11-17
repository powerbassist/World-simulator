extends RefCounted

## A sector's programme on its tab -- V5.3 screen 5 slice 2. The author: "par la loi de
## finances" (a programme is a row of the finance bill, tabled, voted at the month's end);
## the parent's call: a slider that snaps to the programmes in data -- none (the end_*
## action), the 0.55 stop and the 1.0 stop -- with a typed box (H11) that snaps to the
## nearest stop's price. No continuous intensity: that would be a sim change.
##
## Every figure is the sim's: a stop's price a year is FinanceRows.cost_pct_gdp (the bill's
## own reader of a programme row), its blocs the action's offsets, its legality
## Investment.available. The press tables the row through FirmCommands.invest.

const Investment = preload("res://src/sim/investment.gd")
const FinanceRows = preload("res://src/sim/finance_rows.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")


## The sector's stops in order: [{action, intensity}], the end action first (intensity 0).
static func stops(loader, sector: String) -> Array:
	var out: Array = []
	for action in loader.investment_actions:
		var terms: Dictionary = action.effects.get("investment", {})
		if String(terms.get("sector", "")) != sector:
			continue
		var level := float(terms.get("intensity", 0.0)) if String(terms.get("op", "")) == "invest" else 0.0
		out.append({"action": action, "intensity": level})
	out.sort_custom(func(a, b) -> bool: return float(a["intensity"]) < float(b["intensity"]))
	return out


## The stop the sector stands at: the one with its live intensity, 0 for none.
static func current(ns, list: Array, sector: String) -> int:
	var now := Investment.intensity_of(ns, sector)
	for i in list.size():
		if is_equal_approx(float(list[i]["intensity"]), now):
			return i
	return 0


## The stop tabled in the finance bill for this sector, -1 for none.
static func tabled(ns, list: Array, sector: String) -> int:
	var id := String(ns.tabled_bill.get("finance", {}).get(FinanceRows.PROGRAMMES, {}).get(sector, ""))
	for i in list.size():
		if String(list[i]["action"].id) == id:
			return i
	return -1


## EUR bn a year the sector's programme costs at stop `i`: today's cost, plus the bill's
## own price of moving to it.
static func price(state, loader, ns, list: Array, sector: String, i: int) -> float:
	var gdp := float(ns.gdp_eur_bn)
	var to_none := FinanceRows.cost_pct_gdp(state, loader, ns, {FinanceRows.PROGRAMMES: {sector: String(list[0]["action"].id)}})
	var to_stop := FinanceRows.cost_pct_gdp(state, loader, ns, {FinanceRows.PROGRAMMES: {sector: String(list[i]["action"].id)}})
	return (to_stop - to_none) * gdp / 100.0


## The row under `parent`. `panel` keeps the picked stop (`_prog_pick`, -1 for "as it
## stands") and tables through its _on_invest.
static func build(panel, parent: Control, ns, sector: String) -> void:
	var state = panel._state
	var loader = panel._loader
	var list := stops(loader, sector)
	if list.size() < 2:
		return
	var now := current(ns, list, sector)
	var queued := tabled(ns, list, sector)
	var pick: int = panel._prog_pick if panel._prog_pick >= 0 else (queued if queued >= 0 else now)
	var row := PanelKit.buttons(parent)
	var caption := PanelKit.plain_line(row, Strings.t("Programme").to_upper(), PanelKit.Tone.PLAIN)
	caption.theme_type_variation = UiTheme.MICRO
	# A wrapping label in a flow has no width of its own: the slider drew over it.
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = list.size() - 1
	slider.step = 1
	slider.tick_count = list.size()
	slider.ticks_on_borders = true
	slider.custom_minimum_size.x = 200
	slider.set_value_no_signal(pick)
	slider.set_meta("programme", sector)
	# The tab rebuilds on a pick, which freed the slider under a drag (the retro review's item 8): while it is held,
	# the pick is kept and the rebuild waits for the release (Slider.drag_started comes before its value_changed).
	slider.drag_started.connect(func() -> void: panel._dragging = true)
	# A press that moved nothing picks nothing: the stop "as it stands" stays unpicked.
	slider.drag_ended.connect(func(changed: bool) -> void:
		panel._dragging = false
		if changed:
			_pick(panel, int(slider.value)))
	row.add_child(slider)
	var prices: Array = []
	for i in list.size():
		prices.append(price(state, loader, ns, list, sector, i))
	var box := SpinBox.new()
	box.min_value = 0.0
	box.max_value = float(prices.max()) * 2.0 + 1.0
	box.step = 0.01
	box.suffix = Strings.t("bn a year")
	box.custom_minimum_size.x = 170
	box.set_value_no_signal(float(prices[pick]))
	box.set_meta("programme_box", sector)
	# The typed price snaps to the nearest stop: the programmes are the data's, not a dial.
	# An arrow's nudge (one step) moves to the next stop that way, or it would snap back.
	box.value_changed.connect(func(v: float) -> void:
		panel._prog_focus = "box" if box.get_line_edit().has_focus() else ""
		_pick(panel, snap_stop(prices, pick, v, box.step)))
	row.add_child(box)
	var action = list[pick]["action"]
	var name := PanelKit.plain_line(row, _stop_name(list, pick), PanelKit.Tone.PLAIN)
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.set_meta("programme_name", sector)
	# Under a mouse drag the rebuild waits for the release: the price and the name follow live.
	# 4.7.2 emits value_changed on every left press, moved or not, and on a drag that comes
	# back to its start: while held, the readouts follow and the pick waits for the release.
	slider.value_changed.connect(func(v: float) -> void:
		panel._prog_focus = "slider" if slider.has_focus() else ""
		if panel._dragging:
			box.set_value_no_signal(float(prices[int(v)]))
			name.text = _stop_name(list, int(v))
			return
		_pick(panel, int(v)))
	# A keyboard step or an arrow rebuilt the tab and freed the focused control: the new one takes it.
	if panel._prog_focus != "":
		(slider if panel._prog_focus == "slider" else box.get_line_edit()).call_deferred("grab_focus")
		panel._prog_focus = ""
	if queued >= 0:
		PanelKit.plain_line(parent, Strings.t("In the finance bill: %s, voted at the month's end.") % Strings.row_name("investment-actions", list[queued]["action"]))
	if pick == now or pick == queued:
		return
	var strip := EffectsStrip.new()
	parent.add_child(strip)
	var change := -(float(prices[pick]) - float(prices[now]))
	strip.show_lines(Strings.t("Treasury"), Strings.t("%s a year") % EffectsStrip.money_text(change), change,
		EffectsStrip.who_text(action.effects.get("bloc_offset", {})), Strings.t("Voted with the finance bill at the month's end."))
	var go := PanelKit.sized(Button.new())
	go.text = Strings.t("Put it in the finance bill")
	go.set_meta("table_programme", String(action.id))
	# The sim's own refusal (Investment.refusal_reason, #397): "" is open, anything else says why not.
	var refusal := Investment.refusal_reason(state, ns, loader, action)
	go.disabled = refusal != ""
	go.pressed.connect(func() -> void:
		panel._prog_pick = -1
		panel._on_invest(ns, action))
	parent.add_child(go)
	# A disabled verb says why (the retro review's item 9), in the sim's words.
	if go.disabled:
		PanelKit.plain_line(parent, Strings.t(refusal), PanelKit.Tone.DIM).set_meta("programme_refusal", true)  # i18n: row-ok the sim's reason, its English the msgid


## The stop a typed or nudged price picks: the next stop up or down for a nudge of one
## step from the picked stop's price, else the nearest.
static func snap_stop(prices: Array, from: int, v: float, step: float) -> int:
	var moved := v - float(prices[from])
	if absf(moved) <= step * 1.5 and not is_zero_approx(moved):
		return clampi(from + (1 if moved > 0.0 else -1), 0, prices.size() - 1)
	return nearest(prices, v)


static func nearest(prices: Array, v: float) -> int:
	var best := 0
	for i in prices.size():
		if absf(float(prices[i]) - v) < absf(float(prices[best]) - v):
			best = i
	return best


static func _stop_name(list: Array, i: int) -> String:
	return Strings.row_name("investment-actions", list[i]["action"]) if i > 0 else Strings.t("No programme")


static func _pick(panel, i: int) -> void:
	panel._prog_pick = i
	panel._dirty = true  # held off by panel._dragging until the release
