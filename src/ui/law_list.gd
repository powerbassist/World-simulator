extends HBoxContainer

## The Legislature's catalogue -- V5.2-0b, the author's call "Une ligne par loi +
## détail" (docs/design/v5.2-legibility.md). Every proposable law is ONE row: its
## name, a theme chip, a majority chip, the forecast as a small bar with the
## majority marked, and two glyphs for what waits after the division (the second
## chamber, the court), their sentences on hover. Selecting a row opens the detail
## beside the list: the law's summary in full, never cut (the author's "Au clic,
## jamais coupés"), the forecast and the after-the-division sentences spelled out,
## and the verbs.
##
## The page used to be 105 expanded blocks -- 3 850 words and 210 buttons, the
## Senat and court sentence repeated on every row (1 219 words of it). The rows now
## carry no sentence at all; the one selected law carries its whole text.
##
## V5.3-0 (b), spec 3.3: the row's words were still 600 of the tab's 1 045 -- a
## theme word, "simple majority", "court stands", the chamber's name, repeated down
## 105 rows. The theme is an icon now (its word on hover), the threshold shows only
## when it is above half (as a figure), and the after-the-division cells show only
## what stands in the way: a blank cell is a law nothing stops, so the exceptions
## are what the eye finds going down a column. The words are named once, in the
## header row.
##
## The panel (law_panel.gd) still owns every command and every helper the old row
## used (`_forecast_text`, `_majority_phrase`, `_offer` and the verbs); this file
## only lays the catalogue out.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const ChartStack = preload("res://src/ui/chart_stack.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Num = preload("res://src/ui/num.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Government = preload("res://src/sim/government.gd")
const Chambers = preload("res://src/sim/chambers.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")
const Labels = preload("res://src/ui/labels.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const ReferendumK = preload("res://src/sim/referendum_constants.gd")
const LawColumns = preload("res://src/ui/law_columns.gd")

## The forecast's three columns: a for / against pair that reads as opposite, and
## a grey for the undecided between them (the dataviz method's diverging rule).
const FORECAST_COLORS := [Color("#3987e5"), Color(0.557, 0.596, 0.624), Color("#d95926")]
const BAR_WIDTH := 120.0
## A law's name never squeezes below this (px at 100 %); past it the name clips
## and its tooltip carries it whole.
const NAME_WIDTH := 190.0
## The row's fixed columns, px at text size 100 %: theme, threshold, the second
## chamber's glyph, the court's.
const COLUMNS := [28.0, 48.0, 72.0, 64.0]

var _panel
var _rows: VBoxContainer
var _header: HBoxContainer
var _detail: VBoxContainer
var _selected := ""
## V5.3-0 (2.4): the bloc whose liked laws the list shows, "" for every law. Set by
## the briefing's bloc Go and the Society panel's "what calms it" row; cleared by
## the filter's own button.
var bloc_filter := ""
## The last fill's inputs, so a selection rebuilds the detail alone (QA on #96: a
## click that rebuilt all 105 rows and their forecasts cost ~100 ms).
var _shown: Array = []
var _ns
var _party_list: Array = []


func _init(panel) -> void:
	_panel = panel
	name = "Laws"  # i18n: ok
	add_theme_constant_override("separation", 20)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The header sits above the list's scroll, so it stays while the rows move and
	# the rows container holds rows only.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.6
	add_child(left)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 10)
	left.add_child(_header)
	_rows = _column(left, 1.0)
	_rows.add_theme_constant_override("separation", 2)
	_detail = _column(self, 0.4)
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


## Opens a law's detail. The selection survives the panel's refreshes; a law that
## left the list hands the selection back to the first one.
func select(law_id: String) -> void:
	_selected = law_id
	# The filter's own row, when shown, sits above the law rows.
	var first := _rows.get_child_count() - _shown.size()
	for i in _shown.size():
		if first >= 0 and first + i < _rows.get_child_count():
			var pick: Button = _rows.get_child(first + i).get_child(0)
			pick.flat = _shown[i].id != law_id
			pick.set_pressed_no_signal(_shown[i].id == law_id)
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


func fill(ns, party_list: Array, laws: Array) -> void:
	for box in [_rows, _detail]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	if bloc_filter != "":
		laws = liked_by(laws, bloc_filter)
		_filter_row()
	if laws.is_empty():
		if not ns.tabled_bill.is_empty():
			PanelKit.line(_rows, tabled_text(ns), PanelKit.Tone.PLAIN)
		PanelKit.line(_rows, tr("No law is currently proposable."), PanelKit.Tone.PLAIN)
		return
	_shown = laws
	_ns = ns
	_party_list = party_list
	LawColumns.header(_header, ns, COLUMNS, NAME_WIDTH, BAR_WIDTH)
	var chosen = laws[0]
	for law in laws:
		if law.id == _selected:
			chosen = law
	_selected = chosen.id
	for law in laws:
		_rows.add_child(_row(ns, party_list, law, law == chosen))
	_build_detail(ns, party_list, chosen)


