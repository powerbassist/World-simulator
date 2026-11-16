extends RefCounted

## The chief's mark and caption, filled from the month the briefing driver keeps -- G1,
## chief-briefing-brief.md 2. Beside briefing_driver.gd, which is at its size ceiling.
##
## **No stale line** (the brief's new row): the plate was read on day 1, the mark lives
## all month, so the mark and the read rank again when a file is answered and when the
## read opens -- from the memory the month was ranked FROM, so a line keeps the novelty
## it had (the chief's line, its turn and the music band stay the month's).

const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const PriorityWords = preload("res://src/ui/priority_words.gd")
const Staff = preload("res://src/sim/staff.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Priorities = preload("res://src/ui/priorities.gd")
const Strings = preload("res://src/ui/strings.gd")
## main's meta while a re-rank waits for the frame's end (follow()).
const RERANK_QUEUED := "chief_rerank_queued"


## The mark from the month's first line; `rerank` ranks the month again first.
static func refresh(main, rerank := false) -> void:
	var game: Dictionary = BriefingDriver._games.get(main.get_instance_id(), {})
	var state = main._state
	if game.is_empty() or state == null or state.player() == null or not bool(state.player().in_government) \
			or not game.has("memory_before"):
		clear(main)
		return
	if rerank:
		rerank(main)
	var lines: Array = game.get("lines", [])
	var chief = Staff.chief_of(main._loader, String(state.player().id))
	var face: Texture2D = Portrait.texture_for(String(chief.id)) if chief != null else null
	var who := Strings.t("%s, chief of staff") % main._loader.person_name(String(chief.id)) if chief != null else ""
	# What a click does, said on the mark itself (the ux-copy pass: the face alone did not).
	var tip := Strings.t("Click to open the month's briefing.")
	if who != "":
		tip = "\n".join(PackedStringArray([who, tip]))
	_push_read(main, lines, who, face, chief)
	if lines.is_empty():
		main._hud.title_bar.chief_mark.show_line(face, Strings.t("A quiet month"), "", false, tip)
		return
	var first: Dictionary = lines[0]
	var now := int(state.year) * 12 + int(state.month)
	var due_now := not bool(first["standing"]) and int(first["deadline_month"]) >= 0 and int(first["deadline_month"]) <= now
	main._hud.title_bar.chief_mark.show_line(face, PriorityWords.title(first, state, main._loader),
		PriorityWords.chip(first, state), due_now, tip)


## The month ranked again from the memory it was first ranked from: the lines and the
## footer change, nothing the chief said does.
static func rerank(main) -> void:
	var game: Dictionary = BriefingDriver._games.get(main.get_instance_id(), {})
	if game.is_empty() or not game.has("memory_before") or main._state == null or main._state.player() == null:
		return
	var ranked: Dictionary = rank(main, game["memory_before"])
	game["lines"] = ranked["lines"]
	game["also"] = ranked.get("also_due", [])


## The month ranked from `memory`, with each line's "fresh" (a real priority last month's
## lines did not name; a standing read is never new) and the ranking's "new".
static func rank(main, memory: Dictionary) -> Dictionary:
	var state = main._state
	var last: Array = memory.get("last", [])
	var ranked := Priorities.rank(state, main._loader, {"memory": memory,
		"held_events": BriefingDriver._held_events(main), "programme_held": main._paused_for_programme
			or not preload("res://src/sim/programme.gd").available(state, state.player(), main._loader).is_empty()})
	for l in ranked["lines"]:
		l["fresh"] = not bool(l["standing"]) and not last.any(func(p): return p["kind"] == l["kind"] and p["subject"] == l["subject"])
	ranked["new"] = ranked["lines"].any(func(l): return bool(l["fresh"]))
	return ranked


## His line for the month's situation as the caption under the mark, said aloud once a
## month (`key`). The voice is gated on the mark, which stays up for the month: a line
## queued behind a longer messenger's clip outlives the caption's reading timer, so the
## caption comes back when the line starts (heard, so on screen: chief_caption.gd).
static func speak(main, key: String) -> void:
	var game: Dictionary = BriefingDriver._games.get(main.get_instance_id(), {})
	var chief = Staff.chief_of(main._loader, String(main._state.player().id))
	if game.is_empty() or chief == null:
		return
	var situation := Priorities.situation(game["lines"])
	var said := BriefingDriver.chief_said(main._loader, String(chief.id), situation, BriefingDriver._turn(main, situation))
	var caption = main._hud.chief_caption
	caption.say(String(said["text"]), main._hud.title_bar.chief_mark)
	# Gated on the mark, not the caption: the caption hides on its reading timer, and a line queued behind a longer
	# messenger's clip was dropped with it (the retro review's item 13).
	if caption.visible:
		BriefingDriver.speak_once(main, said, main._hud.title_bar.chief_mark, key, _say_again.bind(main, String(said["text"])))


## The queued line starts: its caption back under the mark (a bound static, no lambda: the queue outlives frames).
static func _say_again(main, text: String) -> void:
	if is_instance_valid(main) and main.is_inside_tree():
		main._hud.chief_caption.say(text, main._hud.title_bar.chief_mark)


## What re-ranks the mark, or it names a file that is gone (the retro review's item 14, #393 pass 2 T1): every player
## command -- a dispatch, an audience's Grant or End, a law tabled, the programme, the phone -- ends in the window
## manager's one sweep (its `dirtied`), and an inbox card closed or dismissed changes what holds the clock without one.
## Coalesced: a command that sweeps twice, or closes a card as it sweeps, ranks once, at the frame's end.
static func follow(main) -> void:
	main._windows.dirtied.connect(queue_rerank.bind(main))
	main._hud.inbox.card_closed.connect(queue_rerank.bind(main).unbind(1))
	main._hud.inbox.card_dismissed.connect(queue_rerank.bind(main).unbind(1))


static func queue_rerank(main) -> void:
	if not main.has_meta(RERANK_QUEUED):
		main.set_meta(RERANK_QUEUED, true)
		_rerank_queued.bind(main).call_deferred()


## Not under an open read: its Go buttons index the lines it shows (it ranks again when it opens, and its close
## queues one, BriefingDriver.close).
static func _rerank_queued(main) -> void:
	if not is_instance_valid(main):
		return
	main.remove_meta(RERANK_QUEUED)
	var card = BriefingDriver.card_of(main)
	refresh(main, card == null or not card.visible)


## A load: the ranking's memory and report go with the discarded game (left, the first card closed after the load
## re-ranked from them and put that game's mark back up: the retro review's item 5). The loaded game is ranked now
## from no memory, so its mark is up at once, not blank until its first month end (#393 pass 2, T2).
static func after_load(main, game: Dictionary) -> void:
	game.erase("report")
	game.erase("month_cards")  # held for the discarded game's month end (a load from the pause menu)
	game["pending"] = {}
	game["memory_before"] = {}
	main._hud.chief_caption.clear()
	refresh(main, true)


static func clear(main) -> void:
	main._hud.title_bar.chief_mark.clear()
	main._hud.chief_caption.clear()
	if main._overview_panel != null:
		main._overview_panel.set_read({})


## The Presidency page's lead is this read (rework 2, "one ranking"): the same lines the mark
## names, the chief's face and name, and his line only when the month names something new.
static func _push_read(main, lines: Array, who: String, face: Texture2D, chief) -> void:
	if main._overview_panel == null:
		return
	var said := ""
	if chief != null and lines.any(func(l): return bool(l.get("fresh", false))):
		var situation := Priorities.situation(lines)
		said = String(BriefingDriver.chief_said(main._loader, String(chief.id), situation, BriefingDriver._turn(main, situation))["text"])
	main._overview_panel.set_read({"lines": lines, "who": who, "face": face, "said": said})


## The page's Go on its lead row `index` (rework 2, slice 1). A line about a desk file selects
## that file in the month's folder, which only shows on the invited read, so the read opens
## first, as it stands (no re-rank: the row's index is the stored line's); until G2 retires
## the plate, that is where a file is answered. Any other line goes where the briefing's Go does.
static func page_go(main, index: int) -> void:
	var game: Dictionary = BriefingDriver._games.get(main.get_instance_id(), {})
	var all: Array = (game.get("lines", []) as Array) + (game.get("also", []) as Array)
	if index >= 0 and index < all.size():
		var file := String(preload("res://src/ui/folder_driver.gd").file_of(main, all[index]))
		# Only a file still on the desk: a stale one would open the read and close it again.
		if file != "" and not preload("res://src/ui/inbox_files.gd").of(main._hud.inbox, file).is_empty():
			BriefingDriver.read(main, false)
	BriefingDriver.go(main, index)
