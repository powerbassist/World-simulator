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

signal closed
## (before_snapshot, label) -- the same pair nation_panel.acted and
## law_panel.proposed emit, so a subsidy earns a U4 decision delta on the terms a
## law and a diplomatic action already do.
signal acted(before, label)

const EK = preload("res://src/sim/economy_constants.gd")
const Companies = preload("res://src/sim/companies.gd")
const CompaniesK = preload("res://src/sim/companies_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const SECTOR_LABEL := {
	"agriculture": "Agriculture", "industry": "Industry", "services": "Services",
}

var _state
var _loader
var _dirty := true

var _title: Label
var _body: VBoxContainer
var _close_button: Button


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

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	# The body sits inside a right margin rather than flush to the scroll, because a
	# ScrollContainer draws its bar OVER the content: without this the right-aligned
	# figures in _row() run underneath it, which is what the first captured frame
	# showed for all three ledger values. A vertical bar is ~10px, and this panel is
	# the one surface in the game whose content is guaranteed to overflow.
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 14)
	scroll.add_child(gutter)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	gutter.add_child(_body)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


func hide_close_button() -> void:
	_close_button.hide()


func _process(_delta: float) -> void:
	if not _dirty or not visible or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return

	_title.text = "The private sector"

	for child in _body.get_children():
		child.queue_free()

	if ns.companies.is_empty():
		# Reachable: a nation with no data/companies/<ID>.json has unpartitioned
		# sectors, which is a supported state rather than a hole. Said plainly, so
		# the player of a nation whose register has not been authored yet sees a
		# reason rather than an empty window.
		_header("No register")
		_line("No firms are named for this nation. Its sectors are modelled in aggregate.")
		return

	_build_ledger(ns)
	for sector in EK.SECTOR_TREND.keys():
		_build_sector(ns, String(sector))


## The three figures the register produces, in one place. Both deviation channels
## read exactly 0.0 until a subsidy stands, so a player who has never subsidised
## anybody sees three zeroes -- which is the honest readout and not a bug.
func _build_ledger(ns) -> void:
	_header("The public cost")
	_row("Subsidy bill", "%.3f %% of GDP" % ns.subsidy_bill_pct_gdp)
	_row("Growth effect", "%+.3f %%/yr" % ns.firm_impulse_pct)
	# Signed the way the player reads it -- jobs, not unemployment points -- because
	# the stored figure is an offset ADDED to structural unemployment and a positive
	# number there is bad news. Flipping it here rather than storing it flipped keeps
	# economy.gd's sum readable.
	_row("Jobs effect", "%+.3f pts unemployment" % ns.firm_jobs_offset_pct)


func _build_sector(ns, sector: String) -> void:
	var firms := Companies.firms_in_sector(_loader, ns.id, sector)
	if firms.is_empty():
		return

	var sector_output: float = float(ns.sector_output.get(sector, 0.0))
	var named := 0.0
	for company in firms:
		named += Companies.share_of(ns, company.id)
	_header("%s · %.0f bn · %.0f %% named" % [
		SECTOR_LABEL.get(sector, sector), sector_output, 100.0 * named,
	])

	for company in firms:
		_build_firm(ns, company)


func _build_firm(ns, company) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.text = company.company_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)

	var intensity := Companies.subsidy_of(ns, company.id)
	var state_label := Label.new()
	if intensity > 0.0:
		state_label.text = "subsidised %.0f %%" % (100.0 * intensity)
		state_label.theme_type_variation = UiTheme.GOOD_TEXT
	else:
		state_label.text = "no support"
		state_label.theme_type_variation = UiTheme.CAPTION
	name_row.add_child(state_label)
	block.add_child(name_row)

	# One caption line rather than three rows: revenue, workforce and share are the
	# firm's whole readout and a row each would treble this panel's height for a
	# register that already has eighteen entries across the roster.
	var figures := Label.new()
	figures.text = "%.1f bn · %s jobs · %.1f %% of sector" % [
		Companies.output_eur_bn(ns, company),
		_thousands(Companies.headcount(ns, company)),
		100.0 * Companies.share_of(ns, company.id),
	]
	figures.theme_type_variation = UiTheme.CAPTION
	block.add_child(figures)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	for action in Companies.available(_state, ns, _loader.company_actions, company.id):
		buttons.add_child(_action_button(ns, company, action))
	block.add_child(buttons)

	_body.add_child(block)


func _action_button(ns, company, action) -> Button:
	var button := Button.new()
	button.text = action.action_name
	button.tooltip_text = action.summary
	button.pressed.connect(func(): _on_act(ns, company, action))
	return button


## The baseline is captured BEFORE the command, so the decision delta measures the
## month the subsidy started against the month before it -- U4's contract, and the
## reason `acted` carries a snapshot rather than a label alone.
func _on_act(ns, company, action) -> void:
	var before := Budget.snapshot(_state)
	var result := Companies.execute(_state, ns, _loader.company_actions, action, company.id)
	if not result.get("applied", false):
		return
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


func _header(text: String) -> void:
	var label := Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = UiTheme.MICRO
	_body.add_child(label)


func _line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = UiTheme.CAPTION
	_body.add_child(label)


func _row(left: String, right: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var key := Label.new()
	key.text = left
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.theme_type_variation = UiTheme.CAPTION
	row.add_child(key)

	var value := Label.new()
	value.text = right
	row.add_child(value)

	_body.add_child(row)
