extends PanelContainer

## The organisations surface, V3.2: what each council is voting on, how the
## player voted, what carried, which rules bind, what membership in each org
## charges -- and, for the orgs the player stands outside, what those orgs are
## doing TO them.
##
## Generalises src/ui/bloc_panel.gd (V1.3d), whose window was "The Union"
## because there was exactly one org and its membership was hardcoded. The
## register replaced the hardcoding; this panel walks `loader.orgs` in sorted
## order and asks each one the questions the old panel asked the one.
##
## Its own window rather than a section of nation_panel.gd, and that is the one
## UI call V1.3d had to make: the nation panel is where you act ON a nation you
## have clicked, and an org is not a nation and has no pixel on the map to
## click.
##
## Read-only over sim state like every other panel: the vote leaves as an
## explicit command (Orgs.cast_vote), and nothing here writes GameState. See
## docs/engine-decision.md Rule 2 and docs/orgs-model.md.
##
## Built in code, like the other panels -- see budget_panel.gd's placement note.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Council = preload("res://src/sim/council.gd")
const BK = preload("res://src/sim/bloc_constants.gd")
const CouncilSection = preload("res://src/ui/council_section.gd")
const Relations = preload("res://src/core/relations.gd")
const Ratification = preload("res://src/sim/ratification.gd")
const Trends = preload("res://src/ui/trends.gd")

signal closed

## V1.6 audit, V8. The council vote was the only player command in the game with
## no signal, so it was the only one that never reached Overview's RECENT
## DECISIONS -- a decision binding on the player that the surface built to say
## what you did could not name. Same shape as nation_panel.acted.
signal voted(before, label)

## The accession/withdrawal verbs, same shape as nation_panel.acted: a
## membership fight is a decision the player took and Overview should name.
signal acted(before, label)

var _state
var _loader
var _title: Label
var _body: VBoxContainer
var _dirty := true
var _close_button: Button

## The first enabled verb this panel built on its last refresh. See primary_action().
var _primary: Control = null
## True once a deadline-bearing verb (a treaty waiting on the player's assembly)
## has taken `_primary`; later offers and claims then leave it alone.
var _primary_claimed := false

## A verb the machine refused, spoken on the NEXT refresh rather than appended
## and immediately queue_free'd -- the first version added the line and then
## marked the panel dirty, so the refresh erased it before a frame passed and
## the message was a dead write.
var _refusal_text := ""

## Which folds of the council block are open ("room:<org>", "agenda:<org>"). On the
## panel, not the section, because the body is rebuilt on every refresh.
var _open_sections: Dictionary = {}


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
	_primary = null
	_primary_claimed = false

	for child in _body.get_children():
		child.queue_free()

	var memberships: int = ns.orgs.size()
	_title.text = "Organisations — %d, %d of them yours" % [_loader.orgs.size(), memberships]

	if not _refusal_text.is_empty():
		PanelKit.line(_body, _refusal_text)
		_refusal_text = ""

	for org in _loader.orgs:
		if ns.orgs.has(org.id):
			_refresh_member_org(ns, org)
		else:
			_refresh_outsider_org(ns, org)


## One org the player belongs to: its council when it has one, the rules of
## ITS that bind this nation, and what membership in it charges.
func _refresh_member_org(ns, org) -> void:
	PanelKit.heading(_body, org.name.to_upper())
	if not org.summary.is_empty():
		PanelKit.line(_body, org.summary, PanelKit.Tone.PLAIN)

	if org.council:
		CouncilSection.build(_body, self, _state, _loader, ns, org)
		_refresh_rules(ns, org)
	if org.net_transfers:
		_refresh_contribution(ns, org)
	_refresh_membership_verb(ns, org)
	PanelKit.line(_body, "", PanelKit.Tone.PLAIN)


