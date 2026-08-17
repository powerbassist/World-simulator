extends PanelContainer

## The Economy tab -- U3. Rewritten from the U2 placeholder, which listed nine
## figures at equal weight in the order they happened to occur to whoever wrote
## it, sectors alphabetically last.
##
## The hierarchy here is: one headline (how big the economy is and whether it is
## running above or below where it should be), then the two things the player's
## budget actually moves -- labour and the public finances -- side by side with
## their six-month trend, then where output comes from, as shares rather than as
## three absolute euro figures the player cannot weigh against each other.
##
## The output gap is the figure the old flat list never stated: growth alone does
## not say whether an economy is recovering or overheating, and it is the number
## Economy's own model is built around (docs/economy-model.md).

const Economy = preload("res://src/sim/economy.gd")
const Demography = preload("res://src/sim/demography.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")
const Trends = preload("res://src/ui/trends.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## Widest sector bar, in pixels. The bar is a share of GDP drawn to scale; the
## figure beside it is the one to read precisely.
const BAR_WIDTH := 180

var _state
var _loader
var _title: Label
var _headline: Label
var _headline_note: Label
var _labour: VBoxContainer
var _finances: VBoxContainer
var _sectors: VBoxContainer
var _dirty := true


func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_title = Label.new()
	_title.text = "ECONOMY"
	_title.theme_type_variation = UiTheme.HEADING
	root.add_child(_title)

	_headline = Label.new()
	_headline.theme_type_variation = UiTheme.LEAD
	root.add_child(_headline)

	_headline_note = Label.new()
	_headline_note.theme_type_variation = UiTheme.CAPTION
	_headline_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_headline_note)

	root.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	root.add_child(columns)

	_labour = _build_column(columns, "LABOUR")
	_finances = _build_column(columns, "PUBLIC FINANCES")

	root.add_child(HSeparator.new())

	var sectors_heading := Label.new()
	sectors_heading.text = "OUTPUT BY SECTOR"
	sectors_heading.theme_type_variation = UiTheme.HEADING
	root.add_child(sectors_heading)

	_sectors = VBoxContainer.new()
	_sectors.add_theme_constant_override("separation", 4)
	root.add_child(_sectors)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)


func _build_column(parent: Control, heading: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)

	var label := Label.new()
	label.text = heading
	label.theme_type_variation = UiTheme.HEADING
	col.add_child(label)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	col.add_child(body)
	return body


## Takes the loader only for the nation's name -- the state carries an id, and
## a tab heading reading "ECONOMY — FRA" is a database row, not a heading.
func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if not _dirty or not visible or _state == null:
		return
	_dirty = false
	_refresh()


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return

	var nation = _loader.nations.get(ns.id) if _loader != null else null
	_title.text = "ECONOMY — %s" % (nation.nation_name if nation != null else ns.id)

	for body in [_labour, _finances, _sectors]:
		for child in body.get_children():
			child.queue_free()

	_headline.text = "EUR %.0fbn   %+.2f%%" % [ns.gdp_eur_bn, ns.growth_annual_pct]
	_headline_note.text = "Annual growth against a trend of %+.2f%%. %s" % [
		ns.trend_annual_pct, _gap_sentence(Economy.output_gap_pct(ns))
	]

	_figure(_labour, "%.1f%%" % ns.unemployment_pct, "unemployment")
	_caption(_labour, "Structural floor %.1f%%." % ns.structural_unemployment_pct)
	_trend(_labour, "unemployment_pct")
	_caption(_labour, "Population %.1fM." % (ns.population / 1_000_000.0))

	# V1.5b. Here rather than under GOVERNMENT on the overview beside the delivery
	# lines, and the split is deliberate: a delivery figure is a fact about the
	# GOVERNMENT -- how much of what it spends arrives -- and an age structure is a
	# fact about the COUNTRY, which is what this column already reports. It sits under
	# the population caption it is a decomposition of.
	#
	# Leads with the ratio and states the drift beside it, which is _fill_society()'s
	# lesson one panel over: a level alone is a number with no units the player can
	# act on. Unlike the two lines there this one is NEVER silent -- every nation has
	# an age structure from the first frame, where a delivery factor of exactly 1.0 is
	# a game in which nothing has happened yet.
	_caption(_labour, "%.0f retired per 100 of working age, %+.0f since the start." % [
		100.0 * Demography.dependency_ratio(ns),
		100.0 * (Demography.dependency_ratio(ns) - Demography.start_dependency_ratio(ns)),
	])

	# V1.5c, beside the dependency ratio for the reason the comment above gives: a
	# grievance is a fact about the COUNTRY, so it belongs in the column that reports
	# the country rather than under GOVERNMENT with the delivery lines.
	#
	# SILENT WHEN THERE IS NOTHING TO SAY, which is the delivery lines' rule rather than
	# the dependency ratio's -- the stock reads exactly 0.0 in every game where nobody
	# is angry, and a permanent "unrest 0" row says nothing in most runs. Once it speaks
	# it names the threshold too, because a grievance figure with no bar beside it is a
	# number with no units the player can act on: _fill_defence()'s finding, third time.
	if ns.unrest_pct > 0.05:
		var striking: bool = ns.unrest_pct >= UnrestK.UNREST_THRESHOLD_PCT
		_caption(_labour, "Unrest %.0f of 100. %s" % [
			ns.unrest_pct,
			# Deliberately does not name the act. The label is the message card's --
			# `protest` at this intensity, `strike` higher up -- and the screenshot pass
			# caught the panel saying "the unions are out" beside a card reading
			# DEMONSTRATIONS. This line owns the LEVEL; the card owns the event.
			"Organised action at %.0f." % UnrestK.UNREST_THRESHOLD_PCT if not striking
				else "Past the point where the unions organise.",
		], UiTheme.BAD_TEXT if striking else "")

	_figure(_finances, "%+.1f%%" % -ns.deficit_pct_gdp, "deficit, share of GDP")
	_trend(_finances, "deficit_pct_gdp")
	_caption(_finances, "Debt %.1f%% of GDP." % ns.debt_to_gdp_pct())
	_trend(_finances, "debt_to_gdp_pct")
	_caption(_finances, "Debt service costs %.1f%% of GDP." % ns.debt_service_pct_gdp)

	_fill_sectors(ns)


