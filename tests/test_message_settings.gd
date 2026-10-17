extends SceneTree

## Headless test: godot --headless --script res://tests/test_message_settings.gd
## Non-zero exit on any failure.
##
## V4.8c's two instruments. The REGISTER: every category has a band for every
## switch, the defaults follow severity (and pause sits at the author's Major+),
## and the file round-trips through the settings screen's own section. The
## CONTRACT: a category whose pause band an arrival does not meet keeps the clock
## running -- and its decision still cannot lapse unseen, because the lapse guard
## holds the clock in its last month. The lapse is driven through the machine's
## own countdown (Events._tick_countdowns), not a hand-set number, so a guard that
## fires one month late fails here exactly as it would in play.
##
## Loads the actual main scene: the pause lives in main.gd's arrival path.

const MessageSettings = preload("res://src/ui/message_settings.gd")
const Pending = preload("res://src/ui/pending.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const Events = preload("res://src/sim/events.gd")
const EventsK = preload("res://src/sim/events_constants.gd")

## A scratch file, never the player's user://settings.cfg.
const SCRATCH_PATH := "user://test_message_settings.cfg"

var _failures: Array[String] = []
var _main
var _settings
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)
	# In the tree before anything reads it: a Control outside it has not built.
	_settings = SettingsPanel.new()
	root.add_child(_settings)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the scene's _ready() run

	_check_register()
	_check_file_round_trip()
	_check_settings_grid()
	if _main._state == null or _main._loader == null:
		_fail("main.tscn did not produce a running game")
	else:
		_check_quiet_arrival_and_lapse_guard()
		_check_loud_arrival_pauses()
		_check_quiet_card_deadline_ages()
		_check_notify_band()
		_check_feed_band()
	_finish()
	return false


# --- the register ----------------------------------------------------------------

func _check_register() -> void:
	var reg := MessageSettings.defaults()
	if reg.size() != EventsK.CATEGORIES.size():
		_fail("register: %d categories, the book has %d" % [reg.size(), EventsK.CATEGORIES.size()])
	for category in EventsK.CATEGORIES:
		if not reg.has(category):
			_fail("register: no row for %s" % category)
			continue
		for switch in MessageSettings.SWITCHES:
			if not reg[category].has(switch):
				_fail("register: %s has no %s band" % [category, switch])
				continue
			var band := int(reg[category][switch])
			if band < EventsK.SEVERITY_MIN or band > MessageSettings.OFF:
				_fail("register: %s.%s = %d is not a band" % [category, switch, band])
			# Banded by severity, not by taste: every category sits at the
			# switch's one default.
			if band != int(MessageSettings.DEFAULTS[switch]):
				_fail("register: %s.%s default %d differs from the switch's band" % [category, switch, band])
	if MessageSettings.BAND_LABELS.size() != MessageSettings.OFF:
		_fail("register: %d band labels for %d bands" % [MessageSettings.BAND_LABELS.size(), MessageSettings.OFF])
	# The author's call, pinned: pause is Major+; everything else shows all.
	if int(MessageSettings.DEFAULTS["pause"]) != 2:
		_fail("register: the pause default moved off Major+ (author's call 2026-10-17)")
	for switch in ["notify", "feed", "popup"]:
		if int(MessageSettings.DEFAULTS[switch]) != EventsK.SEVERITY_MIN:
			_fail("register: %s no longer shows every severity by default" % switch)
	# allows(): the band is inclusive, OFF fires for nothing, empty reads as defaults.
	if MessageSettings.allows({}, "scandal", 1, "pause"):
		_fail("allows: a minor arrival meets the default pause band")
	if not MessageSettings.allows({}, "scandal", 2, "pause"):
		_fail("allows: a major arrival misses the default pause band")
	var off := {"scandal": {"popup": MessageSettings.OFF}}
	if MessageSettings.allows(off, "scandal", EventsK.SEVERITY_MAX, "popup"):
		_fail("allows: OFF let a critical through")


func _check_file_round_trip() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_PATH))
	if MessageSettings.load_from(SCRATCH_PATH) != MessageSettings.defaults():
		_fail("file: an absent file did not read as the defaults")
	# Another section must survive a save into the same file.
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "enabled", false)
	cfg.save(SCRATCH_PATH)
	var reg := MessageSettings.defaults()
	reg["disaster"]["pause"] = 1
	reg["commodity"]["feed"] = MessageSettings.OFF
	MessageSettings.save_to(reg, SCRATCH_PATH)
	if MessageSettings.load_from(SCRATCH_PATH) != reg:
		_fail("file: the register did not round-trip")
	cfg = ConfigFile.new()
	cfg.load(SCRATCH_PATH)
	if bool(cfg.get_value("audio", "enabled", true)):
		_fail("file: saving the register lost the [audio] section")
	# A hand-edited value outside the bands is clamped, not trusted.
	cfg.set_value(MessageSettings.SECTION, "scandal.popup", 99)
	cfg.save(SCRATCH_PATH)
	if int(MessageSettings.load_from(SCRATCH_PATH)["scandal"]["popup"]) != MessageSettings.OFF:
		_fail("file: an out-of-band value was not clamped to OFF")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_PATH))


