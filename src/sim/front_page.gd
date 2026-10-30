extends RefCounted

## The press marks what matters -- V5.2d, docs/design/v5.2-d-spec.md section 4
## (the author, 2026-10-25: "des popup de titres de journaux qui marquent des
## events importants"). The month report's `front_page` entry, which
## src/ui/front_page.gd prints:
##
##   {} or {kind: "event"|"moment", id, answer, severity, month: y*12+m,
##          papers: [{outlet, tone}] (two, or one), also: [{kind, id, answer, outlet, tone}] (<= 2)}
##
## STORIES ARRIVE BETWEEN TWO CLOSES, MOSTLY OUTSIDE THE MONTH. A player answers an
## event, forces a bill under 49.3 (and may lose the censure vote) or dissolves the
## Assembly by command, between ticks; a default, a minister's resignation, a
## defection and an election happen inside one. So every story waits in ONE
## register, `ns.front_page_pending`, in arrival order -- note() is its only
## writer, close() its only reader -- and close(), at the end of WorldMonth's
## Elections step, prints the month's front page from it and empties it. The
## register is SAVED (absent_ok, no bump: absent is nothing waiting), so a save
## between an answer and the month's end keeps its headline; the entry itself is
## ephemeral, a note in the report. Events' own `event_history` cannot serve:
## nothing in src/sim/ reads it back (tests/test_events.gd).
##
## The played nation only: an AI nation has no front page to print.
##
## AT MOST ONE A MONTH (D8): the most severe story leads, equal severity goes to
## the earlier arrival, and the next ALSO_MAX ride along as one line each.
##
## PRESENTATION ONLY. The framing machine already moves opinion by outlet
## (src/sim/media.gd); this file adds no second press effect and writes nothing a
## number reads, so the balance table cannot move (D10).

const Cut = preload("res://src/core/cut.gd")
const Media = preload("res://src/sim/media.gd")
const K = preload("res://src/sim/front_page_constants.gd")


## A story for the next close. Ignored for any nation but the played one.
static func note(state, ns, kind: String, id: String, answer: String, severity: int) -> void:
	if ns == null or String(ns.id) != String(state.player_nation_id):
		return
	ns.front_page_pending.append({"kind": kind, "id": id, "answer": answer, "severity": severity})


## A political moment (front_page_constants.MOMENT_SEVERITY's ids; the outcomes
## are the parent's contract with Content, data/headlines/moments.json).
static func note_moment(state, ns, moment: String, outcome: String) -> void:
	note(state, ns, "moment", moment, outcome, int(K.MOMENT_SEVERITY[moment]))


## Article 49.3's two moments off a forced bill's result (Legislature._force): the
## bill carried over the Assembly's head, and the government the censure felled.
static func note_forced(state, ns, result: Dictionary) -> void:
	if bool(result.get("passed", false)):
		note_moment(state, ns, "article_49_3", "carried")
	if bool((result.get("censure", {}) as Dictionary).get("carried", false)):
		note_moment(state, ns, "censure", "government_fell")


