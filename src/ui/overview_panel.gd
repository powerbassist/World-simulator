extends PanelContainer

const PollNoise = preload("res://src/ui/poll_noise.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")

## Overview tab -- U2. A thin re-host of the old HUD's date/government/election
## lines, not new design; U3 owns the "what matters most" answer (ROADMAP.md).
## Same shape as nation_panel.gd: setup(), mark_dirty(), a _process guard, and
## _add_line() into a VBoxContainer rebuilt each refresh.

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
	_title.text = "OVERVIEW"
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

	_title.text = "OVERVIEW — %s" % ns.id

	for child in _body.get_children():
		child.queue_free()

	var standing := "cohabitation" if ns.is_cohabitation else ("minority" if ns.is_minority else "majority")
	_add_line("Government: %d/%d seats (%s)" % [ns.coalition_seats, ns.assembly_seats, standing])
	_add_line("Term %d of %d months, next election %d/%d" % [
		ns.months_in_term, ns.term_months, ns.next_election_month, ns.next_election_year
	])
	_add_line("")
	# The polled figure, not the true one -- matches top_bar.gd and the HUD it
	# replaces; this tab must not leak what the polling panel is deliberately
	# blurring.
	var poll := PollNoise.displayed(
		PollNoise.poll_id(_state.year, _state.month), PollingPanel.HEADLINE_KEY, ns.overall_approval_pct
	)
	_add_line("Approval: %.0f%% (poll)" % poll)
	_add_line("Deficit: %+.1f%% of GDP" % -ns.deficit_pct_gdp)
	_add_line("Unemployment: %.1f%%" % ns.unemployment_pct)


func _add_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(label)
