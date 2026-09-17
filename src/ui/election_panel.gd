extends PanelContainer

## The election result screen. Shown once for every month an election lands —
## which can mean one national result, one EP result, or both at once (France
## and Belgium in June 2029). Reads simulation state and never writes it; the
## only player intent it sends back is "continue", which does not touch
## GameState at all — it just tells main.gd to unpause the clock.
##
## Built in code, like the other two panels — a generated list of party rows
## per result, which a scene file would describe worse.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const K = preload("res://src/sim/election_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Sting = preload("res://src/ui/sting.gd")

signal dismissed

## Display pacing, not model tuning: how long a seat bar takes to fill and how
## much each row waits on the one above it. Skippable by any press (see
## _gui_input) -- a ceremony the player can end is a ceremony, one they cannot
## is an obstacle.
const TALLY_S := 1.2
const TALLY_STAGGER_S := 0.08

## The one thing the agency work proved the player needs TOLD rather than
## shown (V3.6): approval prices CHANGE, not level, so standing still reads
## neutral while a term that ran the country better polls worse -- and the
## vote follows the outcomes with a lag. Measured, not opinion: the V3.0
## probe's table (budget-spend approval 38.1 vs idle 49.4; unemployment 6.95
## vs 7.58; deficit halved). Copy pinned by the author at the plan gate.
const TOLD_LINE := "The vote follows the economy with a lag. A term that ran the country better can poll worse than one that did nothing."

var _state
var _loader
var _title: Label
var _sections: VBoxContainer
var _footer: Control
var _tally_pairs: Array = []
var _tally_tween: Tween


func _ready() -> void:
	# Placement is the owner's job — see the note in budget_panel.gd. Same bug
	# class: a preset in _ready() lands this in the corner before it has a size.
	# 860x600, V2.9: this is the one result screen in the game, carrying the
	# verdict, the attribution and the seat bars -- 640 was the budget panel's
	# size and the bars need the width.
	custom_minimum_size = Vector2(860, 600)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	_title = Label.new()
	root.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The last content panel without this. Default mode lays _sections out at the
	# child's own minimum width, which collapsed the results table to ~370px
	# against the 640px plate and left the dead navy field the playtest
	# photographed beside it. Sibling panels: calendar, city, bloc, campaign.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_sections = VBoxContainer.new()
	_sections.add_theme_constant_override("separation", 20)
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sections)

	_footer = HBoxContainer.new()
	_footer.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(_footer)


func setup(state, loader) -> void:
	_state = state
	_loader = loader


