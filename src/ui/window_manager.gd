extends Control

## Every panel, and the one rule that decides which of them is on screen -- U5a's
## floating windows, docked at V5.1-c2.2 behind the same calls.
##
## **One tab is open at a time, in a workspace of sheets beside the sidebar, under its
## domain's title and beside its domain's other tabs.** G3 S1: the workspace has no pane --
## its header is the first sheet (the domain, the tabs as a segmented control, the
## breadcrumb, "Back to the map"), the tab's page the second, GAP_PANE apart, and it always
## fills the band between the panes (the author's decision 9, 2026-11-21). The author took the board's call
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
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Inbox = preload("res://src/ui/inbox.gd")
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
## mark_all_dirty() ran: the state moved (every player command sweeps here; ChiefMarkView re-ranks on it).
signal dirtied

## G3 S1's geometry: the workspace starts GAP_PANE right of the sidebar's pane and GAP_PANE under
## the top strip's, ends GAP_PANE above the time bar's, and reaches GAP_PANE short of the
## screen's right edge -- always full (decision 9: a screen with little content uses fewer, wider
## sheets, and the map shows in the gaps). The inbox sits beside it at the right: while it shows,
## the workspace ends GAP_PANE short of it (_place_dock). Every edge is read from the pane it
## meets, so the chrome and the workspace cannot drift apart.
const GAP := UiTheme.GAP_PANE
const DOCK_LEFT := GAP + Sidebar.WIDTH + GAP
const DOCK_TOP := GAP + TopBar.BAR_HEIGHT + GAP
const DOCK_BOTTOM := GAP + Ribbon.STRIP_HEIGHT + GAP
## Screen 6, direction A: a tab whose place is the map docks narrow, so the nation stays on
## the map to its right (the Regions tab tints it). The one exception to the full workspace,
## until Regions' own slice (S7) re-lays it. 476: the 500 it was less S1's two gaps, so the map
## frame beside it keeps its left edge (regions_shell.gd; the chips crowd at 160 % without it).
const DOCK_WIDTHS := {"region": 476.0}
const INBOX_GROUP := "inbox"  # inbox.gd's GROUP: the column the workspace makes room for
## G3 S1: the tabs whose panel lays out its own sheets, so their page draws none (tab_page.gd). A
## screen joins this table in the slice that re-lays it on sheets (S2: the Diary).
const OWN_SHEETS := ["calendar", "finances", "companies", "sector_agriculture", "sector_industry", "sector_services", "register"]  # S3: Sectors (#441 T14); S4: Finances, Register

## How many destinations back and forward remember -- a session's worth of
## wandering, not its whole history.
const HISTORY_DEPTH := 20
const HOURGLASS := "res://assets/icons/ui/hourglass.svg"
## The manager's group: a panel that hands work to another (the companies panel's
## "Table a bill" to the Legislature's briefing) finds it here, not through main.gd.
const GROUP := "window_manager"

var _pages := {}        # id -> TabPage
var _keys := {}         # id -> keycode, KEY_NONE for a window with no shortcut
var _also_keys := {}    # keycode -> id, a window's second key (register's `also`)
var _icons := {}        # id -> Material Symbols path, "" for a window with no icon yet
var _titles := {}       # id -> the title its tab shows

var _dock: VBoxContainer
var _body: Control
var _glyph: TextureRect
var _domain_label: Label
var _tab_row: HBoxContainer
var _tab_slot: HBoxContainer   # holds the segmented control, rebuilt per domain
var _crumb_slot: HBoxContainer # the title bar's breadcrumb, docked here (dock_crumb)
var _domain := ""       # the open domain's id (a window in no row is its own)
var _tab_counts := {}   # tab id -> items waiting on the player (V5.3 screen 5)
## G3 S4: a domain's ASIDE -- one sheet at the workspace's right that stays beside every tab of that domain (the
## finance bill's rail on Finances), GAP_PANE from the page. Domain id -> Control; the page ends short of it.
var _asides := {}

## Destinations, "" for the map. The cursor is the one on screen.
var _history: Array[String] = []
var _cursor := -1
var _navigating := false


