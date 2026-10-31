extends PanelContainer

## The president's diary — U6a. Read-only over sim state, like every panel since
## U2: it reads GameState and issues player intent back as an explicit command
## (Calendar.book / Calendar.cancel), never writing state itself.
##
## A MONTH GRID since V5.2 b+ R8 (the author: "a full agenda grid";
## diary_grid.gd), paged across the booking horizon. U6a had chosen a twelve-month
## strip because a month page opened empty seven times in ten (31 % of months
## carried a date then); V5.2 filled the diary -- requests offer days, promises
## and delegations fall due, a request has a last day -- and the grid now marks
## each on its day. What U6a's measurement still argues for stays: the "Next:"
## line always on screen and the LATER footer, so a sparse page reads as sparse
## inside a year rather than as an empty screen.
##
## Booking lives here and NOWHERE ELSE, which is a deviation from the plan taken
## on the plan's own evidence. Every verb row on nation_panel.gd, law_panel.gd and
## government_panel.gd is an HBox holding an autowrapping summary label beside one
## button; a second button narrows the label, the wrap grows the row, and the
## panel is at 860px against U5a's ~886 ceiling having already paid for that fold
## twice (V1.3e, V1.3g). Owning booking in one place is also truer to the verb —
## you open your diary to schedule something.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const ClockCluster = preload("res://src/ui/clock_cluster.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const K = preload("res://src/sim/calendar_constants.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Projects = preload("res://src/sim/projects.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const CabinetK = preload("res://src/sim/cabinet_constants.gd")
const Strings = preload("res://src/ui/strings.gd")
const Bills = preload("res://src/sim/bills.gd")
const DateText = preload("res://src/ui/date_text.gd")
const VisitBooking = preload("res://src/ui/visit_booking.gd")
const AudienceBooking = preload("res://src/ui/audience_booking.gd")
const DiaryGrid = preload("res://src/ui/diary_grid.gd")

signal closed

## Mirrors law_panel.gd's `proposed` and nation_panel.gd's `acted` in purpose but
## NOT in shape: a booking commits nothing this month, so there is no baseline to
## measure and no U4 decision delta to queue. main.gd listens only to repaint.
signal diary_changed

## V5.2b: an audience request's days, booked here (audience_booking.gd).
var audience := AudienceBooking.new()
var _grid := DiaryGrid.new()

## What each fixed-date kind is called on screen. Presentation, so it lives here
## rather than in calendar_constants.gd — src/sim/ names the kind, the panel says
## it in English.
const FIXED_LABEL := {
	K.FIXED_ELECTION: "Legislative election",  # i18n: msgid
	K.FIXED_EP_ELECTION: "European election",  # i18n: msgid
	K.FIXED_EXECUTIVE: "Presidential election",  # i18n: msgid
	K.FIXED_HEAD_OF_STATE: "Head of state's term ends",  # i18n: msgid
	K.FIXED_COUNCIL_PROPOSAL: "Council proposes",  # i18n: msgid
	K.FIXED_COUNCIL_VOTE: "Council votes",  # i18n: msgid
	K.FIXED_COUNCIL_RATIFICATION: "Ratification deadline",  # i18n: msgid
	K.FIXED_DISSOLUTION: "Dissolution available again",  # i18n: msgid
	K.FIXED_COOLDOWN: "Available again",  # i18n: msgid
	K.FIXED_PROJECT: "Opens",  # i18n: msgid
	K.FIXED_REFERENDUM: "Referendum",  # i18n: msgid
	K.FIXED_EVENT: "Answer by",  # i18n: msgid
}

const KIND_LABEL := {
	K.KIND_DIPLOMATIC: "Diplomatic act",  # i18n: msgid
	K.KIND_LAW: "Propose a law",  # i18n: msgid
	K.KIND_RESHUFFLE: "Reshuffle a portfolio",  # i18n: msgid
}

var _state
var _loader
var _title: Label
var _next_up: Label
var _body: VBoxContainer
var _kind_pick: OptionButton
var _subject_label: Label
var _subject_pick: OptionButton
var _act_label: Label
var _act_pick: OptionButton
var _month_pick: OptionButton
var _day_spin: SpinBox
var _travel_note: Label
var _book_button: Button
var _status: Label
## The form's last refusal line and the entry just booked (_refresh_travel_note).
var _refused := ""
var _booked := {}
var _dirty := true
var _close_button: Button


