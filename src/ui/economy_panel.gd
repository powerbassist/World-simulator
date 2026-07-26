extends PanelContainer

## Economy tab -- U2. A thin re-host of the old HUD's GDP/growth/unemployment/
## debt lines plus population and sector output, not new design; U3 owns
## content and hierarchy (ROADMAP.md). Same shape as nation_panel.gd.

var _state
var _title: Label
var _body: VBoxContainer
var _dirty := true


func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_title = Label.new()
	_title.text = "ECONOMY"
	root.add_child(_title)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	root.add_child(_body)


func setup(state) -> void:
	_state = state
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

	_title.text = "ECONOMY — %s" % ns.id

	for child in _body.get_children():
		child.queue_free()

	_add_line("GDP: EUR %.0fbn   growth %+.2f%%" % [ns.gdp_eur_bn, ns.growth_annual_pct])
	_add_line("Unemployment: %.1f%%" % ns.unemployment_pct)
	_add_line("Population: %.1fM" % (ns.population / 1_000_000.0))
	_add_line("")
	_add_line("Debt: %.1f%% of GDP" % ns.debt_to_gdp_pct())
	_add_line("Deficit: %+.1f%% of GDP" % -ns.deficit_pct_gdp)
	_add_line("")

	var sectors: Array = ns.sector_output.keys()
	sectors.sort()
	for sector in sectors:
		_add_line("%s: EUR %.0fbn" % [String(sector).capitalize(), ns.sector_output[sector]])


func _add_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(label)
