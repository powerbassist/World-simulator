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
##   - at text 130 the list leaves the detail its room on the Folder's page;
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

## The Folder's page beside its 300 px list in the full dock (measured, s3 frames): the list column
## must leave the detail this much at text 130.
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
	_check_the_offer_is_built_on_the_file(state, ns, loader)
	_check_the_picker_survives_a_rebuild()
	_check_text_130_leaves_the_detail_room(state, ns, loader)
	_check_the_choice_is_a_command(state, ns, loader)
	_check_a_second_choice_refuses(state, ns, loader)
	_check_the_other_surfaces_read_the_register(state, ns, loader)
	_check_a_conclusion_pushes_a_card(state, ns, loader)


func _folder():
	return _main._events_panel


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
	if not _main._windows.is_open("events") or _folder().selected() != "file:" + _card():
		_fail("the programme card's click did not open the Folder on its file (page '%s')" % _folder().selected())
	_main._windows.close("events")


## V5.1-0c. The offer exists only before the clock first runs in a term; the first play press
## while it stands opens the Folder on the programme file and keeps the clock down -- only until
## the Folder has SHOWN the offer: the next press, with the Folder closed again, runs.
func _check_play_does_not_forfeit_the_offer(state, ns, loader) -> void:
	ProgrammeFile.forget(_main)
	if not _main._clock.paused or not _main._paused_for_programme:
		_fail("the guard check needs the term-start hold up")
		return
	_main._toggle_pause_by_hand()
	if not _main._clock.paused:
		_fail("the first Space at an unchosen term start ran the clock -- the offer is forfeited by one keypress")
	if not _main._windows.is_open("events") or _folder().selected() != "file:" + _card():
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
	# Pass 1: the card closed with its X while the hold stands. The first Space still reaches the offer
	# (its file put back), so the second can run -- the clock is never stuck behind a card gone.
	ProgrammeFile.forget(_main)
	_main._hud.inbox.dismiss(_card())
	_main._toggle_pause_by_hand()
	if not _main._clock.paused or not _main._windows.is_open("events") or _folder().selected() != "file:" + _card() or _card() == "":
		_fail("with the programme card closed, Space did not open the offer on the Folder (page '%s')" % _folder().selected())
	_main._windows.close("events")
	_main._toggle_pause_by_hand()
	if _main._clock.paused:
		_fail("with the programme card closed, the second Space did not run the clock -- the hold is stuck")
	_main._enforce_term_start_programme()


func _open_file() -> void:
	ProgrammeFile.open(_main)
	_folder()._refresh()


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


## The fix drawn at the picture step: at text 130 the blocs chip names one bloc and "+N", so the
## list column leaves the detail its room on the Folder's page.
func _check_text_130_leaves_the_detail_room(state, ns, loader) -> void:
	var before := UiTheme.text_scale()
	UiTheme.set_text_scale(1.3)
	var picker = _folder()._picker
	picker.fill(ns, Programme.available(state, ns, loader))
	var list_min: float = picker.list_min_width()
	if list_min > PAGE_WIDTH - 20.0 - DETAIL_ROOM:
		_fail("at text 130 the programme list needs %.0f px of the %.0f px page -- the detail keeps less than %.0f" % [list_min, PAGE_WIDTH, DETAIL_ROOM])
	# The chip names one bloc and a count, never two names (a width check alone would pass a clipped pair).
	var plus := 0
	for node in _walk(picker._rows):
		if node is Label and String(node.tooltip_text).contains(", "):
			plus += 1
			if String(node.text).contains(", ") or not String(node.text).contains("+"):
				_fail("at text 130 a row's blocs chip reads '%s', not one bloc and a count" % node.text)
	if plus == 0:
		_fail("premise: no offered entry is welcomed by two blocs or more")
	UiTheme.set_text_scale(before)
	picker.fill(ns, Programme.available(state, ns, loader))


## The command path: Choose on the file, main performs Programme.choose(), the clock resumes, the
## card is taken back, and the page shows what was booked -- with its way to the programme lane.
func _check_the_choice_is_a_command(state, ns, loader) -> void:
	var terms: Dictionary = _deadline_entry(state, ns, loader)
	if terms.is_empty():
		_fail("no offered entry carries a deadline -- the fixture needs one")
		return
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
	if Pending.window_ids(state, loader).has("events") and not Programme.available(state, ns, loader).is_empty():
		_fail("pending.gd still marks the offer after the term's programme is chosen")
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
	if not campaign_text.contains(String(terms["name"])) or not campaign_text.contains("%"):
		_fail("the campaign panel's promises section does not read the chosen programme: %s" % campaign_text)


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
