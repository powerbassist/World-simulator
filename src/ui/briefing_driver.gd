extends RefCounted

## The monthly briefing's wiring -- V5.3-0, docs/design/v5.3-0-readability.md 2.2.
## Static over main, as phone_driver.gd is: the card (chief_briefing.gd) to the
## ranking (priorities.gd), the hold, the hold order and the Go table.
##
## **The hold order** (2.2's table): an election result owns the pause first, and
## the briefing opens on its dismissal (or not at all after a defeat); the
## term-start offer, an interrupt and a holding card keep their own holds, and the
## briefing never releases them -- its closing button reads "Next: ..." and opens
## the surface that still holds, so dismissing it never leaves the player before a
## clock that does not move (GLM's finding 5). The front page waits for this card
## as it waits for the count's plate (plate_for).
##
## **The author's call 2** ("Réglage « si nouveau »"): with Messages' "Only when
## something is new", a month whose three are all last month's three does not stop.
##
## A Go closes the card by the same rule as Continue, then opens its target (OPINION:
## a Go that left the clock paused would strand a pause the clock line cannot name).

const ResultTone = preload("res://src/ui/result_tone.gd")
const ChiefBriefing = preload("res://src/ui/chief_briefing.gd")
const ScreenStack = preload("res://src/ui/screen_stack.gd")
const Priorities = preload("res://src/ui/priorities.gd")
const Music = preload("res://src/ui/music.gd")
const Trends = preload("res://src/ui/trends.gd")
const PriorityWords = preload("res://src/ui/priority_words.gd")
const BriefingEffects = preload("res://src/ui/briefing_effects.gd")
const MessageSettings = preload("res://src/ui/message_settings.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Strings = preload("res://src/ui/strings.gd")
const Events = preload("res://src/sim/events.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const Voices = preload("res://src/core/voices.gd")
const Voice = preload("res://src/ui/voice.gd")
const Staff = preload("res://src/sim/staff.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")

## The chief has three lines a situation (#226: 4 chiefs x 3 situations x 3).
const CHIEF_VARIANTS := 3
## The card id the chief's spoken line carries (Voice.hush).
const LINE_CARD := "chief_briefing"  # i18n: ok a card id
## The card's meta naming the month whose line it has said (speak_once).
const SPOKEN := "spoken"  # i18n: ok a meta key
## How often a chief waiting behind a desk speaker looks again, in seconds: short
## enough that the line follows the messenger's at once, long enough to cost nothing.
const QUEUE_POLL_S := 0.25

static var _games := {}
## A test seam: a test of another surface drives whole months and would otherwise
## meet the briefing's dimmed card over what it clicks. The briefing's own tests
## leave it false.
static var suppressed := false


static func register(main) -> void:
	var card := ChiefBriefing.new()
	main._stack.add(ScreenStack.SCENE, card, true, func() -> void: close(main))
	card.hide()
	var game := {"card": card, "lines": [], "memory": {}, "state_id": 0, "pending": {}, "was_running": false}
	_games[main.get_instance_id()] = game
	card.go_pressed.connect(func(i: int) -> void: go(main, i))
	card.closed.connect(func() -> void: close(main))
	# The two verbs block 0 added where a Go lands (2.4); the panels only ask.
	main._agenda_panel.open_requested.connect(func(tab: String) -> void: main._windows.open(tab))
	main._polling_panel.calm_requested.connect(func(tab: String, bloc: String) -> void: _open_laws_or(main, tab, bloc))


static func card_of(main) -> ChiefBriefing:
	return _games.get(main.get_instance_id(), {}).get("card")


static func showing(main) -> bool:
	var card := card_of(main)
	return card != null and card.visible


## The Elections step's front page waits for what owns the screen after the count:
## the briefing when it will open this month, else the count's plate, else nothing.
static func plate_for(main, report: Dictionary) -> Control:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	var results: Array = report.get("election_results", [])
	if not game.is_empty() and _will_show(main, game, report):
		return game["card"]
	return null if results.is_empty() else main._election_panel


## _finish_month's tail on a month with no result on screen: the term start first
## (its hold and card are the briefing's priority 1), then the briefing.
static func finish_month(main, report: Dictionary) -> void:
	main._enforce_term_start_programme()
	open(main, report)


## The count's plate dismissed after a win: the same tail, on the month it closed.
static func after_election(main) -> void:
	main._enforce_term_start_programme()
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	open(main, game.get("report", {}))


static func open(main, report: Dictionary) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	var ns = main._state.player() if main._state != null else null
	var cards: Array = game.get("month_cards", [])
	game.erase("month_cards")
	if game.is_empty() or ns == null or not bool(ns.in_government) or not _will_show(main, game, report):
		# A month the briefing does not show keeps its consequence cards in the inbox.
		for card in cards:
			ResultTone.mark(main._hud.inbox, main._hud.inbox.push(card["title"], card["body"]), String(card.get("tone", "")))
		return
	var ranked: Dictionary = game["pending"]
	game["pending"] = {}
	game["memory"] = ranked["memory"]
	game["lines"] = ranked["lines"]
	game["also"] = ranked.get("also_due", [])
	game["was_running"] = game["was_running"] or not main._clock.paused
	main._clock.paused = true
	var shown := view(main, ranked["lines"], report, game["also"])
	game["card"].show_view(shown)
	speak_once(main, shown, game["card"], "%d:%d" % [main._state.get_instance_id(), int(main._state.year) * 12 + int(main._state.month)])
	main._hud.clock_cluster.refresh(main._clock, preload("res://src/ui/hold_reason.gd").show(main))


## A month's consequence card (effects_ledger.gd, a desk card decided for you),
## held for open(): the briefing says what the month decided on a month it shows
## (spec 3.3), so the card goes to the inbox only on a month it does not.
static func hold_card(main, card: Dictionary) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	if card.is_empty():
		return
	if game.is_empty():
		ResultTone.mark(main._hud.inbox, main._hud.inbox.push(card["title"], card["body"]), String(card.get("tone", "")))
		return
	game["month_cards"] = game.get("month_cards", []) + [card]


## Ranks this month once (cached until the card opens) and says whether it opens.
static func _will_show(main, game: Dictionary, report: Dictionary) -> bool:
	var state = main._state
	if suppressed or state == null or state.player() == null or not bool(state.player().in_government):
		return false
	# A load or a new game is a new state: novelty starts over (2.3).
	if int(game["state_id"]) != state.get_instance_id():
		game["state_id"] = state.get_instance_id()
		game["memory"] = {}
		game["pending"] = {}
	var now := int(state.year) * 12 + int(state.month)
	if game["pending"].is_empty() or int(game["pending"].get("month", -1)) != now:
		var last: Array = game["memory"].get("last", [])
		game["pending"] = Priorities.rank(state, main._loader, {"memory": game["memory"],
			"held_events": _held_events(main), "programme_held": main._paused_for_programme
				or not preload("res://src/sim/programme.gd").available(state, state.player(), main._loader).is_empty()})
		game["pending"]["month"] = now
		# V5.3-0 (d): the month's band, from this ranking whether or not the card shows.
		Music.follow(main, Priorities.situation(game["pending"]["lines"]), Trends.months_to_vote(state, state.player()),
			state.get_instance_id())
		# New: a real priority last month's three did not name. A standing read is
		# never new -- a quiet month does not stop under the setting (call 2).
		for l in game["pending"]["lines"]:
			l["fresh"] = not bool(l["standing"]) and not last.any(func(p): return p["kind"] == l["kind"] and p["subject"] == l["subject"])
		game["pending"]["new"] = game["pending"]["lines"].any(func(l): return bool(l["fresh"]))
	game["report"] = report
	if MessageSettings.briefing_new_only(SettingsPanel.CONFIG_PATH) and not bool(game["pending"]["new"]):
		# Skipped, but the month is remembered: next month compares with this one.
		game["memory"] = game["pending"]["memory"]
		return false
	return true


## The event ids that hold the clock now: main's unseen arrivals and an interrupt.
static func _held_events(main) -> Array:
	var out: Array = []
	for event_id in main._unseen_events:
		if bool(main._unseen_events[event_id]):
			out.append(String(event_id))
	for entry in main._state.player().event_queue:
		if bool(entry.get("interrupt", false)) and not out.has(String(entry.get("event_id", ""))):
			out.append(String(entry.get("event_id", "")))
	return out


static func view(main, lines: Array, report: Dictionary, also: Array = []) -> Dictionary:
	var state = main._state
	var rows: Array = []
	for l in lines:
		rows.append({"icon": PriorityWords.icon_path(String(l["kind"])), "title": PriorityWords.title(l, state, main._loader),
			"chip": PriorityWords.chip(l, state), "held": bool(l["held"]), "new": bool(l.get("fresh", false))})
	var header := Strings.t("A quiet month") if Priorities.quiet(lines) \
		else Strings.t("%s: your priorities") % DateText.month_year(int(state.month), int(state.year))
	var chief = Staff.chief_of(main._loader, String(state.player().id))
	var who := ""
	var said := {"text": "", "clip": ""}
	if chief != null:
		who = Strings.t("%s, chief of staff") % main._loader.person_name(String(chief.id))
		said = chief_said(main._loader, String(chief.id), Priorities.situation(lines), int(state.year) * 12 + int(state.month))
	# The footer, folded by kind; each group's Go is its first item's (index past the
	# three lines into lines + also).
	var groups: Array = []
	var by_kind := {}
	for i in also.size():
		var kind := String(also[i]["kind"])
		if not by_kind.has(kind):
			by_kind[kind] = {"items": [], "index": lines.size() + i}
			groups.append(by_kind[kind])
		by_kind[kind]["items"].append(also[i])
	var footer: Array = groups.map(func(g): return {"text": PriorityWords.group(g["items"], state, main._loader), "index": g["index"]})
	return {"header": header, "who": who, "also": footer, "line": said["text"], "clip": said["clip"], "face": Portrait.texture_for(String(chief.id)) if chief != null else null,
		"feel": Feelings.of(state.player(), String(chief.id)) if chief != null else {},
		"rows": rows, "effects": BriefingEffects.lines(state, main._loader, report), "close": _close_text(main)}


## The chief's line for the month's situation (2.6) as {text, clip}: three variants
## per situation in the voice archetype's own lines, rotated by the month so no line
## plays two months running. The clip (#226's batch) is Voice's only when its hash is
## the line's own, hashed BEFORE the quotes go round it -- the pipeline voiced the
## bare line, so the quoted text would never match.
static func chief_said(loader, person_id: String, situation: String, month_index: int) -> Dictionary:
	var arch := Voices.archetype_of(loader, person_id)
	var key := "%s_%d" % [situation, posmod(month_index, CHIEF_VARIANTS) + 1]
	var english := String((loader.voice_archetypes.get(arch, {}).get("lines", {}) as Dictionary).get(key, ""))
	if english == "":
		return {"text": "", "clip": ""}
	var shown := Strings.row("voices", arch, "lines.%s" % key, english)
	return {"text": Strings.t("“%s”") % shown, "clip": Voice.line_clip(arch, key, shown)}


## Every line id chief_said() can ask for: Priorities.situation()'s answers times the
## variants (tests/test_voice_lines.gd's orphan check reads this).
static func chief_line_ids() -> Array:
	var out: Array = []
	for situation in Priorities.SITUATIONS:
		for i in CHIEF_VARIANTS:
			out.append("%s_%d" % [situation, i + 1])
	return out


## The card's line said aloud once a card: `key` names the month (and the game), so
## a card opened again on the same month does not say it twice (the parent's TAKE 3).
static func speak_once(main: Node, shown: Dictionary, card: CanvasItem, key: String) -> void:
	if String(card.get_meta(SPOKEN, "")) == key:
		return
	card.set_meta(SPOKEN, key)
	speak(main, shown, card)


## Under `main`, where the desk's arriving speakers talk too. A messenger's line
## under way, or waiting behind its sting, is never cut and never talked over: the
## chief waits for it and speaks when it ends, if `card` is still up for the same
## month. Closing the card cancels the wait; nothing replays later (the parent's
## TAKE 1 on #229 -- an arrival month is a tense or crisis one, so dropping the line
## silenced the chief exactly when it mattered).
static func speak(main: Node, shown: Dictionary, card: CanvasItem) -> void:
	var clip := String(shown.get("clip", ""))
	if clip == "" or main == null or not main.is_inside_tree():
		return
	var player := main.get_node_or_null(Voice.NODE) as AudioStreamPlayer
	if player != null and (player.playing or bool(player.get_meta("pending", false))):
		# A Timer the card owns, calling a method: when the card (or main above it)
		# goes, the wait goes with it -- a SceneTree timer's lambda would be called
		# with its captures freed and log an ERROR (#229 QA TAKE 1, #222's class).
		var wait := Timer.new()
		wait.one_shot = true
		wait.wait_time = QUEUE_POLL_S
		wait.timeout.connect(_waited.bind(main, shown, card, wait, card.get_meta(SPOKEN, null)))
		card.add_child(wait)
		wait.start()
		return
	Voice.speak(main, clip, 0.0, LINE_CARD)


static func _waited(main: Node, shown: Dictionary, card: CanvasItem, wait: Timer, key) -> void:
	wait.queue_free()
	if is_instance_valid(main) and card.visible and card.get_meta(SPOKEN, null) == key:
		speak(main, shown, card)


## "Continue", or "Next: ..." naming the surface that still holds the clock.
static func _close_text(main) -> String:
	var held := _holding_event(main)
	if not held.is_empty():
		var ev = Events.event_by_id(main._loader, held)
		return Strings.t("Next: %s") % (Strings.row_name("events", ev) if ev != null else held)
	if main._paused_for_programme:
		return Strings.t("Next: the term's programme")
	return Strings.t("Continue")


static func _holding_event(main) -> String:
	var ns = main._state.player()
	if Events.interrupt_pending(ns):
		var ev = Events.pending_event(ns, main._loader)
		if ev != null:
			return String(ev.id)
	if main._decision_holds_clock():
		var held := _held_events(main)
		return held[0] if not held.is_empty() else ""
	return ""


static func close(main) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	if game.is_empty() or not game["card"].visible:
		return
	game["card"].hide()
	Voice.hush(main, LINE_CARD)  # the chief's line belongs to the card
	game["card"].dismissed.emit()
	# A request the card named, on a line, in the footer or folded into a line's
	# "+N more", has been SEEN under #207's rule (the parent's calls on QA's #218
	# finding and RECORD): its arrival's slowdown gives the player's speed back,
	# unless they picked one since (_seen's own rule).
	for entry in (game["lines"] as Array) + (game.get("also", []) as Array):
		for named in [entry] + (entry.get("folded", []) as Array):
			if String(named.get("kind", "")) == "request":
				AudienceDriver._seen(main, String(named["subject"]))
	var held := _holding_event(main)
	if bool(game["was_running"]) and held.is_empty() and not main._paused_for_programme:
		main._clock.paused = false
	game["was_running"] = false
	# The surface that still holds is the next thing on screen.
	if not held.is_empty():
		_raise_event(main, held)
	elif main._paused_for_programme:
		main._windows.open("agenda")
	main._hud.clock_cluster.refresh(main._clock, preload("res://src/ui/hold_reason.gd").show(main))


## After a load (QA's RECORD on #218, PhoneDriver.after_load's rule): the card of
## the discarded game comes down, and the clock it paused and the lines it named
## belong to that game, so they go too (novelty starts over by _will_show's
## state_id). No `dismissed`: nothing of the discarded game waits on it now.
static func after_load(main) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	if game.is_empty():
		return
	game["card"].hide()
	Voice.hush(main, LINE_CARD)
	game["was_running"] = false
	game["lines"] = []
	game["also"] = []


## Go: close by Continue's rule, then open the line's target (2.4's table).
static func go(main, index: int) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	var all: Array = (game.get("lines", []) as Array) + (game.get("also", []) as Array)
	if game.is_empty() or index < 0 or index >= all.size():
		return
	var line: Dictionary = all[index]
	var target := target_of(line)
	close(main)
	var tab := String(target["tab"])
	var subject := String(line["subject"])
	match String(line["kind"]):
		"crisis", "decision":
			_raise_event(main, subject)
		"request":
			# The verbs are the request card's (Book a day / Delegate / Decline); the
			# Diary beside it shows the days. Booking inside the grid is (b)'s (3.4).
			main._windows.open(tab)
			main._hud.inbox.slide_in()
			main._hud.inbox.raise_card(AudienceDriver.lane_of(main).card_of(subject))
		"bloc":
			_open_laws_or(main, tab, subject)
		"bill":
			_open_laws_or(main, tab, "")  # every law, so the tabled line shows
		"person":
			main._windows.open(tab)
			main._people_panel.focus(subject)
		_:
			main._windows.open(tab)


## Where a line's Go lands: the tab, and the id an enabled control there is tagged
## with (acts_on.gd) -- the line's subject, except a commitment, whose verb is the
## promised thing's own: a programme entry on the Agenda, an office on Politics, a
## figure on the Budget. A tabled bill is RF3's one named exception (the parent's
## call): it lands on the Legislature's tabled line, which has no verb until the
## Assembly divides.
static func target_of(line: Dictionary) -> Dictionary:
	var kind := String(line["kind"])
	var subject := String(line["subject"])
	if kind != "commitment":
		return {"tab": String(line["go"]["tab"]), "acts_on": subject}
	var object := subject.get_slice("|", 2)
	if object.begins_with("programme:"):
		return {"tab": "agenda", "acts_on": object.trim_prefix("programme:")}
	if object.begins_with("office:"):
		return {"tab": "politics", "acts_on": "seats"}
	if object.begins_with("meter:"):
		return {"tab": "budget", "acts_on": "balance"}
	return {"tab": "calendar", "acts_on": subject}


## The Legislature filtered to the laws `bloc` likes, or another tab.
static func _open_laws_or(main, tab: String, bloc: String) -> void:
	if tab == "legislature":
		main._law_panel._laws.bloc_filter = bloc
		main._law_panel.mark_dirty()
	main._windows.open(tab)


static func _raise_event(main, event_id: String) -> void:
	main._hud.inbox.slide_in()
	for card_id in main._event_cards:
		if String(main._event_cards[card_id]) == event_id:
			main._hud.inbox.raise_card(card_id)
