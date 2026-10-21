extends PanelContainer

## The Overview tab -- U3. Rewritten from the U2 placeholder, which was six
## unranked lines re-hosted from the old HUD.
##
## This tab answers one question -- "what matters most right now" -- and it is
## the default tab, so it is the first thing a player reads. That makes ranking
## the whole design: one lead sentence saying the single most pressing thing,
## then four columns each answering a different question, and deliberately no
## GDP, population, sector output or debt level. Those are one click away on
## Economy and none of them is something the player acts on this month.
##
## Reads state and never writes it (engine-decision.md Rule 2). Government's
## censure resolution is called as a probe: resolve_censure() is pure, and
## government_panel.gd already reads it the same way.

const Defence = preload("res://src/sim/defence.gd")
const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const Society = preload("res://src/sim/society.gd")
const SocietyK = preload("res://src/sim/society_constants.gd")
const Government = preload("res://src/sim/government.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")
const Trends = preload("res://src/ui/trends.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")

const MONTH_NAMES: Array[String] = [
	"January", "February", "March", "April", "May", "June",  # i18n: msgid
	"July", "August", "September", "October", "November", "December",  # i18n: msgid
]

## An election closer than this is the story, whatever else is happening.
const ELECTION_URGENT_MONTHS := 6

## Two issues, not four. Society shows the full ranking; the point here is that
## the player leaves with the two they could not afford to have missed.
const TOP_ISSUE_COUNT := 2

## Satisfaction is a [-1, +1] score. Anything inside this band reads as neither
## pleased nor angry, and is shown as such rather than as a number the player has
## no scale for.
const SATISFACTION_BAND := 0.15

## How many past decisions the recent-effects region shows -- U4. A fifth
## region under the four-column row, not a fifth column: the row is already at
## four across 1130px, and a decision log reads better as full-width lines than
## squeezed into the same column width as GOVERNMENT or NEXT ELECTION.
const RECENT_EFFECTS_SHOWN := 5

## Per decision, how many of its moved figures get a line -- the worst-movers,
## not every WATCHED figure, the same "lead with what matters" reasoning as the
## rest of this tab.
const EFFECT_FIGURES_SHOWN := 2

## Which watched figure the electorate would blame on which issue, used only to
## decide whether the lead sentence can name an issue alongside the movement.
## Approval is deliberately absent: falling approval IS the electorate, so
## "approval is down and approval is what people care about" says nothing.
const ISSUE_FOR_FIGURE := {
	"unemployment_pct": "jobs",
	"growth_annual_pct": "growth",
	"deficit_pct_gdp": "public_finances",
	"debt_to_gdp_pct": "public_finances",
}

var _state
var _loader
var _title: Label
var _lead: Label
var _columns := {}   # id -> VBoxContainer holding that column's rebuilt body
var _programme_box: VBoxContainer
var _effects_box: VBoxContainer
var _dirty := true


func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_title = Label.new()
	_title.text = tr("OVERVIEW")
	_title.theme_type_variation = UiTheme.HEADING
	root.add_child(_title)

	_lead = Label.new()
	_lead.theme_type_variation = UiTheme.LEAD
	_lead.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_lead)

	root.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	for spec in [
		["government", tr("GOVERNMENT")],
		["election", tr("NEXT ELECTION")],
		["issues", tr("WHAT THE COUNTRY WANTS")],
		["moving", tr("MOVING, LAST %d MONTHS") % Trends.TREND_MONTHS],
	]:
		# PanelKit.section() IS this panel's column: a tracked heading, a body under
		# it at the kit's own separations, and the body handed back. The four
		# separations and both variations were already identical -- the only line
		# _build_column() had that section() does not is size_flags_vertical =
		# SIZE_FILL, which is a Control's default.
		_columns[spec[0]] = PanelKit.section(row, spec[1])

	root.add_child(HSeparator.new())

	# V4.1. The term's programme, full width UNDER the four columns rather than
	# as a fifth: the row is already at four across 1130px (the finding that
	# kept RECENT DECISIONS out of it), and a list of goals reads as lines.
	_programme_box = VBoxContainer.new()
	_programme_box.add_theme_constant_override("separation", 4)

	var programme_heading := Label.new()
	programme_heading.text = tr("PROGRAMME")
	programme_heading.theme_type_variation = UiTheme.HEADING
	root.add_child(programme_heading)
	root.add_child(_programme_box)

	root.add_child(HSeparator.new())

	var effects_heading := Label.new()
	effects_heading.text = tr("RECENT DECISIONS")
	effects_heading.theme_type_variation = UiTheme.HEADING
	root.add_child(effects_heading)

	_effects_box = VBoxContainer.new()
	_effects_box.add_theme_constant_override("separation", 4)
	root.add_child(_effects_box)


