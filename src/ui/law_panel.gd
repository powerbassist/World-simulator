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
const Government = preload("res://src/sim/government.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Law = preload("res://src/core/law.gd")
const Trends = preload("res://src/ui/trends.gd")
const Referendum = preload("res://src/sim/referendum.gd")
const ReferendumK = preload("res://src/sim/referendum_constants.gd")

## Wider than legislature_constants.ABSTAIN_BAND (0.05) on purpose -- the real
## vote resolves exactly off the same support() value, but the forecast blurs
## a wider band around zero so a close vote is not readable in advance.
const FORECAST_UNCERTAIN_BAND := 0.15

## Carries the pre-vote baseline (Trends.snapshot_now()) and the law's name --
## same reasoning as budget_panel.gd's committed signal. Emitted whether the
## bill passed or not; main.gd only queues an effect worth measuring once a
## month has actually elapsed against it, which a failed vote changes nothing
## to distinguish -- an entry that shows "nothing moved" is still correct.
signal proposed(before: Dictionary, law_name: String)

var _state
var _loader
var _title: Label
var _list: VBoxContainer
var _result_box: VBoxContainer
var _dirty := true
var _close_button: Button


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

	_close_button = Button.new()
	_close_button.text = "Close (L)"
	_close_button.pressed.connect(func(): hide())
	row.add_child(_close_button)

	return row


## Docked-tab mode -- see budget_panel.gd's hide_close_button() for why.
func hide_close_button() -> void:
	_close_button.hide()


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

	# A referendum in flight is the first thing on this page, because while one is
	# running it is the only thing the assembly's own list cannot tell the player.
	if Referendum.is_pending(ns):
		_list.add_child(_build_pending_referendum(ns))

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

	# A carried division on route B is a THIRD outcome and neither word fits it: the
	# assembly said yes and the country has not been asked. Reading "FAILED" against a
	# referendum the player just called is the em-dash-against-a-live-figure bug
	# docs/defence-model.md's screenshot pass found, one block on.
	var verdict := "PASSED" if result["passed"] else "FAILED"
	if result.get("referendum_called", false):
		verdict = "PUT TO THE COUNTRY"
	var heading := Label.new()
	heading.text = "%s — %s" % [law_label, verdict]
	box.add_child(heading)

	if result.get("referendum_route", false) and result.get("refused", false):
		var no_route := Label.new()
		no_route.text = "This constitution has no referendum route for that."
		box.add_child(no_route)
		return box

	# A forced bill had no division, so the seat tally would read all zeroes.
	# What happened instead is the censure motion.
	if result.get("forced", false):
		if result.get("refused", false):
			var refused := Label.new()
			refused.text = "Article 49.3 is not available."
			box.add_child(refused)
			return box
		box.add_child(_build_censure_summary(result.get("censure", {})))
		return box

	var tally := Label.new()
	tally.text = "Yes %d · No %d · Abstain %d, of %d seats" % [
		result["yes_seats"], result["no_seats"], result["abstain_seats"], result["seats_total"]
	]
	box.add_child(tally)

	var rebellion := _rebellion_text(result.get("party_rebels", {}))
	if rebellion != "":
		var broke := Label.new()
		broke.text = rebellion
		broke.autowrap_mode = TextServer.AUTOWRAP_WORD
		box.add_child(broke)

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


## What the assembly did about being bypassed. Names the parties that moved to
## censure, so a survived 49.3 still tells the player who came after them.
func _build_censure_summary(censure: Dictionary) -> Control:
	var box := VBoxContainer.new()
	if censure.is_empty():
		return box

	var ns = _state.player()

	var forced := Label.new()
	forced.text = "Adopted without a vote under Article 49.3."
	box.add_child(forced)

	var tally := Label.new()
	tally.text = "Censure motion: %d for · %d against · %d abstained, of %d seats (needs %d)" % [
		censure["for_seats"], censure["against_seats"], censure["abstain_seats"],
		censure["seats_total"], censure["threshold"],
	]
	box.add_child(tally)

	var verdict := Label.new()
	if censure["carried"]:
		verdict.text = "CENSURED. %s falls; %s %s now heads the government." % [
			_loader.person_name(censure["pm_person_id"]), ns.head_of_government_title, _loader.person_name(ns.pm_person_id)
		]
	else:
		verdict.text = "The motion failed. %s %s survives and the law stands." % [
			ns.head_of_government_title, _loader.person_name(ns.pm_person_id)
		]
	box.add_child(verdict)

	var movers := PackedStringArray()
	for party in _loader.parties.get(ns.id, []):
		if censure["party_votes"].get(party.id, "") == "for":
			movers.append(party.party_name)
	if not movers.is_empty():
		var who := Label.new()
		who.text = "Moved to censure: %s" % ", ".join(movers)
		who.autowrap_mode = TextServer.AUTOWRAP_WORD
		box.add_child(who)

	var rebellion := _rebellion_text(censure.get("party_rebels", {}))
	if rebellion != "":
		var broke := Label.new()
		broke.text = rebellion
		broke.autowrap_mode = TextServer.AUTOWRAP_WORD
		box.add_child(broke)

	# Distinct from the line above on purpose: that one is members who ignored
	# their party, this one is parties that walked. Only the second is expelled.
	var defectors: Array = censure["defectors"]
	if not defectors.is_empty():
		var lost := Label.new()
		lost.text = "%d coalition party(s) voted to censure and are out of government." % defectors.size()
		box.add_child(lost)

	return box


## Who ignored their own party's line, and by how much. The payoff line of the
## whole discipline model -- the player is told which benches they have lost, by
## name, at the moment it costs them a vote.
func _rebellion_text(party_rebels: Dictionary) -> String:
	if party_rebels.is_empty():
		return ""
	var parts := PackedStringArray()
	var total := 0
	for party in _loader.parties.get(_state.player().id, []):
		var rebels: int = int(party_rebels.get(party.id, 0))
		if rebels <= 0:
			continue
		total += rebels
		parts.append("%d %s" % [rebels, party.party_name])
	if parts.is_empty():
		return ""
	return "%d seats broke ranks: %s." % [total, ", ".join(parts)]


## A constitutional amendment reads its OWN nation's real threshold rather
## than the literal string "amendment" -- law.majority only tells
## resolve_vote() to look at ns.amendment_rule, and this is where the display
## does the same lookup. See docs/amendment-model.md.
func _majority_phrase(ns, law) -> String:
	if not law.constitutional:
		return "%s majority" % law.majority
	match ns.amendment_rule:
		"ordinary_law": return "ordinary majority"
		"three_fifths": return "3/5 majority"
		"two_thirds": return "2/3 majority"
		"three_quarters": return "3/4 majority"
		"referendum_required": return "ordinary majority, then a referendum"
		_: return ns.amendment_rule


func _build_law_row(ns, party_list: Array, law) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var heading := Label.new()
	heading.text = "%s  (%s, %s)" % [law.law_name, law.theme, _majority_phrase(ns, law)]
	box.add_child(heading)

	# A system transition rewrites the whole constitution, not one field --
	# named here structurally, off the loaded template's own display_name,
	# rather than left to the law's own summary prose to stay accurate. See
	# docs/transition-model.md.
	if law.changes_system:
		var target_system_id: String = law.effects.get("institutional", {}).get("system_id", "")
		var target = _loader.political_systems.get(target_system_id)
		var target_label: String = target.display_name if target != null else target_system_id
		var target_line := Label.new()
		target_line.text = "Rewrites the constitution to a %s." % target_label
		box.add_child(target_line)

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

	# Article 49.3 exists only under a constitution that has it, and cannot force
	# a constitutional amendment through -- Art. 89's revision procedure has no
	# executive bypass. See docs/amendment-model.md.
	if ns.formation_method == "presidential_appointment" and not law.constitutional:
		var force_btn := Button.new()
		force_btn.text = "Force (49.3)"
		force_btn.disabled = not Government.can_force(ns)
		if force_btn.disabled:
			force_btn.tooltip_text = "Available again in %d months." % ns.force_cooldown_months
		else:
			force_btn.tooltip_text = "Adopt without a vote. The assembly may censure the government instead."
		force_btn.pressed.connect(_on_force.bind(law))
		row.add_child(force_btn)

	# Route B. Offered only where the constitution has one and only for an
	# entrenched change -- Legislature.can_put_to_referendum() is the single
	# authority and this asks it rather than re-deriving the rule. A nation whose
	# route is MANDATORY gets no button, because there is nothing to choose: the
	# Propose button already goes to the country.
	if Legislature.can_put_to_referendum(ns, law):
		var ref_btn := Button.new()
		ref_btn.text = "Referendum"
		ref_btn.tooltip_text = (
			"Pass it by an ordinary majority here, then put it to the country in %d months. "
			+ "Winning is a mandate and losing is a rebuke, and it cannot be called off for free."
		) % ReferendumK.REFERENDUM_DELAY_MONTHS
		ref_btn.pressed.connect(_on_referendum.bind(law))
		row.add_child(ref_btn)

	box.add_child(row)
	return box


## What the country has been asked, when it answers, and what the polls say it
## would answer if it answered today.
##
## The forecast is NOT blurred the way the assembly's is, and the difference is the
## quantity rather than the surface: a seat forecast hides a division that has not
## happened, where this reads Referendum.yes_share() -- the same function the vote
## itself will call, against state that will have moved by then. What makes it
## uncertain is the months, not a band.
func _build_pending_referendum(ns) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var law: Law = _find_law(Referendum.pending_law_id(ns))
	var heading := Label.new()
	heading.text = "REFERENDUM CALLED — %s" % (law.law_name if law != null else Referendum.pending_law_id(ns))
	box.add_child(heading)

	var months := Referendum.months_left(ns)
	var share := Referendum.yes_share(ns, ns.referendum_pending.get("position", {}))
	var line := Label.new()
	line.text = "The country votes in %d %s. If it voted today: %.1f%% yes, %.1f%% no." % [
		months, "month" if months == 1 else "months", share * 100.0, (1.0 - share) * 100.0
	]
	line.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(line)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var cost := Label.new()
	cost.text = "Calling it off costs exactly what losing it costs."
	cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD
	row.add_child(cost)

	var withdraw_btn := Button.new()
	withdraw_btn.text = "Call it off"
	withdraw_btn.tooltip_text = (
		"The same %.2f against every bloc a lost vote would charge, and the same cooldown. "
		+ "What it buys is the slot back now rather than in %d months."
	) % [ReferendumK.REFERENDUM_RESULT_OFFSET, months]
	withdraw_btn.pressed.connect(_on_withdraw)
	row.add_child(withdraw_btn)

	box.add_child(row)
	return box


## The blur is unchanged: a party whose |support| falls inside
## FORECAST_UNCERTAIN_BAND lands in "undecided" rather than a firm column.
##
## Rebel seats are counted into the column they will actually vote in, not left
## inside their party's block. They are not a second kind of uncertainty -- the
## split is deterministic and the government panel already publishes it per
## party, so hiding it here would make the forecast lie in one direction only.
func _forecast_text(ns, party_list: Array, law) -> String:
	var yes := 0
	var no := 0
	var undecided := 0
	var rebels := 0

	for party in party_list:
		var s: float = Legislature.support(ns, party, law)
		var own: float = Legislature.spatial_support(ns, party, law)
		var seats: int = int(ns.seats_by_party.get(party.id, 0))

		var broke := 0
		if Legislature.vote_of(own) != Legislature.vote_of(s):
			broke = Discipline.rebel_seats(ns, party, s, own)
		rebels += broke

		if s > FORECAST_UNCERTAIN_BAND:
			yes += seats - broke
		elif s < -FORECAST_UNCERTAIN_BAND:
			no += seats - broke
		else:
			undecided += seats - broke

		if own > FORECAST_UNCERTAIN_BAND:
			yes += broke
		elif own < -FORECAST_UNCERTAIN_BAND:
			no += broke
		else:
			undecided += broke

	var text := "%d for · %d against · %d undecided" % [yes, no, undecided]
	if rebels > 0:
		text += "  (%d expected to break ranks)" % rebels
	return text


func _on_propose(law) -> void:
	var before := Trends.snapshot_now(_state)
	Legislature.propose(_state, _loader, law)
	proposed.emit(before, law.law_name)
	_dirty = true


func _on_referendum(law) -> void:
	var before := Trends.snapshot_now(_state)
	Legislature.propose(_state, _loader, law, false, true)
	proposed.emit(before, law.law_name)


func _on_withdraw() -> void:
	var ns = _state.player()
	var law: Law = _find_law(Referendum.pending_law_id(ns))
	var law_name: String = law.law_name if law != null else Referendum.pending_law_id(ns)
	var before := Trends.snapshot_now(_state)
	Referendum.withdraw(ns)
	proposed.emit(before, law_name)


func _on_force(law) -> void:
	var before := Trends.snapshot_now(_state)
	Legislature.propose(_state, _loader, law, true)
	proposed.emit(before, law.law_name)
	_dirty = true


func _find_law(law_id: String):
	for law in _loader.laws:
		if law.id == law_id:
			return law
	return null
