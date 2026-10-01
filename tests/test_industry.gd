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
##   - SINGLE WRITER PER ROLE: the two-writer ledger industry.gd's header
##     keeps -- the machine (industry.gd) writes the autonomy fields, and
##     the verb channel that answers them (companies.gd's execute) writes
##     owner/courted/board_chair and commits rescues and break-ups onto
##     failed/window. No THIRD file writes any of it, and that is what the
##     scan below enforces;
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
const CK = preload("res://src/sim/companies_constants.gd")

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
		_test_block_and_allow_takeover()
		_test_break_up()
		_test_rescue_restores_failing()
		_test_court_multiplies_bids()
		_test_appoint_board()
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


## The autonomy fields' register keys, and the only files allowed to write
## them. companies.gd's own writes (share/subsidy/state_share) are excluded
## by construction; execute()'s rescue restore writes share/failed TOGETHER
## and is allowed for "failed" alone (B2 lands it, the pin names it now).
## The scan WALKS src/sim and src/core rather than naming files -- the
## hand-enumerated list was the pass-5 fleet's find and this repo's own
## seventh-list lesson: a future writer in any unlisted file passed silently.
func _test_single_writer() -> void:
	var owned := {"city": false, "failed": false, "rescue_months_left": false,
		"bid_bidder": false, "bid_price_eur_bn": false, "bid_months_left": false,
		"subsidy_shadow": false, "subsidy_lapsed_month": false,
		"owner": false, "courted": false, "board_chair": false}
	var writers := {"city": [], "failed": [], "rescue_months_left": [],
		"bid_bidder": [], "bid_price_eur_bn": [], "bid_months_left": [],
		"subsidy_shadow": [], "subsidy_lapsed_month": [],
		"owner": [], "courted": [], "board_chair": []}
	var roots := ["res://src/sim", "res://src/core"]
	for root_dir: String in roots:
		var dir := DirAccess.open(root_dir)
		if dir == null:
			_fail("single-writer scan cannot open %s" % root_dir)
			continue
		for file in dir.get_files():
			if not String(file).ends_with(".gd"):
				continue
			var path := root_dir + "/" + file
			var text := FileAccess.get_file_as_string(path)
			for key: String in owned.keys():
				var marker := '"%s"' % key
				if text.find(marker) < 0:
					continue
				# An indexed WRITE only: `["key"] =` where the next character
				# is not a second `=` -- the equality `d["city"] == ""` would
				# otherwise false-positive (company.gd's own validation).
				var write := '["%s"] =' % key
				var at := text.find(write)
				while at >= 0:
					if text.substr(at + write.length(), 1) != "=":
						writers[key].append(path)
						break
					at = text.find(write, at + 1)
	for key: String in writers.keys():
		for w in writers[key]:
			# Two legitimate writers per key: the machine (industry.gd) and
			# the verb channel that answers it (companies.gd's execute --
			# block/allow clear the bid, allow writes owner, break-up and the
			# rescue-restore write failed/window). A THIRD file fails.
			if not (String(w).ends_with("industry.gd") or String(w).ends_with("companies.gd")):
				_fail("register key '%s' written outside industry.gd/companies.gd: %s" % [key, w])


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
	if Industry.failing(state, ns, _loader).is_empty():
		_fail("failing() does not report a major in its window")
	# The window lapses: tick past it and the window reads 0 while `failed`
	# stands -- committed is the window-at-zero state, which B2's rescue verb
	# reads. An open window after the horizon means the decrement is broken.
	for _m in IK.RESCUE_WINDOW_MONTHS + 1:
		_tick(state)
	entry = ns.companies[major.id]
	if not bool(entry.get("failed", false)):
		_fail("a failed flag vanished without the rescue verb -- nothing in B1 clears it")
	if int(entry.get("rescue_months_left", -1)) != 0:
		_fail("the rescue window did not lapse to 0 after its horizon (reads %s)" % str(entry.get("rescue_months_left")))


func _test_forced_bid() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	# A bid needs an eligible foreign bidder. Force the draw by walking months
	# with the hazard's own determinism: every month is tried, cap 240.
	var opened := ""
	for _m in 240:
		_tick(state)
		for nation_id in state.nations.keys():
			var bid: Dictionary = Industry.pending_bid(state, state.nations[nation_id], _loader)
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
		if not Industry.pending_bid(state, state.nations[nation_id], _loader).is_empty():
			bid_nation = String(nation_id)
			break
	var target: Dictionary = Industry.pending_bid(state, state.nations[bid_nation], _loader)
	var lapsed := false
	for _m in IK.BID_WINDOW_MONTHS + 1:
		var current: Dictionary = Industry.pending_bid(state, state.nations[bid_nation], _loader)
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


