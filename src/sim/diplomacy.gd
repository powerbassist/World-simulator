extends RefCounted

## Pair-keyed relations, their monthly drift, and the player's diplomatic
## actions.
##
## The model, and the justification for every constant, is
## docs/diplomacy-model.md. This file is the rules; diplomacy_constants.gd is
## the numbers; src/core/relations.gd is the key.
##
## No rand() anywhere, the same discipline economy.gd, opinion.gd and
## legislature.gd hold to: a relations figure is exactly reproducible from
## state, so the budget projection and a reloaded save agree with a played game.
##
## > [!success] V1.3a's declared stopgap is discharged, and V1.3f closes the loop.
## > This file used to say that an action's own `effects.relations` WAS the entire
## > reaction -- the target did not reason, did not retaliate, and third pairs did
## > not move. V1.3e replaced all of that: execute() now resolves third-party
## > effects, _tick_retaliation() lets a target decide how hard to answer, and a
## > partner can refuse a treaty outright.
## >
## > What was still missing after V1.3e is that all of it was REACTIVE -- the nine
## > answered and never spoke first. _tick_agenda() below is V1.3f, and it is the
## > last piece: a nation choosing a target and a verb with nobody having acted on
## > it. There is no declared stopgap left in this file.

const RK = preload("res://src/core/relations.gd")
const Org = preload("res://src/core/org.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Coercion = preload("res://src/sim/coercion.gd")
const CK = preload("res://src/sim/coercion_constants.gd")

## V1.3e's interest model. Preloaded here rather than in coercion.gd, which is
## what decides where the retaliation DECISION lives: foreign_policy.gd preloads
## trade.gd, trade.gd preloads coercion.gd, so a coercion.gd that reached back for
## the interest model would close a cycle GDScript refuses. _tick_retaliation()
## below already owned the loop, so the decision belongs here and Coercion keeps
## only the terms it builds.
const FP = preload("res://src/sim/foreign_policy.gd")
const Trade = preload("res://src/sim/trade.gd")
const FPK = preload("res://src/sim/foreign_policy_constants.gd")
const Defence = preload("res://src/sim/defence.gd")
const DFK = preload("res://src/sim/defence_constants.gd")


## Reset one nation's own diplomacy state. Runs for all ten, same as
## Legislature.init_nation() -- what is per-nation here is the record of what
## this nation has recently DONE, not the relations themselves, which are
## pair-keyed on GameState.
static func init_nation(ns) -> void:
	ns.diplo_cooldown_months = {}
	ns.last_diplomatic_result = {}
	ns.diplo_months_to_act = 0


## Where a pair's relations settle if nobody acts. Derived from the two inputs
## docs/data-sources.md can actually supply -- org co-membership, which the
## register carries as content since V3.2, and a shared land border, which V1.3a
## adds as a fact rather than a tuning number.
##
## `a` and `b` are loader Nation objects, not NationState: neither input is live
## state and neither ever changes, so re-deriving from static data is correct
## and re-deriving from a played game's state would not be. Symmetric by
## construction -- swapping the arguments cannot change the answer, which is
## what lets src/core/relations.gd's key stay sorted.
static func resting(a, b, co_member_bonus: float) -> float:
	var value := DK.REST_BASE
	# V3.2: the co-membership bonus is content -- the sum over the orgs both
	# nations belong to, computed by the caller through Org.shared_bonus().
	# eu carries 15.0, the value EU_CO_MEMBER_BONUS held.
	value += co_member_bonus
	if a.neighbours.has(b.id):
		value += DK.SHARED_BORDER_BONUS
	return clampf(value, DK.RELATIONS_MIN, DK.RELATIONS_MAX)


## Seed every unordered pair at its resting value. Called once by
## GameState.new_game(), after every nation exists.
static func seed_relations(state, loader) -> void:
	for pair in RK.all_pairs(loader.nations.keys()):
		var a = loader.nations[pair[0]]
		var b = loader.nations[pair[1]]
		state.relations[RK.key(pair[0], pair[1])] = resting(a, b, Org.shared_bonus(state, pair[0], pair[1], "relations_bonus"))


## Stagger the nine across the agenda cycle. Called once by GameState.new_game(),
## next to seed_relations() and for the same reason: it needs every nation to
## exist, which init_nation() cannot promise since it runs per nation.
##
## DETERMINISTIC, from the nation's index in a sorted id list. There is no rand()
## anywhere in src/sim/, and this is the field that would most obviously invite
## one -- but Budget.project() ticks this module sixty times on a copy, so a random
## schedule would make the budget panel's "this is what will happen" disagree with
## what then happens, and a reloaded save disagree with the game that wrote it.
##
## The stagger is the whole reason the counter is per-nation rather than one
## counter on GameState the way the council's is: nine actors sharing one would all
## act in the same month, and src/ui/message_stack.gd holds six cards.
##
## The player's nation is left at 0 and never ticked -- has_budget means a human
## decides here, which is the one place in the project that flag is read the other
## way round.
static func seed_agenda(state) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	var i: int = 0
	for id in ids:
		var ns = state.nations[id]
		if ns.has_budget:
			continue
		# +1 so nobody acts in the very first month of a new game, before the
		# player has read anything: a card in month one is noise from a world that
		# has not started yet.
		ns.diplo_months_to_act = 1 + (i % FPK.AGENDA_INTERVAL_MONTHS)
		i += 1


## The pair's current score. Distinct from Relations.score()'s raw dictionary
## read: this one is what the model and the UI should call, and an absent pair
## is a bug rather than a 0.0 -- 0.0 is the WORST possible relations, so a
## silent default here would read as mutual hatred.
static func score(state, a: String, b: String) -> float:
	var k := RK.key(a, b)
	if not state.relations.has(k):
		push_error("diplomacy: no relations entry for '%s' -- seed_relations() did not run" % k)
		return DK.REST_BASE
	return float(state.relations[k])


## Drift every pair toward its resting value, and count down every nation's
## action cooldowns.
##
## `loader` is required rather than defaulted: the resting value is derived from
## static nation data, and a defaulted argument would let the drift silently
## pull toward REST_BASE for every pair -- erasing the EU and border terms that
## are the entire content of the derivation. The same not-defaulted reasoning
## Legislature.apply() gives for its own loader argument.
static func tick_month(state, loader) -> void:
	# V5.0c: membership cannot change inside this tick, so Org.shared_bonus() is
	# memoised for it (see memo_open()); closed on the way out, the one exit.
	Org.memo_open(state)
	for pair_key in state.relations.keys():
		# Explicitly String()-wrapped: Dictionary.keys() is untyped, and `:=`
		# cannot infer a type through it.
		var ids: PackedStringArray = String(pair_key).split(RK.SEPARATOR)
		if ids.size() != 2:
			continue
		var a = loader.nations.get(ids[0])
		var b = loader.nations.get(ids[1])
		if a == null or b == null:
			continue
		var current := float(state.relations[pair_key])
		var target := resting(a, b, Org.shared_bonus(state, a.id, b.id, "relations_bonus"))
		state.relations[pair_key] = clampf(
			current + (target - current) * DK.DRIFT_RATE,
			DK.RELATIONS_MIN, DK.RELATIONS_MAX
		)

	_tick_retaliation(state)

	# Cooldowns tick for every nation, not just the player's -- V1.3e will have
	# the other nine acting through this same path, and a counter that only
	# counts down for one nation would be a bug that only surfaced then.
	for ns in state.nations.values():
		var expired: Array = []
		for cooldown_key in ns.diplo_cooldown_months:
			var remaining: int = int(ns.diplo_cooldown_months[cooldown_key]) - 1
			if remaining <= 0:
				expired.append(cooldown_key)
			else:
				ns.diplo_cooldown_months[cooldown_key] = remaining
		for cooldown_key in expired:
			ns.diplo_cooldown_months.erase(cooldown_key)

	# LAST, and both halves of that placement are load-bearing.
	#
	# After the retaliations, because an answer is not an initiative: a nation
	# weighing an act should be looking at a world that already contains this
	# month's answers rather than last month's, which is the ordering failure
	# docs/trade-model.md records the trade probe catching in the impulse.
	#
	# After the cooldown countdown, because execute() sets a cooldown and running
	# the agenda first would have this same loop decrement it immediately -- an AI
	# verb locked for eleven months where the player's identical verb is locked for
	# twelve. A silent one-month asymmetry between the player and the nine, in a
	# session whose whole subject is that they use the same verbs.
	_tick_agenda(state, loader)
	Org.memo_close()


## Answer every measure that has been in force long enough and has not yet been
## answered. Runs inside tick_month(), which already runs for all ten nations and
## whose own comment anticipated exactly this.
##
## > [!success] V1.3c's DECLARED STOPGAP, discharged at V1.3e.
## > A measure used to be mirrored back at a fixed RETALIATION_FRACTION whatever
## > the target's position was. The target now decides how hard to answer -- from
## > how much the imposer depends on it (how much the answer would hurt) against
## > how much it depends on the imposer (how much the answer would cost) -- and can
## > decide not to answer at all. RETALIATION_FRACTION survives as the ceiling.
## > See docs/foreign-policy-model.md.
## >
## > Still one step and still never first: escalation past the single exchange and
## > acting on its own initiative are V1.3f's, and the `retaliated` flag that bounds
## > the exchange is unchanged.
##
## Deliberately no rand(): the same discipline the rest of this file holds to, so
## the budget projection -- which ticks Diplomacy since V1.3b -- and a reloaded
## save agree with a played game.
static func _tick_retaliation(state) -> void:
	# Collected before writing, because the loop below adds entries to the very
	# dictionary it iterates. The mirror's own `retaliated: true` would stop the
	# recursion in any case, but mutating a Dictionary mid-iteration is undefined
	# in Godot rather than merely subtle.
	var answers: Array = []
	for directed in state.measures.keys():
		var terms: Dictionary = state.measures[directed]
		if bool(terms.get("retaliated", false)):
			continue
		if Coercion.months_in_force(terms, state.year, state.month) < CK.RETALIATION_DELAY_MONTHS:
			continue
		var parts := RK.directed_parts(String(directed))
		if parts.size() != 2:
			continue
		answers.append({"imposer": parts[0], "target": parts[1], "key": directed, "terms": terms})

	for answer in answers:
		var imposer: String = answer["imposer"]
		var target: String = answer["target"]

		# Flagged whether or not an answer lands, so a measure is considered for
		# retaliation exactly once. Without this a target that already had a
		# measure of its own in place would be re-examined every month forever.
		state.measures[answer["key"]]["retaliated"] = true

		# One measure per directed pair, the same rule agreements have. A nation
		# that has already imposed something on the imposer does not stack a
		# second entry on top; it has answered already, whatever its reason was.
		var back := RK.directed_key(target, imposer)
		if state.measures.has(back):
			continue

		# The decision V1.3c did not make. Read here rather than inside Coercion
		# because the interest model needs the trade weights and coercion.gd
		# cannot reach them without closing a preload cycle -- see the FP const
		# at the top of this file.
		var fraction := FP.retaliation_fraction(
			state, imposer, target, CK.RETALIATION_FRACTION
		)
		var mirror := Coercion.retaliation_terms(
			answer["terms"], fraction, state.year, state.month
		)
		if mirror.is_empty():
			continue
		state.measures[back] = mirror

		# The second hit on a pair that has already paid for the original measure,
		# which is why it is small next to an action's own effects.relations.
		RK.adjust(
			state, imposer, target, CK.RETALIATION_RELATIONS_COST,
			DK.RELATIONS_MIN, DK.RELATIONS_MAX
		)


## Let every nation whose counter has run out choose a target and a verb, and act.
## V1.3f, and the last thing in the V1.3 block that made the nine passive.
##
## Lives here rather than in a module of its own for the reason the retaliation
## decision does: foreign_policy.gd preloads trade.gd which preloads coercion.gd,
## so the interest model can never reach available() or execute(). This loop
## already exists, runs for all ten, and owns the verbs. ForeignPolicy scores what
## it is handed; Diplomacy decides what to hand it and what to do with the answer.
##
## What restrains the nine is entirely inside that score, and the asymmetry is
## declared rather than hidden: every action carries a bloc_offset domestic price
## and for a non-player nation that price is dead state, because Opinion.tick_month()
## is gated on has_budget. The player is checked at home; the nine are checked
## abroad, by what an act costs them in their own trade and what the target would
## answer with. See docs/foreign-policy-model.md.
##
## Sorted at both levels, so which nation acts and which target it picks are
## reproducible rather than dependent on Dictionary ordering -- the same discipline
## third_party_effects() and Relations.all_pairs() already hold.
##
## No rand(), like everything else in this file.
static func _tick_agenda(state, loader) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()

	for actor_id in ids:
		var ns = state.nations[actor_id]

		# The one place in the project this flag is read the other way round:
		# has_budget means a human decides here, so the agenda skips exactly the
		# nation the player is governing.
		if ns.has_budget:
			continue

		ns.diplo_months_to_act -= 1
		if ns.diplo_months_to_act > 0:
			continue

		# Reset WHETHER OR NOT it acts. A nation that declines and retried every
		# month would make AGENDA_ACT_MIN a delay rather than a gate, and the model
		# would lose the ability to say nothing at all -- which is the job
		# RETALIATION_MIN_SEVERITY does for an answer.
		ns.diplo_months_to_act = FPK.AGENDA_INTERVAL_MONTHS

		var choice := _best_act(state, loader, actor_id, ids)
		if choice.is_empty():
			continue

		var result := execute(
			state, loader.diplomatic_actions, choice["action"], actor_id, choice["target_id"]
		)
		if not bool(result.get("applied", false)):
			continue

		# A DISPLAY RECORD, not a grievance ledger. Nothing in src/sim/ reads this
		# back and tests/test_foreign_policy.gd asserts so: the relations number is
		# the memory, which is the property that let V1.3e ship an interest model
		# with no serialised state at all.
		state.foreign_acts.push_front({
			"year": state.year,
			"month": state.month,
			"actor_id": actor_id,
			"target_id": choice["target_id"],
			"action_id": choice["action"].id,
			"action_name": choice["action"].action_name,
			"reason": choice["reason"],
		})
		while state.foreign_acts.size() > FPK.AGENDA_ACTS_KEPT:
			state.foreign_acts.remove_at(state.foreign_acts.size() - 1)


## The best (action, target) `actor_id` could take right now, or {} if nothing
## clears AGENDA_ACT_MIN.
##
## One ForeignPolicy.target_terms() per target rather than per candidate: the pair
## terms cost a trade-weight read each and the verbs do not move them. See that
## function for why the split is not a micro-optimisation.
static func _best_act(state, loader, actor_id: String, ids: Array) -> Dictionary:
	var best_score: float = FPK.AGENDA_ACT_MIN
	var best: Dictionary = {}

	# Once per acting nation, not once per target: the stake vector and the
	# actor's own before-measures weights are invariant across this loop, and
	# rebuilding them per target was ~112 full trade-vector builds per acting
	# nation at the 29-nation roster -- the largest single line in the month
	# tick's measured budget. target_terms() carries the same reasoning.
	var sv: Dictionary = FP.stake_vector(state, actor_id)
	var wbm: Dictionary = Trade.weights_before_measures(state, actor_id)
	var even: float = FP.even_share(state, actor_id)

	for target_id in ids:
		if target_id == actor_id:
			continue

		var offers: Array = available(state, loader.diplomatic_actions, actor_id, target_id)
		if offers.is_empty():
			continue

		var terms := FP.target_terms(state, actor_id, target_id, sv, wbm, even)

		for action in offers:
			# Agreements between an AI and the PLAYER are out of scope, and the
			# reason is that there is nobody to ask. would_accept_agreement() is the
			# COUNTERPARTY's decision -- so an AI proposing to the player would have
			# the interest model answer on the player's behalf, which is the one
			# thing a single-player game must not do with the player's own foreign
			# policy. An offer the player answers needs pending state, an expiry and
			# an accept/refuse surface: a second machine, and the split V1.3e's own
			# machine-count test would have caught. AI-to-AI agreements are unaffected
			# and do run.
			if _is_agreement_verb(action) and state.nations[target_id].has_budget:
				continue

			# V1.3g inherits that exclusion exactly, for the same reason and with the
			# narrower test _is_pact_signing_verb() explains: would_accept_pact() is
			# the COUNTERPARTY's decision, so an AI offering the player an alliance
			# would have the interest model answer on the player's behalf. AI-to-AI
			# pacts are unaffected and do run, and an AI can still abandon a pact with
			# the player -- which is the half the agreement version gets wrong.
			if _is_pact_signing_verb(action) and state.nations[target_id].has_budget:
				continue

			var score_v: float = FP.desire_from(terms, action.effects)
			# Strictly greater, so the sorted iteration order breaks ties and the
			# answer is reproducible.
			if score_v > best_score:
				best_score = score_v
				best = {
					"action": action,
					"target_id": target_id,
					"reason": FP.act_reason(terms, action.effects),
				}
	return best


## Which counterparty said no, and why. One place rather than a ternary at the call
## site, so a sixth channel with a gate of its own has somewhere obvious to go.
static func _refusal_reason_for(
	state, actor_id: String, target_id: String, terms: Dictionary, pact_terms: Dictionary
) -> String:
	if String(pact_terms.get("op", "")) == "sign":
		return FP.pact_refusal_reason(state, actor_id, target_id)
	return refusal_reason(state, actor_id, target_id, terms)


## Whether an action asks a counterparty to SIGN a pact -- read off the op rather
## than off the channel being non-empty, which is where _is_agreement_verb() sits.
##
## The distinction is load-bearing rather than tidy. Only signing needs consent:
## abandoning is unilateral, and deploying happens under a pact already agreed. Read
## as "the channel is non-empty", the _best_act() exclusion below would mean an AI
## can never ABANDON a pact with the player -- a human locked into an alliance the
## other side hates, permanently, with no exit on its own side.
##
## > [!note] An existing consequence this uncovered, recorded rather than fixed here
## > _is_agreement_verb() DOES have the non-empty shape, so `withdraw_from_compact`
## > is skipped whenever the target is the player: an AI can never withdraw from a
## > trade agreement with the player. Out of V1.3g's scope; written down so it is
## > not rediscovered as new.
static func _is_pact_signing_verb(action) -> bool:
	var pact: Dictionary = action.effects.get("pact", {})
	return String(pact.get("op", "")) == "sign"


## Whether an action writes GameState.agreements in either direction. Read off the
## effects rather than off a list of action ids, so a new agreement verb in
## data/diplomatic-actions/ is covered without an edit here -- the data-not-code
## rule docs/engine-decision.md states first.
static func _is_agreement_verb(action) -> bool:
	return not (action.effects.get("agreement", {}) as Dictionary).is_empty()


## The kind of measure `actor` has in force against `target`, or "" for none.
## The register's own read, kept in one place so the three precondition fields
## above cannot drift apart.
static func _measure_kind(state, actor_id: String, target_id: String) -> String:
	var terms = state.measures.get(RK.directed_key(actor_id, target_id))
	if terms == null:
		return ""
	return String(terms.get("kind", ""))


## The cooldown key for one verb pointed at one counterparty. Per pair, not per
## action: condemning Germany is no reason to be unable to condemn Italy.
static func cooldown_key(action_id: String, target_id: String) -> String:
	return action_id + RK.SEPARATOR + target_id


## --- the president's day, V2.4a ----------------------------------------------------
##
## Travel duration and the meeting window. Both live here rather than in
## calendar.gd because they are DIPLOMACY's quantities: travel_days() prices a
## booking the diary is about to make, and met() gates verbs available() already
## filters. The scheduler stays a leaf that knows neither — it stores the number
## an entry arrives carrying and never asks where it came from.

## Days one leg of a journey between two capitals occupies. The distance is
## great-circle off the V2.2 register's own coordinates — nation.capital names the
## city, the nation's regions hold its lon/lat — so there is no second geography
## to author and no way for the diary to disagree with the map about where Rome is.
##
## The rate is rail-and-road pace (see TRAVEL_KM_PER_DAY), because the number's
## job is to make Rome cost more than Brussels, not to model transport. A block
## spans travel out + the meeting + travel back, so a state visit occupies
## 2 * travel_days + 1 days of the diary.
##
## A capital missing from its own nation's cities is a register gap nothing else
## has ever hit (all ten capitals are far above CITY_MIN_POP), so it errors loudly
## and prices the journey at the CEILING — a gap must never make travel free.
static func travel_days(loader, from_id: String, to_id: String) -> int:
	var from_lonlat: Variant = _capital_lonlat(loader, from_id)
	var to_lonlat: Variant = _capital_lonlat(loader, to_id)
	if from_lonlat == null or to_lonlat == null:
		return DK.TRAVEL_DAYS_MAX
	var km := _haversine_km(from_lonlat, to_lonlat)
	var days := int(ceil(km / DK.TRAVEL_KM_PER_DAY))
	return clampi(days, DK.TRAVEL_DAYS_MIN, DK.TRAVEL_DAYS_MAX)


## Whether the two leaders have met within the window — the reader half of
## GameState.met_months, and a LEVEL read: the stamp never ticks down, the window
## closes by arithmetic when the calendar runs past it. Symmetric by construction,
## because whichever of the two made the journey, both were in the room.
static func met(state, a: String, b: String) -> bool:
	var stamp = state.met_months.get(RK.key(a, b))
	if stamp == null:
		return false
	return (state.year * 12 + state.month) - int(stamp) <= DK.MEETING_WINDOW_MONTHS


## A nation's capital as a lon/lat, or null. The register keys cities by region,
## so this scans the nation's own cities for the one named nation.capital — a
## per-nation scan over a handful of regions, called once at booking time.
## Variant rather than Vector2 because null is the not-found answer.
static func _capital_lonlat(loader, nation_id: String) -> Variant:
	var nation = loader.nations.get(nation_id)
	if nation == null:
		push_error("diplomacy: no nation '%s' to read a capital from" % nation_id)
		return null
	var wanted := String(nation.capital)
	for region in loader.regions.get(nation_id, []):
		for city in region.cities:
			if String(city.city_name) == wanted:
				return city.lonlat
	push_error("diplomacy: capital '%s' of %s is not in the city register" % [wanted, nation_id])
	return null


## Great-circle distance in kilometres. Half the haversine, on a mean-earth
## radius; the precision is beside the point when the answer is rounded up to
## whole days against a 280 km rate.
static func _haversine_km(a: Vector2, b: Vector2) -> float:
	const EARTH_RADIUS_KM := 6371.0
	var lon1 := deg_to_rad(a.x)
	var lat1 := deg_to_rad(a.y)
	var lon2 := deg_to_rad(b.x)
	var lat2 := deg_to_rad(b.y)
	var dlat := lat2 - lat1
	var dlon := lon2 - lon1
	var h := sin(dlat * 0.5) * sin(dlat * 0.5) \
		+ cos(lat1) * cos(lat2) * sin(dlon * 0.5) * sin(dlon * 0.5)
	return 2.0 * EARTH_RADIUS_KM * asin(minf(1.0, sqrt(h)))


## Every action in `all_actions` that `actor_id` may currently take against
## `target_id`: preconditions met, and not on cooldown against that target.
## Mirrors Legislature.available().
static func available(state, all_actions: Array, actor_id: String, target_id: String) -> Array:
	var out: Array = []
	if actor_id == target_id:
		return out
	var ns = state.nations.get(actor_id)
	if ns == null:
		return out

	for action in all_actions:
		if action.id == "":
			continue
		if ns.diplo_cooldown_months.has(cooldown_key(action.id, target_id)):
			continue
		if _preconditions_met(state, ns, action, target_id):
			out.append(action)
	return out


static func _preconditions_met(state, ns, action, target_id: String) -> bool:
	for cond in action.preconditions:
		var actual: float = _read_field(state, ns, cond["field"], target_id)
		var value: float = cond["value"]
		var ok: bool
		match cond["op"]:
			"<": ok = actual < value
			"<=": ok = actual <= value
			">": ok = actual > value
			">=": ok = actual >= value
			"==": ok = is_equal_approx(actual, value)
			_: ok = false
		if not ok:
			return false
	return true


## "relations" is the pair score against the action's own target; everything
## else is the acting nation's own state, read exactly as
## Legislature._read_field() reads it. Deliberately two lookups in one function
## rather than two functions: a precondition list mixes both freely, and the
## action content should not have to know which kind a field is.
static func _read_field(state, ns, field: String, target_id: String) -> float:
	match field:
		"relations": return score(state, ns.id, target_id)
		# The second pair-state field, and the one that makes propose and withdraw
		# gate themselves with no trade knowledge in this module at all: an enter
		# verb asks for 0, an exit verb asks for 1.
		"agreement_active": return 1.0 if state.agreements.has(RK.key(ns.id, target_id)) else 0.0
		# The third piece of pair state and the first DIRECTED one: this nation's own
		# measure against this target, not the target's against it. An impose verb
		# asks measure_active for 0; a lift verb asks its OWN kind for 1, because
		# one measure per pair means "something is in force" cannot tell a tariff
		# from an embargo and a single field would let either lift clear either.
		"measure_active": return 1.0 if _measure_kind(state, ns.id, target_id) != "" else 0.0
		"tariff_active": return 1.0 if _measure_kind(state, ns.id, target_id) == "tariff" else 0.0
		"sanction_active": return 1.0 if _measure_kind(state, ns.id, target_id) == "sanction" else 0.0
		# V1.3g's five, over its two registers. FOUR of them are about the pair for
		# the reason the three measure fields above are three: `deployment_active`
		# cannot tell a commitment the player chose from one an alliance imposed, so
		# a single field would let a withdraw verb close an obligation the player is
		# not allowed to close. `pact_count` is the odd one and is not about a pair
		# at all -- it is the agenda's brake, authored in the content as
		# `pact_count < N` rather than enforced by a constant in src/sim/.
		"pact_active": return 1.0 if Defence.pact_active(state, ns.id, target_id) else 0.0
		"pact_count": return float(Defence.pact_count(state, ns.id))
		"deployment_active": return 1.0 if Defence.deployment_kind(state, ns.id, target_id) != "" else 0.0
		"deployment_chosen": return 1.0 if Defence.deployment_kind(state, ns.id, target_id) == DFK.DEPLOYMENT_CHOSEN else 0.0
		"deployment_obliged": return 1.0 if Defence.deployment_kind(state, ns.id, target_id) == DFK.DEPLOYMENT_OBLIGED else 0.0
		# V2.4a's, over the sixth pair register. A pair state like the four above
		# it, read through the same machinery so the treaty files gate themselves
		# with no day knowledge in this module at all: a treaty asks for 1, and
		# the state visit that grants it is a different verb in the same content
		# directory.
		"met_recently": return 1.0 if met(state, ns.id, target_id) else 0.0
		"overall_approval_pct": return ns.overall_approval_pct
		"debt_to_gdp_pct": return ns.debt_to_gdp_pct()
		"unemployment_pct": return ns.unemployment_pct
		"deficit_pct_gdp": return ns.deficit_pct_gdp
		"growth_annual_pct": return ns.growth_annual_pct
		_:
			push_error("diplomacy: unknown precondition field '%s'" % field)
			return 0.0


## The player command: move the pair, pay the domestic price, set the cooldown,
## and record the result for the nation panel to read. Returns the result rather
## than mutating a panel, the same shape Legislature.propose() has.
##
## Refuses rather than half-applies when the action is not currently available:
## a UI that offered a stale button would otherwise produce an effect the
## precondition exists to prevent.
static func execute(state, all_actions: Array, action, actor_id: String, target_id: String) -> Dictionary:
	var ns = state.nations.get(actor_id)
	if ns == null:
		return {"action_id": action.id, "target_id": target_id, "applied": false, "refused": true}

	# The counterparty gate is folded into the same refusal as an unmet
	# precondition, deliberately. A verdict applied AFTER the effects would be a
	# third outcome -- available, executed, partner said no -- and would leave the
	# player +6 relations for a treaty that was refused. As a gate there is no
	# third outcome, no new result field, and no UI branch.
	var terms: Dictionary = action.effects.get("agreement", {})
	var blocked_by_partner: bool = (
		String(terms.get("op", "")) == "enter"
		and not would_accept_agreement(state, actor_id, target_id, terms)
	)

	# V1.3g's gate, on the same refusal and for the same reason. Only "sign" is
	# gated: abandoning is a unilateral act, and so is deploying under a pact the
	# partner has already agreed to.
	var pact_terms: Dictionary = action.effects.get("pact", {})
	if String(pact_terms.get("op", "")) == "sign":
		blocked_by_partner = not FP.would_accept_pact(state, actor_id, target_id)

	if blocked_by_partner or not available(state, all_actions, actor_id, target_id).has(action):
		var refused := {
			"action_id": action.id,
			"target_id": target_id,
			"applied": false,
			"refused": true,
			"refused_by_partner": blocked_by_partner,
			# V1.3b shipped `refused_by_partner` and nothing in src/ui/ ever read
			# it, so a partner declining a treaty was silent to the player. Now
			# there is a reason to show, this carries it.
			"refusal_reason": _refusal_reason_for(state, actor_id, target_id, terms, pact_terms) if blocked_by_partner else "",
			"relations_before": score(state, actor_id, target_id),
			"relations_after": score(state, actor_id, target_id),
		}
		ns.last_diplomatic_result = refused
		return refused

	var before := score(state, actor_id, target_id)
	var delta: float = float(action.effects.get("relations", 0.0))

	# V1.3a's stopgap was that this delta IS the entire reaction and no third pair
	# moves. It is discharged here: every nation with a stake in the target judges
	# the actor for it and warms to the target by the same measure.
	#
	# Computed BEFORE the pair itself moves, and as a whole list before any of it
	# is applied. Both matter: applying one adjustment moves the relations the next
	# stake is scaled by, so a resolved-as-you-go version would give an answer that
	# depended on Dictionary iteration order -- the ordering bug docs/trade-model.md
	# records the trade probe catching in the impulse, which was invisible until
	# something finally perturbed a partner.
	var third_party: Array = FP.third_party_effects(state, actor_id, target_id, delta)

	var after := RK.adjust(
		state, actor_id, target_id, delta, DK.RELATIONS_MIN, DK.RELATIONS_MAX
	)

	for effect in third_party:
		RK.adjust(
			state, String(effect["a"]), String(effect["b"]), float(effect["delta"]),
			DK.RELATIONS_MIN, DK.RELATIONS_MAX
		)

	# Through the same clamped accumulator a law, a censure, a reshuffle and a
	# dissolution already write. No new opinion channel and no new ISSUE_KEYS
	# entry -- that call belongs to V1.3d, and a new issue would reopen the
	# whole BLOC_SALIENCE_BASE measurement. See ROADMAP.md (retired 2026-10-05 -- the tier docs carry the build order now).
	var offsets: Dictionary = action.effects.get("bloc_offset", {})
	for bloc in offsets:
		ns.bloc_offset[bloc] = clampf(
			float(ns.bloc_offset.get(bloc, 0.0)) + float(offsets[bloc]),
			LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX
		)

	# The third effect channel, added at V1.3b. Diplomacy owns this register
	# because it is pair state written by a player command, exactly like relations;
	# src/sim/trade.gd reads it and never writes it, so the two modules talk
	# through GameState and never preload each other.
	var pair_key := RK.key(actor_id, target_id)
	match String(terms.get("op", "")):
		"enter":
			state.agreements[pair_key] = {
				"action_id": action.id,
				"action_name": action.action_name,
				"since_year": state.year,
				"since_month": state.month,
				"weight_multiplier": float(terms.get("weight_multiplier", 1.0)),
				"sector_shift": (terms.get("sector_shift", {}) as Dictionary).duplicate(true),
			}
		"exit":
			state.agreements.erase(pair_key)

	# The fourth effect channel, added at V1.3c, on the DIRECTED key: a measure is
	# one nation's act against another, not a contract both sides read, so
	# FRA>DEU and DEU>FRA are separate entries and a retaliation is simply the
	# second one. See src/core/relations.gd's two key builders.
	var measure: Dictionary = action.effects.get("measure", {})
	var directed := RK.directed_key(actor_id, target_id)
	match String(measure.get("op", "")):
		"impose":
			state.measures[directed] = {
				"action_id": action.id,
				"action_name": action.action_name,
				"kind": measure.get("kind", "tariff"),
				"severity": float(measure.get("severity", 0.0)),
				"since_year": state.year,
				"since_month": state.month,
				"retaliated": false,
			}
			# A measure breaks an agreement on the same pair. This is the
			# agreement expiry docs/trade-model.md booked to V1.3c ("no agreement
			# duration or expiry -- V1.3c owns it, via a sanction breaking one"),
			# discharged in one line rather than by building a duration model.
			# Symmetric key, deliberately: the contract had two sides even though
			# the measure has one, so imposing on a partner ends the treaty for
			# both of you.
			state.agreements.erase(pair_key)
		"lift":
			state.measures.erase(directed)

	# The FIFTH effect channel, added at V1.3g. Diplomacy owns the pact writes for
	# the reason it owns the other two -- they are pair state written by a command --
	# but it does NOT own the deployment register's reconciliation, because an
	# obligation has no commanding verb. Defence.tick_month() does that, and it is
	# the only register in the project written by something that is not answering a
	# command. See docs/defence-model.md §3.
	match String(pact_terms.get("op", "")):
		"sign":
			Defence.sign_pact(state, actor_id, target_id, action)
		"abandon":
			# Closes both directions and both kinds through one rule, which is what
			# requiring a pact for a chosen deployment buys.
			Defence.abandon_pact(state, actor_id, target_id)
		"deploy":
			Defence.open_deployment(
				state, actor_id, target_id, DFK.DEPLOYMENT_CHOSEN, action
			)
		"withdraw":
			Defence.close_deployment(state, actor_id, target_id)

	if action.cooldown_months > 0:
		ns.diplo_cooldown_months[cooldown_key(action.id, target_id)] = action.cooldown_months

	# V2.4a, and it is a stamp rather than an effect: the one pair fact this verb
	# writes that nobody negotiated over. Either direction across the pair opens
	# the window for both, which is why the key is the symmetric one.
	if action.opens_meeting:
		state.met_months[RK.key(actor_id, target_id)] = state.year * 12 + state.month

	var result := {
		"action_id": action.id,
		"action_name": action.action_name,
		"target_id": target_id,
		"applied": true,
		"refused": false,
		"refused_by_partner": false,
		"refusal_reason": "",
		"relations_before": before,
		"relations_after": after,
		# How many other pairs this act moved. The nation panel reads it so an
		# act with consequences beyond its target does not look like one without.
		"third_party_pairs": third_party.size(),
		"bloc_offset": offsets.duplicate(true),
		"agreement_op": terms.get("op", ""),
		"measure_op": measure.get("op", ""),
		"measure_kind": measure.get("kind", ""),
	}
	ns.last_diplomatic_result = result
	return result


## Whether `target_id` would sign the agreement `actor_id` is proposing.
##
## > [!success] V1.3b's DECLARED STOPGAP, discharged at V1.3e.
## > This used to be `score(a, b) >= AGREEMENT_ACCEPT_MIN` and nothing else. The
## > target now weighs how much of its own trade runs through the proposer, how
## > warm the pair is, and -- the part a relations threshold could never reach --
## > what is actually on the table. See docs/foreign-policy-model.md.
##
## Takes `terms` where it took none, which is the signature change carrying the
## whole difference: a verdict that cannot see the deal cannot be a verdict about
## the deal. Every caller already had them to hand.
##
## Still a GATE rather than a post-hoc verdict, unchanged from V1.3b and for the
## reason docs/trade-model.md gives: execute() has two outcomes, and a counterparty
## answer applied after the effects would be a third that left the player +6
## relations for a treaty that was refused.
static func would_accept_agreement(state, actor_id: String, target_id: String, terms: Dictionary) -> bool:
	return FP.would_accept_agreement(state, actor_id, target_id, terms)


## Which of the three terms is why they refused, as a key for the nation panel.
## Meaningless unless would_accept_agreement() returned false.
static func refusal_reason(state, actor_id: String, target_id: String, terms: Dictionary) -> String:
	return FP.refusal_reason(state, actor_id, target_id, terms)
