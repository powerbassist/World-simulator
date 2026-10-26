extends SceneTree

## V5.2 C6 -- campaigns paid by the party (docs/design/v5.2-c6-party-campaigns.md,
## bands-v5.2.md B9). src/sim/party_money.gd and the campaign wiring that calls it:
## the price per inhabitant, the income that moves only at an election, the payment
## cheaper first, the stop when the chest runs dry, the start that needs one month,
## and the soft ceiling's evidence.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const PartyMoney = preload("res://src/sim/party_money.gd")
const President = preload("res://src/sim/president.gd")
const Budget = preload("res://src/sim/budget.gd")
const SC = preload("res://src/sim/shadow_constants.gd")

const CHEAP := "ground_game"
const DEAR := "broadcast"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_the_price_is_per_inhabitant()
	_test_funding_reads_the_data()
	_test_net_income_is_zero_until_an_election()
	_test_an_election_moves_the_purse()
	_test_opposition_only_funds_no_party_in_government()
	_test_a_running_effort_is_paid_by_the_party()
	_test_a_start_needs_one_month_in_the_chest()
	_test_the_dearer_effort_stops_first()
	_test_months_payable()
	_test_the_soft_ceiling_leaves_evidence()
	_test_no_ceiling_leaves_no_evidence()
	_test_the_window_spend_clears_with_the_window()
	_test_a_projection_spends_no_real_money()
	_test_no_other_nation_touches_its_money()
	_test_party_money_is_a_leaf()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("test_party_money: OK")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _action(id: String):
	for a in _loader.campaign_actions:
		if a.id == id:
			return a
	return null


## Winds the clock to `months` before the executive election, ticking nothing.
func _wind_to(state, months: int) -> void:
	var ns = state.player()
	var target: int = (ns.next_executive_year * 12 + ns.next_executive_month) - months
	state.year = int(target / 12)
	state.month = target - state.year * 12
	if state.month <= 0:
		state.month += 12
		state.year -= 1


func _site(ns) -> String:
	return Campaign.region_ids(ns, _loader)[0]


func _in_window(nation_id := "FRA"):
	var state = GameState.new_game(_loader, nation_id)
	_wind_to(state, 6)
	return state


## Sets the payer's money to exactly `amount`, through the register's own writer.
func _set_money(ns, amount: float) -> void:
	President.adjust_party_money_eur_m(ns, _loader, String(ns.incumbent_party_id), amount - PartyMoney.money_eur_m(ns, _loader))


func _start(state, ns, effort_id: String) -> Dictionary:
	return Campaign.execute(state, ns, _loader, _action("start_" + effort_id), _site(ns))


func _test_the_price_is_per_inhabitant() -> void:
	var ns = GameState.new_game(_loader, "FRA").player()
	var price := Campaign.price_eur_m(ns, _loader, CHEAP)
	var want: float = float(Campaign.terms_of(_loader, CHEAP)["cost_eur_per_k_pop_month"]) * ns.population / 1.0e9
	if not is_equal_approx(price, want):
		_fail("ground game costs %f EUR m a month, not cost x population / 1e9 = %f" % [price, want])
	# The spec's section 2 table: France, ground game, EUR 0.56 m a month.
	if price < 0.55 or price > 0.56:
		_fail("France's ground game is %f EUR m a month, not the spec's 0.56" % price)


func _test_funding_reads_the_data() -> void:
	var purse: Dictionary = _loader.party_funding.get("FRA", {})
	if not is_equal_approx(float(purse.get("vote_pot_eur_m_year", -1.0)), 32.25):
		_fail("France's vote pot did not load: %s" % str(purse))
	if not is_equal_approx(float(purse.get("cap_eur_m", -1.0)), 22.509):
		_fail("France's campaign ceiling did not load: %s" % str(purse))
	# Germany sets no ceiling: absent is no ceiling, read as a negative cap.
	if float(_loader.party_funding.get("DEU", {}).get("cap_eur_m", 0.0)) >= 0.0:
		_fail("Germany reads a campaign ceiling it does not have")
	var ns = GameState.new_game(_loader, "FRA").player()
	var start := PartyMoney.funding_eur_m_year(ns, _loader, "renouveau_civique", false)
	if not is_equal_approx(start, (32.25 + 34.19) * 0.28):
		_fail("renouveau_civique's start funding is %f, not both pots x its authored 0.28" % start)


