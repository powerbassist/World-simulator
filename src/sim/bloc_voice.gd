extends RefCounted

## A person's voice on the briefing's blocs (CK.BRIEF_BLOCS), both ways. Split out of
## characters.gd, which is at its size cap, and a leaf: it preloads constants and the one
## applier, and is handed the briefing's size rather than reading Characters.
##
## AGAINST: a briefing (Characters' "brief_against" act) writes blocs(magnitude) with the
## briefing's negative price.
## FOR (V5.3 e, the author's "Construire le discours"; Gameplay's regions brief, section 5b):
## when a development fund opens in the region a figure wants -- their `region:` want turns
## served -- the figure speaks for the government, once: blocs() at CK.SPEAK_SHARE of their
## briefing's size, the other sign. It runs in the acts' loop, so it is booked in the acts'
## share (fades on the same half-life, counted by the acts band) and takes the figure's one
## act of the month. A hostile figure (a grudge at the briefing's threshold) does not speak.
## It fires on the fund, not on an ask; an office served is left out, because a government
## formed by an election hands out posts the player did not choose.

const CK = preload("res://src/sim/character_act_constants.gd")
const Legislature = preload("res://src/sim/legislature.gd")


## The briefing's blocs, each at `magnitude` (negative against, positive for).
static func blocs(magnitude: float) -> Dictionary:
	var out := {}
	for bloc in CK.BRIEF_BLOCS:
		out[bloc] = magnitude
	return out


## The month's speeches: each [figure, region id] in `speakers` (the figure's region want turned
## served this month) speaks unless hostile or already acting; the act names the region. `brief_size` is Characters.brief_magnitude; `act`
## builds the act row (Characters._act). Writes through the applier, as a briefing does.
static func speak_for(state, ns, loader, speakers: Array, acted: Dictionary, acts: Array,
		brief_size: Callable, act: Callable) -> void:
	for pair in speakers:
		var person = pair[0]
		if acted.has(person.id) or float(ns.person_grudges.get(person.id, 0.0)) >= CK.GRUDGE_BRIEF_THRESHOLD:
			continue
		var size: float = -CK.SPEAK_SHARE * float(brief_size.call(person, float(ns.person_standing.get(person.id, 0.0))))
		Legislature.apply_effects(state, ns, {"bloc_offset": blocs(size)}, loader, "acts")
		acted[person.id] = true
		acts.append(act.call(state, "speak_for", person.id, {"region": String(pair[1])}))
