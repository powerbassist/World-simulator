extends SceneTree

## Headless test: godot --headless --script res://tests/test_layout_walker.gd
## Non-zero exit on a layout hit that tools/layout_fit_baseline.json does not list, or on a listed
## hit that no longer happens (the ratchet: a line may go, never come back without the parent's OK).
## `-- --write-baseline` rewrites the file from this run.
##
## The generic half of the fit tests: every window main.gd registers (window_manager panel_ids()),
## opened in its default state, at every text size the Settings row offers (0.9 / 1.0 / 1.15) and
## at interface size 1.0 and 0.75 (the 2560x1440 canvas), on a 1920x1080 root set by hand. The
## hand-staged states (a note on the Folder, the programme file, a city card, Save/Load full of
## saves) stay in test_dock_fit.gd, test_i18n_fit.gd and the others: this one finds the window
## nobody thought to name. Four checks, the reliable ones; sibling overlap and "outside its parent"
## were dropped as noise, and a custom _draw surface is out of reach.
##   hbar   a visible horizontal scroll bar anywhere in the workspace;
##   vbar   the page scrolls although its plate hugs (shorter than the band) or fills (its panel
##          has its own scroll built to take the height, which must absorb the overflow);
##   clip   a Label or Button cut by clip_text with no ellipsis and no wrap: the text is wider
##          than the control and nothing says so;
##   class  a PanelKit.buttons() row or a same_class() group whose buttons differ in class or,
##          in drawn size -- the group's promise (panel_kit.gd _share_class(), same_class()).

