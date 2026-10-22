extends RefCounted

## Why the clock is held, said where the clock is -- V5.1-d1b3, the parent's call
## on QA's "the clock paused with no cause I saw": since d1a the inbox can already
## be up over a tab, so a hold that slides it in moves nothing on screen. Every
## hold names its cause on the clock cluster and brings the card it is about to the
## top of the inbox (Inbox.raise_card), whether the inbox moved or not.
##
## Read off main.gd's own hold registers rather than handed in by each caller, so
## the arrival, the lapse guard, an interrupt and the term-start programme all say
## it through one door.

const Events = preload("res://src/sim/events.gd")
const Strings = preload("res://src/ui/strings.gd")


## The line for the clock cluster, "" when nothing the player can answer holds it;
## raises the card it names.
static func show(main) -> String:
	var ns = main._state.player() if main._state != null else null
	if ns == null:
		return ""
	var held := ""
	if Events.interrupt_pending(ns):
		var ev = Events.pending_event(ns, main._loader)
		held = String(ev.id) if ev != null else ""
	if held.is_empty():
		for event_id in main._unseen_events:
			held = String(event_id)
			break
	if not held.is_empty():
		for card_id in main._event_cards:
			if String(main._event_cards[card_id]) == held:
				main._hud.inbox.raise_card(card_id)
		var ev = Events.event_by_id(main._loader, held)
		if ev != null:
			return Strings.t("Paused: %s needs an answer.") % Strings.row_name("events", ev)
	if main._paused_for_programme:
		main._hud.inbox.raise_card(main._programme_card_id)
		return Strings.t("Paused: choose the term's programme.")
	return ""
