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
const Regions = preload("res://src/sim/regions.gd")
const Migration = preload("res://src/sim/migration.gd")
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
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const Referendum = preload("res://src/sim/referendum.gd")
const Chambers = preload("res://src/sim/chambers.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const Events = preload("res://src/sim/events.gd")
const Society = preload("res://src/sim/society.gd")
const Demography = preload("res://src/sim/demography.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Media = preload("res://src/sim/media.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const C = preload("res://src/sim/economy_constants.gd")
const TaxK = preload("res://src/sim/tax_constants.gd")

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
##     V1.5a bumps to 16, on ONE field of three, and the split is again the
##     assertion worth having. `service_quality` earns it: absent it reads 0.0
##     against a France that has spent 11.0 % of GDP on health for decades, so every
##     reader sees a country whose hospitals have ceased to exist and the
##     satisfaction term reads a collapse the player did not cause —
##     `military_capability`'s case at V1.3g, in its strongest form yet, because
##     equilibrium-init does NOT rescue it: re-deriving on load would erase an
##     accumulated decline the player spent a term earning. `corruption` earns
##     nothing (absent it reads 0.0, and a version-15 save is a game that had no
##     `society` law to pass — `regulation_burden`'s case at V1.4b), and
##     `start_service_quality` earns nothing either, being recomputed at init from
##     the `spending_pct_gdp` every nation file already authors. Both are serialised
##     regardless, and for two different reasons the test states separately.
##
##   V1.5b bumps to 17, and it is earned TWICE over — by a new field and, for the
##     first time on this list, by a KEY ADDED TO A DICTIONARY THAT WAS ALREADY
##     SERIALISED. `young_share`/`old_share` are the ordinary half: absent they read
##     0.0, which is not a neutral default but a different model — working share 1.0,
##     dependency ratio 0.0, and the labour force the whole population. The sharp half
##     is `service_quality["pensions"]`, which adds no field at all, so the naive
##     reading is that it cannot bump anything. A version-16 save carries
##     `{"health": …}` and no `pensions` key; `_tick_nation()` reads `.get(key, 0.0)`
##     so the stock starts at zero and climbs, while `quality_deviation()` measures it
##     against a `start_service_quality` that is also 0.0 — so the deviation reads as a
##     large and growing POSITIVE, a France whose pension system has just been invented
##     and is improving fast. A windfall the player did not earn, mis-signed for the
##     rest of the run. The five content fields and `migration_stance` earn nothing;
##     the test asserts the halves separately, because the split is what pins that
##     adding a registry key can earn a bump at all.
##
##   V1.5c bumps to 18 on two fields of seven, and the two earn it by DIFFERENT
##     failures, which is why tests/test_save_load.gd asserts them separately rather
##     than together. `unrest_pct` is `service_quality`'s case: absent it reads 0.0, a
##     perfectly calm France, so a save reloaded mid-crisis silently ends the crisis,
##     and re-deriving on load cannot rescue it because the accumulation IS the state.
##     `unrest_cooldown_months` is U6a's `diplo_months_to_act` case: absent it reads 0,
##     0 means ACT NOW, and a reloaded save therefore fires a strike in its first month
##     whatever the player was doing. `gini_index` would have earned it a third time on
##     `young_share`'s reasoning and is folded into the same bump.
##     `start_gini_index`, `gini_index_per_yr`, `settlement_stance`,
##     `unrest_impulse_pct` and `unrest_acts` all earn nothing, for four reasons already
##     on this list.
##
##   V1.6a bumps to 19 on ONE field of two, and the interesting half is that the
##     session's own plan predicted no bump at all and gave a reason that was true
##     about the wrong thing. It reasoned that a STATELESS system has nothing to
##     serialise -- and src/sim/cycle.gd genuinely stores nothing, has no accumulator
##     and no tick_month(). But NationState.from_dict() rebuilds from the dictionary
##     ALONE and never sees the loader, so every content-derived static fact on that
##     class is already serialised: `eu_member`, `neighbours`, `pop_growth_pct`,
##     `gini_index_per_yr`. STATELESSNESS IS A PROPERTY OF THE MODULE, NOT OF THE SAVE.
##     `cycle_amplitude_rel` is the bump: absent it reads the default 1.0, every nation
##     runs the roster-average cycle instead of its own -- France 45 % louder than its
##     content says -- and the reloaded game runs a different MODEL from the one that
##     saved it, which is `eu_member` at V1.3b and `military_capability` at V1.3g.
##     `cycle_impulse_pct` earns nothing: absent it reads 0.0 and Economy.tick_month()
##     overwrites it from the clock on the first tick, `coercion_impulse_pct`'s case.
##     tests/test_save_load.gd asserts both halves, and the SPLIT is the assertion
##     worth having rather than the bump.
##
## V1.6b bumps to 20, on THREE fields of four, which is a first on this list -- V1.6a
## earned it on one of two and V1.5c on two of seven. `inflation_pct` is
## `service_quality`'s case (the accumulation IS the state, so re-deriving on load
## would erase a term's worth of it); `inflation_anchor_pct` is `cycle_amplitude_rel`'s
## verbatim (content-derived, and from_dict() never sees the loader, so an absent
## anchor collapses every nation's target toward zero and the growth channel bills a
## deflation the nation never had); and `start_inflation_pct` is `start_bloc_burden`'s
## (absent it reads 0.0 against a live ~1.8, so the thirteenth issue is MIS-SIGNED for
## the rest of the run rather than merely missing). `inflation_impulse_pct` earns
## nothing and is serialised anyway. The three are asserted SEPARATELY in
## tests/test_save_load.gd, because a single combined check would let any one of three
## different failures be quietly wrong. See docs/inflation-model.md section 9.
##
## V1.6c bumps to 21 on ONE field, and it is the SMALLEST addition on this list to earn
## one: `start_debt_to_gdp_pct`, a single float with no register behind it. Absent it
## reads 0.0 against a live ~140, so src/sim/credit.gd's debt gap reads the WHOLE stock
## as newly borrowed: the yield comes back at 4.1 against a kept 2.4 and the debt service
## with it -- a France paying seventy per cent more interest for the rest of the run
## because it saved. Measured rather than asserted, and the first draft of this comment
## said "straight to the clamp", which was a guess and was wrong. `cycle_amplitude_rel` at V1.6a, `military_capability` at V1.3g and
## `eu_member` at V1.3b, in the same family: the reloaded game runs a DIFFERENT MODEL
## from the one that saved it, with nothing anywhere to say so. Re-deriving on load does
## not rescue it either, and that is what separates it from every derived price on this
## list -- the live ratio has moved, so re-anchoring on it would silently forgive every
## point of debt the player has added.
##     WHAT V1.6c DID NOT ADD IS THE HALF WORTH PINNING. There is no stored yield, no
##     stored spread and no stored rating, because src/sim/credit.gd is stateless: the
##     yield is a pure read over the debt stock and the grievance, both of which this
##     save has carried since the MVP and V1.5c respectively. tests/test_save_load.gd
##     asserts those three ABSENCES as well as the field, so a later session making the
##     module stateful -- a downgrade record, a rating with memory -- turns it red and
##     has to come and say why. That is the V1.6 decomposition's own split trigger,
##     pinned in the save format rather than only in the docs.
##
## V1.6d bumps to 22 on THREE fields, and two of them add no key to this file at all --
## they GROW a dictionary that has been serialised since S4, which is V1.5b's
## `service_quality["pensions"]` case and the second time on this list.
##   `tax_rates_pct["capital_gains"]` and `["wealth"]`: a version-21 save carries three
##     keys, `revenue_lines()` reads `.get(key, 0.0)`, so both new taxes come back at a
##     rate of ZERO -- a save that silently ABOLISHES two taxes, hands the player back
##     whatever they were collecting, and widens the deficit by exactly it. The matching
##     `start_tax_rates_pct` keys are absent too, so `_erosion()` falls to its
##     zero-reference branch and every later rate rise is priced as a tax invented from
##     nothing. A reloaded game running a DIFFERENT MODEL: `eu_member` at V1.3b.
##   `tax_progressivity` and `start_tax_progressivity` earn it TOGETHER and by ONE
##     failure rather than two, which is why the test asserts them as a pair and not
##     separately the way V1.6b's three are. Absent, both read 0.0 -- which is not a
##     neutral default but PROGRESSIVITY_MIN, the flattest schedule the model has --
##     and because the START reads 0.0 as well the deviation is still exactly zero, so
##     the reloaded game does not merely forget the player's bracket structure, it
##     agrees that a flat tax was always normal. Neither field alone fails in a way the
##     other does not cover, and a check that split them would be checking one failure
##     twice.
##   WHAT V1.6d DID NOT ADD is the half worth pinning, and it is V1.6c's shape one
##     session on: there is NO stored Gini offset, no stored effective index and no
##     stored erosion factor, because src/sim/tax.gd is stateless -- each is a pure read
##     over `tax_progressivity` and two rates this save already carries.
##     tests/test_save_load.gd asserts those absences, so the day a session gives the
##     distribution an accumulator it turns red and has to come and say why. And
##     `gini_index` keeps its single writer, Demography.tick_month(), which is what the
##     V1.6 decomposition's "a second field, not a second writer" asked for -- one step
##     further, because there is no second field either.
##   V1.6f bumps to 23, on the HALF OF ONE FIELD, which is V1.3g's `deployments` split
##     in a new place and the assertion worth more than the bump. `NationState.projects`
##     is one dictionary carrying two things: projects under construction and projects
##     finished. Absent, the BUILDING half fails soft -- "nothing under construction" is
##     the truth about every version-22 save, because those games had no project verb,
##     which is `measures` at V1.3c and `sector_investment` at V1.6e. The DONE half does
##     not: a France that finished the rail spine and the grid has bought a permanent
##     claim on its own trend, and an absent register erases the record of it. Nothing
##     re-derives it, because the only other trace is the accumulator and that is not
##     content. So tests/test_save_load.gd asserts the two halves SEPARATELY, and pins
##     that a saved entry carries exactly the two keys Projects.ENTRY_KEYS names -- a
##     later session caching a cost, a payoff or a start date there turns it red.
##     `project_potential_target_pct` earns nothing on its own (it is derivable from
##     `projects` and data/project-actions/, exactly as `law_potential_target_pct` is
##     derivable from the passed-law list and data/laws/) and is serialised for that
##     field's reason: Economy._update_potential_shift() takes no loader.
##     `project_bill_pct_gdp` earns nothing either, recomputed on the first tick --
##     `investment_bill_pct_gdp`'s case. And `last_project_result` is not serialised at
##     all, `last_investment_result`'s case: a display record of something that has
##     already happened to the register.
##   A FIX bumps to 24, which nothing on this list has done before -- every previous
##     entry is a session adding a machine. `NationState.campaign_started` closes a
##     V1.7a exploit found by external review: start/stop/start inside one month
##     re-paid a campaign action's authored `bloc_offset`, a permanent accumulator
##     charged at the press. The register says which efforts are spent, and it fails
##     the rule in the sharpest way this list records -- absent it reads as "nothing
##     has run yet" while `campaign_running`, serialised beside it since V1.7a, says
##     an effort is in the field. The two disagree, and the disagreement IS the
##     exploit: a save reloaded inside a run-up hands every spent effort back, so
##     save-scumming becomes an unbounded version of the press loop the register
##     exists to close. `diplo_months_to_act` at U6a, whose absent value read as "act
##     now" and fired nine acts in one month, and the spent-days counter U6a's probe
##     deleted before it could hand a reloading player their month back.
##   V1.7c bumps to 25 on TWO fields of four, and they fail the rule differently.
##     `election_system` (with `election_threshold_pct` beside it) is lifted from
##     Nation for the first time: absent it reads "" and ElectoralSystems.allocate()
##     falls through its match, so every seat allocation collapses to zero and the
##     reloaded game runs a different model from the one that saved it -- V1.6a's
##     finding that statelessness is a property of the MODULE and not of the save
##     file, since from_dict() never sees the loader. `referendum_pending` is the
##     second: absent, a referendum the country has already been called to VANISHES,
##     which is a free withdrawal of the one act V1.7c deliberately made un-free.
##     `campaign_started` one commit earlier, and `diplo_months_to_act` at U6a.
##     `referendum_mode` earns nothing on its own -- it is static content, absent it
##     reads "" and a nation with no route is a legal state for six of the ten -- but
##     it is serialised anyway for `eu_member`'s reason: reading "" for FRANCE is a
##     silently different model. And `last_referendum_result` is not serialised at
##     all, `last_project_result`'s case.
##   V1.8 bumps to 26 on THREE fields of four, and the three fail the rule three
##     DIFFERENT ways -- so tests/test_save_load.gd asserts them separately, the pattern
##     V1.5c set and V1.6b extended, because a combined check lets any one of them be
##     quietly wrong. `event_pending` is `referendum_pending`'s case exactly: absent, a
##     crisis the country is already facing VANISHES, which is a free escape from the
##     one act this session deliberately made un-escapable, and `campaign_started` one
##     commit before that. `event_fired` is `passed_law_ids`' case: absent, a resolved
##     `once` event fires a second time and the player pays its price twice for
##     something already settled. `event_quiet_months` is U6a's `diplo_months_to_act`:
##     absent it reads 0, and 0 means *may fire now*, so a save reloaded the month after
##     a crisis hands the player another one immediately. `event_history` earns nothing
##     -- a display record nothing in src/sim/ reads back, `unrest_acts`' case -- and it
##     is serialised anyway, because the ledger is half of what the panel exists to be
##     and a session-only ledger is one the player loses by saving.
##   WHAT V1.8 DID NOT ADD is worth pinning beside them, and it is the same half V1.6c
##     pinned: there is NO stored hazard, no stored draw and no RNG state, because
##     Events.hazard_passes() is a pure function of (nation id, event id, absolute
##     month). tests/test_save_load.gd asserts those absences, so the day a session
##     gives the arrival of an event an accumulator it turns red and has to come and say
##     why. That is also what makes a save reloaded on the month a crisis arrived
##     receive the same crisis rather than a different one.
##
## V1.1e: 26 -> 27, on EIGHT added fields of ten, and they fail the rule by THREE
## DIFFERENT failures -- which is why tests/test_save_load.gd asserts the three groups
## apart rather than together.
##
##   * The six STATIC rows -- has_upper_house, upper_chamber_name, upper_seats,
##     upper_ordinary, upper_amendment and judicial_review -- are
##     content-derived facts that from_dict() cannot re-derive, because it never sees
##     the loader. `cycle_amplitude_rel` at V1.6a and `election_system` at V1.7c, and
##     the failure is loud: absent, a reloaded France has no Senate and no
##     Conseil constitutionnel, which is a DIFFERENT MODEL from the one that saved it.
##   * `upper_share` and `judicial_independence` are accumulated state nothing
##     recomputes on the next tick. The chamber renews only at a legislative election,
##     which for France is up to five years away, and re-deriving rule of law from
##     content on load would erase the erosion a player spent a term buying --
##     `service_quality`'s case at V1.5a in its strongest form.
##   * `held_bills` is a FREE ESCAPE if it goes missing: a bill the second chamber
##     refused simply is not there any more, available to anyone who saves and loads.
##     `referendum_pending`'s case at V1.7c and `event_pending`'s at V1.8.
##
## `start_judicial_independence` earns nothing -- it round-trips through
## data/nations/ and is content rather than state, a firm's authored share at V1.4a --
## and is serialised anyway because nothing recomputes it after init, so a save that
## dropped it would price every deviation against zero. What is NOT added is pinned
## too: no stored upper-house SEATS (Chambers.seats() derives them from the share, so
## a later session storing them turns the assertion red and has to say why) and no
## stored court verdict, because Judiciary is a pure read over a law's own reach.
##
## V2.5 bumps this to 28 on ONE field: `NationState.region_gdp_eur_bn`, the region
## level. Absent, the dictionary is empty, `Regions.total()` returns 0.0, and the
## definitional swap in Economy._apply_growth_to_sectors() writes national GDP to
## zero on the first tick -- the country does not run a different model, it ceases to
## have an economy (military_capability's case at V1.3g in its strongest form).
## Re-seeding on load does not rescue it: the authored `gdp_share` is where a region
## STARTED, and re-seeding would erase the divergence the player watched happen --
## service_quality's reason at V1.5a. The SHARES stay content and round-trip through
## data/regions/, and regional unemployment stays a pure read, so the test still pins
## those two absences.
##
## V2.6a bumps this to 29 on the two SHARES `region_gdp_eur_bn` left behind:
## `NationState.region_pop_share` and `.city_pop_share`, now live state that moves
## every month. Absent, every share reads 0.0, so every city's population is zero --
## no glyph on the map at any zoom, an empty league table in both panels. Re-seeding
## from the authored shares does not rescue them either, for the same reason it did
## not rescue `region_gdp_eur_bn`: the authored share is where a place STARTED, and
## re-seeding would erase the movement the save exists to remember. A stored city
## POPULATION still stays out -- `population x share x share` already answers it, and
## the test keeps that absence red.
##
## V2.6b2 bumps this to 30 on TWO registers, both campaign-sited: `campaign_sites`
## (effort id -> the region its meetings are held in -- a verb writes it and no tick
## recomputes it, and a dropped site silently reverts a running effort to the old
## place-less national reach while the panel still names a place) and
## `campaign_saturation` (region id -> the fraction of the region's attention the
## player's own meetings hold -- a dropped register hands every spoken-to region back
## at full reach, `campaign_started`'s exploit one level up: the tour un-spoken).
## Both absent read as the truth about every version-29 save.
const SAVE_VERSION := 30

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

## The region register, copied off the loader once at new game so src/sim/ can reach
## it without a loader. NationState.eu_member and .neighbours' own precedent, and for
## their reason: Economy.tick_month(state) is called by both balance harnesses and
## eight probes, and widening its signature would break every one of them.
##
## NOT SERIALISED. It is content; a save that carried it would let the partition drift
## from the data/regions/ file that defines it, which is exactly what
## tests/test_save_load.gd's surviving two absences are about. save_manager.load_game()
## re-attaches it from its own loader argument.
var regions := {}  # nation id -> Array of Region

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

## The meeting register — V2.4a, and the sixth piece of pair state. Symmetric key,
## because a meeting is the one pair fact that is genuinely shared: whichever of
## the two made the journey, both leaders were in the room, so a visit either
## direction opens the window for both. That is why it is NOT keyed directed the
## way measures and deployments are — a tariff and its retaliation are two acts,
## a handshake is one.
##
## The value is a STAMP (year*12 + month, never a countdown): `met_recently` is a
## level read off `now - stamp <= MEETING_WINDOW_MONTHS`, so nothing ticks, nothing
## decays and nothing has to remember to close the window — the discipline defence
## obligations were given at V1.3g, applied to a permission rather than a charge.
## Written ONLY by Diplomacy.execute() on an action with opens_meeting.
##
## Earns NO SAVE_VERSION bump: absent reads as "never met", which is true of every
## version-27 save, because those games could meet nobody's leader to any effect.
## `measures`' case at V1.3c and `appointments`' at U6a, a third time.
var met_months := {}  # symmetric key, e.g. "DEU|FRA" -> int absolute month of last meeting

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

## What the unions did — V1.5c. Newest last, each {nation_id, year, month, label,
## unrest_pct}, appended by src/sim/unrest.gd's _tick_nation() and capped at
## unrest_constants.ACTS_KEPT by the writer, for the reason `foreign_acts` above states:
## src/core/ cannot hold the cap because the dependency only runs one way.
##
## > [!important] A DISPLAY RECORD, and here the point is sharper than at V1.3f.
## > This is the one session in the project that could have been tempted to build a
## > literal grievance ledger, and did not: the unrest number IS the memory, exactly as
## > the relations number is. The moment a decision consults this list, the model has
## > two memories that can disagree and the stock stops being the one place anger lives.
## > tests/test_unrest.gd asserts no reader in src/sim/ rather than trusting this
## > comment, which is the assertion tests/test_foreign_policy.gd already makes.
##
## EARNS NO SAVE_VERSION BUMP and is not carried by duplicate_state() —
## tests/test_state_copy.gd's NOT_COPIED list says why: a projection has no past, and
## the SCHEDULE that produces acts (`unrest_cooldown_months`) is on NationState and IS
## copied. `foreign_acts`' split exactly.
var unrest_acts: Array[Dictionary] = []

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

	# AFTER the build loop rather than inside _build_nation(), and the placement is the
	# argument: that function takes the nation's own content and nothing else, where a
	# region register is a second file. Demography, Society, Unrest and Defence each
	# seed a live stock from an init called here for exactly that reason, and this
	# seeds one too.
	for ns in gs.nations.values():
		Regions.init_nation(ns, loader.regions.get(ns.id, []))
		Migration.init_nation(ns, loader.regions.get(ns.id, []))
	gs.regions = loader.regions

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

	# V1.6a, in this block rather than behind a Cycle.init_nation(), and the placement
	# is the argument: Demography, Society, Unrest and Defence each have an init
	# because each seeds a live STOCK, and this seeds none. It is a static fact about
	# the country, exactly like the two above it, and src/sim/cycle.gd has no state to
	# initialise at all. Validated and bounded at load by Nation._validate_cycle(), so
	# the default below is reached only by a fixture that has no `imported` block.
	ns.cycle_amplitude_rel = float(n.cycle.get("amplitude_rel", 1.0))

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
	# V1.6c, from the scenario-OVERRIDDEN figure above rather than from n.debt_to_gdp_pct,
	# and the distinction is the whole point of setting it here: src/sim/credit.gd
	# measures the bond spread against this, so a scenario that hands the player 140 % of
	# GDP is a France that has always carried it and must borrow at the anchor rather
	# than at a penalty for a debt it did not run up. Same argument the two comments
	# around it make for the deficit the electorate measures against.
	# Read back through ns.debt_to_gdp_pct() rather than assigned from the local above,
	# and the round trip is the point rather than a redundancy: the live read is
	# `debt_eur_bn / gdp_eur_bn * 100` and the local is what that was computed FROM, so
	# taking the local leaves a 1e-14 residue and the spread is "almost" zero at new game.
	# Almost is not the claim -- tests/test_credit.gd asserts EXACT equality, because
	# every balance figure this project has quoted against a flat 2.0 depends on it.
	ns.start_debt_to_gdp_pct = ns.debt_to_gdp_pct()

	ns.tax_rates_pct = n.tax_rates_pct.duplicate(true)
	ns.start_tax_rates_pct = ns.tax_rates_pct.duplicate(true)
	# V1.6d. From a model constant rather than from the nation file, and that is a
	# deliberate refusal rather than a shortcut: nothing on tools/import_data.py's
	# licence-clean loop measures how progressive a bracket structure is, and ten
	# identical authored values in ten nation files would be the clustered
	# `coalition_position` failure with extra steps -- a content field that looks
	# per-nation and carries no information. See tax_constants.PROGRESSIVITY_BASE.
	#
	# Start captured from the live value on the line below, which is what makes every
	# term in src/sim/tax.gd read EXACTLY 0.0 at new game for all ten.
	ns.tax_progressivity = TaxK.PROGRESSIVITY_BASE
	ns.start_tax_progressivity = ns.tax_progressivity
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

	# V1.6e. Every sector with no programme and no capital, so the trend shift reads
	# EXACTLY 0.0 in the first month and every month after it until a player acts --
	# which is what lets the whole layer go live with the balance harness
	# bit-identical across every existing regime. Takes no content list where
	# Companies does: the three sectors are model constants, so there is no file that
	# could be absent and nothing a roster could differ over.
	Investment.init_nation(ns)
	Projects.init_nation(ns)
	# V1.7a. Nothing in the field and nobody mobilised, so Campaign.turnout_of() returns
	# election_constants.BLOC_TURNOUT bit-for-bit until a player acts inside a run-up --
	# which is what lets the whole layer go live with the balance harness bit-identical
	# across every existing regime.
	Campaign.init_nation(ns)
	Pledges.init_nation(ns)
	Referendum.init_nation(ns)

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

	# V1.1e, and it must come after Elections for a reason of its own rather than
	# Government's: a second chamber is a TILTED TRANSFORM of the lower one, so
	# Chambers.target_share() reads seats_by_party. Seated at the tilted share
	# outright rather than stepped toward it, because the Senate exists on frame one
	# and has for two centuries -- a renewal lag applied at new game would model a
	# chamber that had just been invented. See docs/upper-house-model.md.
	Chambers.init_nation(ns, n, party_list)
	# Position-free: rule of law is imported content and the review rule is a static
	# fact, so nothing this seeds is derived from any other field. Said out loud
	# because a reader looking at the two ordered comments above will otherwise invent
	# a third. See docs/judiciary-model.md.
	Judiciary.init_nation(ns, n)

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

	# V1.5a, and it MUST come after Cabinet.seat() rather than beside the other
	# init_nation() calls above -- an ordering constraint rather than a preference,
	# and the one thing in this session that a comment is cheaper than a test for.
	# Society.quality_target() reads Cabinet.effectiveness(), which returns
	# VACANT_EFFECTIVENESS until a cabinet is seated. Initialised any earlier,
	# start_service_quality captures the equilibrium of a country with no ministers,
	# the real equilibrium is then higher, and every nation's quality climbs for a
	# decade of every game with no player action -- which is exactly the authored
	# transient defence.gd's own equilibrium-not-zero comment exists to prevent,
	# arriving through the back door.
	# V1.5b, and it must come BEFORE Society.init_nation() for a second, independent
	# ordering constraint of the same kind: Society.quality_target() divides by
	# Demography.dependency_factor(), which reads start_old_share and start_young_share.
	# Initialised after Society, those references are 0.0 when the quality equilibrium
	# is captured, the factor is not 1.0 on the first tick, and every nation's quality
	# steps on frame one of every game with no player action.
	Demography.init_nation(ns, n)

	Society.init_nation(ns)

	# V1.5c, last, and unlike the two above it this is NOT an ordering constraint: every
	# term of the grievance target is a deviation against a reference the calls above have
	# already captured, so the target is exactly 0.0 whenever this runs. It sits here
	# because that is the tick order, and a reader should be able to read the two in the
	# same sequence.
	Unrest.init_nation(ns)

	# V1.8. Position-free: nothing this seeds is derived from any other field, and the
	# register is empty for every nation on frame 1 by construction -- an event has to be
	# announced before it exists, and nothing announces one at new-game.
	Events.init_nation(ns)

	# V1.5d, and it is the ONE call in this function whose position is load-bearing in
	# both directions. It must come after Government.init_nation() above, because an
	# outlet's hostility is its distance from `coalition_position` and that field is
	# NEUTRAL_POSITION until Government.form() has run -- seeded any earlier, every
	# nation's press would measure its distance to the origin instead of to its
	# government. And it seeds the gain at the unframed baseline rather than deriving
	# it, because the derived value belongs to Media.tick_month() and computing it in
	# two places would be the two-writers failure this project has named five times.
	Media.init_nation(ns)

	# V1.6b, and like Unrest above this is NOT an ordering constraint -- said out loud
	# because a reader looking at five ordered inits will otherwise invent a sixth.
	# unemployment_pct, start_unemployment_pct and structural_unemployment_pct are all
	# set to one figure well above, so the unemployment gap is exactly 0.0 and the
	# target equals the nation's anchor whenever this runs.
	#
	# Takes the Nation where Society and Unrest do not, for the reason the inline
	# `cycle_amplitude_rel` read above states: inline is for imported content that
	# seeds no live stock, and the anchor seeds one. Demography.init_nation(ns, n) is
	# the shape being copied.
	Inflation.init_nation(ns, n)

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
	# Copied as a flat duplicate: Budget.project() never reads the meeting
	# register today, but the rule the two lines above state is one added tick
	# away from applying, and duplicate() on a Dictionary of ints is cheap.
	gs.met_months = met_months.duplicate()
	# Nothing in Budget.project()'s pipeline ticks Calendar today, so this copy
	# buys nothing yet -- and it is taken anyway for the reason the two lines
	# above spell out: a shared reference is one added tick away from a budget
	# panel repaint mutating the player's live diary, sixty times a second.
	gs.appointments = appointments.duplicate(true)
	# The register is CONTENT (it never mutates after new_game), so unlike the
	# pair registers above what matters is not who owns it but that a projection
	# HAS one: duplicate(true) gives the copy its own dictionaries and arrays
	# holding the same Region objects, which is as deep as it needs to go --
	# Region is content and nothing anywhere writes through it. An EMPTY register
	# on the copy was a live bug: Regions.tick_month() grew the region LEVEL
	# against an empty region LIST and returned the residual alone, so the budget
	# panel projected a France that lost 98 % of its output. V2.5 shipped exactly
	# that and test_budget caught it.
	gs.regions = regions.duplicate(true)
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
		"met_months": met_months,
		"appointments": appointments,
		"history": history,
		"recent_effects": recent_effects,
		"foreign_acts": foreign_acts,
		"unrest_acts": unrest_acts,
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

	# Absent, this reads as an empty list, which is CORRECT rather than silently wrong --
	# a version-17 save's unions could not act. `foreign_acts`' case directly above, and
	# like it this is not what earned SAVE_VERSION 18; unrest_pct and the cooldown are.
	var strikes: Array = d.get("unrest_acts", [])
	var typed_strikes: Array[Dictionary] = []
	for entry in strikes:
		typed_strikes.append(entry as Dictionary)
	gs.unrest_acts = typed_strikes

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

	# Absent, every pair reads as never having met, which is true of every
	# version-27 save -- those games could not gate a verb on a meeting. Re-floated
	# key by key for the same reason relations are: JSON round-trips a whole
	# number as an int, and the window arithmetic should not depend on how a
	# value happened to be saved.
	var met: Dictionary = d.get("met_months", {})
	for pair_key in met.keys():
		gs.met_months[pair_key] = int(met[pair_key])

	return gs
