extends RefCounted

## The people's lines -- V5.2b. Shared by the audience scene and the phone: one
## loader over data/audiences/*.dialogue (Content's, through DialogueManager, the
## project's stated autoload exception), and the rule for which title opens and
## closes which kind of ask. Moved out of audience_scene.gd at b3, when the phone
## began to speak too.
##
## A stance's file replaces the default title by title (a title twice would not
## compile). A title neither file has gives "": a missing line never stops a scene.

const DIR := "res://data/audiences/"


## The default file with the stance's titles over it, compiled; null without the
## addon or the files.
static func resource_for(stance: String):
	var manager = manager()
	if manager == null:
		return null
	var blocks := titled_blocks(FileAccess.get_file_as_string(DIR + "default.dialogue"))
	var own := DIR + stance + ".dialogue"
	if stance != "" and FileAccess.file_exists(own):
		blocks.merge(titled_blocks(FileAccess.get_file_as_string(own)), true)
	if blocks.is_empty():
		return null
	return manager.create_resource_from_text("\n".join(PackedStringArray(blocks.values())))


## One line of `title` in the speaker's mouth, "" when no file has it. `state`
## carries {{name}}, {{ask}}, {{president}}, {{lever}}, {{topic}}.
static func line(resource, title: String, state: Dictionary) -> String:
	var manager = manager()
	if resource == null or manager == null or not resource.titles.has(title):
		return ""
	var said = await manager.get_next_dialogue_line(resource, title, [state])
	return String(said.text) if said != null else ""


## A .dialogue file cut at its "~ title" lines: title -> its block, title line included.
static func titled_blocks(text: String) -> Dictionary:
	var blocks := {}
	var title := ""
	for row in text.split("\n"):
		if row.begins_with("~ "):
			title = row.substr(2).strip_edges()
			blocks[title] = ""
		if title != "":
			blocks[title] += row + "\n"
	return blocks


## Which opening a request speaks (Content's #126): a visiting head's ask (a
## measure of the played nation's on theirs), an office asked for the month after
## the player's reshuffle, or the ordinary one.
static func opening_title(ns, request: Dictionary) -> String:
	var object := String(request.get("object", ""))
	if object.begins_with("measure:"):
		return "visitor_opening"
	if object.begins_with("office:") and int(request.get("arrived_month", -2)) == int(ns.reshuffle_month) + 1:
		return "reshuffle_opening"
	return "opening"


## The closing title of an audience: a visitor's own parting lines, else the
## ordinary ones. `outcome` is settled, promised or declined.
static func close_title(request: Dictionary, outcome: String) -> String:
	return ("visitor_close_" if String(request.get("object", "")).begins_with("measure:") else "close_") + outcome


static func manager():
	if Engine.has_singleton("DialogueManager"):
		return Engine.get_singleton("DialogueManager")
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("DialogueManager") if tree != null else null
