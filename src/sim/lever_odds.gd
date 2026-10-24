extends RefCounted

## The audience's odds and their fog -- V5.2b b2. Pure: what a lever's chance is
## for this person in this CELL, how wide the printed range is, and which traits
## the president can see. The model is docs/audiences-model.md "The audience";
## the bands are docs/design/bands-v5.2.md B4 (the fog) and B5 (no lever
## dominates), measured by tools/lever_probe.gd.
##
## THE CELL IS THE WHOLE INPUT besides the person's content:
## {knowledge, rapport, relationship, aligned, standing, approval}. Levers builds
## it from the registers; the probe builds B5's grid cells directly, so the
## numbers the band judges are the numbers the scene shows -- one function, not a
## copy of it.
##
## THE FOG NEVER LIES (the author's "fog is shown, never silent"). The range is
## placed around the truth by a seeded offset, so the truth is always inside and
## not always in the middle: a centred range would print the answer.

const K = preload("res://src/sim/lever_constants.gd")
const PK = preload("res://src/sim/president_constants.gd")
const President = preload("res://src/sim/president.gd")
const Cycle = preload("res://src/sim/cycle.gd")


## The true chance that `lever` works on `person` in `cell`, in
## [ODDS_MIN, ODDS_MAX], or -1.0 when the lever is not offered (friendship below
## friend). Each term is the spec's lever table, read off the eight traits that
## already ship (people-model 14.2).
static func odds(person, lever: String, cell: Dictionary) -> float:
	var traits: Array = person.traits
	var k := float(cell.get("knowledge", 0.0))
	var v := 0.0
	match lever:
		"argue":
			v = K.ARGUE_BASE + K.ARGUE_KNOW * k
			v += K.ARGUE_ALIGN if bool(cell.get("aligned", false)) else -K.ARGUE_ALIGN
			if traits.has("stubborn"):
				v += K.ARGUE_STUBBORN
		"bargain":
			v = K.BARGAIN_BASE + K.BARGAIN_KNOW * k
			if traits.has("pragmatic"):
				v += K.BARGAIN_PRAGMATIC
			if traits.has("principled"):
				v += K.BARGAIN_PRINCIPLED
		"promise_date":
			v = K.PROMISE_BASE + K.PROMISE_KNOW * k
			if traits.has("ambitious"):
				v += K.PROMISE_AMBITIOUS
			v += K.PROMISE_SKILL * maxf(0.0, float(person.social_skill) - 0.5) * 2.0
		"pressure":
			v = K.PRESSURE_BASE + K.PRESSURE_KNOW * k
			v += K.PRESSURE_STANDING * (float(cell.get("standing", 0.5)) - 0.5)
			v += K.PRESSURE_APPROVAL * (float(cell.get("approval", 50.0)) - 50.0) / 50.0
			if traits.has("networked"):
				v += K.PRESSURE_NETWORKED
			if traits.has("stubborn"):
				v += K.PRESSURE_STUBBORN
		"flatter":
			v = K.FLATTER_BASE + K.FLATTER_KNOW * k + K.FLATTER_SKILL * float(person.social_skill)
			if traits.has("vain"):
				v += K.FLATTER_VAIN
		"friendship":
			var bond := String(cell.get("relationship", ""))
			if not K.FRIEND_BONDS.has(bond):
				return -1.0
			v = K.FRIEND_BASE + K.FRIEND_KNOW * k
			if bond == "close":
				v += K.FRIEND_CLOSE
		_:
			return -1.0
	v += K.K_RAPPORT * float(cell.get("rapport", 0.0))
	return clampf(v, K.ODDS_MIN, K.ODDS_MAX)


## B4's width: FOG_STRANGER below the acquaintance edge, linear to FOG_KNOWN at
## the known edge, FOG_KNOWN above it.
static func fog_width(knowledge: float) -> float:
	if knowledge <= PK.KNOWLEDGE_ACQUAINTANCE:
		return K.FOG_STRANGER
	if knowledge >= PK.KNOWLEDGE_KNOWN:
		return K.FOG_KNOWN
	var t := (knowledge - PK.KNOWLEDGE_ACQUAINTANCE) / (PK.KNOWLEDGE_KNOWN - PK.KNOWLEDGE_ACQUAINTANCE)
	return lerpf(K.FOG_STRANGER, K.FOG_KNOWN, t)


## The printed range around the true odds `p`, as (lo, hi). The seeded offset
## puts the truth anywhere inside; a range that would leave [0, 1] is shifted
## back, never narrowed, so the width is always B4's and the truth stays inside.
static func shown_range(person_id: String, lever: String, p: float, knowledge: float) -> Vector2:
	var w := fog_width(knowledge)
	var offset := Cycle.unit_pair(person_id, "%s:%s" % [K.SALT_FOG, lever], 0)
	var lo := clampf(p - w * offset, 0.0, 1.0 - w)
	return Vector2(lo, lo + w)


## The person's traits the president can see: each shows once knowledge reaches
## its seeded reveal point, between TRAIT_REVEAL_FLOOR and 1 of the known edge.
## So a stranger sees none, a known person all, and a trait never shows wrong --
## an unseen one reads as unknown.
static func known_traits(ns, person) -> Array[String]:
	var out: Array[String] = []
	var k := President.knowledge(ns, person.id)
	for t in person.traits:
		var at := lerpf(K.TRAIT_REVEAL_FLOOR, 1.0, Cycle.unit_pair(person.id, "%s:%s" % [K.SALT_TRAIT, t], 0))
		if k >= at * PK.KNOWLEDGE_KNOWN:
			out.append(String(t))
	return out
