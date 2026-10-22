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
const Sound = preload("res://src/ui/sound.gd")
const Motion = preload("res://src/ui/motion.gd")
const ElectionNight = preload("res://src/ui/election_night.gd")
const ElectionVerdict = preload("res://src/ui/election_verdict.gd")

signal dismissed

## What the plate is titled while the count runs: the verdict is the last
## thing the night shows, so the title cannot be it yet.
const NIGHT_TITLE := "ELECTION NIGHT"  # i18n: msgid
const SKIP_LABEL := "Skip count"  # i18n: msgid
## How long after a skip the footer button ignores presses: a double click's
## second press lands well inside it, a deliberate second press does not.
const SKIP_GUARD_MS := 400

## The one thing the agency work proved the player needs TOLD rather than
## shown (V3.6): approval prices CHANGE, not level, so standing still reads
## neutral while a term that ran the country better polls worse -- and the
## vote follows the outcomes with a lag. Measured, not opinion: the V3.0
## probe's table (budget-spend approval 38.1 vs idle 49.4; unemployment 6.95
## vs 7.58; deficit halved). Copy pinned by the author at the plan gate.
const TOLD_LINE := "The vote follows the economy with a lag. A term that ran the country better can poll worse than one that did nothing."  # i18n: msgid

var _state
var _loader
var _title: Label
var _sections: VBoxContainer
var _footer: Control
## V4.9b, election night. V3.6's tally filled the seat bars; the night grew it
## into the count -- the regions declare (src/ui/election_night.gd), every
## figure in every table moves with them, the verdict comes last. `_cells` holds
## each row's live controls and finals; `_verdict_nodes` what the night holds
## back. Time-based through Motion.run(), so it is off under --headless and
## skippable by any press on the plate (see _gui_input) -- a ceremony the
## player can end is a ceremony, one they cannot is an obstacle.
var _night
var _cells: Array = []
var _verdict_nodes: Array = []
var _verdict_title := ""
var _ticker: Label
## Bumped by every rebuild: a count still running for a plate that was
## replaced steps into nothing rather than revealing (and sounding) a verdict
## nobody is looking at.
var _night_id := 0
var _revealed := false
var _cont: Button
var _dismiss_label := ""
var _guard_until := 0
## V4.9c. Regions already ticked for this night.
var _ticked := 0


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
## V5.1-d1b2 (G4, the play gate: "when this is election time, the time should be
## paused, with a continue button to make suspense"; the author's answer on where:
## "Oui, un temps avant"). Election day stops on the polls closing, BEFORE the
## count: the plate says so and shows nothing of the result, and its Continue is
## what starts the night. It holds the clock as the result does -- a scene, so no
## door runs it -- and nothing is dismissed until the verdict has been shown.
## The month end calls this; show_results() stays the count itself.
func show_polls_closed(results: Array) -> void:
	_clear_plate()
	_title.text = tr("POLLS CLOSED")
	PanelKit.line(_sections, tr("The polls have closed. The count is about to begin."), PanelKit.Tone.PLAIN)
	_cont = Button.new()
	_cont.text = tr("Continue")
	_cont.pressed.connect(_begin_count.bind(results))
	_footer.add_child(_cont)


## The beat's Continue. The count's own button takes its place, so a double
## click's second half lands on it: guarded as a skip is (QA on #70).
func _begin_count(results: Array) -> void:
	_guard_until = Time.get_ticks_msec() + SKIP_GUARD_MS
	show_results(results)


## A plate emptied for a new night: the last one's count, verdict and buttons gone.
func _clear_plate() -> void:
	_night_id += 1
	Motion.finish(self)
	_cells.clear()
	_verdict_nodes.clear()
	_revealed = false
	for child in _sections.get_children():
		child.queue_free()
	for child in _footer.get_children():
		child.queue_free()


