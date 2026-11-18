extends PanelContainer

## The construction register's order form -- V5.3 c' slice 1 (docs/design/v5.3-c-register.md
## section 9, "One surface"; the author's pick, verbatim: "A pour commander + C en suivi").
## The player picks a unit type, how many and where, reads what it does before tabling, and
## puts it in the finance bill. In the order the decision is made:
##   1. the type (a segment per catalogue type the nation's stock offers), how many, where
##      (by need or by population fills the rows; each row is editable by hand);
##   2. every region on one axis of the type's own figure, now and once the units stand
##      (ChartKit.dots, the shared dot plot), a click picks a region and adds it to the rows;
##   3. the strip: the money (the quote's range and a bar a year), who it moves (the picked
##      region before and after, what the others give back), when it opens and its odds;
##   4. the press, greyed with the bill's own reason before it is pressed (A5's grammar).
##
## SCALABLE BY DATA (the author, verbatim: "i want this scalable with other data in the
## future"): no type, nation or region is named here. A type is a row of data/units/, its
## name and its figure's unit are the row's (Strings), its figures are the sim's (Units,
## UnitPrice), and a nation without a stock file for a type is simply not offered it. The
## Union's line (B2, the envelope) joins the strip in slice 2, from the sim's reads.

signal closed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")
const ProposalNote = preload("res://src/ui/proposal_note.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const ChartKit = preload("res://src/ui/chart_kit.gd")
const RegisterMoney = preload("res://src/ui/register_money.gd")
const Units = preload("res://src/sim/units.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")
const UnitBuild = preload("res://src/sim/unit_build.gd")
const UK = preload("res://src/sim/units_constants.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceRows = preload("res://src/sim/finance_rows.gd")

const SIDE_W := 380.0
const COUNT_MAX := 200
## Below the dock's height: the page's plate margins, so the sheet fills it without a scroll.
const FILL_SLACK := 64.0

var _state
var _loader
var _dirty := true
var _body: VBoxContainer
var _close_button: Button
## What the player set in THIS game; setup() (a load) resets it.
var _type := ""
var _count := 1
var _placed := {}
var _region := ""
var _refusal := ""


func _ready() -> void:
	custom_minimum_size = Vector2(900, 0)
	var root := PanelKit.padded(self, 16, 10)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	# The sheet fills the workspace: the money row sits at its foot, never with the map under it.
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_close_button = Button.new()
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_type = ""
	_count = 1
	_placed = {}
	_region = ""
	_refusal = ""
	_dirty = true


func hide_close_button() -> void:
	_close_button.hide()


func mark_dirty() -> void:
	_dirty = true


## Whether the tab is offered to the nation played: a stock file names at least one type
## (window_manager.gd asks; a rule over data, never a nation id).
func is_offered() -> bool:
	return _state != null and _state.player() != null and not _offered().is_empty()


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null or _state.player() == null:
		return
	# A hand in a spin box keeps it: the sheet is rebuilt when it leaves, never under it (the
	# books' guard, finances_panel.gd). A press held down waits too: a box committing on the
	# focus it lost to that press would otherwise free the button before the release.
	var held: Control = get_viewport().gui_get_focus_owner()
	if held != null and is_ancestor_of(held) and (held is LineEdit or held is SpinBox):
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	_dirty = false
	_refresh()


## The doors (a region's sheet, later a sector's tab or a warning): "Build here" puts the
## count in THAT region, as a hand-set row; the lede and Who it moves follow it. A type that
## has no stock there gives way to the first that has (a rule over data).
func open_for(region_id: String) -> void:
	var ns = _state.player()
	if _type == "" or not _offered().has(_type) or Units.start_capacity(_loader, ns.id, _type, region_id) <= 0.0:
		_type = _first_type()
		for type_id in _offered():
			if Units.start_capacity(_loader, ns.id, type_id, region_id) > 0.0:
				_type = type_id
				break
	_region = region_id
	_placed = {region_id: _count}
	_dirty = true


func selected_type() -> String:
	return _type


func selected_region() -> String:
	return _region


## The programme's rows as the bill carries them: [{region, units}] in the regions' file order.
func rows() -> Array:
	var out: Array = []
	for region in _loader.regions.get(_state.player().id, []):
		if int(_placed.get(String(region.id), 0)) > 0:
			out.append({"region": String(region.id), "units": int(_placed[String(region.id)])})
	return out


func _offered() -> Array:
	var out: Array = []
	var ns = _state.player()
	for row in Units.catalogue(_loader):
		if String(row.get("payoff", "")) == UK.PAYOFF_CAPACITY and Units.offered(_loader, ns.id, String(row["id"])):
			out.append(String(row["id"]))
	return out


func _first_type() -> String:
	var offered := _offered()
	return String(offered[0]) if not offered.is_empty() else ""


func _pick_type(type_id: String) -> void:
	_type = type_id
	_fill(true)


## By need (or by population) for the count; `need` false is by population.
func _fill(need: bool) -> void:
	_placed = {}
	if _type == "":
		return
	var ns = _state.player()
	var filled: Array = Units.fill_by_need(ns, _loader, _type, _count) if need else Units.fill_by_population(ns, _loader, _type, _count)
	for r in filled:
		_placed[String(r["region"])] = int(r["units"])
	if _region == "" and not filled.is_empty():
		_region = String(filled[0]["region"])


func _refresh() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	if _type == "" or not _offered().has(_type):
		_pick_type(_first_type())
	if _type == "":
		PanelKit.plain_line(_body, tr("This nation has no register of buildings yet."), PanelKit.Tone.PLAIN)
		return
	var ns = _state.player()
	custom_minimum_size.y = get_viewport_rect().size.y - WindowManager.DOCK_TOP - WindowManager.DOCK_BOTTOM - FILL_SLACK
	var row: Dictionary = Units.row(_loader, _type)
	# Now, from one basis (preview with nothing placed is the shown figure, test_units pins it).
	var now: Dictionary = Units.preview(ns, _loader, _type, {})
	var shown := {}
	for region in _loader.regions.get(ns.id, []):
		if Units.start_capacity(_loader, ns.id, _type, region.id) > 0.0:
			shown[String(region.id)] = float(now[String(region.id)])
	var nation := Units.national_figure(ns, _loader, _type)
	_lede(row, shown, nation)
	_types()
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 16)
	_body.add_child(middle)
	var after: Dictionary = Units.preview(ns, _loader, _type, _placed)
	_dots(middle, ns, shown, after, nation)
	var quote := _quote(ns)
	_composer(middle, ns, quote)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(spacer)
	_strip(ns, row, quote, shown, after)
	_in_bill(ns)


## "Pays de la Loire: 4.82 hospital beds per 1 000 inhabitants; the nation 5.67." The type's
## summary under it, so a new type explains itself from its own row.
func _lede(row: Dictionary, shown: Dictionary, nation: float) -> void:
	var unit := _figure_unit(row)
	var line := Label.new()
	line.theme_type_variation = UiTheme.LEAD
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if shown.has(_region):
		line.text = tr("%s: %s %s; the nation %s.") % [_region_name(_region), Num.f(float(shown[_region]), 2), unit, Num.f(nation, 2)]
	else:
		line.text = tr("The nation: %s %s.") % [Num.f(nation, 2), unit]
	_body.add_child(line)
	PanelKit.plain_line(_body, Strings.row_summary("units", row), PanelKit.Tone.DIM)
	# What stands there now, as the stock counts it. A count of establishments is shown only
	# where the source publishes one (section 2): with none, the capacity alone, by rule.
	if shown.has(_region):
		var ns = _state.player()
		var units := Units.start_units(_loader, ns.id, _type, _region)
		var capacity := PanelKit.pop_text(Units.start_capacity(_loader, ns.id, _type, _region))
		var stock := Strings.tn("Standing there now: %d establishment, a capacity of %s.", "Standing there now: %d establishments, a capacity of %s.", units) % [units, capacity] if units > 0 else tr("Standing there now: a capacity of %s; no count of establishments is published.") % capacity
		PanelKit.plain_line(_body, stock, PanelKit.Tone.DIM).set_meta("stock", true)


func _figure_unit(row: Dictionary) -> String:
	return Strings.row("units", String(row["id"]), "figure.unit", String((row.get("figure", {}) as Dictionary).get("unit", "")))


func _types() -> void:
	var flow := PanelKit.buttons(_body)
	PanelKit.plain_line(flow, tr("Build"), PanelKit.Tone.DIM).autowrap_mode = TextServer.AUTOWRAP_OFF
	# One choice among the catalogue's types (the shared segmented control): a new type in
	# data/units/ is a new segment, nothing here names one.
	var options: Array = []
	for type_id in _offered():
		options.append({"id": type_id, "label": Strings.row_name("units", Units.row(_loader, type_id))})
	var segments := PanelKit.segmented(flow, options, _type, func(id: String) -> void:
		# A group still emits pressed on the picked segment: re-picking it must not wipe the rows.
		if id == _type:
			return
		_pick_type(id)
		_dirty = true)
	for b in segments.get_children():
		b.set_meta("type_chip", String(b.get_meta("segment")))


func _dots(parent: Control, ns, shown: Dictionary, after: Dictionary, nation: float) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	var data: Array = []
	for region in _loader.regions.get(ns.id, []):
		var id := String(region.id)
		if shown.has(id):
			data.append({"id": id, "label": String(region.region_name), "before": float(shown[id]),
				"after": float(after.get(id, shown[id])), "moved": int(_placed.get(id, 0)) > 0, "selected": id == _region})
	# Worst first, by the figure's own direction: the regions the sheet exists for lead.
	var lower_better := String((Units.row(_loader, _type).get("figure", {}) as Dictionary).get("better", "")) == "lower"
	data.sort_custom(func(a, b): return float(a["before"]) > float(b["before"]) if lower_better else float(a["before"]) < float(b["before"]))
	# The warning band joins when the sim names its threshold (UNIT_REGION_BAND, Systems' slice C).
	var box := ChartKit.dots(col, tr("By region: now, and once built"), data, {"reference": nation})
	var dots = box.get_meta("chart")
	dots.set_meta("dots", true)
	dots.picked.connect(func(id: String) -> void:
		_region = id
		_dirty = true)


func _composer(parent: Control, ns, quote: Dictionary) -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(SIDE_W, 0)
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)
	PanelKit.heading(col, tr("The programme"))
	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 8)
	col.add_child(count_row)
	PanelKit.plain_line(count_row, tr("How many"), PanelKit.Tone.DIM).autowrap_mode = TextServer.AUTOWRAP_OFF
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = COUNT_MAX
	spin.value = _count
	spin.set_meta("count", true)
	spin.value_changed.connect(func(v: float) -> void:
		_count = int(v)
		_fill(true)
		_dirty = true)
	count_row.add_child(spin)
	var fills := PanelKit.buttons(col)
	for pair in [[tr("By need"), true], [tr("By population"), false]]:
		var b := Button.new()
		b.theme_type_variation = UiTheme.SMALL
		b.text = String(pair[0])
		var need: bool = pair[1]
		b.pressed.connect(func() -> void:
			_fill(need)
			_dirty = true)
		fills.add_child(b)
	# One row per region the programme places units in, and the picked region: each editable.
	for region in _loader.regions.get(ns.id, []):
		var id := String(region.id)
		if int(_placed.get(id, 0)) <= 0 and id != _region:
			continue
		if Units.start_capacity(_loader, ns.id, _type, id) <= 0.0:
			continue
		var line := HBoxContainer.new()
		col.add_child(line)
		var name := PanelKit.plain_line(line, String(region.region_name), PanelKit.Tone.PLAIN)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var units := SpinBox.new()
		units.min_value = 0
		units.max_value = COUNT_MAX
		units.value = int(_placed.get(id, 0))
		units.set_meta("region_units", id)
		units.value_changed.connect(func(v: float) -> void:
			# The rows together never pass the count's own ceiling.
			_placed[id] = mini(int(v), COUNT_MAX - (_sum() - int(_placed.get(id, 0))))
			_count = maxi(1, _sum())
			_dirty = true)
		line.add_child(units)
	# The concentration surcharge (section 4), said on the region it falls on, before the press.
	var surcharge: Dictionary = quote.get("surcharge", {})
	for id in surcharge:
		# A warning only when it rounds to 1 % or more (the parent's ruling): the range carries the rest.
		if roundi(100.0 * float(surcharge[id])) >= 1:
			PanelKit.chip(col, tr("+%s %% on the price in %s: many units there within a year") % [
				Num.f(100.0 * float(surcharge[id]), 0), _region_name(String(id))]).set_meta("surcharge", String(id))
	var bill := {FinanceRows.UNITS: [{"type": _type, "op": UK.OP_BUILD, "rows": rows()}]}
	var why := _why_not(bill)
	var press := PanelKit.sized(Button.new())
	press.theme_type_variation = UiTheme.PRIMARY
	press.text = tr("Put it in the finance bill")
	press.disabled = why != ""
	press.set_meta("table", true)
	press.pressed.connect(func() -> void:
		var answer: Dictionary = FinanceBill.table(_state, _loader, bill)
		_refusal = "" if bool(answer.get("tabled", false)) else _reason(answer)
		_dirty = true
		# The bill moved: every panel reads it (firm_commands.invest's sweep).
		var windows: Node = self
		while windows != null and not windows.has_method("mark_all_dirty"):
			windows = windows.get_parent()
		if windows != null:
			windows.mark_all_dirty())
	PanelKit.buttons(col).add_child(press)
	var said := why if why != "" else _refusal
	var refusal := PanelKit.plain_line(col, said, PanelKit.Tone.PLAIN)
	refusal.theme_type_variation = UiTheme.WARN_TEXT
	refusal.visible = said != ""
	refusal.set_meta("refusal", true)


