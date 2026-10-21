extends RefCounted

## The embassies that already exist -- V5.1-0d. Before this nothing modelled them,
## so open_embassy (gated on a meeting and relations >= 50) was offered to France
## for Croatia and Cyprus, and a hands-off run had the AI open 33 embassies in the
## player's capital in its first three years. The register is
## NationState.embassies; the verb's own `embassy_held` precondition reads it and
## its `embassy` effect writes it, both in diplomacy.gd beside the other channels.
##
## Its own file so diplomacy.gd stays within its size baseline; no state of its
## own, no sim module preloaded.

const RK = preload("res://src/core/relations.gd")


## Every roster state holds an embassy in every other's capital, except the pairs
## data/world/embassies.json lists as having no diplomatic relations. Called once
## at new game, from Diplomacy.seed_relations(). Sorted, so a save's bytes do not
## depend on Dictionary order.
static func seed_register(state, loader) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for a in ids:
		var held: Array = []
		for b in ids:
			if a != b and not loader.embassy_exceptions.has(RK.key(a, b)):
				held.append(b)
		state.nations[a].embassies = held
