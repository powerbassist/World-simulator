extends RefCounted

## THE DEV CONSOLE'S ONLY DOOR INTO THE SIMULATION (V5.1-0b). AGENTS.md rule 2:
## the UI never writes GameState, so a cheat is an explicit command that checks
## itself against the field table in src/core/nation_fields.gd and writes here --
## Budget.commit()'s shape, for a dev. src/ui/dev_registry.gd (the console's
## command table) calls these and prints `text`; it holds no write of its own.
##
## Every function returns {ok: bool, text: String}: `text` is the line the console
## prints, and a refusal always says why. A refused command writes nothing.
##
## WHAT `set` MAY TOUCH: a row the table copies by SCALAR and reads back as a
## plain VALUE, which is a number, a flag or a string. A container is refused
## (a one-line value cannot carry one honestly), a display record that is not
## saved is refused (nothing reads it back), and so is `id`, the key every
## register is addressed by. The table is the validator on purpose: a field added
## to it is settable the day it is added, with no second list to forget
## (tests/test_dev_commands.gd sweeps every row).
##
## A cheat sets the figure and nothing else: derived figures settle on the next
## month's tick like any other change, so `set FRA.gdp_eur_bn 10` is a number the
## economy then reacts to, not a fully consistent country.

const NationFields = preload("res://src/core/nation_fields.gd")
const Events = preload("res://src/sim/events.gd")
const EventsK = preload("res://src/sim/events_constants.gd")
const Programme = preload("res://src/sim/programme.gd")

## Longest value `get` prints on one line; a register can be pages of JSON.
const GET_MAX_CHARS := 600

const PLAYER_ALIASES := ["me", "player"]


## "me" is the nation being played; anything else is a nation id.
static func resolve_nation(state, ref: String) -> String:
	if PLAYER_ALIASES.has(ref.to_lower()):
		return String(state.player_nation_id)
	return ref.to_upper()


static func get_field(state, nation_ref: String, field: String) -> Dictionary:
	var ns = _nation(state, nation_ref)
	if ns == null:
		return _no("no nation '%s'" % nation_ref)
	if _row(field).is_empty():
		return _no("no field '%s' on a nation (the table is src/core/nation_fields.gd)" % field)
	var value = ns.get(field)
	var text: String = str(value) if typeof(value) != TYPE_DICTIONARY and typeof(value) != TYPE_ARRAY \
			else JSON.stringify(value)
	if text.length() > GET_MAX_CHARS:
		text = text.substr(0, GET_MAX_CHARS) + "... (%d chars)" % text.length()
	return _yes("%s.%s = %s" % [ns.id, field, text])


static func set_field(state, nation_ref: String, field: String, raw: String) -> Dictionary:
	var ns = _nation(state, nation_ref)
	if ns == null:
		return _no("no nation '%s'" % nation_ref)
	var row := _row(field)
	if row.is_empty():
		return _no("no field '%s' on a nation (the table is src/core/nation_fields.gd)" % field)
	if field == "id":
		return _no("'id' is the key the registers are addressed by; it cannot be set")
	if row[NationFields.COL_COPY] != NationFields.SCALAR or row[NationFields.COL_READ] != NationFields.VALUE:
		return _no("'%s' is not a plain number, flag or string, so it cannot be set from one line" % field)
	var parsed := _parse(typeof(row[NationFields.COL_DEFAULT]), raw)
	if not bool(parsed["ok"]):
		return _no("'%s' is not %s for %s.%s" % [raw, parsed["wanted"], ns.id, field])
	var before = ns.get(field)
	ns.set(field, parsed["value"])
	return _yes("%s.%s: %s -> %s (derived figures settle on the next month)" % [
		ns.id, field, str(before), str(ns.get(field))])


