extends RefCounted

## A firm verb's button and the question it asks first -- V5.3-0 gate G1. The
## author: "button dismantle enterprise destroy instantly an company ? why ? also
## its instant with no warning, also it worked once and dont work for next
## company". Two causes, two answers here:
##
##   - The second break-up in a French sector has no rival left to absorb the
##     split, so the sim refuses it -- while the door still offered it, and the
##     refusal landed at the head of a scrolled body, out of sight. The button
##     now reads Companies.refusal_reason() before the click: disabled, the
##     reason on its hover (the Dissolve button's three ways).
##   - An `irreversible` verb asks on a confirm card first, with what it costs:
##     the jobs that end, the jobs the rivals take on, the treasury's money. The
##     figures come from Companies.preview(), the verb run on a COPY of the
##     nation, so the card cannot disagree with what the click does.
##
## Static and owning nothing, so the panel keeps its size: it holds the card and
## runs the command on `confirmed`.

const Companies = preload("res://src/sim/companies.gd")
const Processes = preload("res://src/sim/processes.gd")
const CK = preload("res://src/sim/companies_constants.gd")
const ConfirmCard = preload("res://src/ui/confirm_card.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")


## The verb's button: disabled with the sim's reason when the arm would refuse
## what the door offers, else live with the verb's summary on its hover.
static func button(state, loader, ns, company, action) -> Button:
	var out := PanelKit.sized(Button.new())
	out.text = Strings.row_name("company-actions", action)
	var why := refusal(state, loader, ns, company, action)
	out.disabled = why != ""
	if why != "":
		out.tooltip_text = Strings.t(why)  # i18n: row-ok the sim's reason, its English the msgid
	else:
		out.tooltip_text = Strings.row_summary("company-actions", action)
	return out


## Why `action` cannot run on `company` now, in the sim's English (the msgid), or
## "" when it can: the one place the Industry tab reads it, for the greyed button
## and the line printed beside it (band A5).
static func refusal(state, loader, ns, company, action) -> String:
	var why := Companies.refusal_reason(state, ns, action, String(company.id), loader)
	# V5.3 a: a firm already in a process refuses the other ownership verbs, and a
	# firm that settled a break-up refuses another referral (#248).
	if why == "":
		why = Processes.refusal(state, ns, String(company.id), action)
	return why


## Asks on `card` (made on `from`'s screen stack at the first ask) and calls
## `run` on its yes. Returns the card for the asker to keep; null with no stack,
## in which case `run` is called at once rather than the click doing nothing.
static func ask(from: Node, card, state, loader, ns, company, action, run: Callable):
	if card == null:
		card = ConfirmCard.on_stack(from)
		if card == null:
			run.call()
			return null
		card.confirmed.connect(func(): (card.get_meta(&"run") as Callable).call())
	# The clock runs behind the card (the Dissolve button's finding): a month turned
	# under it moved the shares, so the player is asked again on the new figures
	# rather than held to ones the card no longer shows.
	var asked := int(state.year) * 12 + int(state.month)
	card.set_meta(&"run", func():
		if int(state.year) * 12 + int(state.month) != asked:
			ask(from, card, state, loader, ns, company, action, run)
		else:
			run.call())
	var verb := Strings.row_name("company-actions", action)
	var head := Strings.t("%s: %s?") % [verb, company.company_name]
	card.ask("%s\n%s" % [head, question(state, loader, ns, company, action)], verb)
	return card