const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const InterfaceSize = preload("res://src/ui/interface_size.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const BASELINE := "res://tools/layout_fit_baseline.json"
## Interface size rows: index 1 is 1.0, index 4 is 0.75 (interface_size.gd SIZES).
const INTERFACE_ROWS: Array[int] = [1, 4]
## A measured text width against a control's: shaping and rounding differ by a pixel or two.
const TOLERANCE := 2.0

var _hits := {}  # key -> detail
var _opened := 0
var _clip_checked := 0  # premise counters: a check that never ran passes silently
var _groups_checked := 0
var _premise: Array[String] = []  # a wrong canvas: never a hit, so a rewrite cannot baseline it


func _initialize() -> void:
	for text_scale in SettingsPanel.TEXT_SCALES:
		await _sweep(text_scale)
	UiTheme.set_text_scale(1.0)
	root.content_scale_factor = 1.0
	_finish()


func _sweep(text_scale: float) -> void:
	UiTheme.set_text_scale(text_scale)
	# After a frame: a size set before the headless window's first one is lost (1920x1920 canvas).
	await process_frame
	root.size = Vector2i(1920, 1080)
	root.content_scale_factor = 1.0
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	var windows = main._windows
	for row in INTERFACE_ROWS:
		root.content_scale_factor = InterfaceSize.SIZES[row]
		await _frames(3)
		var where := "text %d, interface %d" % [roundi(text_scale * 100.0), roundi(InterfaceSize.SIZES[row] * 100.0)]
		var view: Vector2 = main.get_viewport().get_visible_rect().size
		print("layout_walker: %s, canvas %.0fx%.0f" % [where, view.x, view.y])
		var want: Vector2 = Vector2(1920.0, 1080.0) / InterfaceSize.SIZES[row]
		if not view.is_equal_approx(want):
			_premise.append("%s: canvas %.0fx%.0f, wanted %.0fx%.0f" % [where, view.x, view.y, want.x, want.y])
		for id in windows.panel_ids():
			windows.close_all()
			windows.open(String(id), true)
			await _frames(4)
			if not windows.is_open(String(id)):
				print("layout_walker: %s did not open (%s)" % [id, where])
				continue
			_opened += 1
			_check(windows, String(id), where)
	windows.close_all()
	main.queue_free()
	await process_frame


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(windows, id: String, where: String) -> void:
	var page = windows.frame(id)
	var dock: Control = windows.dock()
	# Keyed by the window and a count: a child-index path would move with any row added above it,
	# and the count keeps a second bar in a baselined window from passing under the first.
	var bars: Array[String] = []
	for node in dock.find_children("*", "ScrollContainer", true, false):
		var scroll := node as ScrollContainer
		if scroll.is_visible_in_tree() and scroll.get_h_scroll_bar().visible:
			bars.append("at %s, content %.0f px in %.0f" % [_path(dock, scroll),
				scroll.get_child(0).get_combined_minimum_size().x if scroll.get_child_count() > 0 else 0.0, scroll.size.x])
	if not bars.is_empty():
		_hit(id, where, "hbar", "%d sideways bar%s" % [bars.size(), "" if bars.size() == 1 else "s"], "; ".join(bars))
	var scroll: ScrollContainer = page._scroll
	if scroll.get_v_scroll_bar().visible:
		var band: float = dock.get_parent_area_size().y - windows.DOCK_TOP - windows.DOCK_BOTTOM
		var hugs: bool = dock.size.y < band - 0.5
		var fills: bool = bool(page._content.size_flags_vertical & Control.SIZE_EXPAND)
		if hugs or fills:
			_hit(id, where, "vbar", "hugs" if hugs else "fills", "content %.0f px in a %.0f px view" % [
				page._content.get_combined_minimum_size().y, scroll.size.y])
	for node in dock.find_children("*", "", true, false):
		if node is Label or node is Button:
			_check_clip(node as Control, id, where)
	_check_groups(dock, id, where)


## clip_text with no trimming and no wrap: the only way a Label or Button is drawn narrower than its
## text (a Control is otherwise never smaller than its minimum, which holds the whole text).
func _check_clip(control: Control, id: String, where: String) -> void:
	if not control.is_visible_in_tree() or not control.get("clip_text"):
		return
	if int(control.get("text_overrun_behavior")) != TextServer.OVERRUN_NO_TRIMMING:
		return
	if int(control.get("autowrap_mode")) != TextServer.AUTOWRAP_OFF:
		return
	var text: String = control.tr(String(control.get("text"))) if control.can_auto_translate() else String(control.get("text"))
	if control is Label and (control as Label).uppercase:
		text = text.to_upper()
	if text.strip_edges().is_empty():
		return
	_clip_checked += 1
	var font := control.get_theme_font("font")
	var font_size := control.get_theme_font_size("font_size")
	var need := 0.0
	for line in text.split("\n"):
		need = maxf(need, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var box := control.get_theme_stylebox("normal")
	if box != null:
		need += box.get_minimum_size().x
	if control is Button and (control as Button).icon != null:
		need += (control as Button).icon.get_width() + control.get_theme_constant("h_separation")
	if need > control.size.x + TOLERANCE:
		_hit(id, where, "clip", "%s '%s'" % [control.get_class(), text.left(32)], "needs %.0f px, has %.0f" % [need, control.size.x])


## A group's promise: one class for all, and one drawn size (a kit button's own floor included).
func _check_groups(dock: Control, id: String, where: String) -> void:
	var groups := {}
	for node in dock.find_children("*", "Button", true, false):
		var b := node as Button
		if not b.is_visible_in_tree() or not b.has_meta(PanelKit.CLASS_META):
			continue
		var key = null
		if b.has_meta(PanelKit.CLASS_GROUP_META):
			key = "same_class:%d" % int(b.get_meta(PanelKit.CLASS_GROUP_META))
		elif b.get_parent() is HFlowContainer and PanelKit._is_verb(b):
			key = b.get_parent()
		if key == null:
			continue
		if not groups.has(key):
			groups[key] = []
		groups[key].append(b)
	for key in groups:
		var members: Array = groups[key]
		if members.size() < 2:
			continue
		_groups_checked += 1
		var labels := ", ".join(members.map(func(b): return "'%s'" % (b as Button).text.left(16)))
		var classes := {}
		for b in members:
			classes[(b as Button).get_meta(PanelKit.CLASS_META)] = true
		if classes.size() > 1:
			_hit(id, where, "class", "a group of %d" % members.size(), "%s: %d classes in one group" % [labels, classes.size()])
			continue
		# Every member, a kit button's own floor included: PanelKit.button() keeps the class it was
		# built with as a floor (OWN_MIN_META), so a verb built L in a group that resolves to M draws
		# wider than its siblings -- the uneven row the play found.
		for axis in [0, 1]:
			var sizes: Array = []
			for b in members:
				sizes.append(roundf((b as Button).size[axis]))
			if sizes.max() - sizes.min() > 0.5:
				# The labels go in the detail, not the key: a label carrying live data would churn it.
				_hit(id, where, "class", "a group of %d, %s" % [members.size(), "widths" if axis == 0 else "heights"],
					"%s: %s px" % [labels, sizes])


## A node's place as child indices from the dock: stable between runs, where a built node's name
## (@Label@1234) is not.
func _path(from: Node, node: Node) -> String:
	var steps: Array[String] = []
	while node != from and node != null:
		steps.push_front(str(node.get_index()))
		node = node.get_parent()
	return "/".join(steps)


func _hit(id: String, where: String, kind: String, what: String, detail: String) -> void:
	var key := "%s | %s | %s | %s" % [id, where, kind, what]
	if not _hits.has(key):
		_hits[key] = detail


func _finish() -> void:
	var keys: Array = _hits.keys()
	keys.sort()
	if OS.get_cmdline_user_args().has("--write-baseline"):
		if not _premise.is_empty():
			push_error("FAIL premise, nothing written: " + "; ".join(_premise))
			quit(1)
			return
		var file := FileAccess.open(BASELINE, FileAccess.WRITE)
		file.store_string(JSON.stringify({"hits": keys}, "  ") + "\n")
		file.close()
		print("layout_walker: wrote %d hits to %s" % [keys.size(), BASELINE])
		quit(0)
		return
	var known: Array = []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BASELINE)) if FileAccess.file_exists(BASELINE) else null
	if parsed is Dictionary:
		known = parsed.get("hits", [])
	var failures := 0
	for line in _premise:
		failures += 1
		push_error("FAIL premise: " + line)
	if _opened == 0 or _clip_checked == 0 or _groups_checked == 0:
		failures += 1
		push_error("FAIL premise: %d windows opened, %d clipped labels measured, %d button groups compared" % [
			_opened, _clip_checked, _groups_checked])
	for key in keys:
		if not known.has(key):
			failures += 1
			push_error("FAIL new layout hit: %s (%s)" % [key, _hits[key]])
	for key in known:
		if not _hits.has(key):
			failures += 1
			push_error("FAIL fixed, so the baseline goes down: remove '%s' from %s" % [key, BASELINE])
	print("test_layout_walker: %d windows opened, %d clipped labels measured, %d button groups compared, %d hits, %d in the baseline, %d failures" % [
		_opened, _clip_checked, _groups_checked, keys.size(), known.size(), failures])
	quit(1 if failures > 0 else 0)
