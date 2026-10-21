extends PanelContainer

## The nation, partitioned -- V2.2b's Region panel, landing under Economy on
## docs/panel-system.md §16's rule that a cluster is the domain of the decision.
## V2.5 wrote the quantities that row named -- regional GDP, unemployment and a
## sector mix -- so this panel now reads them: output per head against the national
## average, a live unemployment rate and each region's dominant sector, beside the
## population shares and the named payroll the panel opened with. The payroll is no
## longer the one live number here: share of output, output per head and
## unemployment all move with the clock, because national GDP is the sum of these
## regions and each grows at its own mix's rate.
##
## Still read-only and buttonless, people_panel.gd's design rather than a
## compromise: §5 shipped a STATISTIC and no verb, so there is still nothing here a
## button could do, and a panel with no interactive control cannot repeat the fold
## nation_panel.gd paid for twice. The map reaches the CITY, not the region -- a
## cross is a point and a region is an area, and this session shipped no region
## hover -- so the drawer entry is a region's only way in and it opens on the
## player's own nation.
##
## Authored order IS the ranking: the importer writes regions descending by
## population, so a panel that prints file order prints a league table and
## nothing has to sort.

signal closed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Companies = preload("res://src/sim/companies.gd")
const Region = preload("res://src/core/region.gd")
const Regions = preload("res://src/sim/regions.gd")
const Migration = preload("res://src/sim/migration.gd")
const Num = preload("res://src/ui/num.gd")

var _state
var _loader
var _dirty := true
var _scroll: ScrollContainer
var _pin_pending := false
var _pin_frames := 0

var _title: Label
var _body: VBoxContainer
var _close_button: Button


func _ready() -> void:
	# 560 for the five-column ledger -- the partition columns are narrow but the
	# region name column is not ("Provence-Alpes-Côte d'Azur"), and a ledger that
	# cannot hold its widest row wraps it, which a grid does to no row's benefit.
	# 640 is two-thirds of the ~886 band and Italy's 21 regions plus the partition
	# rows fit under it; the scroll carries anything taller.
	custom_minimum_size = Vector2(560, 640)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_title = Label.new()
	_title.theme_type_variation = UiTheme.LEAD
	root.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_scroll = scroll

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)

	_close_button = Button.new()
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


## Docked-tab mode -- see budget_panel.gd's hide_close_button() for why.
func hide_close_button() -> void:
	_close_button.hide()


func _process(_delta: float) -> void:
	if _pin_pending:
		_pin_pending = false
		_pin_frames = 2
	if _pin_frames > 0 and _scroll != null:
		# Two frames after the refresh, because the freed-and-rebuilt body's
		# minimum size lands a frame after the rebuild that a setup flag
		# triggered -- and a scroll set before that rebuild is undone by it.
		_pin_frames -= 1
		if _pin_frames == 0:
			_scroll.scroll_vertical = int(_body.size.y)
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


## The screenshot tool's route to the league table -- companies_panel.gd's
## standing-flag shape: the rebuild a setup flag triggers would undo a scroll set
## before it, so the pin is applied after that rebuild has laid out.
func scroll_to_bottom() -> void:
	_pin_pending = true
	_dirty = true


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return
	var nation = _loader.nations.get(ns.id)
	if nation == null:
		return

	_title.text = tr("The regions of %s") % nation.nation_name

	for child in _body.get_children():
		child.queue_free()

	var regions: Array = _loader.regions.get(ns.id, [])
	_build_partition(ns, regions)
	_build_table(ns, regions)


