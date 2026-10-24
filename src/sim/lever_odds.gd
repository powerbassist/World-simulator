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
			v += K.PROMISE_SKILL * maxf(0.0, float(person.social_skill) - K.SKILL_MIDDLING) / (1.0 - K.SKILL_MIDDLING)
		"pressure":
			v = K.PRESSURE_BASE + K.PRESSURE_KNOW * k
			v += K.PRESSURE_STANDING * (float(cell.get("standing", K.STANDING_NEUTRAL)) - K.STANDING_NEUTRAL)
			v += K.PRESSURE_APPROVAL * (float(cell.get("approval", K.APPROVAL_NEUTRAL)) - K.APPROVAL_NEUTRAL) / K.APPROVAL_NEUTRAL
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
##
## THE OFFSET IS SEEDED BY THE KNOWLEDGE TOO (QA's R1 on #113). With one offset
## per (person, lever), two readings at different widths -- a topic taught
## something between them -- gave the truth back exactly:
## offset = (lo2 - lo1) / (w1 - w2).
##
## AND EACH STEP'S WINDOW SITS INSIDE THE LAST (pre-gate B, RECORD 6; B4's
## amendment). A fresh offset per knowledge step let the window jump anywhere,
## down included: Turcy's Promise read 47-83 % before a friendly topic and 32-68 %
## after, while the true odds could only have risen. So the distance below the
## truth is a seeded CHAIN over the FOG_SEED_STEP grid (below()): each step draws
## the next one inside the previous window, measured from the truth, and between
## grid points the window moves continuously toward the next step's. Below the
## truth and above it therefore never grow with knowledge; the window rides the
## odds and only shrinks around them. Repeated readings still only intersect, and
## the latest window is all they tell.
static func shown_range(person_id: String, lever: String, p: float, knowledge: float, draw_seed: int = 0) -> Vector2:
	var w := fog_width(knowledge)
	var lo := clampf(p - below(person_id, lever, knowledge, draw_seed), 0.0, 1.0 - w)
	return Vector2(lo, lo + w)


## How far below the truth the window's lower edge sits at `knowledge`, before the
## [0, 1] shift, in [0, fog_width(knowledge)]. Stateless: the chain is walked from
## the stranger's draw at step 0 every time, and a step where the width does not
## move (below acquaintance, above known) draws nothing.
static func below(person_id: String, lever: String, knowledge: float, draw_seed: int = 0) -> float:
	var salt := Cycle.salted("%s:%s" % [K.SALT_FOG, lever], draw_seed)
	var w_prev := fog_width(0.0)
	var a := w_prev * Cycle.unit_pair(person_id, salt, 0)
	var steps := floori(knowledge / K.FOG_SEED_STEP)
	for j in range(1, steps + 1):
		var w_j := fog_width(j * K.FOG_SEED_STEP)
		if w_j < w_prev:
			a = _inside(a, w_prev, w_j, Cycle.unit_pair(person_id, salt, j))
		w_prev = w_j
	var w := fog_width(knowledge)
	if w < w_prev:
		a = _inside(a, w_prev, w, Cycle.unit_pair(person_id, salt, steps + 1))
	return a


## The next distance below the truth for a window narrowing from `w_old` to
## `w_new`, inside the old one: at most `a` (the lower edge does not fall further
## below) and at least a - (w_old - w_new) (the upper edge does not rise further
## above), within [0, w_new]; `u` places it.
static func _inside(a: float, w_old: float, w_new: float, u: float) -> float:
	var lo := maxf(0.0, a - (w_old - w_new))
	var hi := minf(a, w_new)
	return lo + u * (hi - lo)


## The person's traits the president can see: each shows once knowledge reaches
## its seeded reveal point, between TRAIT_REVEAL_FLOOR and 1 of the known edge.
## So a stranger sees none, a known person all, and a trait never shows wrong --
## an unseen one reads as unknown.
static func known_traits(ns, person) -> Array[String]:
	var out: Array[String] = []
	var k := President.knowledge(ns, person.id)
	for t in person.traits:
		var at := lerpf(K.TRAIT_REVEAL_FLOOR, 1.0, Cycle.unit_pair(person.id, Cycle.salted("%s:%s" % [K.SALT_TRAIT, t], ns.draw_seed), 0))
		if k >= at * PK.KNOWLEDGE_KNOWN:
			out.append(String(t))
	return out
