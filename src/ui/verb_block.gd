extends RefCounted

## A sheet's verb block -- the rework pass's C ("plus de menu", the author's pick after the G3 line "right click
## option is ugly"). The right click's plate is gone: a right click selects its row and LIGHTS the block of that
## row's verbs on its sheet, so a verb has one place and one look. The block is any container a screen tags here:
## the Bills sheet's verb row, the order paper's docked block, People's strip under the picked line, a firm's
## "The State's verbs". Lighting scrolls the block into view and gives its first live verb the focus, whose ring is
## drawn in the accent (Godot 4.7 Control: focus shows "via grab_focus()", not from a mouse press).

const META := "verb_block"


static func tag(block: Control) -> Control:
	block.set_meta(META, true)
	return block


## Whether `event` is a right button press (the gesture that lights a row's verbs).
static func is_right_press(event: InputEvent) -> bool:
	var press := event as InputEventMouseButton
	return press != null and press.pressed and press.button_index == MOUSE_BUTTON_RIGHT


## Lights the first visible block under `root`: its first live verb takes the focus, and the block is scrolled into
## its scroll's view once laid out. A block with every verb down still scrolls into view.
static func light(root: Node) -> void:
	for node in root.find_children("*", "", true, false):
		if not node.has_meta(META) or not (node as Control).is_visible_in_tree():
			continue
		var block := node as Control
		for button in block.find_children("*", "Button", true, false):  # i18n: ok a class name
			if (button as Button).is_visible_in_tree() and not (button as Button).disabled:
				(button as Button).grab_focus()
				break
		var scroll: Node = block.get_parent()
		while scroll != null and not (scroll is ScrollContainer):
			scroll = scroll.get_parent()
		if scroll != null:
			_scroll_to.call_deferred(scroll, block)
		return


## Deferred: by then a rebuild may have taken the block out of its scroll (a refresh in the same frame).
static func _scroll_to(scroll: ScrollContainer, block: Control) -> void:
	if is_instance_valid(scroll) and is_instance_valid(block) and scroll.is_ancestor_of(block):
		scroll.ensure_control_visible(block)
