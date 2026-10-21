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


## "01 JAN".
static func day_month(day: int, month_number: int) -> String:
	return "%02d %s" % [day, month(month_number)]
