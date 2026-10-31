extends RefCounted

## V4.3, People who want things: the wants -> acts machine. A LEAF, and the
## tier's own list of what it may touch: character_constants (the schema),
## staff.gd (the V5.3-0 leaf that hands it the cast it walks), legislature.gd
## (the ONE applier, for a brief's bloc_offset price) and government.gd
## (penalise_blocs, the government-price primitive). It never
## preloads cabinet, elections, unrest, media or judiciary -- the METER
## VALUES arrive as arguments the caller hands in, the calendar.gd leaf
## discipline, and what it reads of the world it reads off NationState.
##
## WHAT IT OWNS: the six person-state registers' values. Standing seeds from
## authored ambition; loyalty and grudges move with the acts the player's
## choices produce; the two override registers carry a challenge's or a
## defection's result. What it never does: write seats_by_party (the seat
## follows the whip; elections' to write), write a second approval number
## (bloc_offset is the one channel, priced through the ONE applier), or touch
## the meters (KIND_METERS is a READ).
##
## DETERMINISM IS THE LAW: no rand() anywhere. The whole balance harness
## exists on the promise that two runs differing in one decision differ in
## nothing else, and a coin-flip challenge would void it.
##
## TICK ORDER, pinned by tests/test_characters.gd from this file's source:
## after Cabinet.tick_month, before Elections.tick_month -- wants read
## Opinion-settled state, acts price bloc_offset that Opinion reads NEXT
## month, and Elections, the stamp pair's only writer, still runs last.
##
## ============================================================================
## THE TWO REGISTERS COUPLE THROUGH THE TERM'S OWN HISTORY, AND THAT IS THE
## CHANNEL (rebuilt at the review's C2 -- the first ship's arithmetic was dead)
## ============================================================================
## A STANDING want denied at a level (a meter the government is not holding, an
## entry not on the term's register) accrues GRUDGE_WANT_DENIED a month, net of
## GRUDGE_DECAY_MONTHLY; a DISCRETE one (a portfolio lost) charges once at the
## turn; and briefing against the government costs the briefer LOYALTY_ACT_COST
## of loyalty. So the two registers are ONE WALK: sustained denial builds a
## grudge, the grudge crosses GRUDGE_BRIEF_THRESHOLD, the brief relieves part of
## it and takes a loyalty step, and a person who keeps being denied keeps
## briefing until their loyalty reaches LOYALTY_RESIGN_FLOOR. Neither register
## reaches an act threshold on its own, nothing here fires in one month, and no
## act fires until the person has been served at least once under this player's
## watch (the latch, below). The numbers and their arithmetic are in
## character_act_constants.gd.

