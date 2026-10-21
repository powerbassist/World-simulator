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
const Pledges = preload("res://src/sim/pledges.gd")
const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const ElectionK = preload("res://src/sim/election_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")

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

## The promisable fields as a player thinks of them. Beside BLOC_LABEL for its reason:
## src/sim/pledges_constants.gd keys on the bare field names and carries no display
## text, because a constants file naming things in English is a constants file the
## content has to agree with in two places.
const FIELD_LABEL := {
	"unemployment_pct": "Unemployment",
	"deficit_pct_gdp": "The deficit",
	"debt_to_gdp_pct": "The debt",
	"growth_annual_pct": "Growth",
	"unrest_pct": "Unrest",
	"tax_income_pct": "Income tax",
	"tax_corporate_pct": "Corporation tax",
	"tax_vat_pct": "VAT",
	"tax_capital_gains_pct": "Capital gains tax",
	"tax_wealth_pct": "The wealth tax",
	"spending_health_pct_gdp": "Health spending",
	"spending_education_pct_gdp": "Education spending",
	"spending_defence_pct_gdp": "Defence spending",
	"spending_pensions_pct_gdp": "Pension spending",
	"spending_infrastructure_pct_gdp": "Infrastructure spending",
}

var _state
var _loader
var _dirty := true
## The region the next meeting month is held in -- the player's choice, and the whole
## of V2.6b2's verb: start buttons stay disabled until one is picked, because a
## place-less start is refused by Campaign.execute() and a UI that let one through
## would be a button that silently does nothing. Persists across refreshes.
var _site_region := ""
## projects_panel.gd's device, and this panel has BOTH halves for a reason V1.7a
## recorded: --campaign wants the ledger at the TOP and --pledge wants the promises at
## the BOTTOM, so the scroll is per-flag rather than per-panel. V1.6e's correction has
## a direction as well as a subject.
var _pin_bottom := false

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

## The first enabled verb this panel built on its last refresh. See primary_action().
var _primary: Control = null


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
	# PanelKit.row() would run underneath it. companies_panel.gd's first captured frame is what
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
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


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

	_title.text = tr("Campaign")

	for child in _body.get_children():
		child.queue_free()

	_build_clock(ns)
	_build_turnout(ns)
	_build_running(ns)
	_build_site(ns)
	_build_available(ns)
	# V1.7b, BELOW the campaign rather than in a window of its own: a promise is made
	# in the run-up, so it belongs in the surface that runs the run-up. And below
	# rather than above, because what a player opens this panel for outside a run-up
	# is the months-to-the-vote line at the top -- which is the half V1.7a's own
	# screenshot pass found scrolled off the frame.
	_build_promises(ns)

	if _pin_bottom:
		_apply_bottom()


