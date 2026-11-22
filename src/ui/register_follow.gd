extends PanelContainer

## The register's follow-up tab (V5.3 c' register slice 2, the author's pick "C en suivi";
## docs/design/v5.3-c-register.md sections 5 to 7): what the Register tab put in the finance
## bill, once voted. Each programme under way with its months (a meter), the money paid and
## left and its opening; the Union's envelope when the nation is in an organisation; and an
## overrun card with its answers AS THEY WOULD LAND NOW (UnitOverrun.asks computes them when
## read), answered through UnitOverrun.answer -- the sim's command, as the press is tabling's.
##
## Read-only over GameState otherwise. Every figure is the register's (UnitBuild's rows,
## UnitPrice.opens_at, UnitEnvelope's reads); counts go through int(), since a loaded row
## carries 3.0.

signal closed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Units = preload("res://src/sim/units.gd")
const UK = preload("res://src/sim/units_constants.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")
const UnitOverrun = preload("res://src/sim/unit_overrun.gd")
const UnitEnvelope = preload("res://src/sim/unit_envelope.gd")
const RegisterLanes = preload("res://src/ui/register_lanes.gd")
const RegisterPanel = preload("res://src/ui/register_panel.gd")
const RegisterMoney = preload("res://src/ui/register_money.gd")
const RegisterUnits = preload("res://src/ui/register_units.gd")
const FinanceRowsUi = preload("res://src/ui/finance_rows.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const AnswerRow = preload("res://src/ui/answer_row.gd")
const HOURGLASS := "res://assets/icons/ui/hourglass.svg"

## The empty page's next step (Design T5 on #448): regions_shell opens Register on it.
signal register_requested

var _state
var _loader
var _dirty := true
var _body: VBoxContainer
var _close_button: Button


func _ready() -> void:
	custom_minimum_size = Vector2(900, 0)
	theme_type_variation = UiTheme.BARE  # the page lays out its own sheets (window_manager OWN_SHEETS)
	# No scroll of its own: the workspace's page scrolls (window_manager.frame()).
	var root := VBoxContainer.new()
	add_child(root)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", UiTheme.GAP_PANE)
	root.add_child(_body)
	_close_button = Button.new()
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


func hide_close_button() -> void:
	_close_button.hide()


func mark_dirty() -> void:
	_dirty = true


## A text size moves the header sheet, so the floor (page_room) is read again.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_dirty = true


## Offered where the register is: a stock file names a type the nation can build (a rule
## over data, never a nation id).
func is_offered() -> bool:
	return _state != null and _state.player() != null and not RegisterPanel.offered_types(_loader, _state.player().id).is_empty()


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null or _state.player() == null:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	_dirty = false
	_refresh()


func _refresh() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var ns = _state.player()
	WindowManager.fill_page(self, "programmes")  # the sheet fills the workspace, never scrolls for it
	var building: Array = ns.unit_programmes.filter(func(p): return String(p.get("state", "")) == UK.STATE_BUILDING)
	var asks: Array = UnitOverrun.asks(_state, ns, _loader)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	PanelKit.sheet(_body).add_child(head)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(words)
	var lede := Label.new()
	lede.theme_type_variation = UiTheme.LEAD
	lede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(lede)
	if building.is_empty():
		lede.text = tr("No programme is building.")
		# The next step as a ghost button at the sheet's end: a label, not one more sentence (Design T5 on #448).
		var door := PanelKit.sized(Button.new())
		door.text = tr("Open Register")
		door.theme_type_variation = UiTheme.GHOST
		door.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		door.set_meta("open_register", true)
		door.pressed.connect(func() -> void: register_requested.emit())
		head.add_child(door)
	else:
		lede.text = tr_n("%d programme building.", "%d programmes building.", building.size()) % building.size()
		if not asks.is_empty():
			lede.text += " " + tr_n("%d question waits for you.", "%d questions wait for you.", asks.size()) % asks.size()
		PanelKit.plain_line(words, tr("Every unit voted is built over its months, then open at a running cost for good."), PanelKit.Tone.DIM)
	if not asks.is_empty():
		# The one date on the page: amber is for a date to answer by (Building in C).
		var first_due: int = asks.map(func(c): return _last_month(c)).min()  # the earliest: the one that lapses first
		# A deadline tag wears the hourglass (gate T8 on #443); the triangle is the alert glyph.
		var due := PanelKit.chip(head, tr("Answer by %s") % _month(first_due), UiTheme.CHIP_WARN, HOURGLASS)
		due.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		due.set_meta("due", true)
		for label in due.find_children("*", "Label", true, false):  # i18n: ok a class name
			(label as Label).autowrap_mode = TextServer.AUTOWRAP_OFF  # the date on one line, beside the lede
	if not building.is_empty():
		var list := PanelKit.sheet(_body, tr("Programmes"))
		var lanes := RegisterLanes.new()
		lanes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lanes.set_meta("lanes", true)
		list.add_child(lanes)
		var due := {}  # a programme's ask: the month it is answered by
		for copy in asks:
			due[String(copy["id"])] = _last_month(copy)
		lanes.setup(building.map(func(p): return _lane(p, int(due.get(String(p["id"]), 0)))), UnitPrice.now(_state), {"row": 44})
		for p in building:
			_programme(list, p)
	for copy in asks:
		_overrun(copy)
	# A flow: three asks' bills and the envelope wrap onto a second line rather than squeeze (pass 2 T2 on #448).
	var foot := HFlowContainer.new()
	foot.add_theme_constant_override("h_separation", UiTheme.GAP_PANE)
	foot.add_theme_constant_override("v_separation", UiTheme.GAP_PANE)
	foot.set_meta("follow_foot", true)
	_body.add_child(foot)
	for copy in asks:
		_bill_if_paid(foot, copy)  # one bill a question, as each card carried its own before
	_envelope(ns, foot)
	if foot.get_child_count() == 0:
		_body.remove_child(foot)  # no empty row: it would add a gap under the page
		foot.queue_free()


## A programme's lane: its name, what is paid of its build, its months in the bar, and its ask's answer-by month
## (0: none) with its tag.
func _lane(p: Dictionary, due: int) -> Dictionary:
	var left := int(p["months_left"])
	var built := maxi(0, int(p.get("paid_month", int(p["voted"]) - 1)) - int(p["voted"]) + 1)
	var paid := float(p["paid_eur_m"]) / 1000.0
	return {"label": _name(p), "start": int(p["voted"]), "opens": UnitPrice.opens_at(p), "due": due,
		"tag": tr("answer by %s") % _month(due) if due > 0 else "",
		"sub": tr("paid %s of %s bn") % [Num.f(paid, 2), Num.f(paid + float(p["capital_month_eur_m"]) * left / 1000.0, 2)],
		"bar_text": tr("building · %d of %d months") % [built, built + left]}


func _name(p: Dictionary) -> String:
	var names: Array = []
	var units := 0
	for r in p.get("rows", []):
		names.append(_region_name(String(r.get("region", ""))))
		units += int(r.get("units", 0))
	return tr("%s · %s · %d") % [Strings.row_name("units", Units.row(_loader, String(p["type"]))), ", ".join(names), units]


## One programme under the lanes: its months built and its opening in words (the lane draws them), then the Union's
## line.
func _programme(parent: Control, p: Dictionary) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.set_meta("programme", String(p["id"]))
	parent.add_child(box)
	# Months actually built (the vote month pays): a Delay adds months, so the total is these
	# plus what is left, never the voted build_months.
	var left := int(p["months_left"])
	var built := maxi(0, int(p.get("paid_month", int(p["voted"]) - 1)) - int(p["voted"]) + 1)
	var opens := UnitPrice.opens_at(p)
	PanelKit.plain_line(box, tr("%s: %d of %d months built; opens %s.") % [_name(p), built, built + left, _month(opens)], PanelKit.Tone.DIM)
	var union: Dictionary = p.get("union", {})
	if not union.is_empty():
		# Nothing held (a Delay past its year, the nation out of the Union): the share is lost.
		if float(union["reserved_eur_m"]) <= 0.0 or UnitEnvelope.year_of(opens) > int(union["pays_until"]):
			PanelKit.plain_line(box, tr("The Union's share for it is lost."), PanelKit.Tone.DIM).set_meta("union_lost", true)
		else:
			PanelKit.plain_line(box, tr("The Union holds %s bn for it, paid after the opening if it opens by %d.") % [
				Num.f(float(union["reserved_eur_m"]) / 1000.0, 2), int(union["pays_until"])], PanelKit.Tone.DIM)


## The Union's envelope of the period under way: what is left of it, as a meter.
func _envelope(ns, parent: Control) -> void:
	var org := UnitEnvelope.org_of(_loader, ns)
	if org == "":
		return
	var year := UnitEnvelope.year_of(UnitPrice.now(_state))
	var period := UnitEnvelope.period_of(_loader, org, year)
	if period.is_empty():
		return
	var whole := UnitEnvelope.envelope_eur_m(period, ns.id)
	var left := UnitEnvelope.left_eur_m(_loader, ns, year)
	var section := PanelKit.sheet(parent, tr("The Union's envelope, %d-%d") % [int(period["first_year"]), int(period["last_year"])])
	section.set_meta("envelope", true)
	# Reserved only by a vote in the period's years: its last vote year, not the year it pays until.
	PanelKit.plain_line(section, tr("%s of %s bn left; votes until %d.") % [Num.f(left / 1000.0, 2), Num.f(whole / 1000.0, 2),
		int(period["last_year"])], PanelKit.Tone.PLAIN)
	PanelKit.meter(section, left, maxf(whole, left), maxf(whole, left))


## The overrun ask on its own sheet (Building in C): what the builders ask, then its three answers side by side, each
## with its figure, the units it keeps, the same small chart on one axis (from the vote to the opening it gives) and
## what it makes of the programme, and the date it is answered by, or paid.
func _overrun(copy: Dictionary) -> void:
	var ask: Dictionary = copy["ask"]
	var card := PanelKit.sheet(_body, tr("Overrun ask · %s") % _name(copy))
	card.set_meta("overrun_card", String(copy["id"]))
	var line := HBoxContainer.new()
	card.add_child(line)
	var need := Label.new()
	need.theme_type_variation = UiTheme.LEAD
	need.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	need.text = tr("The builders need %s bn more to finish.") % Num.f(float(ask["eur_m"]) / 1000.0, 2)
	line.add_child(need)
	PanelKit.plain_line(line, tr("One ask a programme: it will not come back."), PanelKit.Tone.DIM).autowrap_mode = TextServer.AUTOWRAP_OFF
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var until := 0
	for a in ask.get("answers", []):
		until = maxi(until, int(a["opens"]))
	var verbs: Array = []
	for a in ask.get("answers", []):
		verbs.append(_answer(row, copy, a, until))
	PanelKit.same_class(verbs)  # one question, one class (AnswerRow's rule)
	PanelKit.plain_line(card, tr("Unanswered by %s: it is paid.") % _month(_last_month(copy)), PanelKit.Tone.DIM)


## One answer as a tile: its name, its figure, the units it keeps, its small chart, what it makes, its button.
func _answer(row: Control, copy: Dictionary, a: Dictionary, until: int) -> Button:
	# The kit's figure tile (test_panel_kit: one home), its box carrying the rest of the answer.
	var tile := PanelKit.figure_tile(row, _answer_figure(copy, a), _answer_caption(copy, a))
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := PanelKit.tile_body(tile).get_child(0) as VBoxContainer
	var answer_id := String(a["id"])
	col.move_child(PanelKit.heading(col, _answer_label(answer_id)), 0)
	# The units each answer keeps, as squares (a Shrink outlines the ones it cuts).
	var squares := RegisterUnits.new()
	squares.set_meta("units_" + answer_id, true)
	col.add_child(squares)
	squares.setup(int(a["units"]), _units(copy))
	var chart := RegisterLanes.new()
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.set_meta("answer_chart_" + answer_id, true)
	col.add_child(chart)
	chart.setup([{"label": "", "start": int(copy["voted"]), "opens": int(a["opens"])}], UnitPrice.now(_state),
		{"label_w": 0.0, "axis": false, "until": until, "row": 18, "ends": true})
	var says := PanelKit.plain_line(col, _answer_says(copy, a), PanelKit.Tone.DIM)
	if bool(a.get("union_lost", false)):
		# Bad news on its own line, its red down-glyph and the amount it loses (Design T4 on #448).
		var lost := HBoxContainer.new()
		lost.add_theme_constant_override("separation", 6)
		lost.set_meta("union_lost_answer", true)
		col.add_child(lost)
		lost.add_child(AnswerRow.Glyph.new(false))
		var held := float(copy.get("union", {}).get("reserved_eur_m", 0.0)) / 1000.0
		var words := PanelKit.plain_line(lost, tr("The Union's share is lost: %s bn.") % Num.f(held, 2), PanelKit.Tone.PLAIN)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var button := PanelKit.sized(Button.new())
	button.text = _answer_label(answer_id)
	button.set_meta("overrun_" + answer_id, true)
	var programme := String(copy["id"])
	button.pressed.connect(func() -> void:
		UnitOverrun.answer(_state, _state.player(), _loader, programme, answer_id)
		_dirty = true
		var windows: Node = self
		while windows != null and not windows.has_method("mark_all_dirty"):
			windows = windows.get_parent()
		if windows != null:
			windows.mark_all_dirty())
	PanelKit.buttons(col).add_child(button)
	return button


func _answer_figure(copy: Dictionary, a: Dictionary) -> String:
	var more := int(a["months_left"]) - int(copy["months_left"])
	match String(a["id"]):
		UK.OVERRUN_PAY:
			return tr("+%s bn") % Num.f(float(copy["ask"]["eur_m"]) / 1000.0, 2)
		UK.OVERRUN_SHRINK:
			return tr("%d of %d units") % [int(a["units"]), _units(copy)]
		_:
			return tr_n("+%d month", "+%d months", more) % more


func _answer_caption(copy: Dictionary, a: Dictionary) -> String:
	var left := int(copy["months_left"])
	match String(a["id"]):
		UK.OVERRUN_PAY:
			return tr_n("over the %d month left", "over the %d months left", left) % left
		UK.OVERRUN_SHRINK:
			return tr("the bill holds")
		_:
			return tr("the same monthly bill")


## Picture C's "the year's bill, if you pay": the capital left with the overrun paid over the
## months left (its share on top, outlined), then the running cost once open.
func _bill_if_paid(parent: Control, copy: Dictionary) -> void:
	var pay := {}
	for a in copy["ask"].get("answers", []):
		if String(a["id"]) == UK.OVERRUN_PAY:
			pay = a
	if pay.is_empty():
		return
	var left := int(pay["months_left"])
	var capital := float(pay["capital_month_eur_m"]) * left
	var q: Dictionary = UnitPrice.quote(_state, _state.player(), _loader, {"type": copy["type"], "op": copy["op"], "rows": copy["rows"]})
	# Its programme in the title: two asks' bills are told apart (pass 2 T2 on #448).
	var card := PanelKit.sheet(parent, tr("The year's bill if you pay · %s, bn") % _name(copy))
	var bill = RegisterMoney.new()
	bill.set_meta("bill_if_paid", true)
	# Its running cost lands on a spending line: that line's hue, never the accent (Diane's R4 on #443).
	bill.running_color = FinanceRowsUi.line_color(String(Units.row(_loader, String(copy["type"])).get("line", "")))
	card.add_child(bill)
	bill.cash_of(UnitPrice.now(_state), left, capital / 1000.0, float(q.get("running_eur_m_year", 0.0)) / 1000.0,
		[tr("Building"), tr("Running cost"), tr("The overrun, paid")])
	bill.mark_overrun(float(copy["ask"]["eur_m"]) / maxf(capital, 1e-9))


## The last month an ask can be answered in: UnitOverrun.tick pays it once now reaches its due
## month, so the due month itself is already too late (pass 2 T1 on #448).
static func _last_month(copy: Dictionary) -> int:
	return int(copy["ask"]["due"]) - 1


func _units(p: Dictionary) -> int:
	var n := 0
	for r in p.get("rows", []):
		n += int(r.get("units", 0))
	return n


func _answer_label(id: String) -> String:
	match id:
		UK.OVERRUN_PAY:
			return tr("Pay")
		UK.OVERRUN_SHRINK:
			return tr("Shrink")
		_:
			return tr("Delay")


## What an answer makes of the programme, from its outcome (UnitOverrun.outcome's fields): the units it keeps and
## when it opens (the figure over it says the money or the months); a lost Union share has its own line.
func _answer_says(_copy: Dictionary, a: Dictionary) -> String:
	return tr_n("%d unit, opens %s.", "%d units, opens %s.", int(a["units"])) % [int(a["units"]), _month(int(a["opens"]))]


func _month(absolute: int) -> String:
	return DateText.month_long_year((absolute - 1) % 12 + 1, (absolute - 1) / 12)  # the month in full (decision 4)


func _region_name(region_id: String) -> String:
	for region in _loader.regions.get(_state.player().id, []):
		if String(region.id) == region_id:
			return String(region.region_name)
	return region_id