## Running costs equal the funding at the start, and before the first legislative
## election the shares ARE the start's, so no party's money moves: exactly, not about.
func _test_net_income_is_zero_until_an_election() -> void:
	for nation_id in ["FRA", "DEU", "GBR", "POL"]:
		var state = GameState.new_game(_loader, nation_id)
		var ns = state.player()
		for i in 24:
			PartyMoney.tick_month(ns, _loader)
		if not ns.party_money_delta_eur_m.is_empty():
			_fail("%s: party money moved with no election: %s" % [nation_id, str(ns.party_money_delta_eur_m)])


func _test_an_election_moves_the_purse() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var pid := "renouveau_civique"
	ns.last_election = {"vote_share": {pid: 0.40}}
	ns.seats_by_party[pid] = 300
	var now := PartyMoney.funding_eur_m_year(ns, _loader, pid, true)
	var want := 32.25 * 0.40 + 34.19 * 300.0 / float(ns.assembly_seats)
	if not is_equal_approx(now, want):
		_fail("after an election the funding is %f, not %f" % [now, want])
	var before := PartyMoney.money_eur_m(ns, _loader)
	PartyMoney.tick_month(ns, _loader)
	var start := PartyMoney.funding_eur_m_year(ns, _loader, pid, false)
	if not is_equal_approx(PartyMoney.money_eur_m(ns, _loader) - before, (now - start) / 12.0):
		_fail("a month after a win paid %f, not a twelfth of the net %f" % [PartyMoney.money_eur_m(ns, _loader) - before, (now - start) / 12.0])
	var purse := PartyMoney.purse(ns, _loader, pid)
	if not is_equal_approx(float(purse["net"]), now - start) or not is_equal_approx(float(purse["running"]), start):
		_fail("the purse view does not split funding, running costs and net: %s" % str(purse))


## Short Money (GBR): the pots fund the opposition only, by the authored government
## at the start and by the coalition after an election -- a data field, no id check.
func _test_opposition_only_funds_no_party_in_government() -> void:
	var state = GameState.new_game(_loader, "GBR")
	var ns = state.player()
	var ruling := String(_loader.nations["GBR"].leader_party_id)
	if PartyMoney.funding_eur_m_year(ns, _loader, ruling, false) != 0.0:
		_fail("GBR's governing party draws Short Money at the start")
	if PartyMoney.funding_eur_m_year(ns, _loader, "national_unity_party", false) <= 0.0:
		_fail("GBR's opposition draws nothing at the start")
	ns.last_election = {"vote_share": {ruling: 0.30, "national_unity_party": 0.35}}
	ns.coalition_party_ids = ["national_unity_party"]
	if PartyMoney.funding_eur_m_year(ns, _loader, "national_unity_party", true) != 0.0:
		_fail("a party that entered government still draws Short Money")
	if PartyMoney.funding_eur_m_year(ns, _loader, ruling, true) <= 0.0:
		_fail("a party that left government draws no Short Money")


func _test_a_running_effort_is_paid_by_the_party() -> void:
	var state = _in_window()
	var ns = state.player()
	if not bool(_start(state, ns, CHEAP).get("applied", false)):
		_fail("the effort did not start, so this check measures nothing")
		return
	var before := PartyMoney.money_eur_m(ns, _loader)
	var stopped: Array = Campaign.tick_month(state, _loader)
	var price := Campaign.price_eur_m(ns, _loader, CHEAP)
	if not is_equal_approx(before - PartyMoney.money_eur_m(ns, _loader), price):
		_fail("a month of ground game took %f from the party, not its price %f" % [before - PartyMoney.money_eur_m(ns, _loader), price])
	if not is_equal_approx(ns.campaign_spent_eur_m, price):
		_fail("the window's spend reads %f, not %f" % [ns.campaign_spent_eur_m, price])
	if not stopped.is_empty():
		_fail("a paid effort was reported stopped: %s" % str(stopped))