## How long there is, and what the campaign is costing. The first thing on the panel
## because it is the only thing that is true outside a run-up, and because the whole
## lever is a decision about TIMING: start early and buy more at more, start late and
## buy less at less.
func _build_clock(ns) -> void:
	PanelKit.heading(_body, tr("The vote"))
	var months := Campaign.months_to_election(_state, ns)
	if months < 0:
		PanelKit.line(_body, tr("No vote is scheduled."))
		return

	PanelKit.row(_body, tr("Months to the vote"), "%d" % months)
	if Campaign.is_open(_state, ns):
		PanelKit.row(_body, tr("Campaign bill"), tr("%.3f %% of GDP") % ns.campaign_bill_pct_gdp)
		PanelKit.line(_body, 
			"The run-up is open. Every effort in the field reaches more voters each"
			+ " month it runs and costs its price each month it runs, and all of it"
			+ " ends at the vote whatever happens."
		)
	else:
		PanelKit.line(_body, 
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
	PanelKit.heading(_body, tr("Expected turnout"))
	var moved := false
	for bloc in OpinionK.BLOC_KEYS:
		var base: float = float(ElectionK.BLOC_TURNOUT[bloc])
		var now: float = Campaign.turnout_of(ns, bloc)
		var delta: float = now - base
		if not is_zero_approx(delta):
			moved = true
		PanelKit.row(_body, 
			String(BLOC_LABEL.get(bloc, bloc)),
			"%.1f %%   %s" % [now * 100.0, "—" if is_zero_approx(delta) else "%+.1f" % (delta * 100.0)],
		)
	if not moved:
		PanelKit.line(_body, tr("Nobody has been mobilised. These are the figures an ordinary election gets."))


func _build_running(ns) -> void:
	var live := Campaign.running(ns)
	if live.is_empty():
		return
	PanelKit.heading(_body, tr("In the field"))
	for eid in live:
		_build_live(ns, String(eid))


func _build_live(ns, effort_id: String) -> void:
	var terms := Campaign.terms_of(_loader, effort_id)
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	PanelKit.line(block, Campaign.name_of(_loader, effort_id), PanelKit.Tone.PLAIN)

	PanelKit.line(block, tr("%.3f %% of GDP a year · %s") % [
		float(terms.get("cost_pct_gdp", 0.0)), _reach_text(terms),
	], PanelKit.Tone.GOOD)

	PanelKit.line(block, _site_text(ns, effort_id), PanelKit.Tone.PLAIN)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	for action in Campaign.available(_state, ns, _loader.campaign_actions):
		if String(action.effects.get("campaign", {}).get("effort_id", "")) != effort_id:
			continue
		buttons.add_child(_button(ns, action))
	block.add_child(buttons)

	_body.add_child(block)


## Where the next meeting month is held. V2.6b2's, and it sits between the field and
## the offers because it prices BOTH: the running effort reads its site's factor here
## and so does every start button below, which is why the buttons stay disabled until
## a region is picked. No default -- a defaulted site would silently ship the capital's
## dominance as the model's answer rather than the player's choice.
func _build_site(ns) -> void:
	PanelKit.heading(_body, tr("Meetings in"))
	var picker := OptionButton.new()
	var region_ids: Array = []
	for region in _loader.regions.get(ns.id, []):
		region_ids.append(String(region.id))
		picker.add_item("%s — %s" % [region.region_name, Campaign.site_city_name(_loader, ns, String(region.id))])
	var selected := region_ids.find(_site_region)
	picker.select(selected)
	picker.item_selected.connect(func(idx: int): _site_region = String(region_ids[idx]); _dirty = true)
	_body.add_child(picker)

	if _site_region == "":
		PanelKit.line(_body,
			"Choose where the meetings are held. Reach falls with the journey's travel" +
			" days, and a region already spoken to gives less the second time.")
		return
	var days := Campaign.travel_days_to(ns, _loader, _site_region)
	PanelKit.line(_body, tr("%d day%s' travel · reach ×%.2f a month · %d%% spoken to") % [
		days, "" if days == 1 else "s",
		Campaign.factor_of(ns, _loader, _site_region),
		roundi(Campaign.spoken(ns, _site_region) * 100.0),
	])


## The running effort's site line -- where the president is, and how spoken-out the
## place is. THE FACTOR IS DELIBERATELY NOT PRINTED HERE: the register reads after the
## month's tick, when the meeting has just re-spoken the region to its clamp, so
## factor_of() returns the discount a HYPOTHETICAL extra meeting would get and not
## what this month delivered -- the first frame printed "×0.00 this month" against a
## month that had delivered a tenth of fresh, a true number wearing a lying label.
## The spoken-to percentage is the decision-bearing fact: high means the tour should
## move, and the picker's own readout prices any move the player is weighing.
func _site_text(ns, effort_id: String) -> String:
	var site := Campaign.site_of(ns, effort_id)
	if site == "":
		return "no meetings on the schedule -- the effort is reaching nobody"
	var city := Campaign.site_city_name(_loader, ns, site)
	var days := Campaign.travel_days_to(ns, _loader, site)
	return "meeting in %s (%s) · %d day%s · %d%% spoken to" % [
		_region_name(ns, site), city, days, "" if days == 1 else "s",
		roundi(Campaign.spoken(ns, site) * 100.0),
	]


func _region_name(ns, region_id: String) -> String:
	for region in _loader.regions.get(ns.id, []):
		if String(region.id) == region_id:
			return String(region.region_name)
	return region_id


## Everything that could be put in the field now. Outside the run-up
## Campaign.available() returns nothing structurally, so this section prints the FIVE
## anyway with their prices and no buttons -- a player planning a campaign four years
## out needs to know what it will cost, and a panel that showed a blank list until June
## would be the decorative axis docs/scenario-model.md records.
func _build_available(ns) -> void:
	PanelKit.heading(_body, tr("Efforts"))
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

	PanelKit.line(block, String(terms.get("effort_name", "")), PanelKit.Tone.PLAIN)

	PanelKit.line(block, tr("%.3f %% of GDP a year · %s") % [
		float(terms.get("cost_pct_gdp", 0.0)), _reach_text(terms),
	])

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
	if String(action.effects.get("campaign", {}).get("op", "")) == "start" and _site_region == "":
		button.disabled = true
		button.tooltip_text = tr("choose where the meetings are held first")
	button.pressed.connect(func(): _on_act(ns, action))
	if _primary == null and not button.disabled:
		_primary = button
	return button


## U4's contract, projects_panel._on_act()'s shape exactly: the baseline is captured
## BEFORE the command, so the delta measures the month the effort began against the
## month before it.
func _on_act(ns, action) -> void:
	var before := Budget.snapshot(_state)
	var result := Campaign.execute(_state, ns, _loader.campaign_actions, action, _site_region)
	if not result.get("applied", false):
		return
	_dirty = true
	acted.emit(before, action.action_name)


# --- Campaign promises (V1.7b) ---------------------------------------------------------

## What is on the books, and what it is costing. Printed whether or not anything is
## promised, for _build_available()'s reason: a player planning a run-up needs to know
## what a promise will cost before the window opens.
##
## THE HEADLINE FIGURE IS MONTHS BROKEN AND NOT A SCORE, because that is what the model
## charges on. src/sim/pledges.gd judges a promise every month it is live and the price
## is the integral, so "broken 14 of 32 months" IS the bill in the units it was rung up
## in -- docs/projects-model.md's months-remaining rule, which is that a panel must not
## print a second unit for a fact the model already has one for.
func _build_promises(ns) -> void:
	PanelKit.heading(_body, tr("Promises"))

	_build_programme(ns)

	var books: Array = Pledges.on_the_books(ns)
	if books.is_empty():
		PanelKit.line(_body, 
			"Nothing has been promised. A promise is made in the run-up and binds the"
			+ " whole of the term it wins: the blocs that want to hear it pay you for"
			+ " saying it now, and every month it stands broken costs you more."
		)
	for entry in books:
		_build_promise_row(ns, entry)

	var offered := Pledges.available(_state, ns, _loader.pledges)
	for action in _loader.pledges:
		var terms: Dictionary = action.effects.get("pledge", {})
		if Pledges.has_pledged(ns, String(terms.get("pledge_id", ""))):
			continue
		_build_promise_offer(ns, action, terms, offered.has(action))


## The term's programme as a READ-ONLY line, docs/programme-model.md section 4's
## mitigation: pledges and programmes are kept apart, but "apart" must not rot
## into two lists the player reconciles by hand -- so the Promises section opens
## on the programme, read through the same Programme.this_term() /
## progress_of() / PanelKit.progress_fraction() trio the Agenda and the Overview
## read. Never a second answer to one read, and never a write: the choice
## happens on the Agenda or nowhere. A concluded entry prints its verdict rather
## than a fraction -- a bar over a delivered programme would be a lie about a
## term that is already priced.
func _build_programme(ns) -> void:
	var this_term: Array = Programme.this_term(ns)
	if this_term.is_empty():
		if Programme.is_term_start(ns):
			PanelKit.line(_body, tr("The term's programme is unset -- the Agenda (K) holds the offer."), PanelKit.Tone.DIM)
		else:
			PanelKit.line(_body, tr("No programme was set this term."), PanelKit.Tone.DIM)
		return
	for entry in this_term:
		var terms: Dictionary = Programme.terms_of(_loader, String(entry["entry_id"]))
		if terms.is_empty():
			# Content the loader no longer defines: the id stands in rather
			# than a bar over nothing, agenda_panel.gd's rule.
			PanelKit.line(_body, tr("%s -- the content behind it is gone; it concludes on the next tick.") % String(entry["entry_id"]), PanelKit.Tone.DIM)
			continue
		var name_text := String(terms["name"])
		match String(entry["status"]):
			ProgrammeK.STATUS_ACTIVE:
				var read: Dictionary = Programme.progress_of(ns, terms)
				var fraction: float = PanelKit.progress_fraction(
					float(read["current_value"]), float(read["goal_value"]), String(read["progressbar"]))
				PanelKit.line(_body, tr("%s · %.2f now against a %.2f goal · %d%% there") % [
					name_text, float(read["current_value"]), float(read["goal_value"]), roundi(fraction * 100.0),
				], PanelKit.Tone.PLAIN)
			ProgrammeK.STATUS_COMPLETE:
				PanelKit.line(_body, tr("%s · Delivered.") % name_text, PanelKit.Tone.GOOD)
			ProgrammeK.STATUS_FAIL:
				PanelKit.line(_body, tr("%s · Missed.") % name_text, PanelKit.Tone.BAD)
			_:
				PanelKit.line(_body, tr("%s · Overtaken by the world.") % name_text, PanelKit.Tone.DIM)


func _build_promise_row(ns, entry: Dictionary) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	PanelKit.line(block, Pledges.name_of(_loader, String(entry["pledge_id"])), PanelKit.Tone.PLAIN)

	var live: bool = Pledges.is_live(_state, entry)
	var broken: bool = live and Pledges.in_breach(_state, ns, entry)

	var state_label := Label.new()
	if not live:
		state_label.text = tr("%s · binds the term beginning %02d/%04d") % [
			_promise_text(entry), int(entry["from_month"]), int(entry["from_year"])]
		state_label.theme_type_variation = UiTheme.CAPTION
	else:
		# THE COST SO FAR, and the first captured frame is what added it. Without it the
		# row read "broken 14 of 14 months" against a player who could see the per-month
		# price on the OFFERS below and had no way to read what the promise they had
		# already made was costing -- the one figure this section exists to be a ledger
		# of. docs/projects-model.md's months-remaining rule from the other side: the
		# count is the unit the model charges in, and the total is what the count is for.
		state_label.text = tr("%s · %s · broken %d of %d months, %.2f approval") % [
			_promise_text(entry),
			"BEING BROKEN" if broken else "being kept",
			int(entry["breach_months"]), int(entry["months_live"]),
			-_charged_so_far(entry),
		]
		state_label.theme_type_variation = UiTheme.BAD_TEXT if broken else UiTheme.GOOD_TEXT
	block.add_child(state_label)

	_body.add_child(block)


func _build_promise_offer(ns, action, terms: Dictionary, can_act: bool) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	PanelKit.line(block, String(terms.get("pledge_name", "")), PanelKit.Tone.PLAIN)

	PanelKit.line(block, "%s · %s" % [
		_promise_text({"field": terms.get("field", ""), "op": terms.get("op", ""), "value": terms.get("value", 0.0)}),
		_breach_text(terms),
	])

	if can_act:
		block.add_child(_pledge_button(ns, action))

	_body.add_child(block)


## The promise itself, in the words a president would use rather than in the register's
## {field, op, value}. Campaign.name_of()'s argument about the noun, one level down: the
## triple is what the model compares and it is not what anybody says out loud.
func _promise_text(entry: Dictionary) -> String:
	var value: float = float(entry.get("value", 0.0))
	var bound: String = "no more than" if String(entry.get("op", "")) == "<=" else "no less than"
	return "%s %s %s" % [FIELD_LABEL.get(String(entry.get("field", "")), String(entry.get("field", ""))), bound, _field_value(String(entry.get("field", "")), value)]


func _field_value(field: String, value: float) -> String:
	if field.begins_with("tax_") or field.begins_with("spending_"):
		return "%.1f %%" % value
	if field == "debt_to_gdp_pct" or field == "deficit_pct_gdp":
		return "%.1f %% of GDP" % value
	return "%.1f %%" % value


## What standing broken costs, per month, in the same points of approval every other
## bloc figure on this shell is printed in.
func _breach_text(terms: Dictionary) -> String:
	var offsets: Dictionary = terms.get("breach_offset", {})
	var parts: Array[String] = []
	for bloc in OpinionK.BLOC_KEYS:
		if not offsets.has(bloc):
			continue
		parts.append("%s %.2f" % [
			String(BLOC_LABEL.get(bloc, bloc)),
			-float(offsets[bloc]) * OpinionK.APPROVAL_SPAN,
		])
	if parts.is_empty():
		return "costs nothing to break"
	# Signed and with the unit named ONCE at the end. The first captured frame printed
	# "a month broken: Pensioners 0.14, Rural 0.10" -- four bare numbers in no unit,
	# against an effort row two lines above printing points of TURNOUT in the same shape.
	return "each month broken: " + ", ".join(parts) + " approval"


## What a promise has taken off the headline so far, in points of approval: the months
## it has stood broken times what one such month costs, rolled up over the blocs it
## names by their own BLOC_SIZE shares.
##
## Derived rather than stored, which is why the register has no accumulator for it: the
## breach rates are CONTENT and the count is the state, so a stored total would be one
## quantity with two writers and would put the ladder in the save file.
func _charged_so_far(entry: Dictionary) -> float:
	var offsets: Dictionary = Pledges.terms_of(_loader, String(entry["pledge_id"])).get("breach_offset", {})
	var per_month := 0.0
	for bloc in offsets:
		per_month += float(offsets[bloc]) * OpinionK.APPROVAL_SPAN * float(OpinionK.BLOC_SIZE.get(bloc, 0.0))
	return per_month * float(entry["breach_months"])

func _pledge_button(ns, action) -> Button:
	var button := Button.new()
	button.text = action.action_name
	button.tooltip_text = action.summary
	button.pressed.connect(func(): _on_promise(ns, action))
	if _primary == null and not button.disabled:
		_primary = button
	return button


func _on_promise(ns, action) -> void:
	var before := Budget.snapshot(_state)
	var result := Pledges.execute(_state, ns, _loader.pledges, action)
	if not result.get("applied", false):
		return
	_dirty = true
	acted.emit(before, action.action_name)


## The control this panel exists to let the player press -- V2.1a's fold contract,
## declared here at V2.1b.
##
## An effort and a promise are both verbs and the effort ladder is built first, so
## the first enabled button in build order is an effort while the window is open
## and a promise once every effort is running. Null outside the run-up, when the
## panel is a ledger of what a campaign cost.
func primary_action() -> Control:
	return _primary
