extends RefCounted

## V5.2b's wiring: the request lane, the Diary's audience days and the audience
## scene, joined to the sim's commands (src/sim/audiences.gd). Static over main's
## registers, as desk_cards.gd and diary_driver.gd are, so main.gd carries one
## register() and one routing call; everything a request does goes through here.
##
## The UI never writes a register (AGENTS.md rule 2): it reads Audiences, calls its
## commands (book, delegate, decline, hold, settle) and redraws from what they
## leave. A request card never holds the clock; the scene does, as a summit does.

const Audiences = preload("res://src/sim/audiences.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const RequestLane = preload("res://src/ui/request_lane.gd")
const AudienceScene = preload("res://src/ui/audience_scene.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const HoldReason = preload("res://src/ui/hold_reason.gd")

const WINDOW := "audience"

## Per game scene (tests run several): {lane, scene, request_id}.
static var _games := {}


static func register(main) -> void:
	var lane := RequestLane.new()
	lane.attach(main._hud.inbox)
	var scene := AudienceScene.new()
	main._windows.register("audience", Strings.t("Audience"), scene, KEY_NONE, main.ICONS + "account_balance.svg")
	_games[main.get_instance_id()] = {"lane": lane, "scene": scene, "request_id": "", "answered": {}}
	lane.book_requested.connect(func(id: String) -> void: _open_booking(main, id))
	lane.delegate_requested.connect(func(id: String) -> void: _answer(main, id, Audiences.delegate(main._state, main._state.player(), main._loader, id)))
	lane.decline_requested.connect(func(id: String) -> void: _answer(main, id, Audiences.decline(main._state, main._state.player(), main._loader, id)))
	main._calendar_panel.audience.booked.connect(func(id: String, date: Dictionary) -> void:
		var result := Audiences.book(main._state, main._state.player(), main._loader, id, date)
		main._calendar_panel.audience.close()
		_answer(main, id, result))
	scene.closed.connect(func() -> void: _end(main))
	# The frame's X ends it too: the hold the opening took goes with the window.
	main._windows.closed.connect(func(id: String) -> void:
		if id == WINDOW:
			_end(main))


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
				main._hud.inbox.push(Strings.t("Unanswered"), Strings.t("%s's request lapsed: they take it as a refusal.") % main._loader.person_name(String(gone.get("person_id", ""))))
	game["lane"].show_requests(rows)
	main._hud.title_bar.set_requests(Audiences.waiting_count(ns))


## A request read off the sim, in the words the card shows.
static func row_of(main, request: Dictionary) -> Dictionary:
	var ns = main._state.player()
	var loader = main._loader
	var id := String(request["id"])
	var answers := Audiences.answers(main._state, ns, loader, id)
	var deadline := int(request["deadline_month"])
	var year := floori((deadline - 1) / 12.0)
	return {"id": id, "person_id": String(request["person_id"]), "stance": String(request["stance"]),
		"person": loader.person_name(String(request["person_id"])),
		"ask": PersonCard.object_text(loader, ns, String(request["object"]), request),
		"by": DateText.month_year(deadline - year * 12, year),
		"price": price_text(Audiences.decline_price(ns, loader, id)),
		"book": answers["book"], "delegate": answers["delegate"], "decline": answers["decline"]}


static func price_text(price: Dictionary) -> String:
	return Strings.t("grudge %s, loyalty %s, rapport %s") % [Num.fs(float(price.get("grudge", 0.0)), 2),
		Num.fs(float(price.get("loyalty", 0.0)), 2), Num.fs(float(price.get("rapport", 0.0)), 2)]


## The diary's outcome, its UI half: the scene for an audience, else the news card
## and, for a visit that landed, the summit (V2.4a / V2.4b).
static func on_appointment(main, outcome: Dictionary) -> void:
	var entry: Dictionary = outcome["entry"]
	if String(entry.get("kind", "")) == CalendarK.KIND_AUDIENCE:
		open_scene(main, String(entry.get("action_id", "")))
		return
	main._world_news.card_appointment(entry, String(outcome["label"]), bool(outcome["ok"]))  # i18n: row-ok DiaryDriver hands back a translated label
	if String(outcome["summit_target"]) != "":
		main._open_summit(String(outcome["summit_target"]), outcome["before"])


## The booked day: the sim holds it, the scene owns the screen and the clock.
static func open_scene(main, request_id: String) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	var ns = main._state.player()
	var request := Audiences.request(ns, request_id)
	if game.is_empty() or request.is_empty() or not bool(Audiences.hold(main._state, ns, main._loader, request_id).get("ok", false)):
		return
	game["request_id"] = request_id
	var row := row_of(main, request)
	row["president"] = main._loader.person_name(String(ns.head_of_state_person_id if ns.head_of_state_kind == "executive_president" else ns.pm_person_id))
	row["name"] = row["person"]  # i18n: row-ok the person's shown name, from the loader
	row["fog"] = "stranger"
	row["offered"] = []
	row["topics"] = []
	row["attempts_left"] = 0
	main._windows.open(WINDOW)
	main._clock.paused = true
	game["scene"].open(row)
	main._hud.clock_cluster.refresh(main._clock, HoldReason.show(main))


## The scene is over. Until b2's levers decide it, an audience with no lever won
## ends as the sim's A2 regime holds one: a refusal, priced as a decline.
static func _end(main) -> void:
	var game: Dictionary = _games.get(main.get_instance_id(), {})
	if game.is_empty() or String(game["request_id"]).is_empty():
		return
	Audiences.settle(main._state, main._state.player(), main._loader, String(game["request_id"]), "declined")
	game["request_id"] = ""
	game["scene"].close_scene()
	main._windows.close(WINDOW)
	if not main._decision_holds_clock():
		main._clock.paused = false
	refresh(main)


static func _open_booking(main, request_id: String) -> void:
	var ns = main._state.player()
	var request := Audiences.request(ns, request_id)
	if request.is_empty():
		return
	main._windows.open("calendar")
	main._calendar_panel.audience.open_for(row_of(main, request), Audiences.offered_dates(main._state, ns, request_id))


static func _answer(main, request_id: String, result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		_games[main.get_instance_id()]["answered"][request_id] = true
	elif String(result.get("error", "")) != "":
		main._hud.inbox.push(Strings.t("The request"), String(result["error"]))  # i18n: row-ok the sim's refusal
	refresh(main)
	main._windows.mark_all_dirty()
