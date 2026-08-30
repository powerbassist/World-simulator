extends VBoxContainer

## The bottom-centre command bar -- U5a, replacing dashboard.gd's tab rail.
##
## Four clusters, each opening a sub-row of the panels under it. The clusters
## are themed rather than one-per-panel on purpose: this game gains surfaces
## every session (V1.3c tariffs, V1.3d the bloc, V1.3f defence, U6's calendar),
## and a flat row of one button per panel has to be redesigned the first time a
## seventh arrives. A cluster absorbs a new entry with a one-line edit in
## main.gd.
##
## Emits an id and nothing else. What that id opens is window_manager.gd's
## business -- this file never sees a panel, which is why the sub-row can list a
## surface that does not exist yet without this file knowing.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Icon = preload("res://src/ui/icon.gd")

signal panel_requested(id: String)

const ICON_PX := 22

var _subrow: HBoxContainer
var _cluster_row: HBoxContainer
var _cluster_buttons := {}   # cluster id -> Button
## cluster id -> {plain, marked}. Both tints are rasterised ONCE, at build time:
## Icon.load_icon() reads an SVG off disk and rasterises it on every call, and the
## pending mark is refreshed on the same path as the clock, which is every day.
var _cluster_icons := {}
var _entries := {}           # cluster id -> Array[Dictionary]
var _open_cluster := ""

## The window that is open and the cluster holding it, whatever route opened it
## -- V2.1c. Held rather than read back off the drawer's buttons, because the
## drawer is rebuilt from scratch every time it opens.
var _active_window := ""
var _active_cluster := ""

## Window ids with something on them awaiting an answer. Whose they are is
## src/ui/pending.gd's business; turning them into clusters is this file's,
## because `_entries` is already the only place that knows which cluster a
## window lives in.
var _pending_ids: Array = []


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 6)

	# The sub-row sits above the clusters and is its own plate, so an open
	# cluster reads as a drawer pulled out of the bar rather than as the bar
	# having grown taller.
	var subrow_holder := PanelContainer.new()
	subrow_holder.theme_type_variation = UiTheme.PLATE
	subrow_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(subrow_holder)

	_subrow = HBoxContainer.new()
	_subrow.add_theme_constant_override("separation", 2)
	subrow_holder.add_child(_subrow)
	subrow_holder.hide()

	var cluster_holder := PanelContainer.new()
	cluster_holder.theme_type_variation = UiTheme.PLATE
	cluster_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(cluster_holder)

	_cluster_row = HBoxContainer.new()
	_cluster_row.add_theme_constant_override("separation", 2)
	cluster_holder.add_child(_cluster_row)


## `entries` is an Array of {id, label, key}, where `key` is the printable name of
## the window's shortcut or "" -- main.gd reads it off the window registry, so this
## file still never sees a panel and never holds a keycode. The order of
## add_cluster() calls is the
## order along the bar, and main.gd's call order is the order a president spends
## a day in rather than alphabetical.
func add_cluster(cluster_id: String, label: String, icon_path: String, entries: Array) -> void:
	var button := Button.new()
	button.theme_type_variation = UiTheme.CLUSTER_BUTTON
	button.toggle_mode = true
	button.text = label.to_upper()
	button.icon = Icon.load_icon(icon_path, UiTheme.TEXT, ICON_PX)
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = false
	# Icon above the label rather than beside it: four clusters side by side
	# with horizontal icons is twice as wide as the reference's bar.
	button.add_theme_constant_override("h_separation", -ICON_PX)
	button.custom_minimum_size.x = 92
	button.pressed.connect(func(): _toggle_cluster(cluster_id))

	_cluster_row.add_child(button)
	_cluster_buttons[cluster_id] = button
	_cluster_icons[cluster_id] = {
		"plain": button.icon,
		"marked": Icon.load_icon(icon_path, UiTheme.ACCENT, ICON_PX),
	}
	_entries[cluster_id] = entries


## Public so Escape and a click on the map can both shut the drawer, and so a
## headless test can assert it closed without synthesising a click.
func close_subrow() -> void:
	_open_cluster = ""
	_refresh_clusters()
	_subrow.get_parent().hide()


func open_cluster() -> String:
	return _open_cluster


## Pull a cluster's drawer open from outside -- V2.1c. tools/screenshot.gd
## photographs it, and a headless check can read its marks without synthesising a
## click, which is `close_subrow()`'s own reason one direction round.
func show_cluster(cluster_id: String) -> void:
	if _open_cluster != cluster_id:
		_toggle_cluster(cluster_id)