## Puts an event on the player's desk through the events system's own staging
## primitive (Events.announce) -- the one the test sweeps and the screenshot
## harness already drive -- after the checks the delivery door would make:
## a known id, not already on the desk, a desk with room.
static func stage_event(state, loader, event_id: String) -> Dictionary:
	var ns = state.player()
	if ns == null:
		return _no("there is no player nation")
	var ev = Events.event_by_id(loader, event_id)
	if ev == null:
		return _no("no event '%s'" % event_id)
	if on_desk(ns, event_id):
		return _no("'%s' is already on the desk" % event_id)
	if ns.event_queue.size() >= EventsK.QUEUE_MAX:
		return _no("the desk is full (%d); answer one first" % EventsK.QUEUE_MAX)
	# The tick's own month index (events.gd _absolute_month): it only picks a sited
	# event's place, and the same pick must come out whichever door staged it.
	Events.announce(ns, ev, int(state.year) * 12 + int(state.month), Events.region_names(ns, loader))
	return _yes("staged '%s' (%s) on the desk" % [event_id, ev.event_name])


## The ids on the player's desk, as a set: what the UI diffs an arrival against.
static func desk_ids(state) -> Dictionary:
	var out := {}
	var ns = state.player()
	if ns != null:
		for entry in ns.event_queue:
			out[String(entry.get("event_id", ""))] = true
	return out


static func on_desk(ns, event_id: String) -> bool:
	for entry in ns.event_queue:
		if String(entry.get("event_id", "")) == event_id:
			return true
	return false


static func person_report(state, loader, person_id: String) -> Dictionary:
	var person = loader.person_by_id.get(person_id, null)
	if person == null:
		return _no("no person '%s'" % person_id)
	var ns = state.player()
	var lines: Array[String] = [
		"%s -- %s (%s)" % [person.id, person.person_name, person.kind],
		"party %s, ambition %.2f, traits %s" % [person.party_id, person.ambition, person.traits],
	]
	if ns != null:
		lines.append("loyalty %s, standing %s (the player's register)" % [
			ns.person_loyalty.get(person.id, "-"), ns.person_standing.get(person.id, "-")])
	return _yes("\n".join(lines))


## Whether the player's term has just begun -- the gate the programme offer runs
## through, read where the console needs it instead of restated.
static func at_term_start(state) -> bool:
	var ns = state.player()
	return ns != null and Programme.is_term_start(ns)


## Why no term start can be reached, or "" when one still can: a lost election
## ends the run, and a nation without a term has none to wait for.
static func term_start_blocker(state) -> String:
	var ns = state.player()
	if ns == null:
		return "there is no player nation"
	if not ns.in_government:
		return "the player is out of government; there is no next term"
	if int(ns.term_months) <= 0:
		return "%s has no fixed term" % ns.id
	return ""


static func _nation(state, ref: String):
	return state.nations.get(resolve_nation(state, ref), null)


## The table row for a field name, or [] -- one scan, no second index to drift.
static func _row(field: String) -> Array:
	for row in NationFields.FIELDS:
		if row[NationFields.COL_NAME] == field:
			return row
	return []


static func _parse(kind: int, raw: String) -> Dictionary:
	var text := raw.strip_edges()
	match kind:
		TYPE_INT:
			if text.is_valid_int():
				return {"ok": true, "value": text.to_int()}
			return {"ok": false, "wanted": "a whole number"}
		TYPE_FLOAT:
			if text.is_valid_float():
				return {"ok": true, "value": text.to_float()}
			return {"ok": false, "wanted": "a number"}
		TYPE_BOOL:
			var word := text.to_lower()
			if ["true", "on", "yes", "1"].has(word):
				return {"ok": true, "value": true}
			if ["false", "off", "no", "0"].has(word):
				return {"ok": true, "value": false}
			return {"ok": false, "wanted": "true or false"}
	return {"ok": true, "value": text}


static func _yes(text: String) -> Dictionary:
	return {"ok": true, "text": text}


static func _no(text: String) -> Dictionary:
	return {"ok": false, "text": text}
