extends RefCounted

## NationState's ONE FIELD TABLE (V5.0a). duplicate_state(), to_dict() and
## from_dict() used to be three hand-written lists over the same 217 fields, and
## a field added to two of them and forgotten in the third failed silently -- the
## from_dict() aliasing V4.6 left open on three registers was that failure. The
## three are now one walk each over FIELDS, and tests/test_nation_fields.gd fails
## when a NationState `var` is missing from the table.
##
## A row is [name, copy, read, default, absent_ok]:
##   copy      how duplicate_state() carries it -- SCALAR assigned, DEEP through
##             duplicate(true) (every container, so a projection owns every level
##             of what it ticks), NONE not at all.
##   read      how from_dict() restores it, or NOT_SAVED when to_dict() leaves it
##             out. VALUE casts to the default's type; COPIED deep-copies the
##             payload; the rest name a reader in nation_field_readers.gd.
##   default   what an ABSENT key reads as. It is the declaration's own default --
##             the test pins the two equal -- so from_dict() leaves an absent field
##             at new()'s value rather than writing a second copy of it.
##   absent_ok whether that absence reads correctly for a save made before the
##             field existed: AGENTS.md's bump rule as a column. false means a new
##             field like it bumps SAVE_VERSION; the test pins the false set
##             against SAVE_VERSION, so adding one without a bump fails. The
##             argument for each verdict is at the field's declaration in
##             nation_state.gd; the trailing comment names the bump or the reason.
##
## Row order is to_dict()'s historical key order, so a save file's bytes did not
## move when the table replaced the list.

const Readers = preload("res://src/core/nation_field_readers.gd")

const COL_NAME := 0
const COL_COPY := 1
const COL_READ := 2
const COL_DEFAULT := 3
const COL_ABSENT_OK := 4

enum { NONE, SCALAR, DEEP }
enum {
	NOT_SAVED, VALUE, COPIED, FLOAT_MAP, INT_MAP, STRING_MAP, SORTED_STRINGS, ROWS,
	FLOAT_MAP_TYPED, STRING_MAP_TYPED, BOOL_MAP_TYPED, PLEDGES, PROGRAMME,
	COMMODITY_STATE, LAW_LEDGER, DRAFT_BILLS, CUSTOM_TAXES, POLL_PURCHASES,
	ASSEMBLY_BILLS, HELD_BILLS,
}


## `dst` is a fresh NationState; every copied container is its own.
static func copy_into(src, dst) -> void:
	for row in FIELDS:
		match row[COL_COPY]:
			SCALAR:
				dst.set(row[COL_NAME], src.get(row[COL_NAME]))
			DEEP:
				dst.set(row[COL_NAME], src.get(row[COL_NAME]).duplicate(true))


## The values ARE the live fields, as they always were: the save path stringifies
## at once, and every reader below rebuilds rather than assigns, so the sharing
## never reaches a loaded state.
static func to_dict(src) -> Dictionary:
	var out := {}
	for row in FIELDS:
		if row[COL_READ] != NOT_SAVED:
			out[row[COL_NAME]] = src.get(row[COL_NAME])
	return out


## `dst` is a fresh NationState. An absent key leaves new()'s declared default.
static func read_into(dst, d: Dictionary) -> void:
	for row in FIELDS:
		var name: String = row[COL_NAME]
		if row[COL_READ] == NOT_SAVED or not d.has(name):
			continue
		dst.set(name, read_value(row[COL_READ], d[name], row[COL_DEFAULT]))


