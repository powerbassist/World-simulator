extends SceneTree

## Headless test: godot --headless --script res://tests/test_date_text.gd
## Non-zero exit on any failure.
##
## V5.1b2. Every date the interface prints goes through DateText, so a language
## translates the month names once. The Diary used to read the English table
## directly ("Calendrier -- JAN 2026" beside a clock that said JANV); this pins the
## formatter and fails if a panel indexes a month table of its own again.

const DateText = preload("res://src/ui/date_text.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []


func _init() -> void:
	Strings.set_language("en")
	if DateText.day_month_year(1, 1, 2026) != "01 JAN 2026":
		_fail("an English date should read 01 JAN 2026, got %s" % DateText.day_month_year(1, 1, 2026))
	if DateText.month_year(5, 2027) != "MAY 2027" or DateText.day_month(3, 12) != "03 DEC":
		_fail("month_year / day_month in English: %s, %s" % [DateText.month_year(5, 2027), DateText.day_month(3, 12)])
	if DateText.month_long(1) != "January" or DateText.month_long(12) != "December":
		_fail("the long names should be English in English")
	Strings.set_language("fr")
	# The same call under French gives the translated abbreviation, everywhere at once.
	if DateText.month(1) == "JAN" or DateText.day_month_year(1, 1, 2026) != "01 %s 2026" % DateText.month(1):
		_fail("a French date should use the translated month, got %s" % DateText.day_month_year(1, 1, 2026))
	for m in range(1, 13):
		if DateText.month(m).strip_edges() == "":
			_fail("month %d has no name in French" % m)
	Strings.set_language("en")
	# Out-of-range months clamp rather than index past the table.
	if DateText.month(0) != "JAN" or DateText.month(13) != "DEC":
		_fail("a month outside 1-12 should clamp")
	_check_no_private_month_tables()
	_check_local_stamp()
	_finish()
	quit(1 if not _failures.is_empty() else 0)


## V5.1-c4.1 (QA #48): the save list printed a save's time in UTC -- 20:35 for a
## save made at 22:35 in Paris. The stamp is local: UTC plus the bias in minutes,
## rolling the date when the hour does.
func _check_local_stamp() -> void:
	var at := int(Time.get_unix_time_from_datetime_string("2026-10-21T20:35:00"))
	if DateText.local_stamp(at, 120) != "2026-10-21 22:35":
		_fail("20:35 UTC at +120 min should read 2026-10-21 22:35, got %s" % DateText.local_stamp(at, 120))
	var late := int(Time.get_unix_time_from_datetime_string("2026-10-21T23:30:00"))
	if DateText.local_stamp(late, 120) != "2026-10-22 01:30":
		_fail("23:30 UTC at +120 min should roll to 2026-10-22 01:30, got %s" % DateText.local_stamp(late, 120))
	if DateText.local_stamp(at, -300) != "2026-10-21 15:35":
		_fail("20:35 UTC at -300 min should read 2026-10-21 15:35, got %s" % DateText.local_stamp(at, -300))


## The English table lives in date_text.gd (and clock_cluster.gd aliases it for callers
## that want the names); no panel may index a month table itself, which is how the
## Diary came to print a month the clock did not.
func _check_no_private_month_tables() -> void:
	for name in DirAccess.get_files_at("res://src/ui"):
		if not String(name).ends_with(".gd") or name == "date_text.gd":
			continue
		var text := FileAccess.get_file_as_string("res://src/ui/%s" % name)
		for line in text.split("\n"):
			# Any month table: the council kept its own ("Jan", "Feb" ... read as MONTHS[i])
			# beside a clock that printed JANV, until V5.1b3.
			if line.contains("MONTH_NAMES[") or line.contains("MONTH_NAMES.size") or line.contains("MONTHS[") \
					or line.to_lower().contains("\"jan\", \"feb\""):
				_fail("%s reads a month table directly instead of DateText: %s" % [name, line.strip_edges()])


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_date_text: all checks passed")
	else:
		for f in _failures:
			printerr(f)