## The month's front page from the waiting stories and this month's report, and
## the register emptied. {} when nothing earned one or the nation has no outlet.
static func close(state, loader, report: Dictionary) -> Dictionary:
	var ns = state.player()
	if ns == null:
		return {}
	var stories: Array = ns.front_page_pending.duplicate()
	ns.front_page_pending.clear()
	# The report's moments came last in the month: the Characters step, then
	# Elections -- arrival order after everything already waiting.
	for act in report.get("character_acts", []):
		if String(act.get("act", "")) == "defect":
			stories.append(_moment("character", "defected"))
		# The prime minister leaving the chair of their own accord (#189 call 2,
		# the outcome #191 added): the resign act's one office today.
		elif String(act.get("act", "")) == "resign" \
				and String((act.get("detail", {}) as Dictionary).get("office", "")) == "premiership":
			stories.append(_moment("character", "prime_minister_resigned"))
	for result in report.get("election_results", []):
		var outcome := _election_outcome(result)
		if outcome != "":
			stories.append(_moment("election", outcome))
	if stories.is_empty():
		return {}
	var shown := papers(ns, loader)
	if shown.is_empty():
		return {}
	var ordered := _by_severity(stories)
	var lead: Dictionary = ordered[0]
	var also: Array = []
	for i in range(1, mini(ordered.size(), K.ALSO_MAX + 1)):
		var story: Dictionary = ordered[i]
		# The same papers as the lead, one story each in turn.
		var paper: Dictionary = shown[(i - 1) % shown.size()]
		also.append({
			"kind": story["kind"], "id": story["id"], "answer": story["answer"],
			"outlet": paper["outlet"], "tone": paper["tone"],
		})
	return {
		"kind": lead["kind"], "id": lead["id"], "answer": lead["answer"],
		"severity": int(lead["severity"]),
		"month": int(state.year) * 12 + int(state.month),
		"papers": shown,
		"also": also,
	}


## The played nation's two papers: its most friendly and its most hostile outlet
## by alignment (ties to id); when both fall in one tone -- then every outlet does,
## the cut being monotone -- the two with the greatest reach instead (ties to id).
## One paper for a nation with one outlet, none for one with no press.
static func papers(ns, loader) -> Array:
	var outlets: Array = loader.outlets.get(ns.id, [])
	if outlets.is_empty():
		return []
	var rows: Array = []
	for outlet in outlets:
		rows.append({"outlet": String(outlet.id), "alignment": Media.outlet_alignment(outlet, ns), "reach": float(outlet.reach)})
	rows.sort_custom(func(a, b):
		return a["alignment"] > b["alignment"] if a["alignment"] != b["alignment"] else a["outlet"] < b["outlet"])
	if rows.size() == 1:
		return [_paper(rows[0])]
	var friendly: Dictionary = rows[0]
	var hostile: Dictionary = rows[rows.size() - 1]
	if tone(friendly["alignment"]) != tone(hostile["alignment"]):
		return [_paper(friendly), _paper(hostile)]
	rows.sort_custom(func(a, b):
		return a["reach"] > b["reach"] if a["reach"] != b["reach"] else a["outlet"] < b["outlet"])
	return [_paper(rows[0]), _paper(rows[1])]


## An alignment in [-1, +1] as one of front_page_constants.TONES.
static func tone(alignment: float) -> String:
	if Cut.above(alignment, K.TONE_CUT):
		return "friendly"
	if Cut.below(alignment, -K.TONE_CUT):
		return "hostile"
	return "neutral"


static func _paper(row: Dictionary) -> Dictionary:
	return {"outlet": row["outlet"], "tone": tone(row["alignment"])}


static func _moment(moment: String, outcome: String) -> Dictionary:
	return {"kind": "moment", "id": moment, "answer": outcome, "severity": int(K.MOMENT_SEVERITY[moment])}


## The president's own vote, or their camp after an Assembly election; "" for a
## European Parliament result and a term-limit notice, which are not the
## president's moment.
static func _election_outcome(result: Dictionary) -> String:
	match String(result.get("kind", "")):
		"executive":
			return "executive_won" if bool(result.get("incumbent_largest", false)) else "executive_lost"
		"national":
			var formation: Dictionary = result.get("formation", {})
			if bool(formation.get("cohabitation", false)):
				return "legislative_opposition"
			if bool(formation.get("minority", false)):
				return "legislative_minority"
			return "legislative_majority"
	return ""


## Most severe first, equal severity in arrival order. A hand insertion sort, not
## sort_custom, which Godot documents as unstable (events.gd's _order_queue).
static func _by_severity(stories: Array) -> Array:
	var ordered: Array = []
	for story in stories:
		var at := ordered.size()
		while at > 0 and int(ordered[at - 1]["severity"]) < int(story["severity"]):
			at -= 1
		ordered.insert(at, story)
	return ordered
