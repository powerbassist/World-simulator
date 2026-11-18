extends PanelContainer

## The Folder -- rework 2 S2, G2 (presidency-page-brief.md, "The folder"): V1.8's Dispatches,
## renamed by the author ("Dossier (Recommended)") and rebuilt on the month's folder's own pieces,
## a list at the left and the chosen item's page (file_view.gd) at the right. Three groups:
##
##   To answer  every file of the inbox (inbox_files.gd: an event, a request, a treaty, a vote,
##              a bill, a fund), and every desk entry with NO card -- an arrival its popup setting
##              kept quiet, or a card closed with its X. Dispatches was the one place those were
##              answered, so the Folder lists them too, or they would lapse unseen.
##   Decided    the ledger, whole: what was decided "including the ones that were made by the
##              clock". A ledger of forced choices has to show which of them the clock made, so a
##              default says "No answer given" and is never dressed as a decision.
##   News       the inbox's notes; the inbox itself shows them as one line, "News: N" (inbox.gd).
##
## NEVER PAUSES (the author, 2026-11-15: "Jamais"; "Page ancrée, horloge qui tourne"). V1.8's
## reason still holds and is now the only rule: a crisis the player can ignore and pay for is the
## whole of the deadline, and a surface that stopped time to ask would remove the choice of not
## answering. A file's answer goes through Inbox.press, the card's own door, so main.gd's handler
## and the request lane keep every rule they had; a desk entry with no card answers by id through
## `acted`, V1.8's own path (main.gd), the U4 baseline taken before the command.
##
## Reads GameState and the inbox, writes neither.

signal closed
## (before_snapshot, label): projects_panel.acted's pair, for a desk entry with no card.
signal acted(before, label)

