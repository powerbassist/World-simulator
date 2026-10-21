extends RefCounted

## The player's side of the council: working the room (bargains), the IOUs the
## player owes, and the agenda verbs (set it when chairing, pay to table it
## otherwise). Split from council_section.gd at V4.5b2 T3 so the read-out and
## the verbs do not share one file.
##
## Static builders like council_section.gd. Presses go back as the panel's bound
## methods (`_on_bargain`, `_on_set_agenda`, `_on_table`), so a refusal speaks
## through the panel's `_refusal_text` and `acted` is emitted in one place. The
## open/closed state of each fold lives on the panel (`section_open`), because
## the panel rebuilds its whole body on every refresh.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Council = preload("res://src/sim/council.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")
const BK = preload("res://src/sim/bloc_constants.gd")
const Relations = preload("res://src/core/relations.gd")
const Strings = preload("res://src/ui/strings.gd")

## More rows than this and the table is a wall; the rest are the settled ones
## (furthest from the threshold), which a bargain cannot move anyway.
const MAX_ROWS := 12
const MONTHS: Array = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


## A fold: a toggle button over a VBox. Returns the VBox; the caller fills it.
static func _fold(body: VBoxContainer, panel, key: String, title: String) -> VBoxContainer:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	var open: bool = panel.is_section_open(key)
	inner.visible = open
	var toggle := Button.new()
	toggle.text = ("%s  ▾" if open else "%s  ▸") % title
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.pressed.connect(func() -> void:
		var now: bool = not inner.visible
		inner.visible = now
		toggle.text = ("%s  ▾" if now else "%s  ▸") % title
		panel.set_section_open(key, now)
	)
	body.add_child(toggle)
	body.add_child(inner)
	return inner


## WORK THE ROOM: one row per other member, closest to flipping first.
static func build_table(body: VBoxContainer, panel, state, loader, ns, org, pending: Dictionary) -> void:
	var inner := _fold(body, panel, "room:" + org.id, Strings.t("WORK THE ROOM"))
	var vote := String(pending.get("player_vote", Orgs.VOTE_ABSTAIN))
	if vote != Orgs.VOTE_FOR and vote != Orgs.VOTE_AGAINST:
		PanelKit.line(inner, Strings.t("Cast your vote first: a bargain asks a member to vote your way."))
		return
	var proposal = Orgs.proposal_by_id(loader, org.id, String(pending.get("proposal_id", "")))
	if proposal == null:
		return

	var rows: Array = []
	var sponsor_row: Dictionary = {}
	for id in Orgs.members(state, org.id):
		if String(id) == ns.id:
			continue
		var margin: float = Orgs.support(state, state.nations[id], proposal) + Council.swing(pending, String(id)) - BK.SUPPORT_THRESHOLD
		# The sponsor is settled, not closest to flipping: shown last, outside
		# the MAX_ROWS cut, so the player always sees whose proposal it is.
		if String(pending.get("sponsor", "")) == String(id):
			sponsor_row = {"id": String(id), "margin": margin}
			continue
		rows.append({"id": String(id), "margin": margin})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ma: float = absf(float(a["margin"]))
		var mb: float = absf(float(b["margin"]))
		if is_equal_approx(ma, mb):
			return String(a["id"]) < String(b["id"])
		return ma < mb
	)

	match vote:
		Orgs.VOTE_FOR:
			PanelKit.line(inner, Strings.t("Ask a member to vote for. One bargain per member per division."))
		Orgs.VOTE_AGAINST:
			PanelKit.line(inner, Strings.t("Ask a member to vote against. One bargain per member per division."))
		_:
			PanelKit.line(inner, Strings.t("Ask a member to abstain. One bargain per member per division."))
	# Someone already bargained with can sort out of the visible rows (a FOR ask on a
	# member who leans FOR moves it away from the threshold), so name them here.
	var struck: Dictionary = pending.get("bargains", {})
	if not struck.is_empty():
		var done: Array = []
		for id in struck.keys():
			done.append(Strings.t("%s (%s, asked %s)") % [
				loader.nation_name(String(id)), String(struck[id].get("currency", "")).replace("_", " "),
				String(struck[id].get("ask", "")).to_upper(),
			])
		done.sort()
		PanelKit.line(inner, Strings.t("Already bargained this division: %s.") % ", ".join(done))
	for i in mini(rows.size(), MAX_ROWS):
		_member_row(inner, panel, state, loader, ns, org, pending, vote, rows[i])
	if rows.size() > MAX_ROWS:
		PanelKit.line(inner, Strings.t("… and %d more, already settled.") % (rows.size() - MAX_ROWS))
	if not sponsor_row.is_empty():
		_member_row(inner, panel, state, loader, ns, org, pending, vote, sponsor_row)
	PanelKit.line(inner, Strings.t("A vote trade is an IOU: when the member you trade with next sponsors a proposal you must back it — abstaining counts as breaking it (%d goodwill). On a treaty it only counts as kept if your assembly ratifies.") % roundi(CouncilK.IOU_BETRAYAL))


