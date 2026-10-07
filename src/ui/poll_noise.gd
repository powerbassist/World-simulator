extends RefCounted

## Polling noise. A published poll is not the truth, and the player should never
## be able to read approval off the screen exactly.
##
## This lives in src/ui/ and nothing in src/sim/ references it, on purpose. The
## simulation contains no randomness at all — that is what makes the budget
## projection provably equal to what subsequently happens (tests/test_budget.gd,
## to 1e-9). So the model never stores a noisy number; the panel adds noise the
## moment it renders one.
##
## Which means the noise cannot be a live rand() either: it is a pure function of
## (poll id, key). Two consequences, both wanted:
##
##   - The panel shows the same figures on every repaint within a month. A poll is
##     a published figure, not a re-roll on each frame.
##   - The numbers survive a save and reload, because there is no RNG state to
##     serialise. S9 gets this for free.
##
## The hash is written out rather than delegated to Godot's `hash()`, so the
## figures do not depend on an engine-internal detail that could change under a
## save file.

## Displayed figures land within this many points of the truth, uniformly.
const NOISE_MAX_PCT := 3.0

## V4.2 T5. The margin of a COMMISSIONED poll -- one the government paid to
## have done properly. The same hash as the ordinary read (the same pollster's
## error keeps its sign), measured at a third of the band: paying narrows the
## number the player already had, it does not draw a new one. display-side
## only, like everything in this file -- the sim never learns a poll exists.
const PRECISE_MAX_PCT := 1.0

const _U32 := 0xFFFFFFFF


## A poll is published once a month and identified by the month it was taken in.
static func poll_id(year: int, month: int) -> int:
	return year * 12 + month


## What the poll says about `true_value`, given the poll and what is being asked
## about. Clamped to the 0-100 the reader expects of an approval figure.
static func displayed(id: int, key: String, true_value: float) -> float:
	return clampf(true_value + offset(id, key), 0.0, 100.0)


## V4.2 T5. The same poll at the commissioned margin -- the read the briefing
## shows once the bill's poll has been bought. Additive on purpose:
## `displayed()` above is untouched, and the existing readers (polling panel,
## overview, trends) keep their band. Shares `_unit()` with `offset()`, so for
## one (id, key) the precise figure always sits inside the ordinary one's
## error bar -- a sharper instrument over the same fieldwork, not a second one.
static func displayed_precise(id: int, key: String, true_value: float) -> float:
	return clampf(true_value + (_unit(id, key) * 2.0 - 1.0) * PRECISE_MAX_PCT, 0.0, 100.0)


## The error this poll happens to carry, in points. Uniform on
## [-NOISE_MAX_PCT, +NOISE_MAX_PCT], so it is unbiased over many polls.
static func offset(id: int, key: String) -> float:
	return (_unit(id, key) * 2.0 - 1.0) * NOISE_MAX_PCT


## Deterministic uniform in [0, 1). FNV-1a over the key, mixed with the poll id
## through splitmix32's finaliser — enough decorrelation that consecutive polls
## and neighbouring blocs look independent, in about ten lines.
static func _unit(id: int, key: String) -> float:
	var z: int = (id * 0x9E3779B1 + _key_seed(key)) & _U32
	z = (z + 0x9E3779B9) & _U32
	z = ((z ^ (z >> 16)) * 0x21F0AAAD) & _U32
	z = ((z ^ (z >> 15)) * 0x735A2D97) & _U32
	z = (z ^ (z >> 15)) & _U32
	return float(z & 0xFFFFFF) / float(0x1000000)


static func _key_seed(key: String) -> int:
	var h: int = 2166136261
	for i in key.length():
		h = (h ^ key.unicode_at(i)) & _U32
		h = (h * 16777619) & _U32
	return h