func _sum() -> int:
	var n := 0
	for id in _placed:
		n += int(_placed[id])
	return n


## Why the press would be refused now, read before it (the very rule tabling meets).
func _why_not(bill: Dictionary) -> String:
	if rows().is_empty():
		return tr("Place at least one unit.")
	# The same programme already in the bill: a second press would add nothing (FinanceRows.merge).
	var held: Array = (_state.player().tabled_bill.get("finance", {}) as Dictionary).get(FinanceRows.UNITS, [])
	for kept in held:
		if String(kept.get("type", "")) == _type and String(kept.get("op", "")) == UK.OP_BUILD and kept.get("rows", []) == rows():
			return tr("This programme is already in the finance bill.")
	var answer: Dictionary = FinanceBill.refusal(_state, _loader, bill)
	return "" if answer.is_empty() else _reason(answer)


## The register's own reason when it gave one, else the bill's, said as every tabling says it.
func _reason(answer: Dictionary) -> String:
	if String(answer.get("reason", "")) != "":
		return Strings.t(String(answer["reason"]))
	return ProposalNote.body(answer, _loader.parties.get(_state.player().id, []))


## The sim's quote for the rows, {} while the rows cannot be tabled as a programme.
func _quote(ns) -> Dictionary:
	var programme := {"type": _type, "op": UK.OP_BUILD, "rows": rows()}
	if rows().is_empty() or UnitBuild.refusal(_state, ns, _loader, [programme]) != "":
		return {}
	# The rows the bill already holds count toward concentration, as FinanceBill.drafted prices them.
	# The same programme already held is this one, never an earlier order of it.
	var earlier: Array = ((ns.tabled_bill.get("finance", {}) as Dictionary).get(FinanceRows.UNITS, []) as Array).filter(
		func(kept): return not (String(kept.get("type", "")) == _type and kept.get("rows", []) == rows()))
	return UnitPrice.quote(_state, ns, _loader, programme, earlier)


