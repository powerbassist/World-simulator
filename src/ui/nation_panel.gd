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
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Trends = preload("res://src/ui/trends.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const Trade = preload("res://src/sim/trade.gd")
const Relations = preload("res://src/core/relations.gd")
const Roster = preload("res://src/core/roster.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")
const Defence = preload("res://src/sim/defence.gd")
const DFK = preload("res://src/sim/defence_constants.gd")

signal closed

## Mirrors law_panel.gd's `proposed`, so main.gd's U4 decision-delta plumbing
## (_queue_effect, a baseline measured against the next history entry) takes it
## with no change of its own.
signal acted(before, label, result)

var _state
var _loader
var _nation_id := ""
var _title: Label
var _body: VBoxContainer
var _actions: VBoxContainer

## The first enabled verb this panel built on its last refresh. See primary_action().
var _primary: Control = null
var _dirty := true
var _close_button: Button


func _ready() -> void:
	# 780 rather than the 360 this shipped with, and the V1.3e screenshot pass is
	# why: at 360 the window sized to its minimum and EVERY DIPLOMATIC ACTION
	# BUTTON fell below the fold, so the eight verbs this panel exists for were
	# reachable only by scrolling a panel that does not look scrollable. The panel
	# had grown a relations score, a trade share, an agreement line and two measure
	# lines since V1.3a set that height, and no test can see a fold.
	#
	# Exactly the failure docs/bloc-model.md records for the bloc panel's own
	# budget section one session earlier. Well inside U5a's ~886px usable band,
	# which is the ceiling a window must not grow through.
	# 860 rather than V1.3e's 780, and V1.3g's screenshot pass is why: the four
	# defence verbs took the list from ten rows to fourteen, and `Lift Sanctions`
	# fell off the panel entirely while `Impose Sanctions` sat on the clip line.
	# The same failure V1.3e recorded here one session earlier, at the same panel,
	# for the same reason -- a list that grows with the block while the height does
	# not. Height ALONE could not fix it: four rows are ~136px and the U5a ceiling is
	# ~886, so this is 80px of height plus the two tightenings below.
	custom_minimum_size = Vector2(420, 860)

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
	# 4 rather than 6: with fourteen verbs the separation is spent fourteen times,
	# so two pixels a row is nearly a whole row back. Layout, so it stays at the
	# call site -- see the styling rule in AGENTS.md.
	_actions.add_theme_constant_override("separation", 4)
	root.add_child(_actions)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func():
		hide()
		closed.emit()
	)
	root.add_child(_close_button)


## Docked in a WindowFrame, whose X is the real close control. Without this the
## panel's own Close hides the CONTENT while window_manager.open() only ever shows
## the FRAME, so the window reopens permanently empty -- docs/playability-audit.md
## V3. The four panels that already had this method never had the bug.
func hide_close_button() -> void:
	_close_button.hide()


func setup(state, loader) -> void:
	_state = state
	_loader = loader


## Called by main.gd when a map click resolves to a nation. Re-entrant --
## clicking a different nation while the panel is open just retargets it.
func show_nation(nation_id: String) -> void:
	_nation_id = nation_id
	_dirty = true


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	# V1.6 audit, V10. `_nation_id == ""` used to be part of this early-out, so
	# opening Diplomacy from the World cluster -- which main.gd registers precisely
	# "so the diplomatic verbs are not hidden behind knowing to click the map" --
	# drew a completely empty window and left it empty. The panel is a card about a
	# selected nation and has nothing to say before one is picked; it now says that
	# rather than saying nothing.
	if _nation_id == "":
		_show_empty_state()
		return
	_refresh()


