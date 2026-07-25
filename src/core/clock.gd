class_name Clock
extends Node

## Daily-tick game clock. No UI knowledge — emits signals, exposes commands.
## advance_one_day() is public so headless tests can drive the calendar
## deterministically without waiting on real time.

signal day_advanced(year: int, month: int, day: int)
signal month_elapsed(year: int, month: int)

const DAYS_IN_MONTH: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const SPEED_DAYS_PER_SECOND: Array[float] = [1.0, 3.0, 7.0]

var year: int = 2026
var month: int = 1
var day: int = 1

var paused: bool = false
var speed: int = 1

var _accum_seconds: float = 0.0


func _process(delta: float) -> void:
	if paused:
		return
	_accum_seconds += delta
	var day_length := 1.0 / SPEED_DAYS_PER_SECOND[speed - 1]
	while _accum_seconds >= day_length:
		_accum_seconds -= day_length
		advance_one_day()


func toggle_pause() -> void:
	paused = not paused


func set_speed(new_speed: int) -> void:
	speed = clampi(new_speed, 1, SPEED_DAYS_PER_SECOND.size())


func advance_one_day() -> void:
	day += 1
	if day > _days_in_month(month, year):
		day = 1
		month += 1
		if month > 12:
			month = 1
			year += 1
		month_elapsed.emit(year, month)
	day_advanced.emit(year, month, day)


func _days_in_month(m: int, y: int) -> int:
	if m == 2 and _is_leap_year(y):
		return 29
	return DAYS_IN_MONTH[m - 1]


func _is_leap_year(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
