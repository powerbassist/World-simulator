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
##   - THE TICK ORDER: the call sits after Economy's and before Opinion's in the
##     month handler, source-read the way test_characters.gd pins its own slot.
##     The layer prices next month's demand off this month's settled output, so
##     both halves of the order are load-bearing rather than tidiness.
##   - THE ABSENT-REGISTER SEED: a nation whose `commodity_state` is `{}` -- the
##     shape a payload with the key stripped hands back, and a hand-built
##     fixture besides -- seeds and ticks rather than crashing. Since Task 5 the
##     key IS serialised, so the check covers the stripped arrival AND the
##     unmodified round trip, which must now carry the register.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Commodities = preload("res://src/sim/commodities.gd")
const CommodityK = preload("res://src/sim/commodity_constants.gd")

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
	_check_tick_order_pin()
	_check_absent_register_bridge()
	_check_high_crossing_stamp()

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
	# The crossing stamp's writer, pinned the same way: commodities.gd assigns it;
	# nation_state.gd is the field's home (declaration, duplicate_state, from_dict
	# carry it) and is the only other file allowed an assignment. READS are fine --
	# events.gd compares it with `==`, which the pattern excludes.
	var stamp_write := RegEx.new()
	stamp_write.compile("commodity_high_month\\s*[-+*/]?=(?!=)")
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
				if f != "nation_state.gd" and not src.is_empty() \
						and stamp_write.search(_code_only(src)) != null:
					_fail("%s/%s assigns commodity_high_month -- commodities.gd is its one writer" % [dir, f])
			f = da.get_next()
		da.list_dir_end()


## THE SEED: every good gets a capacity for every nation, and no price has moved
## yet -- a fresh world sits at base, which is the state the price homeostat must
## be able to leave AND to come back to.
##
## Capacity above zero is asserted because it is a CONTENT claim the machine
## leans on rather than a tolerance: every nation file carries all three sectors
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
			if not cap.has(good_id):
				_fail("nation %s seeded no capacity for %s" % [nation_id, good_id])
				continue
			# V4.11b: a raw or agri good's capacity is the nation's REAL share of
			# world production -- zero where it mines nothing, by design (Albania
			# has no lithium). Every OTHER good keeps the sector-output claim.
			if _loader.commodity_endowments.has(good_id):
				var share := float(_loader.commodity_endowments[good_id].get(nation_id, 0.0))
				if (share > 0.0) != (float(cap[good_id]) > 0.0):
					_fail("nation %s: %s share %f but capacity %f -- the endowment did not reach the seed" % [nation_id, good_id, share, float(cap[good_id])])
			elif float(cap[good_id]) <= 0.0:
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


## THE TICK ORDER, source-read off the month handler the way test_characters.gd
## pins Characters' slot: comments stripped first, then the RELATIVE positions of
## the three calls. A comment saying the order is not the check; the call sites'
## order is. NOT in game_state.gd, which has no month tick at all --
## src/sim/world_month.gd is the month the game and every balance harness run.
##
## AFTER Economy: capacity is derived from `sector_output`, which Economy settles,
## so a tick before it would price this month's production off last month's mix.
## BEFORE Opinion: no SIM module reads the commodity state -- its readers are the
## UI surfaces (the Commodities panel and the two map layers), which read after
## the tick -- and the slot is ahead of the voter so a figure this month can be
## priced in it rather than a month later -- Opinion's own "reads the same month"
## rule for Inflation and Orgs.
##
## There used to be a second read, of balance_probe.gd's hand copy of the month;
## the copy is gone, and tests/test_world_month.gd holds every harness to the one
## month instead. The partial-month probes (calendar/media/trade and the rest)
## still tick a subset and do not carry the call: no SIM module reads the register
## itself (the commodity_price_high hook reads a stamp, through Events), so a probe
## without Events cannot disagree about a SIM figure.
func _check_tick_order_pin() -> void:
	_check_order_in("res://src/sim/world_month.gd", "world_month.gd")


func _check_order_in(path: String, label: String) -> void:
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		_fail("could not read %s" % path)
		return
	var code := _code_only(src)
	var economy_at := code.find("Economy.tick_month(")
	var commodities_at := code.find("Commodities.tick_month(")
	var opinion_at := code.find("Opinion.tick_month(")
	if economy_at == -1 or commodities_at == -1 or opinion_at == -1:
		_fail("%s is missing one of Economy/Commodities/Opinion tick calls" % label)
		return
	if not (economy_at < commodities_at and commodities_at < opinion_at):
		_fail("%s must run Commodities.tick_month after Economy (which settles the output its capacity reads) and before Opinion" % label)


