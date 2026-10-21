extends SceneTree

## Headless test: godot --headless --script res://tests/test_agenda_panel.gd
## Non-zero exit on any failure.
##
## V4.1's surfaces. Loads the actual main scene and drives it a frame at a
## time -- a Control outside the scene tree has not run _ready(), so everything
## it builds is null (docs/engine-decision.md's gotcha;
## test_calendar_panel.gd's pattern).
##
## The assertions are the ones that can fail silently:
##
##   - the TERM-START PAUSE fires: a new game IS an unchosen term start, and
##     the clock must sit still behind the choice until a programme lands;
##   - the offer is BUILT FROM THE REGISTER -- one CHOOSE button per entry
##     Programme.available() hands over, no more, no fewer;
##   - the CHOOSE verb is a COMMAND: the panel emits, main performs, the clock
##     resumes, and the term cannot be answered twice;
##   - the progress bar reads the DERIVED pair -- move the live figure and the
##     bar moves, which a stored fraction structurally cannot do;
##   - a conclusion pushes a card.
##
## The entry ids are read off the loader here exactly as the panel reads them
## off Programme.available() -- an id literal in this file would be the same
## hand-written list tests/test_programme.gd's scanner hunts, one directory
## over. Every fixture below picks its entry by PROPERTY (a deadline, an
## unchosen term), never by name.