## Takes the loader as well as the state, the same shape government_panel.gd
## uses: the censure probe needs the nation's party list, which lives in data
## rather than on the nation state.
func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


func mark_dirty() -> void:
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

	var nation = _loader.nations.get(ns.id) if _loader != null else null
	_title.text = tr("OVERVIEW — %s%s") % [
		nation.nation_name if nation != null else ns.id, _start_suffix(),
	]

	for body in _columns.values():
		for child in body.get_children():
			child.queue_free()
	for child in _programme_box.get_children():
		child.queue_free()
	for child in _effects_box.get_children():
		child.queue_free()

	var censure := _censure_probe(ns)
	# One source (Trends.vote_date): the executive clock where the nation has
	# one, the assembly's otherwise -- the same query the top bar's next-vote
	# figure counts by. Closes decision-log U3.
	var vote := Trends.vote_date(ns)
	var months_to_election := Trends.months_to_vote(_state, ns)
	var satisfaction := Opinion.issue_satisfaction(ns)
	var top := Opinion.top_issues(ns, TOP_ISSUE_COUNT)
	var movements := Trends.movements(_state)
	var worst := Trends.worst(_state)

	_lead.text = _lead_text(ns, censure, months_to_election, top, worst)

	_fill_government(ns, censure)
	_fill_defence(ns)
	_fill_services(ns)
	_fill_press(ns)
	_fill_election(ns, months_to_election, vote.x, vote.y)
	_fill_issues(top, satisfaction)
	_fill_moving(movements, worst)
	_fill_programme(ns)
	_fill_recent_effects()


## Which start this game was begun under, appended to the panel title -- V1.2e.
## Empty for the standard start rather than the word "Standard": a label that is
## always there says nothing, and the whole point is to mark the games that
## differ from the baseline every figure in docs/ was measured against.
func _start_suffix() -> String:
	if _state.scenario_id == "" or _loader == null:
		return ""
	var scenario = _loader.scenarios.get(_state.scenario_id)
	if scenario == null:
		return ""
	return " · %s" % scenario.display_name


## What a censure motion would do today, at ordinary hostility rather than the
## hostility a forced bill provokes -- the Article 49.3 gamble is the Politics
## tab's subject, and this line is about whether the government is standing.
## {} where the nation has no censure procedure at all.
func _censure_probe(ns) -> Dictionary:
	if ns.censure_rule == "none" or _loader == null:
		return {}
	return Government.resolve_censure(ns, _loader.parties.get(ns.id, []), false)


# --- the lead sentence ------------------------------------------------------

