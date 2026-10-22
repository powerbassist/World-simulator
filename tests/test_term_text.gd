extends SceneTree

## Headless test: godot --headless --script res://tests/test_term_text.gd
## Non-zero exit on any failure.
##
## V5.1-c, the rich line a glossary term is marked in (src/ui/term_text.gd,
## PanelKit.rich). What a frame cannot show:
##
##   - a writer's [g=id]word[/g] becomes the engine's dashed, hoverable term
##     ([url=term:id][hint=]word[/hint][/url]: step 0 proved the empty hint
##     suppresses the engine's own tooltip), and every OTHER bracket in the prose
##     stays a bracket -- prose is not BBCode;
##   - the noise rules hold at render: N1 (an id marks once a block), N2 (three
##     marked a block at most), N5 (an id open up the chain reads plain), and an
##     unknown id reads as its word, loudly;
##   - the label routes a hover and a click on a term to the tooltip layer it
##     finds through the group, with its own level, and a press on a term is
##     taken (N4: a term on a clickable row must not fire the row);
##   - PanelKit.rich carries the tone's variation, as PanelKit.line does.

const TermText = preload("res://src/ui/term_text.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Inbox = preload("res://src/ui/inbox.gd")

var _failures: Array[String] = []
var _calls: Array = []
var _frame := 0
var _label


func _init() -> void:
	root.theme = UiTheme.build()
	var stub := Node.new()
	stub.set_script(_stub_script())
	stub.set("calls", _calls)
	root.add_child(stub)
	stub.add_to_group(TermText.GROUP)
	_label = TermText.new()
	_label.size = Vector2(400, 40)
	root.add_child(_label)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_check_markup_turns_tags_into_terms()
	_check_brackets_stay_brackets()
	_check_noise_rules()
	_check_unknown_id_reads_plain()
	_check_routes_hover_and_click()
	_check_rich_carries_the_tone()
	_check_the_sinks_mark_terms()
	_check_once_per_section()
	_finish()
	return true


func _check_markup_turns_tags_into_terms() -> void:
	var out: String = TermText.markup("Your [g=approval]approval[/g] is low.")
	if out != "Your [url=term:approval][hint=]approval[/hint][/url] is low.":
		_fail("markup gave %s" % out)
	_label.set_marked("Your [g=approval]approval[/g] is low.")
	if _label.get_parsed_text() != "Your approval is low.":
		_fail("the marked line reads '%s'" % _label.get_parsed_text())


func _check_brackets_stay_brackets() -> void:
	_label.set_marked("A [b]bold[/b] claim and [g=poll]a poll[/g] [x].")
	if _label.get_parsed_text() != "A [b]bold[/b] claim and a poll [x].":
		_fail("prose brackets were read as BBCode: '%s'" % _label.get_parsed_text())


func _check_noise_rules() -> void:
	var twice: String = TermText.markup("[g=debt]debt[/g] and more [g=debt]debt[/g]")
	if twice.count("[url=") != 1:
		_fail("N1: one id marked %d times in a block" % twice.count("[url="))
	var four: String = TermText.markup("[g=debt]a[/g] [g=gdp]b[/g] [g=poll]c[/g] [g=growth]d[/g]")
	if four.count("[url=") != TermText.MAX_MARKED:
		_fail("N2: %d of four terms marked, the cap is %d" % [four.count("[url="), TermText.MAX_MARKED])
	if not four.ends_with(" d"):
		_fail("N2: the term past the cap did not read as its word: %s" % four)
	# V5.1-d2 (QA RECORD on #60): a See-also line is a LIST of terms, not prose, so
	# it lifts the cap -- APPROVAL's fourth, "salience", was drawn plain.
	var listed: String = TermText.markup("[g=debt]a[/g] [g=gdp]b[/g] [g=poll]c[/g] [g=growth]d[/g]", PackedStringArray(), 4)
	if listed.count("[url=") != 4:
		_fail("a list with its cap lifted marked %d of four terms" % listed.count("[url="))
	var open: String = TermText.markup("[g=poll]poll[/g] and [g=debt]debt[/g]", PackedStringArray(["poll"]))
	if open.contains("term:poll") or not open.contains("term:debt"):
		_fail("N5: an id open up the chain was marked, or the other was not: %s" % open)


func _check_unknown_id_reads_plain() -> void:
	## expects-error: glossary: text marks 'no_such_term'
	var out: String = TermText.markup("a [g=no_such_term]word[/g] here")
	if out != "a word here":
		_fail("an unknown id did not read as its word: %s" % out)


func _check_routes_hover_and_click() -> void:
	_label.set_marked("[g=approval]approval[/g]")
	_label.level = 2
	_calls.clear()
	_label.meta_hover_started.emit("term:approval")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	_label._gui_input(press)
	_label.meta_hover_ended.emit("term:approval")
	var names: Array = _calls.map(func(c): return "%s %s %d" % [c[0], c[1], c[2]])
	if names != ["enter approval 2", "click approval 2", "leave  2"]:
		_fail("the label routed %s to the tooltip layer" % [names])
	_calls.clear()
	_label._gui_input(press)
	if not _calls.is_empty():
		_fail("a press with no term under the pointer reached the tooltip layer: %s" % [_calls])
	_label.level = 0


func _check_rich_carries_the_tone() -> void:
	var box := VBoxContainer.new()
	root.add_child(box)
	var dim: RichTextLabel = PanelKit.rich(box, "dim words")
	var plain: RichTextLabel = PanelKit.rich(box, "plain words", PanelKit.Tone.PLAIN)
	if dim.theme_type_variation != UiTheme.RICH_CAPTION:
		_fail("PanelKit.rich's default tone wore '%s', not the caption variation" % dim.theme_type_variation)
	if plain.theme_type_variation != "":
		_fail("a PLAIN rich line wore '%s'; PLAIN sets no variation" % plain.theme_type_variation)
	if dim.get_script() != TermText:
		_fail("PanelKit.rich did not build a TermText")


## c's two sinks (the spec's step 2): the inbox body, pushed and rewritten, and
## the event text -- read off the source, as the event window needs a whole game.
func _check_the_sinks_mark_terms() -> void:
	var inbox = Inbox.new()
	root.add_child(inbox)
	var id: String = inbox.push("A title", "Your [g=approval]approval[/g] fell.")
	var body = inbox._bodies[id]
	if body.get_script() != TermText or not String(body.text).contains("term:approval"):
		_fail("the inbox body is not a marked rich line: %s" % body.text)
	inbox.set_body(id, "The [g=deficit]deficit[/g] grew.")
	if not String(body.text).contains("term:deficit") or body.get_parsed_text() != "The deficit grew.":
		_fail("set_body bypassed the marking: %s" % body.text)
	inbox.queue_free()
	var source := FileAccess.get_file_as_string("res://src/ui/events_panel.gd")
	for sink in ['PanelKit.rich(_body, Strings.row_summary("events", ev))',
			'PanelKit.rich(block, Strings.choice_summary(ev.id, choice))']:
		if not source.contains(sink):
			_fail("events_panel.gd no longer prints its text through a rich line: %s" % sink)
	_check_the_row_sinks()


## The data rows Content marks next (the tooltip-sinks PR): each summary a panel
## prints goes through a rich line, read off the source as above -- each panel
## needs a whole game to draw. A Button's tooltip_text cannot carry a term, so a
## summary shown there reads its words without the tags.
func _check_the_row_sinks() -> void:
	var sinks := {
		"res://src/ui/events_panel.gd": ["PanelKit.rich(block, what)"],
		"res://src/ui/law_panel.gd": ["PanelKit.rich(box, Strings.law_summary(law), PanelKit.Tone.PLAIN)"],
		"res://src/ui/agenda_panel.gd": [
			'PanelKit.rich(block, Strings.row_summary("programme", terms))',
			'button.tooltip_text = PanelKit.TermText.plain(Strings.row_summary("programme", terms))',
		],
		"res://src/ui/campaign_panel.gd": ['button.tooltip_text = PanelKit.TermText.plain(Strings.row_summary("pledges", action))'],
		"res://src/ui/council_section.gd": ['PanelKit.rich(body, Strings.row("bloc-proposals", String(pending.get("proposal_id", "")), "summary", String(pending.get("summary", ""))))'],
	}
	for path in sinks:
		var source := FileAccess.get_file_as_string(path)
		for sink in sinks[path]:
			if not source.contains(sink):
				_fail("%s does not print its row's text through the term path: %s" % [path.get_file(), sink])
	var plain: String = TermText.plain("Your [g=approval]approval[/g] and [b]the [g=no_such_term]rest[/g][/b].")
	if plain != "Your approval and [b]the rest[/b].":
		_fail("TermText.plain gave '%s'" % plain)


## V5.1-d2, N1 per section, in code (it was Content's hand cut): a term is marked at
## its first occurrence in a section -- a PanelKit.section body, or the whole window
## a panel is registered in -- and drawn plain after that. A rebuilt section starts
## afresh: a line queued for deletion no longer holds its marks.
func _check_once_per_section() -> void:
	var box := VBoxContainer.new()
	root.add_child(box)
	var body: VBoxContainer = PanelKit.section(box, "A section")
	var first: RichTextLabel = PanelKit.rich(body, "Your [g=approval]approval[/g] is up.")
	var second: RichTextLabel = PanelKit.rich(body, "And [g=approval]approval[/g] again, with [g=debt]debt[/g].")
	if not String(first.text).contains("term:approval"):
		_fail("N1 per section: the first occurrence was not marked")
	if String(second.text).contains("term:approval"):
		_fail("N1 per section: a term was marked twice in one section")
	if not String(second.text).contains("term:debt"):
		_fail("N1 per section: another term in the same line lost its mark")
	var elsewhere: VBoxContainer = PanelKit.section(box, "Another section")
	var third: RichTextLabel = PanelKit.rich(elsewhere, "Its own [g=approval]approval[/g].")
	if not String(third.text).contains("term:approval"):
		_fail("N1 per section: a term was not marked in a second section")
	first.queue_free()
	second.queue_free()
	var rebuilt: RichTextLabel = PanelKit.rich(body, "Rebuilt [g=approval]approval[/g].")
	if not String(rebuilt.text).contains("term:approval"):
		_fail("N1 per section: a rebuilt section kept the old lines' marks")
	box.queue_free()


## A stand-in for the tooltip layer: the label finds whatever is in the group
## and calls enter/leave/click on it, so the routing is checked on its own.
func _stub_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = """extends Node
var calls: Array
func enter(id: String, _anchor: Rect2, level: int) -> void:
	calls.append(["enter", id, level])
func leave(level: int) -> void:
	calls.append(["leave", "", level])
func click(id: String, _anchor: Rect2, level: int) -> void:
	calls.append(["click", id, level])
"""
	s.reload()
	return s


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_term_text: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
