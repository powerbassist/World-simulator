extends PanelContainer

## Public works -- V1.6f's surface, laid out again at G3 S4 PR 2c as the author's "A calendrier"
## (works-a-calendar.png; g3-slices/s4-finances/notes.md "Public works"): every work is a lane
## on one axis of years with today and the end of the term on it, the works' bill by year under
## the same axis, and the picked work's sheet beside them. The player decides WHEN: what opens
## before the term ends, and what the bill is in each year until then.
##
## Reads simulation state and content, and writes neither: a verb goes back as an explicit
## command through `acted`, the shape Budget.commit() set. A start applies at once and never
## feeds the finance bill (a project's bill is its own spending line), so the page has no lever
## rows; its one filled button is the picked work's Start, and the finance bill's fold is plain
## here (FinancePages.leads reads that).
##
## A project is in one of three states and each is a different question -- what is BUILT is
## what the treasury pays for now, what is FINISHED is what the country has bought, what is
## ON OFFER is what is left -- so the lanes keep them apart, building first.

signal closed
## (before_snapshot, label) -- the same pair companies_panel.acted, nation_panel.acted
## and law_panel.proposed emit, so beginning a project earns a U4 decision delta on
## the terms a subsidy and a law already do.
signal acted(before, label)

const Projects = preload("res://src/sim/projects.gd")
const Trends = preload("res://src/ui/trends.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")
const ConfirmCard = preload("res://src/ui/confirm_card.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const WorksRows = preload("res://src/ui/works_rows.gd")
const WorksLane = preload("res://src/ui/works_lane.gd")
const WorksBill = preload("res://src/ui/works_bill.gd")
const WorksSheet = preload("res://src/ui/works_sheet.gd")

## The words column of the lanes and the bill, at text size 100 (the picture's 250).
const TEXT_WIDTH := 250.0
## The axis runs at least this far past the last opening, so every wedge shows.
const AXIS_PAST := 30

var _state
var _loader
var _dirty := true
var _body: VBoxContainer
var _close_button: Button
var _picked := ""
## The yes-or-no a Cancel… asks on; made on the screen stack at the first ask.
var _confirm = null

## The control this panel exists to let the player press. See primary_action().
var _primary: Control = null


func _ready() -> void:
	custom_minimum_size = Vector2(900, 0)
	theme_type_variation = UiTheme.BARE  # the page lays out its own sheets (window_manager OWN_SHEETS)
	var root := VBoxContainer.new()
	add_child(root)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
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


## tools/screenshot.gd's --build calls it. The page no longer scrolls on its own (the
## workspace's page does), so there is nothing to pin: kept so the flag still runs.
func scroll_to_bottom() -> void:
	_dirty = true


func hide_close_button() -> void:
	_close_button.hide()


func mark_dirty() -> void:
	_dirty = true


## The work the sheet shows.
func picked() -> String:
	return _picked


## A text size moves the sheets, so the floor (page_room) is read again.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_dirty = true


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return
	_primary = null
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	WindowManager.fill_page(self, "projects")
	var rows := WorksRows.rows(_state, _loader, ns)
	if rows.filter(func(r): return String(r["id"]) == _picked).is_empty():
		_picked = WorksRows.first_pick(rows)
	var now := WorksRows.now(_state)
	var when := Trends.vote_date(ns)
	var term := when.x * 12 + when.y if Trends.months_until(_state, when.x, when.y) >= 0 else -1
	_head(ns, rows, term)
	_build_refusal(ns)
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", UiTheme.GAP_PANE)
	_body.add_child(main)
	_works(main, rows, now, term)
	for r in rows:
		if String(r["id"]) == _picked:
			var free := WorksRows.slots(_loader) - Projects.building_count(ns)
			var sheet := WorksSheet.build(main, r, rows, now, free, func(action) -> void: _on_act(ns, action))
			for b in sheet.find_children("*", "Button", true, false):  # i18n: ok a class name
				if (b as Button).theme_type_variation == UiTheme.PRIMARY:
					_primary = b


## The page's head: the sentence that says what to decide, then the bill, the growth bought
## and the slots taken.
func _head(ns, rows: Array, term: int) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	PanelKit.sheet(_body).add_child(line)
	var lead := Label.new()
	lead.theme_type_variation = UiTheme.LEAD
	lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead.text = _lead(rows, term)
	line.add_child(lead)
	var bill := Projects.bill_pct_gdp(ns, _loader)
	PanelKit.figure_tile(line, tr("%s %%") % Num.f(bill, 3), tr("of GDP a year · %s bn") % Num.f(bill / 100.0 * float(ns.gdp_eur_bn), 1))
	PanelKit.figure_tile(line, tr("+%s %%") % Num.f(ns.project_potential_target_pct, 3), tr("growth a year bought"))
	PanelKit.figure_tile(line, tr("%d of %d") % [Projects.building_count(ns), WorksRows.slots(_loader)], tr("works being built"))


## One whole sentence a case: the picked offer against the term's end, or why nothing can start.
func _lead(rows: Array, term: int) -> String:
	for r in rows:
		if String(r["id"]) == _picked and String(r["state"]) == WorksRows.OFFER:
			var opens := int(r["opens"])
			if term > 0 and opens > term:
				return tr_n("%s would open %d month after your term ends.", "%s would open %d months after your term ends.", opens - term) % [r["name"], opens - term]  # i18n: row-ok the reader's name, through Strings.noun
			return tr("%s would open in %s, before your term ends.") % [r["name"], DateText.month_long_year((opens - 1) % 12 + 1, (opens - 1) / 12)]  # i18n: row-ok the reader's name, through Strings.noun
	if not rows.filter(func(r): return String(r["state"]) == WorksRows.BUILDING).is_empty():
		return tr("Every slot is taken: nothing can start until a work opens.")
	return tr("Every work has been built.") if not rows.is_empty() else tr("Nothing is on offer.")


## The works' sheet: the axis, a lane a work, the legend, then the bill on the same axis.
func _works(main: Control, rows: Array, now: int, term: int) -> void:
	var sheet := PanelKit.sheet(main, tr("Works · %d") % rows.size())
	sheet.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var first := (now - 1) / 12 * 12 + 1
	var last := maxi(now, term) + 12
	for r in rows:
		last = maxi(last, int(r["opens"]) + AXIS_PAST)
	last = (last - 1) / 12 * 12 + 13  # to the next January
	var width := roundf(TEXT_WIDTH * UiTheme.text_scale())
	var verbs := roundf(PanelKit.BTN_W[PanelKit.Size.M] * UiTheme.text_scale())
	var axis: Control = _columns(sheet, width, verbs, WorksLane.new())
	axis.set_meta("works_axis", true)
	axis.axis(first, last, now, term)
	var buttons: Array = []
	for r in rows:
		_lane_row(sheet, r, first, last, now, term, width, verbs, buttons)
	if not buttons.is_empty():
		PanelKit.same_class(buttons, PanelKit.BTN_H_ROW)
	PanelKit.heading(sheet, tr("The works' bill, % of GDP a year"))
	var bill: Control = WorksBill.new()
	var words: Control = _columns(sheet, width, verbs, bill)
	bill.set_meta("works_bill", true)
	var name := ""
	for r in rows:
		if String(r["id"]) == _picked and String(r["state"]) == WorksRows.OFFER:
			name = String(r["name"])  # i18n: row-ok the reader's name, through Strings.noun
	bill.setup(rows, first, last, _picked if name != "" else "", name)
	var caption := PanelKit.plain_line(words.get_child(0), tr("Paid until the work opens."))
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if name != "":
		PanelKit.plain_line(words.get_child(0), tr("Dashed: with the picked work."), PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## A row of the three columns (words, the axis's control, the verbs); returns the middle control,
## or for the bill the row itself (its words column holds the caption).
func _columns(parent: Control, width: float, verbs: float, middle: Control):
	var line := HBoxContainer.new()
	parent.add_child(line)
	var words := VBoxContainer.new()
	words.custom_minimum_size.x = width
	line.add_child(words)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(middle)
	var pad := Control.new()
	pad.custom_minimum_size.x = verbs
	line.add_child(pad)
	return line if middle is WorksBill else middle


func _lane_row(sheet: Control, r: Dictionary, first: int, last: int, now: int, term: int, width: float, verbs: float, buttons: Array) -> void:
	var id := String(r["id"])
	var picked := id == _picked
	# The picked row sits on a tile (sectors_timeline's grammar); the others on the sheet itself.
	var plate: Container = PanelContainer.new() if picked else MarginContainer.new()
	if picked:
		plate.theme_type_variation = UiTheme.TILE_PANEL
	sheet.add_child(plate)
	var line := HBoxContainer.new()
	plate.add_child(line)
	var words := VBoxContainer.new()
	words.custom_minimum_size.x = width
	words.add_theme_constant_override("separation", 0)
	line.add_child(words)
	var title := Button.new()
	title.flat = true
	title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.text = String(r["name"])  # i18n: row-ok the reader's name, through Strings.noun
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = String(r["name"])  # i18n: row-ok the reader's name, through Strings.noun
	title.pressed.connect(func() -> void:
		_picked = id
		_dirty = true)
	words.add_child(title)
	PanelKit.plain_line(words, _sub(r)).autowrap_mode = TextServer.AUTOWRAP_OFF
	var lane: Control = WorksLane.new()
	lane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lane.set_meta("works_lane", id)
	line.add_child(lane)
	lane.lane(r, first, last, now, term, picked)
	var verb := CenterContainer.new()
	verb.custom_minimum_size.x = verbs
	line.add_child(verb)
	var ns = _state.player()
	if String(r["state"]) == WorksRows.OFFER and r["start"] != null:
		var start := PanelKit.button(tr("Start"), PanelKit.Size.S, PanelKit.BTN_H_ROW)
		start.set_meta("works_start_" + id, true)
		start.pressed.connect(func() -> void: _on_act(ns, r["start"]))
		verb.add_child(start)
		buttons.append(start)
	elif String(r["state"]) == WorksRows.BUILDING and r["cancel"] != null:
		var cancel := PanelKit.button(tr("Cancel…"), PanelKit.Size.S, PanelKit.BTN_H_ROW)
		cancel.theme_type_variation = UiTheme.GHOST
		cancel.set_meta("works_cancel_" + id, true)
		cancel.pressed.connect(func() -> void: _ask_cancel(ns, r))
		verb.add_child(cancel)
		buttons.append(cancel)


func _sub(r: Dictionary) -> String:
	var growth := Num.f(float(r["growth_pct"]), 3)
	match String(r["state"]):
		WorksRows.BUILDING:
			return tr("%d of %d months built · +%s %%/yr") % [int(r["months"]) - int(r["left"]), int(r["months"]), growth]
		WorksRows.OFFER:
			return tr("on offer · %s %% of GDP · +%s %%/yr") % [Num.f(float(r["cost_pct"]), 2), growth]
		_:
			return tr("finished · +%s %%/yr") % growth


## Cancelling recovers nothing (Projects: no partial motorway), so it asks first.
func _ask_cancel(ns, r: Dictionary) -> void:
	if _confirm == null:
		_confirm = ConfirmCard.on_stack(self)
		if _confirm == null:
			_on_act(ns, r["cancel"])
			return
		_confirm.confirmed.connect(func() -> void: _on_act(_state.player(), _confirm.get_meta(&"action")))
	_confirm.set_meta(&"action", r["cancel"])
	_confirm.ask(tr("%s: cancel it?\nWhat it has cost is lost, and nothing is built.") % String(r["name"]),  # i18n: row-ok the reader's name, through Strings.noun
		Strings.row_name("project-actions", r["cancel"]))


## U4's contract, companies_panel._on_invest()'s shape exactly: the baseline is
## captured BEFORE the command, so the delta measures the month the work began
## against the month before it.
func _on_act(ns, action) -> void:
	var before := Trends.snapshot_now(_state)
	var result := Projects.execute(_state, ns, _loader.project_actions, action)
	_dirty = true  # a refusal is drawn too: _build_refusal()
	if result.get("applied", false):
		acted.emit(before, Strings.row_name("project-actions", action))


## The last verb the sim refused -- its display record, ns.last_project_result -- as a
## BLOCKED line at the top, so a stale button pressed is never a silent click
## (V5.3-0 RF7, the parent's call on #222: energy, project and investment results).
## The sim gives no reason beyond "not available", so the line says that.
func _build_refusal(ns) -> void:
	var last: Dictionary = ns.last_project_result
	for action in (_loader.project_actions if bool(last.get("refused", false)) else []):
		if String(action.id) == String(last.get("action_id", "")):
			ResultTone.tint(PanelKit.line(_body, tr("%s refused -- it is no longer on offer.") % Strings.row_name("project-actions", action)), ResultTone.BLOCKED)


## The control this panel exists to let the player press -- V2.1a's fold contract: the
## picked work's Start, or nothing (a page with no offer has no main verb).
func primary_action() -> Control:
	return _primary if is_instance_valid(_primary) else null
