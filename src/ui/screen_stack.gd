extends Control

## The layers above the map and the chrome, ranked, and the one answer to "what
## is on top" -- V5.1-c2.1.
##
## Before this, main.gd's Escape branch answered that question in an order its
## comments had to defend (save dialog, then the armed reticle, then the pause
## menu) and nothing else asked it: a panel hotkey under a summit opened the
## budget and closed the summit, an interrupt under one opened Dispatches and
## closed it too, and Escape over the settings screen opened a second pause menu
## that overwrote the clock it was meant to restore.
##
## **The top is the highest RANK on screen, not the last thing shown.** A save
## dialog opened over an armed reticle and the reticle armed under an open dialog
## are the same screen, and Escape must close the dialog first either way.
##
## **Visibility is the one writer.** A panel is registered once with its layer and
## its Escape, and the stack follows its `visibility_changed`: the dozen show(),
## hide() and close() calls already in main.gd and the panels stay the API, and
## no second "is it open" flag can disagree with what the player sees -- the same
## argument `add()`'s holder makes one level down. A mode with no panel (the armed
## reticle) is held and released by hand, because nothing on screen turns on.
##
## Holds no game state.

signal top_changed(from: int, to: int)

const GlossaryTip = preload("res://src/ui/glossary_tip.gd")

## Ranks, lowest first. MAP is the bare map: nothing on the stack.
const MAP := -1
const WORKSPACE := 0
const INBOX := 1
const PLACEMENT := 2
const SCENE := 3
const SYSTEM := 4

## The ranks that hold panels of their own, in draw order: a system screen's dim
## covers a scene, never the reverse. WORKSPACE is the window manager's, below
## the HUD; INBOX is the HUD's column until V5.1-c3.
const _HOSTED := [SCENE, SYSTEM]

## {"layer": int, "node": Control (null for a mode), "cancel": Callable,
## "focus": Control (what held the keyboard below, or null)}, in arrival order.
var _entries: Array = []
var _hosts := {}  # rank -> the full-rect Control its panels are added to
## V5.1-c. The glossary's tooltip chain: the last child, so a plate draws over a
## scene and a system screen. Not a rank -- a held rank would turn the hotkeys off
## under every hover; the chain eats its own Escape (glossary_tip.gd).
var tips := GlossaryTip.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for rank in _HOSTED:
		var host := Control.new()
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(host)
		_hosts[rank] = host
	add_child(tips)


## A panel centred on the screen at `layer` (SCENE or SYSTEM), hidden by its
## caller as before. `dim` darkens the world behind it and eats clicks; `cancel`
## is what Escape does to it -- left empty, Escape cannot put it away (the term
## result: a verdict is dismissed by its own button, never by a key).
func add(layer: int, panel: Control, dim := false, cancel := Callable()) -> void:
	var host: Control = _hosts[layer]
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not dim:
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		# A term result is the one modal moment: dim the world behind it so the
		# verdict owns the screen, and eat clicks -- the election already paused
		# the clock; the backdrop makes the map agree (V2.9). The dim is a
		# SIBLING of the holder, not a child: a CenterContainer collapses a
		# full-rect child to its minimum size. Added before the holder so it
		# draws below the panel and above everything added earlier.
		# It follows the panel's visibility, so every existing show()/hide()
		# call site keeps working unchanged.
		var shade := ColorRect.new()
		shade.color = Color(0.02, 0.03, 0.05, 0.55)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_STOP
		shade.visible = false
		host.add_child(shade)
		# The HOLDER follows the panel too, not just the dim. A Container
		# defaults to MOUSE_FILTER_PASS, so a full-rect dimmed holder goes on
		# taking every click on the screen while the panel inside it is
		# invisible -- which is exactly what V2.9 shipped when it made the
		# election panel blocking: `_election_panel.hide()` hid the panel, the
		# holder stayed up, and a new game was dead to the mouse from its first
		# frame. Doing it here means the next dimmed panel cannot forget -- and
		# a caller sets the PANEL only, because a second writer would be
		# reverted by this one: hiding the holder re-emits visibility_changed
		# on the panel while the panel's own flag is still true, and this
		# handler would put the holder back.
		panel.visibility_changed.connect(func():
			shade.visible = panel.visible
			holder.visible = panel.visible
		)
	holder.add_child(panel)
	host.add_child(holder)
	watch(layer, panel, cancel)


