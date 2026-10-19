extends RefCounted

## The from_dict() halves of NationState's registers: one reader per payload
## shape that a plain deep copy cannot restore. src/core/nation_fields.gd's table
## names the reader each field takes; nothing else calls these.
##
## EVERY READER REBUILDS, NONE ASSIGNS -- commodities-model.md section 6's rule.
## `to_dict()` hands back the LIVE fields, so a reader that returned its payload
## would make `from_dict(state.to_dict())` share a register with `state`, and the
## two would run as one simulation. Every reader returns a container it built.
##
## THE CASTS ARE LOAD-BEARING. Godot's JSON hands numbers back as floats, so an
## int-typed countdown comes back a float and a whole-number float can come back
## shaped differently from the run that saved it; a register that comes back
## different from how it went out is a trap for whoever reads it next. Each reader
## restores the types its register declares, and each whitelists its keys: a
## hand-edited save carrying anything else is dropped on the floor.


## {String: float}, keys re-Stringed. The sector partition, the region and city
## shares, the trade baselines, the org transfers, campaign saturation and the
## upper-house shares: every float-valued register, so that a value that happened
## to land on an integer does not make the arithmetic downstream depend on how it
## was saved (the V2.8 review's re-float).
static func float_map(raw) -> Dictionary:
	var out := {}
	for key in raw:
		out[String(key)] = float(raw[key])
	return out


static func int_map(raw) -> Dictionary:
	var out := {}
	for key in raw:
		out[String(key)] = int(raw[key])
	return out


static func string_map(raw) -> Dictionary:
	var out := {}
	for key in raw:
		out[String(key)] = String(raw[key])
	return out


## `orgs`, re-Stringed and re-sorted, so a save that somehow carried an unsorted
## array reloads into the order every reader iterates.
static func sorted_strings(raw) -> Array:
	var out := []
	for value in raw:
		out.append(String(value))
	out.sort()
	return out


## The event family's Array[Dictionary] registers. A row that is not a
## Dictionary is a corrupted save and is skipped rather than crashed on.
static func rows(raw) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in raw:
		if typeof(row) == TYPE_DICTIONARY:
			out.append((row as Dictionary).duplicate(true))
	return out


## The character registers' halves, typed: a JSON 1.0 comes back as the int 1,
## a typed Dictionary deserves the type it declares, and a stray non-string key
## in an override is a corrupted save refusing loudly rather than a type hole.
static func float_map_typed(raw) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	var src: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	for key in src.keys():
		out[String(key)] = float(src[key])
	return out


static func string_map_typed(raw) -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	var src: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	for key in src.keys():
		out[String(key)] = String(src[key])
	return out


static func bool_map_typed(raw) -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	var src: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	for key in src.keys():
		out[String(key)] = bool(src[key])
	return out


## The pledge register. src/sim/pledges.gd casts on every read and so does not
## care -- but tests/test_save_load.gd compares the two element by element.
static func pledges(raw) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		return []
	var out: Array = []
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		out.append({
			"pledge_id": String(entry.get("pledge_id", "")),
			"field": String(entry.get("field", "")),
			"op": String(entry.get("op", "")),
			"value": float(entry.get("value", 0.0)),
			"from_year": int(entry.get("from_year", 0)),
			"from_month": int(entry.get("from_month", 1)),
			"until_year": int(entry.get("until_year", 0)),
			"until_month": int(entry.get("until_month", 1)),
			"breach_months": int(entry.get("breach_months", 0)),
			"months_live": int(entry.get("months_live", 0)),
		})
	return out


## The programme register, the pledges' shape and reason. The six keys are what
## src/sim/programme.gd writes, which keeps "the register carries no content"
## true across a round trip.
static func programme(raw) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		return []
	var out: Array = []
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		out.append({
			"entry_id": String(entry.get("entry_id", "")),
			"chosen_term": int(entry.get("chosen_term", 0)),
			"months_live": int(entry.get("months_live", 0)),
			"status": String(entry.get("status", "active")),
			"concluded_term": int(entry.get("concluded_term", -1)),
			"concluded_term_month": int(entry.get("concluded_term_month", -1)),
		})
	return out