## What the panel looks like before a nation has been chosen. Not a nation picker:
## the map IS the picker, and a second list of the same ten would be a surface to
## keep in step with it for no gain.
func _show_empty_state() -> void:
	_title.text = "No nation selected"
	for child in _body.get_children():
		child.queue_free()
	for child in _actions.get_children():
		child.queue_free()
	PanelKit.line(_body, "Click a country on the map to open its file. The coloured ones are the nations the game simulates.", PanelKit.Tone.PLAIN)


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

	# The two blank spacers this block had are down to one, for the fold reason in
	# _ready(): a blank line costs the same as a verb row, and there are fourteen
	# verbs competing for the space now.
	# V4.11c. Said only for the simulated grade (the author's call): the player
	# chose among the playable ones at New Game and needs no reminder there, but a
	# nation that answers every verb and can never be picked should say so. NOT
	# "neighbour": the simulated grade is every nation without `playable` -- Italy
	# and Spain as much as the twelve (the V4.11 review caught the first wording).
	if Roster.grade(_loader, _nation_id) == "simulated":
		PanelKit.line(_body, "Simulated nation — not playable", PanelKit.Tone.DIM)
	PanelKit.line(_body, "Leader: %s (%s)" % [_loader.person_name(n.leader_person_id), n.leader_title], PanelKit.Tone.PLAIN)
	PanelKit.line(_body, "GDP: EUR %.0fbn   growth %+.2f%%" % [ns.gdp_eur_bn, ns.growth_annual_pct], PanelKit.Tone.PLAIN)
	PanelKit.line(_body, "Unemployment: %.1f%%" % ns.unemployment_pct, PanelKit.Tone.PLAIN)
	PanelKit.line(_body, "Debt: %.1f%% of GDP" % ns.debt_to_gdp_pct(), PanelKit.Tone.PLAIN)

	# The player's own approval is polled elsewhere with noise applied (see
	# polling_panel.gd) — this panel shows every nation including rivals the
	# player has no poll for, so it reports the true figure plainly rather
	# than reusing a noise model built around one nation's published polls.
	PanelKit.line(_body, "Approval: %.0f%%" % ns.overall_approval_pct, PanelKit.Tone.PLAIN)
	PanelKit.line(_body, "", PanelKit.Tone.PLAIN)
	PanelKit.line(_body, "Term %d of %d months, next election %d/%d" % [
		ns.months_in_term, ns.term_months, ns.next_election_month, ns.next_election_year
	], PanelKit.Tone.PLAIN)

	_refresh_actions()


## Relations and the verbs. Absent entirely for the player's own nation: there
## is no pair, so there is no score to show and nothing to act on.
func _refresh_actions() -> void:
	for child in _actions.get_children():
		child.queue_free()
	_primary = null

	var player_id: String = _state.player_nation_id
	if _nation_id == player_id:
		return

	var heading := Label.new()
	heading.theme_type_variation = UiTheme.HEADING
	heading.text = "RELATIONS"
	_actions.add_child(heading)

	var score := Diplomacy.score(_state, player_id, _nation_id)
	PanelKit.line(_actions, "%s–%s: %.0f / 100" % [player_id, _nation_id, score], PanelKit.Tone.PLAIN)

	# The player's side of the trade weight, not the partner's. The two differ --
	# that asymmetry is the whole point of the directed weight — and showing the
	# viewer's own share is what makes "who matters to me" readable.
	PanelKit.line(_actions, "Trade: %.0f%% of %s's external demand" % [
		100.0 * float(Trade.weights(_state, player_id).get(_nation_id, 0.0)), player_id,
	])

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

	# V1.3g, and ONE line for two registers rather than the three it would take to
	# give the pact, the outbound deployment and its kind a row each. The panel is at
	# its height ceiling and this session adds four verbs to the list below; a
	# register that is empty on a new game does not get to spend three rows saying so.
	# The measure lines above are two because both directions cost the player
	# something -- here only the player's own side bills them.
	_actions.add_child(_alliance_line(player_id))

	var available: Array = Diplomacy.available(
		_state, _loader.diplomatic_actions, player_id, _nation_id
	)

	# Every action, not only the available ones: a verb that vanishes tells the
	# player nothing about why, and the precondition IS the interesting part.
	# Unavailable ones are shown disabled with the reason in the tooltip, the
	# same way law_panel.gd disables a 49.3 button on cooldown.
	#
	# V1.3e: an action the PARTNER would refuse counts as unavailable here, and it
	# did not before. Diplomacy.available() never consulted the counterparty --
	# that gate lives inside execute() -- so a treaty the partner would decline
	# rendered as a live button, and clicking it refused silently. That is exactly
	# the failure V1.3b's own `refused_by_partner` had (shipped, and read by
	# nothing), reappearing INSIDE the session that fixed it, and only a frame
	# showed it. Costs the player nothing: execute() refuses it either way, so
	# disabling it replaces a dead click with a sentence.
	for action in _loader.diplomatic_actions:
		var offered: bool = available.has(action) and _partner_would_accept(action, player_id)
		_actions.add_child(_action_row(action, offered, player_id))


## Whether the counterparty would sign, for an action that proposes an agreement.
## True for every action that does not, so the caller can treat it as one gate.
func _partner_would_accept(action, player_id: String) -> bool:
	var terms: Dictionary = action.effects.get("agreement", {})
	if String(terms.get("op", "")) == "enter":
		return Diplomacy.would_accept_agreement(_state, player_id, _nation_id, terms)

	# V1.3g's gate, folded into the same one. Only "sign" is asked: abandoning is
	# unilateral, and deploying happens under a pact already agreed to.
	var pact: Dictionary = action.effects.get("pact", {})
	if String(pact.get("op", "")) == "sign":
		return ForeignPolicy.would_accept_pact(_state, player_id, _nation_id)

	return true


