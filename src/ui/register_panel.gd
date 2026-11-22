extends PanelContainer

## The construction register's order form -- V5.3 c' slice 1 (docs/design/v5.3-c-register.md
## section 9, "One surface"; the author's pick, verbatim: "A pour commander + C en suivi").
## The player picks a unit type, how many and where, reads what it does before tabling, and
## puts it in the finance bill. G3 S4, Register in C (register-in-c.png): the head (the region against the nation, the
## type's segments), then two sheets side by side -- WHERE (register_where.gd: the regions as the table, each row's
## units set on it, Who it moves) and THE PROGRAMME (register_programme.gd: what and where, the money, when and what
## can go wrong, the press, greyed with the bill's own reason before it is pressed). The bill's rail shows where the
## programme would land (landing()).
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
const ProposalNote = preload("res://src/ui/proposal_note.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const RegisterWhere = preload("res://src/ui/register_where.gd")
const RegisterProgramme = preload("res://src/ui/register_programme.gd")
const RegisterDoor = preload("res://src/ui/register_door.gd")
const Units = preload("res://src/sim/units.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")
const UnitBuild = preload("res://src/sim/unit_build.gd")
const UK = preload("res://src/sim/units_constants.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceRows = preload("res://src/sim/finance_rows.gd")

const COUNT_MAX := 200

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
var _warning := {}  # {type, region, month}: the sheet was opened from a region warning
var _fill_mode := "need"  # how the rows were last filled: "need", "population", "" by hand
var _landing := {}


func _ready() -> void:
	custom_minimum_size = Vector2(900, 0)
	theme_type_variation = UiTheme.BARE  # the page lays out its own sheets (window_manager OWN_SHEETS)
	var root := VBoxContainer.new()
	add_child(root)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", UiTheme.GAP_PANE)
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
	_warning = {}
	_fill_mode = "need"
	_landing = {}
	_dirty = true


func hide_close_button() -> void:
	_close_button.hide()


func mark_dirty() -> void:
	_dirty = true


## A text size moves the header sheet, so the floor (page_room) is read again.
func _notification(what: int) -> void:
	_dirty = _dirty or what == NOTIFICATION_THEME_CHANGED


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
	_fill_mode = ""
	_warning = {}  # a door that is not the warning's puts its bar away (pass 2 on #428)
	_dirty = true


## The region warning's door (register_warning.gd): the type's band_units in that region,
## and the warning's answers under the lede (register_door.gd).
func open_from_warning(type_id: String, region_id: String, month: int) -> void:
	_type = type_id
	place(region_id, int(_loader.unit_types[type_id]["band_units"]))
	_warning = {"type": type_id, "region": region_id, "month": month}


## `units` in the region as a hand-set row, the count with it.
func place(region_id: String, units: int) -> void:
	_region = region_id
	_count = units
	_placed = {region_id: units}
	_fill_mode = ""
	_dirty = true


func clear_warning() -> void:
	_warning = {}
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
	return offered_types(_loader, _state.player().id)


## The catalogue's types the nation can build (the Programmes tab reads the same rule).
static func offered_types(loader, nation_id: String) -> Array:
	var out: Array = []
	for row in Units.catalogue(loader):
		if String(row.get("payoff", "")) == UK.PAYOFF_CAPACITY and Units.offered(loader, nation_id, String(row["id"])):
			out.append(String(row["id"]))
	return out


func _first_type() -> String:
	var offered := _offered()
	return String(offered[0]) if not offered.is_empty() else ""


func _pick_type(type_id: String) -> void:
	_type = type_id
	_fill_mode = "need"
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
	WindowManager.fill_page(self, "register")  # the sheet fills the workspace, never scrolls for it
	var row: Dictionary = Units.row(_loader, _type)
	# Now, from one basis (preview with nothing placed is the shown figure, test_units pins it).
	var now: Dictionary = Units.preview(ns, _loader, _type, {})
	var shown := {}
	for region in _loader.regions.get(ns.id, []):
		if Units.start_capacity(_loader, ns.id, _type, region.id) > 0.0:
			shown[String(region.id)] = float(now[String(region.id)])
	var nation := Units.national_figure(ns, _loader, _type)
	RegisterWhere.lede(self, PanelKit.sheet(_body), row, shown, nation)
	if String(_warning.get("type", "")) == _type and String(_warning.get("region", "")) == _region:
		RegisterDoor.bar(self, PanelKit.sheet(_body), _state, _loader, _warning)  # on its own sheet: no text bare on the map
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", UiTheme.GAP_PANE)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(middle)
	var quote := _quote(ns)
	RegisterWhere.build(self, middle, ns, row, shown, Units.preview(ns, _loader, _type, _placed), nation)
	RegisterProgramme.build(self, middle, ns, row, quote)
	_landing = RegisterProgramme.landing(self, row, quote)


## What the bill's rail shows as this programme's place in it (finance_pages.gd reads it): {} while it cannot be tabled.
func landing() -> Dictionary:
	return _landing


func _figure_unit(row: Dictionary) -> String:
	return Strings.row("units", String(row["id"]), "figure.unit", String((row.get("figure", {}) as Dictionary).get("unit", "")))


func table_programme() -> bool:
	var answer: Dictionary = FinanceBill.table(_state, _loader, {FinanceRows.UNITS: [{"type": _type, "op": UK.OP_BUILD, "rows": rows()}]})
	_refusal = "" if bool(answer.get("tabled", false)) else _reason(answer)
	_dirty = true
	# The bill moved: every panel reads it (firm_commands.invest's sweep).
	var windows: Node = self
	while windows != null and not windows.has_method("mark_all_dirty"):
		windows = windows.get_parent()
	if windows != null:
		windows.mark_all_dirty()
	return _refusal == ""


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
		if FinanceRows.same_units_row(kept, (bill[FinanceRows.UNITS] as Array)[0]):
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
		func(kept): return not FinanceRows.same_units_row(kept, programme))
	return UnitPrice.quote(_state, ns, _loader, programme, earlier)


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
