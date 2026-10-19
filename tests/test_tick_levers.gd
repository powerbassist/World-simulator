extends SceneTree

## Headless test: godot --headless --script res://tests/test_tick_levers.gd
## Non-zero exit on any failure.
##
## V5.0c's month-tick levers are each a claim that a faster path returns the SAME
## FLOAT as the slow one. The 51-regime balance table (cmp-identical) is the
## whole-game proof; this file pins each claim on its own, so a later edit that
## breaks one fails here, by name, rather than as an unexplained balance diff:
##
##   1. Regions.unemployment_by_region() equals unemployment_pct() region by
##      region, for every nation, with sites and access live.
##   2. Org.shared_bonus() memoised equals it computed, and Diplomacy closes the
##      memo on its way out (an open memo would serve stale membership to the
##      Orgs step).
##   3. Trade's skipped lookups are skipped only while the registers are EMPTY:
##      with an agreement and a measure on a pair, the vector still prices both.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Regions = preload("res://src/sim/regions.gd")
const Org = preload("res://src/core/org.gd")
const Trade = preload("res://src/sim/trade.gd")
const RK = preload("res://src/core/relations.gd")

var _failures: Array[String] = []


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])
		_finish()
		return
	var state = GameState.new_game(loader, "FRA")
	for _i in range(3):
		WorldMonth.tick_month(state, loader)
	_check_unemployment_batch(state)
	_check_shared_bonus_memo(state, loader)
	_check_trade_registers(state)
	_finish()


func _check_unemployment_batch(state) -> void:
	var checked := 0
	for id in state.nations:
		var ns = state.nations[id]
		var region_list: Array = state.regions.get(id, [])
		if region_list.is_empty():
			continue
		var access: Dictionary = Regions.accessibility_for(ns, region_list, state.region_graph)
		# Sited and unsited both: the batch hoists the sited mean, so a nation with
		# no sites and one with a synthetic site are two different paths.
		var site_cases: Array = [state.project_sited_pct.get(id, {}), {String(region_list[0].id): 0.25}]
		for sites in site_cases:
			var batch: Dictionary = Regions.unemployment_by_region(ns, region_list, access, sites)
			for region in region_list:
				var one: float = Regions.unemployment_pct(ns, region_list, region.id, access, sites)
				if not batch.has(region.id) or float(batch[region.id]) != one:
					_fail("%s/%s: batched unemployment %s, per-region %s" % [id, region.id, batch.get(region.id), one])
				checked += 1
	if checked < 200:
		_fail("only %d regions compared -- the batch check is not reaching the roster" % checked)


func _check_shared_bonus_memo(state, loader) -> void:
	var ids: Array = state.nations.keys()
	var plain := {}
	for a in ids:
		for b in ids:
			plain[a + ">" + b] = Org.shared_bonus(state, a, b, "trade_bonus")
	Org.memo_open(state)
	for pass_i in range(2):  # the second pass is all hits
		for a in ids:
			for b in ids:
				if Org.shared_bonus(state, a, b, "trade_bonus") != float(plain[a + ">" + b]):
					_fail("memoised shared_bonus(%s, %s) differs on pass %d" % [a, b, pass_i])
	Org.memo_close()
	# A different state never reads another's memo.
	var other = state.duplicate_state()
	Org.memo_open(state)
	other.nations[ids[0]].orgs = []
	if Org.shared_bonus(other, ids[0], ids[1], "trade_bonus") != 0.0:
		_fail("a second state read the first state's memo")
	Org.memo_close()
	# Diplomacy leaves no memo open behind it.
	WorldMonth.tick_month(state, loader)
	if Org._memo_state != null:
		_fail("the shared_bonus memo is still open after the month")


func _check_trade_registers(state) -> void:
	var probe = state.duplicate_state()
	var ids: Array = probe.nations.keys()
	var a: String = "FRA"
	var b: String = "DEU"
	var before: Dictionary = Trade.weights(probe, a)
	probe.agreements[RK.key(a, b)] = {"weight_multiplier": 1.5}
	var with_agreement: Dictionary = Trade.weights(probe, a)
	if not float(with_agreement[b]) > float(before[b]):
		_fail("an agreement on %s-%s did not raise the weight (%s -> %s)" % [a, b, before[b], with_agreement[b]])
	probe.measures[RK.directed_key(b, a)] = {"severity": 1.0, "since_year": probe.year, "since_month": probe.month}
	var with_measure: Dictionary = Trade.weights(probe, a)
	if not float(with_measure[b]) < float(with_agreement[b]):
		_fail("a measure on %s-%s did not cut the weight (%s -> %s)" % [a, b, with_agreement[b], with_measure[b]])
	if ids.size() < 3:
		_fail("roster too small to exercise the trade registers")


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_tick_levers: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