func _ready() -> void:
	add_to_group(GROUP)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_dock = VBoxContainer.new()
	_dock.add_theme_constant_override("separation", GAP)
	_dock.anchor_bottom = 1.0
	_dock.offset_left = DOCK_LEFT
	_place_dock("")
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
	# The first sheet: the domain's glyph and title, its tabs, where you are, and the way out.
	var bar := PanelContainer.new()
	bar.theme_type_variation = UiTheme.PLATE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)

	_glyph = TextureRect.new()
	_glyph.custom_minimum_size = Vector2(18, 18)
	_glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_glyph)

	_domain_label = Label.new()
	_domain_label.theme_type_variation = UiTheme.TITLE
	_domain_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_domain_label)

	_tab_slot = HBoxContainer.new()
	_tab_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_tab_slot)
	_tab_row = HBoxContainer.new()  # replaced by the segmented row on the first domain
	_tab_slot.add_child(_tab_row)   # in the slot, so the first rebuild frees it

	_crumb_slot = HBoxContainer.new()
	_crumb_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_crumb_slot)

	var back_to_map := Button.new()
	back_to_map.text = tr("Back to the map")
	back_to_map.theme_type_variation = UiTheme.GHOST
	# No focus, as on every piece of chrome: a focused button takes Space, the
	# game's pause key, for itself (V5.1-0c's forfeited Agenda).
	back_to_map.focus_mode = Control.FOCUS_NONE
	back_to_map.pressed.connect(close_all)
	row.add_child(back_to_map)
	return bar


## The title bar's breadcrumb, placed in the header sheet beside the tabs (title_bar.follow()).
func dock_crumb(label: Label) -> void:
	if label.get_parent() != null:
		label.get_parent().remove_child(label)
	_crumb_slot.add_child(label)


## The tab buttons of the open domain's segmented control, for the tests.
func tab_buttons() -> Array:
	return _tab_row.get_children()


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
## `also` keys toggle the window too: a surface that took over a retired window keeps its key
## (rework 2: the Presidency page answers O and the Outliner's Q).
func register(id: String, title: String, content: Control, key: int = KEY_NONE, icon_path: String = "", also: Array = []) -> void:
	for k in [key] + also:
		if int(k) != KEY_NONE and id_for_key(int(k)) != "":
			push_error("window '%s' takes key %s, which '%s' already has" % [
				id, OS.get_keycode_string(int(k)), id_for_key(int(k)),
			])
		elif also.has(k):
			_also_keys[int(k)] = id  # a held key stays its first window's
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
	# A panel that still builds its own Close (from before U2 docked them) loses it: the
	# frame's X is the real one, and two on one panel is worse than either. main.gd
	# called hide_close_button() after each of its 18 registrations until V5.2 C6.
	if content.has_method("hide_close_button"):
		content.hide_close_button()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if OWN_SHEETS.has(id):
		page.set_own_sheets()
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
	_place_dock(id)
	# Filling the body again, whatever band a probe imposed with fit_within().
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fit_page(page, id)
	page.show()
	_dock.show()
	for other_id in _pages.keys():
		if other_id != id and _pages[other_id].visible:
			# Quiet: the tab displaced by this one is part of one gesture, and
			# the gesture's sound is the open below.
			_hide_page(other_id)
	_mark_content_dirty(page)
	_mark_tabs(id)
	_fit_dock()  # sized on the frame it opens, not one frame later: no full-height flash

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


## A domain's aside: kept in the body, shown beside each of the domain's tabs (open), hidden elsewhere.
func set_aside(domain: String, aside: Control) -> void:
	_asides[domain] = aside
	aside.hide()
	if aside.get_parent() != null:
		aside.get_parent().remove_child(aside)  # built inside its page, so a page with no manager still has it
	_body.add_child(aside)


