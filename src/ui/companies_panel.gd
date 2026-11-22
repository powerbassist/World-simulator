extends PanelContainer

## The private sector -- V1.4a's one new surface.
##
## Reads simulation state and content, and writes neither: the verb goes back as
## an explicit command through `acted`, which is the shape Budget.commit() set and
## nation_panel.gd follows.
##
## THE WHOLE BODY SCROLLS FROM THE FIRST LINE, and that is this panel's answer to
## the fold nation_panel.gd has paid for three times (V1.3e, V1.3g, U6a). That
## panel keeps its verb rows in a fixed-height column, so every session that adds
## a verb pushes the last one off the bottom of a window whose ceiling U5a fixed at
## ~886px. Here the rows live inside a ScrollContainer, so V1.4b's regulation and
## V1.4c's two ownership verbs cannot push anything out of reach -- the panel grows
## with the register and with the verb list, and both are scheduled to grow.
##
## Grouped by SECTOR rather than listed flat, because a subsidy takes share from
## the rivals in one sector and nowhere else. A player who cannot see who the
## rivals are cannot see what the button does.
##
## V1.6e HANGS ITS WHOLE SURFACE ON THAT GROUPING AND ADDS NO WINDOW: the sector
## programme sits in its sector, beside the firms it competes with for growth.
##
## V5.3 a + b step 2 (docs/design/v5.3-ab.md 3.2) TURNED THE GROUPS INTO CARDS, the
## readability gate's "Industry: lisible NON" answered: what is under way first
## (industry_progress.gd), then three sector cards closed until opened
## (industry_card.gd), a major's verbs one Act away (industry_verbs.gd). This file
## keeps what the player has opened, the commands, and the rows that are not a
## sector's: the bid, the failing firms, the public account.
##
## G3 S3 (the author's "C La frise") RE-LAID THE PAGE: a strip of three sector doors on top,
## then what runs and when it lands as dated rows on one time scale (sectors_timeline.gd), the
## picked row's sheet beside the list where its decision is answered (sectors_decision.gd), and
## the economy's shape under the timeline. The cards are gone from the page (industry_card.gd
## with them): a Needs you route picks its firm's row, and a firm's verbs are its sector tab's
## (Design's T4 on #441).
##
## It also stops returning early on an empty firm register. A nation with no
## data/companies/<ID>.json still has three sectors and can still invest in them --
## the register is what may be absent, not the economy.

signal closed
## (before_snapshot, label) -- the same pair nation_panel.acted and
## law_panel.proposed emit, so a subsidy earns a U4 decision delta on the terms a
## law and a diplomatic action already do.
signal acted(before, label)
## A sector card's Open: the sector tab's window id (main opens it).
signal tab_requested(window_id: String)

