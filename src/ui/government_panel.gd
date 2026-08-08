extends PanelContainer

## The government panel V1.1a adds -- who is in the government, how close it is
## to the line that can bring it down, and how dependable each partner is.
##
## Reads simulation state and never writes it. There is no player command here
## yet: forming a government is something Elections and Government do at a
## schedule boundary, and the censure motion and Article 49.3 are the next
## session's work. See docs/government-model.md.
##
## Built in code, like the other panels -- see budget_panel.gd's placement note.

signal closed

## Carries the pre-command baseline, the same shape budget_panel.gd's
## `committed` and law_panel.gd's `proposed` use, so main.gd's effect-queueing
## treats a dissolution the same way it treats any other player command.
signal dissolved(before: Dictionary)

## Carries the pre-command baseline for a cabinet reassignment -- the same
## shape `dissolved` above uses, so main.gd's effect-queueing treats a
## reshuffle the same way it treats any other player command.
signal reassigned(before: Dictionary)

const Government = preload("res://src/sim/government.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")
const GK = preload("res://src/sim/government_constants.gd")
const K = preload("res://src/sim/election_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Trends = preload("res://src/ui/trends.gd")

## Longest human label for a portfolio -- the panel names the spending line the
## player already knows from the Budget tab, not the internal key.
const PORTFOLIO_LABEL := {
	"health": "Health", "education": "Education", "defence": "Defence",
	"pensions": "Pensions", "infrastructure": "Infrastructure",
}

## Longest human label for each formation method. The panel names the rule the
## player is actually governing under rather than the enum, so a Frenchman is
## told there is no investiture vote instead of reading
## "presidential_appointment".
const METHOD_LABEL := {
	"presidential_appointment": "appointed by the President; no investiture vote",
	"chancellor_election": "elected by the chamber on an absolute majority",
	"investiture": "confirmed by an investiture vote",
	"coalition_negotiation": "formed by coalition negotiation",
	"largest_party": "formed by the largest party; no investiture vote",
	"directorial": "seated by formula; the executive cannot fall",
}

const CENSURE_LABEL := {
	"absolute_members": "an absolute majority of all members",
	"constructive_absolute": "an absolute majority, naming a successor",
	"simple_present": "a simple majority of those voting",
	"none": "no censure motion exists",
}

const DISSOLUTION_LABEL := {
	"executive_discretion": "may be dissolved at will",
	"head_of_state_limited": "may be dissolved, except near the head of state's own term limit",
	"confidence_failure": "may be dissolved only after a lost confidence vote",
	"self_dissolution": "may only dissolve itself, by simple law",
	"none": "cannot be dissolved",
}

const AMENDMENT_LABEL := {
	"ordinary_law": "an ordinary majority, like any other law",
	"three_fifths": "3/5 of the assembly",
	"two_thirds": "2/3 of the assembly",
	"three_quarters": "3/4 of the assembly",
	"referendum_required": "a mandatory referendum; not proposable in this game",
}

var _state
var _loader
var _title: Label
var _body: VBoxContainer
var _dirty := true
var _close_button: Button
var _dissolve_button: Button
var _portfolio_option: OptionButton
var _party_option: OptionButton
var _reassign_button: Button
var _reassign_status: Label
var _party_option_ids: Array[String] = []


func _ready() -> void:
	custom_minimum_size = Vector2(560, 420)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_title = Label.new()
	root.add_child(_title)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	root.add_child(_body)

	_dissolve_button = Button.new()
	_dissolve_button.text = "Dissolve"
	_dissolve_button.pressed.connect(_on_dissolve)
	root.add_child(_dissolve_button)

	var reassign_row := HBoxContainer.new()
	reassign_row.add_theme_constant_override("separation", 8)
	root.add_child(reassign_row)

	_portfolio_option = OptionButton.new()
	for f in CK.PORTFOLIO_KEYS:
		_portfolio_option.add_item(PORTFOLIO_LABEL.get(f, f))
	reassign_row.add_child(_portfolio_option)

	_party_option = OptionButton.new()
	reassign_row.add_child(_party_option)

	_reassign_button = Button.new()
	_reassign_button.text = "Reassign"
	_reassign_button.pressed.connect(_on_reassign)
	reassign_row.add_child(_reassign_button)

	_reassign_status = Label.new()
	_reassign_status.theme_type_variation = UiTheme.CAPTION
	root.add_child(_reassign_status)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func():
		hide()
		closed.emit()
	)
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


