extends RefCounted

## The meetings -- V5.2b b3. A state visit, whichever way it went, is the
## president meeting the other nation's head, and a summit is a state visit with a
## scene: what passed between them lands in the president's registers (the
## author's answer 1, 2026-10-21: the registers reach the foreign heads the
## president meets). The model is docs/audiences-model.md "The meetings".
##
## THE STAMP IS ALREADY WRITTEN. Diplomacy stamps GameState.met_months for the pair
## when a verb that opens a meeting lands (V2.4a); this file only reads it, a month
## late on purpose: the player's own visit lands on a day of the month, the AI's in
## the month's Diplomacy step, and both stamps read `now - 1` at the next tick -- one
## rule, each meeting met once, and no register of its own. A pair stamped again the
## very next month is met once for the two (documented, not guarded).
##
## The summit's own scene stays summits.gd's pure read and main.gd's applier: the
## knowledge is the meeting's, so a scene and a plain visit teach alike. The played
## nation only -- the AI nations hold no audiences (spec C12).

const K = preload("res://src/sim/audience_constants.gd")
const President = preload("res://src/sim/president.gd")
const RK = preload("res://src/core/relations.gd")


## The heads the president met in the month that just ended, each now a little
## better known and liked. First in the WorldMonth "Audiences" step.
static func tick_month(state, loader) -> Array[String]:
	var met: Array[String] = []
	var ns = state.player()
	if ns == null:
		return met
	var last := int(state.year) * 12 + int(state.month) - 1
	for nation_id in state.nations:
		if nation_id == ns.id or int(state.met_months.get(RK.key(ns.id, nation_id), -1)) != last:
			continue
		var head := President.leader_id(state.nations[nation_id])
		if not President.covers(state, ns, loader, head):
			continue
		President.learn_from(state, ns, loader, head, K.KNOW_MEETING)
		President.adjust_rapport(state, ns, loader, head, K.RAPPORT_MEETING)
		met.append(head)
	return met
