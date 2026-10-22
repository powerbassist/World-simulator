extends Control

## Every panel, and the one rule that decides which of them is on screen -- U5a's
## floating windows, docked at V5.1-c2.2 behind the same calls.
##
## **One tab is open at a time, in a workspace docked left, under its domain's
## title and beside its domain's other tabs.** The author took the board's call
## 3 (2026-10-21): the pin goes, and back and forward replace a second window --
## the floating windows' cascade, drag and pin were the tidying a dock removes.
## Which tab sits under which domain is `domains.gd`'s table.
##
## The public calls are the ones main.gd, the tests and the probes already made
## (register, open, close, toggle, is_open, open_ids, frame, panel_ids, title,
## icon_path, shortcut, id_for_key, panels, mark_all_dirty, close_all), so the
## twenty-two panels went in without one being edited. `frame(id)` is now the
## tab's page (tab_page.gd): the scroll, the content and the fold mark.
##
## MOUSE_FILTER_IGNORE on this node so a click beside the dock falls through to
## the map underneath; the dock sets its own filter back to STOP.
##
## Holds no game state. main.gd registers panels it has already built and wired.

const TabPage = preload("res://src/ui/tab_page.gd")
const TitleBar = preload("res://src/ui/title_bar.gd")
const TopBar = preload("res://src/ui/top_bar.gd")
const Sidebar = preload("res://src/ui/sidebar.gd")
const Ribbon = preload("res://src/ui/ribbon.gd")
const Domains = preload("res://src/ui/domains.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Icon = preload("res://src/ui/icon.gd")
const Motion = preload("res://src/ui/motion.gd")
const Sound = preload("res://src/ui/sound.gd")

signal opened(id: String)
signal closed(id: String)

## The board's geometry at the 1920x1080 reference: the dock starts at the
## sidebar's right edge and is 1240 wide, which leaves the 448px strip of map
## the inbox slides over (V5.1-c3); it sits under the title bar and the figure
## strip and above the day ribbon. Every edge is read from the piece it meets,
## so the chrome and the dock cannot drift apart.
const DOCK_LEFT := Sidebar.WIDTH
const DOCK_WIDTH := 1240.0
const DOCK_TOP := TitleBar.HEIGHT + TopBar.BAR_HEIGHT
const DOCK_BOTTOM := Ribbon.STRIP_HEIGHT

## How many destinations back and forward remember -- a session's worth of
## wandering, not its whole history.
const HISTORY_DEPTH := 20

var _pages := {}        # id -> TabPage
var _keys := {}         # id -> keycode, KEY_NONE for a window with no shortcut
var _icons := {}        # id -> Material Symbols path, "" for a window with no icon yet
var _titles := {}       # id -> the title its tab shows

var _dock: VBoxContainer
var _body: Control
var _glyph: TextureRect
var _domain_label: Label
var _tab_row: HBoxContainer
var _domain := ""       # the open domain's id (a window in no row is its own)

## Destinations, "" for the map. The cursor is the one on screen.
var _history: Array[String] = []
var _cursor := -1
var _navigating := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_dock = VBoxContainer.new()
	_dock.add_theme_constant_override("separation", 0)
	_dock.anchor_bottom = 1.0
	_dock.offset_left = DOCK_LEFT
	_dock.offset_right = DOCK_LEFT + DOCK_WIDTH
	_dock.offset_top = DOCK_TOP
	_dock.offset_bottom = -DOCK_BOTTOM
	_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_dock.hide()
	add_child(_dock)
	_dock.add_child(_build_header())

	# A plain Control, not a container: a page fills it by its anchors, and a
	# test can still impose the reference band with fit_within().
	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.add_child(_body)


func _build_header() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = UiTheme.TITLE_BAR
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)

	_glyph = TextureRect.new()
	_glyph.custom_minimum_size = Vector2(16, 16)
	_glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_glyph)

	_domain_label = Label.new()
	_domain_label.theme_type_variation = UiTheme.HEADING
	_domain_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_domain_label)

	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 2)
	_tab_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_tab_row)

	var back_to_map := Button.new()
	back_to_map.text = tr("Back to the map")
	back_to_map.theme_type_variation = UiTheme.SUBROW_BUTTON
	# No focus, as on every piece of chrome: a focused button takes Space, the
	# game's pause key, for itself (V5.1-0c's forfeited Agenda).
	back_to_map.focus_mode = Control.FOCUS_NONE
	back_to_map.pressed.connect(close_all)
	row.add_child(back_to_map)
	return bar


