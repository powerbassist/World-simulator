extends PanelContainer

## The nation info panel S8 adds -- opened by clicking a nation on the map.
## Shows that nation's live simulation values, the same NationState figures
## every other panel reads, not the static data/nations/*.json snapshot from
## game start.
##
## Read-only until V1.3a, which gave it the block's player verbs: relations with
## the clicked nation, and a button per currently-available diplomatic action.
## They live here rather than on a new dashboard tab because you act ON the
## nation you have clicked -- a separate tab would need its own nation picker,
## duplicating the map. Intent still leaves as an explicit command
## (Diplomacy.execute) and the panel still never writes state itself; see
## docs/engine-decision.md Rule 2 and docs/diplomacy-model.md.
##
## Built in code, like the other panels -- see budget_panel.gd's placement note.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Trends = preload("res://src/ui/trends.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const Trade = preload("res://src/sim/trade.gd")
const Relations = preload("res://src/core/relations.gd")

signal closed

## Mirrors law_panel.gd's `proposed`, so main.gd's U4 decision-delta plumbing
## (_queue_effect, a baseline measured against the next history entry) takes it
## with no change of its own.
signal acted(before, label)

var _state
var _loader
var _nation_id := ""
var _title: Label
var _body: VBoxContainer
var _actions: VBoxContainer
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
	_title.theme_type_variation = UiTheme.LEAD
	root.add_child(_title)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	root.add_child(_body)

	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 6)
	root.add_child(_actions)

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

	_refresh_actions()


## Relations and the verbs. Absent entirely for the player's own nation: there
## is no pair, so there is no score to show and nothing to act on.
func _refresh_actions() -> void:
	for child in _actions.get_children():
		child.queue_free()

	var player_id: String = _state.player_nation_id
	if _nation_id == player_id:
		return

	var heading := Label.new()
	heading.theme_type_variation = UiTheme.HEADING
	heading.text = "RELATIONS"
	_actions.add_child(heading)

	var score := Diplomacy.score(_state, player_id, _nation_id)
	var score_line := Label.new()
	score_line.text = "%s–%s: %.0f / 100" % [player_id, _nation_id, score]
	_actions.add_child(score_line)

	# The player's side of the trade weight, not the partner's. The two differ --
	# that asymmetry is the whole point of the directed weight — and showing the
	# viewer's own share is what makes "who matters to me" readable.
	var weight_line := Label.new()
	weight_line.text = "Trade: %.0f%% of %s's external demand" % [
		100.0 * float(Trade.weights(_state, player_id).get(_nation_id, 0.0)), player_id,
	]
	weight_line.theme_type_variation = UiTheme.CAPTION
	_actions.add_child(weight_line)

	var agreement_line := Label.new()
	if _state.agreements.has(Relations.key(player_id, _nation_id)):
		var entry: Dictionary = _state.agreements[Relations.key(player_id, _nation_id)]
		agreement_line.text = "Agreement: %s, since %d/%d" % [
			entry.get("action_name", entry.get("action_id", "")),
			int(entry.get("since_month", 0)), int(entry.get("since_year", 0)),
		]
	else:
		agreement_line.text = "Agreement: none"
		agreement_line.theme_type_variation = UiTheme.CAPTION
	_actions.add_child(agreement_line)

	# BOTH directions, on two lines. The register is directed and a retaliation is
	# the second entry, so a single "coerced" line would hide the half the player
	# did not choose -- which is the half costing them growth.
	_actions.add_child(_measure_line("Measures imposed", player_id, _nation_id))
	_actions.add_child(_measure_line("Measures received", _nation_id, player_id))

	var available: Array = Diplomacy.available(
		_state, _loader.diplomatic_actions, player_id, _nation_id
	)

	# Every action, not only the available ones: a verb that vanishes tells the
	# player nothing about why, and the precondition IS the interesting part.
	# Unavailable ones are shown disabled with the reason in the tooltip, the
	# same way law_panel.gd disables a 49.3 button on cooldown.
	for action in _loader.diplomatic_actions:
		_actions.add_child(_action_row(action, available.has(action), player_id))


## One direction of the coercion register, named. Reads "none" as a caption while
## nothing is in force, the same shape the agreement line above uses, so a quiet
## pair does not shout two extra rows at the player.
func _measure_line(prefix: String, from_id: String, to_id: String) -> Control:
	var line := Label.new()
	var terms = _state.measures.get(Relations.directed_key(from_id, to_id))
	if terms == null:
		line.text = "%s: none" % prefix
		line.theme_type_variation = UiTheme.CAPTION
		return line
	line.text = "%s: %s, severity %.2f, since %d/%d" % [
		prefix,
		terms.get("action_name", terms.get("action_id", "")),
		float(terms.get("severity", 0.0)),
		int(terms.get("since_month", 0)), int(terms.get("since_year", 0)),
	]
	return line


func _action_row(action, is_available: bool, player_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var summary := Label.new()
	summary.text = action.action_name
	summary.tooltip_text = action.summary
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	if not is_available:
		summary.theme_type_variation = UiTheme.CAPTION
	row.add_child(summary)

	var button := Button.new()
	button.text = "Act"
	button.disabled = not is_available
	if not is_available:
		button.tooltip_text = _unavailable_reason(action, player_id)
	else:
		button.tooltip_text = "%+.0f relations with %s." % [
			float(action.effects.get("relations", 0.0)), _nation_id,
		]
		button.pressed.connect(_on_act.bind(action))
	row.add_child(button)

	return row


func _unavailable_reason(action, player_id: String) -> String:
	var ns = _state.nations.get(player_id)
	if ns == null:
		return "Unavailable."
	var key := Diplomacy.cooldown_key(action.id, _nation_id)
	if ns.diplo_cooldown_months.has(key):
		return "Available again in %d months." % int(ns.diplo_cooldown_months[key])
	# Named ahead of the generic reason: "they will not sign" is a different
	# problem from "you cannot propose", and it is the one the player can fix.
	if String(action.effects.get("agreement", {}).get("op", "")) == "enter":
		if not Diplomacy.would_accept_agreement(_state, player_id, _nation_id):
			return "%s will not sign below %.0f relations." % [
				_nation_id, DK.AGREEMENT_ACCEPT_MIN,
			]
	return "Conditions for this action are not met."


func _on_act(action) -> void:
	var before := Trends.snapshot_now(_state)
	Diplomacy.execute(
		_state, _loader.diplomatic_actions, action, _state.player_nation_id, _nation_id
	)
	acted.emit(before, "%s: %s" % [action.action_name, _nation_id])
	_dirty = true


func _add_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(label)
