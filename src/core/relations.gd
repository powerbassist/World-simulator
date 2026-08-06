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

## V1.3c's directed key, for the register a tariff or a sanction lives on.
## Deliberately a DIFFERENT character from SEPARATOR: the two kinds of key are
## not interchangeable, and a directed key passed to key() or to other() would
## sort or split silently rather than fail. With distinct separators, other()
## returns "" for a directed key and every mix-up is visible.
##
## docs/diplomacy-model.md named this in advance as the additive escape hatch --
## a directed layer OVER the symmetric level, with the pair key unchanged and
## nothing already reading `relations` rewritten.
const DIRECTED_SEPARATOR := ">"


## The canonical key for an unordered pair. Sorted, so the caller's argument
## order cannot matter.
static func key(a: String, b: String) -> String:
	if a <= b:
		return a + SEPARATOR + b
	return b + SEPARATOR + a


## The key for one nation acting on another. NOT sorted, and that is the whole
## point: FRA>DEU and DEU>FRA are two separate entries, because a tariff and the
## retaliation against it are two acts and not one contract. An agreement stays
## on key() above, where both sides genuinely read the same terms.
static func directed_key(from: String, to: String) -> String:
	return from + DIRECTED_SEPARATOR + to


## The two sides of a directed key, as [from, to], or an empty array if the
## string is not one. Mirrors other()'s job for the symmetric key: nothing
## outside this file should be splitting a key by hand.
static func directed_parts(directed: String) -> Array:
	var parts := directed.split(DIRECTED_SEPARATOR)
	if parts.size() != 2:
		return []
	return [parts[0], parts[1]]


## The two sides of a symmetric key, as [a, b] with a < b, or an empty array if
## the string is not one. directed_parts()' twin, added at V1.3g because
## GameState.pacts is the first symmetric register something ITERATES rather than
## looks up: relations and agreements are always read for a pair the caller
## already knows, and other() serves that. Splitting by hand in src/sim/ is what
## this file exists to prevent, and the absence of this function was an invitation
## to do it.
static func pair_parts(pair_key: String) -> Array:
	var parts := pair_key.split(SEPARATOR)
	if parts.size() != 2:
		return []
	return [parts[0], parts[1]]


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