## Docked-tab mode -- see budget_panel.gd's hide_close_button() for why.
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
	var n = _loader.nations.get(ns.id)
	if n == null:
		return

	_title.text = "%s %s — %s" % [ns.head_of_government_title, _loader.person_name(ns.pm_person_id), n.chamber_name]

	for child in _body.get_children():
		child.queue_free()

	var system = _loader.political_systems.get(ns.system_id)
	_add_line("%s." % (system.display_name if system != null else ns.system_id))
	if ns.head_of_state_kind != "executive_president":
		_add_line("Head of state: %s %s." % [ns.head_of_state_title, _loader.person_name(ns.head_of_state_person_id)])
	if ns.term_limit > 0:
		_add_line("Term limit: %d of %d served." % [ns.terms_served, ns.term_limit])

	var standing := "Majority government"
	if ns.is_cohabitation:
		standing = "COHABITATION — the assembly majority is against you"
	elif ns.is_minority:
		standing = "MINORITY GOVERNMENT"
	_add_line(standing)

	var majority := Government.majority_seats(ns)
	_add_line("%d of %d seats; a majority needs more than %d." % [
		ns.coalition_seats, ns.assembly_seats, majority
	])

	# The V1.1b reading, and the one that makes the line above less comforting
	# than it looks: seats a party holds are not seats it necessarily delivers.
	var breakable := _worst_case_rebels(ns)
	if breakable > 0:
		_add_line("Up to %d of those break ranks on a bill their own party dislikes, leaving %d." % [
			breakable, ns.coalition_seats - breakable
		])

	if ns.censure_rule == "none":
		_add_line("Censure: %s." % CENSURE_LABEL[ns.censure_rule])
	else:
		var needed := Government.censure_seats(ns)
		var against: int = int(ns.assembly_seats) - int(ns.coalition_seats)
		_add_line("Censure needs %d seats — %s. The opposition holds %d." % [
			needed, CENSURE_LABEL.get(ns.censure_rule, ns.censure_rule), against
		])
		# The honest reading of a French minority government: the opposition can
		# only ever remove you if it votes together, which is why so few do.
		#
		# Both phrasings say "on its own" since V1.1b, because coalition seats
		# move too now -- without that, this line and the 49.3 tally below read
		# as a flat contradiction whenever discipline has eroded.
		if against >= needed:
			_add_line("The opposition could bring this government down on its own.")
		else:
			_add_line("The opposition cannot reach that threshold on its own, even united.")

		# What a censure motion would actually do right now, at the hostility a
		# forced bill would provoke. This is the number Article 49.3 gambles on,
		# so it is shown before the player gambles rather than after.
		#
		# Resolved through the real resolver rather than counted party by party:
		# since V1.1b a motion collects seats from parties whose line is against
		# it, and a tally that missed those would read safer than the vote is.
		var forced := Government.resolve_censure(ns, _loader.parties.get(ns.id, []), true)
		var rebels := 0
		for pid in forced["party_rebels"]:
			rebels += int(forced["party_rebels"][pid])
		_add_line("Under Article 49.3 today: %d seats would move to censure%s." % [
			forced["for_seats"],
			", %d of them against their own party's line" % rebels if rebels > 0 else "",
		])
		if ns.formation_method == "presidential_appointment":
			if ns.force_cooldown_months > 0:
				_add_line("Article 49.3 unavailable for %d months." % ns.force_cooldown_months)
			elif forced["carried"]:
				_add_line("Forcing a bill now would bring the government down.")
			else:
				_add_line("A forced bill would survive censure.")

	if ns.governments_fallen > 0:
		_add_line("Governments censured out of office this run: %d." % ns.governments_fallen)

	_add_line("")
	_add_line("%s %s." % [n.chamber_name, DISSOLUTION_LABEL.get(ns.dissolution_rule, ns.dissolution_rule)])
	if ns.dissolution_rule == "executive_discretion" or ns.dissolution_rule == "head_of_state_limited":
		_add_line("Costs public patience on every call, and locks out further use for %d months once the new assembly is seated." % ns.dissolution_lockout_months)
	if ns.dissolutions_called > 0:
		_add_line("Dissolutions called this run: %d." % ns.dissolutions_called)

	var can_dissolve := Dissolution.can_dissolve(_state, ns)
	_dissolve_button.visible = ns.dissolution_rule != "none" and ns.dissolution_rule != "confidence_failure" and ns.dissolution_rule != "self_dissolution"
	_dissolve_button.disabled = not can_dissolve
	if not can_dissolve:
		_dissolve_button.tooltip_text = Dissolution.refusal_reason(_state, ns)
	else:
		_dissolve_button.tooltip_text = "Call a snap election. No seat forecast -- read the polls, not a projection."

	_add_line("")
	_add_line("Formation: %s." % METHOD_LABEL.get(ns.formation_method, ns.formation_method))
	_add_line("Agreed position: economic %+.2f, social %+.2f." % [
		ns.coalition_position["economic"], ns.coalition_position["social"]
	])
	_add_line("A constitutional amendment needs %s." % AMENDMENT_LABEL.get(ns.amendment_rule, ns.amendment_rule))

	_add_line("")
	_add_line("In government")
	_body.add_child(_build_partner_table(ns))

	_add_line("")
	_add_line("Cabinet")
	_body.add_child(_build_cabinet_table(ns))
	if ns.resignations_count > 0:
		var last: Dictionary = ns.last_resignation
		var last_party := ""
		if _loader != null:
			for party in _loader.parties.get(ns.id, []):
				if party.id == String(last.get("party_id", "")):
					last_party = party.party_name
		_add_line("Ministers resigned this run: %d (last: %s over %s)" % [
			ns.resignations_count, last_party, PORTFOLIO_LABEL.get(last.get("portfolio", ""), last.get("portfolio", ""))
		])
	_refresh_party_option(ns)

	var outside: Array[String] = []
	for party in _loader.parties.get(ns.id, []):
		if not ns.coalition_party_ids.has(party.id) and int(ns.seats_by_party.get(party.id, 0)) > 0:
			outside.append("%s (%d)" % [party.party_name, int(ns.seats_by_party.get(party.id, 0))])
	if not outside.is_empty():
		_add_line("")
		_add_line("In opposition: %s" % ", ".join(outside))


