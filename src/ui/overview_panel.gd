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
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
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
	_title.text = "OVERVIEW"
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
		["government", "GOVERNMENT"],
		["election", "NEXT ELECTION"],
		["issues", "WHAT THE COUNTRY WANTS"],
		["moving", "MOVING, LAST %d MONTHS" % Trends.TREND_MONTHS],
	]:
		# PanelKit.section() IS this panel's column: a tracked heading, a body under
		# it at the kit's own separations, and the body handed back. The four
		# separations and both variations were already identical -- the only line
		# _build_column() had that section() does not is size_flags_vertical =
		# SIZE_FILL, which is a Control's default.
		_columns[spec[0]] = PanelKit.section(row, spec[1])

	root.add_child(HSeparator.new())

	var effects_heading := Label.new()
	effects_heading.text = "RECENT DECISIONS"
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
	if not _dirty or not visible or _state == null:
		return
	_dirty = false
	_refresh()


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return

	var nation = _loader.nations.get(ns.id) if _loader != null else null
	_title.text = "OVERVIEW — %s%s" % [
		nation.nation_name if nation != null else ns.id, _start_suffix(),
	]

	for body in _columns.values():
		for child in body.get_children():
			child.queue_free()
	for child in _effects_box.get_children():
		child.queue_free()

	var censure := _censure_probe(ns)
	var months_to_election := Trends.months_until(_state, int(ns.next_election_year), int(ns.next_election_month))
	var satisfaction := Opinion.issue_satisfaction(ns)
	var top := Opinion.top_issues(ns, TOP_ISSUE_COUNT)
	var movements := Trends.movements(_state)
	var worst := Trends.worst(_state)

	_lead.text = _lead_text(ns, censure, months_to_election, top, worst)

	_fill_government(ns, censure)
	_fill_defence(ns)
	_fill_services(ns)
	_fill_press(ns)
	_fill_election(ns, months_to_election)
	_fill_issues(top, satisfaction)
	_fill_moving(movements, worst)
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
		return "The assembly would bring this government down today — %d of the %d seats a censure motion needs." % [
			int(censure["for_seats"]), int(censure["threshold"])
		]

	if months <= ELECTION_URGENT_MONTHS:
		var approval := _polled_approval(ns)
		var change := Trends.approval_delta(_state, Trends.TREND_MONTHS)
		if is_nan(change):
			return "Election %s. You are polling %.0f%%." % [_when(months), approval]
		return "Election %s. You are polling %.0f%%, %s since %s." % [
			_when(months), approval, _moved(change), _month_name_ago(Trends.TREND_MONTHS)
		]

	if not worst.is_empty():
		var sentence := "%s is %s since %s." % [
			String(worst["label"]), _moved(float(worst["change"])), _month_name_ago(Trends.TREND_MONTHS)
		]
		var issue: String = ISSUE_FOR_FIGURE.get(worst["key"], "")
		if issue != "" and not top.is_empty() and top[0][0] == issue:
			sentence += " It is also what the country cares about most."
		return sentence

	if _state.history.is_empty():
		return "%s, %d months into a %d-month term. Nothing to compare against yet." % [
			_standing_sentence(ns), int(ns.months_in_term), int(ns.term_months)
		]
	return "%s, and nothing is moving sharply. Election %s." % [
		_standing_sentence(ns), _when(months)
	]


# --- the four columns -------------------------------------------------------

func _fill_government(ns, censure: Dictionary) -> void:
	PanelKit.figure(_columns["government"], "%d / %d" % [int(ns.coalition_seats), int(ns.assembly_seats)], "seats held")
	PanelKit.line(_columns["government"], "%s — a majority needs more than %d." % [
		_standing_sentence(ns), Government.majority_seats(ns)
	])

	if censure.is_empty():
		PanelKit.line(_columns["government"], "No censure procedure.")
	elif bool(censure["carried"]):
		PanelKit.line(_columns["government"], "A censure motion would carry: %d of %d." % [
			int(censure["for_seats"]), int(censure["threshold"])
		], PanelKit.Tone.BAD)
	else:
		PanelKit.line(_columns["government"], "A censure motion would fail: %d of %d." % [
			int(censure["for_seats"]), int(censure["threshold"])
		], PanelKit.Tone.GOOD)

	# Only meaningful where the constitution has it at all, so nations without
	# presidential appointment say nothing rather than saying "unavailable".
	if ns.formation_method == "presidential_appointment":
		if Government.can_force(ns):
			PanelKit.line(_columns["government"], "Article 49.3 available.")
		else:
			PanelKit.line(_columns["government"], "Article 49.3 in %s." % Trends.months_text(int(ns.force_cooldown_months)))


