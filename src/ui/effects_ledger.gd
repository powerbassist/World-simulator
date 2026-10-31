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

const ResultTone = preload("res://src/ui/result_tone.gd")
const Trends = preload("res://src/ui/trends.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
## The register's one writer, and its bound (AGENTS.md rule 2).
const RecentEffects = preload("res://src/sim/recent_effects.gd")

## Figures on a consequence card: the biggest movements, by severity's size.
const CARD_FIGURES := 3


## Measure the month's decisions against this month's history entry, record them
## for the Overview and push their card. Empties `pending`.
##
## ONE entry and ONE card per close (V5.1-d1b3, QA on #69): a month's decisions
## cannot be told apart in a month's numbers -- five cards each claiming the same
## movement credited a tariff freeze with the budget's growth jump. So the close
## names what was decided, each name once (a call and its call-off are one), and
## gives what moved since the EARLIEST of them, worded as the month's movement after
## them, not as what one of them did.
##
## Returns the card ({title, body}, empty on a month with nothing decided) and
## pushes it only when given an inbox: main.gd hands it to the briefing instead,
## which says it on a month it shows (spec 3.3).
static func record(state, pending: Array, history_entry: Dictionary, year: int, month: int, inbox) -> Dictionary:
	if pending.is_empty():
		return {}
	# The stamped entry (year/month added), so movements_between() reads the
	# same "now" for approval's poll-noise lookup that the rest of the UI does.
	var dated_entry: Dictionary = history_entry.duplicate(true)
	dated_entry["year"] = year
	dated_entry["month"] = month
	# What the player decided, and what the clock decided for them (a default, QA on
	# #73) -- named apart, each name once.
	var names: PackedStringArray = []
	var defaults: PackedStringArray = []
	for queued in pending:
		var into: PackedStringArray = defaults if bool(queued.get("defaulted", false)) else names
		if not into.has(String(queued["label"])):  # i18n: row-ok an effect's label, routed when queued
			into.append(String(queued["label"]))  # i18n: row-ok an effect's label, routed when queued
	var effect := {
		"label": "; ".join(names + defaults),  # i18n: row-ok effects' labels, routed when queued
		"year": year,
		"month": month,
		"movements": Trends.movements_between(pending[0]["before"], dated_entry),
	}
	RecentEffects.record(state, effect)
	var body := card_body(effect)
	if not names.is_empty() and not defaults.is_empty():
		body = "%s %s" % [Strings.t("Decided for you: %s.") % ", ".join(defaults), body]  # i18n: row-ok effects' labels, routed when queued
	var title := Strings.t("This month you decided: %s") % ", ".join(names) if not names.is_empty() 			else Strings.t("This month, decided for you: %s") % ", ".join(defaults)  # i18n: row-ok effects' labels, routed when queued
	# RF7: a month's decisions are UNCERTAIN in its numbers (briefing_effects), so
	# the card is neutral -- unless the clock decided some of it: RISKY.
	var tone: String = ResultTone.RISKY if not defaults.is_empty() else ""
	if inbox != null:
		ResultTone.mark(inbox, inbox.push(title, body), tone)
	pending.clear()
	return {"title": title, "body": body, "tone": tone}


## After a load (someday.md C6, the parent's ruling): the inbox puts back what the
## saved state can show. The latest consequence is saved -- recent_effects, newest
## first -- so its card returns, dated, since "this month" would no longer be true;
## the pure notes it rode beside were never saved and stay gone.
static func restore_card(state, inbox) -> void:
	if state.recent_effects.is_empty() or inbox == null:
		return
	var effect: Dictionary = state.recent_effects[0]
	inbox.push(Strings.t("Decided in %s: %s") % [DateText.month_year(int(effect.get("month", 1)), int(effect.get("year", 0))),
		String(effect.get("label", ""))], card_body(effect))  # i18n: row-ok an effect's label, routed when queued


## What moved, biggest first: the figures with a reading and a change that prints
## as more than 0.0 (Trends.change_text snaps under 0.05). Shared with the
## Overview's list, so the card and the list cannot rank one month two ways.
static func moved(effect: Dictionary) -> Array:
	var ranked: Array = (effect["movements"] as Array).filter(func(m):
		return not is_nan(float(m["severity"])) and absf(float(m["change"])) >= 0.05)
	ranked.sort_custom(func(a, b): return absf(float(a["severity"])) > absf(float(b["severity"])))
	return ranked


## The card's body: the month's biggest movements since the decisions, each in the
## Overview's own words (Trends.change_text), or that nothing moved.
static func card_body(effect: Dictionary) -> String:
	var ranked := moved(effect)
	if ranked.is_empty():
		return Strings.t("Since then, nothing moved.")
	var parts: PackedStringArray = []
	for i in mini(CARD_FIGURES, ranked.size()):
		var m: Dictionary = ranked[i]
		parts.append("%s %s" % [String(m["label"]), Trends.change_text(float(m["change"]), String(m["unit"]))])  # i18n: row-ok Trends translates its labels
	return Strings.t("Since then: %s.") % " · ".join(parts)
