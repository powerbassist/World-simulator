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
## (3) below: a second window taking Q must be refused, and says so.
## expects-error: window 'probe' takes key Q, which 'overview' already has
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
const PresidencyRows = preload("res://src/ui/presidency_rows.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const ChiefMarkView = preload("res://src/ui/chief_mark_view.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const Priorities = preload("res://src/ui/priorities.gd")
const Staff = preload("res://src/sim/staff.gd")
const SLOT := "__test_presidency_page__"

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
	_check_majority_tones()
	_check_nothing_moved_one_line()
	_draw()
	_check_the_fresh_term()
	_check_every_lane_keeps_its_door_space()
	_check_the_vote_is_named()
	_check_no_dead_requests_door()
	_check_the_programme_lanes()
	_check_concluded_goals()
	_check_approval_goal_is_polled()
	_advance_months(2)
	_check_one_ranking()
	_check_the_chiefs_line_is_the_spoken_one()
	_check_the_counts()
	_check_open_now()
	_check_the_fold()
	_check_approval_is_polled()
	_check_the_government_reads()
	_check_the_words()
	_check_go()
	_check_also_due_and_the_effects()
	_check_one_build_per_command()
	# After the word ceilings: these run months on, past the state the ceilings are read at.
	_check_concluded_chosen_mark()
	_check_the_spoken_line_month()
	_check_a_clashing_key_is_refused()
	_check_open_now_clicks_and_redraws()
	_check_the_line_survives_a_load()
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
	# T10 (#401 pass 2): Q, the Outliner's key, opens the page too (plan S1).
	if _main._windows.id_for_key(KEY_Q) != "overview":
		_fail("Q opens '%s', not the Presidency page" % _main._windows.id_for_key(KEY_Q))
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
	var head: String = _page._term_head.text
	var vote := Trends.vote_date(ns)
	var said := tr("Past year · %s until the presidential vote, %s") if bool(ns.has_executive) else tr("Past year · %s until the assembly vote, %s")
	var want := said % [Trends.months_text(expected), preload("res://src/ui/date_text.gd").month_year(vote.y, vote.x)]
	if head != want:
		_fail("the term's heading reads '%s', expected '%s' (%d months to the vote)" % [head, want, expected])
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
	var cb := func(id: String) -> void: asked.append(id)
	_page.window_requested.connect(cb)
	(_page._goal_doors[0] as Button).pressed.emit()
	_page.window_requested.disconnect(cb)
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
	if shown.size() != expected.size():
		_fail("open now draws %d rows, the register has %d (each section capped by its own +N more)" % [shown.size(), expected.size()])
		return
	for section in OutlinerReadings.SECTIONS:
		var r: Dictionary = OutlinerReadings.read(section, _main._state, _main._loader)
		if section != "agenda" and bool(r["visible"]) and not _text(_page._open_box).contains(String(r["title"])):
			_fail("open now drops the section title '%s'" % r["title"])
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
	_draw()
	var file := BriefingDriver.file_of(_main, lines[0])
	var target := String(BriefingDriver.target_of(lines[0])["tab"])
	_buttons(_page._lead_rows[0])[0].pressed.emit()
	if file != "":
		# G2: a desk file is answered on the Folder tab, the Go shows that file there, never nothing.
		_main._events_panel._refresh()
		if not _main._windows.is_open("events") or _main._events_panel.selected() != "file:" + file:
			_fail("the first Go (a desk file) did not show its file '%s' on the Folder" % file)
	elif not _main._windows.is_open(target) and target != "overview":
		_fail("the first Go did not open '%s'" % target)
	_main._windows.open("overview")


## #401 pass 2, RECORD 11: a command sweeps every panel and queues the chief's re-rank for the frame's
## end. The page builds ONCE, on the re-ranked read: a build in the sweep's frame drew the lead the command
## had just made stale, then built again when the read landed.
func _check_one_build_per_command() -> void:
	_draw()
	var before: int = _page.builds
	var game: Dictionary = BriefingDriver._games.get(_main.get_instance_id(), {})
	var stale := [Priorities._standing("budget", "balance"), Priorities._standing("budget", "balance")]
	game["lines"] = stale  # what the command made stale; the re-rank replaces it
	ChiefMarkView.refresh(_main)  # the page holds that read when the command lands
	_main._windows.mark_all_dirty()  # a command's sweep: dirtied queues the re-rank
	_page._process(0.0)  # the sweep's own frame
	if _page._read.get("lines", []) == stale:
		_fail("the page built on the read the command made stale, before the chief's re-rank")
	_flush_rerank()  # the frame's end
	_page._process(0.0)
	if _page.builds != before + 1:
		_fail("one command built the page %d times, not once" % (_page.builds - before))


## The plate's two other jobs, carried by the page (G2): an item in its last month the lines crowded
## out is shown under the lead with its Go (the parent's rule on #217), and the month's booked effects
## open part 5 (the plate's "What your choices did").
func _check_also_due_and_the_effects() -> void:
	var game: Dictionary = BriefingDriver._games.get(_main.get_instance_id(), {})
	var saved_also: Array = game.get("also", [])
	var saved_report: Dictionary = game.get("report", {})
	game["also"] = [{"kind": "commitment", "subject": "x|y|meter:balance", "deadline_month": 0, "standing": false,
		"held": false, "go": {"tab": "calendar"}}]
	game["report"] = {"history_entry": {}}
	ChiefMarkView.refresh(_main)
	_draw()
	var lead := _text(_page._lead_box)
	if not lead.contains("Also due this month:"):
		_fail("an item the lines crowded out is not under the lead ('Also due this month:' missing)")
	var said: Array = []
	var spy := func(i: int) -> void: said.append(i)
	_page.go_requested.connect(spy)
	for b in _buttons(_page._lead_box):
		if not _page._lead_rows.any(func(row): return row.is_ancestor_of(b)) and b != _page._count_doors["files"] \
				and b != _page._count_doors["requests"]:
			b.pressed.emit()
	_page.go_requested.disconnect(spy)
	if said != [(game.get("lines", []) as Array).size()]:
		_fail("the footer's Go did not ask for its item's index past the lines: %s" % [said])
	game["also"] = saved_also
	game["report"] = saved_report
	ChiefMarkView.refresh(_main)
	if not FileAccess.get_file_as_string("res://src/ui/chief_mark_view.gd").contains("BriefingEffects.lines("):
		_fail("the page's read no longer carries the month's booked effects (BriefingEffects.lines)")


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


## T2: a lane without a door keeps the door's space, so every plot is one width and the
## head's TODAY and VOTE sit over the seam and the diamond of the lanes below.
func _check_every_lane_keeps_its_door_space() -> void:
	for row in _term_box_rows():
		var door: Control = row.get_child(2)
		if not door.visible:
			_fail("a lane hides its door, so its plot is wider than the others")
			return


func _term_box_rows() -> Array:
	var out: Array = []
	for child in _page._term_box.get_children():
		if child is HBoxContainer and not child.is_queued_for_deletion():
			out.append(child)
	return out


## T4: the term's heading names which vote it counts to (Society counts the assembly's).
func _check_the_vote_is_named() -> void:
	var ns = _main._state.player()
	var which := tr("presidential") if bool(ns.has_executive) else tr("assembly")
	if not _text(_page._term_head).contains(which):
		_fail("the term's heading does not name the vote: %s" % _text(_page._term_head))


## T9: no count door that does nothing; a cut lead title keeps its full text as a tooltip.
func _check_no_dead_requests_door() -> void:
	var ns = _main._state.player()
	var requests: Button = _page._count_doors["requests"]
	if Audiences.waiting_count(ns) == 0 and not requests.disabled:
		_fail("'0 requests waiting' is a live button that opens nothing")


func _check_lead_tooltips() -> void:
	for row in _page._lead_rows:
		for child in row.get_children():
			if child is Label and child.size_flags_horizontal == Control.SIZE_EXPAND_FILL and child.tooltip_text != child.text:
				_fail("a lead title that can be cut has no full-text tooltip: '%s'" % child.text)


## T6: the censure result and 49.3 are two reads, each with its own tone.
func _check_majority_tones() -> void:
	var ns = _main._state.player()
	var parts: Array = PresidencyRows.majority(ns, _main._loader)
	var censure := ""
	var article := ""
	for part in parts:
		if String(part[0]).contains("49.3"):
			article = String(part[0])
			if String(part[0]).contains(Strings.t("A censure motion would fail: %d of %d.").substr(0, 10)):
				_fail("the censure and 49.3 share one line: '%s'" % part[0])
		elif String(part[0]).begins_with(Strings.t("A censure motion would fail: %d of %d.").substr(0, 10)):
			censure = String(part[0])
			if int(part[1]) != PanelKit.Tone.GOOD and int(part[1]) != PanelKit.Tone.BAD:
				_fail("the censure verdict carries no tone of its own")
	if ns.formation_method == "presidential_appointment" and (article == "" or censure == ""):
		_fail("the majority's censure and 49.3 are not two lines: %s" % [parts])


## T5: "nothing moved" sits on one line in its row, never wrapped one letter wide.
func _check_nothing_moved_one_line() -> void:
	var row: Control = PresidencyRows.effect_row({"label": "x", "month": 1, "year": 2026, "movements": []})
	root.add_child(row)
	for child in row.get_children():
		if child is Label and child.text == Strings.t("nothing moved") and child.autowrap_mode != TextServer.AUTOWRAP_OFF:
			_fail("'nothing moved' wraps inside its row")
	row.queue_free()


## T3: a concluded goal's chosen mark stays where it was chosen, and its bar is its verdict.
func _check_concluded_goals() -> void:
	var ns = _main._state.player()
	if ns.programme.is_empty():
		return
	var entry: Dictionary = ns.programme[0]
	var saved := entry.duplicate()
	entry["status"] = ProgrammeK.STATUS_FAIL
	entry["months_live"] = 1
	entry["concluded_term"] = int(ns.terms_served)
	entry["concluded_term_month"] = int(ns.months_in_term)
	var lanes: Array = TermReads.goal_lanes(_main._state, _main._loader)
	var before := int(lanes[0]["chosen"])
	ns.months_in_term = int(ns.months_in_term) + 1
	_main._state.history.append(_main._state.history[-1].duplicate() if not _main._state.history.is_empty() else {})
	lanes = TermReads.goal_lanes(_main._state, _main._loader)
	if before >= 0 and int(lanes[0]["chosen"]) > before:
		_fail("a concluded goal's chosen mark slid from %d to %d as the months passed" % [before, lanes[0]["chosen"]])
	_draw()
	for bar in _page._term_box.find_children("*", "ProgressBar", true, false):
		if bar.is_queued_for_deletion():
			continue
		if not is_zero_approx(float(bar.value)):
			_fail("a missed goal's bar shows %.2f, not empty" % float(bar.value))
	_main._state.history.pop_back()
	ns.months_in_term = int(ns.months_in_term) - 1
	ns.programme[0] = saved
	_draw()


## T8: an approval goal reads the polls in its bar and its words, never the true approval.
func _check_approval_goal_is_polled() -> void:
	var state = _main._state
	var ns = state.player()
	var entry_id := ""
	for e in _main._loader.programme:
		if String(e.get("current_value", "")) == TermReads.APPROVAL_FIELD:
			entry_id = String(e["id"])
			break
	if entry_id == "":
		_fail("no approval goal in the programme content to check")
		return
	ns.programme.append({"entry_id": entry_id, "chosen_term": int(ns.terms_served), "months_live": 0,
		"status": ProgrammeK.STATUS_ACTIVE, "concluded_term": -1, "concluded_term_month": -1})
	var lane: Dictionary = TermReads.goal_lanes(state, _main._loader)[-1]
	var polled := Num.f(TermReads.approval_now(state), 2)
	if not String(lane["tip"]).contains(polled):
		_fail("an approval goal's words read '%s', not the poll %s" % [lane["tip"], polled])
	ns.programme.pop_back()


## T7: the page shows the line the chief spoke at the month's end, and a re-rank does not change it.
func _check_the_chiefs_line_is_the_spoken_one() -> void:
	_draw()
	var said: String = _page._said.text
	ChiefMarkView.refresh(_main, true)
	_draw()
	if _page._said.text != said:
		_fail("a mid-month re-rank changed the chief's line on the page from '%s' to '%s'" % [said, _page._said.text])
	var game: Dictionary = BriefingDriver._games.get(_main.get_instance_id(), {})
	var key := "%d:%d" % [_main._state.get_instance_id(), int(_main._state.year) * 12 + int(_main._state.month)]
	var spoken := String(game.get("spoken_line", "")) if String(game.get("spoken_key", "")) == key else ""
	if spoken != said:
		_fail("the page's chief line '%s' is not the one he spoke this month '%s'" % [said, spoken])
	_check_lead_tooltips()


## QA (2) on #401: a goal concluded N months ago keeps the index it was chosen at, however
## many months pass (months_live stops at the conclusion).
func _check_concluded_chosen_mark() -> void:
	var state = _main._state
	var ns = state.player()
	if TermReads.past(state).size() < 8:
		_advance_months(8 - TermReads.past(state).size())
	var past: Array = TermReads.past(state)
	if ns.programme.is_empty() or past.size() < 8:
		_fail("the concluded-mark check needs a programme and 8 months of history (has %d)" % past.size())
		return
	var entry: Dictionary = ns.programme[0]
	var saved := entry.duplicate()
	entry["status"] = ProgrammeK.STATUS_COMPLETE
	entry["months_live"] = 2
	entry["concluded_term"] = int(ns.terms_served)
	entry["concluded_term_month"] = int(ns.months_in_term) - 3
	var chosen := int(TermReads.goal_lanes(state, _main._loader)[0]["chosen"])
	var want := past.size() - 1 - (2 + 3)
	if chosen != want:
		_fail("a goal chosen 5 months ago (2 live, concluded 3 ago) marks index %d, expected %d" % [chosen, want])
	ns.programme[0] = saved


## QA (1) on #401: a month end where the chief speaks puts that line on the page; in the
## next month, before its end, the page carries no line (he has not spoken in it).
func _check_the_spoken_line_month() -> void:
	var game: Dictionary = BriefingDriver._games.get(_main.get_instance_id(), {})
	game["said_in"] = "a situation he never spoke in"  # month_end's rule: a new situation speaks
	_advance_months(1)
	var spoken := String(game.get("spoken_line", ""))
	if spoken.is_empty():
		_fail("a month end that speaks stored no line for the page")
		return
	if _page._said.text != spoken:
		_fail("the page's chief line '%s' is not the one he spoke '%s'" % [_page._said.text, spoken])
	# The next month, before its end: same lines, no new speech.
	var month := int(_main._state.month)
	_main._state.month = month % 12 + 1
	ChiefMarkView.refresh(_main)
	_draw()
	if not _page._said.text.is_empty():
		_fail("the page still shows last month's line '%s' in a month he has not spoken in" % _page._said.text)
	_main._state.month = month
	ChiefMarkView.refresh(_main)


## QA (3) on #401: a second window taking a key already held, as its extra key, is refused.
func _check_a_clashing_key_is_refused() -> void:
	var probe := Control.new()
	_main._windows.register("probe", "probe", probe, KEY_NONE, "", [KEY_Q])
	if _main._windows.id_for_key(KEY_Q) != "overview":
		_fail("a second window took Q from the page: Q opens '%s'" % _main._windows.id_for_key(KEY_Q))


## The outliner's old checks, on its rows here: a release or a right click opens nothing,
## and a refresh after the state moves redraws (a firm gone leaves the list).
func _check_open_now_clicks_and_redraws() -> void:
	_draw()
	if _page._open_rows.is_empty():
		return
	var asked: Array = []
	var cb := func(id: String) -> void: asked.append(id)
	_page.window_requested.connect(cb)
	var words: Label = (_page._open_rows[0] as Button).get_parent().get_child(0)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	words.gui_input.emit(release)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	words.gui_input.emit(right)
	_page.window_requested.disconnect(cb)
	if not asked.is_empty():
		_fail("a release or a right click on an open-now row opened %s" % [asked])
	# A redraw after mark_dirty builds the rows again from the register (a frozen list would keep
	# showing a firm that is gone): the old row nodes leave the page.
	var old_row: Button = _page._open_rows[0]
	_page.mark_dirty()
	_page._process(0.0)
	if _page._open_rows.has(old_row) or not old_row.get_parent().get_parent() == null and not old_row.is_queued_for_deletion():
		_fail("open now did not rebuild its rows after mark_dirty")


## The parent's TAKE on #401 (QA's lead 2): saved at a month end and loaded, the lead carries
## the chief's line for the month's situation -- speak()'s line, with no voice -- not nothing
## until the next month end. Through main's real load (a rebuilt main, #396).
func _check_the_line_survives_a_load() -> void:
	var error := SaveManager.save_game(_main._state, _main._clock, SLOT)
	if error != "":
		_fail("could not save: %s" % error)
		return
	var next = _main._on_load_requested(SLOT)
	if next == null or next == _main:
		_fail("the load handed back no new main")
		return
	_main = next
	_page = _main._overview_panel
	_draw()
	var game: Dictionary = BriefingDriver._games.get(_main.get_instance_id(), {})
	var lines: Array = game.get("lines", [])
	var chief = Staff.chief_of(_main._loader, String(_main._state.player().id))
	var situation := Priorities.situation(lines)
	var want := String(BriefingDriver.chief_said(_main._loader, String(chief.id), situation, BriefingDriver._turn(_main, situation))["text"])
	if _page._said.text.is_empty():
		_fail("after a load the lead shows no line from the chief until the next month end")
	elif _page._said.text != want:
		_fail("after a load the lead says '%s', speak()'s line for '%s' is '%s'" % [_page._said.text, situation, want])
	for path in [SaveManager._path_for(SLOT), SaveManager._path_for(SLOT) + SaveManager.TEMP_SUFFIX]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# --- helpers ----------------------------------------------------------------

func _draw() -> void:
	_main._windows.open("overview")
	_flush_rerank()
	_page.mark_dirty()
	_page._process(0.0)


## The frame's end, where a queued re-rank runs (call_deferred): this test steps no frame between.
func _flush_rerank() -> void:
	if _main.has_meta(ChiefMarkView.RERANK_QUEUED):
		ChiefMarkView._rerank_queued(_main)


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
