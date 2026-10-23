extends RefCounted

## The council block of the organisations panel: what is before an org's
## council, the player's vote, and why the last division went as it did.
##
## Split out of orgs_panel.gd at V4.5b2 because that file was past the few-hundred-
## line mark and the V4.5 council surfaces (sponsor, bargaining, ratification)
## all grow HERE. Static builders over the panel's body rather than a Control of
## its own: the panel rebuilds its whole body on every refresh, and a nested
## node with its own dirty flag would be a second thing to keep in step.
##
## Read-only over sim state like the panel that calls it. A press goes back as
## the panel's own bound method (`panel._on_vote`), so refusals and the `voted`
## signal stay in one place. The first enabled verb is offered through
## `panel.offer_primary()`, which keeps the panel's fold contract.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const Labels = preload("res://src/ui/labels.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")
const Council = preload("res://src/sim/council.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")
const BK = preload("res://src/sim/bloc_constants.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Bargains = preload("res://src/ui/council_bargains.gd")
const Ratification = preload("res://src/sim/ratification.gd")
const LawPanel = preload("res://src/ui/law_panel.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")

const FACE_SIZE := Vector2(48, 60)
## How many chairs after the current one the presidency line names.
const NEXT_CHAIRS := 3
## A drive at or above these reads "hard" / "steadily"; below, "lightly". The
## player never sees the number, only the verb -- the ambition behind it is a
## person trait, not a meter.
const DRIVE_HARD := 0.66
const DRIVE_STEADY := 0.33


## Stands in for GameState so Council.presiding_nation can be asked about a
## later date without touching the real one: it reads only year, month, nations.
class DateProxy:
	var year: int = 0
	var month: int = 1
	var nations: Dictionary = {}


## What is on the table at this org's council, and the player's own vote.
## First, because it is the only part of this section the player can act on.
static func build(body: VBoxContainer, panel, state, loader, ns, org) -> void:
	# First, and the only primary candidate above the vote buttons: a treaty
	# waiting on the player's assembly dies for every member if left alone.
	_ratify_card(body, panel, state, loader, ns, org)
	PanelKit.heading(body, Strings.t("BEFORE THE COUNCIL"))
	_chair_line(body, state, loader, ns, org)

	var pending: Dictionary = Orgs.pending(state, org.id)
	if pending.is_empty():
		PanelKit.line(body, Strings.t("Nothing before the council. The presidency brings the next proposal forward in due course."))
	else:
		PanelKit.line(body, Strings.row("bloc-proposals", String(pending.get("proposal_id", "")), "name", String(pending.get("name", ""))), PanelKit.Tone.PLAIN)
		PanelKit.rich(body, Strings.row("bloc-proposals", String(pending.get("proposal_id", "")), "summary", String(pending.get("summary", ""))))
		_sponsor_row(body, state, loader, ns, org, pending)
		_decision_line(body, loader, org, pending)
		_lobbying_line(body, loader, pending)
		PanelKit.line(body, Strings.tn("Divides in %d month.", "Divides in %d months.", int(pending.get("months_left", 0))) % int(pending.get("months_left", 0)), PanelKit.Tone.PLAIN)

		var current := String(pending.get("player_vote", Orgs.VOTE_ABSTAIN))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for choice in Orgs.VOTE_CHOICES:
			var button := PanelKit.sized(Button.new())
			button.text = Labels.vote(choice)
			button.disabled = choice == current
			# An abstention is in the denominator and neither numerator, so sitting
			# out makes passage harder without spending anything on opposing it.
			# Said here because it is the one rule of this panel a player would
			# otherwise have to infer from a tally.
			if choice == Orgs.VOTE_ABSTAIN:
				button.tooltip_text = Strings.t("Counted against the threshold, for neither side.")
			button.pressed.connect(panel._on_vote.bind(org.id, choice))
			if not button.disabled:
				panel.offer_primary(button)
			row.add_child(button)
		body.add_child(row)
		var standing := Strings.t("Currently: voting against. %s holds %d of the council's seats.")
		if current == Orgs.VOTE_ABSTAIN:
			standing = Strings.t("Currently: abstaining. %s holds %d of the council's seats.")
		elif current == Orgs.VOTE_FOR:
			standing = Strings.t("Currently: voting for. %s holds %d of the council's seats.")
		PanelKit.line(body, standing % [loader.nation_name(ns.id), org.seats(ns.id)])
		_sponsor_reaction_line(body, state, loader, ns, pending)
		Bargains.build_table(body, panel, state, loader, ns, org, pending)

	_aid_line(body, state, ns, org)
	Bargains.build_debts(body, state, loader, ns, org)
	Bargains.build_agenda(body, panel, state, loader, ns, org, Council.chair_at_next_opening(state, loader, org.id))

	var last: Dictionary = Orgs.last_vote(state, org.id)
	if not last.is_empty():
		PanelKit.line(body, "", PanelKit.Tone.PLAIN)
		PanelKit.line(body, (Strings.t("Last division: %s — carried") if bool(last.get("passed", false)) else Strings.t("Last division: %s — fell")) % Strings.row("bloc-proposals", String(last.get("proposal_id", "")), "name", String(last.get("name", ""))), PanelKit.Tone.PLAIN)
		var tally := Strings.t("%d for, %d against, of %d seats. %s abstained.")
		match String(last.get("player_vote", "")):
			Orgs.VOTE_FOR: tally = Strings.t("%d for, %d against, of %d seats. %s voted for.")
			Orgs.VOTE_AGAINST: tally = Strings.t("%d for, %d against, of %d seats. %s voted against.")
		PanelKit.line(body, tally % [
			int(last.get("seats_for", 0)), int(last.get("seats_against", 0)),
			int(last.get("seats_total", 0)), loader.nation_name(ns.id),
		])
		_outcome(body, loader, last)
		_why(body, loader, last)
	PanelKit.line(body, "", PanelKit.Tone.PLAIN)


## RATIFY AT HOME: the forecast of the player's own assembly on a treaty the
## council carried, and the one button that puts it to them. The forecast is
## Legislature.resolve_vote's pure result, shown in law_panel's words.
static func _ratify_card(body: VBoxContainer, panel, state, loader, ns, org) -> void:
	var r: Dictionary = state.orgs[org.id].get("ratifying", {})
	if r.is_empty():
		return
	if String((r.get("nations", {}) as Dictionary).get(ns.id, "")) != CouncilK.RATIFY_PENDING:
		return
	var left: int = int(r.get("months_left", 0))
	PanelKit.heading(body, Strings.tn("RATIFY AT HOME — %s (%d month left)", "RATIFY AT HOME — %s (%d months left)", left) % [
		Strings.row("bloc-proposals", String(r.get("proposal_id", "")), "name", String(r.get("name", ""))), left,
	])
	# The SAME blurred forecast a bill gets in the law screen (law_panel's static
	# forecast_text): exact seat counts here would be a free precise whip count
	# the project's fixed-forecast rule withholds from every other division.
	var proposal = Orgs.proposal_by_id(loader, org.id, String(r.get("proposal_id", "")))
	if proposal != null:
		var treaty = Ratification.treaty_bill(proposal)
		var parties: Array = loader.parties.get(ns.id, [])
		PanelKit.line(body, Strings.t("Your assembly, if it voted today: %s") % LawPanel.forecast_text(
			ns, parties, treaty, LawPanel.forecast_band(ns, treaty.id)), PanelKit.Tone.PLAIN)
	var members: int = Orgs.members(state, org.id).size()
	var r_sponsor := String(r.get("sponsor", ""))
	var falls := Strings.t("If it falls here it falls for all %d members") % members
	if r_sponsor != "" and r_sponsor != ns.id:
		falls += Strings.t("; %s will not forget it") % loader.nation_name(r_sponsor)
	PanelKit.line(body, falls + ".")
	var button := PanelKit.sized(Button.new())
	button.text = Strings.t("Put it to the assembly")
	button.pressed.connect(panel._on_ratify.bind(org.id))
	panel.claim_primary(button)
	body.add_child(button)


## WHY each member voted as it did, not only how.
##
## Until V1.3e the eight voted on ideology alone and there was nothing to say.
## Now they price a proposal against their own books, and the division is only
## legible if the player can see that Luxembourg opposed a fund it would pay for
## while Italy backed one it would draw on. Grouped by reason rather than listed
## per nation: the interesting object is the CAMP. The reasons are recorded at
## the moment of the division by src/sim/orgs.gd, not recomputed here -- the
## books a member voted on were that month's.
static func _why(body: VBoxContainer, loader, last: Dictionary) -> void:
	var reasons: Dictionary = last.get("reasons", {})
	if reasons.is_empty():
		return
	var votes: Dictionary = last.get("votes", {})

	var camps: Dictionary = {}
	var order: Array = reasons.keys()
	order.sort()
	for id in order:
		var key := String(reasons[id])
		if not camps.has(key):
			camps[key] = []
		camps[key].append((Strings.t("%s for") if String(votes.get(id, "")) == Orgs.VOTE_FOR else Strings.t("%s against")) % loader.nation_name(String(id)))

	var keys: Array = camps.keys()
	keys.sort()
	for key in keys:
		PanelKit.line(body, "%s: %s" % [_vote_reason_text(String(key)), ", ".join(camps[key])])


## The model returns a key; the wording lives here, because src/sim/ does not know
## the UI exists and a test should not assert on prose.
static func _vote_reason_text(key: String) -> String:
	match key:
		ForeignPolicy.VOTE_REASON_DRAWS_ON_IT: return Strings.t("stood to draw on it")
		ForeignPolicy.VOTE_REASON_ALREADY_IN_BREACH: return Strings.t("already outside the rule")
		ForeignPolicy.VOTE_REASON_WOULD_PAY: return Strings.t("would have to pay for it")
		ForeignPolicy.VOTE_REASON_TRADES_OUTSIDE: return Strings.t("trades outside the org")
		ForeignPolicy.VOTE_REASON_POLITICS: return Strings.t("on the politics of it")
		CouncilK.REASON_LOBBIED: return Strings.t("brought round by the sponsor")
		CouncilK.REASON_BARGAINED: return Strings.t("struck a bargain with you")
		CouncilK.REASON_SPONSOR: return Strings.t("its own proposal")
	return key


## Who put the pending proposal forward, with the face of the person who is
## pushing it. The sponsor's head of government is read live (Council.drive's
## contract), so an election abroad changes the face on the next refresh.
static func _sponsor_row(body: VBoxContainer, state, loader, ns, org, pending: Dictionary) -> void:
	var sponsor := String(pending.get("sponsor", ""))
	if sponsor == "":
		PanelKit.line(body, Strings.t("No sponsor \u2014 the presidency put it forward."))
		return
	if sponsor == ns.id:
		# Tabled by the player (paid) vs authored as the player nation's own.
		var authored = Orgs.proposal_by_id(loader, org.id, String(pending.get("proposal_id", "")))
		if authored != null and String(authored.sponsor) == ns.id:
			PanelKit.line(body, Strings.t("Your government's proposal."))
		else:
			PanelKit.line(body, Strings.t("You tabled it."))
		return
	var sponsor_ns = state.nations.get(sponsor, null)
	var drive: float = Council.drive(state, loader, sponsor)
	var pushes := Strings.t(" \u2014 %s pushes it lightly")
	if drive >= DRIVE_HARD:
		pushes = Strings.t(" \u2014 %s pushes it hard")
	elif drive >= DRIVE_STEADY:
		pushes = Strings.t(" \u2014 %s pushes it steadily")
	var person_id := String(sponsor_ns.pm_person_id) if sponsor_ns != null else ""
	var who: String = loader.person_name(person_id)
	var text := Strings.t("Sponsored by %s") % loader.nation_name(sponsor)
	if who != "":
		text += pushes % who
	var row := PanelKit.row(body, text, "")
	if person_id != "":
		var face := Portrait.framed_for(person_id, FACE_SIZE)
		row.add_child(face)
		row.move_child(face, 0)
	# The player's own IOU to this sponsor: the one place a vote is owed.
	for d in (state.orgs[org.id].get("debts", []) as Array):
		if String(d.get("debtor", "")) == ns.id and String(d.get("creditor", "")) == sponsor and String(d.get("awaiting", "")) == "":
			var line := Strings.t("This is %s's proposal: you owe them a vote — anything but FOR costs %d goodwill") % [loader.nation_name(sponsor), roundi(CouncilK.IOU_BETRAYAL)]
			var p = Orgs.proposal_by_id(loader, org.id, String(pending.get("proposal_id", "")))
			if p != null and Council.decision_of(loader, p) == CouncilK.DECISION_UNANIMITY:
				line += Strings.t(" and it only counts if your assembly ratifies")
			PanelKit.line(body, line + ".")
			break


## What the sponsor makes of the player's vote, in numbers a player can weigh.
static func _sponsor_reaction_line(body: VBoxContainer, state, loader, ns, pending: Dictionary) -> void:
	var sponsor := String(pending.get("sponsor", ""))
	if sponsor == "" or sponsor == ns.id or not state.nations.has(sponsor):
		return
	var d: float = Council.drive(state, loader, sponsor)
	PanelKit.line(body, Strings.t("Backing it earns %s goodwill (+%s); opposing it costs %s; abstaining costs nothing.") % [
		loader.nation_name(sponsor), Num.f(CouncilK.SPONSOR_THANKS * d, 1), Num.f(CouncilK.SPONSOR_SNUB * d, 1),
	])


## The decision class in plain words; the numbers come from the constants so the
## copy cannot drift from the rule.
static func _decision_line(body: VBoxContainer, loader, org, pending: Dictionary) -> void:
	var p = Orgs.proposal_by_id(loader, org.id, String(pending.get("proposal_id", "")))
	var rule: String = Council.decision_of(loader, p) if p != null else String(org.decision_rule)
	if rule == CouncilK.DECISION_UNANIMITY:
		PanelKit.line(body, Strings.t("A treaty: one vote against vetoes it. If it carries, your assembly must ratify it within %d months \u2014 one rejection anywhere kills it for every member.") % CouncilK.RATIFY_WINDOW_MONTHS)
	else:
		PanelKit.line(body, Strings.t("Decided by qualified majority: %d %% of the seats cast. Abstaining lowers the bar instead of blocking.") % roundi(BK.PASS_SEAT_FRACTION * 100.0))


static func _lobbying_line(body: VBoxContainer, loader, pending: Dictionary) -> void:
	var lobbied: Dictionary = pending.get("lobbied", {})
	if lobbied.is_empty():
		return
	var names: Array = []
	for id in lobbied.keys():
		names.append(loader.nation_name(String(id)))
	names.sort()
	PanelKit.line(body, Strings.t("%s has spent goodwill to bring round: %s.") % [
		loader.nation_name(String(pending.get("sponsor", ""))), ", ".join(names),
	])


## The presidency: who chairs now, until when, and the next few. Evaluated by
## Council.presiding_nation on a DateProxy so the non-member skip rule lives in
## one place.
static func _chair_line(body: VBoxContainer, state, loader, ns, org) -> void:
	if org.presidency.is_empty():
		if org.decision_rule == CouncilK.DECISION_UNANIMITY:
			PanelKit.line(body, Strings.t("No rotating chair: the Secretary General convenes, decisions by consensus."))
		return
	var current := Council.presiding_nation(state, loader, org.id)
	if current == "":
		return
	var months: int = int(org.presidency["months"])
	if current == ns.id:
		PanelKit.line(body, Strings.t("You chair the council this semester.") if months == 6 else Strings.t("You chair the council this term."))
		return
	var anchor: int = int(org.presidency["anchor_index"])
	var now: int = state.year * 12 + (state.month - 1)
	var term: int = floori(float(now - anchor) / float(months))
	var end_idx: int = anchor + (term + 1) * months - 1
	var proxy := DateProxy.new()
	proxy.nations = state.nations
	var next: Array = []
	for k in range(1, NEXT_CHAIRS + 1):
		var idx: int = now + k * months
		proxy.year = idx / 12
		proxy.month = idx % 12 + 1
		var id := Council.presiding_nation(proxy, loader, org.id)
		# A small rotation can seat the same chair twice running; "then X, X" is noise.
		if id != "" and (next.is_empty() or next[-1] != loader.nation_name(id)):
			next.append(loader.nation_name(id))
	var text := Strings.t("Presidency: %s (to %s %d)") % [loader.nation_name(current), DateText.month(end_idx % 12 + 1), end_idx / 12]
	if not next.is_empty():
		text += Strings.t(", then %s") % ", ".join(next)
	PanelKit.line(body, text + ".")


## Vetoes and the road home for the last division.
static func _outcome(body: VBoxContainer, loader, last: Dictionary) -> void:
	var vetoed: Array = last.get("vetoed_by", [])
	if not vetoed.is_empty():
		var names: Array = []
		for id in vetoed:
			names.append(loader.nation_name(String(id)))
		PanelKit.line(body, Strings.t("Vetoed by %s.") % ", ".join(names))
	match String(last.get("ratification", "")):
		"pending": PanelKit.line(body, Strings.t("Awaiting ratification at home."))
		"ratified": PanelKit.line(body, Strings.t("Ratified."))
		"failed": PanelKit.line(body, Strings.t("Fell at ratification."))


## Aid the player pays into this council. Orgs with a transfer line show it in
## THE BUDGET; the rest (a climate accord) have no such section, so it is said here.
static func _aid_line(body: VBoxContainer, state, ns, org) -> void:
	if org.net_transfers:
		return
	var pct: float = Council.aid_line(state, ns.id, org.id)
	if pct <= 0.0:
		return
	var left := 0
	for a in (state.orgs[org.id].get("aid", []) as Array):
		if String(a.get("payer", "")) == ns.id:
			left = maxi(left, int(a.get("months_left", 0)) + 1)
	PanelKit.line(body, Strings.t("You are paying %s %% of GDP in side-payments to this council (%d months left).") % [Num.f(pct, 2), left])
