extends SceneTree

## Headless test: godot --headless --script res://tests/test_election_panel.gd
## Non-zero exit on any failure.
##
## Loads the actual main scene and turns the actual clock, the same shape
## test_game_loop.gd uses, so a broken signal path between the clock, the
## election tick and the panel fails here rather than in a playtest. Driven a
## frame at a time because a Control outside the scene tree has not run
## _ready() — see docs/engine-decision.md. The geometry checks run two frames
## behind the text ones for the same reason one step on: sizes are settled only
## after the panel has laid out at its real width.
##
## France runs two clocks, so this drives past two panels. First the
## presidential election of May 2027, which is the one that can end the game.
## Then June 2029, when the legislative and European Parliament elections land
## in the same month — the double-election case is the one most likely to break
## a panel written for a single result.

const Music = preload("res://src/ui/music.gd")
const MomentCheck = preload("res://tests/moment_check.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Sting = preload("res://src/ui/sting.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const ElectionPanel = preload("res://src/ui/election_panel.gd")

const EXEC_MONTHS := 16       # January 2026 to May 2027, FRA's presidential term.
const TARGET_MONTHS := 41     # January 2026 to June 2029, the Assembly's term.
const GEOMETRY_LAG := 2       # frames between a panel opening and its sizes being read.

const EXEC_TEXT_FRAME := 2
const EXEC_GEOMETRY_FRAME := EXEC_TEXT_FRAME + GEOMETRY_LAG
const NATIONAL_GEOMETRY_FRAME := EXEC_GEOMETRY_FRAME + GEOMETRY_LAG
const DEFEATED_GEOMETRY_FRAME := NATIONAL_GEOMETRY_FRAME + GEOMETRY_LAG

var _failures: Array[String] = []
var _main
var _frame := 0
var _done := false

## suite-exclusive: backs up and restores user://settings.cfg -- the sting
## checks write the Sound setting, and exclusivity is what keeps this file off
## the parallel pool while test_menu.gd mutates the same file. The runner's
## regex reads this line's exact shape; a reworded tag silently re-parallelises
## the test (the V3.6 review's blocker).
var _had_settings := false
var _settings_backup := ""


func _init() -> void:
	# V5.3-0: this test drives months for another surface, not the monthly briefing.
	preload("res://src/ui/briefing_driver.gd").suppressed = true
	_backup_settings()
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _done or _frame < EXEC_TEXT_FRAME:
		return false  # let the scene's _ready() run, or let quit() land
	if _frame == EXEC_TEXT_FRAME:
		_run_exec_text()
	elif _frame == EXEC_GEOMETRY_FRAME:
		# One frame does both: the laid-out executive table is read, then the
		# panel is dismissed and the clock driven on — the double-election
		# panel gets its own GEOMETRY_LAG frames before its geometry is read.
		_check_exec_geometry()
		_check_modal_blocks_the_world()
		_run_national_text()
	elif _frame == NATIONAL_GEOMETRY_FRAME:
		_check_told_once()
		_check_night_settled()
		_check_national_geometry()
		_check_sting_gate()
		_run_defeated_text()
	elif _frame == DEFEATED_GEOMETRY_FRAME:
		_check_defeated_geometry()
		_finish()
	return false


## user://settings.cfg does not outlive this run changed: the sting checks
## wrote it, so the player's real file (or its absence) goes back at the end.
func _backup_settings() -> void:
	_had_settings = FileAccess.file_exists(SettingsPanel.CONFIG_PATH)
	if _had_settings:
		_settings_backup = FileAccess.get_file_as_string(SettingsPanel.CONFIG_PATH)
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	cfg.set_value("audio", "enabled", true)
	cfg.save(SettingsPanel.CONFIG_PATH)


func _restore_settings() -> void:
	if _had_settings:
		var f := FileAccess.open(SettingsPanel.CONFIG_PATH, FileAccess.WRITE)
		f.store_string(_settings_backup)
	else:
		DirAccess.remove_absolute(SettingsPanel.CONFIG_PATH)


func _run_exec_text() -> void:
	if _main._state == null:
		_fail("main scene did not build a GameState")
		_finish()
		return

	var clock: Node = _main.get_node("Clock")
	var ns = _main._state.player()

	_advance(clock, EXEC_MONTHS)

	# The presidential election must have paused the clock and opened the panel.
	if not clock.paused:
		_fail("the clock did not pause for the presidential election (clock at %d-%d)" % [clock.year, clock.month])
		_finish()
		return
	var exec_text := _collect_text(_main._election_panel)
	if not exec_text.contains("Presidential election"):
		_fail("the May 2027 panel is not labelled a presidential election: %s" % exec_text)
	if not ns.in_government:
		_fail("the incumbent lost the 2027 presidential election, so the rest of this test cannot run")
		_finish()
		return
	if not exec_text.contains("RE-ELECTED"):
		_fail("won the presidency but the panel does not say so: %s" % exec_text)

	# A presidential result allocates no seats (elections.gd leaves "seats"
	# empty there), so the table must not carry a seats column at all.
	if exec_text.contains("seats"):
		_fail("the executive table carries a seats column although the office allocates none: %s" % exec_text)

	# V2.9 task 7: the verdict owns the screen. The attribution ("What decided
	# it") reads BEFORE the table -- the playtest buried the one line that says
	# why under the numbers -- and the plate is a result screen, not a side
	# panel. Case-insensitive: PanelKit prints the lines as written.
	var lower := exec_text.to_lower()
	if lower.find("what decided it") > lower.find("vote share"):
		_fail("the attribution reads below the party table; the verdict must lead")

	# V3.6: the one told thing the agency work earned. The verdict's own
	# attribution carries the bound in the game's voice; on a double-election
	# panel it must appear ONCE, on the verdict, not on every section.
	var told_count := exec_text.count(ElectionPanel.TOLD_LINE)
	if told_count < 1:
		_fail("the verdict attribution is missing the told line: %s" % ElectionPanel.TOLD_LINE)

	# The plate grew to hold a verdict and a table: 640 was the budget panel's
	# size, and the seat bars need the width.
	if _main._election_panel.custom_minimum_size.x < 860:
		_fail("the election plate is %.0f wide; a result screen needs the room" % _main._election_panel.custom_minimum_size.x)

	# The panel stays open: the geometry pass GEOMETRY_LAG frames from now reads
	# it at its laid-out width before dismissing it.


func _check_exec_geometry() -> void:
	var scroll := _find_scroll(_main._election_panel)
	if scroll == null:
		_fail("the election panel has no ScrollContainer")
	elif scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		# The playtest's collapsed table: with scrolling on, the ScrollContainer
		# lays _sections out at the child's own minimum width instead of the
		# plate's — the one content panel without what every sibling sets.
		_fail("horizontal scroll is not disabled on the election panel's scroll")
	var table: Control = _main._election_panel._sections.get_child(0)
	if table.size.x <= 500.0:
		_fail("the executive results table does not fill the plate width (got %.0f)" % table.size.x)
	var grid := _find_grid(_main._election_panel)
	if grid == null:
		_fail("the executive panel renders no results grid")
	else:
		print("PROBE exec: panel.x=%.0f scroll.x=%.0f sections.x=%.0f table.x=%.0f grid.x=%.0f grid.right=%.0f" % [
			_main._election_panel.size.x, scroll.size.x, _main._election_panel._sections.size.x,
			table.size.x, grid.size.x, grid.position.x + grid.size.x])
		if grid.columns != 2:
			_fail("the executive table is not party + vote share only (grid has %d columns)" % grid.columns)
	if not _find_bars(_main._election_panel).is_empty():
		_fail("the executive table renders seat bars although the office allocates no seats")


func _run_national_text() -> void:
	# Dismiss it the way the Continue button does, and run on to June 2029.
	var clock: Node = _main.get_node("Clock")
	_main._election_panel.hide()
	clock.paused = false
	_advance(clock, TARGET_MONTHS - EXEC_MONTHS)

	var ns = _main._state.player()

	if ns.last_election.is_empty():
		_fail("no legislative election had resolved by month %d (clock at %d-%d)" % [TARGET_MONTHS, clock.year, clock.month])
		_finish()
		return
	if ns.last_ep_election.is_empty():
		_fail("no EP election had resolved alongside the national one (clock at %d-%d)" % [clock.year, clock.month])

	if not clock.paused:
		_fail("the clock did not pause when the election panel opened")
	if _main._election_panel == null or not _main._election_panel.visible:
		_fail("the election panel is not visible after a legislative election")
		_finish()
		return

	var text := _collect_text(_main._election_panel)

	if not text.contains("%d" % ns.last_election["incumbent_seats"]):
		_fail("panel text does not mention the incumbent's seat count (%d): %s" % [ns.last_election["incumbent_seats"], text])

	var vote_pct := "%.1f%%" % (float(ns.last_election["incumbent_vote_share"]) * 100.0)
	if not text.contains(vote_pct):
		_fail("panel text does not mention the incumbent's vote share (%s): %s" % [vote_pct, text])

	if not text.contains("European Parliament"):
		_fail("panel text does not mention the European Parliament result: %s" % text)

	var attribution: Array = ns.last_election["attribution"]
	if attribution.is_empty():
		_fail("national result carries no attribution")
	else:
		var issue_label: String = OpinionK.ISSUE_LABEL[attribution[0]["issue"]]
		if not text.contains(issue_label):
			_fail("panel text does not name the top issue '%s': %s" % [issue_label, text])

	# A legislative election cannot end a presidency, so this panel must name the
	# government that came out of it and must always offer Continue.
	var pm_name: String = _main._loader.person_name(ns.pm_person_id)
	if not text.contains(pm_name):
		_fail("panel text does not name the head of government ('%s'): %s" % [pm_name, text])

	var has_continue := false
	for child in _main._election_panel._footer.get_children():
		if child is Button and child.text == "Continue":
			has_continue = true
	if ns.in_government and not has_continue:
		_fail("won the election but the panel offers no Continue button")
	if not ns.in_government and has_continue:
		_fail("lost the election but the panel still offers Continue")

	_check_sting_wiring()


## V3.6: on the double-election panel the told line rides the verdict's
## attribution alone -- a sentence printed under every table would be
## wallpaper. Counted here rather than in _run_national_text(): that frame is
## the one show_results ran in, and the previous panel's sections are
## queue_free()d but not yet reaped, so a text read there sees the ghost's
## copy too (the fold finding: a same-frame read answers for the last frame).
## Playtest 2026-09-16 finding B2: the defeat sentences used to be added to
## _footer, an ALIGNMENT_END HBox, where an autowrapping Label with no
## horizontal expand collapses to a ~one-character column -- a vertical stack of
## letters. Both variants (plain defeat, term limit) must sit in _sections like
## the termed-out notice already did, with the footer holding only the button.
## The live ladder never reaches a defeat (France wins both elections above), so
## the verdicts are staged directly through show_results(), the same frame-driven
## pattern the checks above use. State the defeat reads is set and restored
## around the staging; the panel never writes GameState.
func _run_defeated_text() -> void:
	var panel = _main._election_panel
	var ns = _main._state.player()
	var was_gov: bool = ns.in_government

	ns.in_government = false
	panel.show_results([_fake_result("executive")])
	_check_defeat_placement("You have lost your office. This term is over.")
	ns.in_government = was_gov

	panel.show_results([_fake_result("termed_out")])
	_check_termed_out_single_sentence()


## The termed-out verdict carries its own long paragraph; the review's P1 was
## the generic defeat line duplicating it (invisible only while the footer bug
## crushed one copy to a column). Pinned: exactly the long sentence, and
## neither short defeat line anywhere on the plate.
func _check_termed_out_single_sentence() -> void:
	var panel = _main._election_panel
	var long_form := 0
	for node in _descendants(panel._sections):
		# show_results() queue_frees the previous staging's children; same-frame
		# reads still see the ghost's copy (the fold finding, a third place).
		if node is Label and not node.is_queued_for_deletion():
			if "the most the constitution allows" in node.text:
				long_form += 1
			if "You have lost your office" in node.text or "You have served the maximum" in node.text:
				_fail("the termed-out verdict prints a second defeat line: '%s'" % node.text)
	if long_form != 1:
		_fail("the termed-out paragraph appears %d times, expected exactly 1" % long_form)
	var has_button := false
	for node in panel._footer.get_children():
		if node is Label:
			_fail("a defeat sentence sits in _footer, the HBox that collapses autowrap")
		if node is Button and node.text == "Leave office":
			has_button = true
	if not has_button:
		_fail("the termed-out modal footer offers no Leave office button")


## A minimal verdict in the shape Elections.resolve() hands show_results(): no
## seats (an executive office allocates none) and no attribution, because the
## checks here are about the defeat sentence and the footer, not the table.
func _fake_result(kind: String) -> Dictionary:
	var ns = _main._state.player()
	return {
		"kind": kind,
		"incumbent_largest": false,
		"incumbent_party_id": ns.incumbent_party_id,
		"incumbent_vote_share": 0.41,
		"largest_party_id": ns.incumbent_party_id,
		"seats": {},
		"vote_share": {ns.incumbent_party_id: 0.41},
		"seats_total": 0,
		"attribution": [],
		"termed_out": kind == "termed_out",
		"snap": false,
	}


func _check_defeat_placement(sentence: String) -> void:
	var panel = _main._election_panel
	var in_sections := false
	for node in _descendants(panel._sections):
		if node is Label and node.text == sentence:
			in_sections = true
	if not in_sections:
		_fail("the defeat sentence '%s' is not in _sections" % sentence)
	var has_button := false
	for node in panel._footer.get_children():
		if node is Label:
			_fail("a defeat sentence sits in _footer, the HBox that collapses autowrap")
		if node is Button and node.text == "Leave office":
			has_button = true
	if not has_button:
		_fail("the defeated modal footer offers no Leave office button")


## The geometry half of B2, read GEOMETRY_LAG frames after the panel was built
## (the fold lesson: a Label's minimum-size cache lags one invalidation). A
## healthy sentence is one plate-width line or two -- a one-character column of
## this sentence is dozens of lines tall and a few px wide.
func _check_defeated_geometry() -> void:
	var panel = _main._election_panel
	# The termed-out staging ran last, so the specimen is its long paragraph --
	# a longer string than the generic line and a harsher test of the wrap.
	var label := _find_label(panel._sections, "the most the constitution allows")
	if label == null:
		_fail("the defeat sentence label vanished before the geometry read")
		return
	var line_h: float = label.get_theme_font("font").get_height(label.get_theme_font_size("font_size"))
	var min_size := label.get_combined_minimum_size()
	print("PROBE defeat: label.x=%.0f min.y=%.0f line_h=%.1f (%.1f lines)" % [
		label.size.x, min_size.y, line_h, min_size.y / line_h])
	if label.size.x <= 200.0:
		_fail("the defeat sentence lays out at %.0f px wide; it must span the plate" % label.size.x)
	if min_size.y > line_h * 5.0:
		_fail("the defeat sentence lays out %.1f lines tall; the one-character column is back" % (min_size.y / line_h))


## Substring match: the geometry specimens are named by a stable fragment of
## authored copy rather than a full sentence built from loader names.
func _find_label(node, text: String) -> Label:
	for child in node.get_children():
		if child is Label and text in child.text:
			return child
		var found := _find_label(child, text)
		if found != null:
			return found
	return null


func _check_told_once() -> void:
	var text := _collect_text(_main._election_panel)
	if text.count(ElectionPanel.TOLD_LINE) != 1:
		_fail("the told line appears %d times on the double-election panel, expected once" % text.count(ElectionPanel.TOLD_LINE))


## V3.6: show_results() wired the sting. Counted on the same frame the panel
## opened -- a finished player frees itself when the 1.4 s stream ends, which
## no frame gap here can reach, so the count is the wiring's word, not a race.
func _check_sting_wiring() -> void:
	var players := _count_sting_players()
	if players < 1:
		_fail("sound is on but show_results() placed no sting player on the plate")


## V3.6: the sting itself. The synth must be a pure function of the sample
## index (two builds byte-identical, exact length), and the Sound setting must
## gate Sting.play() with no player left behind when it is Off. The gate is
## driven directly and synchronously: one frame, so no finished-player reaping
## can touch the counts.
func _check_sting_gate() -> void:
	var a := Sting._synth()
	var b := Sting._synth()
	if a != b:
		_fail("the sting synth is not deterministic")
	if a.size() != 123480:  # 2 bytes x 44100 Hz x 1.4 s, 16-bit mono
		_fail("sting buffer is %d bytes, expected 123480" % a.size())

	var panel = _main._election_panel
	var before := _count_sting_players()
	_set_sound(false)
	Sting.play(panel)
	if _count_sting_players() != before:
		_fail("sound is off but Sting.play() placed a player anyway")
	_set_sound(true)
	Sting.play(panel)
	if _count_sting_players() != before + 1:
		_fail("sound is on but Sting.play() placed no player")
	# #223 QA D3: the reveal plays its verdict's own sting -- a defeat the losing
	# one, a win and a term limit the won one. WHICH sting, under no recorded file
	# (the synthesized toll), a fixture's and the shipped manifest (QA's TAKE on #228).
	var kept_verdict: Dictionary = panel._verdict
	var kept_revealed: bool = panel._revealed
	for manifest in [{}, MomentCheck.FIXTURE, null]:
		Music.override_manifest = manifest
		for c in [[{"defeated": true}, "election_lost"], [{"defeated": false}, "election_won"],
				[{"defeated": true, "termed_out": true}, "election_won"]]:
			panel._verdict = c[0]
			panel._revealed = false
			var players := _count_sting_players()
			panel._reveal()
			var last: Node = MomentCheck.last_player(panel)
			if _count_sting_players() != players + 1 or not MomentCheck.plays(last, c[1]):
				_fail("the reveal of %s did not play %s (manifest %s)" % [c[0], c[1], manifest])
	Music.override_manifest = null
	panel._verdict = kept_verdict
	panel._revealed = kept_revealed


func _count_sting_players() -> int:
	var n := 0
	for c in _main._election_panel.get_children():
		if c is AudioStreamPlayer:
			n += 1
	return n


func _set_sound(enabled: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	cfg.set_value("audio", "enabled", enabled)
	cfg.save(SettingsPanel.CONFIG_PATH)


## V2.9 task 7: the modal blocks the world behind it -- a full-rect dim with
## STOP filter sits beside the holder when the panel is visible, and follows
## its visibility, so the map cannot be played behind a verdict.
func _check_modal_blocks_the_world() -> void:
	# The dim is the holder's sibling, in the screen stack's scene layer since
	# V5.1-c2.1 (main's own children until then); the election's is the last
	# one BEFORE its own holder in tree order.
	var holder: Node = _main._election_panel.get_parent()
	var dim: ColorRect = null
	for child in holder.get_parent().get_children():
		if child == holder:
			break
		if child is ColorRect:
			dim = child
	if dim == null:
		_fail("the election modal has no dim backdrop")
		return
	if not dim.visible:
		_fail("the dim backdrop is hidden while the result is on screen")
	if dim.mouse_filter != Control.MOUSE_FILTER_STOP:
		_fail("the dim backdrop does not eat clicks")
	if dim.size.x < 900.0:
		_fail("the dim backdrop covers %.0fpx -- it must span the screen" % dim.size.x)


func _check_national_geometry() -> void:
	var scroll := _find_scroll(_main._election_panel)
	if scroll == null:
		_fail("the election panel has no ScrollContainer")
	elif scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_fail("horizontal scroll is not disabled on the election panel's scroll")
	var table: Control = _main._election_panel._sections.get_child(0)
	if table.size.x <= 500.0:
		_fail("the results table does not fill the plate width (got %.0f)" % table.size.x)

	# The national table keeps its seats column, and each party holding seats
	# gets a bar under the grid — the readout the playtest expected and the code
	# never had. The EP table on the same panel adds its own bars on top.
	var ns = _main._state.player()
	var grid := _find_grid(_main._election_panel)
	if grid == null:
		_fail("the results panel renders no results grid")
	elif grid.columns != 3:
		_fail("the national table lost its seats column (grid has %d columns)" % grid.columns)
	var bars := _find_bars(_main._election_panel)
	if bars.size() < ns.last_election["seats"].size():
		_fail("the national table renders fewer seat bars than parties with seats (%d bars, %d parties)" % [bars.size(), ns.last_election["seats"].size()])
	var heaviest := 0.0
	for bar in bars:
		heaviest = maxf(heaviest, bar.value)
	if heaviest <= 0.0:
		_fail("every seat bar reads zero")


## Advance whole months, stopping early if an election pauses the clock.
func _advance(clock: Node, months: int) -> void:
	# V2.9: a DECISION arriving also pauses the clock now -- that used to be the
	# election's alone, and this loop's early return is how an arrival stalled
	# the drive at March 2027 with an empty panel read as its result. The player
	# the loop pretends to be answers what lands on the desk and carries on; the
	# pause that ends the drive is the one no answer exists for (the election).
	# V4.1: an unchosen term start is the second answerable pause -- the driver
	# picks the first offer off the live list and answers it through the same
	# programme_chosen command path the Agenda's CHOOSE button uses, which is
	# what unpauses the clock. A fresh game starts paused behind exactly this.
	var Events := load("res://src/sim/events.gd")
	var Programme := load("res://src/sim/programme.gd")
	var ns = _main._state.player()
	for _month in range(months):
		for _d in range(31):
			clock.advance_one_day()
			if clock.paused:
				# THE VERDICT CHECK FIRST. V1.8's one pending slot made "an event
				# on the desk at the election month" rare enough that the events
				# branch could sit above this; the desk is a queue now, and a
				# drive that answered-and-unpaused over the visible result would
				# run the clock straight past the vote the reading frames own.
				if _main._election_panel.visible:
					# V5.1-d1b2 (G4): election day stops on the polls closing first;
					# the player the loop pretends to be presses its Continue, and
					# the count and verdict the reading frames own come up.
					if _collect_text(_main._election_panel).contains("POLLS CLOSED"):
						_main._election_panel._cont.pressed.emit()
					return
				if Events.is_pending(ns) and not Events.pending_event(ns, _main._loader).choices.is_empty():
					Events.choose(_main._state, _main._loader, String(Events.pending_event(ns, _main._loader).choices[0]["id"]))
					clock.paused = false
					continue
				# An answerable pause with no verdict on screen -- the offer.
				var offer: Array = Programme.available(_main._state, ns, _main._loader)
				if not offer.is_empty():
					_main._agenda_panel.programme_chosen.emit(String(offer[0]["id"]))
					continue
				return


func _collect_text(node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	elif node is RichTextLabel:  # a name is a person link since V5.1-d1b2
		out += node.get_parsed_text() + "\n"
	for child in node.get_children():
		out += _collect_text(child)
	return out


func _find_scroll(panel) -> ScrollContainer:
	for node in _descendants(panel):
		if node is ScrollContainer:
			return node
	return null


func _find_grid(panel) -> GridContainer:
	for node in _descendants(panel):
		if node is GridContainer:
			return node
	return null


func _find_bars(panel) -> Array:
	var out: Array = []
	for node in _descendants(panel):
		if node is ProgressBar:
			out.append(node)
	return out


func _descendants(node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_descendants(child))
	return out


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	_done = true
	_restore_settings()
	if _failures.is_empty():
		print("test_election_panel: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)


## V4.9b: the night as the real tick leaves it. Headless, motion is off, so
## the plate opens on the settled count -- the verdict titled, every seat bar
## full, the ticker done. The sequence itself (count, skip, dismissal, rebuild,
## wall-clock) is tests/test_election_night.gd's; what belongs here is that the
## main scene's own election lands on its finals with no motion to run it.
func _check_night_settled() -> void:
	var panel = _main._election_panel
	if panel._cells.is_empty():
		_fail("the national panel opened with no count cells (no tables built)")
		return
	if not panel._revealed or panel._title.text == ElectionPanel.NIGHT_TITLE:
		_fail("with motion off the plate opened mid-count ('%s')" % panel._title.text)
	var bars := 0
	for cell in panel._cells:
		if cell["bar"] == null:
			continue
		bars += 1
		# Tolerance, not equality: bar.value round-trips a 32-bit property while
		# `final_bar` is a 64-bit double.
		if float(cell["final_bar"]) < 0.0 or absf(float(cell["bar"].value) - float(cell["final_bar"])) > 0.005:
			_fail("a seat bar reads %.4f against final %.4f" % [cell["bar"].value, cell["final_bar"]])
	if bars == 0:
		_fail("the June 2029 plate built no seat bars")
	if not panel._ticker.text.begins_with("All "):
		_fail("the settled plate's ticker reads '%s'" % panel._ticker.text)
