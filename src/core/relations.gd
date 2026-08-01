extends RefCounted

## The pair key, and the only way to build one.
##
## Relations are the first live state in this project that is neither
## per-nation nor global -- a relations score belongs to a PAIR. This file
## exists so nothing can key that pair two different ways: every read and every
## write in src/sim/ and src/ui/ goes through key() below, and a "FRA|DEU" that
## should have been "DEU|FRA" is impossible rather than merely discouraged.
##
## The value is SYMMETRIC: one number per unordered pair, and rel(A, B) ==
## rel(B, A) is structurally true rather than an invariant someone has to
## maintain. The asymmetry that genuinely exists between two nations is about
## interest and leverage -- Luxembourg cares more about Germany than Germany
## about Luxembourg -- and that is derived per-viewer from size and trade share,
## both of which are already per-nation. It is not a second relations number.
## Full argument, including the additive route if V1.3c needs a directed
## grievance layer on top: docs/diplomacy-model.md.
##
## Lives in src/core/ rather than src/sim/ because it is a value-type helper
## over GameState, the same way src/core/law.gd is one over a data file -- it
## holds no model and no tunable. The model is src/sim/diplomacy.gd.

## Safe because every nation id is exactly three uppercase letters, checked by
## Nation._id_regex at load. A separator that could appear inside an id would
## make the key ambiguous.
const SEPARATOR := "|"


## The canonical key for an unordered pair. Sorted, so the caller's argument
## order cannot matter.
static func key(a: String, b: String) -> String:
	if a <= b:
		return a + SEPARATOR + b
	return b + SEPARATOR + a


## The pair's current score, or `fallback` if the pair has none. A missing pair
## is a real possibility only before seed_relations() has run; after that every
## pair in the roster exists, and a fallback that silently reads as 0.0 -- the
## WORST possible relations -- would be a lie. Callers that want the lie to be
## loud pass nothing and get NAN-free 0.0; Diplomacy.get_score() is the one that
## should be used in the model.
static func score(state, a: String, b: String, fallback := 0.0) -> float:
	return float(state.relations.get(key(a, b), fallback))


## Move a pair's score by `delta`, clamped. Returns the new value. The clamp
## lives here rather than at each call site so no writer can leave the pair
## outside the readable range.
static func adjust(state, a: String, b: String, delta: float, min_v: float, max_v: float) -> float:
	var k := key(a, b)
	var updated := clampf(float(state.relations.get(k, 0.0)) + delta, min_v, max_v)
	state.relations[k] = updated
	return updated


## Every unordered pair over `ids`, each once, as [a, b] with a < b. Sorted, so
## the seeding order -- and therefore anything that ever iterates relations --
## is reproducible rather than dependent on Dictionary ordering.
static func all_pairs(ids: Array) -> Array:
	var sorted := ids.duplicate()
	sorted.sort()
	var out: Array = []
	for i in sorted.size():
		for j in range(i + 1, sorted.size()):
			out.append([sorted[i], sorted[j]])
	return out


## The other half of a pair key, given one side. Used by the nation panel, which
## knows the player and the clicked nation but reads a keyed dictionary.
static func other(pair_key: String, known: String) -> String:
	var parts := pair_key.split(SEPARATOR)
	if parts.size() != 2:
		return ""
	if parts[0] == known:
		return parts[1]
	if parts[1] == known:
		return parts[0]
	return ""