## One row per coalition partner: seats, distance from the agreed position, the
## bonus that distance and its discipline actually buy on a government bill, the
## live discipline behind that bonus, and how many of the party's seats would
## break ranks on a bill it dislikes.
##
## The reliability column is the number legislature.gd reads and the discipline
## column is the number that moves; showing both is what makes a partner drifting
## away from the line visible before it costs a vote rather than after.
func _build_partner_table(ns) -> Control:
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 16)

	for header in ["party", "seats", "distance", "reliability", "discipline", "rebels"]:
		var label := Label.new()
		label.text = header
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if header == "party" else HORIZONTAL_ALIGNMENT_RIGHT
		label.custom_minimum_size.x = 200 if header == "party" else 84
		label.theme_type_variation = UiTheme.CAPTION
		grid.add_child(label)

	var by_id := {}
	for party in _loader.parties.get(ns.id, []):
		by_id[party.id] = party

	# Biggest partner first; the premiership follows seats, so this reads top-down
	# as the order of standing in the government.
	var ordered: Array = ns.coalition_party_ids.duplicate()
	ordered.sort_custom(func(a, b): return int(ns.seats_by_party.get(a, 0)) > int(ns.seats_by_party.get(b, 0)))

	for pid in ordered:
		if not by_id.has(pid):
			continue
		var party = by_id[pid]

		var name_label := Label.new()
		name_label.text = party.party_name
		if pid == ns.pm_party_id:
			name_label.text += "  (%s)" % ns.head_of_government_title
		grid.add_child(name_label)

		grid.add_child(_right(str(int(ns.seats_by_party.get(pid, 0)))))

		var pos: Dictionary = K.SLOT_POSITION.get(party.ideology_slot, {"economic": 0.0, "social": 0.0})
		var d_econ: float = float(pos["economic"]) - float(ns.coalition_position["economic"])
		var d_social: float = float(pos["social"]) - float(ns.coalition_position["social"])
		grid.add_child(_right("%.2f" % sqrt(d_econ * d_econ + d_social * d_social)))

		var bonus := Government.coalition_bonus(ns, party)
		grid.add_child(_right("%.0f%%" % (bonus / GK.COALITION_BONUS_MAX * 100.0)))

		# Live against authored, because the drift is the story. A party sitting
		# at its own ceiling prints one number; one that has slipped prints both.
		var live := Discipline.of(ns, party)
		var base := Discipline.base_of(party)
		var discipline_cell := _right("%.2f" % live)
		if live < base - 0.005:
			discipline_cell.text = "%.2f of %.2f" % [live, base]
			discipline_cell.theme_type_variation = UiTheme.BAD_TEXT
		grid.add_child(discipline_cell)

		# The worst a bill can cost this party: the whip's full pull IS the
		# coalition bonus, so that bonus is the strain, measured against members
		# who would otherwise vote the other way.
		grid.add_child(_right(str(Discipline.rebel_seats(ns, party, bonus, 0.0))))

	return grid