## Shows the aside of `id`'s domain, hides the others, and returns the room the page gives up for it: (right, top). Open,
## it stands at the body's right; folded (an aside that can fold does while the inbox shows), it is one line across the
## top, so the page keeps its width (Design's gate T1 on #443).
func _place_aside(id: String) -> Vector2:
	var room := Vector2.ZERO
	for domain in _asides:
		var aside: Control = _asides[domain]
		aside.visible = domain == Domains.domain_of(id)
		if not aside.visible:
			continue
		var folded := false
		if aside.has_method("set_folded"):
			aside.set_folded(_inbox_room() > 0.0)
			folded = aside.is_folded()
		var want := aside.get_combined_minimum_size()
		if folded:
			aside.set_anchors_preset(Control.PRESET_TOP_WIDE)
			aside.offset_left = 0.0
			aside.offset_right = 0.0
			aside.offset_top = 0.0
			aside.offset_bottom = want.y
			room = Vector2(0.0, want.y + GAP)
		else:
			aside.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
			aside.offset_left = -want.x
			aside.offset_right = 0.0
			aside.offset_top = 0.0
			aside.offset_bottom = 0.0
			room = Vector2(want.x + GAP, 0.0)
	return room


func _fit_page(page: Control, id: String) -> void:
	var room := _place_aside(id)
	# Only a page that fills the body: one a probe placed with fit_within() (top-left anchors) keeps the size it was given
	# (pass 2 T12 on #443: offsets written on it every frame shrank it to its minimum).
	if page.anchor_right < 1.0 or page.anchor_bottom < 1.0:
		return
	page.offset_right = -room.x
	page.offset_top = room.y


## The aside shown beside the open tab, or null.
func aside() -> Control:
	for domain in _asides:
		if (_asides[domain] as Control).visible:
			return _asides[domain]
	return null


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


## The panel registered as `id`, or null.
func content(id: String) -> Control:
	return _pages[id]._content if _pages.has(id) else null


## The width the dock takes for a tab on a screen `view_w` wide: its own (Regions), else the band
## beside the inbox -- the narrowest a full tab gets, since the inbox shows by default when a tab
## opens from the map (the fit tests judge a window against this; full is wider). The per-domain
## widths went at G3 S1 (decision 9).
static func dock_width(id: String, view_w := 1920.0) -> float:
	if DOCK_WIDTHS.has(id):
		return float(DOCK_WIDTHS[id])
	return view_w - GAP - DOCK_LEFT - Inbox.WIDTH - GAP


## The dock's right edge: anchored to the screen's, GAP_PANE in, or a narrow tab's own width. While
## the inbox rides over a tab (inbox.gd dock_on_map: it stays from tab to tab until put away) the
## workspace ends GAP_PANE short of it rather than under it: a full workspace under a 440 px
## column hid its right-hand verbs from the pointer (the suite's real clicks on Queue, a grade chip,
## "Table the bill" landed on the inbox). Put away, the workspace is full again on the next frame.
func _place_dock(id: String) -> void:
	if DOCK_WIDTHS.has(id):
		_dock.anchor_right = 0.0
		_dock.offset_right = DOCK_LEFT + float(DOCK_WIDTHS[id])
	else:
		_dock.anchor_right = 1.0
		_dock.offset_right = -GAP - _inbox_room()


## The width the inbox takes from the workspace's right edge when it shows, and a gap; 0 without one.
func _inbox_room() -> float:
	var inbox: Control = get_tree().get_first_node_in_group(INBOX_GROUP) as Control if is_inside_tree() else null
	return inbox.size.x + GAP if inbox != null and inbox.is_visible_in_tree() else 0.0


## The void pass (d), the author's call ("oui"): a page shorter than the dock is a plate as tall as
## its content over the map, not a full-height page with a blank bottom. Re-read every frame the
## dock is up, because a panel rebuilds on its own dirty flag and nothing signals its new height.
## The width is re-read here too, so a text size changed with a narrowed tab open takes at once.
func _process(_delta: float) -> void:
	if _dock.visible:
		_fit_dock()


func _fit_dock() -> void:
	var full: float = size.y - DOCK_TOP - DOCK_BOTTOM
	var want := full
	for id in _pages:
		var page: TabPage = _pages[id]
		if page.visible:
			_place_dock(id)
			_fit_page(page, id)
			var page_height: float = -1.0 if Domains.is_scene(id) else page.wanted_height()
			# A domain with an aside fills the band: the rail is as tall as the workspace, whatever the page.
			if page_height >= 0.0 and aside() == null:
				# The header sheet, the gap between the sheets, the page.
				want = minf(full, ceilf((_dock.get_child(0) as Control).get_combined_minimum_size().y + GAP + page_height))
	_dock.offset_bottom = -DOCK_BOTTOM - maxf(0.0, full - want)


