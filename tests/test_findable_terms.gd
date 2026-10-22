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


## A private settings file: tests in one run share a user dir, and every main that
## boots offers the hint, so the shared file's flag is anyone's.
const HINT_CFG := "user://test_findable_terms_hint.cfg"
const SLOT := "__test_findable_terms__"
const SaveManager = preload("res://src/core/save_manager.gd")


func _init() -> void:
	GlossaryHint.config_path = HINT_CFG
	DirAccess.remove_absolute(HINT_CFG)
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_check_the_underline()
		_check_the_cursor()
		_check_the_first_use_hint()
		# QA on #72: a profile's first session that begins with a LOAD. Saved here,
		# then a fresh profile boots a game with the save pending.
		_main._on_save_requested(SLOT)
		GlossaryHint.reset()
		_main.queue_free()
		_main = load("res://src/ui/main.tscn").instantiate()
		_main.pending_load_slot = SLOT
		root.add_child(_main)
	elif _frame == 7:
		_check_a_load_keeps_the_hint()
		_check_hint_reset()
		SaveManager.delete_slot(SLOT)
		DirAccess.remove_absolute(HINT_CFG)
		_finish()
		return true
	return false


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


func _hints(inbox) -> int:
	var hints := 0
	for id in inbox._bodies:
		var body = inbox._bodies[id]
		if String(body.text).contains("term:") and body.get_parsed_text().to_lower().contains("dotted"):
			hints += 1
	return hints


## A fresh (private) profile's first game shows the note once, with a term to try;
## the same inbox is not offered it twice.
func _check_the_first_use_hint() -> void:
	var source := FileAccess.get_file_as_string("res://src/ui/world_news.gd")
	if not source.contains("GlossaryHint.offer(stack)"):
		_fail("a game's setup does not offer the glossary hint")
	var inbox = _main._hud.inbox
	if _hints(inbox) != 1:
		_fail("a profile's first game shows %d glossary hints with a term to try, not one" % _hints(inbox))
	var count: int = inbox.card_count()
	GlossaryHint.offer(inbox)
	if inbox.card_count() != count:
		_fail("the glossary hint came back a second time")


func _check_a_load_keeps_the_hint() -> void:
	if _hints(_main._hud.inbox) != 1:
		_fail("a profile's first session that began with a load shows %d glossary hints, not one" % _hints(_main._hud.inbox))


## `hint reset`: the dev console re-arms the note (any run on a real profile spends it).
func _check_hint_reset() -> void:
	var console = null
	for child in _main.get_children():
		if child.has_method("run_command"):
			console = child
	if console == null:
		_fail("the game scene has no dev console")
		return
	console.run_command("hint reset")
	var cfg := ConfigFile.new()
	cfg.load(HINT_CFG)
	if bool(cfg.get_value(GlossaryHint.SECTION, GlossaryHint.KEY, false)):
		_fail("hint reset left the glossary hint flagged as seen")


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