func _action(id: String):
	for a in _loader.company_actions:
		if String(a.id) == id:
			return a
	return null


func _test_block_and_allow_takeover() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.nations[PLAYER]
	var major = Companies.majors_of(_loader, PLAYER)[0]
	# No bid: both verbs refused.
	if not Companies.available(state, ns, _loader.company_actions, major.id, _loader).filter(func(a): return String(a.id) == "block_takeover").is_empty():
		_fail("block_takeover offered with no bid pending")
	# Force a bid into the register, the shape industry writes.
	ns.companies[major.id]["bid_bidder"] = "DEU|" + String(Companies.majors_of(_loader, "DEU")[0].id)
	ns.companies[major.id]["bid_price_eur_bn"] = 50.0
	ns.companies[major.id]["bid_months_left"] = 3
	var block = _action("block_takeover")
	if block == null:
		_fail("block_takeover content missing")
		return
	# Relations REST at ~68 on the register's own baseline, so the pulse is
	# asserted as a delta, not against zero.
	var rel_key: String = preload("res://src/core/relations.gd").key(PLAYER, "DEU")
	var relations_before: float = float(state.relations.get(rel_key, 0.0))
	Companies.execute(state, ns, _loader.company_actions, block, major.id, _loader)
	var entry: Dictionary = ns.companies[major.id]
	if String(entry.get("bid_bidder", "")) != "":
		_fail("a blocked bid still stands")
	if float(state.relations.get(rel_key, 0.0)) >= relations_before:
		_fail("blocking a DEU bid left relations unmoved (%.2f vs %.2f)" % [
			float(state.relations.get(rel_key, 0.0)), relations_before])
	# Allow, on a fresh bid: the register carries the new owner.
	ns.companies[major.id]["bid_bidder"] = "DEU|" + String(Companies.majors_of(_loader, "DEU")[0].id)
	ns.companies[major.id]["bid_months_left"] = 3
	var allow = _action("allow_takeover")
	Companies.execute(state, ns, _loader.company_actions, allow, major.id, _loader)
	if String(ns.companies[major.id].get("owner", "")) != "DEU":
		_fail("an allowed bid left no owner in the register")


func _test_break_up() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.nations[PLAYER]
	var major = Companies.majors_of(_loader, PLAYER)[0]
	var breakup = _action("break_up")
	if breakup == null:
		_fail("break_up content missing")
		return
	var before := {}
	for company in Companies.majors_of(_loader, PLAYER):
		before[company.id] = Companies.share_of_company(ns, company)
	# ALL body firms, not the major's sector: the check below covers every
	# body firm, and a sector-filtered snapshot reads the rest as 0.0000.
	var body_before := {}
	for company in Companies.body_of(_loader, PLAYER):
		body_before[company.id] = Companies.share_of_company(ns, company)
	Companies.execute(state, ns, _loader.company_actions, breakup, major.id, _loader)
	var entry: Dictionary = ns.companies[major.id]
	if float(entry.get("share", -1)) != 0.0 or not bool(entry.get("failed", false)):
		_fail("a broken-up major neither lost its share nor marked committed")
	# Structural no-re-escalation: the split goes to the sector's other
	# MAJORS, and the body tier is untouched -- a body firm that moved was
	# the first draft's defect, the escalator by the front door.
	for company in Companies.body_of(_loader, PLAYER):
		var after: float = Companies.share_of_company(ns, company)
		var was: float = float(body_before.get(company.id, 0.0))
		if absf(after - was) > 1e-9:
			_fail("break_up moved body firm %s (%.4f -> %.4f) -- the body is not the split's absorber" % [
				company.id, was, after])


