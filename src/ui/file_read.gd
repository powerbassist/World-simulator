extends RefCounted

## One file of the desk, read for its page -- V5.3 screen 3 (the author picked the month's
## folder and the docked card). A file is an inbox decision or request row (inbox_files.gd);
## this turns it into the dictionary the page draws (file_view.gd), the same for the folder
## and for the docked panel, so the two cannot say two things.
##
## Pure over `main`'s registers, read-only: the player's answer goes back through
## `Inbox.press`, which is the card's own button, so nothing here writes.
##
##   kind "event"    the desk entry's event: a speaker's face and line, each choice with the
##                   tags it carries (effect_tags.gd) and its default marked;
##   kind "request"  an audience request: the person, their ask, each answer with its price;
##   kind "other"    any other row (a treaty, a council vote, a bill, a fund): its words and
##                   its own answers.
##
## The deadline is month-granular in the sim, so it is the LAST DAY of the last month the
## answer is taken, never a day the sim does not hold.

const Events = preload("res://src/sim/events.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const PartyChip = preload("res://src/ui/party_chip.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const RequestLane = preload("res://src/ui/request_lane.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const EffectTags = preload("res://src/ui/effect_tags.gd")
const InboxFiles = preload("res://src/ui/inbox_files.gd")


## The page's dictionary for `file` (an InboxFiles row), {} for a gone one.
static func describe(main, file: Dictionary) -> Dictionary:
	if file.is_empty():
		return {}
	var id := String(file["id"])
	var event_id := String(main._event_cards.get(id, ""))
	if event_id != "":
		var page := _event(main, id, event_id, file)
		if not page.is_empty():
			return page
	var request_id := String(AudienceDriver.lane_of(main)._request_of.get(id, ""))
	if request_id != "":
		var page := _request(main, id, request_id, file)
		if not page.is_empty():
			return page
	var choices: Array = []
	for action in (file["actions"] as Array):
		choices.append(_choice(action, String(action["label"]), "", [], false))  # i18n: row-ok routed by the pusher
	return {"id": id, "kind": "other", "micro": "", "title": String(file["title"]), "situation": String(file["body"]),  # i18n: row-ok routed by the pusher
		"by_text": "", "by_month": -1, "who": {}, "choices": choices}


## The file's name in the folder's list: a request is its person (the page says what they ask), anything
## else the row's own title.
static func list_title(main, file: Dictionary) -> String:
	var request_id := String(AudienceDriver.lane_of(main)._request_of.get(String(file["id"]), ""))
	if request_id != "":
		var request := Audiences.request(main._state.player(), request_id)
		if not request.is_empty():
			return main._loader.person_name(String(request["person_id"]))
	return String(file["title"])  # i18n: row-ok routed by the pusher


## Just the deadline text of a file ("" when it has none), without building its page: the
## folder's list names every file's date and the page of a request is not cheap.
static func by_text(main, file: Dictionary, short := false) -> String:
	var id := String(file["id"])
	var event_id := String(main._event_cards.get(id, ""))
	var now := int(main._state.year) * 12 + int(main._state.month)
	if event_id != "":
		for entry in main._state.player().event_queue:
			if String(entry.get("event_id", "")) == event_id:
				return _by(now + int(entry.get("months_left", 0)) - 1, short)
	var request_id := String(AudienceDriver.lane_of(main)._request_of.get(id, ""))
	if request_id != "":
		var request := Audiences.request(main._state.player(), request_id)
		if not request.is_empty():
			return _by(int(request["deadline_month"]) - 1, short)
	return ""


static func _choice(action: Dictionary, label: String, short: String, tags: Array, is_default: bool, note := "") -> Dictionary:
	return {"words": label, "short": short, "tags": tags, "default": is_default, "note": note,
		"disabled": bool(action.get("disabled", false)), "tip": String(action.get("tooltip", ""))}


static func _event(main, id: String, event_id: String, file: Dictionary) -> Dictionary:
	var ns = main._state.player()
	var ev = Events.event_by_id(main._loader, event_id)
	var entry := {}
	for e in ns.event_queue:
		if String(e.get("event_id", "")) == event_id:
			entry = e
	if ev == null or entry.is_empty():
		return {}
	var title: String = Strings.row_name("events", ev)
	if String(entry.get("region_name", "")) != "":
		title = "%s — %s" % [title, String(entry["region_name"])]
	var now := int(main._state.year) * 12 + int(main._state.month)
	var last := now + int(entry.get("months_left", 0)) - 1
	var who := {}
	var speaker := String(entry.get("speaker", ""))
	var quote := Strings.row("events", String(ev.id), "speaker_line", String(ev.speaker_line)).strip_edges()
	if speaker != "" and quote != "" and main._loader.person_name(speaker) != "":
		who = _who(main, speaker, quote)
	var choices: Array = []
	var actions: Array = file["actions"]
	for i in mini(actions.size(), ev.choices.size()):
		var choice: Dictionary = ev.choices[i]
		choices.append(_choice(actions[i], Strings.choice_label(ev.id, choice), Strings.choice_short(ev.id, choice),
			EffectTags.of(choice), bool(choice.get("is_default", false)), Strings.choice_summary(ev.id, choice)))
	return {"id": id, "kind": "event", "micro": Strings.t("Decision"), "title": title, "situation": Strings.row_summary("events", ev),
		"by_text": _by(last), "by_month": last, "who": who, "choices": choices}


static func _request(main, id: String, request_id: String, file: Dictionary) -> Dictionary:
	var ns = main._state.player()
	var request := Audiences.request(ns, request_id)
	if request.is_empty():
		return {}
	var row := AudienceDriver.row_of(main, request)
	var who := _who(main, String(request["person_id"]), "")
	var choices: Array = []
	var actions: Array = file["actions"]
	for i in actions.size():
		# An answer carries its price as its tooltip; the call has none (nothing it costs is priced), so
		# its card says in one line what it is rather than standing empty beside three that speak.
		var note := String(actions[i].get("tooltip", ""))
		if note == "" and i == RequestLane.CALL:
			note = Strings.t("Ring them instead of seeing them.")
		choices.append(_choice(actions[i], String(actions[i]["label"]), "", [], false, note))  # i18n: row-ok routed by the pusher
	var last := int(request["deadline_month"]) - 1
	return {"id": id, "kind": "request", "micro": Strings.t("Request"), "title": ask_title(main._loader, ns, request), "situation": "",
		"by_text": _by(last), "by_month": last, "who": who, "choices": choices,
		"price": String(row.get("price", "")), "broken_word": bool(row.get("broken_word", false))}


## What a request asks, as the page's headline: "Opposes The Sworn Offices". A want whose object the register
## cannot name (the reader falls back to the raw id) is the plain ask, never "sponsors none".
static func ask_title(loader, ns, request: Dictionary) -> String:
	var object := String(request.get("object", ""))
	var what := PersonCard.object_text(loader, ns, object, request)
	if what == "" or what == object or what == object.get_slice(":", object.get_slice_count(":") - 1):
		return Strings.t("Asks to see you")
	var text := "%s %s" % [Strings.t(PersonCard.stance_label(String(request.get("stance", "")))), what]
	return text.left(1).to_upper() + text.substr(1)


## The person's header words: name (linked), party swatch or kind, mood, their line.
static func _who(main, person_id: String, quote: String) -> Dictionary:
	var ns = main._state.player()
	var party := PartyChip.of(main._loader, ns, person_id)
	var person = main._loader.person_by_id.get(person_id)
	var party_name := String(party.get("name", ""))  # i18n: row-ok a party's name, a proper noun
	var role := party_name if party_name != "" else \
		(Strings.t(String(PersonCard.KIND_LABEL.get(person.kind, person.kind))) if person != null else "")
	return {"id": person_id, "called": main._loader.person_name(person_id), "role": role,
		"colour": party.get("colour", null), "quote": quote, "feel": Feelings.of(ns, person_id)}


## "30/04/2026": the last day of the last month the answer is taken (`last` = year * 12 + month).
static func _by(last: int, short := false) -> String:
	var year := floori((last - 1) / 12.0)
	var month := (last - 1) % 12 + 1
	var day := DateText.days_in(month, year)
	return DateText.day_month(day, month) if short else DateText.day_month_year(day, month, year)