## What THIS org's rules bind, and what each is costing THIS nation rather than
## only what it says. A rule the player complies with reads as compliant rather
## than vanishing: the constraint is the interesting part, which is
## nation_panel.gd's own argument for showing unavailable actions.
func _refresh_rules(ns, org) -> void:
	PanelKit.heading(_body, "RULES IN FORCE")

	var rules := Orgs.rules_in_force(_state, ns)
	var org_rules: Array = []
	for rule in rules:
		if String(rule.get("org_id", "")) == org.id:
			org_rules.append(rule)
	if org_rules.is_empty():
		PanelKit.line(_body, "None. Nothing this council has adopted constrains domestic policy.")
	for rule in org_rules:
		var field: String = String(rule.get("field", ""))
		if field == "":
			PanelKit.line(_body, "%s — no policy constraint" % String(rule.get("name", "")), PanelKit.Tone.PLAIN)
			continue
		PanelKit.line(_body, "%s — %s %s %.1f" % [
			String(rule.get("name", "")),
			BK.CONSTRAINT_LABEL.get(field, field),
			BK.CONSTRAINT_OP_LABEL.get(String(rule.get("op", "")), String(rule.get("op", ""))),
			float(rule.get("value", 0.0)),
		], PanelKit.Tone.PLAIN)
		if float(rule["breach"]) <= 0.0:
			PanelKit.line(_body, "    compliant")
		else:
			PanelKit.line(_body, "    outside by %.2f — %.0f%% of this rule's weight" % [
				float(rule["breach"]),
				100.0 * float(rule["contribution"]) / maxf(float(rule["severity"]), 0.0001),
			])

	# The ONE opinion price: summed over every org and clamped once, said here
	# once rather than repeated under each org's rules.
	PanelKit.line(_body, "", PanelKit.Tone.PLAIN)
	PanelKit.line(_body, "Standing: %.2f of a possible %.2f, across every organisation" % [ns.bloc_burden, BK.BURDEN_MAX], PanelKit.Tone.PLAIN)
	PanelKit.line(_body, "What the electorate weighs under 'Europe'. Zero while you comply — a rule you keep costs you the policy you could not run, not this.")
	PanelKit.line(_body, "", PanelKit.Tone.PLAIN)


func _refresh_contribution(ns, org) -> void:
	PanelKit.heading(_body, "THE BUDGET")
	var parts := Orgs.transfer_breakdown(_state, ns)
	var per_org: Dictionary = (parts.get("orgs", {}) as Dictionary).get(org.id, {})
	PanelKit.line(_body, "Net contribution: %+.3f%% of GDP" % float(per_org.get("base", 0.0)), PanelKit.Tone.PLAIN)
	if not is_zero_approx(float(per_org.get("rules", 0.0))):
		PanelKit.line(_body, "Adopted programmes: %+.3f%% of GDP" % float(per_org.get("rules", 0.0)), PanelKit.Tone.PLAIN)
	if not is_zero_approx(float(per_org.get("fine", 0.0))):
		PanelKit.line(_body, "Penalties: %+.3f%% of GDP" % float(per_org.get("fine", 0.0)), PanelKit.Tone.PLAIN)
	if not is_zero_approx(float(per_org.get("aid", 0.0))):
		PanelKit.line(_body, "Side-payments (aid): %+.3f%% of GDP" % float(per_org.get("aid", 0.0)), PanelKit.Tone.PLAIN)
	PanelKit.line(_body, "All organisations, total: %+.3f%% of GDP" % float(parts.get("total", 0.0)), PanelKit.Tone.PLAIN)
	PanelKit.line(_body, "Charged on the spending side of the budget panel. One point of VAT is worth about 0.53% of GDP.")