func _ready() -> void:
	# 700, comfortably inside U5a's ~886px usable band. The strip is the only part
	# whose length is driven by CONTENT COUNT rather than by a fixed list — a
	# player with thirty bookings has thirty rows — so it is the one thing in this
	# panel that could grow through the ceiling, and it is inside a ScrollContainer
	# that takes the slack. Everything below it is a fixed number of rows.
	custom_minimum_size = Vector2(520, 700)

	var root := PanelKit.padded(self, 16, 10)

	_title = Label.new()
	_title.theme_type_variation = UiTheme.LEAD
	root.add_child(_title)

	# Outside the scroll, and that is the point. A new game's next twelve months
	# are empty -- the nearest dated event is sixteen months out -- so the one
	# thing worth reading sits under thirteen em dashes and needs a scroll to
	# find. This is the answer to "the president cannot see their own year"
	# reduced to one line that is always on screen.
	_next_up = Label.new()
	_next_up.theme_type_variation = UiTheme.CAPTION
	_next_up.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_next_up)

	# The grid above the scroll, its day list inside it: a list that changes height
	# moves nothing below (the form's rule further down).
	root.add_child(_grid)
	_grid.booked.connect(audience.booked.emit)
	_grid.cancel_requested.connect(_on_cancel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_body.add_child(_grid.day_list)

	root.add_child(HSeparator.new())
	root.add_child(audience)
	_build_form(root)

	_close_button = Button.new()
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func():
		hide()
		closed.emit()
	)
	root.add_child(_close_button)


## Four fixed rows whatever the kind is. The subject and act pickers are
## RELABELLED and repopulated rather than shown and hidden, because a form that
## changes height when a dropdown changes moves every control under it — and the
## Book button is the control under it.
func _build_form(root: VBoxContainer) -> void:
	var heading := Label.new()
	heading.theme_type_variation = UiTheme.HEADING
	heading.text = tr("BOOK AN APPOINTMENT")
	root.add_child(heading)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	root.add_child(grid)

	PanelKit.line(grid, tr("Kind"), PanelKit.Tone.PLAIN)
	_kind_pick = OptionButton.new()
	_kind_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for kind in K.KINDS.filter(func(k): return k != K.KIND_AUDIENCE):  # an audience is booked from its request
		_kind_pick.add_item(tr(String(KIND_LABEL.get(kind, kind))))
	_kind_pick.item_selected.connect(func(_i: int): _refresh_form())
	grid.add_child(_kind_pick)

	_subject_label = Label.new()
	_subject_label.text = tr("Partner")
	grid.add_child(_subject_label)
	_subject_pick = OptionButton.new()
	_subject_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subject_pick.item_selected.connect(func(_i: int): _refresh_acts())
	grid.add_child(_subject_pick)

	_act_label = Label.new()
	_act_label.text = tr("Act")
	grid.add_child(_act_label)
	_act_pick = OptionButton.new()
	_act_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A different act is a different journey: the travel note is the state
	# visit's, and no other act carries one.
	_act_pick.item_selected.connect(func(_i: int): _refresh_travel_note())
	grid.add_child(_act_pick)

	PanelKit.line(grid, tr("Date"), PanelKit.Tone.PLAIN)
	var when_row := HBoxContainer.new()
	when_row.add_theme_constant_override("separation", 8)
	_month_pick = OptionButton.new()
	_month_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The month choice bounds the day picker, and the connection is what keeps
	# the SpinBox honest: a 31 in a 30-day month is a booking the scheduler would
	# silently fire on the 31st of the wrong month. V2.4a closed the gap that had
	# existed since U6a.
	_month_pick.item_selected.connect(func(_i: int): _clamp_day_spin())
	when_row.add_child(_month_pick)
	_day_spin = SpinBox.new()
	_day_spin.min_value = 1
	_day_spin.max_value = 31
	_day_spin.value = 15
	_day_spin.value_changed.connect(func(_v: float): _refresh_travel_note())
	when_row.add_child(_day_spin)
	grid.add_child(when_row)

	# V2.4a: what the journey costs in days, said BEFORE the booking is made.
	# The number the ribbon will hatch is the number the player is agreeing to.
	_travel_note = Label.new()
	_travel_note.theme_type_variation = UiTheme.CAPTION
	_travel_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_travel_note)

	_book_button = PanelKit.sized(Button.new())
	_book_button.text = tr("Book it")
	_book_button.pressed.connect(_on_book)
	root.add_child(_book_button)

	_status = Label.new()
	_status.theme_type_variation = UiTheme.CAPTION
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_status)