static func _member_row(inner: VBoxContainer, panel, state, loader, ns, org, pending: Dictionary, ask: String, row: Dictionary) -> void:
	var id: String = row["id"]
	var margin: float = float(row["margin"])
	# An AI sponsor votes FOR its own proposal (Orgs._vote_of), whatever the
	# appraisal says, so it is settled, never "leaning against".
	if String(pending.get("sponsor", "")) == id:
		PanelKit.line(inner, Strings.t("%s — its own proposal: votes FOR") % loader.nation_name(id), PanelKit.Tone.PLAIN)
		var sb := Button.new()
		sb.text = Strings.t("Nothing to bargain for")
		sb.disabled = true
		sb.tooltip_text = Strings.t("It sponsored this proposal: it would take the payment for a vote it was always going to cast.")
		inner.add_child(sb)
		return
	PanelKit.line(inner, (Strings.t("%s — leans FOR (%+.2f)") if margin >= 0.0 else Strings.t("%s — leans AGAINST (%+.2f)")) % [
		loader.nation_name(id), margin,
	], PanelKit.Tone.PLAIN)

	var why_not := {
		CouncilK.CURRENCY_FAVOUR: "", CouncilK.CURRENCY_AID: "", CouncilK.CURRENCY_VOTE_TRADE: "",
	}
	var blocked := ""
	if String(pending.get("sponsor", "")) == id:
		blocked = Strings.t("It sponsored this proposal: it would take the payment for a vote it was always going to cast.")
	elif (pending.get("bargains", {}) as Dictionary).has(id):
		blocked = Strings.t("You have already bargained with this member this division.")
	for c in why_not.keys():
		why_not[c] = blocked
	if blocked == "":
		if Relations.score(state, ns.id, id) < CouncilK.FAVOUR_MIN_RELATIONS:
			why_not[CouncilK.CURRENCY_FAVOUR] = Strings.t("A favour needs relations of at least %d with them.") % roundi(CouncilK.FAVOUR_MIN_RELATIONS)
		for d in (state.orgs[org.id].get("debts", []) as Array):
			if String(d.get("debtor", "")) == ns.id and String(d.get("creditor", "")) == id:
				why_not[CouncilK.CURRENCY_VOTE_TRADE] = Strings.t("You already owe them a vote in this council.")

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var labels := {
		CouncilK.CURRENCY_FAVOUR: Strings.t("Favour (%d goodwill)") % roundi(CouncilK.FAVOUR_RELATIONS_COST),
		CouncilK.CURRENCY_AID: Strings.t("Aid (%.2f %% GDP, %d months)") % [CouncilK.AID_PCT_GDP, CouncilK.AID_MONTHS],
		CouncilK.CURRENCY_VOTE_TRADE: Strings.t("Vote trade"),
	}
	for currency in [CouncilK.CURRENCY_FAVOUR, CouncilK.CURRENCY_AID, CouncilK.CURRENCY_VOTE_TRADE]:
		var button := Button.new()
		button.text = String(labels[currency])
		var reason: String = why_not[currency]
		if reason != "":
			button.disabled = true
			button.tooltip_text = reason
		else:
			button.pressed.connect(panel._on_bargain.bind(org.id, id, currency, ask))
			# No offer_primary: these sit in a collapsed fold, and the panel's
			# primary_action must be a control the player can see.
		buttons.add_child(button)
	inner.add_child(buttons)