func _test_a_start_needs_one_month_in_the_chest() -> void:
	var state = _in_window()
	var ns = state.player()
	_set_money(ns, Campaign.price_eur_m(ns, _loader, CHEAP) * 0.5)
	var result := _start(state, ns, CHEAP)
	if bool(result.get("applied", true)) or String(result.get("reason", "")) != "the party cannot pay for it":
		_fail("a start the chest cannot pay for one month was not refused for money: %s" % str(result))
	if Campaign.is_running(ns, CHEAP):
		_fail("a refused start put the effort in the field")
	_set_money(ns, Campaign.price_eur_m(ns, _loader, CHEAP))
	if not bool(_start(state, ns, CHEAP).get("applied", false)):
		_fail("a chest holding exactly one month could not start the effort")


## Cheaper first: a short chest stops the dearer effort, which keeps what it bought
## (nothing, here) and accrues nothing for the month it was not paid.
func _test_the_dearer_effort_stops_first() -> void:
	var state = _in_window()
	var ns = state.player()
	_start(state, ns, DEAR)
	_start(state, ns, CHEAP)
	if Campaign.running(ns).size() != 2:
		_fail("two efforts did not start, so this check measures nothing")
		return
	var cheap := Campaign.price_eur_m(ns, _loader, CHEAP)
	var dear := Campaign.price_eur_m(ns, _loader, DEAR)
	# Enough for the dearer alone, not for both: paid dearer-first, the cheaper would stop.
	_set_money(ns, dear + cheap * 0.5)
	var stopped: Array = Campaign.tick_month(state, _loader)
	if Campaign.is_running(ns, DEAR) or not Campaign.is_running(ns, CHEAP):
		_fail("the short chest did not stop the dearer effort alone: %s" % str(Campaign.running(ns)))
	if stopped.size() != 1 or String(stopped[0].get("effort_id", "")) != DEAR or String(stopped[0].get("nation_id", "")) != "FRA":
		_fail("the stop was not reported as FRA's broadcast: %s" % str(stopped))
	if not is_equal_approx(PartyMoney.money_eur_m(ns, _loader), dear - cheap * 0.5):
		_fail("the chest holds %f after paying the cheap effort, not %f" % [PartyMoney.money_eur_m(ns, _loader), dear - cheap * 0.5])
	# Pensioners are broadcast's alone among the two: an unpaid month accrues nothing.
	if float(ns.campaign_mobilisation.get("pensioners", 0.0)) != 0.0:
		_fail("the unpaid broadcast accrued its month anyway")
	if not Campaign.has_started(ns, DEAR):
		_fail("a stop for money handed the effort's one run back")


func _test_months_payable() -> void:
	var state = _in_window()
	var ns = state.player()
	var cheap := Campaign.price_eur_m(ns, _loader, CHEAP)
	_set_money(ns, cheap * 3.5)
	if Campaign.months_payable(ns, _loader) != -1:
		_fail("months payable with nothing running is not -1")
	if Campaign.months_payable(ns, _loader, CHEAP) != 3:
		_fail("3.5 months of ground game in the chest reads %d months, not 3" % Campaign.months_payable(ns, _loader, CHEAP))
	_start(state, ns, CHEAP)
	var both := cheap + Campaign.price_eur_m(ns, _loader, DEAR)
	if Campaign.months_payable(ns, _loader, DEAR) != int(floor(cheap * 3.5 / both)):
		_fail("the combined rate's months read %d" % Campaign.months_payable(ns, _loader, DEAR))


