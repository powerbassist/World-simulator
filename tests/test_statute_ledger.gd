extends SceneTree

## V4.2 T1: the per-law effect ledger and the repeal verb.
##
## The load-bearing pins:
##   - REALIZED, NOT AUTHORED: the ledger records what a law's passage actually
##     moved, taken as a before/after diff around apply_effects() -- the clamp
##     speaks for itself. A law whose write hits a bound records the bound, and
##     a repeal subtracts exactly that;
##   - ACCUMULATION: a non-once law passed twice merges into ONE ledger entry
##     (the statute book is per-act, not per-passage);
##   - REPEAL SUBTRACTS THROUGH THE ONE APPLIER: the negated channels go back
##     through apply_effects(), so budget levers route through Budget.commit()
##     and the erosion/demand machinery fires exactly as any budget change;
##   - REFUSALS: constitutional laws and laws with no ledger entry are not
##     repeal targets -- an institution is SET, not accumulated, and you can
##     only repeal what the book recorded;
##   - ROUND-TRIP: the ledger survives save/load and duplicate_state(); a
##     payload without it reads empty with no error (absence = the pre-38
##     truth: nothing recorded, nothing repealable);
##   - EVENT SILENCE: an event choice calling apply_effects() directly records
##     nothing -- an event is not a statute.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Law = preload("res://src/core/law.gd")
const LK = preload("res://src/sim/legislature_constants.gd")

const PLAYER := "FRA"
const SURTAX := "high_earner_surtax"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
	else:
		_test_realized_equals_authored_when_no_clamp_binds()
		_test_clamp_aware_recording()
		_test_repeal_subtracts_exactly()
		_test_repeal_refusals()
		_test_roundtrip_and_absence()
		_test_duplicate_copies()
		_test_event_silence()
		_test_init_resets()
	_finish()


func _law_by_id(law_id: String):
	for law in _loader.laws:
		if law.id == law_id:
			return law
	return null


func _fresh():
	var gs = GameState.new_game(_loader, PLAYER)
	return [gs, gs.player()]


func _test_realized_equals_authored_when_no_clamp_binds() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var before: float = float(ns.tax_rates_pct.get("income", 0.0))
	var before_business: float = float(ns.bloc_offset.get("business", 0.0))
	var law = _law_by_id(SURTAX)
	if law == null:
		_fail("authored law %s not found" % SURTAX)
		return
	Legislature.apply(gs, ns, law, _loader)
	var entry: Dictionary = ns.law_ledger.get(SURTAX, {})
	if entry.is_empty():
		_fail("no ledger entry recorded for %s" % SURTAX)
		return
	var channels: Dictionary = entry.get("channels", {})
	if is_equal_approx(float(channels.get("tax_rates_pct", {}).get("income", 0.0)), 5.0) == false:
		_fail("income ledger %s, expected 5.0 (authored)" % [channels.get("tax_rates_pct", {})])
	if is_equal_approx(float(channels.get("bloc_offset", {}).get("business", 0.0)), -0.15) == false:
		_fail("business ledger %s, expected -0.15" % [channels.get("bloc_offset", {})])
	if is_equal_approx(float(channels.get("bloc_offset", {}).get("workers", 0.0)), 0.05) == false:
		_fail("workers ledger %s, expected +0.05" % [channels.get("bloc_offset", {})])
	if not is_equal_approx(float(ns.tax_rates_pct.get("income", 0.0)), before + 5.0):
		_fail("income rate did not move by the authored delta")
	if not is_equal_approx(float(ns.bloc_offset.get("business", 0.0)), before_business - 0.15):
		_fail("business bloc did not move by the authored delta")


func _test_clamp_aware_recording() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var law = _law_by_id(SURTAX)
	# Passage 1 from a clean register: realized == authored on every channel.
	Legislature.apply(gs, ns, law, _loader)
	# Hand-drive workers to 0.99. Passage 2's authored workers +0.05 would push
	# past BLOC_OFFSET_MAX, so the realized delta is the BOUND (+0.01) -- this
	# is THE reason the ledger takes a before/after diff instead of the
	# authored effects: a repeal that subtracted +0.05 twice would push the
	# register past its own maximum.
	ns.bloc_offset["workers"] = 0.99
	Legislature.apply(gs, ns, law, _loader)
	var workers: float = float(ns.law_ledger[SURTAX]["channels"]["bloc_offset"].get("workers", 0.0))
	# Merged: +0.05 (passage 1) + 0.01 (passage 2, clamped) = +0.06.
	if not is_equal_approx(workers, 0.06):
		_fail("clamped workers ledger %s, expected 0.06 -- the ledger must record the BOUND, not the authored delta" % workers)
	# The same law's business channel realized -0.15 twice with no clamp in the
	# way: the merge is a plain sum.
	var business: float = float(ns.law_ledger[SURTAX]["channels"]["bloc_offset"].get("business", 0.0))
	if not is_equal_approx(business, -0.30):
		_fail("merged business ledger %s, expected -0.30 (two unclamped passages)" % business)


