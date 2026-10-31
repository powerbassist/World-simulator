extends RefCounted

## V5.2b's wiring: the request lane, the Diary's audience days and the audience
## scene, joined to the sim's commands (src/sim/audiences.gd). Static over main's
## registers, as desk_cards.gd and diary_driver.gd are, so main.gd carries one
## register() and one routing call; everything a request does goes through here.
##
## The UI never writes a register (AGENTS.md rule 2): it reads Audiences, calls its
## commands (book, delegate, decline) and redraws from what they leave. A request
## card never holds the clock; the scene does, as a summit does -- and the scene's
## session, Levers', is audience_talks.gd's.

const Audiences = preload("res://src/sim/audiences.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const RequestLane = preload("res://src/ui/request_lane.gd")
const AudienceScene = preload("res://src/ui/audience_scene.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const Strings = preload("res://src/ui/strings.gd")
const AudienceTalks = preload("res://src/ui/audience_talks.gd")
const Words = preload("res://src/ui/lever_words.gd")
const PromiseList = preload("res://src/ui/promise_list.gd")
const PhoneDriver = preload("res://src/ui/phone_driver.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const President = preload("res://src/sim/president.gd")
const ProposalNote = preload("res://src/ui/proposal_note.gd")
const PartyChip = preload("res://src/ui/party_chip.gd")

const WINDOW := "audience"

## Per game scene (tests run several): {lane, scene, session, answered}.
static var _games := {}


static func register(main) -> void:
	var lane := RequestLane.new()
	lane.attach(main._hud.inbox)
	var scene := AudienceScene.new()
	main._windows.register("audience", Strings.t("Audience"), scene, KEY_NONE, main.ICONS + "account_balance.svg")
	# The president's word sits in the Diary under its grid.
	var promises := PromiseList.new()
	main._calendar_panel.requests.promise_slot.add_child(promises)
	# booking_for: the request whose days the Diary shows (V5.3-0 (b2)), "" for none.
	# Presentation only: a load clears it.
	var game := {"lane": lane, "scene": scene, "session": {}, "answered": {}, "promises": promises,
		"slowed_for": {}, "resume_speed": 0, "booking_for": ""}
	_games[main.get_instance_id()] = game
	lane.book_requested.connect(func(id: String) -> void: _open_booking(main, id))
	lane.seen.connect(func(id: String) -> void: _seen(main, id))
	lane.delegate_requested.connect(func(id: String) -> void: _answer(main, id, Audiences.delegate(main._state, main._state.player(), main._loader, id)))
	lane.decline_requested.connect(func(id: String) -> void: _answer(main, id, Audiences.decline(main._state, main._state.player(), main._loader, id)))
	main._calendar_panel.requests.booked.connect(func(id: String, date: Dictionary) -> void:
		var result := Audiences.book(main._state, main._state.player(), main._loader, id, date)
		game["booking_for"] = ""
		_answer(main, id, result)
		_seen(main, id))
	# V5.3-0 (b2): the Diary's request column, the lane's verbs beside the grid.
	var column = main._calendar_panel.requests
	column.focus_requested.connect(func(id: String) -> void: _open_booking(main, id))
	column.delegate_requested.connect(func(id: String) -> void:
		_seen(main, id)
		_answer(main, id, Audiences.delegate(main._state, main._state.player(), main._loader, id)))
	column.decline_requested.connect(func(id: String) -> void:
		_seen(main, id)
		_answer(main, id, Audiences.decline(main._state, main._state.player(), main._loader, id)))
	# A booking left without a day -- its Days pressed again, or the Diary closed
	# under it -- ends the player's action as surely as a booking does.
	column.unfocus_requested.connect(func(id: String) -> void:
		game["booking_for"] = ""
		_seen(main, id)
		refresh(main))
	main._windows.closed.connect(func(id: String) -> void:
		# The booking ends with the Diary: its days no longer tinted, its Days up.
		if id == "calendar" and String(game["booking_for"]) != "":
			var was := String(game["booking_for"])
			game["booking_for"] = ""
			_seen(main, was)
			refresh(main))
	# Each verb redraws the lane's side too: a promise made is in the Diary at once.
	scene.attempted.connect(func(lever: String, args: Dictionary) -> void:
		AudienceTalks.attempt(main, game, lever, args)
		refresh(main))
	scene.talked.connect(func(topic: String, args: Dictionary) -> void: AudienceTalks.talk(main, game, topic, args))
	scene.ended.connect(func() -> void: AudienceTalks.end(main, game))
	scene.offer_answered.connect(func(accepted: bool) -> void: AudienceTalks.offer(main, game, accepted))
	scene.affair.connect(func(action: String) -> void: AudienceTalks.affair(main, game, action))
	scene.closed.connect(func() -> void: _leave(main, game))
	# The frame's X ends it too: the hold the opening took goes with the window.
	main._windows.closed.connect(func(id: String) -> void:
		if id == WINDOW:
			_leave(main, game))
	# V5.2b b3, the phone: a request's "Call them" and a right click in People.
	PhoneDriver.register(main, func() -> void: refresh(main))
	lane.call_requested.connect(func(id: String) -> void:
		var pid := String(Audiences.request(main._state.player(), id).get("person_id", ""))
		PhoneDriver.open_call(main, pid, AudienceTalks.gossip_people(main, pid)))
	main._people_panel.call_requested.connect(func(pid: String) -> void:
		PhoneDriver.open_call(main, pid, AudienceTalks.gossip_people(main, pid)))
	main._people_panel.answer_requested.connect(func(id: String) -> void:
		main._hud.inbox.slide_in()
		main._hud.inbox.raise_card(lane_of(main).card_of(id)))
	main._hud.title_bar.requests_pressed.connect(func() -> void: open_oldest(main))


static func lane_of(main) -> RequestLane:
	return _games.get(main.get_instance_id(), {}).get("lane")


static func scene_of(main) -> AudienceScene:
	return _games.get(main.get_instance_id(), {}).get("scene")


## The lane and the mark, redrawn off the register: after a month, a load, an answer.
static func refresh(main) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	var ns = main._state.player() if main._state != null else null
	if game.is_empty() or ns == null:
		return
	var rows: Array = []
	var live := {}
	for request in Audiences.pending(ns):
		rows.append(row_of(main, request))
		live[String(request["id"])] = true
	# A card whose request left the register without an answer from here lapsed:
	# a refusal the sim has priced, said as a note (it never held anything).
	for id in game["lane"].request_ids():
		if not live.has(id) and not game["answered"].has(id):
			var gone := Audiences.request(ns, id)
			if String(gone.get("status", "")) == "lapsed":
				_note_lapse(main, game, main._loader.person_name(String(gone.get("person_id", ""))))
	# The Diary's days stop showing a request no longer waiting (answered from its
	# card, lapsed, booked elsewhere).
	if not live.has(String(game["booking_for"])):
		game["booking_for"] = ""
	game["lane"].show_requests(rows)
	main._calendar_panel.requests.show_requests(rows, String(game["booking_for"]))
	main._hud.title_bar.set_requests(Audiences.waiting_count(ns))
	game["promises"].show_rows(given_lines(main), judged_rows(main))


## A request read off the sim, in the words the card shows.
static func row_of(main, request: Dictionary) -> Dictionary:
	var ns = main._state.player()
	var loader = main._loader
	var id := String(request["id"])
	var answers := Audiences.answers(main._state, ns, loader, id)
	# The last month an answer is taken: the sim lapses a pending request AS its
	# deadline month begins (Audiences._overdue), so the card names the month
	# before (QA's pre-gate B TAKE 1: "Answer by AUG" lapsed on 1 AUG).
	var last := int(request["deadline_month"]) - 1
	# c1c rule 1: a person holding something on the president takes a refusal as a
	# broken word; the price already counts it (decline_price), the card says why.
	var price := Audiences.decline_price(ns, loader, id)
	return {"id": id, "person_id": String(request["person_id"]), "stance": String(request["stance"]), "object": String(request["object"]),
		"person": loader.person_name(String(request["person_id"])),
		"ask": PersonCard.object_text(loader, ns, String(request["object"]), request),
		"wants": "%s %s" % [Strings.t(PersonCard.stance_label(String(request["stance"]))),
			PersonCard.object_text(loader, ns, String(request["object"]), request)],
		"by": Words.when(last), "party": PartyChip.of(loader, ns, String(request["person_id"])),
		"price": Words.price_text(price, Feelings.of(ns, String(request["person_id"]))), "broken_word": price.has("broken_word"),
		"book": answers["book"], "delegate": answers["delegate"], "decline": answers["decline"]}.merged(_call_answer(main, String(request["person_id"])))


## The card's fourth answer: the sim's own refusal on it (spoken this month
## already), never a guess here.
static func _call_answer(main, pid: String) -> Dictionary:
	var why := String(PhoneDriver.Phone.options(main._state, main._state.player(), main._loader, pid)["why_not"])
	return {"call": {"ok": why == "", "reason": why}}


## The diary's outcome, its UI half: the scene for an audience, else the news card
## and, for a visit that landed, the summit (V2.4a / V2.4b).
static func on_appointment(main, outcome: Dictionary) -> void:
	var entry: Dictionary = outcome["entry"]
	if String(entry.get("kind", "")) == CalendarK.KIND_AUDIENCE:
		open_scene(main, String(entry.get("action_id", "")))
		return
	var card: String = main._world_news.card_appointment(entry, String(outcome["label"]), bool(outcome["ok"]), String(outcome.get("reason", "")))  # i18n: row-ok DiaryDriver hands back a translated label
	if bool(outcome.get("tabled", false)):
		ProposalNote.remember(main, String(entry.get("law_id", "")), card)  # V5.2 b+ R2: the day's card takes the verdict
	if String(outcome["summit_target"]) != "":
		main._open_summit(String(outcome["summit_target"]), outcome["before"])


## The booked day: the audience opens (audience_talks.gd).
static func open_scene(main, request_id: String) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	var request := Audiences.request(main._state.player(), request_id)
	if not game.is_empty() and not request.is_empty() and AudienceTalks.open(main, game, row_of(main, request)):
		refresh(main)


## The month's UI half of the audiences, after their step: the lane and its mark
## (QA on #105: read at Events, the lane was a month behind the register), and the
## promises the month judged, a card each.
static func after_month(main, report: Dictionary) -> void:
	refresh(main)
	AudienceTalks.card_verdicts(main, report)
	# The author's "Ralentir à l'arrivée" (2026-10-24): a month that brings a
	# request drops the clock to speed 1. Not a stop -- a request never holds --
	# but at speed 3 its two months were ten seconds, gone while the player read
	# another panel (QA's pre-gate B CALL 1). A lapse alone does not slow it.
	var arrived: Array = report.get("audience_requests", {}).get("arrived", [])
	if not arrived.is_empty():
		_slow_for(main, arrived)
		main._hud.title_bar.pulse_requests()


## The author's "Revenir à ta vitesse après" (2026-10-30): the speed an arrival
## took is given back once the player has SEEN a request it slowed for (_seen).
## A second arrival while slowed keeps the first speed to give back.
static func _slow_for(main, arrived: Array) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	if game.is_empty():
		return
	if main._clock.speed > 1:
		game["resume_speed"] = main._clock.speed
	for row in arrived:
		game["slowed_for"][String(row.get("id", ""))] = true
	main._clock.set_speed(1)
	main._hud.clock_cluster.refresh(main._clock)


## A request the arrival slowed for was seen -- its card clicked, answered or
## closed, or raised by the title bar's mark: the speed comes back, unless the
## player picked one themselves meanwhile (the clock is no longer at 1).
static func _seen(main, request_id: String) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	if game.is_empty() or not game["slowed_for"].has(request_id):
		return
	var speed := int(game["resume_speed"])
	game["slowed_for"] = {}
	game["resume_speed"] = 0
	if speed > 1 and main._clock.speed == 1:
		main._clock.set_speed(speed)
		main._hud.clock_cluster.refresh(main._clock)


## The "requests waiting" mark's click: the inbox back over a tab, and the
## OLDEST request -- the first to lapse -- raised to the top of its lane. By
## arrival month, not the register's order: an invitation can be appended after
## a younger ask. Refused under a scene, as the sidebar's Inbox entry is.
static func open_oldest(main) -> void:
	var ns = main._state.player() if main._state != null else null
	if ns == null or not main._stack.accepts_hotkeys():
		return
	var oldest := {}
	for request in Audiences.pending(ns):
		if oldest.is_empty() or int(request["arrived_month"]) < int(oldest["arrived_month"]):
			oldest = request
	if oldest.is_empty():
		return
	main._hud.inbox.slide_in()
	main._hud.inbox.raise_card(lane_of(main).card_of(String(oldest["id"])))
	# The mark shows every waiting request, so it sees them all -- the oldest may
	# predate the arrival that slowed the clock (QA's RECORD on #207).
	for request in Audiences.pending(ns):
		_seen(main, String(request["id"]))


## Every promise and IOU in flight, worded, soonest due first (the sim's order).
static func given_lines(main) -> Array:
	var out: Array = []
	for row in President.commitments(main._state.player()):
		out.append(Words.commitment_text(String(row["kind"]), main._loader.person_name(String(row["person_id"])),
			AudienceTalks.want_words(main, String(row["person_id"]), String(row["object"])), int(row["due_month"])))
	return out


## The judged ones with their verdicts, newest first, each dated by the month it
## was judged: kept (or paid), or a lie revealed (a betrayal, for an IOU). A void
## row -- a want the content no longer carries -- was never priced and is not
## the president's word to answer for.
static func judged_rows(main) -> Array:
	var out: Array = []
	for row in President.judged_commitments(main._state.player()):
		if String(row["verdict"]) == "void":
			continue
		var pid := String(row["person_id"])
		var text := Words.verdict_text(String(row["kind"]), String(row["verdict"]) == "kept", main._loader.person_name(pid),
			AudienceTalks.want_words(main, pid, String(row["object"])))
		out.push_front({"text": "%s — %s" % [Words.when(int(row["judged_month"])), text], "kept": String(row["verdict"]) == "kept"})
	return out


## After a load: an audience open in the discarded game is closed there (Levers'
## rule: never let a session go unclosed) and the scene comes down; the lane and
## the Diary are redrawn off the loaded registers.
## V5.3-0 (b), spec 3.4: the lapses are ONE note, not one a person -- eleven
## "X's request lapsed" rows were 110 of the inbox's 347 words at month 12. The
## live note takes each new name, says the count, and keeps the names behind its
## More; once dismissed, the next lapse starts a new note.
static func _note_lapse(main, game: Dictionary, person: String) -> void:
	var inbox = main._hud.inbox
	var id := String(game.get("lapse_note", ""))
	if id == "" or inbox.lane_of(id) == "":
		game["lapse_names"] = []
	(game["lapse_names"] as Array).append(person)
	var names: Array = game["lapse_names"]
	var body := Strings.t("%s's request lapsed: they take it as a refusal.") % person
	if names.size() > 1:
		body = "%s %s" % [Strings.tn("%d request lapsed: taken as a refusal.", "%d requests lapsed: taken as a refusal.", names.size()) % names.size(),
			Strings.t("From: %s.") % ", ".join(names)]
	if id != "" and inbox.lane_of(id) != "":
		inbox.set_body(id, body)
		inbox.raise_card(id)
		return
	game["lapse_note"] = inbox.push(Strings.t("Unanswered"), body)


static func after_load(main) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	if not game.is_empty():
		AudienceTalks.leave(main, game)
		game["slowed_for"] = {}
		game["resume_speed"] = 0
		game["booking_for"] = ""
	PhoneDriver.after_load(main)
	refresh(main)


static func _leave(main, game: Dictionary) -> void:
	if AudienceTalks.leave(main, game):
		refresh(main)


static func _open_booking(main, request_id: String) -> void:
	var ns = main._state.player()
	var request := Audiences.request(ns, request_id)
	if request.is_empty():
		return
	_games[main.get_instance_id()]["booking_for"] = request_id
	main._windows.open("calendar")
	main._calendar_panel.requests.show_days(Audiences.offered_dates(main._state, ns, request_id), main._state, main._loader)
	refresh(main)
	main._calendar_panel.requests.focus_booking(request_id)


static func _answer(main, request_id: String, result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		_games[main.get_instance_id()]["answered"][request_id] = true
	elif String(result.get("error", "")) != "":
		main._hud.inbox.push(Strings.t("The request"), String(result["error"]))  # i18n: row-ok the sim's refusal
	refresh(main)
	main._windows.mark_all_dirty()
