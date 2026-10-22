extends RefCounted

## The monthly countdown of every nation's diplomatic cooldowns, moved verbatim
## out of Diplomacy._settle() so diplomacy.gd could take available()'s read memo
## without growing past its size baseline. execute() sets a cooldown under
## Diplomacy.cooldown_key(); this only counts them down. No state of its own, and
## no sim system preloaded (one constants file, below).
##
## And the HOST's register beside it (the V5.1 play gate's state-visit cadence):
## ns.diplo_hosted_months, {action_id: months}, stamped on the TARGET of a verb
## that carries host_interval_months and read by Diplomacy.available() for every
## actor. A cooldown on what a nation receives rather than on what it does, so it
## lives with the other cooldown and counts down in the same pass.
##
## Calendar's constants are the one preload: unreserved() reads the diary's
## booked status, a plain field, the way calendar.gd reads this file's registers.

const CalK = preload("res://src/sim/calendar_constants.gd")


## Both registers empty -- Diplomacy.init_nation()'s reset.
static func reset(ns) -> void:
	ns.diplo_cooldown_months = {}
	ns.diplo_hosted_months = {}


## execute()'s two stamps for an applied act: the actor's cooldown against this
## target under `key` (Diplomacy.cooldown_key(), passed in so the key has one
## author), and the target's host interval.
static func stamp(state, ns, action, target_id: String, key: String) -> void:
	if action.cooldown_months > 0:
		ns.diplo_cooldown_months[key] = action.cooldown_months
	if action.host_interval_months > 0:
		var host = state.nations.get(target_id)
		if host != null:
			host.diplo_hosted_months[action.id] = action.host_interval_months


## The verbs `target_id` has received within their host interval, by id. Empty
## for a nation not on the roster.
static func hosted(state, target_id: String) -> Dictionary:
	var host = state.nations.get(target_id)
	return host.diplo_hosted_months if host != null else {}


## The AI agenda's half of the host rule: `offers` without any verb carrying a
## host interval that the player's diary has BOOKED against `target_id` on a date
## inside that interval from now. An AI act now would still stand on the booked
## day and refuse it there ("It did not carry."), so a booking reserves the host.
## Only Diplomacy._best_act() -- the agenda -- calls this; the player's own offers
## never pass through it. Nothing booked returns `offers` itself.
static func unreserved(state, target_id: String, offers: Array) -> Array:
	if state.appointments.is_empty() or offers.is_empty():
		return offers
	var now: int = int(state.year) * 12 + int(state.month)
	var out: Array = []
	for action in offers:
		var keep: bool = true
		if action.host_interval_months > 0:
			for e in state.appointments:
				if String(e.get("status", "")) == CalK.STATUS_BOOKED and String(e.get("target_id", "")) == target_id \
						and String(e.get("action_id", "")) == action.id \
						and int(e.get("year", 0)) * 12 + int(e.get("month", 0)) - now < action.host_interval_months:
					keep = false
		if keep:
			out.append(action)
	return out


## Cooldowns tick for every nation, not just the player's -- V1.3e will have
## the other nine acting through this same path, and a counter that only
## counts down for one nation would be a bug that only surfaced then. Run in
## _settle(), before any actor's turn, so a host stamped with N months in month m
## is offered the verb again from month m + N: at most ceil(12 / N) a year.
static func tick(state) -> void:
	for ns in state.nations.values():
		_count_down(ns.diplo_cooldown_months)
		_count_down(ns.diplo_hosted_months)


static func _count_down(register: Dictionary) -> void:
	var expired: Array = []
	for cooldown_key in register:
		var remaining: int = int(register[cooldown_key]) - 1
		if remaining <= 0:
			expired.append(cooldown_key)
		else:
			register[cooldown_key] = remaining
	for cooldown_key in expired:
		register.erase(cooldown_key)
