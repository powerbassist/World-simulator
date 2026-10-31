extends PanelContainer

## Territory -- V5.3-0 (b), the closing gate's R13 ("territory panel is useless ?")
## and the author's call 6, "Un onglet + où tombent tes décisions". The Regions and
## Cities tabs were two read-only tables of eight columns (502 words) that the map
## already drew. Now ONE tab says what the player can act on:
##   - the regions ranked by people, each row its output per head against the
##     nation's, its unemployment, and how many of the player's sites stand there;
##   - a click on a region centres the map there and opens it: its figures, the
##     player's sites each with a Go to the tab whose verbs act on it
##     (territory_sites.gd), and its three largest cities;
##   - a city (one of those, or a cross clicked on the map, any nation's) opens in
##     place (territory_city.gd), with a way back.
## The partition rows and the network line (what share of the nation the register
## names, the land and sea links) stay one click away, folded, not cut.
##
## No per-region history exists (state.history is national), so the spec's "the
## term's change" arrow is not drawn: a UI snapshot would die on a load.

signal closed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const PanelCharts = preload("res://src/ui/panel_charts.gd")
const Labels = preload("res://src/ui/labels.gd")
const Companies = preload("res://src/sim/companies.gd")
const Region = preload("res://src/core/region.gd")
const Regions = preload("res://src/sim/regions.gd")
const Migration = preload("res://src/sim/migration.gd")
const Num = preload("res://src/ui/num.gd")
const TerritorySites = preload("res://src/ui/territory_sites.gd")
const TerritoryCity = preload("res://src/ui/territory_city.gd")

## The figure columns, px at text size 100 %: per head, jobless, sites.
const COLUMNS := [86.0, 76.0, 56.0]
const CITIES_SHOWN := 3

var _state
var _loader
var _dirty := true
var _scroll: ScrollContainer
var _pin_pending := false
var _pin_frames := 0
## main's window manager and map, for a site's Go and a region's centring (attach()).
var _windows
var _map
## "" is the region list; a city id is that city's detail.
var _city_id := ""
## The region opened under its row, "" for none.
var _open_region := ""
var _about_open := false

var _title: Label
var _body: VBoxContainer
var _back_button: Button
var _close_button: Button


func _ready() -> void:
	custom_minimum_size = Vector2(560, 640)
	var root := PanelKit.padded(self, 16, 10)
	_title = Label.new()
	_title.theme_type_variation = UiTheme.LEAD
	root.add_child(_title)
	# V5.2 b+: each region's share of the output, drawn (panel_charts.gd).
	root.add_child(PanelCharts.new(self, PanelCharts.REGIONS))

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	_scroll.add_child(_body)

	_back_button = PanelKit.sized(Button.new())
	_back_button.text = tr("All regions")
	_back_button.pressed.connect(func(): _city_id = ""; _dirty = true)
	_back_button.hide()
	root.add_child(_back_button)
	_close_button = Button.new()
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


func attach(windows, map) -> void:
	_windows = windows
	_map = map


## Docked-tab mode -- see budget_panel.gd's hide_close_button() for why.
func hide_close_button() -> void:
	_close_button.hide()


## The map's route: any nation's city answers. show_city() before the window
## opens, so the content settles before the window sizes itself around it.
func show_city(city_id: String) -> void:
	_city_id = city_id
	_dirty = true


func _process(_delta: float) -> void:
	if _pin_pending:
		_pin_pending = false
		_pin_frames = 2
	if _pin_frames > 0 and _scroll != null:
		# Two frames after the refresh: the rebuilt body's minimum size lands a
		# frame after the rebuild, and a scroll set before it is undone by it.
		_pin_frames -= 1
		if _pin_frames == 0:
			_scroll.scroll_vertical = int(_body.size.y)
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


## The screenshot tool's route to the bottom of the list.
func scroll_to_bottom() -> void:
	_pin_pending = true
	_dirty = true


