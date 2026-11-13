extends RefCounted

## The ONE place a date becomes text -- V5.1b2. Every month name and every date the
## interface prints goes through here, so a language translates twelve names once
## and no panel can show "JAN" beside a clock that says "JANV" (the Diary did: it read
## the English table directly while the clock and the ribbon translated it).
##
## The names are msgids in the usual way: the English stays in the table below,
## marked for the extractor, and is wrapped at the use site.

const Strings = preload("res://src/ui/strings.gd")

const SHORT: Array[String] = [
	"JAN", "FEB", "MAR", "APR", "MAY", "JUN",  # i18n: msgid
	"JUL", "AUG", "SEP", "OCT", "NOV", "DEC",  # i18n: msgid
]

const LONG: Array[String] = [
	"January", "February", "March", "April", "May", "June",  # i18n: msgid
	"July", "August", "September", "October", "November", "December",  # i18n: msgid
]


## The three-letter name of month 1-12 in the current language ("JAN", "JANV").
static func month(month_number: int) -> String:
	return Strings.t(SHORT[clampi(month_number, 1, 12) - 1])


## The full name of month 1-12 ("January", "janvier").
static func month_long(month_number: int) -> String:
	return Strings.t(LONG[clampi(month_number, 1, 12) - 1])


## "01 JAN 2026".
static func day_month_year(day: int, month_number: int, year: int) -> String:
	return "%02d %s %d" % [day, month(month_number), year]


## "JAN 2026".
static func month_year(month_number: int, year: int) -> String:
	return "%s %d" % [month(month_number), year]


## "2026-10-21 22:35": a real-world moment (a save's file time), in the player's
## local time -- `bias_minutes` is the offset from UTC, as the OS reports it.
static func local_stamp(unix: int, bias_minutes: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix + bias_minutes * 60)
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]


## "01 JAN".
static func day_month(day: int, month_number: int) -> String:
	return "%02d %s" % [day, month(month_number)]


const WEEKDAYS: Array[String] = [
	"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat",  # i18n: msgid
]


## "Fri 16/04/2027": the weekday and the full date, the way the title bar's clock writes it
## (the audience's Counter field opens on days, never on a month).
static func weekday_full(day: int, month_number: int, year: int) -> String:
	return "%s %02d/%02d/%d" % [weekday(day, month_number, year), day, month_number, year]


## The three-letter weekday name of a date, in the current language.
static func weekday(day: int, month_number: int, year: int) -> String:
	return Strings.t(WEEKDAYS[weekday_index(day, month_number, year)])


## The days of a month, leap years by the Gregorian rule: the one copy the audience's field and its default share.
static func days_in(month_number: int, year: int) -> int:
	var next := Time.get_unix_time_from_datetime_dict({"year": year + (1 if month_number == 12 else 0), "month": 1 if month_number == 12 else month_number + 1,
		"day": 1, "hour": 0, "minute": 0, "second": 0})
	return int(Time.get_datetime_dict_from_unix_time(next - 86400)["day"])


## 0 for Sunday, as the engine counts.
static func weekday_index(day: int, month_number: int, year: int) -> int:
	var stamp := Time.get_unix_time_from_datetime_dict({"year": year, "month": month_number, "day": day, "hour": 0, "minute": 0, "second": 0})
	return int(Time.get_datetime_dict_from_unix_time(stamp)["weekday"])
