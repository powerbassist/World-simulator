extends RefCounted

## The desk's cards -- V5.1-d2, moved out of main.gd to close its total-lines
## exception (AGENTS.md's size ratchet). What arrived on the desk this month, what
## the clock decided when nobody answered, and the lapse guard that holds the clock
## for a quiet arrival's last month. Static over main.gd's own registers
## (_event_cards, _unseen_events) and holds, the way hold_reason.gd reads them:
## the registers stay where the clock doors and the tests read them.

const Events = preload("res://src/sim/events.gd")
const EffectsLedger = preload("res://src/ui/effects_ledger.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Strings = preload("res://src/ui/strings.gd")
const MessageSettings = preload("res://src/ui/message_settings.gd")
const EventArt = preload("res://src/ui/event_art.gd")
const Sound = preload("res://src/ui/sound.gd")


## V1.8. What arrived on the desk this month, and what the clock decided when the
## player said nothing. The fifth caller of inbox.push() and the FIRST EVER
## CONSUMER of its card_activated signal, which U5a emitted and connected to nothing.
##
## U5a's call 3 said the column ships as furniture because the thing that fills it is
## events, and that "V1.8 adds calls rather than a layout". It held: nothing on screen
## moved to make room, and the one piece of machinery this needed -- a card the player
## can click through to the decision -- was already there waiting.
##
## Two cards and they are opposite in kind. An ARRIVAL is a question, and clicking it
## opens the window where it is answered. A DEFAULT is a thing that already happened to
## the player's government with no button pressed -- _card_appointment()'s class exactly,
## and the sharper case, because with an appointment the player at least booked it.
static func card_events(main, year: int, month: int, desk_before: Dictionary, before: Dictionary) -> void:
	if main._hud == null or main._hud.inbox == null or main._state == null:
		return
	var ns = main._state.player()
	if ns == null:
		return

	# What LEFT the desk this month: ids that were on it before the tick and are
	# not now. Each is a resolution, and each earns its own card -- two crises the
	# clock answered in one month is twice the news, not the same news twice.
	var after := {}
	for entry in ns.event_queue:
		after[String(entry.get("event_id", ""))] = true
	var defaulted_names: Array[String] = []
	for event_id in desk_before.keys():
		if after.has(event_id):
			continue
		# The unseen set's first door, and the invariant's desk half: an id that
		# has left the desk is not unseen, whether it left by the machine's own
		# default (_tick_countdowns answered it a moment ago), the player's card
		# answer or a Dispatches answer -- and its arrival card goes with it.
		# An erase of main._unseen_events missed here used to strand the id and hold
		# the clock past every later answer; a missing card purge left decision
		# buttons with no event to answer.
		dismiss(main, event_id)
		main._unseen_events.erase(event_id)
		var record := {}
		for row in ns.event_history:
			if String(row.get("event_id", "")) == event_id:
				record = row
				break
		if record.is_empty():
			continue
		if not bool(record.get("defaulted", false)) or int(record.get("year", 0)) != year or int(record.get("month", 0)) != month:
			continue
		# A sited crisis names its place here too: this card and the Dispatches
		# ledger print the same record, and two readouts of one record that
		# disagree is the failure class this column keeps catching.
		var named := Strings.record_event_name(record)
		var where := String(record.get("region_name", ""))
		if where != "":
			named = "%s — %s" % [named, where]
		main._hud.inbox.push(Strings.t("Decided for you"),
			Strings.t("%s. Nobody answered, so it went the way it was always going to: %s.") % [named, Strings.record_choice_label(record)])
		defaulted_names.append(Strings.record_event_name(record))

	# The delta is queued HERE and not at the choice, because this is the one case
	# where the player made no decision -- U4's baseline still belongs against it,
	# or a budget that moved by default moves for no reason the ledger names. ONE
	# entry for the whole tick: every departure shares the same pre-tick snapshot,
	# so a queue entry per default would each claim the joint movement of all of
	# them (the cards stay one per event -- only the ledger line is merged).
	if not defaulted_names.is_empty():
		main._queue_effect("; ".join(defaulted_names), before, true)

	# What ARRIVED: ids on the desk now that were not before. Each gets its own
	# decision card, answering its own row.
	# V4.9c: and ONE sting for the month, at the worst severity that arrived --
	# two crises in one tick are one piece of news to the ear, and two stings on
	# one frame would only be louder, not clearer. Gated on NOTIFY (author's
	# call, 2026-10-17): the sting is a notification, so a category the player
	# has told not to notify stays silent too.
	var sting_severity := 0
	for entry in ns.event_queue:
		var event_id := String(entry.get("event_id", ""))
		if desk_before.has(event_id):
			continue
		var ev = Events.event_by_id(main._loader, event_id)
		if ev == null:
			continue
		# A decision the player has not seen must not expire behind their back:
		# "3 months to answer" at speed 3 is thirteen seconds, and both playtest
		# runs produced "Decided for you" records no player answered (2026-09-05).
		# Arrival pauses; the interrupt flag (V2.4b) still opens Dispatches on
		# top -- non-modal, per events-model's argument, but the clock waits
		# until everything unseen has been answered.
		# V4.8c: arrival pauses when the category's PAUSE band says so (default
		# Major+). A quiet arrival is still unseen -- it enters the set as false,
		# and _guard_lapses() holds the clock for it in its last month, so the
		# contract above is kept by name rather than by the arrival pause.
		var severity := int(entry.get("severity", 1))
		# An interrupt ignores the register entirely (message_settings.gd's
		# header; pending.gd's notify read does the same): the content says
		# "until answered", and a preference does not silence it (review pass 1).
		if bool(entry.get("interrupt", false)) \
				or MessageSettings.allows(main._messages, ev.category, severity, "notify"):
			sting_severity = maxi(sting_severity, severity)
		var holds := MessageSettings.allows(main._messages, ev.category, severity, "pause")
		# Recorded and carded BEFORE the hold (QA on #73): the hold names its cause
		# from the unseen set and raises its card (hold_reason.gd).
		main._unseen_events[event_id] = holds
		if MessageSettings.allows(main._messages, ev.category, severity, "popup"):
			push(main, ev, entry)
		if holds:
			main._hold_for_decision()
	if sting_severity > 0:
		Sound.event_sting(main, sting_severity)

	# A quiet arrival's card stays up while the clock runs, so every live
	# decision card's deadline is re-read here, before the guard: a card saying
	# "3 months" beside a desk saying one is two readouts of one entry
	# disagreeing (review pass 2). Before V4.8c the arrival stopped the clock
	# and the sentence could not age under the player.
	refresh_bodies(main, ns)

	# After the arrivals, so a quiet arrival with one month to answer is caught
	# in the month it lands.
	guard_lapses(main, ns)

	# The unseen set's third door re-check: the pause is re-judged AFTER the
	# arrivals, not beside the departure erase above -- a same-month
	# resolve-and-replace (one default fires, another crisis lands) must not
	# resume past the fresh arrival. The same three lines the card-answer path
	# runs.
	main._resume_if_decision_settled()


## V4.8c, THE LAPSE GUARD -- the arrival pause's contract, kept for a quiet
## arrival. Every unanswered entry the pause band let through (false in the unseen
## set) whose countdown is down to its last month -- Events._tick_countdowns
## answers it by default on the NEXT tick -- now holds the clock, and gets its
## decision card if the popup band suppressed one: a clock stopped with nothing on
## screen saying why is the silent failure this column exists to catch. Runs every
## month, right after the tick moved the countdowns. An interrupt is not its
## business: _enforce_interrupt() holds those whatever the settings say.
static func guard_lapses(main, ns) -> void:
	for entry in ns.event_queue:
		var event_id := String(entry.get("event_id", ""))
		if not main._unseen_events.has(event_id) or bool(main._unseen_events[event_id]):
			continue
		if int(entry.get("months_left", 0)) > 1:
			continue
		var ev = Events.event_by_id(main._loader, event_id)
		if ev == null:
			continue
		main._unseen_events[event_id] = true
		main._hold_for_decision()
		if not main._event_cards.values().has(event_id):
			push(main, ev, entry)


## The decision card for one desk entry: the event's choices as buttons, the
## place in the title for a sited event, the plate beside it. One builder for the
## arrival and the lapse guard, so the guard's card is the arrival's card.
## After a load: the loaded desk back in the inbox's Decisions lane (V5.1-c3.2: the
## clear took the discarded game's rows, and a pending question with no row could be
## answered only from Dispatches), and the latest consequence card (C6).
static func restore_after_load(main) -> void:
	for entry in main._state.player().event_queue:
		push(main, Events.event_by_id(main._loader, String(entry.get("event_id", ""))), entry)
	EffectsLedger.restore_card(main._state, main._hud.inbox)
	AudienceDriver.after_load(main)


static func push(main, ev, entry: Dictionary) -> void:
	if ev == null:
		return  # a desk entry whose event the content no longer has (a load)
	var event_id := String(entry.get("event_id", ""))
	var left := int(entry.get("months_left", 0))
	# The card itself is the answer surface. Since V4.8c a quiet arrival's card
	# can be answered with the clock running -- Events.answer is the same chain
	# either way; only the arrival pause used to guarantee a stopped world. The
	# default-choice marker is events_panel's own wording.
	var actions: Array = []
	for choice in ev.choices:
		actions.append({"label": "%s%s" % [
			Strings.choice_label(ev.id, choice),
			Strings.t("   (happens if you say nothing)") if bool(choice.get("is_default", false)) else "",
		]})
	# The title names the place for a sited event -- read straight off the
	# entry, `event_name` untouched (V3.5). The name is already in the
	# register because every reader of it is a leaf over pending state.
	var title: String = Strings.row_name("events", ev)
	var where := String(entry.get("region_name", ""))
	if where != "":
		title = "%s — %s" % [title, where]
	# The same plate the Dispatches desk entry carries, on the title's side:
	# one crisis, one image, in both places it is read. Null (no art yet)
	# draws the card exactly as before -- missing art is silent.
	var art := EventArt.plate_texture(ev.category, int(entry.get("severity", 1)), event_id)
	var card_id: String = main._hud.inbox.push(title, body(ev, left), actions, art)
	main._event_cards[card_id] = event_id


## Every live decision card's deadline sentence, re-read off the desk. A card
## whose event has left the desk was dismissed above; one the eviction dropped is
## a set_body() no-op.
static func refresh_bodies(main, ns) -> void:
	var left_by_id := {}
	for entry in ns.event_queue:
		left_by_id[String(entry.get("event_id", ""))] = int(entry.get("months_left", 0))
	for card_id in main._event_cards.keys():
		var event_id := String(main._event_cards[card_id])
		if not left_by_id.has(event_id):
			continue
		var ev = Events.event_by_id(main._loader, event_id)
		if ev != null:
			main._hud.inbox.set_body(String(card_id), body(ev, int(left_by_id[event_id])))


## Dismiss every message-stack card keyed to an event that has left the desk.
## Finds card ids in main._event_cards mapping to `event_id`, dismisses each, and
## iterates a copy of the keys because `dismiss()` emits `card_dismissed` whose
## handler erases from main._event_cards -- re-entry is harmless; the handler also
## erases from main._unseen_events, which is a no-op when the caller already erased it.
static func dismiss(main, event_id: String) -> void:
	if main._hud == null or main._hud.inbox == null:
		return
	for card_id in main._event_cards.keys().duplicate():
		if String(main._event_cards.get(card_id, "")) == event_id:
			main._hud.inbox.dismiss(card_id)


## The decision card's body: the event's summary line, then the deadline -- the
## same two sentences the arrival card has always carried, now beside buttons
## that answer it (V2.9).
static func body(ev, left: int) -> String:
	return Strings.tn("%s  You have %d month to answer.", "%s  You have %d months to answer.", left) % [
		Strings.row_summary("events", ev), left,
	]