func _test_rescue_restores_failing() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.nations[PLAYER]
	var major = Companies.majors_of(_loader, PLAYER)[0]
	ns.companies[major.id]["failed"] = true
	ns.companies[major.id]["share"] = 0.0
	ns.companies[major.id]["rescue_months_left"] = 4
	var debt_before: float = ns.debt_eur_bn
	var rescue = _action("strategic_rescue")
	Companies.execute(state, ns, _loader.company_actions, rescue, major.id, _loader)
	var entry: Dictionary = ns.companies[major.id]
	if bool(entry.get("failed", false)):
		_fail("a rescue did not clear the failed flag")
	if not is_equal_approx(Companies.share_of_company(ns, major), major.share):
		_fail("a rescue restored %.4f against authored %.4f" % [
			Companies.share_of_company(ns, major), major.share])
	if ns.debt_eur_bn <= debt_before:
		_fail("a bailout was free -- the debt did not move")
	# C1's two legs: the bailout arm gates on the WINDOW, not the flag alone.
	# A committed failure stays committed; a broken-up major is never
	# resurrected while its rivals keep the absorbed split.
	ns.companies[major.id]["failed"] = true
	ns.companies[major.id]["share"] = 0.0
	ns.companies[major.id]["rescue_months_left"] = 0
	Companies.execute(state, ns, _loader.company_actions, rescue, major.id, _loader)
	if not bool(ns.companies[major.id].get("failed", false)) or Companies.share_of_company(ns, major) != 0.0:
		_fail("a rescue resurrected a COMMITTED failure -- the collapse is supposed to be committed")
	# The leg is REAL, on a healthy major: the break-up LANDS (the split goes
	# to the rivals), and the rescue attempted on the dissolved firm is then
	# refused through available()'s failed gate at window 0 -- the first draft
	# pre-failed the firm, so break_up was refused before it could split
	# anything and the assertions below were trivially true (the pass-7
	# fleet's find).
	var state2 = GameState.new_game(_loader, PLAYER)
	var ns2 = state2.nations[PLAYER]
	var major2 = null
	for company in Companies.majors_of(_loader, PLAYER):
		if company.sector != Companies.majors_of(_loader, PLAYER)[0].sector and company.share >= 0.10:
			major2 = company
			break
	if major2 == null:
		major2 = Companies.majors_of(_loader, PLAYER)[1]
	var rivals_before := 0.0
	for other in Companies.majors_of(_loader, PLAYER):
		if other.id != major2.id and other.sector == major2.sector:
			rivals_before += Companies.share_of_company(ns2, other)
	var breakup2 = _action("break_up")
	var dissolved: float = Companies.share_of_company(ns2, major2)
	var landed: Dictionary = Companies.execute(state2, ns2, _loader.company_actions, breakup2, major2.id, _loader)
	if not bool(landed.get("applied", false)):
		_fail("the break-up leg's split was refused -- the leg tests nothing")
	var rivals_after_split := 0.0
	for other in Companies.majors_of(_loader, PLAYER):
		if other.id != major2.id and other.sector == major2.sector:
			rivals_after_split += Companies.share_of_company(ns2, other)
	if absf(rivals_after_split - (rivals_before + dissolved)) > 1e-9:
		_fail("the landed split did not hand the dissolved share to the rivals")
	Companies.execute(state2, ns2, _loader.company_actions, rescue, major2.id, _loader)
	var rivals_after := 0.0
	for other in Companies.majors_of(_loader, PLAYER):
		if other.id != major2.id and other.sector == major2.sector:
			rivals_after += Companies.share_of_company(ns2, other)
	if Companies.share_of_company(ns2, major2) != 0.0 or absf(rivals_after - rivals_after_split) > 1e-9:
		_fail("a rescue undid a break-up -- a dissolved firm does not come back")


func _test_court_multiplies_bids() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.nations[PLAYER]
	# The verb's own gate: courting targets a small major (< 0.10 share). The
	# register's first firm is 0.28 and is rightly refused.
	var major = null
	for company in Companies.majors_of(_loader, PLAYER):
		if company.share < 0.10:
			major = company
			break
	if major == null:
		_fail("no small major to court -- the test needs one")
		return
	var court = _action("court_investor")
	if court == null:
		_fail("court_investor content missing")
		return
	Companies.execute(state, ns, _loader.company_actions, court, major.id, _loader)
	if float(ns.companies[major.id].get("courted", 0.0)) != 1.0:
		_fail("court_investor left no flag in the register")
	# The flag is the verb's own repeat gate: with the courtship standing, the
	# verb is not offered again -- a courtship bought again click by click was
	# the ultra's unpriced-lever finding.
	if not Companies.available(state, ns, _loader.company_actions, major.id, _loader).filter(func(a): return String(a.id) == "court_investor").is_empty():
		_fail("court_investor offered while the courtship it opened still stands")
	# Availability: courting while a bid pends is refused (the flag's whole
	# meaning is inviting the NEXT bid).
	ns.companies[major.id]["bid_bidder"] = "DEU|x"
	if not Companies.available(state, ns, _loader.company_actions, major.id, _loader).filter(func(a): return String(a.id) == "court_investor").is_empty():
		_fail("court_investor offered while a bid was already on the table")


