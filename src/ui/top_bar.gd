extends PanelContainer

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Trends = preload("res://src/ui/trends.gd")
const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")

## The thin strip along the top edge -- U2, rebuilt at U5a.
##
## U2 put six things here because there was nowhere else to put them: the date,
## pause, three speeds and four figures. U5a gives the clock its own corner
## cluster and gives approval to the portrait card, which leaves this doing the
## one job a permanent top strip is good at -- the two or three numbers that are
## true about the country regardless of what the player is looking at.
##
## Deficit, GDP, unemployment, and next to them the vote that ends the
## player's term (V2.9, from the playtest: the goal was four clicks deep and
## two surfaces disagreed about it). Not approval (the portrait carries it, and
## a president reads their own standing off their own face) and not government
## standing, which is a Politics-panel question the player checks rather than
## monitors.
##
## Reads state, never writes it. The gear and save buttons emit; main.gd decides
## what they open, the same shape as every other panel here.

signal settings_requested
signal save_load_requested

const BAR_HEIGHT := 40

var _figure_values := {}
## V4.1. The programme figure, hidden until a programme runs -- it is not one
## of the four always-on figures, so it keeps its own references beside the
## dict the others share.
var _programme_box: Control
var _programme_label: Label
var _programme_value: Label


func _ready() -> void:
	custom_minimum_size = Vector2(0, BAR_HEIGHT)
	# Square corners and its own padding, because this one sits flush against
	# the window edge; every other panel takes the theme's default.
	theme_type_variation = UiTheme.TOP_BAR_PANEL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	row.add_child(_spacer())

	var figures := HBoxContainer.new()
	figures.add_theme_constant_override("separation", 34)
	row.add_child(figures)

	# B10 (playtest 2026-09-16): the value was always signed -- a surplus printed
	# "+2.1%", a deficit "-10.5%" -- so "DEFICIT +10.50%" was a live contradiction
	# on screen. A balance is a signed quantity; the label now says so.
	figures.add_child(_build_figure("deficit", "Budget balance",
		"Surplus is +, deficit is −."))
	figures.add_child(_build_figure("gdp", "GDP"))
	figures.add_child(_build_figure("unemployment", "Unemployment"))
	figures.add_child(_build_figure("election", "Next vote"))
	figures.add_child(_build_programme_figure())
	# V4.3's interim People figure: how many people the term has MOVED (a
	# non-zero grudge or loyalty), not how many exist -- the register is 1595
	# and a permanent "1595" says nothing. Rises only when the player's
	# decisions move someone, which is the number a president actually tracks.
	# The People window (R) is the full surface; this strip is the pulse.
	figures.add_child(_build_figure("people", "People",
		"People whose loyalty or grudge the term has moved. Open the People window (R)."))
	# V4.4's interim V4.8 obligation: the desk -- pending events by count, the worst
	# severity named in the tooltip. Deliberately NOT the programme figure's
	# empty-state hiding: an empty desk is itself a reading (the value says so),
	# because the glance this strip serves is "is anything waiting on me", and
	# hiding the figure answers that question by not asking it.
	figures.add_child(_build_figure("desk", "Desk",
		"Events awaiting an answer. Worst severity in the tooltip."))

	row.add_child(_spacer())

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	row.add_child(tools)

	var save := Button.new()
	save.text = "SAVE"
	save.theme_type_variation = UiTheme.SUBROW_BUTTON
	save.tooltip_text = "Save and load (S)"
	save.pressed.connect(func(): save_load_requested.emit())
	tools.add_child(save)

	var settings := Button.new()
	settings.text = "MENU"
	settings.theme_type_variation = UiTheme.SUBROW_BUTTON
	settings.tooltip_text = "Pause menu (Esc)"
	settings.pressed.connect(func(): settings_requested.emit())
	tools.add_child(settings)


## Label and value on one line rather than stacked, which is what lets the strip
## be 40px instead of U2's 64 and still read at a glance.
func _build_figure(key: String, title: String, tip := "") -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 7)

	var label := Label.new()
	label.text = title.to_upper()
	label.theme_type_variation = UiTheme.MICRO
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(label)

	var value := Label.new()
	value.theme_type_variation = UiTheme.FIGURE
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(value)
	_figure_values[key] = value
	if not tip.is_empty():
		value.tooltip_text = tip
		label.tooltip_text = tip

	return box


