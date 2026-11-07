extends SceneTree

## The plant-closure rate (src/sim/closures.gd): a decade of the real machine for each
## playable nation, nobody answering, counted by announcement. The calibrated rate at the
## base economy: FRA ~14 a decade, accepted by the author at #251; DEU 11, GBR 14, POL 15.
## Run isolated, the same line with another nation at the same time if the CPU is free:
##   APPDATA="$(mktemp -d)" godot --headless --path . --script res://tools/closure_rate_probe.gd
##
## The author's call on #286, the rate follows the economy, is proved here with twins of
## one seed, so two runs differ only by what is forced on them:
##   --force=PCT       a demand impulse of PCT %/yr held each month, through the real
##                     month: -1 is a slump (the gap settles near PCT / GAP_CLOSE, -3.3),
##                     +1 a boom;
##   --policy=subsidise  before the first month the state subsidises every major at the
##                     verb's top intensity, Companies' own verb: a sustained impulse
##                     (firm_impulse_pct) and shares held up;
##   --policy=invest   the three sector programmes at full intensity, Investment's own
##                     verb, so the sectors grow faster;
##   --policy=stimulus the health line raised STIMULUS_PTS of GDP every month through
##                     Budget.commit(), the player's own lever: an impulse the decay
##                     cannot finish, so demand stays lifted;
## and each number of the rule can be tried without editing the data:
##   --chance=X --slope=X --reference=X --cooldown=N --fall=X --nation=FRA

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Companies = preload("res://src/sim/companies.gd")
const Investment = preload("res://src/sim/investment.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")

const RULE_ARGS := {"--fall=": "fall", "--chance=": "monthly_chance", "--slope=": "gap_slope", "--reference=": "reference_fall"}
## Points of GDP a month: 0.6 a year, so its impulse settles near
## MULT_SPENDING x 0.05 / (1 - IMPULSE_DECAY) = 0.45 %/yr.
const STIMULUS_PTS := 0.05
const PROGRAMMES := ["agricultural_transformation", "reindustrialisation", "knowledge_economy_plan"]


func _init() -> void:
	var loader = DataLoader.new()
	loader.load_all()
	var nations: Array = ["FRA", "DEU", "GBR", "POL"]
	var force := 0.0
	var policy := ""
	for arg in OS.get_cmdline_user_args():
		for key in RULE_ARGS:
			if arg.begins_with(key):
				loader.closure_rule[RULE_ARGS[key]] = float(arg.trim_prefix(key))
		if arg.begins_with("--cooldown="):
			loader.closure_rule["cooldown_months"] = int(arg.trim_prefix("--cooldown="))
		if arg.begins_with("--nation="):
			nations = [arg.trim_prefix("--nation=")]
		if arg.begins_with("--force="):
			force = float(arg.trim_prefix("--force="))
		if arg.begins_with("--policy="):
			policy = arg.trim_prefix("--policy=")
	for id in nations:
		_run(loader, String(id), force, policy)
	quit(0)


func _run(loader, id: String, force: float, policy: String) -> void:
	var state = GameState.new_game(loader, id)
	var ns = state.player()
	var acted := _act(state, ns, loader, policy)
	var seen := {}
	var jobs: Array = []
	var by_sector := {}
	var gap_sum := 0.0
	var hook := func(step: String, after: bool, _report: Dictionary) -> void:
		if step == "Economy" and not after and force != 0.0:
			ns.demand_impulse_pct = force
		if step == "Economy" and not after and policy == "stimulus":
			Budget.commit(state, {"spending_pct_gdp": {"health": float(ns.spending_pct_gdp["health"]) + STIMULUS_PTS}})
	for m in 120:
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		WorldMonth.tick_month(state, loader, hook)
		gap_sum += Economy.output_gap_pct(ns)
		for company in Companies.majors_of(loader, id):
			var row: Dictionary = (ns.companies.get(company.id, {}) as Dictionary).get("closure", {})
			if not row.is_empty() and not seen.has(String(row["id"])):
				seen[String(row["id"])] = true
				jobs.append(float(row["jobs"]))
				by_sector[company.sector] = int(by_sector.get(company.sector, 0)) + 1
	var total: float = jobs.reduce(func(sum: float, j: float) -> float: return sum + j, 0.0)
	jobs.sort()
	print("closure_rate %s force %+.1f policy %s (%d acts): %d a decade, mean gap %+.2f, %d majors, mean plant %.0f jobs, largest %.0f, largest move %.3f, workers bloc %.3f, %s" % [
		id, force, policy if policy != "" else "none", acted, seen.size(), gap_sum / 120.0, Companies.majors_of(loader, id).size(),
		total / maxf(float(seen.size()), 1.0), float(jobs[-1]) if not jobs.is_empty() else 0.0,
		(float(jobs[-1]) if not jobs.is_empty() else 0.0) * float(loader.closure_rule["bloc_offset"]["workers"]) / float(loader.closure_rule["reference_jobs"]),
		float(ns.bloc_offset.get("workers", 0.0)), by_sector])


## The policy's own verbs, through what the game offers: how many took.
func _act(state, ns, loader, policy: String) -> int:
	var done := 0
	if policy == "subsidise":
		for company in Companies.majors_of(loader, ns.id):
			var top = null
			for action in Companies.available(state, ns, loader.company_actions, String(company.id), loader):
				var terms: Dictionary = action.effects.get("company", {})
				if String(terms.get("op", "")) == "subsidise" and (top == null or float(terms["intensity"]) > float(top.effects["company"]["intensity"])):
					top = action
			if top != null and bool(Companies.execute(state, ns, loader.company_actions, top, String(company.id), loader).get("applied", false)):
				done += 1
	elif policy == "invest":
		for action in Investment.available(state, ns, loader.investment_actions):
			if PROGRAMMES.has(String(action.id)) and bool(Investment.execute(state, ns, loader.investment_actions, action).get("applied", false)):
				done += 1
	return done
