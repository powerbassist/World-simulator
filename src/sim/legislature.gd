extends RefCounted

## Law proposal, vote resolution and effect application.
##
## A law's support is read off the same two-axis ideology space
## election_constants.gd's SLOT_POSITION already positions every party on --
## no parallel ideology vocabulary. Vote resolution is a pure function of
## ns.seats_by_party (live, election-updated state) and the law; no rand()
## anywhere, so a vote is exactly reproducible from state, the same discipline
## as economy.gd, budget.gd, opinion.gd and elections.gd.
##
## The model, and the justification for every constant, is
## docs/legislature-model.md.

const LK = preload("res://src/sim/legislature_constants.gd")
const LawConditions = preload("res://src/sim/law_conditions.gd")
# V4.2. The yield ceiling lives here (a constants leaf -- no cycle: statute.gd
# preloads this file, and this file preloads only its constants and leaves).
const StatuteK = preload("res://src/sim/statute_constants.gd")
const K = preload("res://src/sim/election_constants.gd")
## V4.2. The composed-law factory: the legality scan reads ns.custom_laws
## through Law.composed_register() because statute.gd preloads THIS file (the
## repeal gate), so the reverse preload would be a cycle.
const Law = preload("res://src/core/law.gd")
const Budget = preload("res://src/sim/budget.gd")
const Government = preload("res://src/sim/government.gd")
const GK = preload("res://src/sim/government_constants.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const DK = preload("res://src/sim/discipline_constants.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
## V1.4b, for REGULATION_BURDEN_MAX alone. Not companies.gd: this file writes the
## burden and never reads what it costs, so the dependency stops at the clamp.
const CK = preload("res://src/sim/companies_constants.gd")
const SK = preload("res://src/sim/society_constants.gd")
const DemoK = preload("res://src/sim/demography_constants.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")
const MediaK = preload("res://src/sim/media_constants.gd")
## V1.7c. One direction only: this file knows how to call a referendum and how to
## apply what it decides; referendum.gd knows nothing about a chamber and preloads
## nothing from here. tests/test_referendum.gd reads that file and fails if the
## dependency ever runs the other way -- src/sim/calendar.gd's leaf property.
const Referendum = preload("res://src/sim/referendum.gd")

## V1.1e, both one direction only and both LEAVES -- neither knows a law exists.
## chambers.gd owns the second chamber's composition and this file resolves its
## division with the same spatial_support() it already owns; judiciary.gd answers
## whether a bill survives and this file decides what that does to the bill.
## tests/test_upper_house.gd and tests/test_judiciary.gd read those two files and
## fail if the dependency ever runs the other way -- src/sim/calendar.gd's property.
const Chambers = preload("res://src/sim/chambers.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const JudiciaryK = preload("res://src/sim/judiciary_constants.gd")
## V5.2 b+ R14: every bill, one lookup (the authored list, the composed register,
## the ownership bills built from content).
const Bills = preload("res://src/sim/bills.gd")
## V5.2 b+ R2: the tabled bill's vote day. Calendar preloads nothing, so no cycle.
const Calendar = preload("res://src/sim/calendar.gd")


## Reset every nation's legislature state. Runs for all ten, same as
## Opinion.init_nation and Elections.init_nation -- a second playable nation is
## then a data change, not a change here.
static func init_nation(ns) -> void:
	ns.law_structural_offset_pct = 0.0
	ns.law_potential_target_pct = 0.0
	ns.law_other_revenue_pct_gdp = 0.0
	ns.bloc_offset = {}
	# V1.4b. Reset here rather than in Companies.init_nation() for the reason the
	# three law_* accumulators above are: whatever WRITES a field resets it, and a
	# regulation is a law. companies.gd only reads this one, exactly as economy.gd
	# only reads `law_structural_offset_pct`.
	ns.regulation_burden = {}
	ns.passed_law_ids = {}
	ns.law_cooldown_months = {}
	ns.law_ledger = {}
	# V4.2 T2. The composition registers, the same rule: whatever WRITES a
	# field resets it, and both are written in statute.gd. V4.2 T4 adds the
	# params register beside them -- written in THIS file's apply() birth
	# step, so it resets here with its fellow registers and not in
	# statute.gd's own init (there is none; the tick is stateless).
	ns.draft_bills = {}
	ns.custom_laws = {}
	ns.custom_taxes = {}
	# V4.2 T5. The paid-poll register, the same rule: its only writer is
	# statute.buy_poll(), so it resets beside the registers that writer's
	# machine owns and not in any file that merely reads it.
	ns.poll_purchases = {}
	# V4.2 T6. The assembly-bill in-tray, the draft_bills rule beside which it
	# sits: whatever WRITES a field resets it, and the writers are statute.gd's
	# generation and division (this file reads the register in available()'s
	# in-flight guard and writes nothing to it).
	ns.assembly_bills = {}
	ns.last_law_result = {}
	ns.tabled_bill = {}  # V5.2 b+ R2: written by propose(), the same rule
	# V1.1e. Whatever WRITES a field resets it -- the three law_* accumulators and
	# `regulation_burden` above give the reason. A held bill is written by propose()
	# in this file and -- V4.2 T6's ultra review -- by statute.gd's assembly division
	# parking a suspensive refusal, and it is released by tick_month() in this file
	# either way, so it is reset here -- and also in Chambers.init_nation(), which has reset
	# it since V1.1e; two cheap idempotences over one register, and the comment
	# that claimed otherwise was the ultra pass-12 fleet's stale-record find.
	ns.held_bills = {}


## Count down cooldowns. Gated on has_budget, the same flag every other
## opinion-reading system uses -- the other nine nations have no assembly vote
## to resolve at MVP.
## `loader` is required rather than defaulted, on the reason apply()'s own header
## gives one function down: a defaulted loader would let a referendum resolve and
## then silently fail to apply the law it carried, which is the half-applied state
## this project refuses throughout.
##
## THE REFERENDUM COUNTDOWN LIVES HERE AND ADDS NO NEW CALL ANYWHERE, which is
## deliberate rather than convenient. src/ui/main.gd, tools/balance_probe.gd,
## tests/test_balance.gd and eight probes already call this function every month, so
## a referendum reaches every harness through a call they all already make.
## docs/media-model.md's V1.5d bug -- neither balance harness called
## Media.tick_month(), so both ran the pre-session model and their agreement about a
## bit-identical re-run was about nothing -- made structurally impossible instead of
## remembered, which is docs/cycle-model.md's V1.6a argument taken deliberately.
static func tick_month(state, loader) -> void:
	for ns in state.nations.values():
		if not ns.has_budget:
			continue
		if ns.force_cooldown_months > 0:
			ns.force_cooldown_months -= 1

		# The existing cooldowns count down FIRST, so that a referendum settled or a
		# held bill released below sets its law's cooldown at full length rather than
		# one month short. Ordered the other way round -- as it was until the V2.8
		# review -- the write lands in front of this loop and is decremented in the
		# same tick, so a lost referendum got N-1 where a lost ordinary vote got N
		# (propose() runs outside the tick), and a law with cooldown_months == 1 got
		# no cooldown at all.
		var expired: Array = []
		for law_id in ns.law_cooldown_months:
			var remaining: int = int(ns.law_cooldown_months[law_id]) - 1
			if remaining <= 0:
				expired.append(law_id)
			else:
				ns.law_cooldown_months[law_id] = remaining
		for law_id in expired:
			ns.law_cooldown_months.erase(law_id)

		var verdict := Referendum.resolve_due(ns)
		if not verdict.is_empty():
			_settle_referendum(state, ns, loader, verdict)

		# V1.1e. The held-bill countdown, HERE and adding no new call anywhere, for
		# the exact reason the referendum countdown above is here: this function is
		# already called every month by src/ui/main.gd, tools/balance_probe.gd,
		# tests/test_balance.gd and eight probes, so a second chamber reaches every
		# harness through a call they all already make. docs/media-model.md's V1.5d bug
		# -- neither balance harness called Media.tick_month(), so both ran the
		# pre-session model and their agreement about a bit-identical re-run was about
		# nothing -- made structurally impossible rather than remembered.
		_tick_held_bills(state, ns, loader)


## What the country decided, turned into law or into a cooldown.
##
## referendum.gd hands this back as DATA and this function acts on it -- U6a's
## Calendar.due() one block on, and it is what lets that file preload nothing from
## here. What it costs the government is charged THERE, because the price is the
## referendum's; what happens to the bill is charged HERE, because a law passing is
## this file's job and always has been.
static func _settle_referendum(state, ns, loader, verdict: Dictionary) -> void:
	var law = Bills.by_id(loader, String(verdict.get("law_id", "")))
	# The constitution can change while the country votes (V5.0d): a law it no
	# longer allows lapses, the held-bill release's rule below.
	if law == null or not _constitution_allows(ns, law):
		return
	if bool(verdict.get("passed", false)):
		apply(state, ns, law, loader)
	elif law.cooldown_months > 0:
		ns.law_cooldown_months[law.id] = law.cooldown_months


## Call off the referendum in flight -- the player's command. Referendum.withdraw()
## charges a loss's price; the loss's COOLDOWN is this file's half, and it is set by
## the same _settle_referendum() a vote the country refused runs. Until V5.0d the
## panel called Referendum.withdraw() alone, so no cooldown was ever set and calling
## it off beat losing it -- the free hedge referendum.gd's own header rules out.
static func withdraw_referendum(state, ns, loader) -> Dictionary:
	var verdict := Referendum.withdraw(ns)
	if not verdict.is_empty():
		_settle_referendum(state, ns, loader, verdict)
	return verdict


## Count every held bill down, and pass the ones whose hold has run out.
##
## A SUSPENSIVE REFUSAL IS A DELAY AND NOT A DEFEAT, so the bill passes on expiry
## with no second division and no command from the player -- which is what a
## suspensive veto is: the Parliament Acts do not ask the Commons to vote again
## after a year, they simply stop the Lords stopping it. The bill still faces the
## COURT on the way out, because the court is a later stage of the same pipeline and
## a bill that took a year to arrive is not thereby constitutional.
##
## OVERRIDING IS NOT FREE, and that is the escalation tools/upper_house_probe.gd's
## table U3 fired: a hold priced in time alone moves the worst bloc 2.37 points over a
## year, under the 3.0 poll floor, and only registers at 15 months -- one short of the
## whole first term. So the release charges UPPER_OVERRIDE_OFFSET through
## Government.penalise_blocs(), which is Article 49.3's own accumulator. Charged HERE
## rather than at the refusal because that is when the government has actually
## insisted -- and ONLY for a bill the government proposed: the origin each entry
## carries since the ultra pass-2 shape is the charge's gate, and a private
## member's bill the chamber held releases free, because nobody insisted on it
## and a price nobody incurred is a levy, not a price.
static func _tick_held_bills(state, ns, loader) -> void:
	var due: Array = []
	for law_id in ns.held_bills:
		var entry: Dictionary = ns.held_bills[law_id]
		var remaining: int = int(entry.get("months", 0)) - 1
		if remaining <= 0:
			due.append(law_id)
		else:
			entry["months"] = remaining
	for law_id in due:
		# The origin is read BEFORE the erase -- it is the charge's gate below.
		var origin: String = String(ns.held_bills[law_id].get("origin", "player"))
		ns.held_bills.erase(law_id)
		var law = Bills.by_id(loader, String(law_id))
		if law == null:
			# A composed law is not in loader.laws -- the register it lives on
			# is ns.custom_laws, rebuilt through the core factory (the same
			# lookup _subtract_ledger runs). Without this half, a held COMPOSED
			# bill was erased here and silently destroyed: no effects, no
			# result, the ultra pass-2 pin in test_statute_assembly.gd holds
			# the behavior either way.
			for composed in Law.composed_register(ns):
				if String(composed.id) == law_id:
					law = composed
					break
		if law == null:
			continue
		var released := {
			"law_id": law.id, "passed": true, "released": true,
			"majority": law.majority, "yes_seats": 0, "no_seats": 0,
			"abstain_seats": 0, "seats_total": ns.assembly_seats,
			"party_votes": {}, "party_support": {}, "party_rebels": {},
			# The hold card named the chamber by its own name twelve months
			# ago; the release card says the same thing the same way.
			"upper_chamber": ns.upper_chamber_name,
		}
		# THE MOOT RELEASE, the ultra pass-4 finding: a REPEAL can release after
		# its TARGET is already gone. Two repeal drafts of one target both compose
		# (repeal_target_legal gates on the live ledger, and the repeal side has
		# no one-in-flight gate), and available()'s consumed-repeal filter runs
		# only on the propose path -- a bill parked in the hold is not re-scanned
		# -- so the second repeal can carry and subtract while the first sits out
		# its hold. Releasing then must subtract NOTHING and charge NOTHING: the
		# subtraction would find an empty book, and recording this as force with
		# the override price would be a release lying about a bill that changed
		# nothing. The record keeps passed/released -- the hold did run out -- and
		# gains the flag that says why the subtraction did not follow. Deliberately
		# no assembly marker either: nothing came into force, so there is no
		# coming-into-force event for a card to announce.
		#
		# The moot branch short-circuits only the SUBTRACTION and only for a PURE
		# repeal (the ultra pass-13 finding): a MIXED bill -- channels beside a
		# `repeals` target -- must still land its own channels and face the court
		# below, exactly as apply() would, because apply() is every path on which
		# a bill takes effect and a blanket skip here would make the same carried
		# bill evaporate or take effect depending on which path delivered it.
		# _subtract_ledger()'s empty-book return is the quiet no-op the pure
		# case needs, so the flag below is the only special-casing a mixed
		# release carries.
		if law.repeals != "" and ledger_of(ns, law.repeals).is_empty() and law.effects.is_empty():
			released["target_already_gone"] = true
			ns.last_law_result = released
			continue
		# THE LAPSED RELEASE (V5.0d): available()'s constitutional gate ran when the
		# bill was proposed, and the system can change during the hold -- a GBR
		# amendment authored for the monarchy, released after the Republic Act,
		# wrote a dissolution rule the republic's template refuses. It lapses:
		# nothing applies, nothing is charged, the moot release's shape.
		if not _constitution_allows(ns, law):
			released["passed"] = false
			released["lapsed"] = true
			ns.last_law_result = released
			continue
		# NEGATED: penalise_blocs() ADDS its argument, and UPPER_OVERRIDE_OFFSET is
		# authored as a positive magnitude -- the same convention every sibling
		# constant breaks by carrying its own sign (FALLEN -0.12, FORCE -0.08,
		# RESHUFFLE -0.04, RESIGNATION -0.06, DISSOLUTION -0.08). Passed unnegated
		# until the V2.8 review, an override RAISED every bloc's approval, which is
		# the opposite of the price tools/upper_house_probe.gd table U4 measured --
		# that sweep ran _run_with_offset(loader, -offset), so the calibration this
		# constant carries has always been a cost. Gated on the origin since the
		# ultra pass 2: an assembly bill's release charges nothing.
		if origin != "assembly":
			Government.penalise_blocs(ns, -ChambersK.UPPER_OVERRIDE_OFFSET)
			released["override_offset"] = -ChambersK.UPPER_OVERRIDE_OFFSET
		else:
			# The ultra pass-3 finding: the release was silent everywhere but
			# the Legislature panel's own record -- the card gate in main.gd
			# reads the assembly marker and the DIVISION'S OWN MONTH off
			# ns.last_law_result, and the release carried neither. The stamp
			# is the RELEASE month (the coming-into-force event's own), the
			# same key the division writes, so the same per-month memory that
			# keeps a quiet month from re-announcing a division keeps it from
			# re-announcing a release.
			released["assembly_bill"] = true
			released["assembly_division_month"] = int(state.year) * 12 + int(state.month)
		_review_and_apply(state, ns, law, loader, released)
		ns.last_law_result = released
		# The member_bill_passed hook's own stamp: last_law_result is
		# overwritten by any later division this month, the release with it.
		# After the review, because the court can strike a released bill
		# (passed -> false) and a struck bill did not come into force.
		if origin == "assembly" and bool(released.get("passed", false)):
			ns.assembly_bill_passed_month = int(state.year) * 12 + int(state.month)


## THE COURT'S GATE, and it is the LAST stage of the pipeline rather than a second
## applier. Called from propose()'s ORDINARY route (a bill that divided and is
## taking effect), from _force(), from the release above, and -- V4.2 T6's ultra
## review -- from statute.gd's assembly division through the public delegate
## below. The old header scoped this to "bills taking effect without the country
## having voted on it", and that scope was false: a DIVIDED bill is not thereby
## exempt from review -- propose()'s ordinary route has court-reviewed every
## carried bill since V1.1e -- and the assembly's division is the ordinary
## legislative procedure, not a stage beyond it. What the court does not see is
## the one landing the third refusal below records: a law the COUNTRY ratified.
##
## DELIBERATELY NOT INSIDE apply_effects(). That function has had two callers since
## V1.8 and the second is an EVENT CHOICE, which is docs/tiers/v1.md section 1's
## "Decree / executive order -- bypass the assembly on a narrow set of matters, at a
## legitimacy cost" discharged at V1.8. A decree annulled by a court is the Conseil
## d'Etat reviewing an administrative act, which is a different body reviewing a
## different thing, and "Judicial appointments" and "Emergency powers" are both
## tiered Someday. Recorded rather than built -- see docs/judiciary-model.md.
##
## Deliberately not inside apply() either: tests, probes, tools/screenshot.gd and
## tools/balance_probe.gd all call apply() directly to SET UP state, and a gate there
## would silently refuse them.
##
## _settle_referendum() does NOT call this, and that is the third refusal. A law the
## country has ratified is not reviewable -- the Conseil constitutionnel declined
## jurisdiction over a referendum law in 1962 -- and it agrees with the exclusion
## Judiciary.reviews() already makes for an amendment, since a referendum in this
## game only ever ratifies one.
static func _review_and_apply(state, ns, law, loader, result: Dictionary) -> void:
	result["reviewable"] = Judiciary.reviews(ns, law)
	if result["reviewable"]:
		result["reach"] = law.reach
		result["tolerance"] = Judiciary.tolerance(ns)
	if Judiciary.strikes_down(ns, law):
		result["passed"] = false
		result["struck_down"] = true
		if law.cooldown_months > 0:
			ns.law_cooldown_months[law.id] = law.cooldown_months
		return
	apply(state, ns, law, loader)


## The assembly division's way in -- the underscore above marks this file's own
## internals, and statute.gd is another file. A carried PMB has divided, which
## is what the court REVIEWS (propose()'s ordinary route is the precedent), so
## the delegation is one line and the review is the same gate every other
## divided bill faces. The block/hold half of the pipeline stays in
## statute.gd's _divide, because which chamber verdict applies is the caller's
## own read.
static func review_and_apply_after_division(state, ns, law, loader, result: Dictionary) -> void:
	_review_and_apply(state, ns, law, loader, result)


## The second chamber's division. A PURE FUNCTION of state, like resolve_vote()
## above and for the same reason: src/ui/law_panel.gd shows the player what the
## second chamber will do before they commit, and a forecast that mutates is a
## forecast that can only be asked once.
##
## READS spatial_support() PLUS A REDUCED WHIP, which is the model's one substantive
## claim about how a second chamber votes -- and the reduction is the probe's third
## correction to this session. A government is not formed from the upper house and
## cannot fall there, so the whip is WEAKER; it is not ABSENT, because senators belong
## to the same parties as deputies. Written without it, the Senat refused seven of
## seven authored amendments and killed the referendum verb outright -- see
## chambers_constants.UPPER_WHIP.
##
## Discipline.rebel_seats() still does not apply: a rebellion is a break with a whip
## that can be enforced, and this chamber's cannot be. So this reuses two functions
## this file already exports plus one Government already exports, and touches
## resolve_vote() not at all -- which matters, because about twenty-five call sites
## read that one.
##
## A SIMPLE MAJORITY OF THE VOTES CAST, on every nation and every class of bill.
## Germany's Art. 79(2) really does need two thirds of the Bundesrat's votes for a
## Basic Law amendment and this model asks for a majority; that is a RECORDED
## REDUCTION, the same shape docs/electoral-systems.md uses per method, and it is
## bounded in practice because Germany's Bundestag bar is already unreachable.
static func resolve_upper(ns, party_list: Array, law) -> Dictionary:
	var chamber := Chambers.seats(ns)
	var yes_seats := 0
	var no_seats := 0
	var abstain_seats := 0
	var seats_total := 0
	for party in party_list:
		var seats: int = int(chamber.get(party.id, 0))
		if seats <= 0:
			continue
		seats_total += seats
		var line: float = clampf(
			spatial_support(ns, party, law)
				+ ChambersK.UPPER_WHIP * Government.coalition_bonus(ns, party),
			-1.0, 1.0
		)
		match vote_of(line):
			"yes": yes_seats += seats
			"no": no_seats += seats
			_: abstain_seats += seats
	return {
		"passed": yes_seats > no_seats,
		"yes_seats": yes_seats,
		"no_seats": no_seats,
		"abstain_seats": abstain_seats,
		"seats_total": seats_total,
	}


## Every law from `all_laws` currently proposable against `ns`: preconditions
## met, not already passed as a once-only law, not on cooldown, and -- for a
## constitutional amendment -- proposable under the nation's own system.
static func available(ns, all_laws: Array) -> Array:
	var out: Array = []
	for law in all_laws:
		if law.id == "":
			continue
		if law.once and ns.passed_law_ids.has(law.id):
			continue
		if ns.law_cooldown_months.has(law.id):
			continue
		# V4.2 ultra pass 2. A repeal whose target has no ledger entry is not
		# proposable: repeal_target_legal() gates it at composition, so a target
		# gone from the book means the repeal was ALREADY carried -- re-offering
		# it would pass a carried no-op (quiet since the pass-4 finding made the
		# empty-ledger subtraction a no-op, but a button that repeals nothing is
		# still the half-removed act class). Kills both the after-cooldown no-op
		# and the propose-path half of the two-repeals-of-one-target case -- the
		# held window's half is the moot release's, in _tick_held_bills; the
		# window self-heals the other way too, since a re-passed target re-opens
		# its own repealer here.
		if law.repeals != "" and not ns.law_ledger.has(law.repeals):
			continue
		# THE YIELD-CAP OFFER GATE, the ultra pass-17 finding: a birth act is
		# repeatable by design (once:false, no passage cooldown), but the
		# revenue model prices at most NEW_TAX_YIELD_CEILING / base of a born
		# key -- the same cap the tax panel's slider has carried since the
		# pass-14 round. A re-passage whose pending product would exceed the
		# cap changes nothing the model can price, so the act is not offered:
		# the _already_in_force shape ("a button that changes nothing is not
		# offered"), which also stops the direct propose route, whose legality
		# scan is this very list. The yield gate in Budget.apply_pending stays
		# as the backstop for routes that bypass this filter.
		var birth: Dictionary = law.new_tax
		var birth_key := String(birth.get("key", ""))
		if not birth.is_empty() and ns.custom_taxes.has(birth_key):
			# The birth's per-passage DELTA rides the effects (statute.gd's
			# compose merges it into tax_rates_pct); new_tax carries only the
			# registration params.
			var base: float = maxf(float(ns.custom_taxes[birth_key].get("base_share", 0.0)), 0.01)
			var pending_rate: float = float(ns.tax_rates_pct.get(birth_key, 0.0)) 				+ float(law.effects.get("tax_rates_pct", {}).get(birth_key, 0.0))
			if base * pending_rate > StatuteK.NEW_TAX_YIELD_CEILING:
				continue
		if not _constitution_allows(ns, law):
			continue
		if _already_in_force(ns, law):
			continue
		# One referendum at a time, and while one is in flight nothing else may be
		# put to the country. A second live question is not a bound that needed a
		# constant -- it is what "the country votes on this" means.
		if Referendum.is_pending(ns) and Referendum.pending_law_id(ns) == law.id:
			continue
		# V1.1e. A bill the second chamber is holding is IN FLIGHT and cannot be
		# proposed again while it waits -- the same thing the line above says about a
		# question already put to the country, and for the same reason: proposing it
		# twice would let the player restart the clock they are waiting out.
		if ns.held_bills.has(law.id):
			continue
		# V4.2 T6. A bill the assembly's own backbench has tabled is IN FLIGHT on
		# exactly the held_bills grounds: the player proposing the same law inside
		# the endorsement window would divide it twice and apply the effects twice,
		# which is the double-application guard this scan exists to keep.
		if _in_assembly_tray(ns, law.id):
			continue
		if _preconditions_met(ns, law):
			out.append(law)
	return out


## Whether the assembly's own backbench has this law tabled -- available()'s
## in-flight guard reads it and nothing else does.
static func _in_assembly_tray(ns, law_id: String) -> bool:
	for entry in ns.assembly_bills.values():
		if String(entry.get("law_id", "")) == law_id:
			return true
	return false


## The constitutional gate: a law authored for a template the nation is not under,
## or a change of system its constitution forbids. available() runs it at proposal;
## a held bill's release and a referendum's settle run it again (V5.0d), because the
## system can change between the division and the day the law would take effect.
static func _constitution_allows(ns, law) -> bool:
	return (not law.constitutional or law.systems.has(ns.system_id)) and (not law.changes_system or ns.permits_system_change)


## An electoral-reform Act that names the method the nation already uses changes
## nothing, and a button that changes nothing is the bug V1.3e's screenshot pass
## found on the diplomacy panel. Checked in code rather than by asking content to
## remember it -- src/sim/campaign.gd's _op_legal() and src/sim/projects.gd's
## available() give the argument -- and it is checked here rather than as a
## precondition because PRECONDITION_FIELDS is numeric and an electoral system is a
## string, which is a schema difference and not an oversight.
static func _already_in_force(ns, law) -> bool:
	var inst: Dictionary = law.effects.get("institutional", {})
	if not inst.has("election_system"):
		return false
	if String(inst["election_system"]) != ns.election_system:
		return false
	# The method matches; the law is still live if it also moves the threshold.
	if inst.has("election_threshold_pct"):
		return is_equal_approx(float(inst["election_threshold_pct"]), ns.election_threshold_pct)
	return true


static func _preconditions_met(ns, law) -> bool:
	return preconditions_met(ns, law.preconditions)


## The precondition reader lives in law_conditions.gd since V5.0d (the size ratchet
## paid for the session's fixes by moving it out whole); these two forwarders keep
## Legislature.preconditions_met / read_field the one public surface every caller
## already names.
static func preconditions_met(ns, conditions: Array) -> bool:
	return LawConditions.preconditions_met(ns, conditions)


static func read_field(ns, field: String) -> float:
	return LawConditions.read_field(ns, field)


## A single party's support for a law, in [-1, +1]. Gaussian falloff on
## ideological distance, same functional form elections.gd:vote_share() uses
## against SLOT_POSITION, with its own (tighter) sigma -- parties are
## disciplined voting blocs, not fuzzy electorates. Plus a bonus for sitting in
## the government whose bill this is.
##
## That bonus used to be a flat GOVERNMENT_BONUS for the single incumbent party.
## It is now earned: government.gd scales it by the party's distance from the
## coalition's agreed position and by how reliably that party delivers its
## seats, so a partner dragged a long way from its own ideology is a less
## dependable vote than the one that wrote the bill. Opposition still gets
## nothing. See docs/government-model.md.
static func support(ns, party, law) -> float:
	return clampf(spatial_support(ns, party, law) + Government.coalition_bonus(ns, party), -1.0, 1.0)


## The same party's view of the same bill with no government whip on it -- the
## purely spatial term, before coalition_bonus(). Split out of support() at V1.1b
## because the gap between the two IS the strain the rebellion split measures,
## and computing it twice in two files would let them drift.
##
## Identical for an opposition party, whose bonus is zero by construction. That
## is why opposition parties never rebel: nothing is pulling their members away
## from where they already stand.
static func spatial_support(ns, party, law) -> float:
	var pos: Dictionary = K.SLOT_POSITION.get(party.ideology_slot, {"economic": 0.0, "social": 0.0})
	var d_econ: float = float(pos["economic"]) - float(law.position["economic"])
	var d_social: float = float(pos["social"]) - float(law.position["social"])
	var dist: float = sqrt(d_econ * d_econ + d_social * d_social)

	return clampf(2.0 * exp(-pow(dist / LK.LAW_SIGMA, 2.0)) - 1.0, -1.0, 1.0)


## How a support score reads as a vote. Named so the forecast in law_panel.gd and
## the real division cannot disagree about where the band sits.
static func vote_of(s: float) -> String:
	if s > LK.ABSTAIN_BAND:
		return "yes"
	if s < -LK.ABSTAIN_BAND:
		return "no"
	return "abstain"


## Vote share -> seats, resolved once against ns.seats_by_party. Does not
## mutate state; propose() below does that after reading the result.
##
## Since V1.1b a party is not one bloc. Its line is support(); its members with
## no whip on them are spatial_support(); where those two read as different votes,
## the share of seats discipline.gd computes goes with the second. `party_votes`
## still names the party's line, and `party_rebels` says how many of its seats
## did not follow it.
## `referendum` selects ROUTE B: the chamber's bar drops to an ordinary majority and
## the amendment is ratified by the country instead of by a supermajority. Defaulted
## to false, unlike apply()'s loader, because false is the behaviour every existing
## caller already has -- a default that means "the way it has always worked" hides
## nothing, where a default that means "skip a step" hides everything.
##
## `support_bonus` is V4.2 T6's, and it is a DEFAULTED parameter on purpose: the
## signature owns about twenty-five call sites and the plan forbade changing
## their shape. The alternative the plan named first -- statute.gd resolving the
## division through a wrapper -- would have re-mirrored this loop and the
## majority match below verbatim, the >10-line duplication the plan's own
## constraint names as the review-finding class. A defaulted parameter keeps
## every existing call source-identical and gives the ONE caller that wants the
## endorsement (statute.gd's division on a private member's bill) a per-party
## additive that moves the PARTY's line without moving `own` -- the members'
## spatial view is theirs, so a line dragged onto a bill the backbench does not
## back can shed seats through the rebellion split that already prices exactly
## that strain. Re-clamped here because support() clamps before the add.
static func resolve_vote(ns, party_list: Array, law, referendum := false, support_bonus := 0.0) -> Dictionary:
	var yes_seats := 0
	var no_seats := 0
	var abstain_seats := 0
	var party_votes := {}
	var party_support := {}
	var party_rebels := {}

	for party in party_list:
		var s: float = support(ns, party, law)
		if support_bonus != 0.0:
			s = clampf(s + support_bonus, -1.0, 1.0)
		var own: float = spatial_support(ns, party, law)
		party_support[party.id] = s

		var seats: int = int(ns.seats_by_party.get(party.id, 0))
		var line := vote_of(s)
		var rebel_line := vote_of(own)

		var rebels := 0
		if rebel_line != line:
			rebels = Discipline.rebel_seats(ns, party, s, own)
		if rebels > 0:
			party_rebels[party.id] = rebels

		match line:
			"yes": yes_seats += seats - rebels
			"no": no_seats += seats - rebels
			_: abstain_seats += seats - rebels
		match rebel_line:
			"yes": yes_seats += rebels
			"no": no_seats += rebels
			_: abstain_seats += rebels

		party_votes[party.id] = line

	var seats_total: int = ns.assembly_seats
	var passed: bool
	match law.majority:
		"simple":
			passed = yes_seats > no_seats
		"absolute":
			passed = float(yes_seats) > LK.ABSOLUTE_MAJORITY_FRACTION * float(seats_total)
		"two_thirds":
			passed = float(yes_seats) >= LK.TWO_THIRDS_MAJORITY_FRACTION * float(seats_total)
		"amendment":
			# Reads the PROPOSING nation's own threshold, not a fixed fraction --
			# the whole point of amendment_rule being per-nation data. Every rule has
			# had a fraction since V1.7c gave referendum_required one; the check
			# stays because an unrecognised rule is still a content bug rather than a
			# runtime state a played game can produce.
			if not LK.AMENDMENT_RULE_FRACTIONS.has(ns.amendment_rule):
				push_error("legislature: amendment_rule '%s' has no seat fraction" % ns.amendment_rule)
				passed = false
			elif referendum:
				# Route B. The referendum replaces the SUPERMAJORITY, not the
				# division -- Art. 89 (FRA), Art. 138 (ITA), Art. 114 (LUX) and
				# Art. 195 (CHE) all put an ordinary chamber majority first. So
				# "passed" here means "carried in the chamber and now goes to the
				# country", and propose() is what turns that into a pending vote.
				#
				# `simple` and not `absolute`, and the probe is what settled it. Art.
				# 89's first stage is the ORDINARY legislative procedure, which is a
				# majority of votes CAST; the absolute reading counts abstentions
				# against and put route B at 270 of the 289 seats it needed in every
				# one of 168 months, so the verb was unreachable in a played run --
				# V1.3f's error, caught by tools/referendum_probe.gd's table R6 rather
				# than shipped. Luxembourg (Art. 114) and Switzerland (Art. 195) read
				# the same way; ITALY IS THE OUTLIER, whose Art. 138 second vote is
				# explicitly absolute, and that divergence is recorded in
				# docs/referendum-model.md the way docs/electoral-systems.md records a
				# per-method reduction rather than being modelled per nation.
				passed = yes_seats > no_seats
			else:
				# A rule at the absolute fraction is "more than half", like the
				# absolute arm above; the higher ones are "at least" bars (V5.0d:
				# >= let a GBR amendment carry at exactly 325 of 650).
				var bar: float = LK.AMENDMENT_RULE_FRACTIONS[ns.amendment_rule] * float(seats_total)
				passed = float(yes_seats) > bar if LK.AMENDMENT_RULE_FRACTIONS[ns.amendment_rule] <= LK.ABSOLUTE_MAJORITY_FRACTION else float(yes_seats) >= bar
		_:
			push_error("legislature: unknown majority type '%s'" % law.majority)
			passed = false

	return {
		"law_id": law.id,
		"passed": passed,
		"majority": law.majority,
		"referendum_route": referendum,
		"yes_seats": yes_seats,
		"no_seats": no_seats,
		"abstain_seats": abstain_seats,
		"seats_total": seats_total,
		"party_votes": party_votes,
		"party_support": party_support,
		"party_rebels": party_rebels,
	}


## Apply a passed law's effects onto ns. Budget-lever effects are routed through
## apply_effects() into Budget.apply_pending so the demand impulse, the erosion
## curve and the opinion issue all fire exactly as they would for a
## player-driven budget change -- the same mechanism, so double-counting is
## structurally impossible. Every other channel is one clamped accumulator, read
## by an existing formula.
##
## V4.2. Two additions, both of them the statute book and neither a new
## applier:
##
##   - A REPEAL subtracts first. A law with `repeals` set removes the target's
##     REALIZED ledger through apply_effects() -- the negated channels, budget
##     levers routed into Budget.apply_pending so the erosion curve and the
##     demand impulse fire exactly as any budget change would -- then erases
##     the target's entry and writes the target's own cooldown (a repealed act
##     sits out its cooldown before it can be re-proposed). It happens at the
##     TOP of apply(), not in propose()'s passed branch, because apply() is
##     every path on which a bill takes effect -- the referendum settle and
##     the upper-house release included -- and a repeal that only worked on
##     one of them would be three machines.
##
##   - The LEDGER is recorded after. The before/after diff around
##     apply_effects() is what makes the record REALIZED rather than authored:
##     every accumulator clamps (and the two budget channels floor at zero --
##     _budget_removal below), and a repeal that subtracted authored deltas
##     against a bound that was binding at passage would drift the register on
##     every repeal. Only apply() records -- an event choice calls
##     apply_effects() directly and records nothing, because an event is not a
##     statute and has no repeal verb.
##
## `loader` is required, not defaulted -- a system transition needs
## loader.political_systems (to re-read lose_condition off the new template)
## and loader.parties (to derive an elected head of state's holder). A
## defaulted param would let a transition silently half-apply, the failure
## mode this project refuses throughout. See docs/transition-model.md.
static func apply(state, ns, law, loader) -> void:
	if law.repeals != "":
		_subtract_ledger(state, ns, loader, law.repeals)
	# V4.2 T4. A BIRTH registers its params BEFORE the rate moves, and this is
	# the ONE registration site: the rate's own application runs through
	# apply_effects() -> Budget.apply_pending, which refuses a pending rate whose
	# key has no params behind it -- so a birth that applied its rate first
	# would be refused by its own applier. One writer, one registration site.
	if not law.new_tax.is_empty():
		_register_new_tax(ns, law)
	var before := _effect_snapshot(ns, law.effects)
	apply_effects(state, ns, law.effects, loader)
	_record_ledger(state, ns, law, before, _effect_snapshot(ns, law.effects))
	if law.once:
		ns.passed_law_ids[law.id] = true


## The channels this law's passage actually moved, keyed as the ledger stores
## them. Only fields the law's own effects NAME are read -- a snapshot that
## walked every register would record another writer's movement as this law's.
static func _effect_snapshot(ns, effects: Dictionary) -> Dictionary:
	var snap := {}
	for key in effects.get("tax_rates_pct", {}):
		# "tax|%s" is split on "|" in _record_ledger to recover the sub-key, so
		# a key containing "|" would corrupt the record -- statute.draft()'s
		# new-tax charset gate (the pipe gate) is what keeps every key that
		# reaches here split-safe.
		snap["tax|%s" % key] = float(ns.tax_rates_pct.get(key, 0.0))
	for key in effects.get("spending_pct_gdp", {}):
		snap["spend|%s" % key] = float(ns.spending_pct_gdp.get(key, 0.0))
	if effects.has("structural_unemployment_pct"):
		snap["struct"] = ns.law_structural_offset_pct
	if effects.has("potential_growth_pct"):
		snap["pot"] = ns.law_potential_target_pct
	if effects.has("other_revenue_pct_gdp"):
		snap["orev"] = ns.law_other_revenue_pct_gdp
	for bloc in effects.get("bloc_offset", {}):
		snap["bloc|%s" % bloc] = float(ns.bloc_offset.get(bloc, 0.0))
	if effects.has("company"):
		var sector: String = String(effects["company"].get("sector", ""))
		snap["burden|%s" % sector] = float(ns.regulation_burden.get(sector, 0.0))
	for term in effects.get("society", {}):
		snap["soc|%s" % term] = _society_field(ns, term)
	return snap


static func _society_field(ns, term: String) -> float:
	match term:
		"corruption": return ns.corruption
		"migration": return ns.migration_stance
		"settlement": return ns.settlement_stance
		"press_freedom": return ns.press_freedom
		"judicial_independence": return ns.judicial_independence
	return 0.0


static func _record_ledger(state, ns, law, before: Dictionary, after: Dictionary) -> void:
	var channels := {}
	for snap_key: String in after:
		if not before.has(snap_key):
			continue
		var delta: float = float(after[snap_key]) - float(before[snap_key])
		if delta == 0.0:
			# EXACT zero, not is_zero_approx: the criterion is "the law moved
			# nothing", and is_zero_approx's 1e-5 ABSOLUTE floor would drop a
			# real sub-1e-5 realized delta -- unrecorded, the channel is
			# un-negatable at repeal and the act permanently un-repealable.
			# The V4.7 lesson's third appearance (industry.gd's 9.8e-6 drain;
			# statute.gd's own exact-zero erasure one file over), named here so
			# the next tolerance question finds the ruling with it.
			continue
		var parts := snap_key.split("|")
		match parts[0]:
			"tax": _ledger_add(channels, "tax_rates_pct", parts[1], delta)
			"spend": _ledger_add(channels, "spending_pct_gdp", parts[1], delta)
			"struct": _ledger_add(channels, "structural_unemployment_pct", "", delta)
			"pot": _ledger_add(channels, "potential_growth_pct", "", delta)
			"orev": _ledger_add(channels, "other_revenue_pct_gdp", "", delta)
			"bloc": _ledger_add(channels, "bloc_offset", parts[1], delta)
			"burden": _ledger_add(channels, "company", parts[1], delta)
			"soc": _ledger_add(channels, "society", parts[1], delta)
	if channels.is_empty():
		return
	var entry: Dictionary = ns.law_ledger.get(law.id, {"channels": {}, "months": []})
	_ledger_merge(entry["channels"], channels)
	entry["months"].append(int(state.year) * 12 + int(state.month))
	ns.law_ledger[law.id] = entry


## One channel of one law's ledger, summed across passages: {"tax_rates_pct":
## {"income": 10.0}, "bloc_offset": {"business": -0.3}, "company": {"sector":
## delta}, "society": {"term": delta}} -- dict channels key by their sub-key,
## scalar channels (the three law_* accumulators) key by "".
static func _ledger_add(channels: Dictionary, channel: String, sub_key: String, delta: float) -> void:
	if not channels.has(channel):
		channels[channel] = {}
	var slot: Dictionary = channels[channel]
	slot[sub_key] = float(slot.get(sub_key, 0.0)) + delta


## Merge one passage's realized channels into the law's accumulated entry --
## a non-once law passed twice is ONE act repealed once, so the second
## passage ADDS to the same sub-keys rather than opening a second entry.
static func _ledger_merge(into: Dictionary, from: Dictionary) -> void:
	for channel in from:
		if channel == "structural_unemployment_pct" or channel == "potential_growth_pct" \
				or channel == "other_revenue_pct_gdp":
			var slot: Dictionary = from[channel]
			_ledger_add(into, channel, "", float(slot.get("", 0.0)))
		else:
			var keyed: Dictionary = from[channel]
			for sub_key in keyed:
				_ledger_add(into, channel, sub_key, float(keyed[sub_key]))


## V4.2 T4. The ONE writer of ns.custom_taxes: a birth's params move onto the
## register in the shape the revenue lines and the save round-trip read --
## {name, base_share, erosion, ref_pct}. The Law's carrier holds `key` too
## (it names what to register); the ENTRY does not store it, because the
## register is keyed by it and a copy inside would be a second answer. The
## guard's remaining job is the UNNAMED key, refused loudly -- a birth with no
## key cannot be registered. An ALREADY-REGISTERED key is a QUIET no-op (the
## ultra pass-4 finding): composed birth laws are once:false by design
## (statute.gd's _compose), so a second passage of the same act is ordinary
## play -- the existing params entry wins (an overwrite would silently
## re-price a tax already on the books) and the rate re-adds through
## apply_effects() like any repeatable tax law. Typed field by field, the
## exact shape from_dict() rebuilds, so a live register and a loaded one
## cannot differ in shape.
static func _register_new_tax(ns, law) -> void:
	var key := String(law.new_tax.get("key", ""))
	if key == "":
		push_error("legislature: birth of tax key '%s' refused -- unnamed" % key)
		return
	if ns.custom_taxes.has(key):
		return
	ns.custom_taxes[key] = {
		"name": String(law.new_tax.get("name", "")),
		"base_share": float(law.new_tax.get("base_share", 0.0)),
		"erosion": float(law.new_tax.get("erosion", 0.0)),
		"ref_pct": float(law.new_tax.get("ref_pct", 0.0)),
	}


## The ledger entry's realized channels for one law, {} when none --
## repeal validation's first gate and Statute.draft()'s frozen preview
## source; a statute panel reads it when one exists.
static func ledger_of(ns, law_id: String) -> Dictionary:
	var entry: Dictionary = ns.law_ledger.get(law_id, {})
	return entry.get("channels", {})


## Whether `law_id` may be targeted by a repeal bill: the book must record it,
## and the target must not SET anything. That is not only the constitutional
## case -- the ordinary-reform route (law.gd's ORDINARY_INSTITUTIONAL_KEYS) lets
## a NON-constitutional law carry effects.institutional (the electoral-reform
## Acts: election_system / election_threshold_pct), and the setting has no
## inverse delta, so a repeal could subtract only the bloc price and leave the
## electoral system in force -- a half-removed act. Restoring an electoral
## system is a NEW reform act, not a repeal, so the gate refuses the channel,
## not the flag. A system transition proper is undone by AMENDMENT, not by
## repeal; that is what docs/amendment-model.md is for. A target the loader
## does not know is a custom law (T2's composed register); composed laws are
## never constitutional and never authored with an institutional channel, so
## the lookup's null reads legal.
static func repeal_target_legal(ns, loader, law_id: String) -> bool:
	if not ns.law_ledger.has(law_id):
		return false
	var target = Bills.by_id(loader, law_id)
	if target == null:
		return true
	return not target.constitutional and not target.effects.has("institutional")


## A repeal's subtraction. The negated channels go back through
## apply_effects() -- the one applier, whose budget levers reach
## Budget.apply_pending and every clamp re-fires symmetrically -- then the entry
## is erased and the target's own cooldown written.
##
## THE FIRST-ORDER BOUND, stated where it can bite: the subtraction clamps
## like any write, so a register already pushed past a bound by OTHER writers
## absorbs part of the removal (a law that contributed -0.10 against a
## register driven to +1.0 by everything else removes nothing). The two
## budget channels have no clamp and take their own floor instead -- a
## removal lands what the register holds, and no more (`_budget_removal`
## below). That is the declared bound of realized-delta bookkeeping --
## docs/legislature-model.md records it -- and not a patchable defect: the
## true counterfactual register is not recoverable once other writers have
## moved in between, and inventing one would be the second answer the
## project refuses.
static func _subtract_ledger(state, ns, loader, law_id: String) -> void:
	var channels: Dictionary = ledger_of(ns, law_id)
	if channels.is_empty():
		# QUIET, not loud. Two overlapping repeal windows are ordinary: the
		# propose path filters a consumed repealer (available()'s ledger gate)
		# but the held window cannot re-run that filter, so a release can arrive
		# with its target already subtracted -- the moot release in
		# _tick_held_bills marks that case and stops before here, and any other
		# route reaching an empty book is the same shape. A second subtraction
		# finding nothing to subtract is a no-op, not a defect: the first repeal
		# already took the book back to zero.
		return
	var negated := {}
	if channels.has("tax_rates_pct"):
		var rates := {}
		for key in channels["tax_rates_pct"]:
			rates[key] = _budget_removal(ns.tax_rates_pct, key, float(channels["tax_rates_pct"][key]))
		negated["tax_rates_pct"] = rates
	if channels.has("spending_pct_gdp"):
		var spending := {}
		for key in channels["spending_pct_gdp"]:
			spending[key] = _budget_removal(ns.spending_pct_gdp, key, float(channels["spending_pct_gdp"][key]))
		negated["spending_pct_gdp"] = spending
	for scalar in ["structural_unemployment_pct", "potential_growth_pct", "other_revenue_pct_gdp"]:
		if channels.has(scalar):
			negated[scalar] = -float(channels[scalar].get("", 0.0))
	if channels.has("bloc_offset"):
		var blocs := {}
		for bloc in channels["bloc_offset"]:
			blocs[bloc] = -float(channels["bloc_offset"][bloc])
		negated["bloc_offset"] = blocs
	if channels.has("company"):
		# The ledger keys the burden channel by sector; apply_effects() reads
		# {"sector": ..., "burden": ...}. A law may only ever name one sector
		# (law.gd's schema), so the entry has one key.
		var sector: String = String(channels["company"].keys()[0])
		negated["company"] = {"sector": sector, "burden": -float(channels["company"][sector])}
	if channels.has("society"):
		var terms := {}
		for term in channels["society"]:
			terms[term] = -float(channels["society"][term])
		negated["society"] = terms
	apply_effects(state, ns, negated, loader)
	ns.law_ledger.erase(law_id)
	# V4.4: the erase is silent otherwise, and the law_repealed hook needs to know
	# WHEN. One writer, one reader (events.gd), sparse.
	ns.repealed_at[law_id] = int(state.year) * 12 + int(state.month)
	# One lookup, one writer: the cooldown comes off the target law wherever it
	# lives. A composed law is not in loader.laws -- the lookup's null reads
	# legal in repeal_target_legal() above for exactly that reason -- so the
	# target is found a second time in the composed register, whose entries all
	# carry DRAFT_COOLDOWN_MONTHS. Without this half, a repealed composition
	# wrote no cooldown at all and available() re-offered it immediately: the
	# apply() header's own rule ("a repealed act sits out its cooldown before
	# it can be re-proposed") failed for the one class of law this block
	# introduced.
	var target = Bills.by_id(loader, law_id)
	if target == null:
		for composed in Law.composed_register(ns):
			if String(composed.id) == law_id:
				target = composed
				break
	if target != null and target.cooldown_months > 0:
		ns.law_cooldown_months[law_id] = target.cooldown_months
	# THE ONCE RETURN, the ultra pass-2 finding: a once-law's flag was the one
	# writer of passed_law_ids and nothing erased it, so a carried repeal
	# removed the act for ever while the docs promise "the act returns by being
	# re-proposed and re-passed after its cooldown". A carried repeal clears the
	# gate -- the act returns by re-passage exactly as documented -- and the
	# once flag's purpose (no re-passing without a fight) survives, because only
	# a CARRIED REPEAL clears it. Composed laws are pinned once:false at birth,
	# so this is the authored class only.
	if target != null and target.once:
		ns.passed_law_ids.erase(law_id)


## THE BUDGET FLOOR, the ultra pass-8 finding: the two budget channels have no
## clamp -- commit() writes them verbatim and every UI writer floors its slider
## at 0.0 -- so a repeal's negation must never land a NEGATIVE rate, a state
## the birth gate's own words refuse ("a negative birth rate is not a rate")
## and the revenue model turns into an unpriced payout. The formula floors the
## RESULTING RATE at zero through both directions: a raise-removal lands what
## the register holds (current 0, recorded +5 -> 0 removal), and a
## cut-restoration passes whole (recorded -5, current 20 -> +5, back to 25).
## Budget.apply_pending() carries the matching landed-rate floor for its other
## callers; the accumulators keep their clamps and need none of this.
static func _budget_removal(register: Dictionary, key: String, recorded: float) -> float:
	var current: float = float(register.get(key, 0.0))
	return maxf(-recorded, -current)


## THE CHANNEL DISPATCH, EXTRACTED AT V1.8 SO AN EVENT CHOICE REACHES IT TOO.
##
## Split out of apply() above and not otherwise changed. What made the split worth
## taking rather than duplicating is the pair of things it protects: `bloc_offset`,
## `regulation_burden`, `corruption`, `migration_stance`, `settlement_stance` and
## `press_freedom` each have exactly ONE writer, and it is this function. A second
## applier in src/sim/events.gd would have been a second writer of all six -- the
## divergence the symmetric pair key exists to make impossible, at the width of a whole
## block -- and the six clamps would then have to agree by inspection rather than by
## being the same line of code.
##
## The APPROVAL PATH is what separates the two callers, and that is V1.4a/V1.4b's a/b
## line one block later: a regulation reaches effects.company through an assembly
## division and a subsidy reaches it directly, and here a law reaches these channels
## through a vote where an event choice reaches them through a decision made under a
## deadline. Same mechanism, different route, one writer.
##
## `loader` stays required for apply()'s own reason -- see its header.
static func apply_effects(state, ns, effects: Dictionary, loader) -> void:
	var pending := {}
	if effects.has("tax_rates_pct"):
		var rates := {}
		for key in effects["tax_rates_pct"]:
			rates[key] = float(ns.tax_rates_pct.get(key, 0.0)) + float(effects["tax_rates_pct"][key])
		pending["tax_rates_pct"] = rates
	if effects.has("spending_pct_gdp"):
		var spending := {}
		for key in effects["spending_pct_gdp"]:
			spending[key] = float(ns.spending_pct_gdp.get(key, 0.0)) + float(effects["spending_pct_gdp"][key])
		pending["spending_pct_gdp"] = spending
	if not pending.is_empty():
		# The NATION-scoped writer, not Budget.commit(): commit is the player's
		# command and reads state.player(). This stays the safeguard so that no
		# caller whose ns is not the player's can ever reach commit: V4.4's first
		# chooser applied the other twenty-eight nations' fiscal answers here and
		# through commit would have rewritten the player's budget with another
		# government's crisis response. Since pass 23 AI event answers skip the
		# fiscal channels (Events._resolve), so today no AI caller arrives here.
		Budget.apply_pending(ns, pending)
		Budget.recompute(state, ns)

	if effects.has("structural_unemployment_pct"):
		ns.law_structural_offset_pct = clampf(
			ns.law_structural_offset_pct + float(effects["structural_unemployment_pct"]),
			LK.STRUCTURAL_OFFSET_MIN_PCT, LK.STRUCTURAL_OFFSET_MAX_PCT
		)

	if effects.has("potential_growth_pct"):
		ns.law_potential_target_pct = clampf(
			ns.law_potential_target_pct + float(effects["potential_growth_pct"]),
			LK.POTENTIAL_TARGET_MIN_PCT, LK.POTENTIAL_TARGET_MAX_PCT
		)

	if effects.has("other_revenue_pct_gdp"):
		ns.law_other_revenue_pct_gdp = clampf(
			ns.law_other_revenue_pct_gdp + float(effects["other_revenue_pct_gdp"]),
			LK.OTHER_REVENUE_MIN_PCT, LK.OTHER_REVENUE_MAX_PCT
		)

	if effects.has("bloc_offset"):
		for bloc in effects["bloc_offset"]:
			var current: float = float(ns.bloc_offset.get(bloc, 0.0))
			ns.bloc_offset[bloc] = clampf(
				current + float(effects["bloc_offset"][bloc]),
				LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX
			)

	# V1.4b, THE FIFTH EFFECT CHANNEL REACHED FROM THIS SIDE. A subsidy reaches
	# effects.company through Companies.execute() as an executive act; a regulation
	# reaches the same channel through here, having survived an assembly division
	# first. That is the whole of the a/b split, and it is two lines of code because
	# the split is about the APPROVAL PATH and not about the mechanism.
	#
	# Accumulates and is SIGNED, so a deregulation law is the negative direction on
	# the same register -- still true now the repeal verb exists (V4.2): repeal
	# removes whole acts or nothing, it never moves a register partway, so easing a
	# sector stays the signed channel's job. One clamp, on the accumulated value --
	# the two channels companies.gd reads it through carry their own.
	# V5.2 b+ R14: an adopted ownership bill runs its verb through the law's door
	# (src/sim/bills.gd): the price on the debt and the act's own bloc_offset, once.
	if effects.has("company_ownership"):
		Bills.adopt(state, ns, loader, effects["company_ownership"])
	if effects.has("company"):
		var sector: String = String(effects["company"]["sector"])
		var burden: float = float(effects["company"]["burden"])
		ns.regulation_burden[sector] = clampf(
			float(ns.regulation_burden.get(sector, 0.0)) + burden,
			-CK.REGULATION_BURDEN_MAX, CK.REGULATION_BURDEN_MAX
		)

	# V1.5a's sixth channel, and the ONLY writer of ns.corruption in the project.
	# Accumulates and is SIGNED for the two reasons src/core/law.gd's
	# _extract_society() gives -- the second of which V1.4b did not need: a
	# one-directional level would make an anti-corruption law inert on a clean state.
	#
	# One clamp, on the accumulated value, exactly as the burden above. The factor
	# society.gd reads it through carries its own bounds, so a second clamp here
	# would be a guard rail guarding a guard rail.
	#
	# V1.5b adds `migration` as a SIBLING accumulator on the same channel, and the two
	# are independent: a law may name either or both, law.gd's _extract_society()
	# requires at least one, and each clamps against its own maximum. This is the only
	# writer of ns.migration_stance in the project, as it is of ns.corruption.
	if effects.has("society"):
		var society: Dictionary = effects["society"]
		if society.has("corruption"):
			ns.corruption = clampf(
				ns.corruption + float(society["corruption"]),
				-SK.CORRUPTION_MAX, SK.CORRUPTION_MAX
			)
		if society.has("migration"):
			ns.migration_stance = clampf(
				ns.migration_stance + float(society["migration"]),
				-DemoK.MIGRATION_STANCE_MAX, DemoK.MIGRATION_STANCE_MAX
			)
		# V1.5c adds `settlement` as a THIRD sibling on the same terms, and this is the
		# only writer of ns.settlement_stance in the project. A third register on one
		# channel with no new shape is what turns V1.5a's declaration into a fact.
		if society.has("settlement"):
			ns.settlement_stance = clampf(
				ns.settlement_stance + float(society["settlement"]),
				-UnrestK.SETTLEMENT_STANCE_MAX, UnrestK.SETTLEMENT_STANCE_MAX
			)
		# V1.5d adds `press_freedom` as a FOURTH sibling, and this is the only writer of
		# ns.press_freedom in the project. Four registers on one channel written by four
		# consecutive sessions, each needing exactly this many lines, is the strongest
		# form of the claim society-model.md section 3 made with one term.
		if society.has("press_freedom"):
			ns.press_freedom = clampf(
				ns.press_freedom + float(society["press_freedom"]),
				-MediaK.PRESS_FREEDOM_MAX, MediaK.PRESS_FREEDOM_MAX
			)
		# V1.1e adds `judicial_independence` as a FIFTH sibling, by a fifth session, and
		# this is the only writer of ns.judicial_independence in the project. It is the
		# first of the five whose stock is a LEVEL rather than a signed stance -- it is
		# seeded from the nation's own measured rule-of-law score where the four above
		# start at 0.0 for everybody -- so its clamp is one-sided in neither direction
		# but bounded by the score's own scale, and law.gd bounds a single Act
		# separately at INDEPENDENCE_LAW_MAX.
		if society.has("judicial_independence"):
			ns.judicial_independence = clampf(
				ns.judicial_independence + float(society["judicial_independence"]),
				JudiciaryK.INDEPENDENCE_MIN, JudiciaryK.INDEPENDENCE_MAX
			)

	# An institution is SET, not nudged -- every key here is an absolute value
	# written straight onto NationState, unlike every channel above. Whether
	# the value is legal for this nation's system was already checked at load
	# by DataLoader against this law's own `systems` list, so writing it here
	# cannot produce the half-understood state V1.2b's cross-check refuses --
	# see docs/amendment-model.md.
	if effects.has("institutional"):
		var inst: Dictionary = effects["institutional"]
		# system_id first -- everything below it in this block, and
		# lose_condition just after, is read as "the new system's own rule",
		# so the nation has to already be pointed at the target before any of
		# them are written. See docs/transition-model.md.
		if inst.has("system_id"):
			ns.system_id = inst["system_id"]
		if inst.has("censure_rule"):
			ns.censure_rule = inst["censure_rule"]
		if inst.has("dissolution_rule"):
			ns.dissolution_rule = inst["dissolution_rule"]
		if inst.has("formation_method"):
			ns.formation_method = inst["formation_method"]
		if inst.has("amendment_rule"):
			ns.amendment_rule = inst["amendment_rule"]
		if inst.has("term_limit"):
			ns.term_limit = int(inst["term_limit"])
		if inst.has("term_months"):
			ns.term_months = int(inst["term_months"])
		# V1.7c, and the only two keys here an ORDINARY Act may write -- see
		# law.gd's ORDINARY_INSTITUTIONAL_KEYS. Read by Elections.resolve() at the
		# next national vote; the European one allocates on pr_national regardless.
		if inst.has("election_system"):
			ns.election_system = inst["election_system"]
		if inst.has("election_threshold_pct"):
			ns.election_threshold_pct = float(inst["election_threshold_pct"])
		if inst.has("system_id"):
			# lose_condition lives on the template, not the nation -- see
			# docs/political-systems.md -- so a transition has to re-read it
			# off the TARGET template, the same way game_state.gd's
			# _build_nation() reads it at new-game.
			var system = loader.political_systems.get(inst["system_id"])
			ns.lose_condition = system.lose_condition if system != null else ns.lose_condition
		if inst.has("head_of_state"):
			_apply_head_of_state(state, ns, loader, inst["head_of_state"])


## Writes a system transition's new head of state. `hos` is law.gd's already-
## validated {kind, title, term_years?} -- and it carries NO name for any kind
## now. The holder is derived on both branches: for `elected_president` from the
## largest party's own leader, because an elected president is someone already on
## the board; and for anything else from the acting nation's own
## `government.pretender_person`.
##
## That second branch is U6b's, and it fixed a real content bug rather than
## tidying one. The Restoration Act authored "Alexander IV" inline, and it
## applies to any `parliamentary_republic` -- so every republic in Europe
## restored the same king. A law names an OFFICE; a nation names the person.
## See docs/transition-model.md and docs/people-model.md.
static func _apply_head_of_state(state, ns, loader, hos: Dictionary) -> void:
	ns.head_of_state_kind = hos["kind"]
	ns.head_of_state_title = hos["title"]
	if hos["kind"] == "elected_president":
		var party_list: Array = loader.parties.get(ns.id, [])
		var largest_id := Government.largest_party_id(ns, party_list)
		var holder_id := ""
		for party in party_list:
			if party.id == largest_id:
				holder_id = party.leader_person_id
				break
		ns.head_of_state_person_id = holder_id
		var term_years := int(hos["term_years"])
		ns.head_of_state_next_year = int(state.year) + term_years
		ns.head_of_state_next_month = int(state.month)
	else:
		var nation = loader.nations.get(ns.id, null)
		ns.head_of_state_person_id = nation.pretender_person_id if nation != null else ""
		ns.head_of_state_next_year = 0
		ns.head_of_state_next_month = 0


## The player command: resolve the vote, apply effects on passage, set a
## cooldown on failure, and record the result for the law screen to read.
## `loader` is the same DataLoader main.gd already threads through to
## Elections.tick_month() -- parties live in loader.parties, keyed by nation id.
##
## `force` is Article 49.3: the bill is adopted without a vote, and the assembly
## may then censure the government instead. See docs/government-model.md.
##
## Article 49.3 cannot force a constitutional amendment through -- the real
## Article 89 revision procedure is a separate track with no executive
## bypass, and this game invents no such bypass for any nation's amendment
## rule either. See docs/amendment-model.md.
## Whether this law may be put to the country by the player's own choice. An
## ordinary Act may not: a referendum in this game ratifies an ENTRENCHED change,
## and putting an electoral-reform bill to a plebiscite is a different mechanic with
## a different real basis (the UK's 2011 AV vote was advisory and voluntary). A
## nation whose constitution has no route may not either, and one whose route is
## MANDATORY does not need asking -- propose() reads that off the nation instead.
static func can_put_to_referendum(ns, law) -> bool:
	if not law.constitutional:
		return false
	if Referendum.is_pending(ns):
		return false
	return Referendum.may_choose(ns)


## `referendum` is ROUTE B, and it is refused for anything but a constitutional
## amendment under a constitution that offers the route. A carried division does NOT
## apply the law: it calls the country, and Legislature.tick_month() settles it
## REFERENDUM_DELAY_MONTHS later. See docs/referendum-model.md.
static func propose(state, loader, law, force := false, referendum := false) -> Dictionary:
	var ns = state.player()
	var party_list: Array = loader.parties.get(ns.id, [])

	# V5.2 b+ R2. ONE PLAYER BILL BEFORE THE ASSEMBLY AT A TIME, and Article 49.3
	# waits for it too: the sitting that divides the tabled bill ends at the
	# month's close. Checked first, so the refusal names the real reason.
	if not ns.tabled_bill.is_empty():
		return refused(ns, law.id, law.majority, "already_tabled")

	# THE ACTION MUST STILL BE LEGAL, which the other four player verbs -- the
	# diplomacy, campaign, pledge and project executors -- each check and this one,
	# the fifth, did not, leaving the UI as the only gate. (Named in prose rather
	# than in code form because tests/test_pledges.gd scans this directory for the
	# literal call and a comment would read as one.) The case
	# that bites is a law already put to the country: available() excludes it, but
	# propose() would still resolve a division and apply it, after which the pending
	# referendum settles and applies the same effects a SECOND time, or fails and
	# writes a cooldown on a law already in force. Checked ahead of the force and
	# referendum routes below because a cooldown is not something Article 49.3
	# overrides -- 49.3 bypasses the assembly, not the clock.
	# V4.2 T2. The scan reads the authored list PLUS the composed register --
	# a custom law is a law like any other, and a scan that could not find
	# one would refuse the player's own bill as unavailable, which is both a
	# wrong verdict and the loss of the double-application guard this scan
	# exists to keep (an unfound law is an unchecked law).
	if open_law(state, ns, loader, law.id) == null:
		var unavailable := {
			"law_id": law.id, "passed": false, "refused": true, "unavailable": true,
			"majority": law.majority, "yes_seats": 0, "no_seats": 0, "abstain_seats": 0,
			"seats_total": ns.assembly_seats, "party_votes": {}, "party_support": {}, "party_rebels": {},
		}
		ns.last_law_result = unavailable
		return unavailable

	if referendum and not can_put_to_referendum(ns, law):
		var no_route := {
			"law_id": law.id, "passed": false, "refused": true, "referendum_route": true,
			"majority": law.majority, "yes_seats": 0, "no_seats": 0, "abstain_seats": 0,
			"seats_total": ns.assembly_seats, "party_votes": {}, "party_support": {}, "party_rebels": {},
		}
		ns.last_law_result = no_route
		return no_route

	if force and law.constitutional:
		var refused := {
			"law_id": law.id, "passed": false, "forced": true, "refused": true,
			"majority": law.majority, "yes_seats": 0, "no_seats": 0, "abstain_seats": 0,
			"seats_total": ns.assembly_seats, "party_votes": {}, "party_support": {}, "party_rebels": {},
		}
		ns.last_law_result = refused
		return refused

	if force:
		return _force(state, ns, party_list, law, loader)

	var route := takes_route(ns, law, referendum)

	# ONE REFERENDUM AT A TIME ON THE MANDATORY ROUTE TOO. can_put_to_referendum()
	# is where is_pending() is checked, and the mandatory branch above never passes
	# through it -- so with a vote in flight on law A, a constitutional law B took
	# the route anyway and Referendum.announce() overwrote ns.referendum_pending
	# wholesale: A's question vanished with no cooldown, no charge and no record.
	# Latent only because CHE is the sole `mandatory` nation and is not playable.
	if route and Referendum.is_pending(ns):
		# Its OWN flag rather than `referendum_route`, which law_panel.gd reads to
		# print "this constitution has no referendum route for that" -- the opposite
		# of what happened here, since this branch is only reachable BECAUSE the
		# constitution has one.
		var in_flight := {
			"law_id": law.id, "passed": false, "refused": true, "referendum_in_flight": true,
			"majority": law.majority, "yes_seats": 0, "no_seats": 0, "abstain_seats": 0,
			"seats_total": ns.assembly_seats, "party_votes": {}, "party_support": {}, "party_rebels": {},
		}
		ns.last_law_result = in_flight
		return in_flight

	# V5.2 b+ R2. TABLED, NOT DIVIDED. The bill is before the Assembly until the
	# close that ends the month, where Division.divide() runs what this function
	# used to run at once (the division, the second chamber, the referendum call,
	# the court, the cooldown) as that close's first step. What comes back is the
	# tabling: the vote day and the forecast, resolve_vote() now -- the pure read
	# the panel already shows. Nothing is written to last_law_result until then.
	ns.tabled_bill = {
		"law_id": law.id, "referendum": referendum, "vote_year": int(state.year),
		"vote_month": int(state.month), "vote_day": Calendar.days_in_month(int(state.year), int(state.month)),
	}
	var tabling: Dictionary = ns.tabled_bill.duplicate()
	tabling["tabled"] = true
	tabling["forecast"] = resolve_vote(ns, party_list, law, route)
	return tabling


## Whether the bill goes to the country after the chamber. A mandatory referendum is
## not a choice the caller makes -- Art. 195 says there is no seats-only path -- so it
## is read off the nation rather than off the button. An `optional` route is the
## caller's; a `mandatory` one is the constitution's, and offering it as an
## alternative would imply the seats-only path it says does not exist. One rule for
## propose() and for the division (src/sim/division.gd) that runs at the close.
static func takes_route(ns, law, referendum: bool) -> bool:
	return referendum or (law.constitutional and Referendum.is_mandatory(ns))


## The law `law_id` among the bills `ns` may table now, or null. propose()'s
## legality and the division's rebuilding of its tabled id are one scan, so the
## division re-reads at the vote the legality the press checked.
static func open_law(state, ns, loader, law_id: String):
	for law in available(ns, Bills.open(state, ns, loader)):
		if law.id == law_id:
			return law
	return null


## A refusal's result, the shape propose()'s refusals all write: nothing divided,
## the `flag` key naming why. Written to last_law_result, as theirs are.
static func refused(ns, law_id: String, majority: String, flag: String) -> Dictionary:
	var result := {
		"law_id": law_id, "passed": false, "refused": true, flag: true,
		"majority": majority, "yes_seats": 0, "no_seats": 0, "abstain_seats": 0,
		"seats_total": ns.assembly_seats, "party_votes": {}, "party_support": {}, "party_rebels": {},
	}
	ns.last_law_result = result
	return result


static func _by_id(party_list: Array) -> Dictionary:
	var by_id := {}
	for party in party_list:
		by_id[party.id] = party
	return by_id


## Article 49.3. The bill is adopted with no vote taken, which is why every seat
## tally below is zero -- there was no division. What the government pays for it
## is a censure motion resolved at FORCE_HOSTILITY_BONUS, and the risk is real
## only for a government that cannot cover the censure threshold.
static func _force(state, ns, party_list: Array, law, loader) -> Dictionary:
	var result := {
		"law_id": law.id,
		"passed": true,
		"forced": true,
		"majority": law.majority,
		"yes_seats": 0,
		"no_seats": 0,
		"abstain_seats": 0,
		"seats_total": ns.assembly_seats,
		"party_votes": {},
		"party_support": {},
		"party_rebels": {},
	}

	if not Government.can_force(ns):
		result["passed"] = false
		result["refused"] = true
		ns.last_law_result = result
		return result

	# V1.1e. A forced bill skips the SECOND CHAMBER and does not skip the COURT, and
	# both halves are real. Art. 49.3 is the Government engaging its responsibility
	# before the Assembly, and a Government determined enough to do that is a
	# Government that has already given the Assembly the last word under Art. 45 --
	# so 49.3 IS the way past the Senate, which is a property nobody authored. It is
	# not a way past the Conseil constitutionnel: the 2023 pension reform reached it
	# after a 49.3 and was partly struck, and that citation is in FRA.json's own
	# government.judicial._note. Only presidential_appointment can force at all, and
	# no nation with an ABSOLUTE second chamber uses it, so nothing is bypassed here
	# that could have killed the bill outright.
	_review_and_apply(state, ns, law, loader, result)
	#
	# A struck bill still costs the government everything forcing it cost: the cooldown
	# below and the censure motion after it are the price of BYPASSING the assembly, not
	# the price of a bill that worked -- docs/government-model.md says forcing costs
	# approval whether or not the motion carries, and this is that sentence one gate
	# later.
	ns.force_cooldown_months = GK.FORCE_COOLDOWN_MONTHS

	var by_id := _by_id(party_list)

	# Bypassing the assembly costs something whether or not the censure motion
	# carries. Without this, a government that can cover the threshold would
	# force every bill it could not win, for free.
	Government.penalise_blocs(ns, GK.FORCE_BLOC_PENALTY)

	# The second price of the article, and the one paid in the chamber rather
	# than in the polls: a government that goes over its own majority's head
	# finds that majority less willing the next time it asks. Applied before the
	# censure motion resolves, because the insult is the reason for the motion.
	Discipline.penalise(ns, ns.coalition_party_ids, DK.FORCE_DISCIPLINE_PENALTY, by_id)

	# Resolved against the government the bill was forced through for, and
	# before any collapse re-forms it, so the vote reads the coalition that
	# actually did the forcing.
	var censure := Government.resolve_censure(ns, party_list, true)
	Discipline.penalise_rebellions(ns, censure["party_rebels"], by_id)
	if censure["carried"]:
		Government.fall(ns, party_list, censure)
		# Cabinet.seat() is called here rather than from inside government.gd
		# itself -- Cabinet depends on Government (cohesion(), penalise_blocs()),
		# so the reverse would be a preload() cycle. See docs/cabinet-model.md.
		Cabinet.seat(ns, party_list)

	ns.last_censure = censure
	result["censure"] = censure
	ns.last_law_result = result
	return result
