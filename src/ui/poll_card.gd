extends RefCounted

## A poll arrives: one quiet card with the country's read, V5.3 b, docs/design/v5.3-ab.md 4.2.
## With an Open on the bill while the measure is still open, the decision the poll was bought
## for; with none on a measure that has closed, a note (QA's RECORD on #299). It spends none of
## the 4 + 6 a year (docs/design/decision-surfaces.md): the card waits and never touches the clock.
##
## TWO ROADS, ONE CARD. MeasurePolls.deliver_due runs each day from DiaryDriver, so a two-week
## poll arrives in two weeks, and at the month's close as the Polls step, whose rows come in
## report["polls"]. A poll is printed once, so it reaches here once.

const Legislature = preload("res://src/sim/legislature.gd")
const PollStrip = preload("res://src/ui/poll_strip.gd")
const Strings = preload("res://src/ui/strings.gd")

## What the Open acts on (acts_on.gd), before the measure's key.
const SUBJECT := "poll|"

## main's instance id -> {cards: {live card id: law id}, wired: the Open's handler is connected}.
static var _games := {}


static func arrived(main, row: Dictionary) -> void:
	var key := String(row["key"])
	var game: Dictionary = _games.get_or_add(main.get_instance_id(), {"cards": {}, "wired": false})
	var inbox = main._hud.inbox
	if not bool(game["wired"]):
		game["wired"] = true
		inbox.card_action.connect(_on_open.bind(main))
	var open: bool = Legislature.open_law(main._state, main._state.player(), main._loader, key) != null
	var card: String = inbox.push(Strings.t("Poll: %s") % measure_name(main, key), PollStrip.support_line(row["ranges"]),
		[{"label": Strings.t("Open"), "acts_on": SUBJECT + key}] if open else [])
	if open:
		game["cards"][card] = key
	main._law_panel.mark_dirty()


static func _on_open(card: String, _index: int, main) -> void:
	var cards: Dictionary = (_games.get(main.get_instance_id(), {}) as Dictionary).get("cards", {})
	if not cards.has(card):
		return
	main._windows.open("legislature")
	main._law_panel._laws._selected = String(cards[card])
	main._law_panel.mark_dirty()
	cards.erase(card)
	main._hud.inbox.dismiss(card)


## A measure's name: a bill, or a draft by its composed name.
static func measure_name(main, key: String) -> String:
	var law = main._law_panel._find_law(key)
	if law != null:
		return Strings.law_name(law)
	var draft: Dictionary = main._state.player().draft_bills.get(key, {})
	return String(draft.get("name", key))  # i18n: row-ok a drafted bill's composed name, not a data row
