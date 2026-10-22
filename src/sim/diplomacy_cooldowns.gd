extends RefCounted

## The monthly countdown of every nation's diplomatic cooldowns, moved verbatim
## out of Diplomacy._settle() so diplomacy.gd could take available()'s read memo
## without growing past its size baseline. execute() sets a cooldown under
## Diplomacy.cooldown_key(); this only counts them down. No state of its own, no
## sim module preloaded.
##
## And the HOST's register beside it (the V5.1 play gate's state-visit cadence):
## ns.diplo_hosted_months, {action_id: months}, stamped on the TARGET of a verb
## that carries host_interval_months and read by Diplomacy.available() for every
## actor. A cooldown on what a nation receives rather than on what it does, so it
## lives with the other cooldown and counts down in the same pass.


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
