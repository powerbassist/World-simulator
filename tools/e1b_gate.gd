extends RefCounted

## events_probe's E1b gate (D4), after the author's call of 2026-10-30: "Mesurer les
## événements seuls, le reste en V5.3". The band judges the EVENT BOOK'S OWN share of
## each bloc's offset over a run -- every choice the run applied to the player (a
## default at its deadline, or an answer), times its authored bloc_offset -- against
## the clamp. The live register is reported beside it and not gated: the scenario's
## authored approval seeds it and other writers move it (Government.penalise_blocs,
## campaigns, pledges, energy, diplomacy, projects...), which is V5.3's carry
## (docs/someday.md), not the event book's.
##
## The share is UNCLAMPED, which is the point: the clamp hid how far past it a career
## of defaults drove a bloc. tests/test_e1b_gate.gd pins both functions and that the
## probe gates through them.

const OpinionK = preload("res://src/sim/opinion_constants.gd")

## Below the clamp by more than this is slack; within it is at the clamp (the live
## register's own reading, kept for the share).
const AT_CLAMP_EPS := 0.001


## bloc -> the summed authored bloc_offset of every applied choice, from the probe's
## fires_by_choice ({event_id: {choice_id: times applied}}). Every bloc is present;
## an event or choice content does not define counts nothing.
static func event_share(loader, fires_by_choice: Dictionary) -> Dictionary:
	var out := {}
	for bloc in OpinionK.BLOC_KEYS:
		out[bloc] = 0.0
	for event_id in fires_by_choice:
		var ev = null
		for candidate in loader.events:
			if String(candidate.id) == String(event_id):
				ev = candidate
				break
		if ev == null:
			continue
		for choice_id in fires_by_choice[event_id]:
			var offsets: Dictionary = (ev.choice_by_id(String(choice_id)).get("effects", {}) as Dictionary).get("bloc_offset", {})
			for bloc in offsets:
				out[bloc] = float(out.get(bloc, 0.0)) + float(offsets[bloc]) * int(fires_by_choice[event_id][choice_id])
	return out


## The blocs whose share sits at or past the clamp, either sign, in BLOC_KEYS order.
static func saturated(share: Dictionary, clamp_max: float) -> Array:
	var out: Array = []
	for bloc in OpinionK.BLOC_KEYS:
		if absf(float(share.get(bloc, 0.0))) >= clamp_max - AT_CLAMP_EPS:
			out.append(bloc)
	return out
