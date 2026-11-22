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
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const DivisionTerms = preload("res://src/sim/division_terms.gd")
const LawMagnitude = preload("res://src/core/law_magnitude.gd")
const Bills = preload("res://src/sim/bills.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Law = preload("res://src/core/law.gd")
const Trends = preload("res://src/ui/trends.gd")
const Referendum = preload("res://src/sim/referendum.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")
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
const LawList = preload("res://src/ui/law_list.gd")
const LawCensure = preload("res://src/ui/law_censure.gd")
const OrderPaper = preload("res://src/ui/order_paper.gd")

## Wider than legislature_constants.ABSTAIN_BAND (0.05) on purpose -- the real
## vote resolves exactly off the same support() value, but the forecast blurs
## a wider band around zero so a close vote is not readable in advance.
const FORECAST_UNCERTAIN_BAND := 0.15

## Carries the pre-vote baseline (Trends.snapshot_now()) and the law's name --
## same reasoning as finances_panel.gd's committed signal. Emitted whether the
## bill passed or not; main.gd only queues an effect worth measuring once a
## month has actually elapsed against it, which a failed vote changes nothing
## to distinguish -- an entry that shows "nothing moved" is still correct.
signal proposed(before: Dictionary, law_name: String, result: Dictionary)
## Asks for the briefing popup: the bills the sheet does not carry (an ownership bill's button).
## The sheet's own Propose divides at once (run_proposal below), its price and polls inline.
signal brief_requested(law)
## A poll bought from the sheet: the baseline and the label, the briefing's `polled` contract.
signal polled(before: Dictionary, label: String)

var _state
var _loader
var _title: Label
var _list: VBoxContainer
var _laws: LawList
var _paper := OrderPaper.new()
var _result_box: VBoxContainer
## The in-flight sheet's body: its plate is shown only while it holds something.
var _flight: VBoxContainer
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
	custom_minimum_size = Vector2(760, 0)  # the dock sets the height (tab_page.gd wanted_height)
	theme_type_variation = UiTheme.BARE  # the page lays out its own sheets (window_manager OWN_SHEETS)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UiTheme.GAP_PANE)
	add_child(root)

	# G3 S5 (Bills = C): the order paper is one slim sheet across the top; the tab's title already
	# says Bills, so the page does not say it again (_title stays for the panel's tests and hosts).
	var paper_sheet := PanelKit.sheet(root)
	_title = Label.new()
	_title.visible = false
	paper_sheet.add_child(_title)
	_paper.changed.connect(mark_dirty)
	paper_sheet.add_child(_paper)

	# V5.2-0b: what is in flight (a referendum, a held bill, the assembly's own bills, the last
	# verdict) on a sheet of its own that stands only while something is in flight; then the
	# catalogue -- the list and the open law's sheet (law_list.gd), each scrolling on its own.
	_flight = PanelKit.sheet(root)
	_result_box = VBoxContainer.new()
	_flight.add_child(_result_box)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 14)
	_flight.add_child(_list)
	_laws = LawList.new(self)
	root.add_child(_laws)

	root.add_child(_build_footer())


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END

	_close_button = Button.new()
	_close_button.text = tr("Close (L)")
	_close_button.pressed.connect(func(): hide())
	row.add_child(_close_button)

	return row


## Docked-tab mode: the docking frame's X is the real close (window_manager.gd's register()).
## Its row goes too: on a page of its own sheets an empty row would still take a gap.
func hide_close_button() -> void:
	_close_button.get_parent().hide()


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_title.text = tr("BILLS — %s") % _loader.nation_name(_state.player().id)
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
	_paper.refresh(_state, _loader, _find_law)

	for child in _result_box.get_children():
		_result_box.remove_child(child)
		child.queue_free()
	# V5.2 b+ R2: while a bill is before the Assembly the last verdict is history,
	# and the page opens on the bill that waits (law_list.gd's tabled line).
	if not ns.last_law_result.is_empty() and ns.tabled_bill.is_empty():
		_result_box.add_child(_build_result_summary(ns.last_law_result))

	for child in _list.get_children():
		_list.remove_child(child)
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
	_flight.get_parent().visible = _result_box.get_child_count() + _list.get_child_count() > 0

	var party_list: Array = _loader.parties.get(ns.id, [])
	# V4.2. Authored laws plus the composed register -- the same concat the
	# legality scan runs, so a draft the player finished is on this list.
	_laws.fill(ns, party_list, _loader.laws + Statute.custom_laws(ns))


