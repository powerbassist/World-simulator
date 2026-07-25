extends PanelContainer

## The law screen. Every proposable law, a forecast of how the assembly would
## vote, and a Propose button that sends the one player command this panel has
## -- Legislature.propose() -- back to the sim.
##
## Reads simulation state and never writes it directly; see engine-decision.md
## Rule 2. Built in code, like the other two panels -- a generated list that a
## scene file would describe worse.
##
## The forecast is deliberately blurred: a party whose |support| falls inside
## FORECAST_UNCERTAIN_BAND renders as "Undecided" rather than a firm yes or no.
## The band is wider than legislature.gd's own ABSTAIN_BAND, so a close vote
## reads as genuinely uncertain right up until it is actually proposed -- a
## display-layer trick, the same shape poll_noise.gd uses for polls, not a
## random number. src/sim/ never learns a forecast exists.

const Legislature = preload("res://src/sim/legislature.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Law = preload("res://src/core/law.gd")

## Wider than legislature_constants.ABSTAIN_BAND (0.05) on purpose -- the real
## vote resolves exactly off the same support() value, but the forecast blurs
## a wider band around zero so a close vote is not readable in advance.
const FORECAST_UNCERTAIN_BAND := 0.15

signal proposed

var _state
var _loader
var _title: Label
var _list: VBoxContainer
var _result_box: VBoxContainer
var _dirty := true


func _ready() -> void:
	custom_minimum_size = Vector2(760, 560)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_title = Label.new()
	root.add_child(_title)

	_result_box = VBoxContainer.new()
	root.add_child(_result_box)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 14)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	root.add_child(_build_footer())


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END

	var close := Button.new()
	close.text = "Close (L)"
	close.pressed.connect(func(): hide())
	row.add_child(close)

	return row


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	var ns = _state.player()
	_title.text = "LEGISLATURE — %s" % ns.id
	_dirty = true


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

	for child in _result_box.get_children():
		child.queue_free()
	if not ns.last_law_result.is_empty():
		_result_box.add_child(_build_result_summary(ns.last_law_result))

	for child in _list.get_children():
		child.queue_free()

	var party_list: Array = _loader.parties.get(ns.id, [])
	var available: Array = Legislature.available(ns, _loader.laws)
	if available.is_empty():
		var none := Label.new()
		none.text = "No law is currently proposable."
		_list.add_child(none)
		return

	for law in available:
		_list.add_child(_build_law_row(ns, party_list, law))


func _build_result_summary(result: Dictionary) -> Control:
	var box := VBoxContainer.new()

	var law: Law = _find_law(result["law_id"])
	var law_label: String = law.law_name if law != null else result["law_id"]

	var heading := Label.new()
	heading.text = "%s — %s" % [law_label, "PASSED" if result["passed"] else "FAILED"]
	box.add_child(heading)

	var tally := Label.new()
	tally.text = "Yes %d · No %d · Abstain %d, of %d seats" % [
		result["yes_seats"], result["no_seats"], result["abstain_seats"], result["seats_total"]
	]
	box.add_child(tally)

	if not result["passed"]:
		var opposed := PackedStringArray()
		for party in _loader.parties.get(_state.player().id, []):
			if result["party_votes"].get(party.id, "") == "no":
				opposed.append(party.party_name)
		if not opposed.is_empty():
			var against := Label.new()
			against.text = "Voted against: %s" % ", ".join(opposed)
			box.add_child(against)

	return box


func _build_law_row(ns, party_list: Array, law) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var heading := Label.new()
	heading.text = "%s  (%s, %s majority)" % [law.law_name, law.theme, law.majority]
	box.add_child(heading)

	var summary := Label.new()
	summary.text = law.summary
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(summary)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var forecast := Label.new()
	forecast.text = "Forecast: %s" % _forecast_text(ns, party_list, law)
	forecast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(forecast)

	var propose_btn := Button.new()
	propose_btn.text = "Propose"
	propose_btn.pressed.connect(_on_propose.bind(law))
	row.add_child(propose_btn)

	box.add_child(row)
	return box


func _forecast_text(ns, party_list: Array, law) -> String:
	var yes := 0
	var no := 0
	var undecided := 0
	for party in party_list:
		var s: float = Legislature.support(ns, party, law)
		var seats: int = int(ns.seats_by_party.get(party.id, 0))
		if s > FORECAST_UNCERTAIN_BAND:
			yes += seats
		elif s < -FORECAST_UNCERTAIN_BAND:
			no += seats
		else:
			undecided += seats
	return "%d for · %d against · %d undecided" % [yes, no, undecided]


func _on_propose(law) -> void:
	Legislature.propose(_state, _loader, law)
	proposed.emit()
	_dirty = true


func _find_law(law_id: String):
	for law in _loader.laws:
		if law.id == law_id:
			return law
	return null