## A gap under a tenth of a point is not "above potential by 0.0%" -- rounding a
## real quantity to zero and then still asserting a direction reads as a bug.
func _gap_sentence(gap: float) -> String:
	if absf(gap) < 0.05:
		return "Output is running at potential."
	return "Output is %s potential by %.1f%%." % ["above" if gap > 0.0 else "below", absf(gap)]


## Largest first, as a share, because the question a sector list answers is
## "what is this economy made of" -- an alphabetical list of absolute figures
## answers nothing without the division done in the player's head.
func _fill_sectors(ns) -> void:
	var total := 0.0
	for value in ns.sector_output.values():
		total += float(value)
	if total <= 0.0:
		return

	var ordered: Array = ns.sector_output.keys()
	ordered.sort_custom(func(a, b): return float(ns.sector_output[a]) > float(ns.sector_output[b]))

	for sector in ordered:
		var value := float(ns.sector_output[sector])
		var share := 100.0 * value / total

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_sectors.add_child(row)

		var name_label := Label.new()
		name_label.text = String(sector).capitalize()
		name_label.custom_minimum_size.x = 120
		row.add_child(name_label)

		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(BAR_WIDTH, 12)
		bar.max_value = 100.0
		bar.value = share
		bar.show_percentage = false
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)

		var share_label := Label.new()
		share_label.text = "%.0f%%" % share
		share_label.custom_minimum_size.x = 50
		share_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(share_label)

		var value_label := Label.new()
		value_label.text = "EUR %.0fbn" % value
		value_label.theme_type_variation = UiTheme.CAPTION
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)


# --- small builders ---------------------------------------------------------

func _figure(body: VBoxContainer, value: String, caption: String) -> void:
	var label := Label.new()
	label.text = value
	label.theme_type_variation = UiTheme.FIGURE
	body.add_child(label)

	var sub := Label.new()
	sub.text = caption
	sub.theme_type_variation = UiTheme.FIGURE_LABEL
	body.add_child(sub)


## V1.5c added the optional variation, for the one caption on this panel that carries a
## state the player is losing to. Defaults to CAPTION, so every existing call is
## unchanged; the colour comes from ui_theme.gd through theme_type_variation, never from
## an override, which is what tests/test_ui_theme.gd enforces.
func _caption(body: VBoxContainer, text: String, variation: String = "") -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = UiTheme.CAPTION if variation == "" else variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_child(label)


## One watched figure's movement over the standard window, coloured by whether
## that direction is good news for this particular figure -- the sign alone does
## not say, which is why Trends.movements() carries the convention rather than
## each panel re-deciding it.
func _trend(body: VBoxContainer, key: String) -> void:
	for row in Trends.movements(_state):
		if row["key"] != key:
			continue
		# Nothing at all, rather than an em dash or a "no data yet" line. Overview's
		# Moving column can print a dash because it sits in a labelled grid; here
		# each trend is a sentence under a figure, and three copies of "no
		# comparison yet" on a first-month screen reads as a broken panel.
		if is_nan(row["severity"]):
			return
		var label := Label.new()
		label.text = "%s over %d months." % [Trends.change_text(float(row["change"])), Trends.TREND_MONTHS]
		label.theme_type_variation = UiTheme.BAD_TEXT if float(row["severity"]) > 0.0 else UiTheme.GOOD_TEXT
		body.add_child(label)
		return
