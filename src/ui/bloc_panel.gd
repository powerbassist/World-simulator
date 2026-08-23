extends PanelContainer

## The bloc surface, V1.3d: what the council is voting on, how the player voted,
## what carried, which rules bind, and what membership is charging.
##
## Its own window rather than a section of nation_panel.gd, and that is the one
## UI call this session had to make. The nation panel is where you act ON a
## nation you have clicked, which is why V1.3a's verbs live there; the council is
## not a nation and has no pixel on the map to click. A bloc section inside the
## nation panel would have to appear under whichever nation happened to be
## selected, which is exactly the "needs its own picker" problem that argument
## avoids, inverted.
##
## Read-only over sim state like every other panel: the vote leaves as an
## explicit command (Bloc.cast_vote), and nothing here writes GameState. See
## docs/engine-decision.md Rule 2 and docs/bloc-model.md.
##
## Built in code, like the other panels -- see budget_panel.gd's placement note.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const BK = preload("res://src/sim/bloc_constants.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")
const Relations = preload("res://src/core/relations.gd")
const Trends = preload("res://src/ui/trends.gd")

signal closed

## V1.6 audit, V8. The council vote was the only player command in the game with
## no signal, so it was the only one that never reached Overview's RECENT
## DECISIONS -- a decision binding on the player that the surface built to say
## what you did could not name. Same shape as nation_panel.acted.
signal voted(before, label)

var _state
var _loader
var _title: Label
var _body: VBoxContainer
var _dirty := true
var _close_button: Button


func _ready() -> void:
	# 620 rather than the 420 this shipped with, and the screenshot pass is why: at
	# 420 the window sized to its minimum and THE BUDGET fell below the fold, so the
	# one section telling the player what membership costs was reachable only by
	# scrolling a panel that did not look scrollable. Well inside U5a's ~886px
	# usable band, which is the ceiling a window must not grow through.
	custom_minimum_size = Vector2(460, 620)

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
	_body.add_theme_constant_override("separation", 4)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

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


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if not _dirty or not visible or _state == null:
		return
	_dirty = false
	_refresh()


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return

	for child in _body.get_children():
		child.queue_free()

	var members := Bloc.members(_state, _loader)
	_title.text = "The Union — %d members" % members.size()

	if not ns.eu_member:
		_refresh_outsider(ns, members)
		return

	_refresh_vote(ns)
	_refresh_rules(ns)
	_refresh_contribution(ns)


## A non-member's view. The done-when this satisfies is the one V1.2d's cold read
## would have caught: two of the three playable nations are outside this bloc, and
## a session that gave them nothing would be shipping a mechanic one nation in
## three can touch. What they get is the receiving end -- the bloc's collective
## external tariff lands on them from every member at once, which is a thing no
## single nation in this game can do.
func _refresh_outsider(ns, members: Array) -> void:
	_heading("OUTSIDE THE UNION")
	_line("%s is not a member. It has no vote in the council and no rule of the" % ns.id)
	_line("council binds it.")
	_caption("Membership is fixed at the start of a game — see docs/bloc-model.md.")
	_line("")

	_heading("MEASURES FROM MEMBERS")
	var levied := 0
	var worst := 0.0
	for member_id in members:
		var terms = _state.measures.get(Relations.directed_key(member_id, ns.id))
		if terms == null:
			continue
		levied += 1
		worst = maxf(worst, float(terms.get("severity", 0.0)))
		_line("%s: %s, severity %.2f" % [
			member_id, terms.get("action_name", terms.get("action_id", "")),
			float(terms.get("severity", 0.0)),
		])
	if levied == 0:
		_caption("None. The council has adopted no common external measure.")
	else:
		_line("")
		_line("%d of %d members levying, worst severity %.2f." % [levied, members.size(), worst])
		_caption("A bloc acting as one is the only thing in this game that imposes from more than one direction at once.")


## What is on the table, and the player's own vote. First, because it is the only
## part of this panel the player can act on and the window is opened to act.
func _refresh_vote(ns) -> void:
	_heading("BEFORE THE COUNCIL")

	var pending: Dictionary = Bloc.pending(_state)
	if pending.is_empty():
		_caption("Nothing before the council. The presidency brings the next proposal forward in due course.")
	else:
		var name_line := Label.new()
		name_line.text = String(pending.get("name", ""))
		name_line.autowrap_mode = TextServer.AUTOWRAP_WORD
		_body.add_child(name_line)
		_caption(String(pending.get("summary", "")))
		_line("Divides in %d %s." % [
			int(pending.get("months_left", 0)),
			"month" if int(pending.get("months_left", 0)) == 1 else "months",
		])

		var current := String(pending.get("player_vote", Bloc.VOTE_ABSTAIN))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for choice in Bloc.VOTE_CHOICES:
			var button := Button.new()
			button.text = choice.capitalize()
			button.disabled = choice == current
			# An abstention is in the denominator and neither numerator, so sitting
			# out makes passage harder without spending anything on opposing it.
			# Said here because it is the one rule of this panel a player would
			# otherwise have to infer from a tally.
			if choice == Bloc.VOTE_ABSTAIN:
				button.tooltip_text = "Counted against the threshold, for neither side."
			button.pressed.connect(_on_vote.bind(choice))
			row.add_child(button)
		_body.add_child(row)
		_caption("Currently: %s. %s holds %d of the council's seats." % [
			current, ns.id, _loader.eu.ep_seats(ns.id),
		])

	var last: Dictionary = Bloc.last_vote(_state)
	if not last.is_empty():
		_line("")
		_line("Last division: %s — %s" % [
			String(last.get("name", "")), "carried" if bool(last.get("passed", false)) else "fell",
		])
		_caption("%d for, %d against, of %d seats. %s voted %s." % [
			int(last.get("seats_for", 0)), int(last.get("seats_against", 0)),
			int(last.get("seats_total", 0)), ns.id, String(last.get("player_vote", "")),
		])
		_refresh_why(last)
	_line("")


