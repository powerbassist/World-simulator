extends SceneTree

## Headless test: godot --headless --script res://tests/test_programme_file.gd
## Non-zero exit on any failure.
##
## The term's programme as the Folder's first file -- rework 2 S3 (the parent's pick B: the
## programme picker is the file page's body; the Agenda tab retired, the Diary stays alone). It was
## test_agenda_panel.gd (V4.1); the checks that read the term-start hold, the command path and the
## other surfaces are kept, the Agenda's own (its register, its mid-term line) left with the tab.
## Loads the actual main scene and drives it a frame at a time -- a Control outside the scene tree
## has not run _ready() (docs/engine-decision.md's gotcha).
##
## The assertions are the ones that can fail silently:
##
##   - the TERM-START PAUSE fires, and the pending mark names the Folder;
##   - the first Space opens the Folder ON THE PROGRAMME FILE, once (V5.1-0c's guard);
##   - the Agenda tab is gone and nothing opens it: the card's click and the Go land on the Folder;
##   - the offer is BUILT FROM THE REGISTER on the file page: one row per entry, one Choose;
##   - the picker SURVIVES the Folder's rebuild (the same node: its selection and its scroll);
##   - the list leaves the detail its room on the Folder's page;
##   - CHOOSE is a COMMAND: main performs, the clock runs, and the page then shows what was booked;
##   - a conclusion pushes a card.
##
## The entry ids are read off the loader -- an id literal here would be the hand-written list
## tests/test_programme.gd's scanner hunts. Fixtures pick an entry by PROPERTY, never by name.