func _refresh() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var found: Dictionary = TerritoryCity.find(_loader, _city_id) if _city_id != "" else {}
	var title := TerritoryCity.build(_body, _state, _loader, found) if not found.is_empty() else ""
	if title != "":
		_title.text = title
		_back_button.show()
		return
	_city_id = ""
	_back_button.hide()
	var ns = _state.player()
	var nation = _loader.nations.get(ns.id) if ns != null else null
	if nation == null:
		return
	_title.text = tr("The regions of %s") % nation.nation_name
	var regions: Array = _loader.regions.get(ns.id, [])
	var access: Dictionary = Regions.accessibility_for(ns, regions, _state.region_graph)
	var sites: Dictionary = TerritorySites.by_region(ns, _loader)
	_body.add_child(_column_heads())
	for region in regions:
		_body.add_child(_region_line(ns, regions, region, access, (sites.get(region.id, []) as Array).size()))
		if region.id == _open_region:
			_body.add_child(_opened(ns, regions, region, access, sites.get(region.id, [])))
	_about(ns, regions)


func _column_heads() -> HBoxContainer:
	var row := HBoxContainer.new()
	var name := _cell(tr("Region"), UiTheme.MICRO, 0.0)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var tips := [tr("Output per head, against the nation's."), tr("Unemployment."),
		tr("Your public works, plants and campaign sites here.")]
	var words := [tr("Per head"), tr("Jobless"), tr("Sites")]
	for i in COLUMNS.size():
		var cell := _cell(words[i], UiTheme.MICRO, COLUMNS[i])
		cell.tooltip_text = tips[i]
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(cell)
	return row


