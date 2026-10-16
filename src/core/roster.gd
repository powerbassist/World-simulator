extends RefCounted

## V4.11. The roster's grade, DERIVED from the registers rather than stored.
## Three grades exist -- playable, simulated, outline -- and only nation files
## carry a flag, so a stored three-value field could hold two values at most:
## the fold the V4.11 handoff asked for would have migrated every nation file
## to say what `playable` already says. `src/sim/` reads neither; AI depth is
## the runtime `has_budget` gate, which is why "simulated" needs no machine.


## "playable" / "simulated" for a nation file, "outline" for an outline-register
## country, "" for anything else.
static func grade(loader, id: String) -> String:
	var nation = loader.nations.get(id, null)
	if nation != null:
		return "playable" if nation.playable else "simulated"
	# V4.11b: the outline REGISTER (data/world/outlines.json), which the loader
	# pins to world.geojson's drawn set one-for-one.
	if loader.outlines.has(id):
		return "outline"
	return ""
