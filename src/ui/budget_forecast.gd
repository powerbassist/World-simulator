extends Node

## The budget window's 24-month forecast, off the frame -- V5.1-0a, and the V5.0
## play gate's "budget levers are broken or freeze the game". The levers were
## never broken: every lever move, and every month end with the window open, ran
## two Budget.project() calls of the real model inside one frame (~5 s each at
## 41 nations, D14). Here each projection runs as Budget.projection() units under
## a frame budget, the panel's levers and books answer at once, and the three
## forecast rows follow.
##
## The numbers are the projection's own -- the real model, every nation, all 24
## months, to the last bit (tests/test_budget_forecast.gd) -- so nothing here is
## an estimate. What changes is WHEN the player sees them:
##   - "now" is projected once per change of state (a month, a command), not
##     once per lever move;
##   - "proposed" waits until the levers have been still for QUIET_FRAMES, so a
##     drag projects once, at its end, whatever moved the lever (drag, wheel,
##     keys -- not every one of them ends in drag_ended);
##   - with nothing edited, "proposed" is "now", and the column repeats it;
##   - a projection begun before a change finishes and is shown, marked as
##     updating, while the next one runs. Restarting on every change would never
##     finish at speed 3, where a month closes faster than a projection does.
## A child of the panel and so inside the windows: closed, it waits; while a
## month closes (month_runner.gd stops the windows' processing) it waits too.

const Budget = preload("res://src/sim/budget.gd")
const C = preload("res://src/sim/economy_constants.gd")
const CycleK = preload("res://src/sim/cycle_constants.gd")

## A settled forecast's rows changed: the panel redraws them.
signal settled

## Projection per frame, alongside the panel's own refresh: a 60 Hz frame keeps
## room for the draw. One unit is at most ~30 ms (a projected month's costliest
## system whole), so a frame can run past this by one unit, never by a month.
const FRAME_BUDGET_USEC := 10000
## A quarter second at 60 Hz with no lever moving: the drag is over.
const QUIET_FRAMES := 15
const COMPUTING := "computing ..."
const UPDATING := " ..."

var _state
var _loader
var _months := 0
var _now: Array = []
var _now_due := true
var _proposed: Array = []
var _proposed_key := ""
var _proposed_due := false
## The panel's pending as JSON, or "" while nothing is edited; and the pending.
var _want_key := ""
var _want: Dictionary = {}
var _quiet := 0
var _job = null              # Budget.ProjectionJob while one runs
var _job_key := ""           # "" for "now", else the pending it projects
## Whether the last projection begun was "now": once a "now" path is on screen the
## two take turns (_begin()).
var _last_now := false
## The frame the panel redrew in -- want() is its refresh's call: that frame has
## spent its share (two ~19 ms previews), and the projection waits one frame.
var _yield_frame := -1


func setup(state, loader, months: int) -> void:
	_state = state
	_loader = loader
	_months = months
	_now = []
	_now_due = true
	_proposed = []
	_proposed_key = ""
	_want_key = ""
	_job = null


## The state moved (the panel's mark_dirty): both forecasts are due again, and
## stay on screen until they are replaced.
func state_changed() -> void:
	_now_due = true
	_proposed_due = true


## What the panel proposes now. `edited` false: nothing pending, "proposed" is "now".
func want(pending: Dictionary, edited: bool) -> void:
	_yield_frame = Engine.get_process_frames()
	var key := JSON.stringify(pending, "", true, true) if edited else ""
	if key == _want_key:
		return
	_want_key = key
	_want = pending.duplicate(true)
	_quiet = QUIET_FRAMES
	# A projection of a budget the player has already moved past answers nothing.
	if _job != null and _job_key != "":
		_job = null


func busy() -> bool:
	return _job != null or _now_due or (_want_key != "" and (_proposed_due or _proposed_key != _want_key))


func now_path() -> Array:
	return _now


func proposed_path() -> Array:
	return _proposed if _want_key != "" and _proposed_key == _want_key else []


## Every projection due, now, in this frame -- for a test or a tool that reads the
## rows synchronously (tools/screenshot.gd photographing the budget window).
func drain() -> void:
	_quiet = 0
	while busy() and _state != null:
		_advance(1 << 62)


func _process(_delta: float) -> void:
	if _state == null or not get_parent().is_visible_in_tree():
		return
	if _yield_frame == Engine.get_process_frames():
		_yield_frame = -1
		return
	if _quiet > 0:
		_quiet -= 1
	_advance(FRAME_BUDGET_USEC)


func _advance(budget_usec: int) -> void:
	var start := Time.get_ticks_usec()
	var ran := false
	while true:
		if _job == null and not _begin():
			return
		if ran and Time.get_ticks_usec() - start >= budget_usec:
			return
		Budget.projection_step(_job)
		ran = true
		if Budget.projection_done(_job):
			if _job_key == "":
				_now = _job.path
			else:
				_proposed = _job.path
				_proposed_key = _job_key
			_job = null
			settled.emit()


