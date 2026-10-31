extends RefCounted

## The words of a priority line -- V5.3-0, the monthly briefing (docs/design/
## v5.3-0-readability.md 2.2). priorities.gd ranks and returns data; this says it,
## one short line and a deadline chip, the text diet's unit: a name and a figure,
## never a sentence of explanation (that is the glossary's).

const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")
const Events = preload("res://src/sim/events.gd")
const Programme = preload("res://src/sim/programme.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const Trends = preload("res://src/ui/trends.gd")

## The Material Symbols icon per kind (assets/icons/material/).
const ICON := {"crisis": "event", "decision": "mail", "election": "campaign", "bill": "gavel",
	"majority": "account_balance", "commitment": "handshake", "request": "person", "programme": "checklist",
	"bloc": "groups", "budget": "payments", "unrest": "diversity_3", "person": "person"}  # i18n: ok icon names


static func icon_path(kind: String) -> String:
	return "res://assets/icons/material/%s.svg" % String(ICON.get(kind, "event"))


## A footer group's words (the card's "Also due this month"): the item's own title
## for one, a count by kind for several.
static func group(items: Array, state, loader) -> String:
	var n := items.size()
	if n == 1:
		return title(items[0], state, loader)
	match String(items[0]["kind"]):
		"crisis": return Strings.tn("%d crisis", "%d crises", n) % n
		"decision": return Strings.tn("%d decision", "%d decisions", n) % n
		"request": return Strings.tn("%d request", "%d requests", n) % n
		"commitment": return Strings.tn("%d promise", "%d promises", n) % n
		"bill": return Strings.tn("%d bill", "%d bills", n) % n
		"programme": return Strings.tn("%d programme goal", "%d programme goals", n) % n
	return Strings.tn("%d vote", "%d votes", n) % n


## The line's title.
static func title(entry: Dictionary, state, loader) -> String:
	var ns = state.player()
	var subject := String(entry["subject"])
	var standing := bool(entry["standing"])
	match String(entry["kind"]):
		"crisis":
			return Strings.t("Crisis: %s") % _event(loader, subject)
		"decision":
			return Strings.t("%s needs an answer") % _event(loader, subject)
		"election":
			return Strings.t("The European election") if subject == "ep" else Strings.t("The next election")
		"bill":
			return Strings.t("The vote on %s") % _law(ns, loader, subject)
		"majority":
			if standing:
				return Strings.t("Your majority: %d of %d seats") % [int(ns.coalition_seats), int(ns.assembly_seats)]
			return Strings.t("Your government has no majority")
		"commitment":
			return Strings.t("Your word to %s") % loader.person_name(subject.split("|")[1] if subject.contains("|") else subject)
		"request":
			return Strings.t("%s asks to see you") % loader.person_name(subject.split("|")[0])
		"programme":
			if subject == "offer":
				return Strings.t("Choose the term's programme")
			return Strings.t("Programme: %s") % Strings.row_name("programme", Programme.terms_of(loader, subject))
		"bloc":
			var polled := PollNoise.displayed(int(state.year) * 12 + int(state.month), subject, float(ns.bloc_approval.get(subject, 0.0)))
			if standing:
				return Strings.t("Weakest in the polls: %s, %s%%") % [Labels.bloc(subject), Num.f(polled, 0)]
			if float(entry.get("moved", 0.0)) < 0.0:
				return Strings.t("%s turning against you") % Labels.bloc(subject)
			return Strings.t("%s coming round to you") % Labels.bloc(subject)
		"budget":
			if standing:
				var deficit := 0.0 if state.history.is_empty() else float(state.history[-1].get("deficit_pct_gdp", 0.0))
				return Strings.t("Deficit: %s%% of GDP") % Num.f(deficit, 1)
			return Strings.t("The deficit is widening")
		"unrest":
			if not standing:
				return Strings.t("Unrest is rising")
			if float(ns.unrest_pct) < 0.05:
				return Strings.t("Unrest is calm")
			return Strings.t("Unrest: %s%%") % Num.f(float(ns.unrest_pct), 1)
		"person":
			return Strings.t("%s is hostile and may leak") % loader.person_name(subject)
	return ""


## The deadline chip: "This month", "In 3 months", "" for a trend; "+N more" after.
static func chip(entry: Dictionary, state) -> String:
	var parts: PackedStringArray = []
	var deadline := int(entry["deadline_month"])
	if deadline >= 0 and not bool(entry["standing"]):
		var months := deadline - (int(state.year) * 12 + int(state.month))
		parts.append(Strings.t("This month") if months <= 0 else Strings.t("In %s") % Trends.months_text(months))
	elif deadline >= 0:
		parts.append(Strings.t("In %s") % Trends.months_text(deadline - (int(state.year) * 12 + int(state.month))))
	if int(entry["more"]) > 0:
		parts.append(Strings.tn("+%d more", "+%d more", int(entry["more"])) % int(entry["more"]))
	return " · ".join(parts)


static func _event(loader, event_id: String) -> String:
	var ev = Events.event_by_id(loader, event_id)
	return Strings.row_name("events", ev) if ev != null else event_id


static func _law(ns, loader, law_id: String) -> String:
	for law in loader.laws:
		if String(law.id) == law_id:
			return Strings.law_name(law)
	# A draft of the assembly's own: its name is in the draft.
	var draft: Dictionary = ns.draft_bills.get(law_id, {})
	return String(draft.get("name", law_id))  # i18n: row-ok a draft's generated name
