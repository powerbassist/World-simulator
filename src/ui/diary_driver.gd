extends RefCounted

## The dispatcher. src/sim/calendar.gd hands back entries and knows nothing about
## what they mean; this fires the command. Every system named here was already
## preloaded by this file, so the diary added no dependency to it -- and composing
## two systems' effects is the orchestrator's job, which is the call
## docs/cabinet-model.md records for Cabinet.seat() and the reason a scheduler
## reaching into three systems was refused.
##
## The `match` is a fixed, small set of system verbs -- the same class as
## _act_reason_text()'s key-to-wording map -- not per-nation or per-law content,
## so docs/engine-decision.md Rule 1 holds.
##
## V5.1c: out of main.gd (D2), as a pure dispatcher. The UI's half of each
## outcome -- the measured effect, the card, a summit -- goes back through
## `on_outcome`, called per entry before the next one fires, so the order of a
## day with two appointments is the one main.gd had.

const Trends = preload("res://src/ui/trends.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Removal = preload("res://src/sim/removal.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")


static func resolve(state, loader, year: int, month: int, day: int, on_outcome: Callable) -> bool:
	var due: Array = Calendar.due(state, year, month, day)
	if due.is_empty():
		return false

	var ns = state.player()

	for entry in due:
		# THE BASELINE IS TAKEN HERE, not when the player booked. U4's decision
		# delta measures a command against the next history entry, and a booking
		# commits nothing in the month it is made -- measured from the press, a
		# deferred act would report the movements of a month in which it did not
		# happen. _pending_effects is also documented as not persisted, so a save
		# across a booking would lose a baseline taken at the press entirely.
		var before := Trends.snapshot_now(state)
		before.merge(Opinion.snapshot(state))

		var label := ""
		var ok := false
		match String(entry.get("kind", "")):
			CalendarK.KIND_DIPLOMATIC:
				var action = _action_by_id(loader, String(entry.get("action_id", "")))
				if action != null:
					var result := Diplomacy.execute(
						state, loader.diplomatic_actions, action,
						state.player_nation_id, String(entry.get("target_id", "")),
					)
					# execute()'s contract is `applied`, not `ok` -- V2.4a found
					# this read as false on every arrival, so a kept visit fired
					# its effects and was recorded as refused anyway.
					ok = bool(result.get("applied", false))
					label = Strings.row_name("diplomatic-actions", action)
			CalendarK.KIND_LAW:
				var law = _law_by_id(loader, String(entry.get("law_id", "")))
				if law != null:
					var result := Legislature.propose(state, loader, law)
					ok = bool(result.get("passed", false))
					label = Strings.law_name(law)
			# V5.2b: the booked audience happens -- the scene opens (audience_driver.gd)
			# and the sim holds it; what it settles is the scene's, not the diary's.
			CalendarK.KIND_AUDIENCE:
				ok = true
			CalendarK.KIND_RESHUFFLE:
				var portfolio := String(entry.get("portfolio", ""))
				var party_id := String(entry.get("party_id", ""))
				# V5.2 b+ R4: the command that prices a removal (Removal.why_not refuses
				# a second removal of one office within the year, on the day as at booking).
				ok = ns != null and bool(Removal.reassign(state, loader, portfolio, party_id).get("ok", false))
				label = Labels.portfolio(portfolio)

		Calendar.resolve(state, Calendar.verb_key(entry), ok)

		# V2.4b: a meeting that LANDED is the summit's trigger. Only the verb
		# that opens a meeting brings a scene; a refused arrival is a journey
		# home, and day-only acts were never journeys.
		var summit_target := ""
		if ok and String(entry.get("kind", "")) == CalendarK.KIND_DIPLOMATIC:
			var action2 = _action_by_id(loader, String(entry.get("action_id", "")))
			if action2 != null and action2.opens_meeting:
				summit_target = String(entry.get("target_id", ""))
		# The UI's half, per entry and in the diary's order (main.gd: the measured
		# effect, the card, the summit), before the next entry fires.
		on_outcome.call({"entry": entry, "label": label, "ok": ok, "before": before, "summit_target": summit_target})
	return true


static func _action_by_id(loader, id: String):
	for action in loader.diplomatic_actions:
		if String(action.id) == id:
			return action
	return null


static func _law_by_id(loader, id: String):
	for law in loader.laws:
		if String(law.id) == id:
			return law
	return null
