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
## V2.6b1, for site_report() alone -- the grievance has a place now, and the panel
## derives it live rather than storing one. Nothing is written back.
const Unrest = preload("res://src/sim/unrest.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Credit = preload("res://src/sim/credit.gd")
const EconomyK = preload("res://src/sim/economy_constants.gd")
const Regions = preload("res://src/sim/regions.gd")
const Energy = preload("res://src/sim/energy.gd")
const Migration = preload("res://src/sim/migration.gd")
const Trends = preload("res://src/ui/trends.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")

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
	_title.text = tr("ECONOMY")
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

	_labour = PanelKit.section(columns, tr("LABOUR"))
	_finances = PanelKit.section(columns, tr("PUBLIC FINANCES"))

	root.add_child(HSeparator.new())

	var sectors_heading := Label.new()
	sectors_heading.text = tr("OUTPUT BY SECTOR")
	sectors_heading.theme_type_variation = UiTheme.HEADING
	root.add_child(sectors_heading)

	_sectors = VBoxContainer.new()
	_sectors.add_theme_constant_override("separation", 4)
	root.add_child(_sectors)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)
## Takes the loader only for the nation's name -- the state carries an id, and
## a tab heading reading "ECONOMY — FRA" is a database row, not a heading.
func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return

	var nation = _loader.nations.get(ns.id) if _loader != null else null
	_title.text = tr("ECONOMY — %s") % (nation.nation_name if nation != null else ns.id)

	for body in [_labour, _finances, _sectors]:
		for child in body.get_children():
			child.queue_free()

	_headline.text = tr("EUR %.0fbn   %+.2f%%") % [ns.gdp_eur_bn, ns.growth_annual_pct]
	_headline_note.text = tr("Annual growth against a trend of %+.2f%%. %s") % [
		ns.trend_annual_pct, _gap_sentence(Economy.output_gap_pct(ns))
	]

	PanelKit.figure(_labour, "%.1f%%" % ns.unemployment_pct, tr("unemployment"))
	PanelKit.line(_labour, tr("Structural floor %.1f%%.") % ns.structural_unemployment_pct)
	_trend(_labour, "unemployment_pct")
	PanelKit.line(_labour, tr("Population %.1fM.") % (ns.population / 1_000_000.0))

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
	PanelKit.line(_labour, tr("%.0f retired per 100 of working age, %+.0f since the start.") % [
		100.0 * Demography.dependency_ratio(ns),
		100.0 * (Demography.dependency_ratio(ns) - Demography.start_dependency_ratio(ns)),
	])

	# V1.6b, beside the dependency ratio and for its reason rather than the unrest
	# line's: prices are a fact about the COUNTRY, and this is the column that reports
	# the country. It sits under the labour rows deliberately, because the unemployment
	# gap two lines above is what drives it -- the panel reads in the order the model
	# computes in, which is the one thing that makes a Phillips curve legible without a
	# sentence of explanation.
	#
	# NEVER SILENT, which is the dependency ratio's rule and not the delivery lines'.
	# Every nation has an inflation rate from the first frame -- France's anchor is
	# 1.75 -- so a line that appeared only once it moved would be hiding the level the
	# deviation is measured against. Leads with the level and states the drift beside
	# it, _fill_society()'s lesson: a level alone is a number with no units the player
	# can act on.
	#
	# TWO DECIMALS ON THE DEVIATION AND ONE ON THE LEVEL, and the asymmetry is the
	# screenshot pass's finding rather than a preference. The first version used the
	# dependency ratio's %+.1f by symmetry and printed "+0.0 since the start" against a
	# live, correct, moved figure -- because tools/inflation_probe.gd table (a) puts the
	# whole REACHABLE deviation at 0.145 points, so one decimal can express exactly two
	# values of it. A format copied from a neighbouring row is a format chosen for a
	# quantity an order of magnitude larger.
	PanelKit.line(_labour, tr("Inflation %.1f%%, %+.2f since the start.") % [
		ns.inflation_pct, Inflation.inflation_deviation(ns),
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
		PanelKit.line(_labour, tr("Unrest %.0f of 100. %s") % [
			ns.unrest_pct,
			# Deliberately does not name the act. The label is the message card's --
			# `protest` at this intensity, `strike` higher up -- and the screenshot pass
			# caught the panel saying "the unions are out" beside a card reading
			# DEMONSTRATIONS. This line owns the LEVEL; the card owns the event.
			tr("Organised action at %.0f.") % UnrestK.UNREST_THRESHOLD_PCT if not striking
				else tr("Past the point where the unions organise."),
		], PanelKit.Tone.BAD if striking else PanelKit.Tone.DIM)

		# V2.6b1. WHERE the grievance is, on its own line and only once there is a
		# place to name. Derived every refresh from the live shares rather than stored,
		# so it moves when the model moves it -- and for Britain and Luxembourg, whose
		# registers cannot single a region out, it is SILENT rather than printing a
		# confident "nowhere". V1.6d's rule: a missing figure is an em dash or nothing,
		# never a default dressed as an answer.
		var site_list: Array = _state.regions.get(ns.id, [])
		var site: Dictionary = Unrest.site_report(ns, site_list,
			Regions.accessibility_for(ns, site_list, _state.region_graph),
			_state.project_sited_pct.get(ns.id, {}))
		if String(site["region_name"]) != "":
			PanelKit.line(_labour, tr("Concentrated in %s%s.") % [
				String(site["region_name"]),
				(" (%s)" % String(site["city_name"])) if String(site["city_name"]) != "" else "",
			], PanelKit.Tone.DIM)

	PanelKit.figure(_finances, "%+.1f%%" % -ns.deficit_pct_gdp, tr("deficit, share of GDP"))
	_trend(_finances, "deficit_pct_gdp")
	PanelKit.line(_finances, tr("Debt %.1f%% of GDP.") % ns.debt_to_gdp_pct())
	_trend(_finances, "debt_to_gdp_pct")
	PanelKit.line(_finances, tr("Debt service costs %.1f%% of GDP.") % ns.debt_service_pct_gdp)

	# V2.8, under the debt-service line because both are standing claims on the same
	# budget. NEVER SILENT, the inflation line's rule rather than the unrest one's:
	# every country in Europe imports energy -- Luxembourg's measured figure is over
	# 100 -- so a line that disappeared at zero would only ever appear when something
	# was wrong, the opposite of a readout. Leads with the level and states the drift
	# beside it, and the drift gets two decimals because the whole reachable move is
	# points of a percentage: V1.6b's own format bug, one asymmetry that repeats.
	PanelKit.line(_finances, tr("Imports %.1f%% of its energy, %+.2f since the start.") % [
		ns.import_dependency_pct, Energy.dependency_deviation_pct(ns, _loader),
	])

	# V1.6c, directly under the debt-service line because that is the line it explains.
	# The panel reads in the order the model computes in, which is the discipline the
	# inflation caption above established one session ago.
	#
	# NEVER SILENT, which is the dependency ratio's and inflation's rule rather than the
	# delivery lines'. Every game has a borrowing rate from the first frame -- it is
	# exactly economy_constants.DEBT_REAL_RATE_PCT -- so a line that appeared only once
	# it moved would hide the level the spread is measured against, which is the whole
	# claim the number makes.
	#
	# LEADS WITH THE RATING, and that is what the rating is FOR. The yield moves in
	# fractions of a point and the spread smaller still, so a letter changing is the
	# event a player can actually see: docs/society-model.md's *a level alone is a number
	# with no units the player can act on*, read a fifth time.
	#
	# TWO DECIMALS ON THE SPREAD AND ON THE YIELD, chosen against the reachable range in
	# tools/credit_probe.gd table (a) rather than copied from the neighbouring row --
	# which is V1.6b's own screenshot bug, one session old. `managed` runs at a spread of
	# +0.33 over fourteen years, so one decimal would print two distinct values of the
	# figure a well-governed run ever shows.
	#
	# Red once the rating has fallen out of the band the anchor sits in, which is the
	# unrest caption's rule: the threshold is named by the model rather than by a number
	# invented for the panel.
	var rating: String = Credit.rating(ns)
	PanelKit.line(_finances, tr("Rated %s. Borrowing at %.2f%%, %+.2f on the anchor.") % [
		rating, Credit.yield_pct(ns), Credit.spread_pct(ns),
	], PanelKit.Tone.BAD if rating != _anchor_rating() else PanelKit.Tone.DIM)

	_fill_sectors(ns)


## The letter every game opens on, because every game opens at the anchor. Computed
## rather than written down, so a content edit to RATING_BANDS cannot leave this panel
## calling a normal rating a downgrade.
func _anchor_rating() -> String:
	return Credit.rating_for(EconomyK.DEBT_REAL_RATE_PCT)


## A gap under a tenth of a point is not "above potential by 0.0%" -- rounding a
## real quantity to zero and then still asserting a direction reads as a bug.
func _gap_sentence(gap: float) -> String:
	if absf(gap) < 0.05:
		return tr("Output is running at potential.")
	return tr("Output is %s potential by %.1f%%.") % [tr("above") if gap > 0.0 else tr("below"), absf(gap)]


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
		value_label.text = tr("EUR %.0fbn") % value
		value_label.theme_type_variation = UiTheme.CAPTION
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)

	# V2.5. Never silent: every nation has regions and a spread, so a line that hid at
	# zero would be a line that never appeared. It leads with the ratio because that is
	# the quantity that MOVES -- the levels are on the Region panel.
	var regions: Array = _loader.regions.get(ns.id, [])
	if not regions.is_empty():
		var lo: float = 999.0
		var hi: float = 0.0
		var richest: String = ""
		var poorest: String = ""
		for region in regions:
			var v: float = Regions.gdp_per_head_index(ns, regions, region.id, Migration.region_share(ns, region.id))
			if v <= 0.0:
				continue
			if v < lo:
				lo = v
				poorest = region.region_name
			if v > hi:
				hi = v
				richest = region.region_name
		if hi > 0.0:
			PanelKit.line(_sectors, tr("Regions: %s produces x%.2f the national output per head, %s x%.2f.") % [
				richest, hi, poorest, lo,
			])
		# V2.7. Position, on the same x-scale as the line above, and never silent
		# for a different reason than it: the accessibility spread is non-zero from
		# month 1 in all ten, so this line names the quantity itself rather than a
		# stance that would hide at zero.
		var access: Dictionary = Regions.accessibility_for(ns, regions, _state.region_graph)
		var a_lo := INF
		var a_hi := -INF
		var best_connected := ""
		var worst_connected := ""
		for region in regions:
			var v: float = float(access.get(region.id, 1.0))
			if v < a_lo:
				a_lo = v
				worst_connected = region.region_name
			if v > a_hi:
				a_hi = v
				best_connected = region.region_name
		if a_hi > 0.0 and best_connected != "":
			PanelKit.line(_sectors, tr("Reach: %s sits x%.2f the national market, %s x%.2f.") % [
				best_connected, a_hi, worst_connected, a_lo,
			])


# --- small builders ---------------------------------------------------------
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
		PanelKit.line(
			body,
			tr("%s over %d months.") % [Trends.change_text(float(row["change"])), Trends.TREND_MONTHS],
			PanelKit.Tone.BAD if float(row["severity"]) > 0.0 else PanelKit.Tone.GOOD,
		)
		return
