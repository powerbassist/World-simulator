extends PanelContainer

## The Presidency page -- rework 2, slice 1 (presidency-page-brief.md, direction A, the
## author's "A, le mandat"). One page replaces the Overview and the Outliner; it keeps the
## window id "overview" (the Q and O keys, country_box's Go and the stagings address it).
##
## FIVE PARTS, IN THIS ORDER. The lead is the chief's read; the term is where it stands, the
## slow things no other surface draws; then what to open now, what the country wants, and,
## folded, what the player's decisions did. The page holds no decision of its own: every row
## is a door to the tab that holds one ("no row without a door").
##
## ONE RANKING. The lead draws the month's STORED lines (set_read(), pushed by
## chief_mark_view.gd whenever the mark is named), never a second Priorities.rank(): the
## ranking's memory is the caller's, so a second call could disagree with the mark.
##
## Reads GameState and the loader and writes neither (engine-decision.md rule 2): a door asks
## through window_requested / go_requested, and main performs it.

## A door: main opens that window.
signal window_requested(window_id: String)
## The lead's row `index` was pressed: the briefing's own Go table performs it.
signal go_requested(index: int)
## The requests count was pressed: the inbox's requests, as the title bar's mark does.
signal requests_requested

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Icon = preload("res://src/ui/icon.gd")
const Grade = preload("res://src/ui/grade.gd")
const Trends = preload("res://src/ui/trends.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Num = preload("res://src/ui/num.gd")
const TermReads = preload("res://src/ui/term_reads.gd")
const TermLane = preload("res://src/ui/term_lane.gd")
const PriorityWords = preload("res://src/ui/priority_words.gd")
const OutlinerReadings = preload("res://src/ui/outliner_readings.gd")
const PresidencyRows = preload("res://src/ui/presidency_rows.gd")
const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const MoodBadge = preload("res://src/ui/mood_badge.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")

## What the country wants: the two issues the Overview kept.
const TOP_ISSUE_COUNT := 2
## Past decisions under the fold (the Overview's U4 number).
const DECISIONS_SHOWN := 5
## The gutter beside the term's lanes, px at text size 100 %.
const GUTTER := 230.0
const FACE_PX := 64

var _state
var _loader
var _dirty := true
var _read := {}
## The Folder's "To answer" count, asked when the lead is drawn (files_driver.gd sets it): one count, whether
## or not a month end has pushed a read yet (QA's TAKE 2 on #403, day 1).
var files_count := Callable()
## A re-rank queued for the frame's end (chief_mark_view.gd), run here first when a build comes before
## it: a build on the old read drew the lead the command had just made stale, then built again once the
## read landed (#401 pass 2, RECORD 11). Empty when none waits.
var _read_now := Callable()
## Builds since boot: a test counts them.
var builds := 0

var _title: Label
var _lead_box: HBoxContainer
var _face: TextureRect
var _who: Label
var _said: Label
var _rows_box: VBoxContainer
var _lead_rows: Array = []
var _count_doors := {}
var _term_box: VBoxContainer
var _term_head: Label
var _approval_lane: Control
var _approval_figure: Label
var _goal_doors: Array = []
var _majority_door: Button
var _open_box: VBoxContainer
var _open_rows: Array = []
var _wants_box: VBoxContainer
var _decided_toggle: Button
var _decided_box: VBoxContainer


func _ready() -> void:
	var root := PanelKit.padded(self, 16, 10)
	_title = PanelKit.heading(root, tr("OVERVIEW"))
	_build_lead(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	PanelKit.heading(head, tr("THE TERM"))
	_term_head = Label.new()
	_term_head.theme_type_variation = UiTheme.CAPTION
	_term_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_term_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_term_head)
	_term_box = VBoxContainer.new()
	_term_box.add_theme_constant_override("separation", 0)
	root.add_child(_term_box)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	root.add_child(cols)
	_open_box = PanelKit.section(cols, tr("OPEN NOW"))
	_open_box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wants_box = PanelKit.section(cols, tr("WHAT THE COUNTRY WANTS"))
	_wants_box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(HSeparator.new())
	_decided_toggle = PanelKit.sized(Button.new())
	_decided_toggle.flat = true
	_decided_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_decided_toggle.pressed.connect(func() -> void:
		_decided_box.visible = not _decided_box.visible
		_decided_toggle.text = _fold_text())
	root.add_child(_decided_toggle)
	_decided_box = VBoxContainer.new()
	_decided_box.visible = false
	root.add_child(_decided_box)


func _build_lead(root: Control) -> void:
	_lead_box = HBoxContainer.new()
	_lead_box.add_theme_constant_override("separation", 16)
	root.add_child(_lead_box)
	_face = TextureRect.new()
	_face.custom_minimum_size = Vector2(FACE_PX, FACE_PX)
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	Grade.apply(_face)
	_lead_box.add_child(_face)
	var said := VBoxContainer.new()
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	said.add_theme_constant_override("separation", 2)
	_lead_box.add_child(said)
	_who = Label.new()
	_who.theme_type_variation = UiTheme.CAPTION
	said.add_child(_who)
	_said = Label.new()
	_said.theme_type_variation = UiTheme.LEAD
	_said.autowrap_mode = TextServer.AUTOWRAP_WORD
	said.add_child(_said)
	_rows_box = VBoxContainer.new()
	said.add_child(_rows_box)
	var counts := VBoxContainer.new()
	counts.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_lead_box.add_child(counts)
	for id in ["files", "requests"]:
		var door := PanelKit.sized(Button.new())
		door.alignment = HORIZONTAL_ALIGNMENT_LEFT
		counts.add_child(door)
		_count_doors[id] = door
	_count_doors["files"].pressed.connect(func() -> void: window_requested.emit("events"))
	_count_doors["requests"].pressed.connect(func() -> void: requests_requested.emit())


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


## The chief's read, from the month the briefing driver keeps: {lines, who, face, said}
## (chief_mark_view.gd). An empty read is a month not ranked yet.
func set_read(read: Dictionary) -> void:
	_read = read
	_read_now = Callable()
	_dirty = true


## A command swept the panels and the read is re-ranked at the frame's end; `rank` runs it now.
func await_read(rank: Callable) -> void:
	_read_now = rank


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null or _state.player() == null:
		return
	if _read_now.is_valid():
		_read_now.call()  # lands through set_read, so the one build below draws the fresh lead
	_dirty = false
	builds += 1
	_refresh()


func _refresh() -> void:
	var ns = _state.player()
	var nation = _loader.nations.get(ns.id) if _loader != null else null
	_title.text = tr("OVERVIEW — %s%s") % [nation.nation_name if nation != null else ns.id, PresidencyRows.start_suffix(_state, _loader)]
	_fill_lead(ns)
	_fill_term(ns)
	_fill_open()
	_fill_wants(ns)
	_fill_decided()


# --- 1. the lead -------------------------------------------------------------

func _fill_lead(ns) -> void:
	_face.texture = _read.get("face")
	_face.visible = _face.texture != null
	# His mood, which the retired plate wore (V5.3-0's emotion kit); a read with none keeps no old one.
	if not (_read.get("feel", {}) as Dictionary).is_empty():
		MoodBadge.wear(_face, _read["feel"])
	elif _face.has_node("MoodBadge"):
		_face.get_node("MoodBadge").free()
	_who.text = String(_read.get("who", ""))
	_said.text = String(_read.get("said", ""))
	_said.visible = not _said.text.is_empty()
	_clear(_rows_box)
	_lead_rows.clear()
	var lines: Array = _read.get("lines", [])
	if not _read.has("lines"):
		PanelKit.line(_rows_box, tr("The chief reports at the month's end."))
	elif lines.is_empty():
		PanelKit.line(_rows_box, tr("Nothing presses this month."))
	for i in lines.size():
		_lead_rows.append(_lead_row(lines[i], i))
	PresidencyRows.also_due(_rows_box, _read.get("also", []), go_requested.emit)
	# One count, the Folder's "To answer" (#403 pass 2 T11), pushed with the read.
	var files: int = int(files_count.call()) if files_count.is_valid() else ns.event_queue.size()
	_count_doors["files"].text = tr_n("%d file to answer", "%d files to answer", files) % files
	var waiting := Audiences.waiting_count(ns)
	_count_doors["requests"].text = tr_n("%d request waiting", "%d requests waiting", waiting) % waiting
	_count_doors["requests"].disabled = waiting == 0  # no request: nothing to open


func _lead_row(line: Dictionary, index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_rows_box.add_child(row)
	var icon := TextureRect.new()
	icon.texture = Icon.load_icon(PriorityWords.icon_path(String(line["kind"])), UiTheme.TEXT_DIM, 18)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var title := _one_line(PanelKit.plain_line(row, PriorityWords.title(line, _state, _loader), PanelKit.Tone.PLAIN), true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.tooltip_text = title.text  # the whole title when the dock cuts it
	var chip := PriorityWords.chip(line, _state)
	if bool(line.get("held", false)):
		# A held line says so in words, never by its colour alone (the briefing's rule).
		chip = tr("Waiting on you") if chip.is_empty() else tr("Waiting on you · %s") % chip
	if not chip.is_empty():
		var tag := _one_line(PanelKit.plain_line(row, chip))
		if bool(line.get("held", false)):
			tag.theme_type_variation = UiTheme.WARN_TEXT
	var go := PanelKit.sized(Button.new())
	go.text = tr("Go")
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func() -> void: go_requested.emit(index))
	row.add_child(go)
	return row


# --- 2. the term -------------------------------------------------------------

func _fill_term(ns) -> void:
	_clear(_term_box)
	_goal_doors.clear()
	var past: Array = TermReads.past(_state)
	var ahead := TermReads.ahead(_state)
	var vote := Trends.vote_date(ns)
	# Named (V5.2-0b): Society counts the assembly's vote, so an unnamed count reads as a contradiction.
	if bool(ns.has_executive):
		_term_head.text = tr("Past year · %s until the presidential vote, %s") % [Trends.months_text(ahead), DateText.month_year(vote.y, vote.x)]
	else:
		_term_head.text = tr("Past year · %s until the assembly vote, %s") % [Trends.months_text(ahead), DateText.month_year(vote.y, vote.x)]
	var months: Array = []
	for e in past:
		months.append([int(e.get("year", 0)), int(e.get("month", 0))])
	_lane_row(null, _lane(TermLane.Kind.HEAD, past.size(), ahead,
		{"months": months, "today": [int(_state.year), int(_state.month)]}), "")
	_fill_approval(past, ahead)
	var lanes: Array = TermReads.goal_lanes(_state, _loader)
	for lane in lanes:
		_fill_goal(lane, past.size(), ahead)
	if lanes.is_empty():
		var to_choose := not Programme.available(_state, ns, _loader).is_empty()
		var gutter := _gutter(tr("Programme"), tr("To choose") if to_choose else tr("None this term"))
		_lane_row(gutter, _lane(TermLane.Kind.NOTE, past.size(), ahead, {"text":
			tr("One goal, judged at the vote.") if to_choose else ""}), "programme" if to_choose else "")
	_fill_majority(ns)
	_fill_state(ns)


func _fill_approval(past: Array, ahead: int) -> void:
	var values: PackedFloat64Array = TermReads.approval(past)
	var gutter := VBoxContainer.new()
	gutter.add_theme_constant_override("separation", 0)
	PanelKit.plain_line(gutter, tr("Approval (polls)"), PanelKit.Tone.PLAIN)
	_approval_figure = Label.new()
	_approval_figure.theme_type_variation = UiTheme.FIGURE
	_approval_figure.text = "%s%%" % Num.f(TermReads.approval_now(_state), 0)
	gutter.add_child(_approval_figure)
	var change := Trends.approval_delta(_state, Trends.TREND_MONTHS)
	if not is_nan(change):
		PanelKit.plain_line(gutter, tr("%s in %d months") % [Trends.change_text(change), Trends.TREND_MONTHS], PanelKit.tone_for(change, false))
	elif values.size() < 2:
		PanelKit.plain_line(gutter, tr("Fills in as the months pass."))
	_approval_lane = _lane_row(gutter, _lane(TermLane.Kind.APPROVAL, past.size(), ahead, {"values": values}), "society")


func _fill_goal(lane: Dictionary, past: int, ahead: int) -> void:
	var status := String(lane["status"])
	var word := "%s%%" % Num.f(float(lane["fraction"]) * 100.0, 0)
	var tone := PanelKit.Tone.PLAIN
	match status:
		ProgrammeK.STATUS_COMPLETE:
			word = tr("Delivered")
			tone = PanelKit.Tone.GOOD
		ProgrammeK.STATUS_FAIL:
			word = tr("Missed")
			tone = PanelKit.Tone.BAD
		ProgrammeK.STATUS_ACTIVE:
			pass
		_:
			word = tr("Overtaken")
			tone = PanelKit.Tone.DIM
	var gutter := VBoxContainer.new()
	gutter.add_theme_constant_override("separation", 0)
	var name := _one_line(PanelKit.plain_line(gutter, String(lane["name"]), PanelKit.Tone.PLAIN), true)  # i18n: row-ok term_reads routes it through Strings.row
	name.tooltip_text = String(lane["tip"])
	gutter.tooltip_text = String(lane["tip"])
	gutter.mouse_filter = Control.MOUSE_FILTER_PASS
	var bar_row := HBoxContainer.new()
	gutter.add_child(bar_row)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(64.0, 6.0)
	bar.max_value = 1.0
	bar.step = 0.0  # Range's 0.01 snap would round the fraction away from the printed pair
	bar.value = float(lane["fraction"])
	bar.show_percentage = false
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(bar)
	_one_line(PanelKit.plain_line(bar_row, word, tone))
	var row := _lane_row(gutter, _lane(TermLane.Kind.GOAL, past, ahead, lane), String(lane["tab"]))
	_goal_doors.append(row.get_child(2))
	# S3: the programme's Go lands here, on the entry's own door (the Agenda's "Work on it" retired).
	ActsOn.tag(row.get_child(2), [String(lane["id"])])


func _fill_majority(ns) -> void:
	var line := VBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for part in PresidencyRows.majority(ns, _loader):
		PanelKit.plain_line(line, String(part[0]), int(part[1]))
	var row := _lane_row(_gutter(tr("Majority"), ""), line, "majority")
	_majority_door = row.get_child(2)


func _fill_state(ns) -> void:
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for read in PresidencyRows.state_lines(_state, ns):
		_door_row(lines, String(read[0]), int(read[1]), String(read[2]))
	# Each line is its own door (defence and services open different tabs): no lane door.
	_lane_row(_gutter(tr("The state"), ""), lines, "")


## A lane: [gutter | plot | door]. `window` "" draws no door.
func _lane_row(gutter: Control, plot: Control, window: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_term_box.add_child(row)
	var g := gutter if gutter != null else Control.new()
	g.custom_minimum_size.x = GUTTER * UiTheme.text_scale()
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(g)
	plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(plot)
	var door := PanelKit.sized(Button.new())
	door.flat = true
	door.text = "›"  # i18n: ok a glyph
	door.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A lane without a door keeps the door's space, so every plot is one width and the head's
	# TODAY and VOTE sit over the seam and the diamond of every lane below (#401 pass 2 T2).
	if window == "":
		door.disabled = true
		door.focus_mode = Control.FOCUS_NONE
		door.mouse_filter = Control.MOUSE_FILTER_IGNORE
		door.modulate = Color.TRANSPARENT
	door.tooltip_text = tr("Open")
	door.pressed.connect(func() -> void: window_requested.emit(window))
	row.add_child(door)
	_term_box.add_child(HSeparator.new())
	return row


func _gutter(name: String, sub: String) -> VBoxContainer:
	var g := VBoxContainer.new()
	g.add_theme_constant_override("separation", 0)
	_one_line(PanelKit.plain_line(g, name, PanelKit.Tone.PLAIN))
	if sub != "":
		_one_line(PanelKit.plain_line(g, sub))
	return g


func _lane(kind: TermLane.Kind, past: int, ahead: int, data: Dictionary) -> Control:
	var lane := TermLane.new()
	lane.setup(kind, past, ahead, data)
	return lane


# --- 3. open now, 4. what the country wants ----------------------------------

func _fill_open() -> void:
	_clear(_open_box)
	_open_rows.clear()
	for section in OutlinerReadings.SECTIONS:
		# The programme's pins are the term's lanes now.
		if section == "agenda":
			continue
		var r: Dictionary = OutlinerReadings.read(section, _state, _loader)
		if not bool(r["visible"]):
			continue
		# Each section keeps its title and its own cap ("+N more", the register's ROW_CAP).
		var title := PanelKit.plain_line(_open_box, String(r["title"]))
		title.theme_type_variation = UiTheme.MICRO
		for row in (r["rows"] as Array):
			_open_rows.append(_door_row(_open_box, String(row["text"]), int(row["tone"]), String(row["window"])))
	if _open_rows.is_empty():
		PanelKit.line(_open_box, tr("Nothing pinned."))


func _fill_wants(ns) -> void:
	_clear(_wants_box)
	var top := Opinion.top_issues(ns, TOP_ISSUE_COUNT)
	var satisfaction := Opinion.issue_satisfaction(ns)
	if top.is_empty():
		PanelKit.line(_wants_box, PanelKit.MISSING)
	for entry in top:
		var issue: String = entry[0]
		var sat := float(satisfaction.get(issue, 0.0))
		_door_row(_wants_box, PresidencyRows.issue_text(issue, float(entry[1]), sat), PresidencyRows.satisfaction_tone(sat), "society")


## A row whose words keep their tone and whose door is the chevron; a click on the words opens it too.
func _door_row(parent: Control, text: String, tone: int, window: String) -> Button:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _one_line(PanelKit.plain_line(row, text, tone), true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = text  # the whole line when the dock trims it
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var door := PanelKit.sized(Button.new())
	door.flat = true
	door.text = "›"  # i18n: ok a glyph
	door.tooltip_text = tr("Open")
	door.pressed.connect(func() -> void: window_requested.emit(window))
	row.add_child(door)
	label.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			door.pressed.emit())
	return door


# --- 5. what your decisions did ----------------------------------------------

func _fill_decided() -> void:
	_clear(_decided_box)
	# The month's booked effects first (the retired plate's "What your choices did"), then the ledger.
	for effect in _read.get("effects", []):
		_decided_box.add_child(PresidencyRows.choice_effect(effect))
	var entries: Array = _state.recent_effects
	if entries.is_empty() and (_read.get("effects", []) as Array).is_empty():
		PanelKit.line(_decided_box, tr("Nothing committed yet this game."))
	for i in mini(DECISIONS_SHOWN, entries.size()):
		_decided_box.add_child(PresidencyRows.effect_row(entries[i]))
	_decided_toggle.text = _fold_text()


func _fold_text() -> String:
	# What the fold holds, both lists (#403 pass 2 T8).
	var held: int = (_read.get("effects", []) as Array).size() + (mini(DECISIONS_SHOWN, _state.recent_effects.size()) if _state != null else 0)
	return ("▾ " if _decided_box.visible else "▸ ") + tr("What your decisions did (%d)") % held  # i18n: ok the fold's glyph


## A label on one line: in an HBox a wrapping label is given no width and stacks its words one
## letter wide. `trim` for the one label of a row that takes the spare width: it is trimmed with
## an ellipsis instead of pushing the row wider (a trimmed label's minimum width is zero, so a
## label that does not expand would vanish).
func _one_line(label: Label, trim := false) -> Label:
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if trim:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.clip_text = true
	return label


func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
