extends SceneTree

## Headless test: godot --headless --script res://tests/test_calendar_panel.gd
## Non-zero exit on any failure.
##
## U6a's surface. Loads the actual main scene and drives it a frame at a time --
## a Control outside the scene tree has not run _ready(), so everything it builds
## is null. See docs/engine-decision.md.
##
## Every assertion is a MUTATION check scoped to this panel's own containers. A
## "some label exists" walk from the scene root passes against the action bar and
## proves nothing, which is the failure tests/test_nation_panel.gd records.
##
## The two that matter most are the ones a green suite could otherwise hide:
##
##   - the strip shows dated state the player NEVER BOOKED. That is U6a's whole
##     headline, and a panel that only ever draws the player's own bookings would
##     be a to-do list. It has to have an election on it out of the box.
##   - a refused booking SAYS SO on screen. docs/trade-model.md's unread
##     `refused_by_partner` shipped a live button that refused silently, and this
##     project has now recorded that failure three times.

const Calendar = preload("res://src/sim/calendar.gd")
const K = preload("res://src/sim/calendar_constants.gd")

## U5a's usable band. A window taller than this has rows the player cannot reach,
## which is a fold no headless assertion can see -- so the one thing that CAN be
## checked headlessly is that the panel does not open past it.
const USABLE_BAND_PX := 886.0

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the scene's _ready() run

	_run()
	_finish()
	return false


func _run() -> void:
	if _main._state == null:
		_fail("main scene did not build a GameState")
		return
	if _main._calendar_panel == null:
		_fail("main scene did not build a calendar panel")
		return

	var panel = _main._calendar_panel
	var state = _main._state

	_check_registered_and_reachable()
	_check_fits_the_band(panel)
	_check_strip_shows_unbooked_dates(panel, state)
	_check_strip_spans_the_horizon(panel, state)
	_check_booking_appears_on_the_strip(panel, state)
	_check_a_refusal_is_printed(panel, state)
	_check_away_line_months(panel, state)


## The two lines main.gd's own comment predicted three sessions ago. Checked
## because a panel that is built but never registered is invisible, and nothing
## else in this file would notice.
func _check_registered_and_reachable() -> void:
	if not _main._windows.is_open("calendar"):
		_main._windows.open("calendar")
	if _main._windows.frame("calendar") == null:
		_fail("no window frame registered under the id 'calendar'")

	# The sub-row is built when a cluster opens, so the entry does not exist until
	# then -- the same reason tests/test_hud.gd drives _toggle_cluster() rather
	# than walking the bar cold.
	var bar = _main._hud.action_bar
	bar._toggle_cluster("state")
	var found := false
	for node in _walk(bar):
		# Upper-cased by add_cluster()'s own sub-row build, so match what the bar
		# actually draws rather than what main.gd passed it.
		if node is Button and String(node.text) == "DIARY":
			found = true
	bar.close_subrow()
	if not found:
		_fail("the State cluster has no Diary entry -- the panel is unreachable without one")


func _check_fits_the_band(panel) -> void:
	if panel.custom_minimum_size.y > USABLE_BAND_PX:
		_fail("the diary opens at %.0fpx, past U5a's %.0fpx usable band" % [
			panel.custom_minimum_size.y, USABLE_BAND_PX,
		])


## THE HEADLINE, and the one assertion in this file written against a measured
## fact rather than an intention. A brand-new game has booked nothing. U6a
## measured nothing dated inside the strip's own horizon either; since V4.5b1
## (one proposal per presidency, PROPOSAL_INTERVAL_MONTHS 6) the councils' first
## openings fall six months in, so the horizon carries those and nothing else.
## France's presidential election is sixteen months out and the legislative
## election forty-one, both past the horizon, so the "later" footer is still what
## names the dates that matter most. Cooldowns do not exist until the player has
## acted. If this fails, the diary opens with the big dates missing.
func _check_strip_shows_unbooked_dates(panel, state) -> void:
	if not state.appointments.is_empty():
		_fail("a new game started with %d bookings -- this check needs an empty diary to mean anything" % state.appointments.size())
		return

	_refresh(panel)
	var text := _strip_text(panel)
	var carries := false
	for label in [
		panel.FIXED_LABEL[K.FIXED_ELECTION],
		panel.FIXED_LABEL[K.FIXED_EP_ELECTION],
		panel.FIXED_LABEL[K.FIXED_EXECUTIVE],
		panel.FIXED_LABEL[K.FIXED_COUNCIL_PROPOSAL],
	]:
		if text.contains(String(label)):
			carries = true
	if not carries:
		_fail("a new game's diary opened with no dated state anywhere on it -- U6a's headline is that the game already knows these dates")
	if not text.contains("LATER"):
		_fail("no `later` footer was drawn -- a new game's elections are all past the horizon, and the footer is what names them")
	# And it must be readable WITHOUT scrolling. The footer sits under thirteen
	# em dashes on a new game, so the strip alone answers "what is coming" only
	# for a player who already scrolled to find out that nothing is.
	if not panel._next_up.text.begins_with("Next:"):
		_fail("the always-visible next-up line read '%s' -- a new game's only content is below the fold of the strip's own scroll" % panel._next_up.text)


