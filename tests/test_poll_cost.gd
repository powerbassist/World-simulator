extends SceneTree

## G8 (the V5.1 play gate, 2026-10-22): "ordering a poll costs absurd amounts,
## more than 1 billion EUR". The price list was a share of GDP -- 0.05 % and
## 0.04 %, EUR 1.45 bn and 1.16 bn for France -- about ten thousand times what
## the fieldwork costs, and a share of GDP is the wrong shape besides: a sample
## of ten thousand costs Luxembourg what it costs France. This pins the price,
## its shape and the one charge Statute.buy_poll() makes.
##
##   1. Each kind's price, exactly, and a ceiling of EUR 1 m on every kind: the
##      ceiling is the regression G8 was, read as a number.
##   2. GDP-independent: France and Luxembourg pay the same for the same kind.
##   3. buy_poll() charges the debt exactly poll_cost_eur_bn() and records it;
##      a refused second commission charges nothing.
##   4. An unknown kind costs nothing and is refused.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Statute = preload("res://src/sim/statute.gd")
const SK = preload("res://src/sim/statute_constants.gd")

## EUR bn. The ceiling is G8's own regression read as a number; the exact
## values are statute_constants.gd's, and a change to them is a change here.
const CEILING_EUR_BN := 0.001
const ASSEMBLY_EUR_BN := 0.00005
const POPULAR_EUR_BN := 0.00015

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
	else:
		_test_prices()
		_test_gdp_independent()
		_test_charge()
		_test_unknown_kind()
	_finish()


func _test_prices() -> void:
	var want := {SK.POLL_KIND_ASSEMBLY: ASSEMBLY_EUR_BN, SK.POLL_KIND_POPULAR: POPULAR_EUR_BN}
	for kind in want:
		var cost: float = SK.poll_cost_eur_bn(kind)
		if not is_equal_approx(cost, float(want[kind])):
			_fail("the %s poll costs EUR %.6f bn, expected %.6f" % [kind, cost, float(want[kind])])
		if cost <= 0.0 or cost > CEILING_EUR_BN:
			_fail("the %s poll costs EUR %.6f bn -- a poll is fieldwork, not a budget line (G8)" % [kind, cost])
	if SK.POLL_COSTS_EUR_BN.size() != want.size():
		_fail("POLL_COSTS_EUR_BN prices %d kinds, this test pins %d" % [SK.POLL_COSTS_EUR_BN.size(), want.size()])


func _test_gdp_independent() -> void:
	var paid := {}
	for nation_id in ["FRA", "LUX"]:
		var gs = GameState.new_game(_loader, nation_id)
		var ns = gs.player()
		var before: float = ns.debt_eur_bn
		var result: Dictionary = Statute.buy_poll(gs, ns, "high_earner_surtax", SK.POLL_KIND_POPULAR)
		if not bool(result.get("ok", false)):
			_fail("%s could not commission a popular poll: %s" % [nation_id, result.get("refusal", "")])
			return
		paid[nation_id] = ns.debt_eur_bn - before
	var gs_fra = GameState.new_game(_loader, "FRA")
	var gs_lux = GameState.new_game(_loader, "LUX")
	if gs_fra.player().gdp_eur_bn < 10.0 * gs_lux.player().gdp_eur_bn:
		_fail("the GDP-independence check needs two economies of very different size")
	if absf(float(paid["FRA"]) - float(paid["LUX"])) > 1e-12:
		_fail("France paid EUR %.6f bn and Luxembourg %.6f bn for the same poll -- a sample does not scale with GDP" % [
			float(paid["FRA"]), float(paid["LUX"])])


func _test_charge() -> void:
	var gs = GameState.new_game(_loader, "FRA")
	var ns = gs.player()
	var before: float = ns.debt_eur_bn
	var result: Dictionary = Statute.buy_poll(gs, ns, "high_earner_surtax", SK.POLL_KIND_ASSEMBLY)
	var charged: float = ns.debt_eur_bn - before
	if absf(charged - SK.poll_cost_eur_bn(SK.POLL_KIND_ASSEMBLY)) > 1e-12:
		_fail("buy_poll charged EUR %.6f bn, poll_cost_eur_bn() says %.6f" % [charged, SK.poll_cost_eur_bn(SK.POLL_KIND_ASSEMBLY)])
	if absf(float(result.get("cost_eur_bn", -1.0)) - charged) > 1e-12:
		_fail("buy_poll reported EUR %.6f bn and charged %.6f" % [float(result.get("cost_eur_bn", -1.0)), charged])
	var recorded: float = float(ns.poll_purchases.get("high_earner_surtax", {}).get(SK.POLL_KIND_ASSEMBLY, {}).get("cost", -1.0))
	if absf(recorded - charged) > 1e-12:
		_fail("the register recorded EUR %.6f bn for a charge of %.6f" % [recorded, charged])
	var mid: float = ns.debt_eur_bn
	var second: Dictionary = Statute.buy_poll(gs, ns, "high_earner_surtax", SK.POLL_KIND_ASSEMBLY)
	if bool(second.get("ok", true)) or ns.debt_eur_bn != mid:
		_fail("a second commission of the same kind was not refused for free")


func _test_unknown_kind() -> void:
	if SK.poll_cost_eur_bn("exit") != 0.0:
		_fail("an unknown poll kind has a price")
	var gs = GameState.new_game(_loader, "FRA")
	var ns = gs.player()
	var before: float = ns.debt_eur_bn
	var result: Dictionary = Statute.buy_poll(gs, ns, "high_earner_surtax", "exit")
	if bool(result.get("ok", true)) or ns.debt_eur_bn != before:
		_fail("an unknown poll kind was sold, or charged")


func _fail(message: String) -> void:
	_failures.append(message)
	print("FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("OK: all poll cost checks passed")
		quit(0)
	else:
		print("%d failures" % _failures.size())
		quit(1)
