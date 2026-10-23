extends RefCounted

## The series a chart draws, read off GameState.history -- V5.2-0a. History is the
## one rolling record the game keeps (one player-nation snapshot a month, written by
## src/sim/world_month.gd, kept through a save); this module only reads it. A figure
## the history does not carry is a register for Systems to add, never a series
## rebuilt here from the current state.
##
## Approval is the PUBLISHED poll, never the truth: each month's figure goes through
## PollNoise with that month's poll id and the polling panel's key, so the line the
## player reads is the run of polls they were shown, and the model's own number
## never reaches the screen.

const PollNoise = preload("res://src/ui/poll_noise.gd")


## The current term's entries, oldest first: the last months_in_term + 1 (the
## month the term began included), bounded by what the history holds -- a load
## mid-term reads its window off the nation, not off the history's length.
static func term_window(state) -> Array:
	var ns = state.player()
	if ns == null:
		return []
	return last(state, int(ns.months_in_term) + 1)


## The last `count` entries, oldest first.
static func last(state, count: int) -> Array:
	var n: int = state.history.size()
	return state.history.slice(maxi(n - count, 0), n)


## One figure per entry; an entry without the key is no point (never a zero).
static func values(entries: Array, key: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for e in entries:
		if e.has(key):
			out.append(float(e[key]))
	return out


static func months(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		out.append([int(e.get("year", 0)), int(e.get("month", 0))])
	return out


## The polls as published: `key` is the history field ("overall_approval_pct", or
## "bloc_approval" read at `poll_key`), `poll_key` the polling panel's key for it.
static func polled(entries: Array, key: String, poll_key: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for e in entries:
		var truth = e.get(key, null)
		if truth is Dictionary:
			truth = truth.get(poll_key, null)
		if truth == null:
			continue
		var id := PollNoise.poll_id(int(e.get("year", 0)), int(e.get("month", 0)))
		out.append(PollNoise.displayed(id, poll_key, float(truth)))
	return out
