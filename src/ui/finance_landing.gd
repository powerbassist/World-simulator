extends Control

## Where the programme on the page beside the rail would land in the finance bill -- G3 S4, Register in C: a dashed
## place in the accent, the same mark as a bookable day in the Diary (diary_day.gd), under the bill's changes. It is a
## place, not a change: nothing is in the bill until the page's own button puts it there.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const DiaryDay = preload("res://src/ui/diary_day.gd")

const PAD := 10.0

var _title := ""
var _line := ""


## {title, line} from the page (register_programme.gd landing()); {} hides the place.
func show_for(place: Dictionary) -> void:
	visible = not place.is_empty()
	custom_minimum_size.y = (UiTheme.SIZE_SMALL * 2.0 + 18.0) * UiTheme.text_scale()  # a text size moves it, the same words or not
	if String(place.get("title", "")) == _title and String(place.get("line", "")) == _line:
		return
	_title = String(place.get("title", ""))
	_line = String(place.get("line", ""))
	queue_redraw()


func title() -> String:
	return _title


func _draw() -> void:
	var accent := UiTheme.accent()
	# Inside the rail's padding on the right as on the left (Diane's T3 on #447): the scroll's column runs to the rim.
	var r := Rect2(Vector2(1, 1), size - Vector2(2.0 + UiTheme.PAD_PANE, 2.0))
	var c := float(UiTheme.R_SMALL)
	for run in [[r.position + Vector2(c, 0), Vector2(r.end.x - c, r.position.y)], [Vector2(r.position.x + c, r.end.y), r.end - Vector2(c, 0)],
			[r.position + Vector2(0, c), Vector2(r.position.x, r.end.y - c)], [Vector2(r.end.x, r.position.y + c), r.end - Vector2(0, c)]]:
		draw_dashed_line(run[0], run[1], accent, 1.5, 4.0)
	# The corners, rounded as the Diary's bookable place's (diary_day.gd _dashed; pass 2 T4 on #447).
	draw_arc(r.position + Vector2(c, c), c, PI, PI * 1.5, 6, accent, 1.5)
	draw_arc(Vector2(r.end.x - c, r.position.y + c), c, PI * 1.5, TAU, 6, accent, 1.5)
	draw_arc(r.end - Vector2(c, c), c, 0.0, PI * 0.5, 6, accent, 1.5)
	draw_arc(Vector2(r.position.x + c, r.end.y - c), c, PI * 0.5, PI, 6, accent, 1.5)
	var font := get_theme_default_font()
	var fs := roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())
	var w := size.x - PAD * 2.0 - UiTheme.PAD_PANE
	draw_string(font, Vector2(PAD, PAD + fs), DiaryDay.fit(_title, font, fs, w), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, accent)  # i18n: row-ok the page's shown text
	draw_string(font, Vector2(PAD, PAD + fs * 2.2), DiaryDay.fit(_line, font, fs, w), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, accent)  # i18n: row-ok the page's shown text