const Events = preload("res://src/sim/events.gd")
const EventsK = preload("res://src/sim/events_constants.gd")
const Trends = preload("res://src/ui/trends.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const MessageSettings = preload("res://src/ui/message_settings.gd")
const FileRead = preload("res://src/ui/file_read.gd")
const FileView = preload("res://src/ui/file_view.gd")
const InboxFiles = preload("res://src/ui/inbox_files.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AudienceK = preload("res://src/sim/audience_constants.gd")
const ProgrammeFile = preload("res://src/ui/programme_file.gd")
const ProgrammePicker = preload("res://src/ui/programme_picker.gd")

const ANSWER := "answer"
const DECIDED := "decided"
const NEWS := "news"
## The list's width, the folder's own (it was chief_briefing.gd's LIST_WIDTH).
const LIST_WIDTH := 300

var _state
var _loader
var _main
var _dirty := true
var _messages := {}  # V4.8c: the FEED band filters the ledger; empty = defaults

var _title: Label
var _list: VBoxContainer
var _page: VBoxContainer
var _close_button: Button
## The item shown: "file:<card id>", "desk:<event id>", "record:<event|year|month|choice>", "note:<card id>".
## Keyed by what the item is, never by its place in a list: a new record or file never turns the page
## shown into another (#403 pass 2 T3; a click there would have answered the other).
var _selected := ""
## The event the shown file or desk entry is about, kept after it leaves the desk: its record is its page then.
var _shown_event := ""
## The shown file lapsed while open: its record says the clock answered it.
var _lapsed := false
## The request the shown file is, kept after it leaves: a request that lapsed while open says so, never
## "Answered." (QA's TAKE 1 on #403).
var _shown_request := ""
## A group asked for (the News line) before the list exists: its first item is chosen at the build.
var _wanted_group := ""
var _groups := {ANSWER: [], DECIDED: [], NEWS: []}
var _buttons := {}  # key -> its list button
## The first enabled answer on the page (tab_page.gd's fold contract).
var _primary: Control = null
## The term's programme file's body (S3): one node for the panel's life, never cleared with the page,
## so its selection and scroll outlive the page's rebuilds; shown on that file only.
var _picker
## The term the programme file was last drawn for: once its offer has gone, its page is what that term booked.
var _programme_term := -1


func _ready() -> void:
	custom_minimum_size = Vector2(520, 0)  # the dock sets the height (tab_page.gd wanted_height)
	# The programme file's picker is the one scroller; tab_page decides its fill once, on the first page
	# shown, so the Folder says it here: a short page still hugs (wanted_height counts what is visible).
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := PanelKit.padded(self, 16, 10)
	_title = Label.new()
	_title.theme_type_variation = UiTheme.LEAD
	root.add_child(_title)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_list = VBoxContainer.new()
	_list.custom_minimum_size.x = LIST_WIDTH
	_list.add_theme_constant_override("separation", 2)
	body.add_child(_list)
	body.add_child(VSeparator.new())
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 10)
	body.add_child(_page)
	_picker = ProgrammePicker.new(func(entry_id: String) -> void: _main._on_programme_chosen(entry_id))
	_picker.hide()
	_page.add_child(_picker)
	_close_button = PanelKit.sized(Button.new())
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func() -> void: closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_selected = ""
	_dirty = true


## The inbox and the registers a file's page reads (file_read.gd reads main's).
func attach(main) -> void:
	_main = main


## V4.8c. The player's message settings; main.gd hands them in at boot and on every close of the
## settings screen.
func set_messages(messages: Dictionary) -> void:
	_messages = messages
	_dirty = true


func hide_close_button() -> void:
	_close_button.hide()


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty and is_visible_in_tree() and _state != null:
		_refresh()


## The groups' keys as the list last showed them: {answer, decided, news}.
func groups() -> Dictionary:
	return _groups


func selected() -> String:
	return _selected


func select(key: String) -> void:
	_selected = key
	_wanted_group = ""
	_lapsed = false
	_dirty = true
	# A note the player picks is the news read; one shown by the fallback or a rebuild is not (pass 1).
	if key.begins_with("note:") and _main != null:
		_main._hud.inbox.news_seen()
	if _list != null and _main != null:
		_refresh()


## An inbox file's page (a priority's Go, briefing_driver.gd). The programme's card opens its file.
func show_file(card_id: String) -> void:
	select(ProgrammeFile.KEY if ProgrammeFile.is_file(_main, card_id) else "file:" + card_id)


## A group's first item (the inbox's News line asks for NEWS).
func show_group(group: String) -> void:
	_selected = ""
	_wanted_group = group
	_dirty = true


## The answer `index` of the file shown. Stays on the tab, the clock as the player left it.
func press(index: int) -> void:
	if _selected.begins_with("file:"):
		InboxFiles.press(_main._hud.inbox, _selected.trim_prefix("file:"), index)
	elif _selected.begins_with("desk:"):
		var ev = Events.event_by_id(_loader, _selected.trim_prefix("desk:"))
		if ev != null and index >= 0 and index < ev.choices.size():
			_on_choose(ev, ev.choices[index])
	_dirty = true


func _refresh() -> void:
	_dirty = false
	var ns = _state.player() if _state != null else null
	if ns == null or _main == null:
		return
	# T4: the rebuild frees the focused item; the keyboard gets the shown item back.
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	# Pass 2 T9: focus on a node the rebuild keeps (the picker's rows) stays where it is.
	var had_focus: bool = owner != null and is_ancestor_of(owner) and not _picker.is_ancestor_of(owner)
	_title.text = tr("FOLDER — %s") % DateText.month_year(int(_state.month), int(_state.year))
	_read_groups(ns)
	var keys: Array = _groups[ANSWER] + _groups[DECIDED] + _groups[NEWS]
	if _wanted_group != "" and not (_groups[_wanted_group] as Array).is_empty():
		_selected = String(_groups[_wanted_group][0])
		if _wanted_group == NEWS:
			_main._hud.inbox.news_seen()  # the News line pressed: the player came for the news
	elif not keys.has(_selected):
		_selected = _follow(ns)
	_wanted_group = ""
	_build_list(ns)
	_build_page(ns)
	if had_focus and _buttons.has(_selected):
		(_buttons[_selected] as Button).grab_focus()


## Where the page goes when what it showed left its list. A file or desk entry about an event follows the
## matter -- to its desk entry while it is on the desk, to its record once decided (the clock's answer says
## so) -- and is never swapped for the next file. Any other file keeps its page ("Answered."). Nothing
## shown yet, or a record or note gone: the next thing waiting, else the last decision, else the news.
func _follow(ns) -> String:
	if _selected == ProgrammeFile.KEY:
		return _selected  # its offer gone: the page is what was booked (T1)
	if _selected.begins_with("file:") or _selected.begins_with("desk:"):
		if _shown_event == "":
			return _selected
		if ns.event_queue.any(func(e): return String(e.get("event_id", "")) == _shown_event):
			return "desk:" + _shown_event
		for record in ns.event_history:  # newest first
			if String(record.get("event_id", "")) == _shown_event:
				_lapsed = bool(record.get("defaulted", false))
				return _record_key(record)
		return _selected
	return String((_groups[ANSWER] + _groups[DECIDED] + _groups[NEWS] + [""])[0])


static func _record_key(record: Dictionary) -> String:
	return "record:%s|%d|%d|%s" % [String(record.get("event_id", "")), int(record.get("year", 0)), int(record.get("month", 0)),
		String(record.get("choice_id", ""))]


func _read_groups(ns) -> void:
	var decided: Array = []
	for record in ns.event_history:  # newest first: Events.answer pushes to the front
		if _shown(record):
			decided.append(_record_key(record))
	_groups = {ANSWER: answer_keys(_main), DECIDED: decided,
		NEWS: _main._hud.inbox.notes().map(func(n): return "note:" + String(n["id"]))}


## "To answer", the one count of what waits (the Presidency page's door reads it too, #403 pass 2 T11): every
## file of the inbox, then every desk entry with no card.
static func answer_keys(main) -> Array:
	var answer: Array = []
	# S3: the term's programme first while its offer stands -- the file, never its card (T2).
	if not ProgrammeFile.offer(main).is_empty():
		answer.append(ProgrammeFile.KEY)
	var carded := {}  # event ids whose card is still a file of the inbox
	for file in InboxFiles.list(main._hud.inbox):
		if ProgrammeFile.is_file(main, String(file["id"])):
			continue
		answer.append("file:" + String(file["id"]))
		if main._event_cards.has(file["id"]):
			carded[String(main._event_cards[file["id"]])] = true
	for entry in main._state.player().event_queue:
		var event_id := String(entry.get("event_id", ""))
		if not carded.has(event_id) and Events.event_by_id(main._loader, event_id) != null:
			answer.append("desk:" + event_id)
	return answer


## V4.8c: the FEED band per category, on the ledger only (the desk shows every entry whatever
## the settings say). Severity is the event's own; the record does not carry it.
func _shown(record: Dictionary) -> bool:
	var ev = Events.event_by_id(_loader, String(record.get("event_id", "")))
	var severity := int(ev.severity) if ev != null else EventsK.SEVERITY_MAX
	return MessageSettings.allows(_messages, String(record.get("category", "")), severity, "feed")


# --- the list ------------------------------------------------------------------------

func _build_list(ns) -> void:
	_clear(_list)
	_buttons.clear()
	_group_head(tr("To answer"), _groups[ANSWER].size())
	if _groups[ANSWER].is_empty():
		PanelKit.line(_list, _quiet_desk(ns))
	for key in _groups[ANSWER]:
		_item(key, _answer_title(key), _answer_date(key))
	_group_head(tr("Decided"), _groups[DECIDED].size())
	if ns.event_history.is_empty():
		PanelKit.line(_list, tr("Nothing has come up yet."))
	for record in ns.event_history:
		if _groups[DECIDED].has(_record_key(record)):
			_item(_record_key(record), Strings.record_event_name(record), DateText.month_year(int(record.get("month", 1)), int(record.get("year", 0))))
	# A hidden row is COUNTED, never silent: a ledger that shrank with nothing saying why reads as lost history.
	var hidden: int = ns.event_history.size() - _groups[DECIDED].size()
	if hidden > 0:
		PanelKit.line(_list, tr_n("%d record hidden by your message settings.", "%d records hidden by your message settings.", hidden) % hidden)
	_group_head(tr("News"), _groups[NEWS].size())
	if _groups[NEWS].is_empty():
		PanelKit.line(_list, tr("No news yet."))
	for note in _main._hud.inbox.notes():
		_item("note:" + String(note["id"]), String(note["title"]), "" if int(note["count"]) == 1 else "×%d" % int(note["count"]))  # i18n: row-ok a note's title, routed by its pusher


func _group_head(text: String, count: int) -> void:
	if _list.get_child_count() > 0:
		# A group starts clear of the one above, so its head does not read as the last item's caption.
		var gap := Control.new()
		gap.custom_minimum_size.y = 10
		_list.add_child(gap)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_list.add_child(head)
	PanelKit.heading(head, text)
	if count > 0:
		var n := Label.new()
		n.text = str(count)
		n.theme_type_variation = UiTheme.MICRO
		head.add_child(n)


## Two states give an empty desk and they are not the same, so the caption names which
## (projects_panel.gd's correction: an empty list must not read as a closed gate).
func _quiet_desk(ns) -> String:
	var longest_quiet := 0
	for category in ns.event_category_quiet:
		longest_quiet = maxi(longest_quiet, int(ns.event_category_quiet[category]))
	if longest_quiet <= 0:
		return tr("Nothing today.")
	var closed_ago: int = EventsK.CATEGORY_QUIET_MONTHS - longest_quiet
	if closed_ago <= 0:
		return tr("Nothing today. The last matter closed this month.")
	return tr_n("Nothing today. The last matter closed %d month ago.", "Nothing today. The last matter closed %d months ago.", closed_ago) % closed_ago


func _answer_title(key: String) -> String:
	if key == ProgrammeFile.KEY:
		return tr("The term's programme")
	if key.begins_with("desk:"):
		return Strings.row_name("events", Events.event_by_id(_loader, key.trim_prefix("desk:")))
	return FileRead.list_title(_main, InboxFiles.of(_main._hud.inbox, key.trim_prefix("file:")))


func _answer_date(key: String) -> String:
	if key == ProgrammeFile.KEY:
		return ""
	if key.begins_with("desk:"):
		return FileRead.desk_by_text(_main, key.trim_prefix("desk:"))
	return FileRead.by_text(_main, InboxFiles.of(_main._hud.inbox, key.trim_prefix("file:")), true)


## One item: its name, which opens its page, and its date beside it.
func _item(key: String, text: String, date: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_list.add_child(row)
	var button := Button.new()
	button.text = text
	button.tooltip_text = text
	button.theme_type_variation = UiTheme.SUBROW_BUTTON
	button.toggle_mode = true
	button.button_pressed = key == _selected
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(select.bind(key))
	row.add_child(button)
	_buttons[key] = button
	if date != "":
		var when := Label.new()
		when.text = date
		when.theme_type_variation = UiTheme.CAPTION
		when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(when)


# --- the page ------------------------------------------------------------------------

func _build_page(ns) -> void:
	for child in _page.get_children():
		if child != _picker:
			_page.remove_child(child)
			child.queue_free()
	# Hidden only off its own page: hiding it to show it again would drop the focus a row holds (T9).
	if _selected != ProgrammeFile.KEY or ProgrammeFile.offer(_main).is_empty():
		_picker.hide()
	_primary = null
	if not _selected.begins_with("file:") and not _selected.begins_with("desk:"):
		_shown_event = ""
		_shown_request = ""
	if _selected == ProgrammeFile.KEY:
		if not ProgrammeFile.offer(_main).is_empty():
			_programme_term = int(ns.terms_served)
			ProgrammeFile.build(_main, _page, _picker)
			return
		ProgrammeFile.booked(_main, _page, _programme_term if _programme_term >= 0 else int(ns.terms_served))
	elif _selected.begins_with("file:"):
		var id := _selected.trim_prefix("file:")
		var live := not InboxFiles.of(_main._hud.inbox, id).is_empty()
		if _main._event_cards.has(id):
			_shown_event = String(_main._event_cards[id])
		if live:
			_shown_request = String(preload("res://src/ui/audience_driver.gd").lane_of(_main)._request_of.get(id, ""))
		var request := Audiences.request(ns, _shown_request) if _shown_request != "" and not live else {}
		if String(request.get("status", "")) == AudienceK.STATUS_LAPSED:
			PanelKit.line(_page, tr("It lapsed while it was open: the request went unanswered."))
		else:
			FileView.build(_page, FileRead.describe(_main, InboxFiles.of(_main._hud.inbox, id)), press)
	elif _selected.begins_with("desk:"):
		_shown_event = _selected.trim_prefix("desk:")
		FileView.build(_page, FileRead.desk_entry(_main, _shown_event), press)
	elif _selected.begins_with("record:"):
		for record in ns.event_history:
			if _record_key(record) == _selected:
				_record_page(record)
				break
	elif _selected.begins_with("note:"):
		_note_page(_selected.trim_prefix("note:"))
	for button in _page.find_children("*", "Button", true, false):  # i18n: ok a class name
		# The hidden picker stays in the page: its rows are never another page's answer (pass 1).
		if not (button as Button).disabled and not _picker.is_ancestor_of(button):
			_primary = button
			break


## A decision as the ledger keeps it: the matter, its date, what was decided and what it meant.
func _record_page(record: Dictionary) -> void:
	# The place, for a sited event: the record carries the name because a past act's site
	# cannot be re-derived once the shares have moved (V2.6b1).
	var heading := Strings.record_event_name(record)
	var where := String(record.get("region_name", ""))
	if where != "":
		heading = "%s — %s" % [heading, where]
	PanelKit.heading(_page, DateText.month_year(int(record.get("month", 1)), int(record.get("year", 0))))
	var title := Label.new()
	title.text = heading
	title.theme_type_variation = UiTheme.FIGURE
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(title)
	var answer := Label.new()
	answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A DEFAULT IS NOT A CHOICE AND THE LEDGER SAYS SO: "Say nothing" beside a month the player
	# never answered would read as a decision they made.
	if bool(record.get("defaulted", false)):
		answer.text = tr("No answer given — %s") % Strings.record_choice_label(record)
		answer.theme_type_variation = UiTheme.BAD_TEXT
		if _lapsed:
			PanelKit.line(_page, tr("It lapsed while it was open: the clock answered it."))
	else:
		answer.text = Strings.record_choice_label(record)
		answer.theme_type_variation = UiTheme.LEAD
	_page.add_child(answer)
	# WHAT IT MEANT, derived from the content rather than stored with the record (a serialised entry
	# keeps its few keys), and empty when the content no longer defines the event.
	var ev = Events.event_by_id(_loader, String(record.get("event_id", "")))
	if ev != null:
		var what := Strings.choice_summary(ev.id, ev.choice_by_id(String(record.get("choice_id", ""))))
		if what != "":
			PanelKit.rich(_page, what)


func _note_page(id: String) -> void:
	for note in _main._hud.inbox.notes():
		if String(note["id"]) != id:
			continue
		var title := Label.new()
		title.text = String(note["title"])  # i18n: row-ok a note's title, routed by its pusher
		title.theme_type_variation = UiTheme.FIGURE
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_page.add_child(title)
		if int(note["count"]) > 1:
			PanelKit.line(_page, tr_n("Came %d time.", "Came %d times.", int(note["count"])) % int(note["count"]))
		# T6: its good / bad / uncertain word, as the card wore it (words, never the colour alone).
		if String(note.get("tag", "")) != "":
			var tag := Label.new()
			tag.text = String(note["tag"])  # i18n: row-ok ResultTone's word, translated there
			tag.uppercase = true
			tag.theme_type_variation = String(note["tag_variation"])
			_page.add_child(tag)
		PanelKit.rich(_page, String(note["body"]), PanelKit.Tone.PLAIN)  # i18n: row-ok a note's body, routed by its pusher


## U4's contract, projects_panel._on_act()'s shape: the baseline is captured BEFORE the command.
## answer() by id, never choose() on the head: with several entries on the desk the answer must be
## THIS entry's.
func _on_choose(ev, choice: Dictionary) -> void:
	var before := Trends.snapshot_now(_state)
	var record := Events.answer(_state, _loader, ev.id, String(choice.get("id", "")))
	if record.is_empty():
		return
	_dirty = true
	acted.emit(before, "%s: %s" % [Strings.row_name("events", ev), Strings.choice_label(ev.id, choice)])


func _clear(box: Control) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


## The control this panel exists to let the player press (V2.1a's fold contract): the first
## enabled answer on the page, null when the page asks nothing.
func primary_action() -> Control:
	# The programme file's Choose follows the picker's selection, which changes without a page build.
	return _picker.primary() if _picker.visible else _primary