## One row per portfolio: holder, effectiveness against the neutral 100% a
## party of average skill and perfect affinity would deliver, and whether the
## holder is short of its d'Hondt entitlement -- the condition that makes a
## resignation reachable. See docs/cabinet-model.md.
func _build_cabinet_table(ns) -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)

	for header in ["portfolio", "holder", "effectiveness", "entitlement"]:
		var label := Label.new()
		label.text = header
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if header in ["portfolio", "holder"] else HORIZONTAL_ALIGNMENT_RIGHT
		label.custom_minimum_size.x = 140 if header in ["portfolio", "holder"] else 100
		label.theme_type_variation = UiTheme.CAPTION
		grid.add_child(label)

	var by_id := {}
	for party in _loader.parties.get(ns.id, []):
		by_id[party.id] = party

	var held := {}
	for f in ns.cabinet:
		var pid: String = String(ns.cabinet[f])
		if pid != "":
			held[pid] = int(held.get(pid, 0)) + 1

	for f in CK.PORTFOLIO_KEYS:
		var portfolio_label := Label.new()
		portfolio_label.text = PORTFOLIO_LABEL.get(f, f)
		grid.add_child(portfolio_label)

		var pid: String = String(ns.cabinet.get(f, ""))
		var holder_label := Label.new()
		if pid == "" or not by_id.has(pid):
			holder_label.text = "VACANT"
			holder_label.theme_type_variation = UiTheme.BAD_TEXT
		else:
			holder_label.text = by_id[pid].party_name
		grid.add_child(holder_label)

		var eff := Cabinet.effectiveness(ns, f)
		var eff_cell := _right("%.0f%%" % (eff * 100.0))
		if eff > 1.0:
			eff_cell.theme_type_variation = UiTheme.GOOD_TEXT
		elif eff < 1.0:
			eff_cell.theme_type_variation = UiTheme.BAD_TEXT
		grid.add_child(eff_cell)

		var entitlement_cell := _right("")
		if pid != "" and by_id.has(pid):
			var ent := int(ns.cabinet_entitlement.get(pid, 0))
			var h := int(held.get(pid, 0))
			if h < ent:
				entitlement_cell.text = "%d of %d" % [h, ent]
				entitlement_cell.theme_type_variation = UiTheme.BAD_TEXT
		grid.add_child(entitlement_cell)

	return grid


## Coalition parties only -- can_assign() refuses everything else. Rebuilt on
## every refresh because the coalition itself can change under the panel
## between one election and the next.
func _refresh_party_option(ns) -> void:
	_party_option.clear()
	_party_option_ids.clear()
	var by_id := {}
	for party in _loader.parties.get(ns.id, []):
		by_id[party.id] = party
	var ordered: Array = ns.coalition_party_ids.duplicate()
	ordered.sort_custom(func(a, b): return int(ns.seats_by_party.get(a, 0)) > int(ns.seats_by_party.get(b, 0)))
	for pid in ordered:
		if not by_id.has(pid):
			continue
		_party_option.add_item(by_id[pid].party_name)
		_party_option_ids.append(pid)


func _on_reassign() -> void:
	var ns = _state.player()
	if ns == null:
		return
	var idx := _portfolio_option.selected
	if idx < 0 or idx >= CK.PORTFOLIO_KEYS.size():
		return
	var party_idx := _party_option.selected
	if party_idx < 0 or party_idx >= _party_option_ids.size():
		return

	var portfolio: String = CK.PORTFOLIO_KEYS[idx]
	var party_id: String = _party_option_ids[party_idx]
	if not Cabinet.can_assign(ns, portfolio, party_id):
		_reassign_status.text = Cabinet.refusal_reason(ns, portfolio, party_id)
		_reassign_status.theme_type_variation = UiTheme.BAD_TEXT
		return

	var before := Trends.snapshot_now(_state)
	Cabinet.assign(_state, portfolio, party_id, _loader.parties.get(ns.id, []))
	_reassign_status.text = ""
	reassigned.emit(before)
	_dirty = true


## Seats the coalition would lose on the worst bill for it -- one its partners
## are whipped hardest to support and like least. The whip's full pull is the
## coalition bonus, so that bonus is the strain; see docs/discipline-model.md.
func _worst_case_rebels(ns) -> int:
	var total := 0
	for party in _loader.parties.get(ns.id, []):
		if not ns.coalition_party_ids.has(party.id):
			continue
		total += Discipline.rebel_seats(ns, party, Government.coalition_bonus(ns, party), 0.0)
	return total


func _on_dissolve() -> void:
	var ns = _state.player()
	if ns == null:
		return
	var before := Trends.snapshot_now(_state)
	Dissolution.dissolve(_state, ns)
	dissolved.emit(before)
	_dirty = true


func _right(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


func _add_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(label)
