extends PanelContainer

## The polling screen. Headline approval, a row per voter bloc, and what the
## electorate currently cares about.
##
## Reads simulation state and never writes it — there is no command to send back,
## because you cannot act on a poll, only on the budget. See engine-decision.md
## Rule 2.
##
## Every figure on this panel is passed through PollNoise first. The live state
## holds the true numbers; the player never sees them. The noise is deterministic
## in the poll id, so the figures hold still between repaints and move once a
## month, which is how a published poll behaves.
##
## Built in code rather than as a .tscn for the same reason the budget screen is:
## it is a generated grid of identical rows.

const Opinion = preload("res://src/sim/opinion.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")

const TOP_ISSUE_COUNT := 4
const HEADLINE_KEY := "overall"

signal closed

var _state
var _title: Label
var _headline: Label
var _bloc_rows := {}          # bloc id -> [approval Label, change Label]
var _issue_rows: Array = []   # [name Label, share Label]
var _dirty := true

## What the previous poll said, so the change column compares like with like:
## two noised figures, not a noised one against a true one.
var _shown_poll_id := -1
var _shown := {}
var _previous := {}


func _ready() -> void:
	# Placement is the owner's job — see the note in budget_panel.gd.
	custom_minimum_size = Vector2(560, 460)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_title = Label.new()
	root.add_child(_title)

	_headline = Label.new()
	root.add_child(_headline)

	root.add_child(_build_blocs())
	root.add_child(_build_issues())

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	root.add_child(_build_footer())


func _build_blocs() -> Control:
	var box := VBoxContainer.new()

	var heading := Label.new()
	heading.text = "Approval by bloc"
	box.add_child(heading)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	box.add_child(grid)

	for header in ["", "share", "approval", "change"]:
		var label := Label.new()
		label.text = header
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if header != "" else HORIZONTAL_ALIGNMENT_LEFT
		label.custom_minimum_size.x = 150 if header == "" else 90
		grid.add_child(label)

	for bloc in K.BLOC_KEYS:
		var name_label := Label.new()
		name_label.text = K.BLOC_LABEL[bloc]
		grid.add_child(name_label)

		var size_label := Label.new()
		size_label.text = "%.0f%%" % (float(K.BLOC_SIZE[bloc]) * 100.0)
		size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(size_label)

		var approval_label := Label.new()
		approval_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(approval_label)

		var change_label := Label.new()
		change_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(change_label)

		_bloc_rows[bloc] = [approval_label, change_label]

	return box


func _build_issues() -> Control:
	var box := VBoxContainer.new()

	var heading := Label.new()
	heading.text = "What the country is thinking about"
	box.add_child(heading)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	box.add_child(grid)

	for _i in range(TOP_ISSUE_COUNT):
		var name_label := Label.new()
		name_label.custom_minimum_size.x = 240
		grid.add_child(name_label)

		var share_label := Label.new()
		share_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		share_label.custom_minimum_size.x = 90
		grid.add_child(share_label)

		_issue_rows.append([name_label, share_label])

	return box


func _build_footer() -> Control:
	var row := HBoxContainer.new()

	var caveat := Label.new()
	caveat.text = "Polls carry a margin of error of about %.0f points." % PollNoise.NOISE_MAX_PCT
	caveat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caveat)

	var close := Button.new()
	close.text = "Close (P)"
	close.pressed.connect(func(): hide(); closed.emit())
	row.add_child(close)

	return row


func setup(state) -> void:
	_state = state
	_title.text = "POLLING — %s" % _state.player().id
	_dirty = true


## Coalesce to at most one refresh per frame, the same shape the budget panel
## uses. Cheaper here — there is no projection to run — but the owner marks this
## dirty on every simulated month either way.
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

	var id := PollNoise.poll_id(_state.year, _state.month)
	var fresh_poll := id != _shown_poll_id

	var current := {}
	current[HEADLINE_KEY] = PollNoise.displayed(id, HEADLINE_KEY, ns.overall_approval_pct)
	for bloc in K.BLOC_KEYS:
		current[bloc] = PollNoise.displayed(id, bloc, float(ns.bloc_approval.get(bloc, 0.0)))

	if fresh_poll:
		_previous = _shown
		_shown = current
		_shown_poll_id = id

	_headline.text = "Approval  %.0f%%" % current[HEADLINE_KEY]

	for bloc in K.BLOC_KEYS:
		var row: Array = _bloc_rows[bloc]
		row[0].text = "%.0f%%" % current[bloc]
		row[1].text = _change_text(bloc, current[bloc])

	var top := Opinion.top_issues(ns, TOP_ISSUE_COUNT)
	for i in _issue_rows.size():
		var row: Array = _issue_rows[i]
		if i >= top.size():
			row[0].text = ""
			row[1].text = ""
			continue
		var issue: String = top[i][0]
		row[0].text = K.ISSUE_LABEL[issue]
		row[1].text = "%.0f%%" % (float(top[i][1]) * 100.0)


func _change_text(key: String, value: float) -> String:
	if not _previous.has(key):
		return "—"
	return "%+.0f" % (value - float(_previous[key]))
