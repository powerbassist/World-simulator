extends SceneTree

## Headless test: godot --headless --script res://tests/test_clock.gd
## Non-zero exit on any failure.
##
## GDScript lambdas snapshot outer locals by value, not by reference, so
## signal-count accumulators here use a single-element array as a mutable cell.

const Clock = preload("res://src/core/clock.gd")


func _init() -> void:
	var failures: Array[String] = []

	var clock := Clock.new()
	clock.year = 2026
	clock.month = 1
	clock.day = 1

	var month_elapsed_count := [0]
	clock.month_elapsed.connect(func(_y, _m): month_elapsed_count[0] += 1)

	var days_in_2026 := 365  # 2026 is not a leap year
	for i in range(days_in_2026):
		clock.advance_one_day()

	if month_elapsed_count[0] != 13:  # PROOF: deliberately red
		failures.append("month_elapsed fired %d times over one year, expected 12" % month_elapsed_count[0])
	if clock.year != 2027 or clock.month != 1 or clock.day != 1:
		failures.append("after 365 days from 2026-01-01, expected 2027-01-01, got %d-%d-%d" % [clock.year, clock.month, clock.day])

	var pause_clock := Clock.new()
	if pause_clock.paused:
		failures.append("clock starts paused, expected running")
	pause_clock.toggle_pause()
	if not pause_clock.paused:
		failures.append("toggle_pause did not pause")
	var day_before := pause_clock.day
	pause_clock._process(10.0)
	if pause_clock.day != day_before:
		failures.append("date advanced while paused")
	pause_clock.toggle_pause()

	var speed_clock := Clock.new()
	var advanced_count := [0]
	speed_clock.day_advanced.connect(func(_y, _m, _d): advanced_count[0] += 1)
	var days_at := []
	for s in [1, 2, 3]:
		speed_clock.set_speed(s)
		advanced_count[0] = 0
		speed_clock._process(1.0)
		days_at.append(advanced_count[0])
	if not (days_at[0] < days_at[1] and days_at[1] < days_at[2]):
		failures.append("speeds not strictly increasing: %s" % [days_at])

	if failures.is_empty():
		print("test_clock: all checks passed")
		quit(0)
	else:
		for f in failures:
			printerr(f)
		quit(1)