## The commodity register is a Dictionary OF Dictionaries (six good-id maps plus
## one float), so the aliasing problem is a level deeper than the flat maps'.
## Each inner map is rebuilt with its values cast to float -- a JSON 1.0 in a
## capacity figure comes back as the int 1. What made aliasing fatal HERE rather
## than latent is that commodities.gd mutates entries IN PLACE: measured before
## the V4.6 fix, the round-trip fixture advanced its register three months per
## loop instead of one. ABSENT is not seeded here: seeding is commodities.gd's
## alone (the single-writer pin).
static func commodity_state(raw) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var src: Dictionary = raw
	for key in src.keys():
		var value = src[key]
		if typeof(value) == TYPE_DICTIONARY:
			var inner := {}
			for good_id in (value as Dictionary).keys():
				inner[String(good_id)] = float(value[good_id])
			out[String(key)] = inner
		else:
			out[String(key)] = float(value)
	return out


## V4.2's ledger: channel deltas are floats, months are ints, both copied.
static func law_ledger(raw) -> Dictionary:
	var out := {}
	for law_id in raw:
		var entry: Dictionary = raw[law_id]
		out[String(law_id)] = {
			"channels": Dictionary(entry.get("channels", {})).duplicate(true),
			"months": Array(entry.get("months", [])).duplicate(true),
		}
	return out


## V4.2 T2. months_left is int-cast because the countdown compares and
## decrements it; the rest of a draft is copied whole.
static func draft_bills(raw) -> Dictionary:
	var out := {}
	for draft_id in raw:
		var copy: Dictionary = Dictionary(raw[draft_id]).duplicate(true)
		copy["size"] = float(copy.get("size", 0.0))
		copy["months_left"] = int(copy.get("months_left", 0))
		out[String(draft_id)] = copy
	return out


## V4.2 T4: the four params are three floats and a name, and a payload key that
## is not one of them has no business in a register the revenue lines iterate.
static func custom_taxes(raw) -> Dictionary:
	var out := {}
	for tax_key in raw:
		var params: Dictionary = raw[tax_key]
		out[String(tax_key)] = {
			"name": String(params.get("name", "")),
			"base_share": float(params.get("base_share", 0.0)),
			"erosion": float(params.get("erosion", 0.0)),
			"ref_pct": float(params.get("ref_pct", 0.0)),
		}
	return out


## V4.2 T5: month and cost are the two fields a record of money spent keeps.
static func poll_purchases(raw) -> Dictionary:
	var out := {}
	for poll_bill in raw:
		var kinds: Dictionary = raw[poll_bill]
		var entry: Dictionary = {}
		for kind in kinds:
			var rec: Dictionary = kinds[kind]
			entry[String(kind)] = {
				"month": int(rec.get("month", 0)),
				"cost": float(rec.get("cost", 0.0)),
			}
		out[String(poll_bill)] = entry
	return out


## V4.2 T6: two ids, a countdown, a backer pair and a bonus the division
## re-clamps around; months_left int-cast for draft_bills' reason.
static func assembly_bills(raw) -> Dictionary:
	var out := {}
	for bill_id in raw:
		var bill: Dictionary = raw[bill_id]
		out[String(bill_id)] = {
			"law_id": String(bill.get("law_id", "")),
			"months_left": int(bill.get("months_left", 0)),
			"backer_firm": String(bill.get("backer_firm", "")),
			"backer_chief": String(bill.get("backer_chief", "")),
			"endorse_bonus": float(bill.get("endorse_bonus", 0.0)),
		}
	return out


## The ultra pass-2 shape is {"months": int, "origin": str}; an int payload (the
## pre-fix shape, never shipped -- 38 was unreleased) wraps as a player hold
## rather than crash int() on a Dictionary.
static func held_bills(raw) -> Dictionary:
	var out := {}
	for law_id in raw:
		var held_entry: Variant = raw[law_id]
		if typeof(held_entry) == TYPE_DICTIONARY:
			out[law_id] = {
				"months": int(held_entry.get("months", 0)),
				"origin": String(held_entry.get("origin", "player")),
			}
		else:
			out[law_id] = {"months": int(held_entry), "origin": "player"}
	return out