func _fill_election(ns, months: int) -> void:
	PanelKit.figure(_columns["election"], Trends.months_text(months), "until the vote")
	PanelKit.line(_columns["election"], "%s %d." % [
		MONTH_NAMES[int(ns.next_election_month) - 1], int(ns.next_election_year)
	])
	# No "month N of M in this term" line. ns.term_months is the nation's nominal
	# term, while next_election_* comes from the real electoral calendar, and on a
	# fresh French game those read "month 0 of 60" beside "41 months until the
	# vote" -- two true figures that look like a contradiction on the one tab
	# whose job is to be unambiguous. Which of the two is wrong is a simulation
	# question; see docs/decision-log.md's U3 entry.
	var change := Trends.approval_delta(_state, Trends.TREND_MONTHS)
	PanelKit.line(_columns["election"], "Polling %.0f%% (%s)." % [_polled_approval(ns), Trends.change_text(change)])


func _fill_issues(top: Array, satisfaction: Dictionary) -> void:
	if top.is_empty():
		PanelKit.line(_columns["issues"], "—")
		return
	for entry in top:
		var issue: String = entry[0]
		var sat: float = float(satisfaction.get(issue, 0.0))
		PanelKit.figure(_columns["issues"], K.ISSUE_LABEL.get(issue, issue), "%.0f%% of what people weigh" % (float(entry[1]) * 100.0))
		PanelKit.line(_columns["issues"], _satisfaction_word(sat), _satisfaction_tone(sat))


## V1.3g. Under GOVERNMENT rather than in a column or a window of its own: the
## whole session's claim is that defence in this game is budgetary and political,
## and a fifth column would have said the opposite before the player read a word.
##
## Two lines, and the second is the one that matters. Capability alone is a number
## with no units the player can act on; capability WITH the price it sets is the
## loop this session is built around -- spend, and commitments get cheaper.
func _fill_defence(ns) -> void:
	PanelKit.line(_columns["government"], "Military capability %.2f — a deployment costs %.2f%% of GDP." % [
		ns.military_capability, Defence.deployment_cost_pct_gdp(ns),
	])

	var allies: Array = Defence.allies(_state, ns.id)
	if allies.is_empty():
		return

	# Only when there is one. A permanent "Alliances: none" is a row that says
	# nothing in every game that never signs a pact, which is most of them.
	var deployed := Defence.deployment_count(_state, ns.id)
	if deployed == 0:
		PanelKit.line(_columns["government"], "Allied with %s." % ", ".join(allies))
	else:
		PanelKit.line(_columns["government"], "Allied with %s; %d deployment%s running." % [
			", ".join(allies), deployed, "" if deployed == 1 else "s",
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
		var text := "%s delivery %+.2f on baseline." % [label, deviation]
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
	var text := "Administration delivers %.0f%% of funding." % (delivery * 100.0)
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
		PanelKit.line(_columns["government"], "Press under state oversight (%+.2f)." % ns.press_freedom, PanelKit.Tone.BAD)
	else:
		PanelKit.line(_columns["government"], "Press independence guaranteed (%+.2f)." % ns.press_freedom)


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
		PanelKit.line(_columns["moving"], "Nothing has moved much.")
	else:
		PanelKit.line(_columns["moving"], "%s is the one to watch." % String(worst["label"]))


## U4: the last few committed decisions, each with the figures it moved most --
## not every WATCHED figure, which would make a law with one small tax nudge
## read as long as one that reshaped the whole budget.
func _fill_recent_effects() -> void:
	var entries: Array = _state.recent_effects
	if entries.is_empty():
		PanelKit.line(_effects_box, "Nothing committed yet this game.")
		return

	for i in mini(RECENT_EFFECTS_SHOWN, entries.size()):
		_effects_box.add_child(_build_effect_row(entries[i]))


func _build_effect_row(effect: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = "%s — %s %d:" % [String(effect["label"]), MONTH_NAMES[int(effect["month"]) - 1], int(effect["year"])]
	label.theme_type_variation = UiTheme.CAPTION
	row.add_child(label)

	var ranked: Array = (effect["movements"] as Array).duplicate()
	ranked = ranked.filter(func(m): return not is_nan(m["severity"]))
	ranked.sort_custom(func(a, b): return float(a["severity"]) > float(b["severity"]))

	if ranked.is_empty():
		PanelKit.line(row, "nothing moved")
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
		return "minority government"
	return "majority government"


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
	return "neither pleased nor angry"


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
		return "this month"
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
		return "flat"
	var direction := "up" if change > 0.0 else "down"
	return "%s %.1f points" % [direction, absf(change)]


func _month_name_ago(months: int) -> String:
	var index: int = int(_state.month) - 1 - months
	var year: int = int(_state.year)
	while index < 0:
		index += 12
		year -= 1
	if year == int(_state.year):
		return MONTH_NAMES[index]
	return "%s %d" % [MONTH_NAMES[index], year]