func _build_result_summary(result: Dictionary) -> Control:
	var box := VBoxContainer.new()

	var law: Law = _find_law(result["law_id"])
	var law_label: String = Strings.law_name(law) if law != null else result["law_id"]

	# RF7: the verdict's word is in the line; its tone colours it.
	LawVerdict.tint(PanelKit.line(box, "%s — %s" % [law_label, LawVerdict.word(result, _state.player() if _state != null else null)], PanelKit.Tone.PLAIN), result, _state.player() if _state != null else null)

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
		box.add_child(LawCensure.box(_state, _loader, result.get("censure", {})))
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

	PanelKit.line(box, tr("Yes %d · No %d · Abstain %d, of %d seats") % [
		result["yes_seats"], result["no_seats"], result["abstain_seats"], result["seats_total"]], PanelKit.Tone.PLAIN)

	# V1.1e. What the second chamber did, under the Assembly's own tally rather than
	# beside it, because the two are the same division read twice.
	if result.has("upper_passed"):
		PanelKit.line(box, tr("%s: Yes %d · No %d · Abstain %d, of %d seats") % [
			result.get("upper_chamber", tr("Second chamber")),
			result["upper_yes_seats"], result["upper_no_seats"],
			result["upper_abstain_seats"], result["upper_seats_total"],
		], PanelKit.Tone.PLAIN)
		if bool(result.get("held_by_upper", false)):
			# WHAT THE CHAMBER DID, not when the bill arrives -- the twenty-first screenshot
			# pass found this frame reading "comes into force in 12 months" here and "in 9
			# months" in the held block directly below it, which is two numbers for one fact
			# on one screen. This box is a record of a division that has already happened and
			# never counts down; the block below is the live one.
			# Same branch as the held list below: an assembly division's hold
			# releases free, so only a government bill's record promises the
			# override price.
			PanelKit.line(box, tr("It is held for %d months, and then comes into force.") % int(result.get("held_months", 0)) if bool(result.get("assembly_bill", false))
				else tr("It is held for %d months, and overriding them costs %s with every bloc.") % [int(result.get("held_months", 0)), Num.f(ChambersK.UPPER_OVERRIDE_OFFSET, 2)], PanelKit.Tone.PLAIN)

	# V1.1e. The court, and it names the ARITHMETIC as well as the verdict -- a rule the
	# player cannot read is not a check on their power, it is a trap. See
	# docs/judiciary-model.md.
	if bool(result.get("struck_down", false)):
		PanelKit.line(box, tr("The court struck it down: it reaches %s against a tolerance of %s.") % [
			Num.f(float(result.get("reach", 0.0)), 2), Num.f(float(result.get("tolerance", 0.0)), 2)], PanelKit.Tone.PLAIN)

	var rebellion := LawCensure.rebellion_text(_state, _loader, result.get("party_rebels", {}))
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


## A constitutional amendment reads its OWN nation's real threshold rather
## than the literal string "amendment" -- law.majority only tells
## resolve_vote() to look at ns.amendment_rule, and this is where the display
## does the same lookup. See docs/amendment-model.md.
func _majority_phrase(ns, law) -> String:
	if not law.constitutional:
		return PanelKit.Labels.majority(String(law.majority))
	match ns.amendment_rule:
		"ordinary_law": return tr("ordinary majority")
		"three_fifths": return tr("3/5 majority")
		"two_thirds": return tr("2/3 majority")
		"three_quarters": return tr("3/4 majority")
		"referendum_required": return tr("ordinary majority, then a referendum")
		_: return ns.amendment_rule


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
	var c := forecast_counts(ns, party_list, law, band)
	var text := Strings.t("%d for · %d against · %d undecided") % [c["yes"], c["no"], c["undecided"]]
	if int(c["rebels"]) > 0:
		text += Strings.t("  (%d expected to break ranks)") % c["rebels"]
	return text