func show_results(results: Array) -> void:
	_clear_plate()

	var ns = _state.player()
	var read: Dictionary = ElectionVerdict.read(results, ns)
	var national = read["national"]
	var eu_result = read["eu_result"]
	var executive = read["executive"]
	var defeated: bool = read["defeated"]
	var termed_out: bool = read["termed_out"]
	_verdict_title = read["title"]
	_title.text = _verdict_title

	_night = ElectionNight.new(_state, results)
	_ticker = PanelKit.plain_line(_sections, "", PanelKit.Tone.DIM)

	# A termed-out notice carries no vote, so there is no table to draw -- see
	# elections.gd. It still gets a sentence: a plate carrying nothing but a title
	# and a footer reads like a screen that failed to load, which is too close to
	# the bug this branch exists to fix.
	if termed_out:
		PanelKit.line(_sections, tr("%s has served %d terms as %s, the most the constitution allows, and cannot stand again. The office passes to whoever wins the election you are not in.") % [
			_loader.person_name(ns.head_of_state_person_id),
			ns.terms_served,
			_loader.nations[ns.id].executive_title,
		], PanelKit.Tone.PLAIN)
	# V2.9: the verdict section leads and carries the attribution -- the
	# playtest buried "What decided it" under the table. Where the executive is
	# drawn from the chamber the NATIONAL result is the verdict and leads.
	elif executive != null:
		_sections.add_child(_build_section(executive, results.find(executive), _loader.nations[ns.id].executive_title, true))
	if national != null:
		_sections.add_child(_build_section(national, results.find(national), _loader.nations[ns.id].chamber_name, executive == null))
	if eu_result != null:
		_sections.add_child(_build_section(eu_result, results.find(eu_result), ""))

	if national != null and ns.has_executive and not defeated:
		var gov := ""
		if ns.is_cohabitation:
			gov = tr("The new Assembly is against you. %s %s leads a government you did not choose.") % [
				ns.head_of_government_title, PanelKit.person(ns.pm_person_id, _loader.person_name(ns.pm_person_id))
			]
		elif ns.is_minority:
			gov = tr("%s %s heads a minority government: %d of %d seats.") % [
				ns.head_of_government_title, PanelKit.person(ns.pm_person_id, _loader.person_name(ns.pm_person_id)), ns.coalition_seats, ns.assembly_seats
			]
		else:
			gov = tr("%s %s forms a government with %d of %d seats.") % [
				ns.head_of_government_title, PanelKit.person(ns.pm_person_id, _loader.person_name(ns.pm_person_id)), ns.coalition_seats, ns.assembly_seats
			]
		_verdict_nodes.append(PanelKit.rich(_sections, gov, PanelKit.Tone.PLAIN))

	# V1.6 audit, V2. The footer gets a control in BOTH branches. It used to build
	# the button only on the winning side, and main.gd unpauses only on `dismissed`
	# -- so a defeated player was left with a plate carrying nothing to press, over
	# a HUD that stayed live because the holder is MOUSE_FILTER_IGNORE. Space
	# unpaused it and the run continued indefinitely behind a "DEFEATED" title.
	# The defeat sentence lives in _sections, not _footer: the footer is an
	# ALIGNMENT_END HBox also holding the button, and an autowrapping Label with no
	# horizontal expand collapses there to a ~one-character column -- the vertical
	# letter stack the 2026-09-16 playtest photographed (finding B2). The
	# termed-out verdict is excluded: its own paragraph above already says it,
	# and while the footer bug crushed this copy to a column the duplication
	# was invisible -- one sentence per verdict now that both render.
	if defeated and not termed_out:
		_verdict_nodes.append(PanelKit.line(_sections, tr("You have lost your office. This term is over."), PanelKit.Tone.PLAIN))

	_dismiss_label = tr("Leave office") if defeated else tr("Continue")
	_cont = Button.new()
	_cont.text = _dismiss_label
	_cont.pressed.connect(_on_footer_pressed)
	_footer.add_child(_cont)

	_start_night()