## One region: its name a button that opens it, then its figures. The output per
## head is said against the nation's (+62 %, -19 %), so the laggards read as minus
## signs down one column. A region with no site of the player's shows a blank.
func _region_line(ns, regions: Array, region, access: Dictionary, site_count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var pick := Button.new()
	pick.text = String(region.region_name)
	pick.theme_type_variation = UiTheme.SUBROW_BUTTON
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.toggle_mode = true
	pick.button_pressed = region.id == _open_region
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.clip_text = true
	pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pick.tooltip_text = pick.text
	pick.pressed.connect(_pick.bind(String(region.id)))
	row.add_child(pick)
	var index: float = Regions.gdp_per_head_index(ns, regions, region.id, Migration.region_share(ns, region.id))
	var sited: Dictionary = _state.project_sited_pct.get(ns.id, {})
	row.add_child(_cell("%s%%" % Num.fs((index - 1.0) * 100.0, 0), "", COLUMNS[0]))
	row.add_child(_cell("%s%%" % Num.f(Regions.unemployment_pct(ns, regions, region.id, access, sited), 1), "", COLUMNS[1]))
	row.add_child(_cell(str(site_count) if site_count > 0 else "", "", COLUMNS[2]))
	return row


## A region opened: the map centred on its largest city; its figures; the player's
## sites there, each with a Go; its largest cities, each opening in place.
func _pick(region_id: String) -> void:
	_open_region = "" if _open_region == region_id else region_id
	if _open_region != "" and _map != null:
		var city = _largest_city(region_id)
		if city != null:
			_map.center_on_lonlat(city.lonlat.x, city.lonlat.y)
	_dirty = true


func _opened(ns, regions: Array, region, access: Dictionary, sites: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var jobs := 0.0
	for city in region.cities:
		jobs += Companies.headcount_in_city(ns, _loader, city.id)
	PanelKit.row(box, tr("People"), PanelKit.pop_text(float(ns.population) * Migration.region_share(ns, region.id)))
	PanelKit.row(box, tr("Share of the output"), "%s%%" % Num.f(Regions.share_of(ns, region.id) * 100.0, 1))
	PanelKit.row(box, tr("Main sector"), _dominant(region))
	PanelKit.row(box, tr("Named jobs"), PanelKit.pop_text(jobs) if jobs > 0.0 else "0")
	PanelKit.row(box, tr("Reach"), "%s×" % Num.f(float(access.get(region.id, 1.0)), 2))
	if not sites.is_empty():
		PanelKit.heading(box, tr("Your sites here"))
		for site in sites:
			var row := PanelKit.buttons(box)
			PanelKit.plain_line(row, String(site["label"]), PanelKit.Tone.PLAIN)  # i18n: row-ok built through Strings in territory_sites.gd
			var go := PanelKit.sized(Button.new())
			go.text = tr("Go")
			go.disabled = _windows == null
			go.pressed.connect(func() -> void: _windows.open(String(site["tab"])))
			row.add_child(go)
	PanelKit.heading(box, tr("Largest cities"))
	var row := PanelKit.buttons(box)
	for city in _cities_by_size(ns, region).slice(0, CITIES_SHOWN):
		var open := PanelKit.sized(Button.new())
		open.text = String(city.city_name)
		open.pressed.connect(show_city.bind(String(city.id)))
		row.add_child(open)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.add_child(box)
	return margin


## The partition and the network, folded: what the register names of the nation's
## people and output, and how the regions link. Both residuals are derived, so
## these rows cannot disagree with the table above.
func _about(ns, regions: Array) -> void:
	var toggle := PanelKit.sized(Button.new())
	toggle.text = tr("About these figures")
	toggle.toggle_mode = true
	toggle.button_pressed = _about_open
	toggle.pressed.connect(func() -> void: _about_open = not _about_open; _dirty = true)
	PanelKit.buttons(_body).add_child(toggle)
	if not _about_open:
		return
	var named := 0.0
	var named_gdp := 0.0
	for region in regions:
		named += Migration.region_share(ns, region.id)
		named_gdp += region.gdp_share
	# maxf: the named shares are a live partition the flow moves every month, and
	# a nation whose register names all of itself can land a hair past 1.0.
	PanelKit.row(_body, tr("Named share of the population"), "%s%%" % Num.f(named * 100.0, 1))
	PanelKit.row(_body, tr("Unnamed — extra-regio and overseas"), "%s%%" % Num.f(maxf(0.0, 1.0 - named) * 100.0, 1))
	PanelKit.row(_body, tr("Named share of output"), "%s%%" % Num.f(named_gdp * 100.0, 1))
	PanelKit.row(_body, tr("Unnamed output — extra-regio"), "%s%%" % Num.f(Region.national_gdp_residual(regions) * 100.0, 1))
	# V2.7, never silent: every region has a place on the graph, read off the edges
	# because the line also says which links are water.
	var land := 0
	var sea := 0
	var degrees := {}
	for region in regions:
		degrees[region.id] = 0
	for edge in (_state.region_graph.get("edges", []) as Array):
		var a := String(edge[0])
		var b := String(edge[1])
		if not degrees.has(a) and not degrees.has(b):
			continue
		if String(edge[3]) == "sea":
			sea += 1
		else:
			land += 1
		for end in [a, b]:
			if degrees.has(end):
				degrees[end] = int(degrees[end]) + 1
	var least = null
	for region in regions:
		if least == null or int(degrees[region.id]) < int(degrees[least.id]):
			least = region
	PanelKit.row(_body, tr("Links between regions"), tr("%d by land · %d by sea") % [land, sea])
	if least != null:
		PanelKit.row(_body, tr("Least connected"), "%s (%d)" % [least.region_name, int(degrees[least.id])])


func _cities_by_size(ns, region) -> Array:
	var cities: Array = region.cities.duplicate()
	cities.sort_custom(func(a, b) -> bool:
		return Migration.city_population(ns, region.id, a.id) > Migration.city_population(ns, region.id, b.id))
	return cities


func _largest_city(region_id: String):
	var ns = _state.player()
	for region in _loader.regions.get(ns.id, []):
		if region.id == region_id and not region.cities.is_empty():
			return _cities_by_size(ns, region)[0]
	return null


func _cell(text: String, variation: String, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if width > 0.0 else HORIZONTAL_ALIGNMENT_LEFT
	label.custom_minimum_size.x = width * UiTheme.text_scale()
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## The mix, as one word: the largest of the three shares -- services almost
## everywhere, which is the honest answer rather than a flaw in the label.
func _dominant(region) -> String:
	var best: String = ""
	var best_share: float = -1.0
	for key in region.sector_mix.keys():
		if float(region.sector_mix[key]) > best_share:
			best_share = float(region.sector_mix[key])
			best = key
	return "%s %s%%" % [Labels.sector(best), Num.f(best_share * 100.0, 0)]