const Companies = preload("res://src/sim/companies.gd")
const Investment = preload("res://src/sim/investment.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Num = preload("res://src/ui/num.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")
const IndustryProgress = preload("res://src/ui/industry_progress.gd")
const TimelineBar = preload("res://src/ui/timeline_bar.gd")
const DateText = preload("res://src/ui/date_text.gd")
const SectorsTimeline = preload("res://src/ui/sectors_timeline.gd")
const SectorsDecision = preload("res://src/ui/sectors_decision.gd")
const FirmCommands = preload("res://src/ui/firm_commands.gd")
const SectorsOverview = preload("res://src/ui/sectors_overview.gd")

var _state
var _loader
var _dirty := true

## The economy's lead sentence, over the share bars (SectorsOverview.charts).
var _title: Label
## The page under the scroll: the doors, then the two columns.
var _page: VBoxContainer
## The left column: the timeline, the economy's shape, the public account.
var _body: VBoxContainer
## Kept rather than left local, and the reason is the screenshot pass. This panel's
## content is guaranteed to overflow -- three sectors, their programmes and up to six
## firms -- so the sector a flag has just acted on is usually below the fold, and a
## frame that cannot show it proves nothing about the row it exists to check.
## tools/screenshot.gd drives this; nothing in the game does.
var _scroll: ScrollContainer
var _pin_bottom := false
var _close_button: Button

## The first enabled verb this panel built on its last refresh. See primary_action().
var _primary: Control = null

## The sim's last refusal, shown at the head of the body until the next act
## lands. The verb arms write refusal reasons into `last_company_result` "for
## the panel to show" -- and nothing read them, so a refused click was a
## no-op the player could not tell from a dead button (the ultra's find;
## the no-sorber break-up and the exhausted board pool are the reachable
## cases).
var _last_refusal := ""
## The card an irreversible verb asks on (CompanyVerb.ask), made at the first ask.
var _confirm
## What the player has opened -- the public account. Held here, not in the rebuilt rows,
## so the month's sweep redraws the tab as the player left it. "" is closed. `_refocus` is the control a toggle came from, focused again after
## the rebuild so the keyboard path does not fall back to the top.
var _open_ledger := ""
var _refocus := []
## The timeline row the side sheet shows, by its key ("" lets _choose pick), and its firm: a
## row that changes kind (a closure rescued becomes rescue|firm) is found again by the firm.
var _pick := ""
var _pick_firm := ""
## The row the side sheet showed at the last build, and the one an answer was given on: it
## stays on the sheet once it stops waiting, unless another row waits (_choose).
var _shown := ""
var _shown_firm := ""
var _held := ""
var _held_firm := ""
## The waiting rows' keys at the last build: a row that starts to wait is picked on its own,
## over the player's older pick (pass 2 on #441, the ask T11). Empty until the first build.
var _waits_seen := {}
var _seen_once := false
## The rows of the last build (a pick's firm), and the month and day it drew: a new day moves
## today's line on the bars it drew, a new month rebuilds.
var _rows: Array = []
var _built_month := -1
var _built_day := -1
## The doors strip and the side column (read by the tests).
var _doors: Control
var _side: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(520, 0)  # the dock sets the height (tab_page.gd wanted_height)

	# No margin round the sheets: they sit on the header sheet's grid, its edges and a gap under it
	# (window_manager OWN_SHEETS; Design's T14 on #441, the Diary's rule).
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	# No gutter for the bar: the outer sheet's edge must meet the header's (T14), and a sheet's own
	# padding keeps its right-aligned figures clear of a bar drawn over it.
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", UiTheme.GAP_PANE)
	_scroll.add_child(_page)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", UiTheme.GAP_PANE)
	_page.add_child(columns)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	columns.add_child(_body)
	_side = VBoxContainer.new()
	_side.custom_minimum_size.x = roundf(SectorsDecision.WIDTH * UiTheme.text_scale())
	_side.add_theme_constant_override("separation", 12)
	columns.add_child(_side)

	_close_button = Button.new()
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true
	# A setup() after the first is a load: the discarded game's open rows and refusal go with it, as sector_panel's do.
	_last_refusal = ""
	_open_ledger = ""
	_refocus = []
	_pick = ""
	_pick_firm = ""
	_held = ""
	_held_firm = ""
	_waits_seen = {}
	_seen_once = false


## Pins the scroll to the bottom, for tools/screenshot.gd. A panel whose body always
## overflows cannot be photographed at the top and called evidence for a row that is
## three sectors down.
##
## A STANDING FLAG rather than a one-shot call, and the first version was the one-shot:
## _refresh() rebuilds every child, so a scroll set before the next rebuild is undone by
## it, and the rebuild is exactly what a setup flag triggers. Nothing in the game sets
## this.
func scroll_to_bottom() -> void:
	_pin_bottom = true
	_dirty = true


func _apply_bottom() -> void:
	if _scroll == null:
		return
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func hide_close_button() -> void:
	_close_button.hide()


func _process(_delta: float) -> void:
	if _state != null and int(_state.year) * 12 + int(_state.month) != _built_month:
		_dirty = true
	elif _state != null and int(_state.day) != _built_day and not _dirty:
		_move_today()
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


## Today's line moves a day on the bars already drawn: a rebuild each day would drop the
## keyboard focus and a click in flight (pass 1 on the pass-2 delta).
func _move_today() -> void:
	_built_day = int(_state.day)
	var today := (float(_state.day) - 1.0) / float(DateText.days_in(int(_state.month), int(_state.year)))
	for bar in _body.find_children("*", "Control", true, false):  # i18n: ok a class name
		if bar is TimelineBar:
			bar.today = today
			bar.queue_redraw()


func mark_dirty() -> void:
	_dirty = true


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return
	_primary = null

	for child in _body.get_children() + _side.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	if _doors != null:
		_doors.get_parent().remove_child(_doors)
		_doors.queue_free()
	var tab := func(id: String) -> void: tab_requested.emit(id)
	_doors = SectorsOverview.doors(_page, _state, _loader, ns, tab)
	_page.move_child(_doors, 0)

	if ns.companies.is_empty():
		# Reachable: a nation with no data/companies/<ID>.json has unpartitioned
		# sectors, which is a supported state rather than a hole. Said plainly, so
		# the player of a nation whose register has not been authored yet sees a
		# reason rather than an empty window. The programmes do not read the register.
		PanelKit.heading(_body, tr("No register"))
		PanelKit.line(_body, tr("No firms are named for this nation. Its sectors are modelled in aggregate."))

	if _last_refusal != "":
		ResultTone.tint(PanelKit.line(_body, _last_refusal), ResultTone.BLOCKED)
	var rows := SectorsTimeline.rows(_state, _loader, ns)
	_rows = rows
	_built_month = int(_state.year) * 12 + int(_state.month)
	_built_day = int(_state.day)
	# The side column follows the text size, as the rest of the page does.
	_side.custom_minimum_size.x = roundf(SectorsDecision.WIDTH * UiTheme.text_scale())
	_pick_new_waits(rows)
	var picked := _choose(rows)
	_shown = String(picked.get("key", ""))
	_shown_firm = String(picked.get("company_id", ""))
	SectorsTimeline.build(_body, _state, rows, String(picked.get("key", "")), _on_pick)
	IndustryProgress.endings(_body, _state, _loader, ns)
	_title = SectorsOverview.charts(_body, _state, _loader, ns, tab)
	_build_ledger(ns)
	SectorsDecision.build(self, _side, picked)
	_restore_focus()

	if _pin_bottom:
		_apply_bottom()


## The row the side sheet shows: the player's pick (a Needs you route sets it, open_firm), or
## its firm's row once the pick changed kind; else the first that waits; else the row last
## answered, or its firm's; else the first; {} when nothing runs.
func _choose(rows: Array) -> Dictionary:
	var firm := func(r, want: String) -> bool: return want != "" and String(r["company_id"]) == want
	for want in [func(r) -> bool: return String(r["key"]) == _pick, func(r) -> bool: return firm.call(r, _pick_firm),
			func(r) -> bool: return bool(r["waits"]), func(r) -> bool: return String(r["key"]) == _held,
			func(r) -> bool: return firm.call(r, _held_firm), func(_r) -> bool: return true]:
		for r in rows:
			if want.call(r):
				return r
	return {}


## A row that starts to wait opens in the sheet on its own: the player's older pick gives way.
func _pick_new_waits(rows: Array) -> void:
	var now := {}
	var fresh := ""
	for r in rows:
		if bool(r["waits"]):
			now[String(r["key"])] = true
			if fresh == "" and _seen_once and not _waits_seen.has(String(r["key"])):
				fresh = String(r["key"])
	if fresh != "":
		set_pick(fresh)
	_waits_seen = now
	_seen_once = true


## Picks the row `key` (a click, a route, a new decision); its firm is kept for a kind change.
func set_pick(key: String) -> void:
	_pick = key
	_pick_firm = ""
	for r in _rows:
		if String(r["key"]) == key:
			_pick_firm = String(r["company_id"])


func _on_pick(key: String) -> void:
	set_pick(key)
	_refocus = ["timeline_pick", key]
	_dirty = true


func _action_by_id(id: String):
	for a in _loader.company_actions:
		if String(a.id) == id:
			return a
	return null


func _firm_object(nation_id: String, company_id: String):
	for company in _loader.companies.get(nation_id, []):
		if company.id == company_id:
			return company
	return null


## The three figures the register produces, in one place. Both deviation channels
## read exactly 0.0 until a subsidy stands, a `business` law passes, or the
## autonomy machine acts -- an idle world's failures and drift move the jobs
## figure off zero by design (the B4 re-run's largest channel), so a non-zero
## row with no verb on record is the machine working and not a bug.
##
## The two deviation rows are NET, and deliberately not split into a subsidy half
## and a regulation half. Splitting them would mean recomputing each channel against
## a hypothetical register, which is a second model of the same quantity kept in
## step by hand; the sector cards above carry the burden instead, so a player who
## wants the attribution reads which sectors are marked.
func _build_ledger(ns) -> void:
	var fold := PanelKit.sized(Button.new())
	# A fold, not bold text (Design's T9 on #441): flat, so toggle() gives it the fold look, PICKED_ROW.
	fold.flat = true
	fold.text = tr("The public account")
	PanelKit.toggle(fold)
	fold.button_pressed = _open_ledger != ""
	fold.set_meta("ledger", "ledger")
	fold.pressed.connect(func() -> void: _toggle("_open_ledger", "ledger", "ledger"))
	_body.add_child(fold)
	if _open_ledger == "":
		return
	PanelKit.row(_body, tr("Subsidy bill"), tr("%s %% of GDP") % Num.f(ns.subsidy_bill_pct_gdp, 3))
	# V1.4c. On the same ledger and not on a second one, because it is the same
	# register read from the other side of the budget -- and it lags a month, like the
	# bill above it, so a firm nationalised this month shows 0.000 until the next tick.
	PanelKit.row(_body, tr("Dividend income"), tr("%s %% of GDP") % Num.f(ns.dividend_revenue_pct_gdp, 3))
	PanelKit.row(_body, tr("Growth effect"), tr("%s %%/yr") % Num.fs(ns.firm_impulse_pct, 3))
	# Signed the way the player reads it -- jobs, not unemployment points -- because
	# the stored figure is an offset ADDED to structural unemployment and a positive
	# number there is bad news. Flipping it here rather than storing it flipped keeps
	# economy.gd's sum readable.
	PanelKit.row(_body, tr("Jobs effect"), tr("%s pts unemployment") % Num.fs(ns.firm_jobs_offset_pct, 3))
	# V1.6e, on the same ledger as the subsidy bill because it is the other half of
	# one question -- what the state is spending on the productive economy -- and it
	# lags a month for the same reason.
	PanelKit.row(_body, tr("Investment bill"), tr("%s %% of GDP") % Num.f(ns.investment_bill_pct_gdp, 3))
	# The trend the capital has BOUGHT, not the growth it is producing this month.
	# Those are different quantities and the difference is the whole lever: the bill
	# lands immediately and this number takes years to arrive, which is why both are
	# printed rather than one summary of them.
	PanelKit.row(_body, tr("Trend bought"), tr("%s %%/yr") % Num.fs(Investment.national_trend_shift_pct(ns), 3))


## A programme is a finance-bill row (firm_commands.gd, shared with the sector tabs).
func _on_invest(_ns, action) -> void:
	FirmCommands.invest(self, action)


## Disabled with the sim's reason when the arm would refuse it (CompanyVerb, G1).
func _action_button(ns, company, action) -> Button:
	var button := CompanyVerb.button(_state, _loader, ns, company, action)
	button.pressed.connect(func(): _on_act(ns, company, action))
	if _primary == null and not button.disabled:
		_primary = button
	return button


## The firm commands live in firm_commands.gd, shared with the sector tabs' sheets.
func _on_act(ns, company, action) -> void:
	FirmCommands.act(self, ns, company, action)


func _act(ns, company, action) -> void:
	FirmCommands.run(self, ns, company, action)


## Opens `key` in the slot named `field` (the ledger), or closes it when it is already open.
func _toggle(field: String, key: String, meta := "") -> void:
	set(field, "" if String(get(field)) == key else key)
	_refocus = [meta, key]
	_dirty = true


func _restore_focus() -> void:
	if _refocus.is_empty() or String(_refocus[0]) == "":
		return
	var want: Array = _refocus
	_refocus = []
	for button in _page.find_children("*", "Button", true, false):  # i18n: ok a class name
		if button.has_meta(want[0]) and str(button.get_meta(want[0])) == str(want[1]):
			button.call_deferred("grab_focus")
			return


func _on_stop(process_id: String, what: String) -> void:
	_held = _shown
	_held_firm = _shown_firm
	FirmCommands.stop(self, process_id, what)


func _on_answer(process_id: String, answer_id: String, what: String) -> void:
	_held = _shown
	_held_firm = _shown_firm
	FirmCommands.answer(self, process_id, answer_id, what)


func _on_closure(closure_id: String, answer_id: String, what: String) -> void:
	_held = _shown
	_held_firm = _shown_firm
	FirmCommands.closure(self, closure_id, answer_id, what)


## The control this panel exists to let the player press -- V2.1a's fold contract.
##
## Duck-typed: tab_page.gd asks through has_method(), so a panel with nothing
## to press simply does not implement this and never draws the fold mark. The
## FIRST enabled action is the answer rather than the last, because a panel whose
## first verb has scrolled off is already a panel whose verbs are hidden.
##
## The subsidy button rather than the investment one: V1.6e photographed this
## panel at the top of a body whose three sector rows all read "No state
## programme" while the ledger above them carried a live 0.654 % of GDP, and the
## rows that were out of sight were the firm rows underneath.
func primary_action() -> Control:
	if is_instance_valid(_primary):
		return _primary
	# G3 S3: a door's Open is the way in.
	for button in _page.find_children("*", "Button", true, false):  # i18n: ok a class name
		if button.has_meta("open_tab"):
			return button
	return null
