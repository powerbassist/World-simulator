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
	for text in given:
		PanelKit.line(self, String(text), PanelKit.Tone.PLAIN)
	for row in judged:
		# RF7: the verdict's word (kept, broken) is in the line; the shared tone colours it.
		ResultTone.tint(PanelKit.line(self, String(row["text"])), ResultTone.GOOD if bool(row["kept"]) else ResultTone.BAD)


func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for child in get_children():
		if child is Label:
			out.append((child as Label).text)
		elif child is RichTextLabel:
			out.append((child as RichTextLabel).get_parsed_text())
	return out