## V1.3e. WHY each member voted as it did, not only how.
##
## Until this session the eight voted on ideology alone and there was nothing to
## say -- a reason would have read "because of who they are" for every member on
## every proposal. Now they price a proposal against their own books, and the
## division is only legible if the player can see that Luxembourg opposed a fund it
## would pay for while Italy backed one it would draw on.
##
## Grouped by reason rather than listed per nation: eight rows of one nation each
## is a table the player reads once and never again, and the interesting object is
## the CAMP. The reasons are recorded at the moment of the division by
## src/sim/bloc.gd, not recomputed here -- the books a member voted on were that
## month's.
func _refresh_why(last: Dictionary) -> void:
	var reasons: Dictionary = last.get("reasons", {})
	if reasons.is_empty():
		return
	var votes: Dictionary = last.get("votes", {})

	var camps: Dictionary = {}
	var order: Array = reasons.keys()
	order.sort()
	for id in order:
		var key := String(reasons[id])
		if not camps.has(key):
			camps[key] = []
		camps[key].append("%s %s" % [
			String(id), "for" if String(votes.get(id, "")) == Bloc.VOTE_FOR else "against",
		])

	var keys: Array = camps.keys()
	keys.sort()
	for key in keys:
		_caption("%s: %s" % [_vote_reason_text(String(key)), ", ".join(camps[key])])


## The model returns a key; the wording lives here, because src/sim/ does not know
## the UI exists and a test should not assert on prose.
func _vote_reason_text(key: String) -> String:
	match key:
		ForeignPolicy.VOTE_REASON_DRAWS_ON_IT: return "stood to draw on it"
		ForeignPolicy.VOTE_REASON_ALREADY_IN_BREACH: return "already outside the rule"
		ForeignPolicy.VOTE_REASON_WOULD_PAY: return "would have to pay for it"
		ForeignPolicy.VOTE_REASON_TRADES_OUTSIDE: return "trades outside the bloc"
		ForeignPolicy.VOTE_REASON_POLITICS: return "on the politics of it"
	return key


## What binds, and what each rule is costing THIS nation rather than only what it
## says. A rule the player complies with reads as compliant rather than vanishing:
## the constraint is the interesting part, which is nation_panel.gd's own argument
## for showing unavailable actions.
func _refresh_rules(ns) -> void:
	_heading("RULES IN FORCE")

	var rules := Bloc.rules_in_force(_state, ns)
	if rules.is_empty():
		_caption("None. Nothing the council has adopted constrains domestic policy.")
	for rule in rules:
		var field: String = String(rule.get("field", ""))
		if field == "":
			_line("%s — no policy constraint" % String(rule.get("name", "")))
			continue
		_line("%s — %s %s %.1f" % [
			String(rule.get("name", "")),
			BK.CONSTRAINT_LABEL.get(field, field),
			BK.CONSTRAINT_OP_LABEL.get(String(rule.get("op", "")), String(rule.get("op", ""))),
			float(rule.get("value", 0.0)),
		])
		if float(rule["breach"]) <= 0.0:
			_caption("    compliant")
		else:
			_caption("    outside by %.2f — %.0f%% of this rule's weight" % [
				float(rule["breach"]),
				100.0 * float(rule["contribution"]) / maxf(float(rule["severity"]), 0.0001),
			])

	_line("")
	_line("Standing: %.2f of a possible %.2f" % [ns.bloc_burden, BK.BURDEN_MAX])
	_caption("What the electorate weighs under 'Europe'. Zero while you comply — a rule you keep costs you the policy you could not run, not this.")
	_line("")


func _refresh_contribution(ns) -> void:
	_heading("THE BUDGET")
	var parts := Bloc.transfer_breakdown(_state, ns)
	_line("Net contribution: %+.3f%% of GDP" % float(parts["base"]))
	if not is_zero_approx(float(parts["rules"])):
		_line("Adopted programmes: %+.3f%% of GDP" % float(parts["rules"]))
	if not is_zero_approx(float(parts["fine"])):
		_line("Penalties: %+.3f%% of GDP" % float(parts["fine"]))
	_line("Total: %+.3f%% of GDP" % ns.bloc_transfer_pct_gdp)
	_caption("Charged on the spending side of the budget panel. One point of VAT is worth about 0.53%% of GDP.")


func _on_vote(choice: String) -> void:
	var before := Trends.snapshot_now(_state)
	Bloc.cast_vote(_state, choice)
	voted.emit(before, "Council vote: %s" % choice)
	_dirty = true


func _heading(text: String) -> void:
	var label := Label.new()
	label.theme_type_variation = UiTheme.HEADING
	label.text = text
	_body.add_child(label)


func _line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(label)


func _caption(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = UiTheme.CAPTION
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(label)