## "now" first -- until a "now" path is on screen, after which the two take turns.
## At speed 3 a month closes before a projection does, so "now" is due again each
## time it lands; first-always would never reach the proposed budget (review pass 1).
func _begin() -> bool:
	var wanted: bool = _want_key != "" and _quiet == 0 and (_proposed_due or _proposed_key != _want_key)
	if _now_due and not (wanted and _last_now and not _now.is_empty()):
		_now_due = false
		_last_now = true
		_job_key = ""
		_job = Budget.projection(_state, {}, _months, _loader)
		return true
	if wanted:
		_proposed_due = false
		_last_now = false
		_job_key = _want_key
		_job = Budget.projection(_state, _want, _months, _loader)
		return true
	return false


## The three forecast rows, key -> [now, proposed] text: a range from the last
## finished path, marked while a newer one computes, or COMPUTING before any.
func rows(ns) -> Dictionary:
	var out := {}
	var now_texts := _texts(ns, _now)
	var mine: Array = proposed_path()
	var proposed_texts := now_texts if _want_key == "" else _texts(ns, mine)
	var now_mark := UPDATING if not _now.is_empty() and (_now_due or (_job != null and _job_key == "")) else ""
	var proposed_mark := now_mark if _want_key == "" \
		else (UPDATING if not mine.is_empty() and (_proposed_due or _job != null) else "")
	for key in now_texts.keys():
		out[key] = [now_texts[key] + now_mark, proposed_texts[key] + proposed_mark]
	return out


func _texts(ns, path: Array) -> Dictionary:
	if path.is_empty():
		return {"proj_growth": COMPUTING, "proj_unemployment": COMPUTING, "proj_debt": COMPUTING}
	var last: Dictionary = path[-1]
	var band := _forecast_half_width(ns)
	# The debt ratio gets a band too, and the screenshot pass is what asked for it: one
	# point figure between two ranges read as a row somebody forgot rather than as a
	# stock behaving differently. The half-width is the same uncertainty carried through
	# the DENOMINATOR -- `band` points of growth a year for two years moves GDP by about
	# that much twice over, and the ratio with it -- so it is derived from the same
	# number rather than being a second guess.
	var years: float = float(_months) / 12.0
	return {
		"proj_growth": _forecast_text(float(last["growth_annual_pct"]), band, 2),
		"proj_unemployment": _forecast_text(float(last["unemployment_pct"]), band * C.OKUN, 2),
		"proj_debt": _forecast_text(float(last["debt_to_gdp_pct"]),
			band * years * float(last["debt_to_gdp_pct"]) / 100.0, 1),
	}


## V1.6a. A PROJECTION IS EXACT AND A FORECAST IS NOT, and these three rows print the
## second while the model computes the first. (Moved here from budget_panel.gd with
## the rows at V5.1-0a, verbatim.)
##
## Budget.project() runs the real model on a copy, so the number it returns is what will
## happen to the last digit -- tests/test_budget.gd asserts it to 1e-9, and V1.6a's
## business cycle reproduces there exactly because it is a pure function of the clock.
## Printing that to two decimals would hand the player a perfect two-year forecast of a
## recession they are supposed to be judged on not having prevented, which is
## docs/tiers/v1.md section 6's mechanic thrown away at the last surface.
##
## src/ui/poll_noise.gd already solved this problem from the other side and its
## reasoning transfers word for word: an approval figure is a PUBLISHED POLL and must
## not be readable exactly, so the model never stores a fuzzed number and the panel
## fuzzes it the moment it renders one. A government growth forecast is a published
## figure in exactly the same sense.
##
## It is a RANGE rather than a nudged point, and that is the one place this departs from
## poll_noise. A nudge invents an error with a sign the model has no basis for; a band
## states the uncertainty and contains the truth. It also costs no hash at all -- the
## half-width is derived, so there is nothing to keep stable across repaints and nothing
## to serialise, which are the two properties poll_noise.gd needed its hash for.
##
## THE SAME HALF-WIDTH IS APPLIED TO BOTH COLUMNS, and that is what keeps this panel
## usable. Its whole job is now-against-proposed, so an independent error on each side
## would fuzz the comparison the player is actually making. One band means the
## DIFFERENCE between the two columns stays exact while the LEVEL is honest about being
## a forecast -- which is also true of real forecasters, whose bias moves both scenarios
## together.
func _forecast_half_width(ns) -> float:
	if ns == null:
		return 0.0
	# One standard deviation of the cycle's own contribution to growth. Derived from
	# the constant and the nation's measured volatility rather than chosen, so a
	# quieter country gets a tighter band without a second number to tune.
	return CycleK.CYCLE_AMPLITUDE_PCT * float(ns.cycle_amplitude_rel)


## "1.05 to 1.62%". An en dash would read as a minus sign against a negative growth
## figure, which is exactly the forecast the player most needs to read correctly.
func _forecast_text(value: float, half_width: float, places: int) -> String:
	if half_width <= 0.0:
		return "%.*f%%" % [places, value]
	return "%.*f to %.*f%%" % [places, value - half_width, places, value + half_width]
