extends RefCounted

## The monthly briefing's wiring -- V5.3-0, docs/design/v5.3-0-readability.md 2.2.
## Static over main, as phone_driver.gd is: the card (chief_briefing.gd) to the
## ranking (priorities.gd), the chief's mark and caption, and the Go table.
##
## **G1, the chief off the clock** (chief-briefing-brief.md; the author, 2026-11-15:
## "Jamais"): a month end never opens the card and never pauses. month_end() ranks the
## month, keeps it, puts the month's consequence cards and sector notes in the inbox,
## names the first line on the mark in the title bar and, when he has something new,
## drops his line under it as a caption. The Messages setting "only when new" went with
## the hold. The card opens only when the player asks (the mark, read()): that read
## holds the clock while it is up, outside the modal budget, until G2 retires it.
##
## Under the invited read the old hold order stands: an interrupt or the term-start
## offer still holding is named by the closing button ("Next: ..."), which opens it.

const ResultTone = preload("res://src/ui/result_tone.gd")
const ChiefBriefing = preload("res://src/ui/chief_briefing.gd")
const ScreenStack = preload("res://src/ui/screen_stack.gd")
const RegionArrival = preload("res://src/ui/region_arrival.gd")
const FinanceSectors = preload("res://src/ui/finance_sectors.gd")
const SectorWarningView = preload("res://src/ui/sector_warning_view.gd")
const Priorities = preload("res://src/ui/priorities.gd")
const Music = preload("res://src/ui/music.gd")
const Trends = preload("res://src/ui/trends.gd")
const PriorityWords = preload("res://src/ui/priority_words.gd")
const BriefingEffects = preload("res://src/ui/briefing_effects.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Strings = preload("res://src/ui/strings.gd")
const Events = preload("res://src/sim/events.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const Voices = preload("res://src/core/voices.gd")
const Voice = preload("res://src/ui/voice.gd")
const Staff = preload("res://src/sim/staff.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const ChiefMarkView = preload("res://src/ui/chief_mark_view.gd")

## The chief has three lines a situation (#226: 4 chiefs x 3 situations x 3).
const CHIEF_VARIANTS := 3
## The card id the chief's spoken line carries (Voice.hush).
const LINE_CARD := Voice.CHIEF_CARD
## The card's meta naming the month whose line it has said (speak_once).
const SPOKEN := "spoken"  # i18n: ok a meta key

static var _games := {}


static func register(main) -> void:
	var card := ChiefBriefing.new()
	main._stack.add(ScreenStack.SCENE, card, true, func() -> void: close(main))
	card.hide()
	var game := {"card": card, "lines": [], "memory": {}, "state_id": 0, "pending": {}, "was_running": false,
		"said_in": "", "turns": {}}
	_games[main.get_instance_id()] = game
	card.go_pressed.connect(func(i: int) -> void: go(main, i))
	card.closed.connect(func() -> void: close(main))
	preload("res://src/ui/folder_driver.gd").attach(main, card)
	# The two verbs block 0 added where a Go lands (2.4); the panels only ask.
	main._agenda_panel.open_requested.connect(func(tab: String) -> void: main._windows.open(tab))
	main._polling_panel.calm_requested.connect(func(tab: String, bloc: String) -> void: _open_laws_or(main, tab, bloc))
	main._hud.inbox.card_action.connect(func(id: String, _i: int) -> void:  # V5.3 B7: a bill card's Go
		if main._assembly_news.take_go(id): _open_laws_or(main, "legislature", ""))
	# G1: the mark opens the read; an answered file ranks the month again, so the mark
	# never names a file that is gone (the brief's "no stale line").
	main._hud.title_bar.chief_pressed.connect(func() -> void: read(main))
	main._hud.inbox.card_closed.connect(func(_id: String) -> void: ChiefMarkView.refresh(main, true))
	main._hud.inbox.card_dismissed.connect(func(_id: String) -> void: ChiefMarkView.refresh(main, true))
	ChiefMarkView.follow_answers(main)


static func card_of(main) -> ChiefBriefing:
	return _games.get(main.get_instance_id(), {}).get("card")


static func showing(main) -> bool:
	var card := card_of(main)
	return card != null and card.visible


## The Elections step's front page waits for what owns the screen after the count:
## the count's plate, else nothing -- the briefing no longer opens by itself (G1). The
## month's report is kept here for after_election, which runs on the plate's dismissal.
static func plate_for(main, report: Dictionary) -> Control:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	if not game.is_empty():
		game["report"] = report
	var results: Array = report.get("election_results", [])
	return null if results.is_empty() else main._election_panel


## _finish_month's tail on a month with no result on screen: the term start first
## (its hold and card are the briefing's priority 1), then the month's ranking.
static func finish_month(main, report: Dictionary) -> void:
	main._enforce_term_start_programme()
	month_end(main, report)


## The count's plate dismissed after a win: the same tail, on the month it closed.
static func after_election(main) -> void:
	main._enforce_term_start_programme()
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	month_end(main, game.get("report", {}))


## The month's tail (G1): B7's calls, the month ranked and kept, its cards and sector
## notes in the inbox, the mark named, and the caption when he speaks. Never a pause.
static func month_end(main, report: Dictionary) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	var ns = main._state.player() if main._state != null else null
	var cards: Array = game.get("month_cards", [])
	game.erase("month_cards")
	if ns != null:
		RegionArrival.check(main)
		preload("res://src/ui/desk_cards.gd").card_called(main)  # B7: the quiet-month call comes after the Events hook
		preload("res://src/ui/council_cards.gd").check(main)  # B7: a treaty at home, a division the player swings
	# The month's consequence cards and its crossings go to the inbox every month: no card
	# says them on its own now (the brief's "What must hold": as on a month not shown).
	var slipped: Array = [] if ns == null else SectorWarningView.note_cards(ns, main._loader, int(main._state.year) * 12 + int(main._state.month))
	cards = preload("res://src/ui/effects_ledger.gd").drop_default_echo(cards)
	for card in cards + slipped:
		ResultTone.mark(main._hud.inbox, main._hud.inbox.push(card["title"], card["body"]), String(card.get("tone", "")))
	if game.is_empty() or ns == null or not bool(ns.in_government) or not _rank_month(main, game, report):
		ChiefMarkView.clear(main)
		return
	var ranked: Dictionary = game["pending"]
	game["pending"] = {}
	# The memory the month was ranked FROM: a re-rank goes through it again, so novelty
	# stays the month's (the brief's "novelty stays monthly").
	game["memory_before"] = game["memory"]
	game["memory"] = ranked["memory"]
	game["lines"] = ranked["lines"]
	game["also"] = ranked.get("also_due", [])
	# Pre-gate B2: the chief speaks when the situation is not the one he last spoke in,
	# or a row is new; otherwise he is silent. Each show turns that situation's line.
	var situation := Priorities.situation(ranked["lines"])
	var speaks := situation != String(game["said_in"]) or bool(ranked.get("new", false))
	game["said_in"] = situation
	game["turns"][situation] = _turn(main, situation) + 1
	ChiefMarkView.refresh(main)
	if speaks:
		ChiefMarkView.speak(main, "%d:%d" % [main._state.get_instance_id(), int(main._state.year) * 12 + int(main._state.month)])


## A month's consequence card (effects_ledger.gd, a desk card decided for you), held
## for month_end(), which puts it in the inbox with the month's other notes.
static func hold_card(main, card: Dictionary) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	if card.is_empty():
		return
	if game.is_empty():
		ResultTone.mark(main._hud.inbox, main._hud.inbox.push(card["title"], card["body"]), String(card.get("tone", "")))
		return
	game["month_cards"] = game.get("month_cards", []) + [card]


## Ranks this month once (cached until month_end takes it); false when there is nothing
## to rank (no player, out of government).
static func _rank_month(main, game: Dictionary, report: Dictionary) -> bool:
	var state = main._state
	if state == null or state.player() == null or not bool(state.player().in_government):
		return false
	# A load or a new game is a new state: novelty starts over (2.3).
	if int(game["state_id"]) != state.get_instance_id():
		game["state_id"] = state.get_instance_id()
		game["memory"] = {}
		game["pending"] = {}
		game["said_in"] = ""
		game["turns"] = {}
	var now := int(state.year) * 12 + int(state.month)
	if game["pending"].is_empty() or int(game["pending"].get("month", -1)) != now:
		game["pending"] = ChiefMarkView.rank(main, game["memory"])
		game["pending"]["month"] = now
		# V5.3-0 (d): the month's band, from this ranking.
		Music.follow(main, Priorities.situation(game["pending"]["lines"]), Trends.months_to_vote(state, state.player()),
			state.get_instance_id())
	game["report"] = report
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
		var situation := Priorities.situation(lines)
		said = chief_said(main._loader, String(chief.id), situation, _turn(main, situation))
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


## How many cards this game has shown in `situation` (open() turns it): the line's
## rotation index. By situation, not by month: a month index repeated a line every
## three months whenever the situation was the same (pre-gate B2).
static func _turn(main, situation: String) -> int:
	return int((_games.get(main.get_instance_id(), {}).get("turns", {}) as Dictionary).get(situation, 0))


## The chief's line for the month's situation (2.6) as {text, clip}: three variants
## per situation in the voice archetype's own lines, `turn` rotating them so no
## line follows itself in one situation. The clip (#226's batch) is Voice's only when its hash is
## the line's own, hashed BEFORE the quotes go round it -- the pipeline voiced the
## bare line, so the quoted text would never match.
static func chief_said(loader, person_id: String, situation: String, turn: int) -> Dictionary:
	var arch := Voices.archetype_of(loader, person_id)
	var key := "%s_%d" % [situation, posmod(turn, CHIEF_VARIANTS) + 1]
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
## chief waits for it in Voice's queue and speaks when it ends, if `card` -- his
## caption since G1 -- is still up. Nothing replays later (the parent's TAKE 1 on #229
## -- an arrival month is a tense or crisis one, so dropping the line silenced the
## chief exactly when it mattered).
static func speak(main: Node, shown: Dictionary, card: CanvasItem) -> void:
	Voice.speak_queued(main, String(shown.get("clip", "")), LINE_CARD, card)


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


## The read the player asked for (G1: the mark, until G2 makes it the Presidency page's
## lead): the month ranked again from its own memory, then today's card, holding the
## clock while it is up -- outside the modal budget, since the player opened it.
## `rerank` false shows the lines as they stand (a test stages them).
static func read(main, rerank := true) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	if game.is_empty() or game["card"].visible or main._state == null or main._state.player() == null:
		return
	if rerank:
		ChiefMarkView.rerank(main)
	game["was_running"] = not main._clock.paused
	main._clock.paused = true
	game["card"].show_view(view(main, game["lines"], game.get("report", {}), game["also"]))
	preload("res://src/ui/folder_driver.gd").refresh(main)
	# A request the read names, on a line, in the footer or folded into a line's "+N
	# more", has been SEEN under #207's rule (the parent's calls on QA's #218 finding and
	# RECORD): its arrival's slowdown gives the player's speed back, unless they picked
	# one since (_seen's own rule). Never opened, AudienceDriver's own rule stands.
	for entry in (game["lines"] as Array) + (game.get("also", []) as Array):
		for named in [entry] + (entry.get("folded", []) as Array):
			if String(named.get("kind", "")) == "request":
				AudienceDriver._seen(main, String(named["subject"]))
	main._hud.clock_cluster.refresh(main._clock, preload("res://src/ui/hold_reason.gd").show(main))


static func close(main) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	if game.is_empty() or not game["card"].visible:
		return
	game["card"].hide()
	game["card"].dismissed.emit()
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


## After a load (QA's RECORD on #218, PhoneDriver.after_load's rule): the card, the mark
## and the caption of the discarded game come down, and the clock it paused and the
## lines it named belong to that game, so they go too (novelty starts over by
## _rank_month's state_id). No `dismissed`: nothing of the discarded game waits on it.
static func after_load(main) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	if game.is_empty():
		return
	game["card"].hide()
	Voice.hush(main, LINE_CARD)
	game["was_running"] = false
	game["lines"] = []
	game["also"] = []
	ChiefMarkView.forget(game)
	ChiefMarkView.clear(main)


## Go: close by Continue's rule, then open the line's target (2.4's table).
static func go(main, index: int) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	var all: Array = (game.get("lines", []) as Array) + (game.get("also", []) as Array)
	if game.is_empty() or index < 0 or index >= all.size():
		return
	var line: Dictionary = all[index]
	if preload("res://src/ui/folder_driver.gd").go(main, line):
		return
	var target := target_of(line)
	# Go keeps the clock paused (pre-gate B5: resumed at speed, a request booked for
	# the next day opened its audience over the Go's target); the player resumes it
	# with Space or the clock. Continue still gives the speed back (#207, #219).
	game["was_running"] = false
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
		"plant":
			# The closure's row heads In progress, the tab's top: a tab left scrolled
			# down would hide the one month's answer.
			main._windows.open(tab)
			main._companies_panel._scroll.scroll_vertical = 0
		"sector":
			main._windows.open(tab)
			FinanceSectors.aim(main._windows.frame(tab)._content, subject)
		"commitment" when tab == "calendar":
			# The Diary on the due day (2.4): a word is judged as its month begins,
			# so its mark and its Call are on the first.
			main._windows.open(tab)
			var due := int(line["deadline_month"])
			var year := floori((due - 1) / 12.0)
			main._calendar_panel._grid.pick(year, due - year * 12, 1)
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
	# A minister's word (pre-gate RF3): the minister does the work, so the Agenda,
	# Politics or the Budget hold no verb of the player's on it -- and the Agenda
	# does not even show a programme entry the player does not hold. The Diary does.
	if subject.get_slice("|", 0) == "delegated":
		return {"tab": "calendar", "acts_on": subject}
	if object.begins_with("programme:"):
		return {"tab": "agenda", "acts_on": object.trim_prefix("programme:")}
	if object.begins_with("office:"):
		return {"tab": "politics", "acts_on": "seats"}
	if object.begins_with("meter:"):
		return {"tab": "finances", "acts_on": "balance"}
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
