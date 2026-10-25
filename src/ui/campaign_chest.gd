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
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const ConfirmCard = preload("res://src/ui/confirm_card.gd")


## The chest's rows: the party's money, how long it pays what runs, and the legal
## ceiling's room -- or what was spent past it, which is what the auditors can find.
static func build(body: Control, ns, loader) -> void:
	PanelKit.heading(body, Strings.t("The party's chest"))
	PanelKit.row(body, Strings.t("Party money"), _eur(PartyMoney.money_eur_m(ns, loader)))
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
static func offer_lines(block: Control, ns, loader, effort_id: String, reach: String) -> void:
	PanelKit.line(block, Strings.t("€%s m · %s") % [Num.f(Campaign.price_eur_m(ns, loader, effort_id), 2), reach])
	var months := Campaign.months_payable(ns, loader, effort_id)
	PanelKit.line(block, Strings.tn("With this added, the chest lasts %d month.", "With this added, the chest lasts %d months.", months) % months)


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
	var card = from.get_meta(&"refusal_card") if from.has_meta(&"refusal_card") else null
	if card == null or not is_instance_valid(card):
		card = ConfirmCard.on_stack(from)
		from.set_meta(&"refusal_card", card)
	if card != null:
		card.tell(why if why != "" else Strings.t("The campaign cannot do that now."))


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
	var body := Strings.tn("The party could not pay this month, so one effort stopped: %s. What it bought stays.", "The party could not pay this month, so these efforts stopped: %s. What they bought stays.", names.size()) % "; ".join(names)
	body += " " + Strings.t("The party has %s.") % _eur(PartyMoney.money_eur_m(ns, loader))
	return inbox.push(Strings.t("Campaign stopped"), body)


## A party in debt (running costs can take it below zero, section 3) reads "−€1.00 m".
static func _eur(amount: float) -> String:
	if amount < 0.0:
		return Strings.t("−€%s m") % Num.f(-amount, 2)
	return Strings.t("€%s m") % Num.f(amount, 2)
