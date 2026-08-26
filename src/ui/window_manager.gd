extends Control

## Every floating panel, and the one rule that decides which of them are on
## screen -- U5a, replacing dashboard.gd's tab rail.
##
## **Opening a panel closes the open unpinned one, and leaves every pinned one
## alone.** That single rule is the whole difference between this and a set of
## tabs: by default the player has one thing open and never has to tidy up, and
## the pin is there for the case tabs could never serve -- reading the budget
## while proposing the law that changes it.
##
## A plain Control rather than a container, because the frames position
## themselves and a container would fight every drag. MOUSE_FILTER_IGNORE on
## this node so a click on empty space falls through to the map underneath;
## each frame sets its own filter back to STOP.
##
## Holds no game state. main.gd registers panels it has already built and wired.

const WindowFrame = preload("res://src/ui/window_frame.gd")

signal opened(id: String)
signal closed(id: String)

## Each new window lands slightly down-right of the last, so two open panels are
## never exactly on top of each other with only the top one reachable.
const CASCADE_STEP := Vector2(28, 24)
const CASCADE_WRAP := 5

## Left to the map on either side, so a window never runs edge to edge and the
## background stays visible as background.
const SIDE_MARGIN := 40.0

var _frames := {}       # id -> WindowFrame
var _cascade_index := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Wraps an already-built, already-wired panel in a frame and keeps it hidden.
## The panel is reparented here and lives for the rest of the session -- closing
## hides it rather than freeing it, because every one of these holds a
## setup(state, loader) and signal connections made once at startup.
func register(id: String, title: String, content: Control) -> void:
	var frame := WindowFrame.new()
	add_child(frame)
	# setup() after add_child(): _ready() has to have run or everything the frame
	# builds is null and the content lands under nothing. CLAUDE.md's gotcha.
	frame.setup(title, content)
	frame.hide()

	frame.close_requested.connect(func(): close(id))
	frame.grabbed.connect(func(): _raise(id))

	_frames[id] = frame


func open(id: String) -> void:
	if not _frames.has(id):
		return

	for other_id in _frames.keys():
		if other_id == id:
			continue
		if _frames[other_id].visible and not _frames[other_id].pinned:
			close(other_id)

	var frame = _frames[id]
	var already_open: bool = frame.visible
	frame.show()
	if frame.has_method("mark_dirty"):
		frame.mark_dirty()
	_mark_content_dirty(frame)

	# Place it only on the way in. A pinned panel the player has dragged
	# somewhere deliberate must not jump back to the cascade when it is raised.
	if not already_open:
		_place(frame)
	_raise(id)

	opened.emit(id)


func close(id: String) -> void:
	if not _frames.has(id) or not _frames[id].visible:
		return
	_frames[id].hide()
	closed.emit(id)


func toggle(id: String) -> void:
	if is_open(id):
		close(id)
	else:
		open(id)


func is_open(id: String) -> bool:
	return _frames.has(id) and _frames[id].visible


func open_ids() -> Array:
	var ids: Array = []
	for id in _frames.keys():
		if _frames[id].visible:
			ids.append(id)
	return ids


func frame(id: String):
	return _frames.get(id, null)


## Every registered panel id, in registration order. main.gd's call order is the
## order a president spends a day in, so this is a meaningful order rather than
## an arbitrary one.
func panel_ids() -> Array:
	return _frames.keys()


## The panels themselves, unwrapped from their frames.
func panels() -> Array:
	var out: Array = []
	for id in _frames.keys():
		var content = _frames[id]._content
		if content != null:
			out.append(content)
	return out


## One repaint queued on every panel that reads GameState -- V2.1a.
##
## This replaces THREE hand-written lists of the same fourteen names:
## main.gd's `_mark_all_dirty()`, tools/screenshot.gd's `_mark_panels_dirty()`
## and, for a different job, tests/test_shell.gd's `EXPECTED_PANELS`. Each was
## written by copying the last one, and the class of bug that produces is the
## most repeated on this project's record: `_people_panel` was missing from
## main.gd's from U6b until V1.4a found it, `_projects_panel` and
## `_campaign_panel` were missing from screenshot.gd's from V1.6f and V1.7a until
## V1.8 found them, and test_shell.gd's still holds seven of fourteen.
##
## register() has known the full set the whole time. Deriving the sweep from it
## makes the omission STRUCTURALLY IMPOSSIBLE rather than remembered, which is
## the standing preference the comment above the deleted list was already
## reaching for when it predicted its own failure.
func mark_all_dirty() -> void:
	for panel in panels():
		if panel.has_method("mark_dirty"):
			panel.mark_dirty()


func close_all() -> void:
	for id in _frames.keys():
		close(id)


func _raise(id: String) -> void:
	if _frames.has(id):
		move_child(_frames[id], get_child_count() - 1)


## Sizes the window to the band between the top strip and the bottom furniture,
## centres it in that band, then steps it down-right by however many have opened
## since the last wrap.
##
## Centred in the *band*, not on the screen: a window centred on 1080 sits 75px
## lower than it looks, because 194 of those pixels belong to the strip and the
## furniture and the window may not use them.
func _place(frame: Control) -> void:
	var band := Vector2(
		size.x - SIDE_MARGIN * 2.0,
		size.y - frame.TOP_MARGIN - frame.BOTTOM_MARGIN
	)
	frame.fit_within(band)

	var offset := CASCADE_STEP * float(_cascade_index)
	frame.position = Vector2(
		(size.x - frame.size.x) / 2.0,
		frame.TOP_MARGIN + (band.y - frame.size.y) / 2.0
	) + offset
	frame.clamp_into_parent()
	_cascade_index = (_cascade_index + 1) % CASCADE_WRAP


## The docked panels rebuilt themselves on tab selection via mark_dirty(). They
## still need that call, and it is on the panel rather than on the frame.
func _mark_content_dirty(frame: Control) -> void:
	for child in frame.get_children():
		for grandchild in child.get_children():
			if grandchild.has_method("mark_dirty"):
				grandchild.mark_dirty()