## What the verb does to jobs and money, in whole sentences, read off the
## sim's preview (the verb run on a copy of the nation).
static func question(state, loader, ns, company, action) -> String:
	if Processes.is_process(action):
		return process_question(state, loader, ns, company, action)
	var preview: Array = Companies.preview(state, ns, loader.company_actions, action, String(company.id), loader)
	var probe = preview[0]
	var result: Dictionary = preview[1]
	var lost := 0.0
	var gained := 0.0
	var takers: Array[String] = []
	for firm in Companies.firms_of(loader, ns.id):
		var moved: float = Companies.headcount(probe, firm) - Companies.headcount(ns, firm)
		if firm.id == company.id:
			lost = -moved
		elif moved > 0.5:
			gained += moved
			takers.append(String(firm.company_name))
	var lines := PackedStringArray()
	if takers.is_empty():
		lines.append(Strings.t("%s jobs end at %s.") % [thousands(lost), company.company_name])
	else:
		lines.append(Strings.t("%s jobs end at %s; its rivals (%s) take on %s. Net: %s jobs.") % [
			thousands(lost), company.company_name, ", ".join(takers), thousands(gained), signed(gained - lost)])
	var price := float(result.get("price_eur_bn", 0.0))
	if price > 0.0:
		lines.append(Strings.t("Costs the treasury %s bn.") % Num.f(price, 1))
	elif price < 0.0:
		lines.append(Strings.t("Raises %s bn for the treasury.") % Num.f(-price, 1))
	else:
		lines.append(Strings.t("No cost to the treasury."))
	if action.irreversible:
		lines.append(Strings.t("It cannot be undone."))
	return " ".join(lines)


## V5.3 a (parent pass 2 on #244): a process verb lands nothing on the click, so its
## question reads Processes.estimate() -- the stages and their months, the price as
## its range, a break-up's odds as their range -- never the arm's instant preview.
## Interface's effects strip replaces this text with the Industry tab's rebuild.
static func process_question(state, loader, ns, company, action) -> String:
	var est: Dictionary = Processes.estimate(state, ns, loader, action, String(company.id))
	var lines := PackedStringArray()
	match String(action.id):
		"minority_stake":
			lines.append(Strings.t("%d months of negotiation, then the stake changes hands.") % int(est["months_lo"]))
		"full_nationalisation":
			lines.append(Strings.t("%d months of the offer, then the transfer; the state takes control after a %d-month transition.") % [
				CK.PROCESS_OFFER_MONTHS, CK.PROCESS_TRANSITION_MONTHS])
		"break_up":
			lines.append(Strings.t("The competition authority investigates for %d to %d months, then rules: a %d to %d %% chance it orders the break-up.") % [
				CK.PROCESS_INVESTIGATION_MONTHS.x, CK.PROCESS_INVESTIGATION_MONTHS.y,
				roundi(100.0 * float(est["odds_lo"])), roundi(100.0 * float(est["odds_hi"]))])
			var rivals: Array[String] = []
			for other in Companies.majors_of(loader, ns.id):
				if other.id != company.id and other.sector == company.sector and not bool(ns.companies.get(other.id, {}).get("failed", false)):
					rivals.append(String(other.company_name))
			lines.append(Strings.t("If it does, after a %d-month remedy its rivals (%s) take %d %% of its market and the %s jobs at %s end.") % [
				CK.PROCESS_REMEDY_MONTHS, ", ".join(rivals), roundi(100.0 * CK.BREAK_UP_ABSORBED),
				thousands(Companies.headcount(ns, company)), company.company_name])
		"privatisation":
			lines.append(Strings.t("%d months of sale, then the state's share changes hands.") % int(est["months_lo"]))
	var lo := minf(float(est["price_lo"]), float(est["price_hi"]))
	var hi := maxf(float(est["price_lo"]), float(est["price_hi"]))
	if String(action.id) == "break_up":
		lines.append(Strings.t("Costs the treasury %s bn in legal fees.") % Num.f(hi, 2))
	elif hi > 0.0:
		lines.append(Strings.t("Costs the treasury %s to %s bn.") % [Num.f(lo, 1), Num.f(hi, 1)])
	else:
		lines.append(Strings.t("Raises %s to %s bn for the treasury.") % [Num.f(-hi, 1), Num.f(-lo, 1)])
	if action.irreversible:
		lines.append(Strings.t("Once it lands it cannot be undone."))
	return " ".join(lines)


## A headcount with its thousands apart ("41 200"): the panel's own format.
static func thousands(value: float) -> String:
	var whole := int(round(value))
	var text := str(absi(whole))
	var out := ""
	while text.length() > 3:
		out = " " + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return ("-" if whole < 0 else "") + text + out


static func signed(value: float) -> String:
	return ("+" if roundi(value) > 0 else "") + thousands(value)
