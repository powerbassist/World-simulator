extends VBoxContainer

## The charts a panel carries -- V5.2-0a. One node per panel, added once in the
## panel's _ready with the panel itself and a kind; it reads the panel's `_state`
## and `_loader` and rebuilds only when what it draws changed (a new month of
## history, a committed budget, a new assembly), so a panel gains its charts in one
## line and its own refresh is untouched. The panel's rows stay below as the
## charts' table twin: every drawn value is still there in figures.
##
## What each kind draws, all from GameState.history (chart_series.gd) or the
## current state, never a series computed here:
##   OVERVIEW  the term in four small multiples: approval (the polls), growth,
##             deficit, unemployment;
##   ECONOMY   growth, unemployment and debt over the last ten years of history; then
##             revenue against spending over the term (V5.2 b+, moved from the Budget
##             tab with it at Finances slice 5);
##   SOCIETY   approval over the term (the polls), then each bloc's; then what the
##             country is thinking about, as bars (V5.2 b+);
##   SEATS     the assembly by party, with the majority marked;
## V5.2 b+ added the last three at the author's gate b: the charts "sont plus
## digestes que des chiffres bruts seul, et pourrai s'etendre a d'autres panneaux".

const ChartKit = preload("res://src/ui/chart_kit.gd")
const ChartSeries = preload("res://src/ui/chart_series.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")
const PartyChip = preload("res://src/ui/party_chip.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const ElectionK = preload("res://src/sim/election_constants.gd")
const Opinion = preload("res://src/sim/opinion.gd")

enum { OVERVIEW, ECONOMY, SOCIETY, SEATS }

## Ten years: a decade of monthly history is as far back as a reader compares.
const ECONOMY_MONTHS := 120
## The narrowest approval range drawn, in points: polls move a few points a month
## and carry +-3 of noise, so a tighter scale draws the noise as a story.
const POLL_SPAN := 20.0

var _panel: Control
var _kind := OVERVIEW
var _signature := ""


func _init(panel: Control, kind: int) -> void:
	_panel = panel
	_kind = kind
	add_theme_constant_override("separation", 10)
	name = "Charts"  # i18n: ok


## The drawing now, for a caller that shows it outside the tree (a tooltip is built, shown and freed).
func draw_now() -> void:
	_build(_panel.get("_state"))


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var state = _panel.get("_state")
	if state == null or state.player() == null:
		return
	var sig := _signature_of(state)
	if sig == _signature:
		return
	_signature = sig
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build(state)


## What the drawing depends on, cheap to take every visible frame. The game itself
## leads it: a load swaps the panel's state for another game (main.gd keeps the
## panels), and a save of the same length at the same date would otherwise keep the
## discarded game's lines up until a month passed (QA on #93).
func _signature_of(state) -> String:
	var ns = state.player()
	var game := "%d/" % state.get_instance_id()
	match _kind:
		SEATS:
			return game + str(ns.seats_by_party)
	return game + "%d/%d" % [state.history.size(), int(ns.months_in_term)]


func _build(state) -> void:
	match _kind:
		OVERVIEW:
			var term := ChartSeries.term_window(state)
			var grid := _grid(4)
			_line(grid, Strings.t("Approval (polls)"), ChartSeries.polled(term, "overall_approval_pct", "overall"), term, {"unit": "%", "min_span": POLL_SPAN})
			_line(grid, Strings.t("Growth"), ChartSeries.values(term, "growth_annual_pct"), term, {"unit": "%", "zero": true})
			_line(grid, Strings.t("Deficit"), ChartSeries.values(term, "deficit_pct_gdp"), term, {"unit": Strings.t("% of GDP"), "zero": true})
			_line(grid, Strings.t("Unemployment"), ChartSeries.values(term, "unemployment_pct"), term, {"unit": "%"})
		ECONOMY:
			var years := ChartSeries.last(state, ECONOMY_MONTHS)
			var grid := _grid(3)
			_line(grid, Strings.t("Growth"), ChartSeries.values(years, "growth_annual_pct"), years, {"unit": "%", "zero": true})
			_line(grid, Strings.t("Unemployment"), ChartSeries.values(years, "unemployment_pct"), years, {"unit": "%"})
			_line(grid, Strings.t("Debt"), ChartSeries.values(years, "debt_to_gdp_pct"), years, {"unit": Strings.t("% of GDP")})
			# The gap between the two lines is the deficit, month by month: the one
			# figure the strip prints, drawn as what makes it.
			var term := ChartSeries.term_window(state)
			var box := ChartKit.line(self, Strings.t("Revenue and spending, % of GDP"), [
				{"label": Strings.t("Revenue"), "values": ChartSeries.values(term, "total_revenue_pct_gdp")},
				{"label": Strings.t("Spending"), "values": ChartSeries.values(term, "total_spending_pct_gdp")}],
				ChartSeries.months(term), {"unit": "%"})
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		SOCIETY:
			var term := ChartSeries.term_window(state)
			_line(self, Strings.t("Approval (polls)"), ChartSeries.polled(term, "overall_approval_pct", "overall"), term, {"unit": "%", "min_span": POLL_SPAN})
			# One shared scale for the six, or the small multiples cannot be compared.
			var lines := {}
			var lo := INF
			var hi := -INF
			for bloc in K.BLOC_KEYS:
				lines[bloc] = ChartSeries.polled(term, "bloc_approval", bloc)
				for v in lines[bloc]:
					lo = minf(lo, v)
					hi = maxf(hi, v)
			var shared := ChartStyle.nice_range(lo, hi, false, POLL_SPAN) if lo <= hi else Vector2(0, 100)
			var grid := _grid(3)
			for bloc in K.BLOC_KEYS:
				_line(grid, Labels.bloc(bloc), lines[bloc], term, {"unit": "%", "fixed": shared})
			# The panel's issues list as bars: the same issues, the same order.
			var count := int(_panel.get_script().get_script_constant_map().get("TOP_ISSUE_COUNT", 4))
			var issues: Array = []
			for entry in Opinion.top_issues(state.player(), count):
				issues.append({"label": Strings.t(String(K.ISSUE_LABEL[entry[0]])), "value": float(entry[1]) * 100.0})
			ChartKit.bars(self, Strings.t("What the country is thinking about, %"), issues, {"unit": "%"})
		SEATS:
			var ns = state.player()
			var seated := _seat_parts(ns, _panel.get("_loader"))
			ChartKit.hemicycle(self, Strings.t("By party; the line is a majority"), seated[0],
				{"marker": 0.5, "unit": Strings.t(" seats"), "places": 0, "colors": seated[1]})


func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	add_child(grid)
	return grid


func _line(parent: Control, title: String, values: PackedFloat64Array, entries: Array, opts: Dictionary) -> void:
	var box := ChartKit.line(parent, title, [{"label": title, "values": values}], ChartSeries.months(entries), opts)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Parties in the data's order, a party without seats included, so a party keeps
## its colour whatever its seats (a segment of zero keeps its slot).
## [parts, colours]: seated left to right as an assembly sits (V5.2 b+ R6) -- the
## economic axis plus half the social one, so a nationalist right sits right of the
## centre right -- each party in its own colour slot (its order in the data).
func _seat_parts(ns, loader) -> Array:
	var parties: Array = loader.parties.get(ns.id, [])
	var order := range(parties.size())
	order.sort_custom(func(a: int, b: int) -> bool: return _seat_x(parties[a]) < _seat_x(parties[b]) or (_seat_x(parties[a]) == _seat_x(parties[b]) and a < b))
	var parts: Array = []
	var colors: Array = []
	for i in order:
		parts.append({"label": String(parties[i].party_name), "value": float(ns.seats_by_party.get(parties[i].id, 0))})
		colors.append(PartyChip.colour_at(i))  # one rule with the people's party chip
	return [parts, colors]


static func _seat_x(party) -> float:
	var pos: Dictionary = ElectionK.SLOT_POSITION.get(String(party.ideology_slot), {"economic": 0.0, "social": 0.0})
	return float(pos["economic"]) + float(pos["social"]) / 2.0