## The laws a bloc likes -- a positive authored price for it -- the most liked
## first (ties keep the list's own order). The authored price is what the
## briefing's preview reads too (briefing.gd), so the filter and the bill's own
## page cannot disagree.
static func liked_by(laws: Array, bloc: String) -> Array:
	var liked := laws.filter(func(law) -> bool: return _offset(law, bloc) > 0.0)
	var order := range(liked.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return _offset(liked[a], bloc) > _offset(liked[b], bloc) or (_offset(liked[a], bloc) == _offset(liked[b], bloc) and a < b))
	return order.map(func(i: int): return liked[i])


static func _offset(law, bloc: String) -> float:
	return float((law.effects.get("bloc_offset", {}) as Dictionary).get(bloc, 0.0))


func _filter_row() -> void:
	var row := PanelKit.buttons(_rows)
	var label := Label.new()
	label.text = tr("Laws %s like") % Labels.bloc(bloc_filter)
	label.theme_type_variation = UiTheme.HEADING
	row.add_child(label)
	var clear := PanelKit.sized(Button.new())
	clear.text = tr("Show every law")
	clear.pressed.connect(func() -> void:
		bloc_filter = ""
		_panel.mark_dirty())
	row.add_child(clear)


func _row(ns, party_list: Array, law, selected: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var pick := Button.new()
	pick.text = Strings.law_name(law)
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.flat = not selected
	pick.toggle_mode = true
	pick.button_pressed = selected
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.clip_text = true
	pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pick.custom_minimum_size.x = NAME_WIDTH * UiTheme.text_scale()
	pick.pressed.connect(select.bind(String(law.id)))
	row.add_child(pick)
	pick.tooltip_text = pick.text
	# Fixed widths, so every row's chips, bar and glyphs stand in the same columns
	# whatever the law's name -- a list read down a column, not row by row.
	row.add_child(LawColumns.theme_icon(String(law.theme), COLUMNS[0]))
	var needs := _chip(LawColumns.threshold(majority_share(ns, law)), UiTheme.CAPTION, COLUMNS[1])
	if needs.text != "":
		needs.tooltip_text = _panel._majority_phrase(ns, law)
		needs.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(needs)
	row.add_child(_forecast_bar(ns, party_list, law, BAR_WIDTH))
	var slots := {"upper": _chip("", UiTheme.CAPTION, COLUMNS[2]), "court": _chip("", UiTheme.CAPTION, COLUMNS[3])}
	for part in after_parts(ns, party_list, law, _panel.FORECAST_UNCERTAIN_BAND):
		if bool(part.get("quiet", false)):
			continue
		var glyph: Label = slots[part["slot"]]
		glyph.text = String(part["glyph"])
		glyph.theme_type_variation = String(part["tone"])
		glyph.tooltip_text = String(part["text"])
		glyph.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(slots["upper"])
	row.add_child(slots["court"])
	return row


func _chip(text: String, tone := UiTheme.CAPTION, width := 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = tone
	label.custom_minimum_size.x = width * UiTheme.text_scale()
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## For, undecided and against as one bar, the law's majority marked across it.
func _forecast_bar(ns, party_list: Array, law, width: float) -> Control:
	var counts: Dictionary = _panel.forecast_counts(ns, party_list, law, _panel.forecast_band(ns, law.id))
	var bar := ChartStack.new()
	bar.setup([
		{"label": tr("For"), "value": float(counts["yes"])},
		{"label": tr("Undecided"), "value": float(counts["undecided"])},
		{"label": tr("Against"), "value": float(counts["no"])},
	], {"marker": majority_share(ns, law), "colors": FORECAST_COLORS, "places": 0, "unit": tr(" seats")})
	bar.custom_minimum_size.x = width
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bar


## The share of the seats the line marks, read the way legislature.gd's division
## reads law.majority (QA on #96: a two-thirds ordinary law drew its line at half).
## A simple majority needs more yes than no; half the seats is where that is sure.
static func majority_share(ns, law) -> float:
	match String(law.majority):
		"two_thirds":
			return LK.TWO_THIRDS_MAJORITY_FRACTION
		"amendment":
			return float(LK.AMENDMENT_RULE_FRACTIONS.get(String(ns.amendment_rule), LK.ABSOLUTE_MAJORITY_FRACTION))
	return LK.ABSOLUTE_MAJORITY_FRACTION


## What waits after the Assembly: a glyph for the row and the sentence for the
## hover and the detail. The second chamber's is a FORECAST blurred like the
## Assembly's, because a chamber is people; the court's is not blurred, because a
## court is a RULE (docs/judiciary-model.md). Empty when nobody can stop the bill.
static func after_parts(ns, party_list: Array, law, band: float) -> Array:
	var parts: Array = []
	var chamber := String(ns.upper_chamber_name)
	var power: String = Chambers.power_over(ns, law)
	if power != ChambersK.VERDICT_NONE:
		var upper := Legislature.resolve_upper(ns, party_list, law)
		var margin: int = int(upper["yes_seats"]) - int(upper["no_seats"])
		if absi(margin) <= int(float(upper["seats_total"]) * band):
			parts.append({"slot": "upper", "glyph": "?", "tone": UiTheme.WARN_TEXT,
				"text": Strings.t("%s: too close to call.") % chamber})
		elif bool(upper["passed"]):
			parts.append({"slot": "upper", "glyph": "", "quiet": true, "tone": UiTheme.CAPTION,
				"text": Strings.t("%s: expected to agree.") % chamber})
		elif power == ChambersK.VERDICT_ABSOLUTE:
			parts.append({"slot": "upper", "glyph": Strings.t("blocks"), "tone": UiTheme.BAD_SMALL,
				"text": Strings.t("%s: expected to refuse, and it cannot be overridden.") % chamber})
		else:
			parts.append({"slot": "upper", "glyph": Strings.t("holds"), "tone": UiTheme.WARN_TEXT,
				"text": Strings.t("%s: expected to refuse, holding it %d months.") % [chamber, ChambersK.UPPER_HOLD_MONTHS]})
	if Judiciary.reviews(ns, law):
		var tolerance: float = Judiciary.tolerance(ns)
		if Judiciary.strikes_down(ns, law):
			parts.append({"slot": "court", "glyph": Strings.t("strikes"), "tone": UiTheme.BAD_SMALL,
				"text": Strings.t("The court would strike it down: it reaches %s against %s.") % [Num.f(law.reach, 2), Num.f(tolerance, 2)]})
		elif law.reach > 0.0:
			parts.append({"slot": "court", "glyph": "", "quiet": true, "tone": UiTheme.CAPTION,
				"text": Strings.t("The court would let it stand: it reaches %s against %s.") % [Num.f(law.reach, 2), Num.f(tolerance, 2)]})
	return parts


## The selected law in full: the name, its summary never cut, the forecast and what
## waits after the division spelled out, then the verbs.
func _build_detail(ns, party_list: Array, law) -> void:
	# V5.2 b+ R2: a bill before the Assembly is the page's first fact while it waits.
	if not ns.tabled_bill.is_empty():
		PanelKit.line(_detail, tabled_text(ns), PanelKit.Tone.PLAIN)
	var title := Label.new()
	title.text = Strings.law_name(law)
	title.theme_type_variation = UiTheme.LEAD
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail.add_child(title)
	PanelKit.line(_detail, "%s · %s" % [PanelKit.Labels.law_theme(law.theme), _panel._majority_phrase(ns, law)])
	# A system transition rewrites the whole constitution, not one field -- named
	# structurally, off the loaded template's display_name (docs/transition-model.md).
	if law.changes_system:
		var target_id: String = law.effects.get("institutional", {}).get("system_id", "")
		var target = _panel._loader.political_systems.get(target_id)
		PanelKit.line(_detail, tr("Rewrites the constitution to a %s.") % (target.display_name if target != null else target_id), PanelKit.Tone.PLAIN)
	PanelKit.rich(_detail, Strings.law_summary(law), PanelKit.Tone.PLAIN)
	_detail.add_child(_forecast_bar(ns, party_list, law, 0.0))
	PanelKit.line(_detail, tr("Forecast: %s") % _panel._forecast_text(ns, party_list, law), PanelKit.Tone.PLAIN)
	for part in after_parts(ns, party_list, law, _panel.FORECAST_UNCERTAIN_BAND):
		PanelKit.line(_detail, String(part["text"]), PanelKit.Tone.PLAIN)
	_verbs(ns, law)


func _verbs(ns, law) -> void:
	var row := PanelKit.buttons(_detail)
	var propose := Button.new()
	propose.name = "Propose"  # i18n: ok a node name
	propose.text = tr("Propose")
	propose.pressed.connect(_panel._on_propose.bind(law))
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
	# V5.2 b+ R2: one bill before the Assembly at a time -- propose() refuses
	# `already_tabled` -- so Propose and the referendum route are down with that
	# reason until it divides, never a press the sim refuses. Article 49.3 adopts
	# without a vote, is never tabled, and stays open on another bill (the parent's
	# call on #173): it answers only to its own cooldown -- but not on the tabled
	# bill itself, which propose() refuses.
	if not ns.tabled_bill.is_empty():
		var same := String(ns.tabled_bill.get("law_id", "")) == String(law.id)
		for verb in row.get_children():
			if verb.name == "Force" and not same:
				continue
			(verb as Button).disabled = true
			(verb as Button).tooltip_text = tabled_text(ns)
			if _panel._primary == verb:
				_panel._primary = null


## Which bill is before the Assembly and the day it divides (ns.tabled_bill; its
## numbers read back as floats after a load).
func tabled_text(ns) -> String:
	var id := String(ns.tabled_bill.get("law_id", ""))
	return tr("%s is before the Assembly: it divides on %s, and no other bill can be put before then.") % [
		Strings.law_name(_panel._find_law(id), id),
		DateText.day_month(int(ns.tabled_bill.get("vote_day", 1)), int(ns.tabled_bill.get("vote_month", 1)))]
