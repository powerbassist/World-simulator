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
	var r := Rect2(Vector2(1, 1), size - Vector2(2, 2))
	var c := float(UiTheme.R_SMALL)
	for run in [[r.position + Vector2(c, 0), Vector2(r.end.x - c, r.position.y)], [Vector2(r.position.x + c, r.end.y), r.end - Vector2(c, 0)],
			[r.position + Vector2(0, c), Vector2(r.position.x, r.end.y - c)], [Vector2(r.end.x, r.position.y + c), r.end - Vector2(0, c)]]:
		draw_dashed_line(run[0], run[1], accent, 1.5, 4.0)
	var font := get_theme_default_font()
	var fs := roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())
	var w := size.x - PAD * 2.0
	draw_string(font, Vector2(PAD, PAD + fs), DiaryDay.fit(_title, font, fs, w), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, accent)  # i18n: row-ok the page's shown text
	draw_string(font, Vector2(PAD, PAD + fs * 2.2), DiaryDay.fit(_line, font, fs, w), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, accent)  # i18n: row-ok the page's shown text
