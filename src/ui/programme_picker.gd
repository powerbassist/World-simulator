extends HBoxContainer

## The Agenda's term-start offer -- V5.3-0 (b), docs/design/v5.3-0-readability.md
## 3.3. The first screen a new player meets was the heaviest in the game: every
## programme's blurb printed on the list, 28 rows and 1 470 words of authored text
## (3.2's inventory). The Legislature's shape (law_list.gd, 0b's "Au clic, jamais
## coupés") now applies here: one row per entry, its name and what lets the player
## shortlist before reading -- the clock, the blocs that welcome it -- and the
## selected entry's text WHOLE in the detail beside the list, with its Choose.
##
## The agenda panel (agenda_panel.gd) still owns the command (programme_chosen) and
## the reads (_read_text, _clock_text); this file lays the offer out.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")

## An entry's name never squeezes below this (px at 100 %); past it the name clips
## and its tooltip carries it whole. The chip columns: the clock, the blocs.
const NAME_WIDTH := 200.0
const COLUMNS := [64.0, 150.0]
## The blocs named on a row before "+N".
const BLOCS_NAMED := 2

var _panel
var _rows: VBoxContainer
var _detail: VBoxContainer
var _shown: Array = []
var _selected := ""
var _ns


func _init(panel) -> void:
	_panel = panel
	name = "Offer"  # i18n: ok
	add_theme_constant_override("separation", 20)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows = _column(0.6)
	_rows.add_theme_constant_override("separation", 2)
	_detail = _column(0.4)
	_detail.add_theme_constant_override("separation", 8)


func _column(ratio: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = ratio
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


## The list column, for the panel to add what reads under the offer (the register).
func rows() -> VBoxContainer:
	return _rows


func selected_id() -> String:
	return _selected


## Sections per group, in the constants' own order, each by authored weight (the
## sweep in tests/test_programme.gd pins one on every entry). A group with nothing
## offered draws nothing.
func fill(ns, offer: Array) -> void:
	for box in [_rows, _detail]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_ns = ns
	_shown = []
	var by_group := {}
	for terms in offer:
		var group := String(terms.get("group", ""))
		if not by_group.has(group):
			by_group[group] = []
		(by_group[group] as Array).append(terms)
	_header()
	var section_of := {}
	for group in ProgrammeK.GROUPS:
		if not by_group.has(group):
			continue
		var entries: Array = by_group[group]
		entries.sort_custom(func(a, b): return float(a.get("weight", 0.0)) > float(b.get("weight", 0.0)))
		section_of[group] = PanelKit.section(_rows, Labels.programme_group(String(group)))
		_shown.append_array(entries)
	if _shown.is_empty():
		return
	if not _shown.any(func(t): return String(t["id"]) == _selected):
		_selected = String(_shown[0]["id"])
	for terms in _shown:
		section_of[String(terms.get("group", ""))].add_child(_row(terms))
	select(_selected)


## Opens an entry's detail; the selection survives the panel's refreshes.
func select(entry_id: String) -> void:
	_selected = entry_id
	for pick in _picks():
		pick.set_pressed_no_signal(String(pick.get_meta("entry")) == entry_id)
		pick.flat = not pick.button_pressed
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	for terms in _shown:
		if String(terms["id"]) == entry_id:
			_build_detail(terms)


func _picks() -> Array:
	var out: Array = []
	for section in _rows.get_children():
		for node in section.find_children("*", "Button", true, false):  # i18n: ok a class name
			if node.has_meta("entry"):
				out.append(node)
	return out


func _row(terms: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var pick := Button.new()
	pick.text = Strings.row_name("programme", terms)
	pick.tooltip_text = pick.text
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.toggle_mode = true
	pick.flat = true
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.clip_text = true
	pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pick.custom_minimum_size.x = NAME_WIDTH * UiTheme.text_scale()
	pick.set_meta("entry", String(terms["id"]))
	pick.pressed.connect(select.bind(String(terms["id"])))
	row.add_child(pick)
	row.add_child(_chip(_clock_chip(terms), COLUMNS[0]))
	var liked := liked_by(terms)
	var chip := _chip(_blocs_chip(liked), COLUMNS[1])
	chip.tooltip_text = ", ".join(liked.map(func(b): return Labels.bloc(String(b))))
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(chip)
	return row


## The columns' names, once above the list, so a row's "term" and its blocs read
## without a legend.
func _header() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size.x = NAME_WIDTH * UiTheme.text_scale()
	row.add_child(spacer)
	row.add_child(_chip(tr("Deadline"), COLUMNS[0]))
	row.add_child(_chip(tr("Welcomed by"), COLUMNS[1]))
	_rows.add_child(row)


func _chip(text: String, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = UiTheme.CAPTION
	label.custom_minimum_size.x = width * UiTheme.text_scale()
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


## The clock as a chip: its months, or the term's end for a goal without one.
func _clock_chip(terms: Dictionary) -> String:
	var timeout := int(terms.get("timeout_months", 0))
	return tr("%d mo") % timeout if timeout > 0 else tr("term")


func _blocs_chip(liked: Array) -> String:
	if liked.is_empty():
		return ""
	var names: Array = liked.slice(0, BLOCS_NAMED).map(func(b): return Labels.bloc(String(b)))
	if liked.size() > BLOCS_NAMED:
		return tr("%s +%d") % [", ".join(names), liked.size() - BLOCS_NAMED]
	return ", ".join(names)


## The blocs an entry welcomes: a positive offset on choosing it or on delivering
## it, the larger first -- the authored numbers the sim books (programme.gd).
static func liked_by(terms: Dictionary) -> Array:
	var best := {}
	for key in ["immediate", "on_complete"]:
		var offsets: Dictionary = (terms.get(key, {}) as Dictionary).get("bloc_offset", {})
		for bloc in offsets:
			if float(offsets[bloc]) > 0.0:
				best[bloc] = maxf(float(best.get(bloc, 0.0)), float(offsets[bloc]))
	var out: Array = best.keys()
	out.sort_custom(func(a, b): return float(best[a]) > float(best[b]) or (best[a] == best[b] and String(a) < String(b)))
	return out


## The selected entry: its name, its text whole, the read and the clock, who
## welcomes it, and Choose.
func _build_detail(terms: Dictionary) -> void:
	var block := _detail
	PanelKit.heading(block, Strings.row_name("programme", terms))
	PanelKit.rich(block, Strings.row_summary("programme", terms))
	PanelKit.line(block, "%s · %s" % [_panel._read_text(_ns, terms), _panel._clock_text(terms, 0, false)], PanelKit.Tone.DIM)
	var liked := liked_by(terms)
	if not liked.is_empty():
		PanelKit.line(block, tr("Welcomed by: %s") % ", ".join(liked.map(func(b): return Labels.bloc(String(b)))), PanelKit.Tone.DIM)
	var button := PanelKit.sized(Button.new())
	button.text = tr("Choose")
	var entry_id := String(terms["id"])
	# The verb is a SIGNAL, not a call: the panel names what was chosen and
	# main.gd performs the command. The panel never writes GameState.
	button.pressed.connect(func(): _panel.programme_chosen.emit(entry_id))
	# V5.3-0 RF3: Choose acts on the entry and on the offer the briefing holds a line for.
	ActsOn.tag(button, [entry_id, "offer"])
	PanelKit.buttons(block).add_child(button)
	_panel._primary = button