## The count, then the verdict. The tables were built with their final
## figures, so a night that never runs -- motion off, a cold caller outside the
## tree (the half-dead Control gotcha: a tween there would not step) -- reveals
## them as built. Otherwise every figure is reset to the empty count, what the
## verdict says is held back, and Motion.run() declares the regions.
func _start_night() -> void:
	var n: int = _night.size()
	if _cells.is_empty() or n == 0 or not is_inside_tree() or not Motion.enabled():
		_apply_count(float(n))
		_reveal()
		return
	_title.text = tr(NIGHT_TITLE)
	_cont.text = tr(SKIP_LABEL)
	# Hidden, not transparent: a transparent verdict kept its space, and the
	# windowed capture showed the count under a ~200 px hole where the
	# attribution would be. The verdict lands on top of the table instead.
	for node in _verdict_nodes:
		node.visible = false
	_apply_count(0.0)
	_ticked = 0
	var id := _night_id
	Motion.run(self, minf(float(n) * Motion.DECLARE_S, Motion.NIGHT_MAX_S), func(t: float):
		if id != _night_id:
			return
		_apply_count(t * float(n))
		# One tick per region as it declares -- except the last, which declares
		# with the verdict's sting instead of a tick a frame before it. That one
		# rule is also what silences a skip: skip() lands the count in a single
		# step at t = 1, so the regions it declares at once declare with the
		# last, and the count's sound stops with the count (test_sound.gd).
		var declared: int = _night.declared(t * float(n))
		if declared > _ticked and declared < n:
			Sound.cue(self, "declare")
		_ticked = maxi(_ticked, declared)
		if t >= 1.0:
			_reveal()
	)


## Every table's figures at `counted` regions declared: the running vote share,
## and the seats and bar declared so far -- the final scaled by the share of the
## electorate counted. Seats are not projected from a running vote; they come
## in with the regions that elect them.
func _apply_count(counted: float) -> void:
	var w: float = _night.counted_weight(counted)
	for cell in _cells:
		var shares: Dictionary = _night.shares_at(int(cell["result"]), counted)
		cell["share"].text = "%s%%" % PanelKit.Num.f((float(shares.get(cell["party"], 0.0)) * 100.0), 1)
		if cell["seats"] != null:
			cell["seats"].text = str(roundi(float(cell["final_seats"]) * w))
		if cell["bar"] != null:
			cell["bar"].value = float(cell["final_bar"]) * w
	var n: int = _night.size()
	# No regions, or no table to count into (a term-limit notice carries no vote).
	if n == 0 or _cells.is_empty():
		_ticker.visible = false
	elif counted >= float(n):
		_ticker.text = tr("All %d regions declared.") % n
	elif _night.declared(counted) == 0:
		_ticker.text = tr("Polls closed. The count begins.")
	else:
		_ticker.text = tr("%d of %d regions declared -- latest, %s.") % [
			_night.declared(counted), n, _night.latest(counted)]


func _reveal() -> void:
	if _revealed:
		return
	_revealed = true
	_title.text = _verdict_title
	_cont.text = _dismiss_label
	Motion.pulse(_title)
	for node in _verdict_nodes:
		node.visible = true
		Motion.arrive(node)
	Sting.play(self)


## Any click on the plate ends the count at once, verdict and all. A click,
## not any button: the wheel scrolls the double-election plate, and a scroll
## that ended the count would be a ceremony taken from the player who was
## reading it (review pass 1).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		skip()


## The footer button says what it does. During the count it reads Skip count
## and skips: it used to read Continue / Leave office from the first frame,
## which told the player the verdict the night was holding back, and pressing
## it on a defeat sent them to the menu having seen neither the result nor why
## (review pass 1). After the reveal it dismisses, as V3.6's did -- a click
## that lands on it is a dismissal the player meant -- except within
## SKIP_GUARD_MS of a skip, so the second half of a double click on Skip count
## cannot dismiss a verdict that has been on screen for a tenth of a second.
func _on_footer_pressed() -> void:
	if Time.get_ticks_msec() < _guard_until:
		return
	if not _revealed:
		skip()
		_guard_until = Time.get_ticks_msec() + SKIP_GUARD_MS
		return
	hide()
	dismissed.emit()


## Lands the night on its final state: every figure the result's own, the
## verdict shown and settled. Public so a test and the screenshot tool take the
## path a click takes.
func skip() -> void:
	Motion.finish(self)
	for node in _verdict_nodes:
		if is_instance_valid(node):
			Motion.finish(node)
	Motion.finish(_title)


