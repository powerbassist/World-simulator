extends PanelContainer

## The campaign -- V1.7a's one new surface.
##
## Reads simulation state and content, and writes neither: the verb goes back as an
## explicit command through `acted`, which is the shape Budget.commit() set and
## projects_panel.gd follows.
##
## IT IS ITS OWN WINDOW AND NOT ROWS ON THE POLLING PANEL, which is the closer
## thematic fit and the wrong one. That panel's contract is that EVERY figure on it
## has been through src/ui/poll_noise.gd, because a published poll must not be
## readable as the truth underneath it -- and a mobilisation figure is not a poll. The
## government knows exactly what it is paying for and exactly who it has reached.
## docs/society-model.md section 11 moved the delivery readout off that panel for the
## identical reason one block earlier.
##
## THE WHOLE BODY SCROLLS FROM THE FIRST LINE, companies_panel.gd's and
## projects_panel.gd's answer to the fold nation_panel.gd has paid for three times.
##
## IT IS NEVER EMPTY AND NEVER SILENT, which is the opposite call from the overview's
## delivery lines and is made for a different reason. A campaign panel is a surface
## the player will open OUTSIDE a run-up -- that is when they are planning one -- and a
## window that said nothing until the window opened would look broken at exactly the
## moment it is being consulted. So it always prints how far away the vote is and what
## the run-up will offer when it arrives.

signal closed
## (before_snapshot, label) -- the same pair projects_panel.acted,
## companies_panel.acted, nation_panel.acted and law_panel.proposed emit, so putting an
## effort in the field earns a U4 decision delta on the terms a build and a law already
## do.
signal acted(before, label)

const Campaign = preload("res://src/sim/campaign.gd")
const CampaignK = preload("res://src/sim/campaign_constants.gd")
const ElectionK = preload("res://src/sim/election_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## The six blocs as a player thinks of them. election_constants.gd and
## opinion_constants.gd both key on the bare ids and neither carries a display name;
## polling_panel.gd capitalises them in place, which is what this follows.
const BLOC_LABEL := {
	"workers": "Workers",
	"pensioners": "Pensioners",
	"urban": "Urban",
	"rural": "Rural",
	"business": "Business",
	"students": "Students",
}

var _state
var _loader
var _dirty := true

var _title: Label
var _body: VBoxContainer
## Kept rather than left local for the SHAPE projects_panel.gd needs it for, and this
## panel deliberately does NOT get that panel's scroll_to_bottom(): --campaign's first
## frame pinned to the bottom and put the months-to-the-vote and the campaign bill --
## the two figures the flag exists to check against the budget panel's own campaign
## line -- off the frame entirely, opening on a sentence cut in half. The top of this
## panel is its ledger, so the flag leaves the scroll where it starts.
var _scroll: ScrollContainer
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

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	# The body sits inside a right margin rather than flush to the scroll, because a
	# ScrollContainer draws its bar OVER the content and the right-aligned figures in
	# _row() would run underneath it. companies_panel.gd's first captured frame is what
	# found that; inherited rather than rediscovered a third time.
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 14)
	_scroll.add_child(gutter)

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

	_title.text = "Campaign"

	for child in _body.get_children():
		child.queue_free()

	_build_clock(ns)
	_build_turnout(ns)
	_build_running(ns)
	_build_available(ns)


## How long there is, and what the campaign is costing. The first thing on the panel
## because it is the only thing that is true outside a run-up, and because the whole
## lever is a decision about TIMING: start early and buy more at more, start late and
## buy less at less.
func _build_clock(ns) -> void:
	_header("The vote")
	var months := Campaign.months_to_election(_state, ns)
	if months < 0:
		_line("No vote is scheduled.")
		return

	_row("Months to the vote", "%d" % months)
	if Campaign.is_open(_state, ns):
		_row("Campaign bill", "%.3f %% of GDP" % ns.campaign_bill_pct_gdp)
		_line(
			"The run-up is open. Every effort in the field reaches more voters each"
			+ " month it runs and costs its price each month it runs, and all of it"
			+ " ends at the vote whatever happens."
		)
	else:
		_line(
			"The run-up opens %d months from now, %d months before the vote. Nothing"
			% [months - CampaignK.CAMPAIGN_WINDOW_MONTHS, CampaignK.CAMPAIGN_WINDOW_MONTHS]
			+ " can be put in the field until then."
		)


