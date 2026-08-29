extends PanelContainer

## The nation, partitioned -- V2.2b's Region panel, landing under Economy on
## docs/panel-system.md §16's rule that a cluster is the domain of the decision:
## the row names its future content "regional GDP, unemployment and sector mix",
## and §5 is the block that writes those quantities. Until then this is the
## register's readout -- shares of the population, the cities each region names,
## and the named payroll, which is the one live number here and the one thing
## making a region more than a name and a share.
##
## Read-only and buttonless, people_panel.gd's design rather than a compromise:
## there is no verb on a region until §5 gives it one, and a panel with no
## interactive control cannot repeat the fold nation_panel.gd paid for twice.
## The map reaches the CITY, not the region -- a cross is a point and a region
## is an area, and this session shipped no region hover -- so the drawer entry
## is a region's only way in and it opens on the player's own nation.
##
## Authored order IS the ranking: the importer writes regions descending by
## population, so a panel that prints file order prints a league table and
## nothing has to sort.

signal closed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Companies = preload("res://src/sim/companies.gd")
const Region = preload("res://src/core/region.gd")

var _state
var _loader
var _dirty := true

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

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)

	_close_button = Button.new()
	_close_button.text = "Close"
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
	if not _dirty or not visible or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return
	var nation = _loader.nations.get(ns.id)
	if nation == null:
		return

	_title.text = "The regions of %s" % nation.nation_name

	for child in _body.get_children():
		child.queue_free()

	var regions: Array = _loader.regions.get(ns.id, [])
	_build_partition(ns, regions)
	_build_table(ns, regions)


## The partition the whole register rests on, in three rows: how much of the
## country the register names, and what the remainder is. The residual is
## derived rather than stored, so these two rows cannot disagree with the table
## below them.
func _build_partition(ns, regions: Array) -> void:
	PanelKit.heading(_body, "The partition")
	var named := 0.0
	for region in regions:
		named += region.share
	var residual: float = Region.national_residual(regions)
	PanelKit.row(_body, "Regions", str(regions.size()))
	PanelKit.row(_body, "Named share of the population", "%.1f%%" % (named * 100.0))
	PanelKit.row(_body, "Unnamed — extra-regio and overseas", "%.1f%%" % (residual * 100.0))


## The league table. The payroll column is the register's one live quantity:
## named jobs read through Companies.headcount_in_city over the region's cities,
## so a subsidy that moves a firm's hiring moves this table. Zero is a TRUE zero
## for seven of the ten nations -- the game names no employer there -- and
## printing it rather than an em dash is the honest direction: PanelKit's em dash
## means a figure is absent, and this one is present and empty.
func _build_table(ns, regions: Array) -> void:
	PanelKit.heading(_body, "By share of the population")
	var rows: Array = []
	for region in regions:
		var jobs := 0.0
		for city in region.cities:
			jobs += Companies.headcount_in_city(ns, _loader, city.id)
		rows.append([
			region.region_name,
			"%.1f%%" % (region.share * 100.0),
			PanelKit.pop_text(float(ns.population) * region.share),
			str(region.cities.size()),
			PanelKit.pop_text(jobs) if jobs > 0.0 else "0",
		])
	PanelKit.ledger(_body, rows)
	PanelKit.line(_body, "Columns: share of the national population · people · named cities · named jobs. A regional economy is not modelled yet.")
