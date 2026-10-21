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
## V1.6e HANGS ITS WHOLE SURFACE ON THAT GROUPING AND ADDS NO WINDOW. The sector
## lever is pointed at exactly the heading _build_sector() was already printing, so
## the readout and the two verbs go under it and the action bar does not grow. What
## did have to change is the lead: this panel is no longer only the private sector,
## because the state's own programme is now on it.
##
## It also stops returning early on an empty firm register. A nation with no
## data/companies/<ID>.json still has three sectors and can still invest in them --
## the register is what may be absent, not the economy.

signal closed
## (before_snapshot, label) -- the same pair nation_panel.acted and
## law_panel.proposed emit, so a subsidy earns a U4 decision delta on the terms a
## law and a diplomatic action already do.
signal acted(before, label)

const EK = preload("res://src/sim/economy_constants.gd")
const Companies = preload("res://src/sim/companies.gd")
const CompaniesK = preload("res://src/sim/companies_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const Investment = preload("res://src/sim/investment.gd")
const Industry = preload("res://src/sim/industry.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")

const SECTOR_LABEL := {
	"agriculture": "Agriculture", "industry": "Industry", "services": "Services",
}

var _state
var _loader
var _dirty := true

var _title: Label
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


func _ready() -> void:
	custom_minimum_size = Vector2(520, 560)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_title = Label.new()
	_title.theme_type_variation = UiTheme.LEAD
	root.add_child(_title)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	# The body sits inside a right margin rather than flush to the scroll, because a
	# ScrollContainer draws its bar OVER the content: without this the right-aligned
	# figures in PanelKit.row() run underneath it, which is what the first captured frame
	# showed for all three ledger values. A vertical bar is ~10px, and this panel is
	# the one surface in the game whose content is guaranteed to overflow.
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 14)
	_scroll.add_child(gutter)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	gutter.add_child(_body)

	_close_button = Button.new()
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


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
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return
	_primary = null

	_title.text = tr("Industry")

	for child in _body.get_children():
		child.queue_free()

	if ns.companies.is_empty():
		# Reachable: a nation with no data/companies/<ID>.json has unpartitioned
		# sectors, which is a supported state rather than a hole. Said plainly, so
		# the player of a nation whose register has not been authored yet sees a
		# reason rather than an empty window.
		#
		# V1.6e turned this from a RETURN into a note. The sector programmes below do
		# not read the firm register at all, so returning here would have hidden a
		# working lever behind a missing content file.
		PanelKit.heading(_body, tr("No register"))
		PanelKit.line(_body, tr("No firms are named for this nation. Its sectors are modelled in aggregate; the investment programmes below still apply."))

	if _last_refusal != "":
		PanelKit.line(_body, _last_refusal)
	_build_autonomy_sections(ns)
	_build_ledger(ns)
	for sector in EK.SECTOR_TREND.keys():
		_build_sector(ns, String(sector))

	if _pin_bottom:
		_apply_bottom()


