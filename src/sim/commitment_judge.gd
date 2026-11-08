extends RefCounted

## What a commitment comes to at its date: one verdict, its price written, with no roll but
## a delegated word's. Moved out of levers.gd at step 6's deal, which added two families and
## met that file's ceiling; Levers.tick_month calls it, so no caller moved. The table is
## docs/audiences-model.md section 7, the deal docs/audiences-model.md section 14.
##
## THE DEAL IS TWO ROWS (docs/design/v5.3-ab.md section 5, no third register). A row carrying
## `deal` names the request that struck it, and each half lets the other go: a person who broke
## a pledge has released the president's word, unpriced (DivisionTerms, at the vote), and the
## president's word broken releases whatever that person still owes (here).

const K = preload("res://src/sim/lever_constants.gd")
const PK = preload("res://src/sim/president_constants.gd")
const President = preload("res://src/sim/president.gd")
const Characters = preload("res://src/sim/characters.gd")
const Coercion = preload("res://src/sim/coercion.gd")
const Lies = preload("res://src/sim/lies.gd")
const Delegation = preload("res://src/sim/delegation.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const Closures = preload("res://src/sim/closures.gd")


## "kept", "broken" or "void", the price written. `row` is a commitment as President casts it.
static func verdict(state, ns, loader, row: Dictionary, meters: Dictionary, leaders: Dictionary) -> String:
	# What a person owes reaches its date unjudged: a pledge whose bill never came, silence
	# that ran its months. Nobody broke anything. A pledge the vote reached is off the register.
	if PK.OWED_KINDS.has(String(row["kind"])):
		return "void"
	var person = loader.person_by_id.get(String(row["person_id"]))
	var object := String(row["object"])
	var want := {}
	if person != null:
		for w in person.wants:
			if String(w["object"]) == object:
				want = w
	# b3: a visitor's ask names a measure the played nation holds, not a want in
	# content; it is served once the measure is lifted -- France's own, so an org's
	# levy written on the emptied pair later does not undo the kept word.
	if person != null and object.begins_with("measure:"):
		want = {"measure": object.substr("measure:".length())}
	# Step 6: no person wants a plant in content, so a minister's word on one is read off the plant.
	if person != null and object.begins_with(AK.FIRM_PREFIX):
		want = {"firm": object.substr(AK.FIRM_PREFIX.length())}
	# Step 6: a word to bring a bill. DivisionTerms marks it when the bill reaches the floor.
	if person != null and object.begins_with("law:"):
		want = {"law": object.substr("law:".length())}
	if want.is_empty():
		return "void"
	var pid := String(person.id)
	var kind := String(row["kind"])
	var served: bool
	if want.has("law"):
		served = bool(row.get("brought", false))
	elif want.has("firm"):
		var closure: Dictionary = (ns.companies.get(want["firm"], {}) as Dictionary).get("closure", {})
		served = [Closures.RESCUING, "sold"].has(String(closure.get("status", "")))
	elif want.has("measure"):
		served = Coercion.own_measure(state, want["measure"]) == null
	else:
		served = Characters.want_served(ns, person, want, meters, leaders)
	# V5.2c: a promise told as a lie is revealed at its date, served or not (B8).
	# V5.3-0 gate: a delegated word the world has not served is the minister's to
	# keep, on the odds it was given (delegation.gd says why the world alone broke 19 in 20).
	if (served or Delegation.keeps(ns, loader, row, String(want.get("stance", "")))) and not bool(row.get("lie", false)):
		if kind != "iou":
			President.adjust_rapport(state, ns, loader, pid, K.PROMISE_KEPT_RAPPORT if kind == "promise" else Delegation.kept_rapport(served))
		return "kept"
	_release(ns, String(row.get("deal", "")))
	if kind == "promise":
		Lies.reveal(state, ns, loader, person)
		return "broken"
	if kind == "delegated":
		Delegation.price_broken(ns, person)
	President.adjust_rapport(state, ns, loader, pid, -K.IOU_BETRAYAL_RAPPORT)
	Characters.price_refusal(ns, person, K.IOU_BETRAYAL_GRUDGE, 0.0)
	Lies.cross(state, ns, loader, person, int(row.get("made_month", 0)))  # c1c rule 1: a broken word to an accomplice
	return "broken"


## The president's word is gone, so what the person owed under it is gone too.
static func _release(ns, deal: String) -> void:
	if deal == "":
		return
	for row in President.owed(ns):
		if String(row.get("deal", "")) == deal:
			President.withdraw_commitment(ns, String(row["kind"]), String(row["person_id"]), String(row["object"]))
