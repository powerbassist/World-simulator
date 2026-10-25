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
const Demography = preload("res://src/sim/demography.gd")
const K = preload("res://src/sim/companies_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Legislature = preload("res://src/sim/legislature.gd")

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
	_table_g_regulation_jobs()
	_table_h_regulation_growth()
	_table_i_redundancy()
	_table_j_dominance()
	_table_k_content()
	_table_l_valuation()
	_table_m_dividend()
	_table_n_fiscal()
	_table_o_shield()
	_table_p_approval()
	_table_q_issue_keys()
	_table_r_redundancy()
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
	# The pool is MAJORS-ONLY since V4.7a: body rivals read 0.0 in the register
	# and contributed nothing, so the sweep's numbers never moved -- but a
	# mirror that reproduced the pool by accident of zeros rather than by the
	# tier rule was one refactoring away from silently wrong.
	var out := {}
	for company in Companies.majors_of(_loader, ns.id):
		if company.sector != sector or company.id == target_id:
			continue
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
	for company in Companies.majors_of(_loader, ns.id):
		if company.sector != sector or company.id == target_id:
			continue
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
			Companies.execute(state, ns, _loader.company_actions, action, company.id, _loader)
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
				Demography.labour_force(ns),
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
		Companies.execute(state, ns, _loader.company_actions, action, company.id, _loader)
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
	Companies.execute(loud, loud.player(), _loader.company_actions, action, _largest(loud, loud.player()), _loader)

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


# =================================================================================
# V1.4b: the sector burden
# =================================================================================
#
# Four more pre-committed bands, written before these sweeps ran:
#
#   (P6) JOBS      *** KILL SWITCH, again ***. A burden at REGULATION_BURDEN_MAX
#                  reaches >= 0.05 points of unemployment on the widest sector.
#                  STANDING PREDICTION, written in advance: agriculture cannot
#                  clear it at any sane value -- 39k named jobs against a 30.9M
#                  labour force -- and that is RECORDED as a structural bound
#                  rather than tuned around.
#
#   (P7) GROWTH    The impulse from a saturated burden on one sector is
#                  0.05-0.60 %/yr, the same band (c) held the subsidy to. A rule
#                  on one sector must no more out-punch a whole budget than a
#                  subsidy to one firm may.
#
#   (P8) REDUNDANCY  Neither beta may set the other's outcome. If moving one
#                  changes nothing the other has not already decided, the loser is
#                  DELETED rather than left unused -- U6a's precedent, and V1.4a's
#                  own flat-rival-floor finding in a third place.
#
#   (P9) DOMINANCE  No authored law strictly dominates another, and a deregulation
#                  stack from month 1 must not be a free opening. Fixed in the
#                  CONTENT if it fires, not in a constant -- V1.3d's precedent.

const REG_JOBS_CANDIDATES := [0.05, 0.10, 0.20, 0.40]
const REG_GROWTH_CANDIDATES := [0.05, 0.10, 0.20, 0.40]


func _business_laws() -> Array:
	var out: Array = []
	for law in _loader.laws:
		if law.theme == "business":
			out.append(law)
	return out


func _law(law_id: String):
	for law in _loader.laws:
		if law.id == law_id:
			return law
	return null


## Sets one sector's burden directly. The probe measures the MODEL, not the
## assembly: which laws pass is tests/test_legislature.gd's subject, and a sweep
## whose rows depended on a vote going one way would be measuring two things.
func _burden(ns, sector: String, value: float) -> void:
	ns.regulation_burden[sector] = value


func _named_payroll(nation_id: String, sector: String) -> float:
	var total := 0.0
	for company in Companies.firms_in_sector(_loader, nation_id, sector):
		total += company.headcount
	return total


# --- (g) P6: the kill switch, on the other channel --------------------------------

func _table_g_regulation_jobs() -> void:
	print("\n=== (g) P6 KILL SWITCH: unemployment points from a saturated burden ===")
	print("     floor 0.05 pts. standing prediction: agriculture cannot clear it.")
	print("%-4s %-12s %6s %12s %12s %12s" % [
		"nat", "sector", "beta", "named jobs", "shed", "unemp pts",
	])

	var best_by_beta := {}
	for beta in REG_JOBS_CANDIDATES:
		var best := 0.0
		for nation_id in PLAYABLE:
			for sector in EK.SECTOR_TREND.keys():
				var state = _new_state(nation_id)
				var ns = state.player()
				_burden(ns, String(sector), K.REGULATION_BURDEN_MAX)
				# The factor is linear in beta, so the shipped model is read once and
				# scaled -- sweeping a const would mean editing the file per row.
				var payroll: float = _named_payroll(nation_id, String(sector))
				var shed: float = payroll * beta * K.REGULATION_BURDEN_MAX
				var points: float = 100.0 * shed / Demography.labour_force(ns)
				if points > best:
					best = points
				if is_equal_approx(beta, K.REGULATION_JOBS_BETA):
					print("%-4s %-12s %6.2f %12.0f %12.0f %12.4f" % [
						nation_id, sector, beta, payroll, shed, points,
					])
		best_by_beta[beta] = best

	print("\n%6s %12s %s" % ["beta", "best pts", "verdict"])
	for beta in REG_JOBS_CANDIDATES:
		print("%6.2f %12.4f %s%s" % [
			beta, best_by_beta[beta],
			"in band" if float(best_by_beta[beta]) >= 0.05 else "BELOW FLOOR",
			"   <-- shipped" if is_equal_approx(beta, K.REGULATION_JOBS_BETA) else "",
		])

	# And the clamp, which V1.4a measured slack for the subsidy and which a burden
	# reaches from the other direction.
	var worst = _new_state("FRA")
	for sector in EK.SECTOR_TREND.keys():
		_burden(worst.player(), String(sector), K.REGULATION_BURDEN_MAX)
	Companies.tick_month(worst, _loader)
	print("     worst reachable jobs offset %.4f against clamp %.3f -- %s" % [
		absf(worst.player().firm_jobs_offset_pct), K.FIRM_JOBS_MAX_PCT,
		"SLACK" if absf(worst.player().firm_jobs_offset_pct) < K.FIRM_JOBS_MAX_PCT else "BINDING",
	])


# --- (h) P7: what a burden costs in growth ---------------------------------------

func _table_h_regulation_growth() -> void:
	print("\n=== (h) P7: growth given up by a saturated burden, %/yr ===")
	print("     band 0.05-0.60 %/yr, the same one (c) held the subsidy to")
	print("%-4s %-12s %10s %12s %12s" % ["nat", "sector", "named %GDP", "beta", "%/yr"])

	var best_by_beta := {}
	for beta in REG_GROWTH_CANDIDATES:
		best_by_beta[beta] = 0.0

	for nation_id in PLAYABLE:
		for sector in EK.SECTOR_TREND.keys():
			var state = _new_state(nation_id)
			var ns = state.player()
			var named_gdp := 0.0
			for company in Companies.firms_in_sector(_loader, nation_id, String(sector)):
				named_gdp += Companies.output_eur_bn(ns, company) / ns.gdp_eur_bn
			for beta in REG_GROWTH_CANDIDATES:
				var cost: float = beta * K.REGULATION_BURDEN_MAX * named_gdp / K.GDP_SHARE_REFERENCE
				if cost > float(best_by_beta[beta]):
					best_by_beta[beta] = cost
				if is_equal_approx(beta, K.REGULATION_GROWTH_BETA):
					print("%-4s %-12s %10.4f %12.2f %12.4f" % [
						nation_id, sector, named_gdp, beta, cost,
					])

	print("\n%6s %12s %s" % ["beta", "worst %/yr", "verdict"])
	for beta in REG_GROWTH_CANDIDATES:
		var v: float = float(best_by_beta[beta])
		var verdict := "in band"
		if v < 0.05:
			verdict = "BELOW FLOOR"
		elif v > 0.60:
			verdict = "TOO LARGE"
		print("%6.2f %12.4f %s%s" % [
			beta, v, verdict,
			"   <-- shipped" if is_equal_approx(beta, K.REGULATION_GROWTH_BETA) else "",
		])


# --- (i) P8: are the two betas telling one story? ---------------------------------

## The failure V1.4a's flat rival floor was: a constant that looks tuned while
## something else sets the outcome. Here the risk is the inverse -- two constants
## that move the same number, so one of them is decorative and should be DELETED
## rather than left unused.
##
## Measured as the RANK ORDER of the three sectors under each channel. If both
## channels rank them identically and in proportion, a player choosing which sector
## to regulate faces one decision wearing two names.
func _table_i_redundancy() -> void:
	print("\n=== (i) P8: do the two channels rank the sectors differently? ===")
	print("%-4s %-12s %12s %12s %12s" % ["nat", "sector", "growth %/yr", "unemp pts", "ratio"])

	for nation_id in PLAYABLE:
		var state = _new_state(nation_id)
		var base = state.player()
		for sector in EK.SECTOR_TREND.keys():
			var s2 = _new_state(nation_id)
			var ns = s2.player()
			_burden(ns, String(sector), K.REGULATION_BURDEN_MAX)
			Companies.tick_month(s2, _loader)
			var g: float = absf(ns.firm_impulse_pct)
			var j: float = absf(ns.firm_jobs_offset_pct)
			print("%-4s %-12s %12.4f %12.4f %12.2f" % [
				nation_id, sector, g, j, (g / j) if j > 0.0 else INF,
			])
		# base is read only to keep the loop honest about which state is which.
		if base == null:
			return
	print("     a CONSTANT ratio down a nation's three rows means one decision, two names.")


# --- (j) P9: is a deregulation stack a free opening? ------------------------------

func _table_j_dominance() -> void:
	print("\n=== (j) P9: every business law stacked from month 1 (FRA, %d months) ===" % TERM_MONTHS)

	var quiet = _new_state("FRA")
	var regulated = _new_state("FRA")
	var freed = _new_state("FRA")
	for law in _business_laws():
		var burden: Dictionary = law.effects.get("company", {})
		if float(burden.get("burden", 0.0)) > 0.0:
			Legislature.apply(regulated, regulated.player(), law, _loader)
		else:
			Legislature.apply(freed, freed.player(), law, _loader)

	for _m in range(TERM_MONTHS):
		for s in [quiet, regulated, freed]:
			Economy.tick_month(s)
			Budget.tick_month(s)
			Opinion.tick_month(s)
			Companies.tick_month(s, _loader)

	print("%-14s %10s %12s %12s" % ["", "quiet", "regulated", "deregulated"])
	for bloc in OK.BLOC_KEYS:
		print("%-14s %10.2f %12.2f %12.2f" % [
			bloc, quiet.player().bloc_approval[bloc],
			regulated.player().bloc_approval[bloc], freed.player().bloc_approval[bloc],
		])
	print("%-14s %10.2f %12.2f %12.2f  (noise floor +-3.0)" % [
		"HEADLINE", quiet.player().overall_approval_pct,
		regulated.player().overall_approval_pct, freed.player().overall_approval_pct,
	])
	for row in [["GDP bn", "gdp_eur_bn"], ["unemployment", "unemployment_pct"]]:
		print("%-14s %10.2f %12.2f %12.2f" % [
			row[0], quiet.player().get(row[1]),
			regulated.player().get(row[1]), freed.player().get(row[1]),
		])
	print("     a deregulated column better than quiet on EVERY row is a free opening.")

	# The accumulated bloc_offset against the clamp legislature_constants has always
	# carried. A stack that saturates it is the clamp-sets-the-number failure in a
	# channel V1.1 built, so the worst reachable value is MEASURED here rather than
	# assumed slack -- this project has now found that failure three times.
	var worst := 0.0
	var worst_bloc := ""
	for s in [regulated, freed]:
		for bloc in OK.BLOC_KEYS:
			var v: float = absf(float(s.player().bloc_offset.get(bloc, 0.0)))
			if v > worst:
				worst = v
				worst_bloc = bloc
	print("     worst accumulated bloc_offset: %s at %.3f against clamp %.2f -- %s" % [
		worst_bloc, worst, 1.0, "SLACK" if worst < 1.0 else "BINDING",
	])


# --- (k) P9: does any authored law strictly dominate another? ---------------------

## Cost against buy, one row per law. Two laws with the same buy at different costs
## is the strictly-dominated shape V1.3c, V1.3d and V1.4a each hit; the fix is
## content, and this table is where it is visible.
##
## THE BUY COLUMN IS SIZE-WEIGHTED, and the first draft of this table was not --
## which made financial_deregulation read as the best row on both axes when its
## unweighted sum hid a charge on pensioners, 0.24 of the electorate, paid for with
## a gift to business, 0.10 of it. A raw sum over blocs is a sum over unequal
## things, and reading a decision off one is the failure this file exists to catch.
func _table_k_content() -> void:
	print("\n=== (k) P9: cost against buy, per authored law (FRA) ===")
	print("%-26s %-12s %8s %10s %10s %12s %8s" % [
		"law", "sector", "burden", "%/yr", "unemp pts", "buy (wtd)", "trend",
	])

	for law in _business_laws():
		var state = _new_state("FRA")
		var ns = state.player()
		Legislature.apply(state, ns, law, _loader)
		Companies.tick_month(state, _loader)
		var weighted := 0.0
		for bloc in law.effects.get("bloc_offset", {}).keys():
			weighted += float(law.effects["bloc_offset"][bloc]) * float(OK.BLOC_SIZE[bloc])
		# The trend column exists because competition_enforcement's whole buy is
		# `potential_growth_pct` and a table without it reads that law as pure cost.
		print("%-26s %-12s %8.2f %10.4f %10.4f %+12.4f %8.2f" % [
			law.id, law.effects["company"]["sector"], law.effects["company"]["burden"],
			ns.firm_impulse_pct, ns.firm_jobs_offset_pct, weighted,
			float(law.effects.get("potential_growth_pct", 0.0)),
		])
	print("     domination is only meaningful WITHIN one sector: two rules on different")
	print("     sectors are not substitutes, because the sector decides which of the")
	print("     player's own subsidised firms the rule reaches.")


# =================================================================================
# V1.4c: ownership
# =================================================================================
#
# Six more pre-committed bands, written before these sweeps ran:
#
#   (P10) PRICE    The debt jump from nationalising the largest firm in the register
#                  is 2-8 points of debt-to-GDP. The purchase must be able to matter
#                  against the bloc's own `debt_to_gdp_pct` rule without breaching it
#                  from a single act.
#
#   (P11) DIVIDEND The line a wholly nationalised champion pays is 0.05-0.40 % of
#                  GDP -- the band SUBSIDY_COST_PCT_GDP sits in, and appreciably
#                  under the ~0.50 one point of income tax is worth.
#
#   (P12) FISCAL   *** NON-DOMINATION ***. Neither verb may be free on both axes. If
#                  nationalising is fiscally positive AND politically positive, the
#                  shape is strictly dominated -- and the fix is CONTENT, not a
#                  constant, which is V1.3d's precedent and V1.4b's table (j).
#
#   (P13) SHIELD   *** KILL SWITCH ***. The jobs shield reaches >= 0.05 points of
#                  unemployment, V1.4b's own floor. STANDING PREDICTION written in
#                  advance: agriculture cannot clear it, for exactly the reason
#                  V1.4b's table (g) measured. Recorded as a bound if it fails.
#
#   (P14) APPROVAL Reported, not banded, and the expectation is V1.4a's and V1.3a's
#                  for the sixth time: the headline does not clear +-3.0 while the
#                  workers and business rows plainly do.
#
#   (P15) ISSUE_KEYS  The call V1.4a, V1.4b and the whole V1.3 block deferred here.
#                  Five tests, four of them V1.3d's and the fifth forced by V1.4b.
#                  Measured before it is decided, the same way V1.3d measured it.

## Swept for (P10). A revenue multiple: 1.0 means a firm is worth one year of what
## it sells.
const PRICE_CANDIDATES := [0.50, 1.00, 2.00, 3.00]

## Swept for (P11).
const YIELD_CANDIDATES := [0.02, 0.04, 0.06, 0.10]

## The candidate thirteenth row, for (P15). Sized against `europe`'s: a mechanic
## that divides the country the way membership does, weighted heaviest on the two
## blocs the authored bloc_offset already splits hardest.
const OWNERSHIP_CANDIDATE := {
	"workers": 0.10, "pensioners": 0.06, "urban": 0.07,
	"rural": 0.05, "business": 0.14, "students": 0.05,
}

## A second candidate, leaning on business as little as the mechanic can bear. Here
## to test whether the dilution the first one causes is a property of THE CANDIDATE
## or of the mechanic: business carries `public_finances` at 0.34, which is where
## S10's ratio lives, and ownership is divisive precisely because business cares.
const OWNERSHIP_CANDIDATE_LIGHT := {
	"workers": 0.10, "pensioners": 0.06, "urban": 0.07,
	"rural": 0.05, "business": 0.04, "students": 0.05,
}


func _ownership_action(op: String):
	var best = null
	for a in _loader.company_actions:
		if String(a.effects.get("company", {}).get("op", "")) != op:
			continue
		if op == "privatise":
			return a
		if best == null or float(a.effects["company"]["stake"]) > float(best.effects["company"]["stake"]):
			best = a
	return best


# --- (l) P10: what a firm is worth, and what buying it does to the debt ------------

func _table_l_valuation() -> void:
	print("\n=== (l) P10: firm valuations and the debt jump from buying one ===")
	print("     band 2-8 points of debt-to-GDP for the largest firm. shipped multiple: %s" % str(K.PRICE_TO_OUTPUT))
	print("%-4s %-22s %10s %10s %12s" % ["nat", "firm", "bn/yr", "value bn", "debt pts"])

	for nation_id in PLAYABLE:
		var state = _new_state(nation_id)
		var ns = state.player()
		for company in Companies.firms_of(_loader, nation_id):
			var out: float = Companies.output_eur_bn(ns, company)
			print("%-4s %-22s %10.1f %10.1f %12.2f" % [
				nation_id, company.id.substr(4), out, out * K.PRICE_TO_OUTPUT,
				100.0 * out * K.PRICE_TO_OUTPUT / ns.gdp_eur_bn,
			])

	print("\n%-10s %10s %10s %10s %s" % ["multiple", "FRA", "DEU", "GBR", "verdict"])
	for multiple in PRICE_CANDIDATES:
		var jumps: Array[float] = []
		for nation_id in PLAYABLE:
			var state = _new_state(nation_id)
			var ns = state.player()
			var target := _largest(state, ns)
			var out := 0.0
			for company in Companies.firms_of(_loader, nation_id):
				if company.id == target:
					out = Companies.output_eur_bn(ns, company)
			jumps.append(100.0 * out * multiple / ns.gdp_eur_bn)
		var worst: float = jumps.min()
		var best: float = jumps.max()
		var verdict := "in band"
		if best < 2.0:
			verdict = "INVISIBLE"
		elif worst > 8.0:
			verdict = "TOO LARGE"
		elif worst < 2.0 or best > 8.0:
			verdict = "split"
		print("%-10s %10.2f %10.2f %10.2f %s%s" % [
			str(multiple), jumps[0], jumps[1], jumps[2], verdict,
			"   <-- shipped" if is_equal_approx(multiple, K.PRICE_TO_OUTPUT) else "",
		])


# --- (m) P11: what owning it pays -------------------------------------------------

func _table_m_dividend() -> void:
	print("\n=== (m) P11: the dividend line for a wholly nationalised champion, %% of GDP ===")
	print("     band 0.05-0.40 %% of GDP. one income-tax point is ~0.50. shipped yield: %s" % str(K.DIVIDEND_YIELD))
	print("%-10s %10s %10s %10s %s" % ["yield", "FRA", "DEU", "GBR", "verdict"])

	for y in YIELD_CANDIDATES:
		var lines: Array[float] = []
		for nation_id in PLAYABLE:
			var state = _new_state(nation_id)
			var ns = state.player()
			var target := _largest(state, ns)
			var out := 0.0
			for company in Companies.firms_of(_loader, nation_id):
				if company.id == target:
					out = Companies.output_eur_bn(ns, company)
			lines.append(100.0 * out * y / ns.gdp_eur_bn)
		var worst: float = lines.min()
		var best: float = lines.max()
		var verdict := "in band"
		if best < 0.05:
			verdict = "BELOW FLOOR"
		elif worst > 0.40:
			verdict = "TOO LARGE"
		elif worst < 0.05 or best > 0.40:
			verdict = "split"
		print("%-10s %10.4f %10.4f %10.4f %s%s" % [
			str(y), lines[0], lines[1], lines[2], verdict,
			"   <-- shipped" if is_equal_approx(y, K.DIVIDEND_YIELD) else "",
		])

	# The whole register at once, against the clamp. V1.4a's bill clamp came back
	# slack and this is the same measurement on the other side of the budget.
	var state = _new_state("FRA")
	var ns = state.player()
	var buy = _ownership_action("nationalise")
	for company in Companies.firms_of(_loader, "FRA"):
		Companies.execute(state, ns, _loader.company_actions, buy, company.id, _loader, true)
	Companies.tick_month(state, _loader)
	print("     THREE ROWS PASS, so this band did not choose the constant -- it measures")
	print("     whether the line is READABLE, not whether it is right. Table (n) chose.")
	print("     whole FRA register nationalised: %.3f%% of GDP against clamp %.2f -- %s" % [
		ns.dividend_revenue_pct_gdp, K.DIVIDEND_MAX_PCT_GDP,
		"SLACK" if ns.dividend_revenue_pct_gdp < K.DIVIDEND_MAX_PCT_GDP else "BINDING",
	])
	print("     ...and it cost %.1f points of debt-to-GDP to get there." % [
		100.0 * (ns.debt_eur_bn - _new_state("FRA").player().debt_eur_bn) / ns.gdp_eur_bn
	])


# --- (n) P12: the fiscal identity, and whether either verb is free -----------------

## THE WHOLE FISCAL SHAPE OF THE SESSION IS TWO CONSTANTS AGAINST A THIRD, and this
## table is where that is visible rather than asserted. The yield ON PRICE is
## DIVIDEND_YIELD / PRICE_TO_OUTPUT; above economy_constants.DEBT_REAL_RATE_PCT,
## nationalising is a slow fiscal gain bought with an instant debt-to-GDP spike, and
## privatising is the mirror. Neither may be free on BOTH axes -- the politics is
## table (p) and this is the money.
func _table_n_fiscal() -> void:
	print("\n=== (n) P12 NON-DOMINATION: the fiscal identity of one nationalisation ===")
	print("     real rate on the debt that buys it: %s %%/yr" % str(EK.DEBT_REAL_RATE_PCT))
	print("     yield on price = DIVIDEND_YIELD / PRICE_TO_OUTPUT = %.2f %%" % (
		100.0 * K.DIVIDEND_YIELD / K.PRICE_TO_OUTPUT
	))
	print("%-4s %-22s %10s %10s %12s %12s %10s" % [
		"nat", "firm", "price bn", "div bn/yr", "interest bn", "net bn/yr", "payback yr",
	])

	for nation_id in PLAYABLE:
		var state = _new_state(nation_id)
		var ns = state.player()
		var target := _largest(state, ns)
		for company in Companies.firms_of(_loader, nation_id):
			if company.id != target:
				continue
			var out: float = Companies.output_eur_bn(ns, company)
			var price: float = out * K.PRICE_TO_OUTPUT
			var div: float = out * K.DIVIDEND_YIELD
			var interest: float = price * EK.DEBT_REAL_RATE_PCT / 100.0
			print("%-4s %-22s %10.1f %10.2f %12.2f %+12.2f %10.1f" % [
				nation_id, company.id.substr(4), price, div, interest, div - interest,
				price / div if div > 0.0 else 0.0,
			])

	var on_price: float = 100.0 * K.DIVIDEND_YIELD / K.PRICE_TO_OUTPUT
	var sign_note := "NEUTRAL"
	if on_price > EK.DEBT_REAL_RATE_PCT + 0.0001:
		sign_note = "POSITIVE"
	elif on_price < EK.DEBT_REAL_RATE_PCT - 0.0001:
		sign_note = "NEGATIVE"
	print("     nationalising is fiscally %s as a FLOW and costs the whole debt jump at" % sign_note)
	print("     once as a STOCK; privatising is the mirror and is the only lever in the")
	print("     game that moves a stock back down. Whether that is a DOMINATED shape is")
	print("     table (p)'s question: a verb free on the money AND on the politics is the")
	print("     failure V1.3c, V1.3d, V1.4a and V1.4b each hit -- and the first draft of")
	print("     this session hit it too, at a yield of 0.04.")


# --- (o) P13: the kill switch on the jobs shield -----------------------------------

## ROW 14's answer, measured. A state holding cancels the compliance factor in
## Companies.headcount(), so its size at full ownership is EXACTLY V1.4b's own jobs
## price read from the other side -- there is no new constant here at all, which is
## why this table confirms an identity through the live model rather than sweeping.
func _table_o_shield() -> void:
	print("\n=== (o) P13 KILL SWITCH: unemployment points saved by a state holding ===")
	print("     floor 0.05 pts, V1.4b's own. standing prediction: agriculture cannot clear it.")
	print("%-4s %-12s %12s %12s %12s" % ["nat", "sector", "private pts", "public pts", "saved"])

	var best := 0.0
	var best_row := ""
	var buy = _ownership_action("nationalise")
	for nation_id in PLAYABLE:
		for sector in EK.SECTOR_TREND.keys():
			var exposed = _new_state(nation_id)
			_burden(exposed.player(), String(sector), K.REGULATION_BURDEN_MAX)
			Companies.tick_month(exposed, _loader)

			var sheltered = _new_state(nation_id)
			_burden(sheltered.player(), String(sector), K.REGULATION_BURDEN_MAX)
			for company in Companies.firms_in_sector(_loader, nation_id, String(sector)):
				Companies.execute(
					sheltered, sheltered.player(), _loader.company_actions, buy, company.id, _loader, true
				)
			Companies.tick_month(sheltered, _loader)

			var saved: float = exposed.player().firm_jobs_offset_pct - sheltered.player().firm_jobs_offset_pct
			if saved > best:
				best = saved
				best_row = "%s %s" % [nation_id, sector]
			print("%-4s %-12s %12.4f %12.4f %12.4f" % [
				nation_id, sector, exposed.player().firm_jobs_offset_pct,
				sheltered.player().firm_jobs_offset_pct, saved,
			])

	print("     best: %s at %.4f pts -- %s" % [
		best_row, best,
		"CLEARS the floor" if best >= 0.05 else "BELOW THE FLOOR, recorded as a bound",
	])

	# And the other direction, which is what stops the shield being free: a public
	# firm in a DEREGULATED sector gives up the hiring the deregulation would bring.
	var freed = _new_state("FRA")
	_burden(freed.player(), "industry", -K.REGULATION_BURDEN_MAX)
	Companies.tick_month(freed, _loader)
	var private_gain: float = freed.player().firm_jobs_offset_pct
	for company in Companies.firms_in_sector(_loader, "FRA", "industry"):
		Companies.execute(freed, freed.player(), _loader.company_actions, buy, company.id, _loader, true)
	Companies.tick_month(freed, _loader)
	print("     FRA industry deregulated: %.4f pts in private hands, %.4f in public --" % [
		private_gain, freed.player().firm_jobs_offset_pct,
	])
	print("     the shield is SIGNED, so it forgoes as well as protects.")


# --- (p) P14: what ownership costs politically --------------------------------------

func _table_p_approval() -> void:
	print("\n=== (p) P14: approval after %d months -- quiet, nationalised, sold (FRA) ===" % TERM_MONTHS)

	var quiet = _new_state("FRA")
	var held = _new_state("FRA")
	var sold = _new_state("FRA")
	var buy = _ownership_action("nationalise")
	var sell = _ownership_action("privatise")
	for s in [held, sold]:
		Companies.execute(s, s.player(), _loader.company_actions, buy, _largest(s, s.player()), _loader, true)

	for m in range(TERM_MONTHS):
		for s in [quiet, held, sold]:
			Economy.tick_month(s)
			Budget.tick_month(s)
			Opinion.tick_month(s)
			Companies.tick_month(s, _loader)
		# Sold a year in, so the column carries the purchase AND the sale -- which is
		# the only way to reach a privatisation at all, since a state that never
		# nationalised has nothing to sell.
		if m == 11:
			Companies.execute(
				sold, sold.player(), _loader.company_actions, sell,
				_largest(sold, sold.player()), _loader, true
			)

	print("%-14s %10s %12s %10s %12s" % ["bloc", "quiet", "nationalised", "sold", "held delta"])
	for bloc in OK.BLOC_KEYS:
		var a: float = float(quiet.player().bloc_approval[bloc])
		var b: float = float(held.player().bloc_approval[bloc])
		var c: float = float(sold.player().bloc_approval[bloc])
		print("%-14s %10.2f %12.2f %10.2f %+12.2f" % [bloc, a, b, c, b - a])
	print("%-14s %10.2f %12.2f %10.2f %+12.2f  (noise floor +-3.0)" % [
		"HEADLINE", quiet.player().overall_approval_pct, held.player().overall_approval_pct,
		sold.player().overall_approval_pct,
		held.player().overall_approval_pct - quiet.player().overall_approval_pct,
	])
	for row in [["deficit", "deficit_pct_gdp"], ["debt ratio", "debt_to_gdp_pct"], ["unemployment", "unemployment_pct"], ["GDP bn", "gdp_eur_bn"]]:
		var a: float = (
			quiet.player().debt_to_gdp_pct() if row[1] == "debt_to_gdp_pct"
			else float(quiet.player().get(row[1]))
		)
		var b: float = (
			held.player().debt_to_gdp_pct() if row[1] == "debt_to_gdp_pct"
			else float(held.player().get(row[1]))
		)
		var c: float = (
			sold.player().debt_to_gdp_pct() if row[1] == "debt_to_gdp_pct"
			else float(sold.player().get(row[1]))
		)
		print("%-14s %10.2f %12.2f %10.2f" % [row[0], a, b, c])
	print("     a column better than quiet on EVERY row is a free opening.")


# --- (q) P15: the ISSUE_KEYS call ---------------------------------------------------

## THE CALL a, b AND THE WHOLE V1.3 BLOCK DEFERRED HERE. Four of V1.3d's five tests
## are reproduced from tools/bloc_probe.gd table (a); the fifth is new and is the one
## most likely to decide it, because a REGULATION has V1.3d's tests 1 and 3 identically
## and V1.4b did not take a key.
func _table_q_issue_keys() -> void:
	print("\n=== (q) P15: what a THIRTEENTH issue would cost the twelve that are measured ===")
	print("     candidate `ownership` row: %s" % str(OWNERSHIP_CANDIDATE))
	print("%-12s %8s %12s %14s" % ["bloc", "size", "ownership w", "scale on rest"])
	for bloc in OK.BLOC_KEYS:
		var base: Dictionary = OK.BLOC_SALIENCE_BASE[bloc]
		var before_sum := 0.0
		for issue in base:
			before_sum += float(base[issue])
		var w: float = float(OWNERSHIP_CANDIDATE[bloc])
		print("%-12s %8.2f %12.3f %14.4f" % [bloc, float(OK.BLOC_SIZE[bloc]), w, before_sum / (before_sum + w)])

	var before := _national_agenda(false, OWNERSHIP_CANDIDATE)
	var after := _national_agenda(true, OWNERSHIP_CANDIDATE)

	print("\n%-18s %12s %12s %12s" % ["issue", "before", "after", "change"])
	var keys: Array = OK.ISSUE_KEYS.duplicate()
	keys.append("ownership")
	for issue in keys:
		print("%-18s %12.4f %12.4f %+12.4f" % [
			issue, float(before.get(issue, 0.0)), float(after.get(issue, 0.0)),
			float(after.get(issue, 0.0)) - float(before.get(issue, 0.0)),
		])

	var spending: Array = ["health", "education", "defence", "pensions", "infrastructure"]
	var pf_b: float = float(before["public_finances"])
	var pf_a: float = float(after["public_finances"])
	var sp_b := 0.0
	var sp_a := 0.0
	for issue in spending:
		sp_b += float(before[issue])
		sp_a += float(after[issue])
	print("\nTHE S10 RATIO -- public_finances : the five spending lines")
	print("  before  %.4f : %.4f  =  %.4f" % [pf_b, sp_b, pf_b / sp_b])
	print("  after   %.4f : %.4f  =  %.4f" % [pf_a, sp_a, pf_a / sp_a])
	print("  drift   %+.4f%% of the ratio (V1.3d's own move was +0.39%%)" % (
		100.0 * ((pf_a / sp_a) / (pf_b / sp_b) - 1.0)
	))
	print("  `ownership` would take %.4f of the national agenda." % float(after["ownership"]))

	# Is the drift the CANDIDATE's or the MECHANIC's? Business carries
	# `public_finances` at 0.34, which is where S10's ratio lives, and ownership is
	# divisive precisely because business cares. A row that leans on business less
	# dilutes less -- and expresses less.
	var light := _national_agenda(true, OWNERSHIP_CANDIDATE_LIGHT)
	var sp_l := 0.0
	for issue in spending:
		sp_l += float(light[issue])
	print("  with business at 0.04 instead of 0.14 the drift is %+.4f%% -- so the" % (
		100.0 * ((float(light["public_finances"]) / sp_l) / (pf_b / sp_b) - 1.0)
	))
	print("  dilution is the BUSINESS WEIGHT's, and the business weight is the mechanic.")

	# TEST 2, measured: is the price already legible on a bloc row without a key?
	# TEST 5, the new one: state ownership as a share of GDP is a single standing
	# stock; a regulation burden is a per-sector rule with no aggregate. Whether that
	# survives is a write-up question, and the number below is what it is weighed
	# against -- how much of the economy the verb can actually move.
	var full = _new_state("FRA")
	var ns = full.player()
	var buy = _ownership_action("nationalise")
	for company in Companies.firms_of(_loader, "FRA"):
		Companies.execute(full, ns, _loader.company_actions, buy, company.id, _loader, true)
	Companies.tick_month(full, _loader)
	var owned := 0.0
	for company in Companies.firms_of(_loader, "FRA"):
		owned += Companies.state_share_of(ns, company.id) * Companies.output_eur_bn(ns, company)
	print("\n  the WHOLE reachable stock: %.2f%% of GDP in public hands." % (100.0 * owned / ns.gdp_eur_bn))
	print("  compare V1.4b's finding that this layer's own channels move growth ~0.1 %%/yr")
	print("  and unemployment ~0.02 pts -- BELOW the opinion model's resolution. An issue")
	print("  whose satisfaction cannot clear resolution is a row of zeroes on the polling")
	print("  panel, which is worse than no row at all.")


## opinion.gd's own roll-up at rest, rebuilt locally: at zero satisfaction
## salience_weights() is the base row renormalised, and the national agenda is the
## size-weighted sum. tools/bloc_probe.gd table (a) rebuilds it the same way and for
## the same reason -- neither table needs a game or a nation.
func _national_agenda(with_ownership: bool, candidate: Dictionary) -> Dictionary:
	var out := {}
	for bloc in OK.BLOC_KEYS:
		var row: Dictionary = (OK.BLOC_SALIENCE_BASE[bloc] as Dictionary).duplicate()
		if with_ownership:
			row["ownership"] = float(candidate[bloc])
		var total := 0.0
		for issue in row:
			total += float(row[issue])
		for issue in row:
			out[issue] = float(out.get(issue, 0.0)) + float(OK.BLOC_SIZE[bloc]) * float(row[issue]) / total
	return out


# --- (r) redundancy: are the two constants one decision wearing two names? ----------

## U6a's precedent: a constant the probe cannot distinguish from another is DELETED,
## not left unused. These two multiply into one ratio for the fiscal SIGN, which is
## the case for suspecting them -- so the table has to show they separate somewhere
## else, or one of them goes and the survivor is expressed as a payback period.
func _table_r_redundancy() -> void:
	print("\n=== (r) redundancy: PRICE_TO_OUTPUT against DIVIDEND_YIELD ===")
	print("     rows sharing a RATIO share a fiscal sign. If they share everything")
	print("     else too, one of them is deleted.")
	print("%-10s %10s %12s %12s %12s" % ["multiple", "yield", "debt pts", "div %GDP", "payback yr"])

	var state = _new_state("FRA")
	var ns = state.player()
	var target := _largest(state, ns)
	var out := 0.0
	for company in Companies.firms_of(_loader, "FRA"):
		if company.id == target:
			out = Companies.output_eur_bn(ns, company)

	# Three pairs on ONE ratio, so the fiscal sign is identical down the column and
	# anything that still moves is what keeps both constants.
	for pair in [[0.50, 0.01], [1.00, 0.02], [2.00, 0.04], [3.00, 0.06]]:
		var multiple: float = pair[0]
		var y: float = pair[1]
		print("%-10s %10s %12.2f %12.4f %12.1f" % [
			str(multiple), str(y), 100.0 * out * multiple / ns.gdp_eur_bn,
			100.0 * out * y / ns.gdp_eur_bn, multiple / y,
		])
	print("     the ratio -- and therefore the payback and the fiscal sign -- is fixed")
	print("     down that column while the debt jump moves 6x and the dividend line with")
	print("     it. The price hits debt-to-GDP ONCE and the yield hits the budget")
	print("     FOREVER, so they are two decisions and both are kept.")
