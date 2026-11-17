extends RefCounted

## The term's programme as the Folder's first file -- rework 2 S3. The Agenda tab retired (the
## Diary stays alone in its domain): the offer is the term-start file in "To answer", its page the
## file's own lead (file_view.gd) over the programme picker (programme_picker.gd). The parent's pick
## at the picture step was B, a picker body, over A, a card per entry: 28 whole summaries put the
## page at 3.5 screens at 1.0 and 5.4 at text 130, and lost the five groups.
##
## Static over main, as the other drivers are. Main performs the command (_on_programme_chosen);
## this file opens the file, draws its page, and draws what was booked once the file has left.

const Programme = preload("res://src/sim/programme.gd")
const ProgrammePicker = preload("res://src/ui/programme_picker.gd")
const FileView = preload("res://src/ui/file_view.gd")
const FileRead = preload("res://src/ui/file_read.gd")
const InboxFiles = preload("res://src/ui/inbox_files.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## main's instance id -> the term (terms_served) whose offer the Folder has drawn. main.gd's play
## guard asks it (V5.1-0c): the first press of a term opens the file, a press after it has shown the
## offer runs the clock.
static var _seen := {}


static func is_file(main, card_id: String) -> bool:
	return card_id != "" and card_id == String(main._programme_card_id)


## The live programme card, "" once chosen or gone.
static func card_of(main) -> String:
	var card := String(main._programme_card_id)
	return card if card != "" and not InboxFiles.of(main._hud.inbox, card).is_empty() else ""


## The programme file open on the Folder; with nothing to choose, the Presidency page, where the
## term's programme is a lane.
static func open(main) -> void:
	var card := card_of(main)
	# The card closed with its X while the offer stands (pass 1): the hold is still up, so the file is put
	# back (the enforcement is idempotent) rather than the press landing nowhere and the clock never running.
	if card == "" and not Programme.available(main._state, main._state.player(), main._loader).is_empty():
		main._enforce_term_start_programme()
		card = card_of(main)
	if card == "":
		main._windows.open("overview")
		return
	main._events_panel.show_file(card)
	main._windows.open("events")


## The Presidency page's doors (window_requested): "programme" is the file, any other id its tab.
static func open_window(window_id: String, main) -> void:
	if window_id == "programme":
		open(main)
	else:
		main._windows.open(window_id)


static func offer_seen(main) -> bool:
	return int(_seen.get(main.get_instance_id(), -1)) == int(main._state.player().terms_served)


## A test's reset of the guard's memory.
static func forget(main) -> void:
	_seen.erase(main.get_instance_id())


## The file's page: its lead, then the picker -- the same node on every build (the Folder keeps it),
## so its selection and its list's scroll outlive a day tick or a command.
static func build(main, page: Control, picker) -> void:
	var ns = main._state.player()
	FileView.build(page, FileRead.describe(main, InboxFiles.of(main._hud.inbox, card_of(main))), func(_i: int) -> void: pass)
	picker.fill(ns, Programme.available(main._state, ns, main._loader))
	picker.show()
	page.move_child(picker, -1)
	_seen[main.get_instance_id()] = int(ns.terms_served)


## The file once chosen: what was booked, the clock running again (the hold was on this file), and
## the door to the lane where it is tracked. The page stays on the matter, never "Answered.".
static func booked(main, page: Control) -> void:
	var live: Array = Programme.this_term(main._state.player())
	if live.is_empty():
		# The card left with nothing chosen (the clock ran past the term start): never dressed as an answer.
		PanelKit.line(page, Strings.t("No programme was chosen this term."), PanelKit.Tone.DIM)
		return
	var ns = main._state.player()
	var terms: Dictionary = Programme.terms_of(main._loader, String(live[-1]["entry_id"]))
	PanelKit.heading(page, Strings.t("Your programme"))
	var title := Label.new()
	title.text = Strings.row_name("programme", terms)
	title.theme_type_variation = UiTheme.FIGURE
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(title)
	PanelKit.line(page, "%s · %s" % [ProgrammePicker.read_text(ns, terms), ProgrammePicker.clock_text(terms)], PanelKit.Tone.DIM)
	if not main._clock.paused:
		PanelKit.line(page, Strings.t("The clock runs again."))
	var lane := PanelKit.sized(Button.new())
	lane.text = Strings.t("Open the programme lane")
	lane.pressed.connect(func() -> void: main._windows.open("overview"))
	PanelKit.buttons(page).add_child(lane)