## Past the legal ceiling the president may spend (soft), and each EUR m over leaves
## the evidence a party-money donation of that size leaves: ONE row, grown, naming a
## covered member of the payer party (Gameplay, 2026-10-25).
func _test_the_soft_ceiling_leaves_evidence() -> void:
	var state = _in_window()
	var ns = state.player()
	_start(state, ns, CHEAP)
	var cap := float(_loader.party_funding["FRA"]["cap_eur_m"])
	var price := Campaign.price_eur_m(ns, _loader, CHEAP)
	ns.campaign_spent_eur_m = cap - price * 0.25
	if not is_equal_approx(PartyMoney.ceiling_room_eur_m(ns, _loader), price * 0.25):
		_fail("the ceiling's room reads %f, not %f" % [PartyMoney.ceiling_room_eur_m(ns, _loader), price * 0.25])
	Campaign.tick_month(state, _loader)
	var rows: Array = []
	for row in ns.exposure_evidence:
		if String(row.get("kind", "")) == "party_money":
			rows.append(row)
	if rows.size() != 1:
		_fail("a month past the ceiling left %d party-money rows, not 1" % rows.size())
		return
	if not is_equal_approx(float(rows[0]["size"]), price * 0.75 * SC.EVIDENCE_PER_EUR_M):
		_fail("the overspend left %f of evidence, not the part past the ceiling %f" % [float(rows[0]["size"]), price * 0.75])
	var who := String(rows[0]["person_id"])
	if who == President.leader_id(ns) or not President.covers(state, ns, _loader, who):
		_fail("the evidence names '%s', not a covered member of the payer party" % who)
	Campaign.tick_month(state, _loader)
	var grown := 0
	for row in ns.exposure_evidence:
		if String(row.get("kind", "")) == "party_money":
			grown += 1
	if grown != 1:
		_fail("a second month past the ceiling left a second row (%d) instead of growing the first" % grown)
	if PartyMoney.ceiling_room_eur_m(ns, _loader) >= 0.0:
		_fail("the room past the ceiling does not read negative")


func _test_no_ceiling_leaves_no_evidence() -> void:
	var state = _in_window("DEU")
	var ns = state.player()
	_start(state, ns, CHEAP)
	ns.campaign_spent_eur_m = 1000.0
	Campaign.tick_month(state, _loader)
	if not ns.exposure_evidence.is_empty():
		_fail("a nation with no ceiling left evidence for spending")
	if not is_inf(PartyMoney.ceiling_room_eur_m(ns, _loader)):
		_fail("a nation with no ceiling reads finite room")


func _test_the_window_spend_clears_with_the_window() -> void:
	var state = _in_window()
	var ns = state.player()
	_start(state, ns, CHEAP)
	Campaign.tick_month(state, _loader)
	if ns.campaign_spent_eur_m <= 0.0:
		_fail("nothing spent inside the window, so this check measures nothing")
	ns.next_executive_year += 5
	Campaign.tick_month(state, _loader)
	if ns.campaign_spent_eur_m != 0.0:
		_fail("the window's spend survived the window closing")


## party_money_delta_eur_m is DEEP and campaign_spent_eur_m a scalar on the copy, so a
## twelve-month forecast inside a run-up pays nothing for real.
func _test_a_projection_spends_no_real_money() -> void:
	var state = _in_window()
	var ns = state.player()
	_start(state, ns, CHEAP)
	var money := PartyMoney.money_eur_m(ns, _loader)
	var spent: float = ns.campaign_spent_eur_m
	var evidence: int = ns.exposure_evidence.size()
	Budget.project(state, {}, 12, _loader)
	if PartyMoney.money_eur_m(ns, _loader) != money or ns.campaign_spent_eur_m != spent or ns.exposure_evidence.size() != evidence:
		_fail("a projection spent real party money or wrote real evidence")


func _test_no_other_nation_touches_its_money() -> void:
	var state = _in_window()
	_start(state, state.player(), CHEAP)
	for i in 4:
		Campaign.tick_month(state, _loader)
	for id in state.nations:
		if String(id) == "FRA":
			continue
		var other = state.nations[id]
		if not other.party_money_delta_eur_m.is_empty() or other.campaign_spent_eur_m != 0.0:
			_fail("%s's party money moved with no campaign and no player" % id)


## campaign.gd preloads this file, and elections.gd preloads campaign.gd: a system
## preload here (characters.gd reaches government and legislature) would be a cycle.
func _test_party_money_is_a_leaf() -> void:
	var file := FileAccess.open("res://src/sim/party_money.gd", FileAccess.READ)
	if file == null:
		_fail("could not read party_money.gd")
		return
	for line in file.get_as_text().split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("const ") or not trimmed.contains("preload("):
			continue
		if trimmed.contains("_constants.gd") or trimmed.contains("res://src/sim/president.gd"):
			continue
		_fail("party_money.gd preloads a system: `%s`" % trimmed)