func _build_section(result: Dictionary, index: int, chamber_label: String, verdict := false) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var kind_label := tr("European Parliament election")
	if result["kind"] == "national":
		kind_label = tr("Snap legislative election") if bool(result.get("snap", false)) else tr("Legislative election")
	elif result["kind"] == "executive":
		kind_label = tr("Presidential election")
	PanelKit.line(box, "%s — %s" % [kind_label, chamber_label] if chamber_label != "" else kind_label, PanelKit.Tone.PLAIN)

	if result["kind"] == "executive":
		var winner_name := _party_name(result["largest_party_id"])
		_verdict_nodes.append(PanelKit.line(box, (
			tr("%s holds the office, first in the vote with %s%%.") if result["incumbent_largest"]
			else tr("%s takes the office; you polled %s%%.")
		) % [winner_name, PanelKit.Num.f(float(result["incumbent_vote_share"]) * 100.0, 1)], PanelKit.Tone.PLAIN))

	if result["kind"] == "national":
		var incumbent_name := _party_name(result["incumbent_party_id"])
		_verdict_nodes.append(PanelKit.line(box, (
			tr("%s remains the largest party: %d of %d seats.") if result["incumbent_largest"]
			else tr("%s is no longer the largest party: %d of %d seats.")
		) % [incumbent_name, result["incumbent_seats"], result["seats_total"]], PanelKit.Tone.PLAIN))

	# The verdict's own section reads verdict, then why, then the numbers -- a
	# result screen, not a spreadsheet (V2.9). The other sections on a
	# double-election panel keep table-then-attribution, which is where a
	# chamber's detail belongs.
	# The attribution says why the verdict went the way it did, so the night
	# holds it back with the verdict.
	var attribution := _build_attribution(result, verdict)
	_verdict_nodes.append(attribution)
	if verdict:
		box.add_child(attribution)
	box.add_child(_build_party_table(result, index))
	if not verdict:
		box.add_child(attribution)
	return box


func _build_party_table(result: Dictionary, index: int) -> Control:
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
	var rows: Array = [[tr("party"), tr("vote share")] + ([tr("seats")] if has_seats else [])]
	for party_id in ordered:
		var name_text := _party_name(party_id)
		if party_id == result["incumbent_party_id"]:
			name_text = tr("%s  (incumbent)") % name_text
		var row: Array = [
			name_text,
			"%s%%" % PanelKit.Num.f((float(shares.get(party_id, 0.0)) * 100.0), 1),
		]
		if has_seats:
			row.append(str(seats[party_id]))
		rows.append(row)

	var host := VBoxContainer.new()
	var grid := PanelKit.ledger(host, rows)
	# The count's handles on this table: each row's share and seats cells, read
	# out of the grid in PanelKit.ledger's row-major order, header row first.
	var columns: int = grid.columns
	var row_cells := {}
	for i in ordered.size():
		var party_id: String = ordered[i]
		var cell := {
			"result": index,
			"party": party_id,
			"share": grid.get_child((i + 1) * columns + 1),
			"seats": grid.get_child((i + 1) * columns + 2) if has_seats else null,
			"final_seats": int(seats.get(party_id, 0)),
			"bar": null,
			"final_bar": 0.0,
		}
		row_cells[party_id] = cell
		_cells.append(cell)

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
			# Built at the finished value the table already computed; the night
			# interpolates DISPLAY values only -- nothing about the result is
			# recomputed or gated on frames.
			bar.value = 100.0 * float(seats[party_id]) / float(total)
			row_cells[party_id]["bar"] = bar
			row_cells[party_id]["final_bar"] = bar.value
			bar.show_percentage = false
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar_row.add_child(bar)
			bars.add_child(bar_row)
		host.add_child(bars)
	return host


func _build_attribution(result: Dictionary, is_verdict := false) -> Control:
	var box := VBoxContainer.new()

	PanelKit.line(box, tr("What decided it"), PanelKit.Tone.PLAIN)

	for entry in result["attribution"]:
		var issue: String = entry["issue"]
		var satisfaction: float = entry["satisfaction"]
		var line := tr("%s — helped (salience %.0f%%)") if satisfaction > 0.05 else (tr("%s — hurt (salience %.0f%%)") if satisfaction < -0.05 else tr("%s — was neutral (salience %.0f%%)"))
		PanelKit.line(box, line % [OpinionK.ISSUE_LABEL[issue], entry["salience"] * 100.0], PanelKit.Tone.PLAIN)

	# Once, on the verdict's attribution only -- a sentence printed under every
	# table on a double-election panel is wallpaper, not a message.
	if is_verdict:
		PanelKit.line(box, tr(TOLD_LINE), PanelKit.Tone.DIM)

	return box


func _party_name(party_id: String) -> String:
	var ns = _state.player()
	for party in _loader.parties.get(ns.id, []):
		if party.id == party_id:
			return party.party_name
	return party_id
