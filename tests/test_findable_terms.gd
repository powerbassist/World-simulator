extends SceneTree

## Headless test: godot --headless --script res://tests/test_findable_terms.gd
## Non-zero exit on any failure.
##
## V5.1-d1c, G12 of the play gate: the author never saw a glossary tooltip
## ("j'ai pas vu les infobulles"). Three things make a term findable (the parent's
## call on the proposal: 1 + 2 + 3):
##   1. the engine's dashes under a term draw at full opacity (underline_alpha
##      100, was the engine's 50), still the text's own colour, no accent;
##   2. the pointer says it: a help cursor over a term, a pointing hand over a
##      person's name, and back off them;
##   3. a first-use hint: one note on the first game a profile plays, whose own
##      body marks a term to try on the spot; never a second time (a settings flag).

const TermText = preload("res://src/ui/term_text.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const GlossaryHint = preload("res://src/ui/glossary_hint.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_check_the_underline()
	_check_the_cursor()
	_check_the_first_use_hint()
	_finish()
	return true


func _check_the_underline() -> void:
	var theme: Theme = UiTheme.build()
	if theme.get_constant("underline_alpha", "RichTextLabel") != 100:
		_fail("a term's dashes draw at %d%% opacity, not 100" % theme.get_constant("underline_alpha", "RichTextLabel"))


func _check_the_cursor() -> void:
	var label = TermText.new()
	root.add_child(label)
	label.set_marked("[g=approval]approval[/g] and [p=FRA_aumont]Cécile Aumont[/p]")
	label.meta_hover_started.emit("term:approval")
	if label.mouse_default_cursor_shape != Control.CURSOR_HELP:
		_fail("over a term the pointer is shape %d, not the help cursor" % label.mouse_default_cursor_shape)
	label.meta_hover_ended.emit("term:approval")
	if label.mouse_default_cursor_shape != Control.CURSOR_ARROW:
		_fail("off a term the pointer stayed shape %d" % label.mouse_default_cursor_shape)
	label.meta_hover_started.emit("person:FRA_aumont")
	if label.mouse_default_cursor_shape != Control.CURSOR_POINTING_HAND:
		_fail("over a name the pointer is shape %d, not the pointing hand" % label.mouse_default_cursor_shape)
	label.meta_hover_ended.emit("person:FRA_aumont")
	if label.mouse_default_cursor_shape != Control.CURSOR_ARROW:
		_fail("off a name the pointer stayed shape %d" % label.mouse_default_cursor_shape)
	label.queue_free()


## On a private settings file: tests in one run share a user dir, and every main
## that boots offers the hint, so the shared file's flag is anyone's.
const HINT_CFG := "user://test_findable_terms_hint.cfg"


func _check_the_first_use_hint() -> void:
	var source := FileAccess.get_file_as_string("res://src/ui/world_news.gd")
	if not source.contains("GlossaryHint.offer(stack)"):
		_fail("a game's setup does not offer the glossary hint")
	DirAccess.remove_absolute(HINT_CFG)
	var inbox = _main._hud.inbox
	var before: Array = inbox._bodies.keys()
	GlossaryHint.offer(inbox, HINT_CFG)
	var hints := 0
	for id in inbox._bodies:
		if before.has(id):
			continue
		var body = inbox._bodies[id]
		if String(body.text).contains("term:") and body.get_parsed_text().to_lower().contains("dotted"):
			hints += 1
	if hints != 1:
		_fail("a profile's first offer shows %d glossary hints with a term to try, not one" % hints)
	var count: int = inbox.card_count()
	GlossaryHint.offer(inbox, HINT_CFG)
	if inbox.card_count() != count:
		_fail("the glossary hint came back a second time")
	DirAccess.remove_absolute(HINT_CFG)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_findable_terms: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