## A non-member's view of one org. The done-when V1.2d's cold read would have
## caught: two of the three playable nations are outside the EU, and a session
## that gave them nothing would be shipping a mechanic one nation in three can
## touch. What they get is the receiving end -- an org acting as one is the only
## thing in this game that imposes from many directions at once.
func _refresh_outsider_org(ns, org) -> void:
	PanelKit.heading(_body, org.name.to_upper())
	if not org.summary.is_empty():
		PanelKit.line(_body, org.summary, PanelKit.Tone.PLAIN)
	PanelKit.line(_body, "%s is not a member. It has no vote in this council and no rule of it binds %s." % [ns.id, ns.id], PanelKit.Tone.PLAIN)

	if not org.council:
		_refresh_membership_verb(ns, org)
		PanelKit.line(_body, "", PanelKit.Tone.PLAIN)
		return

	PanelKit.heading(_body, "MEASURES FROM MEMBERS")
	var members := Orgs.members(_state, org.id)
	var levied := 0
	var worst := 0.0
	for member_id in members:
		var terms = _state.measures.get(Relations.directed_key(member_id, ns.id))
		if terms == null:
			continue
		levied += 1
		worst = maxf(worst, float(terms.get("severity", 0.0)))
		PanelKit.line(_body, "%s: %s, severity %.2f" % [
			member_id, terms.get("action_name", terms.get("action_id", "")),
			float(terms.get("severity", 0.0)),
		], PanelKit.Tone.PLAIN)
	if levied == 0:
		PanelKit.line(_body, "None. The council has adopted no common external measure.")
	else:
		PanelKit.line(_body, "", PanelKit.Tone.PLAIN)
		PanelKit.line(_body, "%d of %d members levying, worst severity %.2f." % [levied, members.size(), worst], PanelKit.Tone.PLAIN)
		PanelKit.line(_body, "An organisation acting as one is the only thing in this game that imposes from more than one direction at once.")


## One membership verb per org section: Join when outside, Leave when inside.
## A membership fight is referendum-first, so the button ASKS THE COUNTRY
## rather than flipping membership -- what it starts is a multi-year domestic
## fight whose terms the org file authors, and the refusal reasons are the
## machine's own, shown in the tooltip (the nation-panel unavailable-verb
## pattern).
func _refresh_membership_verb(ns, org) -> void:
	var joining: bool = not ns.orgs.has(org.id)
	var button := Button.new()
	button.text = ("Begin leaving %s" % org.name) if not joining else ("Begin joining %s" % org.name)
	var fight_running := false
	for fight in _state.accessions:
		if String(fight.get("nation_id", "")) == ns.id:
			fight_running = true
			break
	if fight_running:
		button.disabled = true
		button.tooltip_text = "A membership fight is already running."
	elif joining and org.accession_months == 0:
		button.disabled = true
		button.tooltip_text = "This organisation has no accession process."
	elif not joining and org.withdrawal_months == 0:
		button.disabled = true
		button.tooltip_text = "This organisation has no withdrawal process."
	elif not ns.referendum_pending.is_empty():
		button.disabled = true
		button.tooltip_text = "A referendum is already before the country."
	else:
		button.tooltip_text = "Puts the question to the country by referendum first; the negotiation that follows runs %d months." % (
			int(org.accession_months) if joining else int(org.withdrawal_months))
		button.pressed.connect(_on_membership.bind(org.id, joining))
		if _primary == null:
			_primary = button
	_body.add_child(button)


func _on_membership(org_id: String, joining: bool) -> void:
	var before := Trends.snapshot_now(_state)
	var ns = _state.player()
	var result: Dictionary = Orgs.begin_accession(_state, _loader, ns, org_id) if joining 		else Orgs.begin_withdrawal(_state, _loader, ns, org_id)
	if not bool(result.get("ok", false)):
		# Refused at the machine; the tooltip said why already, but a press that
		# did nothing is the silent-failure class, so the reason is spoken -- on
		# the next refresh, which the dirty flag triggers. Carried as a member
		# rather than appended: a line added here is queue_free'd by the very
		# refresh this mark schedules.
		_refusal_text = "Refused: %s" % String(result.get("reason", ""))
		_dirty = true
		return
	acted.emit(before, "Membership referendum called: %s %s %s" % [
		ns.id, "joins" if joining else "leaves", org_id.to_upper(),
	])
	_dirty = true