## Wraps an already-built, already-wired panel in a page and keeps it hidden.
## The panel is reparented here and lives for the rest of the session -- closing
## hides it rather than freeing it, because every one of these holds a
## setup(state, loader) and signal connections made once at startup.
##
## `key` is the letter that toggles this tab, or KEY_NONE for one reached only by
## the mouse -- V2.1c. `icon_path` is the Material Symbols SVG a window with no
## domain row wears in the header. Both are here rather than in a table in
## main.gd, because a table in main.gd is what the keycode table WAS -- six of
## fourteen surfaces, the rest with no key at all.
func register(id: String, title: String, content: Control, key: int = KEY_NONE, icon_path: String = "") -> void:
	if key != KEY_NONE and id_for_key(key) != "":
		push_error("window '%s' takes key %s, which '%s' already has" % [
			id, OS.get_keycode_string(key), id_for_key(key),
		])
	_keys[id] = key
	_icons[id] = icon_path
	_titles[id] = title
	# A window is the widest section N1 knows (term_text.gd): a panel built with
	# headings rather than PanelKit.section bodies marks a term once in all of it.
	content.set_meta(&"term_section", {})

	var page := TabPage.new()
	_body.add_child(page)
	# setup() after add_child(): _ready() has to have run or everything the page
	# builds is null and the content lands under nothing. AGENTS.md's gotcha.
	page.setup(content)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.hide()
	_pages[id] = page


## `quiet` for a tab the GAME opens on the back of news that already has its
## sound -- the interrupt's Dispatches, whose sound is the event sting.
##
## The new page shows BEFORE the old one hides, so nothing that follows
## visibility (the screen stack, the sidebar's mark) ever sees the bare map in
## the middle of a switch.
##
## A scene in the dock (the summit) is displaced by nothing: it leaves by its own
## close. Refused here, where pages are hidden, rather than at each caller -- QA
## #54 found three map-marker handlers that opened a tab beside a summit, hid it
## and lost its dialogue, after the hotkeys and the nation click had been gated.
func open(id: String, quiet: bool = false) -> void:
	if not _pages.has(id) or (not Domains.is_scene(id) and _scene_shown()):
		return
	var page: TabPage = _pages[id]
	var already_open: bool = page.visible
	var dock_was_up: bool = _dock.visible

	_show_domain_of(id)
	# Filling the body again, whatever band a probe imposed with fit_within().
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.show()
	_dock.show()
	for other_id in _pages.keys():
		if other_id != id and _pages[other_id].visible:
			# Quiet: the tab displaced by this one is part of one gesture, and
			# the gesture's sound is the open below.
			_hide_page(other_id)
	_mark_content_dirty(page)
	_mark_tabs(id)

	if not already_open:
		# V4.9a. The dock rises when it comes up from the map; a tab switch is
		# not an arrival.
		if not dock_was_up:
			Motion.open(_dock)
		if not quiet:
			Sound.cue(self, "open")
	if not Domains.is_scene(id):
		_record(id)
	opened.emit(id)


func close(id: String, quiet: bool = false) -> void:
	if not _pages.has(id) or not _pages[id].visible:
		return
	# Recorded before the page hides, so a listener on `closed` reads the step.
	# A scene's close records the map too: the scene is never a step, but the
	# map it leaves is, so back returns to the tab the scene displaced.
	_record("")
	_hide_page(id)
	_dock.hide()
	if not quiet:
		Sound.cue(self, "close")


func toggle(id: String) -> void:
	if is_open(id):
		close(id)
	else:
		open(id)


func is_open(id: String) -> bool:
	return _pages.has(id) and _pages[id].visible


func open_ids() -> Array:
	var ids: Array = []
	for id in _pages.keys():
		if _pages[id].visible:
			ids.append(id)
	return ids


## The tab's page: its scroll, its content and its fold mark.
func frame(id: String):
	return _pages.get(id, null)


## The dock itself, for the layout tests.
func dock() -> Control:
	return _dock


## Every registered panel id, in registration order. main.gd's call order is the
## order a president spends a day in, so this is a meaningful order rather than
## an arbitrary one.
func panel_ids() -> Array:
	return _pages.keys()


## The open domain's tabs, in the table's order.
func tab_ids() -> Array:
	var out: Array = []
	for button in _tab_row.get_children():
		out.append(String(button.get_meta("tab")))
	return out


## The open domain's title as the header shows it.
func domain_title() -> String:
	return _domain_label.text