## A deterministic ladder, ordered by how irreversible the thing is: losing the
## government, then losing the election, then losing ground. Deterministic
## because a lead line that changed for reasons the player cannot reconstruct is
## worse than no lead line.
func _lead_text(ns, censure: Dictionary, months: int, top: Array, worst: Dictionary) -> String:
	if not censure.is_empty() and bool(censure["carried"]):
		return tr("The assembly would bring this government down today — %d of the %d seats a censure motion needs.") % [
			int(censure["for_seats"]), int(censure["threshold"])
		]

	if months <= ELECTION_URGENT_MONTHS:
		var approval := _polled_approval(ns)
		var change := Trends.approval_delta(_state, Trends.TREND_MONTHS)
		if is_nan(change):
			return tr("Election %s. You are polling %.0f%%.") % [_when(months), approval]
		return tr("Election %s. You are polling %.0f%%, %s since %s.") % [
			_when(months), approval, _moved(change), _month_name_ago(Trends.TREND_MONTHS)
		]

	if not worst.is_empty():
		var sentence := tr("%s is %s since %s.") % [
			String(worst["label"]), _moved(float(worst["change"])), _month_name_ago(Trends.TREND_MONTHS)
		]
		var issue: String = ISSUE_FOR_FIGURE.get(worst["key"], "")
		if issue != "" and not top.is_empty() and top[0][0] == issue:
			sentence += tr(" It is also what the country cares about most.")
		return sentence

	if _state.history.is_empty():
		# months_in_term is a fresh-game counter (0 at Jan 2026) and read
		# "0 months into a 60-month term" beside a vote 16 months out. The term
		# ends at the vote, so months served is the remainder of the same
		# subtraction the countdown already did.
		var months_served := maxi(0, int(ns.term_months) - months)
		return tr("%s, %d months into a %d-month term. Nothing to compare against yet.") % [
			_standing_sentence(ns), months_served, int(ns.term_months)
		]
	return tr("%s, and nothing is moving sharply. Election %s.") % [
		_standing_sentence(ns), _when(months)
	]


# --- the four columns -------------------------------------------------------

func _fill_government(ns, censure: Dictionary) -> void:
	PanelKit.figure(_columns["government"], "%d / %d" % [int(ns.coalition_seats), int(ns.assembly_seats)], tr("seats held"))
	PanelKit.line(_columns["government"], tr("%s — a majority needs more than %d.") % [
		_standing_sentence(ns), Government.majority_seats(ns)
	])

	if censure.is_empty():
		PanelKit.line(_columns["government"], tr("No censure procedure."))
	elif bool(censure["carried"]):
		PanelKit.line(_columns["government"], tr("A censure motion would carry: %d of %d.") % [
			int(censure["for_seats"]), int(censure["threshold"])
		], PanelKit.Tone.BAD)
	else:
		PanelKit.line(_columns["government"], tr("A censure motion would fail: %d of %d.") % [
			int(censure["for_seats"]), int(censure["threshold"])
		], PanelKit.Tone.GOOD)

	# Only meaningful where the constitution has it at all, so nations without
	# presidential appointment say nothing rather than saying "unavailable".
	if ns.formation_method == "presidential_appointment":
		if Government.can_force(ns):
			PanelKit.line(_columns["government"], tr("Article 49.3 available."))
		else:
			PanelKit.line(_columns["government"], tr("Article 49.3 in %s.") % Trends.months_text(int(ns.force_cooldown_months)))


func _fill_election(ns, months: int, vote_year: int, vote_month: int) -> void:
	PanelKit.figure(_columns["election"], Trends.months_text(months), tr("until the vote"))
	PanelKit.line(_columns["election"], "%s %d." % [
		tr(MONTH_NAMES[vote_month - 1]), vote_year
	])
	# The date and the count come from the same clock (the executive's where the
	# nation has one, the assembly's otherwise), which is what U3's old
	# "41 months beside a Diary saying May 2027" contradiction was.
	var change := Trends.approval_delta(_state, Trends.TREND_MONTHS)
	PanelKit.line(_columns["election"], tr("Polling %.0f%% (%s).") % [_polled_approval(ns), Trends.change_text(change)])


func _fill_issues(top: Array, satisfaction: Dictionary) -> void:
	if top.is_empty():
		PanelKit.line(_columns["issues"], "—")
		return
	for entry in top:
		var issue: String = entry[0]
		var sat: float = float(satisfaction.get(issue, 0.0))
		PanelKit.figure(_columns["issues"], K.ISSUE_LABEL.get(issue, issue), tr("%.0f%% of what people weigh") % (float(entry[1]) * 100.0))
		PanelKit.line(_columns["issues"], _satisfaction_word(sat), _satisfaction_tone(sat))


