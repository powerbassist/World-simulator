extends PanelContainer

## The nation info panel S8 adds -- opened by clicking a nation on the map.
## Shows that nation's live simulation values, the same NationState figures
## every other panel reads, not the static data/nations/*.json snapshot from
## game start. Reads simulation state and never writes it; there is no player
## command here, only Close.
##
## Built in code, like the other panels -- see budget_panel.gd's placement note.

signal closed

var _state
var _loader
var _nation_id := ""
var _title: Label
var _body: VBoxContainer
var _dirty := true


func _ready() -> void:
	custom_minimum_size = Vector2(420, 360)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_title = Label.new()
	root.add_child(_title)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	root.add_child(_body)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func():
		hide()
		closed.emit()
	)
	root.add_child(close)


func setup(state, loader) -> void:
	_state = state
	_loader = loader


## Called by main.gd when a map click resolves to a nation. Re-entrant --
## clicking a different nation while the panel is open just retargets it.
func show_nation(nation_id: String) -> void:
	_nation_id = nation_id
	_dirty = true


func _process(_delta: float) -> void:
	if not _dirty or not visible or _state == null or _nation_id == "":
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


func _refresh() -> void:
	var n = _loader.nations.get(_nation_id)
	var ns = _state.nations.get(_nation_id)
	if n == null or ns == null:
		return

	_title.text = "%s — %s" % [n.nation_name, n.capital]

	for child in _body.get_children():
		child.queue_free()

	_add_line("Leader: %s (%s)" % [n.leader_name, n.leader_title])
	_add_line("")
	_add_line("GDP: EUR %.0fbn   growth %+.2f%%" % [ns.gdp_eur_bn, ns.growth_annual_pct])
	_add_line("Unemployment: %.1f%%" % ns.unemployment_pct)
	_add_line("Debt: %.1f%% of GDP" % ns.debt_to_gdp_pct())

	# The player's own approval is polled elsewhere with noise applied (see
	# polling_panel.gd) — this panel shows every nation including rivals the
	# player has no poll for, so it reports the true figure plainly rather
	# than reusing a noise model built around one nation's published polls.
	_add_line("Approval: %.0f%%" % ns.overall_approval_pct)
	_add_line("")
	_add_line("Term %d of %d months, next election %d/%d" % [
		ns.months_in_term, ns.term_months, ns.next_election_month, ns.next_election_year
	])


func _add_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(label)