## THE ABSENT-REGISTER BRIDGE. Before Task 5 this check's subject was the `{}` a
## pre-V4.6 save loaded; serialisation moved WHERE that `{}` comes from without
## retiring the branch, because save_manager refuses a version MISMATCH outright
## (V3.3's own argument at the gate) -- so the absent register now arrives from a
## payload with the KEY stripped, which is exactly the shape of a version-36
## save's dictionary and of a hand-built fixture. Three legs, and the third is
## the one serialisation ADDED:
##
##   1. the hand-emptied field: the branch exists and seeds the right model;
##   2. the key STRIPPED from the payload: the real arrival shape, and the one
##      that would have been the pre-V4.6 load path had the gate permitted it;
##   3. the UNMODIFIED round trip: now carries the register, and must come back
##      non-empty and tick to the same state. Before Task 5 this leg is the one
##      that fired loud; it is kept because it is the pair to leg 2 -- together
##      they say "the key is serialised, and its absence is still handled".
##   4. the PARTIAL register: a payload carrying only some of the seven keys. The
##      gate reads them all (`Commodities.STATE_KEYS`), so a partial one reseeds
##      WHOLE and ticks clean, rather than passing an emptiness test and faulting
##      on the first missing index (measured: 62 SCRIPT ERRORs from one partial
##      register in one month before the gate read the key set).
##
## All of it is the determinism contract rather than a smoke test: every seeded
## route must reach the same state as a fresh init, to the bit, or "the after-load
## world" is a second simulation.
func _check_absent_register_bridge() -> void:
	var fresh = GameState.new_game(_loader, "FRA")
	var loaded = GameState.new_game(_loader, "FRA")
	if fresh == null or loaded == null:
		return
	for nation_id in loaded.nations.keys():
		loaded.nations[nation_id].commodity_state = {}

	var round_trip = GameState.from_dict(fresh.to_dict())
	# Leg 3 asserted before it is ticked: an unmodified round trip that came back
	# empty would mean the key is not serialised after all, and leg 2 below would
	# then be testing the same thing as leg 1.
	for nation_id in round_trip.nations.keys():
		if round_trip.nations[nation_id].commodity_state.is_empty():
			_fail("a round trip lost nation %s's commodity_state -- the key is not serialised, so the stripped-payload leg tests nothing the hand-emptied one does not" % nation_id)
			return
	var payload: Dictionary = fresh.to_dict()
	for nation_id in (payload["nations"] as Dictionary).keys():
		(payload["nations"][nation_id] as Dictionary).erase("commodity_state")
	var stripped = GameState.from_dict(payload)
	# Leg 4: a register missing six of its seven keys. Built off the real payload
	# so it is the arrival shape and not a synthetic NationState.
	var partial_payload: Dictionary = fresh.to_dict()
	for nation_id in (partial_payload["nations"] as Dictionary).keys():
		(partial_payload["nations"][nation_id] as Dictionary)["commodity_state"] = {
			"capacity": {"steel": 1.0},
		}
	var partial = GameState.from_dict(partial_payload)
	for i in TICKS:
		Commodities.tick_month(fresh, _loader)
		Commodities.tick_month(loaded, _loader)
		Commodities.tick_month(round_trip, _loader)
		Commodities.tick_month(stripped, _loader)
		Commodities.tick_month(partial, _loader)
	for nation_id in loaded.nations.keys():
		if not _deep_equal(fresh.nations[nation_id].commodity_state, loaded.nations[nation_id].commodity_state):
			_fail("nation %s seeded lazily diverged from a fresh init -- the lazy seed runs the wrong model" % nation_id)
			return
		if not _deep_equal(fresh.nations[nation_id].commodity_state, round_trip.nations[nation_id].commodity_state):
			_fail("nation %s ticked off a real to_dict/from_dict round trip diverged from a fresh init" % nation_id)
			return
		if not _deep_equal(fresh.nations[nation_id].commodity_state, stripped.nations[nation_id].commodity_state):
			_fail("nation %s seeded from a payload with no commodity_state key diverged from a fresh init -- the absent-key arrival is not the bridge's" % nation_id)
			return
		if not _deep_equal(fresh.nations[nation_id].commodity_state, partial.nations[nation_id].commodity_state):
			_fail("nation %s seeded from a PARTIAL commodity_state (one key of seven) diverged from a fresh init -- a partial register must reseed whole, not fault on the missing keys" % nation_id)
			return