## The pact and the player's own deployment under it, on one line. "none" as a
## caption while there is nothing, the shape the agreement and measure lines use.
func _alliance_line(player_id: String) -> Control:
	var line := Label.new()
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var pact = _state.pacts.get(Relations.key(player_id, _nation_id))
	if pact == null:
		line.text = "Alliance: none"
		line.theme_type_variation = UiTheme.CAPTION
		return line

	var text := "Alliance: %s, since %d/%d" % [
		pact.get("action_name", pact.get("action_id", "")),
		int(pact.get("since_month", 0)), int(pact.get("since_year", 0)),
	]

	var kind := Defence.deployment_kind(_state, player_id, _nation_id)
	if kind == DFK.DEPLOYMENT_OBLIGED:
		# Named as obliged in the player's own words rather than as a register value.
		# This is the one commitment they cannot end from this panel, and the sentence
		# has to say so or the missing button reads as a bug.
		text += " — forces committed under the pact; only abandoning it ends this"
	elif kind == DFK.DEPLOYMENT_CHOSEN:
		text += " — forces deployed by choice"

	line.text = text
	return line


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
		if _primary == null:
			_primary = button
	row.add_child(button)

	return row


func _unavailable_reason(action, player_id: String) -> String:
	var ns = _state.nations.get(player_id)
	if ns == null:
		return "Unavailable."
	var key := Diplomacy.cooldown_key(action.id, _nation_id)
	if ns.diplo_cooldown_months.has(key):
		# The key is written when the act executes (diplomacy.gd), so this is a
		# cooldown the player's own act started -- name it as one. "Available
		# again in 12 months" read like a lock left over from before the game
		# began (playtest 2026-09-05).
		return "Cooldown: available again in %d months." % int(ns.diplo_cooldown_months[key])
	# Named ahead of the generic reason: "they will not sign" is a different
	# problem from "you cannot propose", and it is the one the player can fix.
	var terms: Dictionary = action.effects.get("agreement", {})
	if String(terms.get("op", "")) == "enter":
		if not Diplomacy.would_accept_agreement(_state, player_id, _nation_id, terms):
			return _refusal_text(Diplomacy.refusal_reason(_state, player_id, _nation_id, terms))

	# V1.3g, same shape: a pact the partner would decline is a different problem
	# from a precondition that is not met, and it is the one the player can fix.
	var pact: Dictionary = action.effects.get("pact", {})
	if String(pact.get("op", "")) == "sign":
		if not ForeignPolicy.would_accept_pact(_state, player_id, _nation_id):
			return _refusal_text(
				ForeignPolicy.pact_refusal_reason(_state, player_id, _nation_id)
			)

	return "Conditions for this action are not met."


## V1.3e. The model returns a KEY and this turns it into a sentence, because
## src/sim/ does not know the UI exists and a test should not assert on wording.
##
## Worth its own function rather than being inlined: until this session
## `refused_by_partner` had been on the result dictionary since V1.3b and NOTHING
## in src/ui/ read it, so a partner declining a treaty was silent to the player.
## Each key names the term the player can actually act on.
func _refusal_text(key: String) -> String:
	match key:
		ForeignPolicy.REFUSAL_LOW_STAKE:
			return "%s will not sign: too little of their trade runs through you." % _nation_id
		ForeignPolicy.REFUSAL_POOR_RELATIONS:
			return "%s will not sign: relations are not close enough." % _nation_id
		ForeignPolicy.REFUSAL_THIN_TERMS:
			return "%s will not sign: these terms are not worth it to them." % _nation_id
		# V1.3g, and the only refusal in the set the player answers with a BUDGET
		# rather than with diplomacy: nobody promises to bleed for an army that is
		# not there. The sentence has to point at the defence line or the player
		# reads it as another relations problem and does the wrong thing.
		ForeignPolicy.REFUSAL_WEAK_PARTNER:
			return "%s will not sign: your forces are too slight to be worth an alliance. Sustained defence spending is what changes this." % _nation_id
	return "%s will not sign." % _nation_id


func _on_act(action) -> void:
	var before := Trends.snapshot_now(_state)
	var result := Diplomacy.execute(
		_state, _loader.diplomatic_actions, action, _state.player_nation_id, _nation_id
	)
	# The refusal sentence travels in the result: the shell's acknowledgment
	# card needs it, and the action object whose agreement terms feed the
	# reason lives here, not there.
	if bool(result.get("refused", false)):
		result["reason"] = Diplomacy.refusal_reason(
			_state, _state.player_nation_id, _nation_id, action.effects.get("agreement", {})
		)
	acted.emit(before, "%s: %s" % [action.action_name, _nation_id], result)
	_dirty = true


## The control this panel exists to let the player press -- V2.1a's fold contract.
##
## Duck-typed: window_frame.gd asks through has_method(), so a panel with nothing
## to press simply does not implement this and never draws the fold mark. The
## FIRST enabled action is the answer rather than the last, because a panel whose
## first verb has scrolled off is already a panel whose verbs are hidden.
func primary_action() -> Control:
	return _primary if is_instance_valid(_primary) else null