func _test_repeal_subtracts_exactly() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var income_before: float = float(ns.tax_rates_pct.get("income", 0.0))
	var law = _law_by_id(SURTAX)
	Legislature.apply(gs, ns, law, _loader)
	if not ns.law_ledger.has(SURTAX):
		_fail("repeal test needs a ledger entry")
		return
	var repeal := Law.new()
	repeal.id = "repeal_of_the_surtax"
	repeal.law_name = "Repeal of the High-Earner Surtax"
	repeal.theme = "tax"
	repeal.summary = "Test repeal."
	repeal.position = {"economic": 0.6, "social": 0.0}
	repeal.majority = "simple"
	repeal.repeals = SURTAX
	Legislature.apply(gs, ns, repeal, _loader)
	if not is_equal_approx(float(ns.tax_rates_pct.get("income", 0.0)), income_before):
		_fail("repeal left income at %s, expected %s" % [ns.tax_rates_pct.get("income"), income_before])
	if not is_equal_approx(float(ns.bloc_offset.get("business", 0.0)), 0.0):
		_fail("repeal left business at %s, expected 0.0" % [ns.bloc_offset.get("business")])
	if ns.law_ledger.has(SURTAX):
		_fail("repeal did not erase the target's ledger entry")
	# The repealed act sits out its own cooldown before it can be re-proposed.
	if not ns.law_cooldown_months.has(SURTAX):
		_fail("repeal did not write the target's cooldown")


func _test_repeal_refusals() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	# No ledger entry -> not repealable, whatever else is true about the id.
	if Legislature.repeal_target_legal(ns, _loader, "law_that_never_passed"):
		_fail("a law with no ledger entry must not be a repeal target")
	# A constitutional law with a ledger entry is still refused -- an institution
	# is SET, not accumulated, and a system transition is undone by amendment.
	var amendment = _law_by_id("two_round_presidential")
	if amendment == null:
		# Fall back to any authored constitutional law; the roster carries them.
		for law in _loader.laws:
			if law.constitutional:
				amendment = law
				break
	if amendment != null:
		Legislature.apply(gs, ns, amendment, _loader)
		if Legislature.repeal_target_legal(ns, _loader, amendment.id):
			_fail("constitutional law %s must not be a repeal target" % amendment.id)


func _test_roundtrip_and_absence() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	Legislature.apply(gs, ns, _law_by_id(SURTAX), _loader)
	var d: Dictionary = ns.to_dict()
	var ns2 = NationState.from_dict(d)
	if ns2.law_ledger.get(SURTAX, {}).is_empty():
		_fail("ledger did not survive to_dict/from_dict")
	var d2: Dictionary = ns.to_dict()
	d2.erase("law_ledger")
	var ns3 = NationState.from_dict(d2)
	if not ns3.law_ledger.is_empty():
		_fail("a payload without law_ledger must read empty -- absence is the pre-38 truth")
	if not ns3.law_ledger.get(SURTAX, {}).is_empty():
		_fail("stripped payload resurrected a ledger entry")


func _test_duplicate_copies() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	Legislature.apply(gs, ns, _law_by_id(SURTAX), _loader)
	var s = ns.duplicate_state()
	if s.law_ledger.get(SURTAX, {}).is_empty():
		_fail("duplicate_state dropped the ledger")
	s.law_ledger[SURTAX]["channels"]["bloc_offset"]["business"] = -9.99
	if is_equal_approx(float(ns.law_ledger[SURTAX]["channels"]["bloc_offset"]["business"]), -9.99):
		_fail("duplicate_state shared the ledger dictionary -- a projection would mutate history")


func _test_event_silence() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	# An event choice reaches the same channels through apply_effects() directly
	# and records NOTHING -- an event is not a statute and has no repeal verb.
	Legislature.apply_effects(gs, ns, {"bloc_offset": {"business": -0.2}}, _loader)
	if not ns.law_ledger.is_empty():
		_fail("apply_effects() recorded a ledger entry -- only apply() may")


func _test_init_resets() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	Legislature.apply(gs, ns, _law_by_id(SURTAX), _loader)
	Legislature.init_nation(ns)
	if not ns.law_ledger.is_empty():
		_fail("init_nation did not reset the ledger -- whatever WRITES a field resets it")


func _fail(message: String) -> void:
	_failures.append(message)
	print("FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("OK: all statute ledger checks passed")
		quit(0)
	else:
		print("%d failures" % _failures.size())
		quit(1)