const Programme = preload("res://src/sim/programme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Pending = preload("res://src/ui/pending.gd")
const Trends = preload("res://src/ui/trends.gd")
const ClockCluster = preload("res://src/ui/clock_cluster.gd")

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
	var panel = _main._agenda_panel
	if panel == null:
		_fail("main scene did not build the agenda panel")
		return

	_check_the_term_start_pause_fires(state, ns, loader)
	_check_play_does_not_forfeit_the_offer(state, ns, loader)
	_check_the_offer_is_built_from_the_register(panel, state, ns, loader)
	_check_the_choice_is_a_command(panel, state, ns, loader)
	_check_a_second_choice_refuses(panel, state, ns, loader)
	_check_the_bar_reads_the_derived_pair(panel, state, ns, loader)
	_check_the_other_surfaces_read_the_register(panel, state, ns, loader)
	_check_a_conclusion_pushes_a_card(panel, state, ns, loader)
	_check_mid_term_says_when_the_next_programme_opens(panel, state, ns, loader)


## The modal, at the arrival-pause precedent: the clock does not run past an
## unchosen term start, the card is on the desk, and the pending mark names the
## window that answers it. Nothing is asserted about a window being open --
## main.gd deliberately surfaces this as a card over a clean map, the same
## non-modal call events-model makes for every unflagged arrival.
func _check_the_term_start_pause_fires(state, ns, loader) -> void:
	if not Programme.is_term_start(ns):
		_fail("a new game is not a term start -- this check needs the fresh state to mean anything")
		return
	if not _main._clock.paused:
		_fail("the clock runs at an unchosen term start -- the choice must be surfaced before time moves")
	if String(_main._programme_card_id).is_empty():
		_fail("no programme card was pushed at the unchosen term start")
	if not Pending.window_ids(state, loader).has("agenda"):
		_fail("pending.gd does not mark the agenda at an unchosen term start")


## V5.1-0c. The author "cannot register anything to the agenda": the offer exists
## only before the clock first runs in a term (programme.gd is_term_start), and
## Space is one keypress away. The first play press while the offer stands used
## to drop the hold, one month later the offer was gone for the whole term, and
## nothing said so. Now that press opens the Agenda and keeps the clock down; a
## second press is the player choosing to run without a programme.
func _check_play_does_not_forfeit_the_offer(state, ns, loader) -> void:
	if not _main._clock.paused or not _main._paused_for_programme:
		_fail("the guard check needs the term-start hold up")
		return
	_main._toggle_pause_by_hand()
	if not _main._clock.paused:
		_fail("the first Space at an unchosen term start ran the clock -- the offer is forfeited by one keypress")
	if not _main._windows.is_open("agenda"):
		_fail("the first Space at an unchosen term start did not open the Agenda that holds the offer")
	if Programme.available(state, ns, loader).is_empty():
		_fail("the offer vanished without the clock moving")
	_main._toggle_pause_by_hand()
	if _main._clock.paused:
		_fail("a second Space did not run the clock -- the player must be able to decline the offer")
	# Put the fixture back: the clock has not ticked, so the offer is still there
	# and the enforcement re-raises the hold and the card for the checks below.
	_main._windows.close("agenda")
	_main._enforce_term_start_programme()
	if not _main._clock.paused or not _main._paused_for_programme:
		_fail("re-enforcing an unchosen term start did not restore the hold")


## One CHOOSE button per offered entry, and the panel's fold answer is one of
## them while the offer stands.
func _check_the_offer_is_built_from_the_register(panel, state, ns, loader) -> void:
	if _main._windows.frame("agenda") == null:
		_fail("no window registered under the id 'agenda'")
	if int(_main._windows.shortcut("agenda")) != KEY_K:
		_fail("the agenda window is not on KEY_K")
	var offered: int = Programme.available(state, ns, loader).size()
	if offered == 0:
		_fail("nothing is offerable at a fresh term start -- the sweep test guarantees a live book")
		return

	_refresh(panel)
	var buttons := 0
	for node in _walk(panel._body):
		if node is Button and String(node.text) == "Choose":
			buttons += 1
	if buttons != offered:
		_fail("the offer drew %d CHOOSE buttons against %d offered entries -- the panel is filtering or inventing" % [buttons, offered])
	var action = panel.primary_action()
	if action == null or not (action is Button):
		_fail("primary_action() at term start is not the choose verb")


## The command path: the panel emits, main performs Programme.choose(), the
## clock resumes, the programme card is taken back, an entry-open card is
## pushed, and the pending mark clears.
func _check_the_choice_is_a_command(panel, state, ns, loader) -> void:
	var terms: Dictionary = _deadline_entry(state, ns, loader)
	if terms.is_empty():
		_fail("no offered entry carries a deadline -- the fixture needs one")
		return
	panel.programme_chosen.emit(String(terms["id"]))

	if ns.programme.size() != 1:
		_fail("the choice did not land on the register exactly once (%d entries)" % ns.programme.size())
	if not bool(ns.programme[0]["status"] == "active"):
		_fail("the chosen entry did not land active")
	if _main._clock.paused:
		_fail("the clock is still paused after the choice -- the choice must resume it")
	if not String(_main._programme_card_id).is_empty():
		_fail("the programme card was not dismissed by the choice")
	if Pending.window_ids(state, loader).has("agenda"):
		_fail("pending.gd still marks the agenda after the term's programme is chosen")

	var named := false
	for node in _walk(_main._hud.message_stack):
		if node is Label and String(node.text).contains(String(terms["name"]).to_upper()):
			named = true
	if not named:
		_fail("no card names the chosen programme -- an entry opened silently")


## The gate is the sim's, and the UI answers the refusal: the register stays at
## one entry and a card says why -- a silent verb is `refused_by_partner` again.
func _check_a_second_choice_refuses(panel, state, ns, loader) -> void:
	var register_size: int = ns.programme.size()
	var direct: Dictionary = Programme.choose(state, ns, String(loader.programme[0]["id"]), loader)
	if not bool(direct.get("refused", false)):
		_fail("a second Programme.choose() in one term was not refused")

	var cards_before: int = _main._hud.message_stack.card_count()
	panel.programme_chosen.emit(String(loader.programme[0]["id"]))
	if ns.programme.size() != register_size:
		_fail("a refused second choice still reached the register")
	if _main._hud.message_stack.card_count() != cards_before + 1:
		_fail("a refused choice did not answer with a card -- the verb went silent")


## The bar is the derived pair, not a stored number: the same call twice reads
## the live figure, and stepping the figure toward the goal moves the bar.
func _check_the_bar_reads_the_derived_pair(panel, state, ns, loader) -> void:
	_refresh(panel)
	var bar = _first_progress_bar(panel)
	if bar == null:
		_fail("the chosen entry drew no progress bar")
		return
	var terms: Dictionary = Programme.terms_of(loader, String(ns.programme[0]["entry_id"]))
	var read: Dictionary = Programme.progress_of(ns, terms)
	var expected: float = PanelKit.progress_fraction(
		float(read["current_value"]), float(read["goal_value"]), String(read["progressbar"]))
	if not is_equal_approx(float(bar.value), expected):
		_fail("the bar read %.3f against a derived %.3f" % [float(bar.value), expected])
	if float(bar.value) < 0.0 or float(bar.value) > 1.0:
		_fail("the bar escaped its own 0..1 range: %.3f" % float(bar.value))

	# Derived means it MOVES. Half the remaining gap toward the goal raises the
	# fraction under either authored direction; a stored fraction sits still.
	var field := String(terms["current_value"])
	var stepped: float = (float(read["goal_value"]) + float(read["current_value"])) * 0.5
	ns.set(field, stepped)
	_refresh(panel)
	var moved = _first_progress_bar(panel)
	if moved == null:
		_fail("the progress bar vanished on refresh")
		return
	if not float(moved.value) > float(bar.value) + 0.001:
		_fail("moving the live figure toward the goal did not move the bar (%.3f -> %.3f) -- progress is being stored, not derived" % [
			float(bar.value), float(moved.value),
		])


## The strip and the Overview read the same register: the bar's name and
## percentage up top, the row in the Overview's programme section.
func _check_the_other_surfaces_read_the_register(panel, state, ns, loader) -> void:
	_main._update_top_bar()
	if not _main._top_bar._figure_values["programme"].get_parent().visible:
		_fail("the top bar's programme figure is hidden with a live programme on the register")
	var terms: Dictionary = Programme.terms_of(loader, String(ns.programme[0]["entry_id"]))
	var name_text := String(terms["name"]).to_upper()
	if not String(_main._top_bar._figure_captions["programme"].text).contains(name_text):
		_fail("the top-bar strip does not name the chosen programme: '%s'" % _main._top_bar._figure_captions["programme"].text)
	if not String(_main._top_bar._figure_values["programme"].text).ends_with("%"):
		_fail("the top-bar strip carries no progress percentage: '%s'" % _main._top_bar._figure_values["programme"].text)

	var overview = _main._overview_panel
	_open_window_of(overview)
	overview.mark_dirty()
	overview._process(0.0)
	var text := ""
	for node in _walk(overview._programme_box):
		if node is Label:
			text += String(node.text) + " "
	if overview._programme_box.get_child_count() == 0:
		_fail("the overview's programme section drew nothing")
	if not text.contains(String(terms["name"])):
		_fail("the overview's programme section does not name the entry: %s" % text)

	# The Campaign panel's promises line -- docs/programme-model.md section 4's
	# shared read: the surface that runs the run-up must not leave the player
	# reconciling the pledge list and the programme register by hand.
	var campaign = _main._campaign_panel
	_open_window_of(campaign)
	campaign.mark_dirty()
	campaign._process(0.0)
	var campaign_text := ""
	for node in _walk(campaign._body):
		if node is Label:
			campaign_text += String(node.text) + " "
	if not campaign_text.contains(String(terms["name"])):
		_fail("the campaign panel's promises section does not name the chosen programme: %s" % campaign_text)
	if not campaign_text.contains("%"):
		_fail("the campaign panel's programme line carries no progress figure: %s" % campaign_text)


## A conclusion is news: stage the goal the sweep's harness way (one scripted
## write of the live figure past the complete trigger), let the machine judge
## it, and the card and the delivered state must follow -- along with the strip
## standing down now that nothing is live.
func _check_a_conclusion_pushes_a_card(panel, state, ns, loader) -> void:
	var terms: Dictionary = Programme.terms_of(loader, String(ns.programme[0]["entry_id"]))
	var beyond: float = float(terms["goal_value"]) + (10.0 if String(terms["progressbar"]) == "up" else -10.0)
	ns.set(String(terms["current_value"]), beyond)
	Programme.tick_month(state, loader)
	if String(ns.programme[0]["status"]) != "complete":
		_fail("the fixture did not conclude complete -- the write missed the trigger")

	var cards_before: int = _main._hud.message_stack.card_count()
	_main._card_programme_conclusions()
	if _main._hud.message_stack.card_count() != cards_before + 1:
		_fail("a concluded entry pushed %d cards, expected exactly one" % (_main._hud.message_stack.card_count() - cards_before))

	_refresh(panel)
	var delivered := false
	for node in _walk(panel._body):
		if node is Label and String(node.text).begins_with("Delivered"):
			delivered = true
	if not delivered:
		_fail("the register section does not read the completion")

	# The campaign panel's line prints the verdict rather than a fraction once
	# the term's programme has concluded -- a bar over a delivered programme
	# would be a lie about a term that is already priced.
	var campaign = _main._campaign_panel
	_open_window_of(campaign)
	campaign.mark_dirty()
	campaign._process(0.0)
	var delivered_line := false
	for node in _walk(campaign._body):
		if node is Label and String(node.text).contains("Delivered"):
			delivered_line = true
	if not delivered_line:
		_fail("the campaign panel's programme line does not read the completion")

	_main._update_top_bar()
	if _main._top_bar._figure_values["programme"].get_parent().visible:
		_fail("the top bar still shows a programme with nothing live on the register")


## A deadline entry -- the fixture that exercises the clock line as well as the
## trigger path. Read off the live offer, never an id literal.
func _deadline_entry(state, ns, loader) -> Dictionary:
	for terms in Programme.available(state, ns, loader):
		if int(terms.get("timeout_months", 0)) > 0:
			return terms
	return {}


## Mid-term with nothing chosen the panel used to say only "No programme was set
## this term." -- true, and no help to a player who loaded a save or ran past the
## offer. It now says when programmes open: the first day of the next term, which
## starts at the vote.
func _check_mid_term_says_when_the_next_programme_opens(panel, state, ns, loader) -> void:
	ns.programme = []
	ns.programme_chosen_term = -1
	ns.months_in_term = 7
	_refresh(panel)
	var text := ""
	for node in _walk(panel._body):
		if node is Label and not node.is_queued_for_deletion():
			text += String(node.text) + "
"
	var when := Trends.vote_date(ns)
	if not text.contains(ClockCluster.MONTH_NAMES[when.y - 1]) or not text.contains(str(when.x)):
		_fail("the mid-term Agenda does not say when the next programme opens (%s %d): '%s'" % [
			ClockCluster.MONTH_NAMES[when.y - 1], when.x, text])
	if not text.to_lower().contains("next term"):
		_fail("the mid-term Agenda does not name the next term: '%s'" % text)


func _refresh(panel) -> void:
	_open_window_of(panel)
	panel.mark_dirty()
	panel._process(0.0)


func _first_progress_bar(panel):
	for node in _walk(panel._body):
		if node is ProgressBar:
			return node
	return null


## The walk skips queue_free'd nodes: the panel's refresh retires the previous
## generation with queue_free, which stays in the tree until the frame ends --
## within one frame of refreshes the dead generation is still walkable, and a
## count or a bar read off it answers for the state before the last refresh.
func _walk(node) -> Array:
	var out: Array = [node]
	if node.is_queued_for_deletion():
		return out
	for child in node.get_children():
		out.append_array(_walk(child))
	return out



## The window holding `panel`, opened: since V5.1-0a a panel refreshes only while
## its window shows -- as the player sees it -- so a check that reads one opens
## it first rather than relying on a closed window's panel redrawing anyway.
func _open_window_of(panel) -> void:
	for id in _main._windows.panel_ids():
		if _main._windows.frame(id)._content == panel:
			_main._windows.open(id)

func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_agenda_panel: all checks passed")
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
	_main.queue_free()
	quit(0 if _failures.is_empty() else 1)
