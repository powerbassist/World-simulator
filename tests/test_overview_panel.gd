extends SceneTree

## Headless test: godot --headless --script res://tests/test_overview_panel.gd
## Non-zero exit on any failure.
##
## U3's Overview test. Three things, all of which fail silently on screen --
## which is the reason they are tested at all (CLAUDE.md: new UI behaviour that
## can fail silently needs a test):
##
## 1. A brand-new game has no history, so every trend is unknown. The panel must
##    say so with an em dash rather than render a confident +0.0.
## 2. After a run, the trends must actually be there -- a delta that silently
##    stays "—" forever looks exactly like a young game.
## 3. Approval on this tab is the POLLED figure. A leak of the true number looks
##    completely normal, sits one point from the polled one, and quietly makes
##    the poll noise pointless.
##
## Driven a frame at a time via extends SceneTree, because a Control outside the
## tree has not run _ready() -- docs/engine-decision.md.

const PollNoise = preload("res://src/ui/poll_noise.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")
const Trends = preload("res://src/ui/trends.gd")
const Society = preload("res://src/sim/society.gd")
const Campaign = preload("res://src/sim/campaign.gd")

const DAYS_PER_MONTH := 31

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false

	if _main._overview_panel == null:
		_fail("main scene did not build an overview panel")
		_finish()
		return false

	_main._windows.open("overview")

	_check_fresh_game_has_no_trends()
	_check_countdown_matches_the_player_clock()
	_check_trends_appear_after_a_run()
	_check_approval_is_polled()
	_check_services_are_silent_then_spoken()

	_finish()
	return false


## V1.5a. Both halves, because both can fail silently and one of them is the failure
## this project has now hit four times -- a figure computed, stored, and displayed
## nowhere (V1.3b's `refused_by_partner`, V1.3f's `act_reason()`).
##
## The silent half matters as much as the spoken one: a permanent "delivery 100 %" row
## would say nothing in every game that never passes a `society` law, which is the
## line-that-says-nothing failure the alliance row beside it already avoids.
func _check_services_are_silent_then_spoken() -> void:
	var ns = _main._state.player()

	ns.corruption = 0.0
	for key in ns.service_quality.keys():
		ns.service_quality[key] = ns.start_service_quality[key]
	_main._overview_panel.mark_dirty()
	_main._overview_panel._process(0.0)
	if _column_text("government").to_lower().contains("delivers"):
		_fail("the delivery line is printed with no corruption -- a row that says nothing in most games")

	# Now move it, and the panel must say so. Driven through the real writer rather
	# than by poking the stock, so a broken dispatch fails here too.
	ns.corruption = 0.6
	for _m in range(24):
		Society.tick_month(_main._state)
	_main._overview_panel.mark_dirty()
	_main._overview_panel._process(0.0)

	var text := _column_text("government").to_lower()
	if not text.contains("delivers"):
		_fail("corruption moved and the overview never mentioned delivery -- computed and displayed nowhere")
	if not text.contains("baseline"):
		_fail("service quality moved off its baseline and the overview never said so")


## Nothing has been simulated yet, so all five watched figures are unknown.
func _check_fresh_game_has_no_trends() -> void:
	if not _main._state.history.is_empty():
		_fail("history was not empty at start, so this check proves nothing")
		return

	var moving := _column_text("moving")
	var dashes := moving.count("—")
	if dashes != Trends.WATCHED.size():
		_fail("with no history the Moving column showed %d em dashes, expected %d: %s" % [
			dashes, Trends.WATCHED.size(), moving
		])

	if _lead_text().strip_edges().is_empty():
		_fail("the lead line is empty on a fresh game")


## V2.8.1. The Overview countdown, Campaign's months-to-vote and the Diary's
## soonest fixed row must name the same election. The playtest caught Overview
## on the Assembly clock (41 months) while Campaign and the Diary said 16: the
## column is labelled "until the vote", and the vote that ends the player's term
## is the executive one where the nation elects it separately (France's
## two-clock init in elections.gd). Read off the live panel rather than the
## field, so a wrong clock wired into the column fails here and not in a
## playtest. Runs on the fresh game, before anything advances the clock.
func _check_countdown_matches_the_player_clock() -> void:
	var ns = _main._state.player()
	var expected: int = Campaign.months_to_election(_main._state, ns)
	var text := _column_text("election")
	var months := _first_int(text)
	if months < 0:
		_fail("the election column prints no month count: %s" % text)
	elif months != expected:
		_fail("the election column counts %d months to the vote but the campaign clock says %d" % [months, expected])


func _check_trends_appear_after_a_run() -> void:
	_advance_months(Trends.TREND_MONTHS + 2)

	var moving := _column_text("moving")
	if moving.contains("—"):
		_fail("a watched figure was still unknown after %d months: %s" % [Trends.TREND_MONTHS + 2, moving])
	if not moving.contains("pp"):
		_fail("the Moving column shows no signed change after a run: %s" % moving)

	if _lead_text().strip_edges().is_empty():
		_fail("the lead line is empty after a run")


## The panel must print the poll, not the truth. Months are advanced until the
## two round differently, so the assertion cannot pass by coincidence.
func _check_approval_is_polled() -> void:
	var separated := false
	for _i in range(24):
		if _rounded_polled() != _rounded_true():
			separated = true
			break
		_advance_months(1)

	if not separated:
		_fail("poll noise never moved the rounded approval away from the true figure in 24 months")
		return

	var text := _column_text("election")
	var polled := "Polling %d%%" % _rounded_polled()
	var truth := "Polling %d%%" % _rounded_true()
	if not text.contains(polled):
		_fail("the election column does not show the polled approval '%s': %s" % [polled, text])
	if text.contains(truth):
		_fail("the election column shows the TRUE approval '%s', which the player must never see" % truth)


# --- helpers ----------------------------------------------------------------

func _rounded_polled() -> int:
	var ns = _main._state.player()
	return int(round(PollNoise.displayed(
		PollNoise.poll_id(_main._state.year, _main._state.month),
		PollingPanel.HEADLINE_KEY,
		ns.overall_approval_pct
	)))


func _rounded_true() -> int:
	return int(round(_main._state.player().overall_approval_pct))


func _advance_months(months: int) -> void:
	var clock: Node = _main.get_node("Clock")
	for _d in range(DAYS_PER_MONTH * months):
		clock.advance_one_day()
	_main._overview_panel.mark_dirty()
	_main._overview_panel._process(0.0)


func _lead_text() -> String:
	return _main._overview_panel._lead.text


## The first integer in a column's text, or -1 when it prints none — the
## election figure ("16 months") leads the column, ahead of the date and the
## polling line, so the first number is the countdown.
func _first_int(text: String) -> int:
	var regex := RegEx.new()
	regex.compile("\\d+")
	var found := regex.search(text)
	return int(found.get_string()) if found != null else -1


func _column_text(id: String) -> String:
	var body = _main._overview_panel._columns.get(id)
	if body == null:
		_fail("the overview panel has no '%s' column" % id)
		return ""
	return _collect_text(body)


## Skips nodes already queued for deletion. The panels rebuild their bodies with
## queue_free(), which does not take effect until the end of the frame -- and
## this test drives several refreshes inside one frame, so the outgoing labels
## are still in the tree alongside the incoming ones.
func _collect_text(node) -> String:
	var out := ""
	if node.is_queued_for_deletion():
		return out
	if node is Label or node is Button:
		out += node.text + "\n"
	for child in node.get_children():
		out += _collect_text(child)
	return out


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_overview_panel: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
