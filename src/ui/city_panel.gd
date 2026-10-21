extends PanelContainer

## One level down -- V2.2b's City panel, and the only V2 surface with two ways
## in. docs/panel-system.md §16: *"the route is a click on the map; the drawer
## entry is the way in for a player who does not know that."* So the panel
## carries two views: the ranked list of the PLAYER'S cities (the drawer's
## answer) and one city's detail (the map's answer, for ANY nation -- the
## register is public data and a cross that answered no click would be drawn
## content the game cannot reach).
##
## The back button is this panel's only interactive control, and it is not a
## verb: it returns to the list view the drawer opens. It sits OUTSIDE the
## scroll with Close rather than in a row, for the fold's reason -- a button
## beside an autowrapping label narrows the label, the wrap grows the row, and
## nation_panel.gd paid for that twice.
##
## A city's population is its share read through its region and the nation --
## never authored, city.gd's four-field rule -- so both views multiply the same
## two shares by the LIVE national population and stay true as demography moves.

signal closed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Companies = preload("res://src/sim/companies.gd")
const Region = preload("res://src/core/region.gd")
const Migration = preload("res://src/sim/migration.gd")
const Num = preload("res://src/ui/num.gd")

var _state
var _loader
var _dirty := true

## "" is the list view; a city id is the detail view. The map is the only writer
## besides the back button.
var _city_id := ""

var _title: Label
var _body: VBoxContainer
var _close_button: Button
var _back_button: Button


func _ready() -> void:
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

	_back_button = Button.new()
	_back_button.text = tr("All cities")
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


## Docked-tab mode -- see budget_panel.gd's hide_close_button() for why.
func hide_close_button() -> void:
	_close_button.hide()


## The map's route. Any nation's city answers; an id the register does not hold
## falls back to the list rather than an empty window, because the only writer
## is a cross the register itself drew.
func show_city(city_id: String) -> void:
	_city_id = city_id
	_dirty = true


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


func _refresh() -> void:
	for child in _body.get_children():
		child.queue_free()

	var found: Dictionary = _find(_city_id) if _city_id != "" else {}
	if not found.is_empty():
		_build_detail(found)
		_back_button.show()
		return

	_city_id = ""
	_back_button.hide()
	_build_list()


## {region, city, nation_id}, or {} when the register does not hold the id. The
## register is 112 regions of at most 21 cities, so region.gd's own linear scans
## are the whole index -- find_city over the player's nation would not reach a
## foreign city the map just clicked.
func _find(city_id: String) -> Dictionary:
	for nation_id in _loader.regions.keys():
		var city = Region.find_city(_loader.regions[nation_id], city_id)
		if city != null:
			return {
				"region": Region.region_of_city(_loader.regions[nation_id], city_id),
				"city": city,
				"nation_id": nation_id,
			}
	return {}


func _build_list() -> void:
	var ns = _state.player()
	if ns == null:
		return
	var nation = _loader.nations.get(ns.id)
	if nation == null:
		return

	_title.text = tr("The cities of %s") % nation.nation_name

	var entries: Array = []
	var named := 0.0
	for region in _loader.regions.get(ns.id, []):
		for city in region.cities:
			var pop: float = Migration.city_population(ns, region.id, city.id)
			entries.append({"region": region, "city": city, "population": pop})
			named += Migration.region_share(ns, region.id) * Migration.city_share(ns, city.id)
	entries.sort_custom(func(a, b): return float(a["population"]) > float(b["population"]))

	PanelKit.heading(_body, tr("The named places"))
	PanelKit.row(_body, tr("Cities"), str(entries.size()))
	PanelKit.row(_body, tr("Living in a named city"), "%s%%" % Num.f((named * 100.0), 1))
	PanelKit.line(_body, tr("Everyone else lives in the towns under the cut and the countryside -- the unnamed residual, never stored."))

	PanelKit.heading(_body, tr("By population"))
	var rows: Array = []
	for entry in entries:
		var region = entry["region"]
		var city = entry["city"]
		var jobs: float = Companies.headcount_in_city(ns, _loader, city.id)
		rows.append([
			city.city_name,
			region.region_name,
			PanelKit.pop_text(float(entry["population"])),
			PanelKit.pop_text(jobs) if jobs > 0.0 else "0",
		])
	PanelKit.ledger(_body, rows)


func _build_detail(found: Dictionary) -> void:
	var region = found["region"]
	var city = found["city"]
	var nation_id: String = found["nation_id"]
	var ns = _state.nations.get(nation_id)
	var nation = _loader.nations.get(nation_id)
	if ns == null or nation == null:
		return

	_title.text = city.city_name
	var pop: float = Migration.city_population(ns, region.id, city.id)

	PanelKit.heading(_body, tr("The place"))
	PanelKit.row(_body, tr("Region"), "%s · %s" % [region.region_name, nation_id])
	PanelKit.row(_body, tr("Nation"), String(nation.nation_name))
	PanelKit.row(_body, tr("Population"), PanelKit.pop_text(pop))
	PanelKit.row(_body, tr("Share of its region"), "%s%%" % Num.f((Migration.city_share(ns, city.id) * 100.0), 1))
	PanelKit.row(_body, tr("Share of the nation"), "%s%%" % Num.f((Migration.region_share(ns, region.id) * Migration.city_share(ns, city.id) * 100.0), 2))

	PanelKit.heading(_body, tr("Named employers"))
	# A3. Majors keep a row apiece; the body tier -- which since A3 domiciles
	# most of a big city's firms -- is one aggregate line, the companies
	# panel's own shape. A city holding thirty body firms printed thirty rows
	# for employers with no verb, and the fold finding is about exactly that.
	# V4.7b: the filter reads the LIVE city, the same register fact the jobs
	# total above and every headcount in these rows read -- the authored-city
	# filter listed a relocated firm under its old city while its payroll
	# counted in the new one, one panel two answers (the pass-5 fleet's find).
	var rows: Array = []
	var body_count := 0
	var body_jobs := 0.0
	for company in _loader.companies.get(nation_id, []):
		if Companies.live_city_of(ns, company) != city.id:
			continue
		if Companies.is_major(company):
			rows.append([String(company.company_name), PanelKit.pop_text(Companies.headcount(ns, company))])
		else:
			# The live read, same as the majors' rows beside it: a standing
			# burden scales a body firm's compliance like anybody's, and an
			# authored figure would disagree with the region panel and the
			# migration flow reading the same city (the PR-46 review's nit).
			body_count += 1
			body_jobs += Companies.headcount(ns, company)
	if rows.is_empty() and body_count == 0:
		PanelKit.line(_body, tr("No named employer is domiciled here."))
	else:
		if not rows.is_empty():
			PanelKit.ledger(_body, rows)
		if body_count > 0:
			PanelKit.line(_body, tr("BODY · %d firms · %s jobs") % [body_count, PanelKit.pop_text(body_jobs)])