const CharacterK = preload("res://src/sim/character_constants.gd")
const Government = preload("res://src/sim/government.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const CK = preload("res://src/sim/character_act_constants.gd")
const Staff = preload("res://src/sim/staff.gd")


## Seed standing for the people of ONE nation (new_game calls it for the
## player's, the only nation whose registers anything reads) off authored
## ambition, the only value the register holds before anything happens. The
## seed is ambition plus the trait's floor (the scalar is the dial, the trait
## is the floor -- 14.2's own distinction), so an ambitious person starts
## with weight to use and a contented one starts anonymous. V5.3-0: the people
## are the nation's cast (Staff.cast), so a chief of staff is never seeded.
static func init_nation(ns, loader) -> void:
	ns.person_loyalty.clear()
	ns.person_standing.clear()
	ns.person_grudges.clear()
	ns.party_leader_override.clear()
	ns.person_party_override.clear()
	ns.person_want_state.clear()
	for person in Staff.cast(loader, ns.id):
		var standing := CK.STANDING_SEED_BASE + CK.STANDING_SEED_AMBITION * float(person.ambition)
		if person.traits.has("ambitious"):
			standing += CK.STANDING_SEED_AMBITIOUS_BONUS
		ns.person_standing[person.id] = clampf(standing, 0.0, 1.0)
		ns.person_loyalty[person.id] = 0.0
		ns.person_grudges[person.id] = 0.0


## The month: settle wants into loyalty and grudges, decay the grudges, then
## let the grudge's own pressure cross an act threshold where it does. Acts
## are priced on the machines the table in people-model 14.5 names, and only
## the player's nation runs -- the nine's casts are scenery until they are
## not, and a national register for an AI nation is content nothing reads.
##
## meters: {grievance: float, press_freedom: float, judicial_independence:
## float} -- the caller reads the three meters and hands the values in; this
## file preloads none of their systems.
static func tick_month(state, loader, meters: Dictionary) -> Array:
	var ns = state.player()
	var acts: Array = []

	# The authored leadership edges, walked once: the leaf law keeps party.gd
	# out of this file, so the loader's own parties array supplies the edges
	# every leader read below needs.
	var authored_leaders := {}
	for party in loader.parties.get(state.player_nation_id, []):
		authored_leaders[party.id] = party.leader_person_id

	var people: Array = Staff.cast(loader, state.player_nation_id)
	# The person OBJECTS by id, for the two trait gates that are a property of
	# the person and not of the pulse: PRAGMATIC and STUBBORN scale the decay,
	# so the decaying loop needs the traits in hand. Built once here rather
	# than scanned per register entry.
	var by_id := {}
	for person in people:
		by_id[person.id] = person

	# Decay first, so a settled grudge halves before this month's want settles
	# -- the same sub-ordering opinion.gd uses for the honeymoon, where
	# decaying the old stock before the new pulse lands is what makes the
	# half-life mean the same thing in every month of a term. The acts' old
	# cost fades in the same place, before this month's acts add to it.
	_decay_grudges(ns, by_id)
	_fade_act_offsets(ns)

	# Wants settle, priced on satisfaction the DERIVED reads give. Only an
	# UNSATISFIED want moves a person, and only by the amount the band allows.
	for person in people:
		_settle_wants(ns, person, meters, authored_leaders)

	# The acts, in CK.ACT_KEYS order for determinism, each gated on its own
	# threshold read. One act per person per month -- a person mid-defection
	# does not also brief against the government in the same month, which is
	# as much a legibility rule as a balance one.
	var acted: Dictionary = {}
	var before: Dictionary = ns.bloc_offset.duplicate()
	for act_key in CK.ACT_KEYS:
		for person in people:
			if acted.has(person.id):
				continue
			if _fire_act(state, ns, loader, person, act_key, meters, acts, authored_leaders):
				acted[person.id] = true
	_record_act_offsets(ns, before)
	return acts


## V5.2b, "le cout s'efface": what this month's acts wrote on bloc_offset --
## the real delta, after the clamp, since nothing else in this tick writes it --
## joins the share that fades. The acts price through two doors (the applier for
## a brief, Government.penalise_blocs for the rest), so the record reads the
## result rather than either door.
static func _record_act_offsets(ns, before: Dictionary) -> void:
	for bloc in ns.bloc_offset:
		var wrote := float(ns.bloc_offset[bloc]) - float(before.get(bloc, 0.0))
		if wrote != 0.0:
			ns.act_bloc_offset[bloc] = float(ns.act_bloc_offset.get(bloc, 0.0)) + wrote


## The acts' share shrinks by ACT_OFFSET_MONTHLY_KEEP and bloc_offset gets back
## what faded, so a leak hurts the next vote and is then forgotten. A share too
## small to read is dropped, so the register does not grow a tail of zeros.
static func _fade_act_offsets(ns) -> void:
	for bloc in ns.act_bloc_offset.keys():
		var part := float(ns.act_bloc_offset[bloc])
		var kept := part * CK.ACT_OFFSET_MONTHLY_KEEP
		ns.bloc_offset[bloc] = clampf(float(ns.bloc_offset.get(bloc, 0.0)) + (kept - part),
			Legislature.LK.BLOC_OFFSET_MIN, Legislature.LK.BLOC_OFFSET_MAX)
		if absf(kept) < 0.000001:
			ns.act_bloc_offset.erase(bloc)
		else:
			ns.act_bloc_offset[bloc] = kept


## The grudge half-life, with the two decay traits applied where the person is
## in hand: PRAGMATIC lets go of it twice as fast, STUBBORN holds it twice as
## long. Both multiply, so a person carrying both decays at exactly the base
## rate -- which is the honest reading of two gates that pull opposite ways,
## and is recorded rather than special-cased.
##
## The loop runs over the REGISTER, not the people list: the register is the
## authority on who carries a grudge, and a save written before a content edit
## would otherwise keep an entry nothing ever decays.
static func _decay_grudges(ns, by_id: Dictionary) -> void:
	for pid in ns.person_grudges.keys():
		var decay := CK.GRUDGE_DECAY_MONTHLY
		var person = by_id.get(pid, null)
		if person != null:
			if person.traits.has("pragmatic"):
				decay *= CK.PRAGMATIC_DECAY_FACTOR
			if person.traits.has("stubborn"):
				decay *= CK.STUBBORN_DECAY_FACTOR
		ns.person_grudges[pid] = clampf(
			float(ns.person_grudges[pid]) - decay, 0.0, 1.0
		)


## Loyalty and grudge movement from one month's want read.
##
## THE OWNERSHIP LATCH IS V4.0's FINDING, ONE LEVEL DOWN. Pricing the LEVEL
## outright means a want denied by the world the player INHERITED writes grudge
## every month, and an idle term accumulates betrayals nobody committed. So a
## want denied at the month the watch BEGINS is the world it inherited, and the
## register records that by writing it with the latch FALSE: the latch is
## `latched or served`, seeded from the first read, and it stays false until the
## want has been SERVED at least once under this player's watch. Only then is a
## denial charged, because only then did the player's own government choose the
## condition the person lives under.
##
## AND A STANDING DENIAL IS CHARGED EVERY MONTH IT STANDS, which is the review's
## C2 repair. The first ship pulsed ONLY on the turn -- and measurement on the
## real month tick (three 168-month regimes, tools/characters_probe.gd's terms)
## found a want turns denied one to three times in fourteen years, so a pulse of
## 0.02 against a decay of 0.05 never left zero and no act threshold was
## reachable arithmetic. A want whose object is a STANDING read of the world --
## `meter:` (a level the government holds or does not) and `programme:` (an
## entry on or off this term's register) -- is therefore charged for every month
## it stands denied: a sustained denial nets +GRUDGE_WANT_DENIED -
## GRUDGE_DECAY_MONTHLY and reaches the brief threshold in the tens of months
## the constants' own arithmetic states. A want whose object is a DISCRETE
## HOLDING -- the `office:` family, a slot that points at you or does not --
## is charged ONCE at the turn: a lost portfolio is one event, and billing it
## every month would charge the same decision forty-eight times. The split is
## the object's own nature, not a tuning dial.
##
## The flip memory keeps its own meaning (the last read), because loyalty still
## pulses on the TURN: a want that turns served is one loyalty pulse.
##
## REGISTER KEY GRAMMAR (both keys live in the sixth register, both bool):
##   "<person_id>|<object>"   the last served read -- the flip memory
##   "<person_id>|!<object>"  the latch: served at least once, ever
## The latch is an OR, so it never un-sets, and no third register and no
## SAVE_VERSION move were needed to carry it. `!` is safe as a separator
## because a want object is `family:target` and never carries one.
static func _settle_wants(ns, person, meters: Dictionary, authored_leaders: Dictionary) -> void:
	for want in person.wants:
		var stance := String(want["stance"])
		var object := String(want["object"])
		var served := want_served(ns, person, want, meters, authored_leaders)
		var key: String = String(person.id) + "|" + object
		var prev: bool = ns.person_want_state.get(key, served)
		ns.person_want_state[key] = served
		var latch_key: String = String(person.id) + "|!" + object
		var latched: bool = bool(ns.person_want_state.get(latch_key, served))
		ns.person_want_state[latch_key] = latched or served
		if served and not prev:
			_adjust_loyalty(ns, person.id, CK.LOYALTY_WANT_SERVED)
		elif not served and (latched if _is_standing(object) else prev):
			_adjust_grudge(ns, person, CK.GRUDGE_WANT_DENIED * _denial_factor(person, object))


## A STANDING want's object: a condition the government holds month by month (a
## meter's level, a programme entry's presence on the register). Everything else
## -- the `office:` family -- is a discrete holding, charged once at the turn.
static func _is_standing(object: String) -> bool:
	return object.begins_with("meter:") or object.begins_with("programme:")


## The want-shaped half of a grudge pulse. FERVENT amplifies a METER want's
## denial for the collective kinds, and only there: the meter IS a union
## leader's or an activist's lever (14.4), so being denied at the meter is
## being denied in their own register rather than at one of a politician's
## many objects. A fervent politician gets nothing here, which is the
## distinction the trait's own wording draws.
static func _denial_factor(person, object: String) -> float:
	if person.traits.has("fervent") and object.begins_with("meter:"):
		if CharacterK.KIND_COLLECTIVE.has(String(person.kind)):
			return CK.FERVENT_METER_FACTOR
	return 1.0


## The derived satisfaction read -- NEVER stored. programme reads the live
## register, office reads the slots, meter reads the hand-ins.
##
## want_satisfied is the PUBLIC surface of the private read below -- the
## Programme.this_term() precedent: the People panel consumed a hand-kept
## copy once and the copy diverged inside its own PR (the review's I1, every
## meter want reading "denied" forever while the machine priced it), so the
## panel reads the machine's answer through this one door instead. meters and
## authored_leaders are handed in exactly as tick_month hands them.
static func want_satisfied(ns, person, want: Dictionary, meters: Dictionary, authored_leaders: Dictionary) -> bool:
	return _want_satisfied(ns, person, want, meters, authored_leaders)


## Whether any presidential verb can serve this want -- the gate on a want becoming
## a request (pre-gate B, RECORD 10). A party's leader is made only by a challenge
## (_fire_act), never by the president, own party included: a leadership want drives
## the challenge machine (_challenge_target reads it, and most name ANOTHER party by
## V4.3's design), but it never asks. QA met three people asking the president for
## another party's leadership.
static func servable(want: Dictionary) -> bool:
	return not String(want["object"]).begins_with("office:party_leadership:")


## The stance-aware half: an `oppose` want is served when its object is NOT
## satisfied. V5.2b's request trigger asks it, so the trigger and the
## edge-trigger above cannot read one want two ways.
static func want_served(ns, person, want: Dictionary, meters: Dictionary, authored_leaders: Dictionary) -> bool:
	var satisfied := _want_satisfied(ns, person, want, meters, authored_leaders)
	return satisfied if String(want["stance"]) != "oppose" else not satisfied


static func _want_satisfied(ns, person, want: Dictionary, meters: Dictionary, authored_leaders: Dictionary) -> bool:
	var object := String(want["object"])
	if object.begins_with("programme:"):
		# Satisfied when the sponsored entry is ON THIS TERM's register and
		# alive -- the want's judgement is participation, not conclusion
		# (conclusions pay through the programme's own channel). Both halves
		# are load-bearing: without the term gate a completed entry satisfies
		# for ever, which for an oppose-stance author reads their want denied
		# for ever and bills the standing denial every month to the end of the
		# run -- the priced-forever class the ownership latch exists to refuse.
		# The standard review's 92-scoring find; the gate is the same level
		# comparison Programme.this_term() makes, inlined to keep this file's
		# leaf preloads untouched.
		var entry_id := object.substr("programme:".length())
		return not _programme_entry(ns, entry_id).is_empty()
	if object == "office:premiership":
		return _holds_office(ns, person.id, "premiership")
	if object.begins_with("office:portfolio:"):
		# A portfolio is party-held (cabinet.gd's mechanism); a person's want
		# for one is judged on whether the party they sit in HOLDS it -- the
		# closest satisfaction a party-held slot can give a person, and the
		# demand-a-portfolio feed the landing-site table names. The override
		# register is in hand here, so the authored edge is not needed: a
		# person whose defection moved them reads their new party either way.
		var key := object.substr("office:portfolio:".length())
		var party := _party_of(ns, person)
		return String(ns.cabinet.get(key, "")) == party
	if object.begins_with("office:party_leadership:"):
		var pid := object.substr("office:party_leadership:".length())
		return party_leader(ns, pid, authored_leaders) == person.id
	if object.begins_with("meter:"):
		var meter_key := object.substr("meter:".length())
		var value := float(meters.get(meter_key, 0.0))
		if want.has("below"):
			return value < float(want["below"])
		return value > float(want["above"])
	return false


## The acts. Each gate is a threshold the register already knows; each price
## lands on the machine 14.5's table names; each returns true only when it
## fired. P5's determinism holds by construction -- every read is a level
## comparison, no rand.
static func _fire_act(state, ns, loader, person, act_key: String, meters: Dictionary, acts: Array, authored_leaders: Dictionary) -> bool:
	var grudge := float(ns.person_grudges.get(person.id, 0.0))
	var loyalty := float(ns.person_loyalty.get(person.id, 0.0))
	var standing := float(ns.person_standing.get(person.id, 0.0))

	match act_key:
		"resign":
			# An office-holder whose loyalty has fallen past the floor
			# resigns. The slot clears and the government pays the
			# government-price primitive, the same one a censure costs. ONCE:
			# the person keeps the office only while the state that fired the
			# resignation persists, and after it fires the office is no longer
			# theirs to resign again -- a monthly repeat would be the same
			# scandal re-charged every month (V1.5d's re-fire class).
			var office := _office_held(ns, person.id)
			if office == "" or loyalty > _resign_floor(person):
				return false
			_clear_office(ns, office)
			Government.penalise_blocs(ns, CK.PRICE_RESIGN * _standing_weight(standing))
			_adjust_grudge(ns, person, -CK.GRUDGE_ACT_RELIEF)
			acts.append(_act(state, "resign", person.id, {"office": office}))
			return true

		"defect":
			# A party member with a party and a grudge past the defection
			# threshold walks to the largest party that is not their own. The
			# seat does NOT move -- elections' to write, the whip's to follow.
			var from_party := _party_of(ns, person)
			# ONCE PER REGISTER STATE: a person who has already defected reads
			# their override as their party, and a SECOND walk needs a second
			# grudge earned in the new party -- which the same threshold gate
			# will re-test honestly once the bench authors it. Without this
			# guard the same grudge re-fires the same act every month.
			if ns.person_party_override.has(person.id):
				return false
			if from_party == "" or grudge < CK.GRUDGE_DEFECT_THRESHOLD:
				return false
			var to_party := _largest_other_party(loader, state.player_nation_id, from_party)
			if to_party == "":
				return false
			ns.person_party_override[person.id] = to_party
			# The defection card is campaign-visible; the bloc price is the
			# scandal's, priced through the government primitive.
			Government.penalise_blocs(ns, CK.PRICE_DEFECT * _standing_weight(standing))
			acts.append(_act(state, "defect", person.id, {"from": from_party, "to": to_party}))
			return true

		"challenge":
			# A leadership challenge: standing against the incumbent's, on
			# the register, deterministic. Ambition lowers the threshold; the
			# winner is the higher standing, and a TIE refuses (a tie is no
			# mandate, and resolving it would need the rand the law refuses).
			# ONCE per pair: an override this register already carries means
			# the challenge HAPPENED -- re-firing it would move the party
			# every month (V1.5d's re-fire class again).
			var target_party := _challenge_target(ns, loader, person, authored_leaders)
			if target_party == "":
				return false
			var incumbent := party_leader(ns, target_party, authored_leaders)
			if incumbent == person.id:
				return false
			# A challenge needs GRIEVANCE as well as standing: standing alone
			# is ambition, and month one of a fresh term would otherwise see
			# every ambitious bench figure coup their leader on day one --
			# the already-won/lost defect class, in a person's shape. The
			# grudge is what the player's choices write; the standing is only
			# the muscle that makes the grudge dangerous.
			if grudge < CK.CHALLENGE_GRUDGE_FLOOR:
				return false
			var threshold := CK.CHALLENGE_STANDING_THRESHOLD
			if person.traits.has("ambitious"):
				threshold -= CK.CHALLENGE_AMBITIOUS_DISCOUNT
			if person.traits.has("vain") and _carries_leadership_want(person, target_party):
				threshold -= CK.CHALLENGE_VAIN_DISCOUNT
			if standing < threshold:
				return false
			var incumbent_standing := float(ns.person_standing.get(incumbent, 0.0))
			if standing <= incumbent_standing:
				return false
			ns.party_leader_override[target_party] = person.id
			# The party's own base reads a contest as disorder, whichever way
			# it goes; the challenger's win costs the party, not the player's
			# government, and the price is the primitive's again.
			Government.penalise_blocs(ns, CK.PRICE_CHALLENGE * _standing_weight(standing))
			_adjust_grudge(ns, person, -CK.GRUDGE_ACT_RELIEF)
			acts.append(_act(state, "challenge", person.id, {"party": target_party, "deposed": incumbent}))
			return true

		"brief_against":
			# A networked or grudge-carrying person leaks against the
			# government: bloc_offset, priced through the ONE applier -- the
			# same route a law's price takes, so a second approval writer is
			# never built.
			#
			# THE ONLY NEGATIVE LOYALTY WRITER IN THE PROJECT. A brief is a
			# person spending their relationship with the government, and
			# without this step LOYALTY_RESIGN_FLOOR was unreachable
			# arithmetic -- the review's C2. The cost lands on the BRIEFER,
			# and it is what makes the grudge gate and the loyalty floor two
			# ends of one walk rather than two registers.
			if grudge < CK.GRUDGE_BRIEF_THRESHOLD:
				return false
			var magnitude := CK.PRICE_BRIEF * _standing_weight(standing)
			if person.traits.has("networked"):
				magnitude *= CK.NETWORKED_MAGNITUDE
			# Brief THROUGH the applier, with an effects dict shaped the way
			# the law and the event choice shape theirs -- one channel.
			Legislature.apply_effects(state, ns, {"bloc_offset": _brief_blocs(magnitude)}, loader)
			# GRUDGE_BRIEF_RELIEF, not GRUDGE_ACT_RELIEF: a leak is a VALVE the
			# ladder climbs through, and relieving more than one month's accrual
			# would cap the grudge below the challenge floor for ever (the
			# envelope invariant, stated at the constant).
			_adjust_grudge(ns, person, -CK.GRUDGE_BRIEF_RELIEF)
			_adjust_loyalty(ns, person.id, -CK.LOYALTY_ACT_COST)
			acts.append(_act(state, "brief_against", person.id, {}))
			return true

		_:
			return false
	return false


## The brief's blocs: a leak lands on the blocs whose matter it is. PRICES ARE
## NEGATIVE (character_act_constants' convention 1), so the magnitude is
## copied straight through -- the first ship negated a positive constant here
## and passed a positive constant to penalise_blocs, which ADDED approval for
## an act of betrayal (the review's C1).
static func _brief_blocs(magnitude: float) -> Dictionary:
	var out := {}
	for bloc in CK.BRIEF_BLOCS:
		out[bloc] = magnitude
	return out


## Standing-weighted price multiplier: the act of a person nobody rates costs
## less than the same act by the register's heavyweight.
static func _standing_weight(standing: float) -> float:
	return CK.STANDING_WEIGHT_BASE + standing


## Where this person's resignation floor sits: the band's floor, lowered for a
## LOYAL person -- 14.2's "loyalty floor higher", which was authored into the
## trait table and read by nothing before the review (I3).
static func _resign_floor(person) -> float:
	if person.traits.has("loyal"):
		return CK.LOYALTY_RESIGN_FLOOR - CK.LOYAL_RESIGN_RELIEF
	return CK.LOYALTY_RESIGN_FLOOR


	## Helpers ----------------------------------------------------------------------

## The live programme entry for an id, or {} when it is not alive on this
## term's register. A PURE READ of ns fields -- no Programme preload, because
## a want's satisfaction is a dictionary read the shape of which this file
## already knows. ALIVE means active: a completed entry is a conclusion the
## programme channel already paid, not a standing fact, and a past term's
## entry is not this term's participation.
static func _programme_entry(ns, entry_id: String) -> Dictionary:
	for entry in ns.programme:
		if String(entry.get("entry_id", entry.get("id", ""))) == entry_id:
			if int(entry.get("chosen_term", -1)) != int(ns.terms_served):
				continue
			if String(entry.get("status", "")) == "active":
				return entry
	return {}


## Who holds an office, read off the slots the state owns. The premiership is
## the head of government (ns.pm_person_id); a PORTFOLIO is party-held by the
## mechanism's own law (cabinet.gd assigns ns.cabinet[portfolio] = party_id) --
## there is no person-in-portfolio slot to read or clear, and the resign act
## targets what a PERSON can hold: the premiership and a party leadership.
static func _holds_office(ns, person_id: String, office: String) -> bool:
	if office == "premiership":
		return String(ns.pm_person_id) == person_id
	return false


## The single office a person holds, for the resign act. "" when none -- and
## a portfolio never names one, for the comment above's reason.
static func _office_held(ns, person_id: String) -> String:
	if String(ns.pm_person_id) == person_id:
		return "premiership"
	return ""


## Clear an office slot.
##
## THE REPAIR PATH, STATED HONESTLY (the first ship's comment claimed a monthly
## repair that does not exist). `Government.form()` -- which refills
## `pm_person_id` from the governing party's live leadership -- runs at
## new_game, at a government fall and at an election, and NOT every month. So a
## MID-TERM premiership resignation leaves `pm_person_id` empty until the next
## election or fall: the People panel's executive row reads "—" and
## `_holds_office`/`_office_held` see nobody in the chair. That is recorded as
## OPEN in docs/people-model.md 14.8 rather than papered over -- it is latent
## until the resign gate is reachable in play, and the honest fix (a
## reformation call at the act's landing site, or a leadership-follows rule for
## a vacant premiership) is a design call this block did not take.
static func _clear_office(ns, office: String) -> void:
	if office == "premiership":
		ns.pm_person_id = ""


## The leader of a party: the OVERRIDE the register carries, else the
## AUTHORED edge (party.leader_person_id) the override exists to displace.
## The authored map is built once per tick by the caller -- the leaf law
## keeps party.gd un-preloaded here, and the loader's Party objects are
## walked where the loader is already in hand.
static func party_leader(ns, party_id: String, authored_leaders: Dictionary) -> String:
	if ns.party_leader_override.has(party_id):
		return String(ns.party_leader_override[party_id])
	return String(authored_leaders.get(party_id, ""))


## A person's current party: the override the register carries, else the
## authored edge, else "". No loader argument: the authored edge lives on the
## person (Person.party_id) and the override on the state, so the loader was
## dead weight in this signature -- dropped at the review rather than carried
## for symmetry.
static func _party_of(ns, person) -> String:
	if ns.person_party_override.has(person.id):
		return String(ns.person_party_override[person.id])
	return String(person.party_id)


## The largest party that is not `not_this`, by SEAT SHARE -- the name is the
## contract, and the first ship returned the first entry in file order, which
## is the authored roster's order and not a size. A party list with no
## seat_share at all leaves the best at 0.0 and the first candidate wins,
## which is the same answer as before for a roster that never set one.
static func _largest_other_party(loader, nation_id: String, not_this: String) -> String:
	var best := ""
	var best_share := -1.0
	for party in loader.parties.get(nation_id, []):
		if party.id == not_this:
			continue
		var share := float(party.seat_share)
		if share > best_share:
			best_share = share
			best = String(party.id)
	return best


## The party a challenge targets: the person's own, where they are IN one and
## not already its leader; else the party whose leadership they authored a
## want for.
static func _challenge_target(ns, loader, person, authored_leaders: Dictionary) -> String:
	var own := _party_of(ns, person)
	if own != "" and party_leader(ns, own, authored_leaders) != person.id:
		return own
	for want in person.wants:
		var object := String(want["object"])
		if object.begins_with("office:party_leadership:"):
			var pid := object.substr("office:party_leadership:".length())
			if party_leader(ns, pid, authored_leaders) != person.id:
				return pid
	return ""


## Whether the person authored a want for THIS party's leadership -- the gate
## on the vain trait's challenge discount, and the whole difference between
## `vain` and `ambitious` as levers: ambition is a general drive, vanity is a
## want for a particular chair.
static func _carries_leadership_want(person, party_id: String) -> bool:
	var target := "office:party_leadership:%s" % party_id
	for want in person.wants:
		if String(want["object"]) == target:
			return true
	return false


## Loyalty moves, clamped to the band.
static func _adjust_loyalty(ns, person_id: String, amount: float) -> void:
	ns.person_loyalty[person_id] = clampf(
		float(ns.person_loyalty.get(person_id, 0.0)) + amount,
		CK.LOYALTY_MIN, CK.LOYALTY_MAX
	)


## Grudge moves, clamped to the band, the trait table's INTAKE modifiers
## applied where the person is in hand.
##
## THE GATE IS `amount > 0.0`, AND IT IS THE WHOLE POINT OF THE FIX (review
## I2): both traits scale a grudge TAKEN, not a grudge released, so an act's
## relief (-GRUDGE_ACT_RELIEF) passes through untouched for everyone. The
## first ship read `amount < 0.0` for `loyal`, which halved the RELIEF -- a
## loyal person held their grudge LONGER, the exact inverse of 14.2's table.
static func _adjust_grudge(ns, person, amount: float) -> void:
	var delta := amount
	if amount > 0.0:
		delta *= grudge_intake(person)
	ns.person_grudges[person.id] = clampf(
		float(ns.person_grudges.get(person.id, 0.0)) + delta, 0.0, 1.0
	)


## The trait table's intake factor on a grudge TAKEN: loyal halves it,
## principled doubles it, both multiply. Public since V5.2b, for the request
## card's price; both factors are powers of two, so folding them into one
## product changed no float the old in-line pair wrote.
static func grudge_intake(person) -> float:
	var factor := 1.0
	if person.traits.has("loyal"):
		factor *= CK.LOYAL_GRUDGE_FACTOR
	if person.traits.has("principled"):
		factor *= CK.PRINCIPLED_GRUDGE_FACTOR
	return factor


## V5.2b. The grudge a refusal of `grudge` would write on this person now: the
## trait intake above, and never past GRUDGE_REFUSAL_CEILING -- a refusal brings
## a person to the leak, never past it. The card's price and the price paid read
## this one function. V5.2 b+ R4: `ceiling` is that ceiling unless a door says
## otherwise -- price_removal() below passes the register's own 1.0.
static func refusal_grudge(ns, person, grudge: float, ceiling: float = CK.GRUDGE_REFUSAL_CEILING) -> float:
	if grudge <= 0.0 or not _of_nation(ns, person):
		return 0.0 if grudge > 0.0 else grudge
	var room := maxf(0.0, ceiling - float(ns.person_grudges.get(person.id, 0.0)))
	return minf(grudge * grudge_intake(person), room)


## V5.2b. The price of a refusal -- a declined, delegated or lapsed request, a
## failed lever -- on the two registers people-model 14.1 names, the grudge
## through refusal_grudge() above. The one door for a writer outside this file:
## Audiences and Levers price here, so this file stays the one writer of both
## registers. Returns what was applied, after the clamps, for the card. A foreign
## head (b3: a visitor's request) carries neither register -- loyalty is to this
## nation's leader, and the want ladder acts only for this nation's people -- so a
## refusal of one writes nothing here; its price is the president's rapport.
static func price_refusal(ns, person, grudge: float, loyalty: float, ceiling: float = CK.GRUDGE_REFUSAL_CEILING) -> Dictionary:
	if not _of_nation(ns, person):
		return {"grudge": 0.0, "loyalty": 0.0}
	var grudge_before := float(ns.person_grudges.get(person.id, 0.0))
	var loyalty_before := float(ns.person_loyalty.get(person.id, 0.0))
	ns.person_grudges[person.id] = clampf(grudge_before + refusal_grudge(ns, person, grudge, ceiling), 0.0, 1.0)
	# A door that moves no loyalty (a removal, a lie, a pressure) writes nothing to
	# that register, not even a 0.0 entry for a person who had none (QA on #142).
	if loyalty != 0.0:
		_adjust_loyalty(ns, person.id, loyalty)
	return {
		"grudge": float(ns.person_grudges[person.id]) - grudge_before,
		"loyalty": float(ns.person_loyalty.get(person.id, 0.0)) - loyalty_before,
	}


## V5.2 b+ R4. The removal door: a portfolio taken from the person's party is an
## act against them, not a refusal, so the trait intake and the register's clamp
## apply and the refusal ceiling does not -- a dismissal may carry a leader past
## the leak (src/sim/removal.gd is its caller).
static func price_removal(ns, person, grudge: float) -> Dictionary:
	return price_refusal(ns, person, grudge, 0.0, 1.0)


## The act record the card reads. act is one of CK.ACT_KEYS; person_id names
## the register entry; detail carries what the card needs (the office
## resigned, the party lost or gained, the object briefed against).
##
## year/month are STAMPED from the state at the moment the act fires, so the
## record is self-describing wherever it lands -- the balance probe prints one
## line per act and a card written a month later would otherwise carry the
## month it was printed in. The UI card ignores both fields today; a record
## that cannot say WHEN is a record a later reader has to reconstruct.
static func _act(state, act: String, person_id: String, detail: Dictionary) -> Dictionary:
	return {
		"act": act,
		"person_id": person_id,
		"detail": detail,
		"year": int(state.year),
		"month": int(state.month),
	}


## An authored person of this nation, by the loader's id-prefix rule.
static func _of_nation(ns, person) -> bool:
	return String(person.id).begins_with("%s_" % ns.id)
