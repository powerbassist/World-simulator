extends SceneTree

## Headless test: godot --headless --script res://tests/test_chart_series.gd
## Non-zero exit on any failure.
##
## V5.2-0a. The charts' series come off GameState.history and nothing else: the
## term's window is read off the nation's months_in_term (a load mid-term must not
## draw the whole game as "this term"), a missing figure is no point rather than a
## zero, and approval is the run of PUBLISHED polls -- each month through PollNoise
## with that month's poll id -- so the model's true figure never reaches a chart.

const ChartSeries = preload("res://src/ui/chart_series.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")


class FakeNation:
	var months_in_term := 5


class FakeState:
	var history: Array[Dictionary] = []
	var nation := FakeNation.new()

	func player():
		return nation


var _failures: Array[String] = []


func _init() -> void:
	var state := FakeState.new()
	for i in 30:
		var entry := {"year": 2026 + i / 12, "month": i % 12 + 1, "overall_approval_pct": 50.0,
			"bloc_approval": {"workers": 40.0}, "growth_annual_pct": float(i)}
		if i == 28:
			entry.erase("growth_annual_pct")
		state.history.append(entry)

	var window := ChartSeries.term_window(state)
	if window.size() != 6 or int(window[-1]["growth_annual_pct"]) != 29:
		_fail("months_in_term 5 over 30 months gave %d entries ending %s" % [window.size(), window[-1]])
	state.nation.months_in_term = 50
	if ChartSeries.term_window(state).size() != 30:
		_fail("a term longer than the history did not stop at the history's start")

	var growth := ChartSeries.values(state.history, "growth_annual_pct")
	if growth.size() != 29:
		_fail("a month without the figure became a point (%d values from 30 months, one missing)" % growth.size())

	var shown := ChartSeries.polled(state.history, "overall_approval_pct", "overall")
	var moved := 0
	for i in shown.size():
		var e: Dictionary = state.history[i]
		var expect := PollNoise.displayed(PollNoise.poll_id(int(e["year"]), int(e["month"])), "overall", 50.0)
		if absf(shown[i] - expect) > 1e-9:
			_fail("month %d plots %.3f, not the poll published that month (%.3f)" % [i, shown[i], expect])
			break
		if absf(shown[i] - 50.0) > 1e-6:
			moved += 1
	if moved == 0:
		_fail("every plotted approval equals the truth: the chart is not reading the polls")
	var bloc := ChartSeries.polled(state.history, "bloc_approval", "workers")
	if bloc.size() != 30 or absf(bloc[0] - PollNoise.displayed(PollNoise.poll_id(2026, 1), "workers", 40.0)) > 1e-9:
		_fail("a bloc's line is not its published poll")

	if ChartSeries.months(window)[0] != [int(window[0]["year"]), int(window[0]["month"])]:
		_fail("months() does not follow the entries")

	if _failures.is_empty():
		print("test_chart_series: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