## Which window is open, whatever opened it -- V2.1c, and the first consumer of
## `WindowManager.opened`, declared at U5a and connected to nothing since.
##
## The bar was the only route that marked itself: a keypress, a click on a map
## marker (U6c) and a click on a message card (V1.8) all opened a window while the
## bar went on showing nothing, so the one control that says where you are was
## wrong for three of the four ways of getting there.
func show_active(window_id: String) -> void:
	_active_window = window_id
	_active_cluster = cluster_of(window_id)
	_refresh_clusters()
	_mark_subrow(window_id)


func clear_active() -> void:
	_active_window = ""
	_active_cluster = ""
	_refresh_clusters()
	_mark_subrow("")


## The clusters holding something that awaits the player -- V2.1c. The mark is the
## cluster icon in brass, which is the signature this interface already uses for
## *the state's own material marks what matters* (docs/panel-system.md section 4)
## rather than a second visual rule. No plate is added and nothing is drawn on the
## map: what the mark says is WHERE THE ANSWER IS GIVEN, which is navigation.
func show_pending(window_ids: Array) -> void:
	if window_ids == _pending_ids:
		return
	_pending_ids = window_ids.duplicate()
	_refresh_clusters()


func cluster_of(window_id: String) -> String:
	for cluster_id in _entries.keys():
		for entry in _entries[cluster_id]:
			if str(entry["id"]) == window_id:
				return cluster_id
	return ""


func pending_clusters() -> Array:
	var out: Array = []
	for window_id in _pending_ids:
		var cluster_id := cluster_of(str(window_id))
		if not cluster_id.is_empty() and not out.has(cluster_id):
			out.append(cluster_id)
	return out


## One place decides how every cluster button looks, because three things now
## claim it -- the drawer, the open window and a pending decision -- and three
## separate writers is how they disagree.
func _refresh_clusters() -> void:
	var pending := pending_clusters()
	for id in _cluster_buttons.keys():
		var button: Button = _cluster_buttons[id]
		button.button_pressed = (id == _open_cluster or id == _active_cluster)
		var icons: Dictionary = _cluster_icons[id]
		button.icon = icons["marked"] if pending.has(id) else icons["plain"]


## The open window's own entry, inside the drawer. Toggle mode so the theme's
## existing pressed style does the work -- no new variation, and the drawer says
## the same thing the cluster row says one level down.
func _mark_subrow(window_id: String) -> void:
	for child in _subrow.get_children():
		if child is Button:
			child.button_pressed = (child.has_meta("window_id")
				and str(child.get_meta("window_id")) == window_id)


func _toggle_cluster(cluster_id: String) -> void:
	if _open_cluster == cluster_id:
		close_subrow()
		return

	_open_cluster = cluster_id
	_refresh_clusters()

	for child in _subrow.get_children():
		child.queue_free()
		_subrow.remove_child(child)

	for entry in _entries[cluster_id]:
		var button := Button.new()
		button.theme_type_variation = UiTheme.SUBROW_BUTTON
		button.toggle_mode = true
		button.text = str(entry["label"]).to_upper()
		# V2.3: the window's own glyph beside its name in the drawer -- the same
		# icon the title bar above the open window wears, from the entry's own
		# "icon" field, which _entry() reads off the window registry. Rasterised
		# per drawer open rather than cached: the drawer rebuilds its buttons
		# every time, and caching here would be a second lifetime to keep
		# correct for a decode the cluster row already proved is cheap.
		var icon_path := str(entry.get("icon", ""))
		if not icon_path.is_empty():
			button.icon = Icon.load_icon(icon_path, UiTheme.TEXT, 16)
			button.expand_icon = false
			button.add_theme_constant_override("h_separation", 6)
		var id := str(entry["id"])
		button.set_meta("window_id", id)
		# A shortcut nobody can find is not a shortcut. top_bar.gd's SAVE and MENU
		# buttons have named theirs in a tooltip since U5a; this is that, for the
		# fourteen windows.
		var key := str(entry.get("key", ""))
		button.tooltip_text = str(entry["label"]) if key.is_empty() else "%s (%s)" % [
			str(entry["label"]), key,
		]
		# A toggle button flips itself on press, so the open window -- not the
		# click -- is what decides the mark. Set back and let show_active() say.
		button.pressed.connect(func():
			button.button_pressed = false
			panel_requested.emit(id)
		)
		_subrow.add_child(button)

	_mark_subrow(_active_window)
	_subrow.get_parent().show()