## Twelve months plus the current one, not one page. U6a's probe measured 31 %
## of months carrying a dated event, so a single-month grid opens empty seven
## times in ten; the strip is the shape that answers that, and a later session
## quietly shortening it would undo the finding.
func _check_strip_spans_the_horizon(panel, state) -> void:
	_refresh(panel)
	var text := _strip_text(panel)
	var months_shown := 0
	for offset in range(K.BOOKING_HORIZON_MONTHS + 1):
		var total: int = state.year * 12 + (state.month - 1) + offset
		var heading := "%s %d" % [
			panel.ClockCluster.MONTH_NAMES[total % 12], total / 12,
		]
		if text.contains(heading):
			months_shown += 1
	if months_shown != K.BOOKING_HORIZON_MONTHS + 1:
		_fail("the strip drew %d month headings, expected %d" % [
			months_shown, K.BOOKING_HORIZON_MONTHS + 1,
		])


func _check_booking_appears_on_the_strip(panel, state) -> void:
	var total: int = state.year * 12 + (state.month - 1) + 3
	var entry := Calendar.make_entry(
		K.KIND_DIPLOMATIC, total / 12, total % 12 + 1, 11, "state_visit", "DEU"
	)
	var result: Dictionary = Calendar.book(state, entry)
	if not bool(result["ok"]):
		_fail("the panel test could not book a state visit: %s" % String(result["error"]))
		return

	_refresh(panel)
	if not _strip_text(panel).contains("State Visit"):
		_fail("a booking made it into the register and never appeared on the strip")

	# And it carries a cancel button, which a fixed date must not -- the player
	# cannot move an election.
	var cancels := 0
	for node in _walk(panel._body):
		if node is Button and String(node.text) == "Cancel":
			cancels += 1
	if cancels != 1:
		_fail("the strip drew %d cancel buttons for one booking and a page of fixed dates" % cancels)


## A refusal must be visible. The same verb again is the refusal that is easiest
## to trigger and hardest to explain if it is silent.
func _check_a_refusal_is_printed(panel, state) -> void:
	var total: int = state.year * 12 + (state.month - 1) + 4
	var twin := Calendar.make_entry(
		K.KIND_DIPLOMATIC, total / 12, total % 12 + 1, 2, "state_visit", "DEU"
	)
	var before: int = state.appointments.size()
	var result: Dictionary = Calendar.book(state, twin)
	if bool(result["ok"]):
		_fail("the same verb booked twice -- the previous check left one in flight")
		return
	if state.appointments.size() != before:
		_fail("a refused booking still changed the register")

	panel._status.text = ""
	panel._on_book.call()
	# _on_book reads the form rather than this entry, so the only thing asserted
	# here is that the status line is WRITTEN to at all -- a panel that leaves it
	# blank after a press is one where a refusal goes unsaid.
	if panel._status.text.is_empty():
		_fail("pressing Book left the status line empty -- a refusal the player cannot read is `refused_by_partner` a fourth time")


## B8 (playtest 2026-09-16): the away suffix printed both month tokens even when
## the whole trip sat inside one month -- "(away 08-16, MAR-MAR)" -- which every
## single-month trip renders as a duplicate. One month prints once; a trip that
## crosses a month boundary keeps the span form. Exercised through the panel's
## own line builder, so a formatter regression fails here and not on a player's
## screen. Checked as "no repeated token" rather than the exact string, so a
## later copy edit that keeps the rule stays green.
func _check_away_line_months(panel, state) -> void:
	var year: int = state.year
	# Far enough ahead that the horizon and the passed-date refusals stay out of
	# the way; the formatter reads only the entry.
	var month: int = state.month + 3 if state.month <= 8 else 3
	var single := Calendar.make_entry(
		K.KIND_DIPLOMATIC, year, month, 20, "state_visit", "DEU", "", "", "", "", 3
	)
	var one: String = panel._booking_text(single)
	if not one.contains("(away "):
		_fail("a booking with travel produced no away suffix: '%s'" % one)
	var halves: PackedStringArray = one.split("(")
	var away: String = halves[halves.size() - 1]
	var tokens: PackedStringArray = away.replace("–", " ").replace("-", " ").replace(",", " ").split(" ", false)
	for i in tokens.size():
		for j in range(i + 1, tokens.size()):
			if tokens[i] == tokens[j] and String(tokens[i]).length() == 3 \
					and String(tokens[i]) == String(tokens[i]).to_upper():
				_fail("the away suffix repeats a month token: '%s'" % one)
				return

	var crossing := Calendar.make_entry(
		K.KIND_DIPLOMATIC, year, month, 2, "summit", "ITA", "", "", "", "", 6
	)
	var two: String = panel._booking_text(crossing)
	var d: Dictionary = Calendar.departure(crossing)
	var h: Dictionary = Calendar.arrival_home(crossing)
	if int(d["month"]) == int(h["month"]):
		_fail("the multi-month fixture did not actually cross a month boundary")
		return
	var dm: String = panel.ClockCluster.MONTH_NAMES[int(d["month"]) - 1].substr(0, 3)
	var hm: String = panel.ClockCluster.MONTH_NAMES[int(h["month"]) - 1].substr(0, 3)
	if not two.contains(dm) or not two.contains(hm):
		_fail("a month-crossing trip lost one of its months: '%s'" % two)
	if not two.contains("–"):
		_fail("the two-month away form lost its month span dash: '%s'" % two)


func _refresh(panel) -> void:
	panel.show()
	panel.mark_dirty()
	panel._process(0.0)


## Scoped to the strip's own container. A walk from the scene root would read the
## top bar's date and pass whatever this panel drew.
func _strip_text(panel) -> String:
	var text := ""
	for node in _walk(panel._body):
		if node is Label:
			text += node.text + "\n"
	return text


func _walk(node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_calendar_panel: all checks passed")
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
	_main.queue_free()
	quit(0 if _failures.is_empty() else 1)
