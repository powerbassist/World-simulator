extends Control

## The glossary's tooltip chain -- V5.1-c, docs/design/glossary-tooltips.md "The
## behaviour". A marked term (term_text.gd) hovered for OPEN_DELAY_S opens a plate
## that explains it; a click on the term, or LOCK_HOLD_S still on it, locks the
## plate, and a locked plate takes the mouse, so a term inside it can open the
## next level -- as Crusader Kings III and Victoria 3 do, MAX_DEPTH deep.
##
## Not tip_popup.gd lifted: that is the strip's two-level, figure-anchored popup.
## This one is a list of plates with locks, a depth and the no-cycle rule (N5),
## and a third patch to the strip's machine would have been the wrong economy.
##
## **No ScreenStack rank:** a held tooltip rank would turn accepts_hotkeys() off
## under every hover. The chain eats Escape itself (_input, only while a plate is
## up), and is the stack's last child, so it draws over a scene and a system screen.
##
## Close rules, one place (tick): plate n stays while its term is under the
## pointer, or while it is locked and the pointer is on it, or while a deeper plate
## stays; the rest go GRACE_S later. An unlocked plate passes the mouse through
## ("a tooltip must never block a click on the world"), so only a locked one can
## be travelled into. Escape, or a click away from every locked plate and term,
## closes every level.
##
## Driven through enter / leave / click / tick, the calls term_text.gd makes, so a
## headless test walks the same machine the mouse does. Holds no game state: the
## live line is a figure the UI already shows (glossary_live.gd, rule L1).

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Glossary = preload("res://src/ui/glossary.gd")
const GlossaryLive = preload("res://src/ui/glossary_live.gd")
const TermText = preload("res://src/ui/term_text.gd")

## The spec's felt numbers (OPINION there, no simulation meaning, so here).
const OPEN_DELAY_S := 0.4
const GRACE_S := 0.3
const LOCK_HOLD_S := 1.2
const MAX_DEPTH := 3
## Two plates side by side fit the 960x540 floor.
const WIDTH := 360.0
const EDGE := 8.0
const GAP := 2.0
const FILL_HEIGHT := 2.0

var _state = null
var _loader = null
## Level n's plate at index n - 1: {id, panel, box, fill, locked, over, hold, anchor}.
var _plates: Array = []
## The term under the pointer at each level: 0 is prose, n is plate n's text.
var _term_at := {}
var _pending := {}
var _grace := -1.0
var _refit := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(TermText.GROUP)
	set_process(false)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	close_all()


func depth() -> int:
	return _plates.size()


func is_locked(n: int) -> bool:
	return n >= 1 and n <= _plates.size() and bool(_plates[n - 1]["locked"])


func plate(n: int) -> PanelContainer:
	return _plates[n - 1]["panel"]


## Everything plate n reads, as text: for a test, and for nothing else.
func plate_text(n: int) -> String:
	var out := PackedStringArray()
	for child in (_plates[n - 1]["box"] as Control).get_children():
		if child is RichTextLabel:
			out.append((child as RichTextLabel).get_parsed_text())
		elif child is Label:
			out.append((child as Label).text)
	return "\n".join(out)


func plate_markup(n: int) -> String:
	var out := PackedStringArray()
	for child in (_plates[n - 1]["box"] as Control).get_children():
		if child is RichTextLabel:
			out.append((child as RichTextLabel).text)
	return "\n".join(out)


# -- Events -------------------------------------------------------------------

func enter(id: String, anchor: Rect2, level: int) -> void:
	_term_at[level] = id
	if level >= MAX_DEPTH or _shows(level + 1, id):
		return
	_pending = {"id": id, "anchor": anchor, "level": level, "left": OPEN_DELAY_S}
	set_process(true)


func leave(level: int) -> void:
	_term_at.erase(level)
	if not _pending.is_empty() and int(_pending["level"]) == level:
		_pending = {}


func click(id: String, anchor: Rect2, level: int) -> void:
	_term_at[level] = id
	if level >= MAX_DEPTH:
		return
	_pending = {}
	if not _shows(level + 1, id):
		_open(id, anchor, level, 0.0)
	_lock(level + 1)


func plate_entered(n: int) -> void:
	if n <= _plates.size():
		_plates[n - 1]["over"] = true


func plate_exited(n: int) -> void:
	if n <= _plates.size():
		_plates[n - 1]["over"] = false


func close_all() -> void:
	_truncate(0)
	_pending = {}
	_grace = -1.0
	set_process(false)


func _process(delta: float) -> void:
	tick(delta)
	if _refit > 0:
		_refit -= 1
		for n in range(1, _plates.size() + 1):
			_place(n)


func tick(delta: float) -> void:
	var opened := 0  # a plate opened this tick has been held OPEN_DELAY_S, no more
	if not _pending.is_empty():
		_pending["left"] = float(_pending["left"]) - delta
		var level := int(_pending["level"])
		if float(_pending["left"]) <= 0.0:
			if _term_at.get(level, "") == _pending["id"]:
				_open(_pending["id"], _pending["anchor"], level, OPEN_DELAY_S)
				opened = level + 1
			_pending = {}
	for n in range(1, _plates.size() + 1):
		var p: Dictionary = _plates[n - 1]
		if n != opened and not p["locked"] and _term_at.get(n - 1, "") == p["id"]:
			p["hold"] = float(p["hold"]) + delta
			_show_fill(p)
			if float(p["hold"]) >= LOCK_HOLD_S:
				_lock(n)
	var keep := 0
	for n in range(_plates.size(), 0, -1):
		var p: Dictionary = _plates[n - 1]
		if _term_at.get(n - 1, "") == p["id"] or (p["locked"] and p["over"]):
			keep = n
			break
	if keep < _plates.size():
		_grace = (GRACE_S if _grace < 0.0 else _grace) - delta
		if _grace <= 0.0:
			_truncate(keep)
			_grace = -1.0
	else:
		_grace = -1.0
	if _plates.is_empty() and _pending.is_empty():
		set_process(false)


