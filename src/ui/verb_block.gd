extends RefCounted

## A sheet's verb block -- the rework pass's C ("plus de menu", the author's pick after the G3 line "right click
## option is ugly"). The right click's plate is gone: a right click selects its row and LIGHTS the block of that
## row's verbs on its sheet, so a verb has one place and one look. The block is any container a screen tags here:
## the Bills sheet's verb row, the order paper's docked block, People's strip under the picked line, a firm's
## "The State's verbs". Lighting scrolls the block into view and takes NO focus: a right click is a mouse gesture,
## and a focused verb is pressed by the next Enter or Space (Space is the pause key; on a law with the slot held the
## first live verb is "Force (49.3)", which adopts without a vote). The picked row's own selection is the mark.
## Only a keyboard path hands focus back, to the verb it was on (refocus()).

const META := "verb_block"


static func tag(block: Control) -> Control:
	block.set_meta(META, true)
	return block


## Whether `event` is a right button press (the gesture that lights a row's verbs).
static func is_right_press(event: InputEvent) -> bool:
	var press := event as InputEventMouseButton
	return press != null and press.pressed and press.button_index == MOUSE_BUTTON_RIGHT


## Lights the first visible block under `root`: it is scrolled into its scroll's view once laid out. No focus.
static func light(root: Node) -> void:
	var block := _block(root)
	if block == null:
		return
	var scroll: Node = block.get_parent()
	while scroll != null and not (scroll is ScrollContainer):
		scroll = scroll.get_parent()
	if scroll != null:
		_scroll_to.call_deferred(scroll, block)


## A keyboard path's rebuild: the focus goes back to the verb named `verb` (its node name, else its text) in the
## block under `root`, and the block is lit. That verb gone or down, the keyboard stays in the block on its first
## live verb (the old one was freed with the rebuild).
static func refocus(root: Node, verb: String) -> void:
	light(root)
	var block := _block(root)
	if block == null or verb == "":
		return
	var live: Array = block.find_children("*", "Button", true, false).filter(  # i18n: ok a class name
		func(b) -> bool: return (b as Button).is_visible_in_tree() and not (b as Button).disabled)
	for b in live:
		if key_of(b) == verb:
			(b as Button).grab_focus()
			return
	if not live.is_empty():
		(live[0] as Button).grab_focus()


## The name refocus() finds a button by again: its node name when one was given, else its text.
static func key_of(button: Button) -> String:
	return String(button.name) if not String(button.name).begins_with("@") else button.text


static func _block(root: Node) -> Control:
	for node in root.find_children("*", "", true, false):
		if node.has_meta(META) and (node as Control).is_visible_in_tree() and not _dying(node, root):
			return node as Control
	return null


## Deferred: by then a rebuild may have taken the block out of its scroll (a refresh in the same frame).
static func _scroll_to(scroll: ScrollContainer, block: Control) -> void:
	if is_instance_valid(scroll) and is_instance_valid(block) and scroll.is_ancestor_of(block):
		scroll.ensure_control_visible(block)


## Whether `node` or an ancestor up to `root` is queued for deletion: a panel that rebuilds with queue_free keeps the
## old block in the tree until the frame ends, and lighting it would focus a verb about to be freed.
static func _dying(node: Node, root: Node) -> bool:
	while node != null and node != root:
		if node.is_queued_for_deletion():
			return true
		node = node.get_parent()
	return false