## The desk figure's caption and value are two hover targets for one reading, so
## the live tooltip goes on both -- _build_figure gives the caption a static tip,
## and left alone it would keep saying nothing about severity while the number
## beside it named the worst one.
func _set_desk_tip(text: String) -> void:
	var value: Control = _figure_values["desk"]
	value.tooltip_text = text
	var caption: Control = value.get_parent().get_child(0)
	caption.tooltip_text = text


## V4.1. The chosen programme's name and its nearest-deadline entry's progress,
## as a fifth figure -- the deadline the strip already carries one of (the vote)
## now has the thing that is supposed to land before it. Hidden while nothing
## runs, the defence-allies rule: a permanent "no programme" slot says nothing
## in every game that never opens the Agenda, which is most of them.
func _build_programme_figure() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 7)

	_programme_label = Label.new()
	_programme_label.theme_type_variation = UiTheme.MICRO
	_programme_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_programme_label)

	_programme_value = Label.new()
	_programme_value.theme_type_variation = UiTheme.FIGURE
	_programme_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_programme_value)

	box.visible = false
	_programme_box = box
	return box


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


## The desk tooltip: a critical on the desk is named outright -- that is the one
## line a president must not have to decode -- and any other desk reads as a count
## by severity. The names are events_constants' own register (1 minor, 2 major,
## 3 critical), not new copy.
func _desk_tooltip(worst: int, by_severity: Dictionary) -> String:
	var parts: Array[String] = []
	for severity in [3, 2, 1]:
		var count := int(by_severity.get(severity, 0))
		if count > 0:
			parts.append("%d %s" % [count, ["minor", "major", "critical"][severity - 1]])
	return " · ".join(parts) if not parts.is_empty() else "On the desk."


## Called every day -- cheap enough that main.gd calls it unconditionally rather
## than gating it behind a dirty flag like the floating panels, matching the HUD
## it replaces. The loader is optional so the existing two-argument call still
## works; without one there is no content to name and the figure stays hidden.
func refresh(state, _clock: Node, loader = null) -> void:
	if state == null:
		return
	var ns = state.player()

	# Signed the way a player reads it: a deficit is a negative number. B10: the
	# title above now says "BALANCE" so the + and − signs on this figure agree
	# with their own label.
	_figure_values["deficit"].text = "%+.2f%%" % -ns.deficit_pct_gdp
	_figure_values["gdp"].text = "%.0f Bn" % ns.gdp_eur_bn
	_figure_values["unemployment"].text = "%.2f%%" % ns.unemployment_pct
	# Count, not date: the number ticking down is the urgency; the Overview's
	# date line and the Diary carry the calendar. Same query as theirs, so the
	# three surfaces cannot disagree again. Tooltip keeps the date for free.
	#
	# B3: months_to_vote counts the EXECUTIVE clock where the nation has one,
	# while the Polling panel counts the assembly's -- both correct, so the
	# tooltip names which vote this figure is counting rather than leaving two
	# correct numbers to read as a contradiction.
	var months := Trends.months_to_vote(state, ns)
	# B1 (playtest 2026-09-16): the raw int printed "NEXT VOTE -44 mo" in two
	# ten-year captures -- months_to_vote can legally go negative once the date
	# has passed and the next schedule has not been drawn. The tooltip's
	# months_text clamps; the figure must too.
	if months > 0:
		_figure_values["election"].text = "%d mo" % months
	elif months == 0:
		_figure_values["election"].text = "now"
	else:
		_figure_values["election"].text = "—"
	_figure_values["election"].tooltip_text = _election_tooltip(state, ns, loader, months)

	# V4.3: the moved-people count, both registers read the same way so the
	# figure and the People window's rows cannot disagree about who counts.
	var moved := 0
	for pid in ns.person_grudges.keys():
		if float(ns.person_grudges[pid]) >= 0.05:
			moved += 1
	for pid in ns.person_loyalty.keys():
		if absf(float(ns.person_loyalty[pid])) >= 0.05 and float(ns.person_grudges.get(pid, 0.0)) < 0.05:
			moved += 1
	_figure_values["people"].text = "%d" % moved

	# V4.4: the desk, read straight off the queue register -- the same read
	# Events.is_pending() makes for the brass mark, so the strip and the mark
	# cannot disagree about whether something is waiting.
	var desk: Array = ns.event_queue
	if desk.is_empty():
		# Em dash, not "0 pending": the state is "nothing pending" and a confident
		# zero here would be V1.6d's lie in the strip's own handwriting.
		_figure_values["desk"].text = "— clear"
		_set_desk_tip("Nothing awaits an answer.")
	else:
		var worst := 0
		var by_severity := {}
		for entry in desk:
			var severity := int(entry.get("severity", 1))
			worst = maxi(worst, severity)
			by_severity[severity] = int(by_severity.get(severity, 0)) + 1
		_figure_values["desk"].text = "%d pending" % desk.size()
		_set_desk_tip(_desk_tooltip(worst, by_severity))

	# V4.1. Derived off the same read the Agenda window draws -- the panel and
	# the strip cannot print two answers to one progress question.
	var programme := _nearest_programme(ns, loader)
	_programme_box.visible = not programme.is_empty()
	if programme.is_empty():
		return
	var terms: Dictionary = programme["terms"]
	var live: Dictionary = programme["entry"]
	var name_text := String(terms.get("name", String(live["entry_id"])))
	_programme_label.text = name_text.to_upper()
	var read: Dictionary = Programme.progress_of(ns, terms)
	var fraction := PanelKit.progress_fraction(
		float(read["current_value"]), float(read["goal_value"]), String(read["progressbar"]))
	_programme_value.text = "%.0f%%" % (fraction * 100.0)
	var tip := "%s -- %.2f against a %.2f goal" % [
		name_text, float(read["current_value"]), float(read["goal_value"]),
	]
	var clock_text := _programme_clock_text(terms, live)
	if not clock_text.is_empty():
		tip += " · %s" % clock_text
	_programme_label.tooltip_text = tip
	_programme_value.tooltip_text = tip


