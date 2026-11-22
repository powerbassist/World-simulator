extends HBoxContainer

## The Legislature's catalogue -- the Bills second pass, the author's pick "A : les rayons"
## (gate 3: G3-1 messy, G3-2 not in categories). Three columns: the SHELVES down the left
## (law_filters.gd: a search, one button per category with its count), the open shelf's laws as
## rows (law_row.gd: name, verb, summary, the vote at a glance, and a shut law's reason), and the
## selected law's sheet on the right (law_sheet.gd: the vote in full, what it does to each bloc,
## one verb). Every law of a shelf stands on it, open or shut -- a law the Assembly cannot take now
## says why on its row instead of vanishing (law_gate.gd), and another constitution's laws are not
## this nation's book, so they are left out.
##
## The panel (law_panel.gd) still owns every command and every helper the rows read
## (`forecast_counts`, `_majority_phrase`, `_offer` and the verbs); this file lays the catalogue out.

const VerbBlock = preload("res://src/ui/verb_block.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const ChartStack = preload("res://src/ui/chart_stack.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Labels = preload("res://src/ui/labels.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Government = preload("res://src/sim/government.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")
const ReferendumK = preload("res://src/sim/referendum_constants.gd")
const LawMagnitude = preload("res://src/core/law_magnitude.gd")
const LawGrade = preload("res://src/ui/law_grade.gd")
const LawGate = preload("res://src/sim/law_gate.gd")
const BillActions = preload("res://src/ui/bill_actions.gd")
const LawFilters = preload("res://src/ui/law_filters.gd")
const BlocFilter = preload("res://src/ui/law_bloc_filter.gd")
const LawRow = preload("res://src/ui/law_row.gd")
const LawSheet = preload("res://src/ui/law_sheet.gd")
const LawSeatsTip = preload("res://src/ui/law_seats_tip.gd")
const LawPath = preload("res://src/ui/law_path.gd")

## The forecast's three columns in a vote's tones (G3 decision 3, the author: green, red, grey
## everywhere): for and against read as opposite, the undecided grey between them.
const UNDECIDED := Color(0.557, 0.596, 0.624)
const FORECAST_COLORS := [UiTheme.GOOD, UNDECIDED, UiTheme.BAD]

## The list's sheet at text size 100 % (the picked picture at 1248: summaries on three lines).
const LIST_WIDTH := 372.0

var _panel
var _rows: VBoxContainer
var _head: Label
var _detail: VBoxContainer
var _selected := ""
## The shelves and the search beside the rows (law_filters.gd): built once, so the typed words stay.
var _filters: LawFilters
## V5.3-0 (2.4): the bloc whose liked laws the list shows, "" for every law. Set by
## the briefing's bloc Go and the Society panel's "what calms it" row; cleared by
## the filter's own button.
var bloc_filter := ""
## The last fill's inputs, so a selection rebuilds the detail alone (QA on #96: a
## click that rebuilt all 105 rows and their forecasts cost ~100 ms).
var _shown: Array = []
## Law id -> the gate's flag for every shown law ("" open), read once per fill.
var _why := {}
var _ns
var _party_list: Array = []
## The chip picked on each bill, by id: a display pick until Propose, kept through a refresh
## and the briefing, dropped with its game. See law_grade.gd.
var grades := {}
## The last address the page gave, for the line that answers the press (law_address.gd).
var aired := {}
## The bill whose address is unfolded, "" for none: only one strip stands at a time.
var address_open := ""
var _game = null


func _init(panel) -> void:
	_panel = panel
	name = "Laws"  # i18n: ok
	add_theme_constant_override("separation", UiTheme.GAP_PANE)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	# G3 S5 (Bills = C): two sheets -- the shelves and the open shelf's laws on the left, at the
	# picture's width, and the open law's sheet taking the rest.
	var middle: VBoxContainer = PanelKit.sheet(self)
	var left: Control = middle.get_parent()
	left.size_flags_horizontal = Control.SIZE_FILL
	left.custom_minimum_size.x = LIST_WIDTH * UiTheme.text_scale()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_filters = LawFilters.new(_panel.mark_dirty)
	# A shelf pressed under a bloc's Go is the player choosing the shelf: the Go's filter ends.
	_filters.shelf_pressed.connect(func() -> void: bloc_filter = "")
	middle.add_child(_filters)
	_head = Label.new()
	_head.theme_type_variation = UiTheme.MICRO
	middle.add_child(_head)
	_rows = _column(middle, 1.0)
	_rows.add_theme_constant_override("separation", 10)
	var right: VBoxContainer = PanelKit.sheet(self)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail = _column(right, 1.0)
	_detail.add_theme_constant_override("separation", 8)


func _column(parent: Control, ratio: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# EXPAND, so the tab page lets the panel fill the dock (tab_page.gd's
	# _scrolls_inside, QA #54's list that stopped two thirds down).
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = ratio
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func selected_id() -> String:
	return _selected


## The gate's flag for a shown law, "" when the Assembly may take it now.
func why(law) -> String:
	return String(_why.get(String(law.id), ""))


## The grade this bill goes to the Assembly at: the player's pick, on a bill that may take one.
## 1 on the referendum route, whose settlement reads the row (LawMagnitude.may_grade).
func grade(law, referendum := false) -> float:
	var picked := float(grades.get(String(law.id), 1.0))
	return picked if LawMagnitude.may_grade(law, picked, referendum) else 1.0


## Opens a law's detail. The selection survives the panel's refreshes; a law that
## left the list hands the selection back to the first open one.
func select(law_id: String) -> void:
	# A law on another shelf (a Go, the order paper, a test) opens its shelf first.
	if not _shown.any(func(law) -> bool: return String(law.id) == law_id):
		var law = _panel._find_law(law_id)
		var shelf: String = LawFilters.shelf_of(law, _panel._loader) if law != null else ""
		if shelf != "" and (shelf != _filters.category or _filters.query != ""):
			_filters.open_shelf(shelf)
			_selected = law_id
			_panel._refresh()
			return
	_selected = law_id
	for row in _rows.get_children():
		if row.has_meta("pick"):
			var pick: Button = row.get_meta("pick")
			pick.set_pressed_no_signal(String(row.get_meta("law_id")) == law_id)
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	for law in _shown:
		if law.id == law_id:
			_panel._primary = null
			_build_detail(_ns, _party_list, law)


## The filter is a Go's, not a standing setting: leaving the tab drops it, so the
## Legislature opened later from the sidebar lists every law.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		bloc_filter = ""


## `laws` is every law the nation's book holds, open or not: the gate sorts them here.
func fill(ns, party_list: Array, laws: Array) -> void:
	if not is_same(_game, _panel._state):
		_game = _panel._state
		grades.clear()
		aired.clear()
	for box in [_rows, _detail]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_why.clear()
	var book: Array = []
	for law in laws:
		# Another constitution's laws are not this nation's book, whatever else shuts them.
		if LawGate.constitution_allows(ns, law) and LawFilters.shelf_of(law, _panel._loader) != "":
			_why[String(law.id)] = LawGate.shut(ns, law)
			book.append(law)
	if bloc_filter != "":
		book = liked_by(book, bloc_filter)
		BlocFilter.row(self)
	# A bloc's Go reads every shelf: the laws it likes may stand on any of them.
	book = _filters.apply(book, _panel._loader, bloc_filter != "")
	_shown = book
	_ns = ns
	_party_list = party_list
	_head.text = _head_text(book)
	if book.is_empty():
		# The sheet is empty too, so the bill that waits is said here.
		if not ns.tabled_bill.is_empty():
			PanelKit.line(_rows, tabled_text(ns), PanelKit.Tone.PLAIN)
		PanelKit.line(_rows, _filters.empty_text(), PanelKit.Tone.PLAIN)
		return
	var chosen = null
	for law in book:
		if law.id == _selected or (chosen == null and why(law) == ""):
			chosen = law
	if chosen == null:
		chosen = book[0]
	_selected = chosen.id
	for law in book:
		_rows.add_child(LawRow.build(self, ns, party_list, law, law == chosen, why(law)))
	_build_detail(ns, party_list, chosen)


## "WORK · 13 LAWS · 3 SHUT": what the list holds, above it.
func _head_text(book: Array) -> String:
	var shut := book.filter(func(law) -> bool: return why(law) != "").size()
	var place: String = Labels.law_category(_filters.category) if _filters.query == "" and bloc_filter == "" else Strings.t("Found")
	var text := "%s · %s" % [place, Strings.tn("%d law", "%d laws", book.size()) % book.size()]
	if shut > 0:
		text += " · " + Strings.t("%d shut") % shut
	return text


## The laws a bloc likes, the most liked first (law_bloc_filter.gd).
static func liked_by(laws: Array, bloc: String) -> Array:
	return BlocFilter.liked_by(laws, bloc)


## The forecast's counts at the grade the sheet picked: the bar and the row's words read this one.
func counts_of(ns, party_list: Array, law) -> Dictionary:
	return _panel.forecast_counts(ns, party_list, LawGrade.read(ns, law, grade(law)), _panel.forecast_band(ns, law.id))


## For, undecided and against as one bar, the law's majority marked across it.
## `counts`: the caller's counts_of(), when it holds them already.
func _forecast_bar(ns, party_list: Array, law, width: float, counts := {}) -> Control:
	if counts.is_empty():
		counts = counts_of(ns, party_list, law)
	var bar := ChartStack.new()
	bar.setup([
		{"label": tr("For"), "value": float(counts["yes"])},
		{"label": tr("Undecided"), "value": float(counts["undecided"])},
		{"label": tr("Against"), "value": float(counts["no"])},
	], {"marker": majority_share(ns, law), "colors": FORECAST_COLORS, "places": 0, "unit": tr(" seats"), "bar": 8.0})
	bar.hover = LawSeatsTip.build.bind(_panel, counts)
	bar.custom_minimum_size.x = width
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bar


## The share of the seats the line marks (law_path.gd reads law.majority as the division does).
static func majority_share(ns, law) -> float:
	return LawPath.majority_share(ns, law)


## The selected law in full (law_sheet.gd lays it out).
func _build_detail(ns, party_list: Array, law) -> void:
	LawSheet.build(self, _detail, ns, party_list, law)


## The sheet's verb row, returned so the address and the polls put their folds in it (G3 S5).
func _verbs(ns, law) -> Control:
	var row := PanelKit.buttons(_detail)
	VerbBlock.tag(row)  # a right click on the law's row lights it
	var propose := Button.new()
	propose.name = "Propose"  # i18n: ok a node name
	# The Bills second pass: the verb names the month the bill divides in (the slot's month).
	propose.text = tr("Propose for %s") % DateText.month_long(int(_panel._state.month))
	propose.pressed.connect(_panel.run_proposal.bind(law))
	# V5.3-0 RF3: Propose acts on the law, and on the bloc the list is filtered for.
	ActsOn.tag(propose, [law.id] + ([bloc_filter] if bloc_filter != "" else []))
	_panel._offer(propose)
	row.add_child(propose)
	# Article 49.3 exists only under a constitution that has it, and cannot force a
	# constitutional amendment through (docs/amendment-model.md).
	if ns.formation_method == "presidential_appointment" and not law.constitutional:
		var force := Button.new()
		force.name = "Force"  # i18n: ok a node name
		force.text = tr("Force (49.3)")
		force.disabled = not Government.can_force(ns)
		force.tooltip_text = tr("Cooldown: available again in %d months.") % ns.force_cooldown_months if force.disabled \
			else tr("Adopt without a vote. The assembly may censure the government instead.")
		force.pressed.connect(_panel._on_force.bind(law))
		_panel._offer(force)
		row.add_child(force)
	# Route B, only where the constitution has one and only for an entrenched change;
	# Legislature.can_put_to_referendum() is the single authority.
	if Legislature.can_put_to_referendum(ns, law):
		var ref := Button.new()
		ref.text = tr("Referendum")
		ref.tooltip_text = tr("Pass it by an ordinary majority here, then put it to the country in %d months. Winning is a mandate and losing is a rebuke, and it cannot be called off for free.") % ReferendumK.REFERENDUM_DELAY_MONTHS
		ref.pressed.connect(_panel._on_referendum.bind(law))
		_panel._offer(ref)
		row.add_child(ref)
	# V5.2 b+ R2 and V5.3 screen 4: one bill before the Assembly at a time, and a queue of three
	# behind it. The table (bill_verbs.gd) holds Propose and the referendum route down with its
	# reason, and offers the queue; Article 49.3 answers only to its own cooldown (#173).
	# A shut law (law_gate.gd) is a cell of that table too: every verb down with its reason.
	BillActions.verbs(self, row, ns, law)
	# G3 S5: one filled verb, the one that puts this law on the order paper (Propose, or the queue's
	# press while the slot is held); the others stay plain.
	for verb in row.get_children():
		if verb.visible and (verb.name == "Propose" or verb.name == BillActions.QUEUE):
			verb.theme_type_variation = UiTheme.PRIMARY
			row.move_child(verb, 0)  # the picture's order: the filled verb first
			break
	return row


## Which bill is before the Assembly and the day it divides (ns.tabled_bill; its
## numbers read back as floats after a load).
func tabled_text(ns) -> String:
	var id := String(ns.tabled_bill.get("law_id", ""))
	return tr("%s is before the Assembly: it divides on %s, and no other bill can be put before then.") % [
		Strings.law_name(_panel._find_law(id), id),
		DateText.day_long(int(ns.tabled_bill.get("vote_day", 1)), int(ns.tabled_bill.get("vote_month", 1)))]