## The screen draws the register it will save: one picker per category per
## switch, and each picker's index is its stored band minus one. Read-only over
## the player's real file -- this compares, it never writes.
func _check_settings_grid() -> void:
	var drawn: Dictionary = _settings.messages_from_controls()
	var count := 0
	for category in drawn.keys():
		count += (drawn[category] as Dictionary).size()
	var want := EventsK.CATEGORIES.size() * MessageSettings.SWITCHES.size()
	if count != want:
		_fail("settings grid: %d pickers, the register has %d cells" % [count, want])
	if drawn != MessageSettings.load_from(SettingsPanel.CONFIG_PATH):
		_fail("settings grid: the pickers do not show the stored bands")


# --- the contract ----------------------------------------------------------------

## A non-interrupt event with at least two months to answer, so there is a month
## in which it is quiet and a month in which the guard must catch it.
func _quiet_candidate():
	for candidate in _main._loader.events:
		if not bool(candidate.interrupt) and int(candidate.respond_months) >= 2:
			return candidate
	return null


func _reset_desk() -> void:
	var ns = _main._state.player()
	ns.event_queue.clear()
	_main._unseen_events.clear()
	for leftover in _main._event_cards.keys().duplicate():
		_main._hud.message_stack.dismiss(leftover)
	_main._event_cards.clear()
	_main._paused_for_decision = false
	_main._paused_for_programme = false
	_main._clock.paused = false


func _month_index() -> int:
	return Events._absolute_month(int(_main._state.year), int(_main._state.month))


func _desk(ns) -> Dictionary:
	var out := {}
	for entry in ns.event_queue:
		out[String(entry.get("event_id", ""))] = true
	return out


func _card_for(event_id: String) -> String:
	for id in _main._event_cards:
		if String(_main._event_cards[id]) == event_id:
			return String(id)
	return ""


func _check_quiet_arrival_and_lapse_guard() -> void:
	var ev = _quiet_candidate()
	if ev == null:
		_fail("no non-interrupt event with two months to answer to stage")
		return
	var ns = _main._state.player()
	var event_id := String(ev.id)
	_reset_desk()
	# The category silenced on both arrival switches, at every severity.
	var reg := MessageSettings.defaults()
	reg[ev.category]["pause"] = MessageSettings.OFF
	reg[ev.category]["popup"] = MessageSettings.OFF
	_main._messages = reg

	Events.announce(ns, ev, _month_index(), Events.region_names(ns, _main._loader))
	_main._card_events(_main._state.year, _main._state.month, {}, {})
	if _main._clock.paused:
		_fail("pause OFF: the arrival stopped the clock")
	if not _main._unseen_events.has(event_id):
		_fail("pause OFF: the arrival is not in the unseen set -- the guard cannot see it")
	elif bool(_main._unseen_events[event_id]):
		_fail("pause OFF: the arrival entered the unseen set holding the clock")
	if _card_for(event_id) != "":
		_fail("popup OFF: the arrival pushed a card")

	# Now let the machine's own countdown run, month by month, with the game's
	# rule that a paused clock ticks no month. The decision must never leave the
	# desk by default: the guard stops the clock first.
	var guarded := false
	for _step in range(int(ev.respond_months) + 1):
		if _main._clock.paused:
			guarded = true
			break
		var before := _desk(ns)
		Events._tick_countdowns(_main._state, ns, _main._loader, _month_index())
		_main._card_events(_main._state.year, _main._state.month, before, {})
		if not _desk(ns).has(event_id):
			_fail("LAPSE: the quiet decision was decided by default with the clock running")
			return
	if not guarded:
		_fail("lapse guard: the clock never stopped for the quiet decision")
		return
	var left := -1
	for entry in ns.event_queue:
		if String(entry.get("event_id", "")) == event_id:
			left = int(entry.get("months_left", 0))
	if left != 1:
		_fail("lapse guard: fired with %d months left, not in the last month" % left)
	if not bool(_main._unseen_events.get(event_id, false)):
		_fail("lapse guard: the decision does not hold the clock it stopped")
	var card_id := _card_for(event_id)
	if card_id == "":
		_fail("lapse guard: the clock stopped with no card saying why (popup was OFF)")
		return
	# Answering through the guard's card releases the clock: the card is the
	# arrival's card, wired to the same door.
	_main._hud.message_stack.card_action.emit(card_id, 0)
	if _main._clock.paused:
		_fail("lapse guard: answering the guard's card left the clock stopped")
	if _main._unseen_events.has(event_id):
		_fail("lapse guard: the answered decision is still unseen")
	_reset_desk()