static func read_value(read: int, raw, declared):
	match read:
		VALUE:
			match typeof(declared):
				TYPE_INT: return int(raw)
				TYPE_FLOAT: return float(raw)
				TYPE_BOOL: return bool(raw)
				_: return String(raw)
		COPIED: return raw.duplicate(true)
		FLOAT_MAP: return Readers.float_map(raw)
		INT_MAP: return Readers.int_map(raw)
		STRING_MAP: return Readers.string_map(raw)
		SORTED_STRINGS: return Readers.sorted_strings(raw)
		ROWS: return Readers.rows(raw)
		FLOAT_MAP_TYPED: return Readers.float_map_typed(raw)
		STRING_MAP_TYPED: return Readers.string_map_typed(raw)
		BOOL_MAP_TYPED: return Readers.bool_map_typed(raw)
		PLEDGES: return Readers.pledges(raw)
		PROGRAMME: return Readers.programme(raw)
		COMMODITY_STATE: return Readers.commodity_state(raw)
		LAW_LEDGER: return Readers.law_ledger(raw)
		DRAFT_BILLS: return Readers.draft_bills(raw)
		CUSTOM_TAXES: return Readers.custom_taxes(raw)
		POLL_PURCHASES: return Readers.poll_purchases(raw)
		ASSEMBLY_BILLS: return Readers.assembly_bills(raw)
		HELD_BILLS: return Readers.held_bills(raw)
	push_error("nation_fields: unknown read kind %d" % read)
	return declared


