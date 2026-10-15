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
const Orgs = preload("res://src/sim/orgs.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")


## What is on the table at this org's council, and the player's own vote.
## First, because it is the only part of this section the player can act on.
static func build(body: VBoxContainer, panel, state, ns, org) -> void:
	PanelKit.heading(body, "BEFORE THE COUNCIL")

	var pending: Dictionary = Orgs.pending(state, org.id)
	if pending.is_empty():
		PanelKit.line(body, "Nothing before the council. The presidency brings the next proposal forward in due course.")
	else:
		PanelKit.line(body, String(pending.get("name", "")), PanelKit.Tone.PLAIN)
		PanelKit.line(body, String(pending.get("summary", "")))
		PanelKit.line(body, "Divides in %d %s." % [
			int(pending.get("months_left", 0)),
			"month" if int(pending.get("months_left", 0)) == 1 else "months",
		], PanelKit.Tone.PLAIN)

		var current := String(pending.get("player_vote", Orgs.VOTE_ABSTAIN))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for choice in Orgs.VOTE_CHOICES:
			var button := Button.new()
			button.text = choice.capitalize()
			button.disabled = choice == current
			# An abstention is in the denominator and neither numerator, so sitting
			# out makes passage harder without spending anything on opposing it.
			# Said here because it is the one rule of this panel a player would
			# otherwise have to infer from a tally.
			if choice == Orgs.VOTE_ABSTAIN:
				button.tooltip_text = "Counted against the threshold, for neither side."
			button.pressed.connect(panel._on_vote.bind(org.id, choice))
			if not button.disabled:
				panel.offer_primary(button)
			row.add_child(button)
		body.add_child(row)
		PanelKit.line(body, "Currently: %s. %s holds %d of the council's seats." % [
			current, ns.id, org.seats(ns.id),
		])

	var last: Dictionary = Orgs.last_vote(state, org.id)
	if not last.is_empty():
		PanelKit.line(body, "", PanelKit.Tone.PLAIN)
		PanelKit.line(body, "Last division: %s — %s" % [
			String(last.get("name", "")), "carried" if bool(last.get("passed", false)) else "fell",
		], PanelKit.Tone.PLAIN)
		PanelKit.line(body, "%d for, %d against, of %d seats. %s voted %s." % [
			int(last.get("seats_for", 0)), int(last.get("seats_against", 0)),
			int(last.get("seats_total", 0)), ns.id, String(last.get("player_vote", "")),
		])
		_why(body, last)
	PanelKit.line(body, "", PanelKit.Tone.PLAIN)


## WHY each member voted as it did, not only how.
##
## Until V1.3e the eight voted on ideology alone and there was nothing to say.
## Now they price a proposal against their own books, and the division is only
## legible if the player can see that Luxembourg opposed a fund it would pay for
## while Italy backed one it would draw on. Grouped by reason rather than listed
## per nation: the interesting object is the CAMP. The reasons are recorded at
## the moment of the division by src/sim/orgs.gd, not recomputed here -- the
## books a member voted on were that month's.
static func _why(body: VBoxContainer, last: Dictionary) -> void:
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
		camps[key].append("%s %s" % [
			String(id), "for" if String(votes.get(id, "")) == Orgs.VOTE_FOR else "against",
		])

	var keys: Array = camps.keys()
	keys.sort()
	for key in keys:
		PanelKit.line(body, "%s: %s" % [_vote_reason_text(String(key)), ", ".join(camps[key])])


## The model returns a key; the wording lives here, because src/sim/ does not know
## the UI exists and a test should not assert on prose.
static func _vote_reason_text(key: String) -> String:
	match key:
		ForeignPolicy.VOTE_REASON_DRAWS_ON_IT: return "stood to draw on it"
		ForeignPolicy.VOTE_REASON_ALREADY_IN_BREACH: return "already outside the rule"
		ForeignPolicy.VOTE_REASON_WOULD_PAY: return "would have to pay for it"
		ForeignPolicy.VOTE_REASON_TRADES_OUTSIDE: return "trades outside the org"
		ForeignPolicy.VOTE_REASON_POLITICS: return "on the politics of it"
	return key
