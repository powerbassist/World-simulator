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

const PanelKit = preload("res://src/ui/panel_kit.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Government = preload("res://src/sim/government.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Law = preload("res://src/core/law.gd")
const Trends = preload("res://src/ui/trends.gd")
const Referendum = preload("res://src/sim/referendum.gd")
const Chambers = preload("res://src/sim/chambers.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
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

## The first enabled verb this panel built on its last refresh. See primary_action().
var _primary: Control = null


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
	_primary = null

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

	# V1.1e. A bill the second chamber is holding, for the same reason: it is in
	# flight, it is off the list below, and it is the only thing that list cannot say.
	for law_id in ns.held_bills:
		_list.add_child(_build_held_bill(ns, String(law_id)))

	var party_list: Array = _loader.parties.get(ns.id, [])
	var available: Array = Legislature.available(ns, _loader.laws)
	if available.is_empty():
		PanelKit.line(_list, "No law is currently proposable.", PanelKit.Tone.PLAIN)
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
	# V1.1e. Three more outcomes that are not `FAILED`, for the same reason route B
	# is not: a bill the second chamber is holding has not been beaten, a bill it
	# blocked was beaten somewhere the tally below does not show, and a bill the court
	# struck was carried by both chambers and stopped afterwards. One word for four
	# different things is the readout bug this project keeps finding.
	elif result.get("held_by_upper", false):
		verdict = "HELD BY THE %s" % result.get("upper_chamber", "SECOND CHAMBER").to_upper()
	elif result.get("blocked_by_upper", false):
		verdict = "BLOCKED BY THE %s" % result.get("upper_chamber", "SECOND CHAMBER").to_upper()
	elif result.get("struck_down", false):
		verdict = "STRUCK DOWN"
	elif result.get("released", false):
		verdict = "IN FORCE, OVER THE %s" % result.get("upper_chamber", "SECOND CHAMBER").to_upper()
	PanelKit.line(box, "%s — %s" % [law_label, verdict], PanelKit.Tone.PLAIN)

	# V2.8 review. Two more outcomes with no division behind them, and the tally
	# below would print "Yes 0 - No 0 - Abstain 0, of 577 seats" against both --
	# a chamber that never sat, reported as one that voted the bill down. Same
	# class as the four verdicts above, which is why they are branches and not a
	# shared "refused" word.
	if result.get("unavailable", false):
		PanelKit.line(box, "That is not open to the assembly right now.", PanelKit.Tone.PLAIN)
		return box

	if result.get("referendum_in_flight", false):
		PanelKit.line(box, "The country is already voting on something else.", PanelKit.Tone.PLAIN)
		return box

	if result.get("referendum_route", false) and result.get("refused", false):
		PanelKit.line(box, "This constitution has no referendum route for that.", PanelKit.Tone.PLAIN)
		return box

	# A forced bill had no division, so the seat tally would read all zeroes.
	# What happened instead is the censure motion.
	if result.get("forced", false):
		if result.get("refused", false):
			PanelKit.line(box, "Article 49.3 is not available.", PanelKit.Tone.PLAIN)
			return box
		box.add_child(_build_censure_summary(result.get("censure", {})))
		return box

	var tally := Label.new()
	tally.text = "Yes %d · No %d · Abstain %d, of %d seats" % [
		result["yes_seats"], result["no_seats"], result["abstain_seats"], result["seats_total"]
	]
	box.add_child(tally)

	# V1.1e. What the second chamber did, under the Assembly's own tally rather than
	# beside it, because the two are the same division read twice.
	if result.has("upper_passed"):
		PanelKit.line(box, "%s: Yes %d · No %d · Abstain %d, of %d seats" % [
			result.get("upper_chamber", "Second chamber"),
			result["upper_yes_seats"], result["upper_no_seats"],
			result["upper_abstain_seats"], result["upper_seats_total"],
		], PanelKit.Tone.PLAIN)
		if bool(result.get("held_by_upper", false)):
			var held := Label.new()
			# WHAT THE CHAMBER DID, not when the bill arrives -- the twenty-first screenshot
			# pass found this frame reading "comes into force in 12 months" here and "in 9
			# months" in the held block directly below it, which is two numbers for one fact
			# on one screen. This box is a record of a division that has already happened and
			# never counts down; the block below is the live one.
			held.text = "It is held for %d months, and overriding them costs %.2f with every bloc." % [
				int(result.get("held_months", 0)), ChambersK.UPPER_OVERRIDE_OFFSET]
			held.autowrap_mode = TextServer.AUTOWRAP_WORD
			box.add_child(held)

	# V1.1e. The court, and it names the ARITHMETIC as well as the verdict -- a rule the
	# player cannot read is not a check on their power, it is a trap. See
	# docs/judiciary-model.md.
	if bool(result.get("struck_down", false)):
		PanelKit.line(box, "The court struck it down: it reaches %.2f against a tolerance of %.2f." % [
			float(result.get("reach", 0.0)), float(result.get("tolerance", 0.0))], PanelKit.Tone.PLAIN)

	var rebellion := _rebellion_text(result.get("party_rebels", {}))
	if rebellion != "":
		PanelKit.line(box, rebellion, PanelKit.Tone.PLAIN)

	if not result["passed"]:
		var opposed := PackedStringArray()
		for party in _loader.parties.get(_state.player().id, []):
			if result["party_votes"].get(party.id, "") == "no":
				opposed.append(party.party_name)
		if not opposed.is_empty():
			PanelKit.line(box, "Voted against: %s" % ", ".join(opposed), PanelKit.Tone.PLAIN)

	return box


## What the assembly did about being bypassed. Names the parties that moved to
## censure, so a survived 49.3 still tells the player who came after them.
func _build_censure_summary(censure: Dictionary) -> Control:
	var box := VBoxContainer.new()
	if censure.is_empty():
		return box

	var ns = _state.player()

	PanelKit.line(box, "Adopted without a vote under Article 49.3.", PanelKit.Tone.PLAIN)

	PanelKit.line(box, "Censure motion: %d for · %d against · %d abstained, of %d seats (needs %d)" % [
		censure["for_seats"], censure["against_seats"], censure["abstain_seats"],
		censure["seats_total"], censure["threshold"],
	], PanelKit.Tone.PLAIN)

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
		PanelKit.line(box, rebellion, PanelKit.Tone.PLAIN)

	# Distinct from the line above on purpose: that one is members who ignored
	# their party, this one is parties that walked. Only the second is expelled.
	var defectors: Array = censure["defectors"]
	if not defectors.is_empty():
		PanelKit.line(box, "%d coalition party(s) voted to censure and are out of government." % defectors.size(), PanelKit.Tone.PLAIN)

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

	PanelKit.line(box, "%s  (%s, %s)" % [law.law_name, law.theme, _majority_phrase(ns, law)], PanelKit.Tone.PLAIN)

	# A system transition rewrites the whole constitution, not one field --
	# named here structurally, off the loaded template's own display_name,
	# rather than left to the law's own summary prose to stay accurate. See
	# docs/transition-model.md.
	if law.changes_system:
		var target_system_id: String = law.effects.get("institutional", {}).get("system_id", "")
		var target = _loader.political_systems.get(target_system_id)
		var target_label: String = target.display_name if target != null else target_system_id
		PanelKit.line(box, "Rewrites the constitution to a %s." % target_label, PanelKit.Tone.PLAIN)

	PanelKit.line(box, law.summary, PanelKit.Tone.PLAIN)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var forecast := Label.new()
	forecast.text = "Forecast: %s" % _forecast_text(ns, party_list, law)
	forecast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(forecast)

	# V1.1e. What waits AFTER the division, and the two are shown differently on
	# purpose. The second chamber's line is a FORECAST like the one above it and is
	# blurred by the same band, because a chamber is people. The court's line is not
	# blurred at all, because a court is a RULE -- see docs/judiciary-model.md.
	var after := _after_the_division(ns, party_list, law)
	if after != "":
		PanelKit.line(box, after, PanelKit.Tone.PLAIN)

	var propose_btn := Button.new()
	propose_btn.text = "Propose"
	propose_btn.pressed.connect(_on_propose.bind(law))
	_offer(propose_btn)
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
		_offer(force_btn)
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
		_offer(ref_btn)
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
	PanelKit.line(box, "REFERENDUM CALLED — %s" % (law.law_name if law != null else Referendum.pending_law_id(ns)), PanelKit.Tone.PLAIN)

	var months := Referendum.months_left(ns)
	var share := Referendum.yes_share(ns, ns.referendum_pending.get("position", {}))
	PanelKit.line(box, "The country votes in %d %s. If it voted today: %.1f%% yes, %.1f%% no." % [
		months, "month" if months == 1 else "months", share * 100.0, (1.0 - share) * 100.0
	], PanelKit.Tone.PLAIN)

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
	_offer(withdraw_btn)
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


## What the second chamber and the court will do to a bill that carries the Assembly.
## Empty when neither has anything to say, so a bill nobody can stop shows no line at
## all and the ones that do stand out.
func _after_the_division(ns, party_list: Array, law) -> String:
	var parts := PackedStringArray()

	var power: String = Chambers.power_over(ns, law)
	if power != ChambersK.VERDICT_NONE:
		var upper := Legislature.resolve_upper(ns, party_list, law)
		var margin: int = int(upper["yes_seats"]) - int(upper["no_seats"])
		if absi(margin) <= int(float(upper["seats_total"]) * FORECAST_UNCERTAIN_BAND):
			parts.append("%s: too close to call." % ns.upper_chamber_name)
		elif bool(upper["passed"]):
			parts.append("%s: expected to agree." % ns.upper_chamber_name)
		elif power == ChambersK.VERDICT_ABSOLUTE:
			parts.append("%s: expected to refuse, and it cannot be overridden." % ns.upper_chamber_name)
		else:
			parts.append("%s: expected to refuse, holding it %d months." % [
				ns.upper_chamber_name, ChambersK.UPPER_HOLD_MONTHS])

	if Judiciary.reviews(ns, law):
		var tolerance: float = Judiciary.tolerance(ns)
		if Judiciary.strikes_down(ns, law):
			parts.append("The court would strike it down: it reaches %.2f against %.2f." % [
				law.reach, tolerance])
		elif law.reach > 0.0:
			parts.append("The court would let it stand: it reaches %.2f against %.2f." % [
				law.reach, tolerance])

	return " ".join(parts)


## A bill the second chamber is holding. Its own block at the top of the page, the way
## a pending referendum has one, because the list below cannot show a bill that is not
## proposable.
func _build_held_bill(ns, law_id: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var law: Law = _find_law(law_id)
	PanelKit.line(box, "%s — held by the %s" % [
		law.law_name if law != null else law_id, ns.upper_chamber_name], PanelKit.Tone.PLAIN)

	var months: int = int(ns.held_bills.get(law_id, 0))
	PanelKit.line(box, "The Assembly carried it and the second chamber refused. It comes into force in %s, and overriding them costs %.2f with every bloc." % [
		"one month" if months == 1 else "%d months" % months, ChambersK.UPPER_OVERRIDE_OFFSET], PanelKit.Tone.PLAIN)
	return box


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


## Remembers the first enabled verb built since the last refresh, in build order.
func _offer(button: Button) -> void:
	if _primary == null and not button.disabled:
		_primary = button


## The control this panel exists to let the player press -- V2.1a's fold contract,
## declared here at V2.1b.
##
## Every verb here is rebuilt on each refresh, so this is the first enabled one in
## build order. A referendum in flight is built first and its "Call it off" is
## therefore the verb while one is running, which is right: while the country has
## been asked, that is the only decision the assembly's list cannot offer.
func primary_action() -> Control:
	return _primary
