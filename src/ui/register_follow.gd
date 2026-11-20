extends Control

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

var _state
var _loader
var _dirty := true
var _body: VBoxContainer
var _close_button: Button


func _ready() -> void:
	custom_minimum_size = Vector2(900, 0)
	var root := PanelKit.padded(self, 16, 10)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_body)
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


## Offered where the register is: a stock file names a type the nation can build (a rule
## over data, never a nation id).
func is_offered() -> bool:
	if _state == null or _state.player() == null:
		return false
	for row in Units.catalogue(_loader):
		if String(row.get("payoff", "")) == UK.PAYOFF_CAPACITY and Units.offered(_loader, _state.player().id, String(row["id"])):
			return true
	return false


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
	var building: Array = ns.unit_programmes.filter(func(p): return String(p.get("state", "")) == UK.STATE_BUILDING)
	var asks: Array = UnitOverrun.asks(_state, ns, _loader)
	var lede := Label.new()
	lede.theme_type_variation = UiTheme.LEAD
	lede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(lede)
	if building.is_empty():
		lede.text = tr("No programme is building.")
		PanelKit.plain_line(_body, tr("The Register tab puts one in the finance bill; once voted, it is followed here."), PanelKit.Tone.DIM)
	else:
		lede.text = tr_n("%d programme building.", "%d programmes building.", building.size()) % building.size()
		if not asks.is_empty():
			lede.text += " " + tr_n("%d question waits for you.", "%d questions wait for you.", asks.size()) % asks.size()
		PanelKit.plain_line(_body, tr("Every unit voted is built over its months, then open at a running cost for good."), PanelKit.Tone.DIM)
	for copy in asks:
		_overrun(copy)
	_envelope(ns)
	if not building.is_empty():
		var list := PanelKit.section(_body, tr("Programmes"))
		for p in building:
			_programme(list, p)


func _name(p: Dictionary) -> String:
	var names: Array = []
	var units := 0
	for r in p.get("rows", []):
		names.append(_region_name(String(r.get("region", ""))))
		units += int(r.get("units", 0))
	return tr("%s · %s · %d") % [Strings.row_name("units", Units.row(_loader, String(p["type"]))), ", ".join(names), units]


## One programme: its name, its months as a meter, the money and the opening.
func _programme(parent: Control, p: Dictionary) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.set_meta("programme", String(p["id"]))
	parent.add_child(box)
	PanelKit.plain_line(box, _name(p), PanelKit.Tone.PLAIN)
	var total := int(p["build_months"])
	var left := int(p["months_left"])
	PanelKit.meter(box, float(total - left), float(maxi(total, 1)), float(total))  # the tick: the opening
	var paid := float(p["paid_eur_m"]) / 1000.0
	var to_pay := float(p["capital_month_eur_m"]) * left / 1000.0
	var opens := UnitPrice.opens_at(p)
	PanelKit.plain_line(box, tr("%d of %d months built. Paid %s bn, %s bn to pay; opens %s.") % [
		total - left, total, Num.f(paid, 2), Num.f(to_pay, 2), _month(opens)], PanelKit.Tone.DIM)
	var union: Dictionary = p.get("union", {})
	if not union.is_empty():
		PanelKit.plain_line(box, tr("The Union holds %s bn for it, paid after the opening if it opens by %d.") % [
			Num.f(float(union["reserved_eur_m"]) / 1000.0, 2), int(union["pays_until"])], PanelKit.Tone.DIM)


## The Union's envelope of the period under way: what is left of it, as a meter.
func _envelope(ns) -> void:
	var org := UnitEnvelope.org_of(_loader, ns)
	if org == "":
		return
	var year := UnitEnvelope.year_of(UnitPrice.now(_state))
	var period := UnitEnvelope.period_of(_loader, org, year)
	if period.is_empty():
		return
	var whole := UnitEnvelope.envelope_eur_m(period, ns.id)
	var left := UnitEnvelope.left_eur_m(_loader, ns, year)
	var section := PanelKit.section(_body, tr("The Union's envelope, %d-%d") % [int(period["first_year"]), int(period["last_year"])])
	section.set_meta("envelope", true)
	PanelKit.plain_line(section, tr("%s bn left until %d, of %s.") % [Num.f(left / 1000.0, 2), int(period["pays_until_year"]),
		Num.f(whole / 1000.0, 2)], PanelKit.Tone.PLAIN)
	PanelKit.meter(section, left, maxf(whole, left), maxf(whole, left))


## The overrun card: what the builders ask, by when, and the answers as they would land now.
func _overrun(copy: Dictionary) -> void:
	var ask: Dictionary = copy["ask"]
	var card := PanelKit.section(_body, tr("Overrun ask: %s") % _name(copy))
	card.set_meta("overrun_card", String(copy["id"]))
	PanelKit.chip(card, tr("Answer by %s, or it is paid.") % _month(int(ask["due"])), UiTheme.CHIP_WARN, "warning")
	PanelKit.plain_line(card, tr("The builders need %s bn more to finish. One ask a programme: it will not come back.") % Num.f(float(ask["eur_m"]) / 1000.0, 2),
		PanelKit.Tone.PLAIN)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	for a in ask.get("answers", []):
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var button := PanelKit.sized(Button.new())
		button.text = _answer_label(String(a["id"]))
		button.set_meta("overrun_" + String(a["id"]), true)
		var programme := String(copy["id"])
		var answer_id := String(a["id"])
		button.pressed.connect(func() -> void:
			UnitOverrun.answer(_state, _state.player(), _loader, programme, answer_id)
			_dirty = true
			var windows: Node = self
			while windows != null and not windows.has_method("mark_all_dirty"):
				windows = windows.get_parent()
			if windows != null:
				windows.mark_all_dirty())
		PanelKit.buttons(col).add_child(button)
		PanelKit.plain_line(col, _answer_says(copy, a), PanelKit.Tone.DIM)


func _answer_label(id: String) -> String:
	match id:
		UK.OVERRUN_PAY:
			return tr("Pay")
		UK.OVERRUN_SHRINK:
			return tr("Shrink")
		_:
			return tr("Delay")


## What an answer makes of the programme, from its outcome (UnitOverrun.outcome's fields).
func _answer_says(copy: Dictionary, a: Dictionary) -> String:
	var opens := _month(int(a["opens"]))
	var left := int(copy["months_left"])
	var says := ""
	match String(a["id"]):
		UK.OVERRUN_PAY:
			says = tr("+%s bn over the %d months left; opens %s.") % [Num.f(float(copy["ask"]["eur_m"]) / 1000.0, 2), left, opens]
		UK.OVERRUN_SHRINK:
			says = tr_n("%d unit kept, the bill holds; opens %s.", "%d units kept, the bill holds; opens %s.", int(a["units"])) % [int(a["units"]), opens]
		_:
			says = tr_n("The same monthly bill, %d more month; opens %s.", "The same monthly bill, %d more months; opens %s.", int(a["months_left"]) - left) % [int(a["months_left"]) - left, opens]
	if bool(a.get("union_lost", false)):
		says += " " + tr("The Union's share is lost.")
	return says


func _month(absolute: int) -> String:
	return DateText.month_year((absolute - 1) % 12 + 1, (absolute - 1) / 12)


func _region_name(region_id: String) -> String:
	for region in _loader.regions.get(_state.player().id, []):
		if String(region.id) == region_id:
			return String(region.region_name)
	return region_id
