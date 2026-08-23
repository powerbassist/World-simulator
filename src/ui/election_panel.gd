extends PanelContainer

## The election result screen. Shown once for every month an election lands —
## which can mean one national result, one EP result, or both at once (France
## and Belgium in June 2029). Reads simulation state and never writes it; the
## only player intent it sends back is "continue", which does not touch
## GameState at all — it just tells main.gd to unpause the clock.
##
## Built in code, like the other two panels — a generated list of party rows
## per result, which a scene file would describe worse.

const K = preload("res://src/sim/election_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

signal dismissed

var _state
var _loader
var _title: Label
var _sections: VBoxContainer
var _footer: Control


func _ready() -> void:
	# Placement is the owner's job — see the note in budget_panel.gd. Same bug
	# class: a preset in _ready() lands this in the corner before it has a size.
	custom_minimum_size = Vector2(640, 520)

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
		var why := Label.new()
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.text = "%s has served %d terms as %s, the most the constitution allows, and cannot stand again. The office passes to whoever wins the election you are not in." % [
			_loader.person_name(ns.head_of_state_person_id),
			ns.terms_served,
			_loader.nations[ns.id].executive_title,
		]
		_sections.add_child(why)
	elif executive != null:
		_sections.add_child(_build_section(executive, _loader.nations[ns.id].executive_title))
	if national != null:
		_sections.add_child(_build_section(national, _loader.nations[ns.id].chamber_name))
	if eu_result != null:
		_sections.add_child(_build_section(eu_result, ""))

	if national != null and ns.has_executive and not defeated:
		var gov := Label.new()
		if ns.is_cohabitation:
			gov.text = "The new Assembly is against you. %s %s leads a government you did not choose." % [
				ns.head_of_government_title, _loader.person_name(ns.pm_person_id)
			]
		elif ns.is_minority:
			gov.text = "%s %s heads a minority government: %d of %d seats." % [
				ns.head_of_government_title, _loader.person_name(ns.pm_person_id), ns.coalition_seats, ns.assembly_seats
			]
		else:
			gov.text = "%s %s forms a government with %d of %d seats." % [
				ns.head_of_government_title, _loader.person_name(ns.pm_person_id), ns.coalition_seats, ns.assembly_seats
			]
		_sections.add_child(gov)

	# V1.6 audit, V2. The footer gets a control in BOTH branches. It used to build
	# the button only on the winning side, and main.gd unpauses only on `dismissed`
	# -- so a defeated player was left with a plate carrying nothing to press, over
	# a HUD that stayed live because the holder is MOUSE_FILTER_IGNORE. Space
	# unpaused it and the run continued indefinitely behind a "DEFEATED" title.
	if defeated:
		var over := Label.new()
		if termed_out:
			over.text = "You have served the maximum number of terms. You leave office."
		else:
			over.text = "You have lost your office. This term is over."
		_footer.add_child(over)

	var cont := Button.new()
	cont.text = "Leave office" if defeated else "Continue"
	cont.pressed.connect(func(): hide(); dismissed.emit())
	_footer.add_child(cont)


func _build_section(result: Dictionary, chamber_label: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var heading := Label.new()
	var kind_label := "European Parliament election"
	if result["kind"] == "national":
		kind_label = "Snap legislative election" if bool(result.get("snap", false)) else "Legislative election"
	elif result["kind"] == "executive":
		kind_label = "Presidential election"
	heading.text = "%s — %s" % [kind_label, chamber_label] if chamber_label != "" else kind_label
	box.add_child(heading)

	if result["kind"] == "executive":
		var won := Label.new()
		var winner_name := _party_name(result["largest_party_id"])
		if result["incumbent_largest"]:
			won.text = "%s holds the office on %.1f%% of the vote." % [
				winner_name, float(result["incumbent_vote_share"]) * 100.0
			]
		else:
			won.text = "%s takes the office; you polled %.1f%%." % [
				winner_name, float(result["incumbent_vote_share"]) * 100.0
			]
		box.add_child(won)

	if result["kind"] == "national":
		var verdict := Label.new()
		var incumbent_name := _party_name(result["incumbent_party_id"])
		if result["incumbent_largest"]:
			verdict.text = "%s remains the largest party: %d of %d seats." % [
				incumbent_name, result["incumbent_seats"], result["seats_total"]
			]
		else:
			verdict.text = "%s is no longer the largest party: %d of %d seats." % [
				incumbent_name, result["incumbent_seats"], result["seats_total"]
			]
		box.add_child(verdict)

	box.add_child(_build_party_table(result))
	box.add_child(_build_attribution(result))
	return box


func _build_party_table(result: Dictionary) -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)

	for header in ["party", "vote share", "seats"]:
		var label := Label.new()
		label.text = header
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if header == "party" else HORIZONTAL_ALIGNMENT_RIGHT
		label.custom_minimum_size.x = 220 if header == "party" else 90
		grid.add_child(label)

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

	for party_id in ordered:
		var name_label := Label.new()
		name_label.text = _party_name(party_id)
		if party_id == result["incumbent_party_id"]:
			name_label.text += "  (incumbent)"
		grid.add_child(name_label)

		var share_label := Label.new()
		share_label.text = "%.1f%%" % (float(shares.get(party_id, 0.0)) * 100.0)
		share_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(share_label)

		var seat_label := Label.new()
		seat_label.text = str(seats[party_id]) if seats.has(party_id) else "—"
		seat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(seat_label)

	return grid


func _build_attribution(result: Dictionary) -> Control:
	var box := VBoxContainer.new()

	var heading := Label.new()
	heading.text = "What decided it"
	box.add_child(heading)

	for entry in result["attribution"]:
		var issue: String = entry["issue"]
		var satisfaction: float = entry["satisfaction"]
		var line := Label.new()
		var mood := "helped" if satisfaction > 0.05 else ("hurt" if satisfaction < -0.05 else "was neutral")
		line.text = "%s — %s (salience %.0f%%)" % [OpinionK.ISSUE_LABEL[issue], mood, entry["salience"] * 100.0]
		box.add_child(line)

	return box


func _party_name(party_id: String) -> String:
	var ns = _state.player()
	for party in _loader.parties.get(ns.id, []):
		if party.id == party_id:
			return party.party_name
	return party_id
