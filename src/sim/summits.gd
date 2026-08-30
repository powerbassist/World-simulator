extends RefCounted

## Summit scenes, V2.4b. The dialogue surface of docs/tiers/v2.md section 4,
## chained off V2.4a's meeting arrival: a state visit lands, a scene happens.
##
## This file is a PURE READ and a leaf -- the events.gd precedent, asserted by
## test over the source. It draws one summit as DATA and the orchestrator (the
## window `main.gd` already is for due bookings and foreign acts) fires it: the
## sim never opens a window, never compiles a dialogue, never applies an effect.
## Applying is Legislature.apply_effects(), reached from main.gd, which already
## preloaded it -- the calendar dispatch argument one more time.
##
## THE DRAW IS DETERMINISTIC, on Cycle.unit() over (partner id, meeting stamp)
## -- the same discipline as the event hazard and the business cycle, so a
## replayed or reloaded arrival produces the same scene. There is no summit
## register, no history, no new serialised state at all: a summit is EPHEMERAL,
## it happens once at arrival and what it changed is already in the channels it
## applied through. Nothing that could drift, nothing to prune, SAVE_VERSION
## untouched.

const Cycle = preload("res://src/sim/cycle.gd")


## The summit for this meeting, as data:
## {id, nation_id, nation_name, title, dialogue_text, effects, leader_person_id}
## or {} when the nation has no summit content -- a meeting without a scene is
## the ordinary state visit of V2.4a and before, not an error. The stamp is the
## meeting register's own value, read as the draw's index so a RE-visit can
## draw a different scene from the pool without anything being stored.
static func draw(state, loader, nation_id: String) -> Dictionary:
	var pool: Array = loader.summits.get(nation_id, [])
	if pool.is_empty():
		return {}

	var stamp: int = int(state.met_months.get(_pair_key(state, nation_id), 0))
	var pick: float = Cycle.unit("summit|%s" % nation_id, stamp)
	var summit = pool[int(pick * float(pool.size())) % pool.size()]

	var nation = loader.nations.get(nation_id)
	return {
		"id": String(summit.id),
		"nation_id": nation_id,
		"nation_name": String(nation.nation_name) if nation != null else nation_id,
		"title": String(summit.summit_name),
		"summary": String(summit.summary),
		"leader_person_id": String(nation.leader_person_id) if nation != null else "",
		"dialogue_text": String(summit.dialogue_text),
		"effects": summit.effects,
	}


## The sorted pair key the meeting register uses. Rebuilt here rather than
## preloaded from relations.gd because this file's leaf bar is the calendar
## one -- and a two-element sort is not worth the widest dependency in src/sim/.
static func _pair_key(state, nation_id: String) -> String:
	var a: String = state.player_nation_id
	var b := nation_id
	if a > b:
		var t := a
		a = b
		b = t
	return a + "|" + b