## The three-part strip: the money, who it moves, when and what can go wrong.
func _strip(ns, row: Dictionary, quote: Dictionary, shown: Dictionary, after: Dictionary) -> void:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 24)
	_body.add_child(strip)
	var money := _column(strip, tr("The money"))
	var who := _column(strip, tr("Who it moves"))
	var when := _column(strip, tr("When, and what can go wrong"))
	if quote.is_empty():
		var programme := {"type": _type, "op": UK.OP_BUILD, "rows": rows()}
		var why := UnitBuild.refusal(_state, ns, _loader, [programme]) if not rows().is_empty() else ""
		PanelKit.plain_line(money, Strings.t(why) if why != "" else tr("Place at least one unit."), PanelKit.Tone.DIM)
		return
	var lo := float(quote["lo_eur_m"]) / 1000.0
	var hi := float(quote["hi_eur_m"]) / 1000.0
	var months := int(quote["build_months"])
	var running := float(quote["running_eur_m_year"]) / 1000.0
	var line := PanelKit.plain_line(money, tr("%s to %s bn over %d months, then %s bn a year for good.") % [
		Num.f(lo, 2), Num.f(hi, 2), months, Num.f(running, 2)], PanelKit.Tone.PLAIN)
	line.set_meta("money", true)
	ChartKit.range_bar(money, tr("Price range, bn"), lo, float(quote["estimate_eur_m"]) / 1000.0, hi).set_meta("range", true)
	var cash = RegisterMoney.new()
	cash.set_meta("cash", true)
	money.add_child(cash)
	cash.cash_of(UnitPrice.now(_state), months, float(quote["estimate_eur_m"]) / 1000.0, running, [tr("Building"), tr("Running cost")])
	_who(who, row, shown, after)
	var open_at := UnitPrice.now(_state) + months
	PanelKit.plain_line(when, tr("Opens about %s, %d months after the vote.") % [
		DateText.month_year((open_at - 1) % 12 + 1, (open_at - 1) / 12), months], PanelKit.Tone.PLAIN)
	PanelKit.chip(when, tr("%s %% chance of one overrun ask during the build") % Num.f(100.0 * float(quote["odds"]), 0),
		UiTheme.CHIP_WARN, "warning").set_meta("odds", true)


