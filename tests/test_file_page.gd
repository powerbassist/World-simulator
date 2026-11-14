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
##   - the `short` label: optional, at most SHORT_MAX characters, absent reads as no short.

const GameEvent = preload("res://src/core/event.gd")
const EconomyK = preload("res://src/sim/economy_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const DeskCards = preload("res://src/ui/desk_cards.gd")
const EffectTags = preload("res://src/ui/effect_tags.gd")
const FileRead = preload("res://src/ui/file_read.gd")
const FileView = preload("res://src/ui/file_view.gd")
const FilesDriver = preload("res://src/ui/files_driver.gd")
const InboxFiles = preload("res://src/ui/inbox_files.gd")
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
	_check_a_gone_file()
	_finish()
	return true


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
	var ev = GameEvent.from_dict(raw.duplicate(true), "x.json", errs, EconomyK.TAX_KEYS, EconomyK.SPENDING_KEYS, OpinionK.BLOC_KEYS,
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
	GameEvent.from_dict(long_raw, "x.json", errs2, EconomyK.TAX_KEYS, EconomyK.SPENDING_KEYS, OpinionK.BLOC_KEYS, EconomyK.SECTOR_TREND.keys())
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


func _check_a_gone_file() -> void:
	var view = FilesDriver.view_of(_main)
	_main._windows.open("file")
	view._rebuild()
	var texts := PackedStringArray()
	_texts(view, texts)
	if not " ".join(texts).contains(Strings.t("This file has been answered.")):
		_fail("a file that is gone does not say so: %s" % [texts])
	# A page built for {} directly: the empty state is one line, no buttons.
	var holder := Control.new()
	FileView.build(holder, {}, func(_i: int) -> void: pass)
	var buttons: Array[Button] = []
	_buttons(holder, buttons)
	if not buttons.is_empty():
		_fail("an empty page has buttons")


func _days(month: int, year: int) -> int:
	return preload("res://src/ui/date_text.gd").days_in(month, year)


func _buttons(node: Node, out: Array[Button]) -> void:
	if node is Button and (node as Button).get_parent() != null and not String((node as Button).text).is_empty() and (node as Button).focus_mode == Control.FOCUS_NONE \
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