## The letter that toggles a window, or KEY_NONE.
func shortcut(id: String) -> int:
	return int(_keys.get(id, KEY_NONE))


## The title a window's tab shows -- what an alert elsewhere must call it.
func title(id: String) -> String:
	return String(_titles.get(id, id))


func icon_path(id: String) -> String:
	return String(_icons.get(id, ""))


## The window a keycode toggles, or "" -- the lookup main.gd's match block was.
func id_for_key(key: int) -> String:
	if key == KEY_NONE:
		return ""
	for id in _keys.keys():
		if int(_keys[id]) == key:
			return String(id)
	return ""


## The panels themselves, unwrapped from their pages.
func panels() -> Array:
	var out: Array = []
	for id in _pages.keys():
		var content = _pages[id]._content
		if content != null:
			out.append(content)
	return out


## One repaint queued on every panel that reads GameState -- V2.1a. Derived from
## register(), which has always known the full set: three hand-written lists of
## the same names each missed one in their time, and this makes the omission
## structurally impossible rather than remembered.
func mark_all_dirty() -> void:
	for panel in panels():
		if panel.has_method("mark_dirty"):
			panel.mark_dirty()


## Back to the map. One close cue, and one step of history.
func close_all() -> void:
	for id in open_ids():
		close(id, true)
		Sound.cue(self, "close")


func can_back() -> bool:
	return _cursor > 0


func can_forward() -> bool:
	return _cursor >= 0 and _cursor < _history.size() - 1


func back() -> void:
	if can_back():
		_go(_cursor - 1)


func forward() -> void:
	if can_forward():
		_go(_cursor + 1)


func _go(index: int) -> void:
	if _scene_shown():
		return  # open() would refuse, and the cursor must not move without it
	_navigating = true
	_cursor = index
	var to: String = _history[index]
	if to.is_empty():
		close_all()
	else:
		open(to)
	_navigating = false


## A new destination: the forward path goes, as in a browser, and the oldest
## falls off past HISTORY_DEPTH. A destination equal to the current one is not
## a step.
func _record(to: String) -> void:
	if _navigating:
		return
	if _cursor >= 0 and _history[_cursor] == to:
		return
	_history.resize(_cursor + 1)
	_history.append(to)
	if _history.size() > HISTORY_DEPTH:
		_history.remove_at(0)
	_cursor = _history.size() - 1


func _hide_page(id: String) -> void:
	_pages[id].hide()
	closed.emit(id)


## The header for the domain a tab belongs to: its glyph, its title and one tab
## per registered tab. A scene shows its own title and no tabs; a window in no
## row is its own one-tab domain.
func _show_domain_of(id: String) -> void:
	var domain := Domains.domain_of(id)
	var heading := tr(Domains.title(domain)) if not domain.is_empty() else title(id)
	var glyph_path := Domains.icon_path(domain) if not domain.is_empty() else icon_path(id)
	var tabs: Array = []
	if Domains.is_scene(id):
		domain = id
	elif domain.is_empty():
		domain = id
		tabs = [id]
	else:
		tabs = Domains.tabs(domain, _pages.keys())
	if domain == _domain:
		return
	_domain = domain
	_domain_label.text = heading
	_glyph.texture = Icon.load_icon(glyph_path, UiTheme.TEXT, 16) if not glyph_path.is_empty() else null
	for child in _tab_row.get_children():
		_tab_row.remove_child(child)
		child.queue_free()
	for tab in tabs:
		var button := Button.new()
		button.text = title(tab).to_upper()  # i18n: row-ok translated by the caller (main's register())
		button.toggle_mode = true
		button.theme_type_variation = UiTheme.SUBROW_BUTTON
		button.focus_mode = Control.FOCUS_NONE
		button.set_meta("tab", tab)
		button.pressed.connect(open.bind(String(tab)))
		_tab_row.add_child(button)


## The open tab's button wears the pressed state -- the accent, "you are here".
func _mark_tabs(open_id: String) -> void:
	for button in _tab_row.get_children():
		button.set_pressed_no_signal(String(button.get_meta("tab")) == open_id)


## The panels rebuild themselves on mark_dirty(); the call is on the panel
## rather than on the page.
func _mark_content_dirty(page: TabPage) -> void:
	if page._content != null and page._content.has_method("mark_dirty"):
		page._content.mark_dirty()


func _scene_shown() -> bool:
	for id in _pages.keys():
		if Domains.is_scene(id) and _pages[id].visible:
			return true
	return false