func _on_vote(org_id: String, choice: String) -> void:
	var before := Trends.snapshot_now(_state)
	if not Orgs.cast_vote(_state, org_id, choice):
		# Same silent-failure class as _on_membership: a press the machine refused
		# must not report a decision to Overview's RECENT DECISIONS.
		_refusal_text = "Refused: that vote can no longer be cast."
		_dirty = true
		return
	voted.emit(before, "Council vote (%s): %s" % [org_id.to_upper(), choice])
	_dirty = true


func is_section_open(key: String) -> bool:
	return bool(_open_sections.get(key, false))


func set_section_open(key: String, open: bool) -> void:
	_open_sections[key] = open


func _on_bargain(org_id: String, target_id: String, currency: String, ask: String) -> void:
	var before := Trends.snapshot_now(_state)
	if not Council.bargain(_state, org_id, target_id, currency, ask):
		_refusal_text = "Refused: that bargain can no longer be struck."
		_dirty = true
		return
	acted.emit(before, "Council bargain (%s): %s with %s" % [
		org_id.to_upper(), currency.replace("_", " "), _loader.nation_name(target_id),
	])
	_dirty = true


func _on_ratify(org_id: String) -> void:
	var before := Trends.snapshot_now(_state)
	# Read before submitting: the register clears its ratifying block on a verdict.
	var treaty := String((_state.orgs[org_id].get("ratifying", {}) as Dictionary).get("name", ""))
	var result: Dictionary = Ratification.submit(_state, _loader, org_id)
	if result.has("refused"):
		_refusal_text = "Refused: the treaty can no longer be put to the assembly."
		_dirty = true
		return
	acted.emit(before, "Treaty put to the assembly: %s — %s" % [
		treaty, "ratified" if bool(result.get("passed", false)) else "rejected",
	])
	_dirty = true


func _on_set_agenda(org_id: String, proposal_id: String) -> void:
	var before := Trends.snapshot_now(_state)
	if not Orgs.set_agenda(_state, _loader, org_id, proposal_id):
		_refusal_text = "Refused: that proposal cannot be put first."
		_dirty = true
		return
	acted.emit(before, "Council agenda (%s): you put %s first" % [org_id.to_upper(), _proposal_label(org_id, proposal_id)])
	_dirty = true


func _on_table(org_id: String, proposal_id: String) -> void:
	var before := Trends.snapshot_now(_state)
	if not Orgs.table_proposal(_state, _loader, org_id, proposal_id):
		_refusal_text = "Refused: the chair will not table that now."
		_dirty = true
		return
	acted.emit(before, "Council agenda (%s): tabled %s" % [org_id.to_upper(), _proposal_label(org_id, proposal_id)])
	_dirty = true


func _proposal_label(org_id: String, proposal_id: String) -> String:
	var p = Orgs.proposal_by_id(_loader, org_id, proposal_id)
	return String(p.proposal_name) if p != null else proposal_id


## Called by CouncilSection for each enabled verb it builds; the first one wins.
func offer_primary(control: Control) -> void:
	if _primary == null:
		_primary = control


## A verb with a deadline outranks whatever came first in build order. Without
## this the ratify card lost the primary slot to an earlier org's membership
## button: FRA sits in the climate accord, which is listed before the EU.
func claim_primary(control: Control) -> void:
	if not _primary_claimed:
		_primary = control
		_primary_claimed = true


## The control this panel exists to let the player press -- V2.1a's fold contract,
## declared here at V2.1b.
##
## The councils' vote buttons are rebuilt on every refresh and the one the
## player already holds is disabled, so this is the FIRST ENABLED verb in build
## order rather than a member held from _ready(). Null while no proposal is
## pending anywhere, which is most months: the panel is then a readout and has
## no verb to put above the fold.
func primary_action() -> Control:
	return _primary
