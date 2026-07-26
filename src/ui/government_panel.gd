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

const Government = preload("res://src/sim/government.gd")
const GK = preload("res://src/sim/government_constants.gd")
const K = preload("res://src/sim/election_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")

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

var _state
var _loader
var _title: Label
var _body: VBoxContainer
var _dirty := true


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

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func():
		hide()
		closed.emit()
	)
	root.add_child(close)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


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

	_title.text = "%s %s — %s" % [ns.head_of_government_title, ns.pm_name, n.chamber_name]

	for child in _body.get_children():
		child.queue_free()

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
		if against >= needed:
			_add_line("A united opposition could bring this government down.")
		else:
			_add_line("The opposition cannot reach that threshold even united.")

		# What a censure motion would actually do right now, at the hostility a
		# forced bill would provoke. This is the number Article 49.3 gambles on,
		# so it is shown before the player gambles rather than after.
		var forced_for := 0
		for party in _loader.parties.get(ns.id, []):
			if Government.hostility(ns, party, true) > LK.ABSTAIN_BAND:
				forced_for += int(ns.seats_by_party.get(party.id, 0))
		_add_line("Under Article 49.3 today: %d seats would move to censure." % forced_for)
		if ns.formation_method == "presidential_appointment":
			if ns.force_cooldown_months > 0:
				_add_line("Article 49.3 unavailable for %d months." % ns.force_cooldown_months)
			elif forced_for >= needed:
				_add_line("Forcing a bill now would bring the government down.")
			else:
				_add_line("A forced bill would survive censure.")

	if ns.governments_fallen > 0:
		_add_line("Governments censured out of office this run: %d." % ns.governments_fallen)

	_add_line("")
	_add_line("Formation: %s." % METHOD_LABEL.get(ns.formation_method, ns.formation_method))
	_add_line("Agreed position: economic %+.2f, social %+.2f." % [
		ns.coalition_position["economic"], ns.coalition_position["social"]
	])

	_add_line("")
	_add_line("In government")
	_body.add_child(_build_partner_table(ns))

	var outside: Array[String] = []
	for party in _loader.parties.get(ns.id, []):
		if not ns.coalition_party_ids.has(party.id) and int(ns.seats_by_party.get(party.id, 0)) > 0:
			outside.append("%s (%d)" % [party.party_name, int(ns.seats_by_party.get(party.id, 0))])
	if not outside.is_empty():
		_add_line("")
		_add_line("In opposition: %s" % ", ".join(outside))


## One row per coalition partner: seats, distance from the agreed position, and
## the bonus that distance and its discipline actually buy on a government bill.
## The bonus column is the number legislature.gd reads, shown rather than
## described, so a partner drifting away from the line is visible before it
## costs a vote.
func _build_partner_table(ns) -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)

	for header in ["party", "seats", "distance", "reliability"]:
		var label := Label.new()
		label.text = header
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if header == "party" else HORIZONTAL_ALIGNMENT_RIGHT
		label.custom_minimum_size.x = 220 if header == "party" else 90
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

	return grid


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
