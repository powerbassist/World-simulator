extends SceneTree

## V4.11b. The two generated registers -- real endowments and the outline
## register -- loaded from the committed data. docs/commodities-model.md section 8.
## The loader refuses the structural failures; these pin the CONTENT the model
## relies on, so a regeneration that quietly drops a good or an outline fails here.

const DataLoader = preload("res://src/core/data_loader.gd")
const Roster = preload("res://src/core/roster.gd")
const GameState = preload("res://src/core/game_state.gd")
const Commodities = preload("res://src/sim/commodities.gd")

var _failures: Array[String] = []


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])

	_check_every_natural_good_is_endowed(loader)
	_check_outline_register_matches_the_map(loader)
	_check_europe_imports_what_it_imports(loader)
	_check_imported_ore_becomes_steel(loader)
	_check_the_world_opens_balanced(loader)
	_check_a_pool_cut_moves_the_price()

	if _failures.is_empty():
		print("test_endowments: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _check_every_natural_good_is_endowed(loader) -> void:
	for good_id in loader.commodity_goods.keys():
		var category := String(loader.commodity_goods[good_id].get("category", ""))
		var natural := category == "raw" or category == "agri"
		if natural != loader.commodity_endowments.has(good_id):
			_fail("%s (%s) endowed=%s" % [good_id, category, str(loader.commodity_endowments.has(good_id))])
			continue
		if not natural:
			continue
		var total := 0.0
		for producer in loader.commodity_endowments[good_id].keys():
			total += float(loader.commodity_endowments[good_id][producer])
		if absf(total - 1.0) > 1e-4:
			_fail("%s shares sum to %f" % [good_id, total])


## The outline grade's register is the drawn set, one-for-one, and every outline
## reads "outline" through the derived grade -- the roster-coverage check the
## V4.11 handoff named.
func _check_outline_register_matches_the_map(loader) -> void:
	if loader.outlines.size() != loader.world_features.size():
		_fail("outlines.json carries %d, world.geojson draws %d" % [loader.outlines.size(), loader.world_features.size()])
	for id in loader.outlines.keys():
		if String(loader.outlines[id]["name"]) == "":
			_fail("outline '%s' has no name" % id)
		if Roster.grade(loader, id) != "outline":
			_fail("outline '%s' grades as '%s'" % [id, Roster.grade(loader, id)])


## The point of the block, as content: the roster's own share of world output of
## the goods Europe really imports is small. If a regeneration ever put the
## synthetic world back, these would read near one.
func _check_europe_imports_what_it_imports(loader) -> void:
	for good_id in ["lithium_ore", "rare_earths", "nickel_ore", "crude_oil"]:
		var roster := 0.0
		for producer in loader.commodity_endowments.get(good_id, {}).keys():
			if loader.nations.has(producer):
				roster += float(loader.commodity_endowments[good_id][producer])
		if roster > 0.10:
			_fail("the roster makes %.3f of the world's %s -- the endowment reads as Europe's own again" % [roster, good_id])


## Trade before production: Germany mines no iron ore, so every tonne of its
## steel is made from ore that came in through the routing pass. Before V4.11b's
## order change this nation's steel would have stopped the month its ore became real.
func _check_imported_ore_becomes_steel(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	Commodities.tick_month(state, loader)
	var de: Dictionary = state.nations["DEU"].commodity_state
	if float(de["capacity"]["iron_ore"]) > 0.0:
		_fail("DEU carries an iron-ore endowment -- the fixture this check relies on moved")
	if float(de["trade"]["iron_ore"]) <= 0.0:
		_fail("DEU imported no iron ore")
	if float(de["output"]["steel"]) <= 0.0 and float(de["trade"]["steel"]) >= 0.0:
		_fail("DEU made no steel from its imported ore -- natural goods did not route before production")


## The world volume is every producer's requirement, so endowment and requirement
## close to the unit at the authored start: the opening world is balanced and the
## shares only decide who makes it.
func _check_the_world_opens_balanced(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	Commodities.tick_month(state, loader)
	var price: Dictionary = state.nations["FRA"].commodity_state["price"]
	for good_id in loader.commodity_endowments.keys():
		var ratio := float(price[good_id]) / float(loader.commodity_goods[good_id].base_price)
		if absf(ratio - 1.0) > 0.02:
			_fail("%s opens at %.3f of base -- the world volume does not balance the endowment" % [good_id, ratio])


## The pool is a foreign-policy surface only if its supply moves a price: halve
## the outlines' share of one good and its price must rise.
func _check_a_pool_cut_moves_the_price() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	var good_id := "lithium_ore"
	var shares: Dictionary = loader.commodity_endowments[good_id]
	for producer in shares.keys():
		if not loader.nations.has(producer):
			shares[producer] = float(shares[producer]) * 0.5
	var state = GameState.new_game(loader, "FRA")
	for i in 6:
		Commodities.tick_month(state, loader)
	var ratio := float(state.nations["FRA"].commodity_state["price"][good_id]) / float(loader.commodity_goods[good_id].base_price)
	if ratio <= 1.05:
		_fail("halving the world pool's lithium left its price at %.3f of base" % ratio)


func _fail(message: String) -> void:
	_failures.append(message)
