extends RefCounted

## V4.3, People who want things: the wants -> acts machine. A LEAF, and the
## tier's own list of what it may touch: character_constants (the schema),
## legislature.gd (the ONE applier, for a brief's bloc_offset price) and
## government.gd (penalise_blocs, the government-price primitive). It never
## preloads cabinet, elections, unrest, media or judiciary -- the METER
## VALUES arrive as arguments the caller hands in, the calendar.gd leaf
## discipline, and what it reads of the world it reads off NationState.
##
## WHAT IT OWNS: the five person-state registers' values. Standing seeds from
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

const CharacterK = preload("res://src/sim/character_constants.gd")
const Government = preload("res://src/sim/government.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const CK = preload("res://src/sim/character_act_constants.gd")


## One act, as the record and the UI card read it. act is one of
## CK.ACT_KEYS; person_id names the register entry; detail carries what the
## card needs (the office resigned, the party lost or gained, the object
## briefed against). The record is content for the message stack, not state
## nothing recomputes -- so it is RETURNED by tick_month and never stored on
## NationState, the summits' ephemerality discipline.
##
## A grudge or loyalty that an act settles is the STATE; the act itself is
## the story the state tells this month, and re-deriving a story from its
## consequences is what the diary refuses everywhere else in this project.


## Seed standing for the people of ONE nation (new_game calls it for the
## player's, the only nation whose registers anything reads) off authored
## ambition, the only value the register holds before anything happens. The
## seed is ambition plus the trait's floor (the scalar is the dial, the trait
## is the floor -- 14.2's own distinction), so an ambitious person starts
## with weight to use and a contented one starts anonymous.
static func init_nation(ns, people_list: Array) -> void:
	ns.person_loyalty.clear()
	ns.person_standing.clear()
	ns.person_grudges.clear()
	ns.party_leader_override.clear()
	ns.person_party_override.clear()
	for person in people_list:
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

	# Decay first, so a settled grudge halves before this month's want settles
	# -- the same sub-ordering opinion.gd uses for the honeymoon, where
	# decaying the old stock before the new pulse lands is what makes the
	# half-life mean the same thing in every month of a term.
	_decay_grudges(ns)

	# The authored leadership edges, walked once: the leaf law keeps party.gd
	# out of this file, so the loader's own parties array supplies the edges
	# every leader read below needs.
	var authored_leaders := {}
	for party in loader.parties.get(state.player_nation_id, []):
		authored_leaders[party.id] = party.leader_person_id
	# Wants settle, priced on satisfaction the DERIVED reads give. Only an
	# UNSATISFIED want moves a person, and only by the amount the band allows.
	var people: Array = loader.people.get(state.player_nation_id, [])
	for person in people:
		_settle_wants(ns, person, meters, authored_leaders)

	# The acts, in CK.ACT_KEYS order for determinism, each gated on its own
	# threshold read. One act per person per month -- a person mid-defection
	# does not also brief against the government in the same month, which is
	# as much a legibility rule as a balance one.
	var acted: Dictionary = {}
	for act_key in CK.ACT_KEYS:
		for person in people:
			if acted.has(person.id):
				continue
			if _fire_act(state, ns, loader, person, act_key, meters, acts, authored_leaders):
				acted[person.id] = true
	return acts


## The grudge half-life. PRINCIPLED doubles nothing here -- their own acts
## cost THEM standing, not their grudge decay -- and pragmatic/ stubborn
## scale it, per 14.2's table.
static func _decay_grudges(ns) -> void:
	for pid in ns.person_grudges.keys():
		var decay := CK.GRUDGE_DECAY_MONTHLY
		ns.person_grudges[pid] = clampf(
			float(ns.person_grudges[pid]) - decay, 0.0, 1.0
		)


## Loyalty and grudge movement from one month's want read. A want served pays
## loyalty; a want denied pays grudge; a meter want reads the CURRENT value
## against its authored threshold, and an office want reads the slots.
static func _settle_wants(ns, person, meters: Dictionary, authored_leaders: Dictionary) -> void:
	for want in person.wants:
		var stance := String(want["stance"])
		var satisfied := _want_satisfied(ns, person, want, meters, authored_leaders)
		var served: bool = satisfied if stance != "oppose" else not satisfied
		if served:
			_adjust_loyalty(ns, person.id, CK.LOYALTY_WANT_SERVED)
		else:
			_adjust_grudge(ns, person, CK.GRUDGE_WANT_DENIED)


## The derived satisfaction read -- NEVER stored. programme reads the live
## register, office reads the slots, meter reads the hand-ins.
static func _want_satisfied(ns, person, want: Dictionary, meters: Dictionary, authored_leaders: Dictionary) -> bool:
	var object := String(want["object"])
	if object.begins_with("programme:"):
		# Satisfied when the sponsored entry is ON the term's register and
		# alive -- the want's judgement is participation, not conclusion
		# (conclusions pay through the programme's own channel).
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
		var party := String(person.party_id)
		if ns.person_party_override.has(person.id):
			party = String(ns.person_party_override[person.id])
		return String(ns.cabinet.get(key, "")) == party
	if object.begins_with("office:party_leadership:"):
		var pid := object.substr("office:party_leadership:".length())
		return _party_leader(ns, pid, authored_leaders) == person.id
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
			if office == "" or loyalty > CK.LOYALTY_RESIGN_FLOOR:
				return false
			_clear_office(ns, office)
			Government.penalise_blocs(ns, CK.PRICE_RESIGN * _standing_weight(standing))
			_adjust_grudge(ns, person, -CK.GRUDGE_ACT_RELIEF)
			acts.append(_act("resign", person.id, {"office": office}))
			return true

		"defect":
			# A party member with a party and a grudge past the defection
			# threshold walks to the largest party that is not their own. The
			# seat does NOT move -- elections' to write, the whip's to follow.
			var from_party := _party_of(ns, loader, person)
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
			acts.append(_act("defect", person.id, {"from": from_party, "to": to_party}))
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
			var incumbent := _party_leader(ns, target_party, authored_leaders)
			if incumbent == person.id:
				return false
			var threshold := CK.CHALLENGE_STANDING_THRESHOLD
			if person.traits.has("ambitious"):
				threshold -= CK.CHALLENGE_AMBITIOUS_DISCOUNT
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
			acts.append(_act("challenge", person.id, {"party": target_party, "deposed": incumbent}))
			return true

		"brief_against":
			# A networked or grudge-carrying person leaks against the
			# government: bloc_offset, priced through the ONE applier -- the
			# same route a law's price takes, so a second approval writer is
			# never built.
			if grudge < CK.GRUDGE_BRIEF_THRESHOLD:
				return false
			var magnitude := CK.PRICE_BRIEF * _standing_weight(standing)
			if person.traits.has("networked"):
				magnitude *= CK.NETWORKED_MAGNITUDE
			# Brief THROUGH the applier, with an effects dict shaped the way
			# the law and the event choice shape theirs -- one channel.
			Legislature.apply_effects(state, ns, {"bloc_offset": _brief_blocs(magnitude)}, loader)
			_adjust_grudge(ns, person, -CK.GRUDGE_ACT_RELIEF)
			acts.append(_act("brief_against", person.id, {}))
			return true

		_:
			return false
	return false


## The brief's blocs: a leak lands on the blocs whose matter it is -- workers
## and students carry grievance reads, the middle blocs carry competence
## reads, so a leak about ANY government failure travels the same two
## channels the unrest opinion load already travels.
static func _brief_blocs(magnitude: float) -> Dictionary:
	var out := {}
	for bloc in ["workers", "students"]:
		out[bloc] = -magnitude
	return out


## Standing-weighted price multiplier: the act of a person nobody rates costs
## less than the same act by the register's heavyweight.
static func _standing_weight(standing: float) -> float:
	return 0.5 + standing


## Helpers ----------------------------------------------------------------------

## The live programme entry for an id, or {} when it is not on this term's
## register. A PURE READ of ns.programme -- no Programme preload, because a
## want's satisfaction is a dictionary read the shape of which this file
## already knows.
static func _programme_entry(ns, entry_id: String) -> Dictionary:
	for entry in ns.programme:
		if String(entry.get("entry_id", entry.get("id", ""))) == entry_id:
			var status := String(entry.get("status", ""))
			if status == "complete" or status == "active":
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


## Clear an office slot: the premiership clears pm_person_id, and the repair
## rule (government.gd's own formation path) refills it on the next
## formation pass from the governing party's live leadership.
static func _clear_office(ns, office: String) -> void:
	if office == "premiership":
		ns.pm_person_id = ""


## The leader of a party: the OVERRIDE the register carries, else the
## AUTHORED edge (party.leader_person_id) the override exists to displace.
## The authored map is built once per tick by the caller -- the leaf law
## keeps party.gd un-preloaded here, and the loader's Party objects are
## walked where the loader is already in hand.
static func _party_leader(ns, party_id: String, authored_leaders: Dictionary) -> String:
	if ns.party_leader_override.has(party_id):
		return String(ns.party_leader_override[party_id])
	return String(authored_leaders.get(party_id, ""))


## A person's current party: the override the register carries, else the
## authored edge, else "".
static func _party_of(ns, loader, person) -> String:
	if ns.person_party_override.has(person.id):
		return String(ns.person_party_override[person.id])
	return String(person.party_id)


## The largest party that is not `not_this`, by the loader's own ordering.
static func _largest_other_party(loader, nation_id: String, not_this: String) -> String:
	var parties: Array = loader.parties.get(nation_id, [])
	for party in parties:
		if party.id != not_this:
			return party.id
	return ""


## The party a challenge targets: the person's own, where they are IN one and
## not already its leader; else the party whose leadership they authored a
## want for.
static func _challenge_target(ns, loader, person, authored_leaders: Dictionary) -> String:
	var own := _party_of(ns, loader, person)
	if own != "" and _party_leader(ns, own, authored_leaders) != person.id:
		return own
	for want in person.wants:
		var object := String(want["object"])
		if object.begins_with("office:party_leadership:"):
			var pid := object.substr("office:party_leadership:".length())
			if _party_leader(ns, pid, authored_leaders) != person.id:
				return pid
	return ""


## Loyalty moves, clamped to the band.
static func _adjust_loyalty(ns, person_id: String, amount: float) -> void:
	ns.person_loyalty[person_id] = clampf(
		float(ns.person_loyalty.get(person_id, 0.0)) + amount,
		CK.LOYALTY_MIN, CK.LOYALTY_MAX
	)


## Grudge moves, clamped to the band, the trait table's modifiers applied
## where the person is in hand.
static func _adjust_grudge(ns, person, amount: float) -> void:
	var delta := amount
	if person.traits.has("loyal") and amount < 0.0:
		delta *= CK.LOYAL_GRUDGE_RELIEF
	ns.person_grudges[person.id] = clampf(
		float(ns.person_grudges.get(person.id, 0.0)) + delta, 0.0, 1.0
	)


## The act record the card reads.
static func _act(act: String, person_id: String, detail: Dictionary) -> Dictionary:
	return {
		"act": act,
		"person_id": person_id,
		"detail": detail,
		"year": 0,
		"month": 0,
	}
