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
const PanelCharts = preload("res://src/ui/panel_charts.gd")
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
## V4.2. The composed register reaches the list through statute.custom_laws()
## -- the same read the sim's legality scan makes, so the panel can never
## show a book the sim would refuse or hide one it would accept.
const Statute = preload("res://src/sim/statute.gd")
## V4.2 T5. The poll kinds are the constants file's vocabulary -- the same
## words buy_poll() records and the briefing's buttons send.
const StatuteK = preload("res://src/sim/statute_constants.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const LawVerdict = preload("res://src/ui/law_verdict.gd")

## Wider than legislature_constants.ABSTAIN_BAND (0.05) on purpose -- the real
## vote resolves exactly off the same support() value, but the forecast blurs
## a wider band around zero so a close vote is not readable in advance.
const FORECAST_UNCERTAIN_BAND := 0.15

## Carries the pre-vote baseline (Trends.snapshot_now()) and the law's name --
## same reasoning as budget_panel.gd's committed signal. Emitted whether the
## bill passed or not; main.gd only queues an effect worth measuring once a
## month has actually elapsed against it, which a failed vote changes nothing
## to distinguish -- an entry that shows "nothing moved" is still correct.
signal proposed(before: Dictionary, law_name: String, result: Dictionary)
## V4.2 T5. Propose now OPENS THE BRIEFING rather than dividing on the press:
## a bill briefing the player can read -- channels, landed price, the polls
## they can commission -- before the division is what the whole popup exists
## for, and the division itself is the briefing's verb (main.gd routes its
## propose_requested back into run_proposal() below). One propose path, one
## card path; this signal only asks for the popup.
signal brief_requested(law)

var _state
var _loader
var _title: Label
var _list: VBoxContainer
var _result_box: VBoxContainer
var _dirty := true
var _close_button: Button

## The first enabled verb this panel built on its last refresh. See primary_action().
var _primary: Control = null

## V4.2 T6 review, round 2. An Endorse the sim refused, verbatim from the
## machine -- the companies panel's _last_refusal idiom exactly: SET on a
## refusal and CLEARED on a success inside the handler, NEVER in _refresh()
## (the same refresh that must display a refusal is the one that would erase
## it), and displayed above the section's empty early-return -- the one
## reachable refusal IS the empty-in-tray frame, a stale press at a bill the
## assembly divided between the click and the refresh.
var _endorse_refusal := ""


func _ready() -> void:
	custom_minimum_size = Vector2(760, 560)

	var root := PanelKit.padded(self, 16, 12)

	_title = Label.new()
	root.add_child(_title)
	root.add_child(PanelCharts.new(self, PanelCharts.SEATS))

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
	_close_button.text = tr("Close (L)")
	_close_button.pressed.connect(func(): hide())
	row.add_child(_close_button)

	return row


## Docked-tab mode -- see budget_panel.gd's hide_close_button() for why.
func hide_close_button() -> void:
	_close_button.hide()


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_title.text = tr("LEGISLATURE — %s") % _state.player().id
	_dirty = true


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null:
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

	# V4.2 T6 review. The assembly's own in-tray -- private members' bills and
	# chiefs' bills the machine tabled, which the proposable list below cannot
	# show (a tabled law is by definition not in available()) and whose one
	# answerable verb is the president's stand. The companies panel's
	# autonomy sections are the house idiom for verbs on machine-generated
	# state; everything here is off the in-tray register, no hand-written list.
	# The refusal is NOT cleared here: refresh displays it, the handler owns
	# its lifetime (see _endorse_refusal).
	_build_assembly_section(ns)

	var party_list: Array = _loader.parties.get(ns.id, [])
	# V4.2. Authored laws plus the composed register -- the same concat the
	# legality scan runs, so a draft the player finished is on this list.
	var available: Array = Legislature.available(ns, _loader.laws + Statute.custom_laws(ns))
	if available.is_empty():
		PanelKit.line(_list, tr("No law is currently proposable."), PanelKit.Tone.PLAIN)
		return

	for law in available:
		_list.add_child(_build_law_row(ns, party_list, law))


func _build_result_summary(result: Dictionary) -> Control:
	var box := VBoxContainer.new()

	var law: Law = _find_law(result["law_id"])
	var law_label: String = Strings.law_name(law) if law != null else result["law_id"]

	var verdict: String = LawVerdict.word(result, _state.player() if _state != null else null)
	PanelKit.line(box, "%s — %s" % [law_label, verdict], PanelKit.Tone.PLAIN)

	# V2.8 review. Two more outcomes with no division behind them, and the tally
	# below would print "Yes 0 - No 0 - Abstain 0, of 577 seats" against both --
	# a chamber that never sat, reported as one that voted the bill down. Same
	# class as the four verdicts above, which is why they are branches and not a
	# shared "refused" word.
	if result.get("unavailable", false):
		PanelKit.line(box, tr("That is not open to the assembly right now."), PanelKit.Tone.PLAIN)
		return box

	if result.get("referendum_in_flight", false):
		PanelKit.line(box, tr("The country is already voting on something else."), PanelKit.Tone.PLAIN)
		return box

	if result.get("referendum_route", false) and result.get("refused", false):
		PanelKit.line(box, tr("This constitution has no referendum route for that."), PanelKit.Tone.PLAIN)
		return box

	# A forced bill had no division, so the seat tally would read all zeroes.
	# What happened instead is the censure motion.
	if result.get("forced", false):
		if result.get("refused", false):
			PanelKit.line(box, tr("Article 49.3 is not available."), PanelKit.Tone.PLAIN)
			return box
		box.add_child(_build_censure_summary(result.get("censure", {})))
		return box

	# And a moot release had no division either -- the verdict line above already
	# says why nothing followed, and a tally here would read a chamber that never
	# sat against a bill that came to nothing.
	if result.get("target_already_gone", false):
		return box

	# A HOLD'S RELEASE had no division either (the ultra pass-7 finding): the
	# bill was carried once, BEFORE the second chamber suspended it, and the
	# release applies over that chamber without the assembly re-sitting -- so
	# the tally below read "Yes 0 · No 0 · Abstain 0, of 577 seats" against a
	# chamber that never sat. The card main.gd builds refuses the same tally
	# for the same reason.
	if result.get("released", false):
		return box

	var tally := Label.new()
	tally.text = tr("Yes %d · No %d · Abstain %d, of %d seats") % [
		result["yes_seats"], result["no_seats"], result["abstain_seats"], result["seats_total"]
	]
	box.add_child(tally)

	# V1.1e. What the second chamber did, under the Assembly's own tally rather than
	# beside it, because the two are the same division read twice.
	if result.has("upper_passed"):
		PanelKit.line(box, tr("%s: Yes %d · No %d · Abstain %d, of %d seats") % [
			result.get("upper_chamber", tr("Second chamber")),
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
			# Same branch as the held list below: an assembly division's hold
			# releases free, so only a government bill's record promises the
			# override price.
			if bool(result.get("assembly_bill", false)):
				held.text = tr("It is held for %d months, and then comes into force.") % int(result.get("held_months", 0))
			else:
				held.text = tr("It is held for %d months, and overriding them costs %s with every bloc.") % [
					int(result.get("held_months", 0)), Num.f(ChambersK.UPPER_OVERRIDE_OFFSET, 2)]
			held.autowrap_mode = TextServer.AUTOWRAP_WORD
			box.add_child(held)

	# V1.1e. The court, and it names the ARITHMETIC as well as the verdict -- a rule the
	# player cannot read is not a check on their power, it is a trap. See
	# docs/judiciary-model.md.
	if bool(result.get("struck_down", false)):
		PanelKit.line(box, tr("The court struck it down: it reaches %s against a tolerance of %s.") % [
			Num.f(float(result.get("reach", 0.0)), 2), Num.f(float(result.get("tolerance", 0.0)), 2)], PanelKit.Tone.PLAIN)

	var rebellion := _rebellion_text(result.get("party_rebels", {}))
	if rebellion != "":
		PanelKit.line(box, rebellion, PanelKit.Tone.PLAIN)

	if not result["passed"]:
		var opposed := PackedStringArray()
		for party in _loader.parties.get(_state.player().id, []):
			if result["party_votes"].get(party.id, "") == "no":
				opposed.append(party.party_name)
		if not opposed.is_empty():
			PanelKit.line(box, tr("Voted against: %s") % ", ".join(opposed), PanelKit.Tone.PLAIN)

	return box


## What the assembly did about being bypassed. Names the parties that moved to
## censure, so a survived 49.3 still tells the player who came after them.
func _build_censure_summary(censure: Dictionary) -> Control:
	var box := VBoxContainer.new()
	if censure.is_empty():
		return box

	var ns = _state.player()

	PanelKit.line(box, tr("Adopted without a vote under Article 49.3."), PanelKit.Tone.PLAIN)

	PanelKit.line(box, tr("Censure motion: %d for · %d against · %d abstained, of %d seats (needs %d)") % [
		censure["for_seats"], censure["against_seats"], censure["abstain_seats"],
		censure["seats_total"], censure["threshold"],
	], PanelKit.Tone.PLAIN)

	var verdict := Label.new()
	if censure["carried"]:
		verdict.text = tr("CENSURED. %s falls; %s %s now heads the government.") % [
			_loader.person_name(censure["pm_person_id"]), ns.head_of_government_title, _loader.person_name(ns.pm_person_id)
		]
	else:
		verdict.text = tr("The motion failed. %s %s survives and the law stands.") % [
			ns.head_of_government_title, _loader.person_name(ns.pm_person_id)
		]
	box.add_child(verdict)

	var movers := PackedStringArray()
	for party in _loader.parties.get(ns.id, []):
		if censure["party_votes"].get(party.id, "") == "for":
			movers.append(party.party_name)
	if not movers.is_empty():
		var who := Label.new()
		who.text = tr("Moved to censure: %s") % ", ".join(movers)
		who.autowrap_mode = TextServer.AUTOWRAP_WORD
		box.add_child(who)

	var rebellion := _rebellion_text(censure.get("party_rebels", {}))
	if rebellion != "":
		PanelKit.line(box, rebellion, PanelKit.Tone.PLAIN)

	# Distinct from the line above on purpose: that one is members who ignored
	# their party, this one is parties that walked. Only the second is expelled.
	var defectors: Array = censure["defectors"]
	if not defectors.is_empty():
		PanelKit.line(box, tr_n("%d coalition party voted to censure and is out of government.", "%d coalition parties voted to censure and are out of government.", defectors.size()) % defectors.size(), PanelKit.Tone.PLAIN)

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
	return tr("%d seats broke ranks: %s.") % [total, ", ".join(parts)]


## A constitutional amendment reads its OWN nation's real threshold rather
## than the literal string "amendment" -- law.majority only tells
## resolve_vote() to look at ns.amendment_rule, and this is where the display
## does the same lookup. See docs/amendment-model.md.
func _majority_phrase(ns, law) -> String:
	if not law.constitutional:
		return tr("%s majority") % law.majority
	match ns.amendment_rule:
		"ordinary_law": return tr("ordinary majority")
		"three_fifths": return tr("3/5 majority")
		"two_thirds": return tr("2/3 majority")
		"three_quarters": return tr("3/4 majority")
		"referendum_required": return tr("ordinary majority, then a referendum")
		_: return ns.amendment_rule


func _build_law_row(ns, party_list: Array, law) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	PanelKit.line(box, "%s  (%s, %s)" % [Strings.law_name(law), PanelKit.Labels.law_theme(law.theme), _majority_phrase(ns, law)], PanelKit.Tone.PLAIN)

	# A system transition rewrites the whole constitution, not one field --
	# named here structurally, off the loaded template's own display_name,
	# rather than left to the law's own summary prose to stay accurate. See
	# docs/transition-model.md.
	if law.changes_system:
		var target_system_id: String = law.effects.get("institutional", {}).get("system_id", "")
		var target = _loader.political_systems.get(target_system_id)
		var target_label: String = target.display_name if target != null else target_system_id
		PanelKit.line(box, tr("Rewrites the constitution to a %s.") % target_label, PanelKit.Tone.PLAIN)

	PanelKit.rich(box, Strings.law_summary(law), PanelKit.Tone.PLAIN)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var forecast := Label.new()
	forecast.text = tr("Forecast: %s") % _forecast_text(ns, party_list, law)
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
	propose_btn.text = tr("Propose")
	propose_btn.pressed.connect(_on_propose.bind(law))
	_offer(propose_btn)
	row.add_child(propose_btn)

	# Article 49.3 exists only under a constitution that has it, and cannot force
	# a constitutional amendment through -- Art. 89's revision procedure has no
	# executive bypass. See docs/amendment-model.md.
	if ns.formation_method == "presidential_appointment" and not law.constitutional:
		var force_btn := Button.new()
		force_btn.text = tr("Force (49.3)")
		force_btn.disabled = not Government.can_force(ns)
		if force_btn.disabled:
			force_btn.tooltip_text = tr("Cooldown: available again in %d months.") % ns.force_cooldown_months
		else:
			force_btn.tooltip_text = tr("Adopt without a vote. The assembly may censure the government instead.")
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
		ref_btn.text = tr("Referendum")
		ref_btn.tooltip_text = tr("Pass it by an ordinary majority here, then put it to the country in %d months. Winning is a mandate and losing is a rebuke, and it cannot be called off for free.") % ReferendumK.REFERENDUM_DELAY_MONTHS
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

	PanelKit.line(box, tr("REFERENDUM CALLED — %s") % Strings.law_name(_find_law(Referendum.pending_law_id(ns)), Referendum.pending_law_id(ns)), PanelKit.Tone.PLAIN)

	var months := Referendum.months_left(ns)
	var share := Referendum.yes_share(ns, ns.referendum_pending.get("position", {}))
	PanelKit.line(box, tr_n("The country votes in %d month. If it voted today: %s%% yes, %s%% no.", "The country votes in %d months. If it voted today: %s%% yes, %s%% no.", months) % [months, Num.f(share * 100.0, 1), Num.f((1.0 - share) * 100.0, 1)], PanelKit.Tone.PLAIN)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var cost := Label.new()
	cost.text = tr("Calling it off costs exactly what losing it costs.")
	cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD
	row.add_child(cost)

	var withdraw_btn := Button.new()
	withdraw_btn.text = tr("Call it off")
	withdraw_btn.tooltip_text = tr("The same %s against every bloc a lost vote would charge, and the same cooldown. What it buys is the slot back now rather than in %d months.") % [Num.f(ReferendumK.REFERENDUM_RESULT_OFFSET, 2), months]
	withdraw_btn.pressed.connect(_on_withdraw)
	_offer(withdraw_btn)
	row.add_child(withdraw_btn)

	box.add_child(row)
	return box


## The blur is unchanged: a party whose |support| falls inside the band lands
## in "undecided" rather than a firm column. The band is not a constant here
## any more -- V4.2 T5's commissioned assembly poll buys it down to
## legislature_constants.ABSTAIN_BAND for THAT bill, and `forecast_band()`
## reads the purchase register. STATIC, and the briefing calls this same walk:
## the forecast is one computation and two windows, the same one-source rule
## PanelKit's ledgers keep for figures -- a second effects-walk in briefing.gd
## is exactly the drift this project keeps paying to find.
##
## Rebel seats are counted into the column they will actually vote in, not left
## inside their party's block. They are not a second kind of uncertainty -- the
## split is deterministic and the government panel already publishes it per
## party, so hiding it here would make the forecast lie in one direction only.
static func forecast_text(ns, party_list: Array, law, band: float) -> String:
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

		if s > band:
			yes += seats - broke
		elif s < -band:
			no += seats - broke
		else:
			undecided += seats - broke

		if own > band:
			yes += broke
		elif own < -band:
			no += broke
		else:
			undecided += broke

	var text := Strings.t("%d for · %d against · %d undecided") % [yes, no, undecided]
	if rebels > 0:
		text += Strings.t("  (%d expected to break ranks)") % rebels
	return text


func _forecast_text(ns, party_list: Array, law) -> String:
	return forecast_text(ns, party_list, law, forecast_band(ns, law.id))


## The band THIS bill's forecast is blurred by: the ordinary uncertainty, or
## the assembly poll's ABSTAIN_BAND where one was bought -- the whole point of
## the purchase is that the whip count firms up, and only for the bill that
## was polled. Reads the purchase register HERE, in src/ui/ where it belongs:
## src/sim/ never reads it (statute.buy_poll is its one sim touch).
static func forecast_band(ns, bill_key: String) -> float:
	if ns.poll_purchases.get(bill_key, {}).has(StatuteK.POLL_KIND_ASSEMBLY):
		return LK.ABSTAIN_BAND
	return FORECAST_UNCERTAIN_BAND


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
			parts.append(tr("%s: too close to call.") % ns.upper_chamber_name)
		elif bool(upper["passed"]):
			parts.append(tr("%s: expected to agree.") % ns.upper_chamber_name)
		elif power == ChambersK.VERDICT_ABSOLUTE:
			parts.append(tr("%s: expected to refuse, and it cannot be overridden.") % ns.upper_chamber_name)
		else:
			parts.append(tr("%s: expected to refuse, holding it %d months.") % [
				ns.upper_chamber_name, ChambersK.UPPER_HOLD_MONTHS])

	if Judiciary.reviews(ns, law):
		var tolerance: float = Judiciary.tolerance(ns)
		if Judiciary.strikes_down(ns, law):
			parts.append(tr("The court would strike it down: it reaches %s against %s.") % [
				Num.f(law.reach, 2), Num.f(tolerance, 2)])
		elif law.reach > 0.0:
			parts.append(tr("The court would let it stand: it reaches %s against %s.") % [
				Num.f(law.reach, 2), Num.f(tolerance, 2)])

	return " ".join(parts)


## A bill the second chamber is holding. Its own block at the top of the page, the way
## a pending referendum has one, because the list below cannot show a bill that is not
## proposable.
func _build_held_bill(ns, law_id: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	PanelKit.line(box, tr("%s — held by the %s") % [
		Strings.law_name(_find_law(law_id), law_id), ns.upper_chamber_name], PanelKit.Tone.PLAIN)

	# The ultra pass-2 shape: the entry carries {"months", "origin"}.
	var months: int = int(ns.held_bills.get(law_id, {}).get("months", 0))
	# The override clause is the GOVERNMENT's insistence priced -- an assembly
	# hold releases free (legislature.gd's origin gate charges nothing nobody
	# incurred), so its sentence promises no cost. The ultra pass-3 finding:
	# the clause rode unconditioned, promising a price the assembly class
	# never pays.
	if String(ns.held_bills.get(law_id, {}).get("origin", "player")) == "assembly":
		PanelKit.line(box, tr_n("The Assembly carried it and the second chamber refused. It comes into force in %d month.", "The Assembly carried it and the second chamber refused. It comes into force in %d months.", months) % months, PanelKit.Tone.PLAIN)
	else:
		PanelKit.line(box, tr_n("The Assembly carried it and the second chamber refused. It comes into force in %d month, and overriding them costs %s with every bloc.", "The Assembly carried it and the second chamber refused. It comes into force in %d months, and overriding them costs %s with every bloc.", months) % [
			months, Num.f(ChambersK.UPPER_OVERRIDE_OFFSET, 2)], PanelKit.Tone.PLAIN)
	return box


## The ASSEMBLY BILLS section: the header, then one compact row per bill in
## the machine's in-tray -- the law's name off the loader, the backer line
## when a chief lobbied the bill in, the months to the division, and Endorse
## wherever the president has not yet stood. One endorsement per bill is the
## sim's rule, so a taken stand REPLACES the verb with its record rather
## than leaving a live button whose only possible future is a refusal (the
## companies panel's spent-verb shape).
func _build_assembly_section(ns) -> void:
	# Above the empty early-return on purpose: the one reachable refusal is a
	# stale press at a bill the assembly divided between the click and the
	# refresh -- precisely the frame that arrives here with nothing left to
	# list. A refusal the empty-in-tray frame swallowed would be a press that
	# did nothing and said so nowhere.
	if _endorse_refusal != "":
		PanelKit.line(_list, _endorse_refusal)
	if ns.assembly_bills.is_empty():
		return
	PanelKit.heading(_list, tr("ASSEMBLY BILLS"))
	for bill_id in ns.assembly_bills:
		var entry: Dictionary = ns.assembly_bills[bill_id]
		var law = _find_law(String(entry.get("law_id", "")))
		var months := int(entry.get("months_left", 0))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		PanelKit.line(box, tr_n("%s — before the assembly, divides in %d month.", "%s — before the assembly, divides in %d months.", months) % [
			Strings.law_name(law) if law != null else String(entry.get("law_id", "")), months], PanelKit.Tone.PLAIN)
		var firm_id := String(entry.get("backer_firm", ""))
		if firm_id != "":
			# The B3 person_name idiom: the chief resolves through the loader
			# like every other named person -- a missing name reads as a role,
			# never as a raw id or an empty space.
			var chief: String = _loader.person_name(String(entry.get("backer_chief", "")))
			PanelKit.line(box, tr("%s's chief %s backs this bill.") % [
				_loader.firm_name(ns.id, firm_id),
				chief if chief != "" else tr("the chief")], PanelKit.Tone.PLAIN)
		if float(entry.get("endorse_bonus", 0.0)) != 0.0:
			PanelKit.line(box, tr("Endorsed — the president's stand is on the record."), PanelKit.Tone.PLAIN)
		else:
			box.add_child(_build_endorse_button(String(bill_id)))
		_list.add_child(box)


func _build_endorse_button(bill_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	# The tooltip names the trade off the constants' own vocabulary, so the
	# button cannot drift from what the machine actually charges.
	var price_bits := PackedStringArray()
	for bloc in StatuteK.PMB_ENDORSE_PRICE:
		price_bits.append("%s %s" % [PanelKit.Labels.bloc(String(bloc)), Num.fs(float(StatuteK.PMB_ENDORSE_PRICE[bloc]), 2)])
	var endorse_btn := Button.new()
	endorse_btn.text = tr("Endorse")
	endorse_btn.tooltip_text = tr("Stand behind the bill publicly: %s on every party's support line at its division, priced now as executive activism (%s). One stand per bill.") % [Num.fs(StatuteK.PMB_ENDORSE_SUPPORT, 2), ", ".join(price_bits)]
	endorse_btn.pressed.connect(_on_endorse.bind(bill_id))
	_offer(endorse_btn)
	row.add_child(endorse_btn)
	return row


## The player's stand. The sim owns every rule -- the bonus onto the in-tray
## entry, the price through the ONE applier, the one-per-bill refusal -- and
## this panel sends the command and marks itself dirty; the refresh then
## shows the record where the button was.
func _on_endorse(bill_id: String) -> void:
	var result: Dictionary = Statute.endorse(_state, _state.player(), _loader, bill_id)
	_endorse_refusal = "" if bool(result.get("ok", false)) \
		else String(result.get("refusal", tr("The assembly refused the stand.")))
	_dirty = true


## V4.2 T5. The press opens the briefing; the division happens from the
## briefing's own verb, routed back into run_proposal() below. A bill the
## player can read before the vote -- and commission a poll on before it --
## is the whole of what the briefing is for.
func _on_propose(law) -> void:
	brief_requested.emit(law)


## The division itself. Public because the briefing's verb lands here through
## main.gd -- one propose path (this body), one card path (the `proposed`
## handler in main.gd), whichever surface pressed the button. The forced and
## referendum routes come through it too: when Referendum kept a body of its
## own it forgot to redraw, and the panel kept the old result's buttons (V5.0d).
func run_proposal(law, force := false, referendum := false) -> void:
	var before := Trends.snapshot_now(_state)
	var result := Legislature.propose(_state, _loader, law, force, referendum)
	proposed.emit(before, Strings.law_name(law), result)
	_dirty = true


func _on_referendum(law) -> void:
	run_proposal(law, false, true)


func _on_withdraw() -> void:
	var ns = _state.player()
	var law: Law = _find_law(Referendum.pending_law_id(ns))
	var law_name: String = Strings.law_name(law, Referendum.pending_law_id(ns))
	var before := Trends.snapshot_now(_state)
	# A Legislature command, not Referendum.withdraw(): the panel writes no sim
	# state itself (AGENTS.md rule 2), and the command sets the loss's cooldown.
	# Nothing in flight (a stale second press): no decision to record.
	if not Legislature.withdraw_referendum(_state, ns, _loader).is_empty():
		proposed.emit(before, law_name, {"withdrawn": true})
	_dirty = true


func _on_force(law) -> void:
	run_proposal(law, true)


func _find_law(law_id: String):
	for law in _loader.laws:
		if law.id == law_id:
			return law
	# V4.2 ultra pass 2: a composed law lives on the register, not the loader --
	# the briefing's _repeal_line idiom. Without the fallback every held bill,
	# referendum and result summary for a composed law printed the raw
	# draft_NNNN id on the panel that lists the laws.
	if _state != null and _state.player() != null:
		for law in Statute.custom_laws(_state.player()):
			if String(law.id) == law_id:
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
## been asked, that is the only decision the assembly's list cannot offer. An
## assembly bill awaiting its endorsement builds next -- with no referendum in
## flight, the Endorse button is the verb, which is also right: its window is
## PMB_MONTHS_TO_VOTE, the shortest clock on the page.
func primary_action() -> Control:
	return _primary
