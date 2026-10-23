extends SceneTree

## Headless test: godot --headless --script res://tests/test_person_links.gd
## Non-zero exit on any failure.
##
## V5.1-d1b2, G9 of the play gate: "i cant click any politician to get their
## card". The People panel's rows had the one card (person_card.gd) on hover and
## nothing else did. A name the UI prints through a rich line can now be marked
## [p=id]Name[/p] (TermText): hovering it shows the shared card, clicking it pins
## the card until Escape or a click away -- the glossary layer's own close rules.
##
##   - the markup: a marked name becomes a person link, other brackets stay text;
##   - the surfaces the play gate named: the Diplomacy window's leader, the
##     Politics window's head of government and head of state, the portrait's
##     name -- each a link to the right person;
##   - the card: shown on hover with the person's name, gone on leave; pinned by a
##     click, still up after the pointer leaves, gone on Escape.

const TermText = preload("res://src/ui/term_text.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main._on_nation_clicked("DEU")
	elif _frame == 8:
		_check_the_card_is_tight()
		_finish()
		return true
	elif _frame == 5:
		_check_markup()
		_check_surfaces()
		_check_the_card()
		_check_the_card_does_not_grow()
	return false


func _check_markup() -> void:
	var out: String = TermText.markup("Led by [p=pers_x]Ada Example[/p] [b]now[/b].")
	if not out.contains("person:pers_x"):
		_fail("a marked name is not a person link: %s" % out)
	if not out.contains("Ada Example") or out.contains("[p="):
		_fail("the marked name lost its words or kept its tag: %s" % out)
	if not out.contains("[lb]b]now[lb]/b]"):
		_fail("a bracket beside a name was read as BBCode: %s" % out)


func _check_surfaces() -> void:
	var loader = _main._loader
	var ns = _main._state.player()
	var deu = loader.nations["DEU"]
	_expect_link(_main._nation_panel, String(deu.leader_person_id), "the Diplomacy window's leader")
	_main._windows.open("politics")
	_main._government_panel._process(0.0)
	_expect_link(_main._government_panel, String(ns.pm_person_id), "the Politics window's head of government")
	# Shown only where the head of state is not the executive (not France's president).
	if ns.head_of_state_kind != "executive_president":
		_expect_link(_main._government_panel, String(ns.head_of_state_person_id), "the Politics window's head of state")
	_expect_link(_main._hud, String(loader.nations[ns.id].leader_person_id), "the portrait's name")
	_main._windows.close_all()


func _check_the_card() -> void:
	var tip = _main._stack.tips
	var ns = _main._state.player()
	var id := String(ns.pm_person_id)
	var name: String = _main._loader.person_name(id)
	var at := Rect2(400, 300, 1, 16)
	tip.person_enter(id, at)
	if not tip.person_card_visible() or not tip.person_card_text().contains(name):
		_fail("hovering a name did not show its card (%s)" % tip.person_card_text())
	tip.person_leave()
	if tip.person_card_visible():
		_fail("the card stayed after the pointer left an unpinned name")
	tip.person_click(id, at)
	tip.person_leave()
	if not tip.person_card_visible():
		_fail("a clicked name's card went when the pointer left")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	tip._input(escape)
	if tip.person_card_visible():
		_fail("Escape did not put a pinned card away")


## PRE-GATE 2 B2: show_for queue_free'd the old rows without removing them, so a
## second show in the same frame (a hover moving between names) counted both
## sets in the card's minimum size -- 2-2.6x the content's height.
func _check_the_card_does_not_grow() -> void:
	var card = _main._stack.tips._people._card
	var ns = _main._state.player()
	var id := String(ns.pm_person_id)
	card.show_for(id, _main._loader, ns, Vector2(400, 300))
	var once: float = card.get_combined_minimum_size().y
	card.show_for(id, _main._loader, ns, Vector2(400, 300))
	card.show_for(id, _main._loader, ns, Vector2(400, 300))
	var again: float = card.get_combined_minimum_size().y
	if once <= 0.0 or again > once + 1.0:
		_fail("showing the card again grew it from %.0f to %.0f px" % [once, again])
	# Left up: _check_the_card_is_tight reads it a few frames on.


## PRE-GATE 2 B2 round 2: in the frame of a show the rows are measured before their
## width is known, the panel grows to that minimum and never shrinks -- 312 px for
## 177 px of content on screen. A few frames after a show it must be as tall as its
## content.
func _check_the_card_is_tight() -> void:
	var card = _main._stack.tips._people._card
	var need: float = card.get_combined_minimum_size().y
	if not card.visible or card.size.y > need + 1.0:
		_fail("the card is %.0f px tall for %.0f px of content (visible %s)" % [card.size.y, need, card.visible])
	card.hide()


func _expect_link(root_node: Node, person_id: String, where: String) -> void:
	if person_id.is_empty():
		_fail("premise: no person behind %s" % where)
		return
	for node in _all(root_node):
		if node.get_script() == TermText and String(node.text).contains("person:" + person_id):
			return
	_fail("%s is not a link to their card (%s)" % [where, person_id])


func _all(node: Node) -> Array:
	var out := [node]
	for child in node.get_children():
		out.append_array(_all(child))
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_person_links: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
