extends RefCounted

## The live game. Everything that changes as the simulation runs, and nothing
## that does not — static content stays in data/ and is never mutated.
##
## Systems in src/sim/ read and write this. The UI reads it and never writes it;
## player intent comes back as an explicit command (Budget.commit). See
## docs/data-architecture.md and engine-decision.md Rule 2.
##
## Minimal on purpose: S5 adds opinion, S6 adds election state, S9 adds the
## serialisation. Fields are added by the session whose model reads them.

const NationState = preload("res://src/core/nation_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Government = preload("res://src/sim/government.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const Defence = preload("res://src/sim/defence.gd")
const Companies = preload("res://src/sim/companies.gd")
const C = preload("res://src/sim/economy_constants.gd")

## 6 as of V1.2b: political-system fields (system_id, head-of-state,
## lose_condition, term_limit) added to NationState, none of which a version-5
## save carries — a loaded game would read an empty lose_condition and never be
## able to end a run. 7 as of V1.2c: amendment_rule, mutable at runtime (an
## amendment may entrench its own threshold), so a version-6 save's absent
## value would silently read as "" -- no rule ever passes, an amendment law is
## proposable to no one, and the failure is silent rather than loud. 8 as of
## V1.2d: permits_system_change, and system_id/lose_condition/head-of-state
## become mutable at runtime for the first time (a system transition writes
## all of them) -- a version-7 save's absent permits_system_change would
## silently read as false, refusing a transition the nation's own data
## permits. SaveManager rejects an unknown version outright — see
## docs/data-architecture.md. 9 as of V1.3a: `relations` below, plus the
## `bloc_offset` -> `bloc_offset` rename on NationState. Relations earn the
## bump under this comment's own rule and `scenario_id`'s absence of one -- the
## test is not "a new field" but "would a missing field read as something
## wrong?". An absent relations dictionary reads as {}, every pair then resolves
## to 0.0, and 0.0 is the WORST possible relations rather than a neutral
## default: a version-8 save would load as ten nations who all hate each other.
## The rename is the same class of loud-vs-silent failure -- a version-8 save's
## `bloc_offset` key would be dropped on load, quietly discarding every
## accumulated approval offset a played game has earned.
##
## 10 as of V1.3b, and the fields that earn it are NationState.eu_member and
## .neighbours -- NOT `agreements` below, and not the trade baselines either.
## Both of those were candidates and both were checked rather than assumed, in
## tests/test_save_load.gd's _run_trade_roundtrip():
##
##   - An absent `agreements` register reads as {}, which is exactly right for
##     every version-9 save: those games could not sign one. `scenario_id`'s case
##     again, and it would not have earned a bump on its own.
##   - An absent `trade_baseline_by_partner` fails SOFT, not loud: the fallback in
##     Trade.external_impulse() re-bases a missing partner to its current growth,
##     so the channel silently re-zeroes at the moment of loading and an in-flight
##     external shock is erased. Real, and worth saving for, but recoverable.
##   - An absent eu_member/neighbours is the loud one. Every nation loads
##     landlocked and outside the EU, both gravity bonuses vanish from
##     src/sim/trade.gd's weight, and the whole trade model silently collapses
##     back to the GDP-only vector V1.3b replaced. A reloaded game would run a
##     DIFFERENT MODEL from the one that saved it, with nothing anywhere to say
##     so. That is the "would a missing field read as something wrong" test this
##     comment sets, in its strongest form yet.
##   - V1.3c earned no bump and the test said so: an absent `measures` reads as
##     {}, which is CORRECT for every version-10 save because those games could
##     not impose one. `agreements`' case exactly.
##   - V1.3d earns one, and this is the answer tests/test_save_load.gd's
##     still-at-10 assertion was left demanding. Three fields, and the loud one is
##     not the register. An absent `bloc` reads as no council and no rules, which
##     for a bloc whose whole premise is that its rules are always in force is
##     wrong rather than empty. An absent `bloc_base_transfer_pct_gdp` reads as a
##     France that has never paid into a budget it has always paid into, silently
##     moving the deficit every economy constant is measured against. And an
##     absent `start_bloc_burden` reads as 0.0 against a live burden, so a game
##     reloaded while in breach scores the breach as NEW -- the europe issue
##     mis-signed for the rest of the run. All three are eu_member/neighbours'
##     case: a reloaded game would run a different model from the one that saved it.
##   - V1.3e earned none and added no serialised field at all: both interest
##     functions are pure reads over live state, and the two things they write --
##     `relations` and `measures` -- were serialised at V1.3a and V1.3c. That is
##     what "no grievance ledger" buys; the relations number IS the memory.
##   - V1.3f earns one, and exactly ONE of its two additions is why.
##     NationState.diplo_months_to_act absent reads as 0, so every one of the nine
##     acts in the first month after a reload -- a nine-act burst a played game
##     cannot produce, because the staggered counters are the whole mechanism that
##     spreads them. eu_member/neighbours' case again: the reloaded game behaves
##     differently from the one that saved it, with nothing to say so.
##     `foreign_acts` does NOT earn it -- absent it reads as "nothing has happened
##     yet", which is correct, and that is `measures`' case at V1.3c. The test
##     asserts both halves rather than leaving the distinction to this comment.
##   - V1.3g earns one, and again exactly ONE of its three additions is why, but
##     the interesting part is that the third SPLITS. NationState.military_capability
##     absent reads as 0.0 against a France that has spent 2.0 % of GDP on defence
##     since before the game started: the deployment cost divides by it so every
##     commitment jumps to the clamp, and would_accept_pact() reads the whole roster
##     as militarily worthless. eu_member/neighbours' case in its strongest form.
##     `pacts` does NOT earn it -- absent it reads as "nothing signed", correct for
##     every version-12 save because those games could not sign one, which is
##     `measures`' case again. `deployments` earns it on ONE HALF ONLY: an obliged
##     entry is re-derived on the next tick from `pacts` x `measures`, both of which
##     the save carries, and that fails soft for a month the way
##     trade_baseline_by_partner does -- but a CHOSEN one is derivable from nothing,
##     so an absent register silently withdraws the player's own forces and drops
##     their bill with them. The test asserts all four, and the split is the
##     assertion worth having: it PINS the property that obliged deployments are
##     derived, so a later session that makes them stateful turns it red.
##
##   - U6a adds `appointments` and does NOT bump, and the interesting half is what
##     it did not add. An absent diary reads as "nothing booked", correct for every
##     version-13 save because those games could not book -- `measures` at V1.3c,
##     down to being player-created state derivable from nothing. The field that
##     WOULD have earned a bump was a spent-days counter, which reads 0 when absent
##     and hands a player eight days into a month all of them back on reload; the
##     probe cut the currency it counted before any of it was written, so the
##     question never reached this list. And `day` earns nothing because it is not
##     serialised at all: save_manager.gd already carries clock.day at the payload's
##     top level, so the mirror's source round-trips and a copy here would be two
##     records of one fact. tests/test_save_load.gd asserts the version is STILL 13,
##     so a later session raising it has to come and say why -- the shape V1.3c left
##     and V1.3d answered.
##
##   - U6b is that session, and it bumps on a RE-KEY rather than on a new field.
##     `pm_name`, `head_of_state_person_id` and `start_head_of_government_person_id`
##     used to hold NAMES and now hold person ids into data/people/. Nothing was
##     added, so the naive reading is that nothing is at risk -- but the rule is
##     "would a missing field read as something wrong?", and an absent
##     `pm_person_id` reads as a nation with NO head of government, which is a
##     claim about the world rather than a missing label. A version-13 save also
##     carries the old keys, so without the bump every one of the three would load
##     as "" while the save itself looks intact: `military_capability`'s case at
##     V1.3g, and `eu_member`/`neighbours` at V1.3b, in their strongest form yet --
##     the reloaded game would render a government nobody governs.
##
##     What U6b did NOT add is again the interesting half. There is no per-person
##     serialised state at all, because a person is pure content: an id and a name,
##     with every relationship expressed by the reference that owns it. The one
##     field that would have earned this bump on its own -- a stored
##     `ns.cabinet_person` -- was never written, because the probe cut the minister
##     bench that needed it. And `appointments`' `person_id` earns nothing: it is a
##     derived LABEL, so an absent one reads as "not recorded", and the entry's
##     identity is still Calendar.verb_key(), which U6b did not touch.
##   - V1.4a bumps to 15 on ONE field of five, and the four that earn nothing are
##     the interesting half. `NationState.companies` is the bump: absent, every
##     firm reads as share 0.0, so the partition simply is not there — a subsidy
##     the save is still billing the player for through a serialised budget line
##     moves a share that does not exist, and `output_eur_bn()` reports a register
##     of firms that produce nothing. `military_capability` at V1.3g and
##     `eu_member`/`neighbours` at V1.3b: a reloaded game running a DIFFERENT MODEL
##     from the one that saved it.
##
##     The other four fail the rule cleanly. `subsidy_bill_pct_gdp`,
##     `firm_impulse_pct` and `firm_jobs_offset_pct` are all recomputed from
##     `companies` on the first tick after a load and read 0.0 when absent, which
##     is exactly right for a version-14 save because those games could not
##     subsidise anybody — `measures` at V1.3c and `appointments` at U6a, down to
##     the reasoning. `last_company_result` is a UI record with no reader in
##     src/sim/ at all.
##
##     And what V1.4a did NOT put in the register is what keeps the list short: a
##     firm's authored share and headcount are CONTENT, so the baseline every
##     deviation is measured against round-trips through data/companies/ rather
##     than through the save. A saved baseline would be the same fact in two
##     places, and the first version of it to drift would be the one in the save.
const SAVE_VERSION := 15

var save_version: int = SAVE_VERSION
var player_nation_id: String = ""

## Which data/scenarios/*.json start this game was begun under; "" is the
## standard start. Read-only after new_game() -- a scenario is an authored
## STARTING state, applied once, so nothing mutates this and no system reads it
## except the UI, which shows the player which start they are in.
##
## No SAVE_VERSION bump for it: a scenario's effects live in the ordinary
## fields a save already carries, and a version-8 save with no scenario_id
## reads as "" -- which is correct for every save that exists, not silently
## wrong. That is the condition this file's SAVE_VERSION comment gives for a
## bump, and it does not hold here. See docs/scenario-model.md.
var scenario_id: String = ""

## Mirrored from the Clock on each monthly tick, so history entries are stamped.
## The Clock stays authoritative for the date; folding it in here is S9's call.
var year: int = 0
var month: int = 0

## Mirrored from the Clock on each DAILY tick — U6a, the first thing in this
## project to need a resolution finer than a month. Same S9 call as year/month:
## the Clock stays authoritative, this is a copy so src/sim/ can read a date
## without knowing a Clock exists.
##
## NOT serialised, and that is a property rather than an oversight:
## save_manager.gd already writes `clock.day` at the payload's top level and
## restores it, so the mirror's source round-trips and main.gd re-mirrors it on
## the first day tick after a load. A second copy in game_state's own dict would
## be two records of one fact that can disagree — the divergence the symmetric
## pair key exists to make impossible, in a smaller place.
var day: int = 1

var nations := {}  # String id -> NationState

## Pair-keyed diplomatic relations, 0-100, one entry per unordered pair of the
## ten -- 45 in all. The FIRST live state in this project that is neither
## per-nation nor global, which is why it sits here rather than on NationState:
## a relations score belongs to a pair, and mirroring it onto both nations would
## double the write path and reintroduce a divergence the symmetric key makes
## impossible.
##
## Keys are built ONLY by src/core/relations.gd's key(), never by string
## concatenation at a call site. Seeded once by Diplomacy.seed_relations() from
## values derived at load, then owned by Diplomacy.tick_month() and by the
## player's own diplomatic actions. See docs/diplomacy-model.md.
var relations := {}  # sorted pair key, e.g. "DEU|FRA" -> float in [0, 100]

## Trade agreements in force, on the same pair key relations use, at most one per
## pair. The second piece of pair state, added at V1.3b, and it sits beside
## relations for the same reason relations sit here rather than on NationState.
##
## Each entry carries the TERMS, not the id of the action that wrote them:
## {action_id, action_name, since_year, since_month, weight_multiplier,
## sector_shift}. An agreement is a signed contract, and its terms are what was
## agreed at signing rather than what the content file says later -- and storing
## them is what lets src/sim/trade.gd take no loader, which in turn is what keeps
## Economy.tick_month()'s signature unchanged across its twenty-eight call sites.
##
## Written ONLY by Diplomacy.execute(); src/sim/trade.gd reads it and never writes.
## See docs/trade-model.md.
var agreements := {}  # sorted pair key -> Dictionary of agreed terms

## Coercive measures in force -- tariffs and sanctions, V1.3c. The third piece of
## pair state, and the FIRST that is DIRECTED: keyed "FRA>DEU" by
## src/core/relations.gd's directed_key(), never by the sorted key() the other two
## use.
##
## That is the additive escape hatch docs/diplomacy-model.md named in advance: a
## directed layer OVER the symmetric level, with the pair key unchanged and nothing
## already reading `relations` rewritten. It is directed because a measure is not a
## contract -- FRA>DEU and DEU>FRA are two separate acts, and a retaliation is
## precisely the second one. An agreement stays symmetric, where both sides really
## do read the same terms.
##
## Each entry carries the TERMS the way an agreement does, and for the same two
## reasons: a measure is imposed at a moment and its severity is what was imposed,
## and storing the terms is what lets src/sim/coercion.gd take no loader.
## {action_id, action_name, kind, severity, since_year, since_month, retaliated}.
## Severity is the model's only intensity dial -- an authored tariff rate was cut
## at measurement time as the same number written twice.
##
## Written ONLY by Diplomacy (execute() for the player, tick_month() for the
## declared-stopgap retaliation); src/sim/coercion.gd and src/sim/trade.gd read it
## and never write. See docs/coercion-model.md.
var measures := {}  # directed key, e.g. "FRA>DEU" -> Dictionary of measure terms

## The bloc's own live state -- V1.3d, and the FOURTH kind of state in this
## project. Per-nation state is on NationState; relations and agreements are
## symmetric pair state; measures are directed pair state. A bloc rule is none of
## those: it is ONE object binding eight nations at once, and mirroring it onto
## each member would be the divergence the symmetric pair key was chosen to make
## impossible, committed at a wider scale.
##
## {rules: {proposal_id -> terms}, pending: {} or one proposal being voted on,
## last_vote: {} or the last division, next_index: int, months_to_next: int}.
##
## The rules carry the TERMS the council adopted rather than the proposal id
## alone -- the third time this project has made that call, after an agreement's
## terms and a measure's severity, and for the same reason: what binds you is
## what was adopted, not what the content file says later.
##
## `next_index` and `months_to_next` are the whole scheduler. There is no RNG
## anywhere in it, so the council survives a save and a reload with no generator
## state to serialise -- the same property docs/opinion-model.md's polling noise
## gets for free. Written ONLY by src/sim/bloc.gd. See docs/bloc-model.md.
var bloc := {}

## Defensive pacts -- V1.3g, and the fifth register rather than a fifth KIND of
## state. Symmetric pair state on the same key builder relations and agreements
## use, because a mutual defence commitment has one shared value the way a
## relationship and a contract do.
##
## An alliance looks like a SET, and the temptation was to make it one -- a second
## object binding N nations, the shape `bloc` above took. It is not needed: the set
## is a derived read, Defence.allies(), and the genuinely multilateral case already
## exists as the bloc, which already carries `common_defence_floor`. V1.3g is the
## first session since V1.3a to add two registers and no new shape.
##
## {action_id, action_name, since_year, since_month}. Written by
## Diplomacy.execute() through the fifth effect channel, and by nothing else.
var pacts := {}  # symmetric key, e.g. "DEU|FRA" -> Dictionary of pact terms

## Deployments -- V1.3g. DIRECTED pair state on `measures`' separator, because
## France committing forces in support of Germany and the reverse are two acts with
## two bills, exactly as a tariff and its retaliation are.
##
## {kind, since_year, since_month, and action_id/action_name when a verb opened it}.
## `kind` is "chosen" or "obliged", and the difference is not cosmetic: a chosen one
## was a player command and is derivable from nothing, while an obliged one is a
## LEVEL READ over (pacts x measures) that src/sim/defence.gd re-derives every
## month. That is what makes an obligation impossible for the player to close and
## what keeps it bounded -- see docs/defence-model.md §3.
##
## The one register in the project written by a module that is not answering a
## command, because nobody issues an obligation.
var deployments := {}  # directed key, e.g. "FRA>DEU" -> Dictionary of deployment terms

## The president's diary — U6a. The player's own bookings, each a deferred call
## to a command that already exists: {kind, year, month, day, action_id,
## target_id, law_id, portfolio, party_id, person_id, status}. Ids only, never
## object references — which is what makes it serialisable, and is the constraint
## that kept src/sim/calendar.gd from needing to know what a Law or a
## DiplomaticAction is.
##
## Global rather than per-nation, and it stays correct when a second nation
## becomes playable: a diary belongs to whoever is holding the pen, and there is
## exactly one player. Bounded by calendar_constants.MAX_APPOINTMENTS and pruned
## of resolved entries by Calendar.tick_month(), so it is the one register here
## with no accumulator behind it.
##
## Earns NO SAVE_VERSION bump, and the test says so rather than this comment:
## absent, it reads as "nothing booked", which is correct for every version-13
## save because those games could not book one. That is `measures`' case exactly
## — likewise player-created state derivable from nothing, and likewise not a
## bump. This is the WHOLE of what U6a serialises: the one field that would have
## earned a bump was a spent-days counter, and U6a's probe cut the currency it
## counted before any of it was written. See docs/calendar-model.md §2.
var appointments: Array[Dictionary] = []

var history: Array[Dictionary] = []

## What the player's last few commands actually did -- U4. Newest first, each
## {label, year, month, movements}, movements in Trends.movements_between()
## shape. Appended by main.gd's _on_month_elapsed(), the one place a committed
## decision's baseline meets the history entry it is measured against.
var recent_effects: Array[Dictionary] = []

## What the other nine did on their own initiative — V1.3f. Newest first, each
## {year, month, actor_id, target_id, action_id, action_name, reason}, appended by
## src/sim/diplomacy.gd's _tick_agenda() and capped at FOREIGN_ACTS_KEPT.
## recent_effects' shape and bound, for the same reason: a column of cards is a
## window on the recent past, not an archive.
##
## > [!important] A DISPLAY RECORD, and deliberately NOT a grievance ledger.
## > docs/foreign-policy-model.md's central property is that the relations number
## > IS the memory — which is what let V1.3e ship a whole interest model with no
## > serialised field. That survives only if nothing in src/sim/ ever reads this
## > list back: the moment a decision consults it, the model has two memories that
## > can disagree, and the pair score stops being the one place history lives.
## > tests/test_foreign_policy.gd asserts no reader in src/sim/ rather than
## > trusting this comment.
## The cap is foreign_policy_constants.AGENDA_ACTS_KEPT, held by the writer rather
## than here -- the shape main.gd's RECENT_EFFECTS_KEPT already has for
## recent_effects, and the reason src/core/ cannot hold it is that game_state.gd
## preloads diplomacy.gd, so the dependency only runs one way.
var foreign_acts: Array[Dictionary] = []

## Problems found while building the state. Surfaced the same way the loader's
## are — loudly, naming the nation and the field.
var errors: Array[String] = []


## Build live state by copying starting values out of loaded static data.
## `loader` is a DataLoader that has already run load_all() without errors.
##
## `scenario_id` names a data/scenarios/*.json start; "" is the standard start,
## which is what every existing caller wants and so what the default gives. A
## scenario applies to the PLAYER's nation only, once, here -- see
## docs/scenario-model.md.
static func new_game(loader, player_id: String, scenario_id: String = ""):
	var gs = new()
	gs.player_nation_id = player_id
	gs.scenario_id = scenario_id

	var scenario = null
	if scenario_id != "":
		scenario = loader.scenarios.get(scenario_id)
		if scenario == null:
			gs.errors.append("scenario '%s' was not loaded" % scenario_id)
		elif scenario.nation_id != player_id:
			# Refused, not silently ignored: a scenario authored for another
			# nation would otherwise produce a game that says it is running one
			# start and is running a different one.
			gs.errors.append("scenario '%s' is authored for nation '%s', not the player's '%s'" % [scenario_id, scenario.nation_id, player_id])
			scenario = null

	# Before the loop, because a nation's net position is relative to the bloc mean
	# and so needs every member at once -- and it has to be in hand INSIDE
	# _build_nation(), where the starting deficit that opinion measures against is
	# captured. Derived from the loader's static data, so it is a fact about the
	# starting world rather than something that drifts with live GDP.
	var net_positions := Bloc.net_positions(loader)

	var ids: Array = loader.nations.keys()
	ids.sort()
	for id in ids:
		var party_list: Array = loader.parties.get(id, [])
		var company_list: Array = loader.companies.get(id, [])
		var applied = scenario if id == player_id else null
		gs.nations[id] = _build_nation(loader.nations[id], id == player_id, party_list, company_list, loader.eu, loader.political_systems, gs.errors, applied, float(net_positions.get(id, 0.0)))

	if not gs.nations.has(player_id):
		gs.errors.append("player nation '%s' was not loaded" % player_id)
		return gs

	# One baseline per partner rather than one aggregate, so the external impulse
	# is zero at new-game under ANY weighting -- including a weighting the player
	# later changes by improving relations. See
	# NationState.trade_baseline_by_partner for why that property is load-bearing.
	for ns in gs.nations.values():
		for partner_id in gs.nations.keys():
			if partner_id != ns.id:
				ns.trade_baseline_by_partner[partner_id] = gs.nations[partner_id].growth_annual_pct

	# After every nation exists, because a pair needs both halves, and outside
	# _build_nation() because relations are the one piece of starting state that
	# is not a nation's own. Reads the loader's Nation objects (eu_member,
	# neighbours) rather than NationState -- neither input is live state and
	# neither ever changes. See docs/diplomacy-model.md.
	Diplomacy.seed_relations(gs, loader)
	# Next to seed_relations() and for the same reason: it needs every nation to
	# exist, which the per-nation init_nation() cannot promise. V1.3f.
	Diplomacy.seed_agenda(gs)

	# After every nation exists, for the same reason relations are seeded here: the
	# council is not any one nation's property. Nothing is in force at new-game, so
	# every nation's burden is exactly zero and start_bloc_burden is too -- which is
	# what makes the europe issue exactly zero at new-game like every other, with no
	# calibration term.
	Bloc.init_state(gs)

	return gs


## `scenario` is a Scenario for the player's nation, or null for a standard
## start and for every non-player nation. It overrides exactly three things --
## debt, seat composition, starting approval -- each at the one point below
## where that value first enters live state. Everything downstream (discipline,
## the coalition, the cabinet, dissolution) then reads the overridden figures
## and needs no scenario awareness of its own. See docs/scenario-model.md.
static func _build_nation(n, is_player: bool, party_list: Array, company_list: Array, eu, political_systems: Dictionary, errors: Array[String], scenario = null, bloc_net_position_pct_gdp: float = 0.0):
	var ns = NationState.new()
	ns.id = n.id
	ns.has_budget = is_player
	ns.population = float(n.population)

	# Static facts, copied once and never mutated, so the trade weight can read
	# them without a loader. See NationState's own declaration for why that matters.
	ns.eu_member = n.eu_member
	# assign() rather than duplicate(): Nation.neighbours is an Array[String], and
	# duplicate() preserves the element type. NationState's copy is declared plain
	# Array and has to stay one -- test_state_copy.gd walks every field generically
	# and probes an Array by appending a numeric sentinel, which a typed array
	# refuses, and the refusal reads as "not duplicated" rather than as a type error.
	ns.neighbours = []
	ns.neighbours.assign(n.neighbours)

	# Sector shares sum to 1.0 only within the validator's tolerance, so GDP is
	# defined as the sum of sector output rather than the other way round. That
	# invariant then holds exactly, forever, and the economy tick preserves it.
	for key in C.SECTOR_TREND.keys():
		ns.sector_output[key] = n.gdp_eur_bn * float(n.sectors.get(key, 0.0))
	ns.gdp_eur_bn = _sum(ns.sector_output)
	ns.potential_gdp_eur_bn = ns.gdp_eur_bn  # start at a zero output gap

	ns.unemployment_pct = n.unemployment_pct
	ns.start_unemployment_pct = n.unemployment_pct
	ns.structural_unemployment_pct = n.unemployment_pct

	# Before Budget.recompute() below, so the debt service a scenario's debt
	# implies is in the starting deficit that Opinion then measures against --
	# an inherited debt is a permanent drag on the budget, which is the whole
	# point of the axis, rather than a number on a panel.
	var debt_to_gdp_pct: float = n.debt_to_gdp_pct
	if scenario != null and scenario.has_debt_to_gdp_pct:
		debt_to_gdp_pct = scenario.debt_to_gdp_pct
	ns.debt_eur_bn = debt_to_gdp_pct / 100.0 * ns.gdp_eur_bn

	ns.tax_rates_pct = n.tax_rates_pct.duplicate(true)
	ns.start_tax_rates_pct = ns.tax_rates_pct.duplicate(true)
	ns.spending_pct_gdp = n.spending_pct_gdp.duplicate(true)
	ns.start_spending_pct_gdp = ns.spending_pct_gdp.duplicate(true)
	ns.other_spending_pct_gdp = n.other_spending_pct_gdp

	# Calibrate the residual so starting revenue equals the authored real figure.
	var modelled := Budget.modelled_revenue_total(ns.tax_rates_pct, ns.start_tax_rates_pct)
	ns.other_revenue_pct_gdp = n.tax_revenue_pct_gdp - modelled
	if ns.other_revenue_pct_gdp < 0.0:
		errors.append(
			"%s: modelled taxes yield %.1f%% of GDP but the nation only collects %.1f%% — revenue residual would be negative, clamped to 0" %
			[n.id, modelled, n.tax_revenue_pct_gdp]
		)
		ns.other_revenue_pct_gdp = 0.0

	# Before Budget.recompute() below, exactly like the scenario's debt above and
	# for the same reason: a standing contribution the player inherited is a
	# permanent drag on the books, so it belongs INSIDE the starting deficit that
	# opinion then measures every later deficit against. Set after that recompute,
	# it would appear on the first monthly tick and read to the electorate as the
	# player having just started paying it.
	ns.bloc_base_transfer_pct_gdp = bloc_net_position_pct_gdp
	ns.bloc_transfer_pct_gdp = bloc_net_position_pct_gdp

	ns.trend_annual_pct = Economy.trend_pct(ns)
	ns.growth_annual_pct = ns.trend_annual_pct
	# `null` state, said out loud at the one call site where it is provably right
	# rather than defaulted in the signature -- V1.3b's argument against a
	# defaulted loader on project() applies to a defaulted state here too. A
	# new-game nation has no measures against anyone: the register starts empty and
	# a scenario cannot author one, the same way it cannot author an agreement. And
	# `gs` is only half-populated at this point in the loop, so threading it
	# through would hand Trade.weights() a partial roster.
	Budget.recompute(null, ns)

	# Before Opinion, which is the one init that now WRITES bloc_offset --
	# a scenario's authored approval is held at its target through that
	# accumulator, and Legislature.init_nation() zeroes it. Moved ahead of
	# Opinion rather than teaching Legislature to spare one key: it zeroes law
	# state and reads nothing, so it is order-independent against everything
	# here. See docs/scenario-model.md.
	Legislature.init_nation(ns)
	# Order-independent against everything here for the same reason Legislature
	# is: it zeroes this nation's own diplomacy record and reads nothing. The
	# relations themselves are pair state, seeded in new_game() once every
	# nation exists.
	Diplomacy.init_nation(ns)
	# AFTER the spending line is loaded, unlike the two above, because capability is
	# seeded at its equilibrium rather than at zero and the equilibrium IS the
	# defence spending line. Seeding at zero would mean every nation in the roster
	# spends the first decade of every game acquiring an army it already had.
	Defence.init_nation(ns)

	# Every firm at its authored share with no subsidy standing, which is what
	# makes both of V1.4a's channels read exactly 0.0 in the first month and every
	# month after it until a player acts. An empty list is the normal case for the
	# seven nations that are not yet playable.
	Companies.init_nation(ns, company_list)

	# After recompute, so the starting deficit opinion measures against is real.
	Opinion.init_nation(ns, scenario.bloc_approval if scenario != null else {})

	Elections.init_nation(ns, n, party_list, eu, scenario.seat_share if scenario != null else {})
	# Before Government, which reads discipline the moment it computes the first
	# coalition bonus — seeding after formation would score that one government
	# against an empty table.
	Discipline.init_nation(ns, party_list)
	# After Elections, which seeds seats_by_party and incumbent_party_id — the
	# two things a formation search reads.
	Government.init_nation(ns, n, party_list)

	# The template is a constraint the loader already enforced against this
	# nation's own flat fields (data_loader.gd's _validate_political_system) --
	# lose_condition is the one field only the template carries, so it is read
	# here rather than copied from Nation like formation_method/censure_rule
	# above. See docs/political-systems.md.
	var system = political_systems.get(n.system_id)
	ns.lose_condition = system.lose_condition if system != null else ""
	# After Government, which forms the starting coalition Cabinet.seat() reads.
	# Called here rather than from inside government.gd -- Cabinet depends on
	# Government, so the reverse would be a preload() cycle. See
	# docs/cabinet-model.md.
	Cabinet.init_nation(ns)
	Cabinet.seat(ns, party_list)
	Dissolution.init_nation(ns, n)

	return ns


static func _sum(d: Dictionary) -> float:
	var total := 0.0
	for v in d.values():
		total += float(v)
	return total


func player():
	return nations.get(player_nation_id)


## Deep copy for the budget projection: the same simulation, run forward on a
## throwaway. History is deliberately not copied — a projection has no past.
func duplicate_state():
	var gs = new()
	gs.save_version = save_version
	gs.player_nation_id = player_nation_id
	gs.scenario_id = scenario_id
	gs.year = year
	gs.month = month
	gs.relations = relations.duplicate(true)
	gs.agreements = agreements.duplicate(true)
	# Copied for the same reason agreements are: Budget.project() runs the real
	# model forward on this copy, and a projection that dropped the measures in
	# force would report a tariff's revenue as never having existed.
	gs.measures = measures.duplicate(true)
	# Copied for the same reason measures are, and one step further: Budget.project()
	# now ticks Bloc, so a projection that dropped the council would report the
	# penalties a defied rule is charging as never having existed -- and the budget
	# panel is the one surface that promises "this is what will happen".
	gs.bloc = bloc.duplicate(true)
	# duplicate(true) rather than assignment, and for a sharper reason than the
	# three above: Defence.tick_month() WRITES `deployments` on this copy when it
	# reconciles obligations, so a shared reference would let a budget-panel repaint
	# mutate the live register -- silently, sixty times per refresh.
	gs.pacts = pacts.duplicate(true)
	gs.deployments = deployments.duplicate(true)
	# Nothing in Budget.project()'s pipeline ticks Calendar today, so this copy
	# buys nothing yet -- and it is taken anyway for the reason the two lines
	# above spell out: a shared reference is one added tick away from a budget
	# panel repaint mutating the player's live diary, sixty times a second.
	gs.appointments = appointments.duplicate(true)
	for id in nations.keys():
		gs.nations[id] = nations[id].duplicate_state()
	return gs


## Stamp a simulation snapshot with the current date and record it.
func append_history(snapshot: Dictionary) -> void:
	var entry := snapshot.duplicate(true)
	entry["year"] = year
	entry["month"] = month
	history.append(entry)


## Serialise the whole live state to a plain, JSON-safe Dictionary. Same field
## set as duplicate_state(), walked the same way, plus history — a save is not
## a projection, so unlike duplicate_state() the chart data comes along. errors
## does not: it is new-game diagnostics, meaningless once a game has been
## played and saved. See docs/data-architecture.md Persistence.
func to_dict() -> Dictionary:
	var nations_dict := {}
	for id in nations.keys():
		nations_dict[id] = nations[id].to_dict()

	return {
		"save_version": save_version,
		"player_nation_id": player_nation_id,
		"scenario_id": scenario_id,
		"year": year,
		"month": month,
		"nations": nations_dict,
		"relations": relations,
		"agreements": agreements,
		"measures": measures,
		"bloc": bloc,
		"pacts": pacts,
		"deployments": deployments,
		"appointments": appointments,
		"history": history,
		"recent_effects": recent_effects,
		"foreign_acts": foreign_acts,
	}


## Inverse of to_dict(). Does not check save_version — the caller (SaveManager)
## checks it before this is ever called, since a mismatch must fail loudly
## rather than build a half-understood state.
static func from_dict(d: Dictionary):
	var gs = new()
	gs.save_version = int(d.get("save_version", SAVE_VERSION))
	gs.player_nation_id = d.get("player_nation_id", "")
	# Absent in a version-8 save, and "" is exactly right for one: those games
	# were all standard starts. See the field's own declaration for why this is
	# the one runtime-readable addition that does not earn a version bump.
	gs.scenario_id = d.get("scenario_id", "")
	gs.year = int(d.get("year", 0))
	gs.month = int(d.get("month", 0))

	var nations_dict: Dictionary = d.get("nations", {})
	for id in nations_dict.keys():
		gs.nations[id] = NationState.from_dict(nations_dict[id])

	# Re-floated key by key rather than taken wholesale: JSON round-trips a
	# whole-number score as an int, and a relations dictionary holding a mix of
	# ints and floats would make the drift arithmetic depend on how a value
	# happened to be saved.
	var rel: Dictionary = d.get("relations", {})
	for pair_key in rel.keys():
		gs.relations[pair_key] = float(rel[pair_key])

	# Re-floated the same way and for the same reason, one level deeper: the
	# multiplier and the three sector shifts are all read as floats by the trade
	# model, and JSON round-trips a whole-number multiplier as an int.
	var agr: Dictionary = d.get("agreements", {})
	for pair_key in agr.keys():
		var entry: Dictionary = agr[pair_key]
		var shifts := {}
		var raw_shifts: Dictionary = entry.get("sector_shift", {})
		for sector in raw_shifts.keys():
			shifts[sector] = float(raw_shifts[sector])
		gs.agreements[pair_key] = {
			"action_id": entry.get("action_id", ""),
			"action_name": entry.get("action_name", ""),
			"since_year": int(entry.get("since_year", 0)),
			"since_month": int(entry.get("since_month", 0)),
			"weight_multiplier": float(entry.get("weight_multiplier", 1.0)),
			"sector_shift": shifts,
		}

	# Re-floated the same way again. An absent `measures` reads as {} and that is
	# CORRECT rather than silently wrong for every version-10 save -- those games
	# could not impose a measure -- which is why V1.3c earns no SAVE_VERSION bump.
	# The same test scenario_id passed and eu_member/neighbours failed. See the
	# SAVE_VERSION comment at the top of this file and docs/coercion-model.md.
	var meas: Dictionary = d.get("measures", {})
	for directed_key in meas.keys():
		var entry: Dictionary = meas[directed_key]
		gs.measures[directed_key] = {
			"action_id": entry.get("action_id", ""),
			"action_name": entry.get("action_name", ""),
			"kind": entry.get("kind", ""),
			"severity": float(entry.get("severity", 0.0)),
			"since_year": int(entry.get("since_year", 0)),
			"since_month": int(entry.get("since_month", 0)),
			"retaliated": bool(entry.get("retaliated", false)),
		}

	# V1.3g's two registers, re-inted field by field the same way. `pacts` absent
	# reads as {} and that is CORRECT for every version-12 save -- those games could
	# not sign one -- which is `measures`' case exactly and why it does not earn the
	# bump on its own. `deployments` absent is correct for the OBLIGED half only,
	# which Defence.tick_month() re-derives from the two registers above; the chosen
	# half is derivable from nothing and is half of what SAVE_VERSION 13 is for.
	var pact_reg: Dictionary = d.get("pacts", {})
	for pair_key in pact_reg.keys():
		var entry: Dictionary = pact_reg[pair_key]
		gs.pacts[pair_key] = {
			"action_id": entry.get("action_id", ""),
			"action_name": entry.get("action_name", ""),
			"since_year": int(entry.get("since_year", 0)),
			"since_month": int(entry.get("since_month", 0)),
		}

	var deploy_reg: Dictionary = d.get("deployments", {})
	for directed_key in deploy_reg.keys():
		var entry: Dictionary = deploy_reg[directed_key]
		var rebuilt := {
			"kind": entry.get("kind", ""),
			"since_year": int(entry.get("since_year", 0)),
			"since_month": int(entry.get("since_month", 0)),
		}
		# Only a deployment a VERB opened carries these. An obliged one has no
		# action behind it, which is the whole point of it, and writing empty
		# strings in would make the panel unable to tell the two apart.
		if entry.has("action_id"):
			rebuilt["action_id"] = entry.get("action_id", "")
			rebuilt["action_name"] = entry.get("action_name", "")
		gs.deployments[directed_key] = rebuilt

	# Re-floated and re-inted field by field, the same way agreements and measures
	# are and for the same reason: JSON round-trips a whole-number severity as an
	# int, and the burden arithmetic would otherwise depend on how a value happened
	# to be saved. The scheduler's two counters are ints and must come back as ints,
	# or the countdown compares a float against an int forever.
	var raw_bloc: Dictionary = d.get("bloc", {})
	if not raw_bloc.is_empty():
		var rules := {}
		for proposal_id in (raw_bloc.get("rules", {}) as Dictionary).keys():
			var rule: Dictionary = raw_bloc["rules"][proposal_id]
			rules[proposal_id] = {
				"name": rule.get("name", ""),
				"field": rule.get("field", ""),
				"op": rule.get("op", ""),
				"value": float(rule.get("value", 0.0)),
				"tolerance": float(rule.get("tolerance", 1.0)),
				"severity": float(rule.get("severity", 0.0)),
				"transfer_pct_gdp": float(rule.get("transfer_pct_gdp", 0.0)),
				"since_year": int(rule.get("since_year", 0)),
				"since_month": int(rule.get("since_month", 0)),
			}
		gs.bloc = {
			"rules": rules,
			"pending": raw_bloc.get("pending", {}),
			"last_vote": raw_bloc.get("last_vote", {}),
			"next_index": int(raw_bloc.get("next_index", 0)),
			"months_to_next": int(raw_bloc.get("months_to_next", 0)),
		}
		var pend: Dictionary = gs.bloc["pending"]
		if not pend.is_empty():
			pend["months_left"] = int(pend.get("months_left", 1))

	var hist: Array = d.get("history", [])
	var typed_hist: Array[Dictionary] = []
	for entry in hist:
		typed_hist.append(entry as Dictionary)
	gs.history = typed_hist

	var effects: Array = d.get("recent_effects", [])
	var typed_effects: Array[Dictionary] = []
	for entry in effects:
		typed_effects.append(entry as Dictionary)
	gs.recent_effects = typed_effects

	# Absent, this reads as an empty list, which is CORRECT rather than silently
	# wrong -- a version-11 save's nine could not act. It is `measures`' case at
	# V1.3c, and it is not what earned SAVE_VERSION 12; diplo_months_to_act is.
	var acts: Array = d.get("foreign_acts", [])
	var typed_acts: Array[Dictionary] = []
	for entry in acts:
		typed_acts.append(entry as Dictionary)
	gs.foreign_acts = typed_acts

	# Absent, this reads as "nothing booked" -- correct for every version-13 save,
	# because those games had no diary to book into. `measures`' case at V1.3c,
	# and like `measures` it earns no bump. `day` is deliberately NOT read back
	# here: save_manager.gd carries clock.day at the payload's top level and
	# main.gd re-mirrors it, so a second copy in this dict would be two records of
	# one fact. tests/test_save_load.gd asserts both halves.
	var appts: Array = d.get("appointments", [])
	var typed_appts: Array[Dictionary] = []
	for entry in appts:
		typed_appts.append(entry as Dictionary)
	gs.appointments = typed_appts

	return gs
