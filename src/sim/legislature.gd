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
const K = preload("res://src/sim/election_constants.gd")
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
const ReferendumK = preload("res://src/sim/referendum_constants.gd")


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
	ns.last_law_result = {}


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

		# Before the cooldowns, so a referendum that fails this month sets its law's
		# cooldown at full length rather than one month short.
		var verdict := Referendum.resolve_due(ns)
		if not verdict.is_empty():
			_settle_referendum(state, ns, loader, verdict)
		var expired: Array = []
		for law_id in ns.law_cooldown_months:
			var remaining: int = int(ns.law_cooldown_months[law_id]) - 1
			if remaining <= 0:
				expired.append(law_id)
			else:
				ns.law_cooldown_months[law_id] = remaining
		for law_id in expired:
			ns.law_cooldown_months.erase(law_id)


## What the country decided, turned into law or into a cooldown.
##
## referendum.gd hands this back as DATA and this function acts on it -- U6a's
## Calendar.due() one block on, and it is what lets that file preload nothing from
## here. What it costs the government is charged THERE, because the price is the
## referendum's; what happens to the bill is charged HERE, because a law passing is
## this file's job and always has been.
static func _settle_referendum(state, ns, loader, verdict: Dictionary) -> void:
	var law = _law_by_id(loader, String(verdict.get("law_id", "")))
	if law == null:
		return
	if bool(verdict.get("passed", false)):
		apply(state, ns, law, loader)
	elif law.cooldown_months > 0:
		ns.law_cooldown_months[law.id] = law.cooldown_months


static func _law_by_id(loader, law_id: String):
	if loader == null or law_id == "":
		return null
	for law in loader.laws:
		if law.id == law_id:
			return law
	return null


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
		if law.constitutional and not law.systems.has(ns.system_id):
			continue
		if law.changes_system and not ns.permits_system_change:
			continue
		if _already_in_force(ns, law):
			continue
		# One referendum at a time, and while one is in flight nothing else may be
		# put to the country. A second live question is not a bound that needed a
		# constant -- it is what "the country votes on this" means.
		if Referendum.is_pending(ns) and Referendum.pending_law_id(ns) == law.id:
			continue
		if _preconditions_met(ns, law):
			out.append(law)
	return out


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


## Public since V1.8: an event carries the same {field, op, value} triple against the
## same whitelist, so it evaluates them through the same function rather than through a
## copy. The list legislature_constants.gd and read_field() already spell out twice does
## not need a third reader spelling it out a fourth time.
static func preconditions_met(ns, conditions: Array) -> bool:
	for cond in conditions:
		var actual: float = read_field(ns, cond["field"])
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


static func read_field(ns, field: String) -> float:
	match field:
		"debt_to_gdp_pct": return ns.debt_to_gdp_pct()
		"unemployment_pct": return ns.unemployment_pct
		"deficit_pct_gdp": return ns.deficit_pct_gdp
		"overall_approval_pct": return ns.overall_approval_pct
		"growth_annual_pct": return ns.growth_annual_pct
		"terms_served": return float(ns.terms_served)
		"unrest_pct": return ns.unrest_pct
		# V1.5c added the entry above and legislature_constants.PRECONDITION_FIELDS in
		# two separate edits, and the suite caught the gap between them: the whitelist
		# admits a field and this match decides what it means, so THE LIST EXISTS TWICE
		# and a session can add half of it. Not merged here -- src/core/law.gd validates
		# against the constant at LOAD time and this runs per frame, so the constant has
		# to be a plain array -- but recorded, because the next field added will hit it.
		_:
			push_error("legislature: unknown precondition field '%s'" % field)
			return 0.0


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
static func resolve_vote(ns, party_list: Array, law, referendum := false) -> Dictionary:
	var yes_seats := 0
	var no_seats := 0
	var abstain_seats := 0
	var party_votes := {}
	var party_support := {}
	var party_rebels := {}

	for party in party_list:
		var s: float = support(ns, party, law)
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
				passed = float(yes_seats) >= LK.AMENDMENT_RULE_FRACTIONS[ns.amendment_rule] * float(seats_total)
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
## Budget.commit() so the demand impulse, the erosion curve and the opinion
## issue all fire exactly as they would for a player-driven budget change --
## the same mechanism, so double-counting is structurally impossible. Every
## other channel is one clamped accumulator, read by an existing formula.
##
## `loader` is required, not defaulted -- a system transition needs
## loader.political_systems (to re-read lose_condition off the new template)
## and loader.parties (to derive an elected head of state's holder). A
## defaulted param would let a transition silently half-apply, the failure
## mode this project refuses throughout. See docs/transition-model.md.
static func apply(state, ns, law, loader) -> void:
	apply_effects(state, ns, law.effects, loader)

	if law.once:
		ns.passed_law_ids[law.id] = true


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
		Budget.commit(state, pending)

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
	# the same register rather than a repeal verb this project does not have. One
	# clamp, on the accumulated value -- the two channels companies.gd reads it
	# through carry their own.
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

	# A mandatory referendum is not a choice the caller makes -- Art. 195 says there
	# is no seats-only path -- so it is read off the nation rather than off the
	# button. An `optional` route is the caller's; a `mandatory` one is the
	# constitution's, and offering it as an alternative would imply the seats-only
	# path it says does not exist.
	var route: bool = referendum or (law.constitutional and Referendum.is_mandatory(ns))

	var result := resolve_vote(ns, party_list, law, route)
	if result["passed"] and route:
		# The chamber said yes; the country has not been asked yet. Nothing is
		# applied, no `once` flag is set and no cooldown is written -- the law is IN
		# FLIGHT, which is a third outcome this function did not have before.
		Referendum.announce(ns, law.id, law.position)
		result["passed"] = false
		result["referendum_called"] = true
		result["referendum_months"] = ReferendumK.REFERENDUM_DELAY_MONTHS
	elif result["passed"]:
		apply(state, ns, law, loader)
	elif law.cooldown_months > 0:
		ns.law_cooldown_months[law.id] = law.cooldown_months

	# A whip that failed fails more easily next time, whichever way the bill went.
	# Applied here rather than in resolve_vote(), which stays a pure function of
	# state so the forecast can call it as often as it likes.
	Discipline.penalise_rebellions(ns, result["party_rebels"], _by_id(party_list))

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

	apply(state, ns, law, loader)
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
