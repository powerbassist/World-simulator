extends RefCounted

## The month's measurement of the player's decisions -- U4's recent_effects,
## moved out of main.gd at V5.1-d1b, with its new second reader.
##
## A decision is queued with the state before it (main.gd's _queue_effect) and
## measured at the next month's History step against the entry that month
## settled. The measurement went only to the Overview's list; G10 of the play
## gate ("je n'ai pas bcp de retour des conséquences") is that nobody opens the
## Overview to find out what an answer did. So the same close now hands each
## measured decision back as a card in the inbox's notes: its name and its
## biggest movements, read from the very entry the Overview reads -- one
## measurement, two places to meet it.

const Trends = preload("res://src/ui/trends.gd")
const Strings = preload("res://src/ui/strings.gd")

## How many decisions the Overview's list keeps -- U4. Not the array's own size,
## which is unbounded; trimmed so a long session's save does not grow one entry
## per commit forever.
const KEPT := 5
## Figures on a consequence card: the biggest movements, by severity's size.
const CARD_FIGURES := 3


## Measure every queued decision against this month's history entry, record it
## for the Overview, and push its card. Empties `pending`.
static func record(state, pending: Array, history_entry: Dictionary, year: int, month: int, inbox) -> void:
	# The stamped entry (year/month added), so movements_between() reads the
	# same "now" for approval's poll-noise lookup that the rest of the UI does.
	var dated_entry: Dictionary = history_entry.duplicate(true)
	dated_entry["year"] = year
	dated_entry["month"] = month
	for queued in pending:
		var effect := {
			"label": queued["label"],  # i18n: row-ok an effect's label, routed when queued
			"year": year,
			"month": month,
			"movements": Trends.movements_between(queued["before"], dated_entry),
		}
		state.recent_effects.push_front(effect)
		if inbox != null:
			inbox.push(Strings.t("What came of it: %s") % String(effect["label"]), card_body(effect))  # i18n: row-ok an effect's label, routed when queued
	pending.clear()
	while state.recent_effects.size() > KEPT:
		state.recent_effects.remove_at(state.recent_effects.size() - 1)


## The card's body: the biggest movements, each in the Overview's own words
## (Trends.change_text), or that nothing moved.
static func card_body(effect: Dictionary) -> String:
	var ranked: Array = (effect["movements"] as Array).filter(func(m): return not is_nan(float(m["severity"])))
	ranked.sort_custom(func(a, b): return absf(float(a["severity"])) > absf(float(b["severity"])))
	if ranked.is_empty():
		return Strings.t("nothing moved")
	var parts: PackedStringArray = []
	for i in mini(CARD_FIGURES, ranked.size()):
		var m: Dictionary = ranked[i]
		parts.append("%s %s" % [String(m["label"]), Trends.change_text(float(m["change"]), String(m["unit"]))])  # i18n: row-ok Trends translates its labels
	return " · ".join(parts)