## V4.7b: the autonomy machine's two answerable states, each with the verb
## row on it. A pending bid offers block/allow; a failing major offers the
## rescue (its restore arm answers the window). Both vanish when answered or
## lapsed -- the sections are the state's own material, not a feed.
func _build_autonomy_sections(ns) -> void:
	var bid: Dictionary = Industry.pending_bid(_state, ns, _loader)
	if not bid.is_empty():
		PanelKit.heading(_body, tr("Foreign takeover bid"))
		var firm_name: String = _loader.firm_name(ns.id, String(bid["company_id"]))
		# EUR bn, its own format -- pop_text is the POPULATION formatter and
		# rendered a 50 bn offer as "0 k" (the B3 review's Important). The
		# bidder resolves through the loader like every other surface -- the
		# raw three-letter id read as a country's name on the shipped frame
		# (the pass-4 fleet's find).
		PanelKit.line(_body, tr("%s offers %.1f bn for %s -- %d months left.") % [
			_loader.nation_name(String(bid["bidder_nation"])), float(bid["price_eur_bn"]),
			firm_name, int(bid["months_left"])])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		# The same gate the failing row answers to: available() is the door
		# execute() refuses through. A bid standing on a FAILED firm once
		# rendered dead Block/Allow buttons beside the rescue row (the
		# pass-4 fleet's merged find); the machine now clears a bid at the
		# failure commit, and this gate is the defence in depth -- if a bid
		# and a failure ever coexist again, the buttons go with the door.
		var bid_actions: Array = Companies.available(_state, ns, _loader.company_actions, String(bid["company_id"]), _loader)
		for action_id in ["block_takeover", "allow_takeover"]:
			var action = _action_by_id(action_id)
			if action != null and bid_actions.has(action):
				row.add_child(_action_button(ns, _firm_object(ns.id, String(bid["company_id"])), action))
		_body.add_child(row)
	var failing: Array = Industry.failing(_state, ns, _loader)
	if not failing.is_empty():
		PanelKit.heading(_body, tr("Failing firms"))
		for failure in failing:
			var company_id := String(failure["company_id"])
			PanelKit.line(_body, tr("%s -- rescue window: %d months left.") % [
				_loader.firm_name(ns.id, company_id), int(failure["months_left"])])
			var action = _action_by_id("strategic_rescue")
			if action == null:
				continue
			# NO availability gate here, deliberately, and this is not the
			# oversight it looks like beside the bid row above: available()'s
			# failed gate offers strategic_rescue UNCONDITIONALLY on a firm
			# inside its window (the pass-2 zombie fix), so every firm this
			# loop lists has the verb -- an earlier draft gated and noted a
			# subsidised-firm refusal that the same fix made unreachable
			# (the failure commit clears the subsidy; the pass-4 fleet found
			# the note dead). If a future gate ever refuses here again, gate
			# AND note come back together.
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			row.add_child(_action_button(ns, _firm_object(ns.id, company_id), action))
			_body.add_child(row)


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
## step by hand; the sector headings below carry the burden instead, so a player who
## wants the attribution reads which sectors are marked.
func _build_ledger(ns) -> void:
	PanelKit.heading(_body, tr("The public account"))
	PanelKit.row(_body, tr("Subsidy bill"), tr("%.3f %% of GDP") % ns.subsidy_bill_pct_gdp)
	# V1.4c. On the same ledger and not on a second one, because it is the same
	# register read from the other side of the budget -- and it lags a month, like the
	# bill above it, so a firm nationalised this month shows 0.000 until the next tick.
	PanelKit.row(_body, tr("Dividend income"), tr("%.3f %% of GDP") % ns.dividend_revenue_pct_gdp)
	PanelKit.row(_body, tr("Growth effect"), tr("%+.3f %%/yr") % ns.firm_impulse_pct)
	# Signed the way the player reads it -- jobs, not unemployment points -- because
	# the stored figure is an offset ADDED to structural unemployment and a positive
	# number there is bad news. Flipping it here rather than storing it flipped keeps
	# economy.gd's sum readable.
	PanelKit.row(_body, tr("Jobs effect"), tr("%+.3f pts unemployment") % ns.firm_jobs_offset_pct)
	# V1.6e, on the same ledger as the subsidy bill because it is the other half of
	# one question -- what the state is spending on the productive economy -- and it
	# lags a month for the same reason.
	PanelKit.row(_body, tr("Investment bill"), tr("%.3f %% of GDP") % ns.investment_bill_pct_gdp)
	# The trend the capital has BOUGHT, not the growth it is producing this month.
	# Those are different quantities and the difference is the whole lever: the bill
	# lands immediately and this number takes years to arrive, which is why both are
	# printed rather than one summary of them.
	PanelKit.row(_body, tr("Trend bought"), tr("%+.3f %%/yr") % Investment.national_trend_shift_pct(ns))


func _build_sector(ns, sector: String) -> void:
	var firms := Companies.firms_in_sector(_loader, ns.id, sector)
	var sector_output: float = float(ns.sector_output.get(sector, 0.0))
	var named := 0.0
	for company in firms:
		# share_of_company, not share_of: the sparse register reads 0.0 for
		# every untouched body firm, and the heading would print the majors'
		# share (~0.3) against authored coverage of ~0.88 -- the A3 review's
		# Critical 2.
		named += Companies.share_of_company(ns, company)
	# V1.4b. The burden is per SECTOR, so it belongs on the sector's own line and
	# nowhere else -- putting it on a firm row would suggest a rule the player could
	# point at one company, which is exactly what src/core/law.gd refuses.
	var burden: float = Companies.regulation_burden_of(ns, sector)
	var rule := ""
	if burden > 0.0:
		rule = " · regulated %+.2f" % burden
	elif burden < 0.0:
		rule = " · deregulated %+.2f" % burden
	PanelKit.heading(_body, tr("%s · %.0f bn · %.0f %% named%s") % [
		SECTOR_LABEL.get(sector, sector), sector_output, 100.0 * named, rule,
	])

	_build_investment(ns, sector)

	# A3. The majors own the verbs and the rows; the body is the register's
	# fabric and gets ONE aggregate line plus its five biggest employers as
	# caption lines -- ~80 body firms printed as full rows would bury every
	# major under content that has no verb, and the fold contract needs the
	# panel's primary action (the verbs) above the readout, not under it.
	var majors := []
	var body := []
	for company in firms:
		if Companies.is_major(company):
			majors.append(company)
		else:
			body.append(company)
	_build_body(ns, sector, body)

	for company in majors:
		_build_firm(ns, company)