## Docked in the workspace, whose way back to the map is the real close. Without this the
## panel's own Close hides the CONTENT while window_manager.open() only ever shows
## the FRAME, so the window reopens permanently empty -- docs/playability-audit.md
## V3. The four panels that already had this method never had the bug.
func hide_close_button() -> void:
	_close_button.hide()


func setup(state, loader) -> void:
	_state = state
	_loader = loader


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func _refresh() -> void:
	if _state.player() == null:
		return
	_refresh_strip()
	_refresh_months()
	_refresh_form()


## The grid's entries: the register and the fixed dates over the horizon, each
## named here (the grid adds what it reads itself). A booking still to come
## carries its cancel, except an audience: that day is the asker's, kept through
## Audiences, and the Diary's own cancel would leave the request booked for no day.
func _refresh_strip() -> void:
	for child in _body.get_children():
		if child != _grid.day_list:
			child.queue_free()

	# V5.3-0 (b): the month is the grid's own header and today is the title bar's.
	_title.text = tr("Diary")

	var rows := Calendar.upcoming(_state, K.BOOKING_HORIZON_MONTHS)
	_refresh_next_up(rows)

	var items := []
	for row in rows:
		var booking: bool = row.has("status")
		var live: bool = booking and String(row["status"]) == K.STATUS_BOOKED and String(row.get("kind", "")) != K.KIND_AUDIENCE
		items.append({"year": int(row["year"]), "month": int(row["month"]), "day": int(row.get("day", 1)),
			"text": _booking_text(row) if booking else _fixed_text(row), "mark": "booking" if booking else "fixed",
			"cancel": Calendar.verb_key(row) if live else ""})
	_grid.show_items(_state, _loader, items)

	_refresh_later()


## The nearest thing on the diary, whether or not it is inside the strip. Falls
## through to the `later` list precisely because that is where a new game's
## nearest event lives.
func _refresh_next_up(rows: Array) -> void:
	# Skips anything already resolved. The strip draws a kept appointment because
	# the diary's past is worth reading; "Next" is a different question, and the
	# first frame answered it with an act that had already happened.
	var soonest := []
	for row in rows:
		if row.has("status") and String(row["status"]) != K.STATUS_BOOKED:
			continue
		soonest.append(row)
	if soonest.is_empty():
		soonest = Calendar.later(_state, K.BOOKING_HORIZON_MONTHS, 1)
	if soonest.is_empty():
		_next_up.text = tr("Nothing ahead.")
		return

	var row: Dictionary = soonest[0]
	var what := _booking_text(row) if row.has("status") else _fixed_text(row)
	_next_up.text = tr("Next: %s — %s.") % [what, DateText.day_month_year(int(row.get("day", 1)), int(row["month"]), int(row["year"]))]


## The footer. Without it a new game's diary opens completely blank -- France's
## nearest dated event is sixteen months out, past the strip's own horizon, and
## cooldowns do not exist until the player has acted. Measured rather than
## guessed; see Calendar.later().
func _refresh_later() -> void:
	var rows := Calendar.later(_state, K.BOOKING_HORIZON_MONTHS, K.LATER_SHOWN)
	if rows.is_empty():
		return

	PanelKit.heading(_body, tr("LATER"))

	for row in rows:
		PanelKit.line(_body, "    %s — %s" % [DateText.month_year(int(row["month"]), int(row["year"])), _fixed_text(row)])


func _fixed_text(entry: Dictionary) -> String:
	var kind := String(entry.get("kind", ""))
	var label := tr(String(FIXED_LABEL.get(kind, kind)))
	var ref := String(entry.get("ref", ""))
	if ref.is_empty():
		return label
	if kind == K.FIXED_COOLDOWN:
		return "%s: %s" % [label, _cooldown_name(ref)]
	if kind == K.FIXED_PROJECT:
		return "%s: %s" % [label, Strings.noun("project-actions", _loader.project_actions, "project", "project_id", ref, "project_name", Projects.name_of(_loader, ref))]
	if kind == K.FIXED_REFERENDUM:
		return "%s: %s" % [label, _law_name(ref)]
	# The event register carries its own name, so this row needs no lookup at all --
	# the one kind on this list that does not.
	if kind == K.FIXED_EVENT:
		return "%s: %s" % [label, ref]
	return "%s: %s" % [label, ref]


