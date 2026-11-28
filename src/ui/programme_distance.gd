extends RefCounted

## The programme figure in words (the author's call A on the blind play 11-28): the distance in the goal's own unit
## from the figure on the day of the choice, and no percentage. With no such figure (an offer not yet chosen, a row
## saved before it was kept), or a goal already met at it, it reads "now X · goal Y".

const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const Num = preload("res://src/ui/num.gd")
const Strings = preload("res://src/ui/strings.gd")


## The figure the running entry `id` started from, NAN when none was kept.
static func start_of(ns, id: String) -> float:
	for row in ns.programme:
		if String(row["entry_id"]) == id and String(row["status"]) == ProgrammeK.STATUS_ACTIVE:
			return float(row.get("start", NAN))
	return NAN


static func of(ns, terms: Dictionary, now: float) -> String:
	return words(terms, start_of(ns, String(terms["id"])), now)


## `start` and `now` as the caller shows them (a page that prints polls passes polls).
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
