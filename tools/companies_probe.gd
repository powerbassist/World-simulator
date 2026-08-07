extends SceneTree

## V1.4a's headless sweep. Every constant in src/sim/companies_constants.gd is set
## from a table below rather than guessed and defended afterwards, which is the
## discipline docs/decision-log.md records for every tuned number on this project.
##
## THE BANDS ARE PRE-COMMITTED, written before the sweep ran, so a number landing
## outside one is a finding rather than a reason to widen the band:
##
##   (P1) SHARE     A subsidy held for a full five-year term moves the firm's share
##                  of its sector by 25-75 % RELATIVE. Under 25 % the lever is
##                  decorative -- docs/scenario-model.md's failure. Over 75 % one
##                  verb rewrites a sector, and the register stops being a partition
##                  the player reads and becomes a slider they drag.
##
##   (P2) GROWTH    The impulse from one full-intensity subsidy on the largest firm
##                  is >= 0.05 %/yr -- five times tools/trade_probe.gd's
##                  GROWTH_LEGIBLE_PCT of 0.01 -- and <= 0.60 %/yr. The ceiling is
##                  the honest half: a subsidy to ONE FIRM must not out-punch a
##                  whole budget, whose demand impulse runs to several points.
##
##   (P3) JOBS      *** KILL SWITCH ***. The jobs channel reaches >= 0.05 points of
##                  unemployment over five years on the widest reachable pairing. If
##                  it cannot, the channel is BELOW THE READABLE FLOOR and that is
##                  recorded as a structural bound rather than tuned around --
##                  docs/defence-model.md's DEPLOYMENT_OPINION_CHOSEN finding, where
##                  raising a constant until an arithmetically impossible number
##                  moved would have been tuning against the size of a real
##                  electorate. Here it would be tuning against the size of a real
##                  labour force.
##
##   (P4) APPROVAL  Reported, not banded. The expectation written down in advance is
##                  that a subsidy to one firm does NOT clear the +-3.0 poll-noise
##                  floor in the headline figure and IS visible on a bloc row --
##                  V1.3a's finding, which V1.3g reached again from the other side.
##
##   (P5) CLAMP     The reachable worst case -- every firm subsidised at full
##                  intensity, forever -- sits strictly below SUBSIDY_BILL_MAX_PCT_GDP.
##                  A clamp that binds is a clamp setting the number.
##
## Not a test. Excluded from tools/run_tests.sh by design, so run it explicitly:
##   godot --headless --script res://tools/companies_probe.gd

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Companies = preload("res://src/sim/companies.gd")
const K = preload("res://src/sim/companies_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")

const PLAYABLE := ["FRA", "DEU", "GBR"]
const TERM_MONTHS := 60
const RUN_MONTHS := 168

## Swept for (P1). The shipped value is whichever row lands inside the band.
const SHIFT_CANDIDATES := [0.0005, 0.0010, 0.0020, 0.0040, 0.0080]

## Swept for (P2). One tax point is worth roughly 0.50 % of GDP
## (economy_constants.TAX_BASE_SHARE), which is the anchor the cost table reads
## against.
const GROWTH_BETA_CANDIDATES := [0.10, 0.20, 0.30, 0.50, 0.80]

var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("loader errors: %s" % [_loader.errors])
		quit(1)
		return

	_table_a_register()
	_table_b_share_sweep()
	_table_c_growth_sweep()
	_table_d_jobs()
	_table_e_bill()
	_table_f_approval()
	quit(0)


func _new_state(nation_id: String):
	return GameState.new_game(_loader, nation_id)


func _subsidise_action(op_intensity: float):
	for a in _loader.company_actions:
		if String(a.effects.get("company", {}).get("op", "")) != "subsidise":
			continue
		if is_equal_approx(float(a.effects["company"]["intensity"]), op_intensity):
			return a
	return null


func _largest(state, ns) -> String:
	var best := ""
	var best_output := -1.0
	for company in Companies.firms_of(_loader, ns.id):
		var out: float = Companies.output_eur_bn(ns, company)
		if out > best_output:
			best_output = out
			best = String(company.id)
	return best


# --- (a) What the register looks like ------------------------------------------