func _check_loud_arrival_pauses() -> void:
	var ev = _quiet_candidate()
	if ev == null:
		return
	var ns = _main._state.player()
	_reset_desk()
	# Pause at All for this category: the arrival stops the world as it always did.
	var reg := MessageSettings.defaults()
	reg[ev.category]["pause"] = EventsK.SEVERITY_MIN
	_main._messages = reg
	Events.announce(ns, ev, _month_index(), Events.region_names(ns, _main._loader))
	_main._card_events(_main._state.year, _main._state.month, {}, {})
	if not _main._clock.paused or not bool(_main._unseen_events.get(String(ev.id), false)):
		_fail("pause ALL: the arrival did not stop the clock")
	if _card_for(String(ev.id)) == "":
		_fail("popup default: the arrival pushed no card")
	_reset_desk()


## Review pass 2: a quiet arrival's card stays up while the clock runs, so its
## "N months to answer" must follow the desk, month by month -- and the guard's
## last month must read "1 month", not the arrival's number.
func _check_quiet_card_deadline_ages() -> void:
	var ev = _quiet_candidate()
	if ev == null:
		return
	var ns = _main._state.player()
	var event_id := String(ev.id)
	_reset_desk()
	var reg := MessageSettings.defaults()
	reg[ev.category]["pause"] = MessageSettings.OFF
	_main._messages = reg
	Events.announce(ns, ev, _month_index(), Events.region_names(ns, _main._loader))
	_main._card_events(_main._state.year, _main._state.month, {}, {})
	var card_id := _card_for(event_id)
	if card_id == "":
		_fail("deadline: the quiet arrival with popup on pushed no card")
		return
	while not _main._clock.paused:
		var before := _desk(ns)
		Events._tick_countdowns(_main._state, ns, _main._loader, _month_index())
		_main._card_events(_main._state.year, _main._state.month, before, {})
		if not _desk(ns).has(event_id):
			_fail("deadline: the quiet decision lapsed")
			return
		var left := -1
		for entry in ns.event_queue:
			if String(entry.get("event_id", "")) == event_id:
				left = int(entry.get("months_left", 0))
		var want := "You have %d %s to answer." % [left, "month" if left == 1 else "months"]
		var body: String = _main._hud.message_stack._bodies[card_id].text
		if not body.ends_with(want):
			_fail("deadline: the card reads '%s' with %d months left" % [body, left])
			break
	_reset_desk()


func _check_notify_band() -> void:
	var ev = _quiet_candidate()
	if ev == null:
		return
	var ns = _main._state.player()
	_reset_desk()
	Events.announce(ns, ev, _month_index(), Events.region_names(ns, _main._loader))
	var state = _main._state
	var loader = _main._loader
	if not Pending.window_ids(state, loader, {}).has("events"):
		_fail("notify default: a crisis on the desk lit no mark")
	var reg := MessageSettings.defaults()
	reg[ev.category]["notify"] = MessageSettings.OFF
	if Pending.window_ids(state, loader, reg).has("events"):
		_fail("notify OFF: the mark still lit for a crisis with months to run")
	ns.event_queue[0]["months_left"] = 1
	if not Pending.window_ids(state, loader, reg).has("events"):
		_fail("notify OFF: a decision in its last month lit no mark")
	_reset_desk()


func _check_feed_band() -> void:
	var ev = _quiet_candidate()
	if ev == null:
		return
	var ns = _main._state.player()
	var panel = _main._events_panel
	var history_before: Array = ns.event_history.duplicate(true)
	ns.event_history.append({
		"event_id": ev.id, "event_name": ev.event_name, "choice_id": "",
		"choice_label": "x", "defaulted": false, "year": int(_main._state.year),
		"month": int(_main._state.month), "category": ev.category,
	})
	var reg := MessageSettings.defaults()
	reg[ev.category]["feed"] = MessageSettings.OFF
	panel.set_messages(reg)
	panel._refresh()
	if not _panel_says(panel, "hidden by your message settings"):
		_fail("feed OFF: the ledger hid a record without saying so")
	panel.set_messages({})
	panel._refresh()
	if _panel_says(panel, "hidden by your message settings"):
		_fail("feed default: the ledger hid a record")
	ns.event_history = history_before
	panel._refresh()


func _panel_says(panel: Node, text: String) -> bool:
	var stack: Array = [panel]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.is_queued_for_deletion():
			continue  # _refresh() frees the old rows at frame end
		if node is Label and String((node as Label).text).contains(text):
			return true
		stack.append_array(node.get_children())
	return false


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_message_settings: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