func _input(event: InputEvent) -> void:
	if _plates.is_empty():
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		close_all()
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed and _term_at.is_empty() and not _on_a_locked_plate(button.position):
		close_all()


# -- Drawing ------------------------------------------------------------------

func _open(id: String, anchor: Rect2, level: int, held: float) -> void:
	_truncate(level)
	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.PLATE
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	panel.add_child(box)
	var n := level + 1
	panel.mouse_entered.connect(plate_entered.bind(n))
	panel.mouse_exited.connect(plate_exited.bind(n))
	add_child(panel)
	var p := {"id": id, "panel": panel, "box": box, "fill": null, "locked": false,
		"over": false, "hold": held, "anchor": anchor}
	_plates.append(p)
	PanelKit.heading(box, Glossary.term(id))
	_rich(box, Glossary.definition(id), PanelKit.Tone.PLAIN, n)
	var live := Glossary.live_name(id)
	var value := GlossaryLive.value(live, _state, _loader)
	if not value.is_empty():
		var source := GlossaryLive.source(live)
		PanelKit.line(box, tr("Your value: %s") % value if source.is_empty()
			else tr("Your value: %s (%s)") % [value, source], PanelKit.Tone.PLAIN)
	var others := PackedStringArray()
	for other in Glossary.see_also(id):
		others.append("[g=%s]%s[/g]" % [other, Glossary.term(other)])
	if not others.is_empty():
		_rich(box, tr("See also: %s") % ", ".join(others), PanelKit.Tone.DIM, n)
	var fill := ColorRect.new()
	fill.color = UiTheme.accent()
	fill.custom_minimum_size = Vector2(0, FILL_HEIGHT)
	fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(fill)
	p["fill"] = fill
	_set_mouse(p)
	_show_fill(p)
	_place(n)
	_refit = 2
	set_process(true)


func _lock(n: int) -> void:
	if n > _plates.size() or _plates[n - 1]["locked"]:
		return
	var p: Dictionary = _plates[n - 1]
	p["locked"] = true
	(p["fill"] as Control).visible = false
	var body := Glossary.body(p["id"])
	if not body.is_empty():
		# Under the definition, as the spec has it: heading, definition, body.
		(p["box"] as Control).move_child(_rich(p["box"], body, PanelKit.Tone.DIM, n), 2)
	_set_mouse(p)
	_refit = 2
	set_process(true)


## A rich line at plate n: its terms open plate n + 1, and every id open up to
## and including this plate reads plain (N5).
func _rich(box: Control, text: String, tone: PanelKit.Tone, n: int) -> RichTextLabel:
	var label = PanelKit.rich(box, "", tone)
	label.level = n
	for i in n:
		label.exclude.append(String(_plates[i]["id"]))
	label.set_marked(text)
	return label


func _truncate(keep: int) -> void:
	while _plates.size() > keep:
		var p: Dictionary = _plates.pop_back()
		(p["panel"] as Node).queue_free()
		for level in range(keep + 1, MAX_DEPTH + 1):
			_term_at.erase(level)


## An unlocked plate passes the mouse through, its terms included; a locked one
## takes it, so its terms can be hovered and clicked.
func _set_mouse(p: Dictionary) -> void:
	var locked: bool = p["locked"]
	(p["panel"] as Control).mouse_filter = Control.MOUSE_FILTER_STOP if locked else Control.MOUSE_FILTER_IGNORE
	for child in (p["box"] as Control).get_children():
		if child is RichTextLabel:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_PASS if locked else Control.MOUSE_FILTER_IGNORE


func _show_fill(p: Dictionary) -> void:
	var share := clampf((float(p["hold"]) - OPEN_DELAY_S) / (LOCK_HOLD_S - OPEN_DELAY_S), 0.0, 1.0)
	(p["fill"] as Control).custom_minimum_size.x = share * (WIDTH - 2.0 * EDGE)


func _on_a_locked_plate(point: Vector2) -> bool:
	for p in _plates:
		if p["locked"] and (p["panel"] as Control).get_global_rect().has_point(point):
			return true
	return false


## Below and right of the term, flipped above when it would leave the bottom;
## a nested plate beside its parent, on whichever side fits, else below its term
## over the parent, so the term stays visible. Every plate clamped EDGE inside.
func _place(n: int) -> void:
	var p: Dictionary = _plates[n - 1]
	var panel: Control = p["panel"]
	panel.reset_size()
	var size_now := panel.get_combined_minimum_size()
	var view := get_viewport_rect().size
	var anchor: Rect2 = p["anchor"]
	var at := Vector2(anchor.position.x, anchor.end.y + GAP)
	if n > 1:
		var parent: Rect2 = (_plates[n - 2]["panel"] as Control).get_global_rect()
		at = Vector2(parent.end.x + GAP, anchor.position.y)
		if at.x + size_now.x > view.x - EDGE:
			at.x = parent.position.x - size_now.x - GAP
		if at.x < EDGE:
			at = Vector2(parent.position.x, anchor.end.y + GAP)
	if at.y + size_now.y > view.y - EDGE:
		at.y = anchor.position.y - size_now.y - GAP
	at.x = clampf(at.x, EDGE, maxf(EDGE, view.x - size_now.x - EDGE))
	at.y = clampf(at.y, EDGE, maxf(EDGE, view.y - size_now.y - EDGE))
	panel.position = at


func _shows(n: int, id: String) -> bool:
	return n <= _plates.size() and _plates[n - 1]["id"] == id
