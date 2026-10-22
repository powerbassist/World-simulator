extends PanelContainer

## The summit scene, V2.4b — a meeting that became a conversation.
##
## The balloon is deliberately SMALL and the addon deliberately load-bearing:
## lines come from the DialogueManager autoload (the project's stated exception
## to the no-autoloads rule, adopted at V2.4b) through get_next_dialogue_line(),
## which is the addon's own traversal and the reason the adoption is worth its
## price — conditions, mutations and jumps are all handled there, so summit
## content may grow into any of them without this panel changing.
##
## What the panel OWNS is the frame: the leader's portrait, the nation band,
## the response buttons, and the one contract — concluded() fires ONCE, with
## the response the player chose, and the orchestrator (main.gd) applies its
## effects through Legislature.apply_effects(). The panel never touches state;
## the effects ride the same channels a law and an event choice use, which is
## the whole reason summits are no new machine at all.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const DMConstants = preload("res://addons/dialogue_manager/constants.gd")

signal concluded(summit_id: String, choice_label: String)

var _state
var _loader

var _resource: Resource
var _effects: Dictionary
var _summit_id: String
var _choice: String = ""
## The line after the spoken one on screen -- what Continue walks to. V5.1-d1b2 (QA
## on #70): Continue called _advance() with no key, which is the dialogue's START,
## so every path's closing line looped back to the opening and no summit ever
## concluded or applied its choice.
var _next := ""
## The nation visited while a scene runs, "" otherwise -- the clock's hold line
## names it (hold_reason.gd).
var visiting := ""

var _title: Label
var _leader_box: Control
var _line_label: Label
var _speaker_label: Label
var _choices_box: VBoxContainer
var _continue_button: Button
var _dirty := true


func _ready() -> void:
	custom_minimum_size = Vector2(620, 520)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_title = Label.new()
	_title.theme_type_variation = UiTheme.LEAD
	root.add_child(_title)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# The face the meeting was FOR. The V2.2 portrait fallback is shared, so a
	# person without art is the silhouette and the scene plays anyway — a
	# missing portrait is SILENT in game, V2.3's own policy.
	_leader_box = Control.new()
	_leader_box.custom_minimum_size = Vector2(180, 247)
	body.add_child(_leader_box)

	var speech := VBoxContainer.new()
	speech.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speech.add_theme_constant_override("separation", 8)
	body.add_child(speech)

	_speaker_label = Label.new()
	_speaker_label.theme_type_variation = UiTheme.MICRO
	speech.add_child(_speaker_label)

	# Body text, no variation -- PanelKit's Tone.PLAIN convention: the scene's
	# own prose, not a caption.
	_line_label = Label.new()
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_line_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	speech.add_child(_line_label)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 6)
	root.add_child(_choices_box)

	_continue_button = Button.new()
	_continue_button.text = tr("Continue")
	_continue_button.pressed.connect(func(): _advance(_next))
	root.add_child(_continue_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader


func mark_dirty() -> void:
	_dirty = true


## The orchestrator's one call. Compiles the scene through the addon and walks
## in from its first title. A compile failure here is a CONTENT bug the loader
## was written to make impossible — it stored text that never compiled — so it
## pushes loudly and closes rather than shipping an empty scene.
func show_summit(summit: Dictionary) -> void:
	_summit_id = String(summit.get("id", ""))
	visiting = String(summit.get("nation_name", ""))
	_effects = summit.get("effects", {})
	_choice = ""
	_title.text = String(summit.get("title", tr("A meeting")))

	var manager = _manager()
	if manager == null:
		push_error("summit: DialogueManager autoload is absent -- the committed project.godot should carry it")
		_conclude()
		return
	_resource = manager.create_resource_from_text(String(summit.get("dialogue_text", "")))
	if _resource == null:
		push_error("summit: dialogue for '%s' did not compile" % _summit_id)
		_conclude()
		return

	for child in _leader_box.get_children():
		child.queue_free()
	var person_id := String(summit.get("leader_person_id", ""))
	if person_id != "":
		# The room the sidecar names, staged behind the leader -- the summit's
		# own scene field, validated at load; an unknown name already died there.
		_leader_box.add_child(Portrait.framed_for(
			person_id, Vector2(180, 247), Portrait.Emotion.NEUTRAL,
			Portrait.scene_from_name(String(summit.get("scene", "summit_hall")))))

	_advance("")


func _manager():
	if Engine.has_singleton("DialogueManager"):
		return Engine.get_singleton("DialogueManager")
	# Script autoloads are not Engine singletons; they are nodes under root.
	var node := get_node_or_null("/root/DialogueManager")
	return node


## One beat. The addon resolves the next line -- skipping titles, evaluating
## whatever the scene contains -- and the panel renders exactly three kinds of
## beat: a spoken line, a choice, and the end. When the line walked INTO a
## title named in the sidecar's effects, the choice it belongs to has been
## made and is recorded as the one concluded() carries.
func _advance(from_key: String = "") -> void:
	if _resource == null:
		return
	var line = await _manager().get_next_dialogue_line(_resource, from_key)

	# END, or a dead resource: the scene is over. What was chosen is what the
	# player last chose; "" is the honest answer for a scene with no priced
	# fork on its path.
	if line == null:
		_conclude()
		return

	_clear_choices()
	if line.responses.size() > 0:
		_speaker_label.text = String(line.character) if String(line.character) != "" else ""
		_line_label.text = String(line.text)
		for response in line.responses:
			var button := Button.new()
			button.text = String(response.text)
			# The choice is recorded at the PRESS, from the response's own
			# label -- the exact string the sidecar prices -- rather than by
			# interpreting the compiler's jump ids. What the player pressed is
			# what concluded() carries, however many beats follow.
			button.pressed.connect(func():
				_choice = String(response.text)
				_advance(String(response.next_id))
			)
			_choices_box.add_child(button)
		_continue_button.hide()
	else:
		_speaker_label.text = String(line.character)
		_line_label.text = String(line.text)
		_next = String(line.next_id)
		_continue_button.show()
		_continue_button.grab_focus()


func _clear_choices() -> void:
	for child in _choices_box.get_children():
		child.queue_free()


func _conclude() -> void:
	var id := _summit_id
	var choice := _choice
	_resource = null
	_summit_id = ""
	visiting = ""
	_line_label.text = ""
	_speaker_label.text = ""
	_clear_choices()
	# Hidden with the rest of the scene. Left showing until the V2.8 review, so the
	# end of a summit was an empty plate with a focused Continue button that did
	# nothing forever -- _advance() returns immediately once _resource is null.
	_continue_button.hide()
	concluded.emit(id, choice)