## The height a page's content has without scrolling once the page fills the dock: the band less
## the header sheet as drawn, the gap under it and the page sheet's own margins. A panel whose sheet
## is the workspace (the register) takes it as its floor (#439 pass 2 T1: a floor of the screen less
## a fixed 64 was sized for BUREAU's 39 px header, and the taller header sheet made it scroll).
func page_room(id: String) -> float:
	var page: TabPage = _pages.get(id, null)
	var plate := page.get_theme_stylebox("panel") if page != null else null
	var header := (_dock.get_child(0) as Control).get_combined_minimum_size().y
	# A domain's aside folded to one line over the page (the bill's rail while the inbox shows) takes its height too.
	var over := aside()
	var strip: float = over.get_combined_minimum_size().y + GAP if over != null and over.has_method("is_folded") and over.is_folded() else 0.0
	return size.y - DOCK_TOP - DOCK_BOTTOM - header - GAP - strip - (plate.get_minimum_size().y if plate != null else 0.0)


## Sets `panel`'s height floor to its page's room (page_room), from wherever the panel sits.
static func fill_page(panel: Control, id: String) -> void:
	var manager = panel.get_tree().get_first_node_in_group(GROUP) if panel.is_inside_tree() else null
	if manager != null:
		panel.custom_minimum_size.y = manager.page_room(id)


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


func _offered(id: String) -> bool:
	var panel := content(id)
	return panel == null or not panel.has_method("is_offered") or bool(panel.is_offered())


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
	return String(_also_keys.get(key, ""))


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
	dirtied.emit()


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
		# A tab whose panel says it is not offered to the nation played is left out (a rule over
		# its data: the register without a stock file); a panel that says nothing is always offered.
		tabs = Domains.tabs(domain, _pages.keys()).filter(func(t): return _offered(String(t)))
	# The same domain keeps its row only while the offered tabs are the same: what a panel
	# offers can change without the domain ever changing.
	if domain == _domain and tabs == tab_ids():
		return
	_domain = domain
	_domain_label.text = heading
	_glyph.texture = Icon.load_icon(glyph_path, UiTheme.TEXT, 16) if not glyph_path.is_empty() else null
	for child in _tab_slot.get_children():
		_tab_slot.remove_child(child)
		child.queue_free()
	# G3 S1: the tabs are a segmented control in sentence case (PanelKit.segmented), the open one
	# a raised control. One tab is still shown, so a lone tab names itself as a sibling would.
	var options: Array = []
	for tab in tabs:
		options.append({"id": String(tab), "label": title(tab)})
	if options.is_empty():
		# A scene has no tabs: no segmented ground either, or an empty tile square sits by the title.
		_tab_row = HBoxContainer.new()
		_tab_slot.add_child(_tab_row)
		return
	_tab_row = PanelKit.segmented(_tab_slot, options, "", func(tab: String) -> void: open(tab))
	for button in _tab_row.get_children():
		button.focus_mode = Control.FOCUS_NONE  # chrome: Space is the pause key
		button.set_meta("tab", String(button.get_meta("segment")))
	_mark_counts()


## A tab with something waiting on the player wears the hourglass and the count
## (V5.3 screen 5: the sector tabs). A STATUS mark, the attention tone, never the
## accent; the count is the words, so it is never colour alone. Kept, so a domain
## built later picks it up; refreshed on the per-day pending pass.
func set_tab_counts(counts: Dictionary) -> void:
	_tab_counts = counts.duplicate()
	_mark_counts()


func _mark_counts() -> void:
	for button in _tab_row.get_children():
		var tab := String(button.get_meta("tab"))
		var count := int(_tab_counts.get(tab, 0))
		button.text = title(tab) + ("  %d" % count if count > 0 else "")  # i18n: row-ok translated by the caller (main's register())
		button.icon = Icon.load_icon(HOURGLASS, UiTheme.WARN, 14) if count > 0 else null
		button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT


## The open tab's segment wears the pressed state -- a raised control, "you are here".
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