## The static picture, before any lever is pulled. Printed first because every band
## below is read against these numbers: a firm's weight in the economy is what the
## growth channel scales by, and the gap in jobs-per-share between two rivals in one
## sector is the ENTIRE jobs channel.
func _table_a_register() -> void:
	print("\n=== (a) the register at new-game ===")
	print("%-4s %-22s %-12s %8s %10s %9s %12s" % [
		"nat", "firm", "sector", "share", "bn/yr", "%GDP", "jobs/share",
	])
	for nation_id in PLAYABLE:
		var state = _new_state(nation_id)
		var ns = state.player()
		for company in Companies.firms_of(_loader, nation_id):
			var out: float = Companies.output_eur_bn(ns, company)
			print("%-4s %-22s %-12s %8.3f %10.1f %9.4f %12.0f" % [
				nation_id, company.id.substr(4), company.sector, company.share,
				out, out / ns.gdp_eur_bn, company.headcount / company.share,
			])


# --- (b) P1: how fast share moves -----------------------------------------------

## Relative share gain over one five-year term, per candidate rate. The band is
## 25-75 %: below it the lever is decorative, above it one verb rewrites a sector.
##
## Run by stepping Companies.tick_month() alone, so the number is the share model
## and nothing else -- no growth, no budget, no opinion in the way.
func _table_b_share_sweep() -> void:
	print("\n=== (b) P1: relative share gain over a %d-month term, by SHARE_SHIFT_PER_MONTH ===" % TERM_MONTHS)
	print("     band 25-75 %% relative. shipped value: %s" % str(K.SHARE_SHIFT_PER_MONTH))
	print("     `t90` is months to reach 90 %% of the endpoint -- once the floor is")
	print("     relative, the ENDPOINT is content and the rate only sets the SPEED, so")
	print("     that is the column the rate has to be chosen on. Band 12-48 months,")
	print("     fixed before this column existed: under 12 the standing bill buys")
	print("     nothing after the first year, over 48 it never pays inside a term.")
	print("%-10s %10s %10s %10s %6s %10s" % ["shift", "FRA", "DEU", "GBR", "t90", "verdict"])

	for shift in SHIFT_CANDIDATES:
		var gains: Array[float] = []
		var t90 := 0
		for nation_id in PLAYABLE:
			var state = _new_state(nation_id)
			var ns = state.player()
			var target := _largest(state, ns)
			var start: float = Companies.share_of(ns, target)
			# The rate is a constant, so the sweep re-implements one line of
			# _tick_shares() rather than mutating a const: at full intensity the gainer
			# takes `shift` a month from its named rivals, floored at SHARE_MIN.
			var share := start
			var rivals := _rival_shares(ns, target)
			var floors := _rival_floors(ns, target)
			# The endpoint this rate is converging on, so t90 is measured against the
			# model's own answer rather than against the term's last value.
			var endpoint := start
			for r in floors.keys():
				endpoint += maxf(float(rivals[r]) - float(floors[r]), 0.0)
			var reached := 0
			for _m in range(TERM_MONTHS):
				if reached == 0 and share >= start + 0.9 * (endpoint - start):
					reached = _m
				var available := 0.0
				for r in rivals.keys():
					available += maxf(float(rivals[r]) - float(floors[r]), 0.0)
				var gain: float = minf(shift, minf(available, maxf(K.SHARE_MAX - share, 0.0)))
				if gain <= 0.0:
					break
				share += gain
				for r in rivals.keys():
					var supply: float = maxf(float(rivals[r]) - float(floors[r]), 0.0)
					rivals[r] = float(rivals[r]) - gain * supply / available
			gains.append(100.0 * (share - start) / start)
			t90 = maxi(t90, reached if reached > 0 else TERM_MONTHS)

		var worst: float = gains.min()
		var best: float = gains.max()
		var verdict := "in band"
		if best < 25.0:
			verdict = "DECORATIVE"
		elif worst > 75.0:
			verdict = "TOO FAST"
		elif worst < 25.0 or best > 75.0:
			verdict = "split"
		elif t90 < 12:
			verdict = "TOO FAST t90"
		elif t90 > 48:
			verdict = "TOO SLOW t90"
		print("%-10s %9.1f%% %9.1f%% %9.1f%% %6d %10s" % [
			str(shift), gains[0], gains[1], gains[2], t90, verdict,
		])


