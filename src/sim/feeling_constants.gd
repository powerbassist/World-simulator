extends RefCounted

## The feeling bands' cuts -- where a person's grudge, rapport or loyalty changes
## its word on a card (src/ui/feelings.gd holds the words) and, since V5.3 B7, where
## the quiet-month call and the density probe judge whether a request's answers
## differ (request_landings.gd): the author's ruling of 2026-11-10 moved the cuts
## here so the sim and the screen read one definition. Each cut is where the
## person's behaviour changes (0.45 the brief, 0.60 the defection, the resign floor),
## the spec's own (docs/design/v5.2-bplus-spec.md R11 + Q2).
##
## Each register's bands, lowest first: [the band's upper cut, whether the band
## includes that cut]. A band index is the same index into feelings.gd's words.

const ActK = preload("res://src/sim/character_act_constants.gd")
## bands-v5.2.md, the B6 amendment: ONE comparison for every cut, the one the
## sim's bonds call too, so a card cannot say "cold" while the bond says nothing.
const Cut = preload("res://src/core/cut.gd")

const CUTS := {
	"grudge": [[0.05, false], [0.20, false], [0.45, false], [0.60, false], [INF, true]],
	"rapport": [
		[-0.30, false], [-0.05, false],
		# Closed at both ends: a delegation's snub (-0.05) from 0 stays neutral, so
		# only a refusal (-0.10) moves this word.
		[0.05, true], [0.30, true], [INF, true],
	],
	"loyalty": [
		# Closed at the floor: the premier resigns AT it (characters.gd, loyalty <=
		# the floor), so the floor itself reads as the brink. The sim's constant,
		# never a copy (the parent's call on #151).
		[ActK.LOYALTY_RESIGN_FLOOR, true], [-0.10, false], [0.10, true], [0.40, true], [INF, true],
	],
}
## Each register's span: a landing is clamped into it before its band is read.
const RANGE := {"grudge": Vector2(0.0, 1.0), "rapport": Vector2(-1.0, 1.0), "loyalty": Vector2(-1.0, 1.0)}


## The band `value` falls in, lowest first; -1 above every cut (NaN).
static func band(register: String, value: float) -> int:
	var cuts: Array = CUTS[register]
	for i in cuts.size():
		var cut := float(cuts[i][0])
		if Cut.at_or_below(value, cut) if bool(cuts[i][1]) else Cut.below(value, cut):
			return i
	return -1