## A diplomatic cooldown key is "action_id|TARGET"; a law cooldown key is a law
## id. Both are ids the content can name, and naming them here is what turns "in
## 14 months" on a panel the player has to be standing on into a date on a page.
func _cooldown_name(ref: String) -> String:
	if ref.contains("|"):
		var parts := ref.split("|")
		return tr("%s with %s") % [_action_name(parts[0]), _nation_name(parts[1])]
	return _law_name(ref)


func _booking_text(entry: Dictionary) -> String:
	match String(entry.get("kind", "")):
		K.KIND_DIPLOMATIC:
			# The person is a LABEL on the act, never part of its identity -- so
			# it is appended to the text and stays out of Calendar.verb_key().
			var who: String = _loader.person_name(String(entry.get("person_id", "")))
			var line := tr("%s with %s") % [
				_action_name(String(entry.get("action_id", ""))),
				_nation_name(String(entry.get("target_id", ""))),
			]
			if not who.is_empty():
				line = "%s — %s" % [line, who]
			# V2.4a: the block, not just the meeting. The row is anchored on the
			# meeting day but the act occupies the journey either side, and a
			# diary that hid the legs would disagree with the ribbon.
			return line + VisitBooking.away_text(entry)
		K.KIND_LAW:
			return tr("Propose %s") % _law_name(String(entry.get("law_id", "")))
		K.KIND_RESHUFFLE:
			return tr("%s to %s") % [
				PanelKit.Labels.portfolio(String(entry.get("portfolio", ""))),
				_party_name(String(entry.get("party_id", ""))),
			]
	return tr("Audience: %s") % _loader.person_name(String(entry.get("target_id", ""))) if String(entry.get("kind", "")) == K.KIND_AUDIENCE else String(entry.get("kind", ""))


## --- the form --------------------------------------------------------------

func _refresh_months() -> void:
	var selected := maxi(_month_pick.selected, 0)
	_month_pick.clear()
	for offset in range(K.BOOKING_HORIZON_MONTHS + 1):
		var when := _month_at(offset)
		_month_pick.add_item(DateText.month_year(int(when["month"]), int(when["year"])))
	_month_pick.selected = mini(selected, _month_pick.item_count - 1)


func _refresh_form() -> void:
	var kind := _selected_kind()
	var player_id: String = _state.player_nation_id
	var ns = _state.player()
	# V5.1-d1b2: a refresh keeps what the player picked. The form was rebuilt on
	# every refresh -- a day ticking with the Diary open -- and fell back to the
	# first partner and the first act, a visit filled in from Diplomacy included.
	var keep := _selected_subject()

	_subject_pick.clear()
	match kind:
		K.KIND_DIPLOMATIC:
			_subject_label.text = tr("Partner")
			_act_label.text = tr("Act")
			var ids: Array = _state.nations.keys()
			ids.sort()
			for id in ids:
				if String(id) != player_id:
					_subject_pick.add_item(_nation_name(String(id)))
					_subject_pick.set_item_metadata(_subject_pick.item_count - 1, String(id))
		K.KIND_LAW:
			_subject_label.text = tr("Chamber")
			_act_label.text = tr("Law")
			_subject_pick.add_item(tr("National Assembly"))
			_subject_pick.set_item_metadata(0, "")
		K.KIND_RESHUFFLE:
			_subject_label.text = tr("Party")
			_act_label.text = tr("Portfolio")
			for party_id in ns.coalition_party_ids:
				_subject_pick.add_item(_party_name(String(party_id)))
				_subject_pick.set_item_metadata(_subject_pick.item_count - 1, String(party_id))

	_subject_pick.disabled = _subject_pick.item_count <= 1
	_select_meta(_subject_pick, keep)
	_refresh_acts()