func _rival_shares(ns, target_id: String) -> Dictionary:
	var sector := ""
	for company in Companies.firms_of(_loader, ns.id):
		if company.id == target_id:
			sector = company.sector
	var out := {}
	for company in Companies.firms_in_sector(_loader, ns.id, sector):
		if company.id != target_id:
			out[company.id] = Companies.share_of(ns, company.id)
	return out


## Half of each rival's AUTHORED share -- the floor the probe's own first sweep
## forced into the model. See companies_constants.RIVAL_FLOOR_FRACTION.
func _rival_floors(ns, target_id: String) -> Dictionary:
	var sector := ""
	for company in Companies.firms_of(_loader, ns.id):
		if company.id == target_id:
			sector = company.sector
	var out := {}
	for company in Companies.firms_in_sector(_loader, ns.id, sector):
		if company.id != target_id:
			out[company.id] = K.RIVAL_FLOOR_FRACTION * company.share
	return out


# --- (c) P2: how much growth a subsidy buys -------------------------------------

## The impulse at full intensity, per candidate beta, for the largest firm of each
## playable nation. Band: 0.05 to 0.60 %/yr.
func _table_c_growth_sweep() -> void:
	print("\n=== (c) P2: growth impulse at intensity 1.0 on the largest firm, by SUBSIDY_GROWTH_BETA ===")
	print("     band 0.05-0.60 %%/yr. shipped value: %s" % str(K.SUBSIDY_GROWTH_BETA))
	print("%-10s %10s %10s %10s %10s" % ["beta", "FRA", "DEU", "GBR", "verdict"])

	for beta in GROWTH_BETA_CANDIDATES:
		var impulses: Array[float] = []
		for nation_id in PLAYABLE:
			var state = _new_state(nation_id)
			var ns = state.player()
			var target := _largest(state, ns)
			var gdp_share := 0.0
			for company in Companies.firms_of(_loader, nation_id):
				if company.id == target:
					gdp_share = Companies.output_eur_bn(ns, company) / ns.gdp_eur_bn
			impulses.append(beta * gdp_share / K.GDP_SHARE_REFERENCE)

		var worst: float = impulses.min()
		var best: float = impulses.max()
		var verdict := "in band"
		if best < 0.05:
			verdict = "BELOW FLOOR"
		elif worst > 0.60:
			verdict = "TOO LARGE"
		elif worst < 0.05 or best > 0.60:
			verdict = "split"
		print("%-10s %9.3f%% %9.3f%% %9.3f%% %10s" % [
			str(beta), impulses[0], impulses[1], impulses[2], verdict,
		])


# --- (d) P3: the kill switch ----------------------------------------------------

## Jobs created, and what they are worth in points of unemployment, for every firm
## in the register subsidised alone for a five-year term.
##
## THE KILL SWITCH. If the best row here cannot reach 0.05 points, the jobs channel
## is below the readable floor and V1.4a records that as a bound rather than raising
## a constant to hide it. There is no constant to raise honestly: the channel is
## arithmetic -- jobs moved, divided by a real labour force -- and the only tuned
## number anywhere near it is the share rate, which (b) has already fixed against a
## band of its own.
func _table_d_jobs() -> void:
	print("\n=== (d) P3 KILL SWITCH: jobs and unemployment points over a %d-month term ===" % TERM_MONTHS)
	print("     floor 0.05 pts of unemployment on the best row")
	print("%-4s %-22s %12s %12s %12s" % ["nat", "firm subsidised", "net jobs", "unemp pts", "labour force"])

	var best_points := 0.0
	var best_row := ""
	for nation_id in PLAYABLE:
		for company in Companies.firms_of(_loader, nation_id):
			var state = _new_state(nation_id)
			var ns = state.player()
			var action = _subsidise_action(1.0)
			Companies.execute(state, ns, _loader.company_actions, action, company.id)
			for _m in range(TERM_MONTHS):
				Companies.tick_month(state, _loader)

			var net_jobs := 0.0
			for f in Companies.firms_of(_loader, nation_id):
				net_jobs += Companies.headcount(ns, f) - f.headcount
			var points: float = absf(ns.firm_jobs_offset_pct)
			if points > best_points:
				best_points = points
				best_row = "%s %s" % [nation_id, company.id]
			print("%-4s %-22s %12.0f %12.4f %12.0f" % [
				nation_id, company.id.substr(4), net_jobs, -ns.firm_jobs_offset_pct,
				ns.population * K.LABOUR_FORCE_SHARE,
			])

	print("     best: %s at %.4f pts -- %s" % [
		best_row, best_points,
		"CLEARS the floor" if best_points >= 0.05 else "BELOW THE FLOOR, recorded as a bound",
	])