## Follows a control the stack does not own -- a window frame, at WORKSPACE or,
## for a summit, at SCENE.
func watch(layer: int, node: Control, cancel := Callable()) -> void:
	node.visibility_changed.connect(_sync.bind(layer, node, cancel))
	_sync(layer, node, cancel)


## A mode with nothing of its own on screen (the armed reticle). One per rank:
## arming again replaces the last.
func hold(layer: int, cancel: Callable) -> void:
	var before := top()
	_drop_mode(layer)
	_entries.append({"layer": layer, "node": null, "cancel": cancel, "focus": null})
	_moved(before)


## A mode another node switches on and off through a `toggled(on: bool)` signal
## -- the inbox sliding over a tab.
func follow_mode(layer: int, toggled: Signal, cancel: Callable) -> void:
	toggled.connect(func(on: bool):
		if on:
			hold(layer, cancel)
		else:
			release(layer)
	)


func release(layer: int) -> void:
	var before := top()
	_drop_mode(layer)
	_moved(before)


func top() -> int:
	var rank := MAP
	for entry in _entries:
		rank = maxi(rank, int(entry["layer"]))
	return rank


## A letter that opens a window, and M that sweeps them, act only on the map,
## a domain and the inbox: above that, the screen belongs to what is on it.
func accepts_hotkeys() -> bool:
	return top() <= INBOX


## Escape: puts away the newest thing at the top rank, if it allows that. False
## when there is nothing to put away or the top refuses, and nothing below the
## top is reached either way -- main.gd then opens the pause menu.
func cancel() -> bool:
	var found = null
	for entry in _entries:
		if found == null or int(entry["layer"]) >= int(found["layer"]):
			found = entry
	if found == null or not (found["cancel"] as Callable).is_valid():
		return false
	(found["cancel"] as Callable).call()
	return true


## The visibility_changed handler. Reads the node's OWN flag, not
## is_visible_in_tree(): a dimmed holder hiding re-emits on its panel while the
## panel's flag still says shown, and that is not a close.
func _sync(layer: int, node: Control, cancel_call: Callable) -> void:
	var index := -1
	for i in _entries.size():
		if _entries[i]["node"] == node:
			index = i
	var before := top()
	if node.visible and index < 0:
		_entries.append({
			"layer": layer, "node": node, "cancel": cancel_call,
			"focus": _take_focus(node) if layer >= SCENE else null,
		})
	elif not node.visible and index >= 0:
		var entry: Dictionary = _entries[index]
		_entries.remove_at(index)
		_give_focus_back(entry)
	_moved(before)


## A scene or a system screen takes the keyboard from the layer below -- an
## arrow meant for the menu must not move a lever behind it -- and remembers
## where it was. It does not focus its own first control: a scene's first button
## is a verb (a poll, a proposal, a dismissal) that Space or Enter would fire,
## so a panel that wants focus takes it itself, as the summit's Continue does.
func _take_focus(node: Control) -> Control:
	var owner := get_viewport().gui_get_focus_owner()
	if owner == null or node.is_ancestor_of(owner):
		return null
	owner.release_focus()
	return owner


## Back to the control that had it -- unless something else has taken the
## keyboard since, or that control has gone.
func _give_focus_back(entry: Dictionary) -> void:
	var below = entry["focus"]
	if below == null or not is_instance_valid(below) or not (below as Control).is_visible_in_tree():
		return
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and not (entry["node"] as Control).is_ancestor_of(owner):
		return
	(below as Control).grab_focus()


func _drop_mode(layer: int) -> void:
	for i in range(_entries.size() - 1, -1, -1):
		if _entries[i]["node"] == null and int(_entries[i]["layer"]) == layer:
			_entries.remove_at(i)


func _moved(before: int) -> void:
	var now := top()
	if now != before:
		top_changed.emit(before, now)
