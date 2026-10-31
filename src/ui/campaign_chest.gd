extends RefCounted

## The party's chest on the campaign panel -- V5.2 C6 (docs/design/v5.2-c6-party-campaigns.md
## section 9): since C6 the governing party pays for the campaign, not the budget, so the
## player has to see the money before it runs out, and a start it cannot pay for has to
## say so rather than look like a dead click.
##
## Read-only over the sim's own read surface (Campaign.price_eur_m, months_payable,
## PartyMoney.money_eur_m, ceiling_room_eur_m): the refusal's figures are the very
## numbers Campaign.execute() compares, so the button and the command never disagree.
## Static, so the panel at its size ratchet calls it in one line per use.

const Campaign = preload("res://src/sim/campaign.gd")
const PartyMoney = preload("res://src/sim/party_money.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const ConfirmCard = preload("res://src/ui/confirm_card.gd")
const Pledges = preload("res://src/sim/pledges.gd")


## The chest's rows: the party's money, its purse a year (public funding, running
## costs and the net, section 6: seats won can still leave the party poorer), how long
## it pays what runs, and the legal ceiling's room -- or what was spent past it, which
## is what the auditors can find.
static func build(body: Control, ns, loader) -> void:
	PanelKit.heading(body, Strings.t("The party's chest"))
	PanelKit.row(body, Strings.t("Party money"), _eur(PartyMoney.money_eur_m(ns, loader)))
	var purse := PartyMoney.purse(ns, loader, String(ns.incumbent_party_id))
	PanelKit.row(body, Strings.t("Public funding a year"), _eur(float(purse["funding"])))
	PanelKit.row(body, Strings.t("Running costs a year"), _eur(float(purse["running"])))
	# The net in words, never by colour alone: which way the money goes is the label.
	# Zero before any election (running costs are sized to the start's funding), and
	# below the cent it prints as zero, so it says so rather than "gains €0.00 m".
	var net := float(purse["net"])
	if absf(net) < 0.005:
		PanelKit.row(body, Strings.t("The party breaks even"), _eur(0.0))
	elif net < 0.0:
		PanelKit.row(body, Strings.t("The party loses a year"), _eur(-net), PanelKit.Tone.BAD)
	else:
		PanelKit.row(body, Strings.t("The party gains a year"), _eur(net), PanelKit.Tone.GOOD)
	var months := Campaign.months_payable(ns, loader)
	if months >= 0:
		PanelKit.row(body, Strings.t("Pays what runs for"), Strings.tn("%d month", "%d months", months) % months,
			PanelKit.Tone.BAD if months <= 1 else PanelKit.Tone.PLAIN)
	var room := PartyMoney.ceiling_room_eur_m(ns, loader)
	if room == INF:
		return
	if room >= 0.0:
		PanelKit.row(body, Strings.t("Room under the legal ceiling"), _eur(room))
	else:
		PanelKit.row(body, Strings.t("Spent past the legal ceiling"), _eur(-room), PanelKit.Tone.BAD)
		PanelKit.line(body, Strings.t("The auditors can find what was spent past the ceiling."))


## An offer's price, its reach, and -- before the start -- how many months the chest
## pays at the rate with this effort added to what runs (section 3: the start checks one
## month of the new effort alone, so this is where the player sees the shorter run).
## An effort that ran this run-up and stopped, by the player or for money, cannot start
## again before the vote (Campaign._op_legal(): one run per window), so it gets no
## forecast -- a months line there read as an invitation to a start that does not exist
## (QA's TAKE on #184) -- and says why it has no button.
static func offer_lines(block: Control, ns, loader, effort_id: String, reach: String) -> void:
	PanelKit.line(block, Strings.t("€%s m · %s") % [Num.f(Campaign.price_eur_m(ns, loader, effort_id), 2), reach])
	if Campaign.has_started(ns, effort_id) and not Campaign.is_running(ns, effort_id):
		PanelKit.line(block, Strings.t("Already used: one run per run-up."))


## How long the chest pays with the effort added: its Start button's hover (spec
## 3.5's campaign diet), "" for an effort already used this run-up.
static func lasts_text(ns, loader, effort_id: String) -> String:
	if Campaign.has_started(ns, effort_id) and not Campaign.is_running(ns, effort_id):
		return ""
	var months := Campaign.months_payable(ns, loader, effort_id)
	return Strings.tn("Chest then lasts %d month.", "Chest then lasts %d months.", months) % months


## Why a campaign button cannot be pressed, as the sentence its tooltip shows; "" when
## it can. The site first (Campaign.execute()'s own order), then the money.
static func why_not(ns, loader, action, site_region: String) -> String:
	var terms: Dictionary = action.effects.get("campaign", {})
	if String(terms.get("op", "")) != "start":
		return ""
	if site_region == "":
		return Strings.t("choose where the meetings are held first")
	var price := PartyMoney.price_eur_m(ns, terms)
	var money := PartyMoney.money_eur_m(ns, loader)
	if money < price:
		return Strings.t("The party cannot pay for it: it costs %s a month, and the party has %s.") % [_eur(price), _eur(money)]
	return ""


## A command the sim refused, said on a card: never a dead click. One card per panel,
## made on the first refusal and kept on `from` -- on_stack() adds a new one each call.
static func tell_refused(from: Node, ns, loader, action, site_region: String) -> void:
	var why := why_not(ns, loader, action, site_region)
	_tell(from, why if why != "" else Strings.t("The campaign cannot do that now."))


## A promise made from the panel: the sim's command, its refusal said on the same
## card as an effort's (V5.3-0 RF7: the campaign's results, never a dead click).
## True when the promise was made.
static func promise(from: Node, state, ns, loader, action) -> bool:
	var result := Pledges.execute(state, ns, loader.pledges, action)
	if not result.get("applied", false):
		_tell(from, Strings.t("%s refused -- it is no longer on offer.") % Strings.row_name("pledges", action))
	return bool(result.get("applied", false))


## The panel's one refusal card, its sentence in the BLOCKED tone.
static func _tell(from: Node, why: String) -> void:
	var card = from.get_meta(&"refusal_card") if from.has_meta(&"refusal_card") else null
	if card == null or not is_instance_valid(card):
		card = ConfirmCard.on_stack(from)
		from.set_meta(&"refusal_card", card)
	if card != null:
		card.tell(why)
		ResultTone.tint(card._question, ResultTone.BLOCKED)


## The month's efforts stopped for money (the report's `campaign_stopped`), as ONE note
## in the inbox -- never a hold (section 3), and one a month, not one per effort (R13).
## Other nations' stops are theirs. Returns the note's id, "" when there was none.
static func note_stopped(inbox, stopped: Array, state, loader) -> String:
	var names := PackedStringArray()
	for row in stopped:
		if row is Dictionary and String(row.get("nation_id", "")) == String(state.player_nation_id):
			var eid := String(row.get("effort_id", ""))
			names.append(Strings.noun("campaign-actions", loader.campaign_actions, "campaign", "effort_id", eid, "effort_name", Campaign.name_of(loader, eid)))
	if names.is_empty() or inbox == null:
		return ""
	var ns = state.player()
	var body := Strings.tn("The party could not pay this month, so one effort stopped: %s. What it bought stays, but it cannot run again before the vote.", "The party could not pay this month, so these efforts stopped: %s. What they bought stays, but they cannot run again before the vote.", names.size()) % "; ".join(names)
	body += " " + Strings.t("The party has %s.") % _eur(PartyMoney.money_eur_m(ns, loader))
	return ResultTone.push(inbox, Strings.t("Campaign stopped"), body, ResultTone.BAD)


## A party in debt (running costs can take it below zero, section 3) reads "−€1.00 m".
static func _eur(amount: float) -> String:
	if amount < 0.0:
		return Strings.t("−€%s m") % Num.f(-amount, 2)
	return Strings.t("€%s m") % Num.f(amount, 2)