## The act list is what the SIM says is available, not the content's full
## catalogue: a verb the player could not fire today is a verb they should not be
## able to book, and re-deriving that rule here would be the second copy of it.
## One exception, shared with the Diplomacy row (VisitBooking.bookable_acts, QA on
## #76): a meeting the host refuses only until its free day -- the day check below
## refuses the days before it.
func _refresh_acts() -> void:
	var kind := _selected_kind()
	var ns = _state.player()
	var keep := String(_act_pick.get_item_metadata(_act_pick.selected)) if _act_pick.selected >= 0 else ""
	_act_pick.clear()

	match kind:
		K.KIND_DIPLOMATIC:
			var target := _selected_subject()
			if target.is_empty():
				return
			for action in VisitBooking.bookable_acts(_state, _loader, target):
				_act_pick.add_item(Strings.row_name("diplomatic-actions", action))
				_act_pick.set_item_metadata(_act_pick.item_count - 1, String(action.id))
		K.KIND_LAW:
			for law in Legislature.available(ns, _loader.laws):
				_act_pick.add_item(String(Strings.law_name(law)))
				_act_pick.set_item_metadata(_act_pick.item_count - 1, String(law.id))
		K.KIND_RESHUFFLE:
			var party_id := _selected_subject()
			for portfolio in CabinetK.PORTFOLIO_KEYS:
				if Cabinet.can_assign(ns, String(portfolio), party_id):
					_act_pick.add_item(PanelKit.Labels.portfolio(String(portfolio)))
					_act_pick.set_item_metadata(_act_pick.item_count - 1, String(portfolio))

	_select_meta(_act_pick, keep)
	_book_button.disabled = _act_pick.item_count == 0
	if _act_pick.item_count == 0:
		_status.text = tr("Nothing of that kind is available to book today.")
	_refresh_travel_note()


## The item whose metadata is `value`, selected; the selection stands when none is.
func _select_meta(pick: OptionButton, value: String) -> void:
	for i in pick.item_count:
		if String(pick.get_item_metadata(i)) == value:
			pick.selected = i


## The day picker never offers a day the chosen month does not have. Called on
## month selection and on refresh, because the horizon list rebuilds the months.
func _clamp_day_spin() -> void:
	var when := _month_at(maxi(_month_pick.selected, 0))
	_day_spin.max_value = Calendar.days_in_month(int(when["year"]), int(when["month"]))
	_day_spin.value = clampf(_day_spin.value, 1.0, float(_day_spin.max_value))
	_refresh_travel_note()


## V2.4a. Only the go-there verbs occupy travel days -- the ones whose action
## carries opens_meeting. The note states the block before it is made, in the
## ribbon's own terms, so the player agrees to the days they are about to see
## hatched. V5.1-d1b2: and a day that cannot be booked says why, Book held, so an
## invalid day reads as one before the press (VisitBooking.form_note).
func _refresh_travel_note() -> void:
	if _travel_note == null or _state == null:
		return
	var entry := _entry_from_form()
	var note: Dictionary = VisitBooking.form_note(_state, entry)
	_travel_note.text = String(note["travel"])
	# QA on #70: the refusal is the player's while choosing -- cleared when the day
	# turns valid, and never written over the booking just made ("Booked: ...").
	var refusal := String(note["refusal"]) if entry != _booked else ""
	if refusal != "" or _status.text == _refused:
		_status.text = refusal
	_refused = refusal
	_book_button.disabled = entry.is_empty() or String(note["refusal"]) != ""


## V5.1-d1b2 (G13, the author: "on ne peut pas choisir la date dans l'agenda"). A
## meeting verb pressed on the Diplomacy window opens this form on that visit --
## partner, act and travel filled in, the earliest open day offered -- and the
## player picks the day and books it here. Nothing is booked until they do.
func fill_booking(action_id: String, target_id: String, windows) -> void:
	windows.open("calendar")
	# Built now, not on the next frame's refresh: the month is picked below.
	_refresh_months()
	_kind_pick.selected = K.KINDS.find(K.KIND_DIPLOMATIC)
	_refresh_form()
	_select_meta(_subject_pick, target_id)
	_refresh_acts()
	_select_meta(_act_pick, action_id)
	var first := VisitBooking.earliest_entry(_state, _loader, _action_by_id(action_id), target_id)
	if not first.is_empty():
		_month_pick.selected = (int(first["year"]) * 12 + int(first["month"])) - (int(_state.year) * 12 + int(_state.month))
		_clamp_day_spin()
		_day_spin.value = int(first["day"])
	_status.text = ""
	_refresh_travel_note()


func _form_date() -> Dictionary:
	var when := _month_at(maxi(_month_pick.selected, 0))
	return {
		"year": int(when["year"]), "month": int(when["month"]),
		"day": int(_day_spin.value),
	}


func _selected_travel_days() -> int:
	if _selected_kind() != K.KIND_DIPLOMATIC or _act_pick.selected < 0:
		return 0
	var action = _action_by_id(String(_act_pick.get_item_metadata(_act_pick.selected)))
	if action == null or not action.opens_meeting:
		return 0
	return Diplomacy.travel_days(_loader, _state.player_nation_id, _selected_subject())


func _action_by_id(id: String):
	for action in _loader.diplomatic_actions:
		if String(action.id) == id:
			return action
	return null


