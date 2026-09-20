extends SceneTree

## V4.6, Task 2. The commodity state and the production tick's structural pins,
## headless -- the test_characters.gd shape, one layer down.
##
##   - THE LEAF PROPERTY: commodities.gd preloads commodity_constants and
##     NOTHING ELSE -- no economy, trade, budget or UI. What it reads of the
##     world it reads off GameState/NationState, and the recipe content arrives
##     as the loader argument rather than a preload.
##   - THE SINGLE-WRITER PIN: nothing but commodities.gd writes
##     `commodity_state`, anywhere in src/.
##   - DETERMINISM: two independent fresh states ticked twelve months, and one
##     state's own duplicate_state() copy ticked beside it, produce identical
##     commodity state. A rand() or a module-level static would show up here.
##   - THE SHAPE AND THE BOUND: every good seeds a capacity, prices start AT
##     base and never leave the plus-or-minus seventy-five percent band --
##     including through a shortage, which is the case that would otherwise
##     divide by zero or run away.
##   - THE PRODUCTION ORDER: every manufactured good in the register actually
##     comes out of a month, which is the direct check on the topological order
##     the first draft got wrong (`energy` holds both `uranium_fuel` and the
##     `electricity` made from it).
##   - THE SHORTAGE IS LOCAL: a collapsed endowment stops that nation's chain, and
##     the same goods are still made elsewhere -- the difference between a
##     shortage and a broken machine.
##
## The tick-order pin the plan listed here lands in Task 3, where the wiring it
## reads exists; asserting an order against a call site nobody has written yet
## would be a pin on nothing.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Commodities = preload("res://src/sim/commodities.gd")