## V1.3g. Under GOVERNMENT rather than in a column or a window of its own: the
## whole session's claim is that defence in this game is budgetary and political,
## and a fifth column would have said the opposite before the player read a word.
##
## Two lines, and the second is the one that matters. Capability alone is a number
## with no units the player can act on; capability WITH the price it sets is the
## loop this session is built around -- spend, and commitments get cheaper.
func _fill_defence(ns) -> void:
	PanelKit.line(_columns["government"], tr("Military capability %.2f — a deployment costs %.2f%% of GDP.") % [
		ns.military_capability, Defence.deployment_cost_pct_gdp(ns),
	])

	var allies: Array = Defence.allies(_state, ns.id)
	if allies.is_empty():
		return

	# Only when there is one. A permanent "Alliances: none" is a row that says
	# nothing in every game that never signs a pact, which is most of them.
	var deployed := Defence.deployment_count(_state, ns.id)
	if deployed == 0:
		PanelKit.line(_columns["government"], tr("Allied with %s.") % ", ".join(allies))
	else:
		PanelKit.line(_columns["government"], tr_n("Allied with %s; %d deployment running.", "Allied with %s; %d deployments running.", deployed) % [
			", ".join(allies), deployed,
		], PanelKit.Tone.BAD)


## V1.5a. Under GOVERNMENT beside capability, which is where docs/tiers/v1.md §3 put
## the last derived national statistic of this shape, and _fill_defence() above is the
## template rather than a coincidence: its comment says capability alone is a number
## with no units the player can act on, and capability WITH the price it sets is the
## loop. Service quality has exactly that problem and exactly that answer.
##
## NOT ON THE POLLING PANEL, and the plan said it would be. That panel's contract is
## that EVERY figure on it has been through PollNoise -- the player never sees a true
## number there -- and a service statistic is not a poll: the government knows what its
## own hospitals cost and how well they run. Putting an un-noised figure on a screen
## whose whole discipline is that nothing is un-noised would be a contract the player
## cannot see being broken. The window is still the one that exists, so the "no new
## window" cut holds; only the panel changed.
##
## Silent when there is nothing to say. A permanent "delivery 100 %, quality unchanged"
## row is the line that says nothing in every game that never passes a `society` law,
## which is the failure the alliance line directly above avoids the same way.
func _fill_services(ns) -> void:
	for key in SocietyK.QUALITY_KEYS:
		var deviation: float = Society.quality_deviation(ns, key)
		if is_zero_approx(deviation):
			continue
		# Leads with the DEVIATION and not the level, which is _fill_defence()'s lesson
		# applied rather than restated: the stock's absolute value is a number in no
		# units the player can act on, and its distance from its own baseline is the
		# thing they caused. Short, because this column is ~110px wide and the
		# capability line above it already wraps to four lines.
		var label: String = K.ISSUE_LABEL.get(key, key)
		var text := tr("%s delivery %+.2f on baseline.") % [label, deviation]
		if deviation < 0.0:
			PanelKit.line(_columns["government"], text, PanelKit.Tone.BAD)
		else:
			PanelKit.line(_columns["government"], text)

	# The cause, beside the effect, and only when the player has moved it. Reads the
	# factor rather than the level, because the level is a signed abstraction and the
	# factor is what it does: what share of a spending line reaches the service.
	if is_zero_approx(ns.corruption):
		return
	var delivery: float = Society.delivery_factor(ns)
	var text := tr("Administration delivers %.0f%% of funding.") % (delivery * 100.0)
	if delivery < 1.0:
		PanelKit.line(_columns["government"], text, PanelKit.Tone.BAD)
	else:
		PanelKit.line(_columns["government"], text)


## V1.5d. The press, in one line, and only when the player has moved it.
##
## SILENT AT ZERO, which is _fill_services()' rule above and the reason it is the press
## FREEDOM STANCE that is printed rather than the framing spread. The spread is non-zero
## from month 1 in all three authored nations -- it is a fact about the country, not
## about the government -- so a line on it would be permanent furniture saying nothing,
## exactly the failure this column has avoided four times. The stance is zero until a
## press law passes, so the line appears when there is something to say about a decision.
##
## Reads the STANCE and not the gain, for _fill_services()' reason one line down: the
## per-bloc gain is an abstraction in no units the player can act on, and the polling
## panel already shows what it DOES by reordering the agenda list. This says what they
## did; that shows what it cost.
func _fill_press(ns) -> void:
	if is_zero_approx(ns.press_freedom):
		return
	if ns.press_freedom < 0.0:
		PanelKit.line(_columns["government"], tr("Press under state oversight (%+.2f).") % ns.press_freedom, PanelKit.Tone.BAD)
	else:
		PanelKit.line(_columns["government"], tr("Press independence guaranteed (%+.2f).") % ns.press_freedom)