func _on_book() -> void:
	var entry := _entry_from_form()
	if entry.is_empty():
		return
	# V5.2 b+ R4: a Reassign the limit will refuse on its day is refused now (Removal.why_not).
	var result: Dictionary = preload("res://src/ui/cabinet_verbs.gd").book(_state, entry)
	if bool(result["ok"]):
		_booked = entry
		_status.text = tr("Booked: %s, %s.") % [_booking_text(entry), DateText.day_month_year(int(entry["day"]), int(entry["month"]), int(entry["year"]))]
		mark_dirty()
		diary_changed.emit()
	else:
		# The refusal reason, printed rather than swallowed. A booking that
		# refuses silently is docs/trade-model.md's unread `refused_by_partner`,
		# which this project has now shipped twice.
		_status.text = tr("Refused: %s.") % Strings.t(String(result["error"]))  # i18n: row-ok the sim's reason, its English the msgid


func _on_cancel(key: String) -> void:
	if Calendar.cancel(_state, key):
		_status.text = tr("Cancelled.")
		mark_dirty()
		diary_changed.emit()


func _entry_from_form() -> Dictionary:
	if _act_pick.selected < 0: return {}
	var kind := _selected_kind()
	var when := _month_at(maxi(_month_pick.selected, 0))
	var day := int(_day_spin.value)
	var act := String(_act_pick.get_item_metadata(_act_pick.selected))
	var subject := _selected_subject()

	match kind:
		K.KIND_DIPLOMATIC:
			# The one verb that is literally "meet someone", so it is the one that
			# carries a person. A law is proposed to an assembly and a reshuffle
			# hands a department to a PARTY -- U6b's probe cut the minister bench,
			# so neither has a person to name, and "" says so rather than guessing
			# at a party leader who is not taking the job.
			#
			# V2.4a: travel_days is priced HERE, at booking, and stored on the
			# entry -- the scheduler stays a leaf and never re-derives it. Every
			# opens_meeting act travels; nothing else does.
			return Calendar.make_entry(
				kind, int(when["year"]), int(when["month"]), day, act, subject,
				"", "", "", _leader_person_id(subject), _selected_travel_days()
			)
		K.KIND_LAW:
			return Calendar.make_entry(
				kind, int(when["year"]), int(when["month"]), day, "", "", act
			)
		K.KIND_RESHUFFLE:
			return Calendar.make_entry(
				kind, int(when["year"]), int(when["month"]), day, "", "", "", act, subject
			)
	return {}


func _selected_kind() -> String:
	return String(K.KINDS[maxi(_kind_pick.selected, 0)])


func _selected_subject() -> String:
	return "" if _subject_pick.selected < 0 else String(_subject_pick.get_item_metadata(_subject_pick.selected))


func _month_at(offset: int) -> Dictionary:
	var total: int = _state.year * 12 + (_state.month - 1) + offset
	return {"year": total / 12, "month": total % 12 + 1}


## --- naming ----------------------------------------------------------------

func _nation_name(id: String) -> String:
	return String(_loader.nations[id].nation_name) if _loader.nations.has(id) else id


## Whom a state visit to `nation_id` actually meets. Resolved at BOOKING time
## rather than at arrival, so the diary shows the person the president intended
## to see -- a foreign government that changes in the meantime is a thing the
## player should be able to notice, not something the entry rewrites behind them.
func _leader_person_id(nation_id: String) -> String:
	var n = _loader.nations.get(nation_id)
	return String(n.leader_person_id) if n != null else ""


func _action_name(id: String) -> String:
	var action = _action_by_id(id)
	return Strings.row_name("diplomatic-actions", action) if action != null else id


func _law_name(id: String) -> String:
	return Strings.law_name(Bills.by_id(_loader, id), id)


func _party_name(id: String) -> String:
	for party in _loader.parties.get(_state.player_nation_id, []):
		if String(party.id) == id:
			return String(party.party_name)
	return id


## The control this panel exists to let the player press -- V2.1a's fold contract,
## declared here at V2.1b.
##
## Book it, and it is the panel's only verb: the per-entry Cancel buttons sit
## inside the strip's own scroll, which the frame cannot see past. Built once in
## _build_form() and alive for the session, so it is held rather than re-found --
## government_panel's shape. Disabled while nothing is bookable, and the contract
## reads the first ENABLED verb, so that month draws no mark.
func primary_action() -> Control:
	if _book_button != null and not _book_button.disabled:
		return _book_button
	return null