## `results` is the non-empty Array Elections.tick_month() returned this month —
## one or two Dictionaries, each shaped by Elections.resolve(). Builds the whole
## panel fresh; there is no partial-refresh path because this only ever shows
## once per election, not every frame like the other two panels.
func show_results(results: Array) -> void:
	_kill_tally()
	for child in _sections.get_children():
		child.queue_free()
	for child in _footer.get_children():
		child.queue_free()

	var ns = _state.player()
	var national = null
	var eu_result = null
	var executive = null
	for r in results:
		if r["kind"] == "national":
			national = r
		elif r["kind"] == "eu_parliament":
			eu_result = r
		elif r["kind"] == "executive":
			executive = r
		elif r["kind"] == "termed_out":
			# Read as the executive verdict for every purpose on this screen -- it
			# ends the term exactly as a lost election does -- while staying a
			# distinct kind everywhere else. See elections.gd.
			executive = r

	# Only an executive election can end the player's term. Where the executive
	# is drawn from the chamber there is no separate executive result and the
	# national one carries the verdict, exactly as before V1.1a.
	var verdict_result = executive if executive != null else national
	var defeated: bool = verdict_result != null and not verdict_result["incumbent_largest"] and not ns.in_government
	# V1.6 audit, V1. A term limit ends the run whatever the vote said, so the
	# defeat test above misses it -- the incumbent's PARTY may well have won.
	var termed_out: bool = verdict_result != null and bool(verdict_result.get("termed_out", false))
	if termed_out:
		defeated = true

	var snap: bool = national != null and bool(national.get("snap", false))

	if executive != null:
		_title.text = "TERM LIMIT" if termed_out else ("DEFEATED" if defeated else "RE-ELECTED")
	elif national != null:
		# A legislative election under a separately elected executive does not
		# end the term. It decides whether the player still commands a majority.
		if ns.has_executive:
			if ns.is_cohabitation:
				_title.text = "COHABITATION"
			elif snap:
				_title.text = "SNAP ELECTION"
			else:
				_title.text = "NEW ASSEMBLY"
		else:
			_title.text = "DEFEATED" if defeated else "RE-ELECTED"
	else:
		_title.text = "EUROPEAN PARLIAMENT ELECTION"

	# A termed-out notice carries no vote, so there is no table to draw -- see
	# elections.gd. It still gets a sentence: a plate carrying nothing but a title
	# and a footer reads like a screen that failed to load, which is too close to
	# the bug this branch exists to fix.
	if termed_out:
		PanelKit.line(_sections, "%s has served %d terms as %s, the most the constitution allows, and cannot stand again. The office passes to whoever wins the election you are not in." % [
			_loader.person_name(ns.head_of_state_person_id),
			ns.terms_served,
			_loader.nations[ns.id].executive_title,
		], PanelKit.Tone.PLAIN)
	# V2.9: the verdict section leads and carries the attribution -- the
	# playtest buried "What decided it" under the table. Where the executive is
	# drawn from the chamber the NATIONAL result is the verdict and leads.
	elif executive != null:
		_sections.add_child(_build_section(executive, _loader.nations[ns.id].executive_title, true))
	if national != null:
		_sections.add_child(_build_section(national, _loader.nations[ns.id].chamber_name, executive == null))
	if eu_result != null:
		_sections.add_child(_build_section(eu_result, ""))

	if national != null and ns.has_executive and not defeated:
		var gov := ""
		if ns.is_cohabitation:
			gov = "The new Assembly is against you. %s %s leads a government you did not choose." % [
				ns.head_of_government_title, _loader.person_name(ns.pm_person_id)
			]
		elif ns.is_minority:
			gov = "%s %s heads a minority government: %d of %d seats." % [
				ns.head_of_government_title, _loader.person_name(ns.pm_person_id), ns.coalition_seats, ns.assembly_seats
			]
		else:
			gov = "%s %s forms a government with %d of %d seats." % [
				ns.head_of_government_title, _loader.person_name(ns.pm_person_id), ns.coalition_seats, ns.assembly_seats
			]
		PanelKit.line(_sections, gov, PanelKit.Tone.PLAIN)

	# V1.6 audit, V2. The footer gets a control in BOTH branches. It used to build
	# the button only on the winning side, and main.gd unpauses only on `dismissed`
	# -- so a defeated player was left with a plate carrying nothing to press, over
	# a HUD that stayed live because the holder is MOUSE_FILTER_IGNORE. Space
	# unpaused it and the run continued indefinitely behind a "DEFEATED" title.
	# The defeat sentence lives in _sections, not _footer: the footer is an
	# ALIGNMENT_END HBox also holding the button, and an autowrapping Label with no
	# horizontal expand collapses there to a ~one-character column -- the vertical
	# letter stack the 2026-09-16 playtest photographed (finding B2). Same sentence,
	# same reading order, in the container the termed-out branch already used.
	if defeated:
		PanelKit.line(_sections, (
			"You have served the maximum number of terms. You leave office." if termed_out
			else "You have lost your office. This term is over."
		), PanelKit.Tone.PLAIN)

	var cont := Button.new()
	cont.text = "Leave office" if defeated else "Continue"
	cont.pressed.connect(func(): hide(); dismissed.emit())
	_footer.add_child(cont)

	_start_tally()
	Sting.play(self)


## The tally reveals what show_results already computed: each bar tweens to the
## `final` recorded at build time, so a skip lands on exactly the numbers the
## result carries. Time-based (Tween), never frame-counted -- the ceremony must
## cost the same at 30 and 144 fps. The out-of-tree guard is the half-dead
## Control gotcha: create_tween() on a node outside the tree does not run, so a
## cold caller gets the finished readout rather than a silent non-animation.
func _start_tally() -> void:
	if _tally_pairs.is_empty():
		return
	if not is_inside_tree():
		_kill_tally()
		return
	_tally_tween = create_tween()
	for i in _tally_pairs.size():
		var p: Dictionary = _tally_pairs[i]
		_tally_tween.tween_property(p["bar"], "value", p["final"], TALLY_S) \
			.set_delay(i * TALLY_STAGGER_S)


## Any click finishes the tally instantly; Space or Enter on the focused footer
## button dismisses outright, which ends the ceremony its own way. The button's
## press is deliberately NOT routed through here: a click that lands on it is a
## dismissal the player meant, and a ceremony that could eat that click would
## be a ceremony that ate a result (the V3.6 handoff's own sentence).
func _gui_input(event: InputEvent) -> void:
	if _tally_tween == null:
		return
	if event is InputEventMouseButton and event.pressed:
		_kill_tally()


## Kills the tween and snaps every live bar to its final. Freed bars (a
## previous election's, queue_free'd when the plate rebuilt) are skipped --
## setting a value on a freed instance is the crash this guard exists for.
func _kill_tally() -> void:
	if _tally_tween != null and _tally_tween.is_valid():
		_tally_tween.kill()
	_tally_tween = null
	for p in _tally_pairs:
		if is_instance_valid(p["bar"]):
			p["bar"].value = p["final"]
	_tally_pairs.clear()