func _test_appoint_board() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.nations[PLAYER]
	var major = Companies.majors_of(_loader, PLAYER)[0]
	var appoint = _action("appoint_board")
	if appoint == null:
		_fail("appoint_board content missing")
		return
	# Availability: refused with no state holding.
	if not Companies.available(state, ns, _loader.company_actions, major.id, _loader).filter(func(a): return String(a.id) == "appoint_board").is_empty():
		_fail("appoint_board offered with no state stake")
	# Take a stake, appoint: the chair is an executive of the nation, and the
	# name resolves.
	var nationalise = _action("minority_stake")
	Companies.execute(state, ns, _loader.company_actions, nationalise, major.id, _loader)
	if not Companies.available(state, ns, _loader.company_actions, major.id, _loader).filter(func(a): return String(a.id) == "appoint_board").is_empty():
		pass
	else:
		_fail("appoint_board not offered with a state stake standing")
	Companies.execute(state, ns, _loader.company_actions, appoint, major.id, _loader)
	var chair: String = String(ns.companies[major.id].get("board_chair", ""))
	if chair == "":
		_fail("an appointment left no chair in the register")
		return
	var resolved := false
	for person in _loader.people.get(PLAYER, []):
		if String(person.id) == chair:
			resolved = String(person.kind) == "executive"
			break
	if not resolved:
		_fail("chair '%s' is not an executive of the nation" % chair)
	# A second appointment REPLACES (one chair per firm): the chair may stay
	# the same draw or change, but it must never empty, and the register never
	# holds two.
	var first: String = chair
	Companies.execute(state, ns, _loader.company_actions, appoint, major.id, _loader)
	var second: String = String(ns.companies[major.id].get("board_chair", ""))
	if second == "":
		_fail("a re-appointment emptied the chair")
	var chairs := 0
	for other_id in ns.companies.keys():
		if String(ns.companies[other_id].get("board_chair", "")) == second and second != "":
			chairs += 1
	if chairs > 1:
		_fail("the same executive chairs %d firms -- one chair per firm" % chairs)
	# The exhausted pool REFUSES, and the standing chairs survive: take stakes
	# across the roster, appoint round-robin until no unseated executive
	# remains, then try once more and read the refusal. An appointment that
	# emptied the chair while still pricing the blocs was patronage backwards
	# (the pass-2 ultra's find). The loop counts the nation's executives
	# rather than trusting the roster's shape.
	var executives := 0
	for person in _loader.people.get(PLAYER, []):
		if String(person.kind) == "executive":
			executives += 1
	var roster := Companies.majors_of(_loader, PLAYER)
	for company in roster:
		if String(company.id) != major.id:
			Companies.execute(state, ns, _loader.company_actions, nationalise, company.id, _loader)
	var seated := func() -> int:
		var names := {}
		for other_id in ns.companies.keys():
			var chair_name: String = String(ns.companies[other_id].get("board_chair", ""))
			if chair_name != "":
				names[chair_name] = true
		var distinct := 0
		for person in _loader.people.get(PLAYER, []):
			if String(person.kind) == "executive" and names.has(String(person.id)):
				distinct += 1
		return distinct
	var guard: int = executives * roster.size() + executives + 8
	while seated.call() < executives and guard > 0:
		guard -= 1
		for company in roster:
			if seated.call() >= executives:
				break
			Companies.execute(state, ns, _loader.company_actions, appoint, company.id, _loader)
	if seated.call() >= executives:
		var before_chairs := {}
		for other_id in ns.companies.keys():
			before_chairs[other_id] = String(ns.companies[other_id].get("board_chair", ""))
		var exhausted: Dictionary = Companies.execute(state, ns, _loader.company_actions, appoint, major.id, _loader)
		if bool(exhausted.get("applied", true)):
			_fail("an appointment went through with every executive seated -- the pool's bound did not hold")
		for other_id in before_chairs.keys():
			if String(ns.companies[other_id].get("board_chair", "")) != String(before_chairs[other_id]):
				_fail("the refused appointment disturbed %s's chair" % other_id)


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
