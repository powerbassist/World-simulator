extends VBoxContainer

## The president's word, in the Diary -- V5.2b b2. The author's call (2026-10-24,
## "Oui, parole donnée"): a promise binds even when the lever failed, so every one
## in flight is listed here with its date, and each judged one with its verdict --
## kept, or a lie revealed (an IOU: paid, or a betrayal). The player who forgets a
## promise is not spared it; they were shown it.
##
## It takes ROWS already worded by the wiring (audience_driver.gd), so this file
## reads no register. Hidden while there is nothing to show: an empty heading
## would be prose for nothing.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## Past this many words the list scrolls in a box of CAP_PX: it sits under the
## Diary's day list, outside its scroll, and a long term's dozen words squeezed
## that scroll to nothing -- "Book here" fell out of view and three requests
## lapsed into refusals (final pre-gate TAKE 2). About three body lines.
const FOLD_AT := 3
const CAP_PX := 72.0


func _init() -> void:
	name = "PromiseList"  # i18n: ok
	add_theme_constant_override("separation", 4)
	visible = false


## `given`: [String], one line a commitment in flight. `judged`: [{text, kept}].
func show_rows(given: Array, judged: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	visible = not (given.is_empty() and judged.is_empty())
	if not visible:
		return
	PanelKit.heading(self, tr("Your word"))
	var host: Control = self
	if given.size() + judged.size() > FOLD_AT:
		var scroll := ScrollContainer.new()
		scroll.name = "Words"  # i18n: ok a node name, found by tests
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size.y = CAP_PX * UiTheme.text_scale()
		add_child(scroll)
		host = VBoxContainer.new()
		host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host.add_theme_constant_override("separation", 4)
		scroll.add_child(host)
	for text in given:
		PanelKit.line(host, String(text), PanelKit.Tone.PLAIN)
	for row in judged:
		# RF7: the verdict's word (kept, broken) is in the line; the shared tone colours it.
		ResultTone.tint(PanelKit.line(host, String(row["text"])), ResultTone.GOOD if bool(row["kept"]) else ResultTone.BAD)


func lines() -> PackedStringArray:
	var out := PackedStringArray()
	# In tree order, through the scroll a long list sits in.
	for child in find_children("*", "Control", true, false):  # i18n: ok a class name
		if child is Label:
			out.append((child as Label).text)
		elif child is RichTextLabel:
			out.append((child as RichTextLabel).get_parsed_text())
	return out