const Programme = preload("res://src/sim/programme.gd")
const Pending = preload("res://src/ui/pending.gd")
const Strings = preload("res://src/ui/strings.gd")
const Domains = preload("res://src/ui/domains.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const ProgrammeFile = preload("res://src/ui/programme_file.gd")
const ProgrammePicker = preload("res://src/ui/programme_picker.gd")
const ProgrammeDistance = preload("res://src/ui/programme_distance.gd")
const OutlinerReadings = preload("res://src/ui/outliner_readings.gd")
const StripChildren = preload("res://src/ui/strip_children.gd")
const TermReads = preload("res://src/ui/term_reads.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")
const Num = preload("res://src/ui/num.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")

## The Folder's page beside its 300 px list in the full dock (measured, s3 frames): the list column
## must leave the detail this much.
const PAGE_WIDTH := 846.0
const DETAIL_ROOM := 300.0

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the scene's _ready() run
	_run()
	_finish()
	return false


func _run() -> void:
	if _main._state == null:
		_fail("main scene did not build a GameState")
		return
	var state = _main._state
	var ns = state.player()
	var loader = _main._loader
	_check_the_term_start_pause_fires(state, ns, loader)
	_check_the_agenda_tab_is_gone()
	_check_play_does_not_forfeit_the_offer(state, ns, loader)
	_check_an_empty_offer_releases_the_hold(state, ns, loader)
	_check_opening_the_file_leaves_the_clock(state, ns, loader)
	_check_the_offer_is_built_on_the_file(state, ns, loader)
	_check_the_picker_survives_a_rebuild()
	_check_focus_survives_a_rebuild()
	_check_the_fill_refreshes_its_detail(state, ns, loader)
	_check_the_list_leaves_the_detail_room(state, ns, loader)
	_check_past_terms_are_on_the_file(state, ns, loader)
	_check_the_choice_is_a_command(state, ns, loader)
	_check_the_booked_page_reads_its_term(state, ns, loader)
	_check_a_second_choice_refuses(state, ns, loader)
	_check_the_distance_words()
	_check_the_other_surfaces_read_the_register(state, ns, loader)
	_check_the_polled_lane_starts_from_a_poll(state, ns, loader)
	_check_a_conclusion_pushes_a_card(state, ns, loader)
	_check_mid_term_says_when_the_next_programme_opens(state, ns, loader)
	_check_a_reload_forgets_the_guard()


func _folder():
	return _main._events_panel


func _forget() -> void:
	ProgrammeFile._seen.erase(_main.get_instance_id())


func _card() -> String:
	return String(_main._programme_card_id)


## The modal, at the arrival-pause precedent: the clock does not run past an unchosen term start,
## the card is on the desk, and the pending mark names the window that answers it -- the Folder.
func _check_the_term_start_pause_fires(state, ns, loader) -> void:
	if not Programme.is_term_start(ns):
		_fail("a new game is not a term start -- this check needs the fresh state to mean anything")
		return
	if not _main._clock.paused:
		_fail("the clock runs at an unchosen term start -- the choice must be surfaced before time moves")
	if _card().is_empty():
		_fail("no programme card was pushed at the unchosen term start")
	var marks: Array = Pending.window_ids(state, loader)
	if not marks.has("events") or marks.has("agenda"):
		_fail("pending.gd marks %s at an unchosen term start, not the Folder" % [marks])
	var body := ""
	for card in _main._hud.inbox.notes() + _files():
		if String(card["id"]) == _card():
			body = String(card["body"])
	if not body.contains(Strings.t("The Folder holds the offer.")):
		_fail("the programme card does not say the Folder holds the offer: '%s'" % body)


func _files() -> Array:
	return preload("res://src/ui/inbox_files.gd").list(_main._hud.inbox)


## S3: the Agenda domain keeps the Diary alone, no window answers to "agenda", and the card's click
## opens the Folder on the programme file.
func _check_the_agenda_tab_is_gone() -> void:
	if _main._windows.frame("agenda") != null:
		_fail("a window is still registered under the id 'agenda'")
	if Domains.tabs("agenda", _main._windows.panel_ids()) != ["calendar"]:
		_fail("the Agenda domain holds %s, not the Diary alone" % [Domains.tabs("agenda", _main._windows.panel_ids())])
	_main._windows.close("events")
	_main._hud.inbox.card_activated.emit(_card())
	if not _main._windows.is_open("events") or _folder().selected() != ProgrammeFile.KEY:
		_fail("the programme card's click did not open the Folder on its file (page '%s')" % _folder().selected())
	# The card is not the file: one item for the offer in To answer, never the card beside it.
	_folder()._refresh()
	var listed: Array = _folder().groups()[_folder().ANSWER]
	if not listed.has(ProgrammeFile.KEY) or listed.has("file:" + _card()):
		_fail("To answer lists %s: the programme file once, not its card" % [listed])
	_main._windows.close("events")


## V5.1-0c. The offer exists only before the clock first runs in a term; the first play press
## while it stands opens the Folder on the programme file and keeps the clock down -- only until
## the Folder has SHOWN the offer: the next press, with the Folder closed again, runs.
func _check_play_does_not_forfeit_the_offer(state, ns, loader) -> void:
	_forget()
	if not _main._clock.paused or not _main._paused_for_programme:
		_fail("the guard check needs the term-start hold up")
		return
	_main._toggle_pause_by_hand()
	if not _main._clock.paused:
		_fail("the first Space at an unchosen term start ran the clock -- the offer is forfeited by one keypress")
	if not _main._windows.is_open("events") or _folder().selected() != ProgrammeFile.KEY:
		_fail("the first Space did not open the Folder on the programme file (page '%s')" % _folder().selected())
	if Programme.available(state, ns, loader).is_empty():
		_fail("the offer vanished without the clock moving")
	_main._windows.close("events")
	_main._toggle_pause_by_hand()
	if _main._clock.paused:
		_fail("the second Space, with the Folder closed again, did not run the clock -- the guard nags on every press")
	if _main._windows.is_open("events"):
		_fail("the second Space reopened the Folder")
	# The clock has not ticked: the offer stands and the enforcement re-raises the hold and the card.
	_main._enforce_term_start_programme()
	if not _main._clock.paused or not _main._paused_for_programme:
		_fail("re-enforcing an unchosen term start did not restore the hold")
	# Pass 2 T2: the card closed with its X while the hold stands. The file follows the offer, not the
	# card: it stays in To answer, the first Space reaches it, the second runs.
	_forget()
	_main._hud.inbox.dismiss(_card())
	_folder()._refresh()
	if not _folder().groups()[_folder().ANSWER].has(ProgrammeFile.KEY):
		_fail("with the programme card closed, the offer left To answer while it stands")
	_main._toggle_pause_by_hand()
	if not _main._clock.paused or not _main._windows.is_open("events") or _folder().selected() != ProgrammeFile.KEY:
		_fail("with the programme card closed, Space did not open the offer on the Folder (page '%s')" % _folder().selected())
	_main._windows.close("events")
	_main._toggle_pause_by_hand()
	if _main._clock.paused:
		_fail("with the programme card closed, the second Space did not run the clock -- the hold is stuck")
	_main._enforce_term_start_programme()


func _open_file() -> void:
	ProgrammeFile.open(_main)
	_folder()._refresh()


## T13: the hold with nothing left to choose and no card (the offer emptied under it): Space runs the
## clock rather than opening a page that cannot show the offer.
func _check_an_empty_offer_releases_the_hold(state, ns, loader) -> void:
	_forget()
	var was := int(ns.programme_chosen_term)
	ns.programme_chosen_term = int(ns.terms_served)  # the offer is empty
	_main._drop_programme_card()
	_main._paused_for_programme = true
	_main._clock.paused = true
	_main._toggle_pause_by_hand()
	if _main._clock.paused:
		_fail("an empty offer with the hold up: Space did not run the clock")
	ns.programme_chosen_term = was
	_main._enforce_term_start_programme()


## T6 (G2): opening the file is navigation -- the clock stays as the player has it.
func _check_opening_the_file_leaves_the_clock(state, ns, loader) -> void:
	_main._clock.paused = false
	ProgrammeFile.open(_main)
	if _main._clock.paused:
		_fail("opening the programme file paused a running clock")
	_main._windows.close("events")
	_main._enforce_term_start_programme()


## One row per offered entry and one Choose, under the file's own lead; the page's fold answer is
## Choose while the offer stands.
func _check_the_offer_is_built_on_the_file(state, ns, loader) -> void:
	var offered: int = Programme.available(state, ns, loader).size()
	if offered == 0:
		_fail("nothing is offerable at a fresh term start -- the sweep test guarantees a live book")
		return
	_open_file()
	var page: Control = _folder()._page
	var rows := 0
	var buttons := 0
	for node in _walk(page):
		if node is Button and node.has_meta("entry") and node.is_visible_in_tree():
			rows += 1
		if node is Button and String(node.text) == Strings.t("Choose") and node.is_visible_in_tree():
			buttons += 1
	if rows != offered:
		_fail("the file page drew %d rows against %d offered entries -- filtering or inventing" % [rows, offered])
	if buttons != 1:
		_fail("the file page drew %d Choose buttons; the selected entry's detail carries one" % buttons)
	if not _text(page).contains(Strings.t("The term's programme")):
		_fail("the programme file's page lost its title")
	# T5 (d): the intro keeps its dotted term.
	if not _walk(page).any(func(n): return n is RichTextLabel and n.is_visible_in_tree() and String(n.text).contains("Delivery is judged")):
		_fail("the programme file's page lost the intro with its [g=programme] term")
	var picker = _folder()._picker
	var last: Button = _walk(page).filter(func(n): return n is Button and n.has_meta("entry")).back()
	last.pressed.emit()
	var summary := Strings.row_summary("programme", Programme.terms_of(loader, String(last.get_meta("entry"))))
	var opening := " ".join(summary.split(" ").slice(0, 4))
	if not _walk(picker._detail).any(func(n): return n is RichTextLabel and String(n.text).contains(opening)):
		_fail("selecting an entry does not show its text whole in the detail")
	var action = _folder().primary_action()
	if not (action is Button) or String(action.text) != Strings.t("Choose"):
		_fail("primary_action() on the programme file is not Choose")


## The Folder clears its page on every build; the picker is kept, so its selection (and its list's
## scroll, a property of the same node) outlive a day tick or a command.
func _check_the_picker_survives_a_rebuild() -> void:
	var picker = _folder()._picker
	var chosen: String = picker.selected_id()
	_folder().mark_dirty()
	_folder()._refresh()
	if _folder()._picker != picker or not is_instance_valid(picker) or picker.is_queued_for_deletion():
		_fail("the Folder's rebuild replaced the picker -- its selection and scroll are lost")
	elif picker.selected_id() != chosen:
		_fail("the Folder's rebuild moved the selection from %s to %s" % [chosen, picker.selected_id()])
	if not picker.is_visible_in_tree():
		_fail("the picker is hidden on its own file after a rebuild")
	# Another page hides it; the programme file shows it again with the same selection.
	if not _main._hud.inbox.notes().is_empty():
		_folder().select("note:" + String(_main._hud.inbox.notes()[0]["id"]))
		if picker.visible:
			_fail("the picker stayed up on another page")
		var action = _folder().primary_action()
		if action != null and picker.is_ancestor_of(action):
			_fail("on another page the Folder's primary action is a hidden programme row")
	_open_file()
	if picker.selected_id() != chosen:
		_fail("coming back to the programme file lost the selection")


## T9: a rebuild (each day tick at month 0) keeps focus on the picker row that has it -- the row is the
## same node -- rather than pulling the keyboard back to the list.
func _check_focus_survives_a_rebuild() -> void:
	_open_file()
	var row: Button = _walk(_folder()._picker._rows).filter(func(n): return n is Button and n.has_meta("entry"))[1]
	row.grab_focus()
	if _folder().get_viewport().gui_get_focus_owner() != row:
		_fail("premise: the picker row did not take the focus")
	_folder().mark_dirty()
	_folder()._refresh()
	if _folder().get_viewport().gui_get_focus_owner() != row:
		_fail("a rebuild moved the focus off the picker row that held it (now %s)" % _folder().get_viewport().gui_get_focus_owner())


## T11 + T12: an equal fill redraws the detail (its read moves with the state), and a fill that empties
## the list drops the Choose it freed.
func _check_the_fill_refreshes_its_detail(state, ns, loader) -> void:
	var picker = _folder()._picker
	var offer: Array = Programme.available(state, ns, loader)
	picker.fill(ns, offer)
	picker.select(String(offer[0]["id"]))
	var terms: Dictionary = offer[0]
	var field := String(terms["current_value"])
	var was: float = float(ns.get(field))
	ns.set(field, was + 3.0)
	picker.fill(ns, offer)
	if not _text(picker._detail).contains(ProgrammePicker.read_text(ns, terms)):
		_fail("an equal fill left the detail's read stale")
	ns.set(field, was)
	picker.fill(ns, [])
	var primary = picker.primary()
	if primary != null and (not is_instance_valid(primary) or primary.is_queued_for_deletion()):
		_fail("a fill that emptied the list left primary() on a freed Choose")
	picker.fill(ns, offer)


## The fix drawn at the picture step: at the largest text size the list column leaves the detail its
## room on the Folder's page. (At 130 % the blocs chip named one bloc and "+N"; 115 % and 130 % are
## gone.)
func _check_the_list_leaves_the_detail_room(state, ns, loader) -> void:
	var picker = _folder()._picker
	picker.fill(ns, Programme.available(state, ns, loader))
	var list_min: float = picker.list_min_width()
	if list_min > PAGE_WIDTH - 20.0 - DETAIL_ROOM:
		_fail("the programme list needs %.0f px of the %.0f px page -- the detail keeps less than %.0f" % [list_min, PAGE_WIDTH, DETAIL_ROOM])
	# QA on #433: the two bloc names the chip now carries are not cut to an ellipsis.
	var cut := []
	var measured := 0
	for node in _walk(picker._rows):
		if node is Label and node.is_visible_in_tree() and node.clip_text and node.text != "":
			node.clip_text = false
			node.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
			var need: float = node.get_minimum_size().x
			node.clip_text = true
			node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			if String(node.text).contains(","):
				measured += 1
			if need > node.size.x + 0.5 and String(node.text).contains(","):
				cut.append("%s (%.0f of %.0f px)" % [node.text, need, node.size.x])
	if measured == 0:
		_fail("premise: no two-bloc chip was measured")
	if not cut.is_empty():
		_fail("a bloc chip is cut: %s" % ", ".join(cut))
	picker.fill(ns, Programme.available(state, ns, loader))


## T5 (a): a past term's verdict on the programme file beside the offer, and in the Presidency
## programme lane's tooltip.
func _check_past_terms_are_on_the_file(state, ns, loader) -> void:
	var offer: Array = Programme.available(state, ns, loader)
	var terms: Dictionary = offer[0]
	ns.terms_served = 1
	ns.programme.append({"entry_id": String(terms["id"]), "status": "complete", "chosen_term": 0, "concluded_term": 0,
		"months_live": 4, "concluded_term_month": 4})
	var line := Strings.t("Delivered, term %d.") % 1
	_folder().mark_dirty()
	_open_file()
	if not _text(_folder()._page).contains(line):
		_fail("the programme file does not show the past term's verdict ('%s'): %s" % [line, _text(_folder()._page)])
	var overview = _main._overview_panel
	_main._windows.open("overview")
	overview.mark_dirty()
	overview._process(0.0)
	var tips := ""
	for n in _walk(overview._term_box):
		if n is Control:
			tips += String((n as Control).tooltip_text) + "\n"
	if not tips.contains(line):
		_fail("the Presidency programme lane's tooltip does not carry the past term's verdict")
	ns.programme.pop_back()
	ns.terms_served = 0
	_folder().mark_dirty()


## The command path: Choose on the file, main performs Programme.choose(), the clock resumes, the
## card is taken back, and the page shows what was booked -- with its way to the programme lane.
func _check_the_choice_is_a_command(state, ns, loader) -> void:
	var terms: Dictionary = _deadline_entry(state, ns, loader)
	if terms.is_empty():
		_fail("no offered entry carries a deadline -- the fixture needs one")
		return
	# T1: an event's page seen first on the Folder; the programme file chosen after must not follow it.
	var ev = _main._loader.events[0]
	var Ev = preload("res://src/sim/events.gd")
	Ev.announce(ns, ev, int(state.year) * 12 + int(state.month), Ev.region_names(ns, _main._loader))
	_folder().select("desk:" + String(ev.id))
	_open_file()
	_folder()._picker.select(String(terms["id"]))
	var choose: Button = _folder().primary_action()
	if choose == null:
		_fail("no Choose on the programme file")
		return
	choose.pressed.emit()
	if ns.programme.size() != 1:
		_fail("the choice did not land on the register exactly once (%d entries)" % ns.programme.size())
	elif String(ns.programme[0]["entry_id"]) != String(terms["id"]):
		_fail("Choose booked %s, not the selected %s" % [ns.programme[0]["entry_id"], terms["id"]])
	if _main._clock.paused:
		_fail("the clock is still paused after the choice -- the choice must resume it")
	if not _card().is_empty():
		_fail("the programme card was not dismissed by the choice")
	var named := false
	for node in _walk(_main._hud.inbox):
		if node is Label and String(node.text).contains(String(terms["name"]).to_upper()):
			named = true
	if not named:
		_fail("no card names the chosen programme -- an entry opened silently")
	# The page stays on the matter: what was booked, the clock running again, and the lane's door.
	_folder()._refresh()
	var text := _text(_folder()._page)
	if text.contains(Strings.t("Answered.")):
		_fail("after Choose the programme file reads 'Answered.' rather than what was booked")
	if not text.contains(Strings.row_name("programme", terms)):
		_fail("after Choose the page does not name the booked entry: '%s'" % text)
	if not text.contains(Strings.t("The clock runs again.")):
		_fail("after Choose the page does not say the clock runs again: '%s'" % text)
	if _folder().selected() != ProgrammeFile.KEY:
		_fail("after Choose the Folder followed another matter (page '%s'), not the booked programme" % _folder().selected())
	ns.event_queue.clear()
	if Pending.window_ids(state, loader).has("events"):
		_fail("pending.gd still marks the Folder after the term's programme is chosen (nothing else is on the desk)")
	if _folder()._picker.is_visible_in_tree():
		_fail("the picker is still up after the choice")
	var lane: Button = null
	for node in _walk(_folder()._page):
		if node is Button and String(node.text) == Strings.t("Open the programme lane"):
			lane = node
	if lane == null:
		_fail("after Choose the page has no way to the programme lane")
	else:
		lane.pressed.emit()
		if not _main._windows.is_open("overview"):
			_fail("'Open the programme lane' did not open the Presidency page")
	# With the file gone, every door to it lands on the Presidency page, where the lane is.
	_main._windows.close_all()
	ProgrammeFile.open(_main)
	if not _main._windows.is_open("overview"):
		_fail("opening the programme file after the choice did not land on the Presidency page")
	# A live goal's door opens its group's working tab: every tab named there is registered.
	for group in preload("res://src/ui/term_reads.gd").GROUP_TAB:
		var tab := String(preload("res://src/ui/term_reads.gd").GROUP_TAB[group])
		if _main._windows.frame(tab) == null:
			_fail("the %s group's goals open '%s', which no window is" % [group, tab])


## T8 + T10: the booked page reads the file's own term -- a later term does not blank it -- and prints the
## live clock (StripReadings' words); T1 is pinned in the choice check (an event seen before the file).
func _check_the_booked_page_reads_its_term(state, ns, loader) -> void:
	var entry: Dictionary = ns.programme[0]
	var terms: Dictionary = Programme.terms_of(loader, String(entry["entry_id"]))
	_main._windows.open("events")
	_folder()._refresh()
	if not _text(_folder()._page).contains(StripReadings.programme_clock_text(terms, entry)):
		_fail("the booked page does not print the live clock: %s" % _text(_folder()._page))
	# A later term, past its own start (so no new offer): the file still reads its own term's booking.
	ns.terms_served += 1
	ns.months_in_term = 3
	_folder().mark_dirty()
	_folder()._refresh()
	var later := _text(_folder()._page)
	if not later.contains(Strings.row_name("programme", terms)):
		_fail("a later term blanked the booked page of the term it was chosen in: %s" % later)
	ns.terms_served -= 1
	ns.months_in_term = 0
	_folder().mark_dirty()


## The gate is the sim's, and the UI answers the refusal with a card.
func _check_a_second_choice_refuses(state, ns, loader) -> void:
	var register_size: int = ns.programme.size()
	var direct: Dictionary = Programme.choose(state, ns, String(loader.programme[0]["id"]), loader)
	if not bool(direct.get("refused", false)):
		_fail("a second Programme.choose() in one term was not refused")
	var cards_before: int = _main._hud.inbox.card_count()
	_main._on_programme_chosen(String(loader.programme[0]["id"]))
	if ns.programme.size() != register_size:
		_fail("a refused second choice still reached the register")
	if _main._hud.inbox.card_count() != cards_before + 1:
		_fail("a refused choice did not answer with a card -- the verb went silent")


## The strip, the Presidency page and the Campaign read the same register.
func _check_the_other_surfaces_read_the_register(state, ns, loader) -> void:
	_main._update_top_bar()
	if not _main._top_bar.figure_box("programme").visible:
		_fail("the top bar's programme figure is hidden with a live programme on the register")
	var terms: Dictionary = Programme.terms_of(loader, String(ns.programme[0]["entry_id"]))
	var tip := ""
	for line in _main._top_bar._tips["programme"]:
		tip += String(line["text"]) + " "
	if not tip.contains(String(terms["name"])):
		_fail("the top-bar strip's programme tip does not name the chosen programme: '%s'" % tip)
	var overview = _main._overview_panel
	_main._windows.open("overview")
	overview.mark_dirty()
	overview._process(0.0)
	if overview._goal_doors.is_empty():
		_fail("the Presidency page's term drew no programme lane")
	elif not _text(overview._term_box).contains(String(terms["name"])):
		_fail("the Presidency page's programme lane does not name the entry")
	var campaign = _main._campaign_panel
	_main._windows.open("campaign")
	campaign.mark_dirty()
	campaign._process(0.0)
	var campaign_text := _text(campaign._body)
	if is_nan(ProgrammeDistance.start_of(ns, String(terms["id"]))):
		_fail("the chosen entry has no starting figure, so the surfaces below prove nothing")
	var want: String = ProgrammeDistance.of(ns, terms, float(Programme.progress_of(ns, terms)["current_value"]))
	if not campaign_text.contains(String(terms["name"])) or not campaign_text.contains(want):
		_fail("the campaign panel's promises section does not read '%s': %s" % [want, campaign_text])
	var surfaces := {
		"the strip's tip": tip,
		"the strip's list": str(StripChildren._programme(ns, loader)),
		"the file's read": ProgrammePicker.read_text(ns, terms),
	}
	if bool(terms.get("pinned", false)):
		surfaces["the outliner's row"] = str(OutlinerReadings._agenda(ns, loader))
	if String(terms["current_value"]) != TermReads.APPROVAL_FIELD:
		surfaces["the Presidency lane's words"] = String(TermReads.goal_lanes(state, loader)[0]["tip"])
	for name in surfaces:
		if not String(surfaces[name]).contains(want):
			_fail("%s does not read '%s': %s" % [name, want, surfaces[name]])


## The author's call A (blind play 11-28): the distance in the goal's own unit from the figure at the choice.
func _check_the_distance_words() -> void:
	var down := {"goal_value": 7.0, "progressbar": "down", "unit": "%"}
	var up := {"goal_value": 53.0, "progressbar": "up", "unit": "%"}
	var terms_count := {"goal_value": 1.0, "progressbar": "up", "unit": "terms"}
	var f := func(v: float) -> String: return Num.f(v, 2)
	var done := func(s: float, g: float, d: float, span: float) -> String:
		return "%s to %s: %s of %s done" % [f.call(s), f.call(g), f.call(d), f.call(span)]
	var cases := [
		["nothing moved", down, 7.4, 7.4, done.call(7.4, 7.0, 0.0, 0.4)],
		["part of the way", down, 7.4, 7.2, done.call(7.4, 7.0, 0.2, 0.4)],
		["past the goal", down, 7.4, 6.5, done.call(7.4, 7.0, 0.4, 0.4)],
		["the wrong way, down", down, 7.4, 7.77, done.call(7.4, 7.0, 0.0, 0.4) + ", now %s the wrong way" % f.call(0.37)],
		["under a rounding", down, 7.4, 7.4001, done.call(7.4, 7.0, 0.0, 0.4)],
		["part of the way up", up, 50.0, 51.0, done.call(50.0, 53.0, 1.0, 3.0)],
		["the wrong way, up", up, 50.0, 49.0, done.call(50.0, 53.0, 0.0, 3.0) + ", now %s the wrong way" % f.call(1.0)],
		["met at the start", down, 6.8, 7.1, "now %s · goal %s" % [f.call(7.1), f.call(7.0)]],
		["met within a rounding", down, 7.003, 7.003, "now %s · goal %s" % [f.call(7.0), f.call(7.0)]],
		["no start kept", down, NAN, 7.4, "now %s · goal %s" % [f.call(7.4), f.call(7.0)]],
		["terms are counted whole", terms_count, 0.0, 0.0, "0 to 1: 0 of 1 done"],
	]
	for case in cases:
		var said: String = ProgrammeDistance.words(case[1], case[2], case[3])
		if said != String(case[4]):
			_fail("%s: '%s', expected '%s'" % [case[0], said, case[4]])


## The Presidency lane prints approval as the poll the player was shown, so it starts from that month's poll too.
func _check_the_polled_lane_starts_from_a_poll(state, ns, loader) -> void:
	var terms := {}
	for e in loader.programme:
		if String(e["current_value"]) == TermReads.APPROVAL_FIELD and String(e["progressbar"]) == "up":
			terms = e
			break
	var kept: Array = ns.programme
	var start := float(terms["goal_value"]) - 10.0
	ns.programme = [{"entry_id": String(terms["id"]), "chosen_term": int(ns.terms_served), "months_live": 3,
		"status": "active", "concluded_term": -1, "concluded_term_month": -1, "start": start}]
	var polled: float = PollNoise.displayed(PollNoise.poll_id(state.year, state.month) - 3, PollingPanel.HEADLINE_KEY, start)
	var tip := String(TermReads.goal_lanes(state, loader)[0]["tip"])
	if not tip.contains("%s to " % Num.f(polled, 2)):
		_fail("the polled lane does not start from the choosing month's poll %s: '%s'" % [Num.f(polled, 2), tip])
	ns.programme = kept


## A conclusion is news: a card, and the strip stands down with nothing live.
func _check_a_conclusion_pushes_a_card(state, ns, loader) -> void:
	var terms: Dictionary = Programme.terms_of(loader, String(ns.programme[0]["entry_id"]))
	var beyond: float = float(terms["goal_value"]) + (10.0 if String(terms["progressbar"]) == "up" else -10.0)
	ns.set(String(terms["current_value"]), beyond)
	Programme.tick_month(state, loader)
	if String(ns.programme[0]["status"]) != "complete":
		_fail("the fixture did not conclude complete -- the write missed the trigger")
	var cards_before: int = _main._hud.inbox.card_count()
	_main._card_programme_conclusions()
	if _main._hud.inbox.card_count() != cards_before + 1:
		_fail("a concluded entry pushed %d cards, expected exactly one" % (_main._hud.inbox.card_count() - cards_before))
	_main._update_top_bar()
	if _main._top_bar.figure_box("programme").visible:
		_fail("the top bar still shows a programme with nothing live on the register")
	# T10: the booked page reads the verdict once the entry concluded.
	_main._windows.open("events")
	_folder().select(ProgrammeFile.KEY)
	if not _text(_folder()._page).contains(Strings.t("Delivered")):
		_fail("the booked page does not read the delivered verdict: %s" % _text(_folder()._page))


## T5 (b, c): mid-term with nothing chosen, the Presidency page's programme lane says when the next
## programme opens and has a door to the campaign.
func _check_mid_term_says_when_the_next_programme_opens(state, ns, loader) -> void:
	var saved: Array = ns.programme.duplicate(true)
	var saved_term := int(ns.programme_chosen_term)
	ns.programme = []
	ns.programme_chosen_term = -1
	ns.months_in_term = 7
	var overview = _main._overview_panel
	_main._windows.open("overview")
	overview.mark_dirty()
	overview._process(0.0)
	var text := ""
	for n in _walk(overview._term_box):
		if n.get("_data") is Dictionary:
			text += String(n.get("_data").get("text", "")) + "
"
	if not text.to_lower().contains("next term"):
		_fail("the mid-term programme lane does not say when the next term starts: %s" % text)
	var asked: Array = []
	var cb := func(id: String) -> void: asked.append(id)
	overview.window_requested.connect(cb)
	for n in _walk(overview._term_box):
		if n is Button and String(n.tooltip_text) == Strings.t("Open") and not (n as Button).disabled:
			n.pressed.emit()
	overview.window_requested.disconnect(cb)
	if not asked.has("campaign"):
		_fail("the mid-term programme lane has no door to the campaign (doors asked %s)" % [asked])
	ns.programme = saved
	ns.programme_chosen_term = saved_term
	ns.months_in_term = 0


## T14: a reload forgets the guard's memory of the old main (GameReload.forget_main, MAIN_KEYED_STATICS).
func _check_a_reload_forgets_the_guard() -> void:
	ProgrammeFile.open(_main)
	_folder()._refresh()
	var id: int = _main.get_instance_id()
	ProgrammeFile._seen[id] = 0
	preload("res://src/ui/game_reload.gd").forget_main(_main)
	if ProgrammeFile._seen.has(id):
		_fail("GameReload.forget_main left the programme guard's memory of the old main")


func _deadline_entry(state, ns, loader) -> Dictionary:
	for terms in Programme.available(state, ns, loader):
		if int(terms.get("timeout_months", 0)) > 0:
			return terms
	return {}


func _text(node: Node) -> String:
	var out := ""
	for n in _walk(node):
		if (n is Label or n is RichTextLabel or n is Button) and (n as Control).is_visible_in_tree():
			out += String(n.text) + "\n"
	return out


## The walk skips queue_free'd nodes: a refresh retires the previous generation with queue_free,
## which stays walkable until the frame ends.
func _walk(node) -> Array:
	var out: Array = [node]
	if node.is_queued_for_deletion():
		return out
	for child in node.get_children():
		out.append_array(_walk(child))
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_programme_file: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	quit(1)
