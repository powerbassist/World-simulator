extends SceneTree

## Headless test: godot --headless --script res://tests/test_presidency_page.gd
## Non-zero exit on any failure.
##
## Rework 2, slice 1 (presidency-page-brief.md, direction A, the author's "A, le
## mandat"): ONE Presidency page replaces the Overview and the Outliner. What it pins,
## each of which fails silently on screen:
##
## 1. One ranking: the lead's rows are the month's STORED lines, the same ones the
##    chief's mark in the title bar names -- never a second ranking that can disagree.
## 2. Every lead row has its own Go, and a Go opens that line's target.
## 3. The term reads the player's vote clock (Campaign's), the POLLED approval and
##    the programme register, one lane per entry, each lane a door.
## 4. "Open now" is the outliner's register (outliner_readings.gd) less the programme
##    pins the term already draws, six rows at most, each opening its window.
## 5. The counts are the desk and the requests, each a door.
## 6. The decisions fold is closed at rest and opens on a click.
## 7. The Outliner retired: no "outliner" window, O opens the page (one key a window), the Presidency
##    domain holds the page and Dispatches.
##
## Driven a frame at a time via extends SceneTree (a Control outside the tree has
## not run _ready()).

const PollNoise = preload("res://src/ui/poll_noise.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")
const Trends = preload("res://src/ui/trends.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Programme = preload("res://src/sim/programme.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const OutlinerReadings = preload("res://src/ui/outliner_readings.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const TermReads = preload("res://src/ui/term_reads.gd")
const Domains = preload("res://src/ui/domains.gd")
const TermLane = preload("res://src/ui/term_lane.gd")
const Strings = preload("res://src/ui/strings.gd")
const Government = preload("res://src/sim/government.gd")
const Defence = preload("res://src/sim/defence.gd")
const Society = preload("res://src/sim/society.gd")
const SocietyK = preload("res://src/sim/society_constants.gd")
const Num = preload("res://src/ui/num.gd")

const DAYS_PER_MONTH := 31
## The re-declared ceilings (card G; the parent accepted 170 / 60, 2026-11-16): the
## whole page and, inside it, the chief's read.
const PAGE_WORDS := 170
const LEAD_WORDS := 60

var _failures: Array[String] = []
var _main
var _page
var _frame := 0
var _orphans_before := -1


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	if _leak_frame > 0:
		# Two frames on: the rebuilt rows' queue_free has run; what is left orphaned leaked.
		if _orphans_before >= 0 and _frame >= _leak_frame + 2:
			_check_no_leak()
			_finish()
		return false
	_page = _main._overview_panel
	if _page == null or String(_page.get_script().resource_path) != "res://src/ui/presidency_page.gd":
		_fail("main's overview window is not the Presidency page")
		_finish()
		return false

	_check_the_outliner_retired()
	_check_the_lane_geometry()
	_draw()
	_check_the_fresh_term()
	_check_the_programme_lanes()
	_advance_months(2)
	_check_one_ranking()
	_check_the_counts()
	_check_open_now()
	_check_the_fold()
	_check_approval_is_polled()
	_check_the_government_reads()
	_check_the_words()
	_check_go()
	_start_leak_check()
	return false


func _check_the_outliner_retired() -> void:
	if _main._windows.panel_ids().has("outliner"):
		_fail("an 'outliner' window is still registered")
	var src := FileAccess.get_file_as_string("res://src/ui/main.gd")
	if src.contains("_windows.register(\"outliner\""):
		_fail("main.gd still registers the outliner")
	if not src.contains("_windows.register(\"overview\", tr(\"Overview\"), _overview_panel, KEY_O"):
		_fail("O does not open the Presidency page")
	var tabs: Array = []
	for row in Domains.TABLE:
		if String(row["id"]) == "presidency":
			tabs = row["tabs"]
	if tabs != ["overview", "events"]:
		_fail("the Presidency domain holds %s, expected the page and Dispatches" % [tabs])


## Day 1: no history, no programme, the vote 16 months off. The page says so and pads nothing.
func _check_the_fresh_term() -> void:
	var ns = _main._state.player()
	var expected: int = Campaign.months_to_election(_main._state, ns)
	var head: String = _text(_page._term_head)
	if not head.contains(str(expected)):
		_fail("the term's heading does not count %d months to the vote: %s" % [expected, head])
	var past: Array = TermReads.past(_main._state)
	if past.size() > 1:
		_fail("a fresh game has %d months of history, so this check proves nothing" % past.size())
	if not _text(_page._approval_lane).contains(tr("Fills in as the months pass.")):
		_fail("the approval lane on day 1 does not say it fills in: %s" % _text(_page._approval_lane))
	if not _text(_page._lead_box).contains(tr("The chief reports at the month's end.")):
		_fail("before the first month end the lead does not say when the chief reports: %s" % _text(_page._lead_box))
	if Programme.this_term(ns).is_empty() and not _text(_page._term_box).contains(tr("To choose")):
		_fail("with no programme chosen the term does not say one is to choose: %s" % _text(_page._term_box))


## One lane per entry of this term's programme, naming it, with its own door; the
## past half reads the figure the entry is judged on, the future half its window.
func _check_the_programme_lanes() -> void:
	var state = _main._state
	var ns = state.player()
	var offer: Array = Programme.available(state, ns, _main._loader)
	if offer.is_empty():
		_fail("no programme entry is on offer at the start, so the lanes cannot be checked")
		return
	var entry_id := String(offer[0]["id"])
	var result: Dictionary = Programme.choose(state, ns, entry_id, _main._loader)
	if not bool(result.get("applied", false)):
		_fail("could not choose '%s': %s" % [entry_id, result])
		return
	_draw()
	var lanes: Array = TermReads.goal_lanes(state, _main._loader)
	if lanes.size() != Programme.this_term(ns).size():
		_fail("TermReads gives %d lanes for %d entries" % [lanes.size(), Programme.this_term(ns).size()])
	if _page._goal_doors.size() != lanes.size():
		_fail("the page draws %d programme lanes for %d entries" % [_page._goal_doors.size(), lanes.size()])
		return
	var terms: Dictionary = Programme.terms_of(_main._loader, entry_id)
	if not _text(_page._term_box).contains(_page.Strings.row("programme", entry_id, "name", String(terms["name"]))):
		_fail("the programme lane does not name the entry: %s" % _text(_page._term_box))
	var lane: Dictionary = lanes[0]
	var timeout := int(terms.get("timeout_months", 0))
	var ahead: int = Trends.months_to_vote(state, ns)
	var due_expected := ahead if timeout <= 0 else mini(timeout, ahead)
	if int(lane["due"]) != due_expected:
		_fail("the lane's deadline is %d months ahead, expected %d (timeout %d)" % [lane["due"], due_expected, timeout])
	if timeout <= 0 and String(lane["due_text"]) != Strings.t("judged at the vote"):
		_fail("a goal without a clock says '%s' at its deadline, not 'judged at the vote'" % lane["due_text"])
	elif timeout > 0 and String(lane["due_text"]).is_empty():
		_fail("a goal with a clock names no deadline month")
	_check_the_goal_tip(lane)
	var asked: Array = []
	_page.window_requested.connect(func(id: String) -> void: asked.append(id))
	(_page._goal_doors[0] as Button).pressed.emit()
	if asked.size() != 1 or String(asked[0]) == "":
		_fail("a programme lane's door asked for %s" % [asked])


## The lead is the chief's read: the month's stored lines, in order, and its first row
## is what the mark in the title bar says.
func _check_one_ranking() -> void:
	var game: Dictionary = BriefingDriver._games.get(_main.get_instance_id(), {})
	var lines: Array = game.get("lines", [])
	_draw()
	if _page._lead_rows.size() != lines.size():
		_fail("the lead draws %d rows, the month has %d lines" % [_page._lead_rows.size(), lines.size()])
		return
	if lines.is_empty():
		if not _text(_page._lead_box).contains(tr("Nothing presses this month.")):
			_fail("a quiet month's lead does not say so: %s" % _text(_page._lead_box))
		return
	var mark: String = _main._hud.title_bar.chief_mark.title_text()
	if not _text(_page._lead_rows[0]).contains(mark):
		_fail("the lead's first row '%s' is not the mark's '%s'" % [_text(_page._lead_rows[0]), mark])
	for row in _page._lead_rows:
		if _buttons(row).size() != 1:
			_fail("a lead row carries %d buttons, expected one Go" % _buttons(row).size())


func _check_the_counts() -> void:
	var ns = _main._state.player()
	var files: Button = _page._count_doors["files"]
	var requests: Button = _page._count_doors["requests"]
	if not files.text.begins_with(str(ns.event_queue.size())):
		_fail("the files door reads '%s', the desk holds %d" % [files.text, ns.event_queue.size()])
	if not requests.text.begins_with(str(Audiences.waiting_count(ns))):
		_fail("the requests door reads '%s', %d wait" % [requests.text, Audiences.waiting_count(ns)])
	var asked: Array = []
	var cb := func(id: String) -> void: asked.append(id)
	_page.window_requested.connect(cb)
	files.pressed.emit()
	_page.window_requested.disconnect(cb)
	if asked != ["events"]:
		_fail("the files door asked for %s, expected Dispatches" % [asked])
	var heard := [0]
	var heard_cb := func() -> void: heard[0] += 1
	_page.requests_requested.connect(heard_cb)
	asked.clear()
	_page.window_requested.connect(cb)
	requests.pressed.emit()
	_page.window_requested.disconnect(cb)
	_page.requests_requested.disconnect(heard_cb)
	if heard[0] != 1 or not asked.is_empty():
		_fail("the requests door asked %d times and opened %s; expected the inbox's requests once" % [heard[0], asked])
	# A click on a wants row's words opens Opinion, as its chevron does.
	var words: Label = _page._wants_box.get_child(0).get_child(0) if _page._wants_box.get_child_count() > 0 else null
	if words != null:
		asked.clear()
		_page.window_requested.connect(cb)
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		words.gui_input.emit(press)
		_page.window_requested.disconnect(cb)
		if asked != ["society"]:
			_fail("a click on a want's words asked for %s, expected Opinion" % [asked])
	var majority: Button = _page._majority_door
	asked.clear()
	_page.window_requested.connect(cb)
	majority.pressed.emit()
	_page.window_requested.disconnect(cb)
	if asked != ["majority"]:
		_fail("the majority lane asked for %s, expected the Majority tab" % [asked])


## The outliner's register, less the programme pins the term draws, capped, each a door.
func _check_open_now() -> void:
	var expected: Array = []
	for section in OutlinerReadings.SECTIONS:
		if section == "agenda":
			continue
		var r: Dictionary = OutlinerReadings.read(section, _main._state, _main._loader)
		if bool(r["visible"]):
			expected.append_array(r["rows"])
	var shown: Array = _page._open_rows
	if shown.size() != mini(expected.size(), _page.OPEN_ROWS):
		_fail("open now draws %d rows, the register has %d (cap %d)" % [shown.size(), expected.size(), _page.OPEN_ROWS])
		return
	for i in shown.size():
		var asked: Array = []
		var cb := func(id: String) -> void: asked.append(id)
		_page.window_requested.connect(cb)
		(shown[i] as Button).pressed.emit()
		_page.window_requested.disconnect(cb)
		if asked != [String(expected[i]["window"])]:
			_fail("open-now row %d asked for %s, expected '%s'" % [i, asked, expected[i]["window"]])


func _check_the_fold() -> void:
	if _page._decided_box.visible:
		_fail("the decisions fold is open at rest")
	_page._decided_toggle.pressed.emit()
	if not _page._decided_box.visible:
		_fail("the decisions fold does not open on a click")
	_page._decided_toggle.pressed.emit()


## Every read the Overview's Government column showed still renders on the page (the parent's
## ruling on S1, option (a)): the seats, the line a majority must clear, the censure, 49.3, and
## the state's reads -- the three silent-at-zero ones staged non-zero, then put back.
func _check_the_government_reads() -> void:
	var ns = _main._state.player()
	var key: String = SocietyK.QUALITY_KEYS[0]
	var quality: float = ns.service_quality[key]
	var corruption: float = ns.corruption
	var press: float = ns.press_freedom
	ns.service_quality[key] = float(ns.start_service_quality.get(key, 0.0)) - 0.2
	ns.corruption = 0.3
	ns.press_freedom = -0.4
	_draw()
	var text := _text(_page)
	var expected: Array = [
		"%d / %d" % [int(ns.coalition_seats), int(ns.assembly_seats)],
		str(Government.majority_seats(ns)),
		Strings.t("Military capability %s — a deployment costs %s%% of GDP.") % [
			Num.f(ns.military_capability, 2), Num.f(Defence.deployment_cost_pct_gdp(ns), 2)],
		Strings.t("%s delivery %s on baseline.") % [preload("res://src/sim/opinion_constants.gd").ISSUE_LABEL.get(key, key),
			Num.fs(Society.quality_deviation(ns, key), 2)],
		Strings.t("Administration delivers %.0f%% of funding.") % (Society.delivery_factor(ns) * 100.0),
		Strings.t("Press under state oversight (%s).") % Num.fs(ns.press_freedom, 2),
	]
	if ns.censure_rule != "none":
		var censure: Dictionary = Government.resolve_censure(ns, _main._loader.parties.get(ns.id, []), false)
		expected.append(str(int(censure["threshold"])))
	if ns.formation_method == "presidential_appointment":
		expected.append("49.3")
	if not Defence.allies(_main._state, ns.id).is_empty():
		expected.append(", ".join(Defence.allies(_main._state, ns.id)))
	for want in expected:
		if not text.contains(String(want)):
			_fail("the page no longer shows the Overview's government read '%s'" % want)
	ns.service_quality[key] = quality
	ns.corruption = corruption
	ns.press_freedom = press


## The approval figure is the poll, never the truth: months advance until the two round apart.
func _check_approval_is_polled() -> void:
	var ns = _main._state.player()
	for _i in range(24):
		if _rounded_polled() != int(round(ns.overall_approval_pct)):
			break
		_advance_months(1)
	if _rounded_polled() == int(round(ns.overall_approval_pct)):
		_fail("poll noise never separated the rounded approval in 24 months")
		return
	var figure: String = _page._approval_figure.text
	if not figure.begins_with(str(_rounded_polled())):
		_fail("the approval figure reads '%s', the poll says %d" % [figure, _rounded_polled()])


func _check_the_words() -> void:
	_draw()
	var page_words := _words(_text(_page))
	var lead_words := _words(_text(_page._lead_box))
	if page_words > PAGE_WORDS:
		_fail("the page shows %d words, over its ceiling %d" % [page_words, PAGE_WORDS])
	if lead_words > LEAD_WORDS:
		_fail("the chief's read shows %d words, over its ceiling %d" % [lead_words, LEAD_WORDS])


## A Go opens its line's target (the briefing's own Go table), the page does not open.
func _check_go() -> void:
	var game: Dictionary = BriefingDriver._games.get(_main.get_instance_id(), {})
	var lines: Array = game.get("lines", [])
	_draw()
	if lines.is_empty() or _page._lead_rows.is_empty():
		return
	# Each row's Go names its own index (the briefing's Go table is indexed by it).
	var last: int = _page._lead_rows.size() - 1
	var said: Array = []
	var spy := func(i: int) -> void: said.append(i)
	_page.go_requested.connect(spy)
	_buttons(_page._lead_rows[last])[0].pressed.emit()
	_page.go_requested.disconnect(spy)
	if said != [last]:
		_fail("row %d's Go asked for %s" % [last, said])
	BriefingDriver.close(_main)
	_draw()
	var file := String(preload("res://src/ui/folder_driver.gd").file_of(_main, lines[0]))
	var target := String(BriefingDriver.target_of(lines[0])["tab"])
	_buttons(_page._lead_rows[0])[0].pressed.emit()
	if file != "":
		# A desk file is answered in the month's folder (until G2): the Go shows that file, never nothing.
		var card = BriefingDriver.card_of(_main)
		if not card.visible or card.selected_file() != file:
			_fail("the first Go (a desk file) did not show its file '%s' in the folder" % file)
		BriefingDriver.close(_main)
	elif not _main._windows.is_open(target) and target != "overview":
		_fail("the first Go did not open '%s'" % target)


## The hinge: the past year ends at the seam (today), the future half ends at the vote.
func _check_the_lane_geometry() -> void:
	var lane := TermLane.new()
	root.add_child(lane)
	lane.setup(TermLane.Kind.GOAL, 12, 40, {})
	lane.size = Vector2(400.0, 40.0)
	if not is_equal_approx(lane.past_x(11), lane.seam_x()) or not is_equal_approx(lane.seam_x(), 400.0 * TermLane.SEAM) 			or not is_equal_approx(lane.past_x(0), TermLane.LEFT * preload("res://src/ui/ui_theme.gd").text_scale()):
		_fail("today is not at the seam: past_x(11) %s, seam %s" % [lane.past_x(11), lane.seam_x()])
	if not is_equal_approx(lane.future_x(40), 400.0 - TermLane.PAD) or not is_equal_approx(lane.future_x(0), lane.seam_x()):
		_fail("the future half does not run from the seam to the vote: %s .. %s" % [lane.future_x(0), lane.future_x(40)])
	lane.queue_free()


## Pass 1 (#401): every refresh rebuilds the lanes; nothing it replaces may stay orphaned.
var _leak_frame := 0


func _start_leak_check() -> void:
	_draw()
	_leak_frame = _frame
	await process_frame
	await process_frame
	_orphans_before = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for _i in 3:
		_page.mark_dirty()
		_page._process(0.0)
	_leak_frame = _frame


func _check_no_leak() -> void:
	var after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	if after > _orphans_before:
		_fail("three refreshes left %d orphan nodes behind (%d -> %d)" % [after - _orphans_before, _orphans_before, after])


## The goal lane's figures are on the page as words, the chart kit's table rule: now, the goal, the clock.
func _check_the_goal_tip(lane: Dictionary) -> void:
	var tip := String(lane.get("tip", ""))
	if not tip.contains(Num.f(float(lane["goal"]), 2)):
		_fail("the goal lane's words do not name its goal %s: '%s'" % [Num.f(float(lane["goal"]), 2), tip])
	var door: Button = _page._goal_doors[0]
	var gutter: Control = door.get_parent().get_child(0)
	if gutter.tooltip_text != tip:
		_fail("the goal lane's gutter does not carry its now / goal / clock words")


# --- helpers ----------------------------------------------------------------

func _draw() -> void:
	_main._windows.open("overview")
	_page.mark_dirty()
	_page._process(0.0)


func _advance_months(months: int) -> void:
	var clock: Node = _main.get_node("Clock")
	for _d in range(DAYS_PER_MONTH * months):
		clock.advance_one_day()
	_main._windows.close_all()
	_draw()


func _rounded_polled() -> int:
	return int(round(PollNoise.displayed(PollNoise.poll_id(_main._state.year, _main._state.month),
		PollingPanel.HEADLINE_KEY, _main._state.player().overall_approval_pct)))


func _buttons(node: Node) -> Array:
	var out: Array = []
	for child in node.find_children("*", "Button", true, false):
		if not child.is_queued_for_deletion():
			out.append(child)
	return out


func _words(text: String) -> int:
	var n := 0
	for w in text.split(" ", false):
		for part in w.split("\n", false):
			if part.strip_edges() != "":
				n += 1
	return n


## Visible text only, skipping nodes queued for deletion and hidden branches.
func _text(node) -> String:
	if node == null or node.is_queued_for_deletion():
		return ""
	if node is CanvasItem and not node.visible:
		return ""
	var out := ""
	if node is Label:
		out += node.text + "\n"
	elif node is Button:
		out += node.text + "\n"
	elif node is RichTextLabel:
		out += node.get_parsed_text() + "\n"
	for child in node.get_children():
		out += _text(child)
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_presidency_page: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