## THE CROSSING STAMP (V4.4 pass 22). `ns.commodity_high_month` is the absolute
## month a good's price went from below HIGH_PRICE_RATIO of base to at-or-above it
## across ONE tick, which is what makes the events hook an edge: the world vector
## drifts to its clamp within months, so a level read fired almost every month.
## Three legs, each against a vector STAGED so the answer does not depend on how
## many OTHER goods happen to cross that month:
##   A. a good just below the line that the tick pushes over it stamps the month;
##   B. the vector sitting at-or-above the line before the tick does NOT stamp
##      (the stamp would otherwise re-fire every month it stays high);
##   C. a good that fell back below the line (the fall is STAGED by hand -- the
##      leg tests the second crossing, not why the price fell) and crosses again
##      re-stamps, with the NEW month (a "write only the first crossing" shape
##      would keep the old one).
## The good staged is the one the unmodified world pushes hardest UP, so "the tick
## pushes it over" is a measured premise, checked below, and not an assumption.
func _check_high_crossing_stamp() -> void:
	var probe = _new_state()
	if probe == null:
		return
	var probe_ns = probe.player()
	if probe_ns.commodity_high_month != -1:
		_fail("a fresh game's commodity_high_month reads %d, not -1" % probe_ns.commodity_high_month)
	var rising := ""
	var rise := 1.0
	var goods := _goods_sorted()
	Commodities.tick_month(probe, _loader)
	for good_id in goods:
		var ratio := float(probe_ns.commodity_state["price"][good_id]) / float(_loader.commodity_goods[good_id].base_price)
		if ratio > rise:
			rise = ratio
			rising = String(good_id)
	if rising == "":
		_fail("no good's price rose in the first tick -- the crossing legs have nothing to push over the line")
		return

	var state = _new_state()
	var ns = state.player()
	var prices: Dictionary = ns.commodity_state["price"]
	var line_of := func(good_id) -> float:
		return float(_loader.commodity_goods[good_id].base_price) * CommodityK.HIGH_PRICE_RATIO
	var stage_all_high := func() -> void:
		for good_id in goods:
			prices[good_id] = float(line_of.call(good_id)) * 1.001

	# A. just below the line, pushed over it.
	stage_all_high.call()
	prices[rising] = float(line_of.call(rising)) * 0.999999
	var month_a := int(state.year) * 12 + int(state.month)
	Commodities.tick_month(state, _loader)
	if float(prices[rising]) < float(line_of.call(rising)):
		_fail("%s staged just under the line did not cross it in one tick -- the premise of legs A and C does not hold" % rising)
		return
	if ns.commodity_high_month != month_a:
		_fail("a good crossing the line in month %d left commodity_high_month at %d" % [month_a, ns.commodity_high_month])

	# B. at-or-above the line before the tick: staying high stamps nothing.
	ns.commodity_high_month = -1
	state.month += 1
	stage_all_high.call()
	Commodities.tick_month(state, _loader)
	if ns.commodity_high_month != -1:
		_fail("a vector already above the line stamped month %d -- the hook would fire every month it stays high" % ns.commodity_high_month)

	# C. fell back below the line, crosses again: the NEW month replaces the old.
	state.month += 1
	stage_all_high.call()
	prices[rising] = float(line_of.call(rising)) * 0.999999
	var month_c := int(state.year) * 12 + int(state.month)
	ns.commodity_high_month = month_a
	Commodities.tick_month(state, _loader)
	if ns.commodity_high_month != month_c:
		_fail("a good that fell back and crossed again left commodity_high_month at %d, not the new month %d" % [ns.commodity_high_month, month_c])


## The fixture, and since Task 3 it deliberately does NOT seed: `new_game()` does,
## so this one call is where the init wiring is proven. Seeding here as well would
## have made every check below pass over a game that never seeds a commodity.
func _new_state():
	var state = GameState.new_game(_loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game(FRA) reported %s" % [state.errors])
		return null
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