## B1/B3. The vote figure counts Trends.vote_date() -- the EXECUTIVE clock where
## the nation elects one separately, the single chamber's schedule where it does
## not (the two are then the same schedule, trends.gd's own note). Name which
## vote is being counted, off the loader's nation data; no nation-specific copy.
## Without a loader the two-argument call still works and keeps the original
## generic wording.
func _election_tooltip(state, ns, loader, months: int) -> String:
	if months < 0:
		# No "Win it." here: the vote the player was supposed to win is over.
		return "The vote that ends your term has been held."
	var what := "vote"
	if loader != null and loader.nations.has(ns.id):
		var nation = loader.nations[ns.id]
		if bool(ns.has_executive):
			what = "vote for %s" % nation.executive_title
		else:
			what = "vote for the %s" % nation.chamber_name
	return "The %s that ends your term -- %s. Win it." % [what, Trends.months_text(months)]


## The register entry the strip prices: the live one with the nearest deadline,
## or the first live one when none carries a clock. The strip's whole contract
## is the glance -- one name, one percentage.
func _nearest_programme(ns, loader) -> Dictionary:
	var best := {}
	var best_left := 1 << 30
	for entry in ns.programme:
		if String(entry["status"]) != ProgrammeK.STATUS_ACTIVE:
			continue
		var terms: Dictionary = Programme.terms_of(loader, String(entry["entry_id"]))
		if terms.is_empty():
			continue
		var timeout := int(terms.get("timeout_months", 0))
		# A deadline always beats a no-deadline entry; no-deadline entries keep
		# register order, which is the order the player chose them in.
		var left := timeout - int(entry["months_live"])
		var score := left if timeout > 0 else (1 << 30) - 1
		if best.is_empty() or score < best_left:
			best = {"terms": terms, "entry": entry}
			best_left = score
	return best


func _programme_clock_text(terms: Dictionary, live: Dictionary) -> String:
	var timeout := int(terms.get("timeout_months", 0))
	if timeout <= 0:
		return ""
	var left := timeout - int(live["months_live"])
	if left <= 0:
		return "its deadline is now"
	return "%s to its deadline" % ("1 month" if left == 1 else "%d months" % left)
