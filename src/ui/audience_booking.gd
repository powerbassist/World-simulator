extends VBoxContainer

## Booking an audience, in the Diary -- V5.2b. A request's "Book a day…" opens the
## Diary on this block: who asks, what they want, and the days THEY offer
## (`Audiences.offered_dates()`: two inside the request's window). A free day is a
## button; a taken one is shown disabled with the Diary's own refusal on its hover,
## so the player sees why, not just that (B2). One booking route, the Diary's, as
## G13 asked of the visits ("two routes doing the same verb differently").
##
## It books nothing itself: a pressed day emits `booked`, and the wiring calls
## `Audiences.book()` -- the sim's command (AGENTS.md rule 2).

signal booked(request_id: String, date: Dictionary)

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")

var _request_id := ""


func _init() -> void:
	name = "AudienceBooking"  # i18n: ok
	add_theme_constant_override("separation", 4)
	visible = false


func request_id() -> String:
	return _request_id


## `row` is the lane's row ({id, person, ask}); `dates` the offered days
## [{year, month, day, free, reason}].
func open_for(row: Dictionary, dates: Array) -> void:
	_request_id = String(row["id"])
	for child in get_children():
		remove_child(child)
		child.queue_free()
	PanelKit.heading(self, Strings.t("Audience: %s") % String(row.get("person", "")))
	PanelKit.line(self, String(row.get("ask", "")), PanelKit.Tone.PLAIN)
	var days := PanelKit.buttons(self)
	for date in dates:
		var day := Button.new()
		day.text = Strings.t("Book %s") % DateText.day_month(int(date["day"]), int(date["month"]))
		day.disabled = not bool(date.get("free", false))
		day.tooltip_text = String(date.get("reason", "")) if day.disabled else ""
		var picked: Dictionary = {"year": int(date["year"]), "month": int(date["month"]), "day": int(date["day"])}
		day.pressed.connect(func() -> void: booked.emit(_request_id, picked))
		days.add_child(day)
	if dates.is_empty():
		PanelKit.line(self, Strings.t("They offer no day you can take."))
	visible = true


func close() -> void:
	_request_id = ""
	visible = false