## The IOUs the player owes in this council.
static func build_debts(body: VBoxContainer, state, loader, ns, org) -> void:
	var now: int = state.year * 12 + (state.month - 1)
	var any := false
	for d in (state.orgs[org.id].get("debts", []) as Array):
		if String(d.get("debtor", "")) != ns.id:
			continue
		if not any:
			PanelKit.heading(body, Strings.t("IOUS OWED"))
			any = true
		var end_idx: int = now + maxi(int(d.get("months_left", 0)), 0)
		var text := Strings.t("You owe %s a vote (lapses %s %d)") % [
			loader.nation_name(String(d.get("creditor", ""))), MONTHS[end_idx % 12], end_idx / 12,
		]
		var awaiting := String(d.get("awaiting", ""))
		if awaiting != "":
			var treaty = Orgs.proposal_by_id(loader, org.id, awaiting)
			text += Strings.t(" — kept only if %s is ratified at home") % (String(treaty.proposal_name) if treaty != null else awaiting)
		PanelKit.line(body, text)


## Set the agenda when chairing; otherwise pay the chair to table one.
static func build_agenda(body: VBoxContainer, panel, state, loader, ns, org, chair: String) -> void:
	if org.presidency.is_empty() or chair == "":
		return
	var register: Dictionary = state.orgs[org.id]
	var pending: Dictionary = Orgs.pending(state, org.id)
	var chairing: bool = chair == ns.id
	var title := Strings.t("SET THE AGENDA") if chairing else Strings.t("Table a proposal (%d goodwill with %s)") % [
		roundi(CouncilK.TABLE_RELATIONS_COST), loader.nation_name(chair),
	]

	var chosen := String(register.get("agenda_choice", ""))
	var tabled: Dictionary = register.get("tabled", {})
	if chairing and chosen != "":
		var p = Orgs.proposal_by_id(loader, org.id, chosen)
		PanelKit.line(body, Strings.t("You have put %s first.") % (String(p.proposal_name) if p != null else chosen))
		return
	if not chairing and not tabled.is_empty():
		var tp = Orgs.proposal_by_id(loader, org.id, String(tabled.get("proposal_id", "")))
		PanelKit.line(body, Strings.t("You have tabled %s with the chair.") % String(tp.proposal_name) if tp != null else Strings.t("You have tabled a proposal with the chair."))
		return

	var inner := _fold(body, panel, "agenda:" + org.id, title)
	if chairing:
		var open_idx: int = state.year * 12 + (state.month - 1) + Council.months_to_opening(state, org.id)
		PanelKit.line(inner, Strings.t("You chair the council from %s %d: choose what opens first.") % [MONTHS[open_idx % 12], open_idx / 12])
	var listed := 0
	for p in loader.org_proposals.get(org.id, []):
		# _eligible is the sim's one opening rule; reading it here keeps the list
		# from offering what set_agenda/table_proposal would refuse.
		if not Orgs._eligible(state, org.id, p) or String(pending.get("proposal_id", "")) == p.id:
			continue
		listed += 1
		var button := Button.new()
		button.text = (Strings.t("Put first: %s") if chairing else Strings.t("Table: %s")) % p.proposal_name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if chairing:
			button.pressed.connect(panel._on_set_agenda.bind(org.id, p.id))
		else:
			button.pressed.connect(panel._on_table.bind(org.id, p.id))
		inner.add_child(button)
	if listed == 0:
		PanelKit.line(inner, Strings.t("Nothing eligible to bring forward."))