func _build_section(result: Dictionary, chamber_label: String, verdict := false) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var kind_label := "European Parliament election"
	if result["kind"] == "national":
		kind_label = "Snap legislative election" if bool(result.get("snap", false)) else "Legislative election"
	elif result["kind"] == "executive":
		kind_label = "Presidential election"
	PanelKit.line(box, "%s — %s" % [kind_label, chamber_label] if chamber_label != "" else kind_label, PanelKit.Tone.PLAIN)

	if result["kind"] == "executive":
		var winner_name := _party_name(result["largest_party_id"])
		PanelKit.line(box, (
			"%s holds the office on %.1f%% of the vote." if result["incumbent_largest"]
			else "%s takes the office; you polled %.1f%%."
		) % [winner_name, float(result["incumbent_vote_share"]) * 100.0], PanelKit.Tone.PLAIN)

	if result["kind"] == "national":
		var incumbent_name := _party_name(result["incumbent_party_id"])
		PanelKit.line(box, (
			"%s remains the largest party: %d of %d seats." if result["incumbent_largest"]
			else "%s is no longer the largest party: %d of %d seats."
		) % [incumbent_name, result["incumbent_seats"], result["seats_total"]], PanelKit.Tone.PLAIN)

	# The verdict's own section reads verdict, then why, then the numbers -- a
	# result screen, not a spreadsheet (V2.9). The other sections on a
	# double-election panel keep table-then-attribution, which is where a
	# chamber's detail belongs.
	if verdict:
		box.add_child(_build_attribution(result, true))
	box.add_child(_build_party_table(result))
	if not verdict:
		box.add_child(_build_attribution(result))
	return box


func _build_party_table(result: Dictionary) -> Control:
	var seats: Dictionary = result["seats"]
	var shares: Dictionary = result["vote_share"]

	# An executive election allocates no seats — one office, not a chamber — so
	# the table falls back to ranking by vote share.
	var ordered: Array
	if seats.is_empty():
		ordered = shares.keys()
		ordered.sort_custom(func(a, b): return float(shares[a]) > float(shares[b]))
	else:
		ordered = seats.keys()
		ordered.sort_custom(func(a, b): return int(seats[a]) > int(seats[b]))

	# The seats column exists only when the data does: an executive election
	# allocates no seats, and a column of em dashes stacked in a ~20px gutter is
	# how the playtest read "orphaned letters" down the side of the modal.
	var has_seats: bool = not seats.is_empty()
	var rows: Array = [["party", "vote share"] + (["seats"] if has_seats else [])]
	for party_id in ordered:
		var name_text := _party_name(party_id)
		if party_id == result["incumbent_party_id"]:
			name_text += "  (incumbent)"
		var row: Array = [
			name_text,
			"%.1f%%" % (float(shares.get(party_id, 0.0)) * 100.0),
		]
		if has_seats:
			row.append(str(seats[party_id]))
		rows.append(row)

	var host := VBoxContainer.new()
	PanelKit.ledger(host, rows)

	# Bars under the ledger: the table numbers the seats, the bars weigh them —
	# the economy panel's idiom, themed by ui_theme's ProgressBar entry, so no
	# second visual rule is joined. The ledger stays one grid (V1.6f): the bar
	# block is the panel's own, beside the grid rather than a cell inside it.
	if has_seats:
		var total := maxi(1, int(result["seats_total"]))
		var bars := VBoxContainer.new()
		bars.add_theme_constant_override("separation", 3)
		for party_id in ordered:
			var bar_row := HBoxContainer.new()
			bar_row.add_theme_constant_override("separation", 8)
			var label := Label.new()
			label.text = _party_name(party_id)
			label.theme_type_variation = UiTheme.CAPTION
			label.custom_minimum_size.x = 180.0
			bar_row.add_child(label)
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(240.0, 12.0)
			bar.max_value = 100.0
			# The tally starts the bars empty and records the finished value the
			# table already computed -- the reveal interpolates DISPLAY values
			# only; nothing about the result is recomputed or gated on frames.
			bar.value = 0.0
			_tally_pairs.append({"bar": bar, "final": 100.0 * float(seats[party_id]) / float(total)})
			bar.show_percentage = false
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar_row.add_child(bar)
			bars.add_child(bar_row)
		host.add_child(bars)
	return host


func _build_attribution(result: Dictionary, is_verdict := false) -> Control:
	var box := VBoxContainer.new()

	PanelKit.line(box, "What decided it", PanelKit.Tone.PLAIN)

	for entry in result["attribution"]:
		var issue: String = entry["issue"]
		var satisfaction: float = entry["satisfaction"]
		var mood := "helped" if satisfaction > 0.05 else ("hurt" if satisfaction < -0.05 else "was neutral")
		PanelKit.line(box, "%s — %s (salience %.0f%%)" % [
			OpinionK.ISSUE_LABEL[issue], mood, entry["salience"] * 100.0,
		], PanelKit.Tone.PLAIN)

	# Once, on the verdict's attribution only -- a sentence printed under every
	# table on a double-election panel is wallpaper, not a message.
	if is_verdict:
		PanelKit.line(box, TOLD_LINE, PanelKit.Tone.DIM)

	return box


func _party_name(party_id: String) -> String:
	var ns = _state.player()
	for party in _loader.parties.get(ns.id, []):
		if party.id == party_id:
			return party.party_name
	return party_id
