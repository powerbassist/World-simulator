extends RefCounted

## V5.2b, "le cout s'efface": the acts' share of bloc_offset, the part that fades.
## Split out of characters.gd at its line cap (call A, #466's QA RECORDs): this file
## is the act_bloc_offset register's one writer. Characters books the month's acts and
## fades the share; a landed plant closure (closures.gd, the parent's TAKE 2 on #251)
## is an act too and books here. A leaf: its constants and the bounds, no system.

const CK = preload("res://src/sim/character_act_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")


## What the acts about to be priced are measured from: bloc_offset and the "bound" row
## as they stand. An old save's share is seeded first (QA's R1 on #466): a closure cut
## can come before the month's fade, and its own "acts" row would hide the old save.
static func snapshot(ns) -> Dictionary:
	_seed(ns)
	return {"offset": (ns.bloc_offset as Dictionary).duplicate(),
		"bound": (ns.offset_by_source.get("bound", {}) as Dictionary).duplicate()}


## What the acts since `before` wrote on bloc_offset -- the real delta, after the
## clamp, since nothing else in the window writes it -- joins the share that fades.
## The acts price through two doors (the applier for a brief,
## Government.penalise_blocs for the rest), so the record reads the result rather
## than either door. What of it was a clamp's pull-back (the "bound" row's move) is
## kept beside it, so the fade can book that part back to "bound".
static func book(ns, before: Dictionary) -> void:
	var was: Dictionary = before["offset"]
	var bound_was: Dictionary = before["bound"]
	var bound: Dictionary = ns.offset_by_source.get("bound", {})
	for bloc in ns.bloc_offset:
		var wrote := float(ns.bloc_offset[bloc]) - float(was.get(bloc, 0.0))
		if wrote != 0.0:
			ns.act_bloc_offset[bloc] = float(ns.act_bloc_offset.get(bloc, 0.0)) + wrote
			var pulled := float(bound.get(bloc, 0.0)) - float(bound_was.get(bloc, 0.0))
			if pulled != 0.0:
				ns.act_bound_share[bloc] = float(ns.act_bound_share.get(bloc, 0.0)) + pulled


## The share shrinks by ACT_OFFSET_MONTHLY_KEEP and bloc_offset gets back what
## faded, so a leak hurts the next vote and is then forgotten. A share too small to
## read is dropped, so the register does not grow a tail of zeros.
## The fade is one write per bloc, as it always was (bloc_offset moves bit for bit as
## before); its booking is then split: the pull-back's part of what it moved goes from
## "acts" to "bound" (QA's R0 on #466).
static func fade(ns) -> void:
	_seed(ns)
	for bloc in ns.act_bloc_offset.keys():
		var part := float(ns.act_bloc_offset[bloc])
		var kept := part * CK.ACT_OFFSET_MONTHLY_KEEP
		var acts_was := _acts_row(ns, bloc)
		ns.add_bloc_offset(bloc, kept - part, "acts", LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX)
		var pulled := float(ns.act_bound_share.get(bloc, 0.0))
		if pulled != 0.0 and part != 0.0:  # a share an opposite act cancelled to 0.0 moved nothing
			var back := (_acts_row(ns, bloc) - acts_was) * pulled / part
			ns.offset_by_source["acts"][bloc] = _acts_row(ns, bloc) - back
			var bound: Dictionary = ns.offset_by_source.get("bound", {})
			bound[bloc] = float(bound.get(bloc, 0.0)) + back
			ns.offset_by_source["bound"] = bound
		if absf(kept) < 0.000001:
			ns.act_bloc_offset.erase(bloc)
			ns.act_bound_share.erase(bloc)
		else:
			ns.act_bloc_offset[bloc] = kept
			if pulled != 0.0:
				ns.act_bound_share[bloc] = pulled * CK.ACT_OFFSET_MONTHLY_KEEP


## A share with no "acts" row is a save from before offset_by_source (an act always
## books its row, even at 0): the share is the acts', so seed it and the fade nets it out
## rather than opening a positive row against earlier. Lazy, so the field table's absent
## still reads its default; a copy, so the row and the share move apart.
static func _seed(ns) -> void:
	if not ns.act_bloc_offset.is_empty() and not ns.offset_by_source.has("acts"):
		ns.offset_by_source["acts"] = ns.act_bloc_offset.duplicate()


static func _acts_row(ns, bloc: String) -> float:
	return float((ns.offset_by_source.get("acts", {}) as Dictionary).get(bloc, 0.0))