func _column(parent: Control, heading: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.0
	parent.add_child(col)
	PanelKit.heading(col, heading)
	return col


## The picked region before and after, and the most any other region gives back.
func _who(col: VBoxContainer, row: Dictionary, shown: Dictionary, after: Dictionary) -> void:
	var here := _region if int(_placed.get(_region, 0)) > 0 else (String(rows()[0]["region"]) if not rows().is_empty() else "")
	if here == "" or not shown.has(here):
		return
	PanelKit.plain_line(col, tr("%s: %s → %s %s.") % [_region_name(here), Num.f(float(shown[here]), 2),
		Num.f(float(after[here]), 2), _figure_unit(row)], PanelKit.Tone.PLAIN)
	var back := 0.0
	for id in shown:
		if int(_placed.get(id, 0)) <= 0:
			back = maxf(back, absf(float(after[id]) - float(shown[id])))
	PanelKit.plain_line(col, tr("The other regions give back up to %s: the nation's figure moves only with the money on its line.") % Num.f(back, 2), PanelKit.Tone.DIM)


## The programmes the tabled finance bill already carries, with the day it divides.
func _in_bill(ns) -> void:
	var held: Array = (ns.tabled_bill.get("finance", {}) as Dictionary).get(FinanceRows.UNITS, [])
	if held.is_empty():
		return
	PanelKit.heading(_body, tr("In the finance bill"))
	var when := DateText.day_month(int(ns.tabled_bill.get("vote_day", 1)), int(ns.tabled_bill.get("vote_month", 1)))
	var forced := bool(ns.tabled_bill.get("forced", false))
	for p in held:
		var n := 0
		for r in p.get("rows", []):
			n += int(r.get("units", 0))
		var name := Strings.row_name("units", Units.row(_loader, String(p.get("type", ""))))
		var text := Strings.tn("%d unit of %s: adopted without a vote on %s.", "%d units of %s: adopted without a vote on %s.", n) if forced else Strings.tn("%d unit of %s: it divides on %s.", "%d units of %s: it divides on %s.", n)
		PanelKit.plain_line(_body, text % [n, name, when],
			PanelKit.Tone.PLAIN).set_meta("in_bill", true)


## Whether any catalogue type the nation's stock offers stands in the region: the region
## sheet's door is shown only where something can be built (no dead click).
static func can_build_in(loader, nation_id: String, region_id: String) -> bool:
	for row in Units.catalogue(loader):
		var id := String(row["id"])
		if String(row.get("payoff", "")) == UK.PAYOFF_CAPACITY and Units.offered(loader, nation_id, id) and Units.start_capacity(loader, nation_id, id, region_id) > 0.0:
			return true
	return false


func _region_name(region_id: String) -> String:
	for region in _loader.regions.get(_state.player().id, []):
		if String(region.id) == region_id:
			return String(region.region_name)
	return region_id