## A3's body aggregate: one line saying the fabric exists and how much of the
## sector it holds, then the five biggest body employers by headcount -- enough
## to see the tier is real firms with real jobs, not enough to bury the majors.
## The jobs read is the LIVE one (Companies.headcount), the same read the
## majors' rows above use: a body firm's share never moves in 7a, but a
## standing regulation burden scales its compliance factor like anybody's --
## and the PR-46 review measured the authored read diverging 3-10 % from the
## live figure the sim itself consumes, in the same panel as burden-scaled
## major rows. One readout, one time.
func _build_body(ns, sector: String, body: Array) -> void:
	if body.is_empty():
		return
	var share := 0.0
	var jobs := 0.0
	for company in body:
		# The fallback read, same reason as the sector heading above: nothing
		# writes a body entry in 7a, and a register-only read would print the
		# tier's headline line at 0.00 of sector forever -- the A3 review's
		# Critical 1, V1.6d's present-figure-as-zero class.
		share += Companies.share_of_company(ns, company)
		jobs += Companies.headcount(ns, company)
	PanelKit.line(_body, tr("BODY · %d firms · %.2f of sector · %s jobs") % [
		body.size(), share, _thousands(jobs),
	])
	var ranked := body.duplicate()
	var live_jobs := {}
	for company in body:
		live_jobs[company.id] = Companies.headcount(ns, company)
	ranked.sort_custom(func(a, b): return float(live_jobs[a.id]) > float(live_jobs[b.id]))
	for i in mini(5, ranked.size()):
		var company = ranked[i]
		PanelKit.line(_body, tr("  %s · %s jobs") % [
			company.company_name, _thousands(float(live_jobs[company.id])),
		])


## V1.6e's readout and its two verbs, under the sector heading they are pointed at.
##
## THREE FIGURES AND NOT ONE, because they are three different times. The intensity
## is what the treasury is committed to now, the capital is what that has actually
## built, and the shift is what the capital is worth -- and the gap between the
## first and the second IS the lever, since the row asks for money that takes
## several years to arrive. Collapsing them into one progress figure would hide the
## only thing a player has to plan around.
##
## Never silent, and deliberately so: a sector with no programme prints a zero line
## rather than nothing, because an absent row reads as "this sector cannot be
## invested in" and every sector can.
func _build_investment(ns, sector: String) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	var intensity := Investment.intensity_of(ns, sector)
	var capital := Investment.capital_of(ns, sector)
	var shift := float(Investment.sector_trend_shift(ns).get(sector, 0.0))

	var state_label := Label.new()
	if intensity > 0.0:
		state_label.text = tr("State programme %.0f %% · capital %.2f · %+.3f %%/yr to this sector") % [
			100.0 * intensity, capital, shift,
		]
		state_label.theme_type_variation = UiTheme.GOOD_TEXT
	elif capital > 0.0:
		# The withdrawn case, and it needs its own line rather than falling into the
		# one below: the money has stopped and the capital has not gone, which is the
		# half of this model a single "no programme" caption would misreport.
		state_label.text = tr("No programme · capital %.2f depreciating · %+.3f %%/yr to this sector") % [
			capital, shift,
		]
		state_label.theme_type_variation = UiTheme.CAPTION
	else:
		state_label.text = tr("No state programme")
		state_label.theme_type_variation = UiTheme.CAPTION
	block.add_child(state_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	for action in Investment.available(_state, ns, _loader.investment_actions):
		if String(action.effects.get("investment", {}).get("sector", "")) != sector:
			continue
		buttons.add_child(_investment_button(ns, action))
	block.add_child(buttons)

	_body.add_child(block)


func _investment_button(ns, action) -> Button:
	var button := Button.new()
	button.text = action.action_name
	button.tooltip_text = action.summary
	button.pressed.connect(func(): _on_invest(ns, action))
	return button


## U4's contract, `_on_act()`'s shape exactly: the baseline is captured BEFORE the
## command, so the delta measures the month the programme started against the month
## before it.
func _on_invest(ns, action) -> void:
	var before := Budget.snapshot(_state)
	var result := Investment.execute(_state, ns, _loader.investment_actions, action)
	if not result.get("applied", false):
		return
	_dirty = true
	acted.emit(before, action.action_name)


func _build_firm(ns, company) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.text = company.company_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)

	# V4.7b: the SOE chair -- a name on the firm the state part-owns. Reads the
	# register's person id and resolves it against the nation's people; an
	# absent chair is a firm with no appointment, said by silence.
	var chair: String = String(ns.companies.get(company.id, {}).get("board_chair", ""))
	if chair != "":
		var chair_name: String = _loader.person_name(chair)
		PanelKit.line(block, tr("Chair: %s") % (chair_name if chair_name != "" else chair))

	# Two facts about one firm, and both are live state with one writer each -- a
	# subsidy is not an ownership and a player who has done both must see both. Joined
	# on one label rather than given a row apiece, for the reason the figures caption
	# below is one line: eighteen firms across the roster.
	var intensity := Companies.subsidy_of(ns, company.id)
	var held := Companies.state_share_of(ns, company.id)
	var parts: Array[String] = []
	if held > 0.0:
		parts.append("public %.0f %%" % (100.0 * held))
	if intensity > 0.0:
		parts.append("subsidised %.0f %%" % (100.0 * intensity))

	var state_label := Label.new()
	if parts.is_empty():
		state_label.text = tr("private · no support")
		state_label.theme_type_variation = UiTheme.CAPTION
	else:
		state_label.text = " · ".join(parts)
		state_label.theme_type_variation = UiTheme.GOOD_TEXT
	name_row.add_child(state_label)
	block.add_child(name_row)

	# One caption line rather than three rows: revenue, workforce and share are the
	# firm's whole readout and a row each would treble this panel's height for a
	# register that already has eighteen entries across the roster.
	PanelKit.line(block, tr("%.1f bn · %s jobs · %.1f %% of sector") % [
		Companies.output_eur_bn(ns, company),
		_thousands(Companies.headcount(ns, company)),
		100.0 * Companies.share_of(ns, company.id),
	])

	# V1.4c. The price is DERIVED, so it exists nowhere an author could have written
	# it down and the panel is the only place the player can read it before deciding.
	# A button labelled "Nationalisation" with the cost invisible is the fold V1.3e
	# paid for in a different shape: the figure that decides the act, not on screen.
	var money := Label.new()
	var value := Companies.value_eur_bn(ns, company)
	if held > 0.0:
		money.text = tr("worth %.1f bn · %.1f bn held · %.2f bn/yr to the treasury") % [
			value, held * value,
			held * Companies.output_eur_bn(ns, company) * CompaniesK.DIVIDEND_YIELD,
		]
	else:
		money.text = tr("worth %.1f bn") % value
	money.theme_type_variation = UiTheme.CAPTION
	block.add_child(money)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	for action in Companies.available(_state, ns, _loader.company_actions, company.id, _loader):
		buttons.add_child(_action_button(ns, company, action))
	block.add_child(buttons)

	_body.add_child(block)