## Long enough for a price homeostat to overshoot twice if it is going to.
const TICKS := 12
const BAND_LO := 0.25
const BAND_HI := 1.75

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_leaf_property()
	_check_single_writer()
	_check_seeding()
	_check_determinism()
	_check_every_recipe_chain_produces()
	_check_shortage_is_bounded()
	_check_prices_hold_the_band()

	if _failures.is_empty():
		print("test_commodities: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


## THE LEAF PROPERTY, source-scanned the way test_characters.gd polices its own:
## the ALLOWED preload and no others, checked over comment-stripped source so a
## docstring naming a system this file refuses to load cannot satisfy the scan.
func _check_leaf_property() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/commodities.gd")
	if src.is_empty():
		_fail("could not read src/sim/commodities.gd")
		return
	var allowed := ["commodity_constants.gd"]
	var code := _code_only(src)
	for line in code.split("\n"):
		var l := String(line)
		if l.contains("preload("):
			var found := false
			for a in allowed:
				if l.contains(String(a)):
					found = true
			if not found:
				_fail("commodities.gd preloads outside its leaf: %s" % l.strip_edges())
		if l.contains("get_node(") or l.contains("res://src/ui"):
			_fail("commodities.gd reaches the UI: %s" % l.strip_edges())


## SINGLE WRITER: `commodity_state` is commodities.gd's alone. The scan matches
## the WRITE form -- an indexed assignment into the register or an erase on it --
## the read/write shape test_characters.gd's tripwire already uses.
func _check_single_writer() -> void:
	for dir in ["src/sim", "src/core", "src/ui"]:
		var da := DirAccess.open("res://%s" % dir)
		if da == null:
			continue
		da.list_dir_begin()
		var f := da.get_next()
		while f != "":
			if not f.ends_with(".gd"):
				f = da.get_next()
				continue
			if f != "commodities.gd":
				var src := FileAccess.get_file_as_string("res://%s/%s" % [dir, f])
				if not src.is_empty() and _indexed_write(_code_only(src), "commodity_state"):
					_fail("%s/%s writes commodity_state -- commodities.gd is its one writer" % [dir, f])
			f = da.get_next()
		da.list_dir_end()


## THE SEED: every good gets a capacity for every nation, and no price has moved
## yet -- a fresh world sits at base, which is the state the price homeostat must
## be able to leave AND to come back to.
##
## Capacity above zero is asserted because it is a CONTENT claim the machine
## leans on rather than a tolerance: all ten nation files carry all three sectors
## above zero. `_bucket()` deliberately applies no floor, so a nation file that
## authored a zero sector would show up HERE rather than as a silently dead
## column.
func _check_seeding() -> void:
	var state = _new_state()
	if state == null:
		return
	for nation_id in state.nations.keys():
		var cs: Dictionary = state.nations[nation_id].commodity_state
		if cs.is_empty():
			_fail("nation %s seeded no commodity_state" % nation_id)
			continue
		var cap: Dictionary = cs.get("capacity", {})
		if cap.size() != _loader.commodity_goods.size():
			_fail("nation %s seeded %d capacities for %d goods" % [nation_id, cap.size(), _loader.commodity_goods.size()])
		for good_id in _goods_sorted():
			if not cap.has(good_id) or float(cap[good_id]) <= 0.0:
				_fail("nation %s has no capacity for %s -- its authored sector mix has a zero where this machine needs an endowment" % [nation_id, good_id])
			var base := float(_loader.commodity_goods[good_id].base_price)
			if not is_equal_approx(float(cs["price"].get(good_id, 0.0)), base):
				_fail("nation %s starts %s at %s, not its base %s" % [nation_id, good_id, cs["price"].get(good_id, 0.0), base])


## DETERMINISM, both ways. Two INDEPENDENT fresh states catch order-dependence
## on anything module-level; one state's duplicate_state() copy catches a tick
## that reads the live object rather than the one it was handed. The registers
## are compared as deep structures, so a float that differs in its last bit is
## a failure rather than a rounding note.
func _check_determinism() -> void:
	var one = _new_state()
	var two = _new_state()
	if one == null or two == null:
		return
	var copy = one.duplicate_state()

	for i in TICKS:
		Commodities.tick_month(one, _loader)
		Commodities.tick_month(two, _loader)
		Commodities.tick_month(copy, _loader)

	if not _deep_equal(one.player().commodity_state, two.player().commodity_state):
		_fail("two identical starting states diverged after %d ticks -- the machine is not deterministic" % TICKS)
	if not _deep_equal(one.player().commodity_state, copy.player().commodity_state):
		_fail("a duplicate_state() copy diverged from its original after %d ticks" % TICKS)
	# The world price is ONE vector: every nation must read the same number.
	var first: Dictionary = one.player().commodity_state["price"]
	for nation_id in one.nations.keys():
		var price: Dictionary = one.nations[nation_id].commodity_state["price"]
		for good_id in _goods_sorted():
			if not is_equal_approx(float(price.get(good_id, 0.0)), float(first.get(good_id, 0.0))):
				_fail("nation %s reads %s at %s while the player reads %s -- two world prices" % [
					nation_id, good_id, price.get(good_id, 0.0), first.get(good_id, 0.0)])
				return


## THE PRODUCTION ORDER, and it was a real defect this test now closes. The first
## version produced goods in the CATEGORY list, which looked topological and is
## not: `energy` holds both `uranium_fuel` (depth 1) and `electricity` (depth 2,
## made from it), so electricity was produced before the fuel it needs and the
## whole downstream chain -- steel, machinery, vehicles -- was produced from
## nothing. Silent, because a missing input reads as a zero and a zero output is
## an ordinary-looking figure.
##
## The check is the DIRECT one rather than a source read: every manufactured good
## in the register must actually come out of a month. A good the world cannot
## produce at any capacity is a machine defect; a good that is merely scarce is
## content, and scarcity cannot make this go red because capacity is what the
## chain is measured against, not demand.
func _check_every_recipe_chain_produces() -> void:
	var state = _new_state()
	if state == null:
		return
	for i in 3:
		Commodities.tick_month(state, _loader)
	var made := {}
	for nation_id in state.nations.keys():
		for good_id in _goods_sorted():
			made[good_id] = float(made.get(good_id, 0.0)) + float(state.nations[nation_id].commodity_state["output"][good_id])
	for recipe_id in _loader.commodity_recipes.keys():
		var output := String(_loader.commodity_recipes[recipe_id].output)
		if float(made.get(output, 0.0)) <= 0.0:
			_fail("%s is made by %s and no nation produced a unit of it -- the production order is not topological" % [output, recipe_id])


## THE SHORTAGE: one nation's INDUSTRY endowment is taken away, so the goods
## downstream of the recipe chain cannot be made there and their demand stands
## unmet. Capacity is DERIVED from `sector_output` on every tick rather than
## read back off the register, so the endowment is what has to move -- zeroing
## the register's own capacity field would be inert, which is exactly the trap
## this check was written into once.
##
## Three things are pinned: the tick SURVIVES (no NaN, no infinity anywhere), the
## price response stays inside the band, and the shock is LOCAL -- FRA makes no
## steel while another nation still does, which is what distinguishes a shortage
## from a broken machine.
func _check_shortage_is_bounded() -> void:
	var state = _new_state()
	if state == null:
		return
	var downstream := "steel"
	var other := "DEU"
	var ns = state.player()
	var before := float(ns.commodity_state["price"][downstream])
	for good_id in _goods_sorted():
		if float(ns.commodity_state["output"].get(good_id, 0.0)) != 0.0:
			_fail("a fresh seed already has output for %s -- the fixture is not a clean month" % good_id)
			return
	ns.sector_output["industry"] = 0.0
	for i in 6:
		Commodities.tick_month(state, _loader)
	for good_id in _goods_sorted():
		var price := float(ns.commodity_state["price"][good_id])
		if is_nan(price) or is_inf(price):
			_fail("a collapsed endowment left %s at %s" % [good_id, price])
		var output := float(ns.commodity_state["output"][good_id])
		if is_nan(output) or is_inf(output):
			_fail("a collapsed endowment left %s output at %s" % [good_id, output])
	if float(ns.commodity_state["output"][downstream]) > 0.0:
		_fail("%s was still produced with no industry at all -- the recipe was not respected" % downstream)
	var survivor = state.nations[other].commodity_state["output"]
	if float(survivor.get(downstream, 0.0)) <= 0.0:
		_fail("%s stopped making %s too -- the shock was not local to one nation" % [other, downstream])
	if float(ns.commodity_state["price"][downstream]) <= before:
		_fail("%s did not get dearer when its input ran out -- the price channel is dead" % downstream)
	if float(ns.commodity_state["value_added_eur_bn"]) >= float(state.nations[other].commodity_state["value_added_eur_bn"]):
		_fail("the collapsed nation's value added did not fall below the intact one's -- the delta is not reading the shock")


## THE BOUND, over a run long enough for a homeostat to run away if it is going
## to, and over every nation: prices stay within plus-or-minus seventy-five
## percent of base and no figure is NaN.
##
## AND THE NEGATIVE HALF, which measurement put here: a machine whose prices ALL
## sit at a clamp edge is not a world under strain, it is a world that has stopped
## -- the first draft capped production at each nation's own demand, so nobody
## ever held a surplus, trade was identically zero and the vector walked to the
## ceiling and stayed (32 of 60 goods). The pin is that the vector did not do
## that: the model is not allowed to be a constant. `at_edge` is deliberately not
## compared against a count -- how many goods are scarce is content, and pinning
## it would be pinning the answers.
func _check_prices_hold_the_band() -> void:
	var state = _new_state()
	if state == null:
		return
	for i in 24:
		Commodities.tick_month(state, _loader)
	var at_edge := 0
	for nation_id in state.nations.keys():
		var cs: Dictionary = state.nations[nation_id].commodity_state
		for good_id in _goods_sorted():
			var base := float(_loader.commodity_goods[good_id].base_price)
			var price := float(cs["price"][good_id])
			if price < base * BAND_LO - 1e-9 or price > base * BAND_HI + 1e-9:
				_fail("nation %s has %s at %s, outside the band [%s, %s]" % [
					nation_id, good_id, price, base * BAND_LO, base * BAND_HI])
				return
			var va := float(cs["value_added_eur_bn"])
			if is_nan(va) or is_inf(va):
				_fail("nation %s value added is %s" % [nation_id, va])
				return
			if nation_id == state.player_nation_id and (is_equal_approx(price, base * BAND_LO) or is_equal_approx(price, base * BAND_HI)):
				at_edge += 1
	if at_edge >= _goods_sorted().size():
		_fail("all %d prices sit on a clamp edge after 24 months -- the world stopped moving, it is not under strain" % at_edge)


func _new_state():
	var state = GameState.new_game(_loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game(FRA) reported %s" % [state.errors])
		return null
	for nation_id in state.nations.keys():
		Commodities.init_nation(state.nations[nation_id], _loader)
	return state


func _goods_sorted() -> Array:
	var ids: Array = _loader.commodity_goods.keys()
	ids.sort()
	return ids


## Assignment-shaped write detection: a line that indexes the register AND
## assigns into it (`] =`) or erases from it. A dictionary DECLARATION and a
## whole-property assignment are reads' and the state layer's business.
func _indexed_write(code: String, reg: String) -> bool:
	for raw_line in code.split("\n"):
		var line := String(raw_line)
		if not line.contains("%s[" % reg):
			continue
		if line.contains("] =") or line.contains(".erase("):
			return true
	return false


func _code_only(src: String) -> String:
	var out := ""
	for raw_line in src.split("\n"):
		var line := String(raw_line)
		var hash_at := line.find("#")
		if hash_at != -1:
			line = line.substr(0, hash_at)
		out += line + "\n"
	return out


func _deep_equal(a, b) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_DICTIONARY:
			if a.size() != b.size():
				return false
			for key in a.keys():
				if not b.has(key) or not _deep_equal(a[key], b[key]):
					return false
			return true
		TYPE_ARRAY:
			if a.size() != b.size():
				return false
			for i in range(a.size()):
				if not _deep_equal(a[i], b[i]):
					return false
			return true
		TYPE_FLOAT:
			return absf(a - b) < 1e-12
		_:
			return a == b


func _fail(message: String) -> void:
	_failures.append(message)