func _fill_moving(movements: Array, worst: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	_columns["moving"].add_child(grid)

	for row in movements:
		PanelKit.line(grid, String(row["label"]))

		var change: float = float(row["change"])
		var value := Label.new()
		value.text = Trends.change_text(change)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not is_nan(row["severity"]):
			value.theme_type_variation = UiTheme.BAD_TEXT if float(row["severity"]) > 0.0 else UiTheme.GOOD_TEXT
		grid.add_child(value)

	if worst.is_empty():
		PanelKit.line(_columns["moving"], tr("Nothing has moved much."))
	else:
		PanelKit.line(_columns["moving"], tr("%s is the one to watch.") % String(worst["label"]))


## V4.1. The term's programme, per-entry rows with the derived progress -- the
## same PanelKit.progress_fraction() the Agenda window and the top-bar strip
## draw, so the three surfaces cannot carry three answers to one read.
##
## NEVER SILENT, unlike the press and delivery lines above and for a different
## reason: those hide at zero because a permanent line about nothing moved is
## furniture. An unset programme is not zero -- it is the one decision the
## resting-screen probe (V2.1c) measured the game failing to announce, so the
## unset state says where the choice lives instead of hiding.
func _fill_programme(ns) -> void:
	# The shared read, Programme.this_term(): the Agenda and the Campaign
	# panel's promises line answer the same question from the same filter, so
	# no second answer to "what is this term's programme" can drift into a
	# panel.
	var this_term: Array = Programme.this_term(ns)

	if this_term.is_empty():
		if Programme.is_term_start(ns):
			PanelKit.line(_programme_box,
				tr("The term's programme is unset -- the Agenda (K) holds the offer."))
		else:
			PanelKit.line(_programme_box, tr("No programme was set this term."))
		return

	for entry in this_term:
		_programme_box.add_child(_programme_row(ns, entry))


func _programme_row(ns, entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var terms: Dictionary = Programme.terms_of(_loader, String(entry["entry_id"]))
	var name_label := Label.new()
	name_label.text = String(terms.get("name", String(entry["entry_id"])))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var status_label := Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	match String(entry["status"]):
		ProgrammeK.STATUS_ACTIVE:
			var fraction := _entry_fraction(ns, terms)
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(160.0, 12.0)
			bar.max_value = 1.0
			# Step 0: Range's default 0.01 snap would round the derived fraction
			# away from the pair the Agenda and the strip print beside it.
			bar.step = 0.0
			bar.value = fraction
			bar.show_percentage = false
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.tooltip_text = _entry_tooltip(ns, terms, entry)
			row.add_child(bar)
			status_label.text = "%.0f%%" % (fraction * 100.0)
		ProgrammeK.STATUS_COMPLETE:
			status_label.text = tr("Delivered")
			status_label.theme_type_variation = UiTheme.GOOD_TEXT
		ProgrammeK.STATUS_FAIL:
			status_label.text = tr("Missed")
			status_label.theme_type_variation = UiTheme.BAD_TEXT
		_:
			status_label.text = tr("Overtaken")
			status_label.theme_type_variation = UiTheme.CAPTION
	row.add_child(status_label)
	return row


func _entry_fraction(ns, terms: Dictionary) -> float:
	if terms.is_empty():
		return 0.0
	var read: Dictionary = Programme.progress_of(ns, terms)
	return PanelKit.progress_fraction(
		float(read["current_value"]), float(read["goal_value"]), String(read["progressbar"]))


func _entry_tooltip(ns, terms: Dictionary, entry: Dictionary) -> String:
	if terms.is_empty():
		return tr("No content behind this entry; it concludes on the next tick.")
	var read: Dictionary = Programme.progress_of(ns, terms)
	var tip := tr("%.2f against a %.2f goal") % [
		float(read["current_value"]), float(read["goal_value"]),
	]
	var timeout := int(terms.get("timeout_months", 0))
	if timeout > 0:
		var left := timeout - int(entry["months_live"])
		tip += tr_n(" · %d month to its deadline", " · %d months to its deadline", left) % left
	return tip


## U4: the last few committed decisions, each with the figures it moved most --
## not every WATCHED figure, which would make a law with one small tax nudge
## read as long as one that reshaped the whole budget.
func _fill_recent_effects() -> void:
	var entries: Array = _state.recent_effects
	if entries.is_empty():
		PanelKit.line(_effects_box, tr("Nothing committed yet this game."))
		return

	for i in mini(RECENT_EFFECTS_SHOWN, entries.size()):
		_effects_box.add_child(_build_effect_row(entries[i]))


func _build_effect_row(effect: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = "%s — %s %d:" % [String(effect["label"]), tr(MONTH_NAMES[int(effect["month"]) - 1]), int(effect["year"])]
	label.theme_type_variation = UiTheme.CAPTION
	row.add_child(label)

	var ranked: Array = (effect["movements"] as Array).duplicate()
	ranked = ranked.filter(func(m): return not is_nan(m["severity"]))
	ranked.sort_custom(func(a, b): return float(a["severity"]) > float(b["severity"]))

	if ranked.is_empty():
		PanelKit.line(row, tr("nothing moved"))
		return row

	for i in mini(EFFECT_FIGURES_SHOWN, ranked.size()):
		var m: Dictionary = ranked[i]
		var figure := Label.new()
		figure.text = "%s %s" % [String(m["label"]), Trends.change_text(float(m["change"]), String(m["unit"]))]
		figure.theme_type_variation = UiTheme.BAD_TEXT if float(m["severity"]) > 0.0 else UiTheme.GOOD_TEXT
		row.add_child(figure)

	return row


# --- wording ----------------------------------------------------------------

func _standing_word(ns) -> String:
	if ns.is_cohabitation:
		return "cohabitation"
	if ns.is_minority:
		return tr("minority government")
	return tr("majority government")


## Not String.capitalize(), which title-cases every word and would render
## "minority government" as "Minority Government".
func _standing_sentence(ns) -> String:
	var word := _standing_word(ns)
	return word.substr(0, 1).to_upper() + word.substr(1)


func _satisfaction_word(sat: float) -> String:
	if sat > SATISFACTION_BAND:
		return "satisfied"
	if sat < -SATISFACTION_BAND:
		return "dissatisfied"
	return tr("neither pleased nor angry")


## Three tones, not two. An electorate that is neither pleased nor angry is not
## bad news, and colouring it as if it were makes the page read as a wall of alarm
## on a turn where nothing is wrong. PanelKit.tone_for() cannot answer this one:
## it reads a movement against a convention where this reads a LEVEL against a
## band, so the panel keeps the judgement and the kit keeps the drawing.
func _satisfaction_tone(sat: float) -> PanelKit.Tone:
	if sat > SATISFACTION_BAND:
		return PanelKit.Tone.GOOD
	if sat < -SATISFACTION_BAND:
		return PanelKit.Tone.BAD
	return PanelKit.Tone.DIM


func _when(months: int) -> String:
	if months <= 0:
		return tr("this month")
	return "in %s" % Trends.months_text(months)


## Approval is always the polled figure, never ns.overall_approval_pct. The true
## number exists in state and the player is never shown it -- top_bar.gd and
## polling_panel.gd hold the same line, and nation_panel.gd is the deliberate
## exception because it covers rival nations rather than the player.
func _polled_approval(ns) -> float:
	return PollNoise.displayed(
		PollNoise.poll_id(_state.year, _state.month), PollingPanel.HEADLINE_KEY, ns.overall_approval_pct
	)


func _moved(change: float) -> String:
	if absf(change) < 0.05:
		return tr("flat")
	return (tr("up %.1f points") if change > 0.0 else tr("down %.1f points")) % absf(change)


func _month_name_ago(months: int) -> String:
	var index: int = int(_state.month) - 1 - months
	var year: int = int(_state.year)
	while index < 0:
		index += 12
		year -= 1
	if year == int(_state.year):
		return tr(MONTH_NAMES[index])
	return "%s %d" % [tr(MONTH_NAMES[index]), year]
