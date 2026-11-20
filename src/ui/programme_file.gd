extends RefCounted

## The term's programme as the Folder's first file -- rework 2 S3. The Agenda tab retired (the
## Diary stays alone in its domain): the offer is the term-start file in "To answer", its page a
## lead (file_view.gd) over the programme picker (programme_picker.gd). The parent's pick at the
## picture step was B, a picker body, over A, a card per entry: 28 whole summaries put the page at
## 3.5 screens at 1.0 and 5.4 at the former 130 % text size, and lost the five groups.
##
## THE FILE FOLLOWS THE OFFER, NOT THE CARD (#405 pass 2, T2): it is listed under KEY while
## Programme.available() holds anything, whatever became of the inbox card -- closed with its X,
## the offer and the clock's hold still stand, and the file with them. The card is a door to it.
##
## Static over main, as the other drivers are. Main performs the command (_on_programme_chosen);
## this file opens the file, draws its page, and draws what was booked once the offer has gone.
## Opening is navigation and never touches the clock (G2); only the term-start hold does.

const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const ProgrammePicker = preload("res://src/ui/programme_picker.gd")
const FileView = preload("res://src/ui/file_view.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const TermReads = preload("res://src/ui/term_reads.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")

## The Folder's key for the file (events_panel.gd lists it first in To answer while the offer stands).
const KEY := "programme"

## main's instance id -> the term (terms_served) whose offer the Folder has drawn. main.gd's play
## guard asks it (V5.1-0c): the first press of a term opens the file, a press after it has shown the
## offer runs the clock. GameReload.forget_main erases a main's row (MAIN_KEYED_STATICS).
static var _seen := {}


static func offer(main) -> Array:
	return Programme.available(main._state, main._state.player(), main._loader)


## Whether `card_id` is the programme's inbox card (its click and show_file open the file).
static func is_file(main, card_id: String) -> bool:
	return card_id != "" and card_id == String(main._programme_card_id)


## The file on the Folder while the offer stands; once it has gone, the Presidency page, focused on the
## programme's lane (on `entry_id`'s when given). Navigation only: the clock stays as the player has it.
static func open(main, entry_id := "") -> void:
	if offer(main).is_empty():
		main._windows.open("overview")
		main._overview_panel.focus_goal(entry_id)
		return
	main._events_panel.select(KEY)
	main._windows.open("events")
	_seen[main.get_instance_id()] = int(main._state.player().terms_served)  # opened on it: the offer is shown


## The play guard (main.gd's _toggle_pause_by_hand): true when this press is spent opening the offer --
## the first press of a term that has one. With nothing to choose the press runs the clock (T13: a hold
## whose offer emptied under it never strands the clock).
static func held_press(main) -> bool:
	if offer_seen(main) or offer(main).is_empty():
		return false
	open(main)
	return true


## The Presidency page's doors (window_requested): "programme" is the file, any other id its tab.
static func open_window(window_id: String, main) -> void:
	if window_id == KEY:
		open(main)
	else:
		main._windows.open(window_id)


static func offer_seen(main) -> bool:
	return int(_seen.get(main.get_instance_id(), -1)) == int(main._state.player().terms_served)


## The file's page: its lead, the record of the terms before (the Agenda's register, T5 a), then the
## picker -- the same node on every build (the Folder keeps it), so its selection and its list's scroll
## outlive a day tick or a command.
static func build(main, page: Control, picker) -> void:
	var ns = main._state.player()
	FileView.build(page, {"id": "", "kind": "other", "micro": "", "title": Strings.t("The term's programme"),
		"situation": Strings.t("Pick the term's [g=programme]programme[/g]. Delivery is judged when it lands or its deadline passes."),
		"by_text": "", "by_month": -1, "who": {}, "choices": []}, func(_i: int) -> void: pass)
	_record(page, ns, main._loader)
	picker.fill(ns, offer(main))
	picker.show()
	page.move_child(picker, -1)
	if page.is_visible_in_tree():  # a build the player sees; a hidden Folder's rebuild shows nothing
		_seen[main.get_instance_id()] = int(ns.terms_served)


static func _record(page: Control, ns, loader) -> void:
	var lines: Array = TermReads.past_record(ns, loader)
	if lines.is_empty():
		return
	PanelKit.heading(page, Strings.t("Past terms"))
	for line in lines:
		ResultTone.tint(PanelKit.line(page, String(line["text"]), PanelKit.Tone.DIM), String(line["tone"]))  # i18n: row-ok TermReads routes the name and the verdict


## The file once its offer has gone, for the term it was drawn in (T8): what was booked, its clock or its
## verdict (T10), the clock running again while that term is still the one at its start, and the door to
## the lane where it is tracked. Never "Answered.": nothing chosen says so.
static func booked(main, page: Control, term: int) -> void:
	var ns = main._state.player()
	var entry := {}
	for e in ns.programme:
		if int(e["chosen_term"]) == term:
			entry = e
	if entry.is_empty():
		PanelKit.line(page, Strings.t("No programme was chosen this term."), PanelKit.Tone.DIM)
		return
	var terms: Dictionary = Programme.terms_of(main._loader, String(entry["entry_id"]))
	PanelKit.heading(page, Strings.t("Your programme"))
	var title := Label.new()
	title.text = Strings.row_name("programme", terms)
	title.theme_type_variation = UiTheme.FIGURE
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(title)
	match String(entry["status"]):
		ProgrammeK.STATUS_ACTIVE:
			PanelKit.line(page, "%s · %s" % [ProgrammePicker.read_text(ns, terms), StripReadings.programme_clock_text(terms, entry)], PanelKit.Tone.DIM)
		ProgrammeK.STATUS_COMPLETE:
			ResultTone.tint(PanelKit.line(page, Strings.t("Delivered")), ResultTone.GOOD)
		ProgrammeK.STATUS_FAIL:
			ResultTone.tint(PanelKit.line(page, Strings.t("Missed")), ResultTone.BAD)
		_:
			PanelKit.line(page, Strings.t("Overtaken"), PanelKit.Tone.DIM)
	if term == int(ns.terms_served) and Programme.is_term_start(ns) and not main._clock.paused:
		PanelKit.line(page, Strings.t("The clock runs again."))
	var lane := PanelKit.sized(Button.new())
	lane.text = Strings.t("Open the programme lane")
	lane.pressed.connect(func() -> void: open(main, String(entry["entry_id"])))
	PanelKit.buttons(page).add_child(lane)