## The same walk, as the counts (V5.2-0b: the catalogue's forecast bar). It is the division's
## own tally (DivisionTerms.seats_of: a pledge, the peel, an address's sway) with only the band
## its own, so at ABSTAIN_BAND it reads what resolve_vote reads, law by law (tests/
## test_forecast_reads.gd; the review's finding 3 on #298). A tabled bill reads at its grade, so
## it takes the row: a graded copy of the tabled bill would read twice graded.
static func forecast_counts(ns, party_list: Array, law, band: float) -> Dictionary:
	var bill = LawMagnitude.scaled(law, float(ns.tabled_bill.get("scale", 1.0))) if String(ns.tabled_bill.get("law_id", "")) == String(law.id) else law
	var totals := [0, 0, 0]
	var rebels := 0
	for party in party_list:
		var s: float = Legislature.support(ns, party, bill)
		var lean: float = Legislature.spatial_support(ns, party, bill)
		var own: float = clampf(lean + DivisionTerms.of(lean, party, bill), -1.0, 1.0)
		var broke := 0
		if Legislature.vote_of(own) != Legislature.vote_of(s):
			broke = Discipline.rebel_seats(ns, party, s, own)
		rebels += broke
		var tally := DivisionTerms.seats_of(_line_at(s, band), _line_at(own, band), int(ns.seats_by_party.get(party.id, 0)), broke,
			DivisionTerms.pledged_seats(ns, party, bill), DivisionTerms.peel_share(ns, party, bill) + DivisionTerms.swayed_share(ns, party, bill, false),
			DivisionTerms.swayed_share(ns, party, bill, true))
		for i in 3:
			totals[i] += int(tally[i])
	return {"yes": totals[0], "no": totals[1], "undecided": totals[2], "rebels": rebels}


static func _line_at(support_now: float, band: float) -> String:
	if support_now > band:
		return "yes"
	return "no" if support_now < -band else "abstain"


## The band THIS bill's forecast is blurred by: the ordinary uncertainty, or
## the assembly poll's ABSTAIN_BAND where one was bought -- the whole point of
## the purchase is that the whip count firms up, and only for the bill that
## was polled. Reads the purchase register HERE, in src/ui/ where it belongs:
## src/sim/ never reads it (statute.buy_poll is its one sim touch).
static func forecast_band(ns, bill_key: String) -> float:
	if ns.poll_purchases.get(bill_key, {}).has(StatuteK.POLL_KIND_ASSEMBLY):
		return LK.ABSTAIN_BAND
	return FORECAST_UNCERTAIN_BAND


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
	row.add_child(preload("res://src/ui/acts_on.gd").tag(endorse_btn, ["assembly|%s" % bill_id]))  # B7: the bill card's Go
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


## The division itself. Public because the sheet's Propose and the briefing's both land here
## (the latter through main.gd) -- one propose path (this body), one card path (the `proposed`
## handler in main.gd), whichever surface pressed the button. The forced and
## referendum routes come through it too: when Referendum kept a body of its
## own it forgot to redraw, and the panel kept the old result's buttons (V5.0d).
func run_proposal(law, force := false, referendum := false) -> void:
	var before := Trends.snapshot_now(_state)
	var result := Legislature.propose(_state, _loader, law, force, referendum, _laws.grade(law, referendum))
	proposed.emit(before, Strings.law_name(law), result)
	LawVerdict.sting(self, result, _state.player())  # V5.3-0 (d)
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
	# R14: Bills.by_id -- an authored law, or an ownership bill rebuilt from its id.
	var found = Bills.by_id(_loader, law_id)
	# V4.2 ultra pass 2: a composed law lives on the register, not the loader --
	# the briefing's _repeal_line idiom. Without the fallback every held bill,
	# referendum and result summary for a composed law printed the raw
	# draft_NNNN id on the panel that lists the laws.
	if found == null and _state != null and _state.player() != null:
		for law in Statute.custom_laws(_state.player()):
			if String(law.id) == law_id:
				found = law
	return found


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