## The partition the whole register rests on, now in BOTH quantities: how much of
## the country's people and how much of its output the register names, and what
## the remainders are. Both residuals are derived rather than stored, so these rows
## cannot disagree with the table below them.
func _build_partition(ns, regions: Array) -> void:
	PanelKit.heading(_body, tr("The partition"))
	var named := 0.0
	for region in regions:
		named += Migration.region_share(ns, region.id)
	# maxf, and it is not decoration now that V2.6a's rate is live: the named shares
	# are a live partition the flow moves every month, so a nation whose register
	# names all of itself can land a hair the wrong side of 1.0 on float accumulation
	# and print "-0.0%" at a player. The floor was here before the helper this
	# replaced was inlined, and it comes back with the rate that made it load-bearing.
	var residual: float = maxf(0.0, 1.0 - named)
	PanelKit.row(_body, tr("Regions"), str(regions.size()))
	PanelKit.row(_body, tr("Named share of the population"), "%s%%" % Num.f((named * 100.0), 1))
	PanelKit.row(_body, tr("Unnamed — extra-regio and overseas"), "%s%%" % Num.f((residual * 100.0), 1))
	var named_gdp: float = 0.0
	for region in regions:
		named_gdp += region.gdp_share
	PanelKit.row(_body, tr("Named share of output"), "%s%%" % Num.f((named_gdp * 100.0), 1))
	PanelKit.row(_body, tr("Unnamed output — extra-regio"), "%s%%" % Num.f((Region.national_gdp_residual(regions) * 100.0), 1))

	# V2.7. NEVER SILENT, on the rule V1.7c set for the electoral method: every
	# region has a position on the graph, where an absent route is a fact most
	# constitutions simply do not have. Read off the edges rather than through
	# Network.adjacency() because the line also says which links are water.
	var land := 0
	var sea := 0
	var degrees: Dictionary = {}
	for region in regions:
		degrees[region.id] = 0
	for edge in (_state.region_graph.get("edges", []) as Array):
		var a := String(edge[0])
		var b := String(edge[1])
		var touch := degrees.has(a)
		var touch_b := degrees.has(b)
		if not touch and not touch_b:
			continue
		if String(edge[3]) == "sea":
			sea += 1
		else:
			land += 1
		if touch:
			degrees[a] = int(degrees[a]) + 1
		if touch_b:
			degrees[b] = int(degrees[b]) + 1
	var least := ""
	var least_degree := 1 << 30
	for region in regions:
		if int(degrees[region.id]) < least_degree:
			least_degree = int(degrees[region.id])
			least = region.region_name
	PanelKit.line(_body, tr("On the transport graph: %d land links and %d sea links touch these regions; %s is the least connected, with %d.") % [land, sea, least, least_degree])


## The league table. The payroll column is the register's one live quantity:
## named jobs read through Companies.headcount_in_city over the region's cities,
## so a subsidy that moves a firm's hiring moves this table. Zero is a TRUE zero
## for seven of the ten nations -- the game names no employer there -- and
## printing it rather than an em dash is the honest direction: PanelKit's em dash
## means a figure is absent, and this one is present and empty.
func _build_table(ns, regions: Array) -> void:
	PanelKit.heading(_body, tr("By share of the population"))
	# V2.7. One read per refresh; the row loop below passes it to every region's
	# unemployment figure. The argument is required -- regions.gd's own rule.
	var access: Dictionary = Regions.accessibility_for(ns, regions, _state.region_graph)
	var sites: Dictionary = _state.project_sited_pct.get(ns.id, {})
	var rows: Array = []
	for region in regions:
		var jobs := 0.0
		for city in region.cities:
			jobs += Companies.headcount_in_city(ns, _loader, city.id)
		# Output per head against the national average is the column nobody authored:
		# `gdp_share / share` is two partitions of one nation divided by each other,
		# and it is why carrying both is worth more than carrying either.
		var index: float = Regions.gdp_per_head_index(ns, regions, region.id, Migration.region_share(ns, region.id))
		rows.append([
			region.region_name,
			"%s%%" % Num.f((Regions.share_of(ns, region.id) * 100.0), 1),
			PanelKit.pop_text(float(ns.population) * Migration.region_share(ns, region.id)),
			"x%s" % Num.f(index, 2),
			"x%s" % Num.f(float(access.get(region.id, 1.0)), 2),
			"%s%%" % Num.f(Regions.unemployment_pct(ns, regions, region.id, access, sites), 1),
			_dominant(region),
			PanelKit.pop_text(jobs) if jobs > 0.0 else "0",
		])
	PanelKit.ledger(_body, rows)
	PanelKit.line(_body, tr("Columns: share of output · people · output per head against the national average · accessibility against the national average · unemployment · dominant sector · named jobs."))
	PanelKit.line(_body, tr("National GDP is the sum of these regions. A region grows at the national rate plus what its own sector mix is worth, and those differences cancel across the country — so a region's mix moves its share and never the level."))
	PanelKit.line(_body, tr("Position moves output too: what a region makes, times how far its market reaches — also cancelling across the country, also never the level."))


## The mix, as one word. The three shares are on the region and the panel has one
## column, so what is printed is the largest -- and services wins almost everywhere,
## which is the honest answer rather than a flaw in the label.
func _dominant(region) -> String:
	var best: String = ""
	var best_share: float = -1.0
	for key in region.sector_mix.keys():
		var v: float = float(region.sector_mix[key])
		if v > best_share:
			best_share = v
			best = key
	return "%s %.0f%%" % [best.capitalize(), best_share * 100.0]
