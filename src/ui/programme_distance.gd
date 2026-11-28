extends RefCounted

## The programme figure in words (the author's call A on the blind play 11-28): the distance in the goal's own unit
## from the figure on the day of the choice, and no percentage. With no such figure (an offer not yet chosen, a row
## saved before it was kept), or a goal already met at it, it reads "now X · goal Y".

const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")
const Num = preload("res://src/ui/num.gd")
const Strings = preload("res://src/ui/strings.gd")

## The judged figure the player only ever sees as a poll.
const APPROVAL_FIELD := "overall_approval_pct"


## The figure the running entry `id` started from, NAN when none was kept.
static func start_of(ns, id: String) -> float:
	return float(_running(ns, id).get("start", NAN))


## The distance of entry `terms` as the player sees its figure. Approval is the poll at both ends, the choosing month's
## and today's: the poll noise is the game's own hiding, so no distance reads the true approval. An entry not running
## has no start.
static func of(state, terms: Dictionary) -> String:
	var ns = state.player()
	var row := _running(ns, String(terms["id"]))
	var start := float(row.get("start", NAN))
	var now := float(Programme.progress_of(ns, terms)["current_value"])
	if String(terms["current_value"]) == APPROVAL_FIELD:
		var poll := PollNoise.poll_id(state.year, state.month)
		now = PollNoise.displayed(poll, PollingPanel.HEADLINE_KEY, now)
		if not is_nan(start):
			start = PollNoise.displayed(poll - int(row["months_live"]), PollingPanel.HEADLINE_KEY, start)
	return words(terms, start, now)


static func _running(ns, id: String) -> Dictionary:
	for row in ns.programme:
		if String(row["entry_id"]) == id and String(row["status"]) == ProgrammeK.STATUS_ACTIVE:
			return row
	return {}


## `start` and `now` as the player sees them.
static func words(terms: Dictionary, start: float, now: float) -> String:
	var goal := float(terms["goal_value"])
	var way := -1.0 if String(terms["progressbar"]) == ProgrammeK.PROGRESS_DIRECTIONS[1] else 1.0
	var places := 0 if String(terms.get("unit", "")) == "terms" else 2
	var span := (goal - start) * way
	var half := 0.5 * pow(10.0, -places)  # under half the last printed digit nothing shows
	if is_nan(start) or span < half:
		return Strings.t("now %s · goal %s") % [Num.f(now, places), Num.f(goal, places)]
	var moved := (now - start) * way
	var said := [Num.f(start, places), Num.f(goal, places), Num.f(absf(clampf(moved, 0.0, span)), places), Num.f(span, places)]
	if -moved < half:
		return Strings.t("%s to %s: %s of %s done") % said
	return Strings.t("%s to %s: %s of %s done, now %s the wrong way") % (said + [Num.f(-moved, places)])
