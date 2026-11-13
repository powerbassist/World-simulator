extends RefCounted

## What the audience scene tells the dialogue and which extra rows it draws -- V5.3. Pure reads over
## the `view` the wiring hands the scene; nothing here touches the sim or a node.

const AudienceTalkView = preload("res://src/ui/audience_talk_view.gd")
const Strings = preload("res://src/ui/strings.gd")


## What a title of the dialogue is told: her name, the ask, the president, the first name.
static func vars(view: Dictionary) -> Dictionary:
	return {"name": String(view.get("name", "")), "ask": String(view.get("ask", "")),  # i18n: row-ok the person's shown name, resolved by the wiring
		"president": String(view.get("president", "")), "lever": "", "topic": "", "first": String(view.get("name", "")).get_slice(" ", 0)}  # i18n: row-ok a shown name


## The affair's lines, the president's own: a lover has one that ends it; after a Flirt said this
## audience one asks it (once: it reads Asked afterwards, whatever she answered). Not ranked: the
## sim's gates (Shadows.may_begin_affair) decide, and the person's no is hers to say in words.
static func affair_rows(view: Dictionary) -> Array:
	var aff: Dictionary = view.get("affair", {})
	var first := String(view.get("name", "")).get_slice(" ", 0)  # i18n: row-ok a shown name
	if bool(aff.get("lovers", false)):
		return [{"id": "affair_end", "topic": "affair", "tag": "regard", "args": {}, "people": [], "suffix": "", "asked": false, "blocked": "",
			"plain": Strings.t("This has to end, %s.") % first, "sub": false}]
	if bool(aff.get("flirted", false)):
		return [{"id": "affair_ask", "topic": "affair", "tag": "scandal", "args": {}, "people": [], "suffix": "", "sub": true,
			"asked": bool(aff.get("asked", false)), "blocked": String(aff.get("blocked", "")), "plain": Strings.t("Stay after the others have gone.")}]
	return []


## The line the files do not have: the topic's own word, and a gossip's sentence around its faces.
static func plain(line: Dictionary) -> String:
	if not (line.get("people", []) as Array).is_empty():
		return Strings.t("What do you make of") + " " + AudienceTalkView.MARK + "?"
	return String(line.get("plain", line["topic"]))  # i18n: row-ok the wiring's own word for the line
