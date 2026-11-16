extends RefCounted

## Who speaks for a region -- screen 6 (Gameplay's regions brief, 5b, "the figure speaks for
## you"). A pure read for the sheet and the fund's strip: the people whose `region:<id>` want
## names the region, and what their voice is worth if a fund opens there.
##
## The worth is the sim's own arithmetic, not a copy of it: BlocVoice.speak_for writes
## -CK.SPEAK_SHARE x Characters.brief_magnitude() on each of the briefing's blocs (the
## briefing's price is negative, so the voice is positive), and an offset reads on a bloc's
## printed figure at OK.APPROVAL_SPAN points per unit. A figure at the briefing's grudge
## threshold does not speak (BlocVoice's own test), and the sheet says so.

const Characters = preload("res://src/sim/characters.gd")
const CK = preload("res://src/sim/character_act_constants.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const Labels = preload("res://src/ui/labels.gd")


## [{person, points, hostile}], the data's order. Empty when nobody wants the region.
static func of(ns, loader, region_id: String) -> Array:
	var out: Array = []
	var object := "region:" + region_id
	for person in loader.people.get(ns.id, []):
		for want in person.wants:
			if String(want["object"]) != object:
				continue
			var standing := float(ns.person_standing.get(person.id, 0.0))
			out.append({"person": person,
				"points": -CK.SPEAK_SHARE * Characters.brief_magnitude(person, standing) * OK.APPROVAL_SPAN,
				"hostile": float(ns.person_grudges.get(person.id, 0.0)) >= CK.GRUDGE_BRIEF_THRESHOLD})
			break
	return out


## The blocs the voice lands on, as words ("Workers, Students").
static func blocs_text() -> String:
	var words := PackedStringArray()
	for bloc in CK.BRIEF_BLOCS:
		words.append(Labels.bloc(String(bloc)))
	return ", ".join(words)
