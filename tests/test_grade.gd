extends SceneTree

## Headless test: godot --headless --script res://tests/test_grade.gd
## Non-zero exit on any failure.
##
## V5.1a. The one grade every photographic surface wears -- portraits, scene
## backdrops, event-art plates -- so a library generated over months reads as one
## direction ("agence de presse": neutral, contrast +5 %, saturation +4 %). The
## grade is a material on a TextureRect, which fails silently (a surface that
## forgot it just looks ungraded), so each place that makes such a rect is
## checked here, as the objects the callers actually get.

const Grade = preload("res://src/ui/grade.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const EventArt = preload("res://src/ui/event_art.gd")
const MessageStack = preload("res://src/ui/message_stack.gd")

var _failures: Array[String] = []


func _init() -> void:
	_check_material()
	_check_portrait_surfaces()
	_check_event_art_surfaces()
	if _failures.is_empty():
		print("test_grade: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)


func _check_material() -> void:
	var m := Grade.material()
	if m == null or m.shader == null:
		_fail("Grade.material() has no shader")
		return
	if Grade.material() != m:
		_fail("Grade.material() is not one shared material (a new one per rect defeats batching)")
	var names := []
	for u in m.shader.get_shader_uniform_list():
		names.append(u["name"])
	for needed in ["contrast", "saturation"]:
		if not names.has(needed):
			_fail("the grade shader has no '%s' uniform" % needed)
	if not is_equal_approx(float(m.get_shader_parameter("contrast")), 1.05):
		_fail("contrast is not 1.05")
	if not is_equal_approx(float(m.get_shader_parameter("saturation")), 1.04):
		_fail("saturation is not 1.04")


## control_for() on a person with art, and staged_for() over a scene: the bust
## and the backdrop are both rects and both are graded. A person is taken from
## the portrait directory itself so the test needs no data load.
func _check_portrait_surfaces() -> void:
	var person := _first_portrait_id()
	if person == "":
		_fail("no portrait art found to test against")
		return
	var bust := Portrait.control_for(person, Vector2(108, 148))
	if not bust is TextureRect:
		_fail("control_for gave a %s, not a TextureRect, for a person with art" % bust.get_class())
	elif not Grade.is_graded(bust):
		_fail("the portrait bust is not graded")
	bust.free()

	var staged := Portrait.framed_for(person, Vector2(108, 148), Portrait.Emotion.NEUTRAL, Portrait.Scene.OFFICE)
	var rects := _rects_in(staged)
	if rects.is_empty():
		_fail("the staged portrait has no TextureRect at all")
	for rect in rects:
		# The vignette is an overlay of its own, not a photograph.
		if rect.texture is GradientTexture2D:
			continue
		if not Grade.is_graded(rect):
			_fail("a staged portrait surface is not graded: %s" % rect.name)
	staged.free()


func _check_event_art_surfaces() -> void:
	var tex := EventArt.plate_texture("fiscal", 2, "probe")
	if tex == null:
		_fail("no event art plate found to test against")
		return
	var rect := Grade.apply(TextureRect.new())
	if not Grade.is_graded(rect):
		_fail("Grade.apply did not grade the rect it was given")
	rect.free()

	# The arrival card's plate, through the real stack.
	var stack := MessageStack.new()
	root.add_child(stack)
	stack.push("Crisis", "A body.", [], tex)
	var plates := _rects_in(stack)
	if plates.is_empty():
		_fail("a message pushed with art has no TextureRect")
	for plate in plates:
		if not Grade.is_graded(plate):
			_fail("the arrival card's event plate is not graded")
	stack.free()


func _first_portrait_id() -> String:
	for name in DirAccess.get_files_at("res://assets/portraits/neutral"):
		if name.ends_with(".webp"):
			return name.get_basename()
	return ""


func _rects_in(node: Node) -> Array[TextureRect]:
	var out: Array[TextureRect] = []
	if node is TextureRect:
		out.append(node)
	for child in node.get_children():
		out.append_array(_rects_in(child))
	return out


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)
