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
const DissolveButton = preload("res://src/ui/dissolve_button.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const JudiciaryK = preload("res://src/sim/judiciary_constants.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Removal = preload("res://src/sim/removal.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")
const GK = preload("res://src/sim/government_constants.gd")
const K = preload("res://src/sim/election_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const RepublicPlate = preload("res://src/ui/republic_plate.gd")
const ChartKit = preload("res://src/ui/chart_kit.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")
const Trends = preload("res://src/ui/trends.gd")
const Num = preload("res://src/ui/num.gd")

## Longest human label for a portfolio -- the panel names the spending line the
## player already knows from the Budget tab, not the internal key.
const PORTFOLIO_LABEL := {
	"health": "Health", "education": "Education", "defence": "Defence",  # i18n: msgid
	"pensions": "Pensions", "infrastructure": "Infrastructure",  # i18n: msgid
}

## Longest human label for each formation method. The panel names the rule the
## player is actually governing under rather than the enum, so a Frenchman is
## told there is no investiture vote instead of reading
## "presidential_appointment".
const METHOD_LABEL := {
	"presidential_appointment": "appointed by the President; no investiture vote",  # i18n: msgid
	"chancellor_election": "elected by the chamber on an absolute majority",  # i18n: msgid
	"investiture": "confirmed by an investiture vote",  # i18n: msgid
	"coalition_negotiation": "formed by coalition negotiation",  # i18n: msgid
	"largest_party": "formed by the largest party; no investiture vote",  # i18n: msgid
	"directorial": "seated by formula; the executive cannot fall",  # i18n: msgid
}

const CENSURE_LABEL := {
	"absolute_members": "an absolute majority of all members",  # i18n: msgid
	"constructive_absolute": "an absolute majority, naming a successor",  # i18n: msgid
	"simple_present": "a simple majority of those voting",  # i18n: msgid
	"none": "no censure motion exists",  # i18n: msgid
}

const DISSOLUTION_LABEL := {
	"executive_discretion": "may be dissolved at will",  # i18n: msgid
	"head_of_state_limited": "may be dissolved, except near the head of state's own term limit",  # i18n: msgid
	"confidence_failure": "may be dissolved only after a lost confidence vote",  # i18n: msgid
	"self_dissolution": "may only dissolve itself, by simple law",  # i18n: msgid
	"none": "cannot be dissolved",  # i18n: msgid
}

const AMENDMENT_LABEL := {
	"ordinary_law": "an ordinary majority, like any other law",  # i18n: msgid
	"three_fifths": "3/5 of the assembly",  # i18n: msgid
	"two_thirds": "2/3 of the assembly",  # i18n: msgid
	"three_quarters": "3/4 of the assembly",  # i18n: msgid
	"referendum_required": "an ordinary majority of the assembly, and then a referendum",  # i18n: msgid
}

## V1.7c. Silent under `none`, which is six of the ten: a line saying a country has
## no referendum is permanent furniture, and docs/society-model.md section 11's rule
## is that a readout silent at zero beats one that always prints.
## V1.1e. The wording is the CHAMBER's power over the player, not the chamber's own
## procedure: `suspensive` reads as a delay because that is what it costs, and
## `absolute` reads as a veto because that is what it is.
const VERDICT_LABEL := {
	ChambersK.VERDICT_NONE: "does not see",  # i18n: msgid
	ChambersK.VERDICT_SUSPENSIVE: "can delay",  # i18n: msgid
	ChambersK.VERDICT_ABSOLUTE: "can block",  # i18n: msgid
}

const REFERENDUM_LABEL := {
	"optional": "The head of state may put an amendment to the country instead, on an ordinary majority here.",  # i18n: msgid
	"mandatory": "Every amendment goes to the country; there is no path through the assembly alone.",  # i18n: msgid
}

## V1.7c, and this line exists because the SCREENSHOT PASS found it missing. The
## session made `election_system` live state and left no surface saying which one is
## live, so a player who passed the Proportional Representation Act could not read that
## it had taken effect until the next legislative election three years later -- a lever
## whose only feedback is a three-year wait is a lever with no readout at all.
##
## NEVER SILENT, unlike the referendum line above, and the distinction is the same one
## docs/credit-model.md drew for the rating: an absent referendum route is a fact about
## a constitution that most nations simply do not have, where every assembly in the
## world is elected somehow. What it says is how, not whether.
const ELECTION_SYSTEM_LABEL := {
	"pr_dhondt": "proportional representation, D'Hondt",  # i18n: msgid
	"pr_national": "national proportional representation",  # i18n: msgid
	"fptp": "single-member seats, one round",  # i18n: msgid
	"two_round": "single-member seats over two rounds",  # i18n: msgid
	"parallel": "a parallel mix of list and single-member seats",  # i18n: msgid
}

## The constitution plate's label tables (republic_plate.gd reads them, no copy).
const PLATE_LABELS := {"censure": CENSURE_LABEL, "dissolution": DISSOLUTION_LABEL, "method": METHOD_LABEL,
	"amendment": AMENDMENT_LABEL, "referendum": REFERENDUM_LABEL, "election": ELECTION_SYSTEM_LABEL}

var _state
var _loader
var _title: RichTextLabel
var _body: VBoxContainer
var _dirty := true
var _close_button: Button
var _dissolve_button: DissolveButton
var _portfolio_option: OptionButton
var _party_option: OptionButton
var _reassign_button: Button
var _reassign_status: Label
var _party_option_ids: Array[String] = []
## The constitution's folded plate (V5.2-0b); kept across refreshes so it stays open.
var _plate := RepublicPlate.new()


func _ready() -> void:
	custom_minimum_size = Vector2(560, 420)

	var root := PanelKit.padded(self, 16, 10)

	# A rich line since V5.1-d1b2 (G9): the head of government's name opens their card.
	_title = PanelKit.TermText.new()
	root.add_child(_title)

	# THE VERBS COME BEFORE THE READOUT -- V2.1b, and it is the fold contract's own
	# remedy rather than a preference. This panel's body runs to about 945px of
	# assembly arithmetic against a usable band of 826, so with the buttons under it
	# Dissolve sat 39px below the fold and no height could lift it: the band is the
	# ceiling and the content is taller than the band, which is V1.3g's finding
	# exactly. Ordering can, and it fixes it structurally -- the verb stays reachable
	# whatever the body grows to, where 39px of headroom would have been one added
	# row from failing again.
	# V5.2 b+ (R3): the one Dissolve button, the Legislature's too (dissolve_button.gd).
	_dissolve_button = DissolveButton.new()
	_dissolve_button.dissolved.connect(_on_dissolved)
	root.add_child(_dissolve_button)

	var reassign_row := HBoxContainer.new()
	reassign_row.add_theme_constant_override("separation", 8)
	root.add_child(reassign_row)

	_portfolio_option = OptionButton.new()
	for f in CK.PORTFOLIO_KEYS:
		_portfolio_option.add_item(tr(PORTFOLIO_LABEL.get(f, f)))
	reassign_row.add_child(_portfolio_option)

	_party_option = OptionButton.new()
	reassign_row.add_child(_party_option)

	_reassign_button = Button.new()
	_reassign_button.text = tr("Reassign")
	_reassign_button.pressed.connect(_on_reassign)
	reassign_row.add_child(_reassign_button)

	_reassign_status = Label.new()
	_reassign_status.theme_type_variation = UiTheme.CAPTION
	root.add_child(_reassign_status)


	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	root.add_child(_body)

	_close_button = Button.new()
	_close_button.text = tr("Close")
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
	var n = _loader.nations.get(ns.id)
	if n == null:
		return

	_title.set_marked("%s %s — %s" % [ns.head_of_government_title, PanelKit.person(ns.pm_person_id, _loader.person_name(ns.pm_person_id)), n.chamber_name])

	for child in _body.get_children():
		if child == _plate:
			_body.remove_child(_plate)
		else:
			child.queue_free()

	# V5.2-0b (docs/design/v5.2-legibility.md): the live arithmetic, short, under
	# the seat bar it reads; the constitution folds into its plate (the author's
	# "Une plaque repliée"); the tables get real headings.
	_seat_bar(ns)
	PanelKit.line(_body, tr("COHABITATION — the assembly majority is against you") if ns.is_cohabitation 		else (tr("MINORITY GOVERNMENT") if ns.is_minority else tr("Majority government")), PanelKit.Tone.PLAIN)
	PanelKit.line(_body, tr("%d of %d seats · a majority needs %d") % [ns.coalition_seats, ns.assembly_seats, Government.majority_seats(ns) + 1], PanelKit.Tone.PLAIN)
	# Seats a party holds are not seats it necessarily delivers (V1.1b).
	var breakable := _worst_case_rebels(ns)
	if breakable > 0:
		PanelKit.line(_body, tr("Up to %d may break ranks, leaving %d") % [breakable, ns.coalition_seats - breakable], PanelKit.Tone.PLAIN)
	if ns.censure_rule != "none":
		var needed := Government.censure_seats(ns)
		var against: int = int(ns.assembly_seats) - int(ns.coalition_seats)
		PanelKit.line(_body, tr("Censure needs %d · the opposition holds %d") % [needed, against], PanelKit.Tone.PLAIN)
		if against >= needed:
			PanelKit.line(_body, tr("The opposition could bring this government down on its own."), PanelKit.Tone.PLAIN)
		# Only a constitution with Article 49.3 has this tally: the same gate as
		# Government.can_force. Resolved through the real resolver (V1.1b: a motion
		# collects seats from parties whose line is against it).
		if ns.formation_method == "presidential_appointment":
			var forced := Government.resolve_censure(ns, _loader.parties.get(ns.id, []), true)
			var rebels := 0
			for pid in forced["party_rebels"]:
				rebels += int(forced["party_rebels"][pid])
			PanelKit.rich(_body, tr("Under [g=article_49_3]Article 49.3[/g] today: %d seats would move to censure%s.") % [
				forced["for_seats"],
				tr(", %d of them against their own party's line") % rebels if rebels > 0 else "",
			], PanelKit.Tone.PLAIN)
			if ns.force_cooldown_months > 0:
				PanelKit.line(_body, tr("Article 49.3 unavailable for %d months.") % ns.force_cooldown_months, PanelKit.Tone.PLAIN)
			elif forced["carried"]:
				PanelKit.line(_body, tr("Forcing a bill now would bring the government down."), PanelKit.Tone.PLAIN)
			else:
				PanelKit.line(_body, tr("A forced bill would survive censure."), PanelKit.Tone.PLAIN)
	if ns.governments_fallen > 0:
		PanelKit.line(_body, tr("Governments censured out of office this run: %d.") % ns.governments_fallen, PanelKit.Tone.PLAIN)

	_dissolve_button.sync(_state, ns)

	_body.add_child(_plate)
	_plate.fill(ns, _loader, PLATE_LABELS, _upper_phrase(ns), _court_phrase(ns))

	PanelKit.heading(_body, tr("In government"))
	_body.add_child(_build_partner_table(ns))

	PanelKit.heading(_body, tr("Cabinet"))
	_body.add_child(_build_cabinet_table(ns))
	if ns.resignations_count > 0:
		var last: Dictionary = ns.last_resignation
		var last_party := ""
		if _loader != null:
			for party in _loader.parties.get(ns.id, []):
				if party.id == String(last.get("party_id", "")):
					last_party = party.party_name
		PanelKit.line(_body, tr("Ministers resigned this run: %d (last: %s over %s)") % [
			ns.resignations_count, last_party, tr(PORTFOLIO_LABEL.get(last.get("portfolio", ""), last.get("portfolio", "")))
		], PanelKit.Tone.PLAIN)
	_refresh_party_option(ns)

	var outside: Array[String] = []
	for party in _loader.parties.get(ns.id, []):
		if not ns.coalition_party_ids.has(party.id) and int(ns.seats_by_party.get(party.id, 0)) > 0:
			outside.append("%s (%d)" % [party.party_name, int(ns.seats_by_party.get(party.id, 0))])
	if not outside.is_empty():
		PanelKit.heading(_body, tr("In opposition"))
		PanelKit.line(_body, ", ".join(outside), PanelKit.Tone.PLAIN)


## The assembly as a hemicycle (V5.2 b+ R6; a bar since V5.2-0b): the government's parties, then the
## opposition's, each in the slot the Legislature's bar gives it (the colour follows
## the party, never its side), the majority and the censure threshold marked.
func _seat_bar(ns) -> void:
	var parties: Array = _loader.parties.get(ns.id, [])
	var parts: Array = []
	var colors: Array = []
	for in_government in [true, false]:
		for i in parties.size():
			if ns.coalition_party_ids.has(parties[i].id) == in_government:
				parts.append({"label": String(parties[i].party_name), "value": float(ns.seats_by_party.get(parties[i].id, 0))})
				colors.append(ChartStyle.SERIES[mini(i, ChartStyle.SERIES.size() - 1)])
	var marks := [float(Government.majority_seats(ns) + 1) / maxf(float(ns.assembly_seats), 1.0)]
	if ns.censure_rule != "none":
		marks.append(float(Government.censure_seats(ns)) / maxf(float(ns.assembly_seats), 1.0))
	ChartKit.hemicycle(_body, tr("Government, then opposition — the lines mark a majority and censure"), parts,
		{"markers": marks, "colors": colors, "places": 0, "unit": tr(" seats")})


## One row per coalition partner: seats, distance from the agreed position, the
## bonus that distance and its discipline actually buy on a government bill, the
## live discipline behind that bonus, and how many of the party's seats would
## break ranks on a bill it dislikes.
##
## The reliability column is the number legislature.gd reads and the discipline
## column is the number that moves; showing both is what makes a partner drifting
## away from the line visible before it costs a vote rather than after.
## What the second chamber can do, per class of bill. Two rows, because the real
## distinction is between an ordinary bill and a constitutional revision and not
## between second chambers -- France's Senat delays the first under Art. 45 and cannot
## be overridden on the second under Art. 89.
func _upper_phrase(ns) -> String:
	var ordinary: String = tr(VERDICT_LABEL.get(ns.upper_ordinary, ns.upper_ordinary))
	var amendment: String = tr(VERDICT_LABEL.get(ns.upper_amendment, ns.upper_amendment))
	if ns.upper_ordinary == ns.upper_amendment:
		return tr("%s any bill") % ordinary
	return tr("%s an ordinary bill and %s an amendment") % [ordinary, amendment]


## The court, with the ARITHMETIC and not just the label. A rule the player cannot read
## is not a check on their power, it is a trap -- docs/judiciary-model.md.
func _court_phrase(ns) -> String:
	if ns.judicial_review == JudiciaryK.REVIEW_NONE:
		return tr("No court may strike down an Act of the legislature.")
	var drift: float = Judiciary.independence_deviation(ns)
	var text := tr("Rule of law %s; the court strikes a bill reaching past %s.") % [
		Num.f(ns.judicial_independence, 1), Num.f(Judiciary.tolerance(ns), 2)]
	if absf(drift) >= 0.05:
		text += tr("  %s since the start.") % Num.fs(drift, 1)
	return text


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
		grid.add_child(_right(Num.f(sqrt(d_econ * d_econ + d_social * d_social), 2)))

		var bonus := Government.coalition_bonus(ns, party)
		grid.add_child(_right("%.0f%%" % (bonus / GK.COALITION_BONUS_MAX * 100.0)))

		# Live against authored, because the drift is the story. A party sitting
		# at its own ceiling prints one number; one that has slipped prints both.
		var live := Discipline.of(ns, party)
		var base := Discipline.base_of(party)
		var discipline_cell := _right(Num.f(live, 2))
		if live < base - 0.005:
			discipline_cell.text = tr("%s of %s") % [Num.f(live, 2), Num.f(base, 2)]
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
		PanelKit.line(grid, tr(PORTFOLIO_LABEL.get(f, f)), PanelKit.Tone.PLAIN)

		var pid: String = String(ns.cabinet.get(f, ""))
		var holder_label := Label.new()
		if pid == "" or not by_id.has(pid):
			holder_label.text = tr("VACANT")
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
				entitlement_cell.text = tr("%d of %d") % [h, ent]
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
	# V5.2 b+ R4: the command refuses with its reason (Removal.why_not), or prices
	# the removal and seats the party.
	var before := Trends.snapshot_now(_state)
	var result: Dictionary = Removal.reassign(_state, _loader, portfolio, party_id)
	_reassign_status.text = String(result["error"])
	if not bool(result["ok"]):
		_reassign_status.theme_type_variation = UiTheme.BAD_TEXT
		return
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


func _on_dissolved(before: Dictionary) -> void:
	dissolved.emit(before)
	_dirty = true


func _right(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


## The control this panel exists to let the player press -- V2.1a's fold contract.
##
## Both verbs are built once in _ready() and live for the session, so unlike the
## action panels there is nothing to re-find on a refresh. Dissolve first because
## it is first in the layout and the rule is "the first verb", not "the most
## important one" -- a panel whose FIRST verb has scrolled off is already a panel
## whose verbs are hidden, and deciding which of two is more important is a
## judgement this contract does not need to make.
##
## Falls through to Reassign where the nation's dissolution rule hides Dissolve
## outright, which is six of the ten.
func primary_action() -> Control:
	if _dissolve_button != null and _dissolve_button.visible:
		return _dissolve_button
	return _reassign_button
