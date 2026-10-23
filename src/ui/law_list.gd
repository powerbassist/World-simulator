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
## The panel (law_panel.gd) still owns every command and every helper the old row
## used (`_forecast_text`, `_majority_phrase`, `_offer` and the verbs); this file
## only lays the catalogue out.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const ChartStack = preload("res://src/ui/chart_stack.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Government = preload("res://src/sim/government.gd")
const Chambers = preload("res://src/sim/chambers.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const ReferendumK = preload("res://src/sim/referendum_constants.gd")

## The forecast's three columns: a for / against pair that reads as opposite, and
## a grey for the undecided between them (the dataviz method's diverging rule).
const FORECAST_COLORS := [Color("#3987e5"), Color(0.557, 0.596, 0.624), Color("#d95926")]
const BAR_WIDTH := 120.0
## A law's name never squeezes below this (px at 100 %); past it the name clips
## and its tooltip carries it whole.
const NAME_WIDTH := 190.0
## The row's fixed columns, px at text size 100 %: theme, majority, the second
## chamber's glyph, the court's.
const COLUMNS := [80.0, 104.0, 118.0, 82.0]

var _panel
var _rows: VBoxContainer
var _detail: VBoxContainer
var _selected := ""
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
	_rows = _column(self, 0.6)
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
	for i in _rows.get_child_count():
		if i < _shown.size():
			var pick: Button = _rows.get_child(i).get_child(0)
			pick.flat = _shown[i].id != law_id
			pick.set_pressed_no_signal(_shown[i].id == law_id)
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	for law in _shown:
		if law.id == law_id:
			_panel._primary = null
			_build_detail(_ns, _party_list, law)


func fill(ns, party_list: Array, laws: Array) -> void:
	for box in [_rows, _detail]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	if laws.is_empty():
		PanelKit.line(_rows, tr("No law is currently proposable."), PanelKit.Tone.PLAIN)
		return
	_shown = laws
	_ns = ns
	_party_list = party_list
	var chosen = laws[0]
	for law in laws:
		if law.id == _selected:
			chosen = law
	_selected = chosen.id
	for law in laws:
		_rows.add_child(_row(ns, party_list, law, law == chosen))
	_build_detail(ns, party_list, chosen)


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
	row.add_child(_chip(PanelKit.Labels.law_theme(law.theme), UiTheme.CAPTION, COLUMNS[0]))
	row.add_child(_chip(_panel._majority_phrase(ns, law), UiTheme.CAPTION, COLUMNS[1]))
	row.add_child(_forecast_bar(ns, party_list, law, BAR_WIDTH))
	var slots := {"upper": _chip("", UiTheme.CAPTION, COLUMNS[2]), "court": _chip("", UiTheme.CAPTION, COLUMNS[3])}
	for part in after_parts(ns, party_list, law, _panel.FORECAST_UNCERTAIN_BAND):
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
			parts.append({"slot": "upper", "glyph": Strings.t("%s ?") % chamber, "tone": UiTheme.WARN_TEXT,
				"text": Strings.t("%s: too close to call.") % chamber})
		elif bool(upper["passed"]):
			parts.append({"slot": "upper", "glyph": Strings.t("%s agrees") % chamber, "tone": UiTheme.CAPTION,
				"text": Strings.t("%s: expected to agree.") % chamber})
		elif power == ChambersK.VERDICT_ABSOLUTE:
			parts.append({"slot": "upper", "glyph": Strings.t("%s blocks") % chamber, "tone": UiTheme.BAD_SMALL,
				"text": Strings.t("%s: expected to refuse, and it cannot be overridden.") % chamber})
		else:
			parts.append({"slot": "upper", "glyph": Strings.t("%s holds %d mo") % [chamber, ChambersK.UPPER_HOLD_MONTHS], "tone": UiTheme.WARN_TEXT,
				"text": Strings.t("%s: expected to refuse, holding it %d months.") % [chamber, ChambersK.UPPER_HOLD_MONTHS]})
	if Judiciary.reviews(ns, law):
		var tolerance: float = Judiciary.tolerance(ns)
		if Judiciary.strikes_down(ns, law):
			parts.append({"slot": "court", "glyph": Strings.t("court strikes"), "tone": UiTheme.BAD_SMALL,
				"text": Strings.t("The court would strike it down: it reaches %s against %s.") % [Num.f(law.reach, 2), Num.f(tolerance, 2)]})
		elif law.reach > 0.0:
			parts.append({"slot": "court", "glyph": Strings.t("court stands"), "tone": UiTheme.CAPTION,
				"text": Strings.t("The court would let it stand: it reaches %s against %s.") % [Num.f(law.reach, 2), Num.f(tolerance, 2)]})
	return parts


## The selected law in full: the name, its summary never cut, the forecast and what
## waits after the division spelled out, then the verbs.
func _build_detail(ns, party_list: Array, law) -> void:
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
	propose.text = tr("Propose")
	propose.pressed.connect(_panel._on_propose.bind(law))
	_panel._offer(propose)
	row.add_child(propose)
	# Article 49.3 exists only under a constitution that has it, and cannot force a
	# constitutional amendment through (docs/amendment-model.md).
	if ns.formation_method == "presidential_appointment" and not law.constitutional:
		var force := Button.new()
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
