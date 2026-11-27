extends SceneTree

## Headless test: godot --headless --script res://tests/test_screenshot_guards.gd
## Non-zero exit on any failure.
##
## tools/screenshot.gd --text took any number (Igor shot 130, a size no player can pick). It now
## refuses what the Settings row does not offer; the sizes are read from SettingsPanel.TEXT_SCALES,
## so a size the game adds is accepted without touching the tool. The other half of the same fix,
## screenshot_all.py refusing a size folder that lies about --interface-size, is `python
## tools/screenshot_all.py --selftest` (the gate and CI run it).
##
## Also the tree walk behind each frame's .json (tools/panel_dump.gd), whose drift would be silent.

const Shot = preload("res://tools/screenshot.gd")
const PanelDump = preload("res://tools/panel_dump.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	for scale in SettingsPanel.TEXT_SCALES:
		var pct := str(roundi(scale * 100.0))
		if Shot.text_pct_refusal(pct) != "":
			_failures.append("--text %s is a size the game offers but was refused" % pct)
	for raw in ["130", "115", "0", "-5", "101", "1.0", "abc", "", "100 "]:
		var message: String = Shot.text_pct_refusal(raw)
		if message == "":
			_failures.append("--text '%s' is not a size the game offers but was accepted" % raw)
		elif not message.contains("90, 100)"):
			_failures.append("--text '%s': the refusal does not list the allowed sizes: %s" % [raw, message])

## A frame in: a Control outside the tree has no rect.
func _process(_delta: float) -> bool:
	_check_the_dump()
	for failure in _failures:
		push_error("FAIL " + failure)
	print("test_screenshot_guards: %d failures" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
	return true


func _check_the_dump() -> void:
	var box := Control.new()
	var shown := Label.new()
	shown.text = "seen"
	shown.position = Vector2(10, 2)
	shown.size = Vector2(60, 24)
	var hidden := Label.new()
	hidden.visible = false
	box.size = Vector2(200, 30)
	# top_level, as the tip popup is: outside its clipping parent and still drawn.
	var loose := Label.new()
	loose.text = "loose"
	loose.top_level = true
	loose.position = Vector2(0, 40)
	loose.size = Vector2(40, 20)
	box.clip_contents = true
	box.add_child(hidden)
	box.add_child(shown)
	box.add_child(loose)
	# Sticks out of the box on the right, and so does its child, under a parent that does not clip.
	var partly := Control.new()
	partly.position = Vector2(180, 5)
	partly.size = Vector2(60, 20)
	var deep := Control.new()
	deep.position = Vector2(10, 0)
	deep.size = Vector2(40, 10)
	partly.add_child(deep)
	box.add_child(partly)
	var faded := Control.new()
	faded.modulate.a = 0.0
	faded.size = Vector2(10, 10)
	box.add_child(faded)
	var half := Control.new()
	half.modulate.a = 0.5
	half.size = Vector2(10, 10)
	box.add_child(half)
	root.add_child(box)
	var nodes := PanelDump.new().walk(root)
	if nodes.size() != 6 or nodes[2].clip != nodes[2].rect:
		_failures.append("the dump should hold the box, its label, the unclipped top_level one, the two cut ones and the half faded one: %s" % [nodes])
		return
	var label: Dictionary = nodes[1]
	if label.text != "seen" or not label.rebuilt or label.index_path != [box.get_index(), 1]:
		_failures.append("the label's dump entry is wrong: %s" % label)
	var edge: float = nodes[0].rect[0] + nodes[0].rect[2]
	for cut: Dictionary in [nodes[3], nodes[4]]:
		var rect: Array = cut.rect
		var clip: Array = cut.clip
		if rect[0] + rect[2] <= edge or clip[0] != rect[0] or absf(clip[0] + clip[2] - edge) > 0.05:
			_failures.append("a control sticking out of a clipping box should be cut at its edge %s: %s" % [edge, cut])
	if not is_equal_approx(nodes[5].alpha, 0.5):
		_failures.append("a half faded control should read alpha 0.5: %s" % nodes[5])