# --- (e) P5: the bill against its clamp and against a tax point -------------------

func _table_e_bill() -> void:
	print("\n=== (e) P5: the subsidy bill, %% of GDP ===")
	print("     one tax point is worth ~0.50 %% of GDP. clamp: %s" % str(K.SUBSIDY_BILL_MAX_PCT_GDP))
	print("%-30s %10s %14s" % ["firms subsidised at full", "bill", "tax points"])

	var state = _new_state("FRA")
	var ns = state.player()
	var action = _subsidise_action(1.0)
	var n := 0
	for company in Companies.firms_of(_loader, "FRA"):
		Companies.execute(state, ns, _loader.company_actions, action, company.id)
		Companies.tick_month(state, _loader)
		n += 1
		print("%-30d %9.3f%% %14.2f" % [n, ns.subsidy_bill_pct_gdp, ns.subsidy_bill_pct_gdp / 0.50])

	print("     reachable worst case %.3f against clamp %.3f -- %s" % [
		ns.subsidy_bill_pct_gdp, K.SUBSIDY_BILL_MAX_PCT_GDP,
		"SLACK" if ns.subsidy_bill_pct_gdp < K.SUBSIDY_BILL_MAX_PCT_GDP else "BINDING",
	])


# --- (f) P4: what it costs politically -------------------------------------------

## A five-year subsidised run against an otherwise identical quiet one. Reported
## rather than banded, and the expectation written down in advance is that the
## headline figure does NOT clear +-3.0 while a bloc row does.
func _table_f_approval() -> void:
	print("\n=== (f) P4: approval after %d months, subsidised vs quiet (FRA) ===" % TERM_MONTHS)

	var quiet = _new_state("FRA")
	var loud = _new_state("FRA")
	var action = _subsidise_action(1.0)
	Companies.execute(loud, loud.player(), _loader.company_actions, action, _largest(loud, loud.player()))

	for _m in range(TERM_MONTHS):
		for s in [quiet, loud]:
			Economy.tick_month(s)
			Budget.tick_month(s)
			Opinion.tick_month(s)
		Companies.tick_month(loud, _loader)
		Companies.tick_month(quiet, _loader)

	print("%-14s %10s %10s %10s" % ["bloc", "quiet", "subsidised", "delta"])
	for bloc in OK.BLOC_KEYS:
		var a: float = float(quiet.player().bloc_approval[bloc])
		var b: float = float(loud.player().bloc_approval[bloc])
		print("%-14s %10.2f %10.2f %+10.2f" % [bloc, a, b, b - a])
	var head_a: float = quiet.player().overall_approval_pct
	var head_b: float = loud.player().overall_approval_pct
	print("%-14s %10.2f %10.2f %+10.2f  (noise floor +-3.0)" % [
		"HEADLINE", head_a, head_b, head_b - head_a,
	])
	print("%-14s %10.3f %10.3f %+10.3f" % [
		"deficit", quiet.player().deficit_pct_gdp, loud.player().deficit_pct_gdp,
		loud.player().deficit_pct_gdp - quiet.player().deficit_pct_gdp,
	])
	print("%-14s %10.3f %10.3f %+10.3f" % [
		"unemployment", quiet.player().unemployment_pct, loud.player().unemployment_pct,
		loud.player().unemployment_pct - quiet.player().unemployment_pct,
	])
	print("%-14s %10.1f %10.1f %+10.1f" % [
		"GDP bn", quiet.player().gdp_eur_bn, loud.player().gdp_eur_bn,
		loud.player().gdp_eur_bn - quiet.player().gdp_eur_bn,
	])
