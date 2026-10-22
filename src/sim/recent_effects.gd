extends RefCounted

## The one writer of GameState.recent_effects -- what the player's last few
## commands did (U4). AGENTS.md rule 2: the UI reads GameState and never writes
## it, and player intent comes back as an explicit command, Budget.commit() the
## model. The measurement stays the UI's (src/ui/effects_ledger.gd builds the
## entry with Trends, which src/sim/ cannot reach); this records it, the way
## commit() takes a plan the panel built. tests/test_effects_ledger.gd fails if
## anything else under src/ writes the register.
##
## No state of its own; its bound is recent_effects_constants.gd's.

const K = preload("res://src/sim/recent_effects_constants.gd")


## Record one measured close, newest first, and keep the last K.KEPT.
static func record(state, effect: Dictionary) -> void:
	state.recent_effects.push_front(effect)
	while state.recent_effects.size() > K.KEPT:
		state.recent_effects.remove_at(state.recent_effects.size() - 1)
