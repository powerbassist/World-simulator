extends SceneTree

## Headless test: godot --headless --script res://tests/test_file_page.gd
## Non-zero exit on any failure.
##
## V5.3 screen 3, the file page (the author picked the month's folder and the docked card).
## What can fail silently:
##   - an effect key an event carries that effect_tags.gd does not word: the choice would show
##     bloc tags alone while its real cost is corruption or a sector burden (the whole point
##     of the page is that the cost is on the card);
##   - the door: a gone row or a disabled answer must be refused, an enabled one must be the
##     card's own button, and a note must not be a file;
##   - the page's facts: the deadline is the last day of the last month the answer is taken
##     (now + months_left - 1), the default is marked exactly once, the buttons number the
##     choices (so the press index IS the choice index main.gd answers);
##   - a file that is gone reads as such, never as a stale page;
##   - a request still waiting never reads "Answered." because its card was put up again (G5, blind play 11-28);
##   - the `short` label: optional, at most SHORT_MAX characters, absent reads as no short.

const GameEvent = preload("res://src/core/event.gd")
const EconomyK = preload("res://src/sim/economy_constants.gd")
# The tax kinds an event may name are the library's since V5.3 e (#334 removed EconomyK.TAX_KEYS).
const TaxesLoader = preload("res://src/core/loaders/taxes_loader.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const DeskCards = preload("res://src/ui/desk_cards.gd")
const EffectTags = preload("res://src/ui/effect_tags.gd")
const FileRead = preload("res://src/ui/file_read.gd")
const FileView = preload("res://src/ui/file_view.gd")
const FilesDriver = preload("res://src/ui/files_driver.gd")
const InboxFiles = preload("res://src/ui/inbox_files.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_check_every_effect_key_is_worded()
	_check_short_label()
	_check_the_door()
	_check_an_event_file()
	_check_request_titles()
	_check_a_gone_file()
	_check_a_re_put_request_keeps_its_page()
	_check_every_option_keeps_its_title()
	_finish()
	return true


## Each button names its file as the folder's list does, and a press goes where the card's own click
## goes (main.gd's card_activated route): the programme card to the Agenda, a file to this page.
func _check_desk_buttons(view, listed: Array, open_files: Array) -> void:
	var saw_request := false
	var saw_programme := false
	for i in open_files.size():
		var file: Dictionary = open_files[i]
		var button: Button = listed[i]
		var want := FileRead.list_title(_main, file)
		saw_request = saw_request or want != String(file["title"])
		if button.text != want:
			_fail("the desk lists '%s' as '%s', not '%s'" % [file["id"], button.text, want])
		_main._windows.close_all()
		button.pressed.emit()
		if String(file["id"]) == String(_main._programme_card_id):
			saw_programme = true
			if not _main._windows.is_open("events") or _main._events_panel.selected() != preload("res://src/ui/programme_file.gd").KEY:
				_fail("the programme card on the desk did not open its file on the Folder (open: %s)" % [_main._windows.open_ids()])
		elif view.file_id() != String(file["id"]):
			_fail("pressing a listed file opened '%s', not '%s'" % [view.file_id(), file["id"]])
		view.show_file("card_gone")
		view._rebuild()
		listed = view.find_children("*", "Button", true, false).filter(
				func(b) -> bool: return not (b as Node).is_queued_for_deletion())
	if not saw_request:
		_fail("premise: no request on the desk whose list title differs from its card's")
	if not saw_programme:
		_fail("premise: the term's programme card is not on the desk")


func _check_every_effect_key_is_worded() -> void:
	var seen := 0
	for ev in _main._loader.events:
		for choice in ev.choices:
			var effects: Dictionary = choice["effects"]
			for key in effects:
				if not EffectTags.WORDED.has(key):
					_fail("%s.%s carries effect '%s', which effect_tags.gd does not word" % [ev.id, choice["id"], key])
					continue
				var worded: Array = EffectTags.WORDED[key]
				if worded.is_empty() or not (effects[key] is Dictionary):
					continue
				for sub in effects[key]:
					if not worded.has(sub):
						_fail("%s.%s carries '%s.%s', which effect_tags.gd does not word" % [ev.id, choice["id"], key, sub])
			var tags := EffectTags.of(choice)
			seen += 1
			if tags.is_empty() or tags.size() > EffectTags.TAG_MAX:
				_fail("%s.%s has %d tags, outside 1..%d" % [ev.id, choice["id"], tags.size(), EffectTags.TAG_MAX])
			for tag in tags:
				if String(tag["text"]) == Strings.t("Other effects"):
					_fail("%s.%s fell through to 'Other effects'" % [ev.id, choice["id"]])
	if seen < 300:
		_fail("only %d choices were swept: the content did not load" % seen)
	# A corruption cost and a sector burden are tags, not silence, and they outrank the third bloc.
	var tags := EffectTags.of({"effects": {"bloc_offset": {"rural": 0.06, "urban": -0.05, "business": -0.01},
		"society": {"corruption": 0.04}, "company": {"sector": "agriculture", "burden": 0.04}}})
	var text := " | ".join(tags.map(func(t): return String(t["text"])))
	if not text.contains(Strings.t("Looser on corruption")):
		_fail("a corruption cost or a sector burden is not on the choice's tags: %s" % text)
	if tags.size() != EffectTags.TAG_MAX:
		_fail("four effects and three blocs make %d tags, not the cap %d" % [tags.size(), EffectTags.TAG_MAX])


func _check_short_label() -> void:
	var raw := {"id": "x", "name": "X", "summary": "s", "likelihood": 0.05, "category": "scandal", "respond_months": 2, "choices": [
		{"id": "a", "label": "A long label for a button", "summary": "do a", "short": "Carry it",
			"effects": {"bloc_offset": {"business": 0.01}}, "default": true},
		{"id": "b", "label": "B", "summary": "do b", "effects": {"bloc_offset": {"workers": 0.01}}}]}
	var errs: Array[String] = []
	var ev = GameEvent.from_dict(raw.duplicate(true), "x.json", errs, TaxesLoader.FIRST, EconomyK.SPENDING_KEYS, OpinionK.BLOC_KEYS,
		EconomyK.SECTOR_TREND.keys())
	if not errs.is_empty():
		_fail("a valid `short` was refused: %s" % [errs])
		return
	if Strings.choice_short(ev.id, ev.choices[0]) != "Carry it":
		_fail("the choice's short label did not come through")
	if Strings.choice_short(ev.id, ev.choices[1]) != "":
		_fail("a choice with no short reads '%s', not '' (the page falls back to the label itself)" % Strings.choice_short(ev.id, ev.choices[1]))
	var long_raw := raw.duplicate(true)
	long_raw["choices"][0]["short"] = "x".repeat(GameEvent.SHORT_MAX + 1)
	var errs2: Array[String] = []
	GameEvent.from_dict(long_raw, "x.json", errs2, TaxesLoader.FIRST, EconomyK.SPENDING_KEYS, OpinionK.BLOC_KEYS, EconomyK.SECTOR_TREND.keys())
	if errs2.is_empty():
		_fail("a `short` past SHORT_MAX (%d) was accepted: it would not fit the 180 px button" % GameEvent.SHORT_MAX)


func _check_the_door() -> void:
	var inbox = _main._hud.inbox
	var pressed: Array = []
	inbox.card_action.connect(func(id: String, index: int) -> void: pressed.append([id, index]))
	var asked: String = inbox.push("A question", "Body", [{"label": "No", "disabled": true, "tooltip": "why not"}, {"label": "Yes"}])
	var note: String = inbox.push("News", "Nothing asked")
	if InboxFiles.of(inbox, asked).is_empty():
		_fail("a card with answers is not a file")
	if not InboxFiles.of(inbox, note).is_empty():
		_fail("a plain note is a file")
	if InboxFiles.press(inbox, asked, 0) or not pressed.is_empty():
		_fail("a disabled answer was pressed through the door")
	if not InboxFiles.press(inbox, asked, 1) or pressed != [[asked, 1]]:
		_fail("an enabled answer did not go through the card's own signal: %s" % [pressed])
	if InboxFiles.press(inbox, asked, 2) or InboxFiles.press(inbox, asked, -1):
		_fail("an answer index outside the card's was pressed")
	# QA #333 T2: a body rewritten in place (a council vote moving on, a bill) is what the page reads.
	inbox.set_body(asked, "A newer body")
	if String(InboxFiles.of(inbox, asked).get("body", "")) != "A newer body":
		_fail("the file page still reads the body the card was pushed with, not the one it shows now")
	inbox.dismiss(asked)
	if InboxFiles.press(inbox, asked, 1) or not InboxFiles.of(inbox, asked).is_empty():
		_fail("a gone card is still a file, or can still be pressed")
	# THE LANE TRAP: a row in DECISIONS is a file for as long as it stands, and listing it does
	# not change what it is (a decision is never evicted; a note can be).
	var held: String = inbox.push("Held", "A protected row", [], null, true)
	if InboxFiles.of(inbox, held).is_empty() or inbox.lane_of(held) != inbox.DECISIONS:
		_fail("a protected decision row is not a file in the Decisions lane")
	inbox.dismiss(held)
	inbox.dismiss(note)


func _desk(ns, index: int, months_left: int) -> void:
	var ev = _main._loader.events[index]
	var entry := {"event_id": String(ev.id), "event_name": ev.event_name, "months_left": months_left, "severity": 1,
		"category": ev.category, "interrupt": false}
	ns.event_queue.append(entry)
	DeskCards.push(_main, ev, entry)


func _check_an_event_file() -> void:
	var ns = _main._state.player()
	var inbox = _main._hud.inbox
	ns.event_queue.clear()
	_desk(ns, 0, 3)
	var ev = _main._loader.events[0]
	var card := ""
	for id in _main._event_cards:
		if String(_main._event_cards[id]) == String(ev.id):
			card = String(id)
	var file := InboxFiles.of(inbox, card)
	if file.is_empty():
		_fail("the desk's event card is not a file")
		return
	var page := FileRead.describe(_main, file)
	if String(page.get("kind", "")) != "event":
		_fail("an event's file reads as '%s'" % page.get("kind", ""))
		return
	var choices: Array = page["choices"]
	if choices.size() != ev.choices.size():
		_fail("the page has %d choices for an event with %d" % [choices.size(), ev.choices.size()])
	var defaults := 0
	for i in choices.size():
		if bool(choices[i]["default"]):
			defaults += 1
			if not bool(ev.choices[i]["is_default"]):
				_fail("choice %d is marked as the default and is not" % i)
		if (choices[i]["tags"] as Array).is_empty():
			_fail("choice %d carries no tag: the page would not say what it costs" % i)
	if defaults != 1:
		_fail("%d choices are marked as the default; exactly one is" % defaults)
	var now := int(_main._state.year) * 12 + int(_main._state.month)
	var last := now + 3 - 1
	if int(page["by_month"]) != last:
		_fail("the deadline's month is %d, not now + months_left - 1 (%d)" % [int(page["by_month"]), last])
	var year := floori((last - 1) / 12.0)
	var month := (last - 1) % 12 + 1
	if String(page["by_text"]) != preload("res://src/ui/date_text.gd").day_month_year(_days(month, year), month, year):
		_fail("the deadline reads '%s', not the last day of %d/%d" % [page["by_text"], month, year])
	# The docked panel shows it, and the button's index IS the choice's index.
	FilesDriver.activated(_main, card)
	var view = FilesDriver.view_of(_main)
	if view == null or view.file_id() != card or not _main._windows.is_open("file"):
		_fail("a click on the event's card did not open its file")
		return
	view._rebuild()
	var buttons: Array[Button] = []
	_buttons(view, buttons)
	if buttons.size() != choices.size():
		_fail("the docked page has %d buttons for %d choices" % [buttons.size(), choices.size()])
		return
	var before: int = ns.event_queue.size()
	buttons[1].pressed.emit()
	if ns.event_queue.size() != before - 1:
		_fail("pressing the page's second button did not answer the event (the desk went %d -> %d)" % [before, ns.event_queue.size()])
	if ns.event_queue.any(func(e): return String(e["event_id"]) == String(ev.id)):
		_fail("the answered event is still on the desk")
	# A click on a plain note keeps the Dispatches window.
	var note: String = inbox.push("A note", "Just news")
	FilesDriver.activated(_main, note)
	if not _main._windows.is_open("events"):
		_fail("a click on a note no longer opens Dispatches")
	inbox.dismiss(note)


## QA #333 T1: a request's headline is its ask in words, never a raw id and never "none". Swept over every want
## of every person of the played nation, and the one the screenshot flags stage (a want with no target).
func _check_request_titles() -> void:
	var ns = _main._state.player()
	var loader = _main._loader
	var swept := 0
	for person in loader.people[String(ns.id)]:
		for want in person.wants:
			var request := {"object": String(want["object"]), "stance": String(want["stance"])}
			for key in want:
				request[key] = want[key]
			var title := FileRead.ask_title(loader, ns, request)
			swept += 1
			for bad in ["none", "prog_", "office:", ":", "_"]:
				if title.to_lower().contains(bad):
					_fail("%s's ask '%s' reads '%s': it shows a raw id or 'none'" % [person.id, want["object"], title])
			if title == "" or title.left(1) != title.left(1).to_upper():
				_fail("%s's ask reads '%s': empty or not capitalised" % [person.id, title])
	if swept < 20:
		_fail("only %d wants were swept" % swept)
	if FileRead.ask_title(loader, ns, {"object": "programme:none", "stance": "sponsor"}) != Strings.t("Asks to see you"):
		_fail("a want with no target does not read as the plain ask")
	if FileRead.ask_title(loader, ns, {"object": "programme:nothing_like_it", "stance": "oppose"}) != Strings.t("Asks to see you"):
		_fail("a programme the register cannot name shows its raw id")


## G5: a phone call spends the month's call, so the lane puts the request's card up again under a new id. Both pages
## that showed the old card go on showing the request.
func _check_a_re_put_request_keeps_its_page() -> void:
	var ns = _main._state.player()
	for person in _main._loader.people.get(String(ns.id), []):
		if not person.wants.is_empty() and String(person.id) != String(ns.head_of_state_person_id):
			Audiences._arrive(ns, person, person.wants[0], int(_main._state.year) * 12 + int(_main._state.month), [])
			break
	AudienceDriver.refresh(_main)
	var lane = AudienceDriver.lane_of(_main)
	if lane.request_ids().is_empty():
		_fail("premise: no request card for the re-put check")
		return
	var request_id := String(lane.request_ids()[0])
	var old: String = lane.card_of(request_id)
	var folder = _main._events_panel
	_main._windows.open("events")
	folder.select("file:" + old)
	var view = FilesDriver.view_of(_main)
	view.show_file(old)
	ns.phone_calls[String(Audiences.request(ns, request_id)["person_id"])] = int(_main._state.year) * 12 + int(_main._state.month)
	AudienceDriver.refresh(_main)
	if lane.card_of(request_id) == old:
		_fail("premise: a spent call did not put the card up again")
		return
	folder._dirty = true
	folder._process(0.0)
	var said := PackedStringArray()
	_texts(folder._page, said)
	if " ".join(said).contains(Strings.t("Answered.")):
		_fail("the folder says a waiting request is answered: %s" % [said])
	if folder.selected() != "file:" + lane.card_of(request_id):
		_fail("the folder does not follow the request's new card: %s" % folder.selected())
	_main._windows.open("file")
	view._rebuild()
	said = PackedStringArray()
	_texts(view, said)
	if " ".join(said).contains(Strings.t("Answered.")):
		_fail("the docked page says a waiting request is answered: %s" % [said])


func _check_a_gone_file() -> void:
	# A request on the desk beside the term's programme card (#400 pass 2, T4 and T9): its button reads
	# the person's name, as the folder's list does, and the programme card opens the Agenda.
	var ns = _main._state.player()
	for person in _main._loader.people.get(String(ns.id), []):
		if not person.wants.is_empty() and String(person.id) != String(ns.head_of_state_person_id):
			Audiences._arrive(ns, person, person.wants[0], int(_main._state.year) * 12 + int(_main._state.month), [])
			break
	AudienceDriver.refresh(_main)
	var view = FilesDriver.view_of(_main)
	_main._windows.open("file")
	view._rebuild()
	var texts := PackedStringArray()
	_texts(view, texts)
	if not " ".join(texts).contains(Strings.t("Answered.")):
		_fail("a file that is gone does not say so: %s" % [texts])
	# The void pass (c), the author's pick "Encore sur ton bureau": after an answer the page lists
	# what is still on the desk, one button per open file, and a press opens it here.
	var open_files: Array = InboxFiles.list(_main._hud.inbox)
	if open_files.is_empty():
		_fail("premise: no open file on the desk to list")
	elif not " ".join(texts).to_lower().contains(Strings.t("Still on your desk").to_lower()):
		_fail("an answered page does not say what is still on the desk: %s" % [texts])
	else:
		var listed: Array = view.find_children("*", "Button", true, false).filter(
				func(b) -> bool: return not (b as Node).is_queued_for_deletion())
		if listed.size() != open_files.size():
			_fail("an answered page lists %d files, the desk holds %d" % [listed.size(), open_files.size()])
		else:
			_check_desk_buttons(view, listed, open_files)
	view.show_file("card_gone")
	_main._hud.inbox.clear()
	view._rebuild()
	texts = PackedStringArray()
	_texts(view, texts)
	if not " ".join(texts).contains(Strings.t("Nothing else waits on your signature.")):
		_fail("an answered page with an empty desk does not say so: %s" % [texts])
	# A load rebinds every panel with setup(state, loader): the file the discarded game showed is gone with it
	# (test_audience_load and eight more suites broke on a different signature, which this pins by name).
	view.show_file("card_gone")
	view.setup(_main._state, _main._loader)
	if view.file_id() != "":
		_fail("a load left the docked page on the discarded game's file '%s'" % view.file_id())

	# A page built for {} directly: the empty state is one line, no buttons.
	var holder := Control.new()
	FileView.build(holder, {}, func(_i: int) -> void: pass)
	var buttons: Array[Button] = []
	_buttons(holder, buttons)
	if not buttons.is_empty():
		_fail("an empty page has buttons")


## G20 (blind play 11-28): beside cards headed by their label, the one with no `short` had no title at all.
func _check_every_option_keeps_its_title() -> void:
	var choice := func(words: String, short: String) -> Dictionary:
		return {"words": words, "short": short, "default": false, "tags": [], "note": "", "disabled": false, "tip": ""}
	for case in [[[choice.call("Open talks at once", "Talk"), choice.call("Clear the halls", "")], 1], [[choice.call("Yes", ""), choice.call("No", "")], 0]]:
		var holder := Control.new()
		FileView.build(holder, {"who": {}, "micro": "", "by_text": "", "title": "A matter", "situation": "", "choices": case[0]}, func(_i: int) -> void: pass)
		var texts := PackedStringArray()
		_texts(holder, texts)
		for option in case[0]:
			# A page where no option has a short label stays buttons alone: a head would only say the button twice.
			if texts.count(String(option["words"])) != case[1]:
				_fail("the option '%s' heads %d cards, expected %d: %s" % [option["words"], texts.count(String(option["words"])), case[1], texts])
		holder.free()


func _days(month: int, year: int) -> int:
	return preload("res://src/ui/date_text.gd").days_in(month, year)


func _buttons(node: Node, out: Array[Button]) -> void:
	if node is Button and (node as Button).get_parent() != null and not String((node as Button).text).is_empty() \
			and (node as Button).custom_minimum_size.x == FileView.BUTTON_WIDTH:
		out.append(node)
	for child in node.get_children():
		_buttons(child, out)


func _texts(node: Node, out: PackedStringArray) -> void:
	if node is Label:
		out.append((node as Label).text)
	elif node is RichTextLabel:
		out.append((node as RichTextLabel).get_parsed_text())
	for child in node.get_children():
		_texts(child, out)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_file_page: all checks passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	quit(1)
