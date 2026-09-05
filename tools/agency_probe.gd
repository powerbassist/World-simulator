extends SceneTree

## Headless probe: godot --headless --script res://tools/agency_probe.gd
## (add `-- --json` for the stable-key summary). Dev-only, never ships.
##
## V2.9b. Answers the playtest's F6 with numbers instead of two anecdotes: does
## ONE TERM of play move a player-visible quantity at all? Five scripted policy
## styles ride the sim's own tick in main.gd's order and the same verbs the UI
## issues (Budget.commit, Legislature.propose, Diplomacy.execute,
## Campaign.execute, Projects.execute) -- never a written field, per the
## harness's own rule that a regime bypassing the verbs tests a model the
## player cannot reach.
##
## THE APPROVAL PATH (what a player verb can reach, V1.5c's measured table):
## bloc approval moves toward APPROVAL_NEUTRAL + SPAN * (salience-weighted
## issue satisfaction + law_offset - unrest_opinion_load), by INERTIA_RATE.
## The satisfactions a verb touches: budget -> tax_*/spending_* directly and
## jobs/growth through the economy; laws -> law_offset and service quality;
## unrest -> unrest_opinion_load; projects/investment -> growth only.
## Campaign reaches NOTHING here -- its mobilisation feeds Elections.vote_share
## at the vote, which is why campaign-only is scored on vote share, not
## approval. Diplomacy reaches approval only through the openness level's
## growth term.
##
## DETERMINISM, AND WHY THERE ARE NO SEEDS: the sim has no RNG anywhere (every
## bit-identity re-run this project has recorded depends on it), so the plan's
## "30 seeds" would be 30 identical runs. The stability read is policy
## VARIANTS inside the budget family's own free parameter (tax-led vs
## spend-led) instead -- BALANCE_PLAN.md's correction. Poll noise is
## month-indexed and style-blind, so polled deltas equal true deltas.
##
## Events are answered ON ARRIVAL in EVERY style with the harness's "soft"
## rule (non-default choice, best bloc-weighted approval), so the event
## channel never confounds the family comparison.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Defence = preload("res://src/sim/defence.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Companies = preload("res://src/sim/companies.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const Society = preload("res://src/sim/society.gd")
const Demography = preload("res://src/sim/demography.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Events = preload("res://src/sim/events.gd")
const Media = preload("res://src/sim/media.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Energy = preload("res://src/sim/energy.gd")
const Regions = preload("res://src/sim/regions.gd")
const Migration = preload("res://src/sim/migration.gd")

const START_YEAR := 2026
const MONTHS := 16          # Jan 2026 -> the May 2027 executive election.
const AGENCY_BAND := 1.0    # points of approval by month 6 (pre-declared).

## Quarterly commits at months 1/4/7/10/13 -- a budget player works on the
## quarter, not every month; the harness's regimes commit once and hold.
const COMMIT_MONTHS := [1, 4, 7, 10, 13]
const LAW_MONTHS := [3, 6, 9, 12]
const DIPLO_MONTHS := [2, 5, 8, 11]

const STYLES := [
	{"id": "idle", "budget": {}, "laws": false, "diplomacy": false, "project": false, "campaign": []},
	{"id": "budget-tax", "budget": {
		"tax_rates_pct": {"income": 4.0, "corporate": 2.0, "vat": 2.0},
		"spending_pct_gdp": {"pensions": -1.5, "health": -1.0},
	}, "laws": false, "diplomacy": false, "project": false, "campaign": []},
	{"id": "budget-spend", "budget": {
		"tax_rates_pct": {"income": 2.0, "corporate": -2.0},
		"spending_pct_gdp": {"infrastructure": 2.0, "education": 1.5, "health": 1.0},
	}, "laws": false, "diplomacy": false, "project": false, "campaign": []},
	{"id": "full-tax", "budget": {
		"tax_rates_pct": {"income": 4.0, "corporate": 2.0, "vat": 2.0},
		"spending_pct_gdp": {"pensions": -1.5, "health": -1.0},
	}, "laws": true, "diplomacy": true, "project": true, "campaign": [8]},
	{"id": "campaign-only", "budget": {}, "laws": false, "diplomacy": false, "project": false, "campaign": [8, 12]},
]


func _init() -> void:
	var as_json := "--json" in OS.get_cmdline_user_args()
	var summaries := {}
	for style in STYLES:
		summaries[String(style["id"])] = _run_style(style)

	var idle: Dictionary = summaries["idle"]
	var best_family := ""
	var best_delta := -999.0
	var deltas := {}
	for style in STYLES:
		var id := String(style["id"])
		if id == "idle":
			continue
		var family := id.split("-")[0]
		var d6: float = float(summaries[id]["approval_m6"]) - float(idle["approval_m6"])
		if not deltas.has(family) or d6 > float(deltas[family]):
			deltas[family] = d6
		if d6 > best_delta:
			best_delta = d6
			best_family = family

	var verdict := "PASS" if best_delta >= AGENCY_BAND else "FAIL"

	if as_json:
		print(JSON.stringify({
			"schema": "agency-probe/v1",
			"band_points_m6": AGENCY_BAND,
			"styles": summaries,
			"deltas_vs_idle_m6": deltas,
			"best_family": best_family,
			"best_delta_m6": best_delta,
			"verdict": verdict,
		}, "  "))
	else:
		_print_table(summaries, deltas, best_family, best_delta, verdict)
	quit(0)


func _print_table(summaries: Dictionary, deltas: Dictionary, best_family: String, best_delta: float, verdict: String) -> void:
	print("")
	print("=== AGENCY PROBE — one term (FRA Standard, %d months) ===" % MONTHS)
	print("%-14s %8s %8s %8s %9s %9s %8s  %s" % [
		"style", "appr m6", "appr m16", "d_m6", "unemp m16", "defic m16", "vote %", "campaign?"])
	for id in summaries:
		var s: Dictionary = summaries[id]
		var d6: float = float(s["approval_m6"]) - float(summaries["idle"]["approval_m6"])
		print("%-14s %8.2f %8.2f %+8.2f %9.2f %9.2f %7.1f%%  %s" % [
			id, float(s["approval_m6"]), float(s["approval_m16"]), d6,
			float(s["unemployment_m16"]), float(s["deficit_m16"]),
			float(s["vote_share"]) * 100.0,
			", ".join(s["campaign_log"]),
		])
	print("")
	print("family deltas vs idle at month 6: %s" % str(deltas))
	print("VERDICT: agency %s — best family '%s' at %+.2f points (band +%.1f)" % [
		verdict, best_family, best_delta, AGENCY_BAND])


func _run_style(style: Dictionary) -> Dictionary:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return {}

	var state = GameState.new_game(loader, "FRA")
	state.year = START_YEAR
	state.month = 1

	var ns = state.player()
	var party_list: Array = loader.parties.get("FRA", [])
	var log: Array = []

	# Month 1's budget commits BEFORE the loop, the harness's own shape.
	var commit_months: Array = COMMIT_MONTHS.duplicate()
	commit_months.erase(1)
	if not (style["budget"] as Dictionary).is_empty():
		Budget.commit(state, _pending_for(ns, style["budget"]))

	var campaign_log: Array = []
	var year := START_YEAR
	var month := 1
	var result_record := {}
	for i in range(MONTHS):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month

		# The tick order is main.gd's and balance_probe.gd's, verbatim in
		# sequence: a probe whose month differs from the game's month measures
		# a simulation the player never played.
		var access_by_nation: Dictionary = {}
		for member_id in state.nations.keys():
			access_by_nation[member_id] = Regions.accessibility_for(
				state.nations[member_id], state.regions.get(member_id, []), state.region_graph)
		Energy.tick_month(state, loader, access_by_nation)
		Economy.tick_month(state)
		Budget.tick_month(state)
		Bloc.tick_month(state, loader)
		Inflation.tick_month(state)
		Media.tick_month(state, loader)
		Opinion.tick_month(state)
		var entry := Budget.snapshot(state)
		entry.merge(Opinion.snapshot(state))
		state.append_history(entry)
		Discipline.tick_month(state, loader)
		Legislature.tick_month(state, loader)
		Dissolution.tick_month(state)
		Diplomacy.tick_month(state, loader)
		Defence.tick_month(state)
		Companies.tick_month(state, loader)
		Migration.tick_month(state, loader)
		Investment.tick_month(state)
		Projects.tick_month(state, loader)
		Campaign.tick_month(state, loader)
		Pledges.tick_month(state, loader)
		Demography.tick_month(state)
		Society.tick_month(state)
		Unrest.tick_month(state)
		Events.tick_month(state, loader)
		_answer_event(state, loader, ns, log, year, month)
		Cabinet.tick_month(state, loader)

		# The verbs, in the slot the harness puts its regime actions: after the
		# ticks, before the calendar and the election.
		if (i + 1) in commit_months and not (style["budget"] as Dictionary).is_empty():
			Budget.commit(state, _pending_for(ns, style["budget"]))
		if bool(style["laws"]) and (i + 1) in LAW_MONTHS:
			_propose_best_law(state, loader, ns, party_list, log, year, month)
		if bool(style["diplomacy"]) and (i + 1) in DIPLO_MONTHS:
			_sign_an_agreement(state, loader, ns, log, year, month)
		if (i + 1) in (style["campaign"] as Array):
			_campaign_best_site(state, loader, ns, log, year, month, campaign_log)
		if bool(style["project"]) and i + 1 == 6:
			_break_ground(state, loader, ns, log, year, month)

		# The day loop for calendar parity. None of these styles BOOK anything
		# (the agreement verb executes; it does not book), so the register is
		# empty by construction and due() is the one is_empty() check the
		# harness's U6a note describes.
		state.day = 0
		for d in range(_days_in_month(month, year)):
			state.day = d + 1
			Calendar.due(state, year, month, state.day)
		Calendar.tick_month(state)

		for r in Elections.tick_month(state, loader):
			if r["kind"] == "executive" or (r["kind"] == "national" and not ns.has_executive):
				result_record = r

		if (i + 1) == 6 or (i + 1) == MONTHS:
			log.append("%d-%02d approval %.2f unemp %.2f deficit %.2f grievance %.2f" % [
				year, month, float(ns.overall_approval_pct), float(ns.unemployment_pct),
				float(ns.deficit_pct_gdp), float(ns.unrest_pct),
			])

	var vote_share: float = -1.0
	var decided := ""
	if not result_record.is_empty():
		vote_share = float(result_record.get("incumbent_vote_share", -1.0))
		var bits: Array = []
		for entry2 in result_record.get("attribution", []):
			bits.append("%s %s" % [String(entry2.get("issue", "")), String(entry2.get("mood", ""))])
		decided = "win" if bool(result_record.get("incumbent_largest", false)) else "loss"
		if not bits.is_empty():
			decided += " (" + "; ".join(bits) + ")"

	return {
		"approval_m6": _approval_at(state, 6),
		"approval_m16": _approval_at(state, 16),
		"unemployment_m16": float(ns.unemployment_pct),
		"deficit_m16": float(ns.deficit_pct_gdp),
		"grievance_m16": float(ns.unrest_pct),
		"vote_share": vote_share,
		"outcome": decided,
		"campaign_log": campaign_log,
		"log": log,
	}


## History holds one snapshot per simulated month in order; month 6 is index 5
## and month 16 index 15. Read from the snapshot, not off the live field, so
## the metric is the month's own figure rather than the term's last.
func _approval_at(state, month_index: int) -> float:
	var history: Array = state.history
	if history.size() >= month_index:
		return float(history[month_index - 1].get("overall_approval_pct", 0.0))
	return 0.0


func _pending_for(ns, delta: Dictionary) -> Dictionary:
	var pending := {}
	if delta.has("tax_rates_pct"):
		var rates := {}
		for key in delta["tax_rates_pct"]:
			var start: float = float(ns.start_tax_rates_pct.get(key, 0.0))
			rates[key] = clampf(start + float(delta["tax_rates_pct"][key]), 0.0, 100.0)
		pending["tax_rates_pct"] = rates
	if delta.has("spending_pct_gdp"):
		var spending := {}
		for key in delta["spending_pct_gdp"]:
			var start: float = float(ns.start_spending_pct_gdp.get(key, 0.0))
			spending[key] = clampf(start + float(delta["spending_pct_gdp"][key]), 0.0, 100.0)
		pending["spending_pct_gdp"] = spending
	return pending


## Pass-forecast-guided: the available law whose expected yes-seats is highest,
## read off Legislature.support -- the same per-party support the law panel's
## blurred forecast prints. Proposing through the verb, refusing nothing: a
## failed vote is information the player also had coming.
func _propose_best_law(state, loader, ns, party_list: Array, log: Array, year: int, month: int) -> void:
	var best = null
	var best_yes := -1.0
	for law in Legislature.available(ns, loader.laws):
		var yes := 0.0
		for party in party_list:
			yes += float(ns.seats_by_party.get(party.id, 0)) * (1.0 if Legislature.support(ns, party, law) > 0.0 else 0.0)
		if yes > best_yes:
			best_yes = yes
			best = law
	if best == null:
		log.append("%d-%02d no law available" % [year, month])
		return
	var result := Legislature.propose(state, loader, best)
	log.append("%d-%02d law '%s' %s (yes %d / %d)" % [
		year, month, String(best.id),
		"PASSED" if bool(result.get("passed", false)) else "failed",
		int(result.get("yes_seats", 0)), int(result.get("seats_total", 0)),
	])


## The harness's own agreement shape: the authored 'enter' action at the best-
## scored partner, through Diplomacy.execute and never a written agreement.
func _sign_an_agreement(state, loader, ns, log: Array, year: int, month: int) -> void:
	var action = null
	for candidate in loader.diplomatic_actions:
		if String(candidate.effects.get("agreement", {}).get("op", "")) == "enter":
			action = candidate
			break
	if action == null:
		return
	var best := ""
	var best_score := -1.0e9
	for id in state.nations.keys():
		if String(id) == ns.id:
			continue
		var value := Diplomacy.score(state, ns.id, String(id))
		if value > best_score:
			best_score = value
			best = String(id)
	if best == "":
		return
	var result := Diplomacy.execute(state, loader.diplomatic_actions, action, ns.id, best)
	log.append("%d-%02d agreement with %s: %s" % [
		year, month, best,
		"agreed" if bool(result.get("applied", false)) else "refused",
	])


## The largest live-population region, ties to the sorted scan -- a
## deterministic answer, and the siting a tour regime already vindicated.
func _campaign_best_site(state, loader, ns, log: Array, year: int, month: int, campaign_log: Array) -> void:
	var site := ""
	var best_share := -1.0
	for region in loader.regions.get(ns.id, []):
		var share: float = Migration.region_share(ns, String(region.id))
		if share > best_share + 0.0000001 or (absf(share - best_share) <= 0.0000001 and (site == "" or String(region.id) < site)):
			best_share = share
			site = String(region.id)
	if site == "":
		return
	for a in loader.campaign_actions:
		if String(a.effects.get("campaign", {}).get("op", "")) != "start":
			continue
		var result := Campaign.execute(state, ns, loader.campaign_actions, a, site)
		var line := "%d-%02d campaign '%s' @ %s: %s" % [
			year, month, String(a.id), site,
			"applied" if bool(result.get("applied", false)) else "refused",
		]
		log.append(line)
		campaign_log.append("%s@%s(%s)" % [String(a.id), site, "y" if bool(result.get("applied", false)) else "n"])
		return
	log.append("%d-%02d no campaign start action authored" % [year, month])


func _break_ground(state, loader, ns, log: Array, year: int, month: int) -> void:
	for a in loader.project_actions:
		if String(a.effects.get("project", {}).get("op", "")) != "start":
			continue
		var result := Projects.execute(state, ns, loader.project_actions, a)
		if bool(result.get("applied", false)):
			log.append("%d-%02d project '%s' begun" % [year, month, String(a.id)])
			return
	log.append("%d-%02d no project could be begun" % [year, month])


## Events answered on arrival, EVERY style, harness "soft" rule: the non-default
## choice best for bloc-weighted approval. A fault the player always clears, so
## the style comparison never rides an expired card.
func _answer_event(state, loader, ns, log: Array, year: int, month: int) -> void:
	if not Events.is_pending(ns):
		return
	var ev = Events.pending_event(ns, loader)
	if ev == null:
		return
	var pick: Dictionary = {}
	var pick_score := 0.0
	for c in ev.choices:
		if bool(c["is_default"]):
			continue
		var score := 0.0
		var terms: Dictionary = (c["effects"] as Dictionary).get("bloc_offset", {})
		for bloc in terms:
			score += float(K.BLOC_SIZE.get(bloc, 0.0)) * float(terms[bloc])
		if pick.is_empty() or score > pick_score:
			pick = c
			pick_score = score
	if pick.is_empty():
		return
	if not Events.choose(state, loader, String(pick["id"])).is_empty():
		log.append("%d-%02d event '%s' -> %s" % [year, month, String(ev.event_name), String(pick["label"])])


func _days_in_month(m: int, y: int) -> int:
	if m == 2 and (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)):
		return 29
	return [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