## Who is going to turn out, bloc by bloc, against who would have without a campaign.
##
## THE LEVEL AND THE DEVIATION ON ONE ROW, because either alone is unreadable: the
## level with no baseline says nothing about what the money bought, and the deviation
## with no level says nothing about how much room is left. Pensioners at 0.82 and
## students at 0.45 have very different room, and that asymmetry is the model rather
## than a table -- see Campaign.turnout_of().
func _build_turnout(ns) -> void:
	_header("Expected turnout")
	var moved := false
	for bloc in OpinionK.BLOC_KEYS:
		var base: float = float(ElectionK.BLOC_TURNOUT[bloc])
		var now: float = Campaign.turnout_of(ns, bloc)
		var delta: float = now - base
		if not is_zero_approx(delta):
			moved = true
		_row(
			String(BLOC_LABEL.get(bloc, bloc)),
			"%.1f %%   %s" % [now * 100.0, "—" if is_zero_approx(delta) else "%+.1f" % (delta * 100.0)],
		)
	if not moved:
		_line("Nobody has been mobilised. These are the figures an ordinary election gets.")


func _build_running(ns) -> void:
	var live := Campaign.running(ns)
	if live.is_empty():
		return
	_header("In the field")
	for eid in live:
		_build_live(ns, String(eid))


func _build_live(ns, effort_id: String) -> void:
	var terms := Campaign.terms_of(_loader, effort_id)
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	name_label.text = Campaign.name_of(_loader, effort_id)
	block.add_child(name_label)

	var state_label := Label.new()
	state_label.text = "%.3f %% of GDP a year · %s" % [
		float(terms.get("cost_pct_gdp", 0.0)), _reach_text(terms),
	]
	state_label.theme_type_variation = UiTheme.GOOD_TEXT
	block.add_child(state_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	for action in Campaign.available(_state, ns, _loader.campaign_actions):
		if String(action.effects.get("campaign", {}).get("effort_id", "")) != effort_id:
			continue
		buttons.add_child(_button(ns, action))
	block.add_child(buttons)

	_body.add_child(block)


## Everything that could be put in the field now. Outside the run-up
## Campaign.available() returns nothing structurally, so this section prints the FIVE
## anyway with their prices and no buttons -- a player planning a campaign four years
## out needs to know what it will cost, and a panel that showed a blank list until June
## would be the decorative axis docs/scenario-model.md records.
func _build_available(ns) -> void:
	_header("Efforts")
	var live: Array = Campaign.running(ns)
	var offered := Campaign.available(_state, ns, _loader.campaign_actions)

	for action in _loader.campaign_actions:
		var terms: Dictionary = action.effects.get("campaign", {})
		if String(terms.get("op", "")) != "start":
			continue
		if live.has(String(terms.get("effort_id", ""))):
			continue
		_build_offer(ns, action, terms, offered.has(action))


func _build_offer(ns, action, terms: Dictionary, can_act: bool) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	name_label.text = String(terms.get("effort_name", ""))
	block.add_child(name_label)

	var terms_label := Label.new()
	terms_label.text = "%.3f %% of GDP a year · %s" % [
		float(terms.get("cost_pct_gdp", 0.0)), _reach_text(terms),
	]
	terms_label.theme_type_variation = UiTheme.CAPTION
	block.add_child(terms_label)

	if can_act:
		block.add_child(_button(ns, action))

	_body.add_child(block)


## Who an effort reaches and how hard, per month, in the units the turnout rows above
## are printed in rather than in the log-odds the register holds. A player should never
## have to read a log-odds shift, and a panel printing one would be two units for one
## fact -- docs/projects-model.md's months-remaining rule.
##
## Measured at the bloc's OWN baseline, because the same shift is worth more to a bloc
## with more room: +0.06 a month is +1.4 points to students and +0.9 to pensioners, and
## the whole point of the log-odds form is that the model says so without a table.
func _reach_text(terms: Dictionary) -> String:
	var mobilisation: Dictionary = terms.get("mobilisation", {})
	var parts: Array[String] = []
	for bloc in OpinionK.BLOC_KEYS:
		if not mobilisation.has(bloc):
			continue
		var base: float = float(ElectionK.BLOC_TURNOUT[bloc])
		var odds: float = base / (1.0 - base) * exp(float(mobilisation[bloc]))
		var moved: float = odds / (1.0 + odds) - base
		parts.append("%s %+.1f" % [String(BLOC_LABEL.get(bloc, bloc)), moved * 100.0])
	if parts.is_empty():
		return "reaches nobody"
	return "a month: " + ", ".join(parts)


func _button(ns, action) -> Button:
	var button := Button.new()
	button.text = action.action_name
	button.tooltip_text = action.summary
	button.pressed.connect(func(): _on_act(ns, action))
	return button


## U4's contract, projects_panel._on_act()'s shape exactly: the baseline is captured
## BEFORE the command, so the delta measures the month the effort began against the
## month before it.
func _on_act(ns, action) -> void:
	var before := Budget.snapshot(_state)
	var result := Campaign.execute(_state, ns, _loader.campaign_actions, action)
	if not result.get("applied", false):
		return
	_dirty = true
	acted.emit(before, action.action_name)


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