const FIELDS := [
	["id", SCALAR, VALUE, "", false],
	["neighbours", DEEP, COPIED, [], false],
	["orgs", DEEP, SORTED_STRINGS, [], false],
	["org_base_transfer_pct_gdp", DEEP, FLOAT_MAP, {}, false],
	["org_seats", DEEP, INT_MAP, {}, false],
	["sector_output", DEEP, FLOAT_MAP, {}, false],
	["region_gdp_eur_bn", DEEP, FLOAT_MAP, {}, false],
	["region_pop_share", DEEP, FLOAT_MAP, {}, false],
	["city_pop_share", DEEP, FLOAT_MAP, {}, false],
	["gdp_eur_bn", SCALAR, VALUE, 0.0, false],
	["potential_gdp_eur_bn", SCALAR, VALUE, 0.0, false],
	["trend_annual_pct", SCALAR, VALUE, 0.0, false],
	["growth_annual_pct", SCALAR, VALUE, 0.0, false],
	["unemployment_pct", SCALAR, VALUE, 0.0, false],
	["structural_unemployment_pct", SCALAR, VALUE, 0.0, false],
	["start_unemployment_pct", SCALAR, VALUE, 0.0, false],
	["population", SCALAR, VALUE, 0.0, false],
	["has_budget", SCALAR, VALUE, false, false],
	["tax_progressivity", SCALAR, VALUE, 0.0, false],
	["start_tax_progressivity", SCALAR, VALUE, 0.0, false],
	["tax_rates_pct", DEEP, COPIED, {}, false],
	["spending_pct_gdp", DEEP, COPIED, {}, false],
	["start_tax_rates_pct", DEEP, COPIED, {}, false],
	["start_spending_pct_gdp", DEEP, COPIED, {}, false],
	["other_spending_pct_gdp", SCALAR, VALUE, 0.0, false],
	["other_revenue_pct_gdp", SCALAR, VALUE, 0.0, false],
	["revenue_pct_gdp", DEEP, COPIED, {}, false],
	["total_revenue_pct_gdp", SCALAR, VALUE, 0.0, false],
	["total_spending_pct_gdp", SCALAR, VALUE, 0.0, false],
	["debt_service_pct_gdp", SCALAR, VALUE, 0.0, false],
	["deficit_pct_gdp", SCALAR, VALUE, 0.0, false],
	["debt_eur_bn", SCALAR, VALUE, 0.0, false],
	["start_deficit_pct_gdp", SCALAR, VALUE, 0.0, false],
	["start_debt_to_gdp_pct", SCALAR, VALUE, 0.0, false],  # bump 21
	["bloc_approval", DEEP, COPIED, {}, false],
	["overall_approval_pct", SCALAR, VALUE, 0.0, false],
	["issue_salience", DEEP, COPIED, {}, false],
	["demand_impulse_pct", SCALAR, VALUE, 0.0, false],
	["potential_shift_pct", SCALAR, VALUE, 0.0, false],
	["external_impulse_pct", SCALAR, VALUE, 0.0, false],
	["trade_baseline_by_partner", DEEP, FLOAT_MAP, {}, false],  # bump 10
	["coercion_impulse_pct", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["cycle_impulse_pct", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["cycle_amplitude_rel", SCALAR, VALUE, 1.0, false],  # bump 19
	["inflation_pct", SCALAR, VALUE, 0.0, false],  # bump 20
	["start_inflation_pct", SCALAR, VALUE, 0.0, false],  # bump 20
	["inflation_anchor_pct", SCALAR, VALUE, 0.0, false],  # bump 20
	["inflation_impulse_pct", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["bloc_transfer_pct_gdp", SCALAR, VALUE, 0.0, false],
	["bloc_burden", SCALAR, VALUE, 0.0, false],
	["start_bloc_burden", SCALAR, VALUE, 0.0, false],
	["assembly_seats", SCALAR, VALUE, 0, false],
	["election_system", SCALAR, VALUE, "", false],  # bump 25
	["election_threshold_pct", SCALAR, VALUE, 0.0, false],  # bump 25
	["term_months", SCALAR, VALUE, 0, false],
	["months_in_term", SCALAR, VALUE, 0, false],
	["next_election_year", SCALAR, VALUE, 0, false],
	["next_election_month", SCALAR, VALUE, 0, false],
	["next_ep_election_year", SCALAR, VALUE, 0, false],
	["next_ep_election_month", SCALAR, VALUE, 0, false],
	["terms_served", SCALAR, VALUE, 0, false],
	["incumbent_party_id", SCALAR, VALUE, "", false],
	["seats_by_party", DEEP, COPIED, {}, false],
	["last_election", DEEP, COPIED, {}, false],
	["last_ep_election", DEEP, COPIED, {}, false],
	["in_government", SCALAR, VALUE, true, false],
	["has_executive", SCALAR, VALUE, false, false],
	["next_executive_year", SCALAR, VALUE, 0, false],
	["next_executive_month", SCALAR, VALUE, 0, false],
	["system_id", SCALAR, VALUE, "", false],
	["head_of_state_kind", SCALAR, VALUE, "", false],
	["head_of_state_title", SCALAR, VALUE, "", false],
	["head_of_state_person_id", SCALAR, VALUE, "", false],
	["head_of_state_next_year", SCALAR, VALUE, 0, false],
	["head_of_state_next_month", SCALAR, VALUE, 0, false],
	["lose_condition", SCALAR, VALUE, "", false],
	["term_limit", SCALAR, VALUE, 0, false],
	["amendment_rule", SCALAR, VALUE, "", false],
	["referendum_mode", SCALAR, VALUE, "", false],
	["referendum_pending", DEEP, COPIED, {}, false],
	["last_referendum_result", DEEP, COPIED, {}, true],  # absent is "no vote yet"; the org fight reads it (V5.0d)
	["event_queue", DEEP, ROWS, [], false],
	["event_fired", DEEP, COPIED, {}, false],
	["event_category_quiet", DEEP, COPIED, {}, false],
	["event_cooldowns", DEEP, COPIED, {}, false],
	["event_armed", DEEP, ROWS, [], false],
	["repealed_at", DEEP, COPIED, {}, true],  # a stamp: absent is 'not yet'
	["last_accession", DEEP, COPIED, {}, true],  # a stamp: absent is 'not yet'
	["assembly_bill_passed_month", SCALAR, VALUE, -1, true],  # a stamp: absent is 'not yet'
	["commodity_high_month", SCALAR, VALUE, -1, true],  # a stamp: absent is 'not yet'
	["event_history", DEEP, ROWS, [], true],  # display record nothing reads back
	["permits_system_change", SCALAR, VALUE, false, false],
	["dissolution_rule", SCALAR, VALUE, "", false],
	["dissolution_lockout_months", SCALAR, VALUE, 0, false],
	["dissolution_notice_months", SCALAR, VALUE, 0, false],
	["dissolution_lockout_remaining", SCALAR, VALUE, 0, false],
	["dissolution_pending", SCALAR, VALUE, false, false],
	["dissolutions_called", SCALAR, VALUE, 0, false],
	["last_dissolution", DEEP, COPIED, {}, false],
	["formation_method", SCALAR, VALUE, "", false],
	["censure_rule", SCALAR, VALUE, "", false],
	["head_of_government_title", SCALAR, VALUE, "", false],
	["start_head_of_government_person_id", SCALAR, VALUE, "", false],
	["coalition_party_ids", DEEP, COPIED, [], false],
	["coalition_seats", SCALAR, VALUE, 0, false],
	["coalition_position", DEEP, COPIED, {"economic": 0.0, "social": 0.0}, false],
	["pm_party_id", SCALAR, VALUE, "", false],
	["pm_person_id", SCALAR, VALUE, "", false],
	["is_cohabitation", SCALAR, VALUE, false, false],
	["is_minority", SCALAR, VALUE, false, false],
	["last_formation", DEEP, COPIED, {}, false],
	["force_cooldown_months", SCALAR, VALUE, 0, false],
	["censure_barred_party_ids", DEEP, COPIED, [], false],
	["governments_fallen", SCALAR, VALUE, 0, false],
	["last_censure", DEEP, COPIED, {}, false],
	["cabinet", DEEP, COPIED, {}, false],
	["cabinet_effectiveness", DEEP, COPIED, {}, false],
	["cabinet_entitlement", DEEP, COPIED, {}, false],
	["reshuffles_called", SCALAR, VALUE, 0, false],
	["reshuffle_month", SCALAR, VALUE, -1, true],  # V5.2b b3: a stamp: absent is 'not yet'
	["resignations_count", SCALAR, VALUE, 0, false],
	["last_resignation", DEEP, COPIED, {}, false],
	["party_discipline", DEEP, COPIED, {}, false],
	["law_structural_offset_pct", SCALAR, VALUE, 0.0, false],
	["law_potential_target_pct", SCALAR, VALUE, 0.0, false],
	["law_other_revenue_pct_gdp", SCALAR, VALUE, 0.0, false],
	["bloc_offset", DEEP, COPIED, {}, false],
	["passed_law_ids", DEEP, COPIED, {}, false],
	["law_cooldown_months", DEEP, COPIED, {}, false],
	["law_ledger", DEEP, LAW_LEDGER, {}, false],  # bump 38
	["draft_bills", DEEP, DRAFT_BILLS, {}, false],  # bump 38
	["custom_laws", DEEP, COPIED, {}, false],  # bump 38
	["custom_taxes", DEEP, CUSTOM_TAXES, {}, false],  # bump 38
	["poll_purchases", DEEP, POLL_PURCHASES, {}, false],  # bump 38
	["assembly_bills", DEEP, ASSEMBLY_BILLS, {}, false],  # bump 38
	["last_law_result", DEEP, COPIED, {}, false],
	["diplo_cooldown_months", DEEP, COPIED, {}, false],
	["diplo_hosted_months", DEEP, COPIED, {}, true],  # empty = nothing hosted recently
	["last_diplomatic_result", DEEP, COPIED, {}, false],
	["diplo_months_to_act", SCALAR, VALUE, 0, false],  # bump 12
	["military_capability", SCALAR, VALUE, 0.0, false],  # bump 13
	["deployment_bill_pct_gdp", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["deployment_opinion_load", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["companies", DEEP, COPIED, {}, false],  # bump 15
	["subsidy_bill_pct_gdp", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["firm_impulse_pct", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["firm_jobs_offset_pct", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["dividend_revenue_pct_gdp", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["regulation_burden", DEEP, COPIED, {}, true],  # no verb wrote it before: empty is the truth
	["sector_investment", DEEP, COPIED, {}, true],  # no verb wrote it before: empty is the truth
	["investment_bill_pct_gdp", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["last_investment_result", NONE, NOT_SAVED, {}, true],  # display record of the last verb
	["projects", DEEP, COPIED, {}, false],  # bump 23
	["project_potential_target_pct", SCALAR, VALUE, 0.0, false],
	["project_bill_pct_gdp", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["last_project_result", NONE, NOT_SAVED, {}, true],  # display record of the last verb
	["plants", DEEP, COPIED, {}, true],  # no verb wrote it before: empty is the truth
	["plant_seq", SCALAR, VALUE, 0, true],  # no verb wrote it before: empty is the truth
	["start_energy_mix", DEEP, COPIED, {}, false],  # bump 31
	["start_import_dependency_pct", SCALAR, VALUE, 0.0, false],  # bump 31
	["energy_kwh_per_capita", SCALAR, VALUE, 0.0, false],  # bump 31
	["start_co2e_per_capita_t", SCALAR, VALUE, 0.0, false],  # bump 34
	["co2e_per_capita_t", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["energy_bill_pct_gdp", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["import_dependency_pct", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["energy_impulse_pct", SCALAR, VALUE, 0.0, false],
	["last_energy_result", NONE, NOT_SAVED, {}, true],  # display record of the last verb
	["campaign_running", DEEP, COPIED, [], true],  # no verb wrote it before: empty is the truth
	["campaign_started", DEEP, COPIED, [], false],  # bump 24
	["campaign_mobilisation", DEEP, COPIED, {}, true],  # no verb wrote it before: empty is the truth
	["campaign_bill_pct_gdp", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["campaign_sites", DEEP, STRING_MAP, {}, false],  # bump 30
	["campaign_saturation", DEEP, FLOAT_MAP, {}, false],  # bump 30
	["last_campaign_result", NONE, NOT_SAVED, {}, true],  # display record of the last verb
	["pledges", DEEP, PLEDGES, [], true],  # no verb wrote it before: empty is the truth
	["last_pledge_result", NONE, NOT_SAVED, {}, true],  # display record of the last verb
	["programme", DEEP, PROGRAMME, [], false],  # bump 35
	["programme_chosen_term", SCALAR, VALUE, -1, false],
	["programme_stock", SCALAR, VALUE, 0.0, false],
	["person_loyalty", DEEP, FLOAT_MAP_TYPED, {}, false],  # bump 36
	["person_standing", DEEP, FLOAT_MAP_TYPED, {}, false],  # bump 36
	["person_grudges", DEEP, FLOAT_MAP_TYPED, {}, false],  # bump 36
	["party_leader_override", DEEP, STRING_MAP_TYPED, {}, false],  # bump 36
	["person_party_override", DEEP, STRING_MAP_TYPED, {}, false],  # bump 36
	["person_want_state", DEEP, BOOL_MAP_TYPED, {}, true],  # each want reads as its own state: no false pulse
	["commodity_state", DEEP, COMMODITY_STATE, {}, false],  # bump 37
	["last_company_result", DEEP, COPIED, {}, false],
	["service_quality", DEEP, COPIED, {}, false],  # bump 16
	["start_service_quality", DEEP, COPIED, {}, true],  # content (its declaration: earns nothing)
	["corruption", SCALAR, VALUE, 0.0, true],  # no verb wrote it before: empty is the truth
	["young_share", SCALAR, VALUE, 0.0, false],  # bump 17
	["old_share", SCALAR, VALUE, 0.0, false],  # bump 17
	["start_young_share", SCALAR, VALUE, 0.0, true],  # content (its declaration: earns nothing)
	["start_old_share", SCALAR, VALUE, 0.0, true],  # content (its declaration: earns nothing)
	["young_share_per_yr", SCALAR, VALUE, 0.0, true],  # content (its declaration: earns nothing)
	["old_share_per_yr", SCALAR, VALUE, 0.0, true],  # content (its declaration: earns nothing)
	["participation_share", SCALAR, VALUE, 0.0, false],
	["pop_growth_pct", SCALAR, VALUE, 0.0, false],
	["migration_stance", SCALAR, VALUE, 0.0, true],  # no verb wrote it before: empty is the truth
	["gini_index", SCALAR, VALUE, 0.0, false],  # bump 18
	["start_gini_index", SCALAR, VALUE, 0.0, true],  # content (its declaration: earns nothing)
	["gini_index_per_yr", SCALAR, VALUE, 0.0, true],  # content (its declaration: earns nothing)
	["unrest_pct", SCALAR, VALUE, 0.0, false],  # bump 18
	["unrest_cooldown_months", SCALAR, VALUE, 0, false],  # bump 18
	["unrest_impulse_pct", SCALAR, VALUE, 0.0, true],  # a shock already over: soft, self-correcting
	["unrest_opinion_load", SCALAR, VALUE, 0.0, true],  # rewritten by the next tick
	["settlement_stance", SCALAR, VALUE, 0.0, true],  # no verb wrote it before: empty is the truth
	["press_freedom", SCALAR, VALUE, 0.0, true],  # no verb wrote it before: empty is the truth
	["framing_gain", DEEP, COPIED, {}, true],  # rewritten by the next tick
	["has_upper_house", SCALAR, VALUE, false, false],  # bump 27
	["upper_chamber_name", SCALAR, VALUE, "", false],  # bump 27
	["upper_seats", SCALAR, VALUE, 0, false],  # bump 27
	["upper_ordinary", SCALAR, VALUE, "", false],  # bump 27
	["upper_amendment", SCALAR, VALUE, "", false],  # bump 27
	["upper_share", DEEP, FLOAT_MAP, {}, false],  # bump 27
	["held_bills", DEEP, HELD_BILLS, {}, false],  # bump 27
	["judicial_review", SCALAR, VALUE, "", false],  # bump 27
	["judicial_independence", SCALAR, VALUE, 0.0, false],  # bump 27
	["start_judicial_independence", SCALAR, VALUE, 0.0, true],  # content (its declaration: earns nothing)
	["embassies", DEEP, COPIED, [], false],  # bump 41
	["no_relations", DEEP, COPIED, [], false],  # bump 41
	["person_knowledge", DEEP, FLOAT_MAP_TYPED, {}, true],  # V5.2a: absent is a stranger
	["person_rapport", DEEP, FLOAT_MAP_TYPED, {}, true],  # V5.2a: absent is neutral
	["person_bond", DEEP, STRING_MAP_TYPED, {}, true],  # V5.2a: absent is no bond
	["person_wealth_delta_eur_m", DEEP, FLOAT_MAP_TYPED, {}, true],  # V5.2a: absent is no change
	["party_money_delta_eur_m", DEEP, FLOAT_MAP_TYPED, {}, true],  # V5.2a: absent is no change
	["commitments", DEEP, ROWS, [], true],  # V5.2a: absent is nothing promised
	["commitments_judged", DEEP, ROWS, [], true],  # V5.2b b2.1: absent is nothing judged yet
	["exposure_evidence", DEEP, ROWS, [], true],  # V5.2a: absent is nothing left behind
	["audience_requests", DEEP, ROWS, [], true],  # V5.2b: absent is nobody has asked
	["audience_asked_month", DEEP, INT_MAP, {}, true],  # V5.2b: absent is nobody has asked
	["phone_calls", DEEP, INT_MAP, {}, true],  # V5.2b b3: absent is nobody called
	["act_bloc_offset", DEEP, FLOAT_MAP_TYPED, {}, true],  # V5.2b: absent is acts priced as permanent
]
