extends SceneTree

## Headless test: godot --headless --script res://tests/test_audience_scene.gd
## Non-zero exit on any failure.
##
## V5.2b, the audience scene, on Levers' row shapes (.superpowers/sdd/v5.2b-plan.md):
##   - the levers print their odds as a range ("35–60 %"), never a point, and say
##     why the range is wide (the fog word); a lever the sim does not offer is
##     disabled with its reason;
##   - a real click on a lever (press and release frames apart) emits that lever;
##   - three attempts spent disable every lever, and the scene says to end it;
##   - the person's opening line comes through DialogueManager from
##     data/audiences/default.dialogue ({{ask}} in their mouth), and a title no
##     file has falls back without stopping the scene;
##   - a stance's file replaces the default title by title (a title twice would not
##     compile), and once Content ships any stance file, every stance has one.

const AudienceScene = preload("res://src/ui/audience_scene.gd")
const PersonCard = preload("res://src/ui/person_card.gd")

var _failures: Array[String] = []
var _scene
var _frame := 0
var _pressed := []

const OFFERED := [
	{"lever": "argue", "offered": true, "why_not": "", "odds_lo": 0.35, "odds_hi": 0.6, "fog": "stranger", "spends": {}},
	{"lever": "friendship", "offered": false, "why_not": "You are not friends.", "odds_lo": 0.0, "odds_hi": 0.0, "fog": "stranger", "spends": {}},
]


func _init() -> void:
	_scene = AudienceScene.new()
	_scene.size = Vector2(1120, 630)
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_scene.attempted.connect(func(lever: String) -> void: _pressed.append(lever))
			_scene.open({"request_id": "req_1", "person_id": "", "name": "Cécile Aumont",
				"ask": "the pension age held", "stance": "defend", "president": "Daniel Moucron",
				"fog": "stranger", "offered": OFFERED,
				"topics": [{"topic": "family", "offered": true}, {"topic": "flirt", "offered": false, "why_not": "Not with her."}],
				"attempts_left": 3})
		5:
			_check_open()
			_press(true)
		9:
			_press(false)
		11:
			if _pressed != ["argue"]:
				_fail("a held click on Argue emitted %s" % [_pressed])
			_scene.show_result("She will not move.", OFFERED, 0, "lever_argue_failure")
		13:
			_check_spent()
			_check_blocks()
			_check_stance_files()
			_check_files_compile()
			_finish()
			return true
	return false


func _argue() -> Button:
	for b in _scene._levers.get_children():
		if b is Button and (b as Button).text == "Argue":
			return b
	return null


func _check_open() -> void:
	var labels: Array = []
	for c in _scene._levers.get_children():
		if c is Label:
			labels.append((c as Label).text)
	if not labels.has("35–60 %"):
		_fail("the argue lever's odds are not the range 35–60 %%: %s" % [labels])
	var friendship: Button = null
	for b in _scene._levers.get_children():
		if b is Button and (b as Button).text == "Appeal to friendship":
			friendship = b
	if friendship == null or not friendship.disabled or friendship.tooltip_text != "You are not friends.":
		_fail("a lever the sim does not offer is not disabled with its reason")
	if not _scene._fog.text.contains("stranger"):
		_fail("the scene does not say why the odds are wide: %s" % _scene._fog.text)
	# Content's lines frame the want in a sentence; the placeholder says it bare.
	if not _scene._line.text.contains("the pension age held"):
		_fail("the opening line does not carry the asker's want through the dialogue: '%s'" % _scene._line.text)
	if _scene.visiting != "Cécile Aumont":
		_fail("the hold line's seam does not name the person")


func _check_spent() -> void:
	var argue := _argue()
	if argue == null or not argue.disabled:
		_fail("three attempts spent left Argue live")
	if not _scene._attempts.text.contains("end the audience"):
		_fail("no attempts left, and the scene does not say to end it: %s" % _scene._attempts.text)
	if _scene._result.text != "She will not move.":
		_fail("the result is not shown")


func _check_blocks() -> void:
	var base := AudienceScene.titled_blocks("~ opening\nA: one\n=> END\n~ close_settled\nA: bye\n=> END\n")
	var own := AudienceScene.titled_blocks("~ opening\nA: mine\n=> END\n")
	base.merge(own, true)
	if base.size() != 2 or not String(base["opening"]).contains("mine") or not String(base["close_settled"]).contains("bye"):
		_fail("a stance's title does not replace the default's alone: %s" % [base])


## Every file under data/audiences compiles through the addon (Content's #103
## suggestion, test_summits' shape), and once the default carries more than the
## placeholder's opening it carries every title the scene asks for.
func _check_files_compile() -> void:
	var manager = root.get_node_or_null("/root/DialogueManager")
	if manager == null:
		_fail("no DialogueManager autoload to compile with")
		return
	var titles := ["opening", "close_settled", "close_promised", "close_declined"]
	for lever in AudienceScene.LEVER_LABEL.keys():
		titles.append("lever_%s_success" % lever)
		titles.append("lever_%s_failure" % lever)
	for topic in AudienceScene.TOPIC_LABEL.keys():
		titles.append("topic_%s" % topic)
	var dir := DirAccess.open("res://data/audiences")
	for file in dir.get_files():
		if not file.ends_with(".dialogue"):
			continue
		var text := FileAccess.get_file_as_string("res://data/audiences/" + file)
		if manager.create_resource_from_text(text) == null:
			_fail("data/audiences/%s does not compile" % file)
		if file == "default.dialogue":
			var blocks := AudienceScene.titled_blocks(text)
			if blocks.size() > 1:
				for t in titles:
					if not blocks.has(t):
						_fail("default.dialogue lacks the title %s" % t)


## Content's PR ships the stance files (the parent's call): until then only the
## default exists; once any stance file lands, every stance must have one.
func _check_stance_files() -> void:
	var dir := DirAccess.open("res://data/audiences")
	if dir == null or not dir.file_exists("default.dialogue"):
		_fail("data/audiences/default.dialogue is missing")
		return
	var stances: Array = PersonCard.STANCE_LABEL.keys()
	var shipped := 0
	for stance in stances:
		if dir.file_exists("%s.dialogue" % stance):
			shipped += 1
	if shipped > 0 and shipped < stances.size():
		_fail("Content shipped %d of %d stance dialogues; every request stance needs one" % [shipped, stances.size()])


func _press(down: bool) -> void:
	var target := _argue()
	if target == null:
		_fail("no Argue button")
		return
	var at: Vector2 = target.get_global_rect().get_center()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = down
	click.position = at
	click.global_position = at
	root.push_input(click, true)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_audience_scene: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