func _action_button(ns, company, action) -> Button:
	var button := Button.new()
	button.text = action.action_name
	button.tooltip_text = action.summary
	button.pressed.connect(func(): _on_act(ns, company, action))
	if _primary == null and not button.disabled:
		_primary = button
	return button


## The baseline is captured BEFORE the command, so the decision delta measures the
## month the subsidy started against the month before it -- U4's contract, and the
## reason `acted` carries a snapshot rather than a label alone.
func _on_act(ns, company, action) -> void:
	var before := Budget.snapshot(_state)
	var result := Companies.execute(_state, ns, _loader.company_actions, action, company.id, _loader)
	if not result.get("applied", false):
		# The refusal is the panel's to show -- the verb arms' own words. The
		# reason (an exhausted executive pool, no major left to absorb a
		# split) is the sim's, verbatim; a refusal with none reads as refused
		# plainly rather than silently.
		var reason := String(result.get("reason", ""))
		_last_refusal = "%s refused%s" % [action.action_name, " -- %s" % reason if reason != "" else "."]
		_dirty = true
		return
	_last_refusal = ""
	_dirty = true
	acted.emit(before, "%s: %s" % [action.action_name, company.company_name])


func _thousands(value: float) -> String:
	var whole := int(round(value))
	var text := str(absi(whole))
	var out := ""
	while text.length() > 3:
		out = " " + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return ("-" if whole < 0 else "") + text + out


## The control this panel exists to let the player press -- V2.1a's fold contract.
##
## Duck-typed: window_frame.gd asks through has_method(), so a panel with nothing
## to press simply does not implement this and never draws the fold mark. The
## FIRST enabled action is the answer rather than the last, because a panel whose
## first verb has scrolled off is already a panel whose verbs are hidden.
##
## The subsidy button rather than the investment one: V1.6e photographed this
## panel at the top of a body whose three sector rows all read "No state
## programme" while the ledger above them carried a live 0.654 % of GDP, and the
## rows that were out of sight were the firm rows underneath.
func primary_action() -> Control:
	return _primary if is_instance_valid(_primary) else null
