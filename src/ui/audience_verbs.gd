extends VBoxContainer

## The audience's verbs -- V5.2b b2: the six levers and the topics, each with what
## it needs chosen BEFORE the click (bargain's currency, the promise's date, the
## gossip's third person) and what it will cost shown beside it, so nothing is
## paid that was not read first. The odds are Levers.offered()'s range, never
## computed here (B4); a lever or a choice the sim refuses stays on screen,
## disabled, its reason on the hover.
##
## It writes nothing: a click emits the verb and its args, and the wiring calls
## Levers.attempt() / talk().

signal attempted(lever: String, args: Dictionary)
signal talked(topic: String, args: Dictionary)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Words = preload("res://src/ui/lever_words.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const President = preload("res://src/sim/president.gd")

var _levers: GridContainer
var _attempts: Label
var _talk_heading: Label
var _topics: HFlowContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_levers = GridContainer.new()
	_levers.columns = 3
	_levers.add_theme_constant_override("h_separation", 16)
	add_child(_levers)
	_attempts = Label.new()
	_attempts.theme_type_variation = UiTheme.CAPTION
	add_child(_attempts)
	_talk_heading = PanelKit.heading(self, tr("Or talk"))
	_topics = PanelKit.buttons(self)


## `offered` / `topics`: Levers' rows (or Phone.options()'s, the same shape).
## `choices`: {now: the absolute month a promise counts from, people: [{id, name,
## know, key}] a gossip may name, quiet: no attempts line, given_due: a promise
## already given on this want (given_due() below), 0 for none}.
func show_verbs(offered: Array, topics: Array, attempts_left: int, choices: Dictionary) -> void:
	for box in [_levers, _topics]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	for row in offered:
		_lever_row(row, int(choices.get("now", 0)), int(choices.get("given_due", 0)))
	# The phone says its one try itself (`quiet`, phone_dialog.gd).
	_attempts.visible = not bool(choices.get("quiet", false))
	# No levers offered at all (none fit): the audience is heard, not argued --
	# saying "no attempts left" would be a lie.
	if offered.is_empty():
		_attempts.text = tr("Hear them out, then end the audience.")
	elif attempts_left > 0:
		_attempts.text = tr_n("%d attempt left", "%d attempts left", attempts_left) % attempts_left
	else:
		_attempts.text = tr("No attempts left: end the audience.")
	_talk_heading.visible = not topics.is_empty()
	for row in topics:
		_topic(row, choices.get("people", []))


## The month a promise already given to `pid` on `object` falls due, or 0 -- the
## `given_due` choice both views pass: the greyed Promise row shows it rather than
## the picker's default a year out (QA's pre-gate B RECORD 7: "due DEC 2027" after
## a word given for MAR 2027).
static func given_due(ns, pid: String, object: String) -> int:
	for row in President.commitments_with(ns, pid):
		if String(row["kind"]) == "promise" and String(row["object"]) == object:
			return int(row["due_month"])
	return 0


func lever_button(lever: String) -> Button:
	return _levers.find_child("Lever_" + lever, true, false) as Button


func topic_button(topic: String) -> Button:
	return _topics.find_child("Topic_" + topic, true, false) as Button


func _lever_row(row: Dictionary, now: int, given: int) -> void:
	var lever := String(row["lever"])
	var cell := HBoxContainer.new()
	var button := PanelKit.sized(Button.new())
	button.name = "Lever_" + lever
	button.text = Words.lever(lever)
	button.disabled = not bool(row.get("offered", false))
	button.tooltip_text = Words.reason(String(row.get("why_not", "")))
	cell.add_child(button)
	var odds := Label.new()
	# A lever the person cannot be moved by at all (no friendship to appeal to) has
	# no odds to range over: a dash, not "0–0 %".
	var none := not bool(row.get("offered", false)) and float(row.get("odds_hi", 0.0)) <= 0.0
	odds.text = "—" if none else Words.odds_text(float(row.get("odds_lo", 0.0)), float(row.get("odds_hi", 0.0)))
	var spend := Label.new()
	spend.theme_type_variation = UiTheme.CAPTION
	spend.autowrap_mode = TextServer.AUTOWRAP_WORD
	spend.custom_minimum_size.x = 300
	spend.text = Words.spends_text(row.get("spends", {}))
	var args := {}
	match lever:
		"bargain":
			cell.add_child(_currency_pick(row, spend, args))
		"promise_date":
			cell.add_child(_date_pick(row, now, spend, args, given))
	# A choice beside a lever that cannot be tried is down with it.
	for pick in cell.get_children():
		if pick is OptionButton:
			pick.disabled = button.disabled
	button.pressed.connect(func() -> void: attempted.emit(lever, args.duplicate()))
	_levers.add_child(cell)
	_levers.add_child(odds)
	_levers.add_child(spend)


## Bargain pays one currency: a favour (rapport) or a vote trade (an IOU). Aid
## is listed and refused with the sim's reason until a later block builds it.
func _currency_pick(row: Dictionary, spend: Label, args: Dictionary) -> OptionButton:
	var pick := OptionButton.new()
	pick.name = "Currency"
	var rows: Array = row.get("currencies", [])
	if rows.is_empty():
		var spends: Dictionary = row.get("spends", {})
		rows = [{"currency": LK.CURRENCY_FAVOUR, "offered": true, "spends": {"rapport": spends.get("rapport", 0.0)}},
			{"currency": LK.CURRENCY_VOTE_TRADE, "offered": true, "spends": {"iou": 1.0}}]
	for c in rows:
		pick.add_item(Words.currency(String(c["currency"])))
		var i := pick.item_count - 1
		pick.set_item_metadata(i, c)
		pick.set_item_disabled(i, not bool(c.get("offered", true)))
		pick.set_item_tooltip(i, Words.reason(String(c.get("why_not", ""))))
	var chosen := func(i: int) -> void:
		var c: Dictionary = pick.get_item_metadata(i)
		args["currency"] = String(c["currency"])
		spend.text = Words.spends_text(c.get("spends", {}))
	pick.item_selected.connect(chosen)
	# Selected outright: an OptionButton left to itself showed the last item (the
	# refused aid) while the args and the cost were the favour's.
	pick.select(0)
	chosen.call(0)
	return pick


## The promise's date, inside the window the sim takes (the row's `dates`, or the
## constants from today until the row carries them); a year out by default. A
## word already given (`given`, the row refused) shows its own date instead:
## the picker's window has moved on with today, so the date goes in by name.
func _date_pick(row: Dictionary, now: int, spend: Label, args: Dictionary, given := 0) -> OptionButton:
	var spends: Dictionary = row.get("spends", {})
	var window: Dictionary = row.get("dates", {"earliest": now + LK.PROMISE_MIN_MONTHS, "latest": now + LK.PROMISE_MAX_MONTHS})
	var pick := OptionButton.new()
	pick.name = "Due"
	for due in range(int(window["earliest"]), int(window["latest"]) + 1):
		pick.add_item(Words.when(due))
		pick.set_item_metadata(pick.item_count - 1, due)
	var chosen := func(i: int) -> void:
		args["due_month"] = int(pick.get_item_metadata(i))
		spend.text = Words.spends_text(spends, int(args["due_month"]))
	pick.item_selected.connect(chosen)
	if given > 0 and not bool(row.get("offered", false)):
		pick.clear()
		pick.add_item(Words.when(given))
		pick.set_item_metadata(0, given)
		pick.select(0)
		chosen.call(0)
		return pick
	var year_out := clampi(now + 12 - int(window["earliest"]), 0, pick.item_count - 1)
	pick.select(year_out)
	chosen.call(year_out)
	return pick


func _topic(row: Dictionary, people: Array) -> void:
	var topic := String(row["topic"])
	var button := Button.new()
	button.name = "Topic_" + topic
	button.text = Words.topic(topic)
	button.disabled = not bool(row.get("offered", true))
	button.tooltip_text = Words.reason(String(row.get("why_not", "")))
	var args := {}
	_topics.add_child(button)
	if topic == "gossip":
		var pick := OptionButton.new()
		pick.name = "About"
		for p in people:
			pick.add_item(String(p["name"]))  # i18n: row-ok a person's shown name, from the loader
			pick.set_item_metadata(pick.item_count - 1, String(p["id"]))
		var chosen := func(i: int) -> void: args["about"] = String(pick.get_item_metadata(i))
		pick.item_selected.connect(chosen)
		if pick.item_count > 0:
			chosen.call(0)
		else:
			button.disabled = true
			button.tooltip_text = tr("You know no one else to talk about.")
		pick.disabled = button.disabled
		_topics.add_child(pick)
	button.pressed.connect(func() -> void: talked.emit(topic, args.duplicate()))
