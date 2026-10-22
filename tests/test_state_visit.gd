extends SceneTree

## Headless test: godot --headless --script res://tests/test_state_visit.gd
## Non-zero exit on any failure.
##
## V5.1-d1b2, G13 of the play gate: "state visit est toujours cassé". Nothing in
## the machine was broken; the author named four things that read as broken:
##   (b) two ways to visit, behaving differently: the Diplomacy row now opens the
##       Diary's booking form on that visit (partner, act, travel, the earliest open
##       day offered); the player picks the day -- an invalid one reads as such --
##       and books it there; closing the form books nothing; the row then says when
##       ("on ne peut pas choisir la date dans l'agenda", the author on the first build);
##   (c) a greyed-out row with its reason only on hover: a cooldown, a partner's
##       refusal or a booking in hand is a visible line under the row;
##   (d) "Agreed." for a visit: a kept visit reads "Received in <capital>.";
##   (a) a note every month for the AI's visits to the player: one rolling note a
##       year, replaced rather than stacked. (The AI's behaviour is V5.2/V5.4's.)

const Calendar = preload("res://src/sim/calendar.gd")
const RK = preload("res://src/core/relations.gd")
const DateText = preload("res://src/ui/date_text.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main._clock.set_process(false)
		_main._paused_for_programme = false
		_main._on_nation_clicked("DEU")
	elif _frame == 5:
		_check_the_row_books_a_visit()
		_check_a_kept_visit_reads_right()
		_check_visits_to_you_roll()
		_check_a_hosted_visit_says_until_when()
		_finish()
		return true
	return false


func _visit():
	for a in _main._loader.diplomatic_actions:
		if a.opens_meeting:
			return a
	return null


func _check_the_row_books_a_visit() -> void:
	var state = _main._state
	var panel = _main._nation_panel
	var diary = _main._calendar_panel
	var visit = _visit()
	var before: float = float(state.relations.get(RK.key("FRA", "DEU"), 0.0))

	# Cancel books nothing: the form opens, and is closed. A refresh passes first --
	# the open's own, or a day ticking -- and must not rebuild the form over the visit.
	panel._on_act(visit)
	diary._process(0.0)
	diary.mark_dirty()
	diary._process(0.0)
	if not _main._windows.is_open("calendar"):
		_fail("Book on the Diplomacy row did not open the Diary's form")
		return
	if diary._selected_subject() != "DEU" or String(diary._act_pick.get_item_metadata(diary._act_pick.selected)) != String(visit.id):
		_fail("the Diary's form did not open on the visit to Germany")
	if not _booked(visit).is_empty():
		_fail("opening the form booked the visit before the player picked a day")
	_main._windows.close_all()
	if not _booked(visit).is_empty():
		_fail("closing the form booked the visit")

	# The default is the earliest open day; an invalid day reads as one.
	_main._on_nation_clicked("DEU")
	panel._on_act(visit)
	diary._process(0.0)
	var first: Dictionary = diary._entry_from_form()
	if not Calendar.can_book(state, first):
		_fail("the form's default day is not an open one: %s" % Calendar.refusal_reason(state, first))
	diary._month_pick.selected = 0
	diary._clamp_day_spin()
	diary._day_spin.value = int(state.day)
	if not diary._book_button.disabled or not String(diary._status.text).contains("cannot be booked"):
		_fail("today, an invalid day, did not read as one (Book %s, '%s')" % [
			"held" if diary._book_button.disabled else "live", diary._status.text])

	# A later day the player picks is the day booked.
	diary._month_pick.selected = 1
	diary._clamp_day_spin()
	diary._day_spin.value = 15
	# QA on #70 (TAKE 3): the refusal goes once the day is valid...
	if String(diary._status.text).contains("cannot be booked") or diary._book_button.disabled:
		_fail("a valid day kept the refusal line (Book %s, '%s')" % ["held" if diary._book_button.disabled else "live", diary._status.text])
	diary._on_book()
	# ...and a booking's confirmation stands over the refresh that follows it.
	diary._process(0.0)
	if not String(diary._status.text).begins_with("Booked:"):
		_fail("a successful booking reads '%s', not its confirmation" % diary._status.text)
	var booked: Dictionary = _booked(visit)
	if booked.is_empty():
		_fail("Book in the Diary's form booked nothing")
		return
	var next_month: int = int(state.month) % 12 + 1
	if int(booked["day"]) != 15 or int(booked["month"]) != next_month:
		_fail("the picked day was not the day booked: %d/%d" % [int(booked["day"]), int(booked["month"])])
	if int(booked.get("travel_days", 0)) <= 0:
		_fail("the booked visit carries no travel days")
	if float(state.relations.get(RK.key("FRA", "DEU"), 0.0)) != before:
		_fail("the row ran the visit at once instead of booking it")
	_main._windows.close_all()
	_main._on_nation_clicked("DEU")
	panel.mark_dirty()
	panel._process(0.0)
	var text := _text_of(panel)
	if not text.contains("Booked for"):
		_fail("the row does not say when the visit happens: %s" % text)


func _booked(visit) -> Dictionary:
	for e in Calendar.booked(_main._state):
		if String(e.get("action_id", "")) == String(visit.id) and String(e.get("target_id", "")) == "DEU":
			return e
	return {}


func _check_a_kept_visit_reads_right() -> void:
	var inbox = _main._hud.inbox
	var cards: Array = inbox._cards.keys()
	var clock = _main._clock
	for _i in range(75):
		clock.paused = false
		clock.advance_one_day()
		if Calendar.booked(_main._state).is_empty():
			break
	var capital: String = _main._loader.nations["DEU"].capital
	var seen := false
	for id in inbox._cards:
		if cards.has(id):
			continue
		var text := _text_of(inbox._cards[id])
		if text.contains("Received in %s." % capital):
			seen = true
		if text.contains("Agreed."):
			_fail("a visit still reads 'Agreed.': %s" % text)
	if not seen:
		_fail("the kept visit's card does not read 'Received in %s.'" % capital)
	# (c) the row, now on its cooldown, says so under it.
	# The kept visit opened its summit, which put the Diplomacy tab away.
	_main._windows.close_all()
	_main._on_nation_clicked("DEU")
	var panel = _main._nation_panel
	panel.mark_dirty()
	panel._process(0.0)
	if not _text_of(panel).contains("Cooldown: available again in"):
		_fail("the greyed visit row does not show its cooldown as a line")


func _check_visits_to_you_roll() -> void:
	var state = _main._state
	var news = _main._world_news
	var inbox = _main._hud.inbox
	var visit = _visit()
	var before: int = inbox.lane_count(inbox.NOTES)
	for month_actor in [[1, "DEU"], [2, "AUT"], [3, "ITA"]]:
		# Newest first, as diplomacy.gd records them.
		state.foreign_acts.push_front({
			"year": int(state.year), "month": int(month_actor[0]), "actor_id": String(month_actor[1]),
			"target_id": state.player_nation_id, "action_id": String(visit.id),
			"action_name": visit.action_name, "reason": "",
		})
		news.card_foreign_acts(int(state.year), int(month_actor[0]))
	var rolling := 0
	var last := ""
	for id in inbox._cards:
		var text := _text_of(inbox._cards[id])
		if text.to_lower().contains("visits to you"):
			rolling += 1
			last = inbox._bodies[id].get_parsed_text()
	if rolling != 1:
		_fail("visits to the player made %d notes in three months, not one rolling note" % rolling)
	elif not (last.contains("Germany") and last.contains("Austria") and last.contains("Italy")):
		_fail("the rolling note does not keep the year's visitors: %s" % last.replace("
", " | "))
	# QA on #70 (TAKE 2): a load is a different game -- its tally starts afresh, not
	# on top of the discarded game's visitors. setup() is what a load runs.
	news.setup(state, _main._loader, inbox)
	state.foreign_acts.push_front({
		"year": int(state.year), "month": 4, "actor_id": "ESP",
		"target_id": state.player_nation_id, "action_id": String(visit.id),
		"action_name": visit.action_name, "reason": "",
	})
	news.card_foreign_acts(int(state.year), 4)
	var newest := ""
	for id in inbox._cards:
		if _text_of(inbox._cards[id]).to_lower().contains("visits to you"):
			newest = inbox._bodies[id].get_parsed_text()
	if newest.contains("Germany") or not newest.begins_with("1 visit"):
		_fail("the tally carried the discarded game's visitors across a load: %s" % newest)


## V5.1-d2, the host rule's reason line (#74; author: "Oui, pour tous"): a nation
## that received a state visit within its host interval is offered none, and the
## disabled row says from when it can be -- not the generic "conditions not met",
## which the row hides.
func _check_a_hosted_visit_says_until_when() -> void:
	var state = _main._state
	var panel = _main._nation_panel
	var visit = _visit()
	var host = state.nations.get("ITA")
	if host == null or visit.host_interval_months <= 0:
		_fail("premise: Italy on the roster and the visit carrying a host interval")
		return
	host.diplo_hosted_months[String(visit.id)] = 4
	var at: int = int(state.year) * 12 + int(state.month) - 1 + 4
	var expected: String = "Italy receives another from %s." % DateText.day_month_year(1, at % 12 + 1, at / 12)
	_main._windows.close_all()
	_main._on_nation_clicked("ITA")
	panel.mark_dirty()
	panel._process(0.0)
	var text := _text_of(panel)
	if not text.contains(expected):
		_fail("a hosted visit's row does not say from when: wanted '%s' in %s" % [expected, text])
	host.diplo_hosted_months.erase(String(visit.id))


func _text_of(node: Node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	elif node is RichTextLabel:
		out += node.get_parsed_text() + "\n"
	for child in node.get_children():
		out += _text_of(child)
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_state_visit: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
