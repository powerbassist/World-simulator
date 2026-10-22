extends RefCounted

## The monthly countdown of every nation's diplomatic cooldowns, moved verbatim
## out of Diplomacy._settle() so diplomacy.gd could take available()'s read memo
## without growing past its size baseline. execute() sets a cooldown under
## Diplomacy.cooldown_key(); this only counts them down. No state of its own, no
## sim module preloaded.


## Cooldowns tick for every nation, not just the player's -- V1.3e will have
## the other nine acting through this same path, and a counter that only
## counts down for one nation would be a bug that only surfaced then.
static func tick(state) -> void:
	for ns in state.nations.values():
		var expired: Array = []
		for cooldown_key in ns.diplo_cooldown_months:
			var remaining: int = int(ns.diplo_cooldown_months[cooldown_key]) - 1
			if remaining <= 0:
				expired.append(cooldown_key)
			else:
				ns.diplo_cooldown_months[cooldown_key] = remaining
		for cooldown_key in expired:
			ns.diplo_cooldown_months.erase(cooldown_key)
