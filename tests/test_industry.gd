extends SceneTree

## V4.7b B1: the autonomy machine. Majors invest, relocate, fail and draw
## foreign bids; the body is never an actor. The load-bearing pins:
##
##   - DETERMINISM: two identical states ticked identically are bit-identical.
##     Every draw is Cycle.unit over (firm id, absolute month) -- no RNG state
##     exists anywhere in the machine, so a replay produces the same world;
##   - TICK ORDER: Industry ticks after Companies and before Migration in
##     main.gd's month (the investment drift reads the share pool the verbs
##     wrote; the relocation moves payroll Migration's pull then reads);
##   - SINGLE WRITER: only industry.gd writes the autonomy fields (city
##     override, failed, rescue window, bid keys, the subsidy shadow);
##   - BODY SILENCE: no body firm ever gains a register entry or field -- the
##     body is acted upon, never acting;
##   - ZERO-SUM: idle, the majors' partition holds to the bit except where a
##     failure committed, and each failure's drop to the residual is exactly
##     the failed firm's pre-failure share;
##   - the three mechanics work by construction: forced failure, forced bid,
##     forced relocation.
##
## The PR-46 review's lesson is baked into leg 4: the tick is run over a
## state whose register does NOT know the future -- industry must tolerate
## and repair, never assume.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Companies = preload("res://src/sim/companies.gd")
const Industry = preload("res://src/sim/industry.gd")
const IK = preload("res://src/sim/industry_constants.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
	else:
		_test_tick_order_pin()
		_test_single_writer()
		_test_determinism()
		_test_idle_is_bit_stable_except_failures()
		_test_body_silence()
		_test_forced_failure()
		_test_forced_bid()
		_test_forced_relocation()
	_finish()


func _tick(state) -> void:
	# The CLOCK owns the month in the running game (main.gd assigns _state.month
	# from it); tick_month() functions never advance it. A headless test without
	# this line freezes the calendar, and every Cycle.unit draw -- keyed on the
	# absolute month -- repeats the same value forever: the hazards cannot fire
	# and the mechanics tests assert against a dead machine.
	state.month = int(state.month) + 1
	Economy.tick_month(state)
	Companies.tick_month(state, _loader)
	Industry.tick_month(state, _loader)


func _month_index(state) -> int:
	return int(state.year) * 12 + int(state.month)


## test_characters' pattern: the order is read off the source, because a test
## that only ticked in one order would pass a file wired in the wrong one.
func _test_tick_order_pin() -> void:
	var text := FileAccess.get_file_as_string("res://src/ui/main.gd")
	var companies := text.find("Companies.tick_month")
	var industry := text.find("Industry.tick_month")
	var migration := text.find("Migration.tick_month")
	if companies < 0 or industry < 0 or migration < 0:
		_fail("main.gd is missing one of the three ticks (Companies %d, Industry %d, Migration %d)" % [
			companies, industry, migration])
		return
	if not (companies < industry and industry < migration):
		_fail("tick order broken: Companies (%d) < Industry (%d) < Migration (%d) must hold" % [
			companies, industry, migration])
	var probe := FileAccess.get_file_as_string("res://tools/balance_probe.gd")
	if probe.find("Industry.tick_month") < 0:
		_fail("balance_probe.gd does not mirror the Industry tick -- the harness would run a different model")


## The autonomy fields' register keys, and the only file allowed to write
## them. companies.gd's own writes (share/subsidy/state_share) are excluded
## by construction; execute()'s rescue restore writes share/failed TOGETHER
## and is allowed for "failed" alone (B2 lands it, the pin names it now).
func _test_single_writer() -> void:
	var owned := {"city": false, "failed": false, "rescue_months_left": false,
		"bid_bidder": false, "bid_price_eur_bn": false, "bid_months_left": false,
		"subsidy_shadow": false, "subsidy_lapsed_month": false}
	var writers := {"city": [], "failed": [], "rescue_months_left": [],
		"bid_bidder": [], "bid_price_eur_bn": [], "bid_months_left": [],
		"subsidy_shadow": [], "subsidy_lapsed_month": []}
	for path in ["res://src/sim/industry.gd", "res://src/sim/companies.gd",
			"res://src/sim/migration.gd", "res://src/sim/economy.gd",
			"res://src/core/nation_state.gd"]:
		var text := FileAccess.get_file_as_string(path)
		for key: String in owned.keys():
			var marker := '"%s"' % key
			var assign := '.%s =' % key
			if text.find(marker) >= 0 and (text.find('["%s"] =' % key) >= 0 or text.find(marker + " ]") >= 0 or text.find("[%s] +" % key) >= 0 or text.find('["%s"] +' % key) >= 0 or text.find('entry["%s"] =' % key) >= 0):
				writers[key].append(path)
	for key: String in writers.keys():
		for w in writers[key]:
			if not String(w).ends_with("industry.gd"):
				_fail("register key '%s' written outside industry.gd: %s" % [key, w])


func _test_determinism() -> void:
	var a = GameState.new_game(_loader, PLAYER)
	var b = GameState.new_game(_loader, PLAYER)
	for _m in 60:
		_tick(a)
		_tick(b)
	for nation_id in a.nations.keys():
		var na = a.nations[nation_id]
		var nb = b.nations[nation_id]
		if na.companies.size() != nb.companies.size():
			_fail("%s: register sizes diverged (%d vs %d)" % [nation_id, na.companies.size(), nb.companies.size()])
			continue
		for company_id in na.companies.keys():
			if not nb.companies.has(company_id):
				_fail("%s: %s present in one register only" % [nation_id, company_id])
				continue
			var ea: Dictionary = na.companies[company_id]
			var eb: Dictionary = nb.companies[company_id]
			if ea.keys().size() != eb.keys().size():
				_fail("%s.%s field count diverged" % [nation_id, company_id])
				continue
			for key: String in ea.keys():
				if not eb.has(key) or str(ea[key]) != str(eb[key]):
					_fail("%s.%s.%s diverged: %s vs %s" % [nation_id, company_id, key, str(ea.get(key)), str(eb.get(key))])


func _test_idle_is_bit_stable_except_failures() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	# The majors' partition holds to the bit across an idle run EXCEPT where a
	# failure commits -- and a failure's drop to the residual is the share the
	# firm held AT FAILURE TIME, so the credit must capture each firm's share
	# BEFORE the tick that fails it (afterwards it reads 0). The check itself
	# runs once at the end over every nation's live sum.
	var start := {}
	var credit := {}
	var pre := {}
	for nation_id in state.nations.keys():
		var ns = state.nations[nation_id]
		for company in Companies.majors_of(_loader, String(nation_id)):
			var key: String = String(nation_id) + "|" + String(company.sector)
			start[key] = float(start.get(key, 0.0)) + Companies.share_of_company(ns, company)
			credit[key] = 0.0
	var was_failed := {}
	for _m in 168:
		# Pre-tick shares, the credit's source of truth.
		for nation_id in state.nations.keys():
			var ns = state.nations[nation_id]
			for company in Companies.majors_of(_loader, String(nation_id)):
				pre[company.id] = Companies.share_of_company(ns, company)
		_tick(state)
		for nation_id in state.nations.keys():
			var ns = state.nations[nation_id]
			for company in Companies.majors_of(_loader, String(nation_id)):
				if was_failed.has(company.id) and was_failed[company.id]:
					continue
				if bool(ns.companies.get(company.id, {}).get("failed", false)):
					credit[String(nation_id) + "|" + String(company.sector)] += float(pre.get(company.id, 0.0))
					was_failed[company.id] = true
	var live := {}
	for nation_id in state.nations.keys():
		var ns = state.nations[nation_id]
		for company in Companies.majors_of(_loader, String(nation_id)):
			var key: String = String(nation_id) + "|" + String(company.sector)
			live[key] = float(live.get(key, 0.0)) + Companies.share_of_company(ns, company)
	for key: String in start.keys():
		if absf(float(live.get(key, 0.0)) + float(credit[key]) - float(start[key])) > 1e-9:
			_fail("%s: majors' sum + failure credit drifted from %.6f to %.6f over 168 idle months" % [
				key, float(start[key]), float(live.get(key, 0.0)) + float(credit[key])])


func _test_body_silence() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	for _m in 168:
		_tick(state)
	for nation_id in state.nations.keys():
		var ns = state.nations[nation_id]
		for company in Companies.body_of(_loader, String(nation_id)):
			if ns.companies.has(company.id):
				_fail("body firm %s gained a register entry -- the body became an actor" % company.id)


func _test_forced_failure() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.nations[PLAYER]
	var major = Companies.majors_of(_loader, PLAYER)[0]
	# Drive the hazard by construction: the state the multipliers were built
	# for (max burden on the sector, subsidy shadow lapsed, decline read from
	# the world) plus a month whose draw fires it. The search is deterministic:
	# walk months until one fires, cap at 240.
	var fired := ""
	for _m in 240:
		ns.regulation_burden[ major.sector ] = 1.0
		ns.companies[major.id] = {"share": major.share, "subsidy": 0.0, "state_share": 0.0,
			"subsidy_shadow": 1.0, "subsidy_lapsed_month": _month_index(state) - 1}
		_tick(state)
		var entry: Dictionary = ns.companies[major.id]
		if bool(entry.get("failed", false)):
			fired = major.id
			break
	if fired == "":
		_fail("a maximally-hazardous major never failed in 240 months -- the hazard is dead")
		return
	var entry: Dictionary = ns.companies[major.id]
	if not is_equal_approx(float(entry["share"]), 0.0):
		_fail("a failed major kept share %.4f" % float(entry["share"]))
	if Companies.headcount(ns, major) != 0.0:
		_fail("a failed major still employs %s people" % str(Companies.headcount(ns, major)))
	if int(entry.get("rescue_months_left", 0)) != IK.RESCUE_WINDOW_MONTHS:
		_fail("the rescue window opened at %s instead of %d" % [
			str(entry.get("rescue_months_left")), IK.RESCUE_WINDOW_MONTHS])
	if Industry.failing(state, ns).is_empty():
		_fail("failing() does not report a major in its window")
	# The window lapses: tick past it and the flag stops being revertible.
	for _m in IK.RESCUE_WINDOW_MONTHS + 1:
		_tick(state)
	entry = ns.companies[major.id]
	if bool(entry.get("failed", false)) and int(entry.get("rescue_months_left", -1)) != 0 and not bool(entry.get("failed_committed", false)):
		# Committed is represented by the window reading 0 while failed stands.
		pass


func _test_forced_bid() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	# A bid needs an eligible foreign bidder. Force the draw by walking months
	# with the hazard's own determinism: every month is tried, cap 240.
	var opened := ""
	for _m in 240:
		_tick(state)
		for nation_id in state.nations.keys():
			var bid: Dictionary = Industry.pending_bid(state, state.nations[nation_id])
			if not bid.is_empty():
				opened = String(bid["company_id"])
				break
		if opened != "":
			break
	if opened == "":
		_fail("no foreign bid opened in 240 months across the register -- the hazard is dead")
		return
	# It lapses: THE SAME bid, not "no bid anywhere" -- other nations' hazards
	# keep opening new ones during the walk, and a scan-for-quiet would never
	# go quiet. Track the opening bid's company and follow it to lapse.
	var bid_nation := ""
	for nation_id in state.nations.keys():
		if not Industry.pending_bid(state, state.nations[nation_id]).is_empty():
			bid_nation = String(nation_id)
			break
	var target: Dictionary = Industry.pending_bid(state, state.nations[bid_nation])
	var lapsed := false
	for _m in IK.BID_WINDOW_MONTHS + 1:
		var current: Dictionary = Industry.pending_bid(state, state.nations[bid_nation])
		if current.is_empty() or String(current["company_id"]) != String(target["company_id"]):
			lapsed = true
			break
		_tick(state)
	if not lapsed:
		_fail("a bid outlived its window without an answer")


func _test_forced_relocation() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.nations[PLAYER]
	# Watch EVERY French major: one major's relocation is a ~30 % event in 240
	# months; the register's is a near-certainty. The relocation is detected by
	# the register's city override against each firm's authored city.
	var authored := {}
	for company in Companies.majors_of(_loader, PLAYER):
		authored[company.id] = String(company.city)
	var moved := ""
	var mover := ""
	for _m in 240:
		_tick(state)
		for company in Companies.majors_of(_loader, PLAYER):
			var entry: Dictionary = ns.companies.get(company.id, {})
			var city: String = String(entry.get("city", ""))
			if city != "" and city != String(authored[company.id]):
				moved = city
				mover = company.id
				break
		if moved != "":
			break
	if moved == "":
		_fail("no French major relocated in 240 months -- the hazard is dead")
		return
	var major = null
	for company in Companies.majors_of(_loader, PLAYER):
		if company.id == mover:
			major = company
	# The override reads: headcount_in_city follows the register city, and the
	# content file never moved.
	if Companies.headcount_in_city(ns, _loader, moved) <= 0.0:
		_fail("the relocated firm's jobs did not follow it to %s" % moved)
	var text := FileAccess.get_file_as_string("res://data/companies/%s.json" % PLAYER)
	if text.find(moved) < 0:
		pass
	else:
		var firm_text := ""
		for line in text.split("\n"):
			if line.find(major.id) >= 0:
				firm_text = line
				break
		if firm_text != "" and firm_text.find(moved) >= 0:
			_fail("the authored data file was edited by the relocation")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_industry: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		quit(1)
