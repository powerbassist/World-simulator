extends RefCounted

## What the Presidency page's term draws -- rework 2, direction A (presidency-page-brief.md;
## the author's "A, le mandat" and "Coupure en deux"). A pure, read-only query over
## GameState: twelve months back on one side of today, the term to the vote on the other.
##
## THE TWO HALVES KEEP THEIR OWN SCALE (the hinge, the author's call): at 58 months to the
## vote a single linear axis squeezes the past year to a sixth of the width, and the files
## of the next three months already live in the bar's horizon and the Diary, so the future
## half draws only what lies beyond them: each programme entry's window and the vote.
##
## A PROGRAMME LANE IS THE FIGURE AGAINST ITS GOAL, never a bar on time (the parent's call):
## progress toward 7 % is not elapsed time. The past half is the figure the entry is judged
## on (`current_value`, read off GameState.history), the future half its window to the
## deadline; the gutter prints the progress the Agenda and the strip print.

const ChartSeries = preload("res://src/ui/chart_series.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")
const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const Trends = preload("res://src/ui/trends.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const ProgrammeDistance = preload("res://src/ui/programme_distance.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")
const Num = preload("res://src/ui/num.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")

## A programme group's working tab: where the levers that move its goals live (OPINION, V5.3-0 2.4:
## the data carries no tab, and a goal's group is the closest general rule -- an economy goal is moved
## by the budget's levers, an institutional or a society goal by a law). It was agenda_panel.gd's.
const GROUP_TAB := {"economy": "finances", "europe": "diplomacy", "institutions": "legislature",
	"office": "majority", "society": "legislature"}  # i18n: ok tab ids

## The past half: the last year of polls, the span a reader compares a term against.
const PAST_MONTHS := 12
## The field the approval lane reads; a programme entry judged on it is drawn as the poll.
const APPROVAL_FIELD := ProgrammeDistance.APPROVAL_FIELD


## The past half's snapshots, oldest first, at most a year (GameState.history).
static func past(state) -> Array:
	return ChartSeries.last(state, PAST_MONTHS)


## The approval the player was shown, month by month: the polls, never the truth.
static func approval(entries: Array) -> PackedFloat64Array:
	return ChartSeries.polled(entries, APPROVAL_FIELD, PollingPanel.HEADLINE_KEY)


## Today's poll, the figure the page prints beside the line.
static func approval_now(state) -> float:
	return PollNoise.displayed(PollNoise.poll_id(state.year, state.month), PollingPanel.HEADLINE_KEY,
		state.player().overall_approval_pct)


## Months from today to the player's vote: the one shared query (Trends.months_to_vote).
static func ahead(state) -> int:
	return maxi(Trends.months_to_vote(state, state.player()), 0)


## One lane per entry of this term's programme, in register order:
## {id, name, status, fraction, values (the judged figure over `past`), goal, chosen (the
## index in `past` where it was chosen, -1 when before the window), due (months ahead to its
## deadline, -1 once concluded), due_text, tip (now, goal and clock in words: the gutter's
## table twin of what the lane draws), tab (where its goal is moved)}.
static func goal_lanes(state, loader) -> Array:
	var ns = state.player()
	var entries := past(state)
	var to_vote := ahead(state)
	var out: Array = []
	for entry in Programme.this_term(ns):
		var id := String(entry["entry_id"])
		var terms: Dictionary = Programme.terms_of(loader, id)
		var field := String(terms.get("current_value", ""))
		var live := String(entry["status"]) == ProgrammeK.STATUS_ACTIVE
		var months_live := int(entry["months_live"])
		var timeout := int(terms.get("timeout_months", 0))
		var due := -1
		if live:
			due = to_vote if timeout <= 0 else mini(maxi(timeout - months_live, 0), to_vote)
		# months_live stops at the conclusion: the months since are the term's months past it.
		var months_ago := months_live if live else months_live + maxi(int(ns.months_in_term) - int(entry["concluded_term_month"]), 0)
		var chosen := entries.size() - 1 - months_ago
		var values: PackedFloat64Array = approval(entries) if field == APPROVAL_FIELD else ChartSeries.values(entries, field)
		out.append({
			"id": id,
			"name": Strings.row("programme", id, "name", String(terms.get("name", id))),
			"status": String(entry["status"]),
			"fraction": _fraction(state, terms, String(entry["status"])),
			"values": values,
			"goal": float(terms.get("goal_value", 0.0)),
			"chosen": chosen if chosen >= 0 else -1,
			"due": due,
			"due_text": _due_text(state, terms, due, live),
			"tip": _tip(state, terms, entry) + record_text(ns, loader),
			"tab": String(GROUP_TAB.get(String(terms.get("group", "")), "overview")),
		})
	return out


## The bar is the verdict once there is one: delivered full, missed or overtaken empty; a live
## goal reads its figure, through the polls when the figure is approval.
static func _fraction(state, terms: Dictionary, status: String) -> float:
	if terms.is_empty() or status != ProgrammeK.STATUS_ACTIVE:
		return 1.0 if status == ProgrammeK.STATUS_COMPLETE else 0.0
	var read: Dictionary = _progress(state, terms)
	return PanelKit.progress_fraction(float(read["current_value"]), float(read["goal_value"]), String(read["progressbar"]))


## Programme.progress_of, with approval read as the poll the player was shown (this file's rule).
static func _progress(state, terms: Dictionary) -> Dictionary:
	var read: Dictionary = Programme.progress_of(state.player(), terms)
	if String(terms.get("current_value", "")) == APPROVAL_FIELD:
		read["current_value"] = approval_now(state)
	return read


## The distance and the clock, in the Overview's words (its programme row's tooltip), so the
## strip, the Agenda and the page word one deadline one way.
static func _tip(state, terms: Dictionary, entry: Dictionary) -> String:
	if terms.is_empty():
		return ""
	var tip := ProgrammeDistance.of(state, terms)
	if String(entry["status"]) == ProgrammeK.STATUS_ACTIVE:
		tip += " · " + StripReadings.programme_clock_text(terms, entry)
	return tip


## The deadline's words at its mark: the month it falls, or "judged at the vote".
static func _due_text(state, terms: Dictionary, due: int, live: bool) -> String:
	if not live:
		return ""
	if int(terms.get("timeout_months", 0)) <= 0:
		return Strings.t("judged at the vote")
	var month0 := int(state.year) * 12 + int(state.month) - 1 + due
	return DateText.month_year(month0 % 12 + 1, month0 / 12)


## The record of the terms before this one (rework 2 S3: it was the Agenda's register), oldest first:
## {text, tone} per concluded entry -- its name and its verdict, the tone a ResultTone key ("" when the
## world overtook it). The programme file shows it beside the offer, the Presidency lane in its tooltip.
static func past_record(ns, loader) -> Array:
	var out: Array = []
	for entry in ns.programme:
		if int(entry["chosen_term"]) >= int(ns.terms_served):
			continue
		var id := String(entry["entry_id"])
		var name := Strings.row("programme", id, "name", String(Programme.terms_of(loader, id).get("name", id)))
		var term := int(entry["concluded_term"]) + 1
		match String(entry["status"]):
			ProgrammeK.STATUS_COMPLETE:
				out.append({"text": "%s — %s" % [name, Strings.t("Delivered, term %d.") % term], "tone": ResultTone.GOOD})
			ProgrammeK.STATUS_FAIL:
				out.append({"text": "%s — %s" % [name, Strings.t("Missed, term %d.") % term], "tone": ResultTone.BAD})
			_:
				out.append({"text": "%s — %s" % [name, Strings.t("Overtaken by the world, term %d.") % term], "tone": ""})
	return out


## The record as a tooltip's tail: "" with no past term, else a line per entry after a break (T5 a).
static func record_text(ns, loader) -> String:
	var lines: Array = past_record(ns, loader).map(func(r): return String(r["text"]))
	return "" if lines.is_empty() else "
" + "
".join(lines)


## Mid-term with nothing chosen (V5.1-0c, the Agenda's line until S3), in two parts: the rule (a
## programme is chosen on a term's first day; the lane's tooltip) and the date it next opens (the lane's
## one drawn line). With no vote scheduled the line is the rule, never a date that does not exist.
static func unset_rule(ns) -> String:
	if Programme.is_term_start(ns):
		return Strings.t("Nothing is offerable this term -- every gate in the book is shut.")
	return Strings.t("No programme was set this term: one is chosen on a term's first day.")


static func unset_line(ns) -> String:
	var when := Trends.vote_date(ns)
	if Programme.is_term_start(ns) or when.y < 1 or when.y > DateText.SHORT.size():
		return unset_rule(ns)
	return Strings.t("The next term starts after the vote in %s %d.") % [DateText.month(when.y), when.x]
