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
##   - THE MOOT RELEASE (ultra pass 4): a repeal releasing after its target is
##     already repealed applies nothing, records target_already_gone, charges
##     no override -- and an empty-ledger subtraction is a quiet no-op;
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
const Budget = preload("res://src/sim/budget.gd")
const Law = preload("res://src/core/law.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Statute = preload("res://src/sim/statute.gd")
## The ultra pass-6 reader leg: the moot release's verdict is rendered by the
## law panel's result summary, so the pin drives the real panel class.
const LawPanelUi = preload("res://src/ui/law_panel.gd")

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
		_test_budget_floor_on_repeal()
		_test_mixed_moot_release_lands_channels()
		_test_cut_restoration_on_repeal()
		_test_committed_rates_floor_at_zero()
		_test_repeal_refusals()
		_test_once_law_returns_on_repeal()
		_test_consumed_repeal_not_reoffered()
		_test_overlapping_repeals_release_moot()
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


## The ultra pass-8 finding, pinned on the review's own chain: the surtax's
## +5.0 lands, the player cuts income to 0.0 through the budget (a floor every
## UI writer applies), and the repeal's negation must land what the register
## holds -- 0.0, never -5.0. The accumulators' clamps do not reach the two
## budget channels (commit() writes them verbatim), so the floor lives in the
## subtraction itself (`_budget_removal`).
func _test_budget_floor_on_repeal() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var law = _law_by_id(SURTAX)
	Legislature.apply(gs, ns, law, _loader)
	if not is_equal_approx(float(ns.tax_rates_pct.get("income", 0.0)), income_at_fresh() + 5.0):
		_fail("budget-floor fixture: the surtax did not land")
		return
	# The player's own budget action, the way the Tax Code panel commits it.
	Budget.commit(gs, {"tax_rates_pct": {"income": 0.0}})
	if not is_equal_approx(float(ns.tax_rates_pct.get("income", 0.0)), 0.0):
		_fail("budget-floor fixture: the manual cut did not land")
		return
	var repeal := Law.new()
	repeal.id = "repeal_after_the_cut"
	repeal.law_name = "Repeal After The Cut"
	repeal.theme = "tax"
	repeal.summary = "Test repeal against a floored register."
	repeal.position = {"economic": 0.6, "social": 0.0}
	repeal.majority = "simple"
	repeal.repeals = SURTAX
	Legislature.apply(gs, ns, repeal, _loader)
	var landed: float = float(ns.tax_rates_pct.get("income", 0.0))
	if landed < 0.0:
		_fail("repeal negation landed income at %s -- a negative rate is a state no writer refuses into existence" % landed)
	if not is_equal_approx(landed, 0.0):
		_fail("repeal negation landed income at %s, expected the floor 0.0" % landed)
	if ns.law_ledger.has(SURTAX):
		_fail("the floored repeal did not erase the target's entry")


## The ultra pass-13 finding: a MIXED bill (channels + repeals) held by the
## second chamber and released after its target is gone must still land its
## OWN channels -- apply() is every path on which a bill takes effect.
func _test_mixed_moot_release_lands_channels() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var law = _law_by_id(SURTAX)
	Legislature.apply(gs, ns, law, _loader)
	var mixed := Law.new()
	mixed.id = "mixed_release_probe"
	mixed.law_name = "Mixed Release Probe"
	mixed.theme = "tax"
	mixed.summary = "Test mixed bill."
	mixed.position = {"economic": 0.6, "social": 0.0}
	mixed.majority = "simple"
	mixed.repeals = SURTAX
	mixed.effects = {"spending_pct_gdp": {"health": 0.3}}
	# A hand-built law exists only if the register carries it -- the same
	# composed-register fallback the real release path walks.
	ns.custom_laws[mixed.id] = mixed.to_save_dict()
	# Hand-park it the machine's way: the second chamber suspended the mixed
	# bill, and the target's ledger is still live (nothing else repealed it).
	ns.held_bills[mixed.id] = {"months": 1, "origin": "assembly"}
	# A second, PURE repeal of the same target carries while the mixed bill
	# sits in the hold -- the target's book is now empty.
	var pure := Law.new()
	pure.id = "pure_repeal_probe"
	pure.law_name = "Pure Repeal Probe"
	pure.theme = "tax"
	pure.summary = "Test pure repeal."
	pure.position = {"economic": 0.6, "social": 0.0}
	pure.majority = "simple"
	pure.repeals = SURTAX
	Legislature.apply(gs, ns, pure, _loader)
	if ns.law_ledger.has(SURTAX):
		_fail("mixed-moot fixture: the pure repeal did not subtract")
		return
	var health_before: float = float(ns.spending_pct_gdp.get("health", 0.0))
	# Release the mixed bill through the REAL release path.
	Legislature.tick_month(gs, _loader)
	var health_after: float = float(ns.spending_pct_gdp.get("health", 0.0))
	if not is_equal_approx(health_after, health_before + 0.3):
		_fail("a mixed bill's moot release dropped its own channels: health %s -> %s" % [
			health_before, health_after])
	# No target_already_gone flag on a MIXED release: the flag means "why
	# nothing followed", and the bill's own channels did follow -- only a
	# pure repeal's release carries it.

## The ultra pass-9 finding: pass 8's own floor over-clamped the REMOVAL, so
## repealing a CUT restored nothing -- corporate_tax_cut (-5) repealed at a
## live rate of 20 stayed 20 while the book claimed the act was gone. The
## floor belongs on the RESULTING RATE: a cut-restoration passes whole.
func _test_cut_restoration_on_repeal() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var start_corporate: float = float(ns.tax_rates_pct.get("corporate", 0.0))
	var cut = _law_by_id("corporate_tax_cut")
	if cut == null:
		_fail("cut-restoration fixture: corporate_tax_cut not found")
		return
	Legislature.apply(gs, ns, cut, _loader)
	var after_cut: float = float(ns.tax_rates_pct.get("corporate", 0.0))
	if not is_equal_approx(after_cut, start_corporate - 5.0):
		_fail("cut-restoration fixture: the cut did not land (%s)" % after_cut)
		return
	var repeal := Law.new()
	repeal.id = "repeal_of_the_corporate_cut"
	repeal.law_name = "Repeal of the Corporate Tax Relief Act"
	repeal.theme = "tax"
	repeal.summary = "Test repeal of a cut."
	repeal.position = {"economic": -0.6, "social": 0.0}
	repeal.majority = "simple"
	repeal.repeals = "corporate_tax_cut"
	Legislature.apply(gs, ns, repeal, _loader)
	if not is_equal_approx(float(ns.tax_rates_pct.get("corporate", 0.0)), start_corporate):
		_fail("repealing a cut restored nothing: corporate at %s, expected %s" % [
			ns.tax_rates_pct.get("corporate"), start_corporate])


## The ultra pass-9 nit's class, closed at the ONE writer: a composed cut
## bigger than the live rate lands AT zero (priced as cut-to-zero), never
## negative -- including the pre-existing double-passage hole (a repeatable
## cut law passing twice below the live rate).
func _test_committed_rates_floor_at_zero() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	Budget.commit(gs, {"tax_rates_pct": {"vat": -30.0}})
	var vat: float = float(ns.tax_rates_pct.get("vat", 0.0))
	if vat < 0.0:
		_fail("commit landed vat at %s -- the landed-rate floor did not fire" % vat)
	if not is_equal_approx(vat, 0.0):
		_fail("commit's floor landed vat at %s, expected 0.0" % vat)
	var spending_before: float = float(ns.spending_pct_gdp.get("health", 0.0))
	Budget.commit(gs, {"spending_pct_gdp": {"health": spending_before - 999.0}})
	if float(ns.spending_pct_gdp.get("health", 0.0)) < 0.0:
		_fail("commit landed a negative spending line")


func income_at_fresh() -> float:
	var pair = _fresh()
	return float(pair[1].tax_rates_pct.get("income", 0.0))


func _test_repeal_refusals() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	# No ledger entry -> not repealable, whatever else is true about the id.
	if Legislature.repeal_target_legal(ns, _loader, "law_that_never_passed"):
		_fail("a law with no ledger entry must not be a repeal target")
	# A constitutional law with a ledger entry is still refused -- an institution
	# is SET, not accumulated, and a system transition is undone by amendment.
	var amendment = _law_by_id("single_term_reform")
	if amendment == null:
		_fail("authored constitutional law single_term_reform not found")
		return
	Legislature.apply(gs, ns, amendment, _loader)
	# The entry must exist BEFORE the refusal check, or this leg could pass via
	# the no-ledger gate rather than the constitutional gate.
	if not ns.law_ledger.has(amendment.id):
		_fail("constitutional law %s recorded no ledger entry -- the refusal leg is vacuous" % amendment.id)
		return
	if Legislature.repeal_target_legal(ns, _loader, amendment.id):
		_fail("constitutional law %s must not be a repeal target" % amendment.id)
	# A NON-constitutional law that carries effects.institutional is refused too:
	# the ordinary electoral-reform route SETS election_system/threshold, which has
	# no inverse delta, so a repeal would strip only the bloc price and leave the
	# electoral setting in force -- a half-removed act.
	var reform = _law_by_id("proportional_representation_act")
	if reform == null:
		_fail("authored institutional law proportional_representation_act not found")
		return
	Legislature.apply(gs, ns, reform, _loader)
	if reform.constitutional:
		_fail("proportional_representation_act must be non-constitutional for this leg to test the institutional gate")
		return
	if not ns.law_ledger.has(reform.id):
		_fail("institutional law %s recorded no ledger entry -- the refusal leg is vacuous" % reform.id)
		return
	if Legislature.repeal_target_legal(ns, _loader, reform.id):
		_fail("non-constitutional institutional law %s must not be a repeal target -- the setting has no inverse delta" % reform.id)


## THE ONCE RETURN, the ultra pass-2 finding: a once-law's passed flag was
## written at apply() and nothing ever erased it, so a carried repeal removed
## the act for ever while the docs promise "the act returns by being
## re-proposed and re-passed after its cooldown". A carried repeal now clears
## the gate. coal_phase_out_act is a non-constitutional once law with
## cooldown_months 0, so the return is immediate -- both facts asserted.
func _test_once_law_returns_on_repeal() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var law = _law_by_id("coal_phase_out_act")
	if law == null:
		_fail("authored once law coal_phase_out_act not found")
		return
	if not law.once:
		_fail("coal_phase_out_act must be a once law for this leg to mean anything")
		return
	Legislature.apply(gs, ns, law, _loader)
	if not ns.passed_law_ids.has(law.id):
		_fail("setup: applying the once law must set its passed flag")
		return
	var repeal := Law.new()
	repeal.id = "repeal_of_the_coal_phase_out"
	repeal.law_name = "Repeal of the Coal Phase-Out Act"
	repeal.theme = "business"
	repeal.summary = "Test repeal."
	repeal.position = {"economic": 0.5, "social": 0.0}
	repeal.majority = "simple"
	repeal.repeals = law.id
	Legislature.apply(gs, ns, repeal, _loader)
	if ns.passed_law_ids.has(law.id):
		_fail("a carried repeal left the once flag set -- the act can never return")
	var offered := false
	for open_law in Legislature.available(ns, _loader.laws):
		if open_law.id == law.id:
			offered = true
			break
	if int(law.cooldown_months) != 0:
		_fail("the fixture's once law grew a cooldown -- the immediate-return read needs cooldown 0")
	elif not offered:
		_fail("the repealed once law was not re-offered -- the return is still dead")


## A repeal whose target is gone from the book is not proposable -- the ultra
## pass-2 nit. available() re-offered a consumed repealer after its (nonexistent)
## cooldown and a second passage logged "a race or a bug" from the ordinary
## propose path; the filter kills the no-op and keeps _subtract_ledger's
## premise honest.
func _test_consumed_repeal_not_reoffered() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	Legislature.apply(gs, ns, _law_by_id(SURTAX), _loader)
	var repeal := Law.new()
	repeal.id = "repeal_of_the_surtax"
	repeal.law_name = "Repeal of the High-Earner Surtax"
	repeal.theme = "tax"
	repeal.summary = "Test repeal."
	repeal.position = {"economic": 0.6, "social": 0.0}
	repeal.majority = "simple"
	repeal.repeals = SURTAX
	Legislature.apply(gs, ns, repeal, _loader)
	if ns.law_ledger.has(SURTAX):
		_fail("setup: the target's ledger entry must be gone after the carried repeal")
		return
	var offered := false
	for open_law in Legislature.available(ns, [repeal]):
		if open_law.id == repeal.id:
			offered = true
			break
	if offered:
		_fail("a consumed repealer was re-offered -- its next passage is a carried no-op")


## THE MOOT RELEASE, the ultra pass-4 finding: two repeal drafts of one target
## BOTH compose (repeal_target_legal gates on the live ledger, and the repeal
## side has no one-in-flight gate), the first parks as an assembly-origin hold,
## the second proposes, carries and SUBTRACTS -- and the held first then
## releases with nothing left to subtract. The release must apply nothing,
## mark its record with why, and charge no override price; the empty-ledger
## subtraction behind it is a quiet no-op, not the "race or a bug" error the
## propose-path filter's comment used to promise could not happen.
func _test_overlapping_repeals_release_moot() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var income_before: float = float(ns.tax_rates_pct.get("income", 0.0))
	Legislature.apply(gs, ns, _law_by_id(SURTAX), _loader)
	if not ns.law_ledger.has(SURTAX):
		_fail("setup: the target needs a ledger entry")
		return
	var spec := {
		"name": "Repeal of the High-Earner Surtax",
		"position": {"economic": -0.3, "social": 0.0},
		"channels": {},
		"repeals": SURTAX,
	}
	var first: Dictionary = Statute.draft(gs, ns, _loader, spec.duplicate(true))
	var second: Dictionary = Statute.draft(gs, ns, _loader, spec.duplicate(true))
	if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
		_fail("two repeal drafts of one target must both compose -- the finding's premise: '%s' / '%s'"
			% [first.get("refusal", ""), second.get("refusal", "")])
		return
	# _tick_drafts, not tick_month: the assembly's own hazard would table bills
	# beside the countdown, and this leg needs a held-bill population of one.
	for i in range(int(ns.draft_bills[String(first["draft_id"])]["months_left"])):
		Statute._tick_drafts(ns)
	var laws: Array = Statute.custom_laws(ns)
	if laws.size() != 2 or String(laws[0].repeals) != SURTAX or String(laws[1].repeals) != SURTAX:
		_fail("the two repeal drafts did not compose as a pair (%d laws)" % laws.size())
		return
	# Hand-park the FIRST as an assembly-origin hold -- the exact shape
	# statute.gd's suspensive refusal writes -- then propose the second, which
	# carries and subtracts under it.
	ns.held_bills[String(laws[0].id)] = {"months": 1, "origin": "assembly"}
	var result: Dictionary = Legislature.propose(gs, _loader, laws[1])
	if not bool(result.get("passed", false)):
		_fail("test setup: the second repeal must carry for this leg to mean anything: %s" % [result])
		return
	if ns.law_ledger.has(SURTAX):
		_fail("setup: the second repeal must have emptied the target's ledger")
		return
	# Tick the hold out with the registers snapshotted: a no-op release must
	# move nothing, record honestly, and charge nothing.
	var bloc_before: Dictionary = ns.bloc_offset.duplicate(true)
	var ledger_keys: Array = ns.law_ledger.keys()
	Legislature.tick_month(gs, _loader)
	if ns.held_bills.has(String(laws[0].id)):
		_fail("the hold did not release after its month")
		return
	var released: Dictionary = ns.last_law_result
	if String(released.get("law_id", "")) != String(laws[0].id):
		_fail("the release tick recorded the wrong law: '%s'" % released.get("law_id", ""))
		return
	if not bool(released.get("released", false)) or not bool(released.get("passed", false)):
		_fail("the release lost its passed/released record: %s" % [released])
		return
	# THE PIN: the record says WHY nothing followed the hold's expiry.
	if not bool(released.get("target_already_gone", false)):
		_fail("a release whose target was already repealed carried no target_already_gone mark: %s" % [released])
	if released.has("override_offset"):
		_fail("a moot release charged the override price nobody incurred")
	for bloc in bloc_before:
		if not is_equal_approx(float(ns.bloc_offset.get(bloc, 0.0)), float(bloc_before[bloc])):
			_fail("the moot release moved %s -- a no-op must write no price" % bloc)
	if ns.law_ledger.keys() != ledger_keys:
		_fail("the moot release touched the ledger: %s vs %s" % [ns.law_ledger.keys(), ledger_keys])
	if not is_equal_approx(float(ns.tax_rates_pct.get("income", 0.0)), income_before):
		_fail("the target must stay repealed -- income at %s, expected %s"
			% [ns.tax_rates_pct.get("income"), income_before])
	# THE READER (ultra pass 6): the record's one surface is the law panel's
	# result summary, and until now it read the released branch -- "IN FORCE,
	# over the SENAT" against a release that changed nothing, with a Yes 0 -
	# No 0 tally for a chamber that never sat. Driven on the real panel class:
	# the writer-side pins above could not see that half. The builder needs
	# only _state/_loader (it builds its own box), so the panel never enters
	# the tree -- _ready() has not run out here, and everything below is
	# hand-freed Node memory.
	var panel = LawPanelUi.new()
	panel._state = gs
	panel._loader = _loader
	var summary: Control = panel._build_result_summary(released)
	var text := _summary_text(summary)
	summary.free()
	panel.free()
	if text.find("IN FORCE") != -1:
		_fail("a moot release still reads IN FORCE: %s" % text)
	if text.find("MOOT") == -1:
		_fail("a moot release carries no MOOT verdict: %s" % text)
	if text.find("Abstain 0") != -1:
		_fail("a moot release prints a seat tally for a division that never sat: %s" % text)


## The summary box's full text: every Label, walked deep (PanelKit lines are
## direct children; the seat tally is a bare Label beside them).
func _summary_text(node: Node) -> String:
	var out := ""
	for child in node.get_children():
		if child is Label:
			out += String(child.text) + "\n"
		else:
			out += _summary_text(child)
	return out


func _test_roundtrip_and_absence() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	Legislature.apply(gs, ns, _law_by_id(SURTAX), _loader)
	var d: Dictionary = ns.to_dict()
	var ns2 = NationState.from_dict(d)
	if ns2.law_ledger.get(SURTAX, {}).is_empty():
		_fail("ledger did not survive to_dict/from_dict")
	# One concrete channel value AND the month stamp, not just entry presence --
	# a round trip that re-keyed or re-typed the payload would still be non-empty.
	if is_equal_approx(float(ns2.law_ledger[SURTAX]["channels"].get("bloc_offset", {}).get("business", 0.0)), -0.15) == false:
		_fail("round-tripped business bloc %s, expected -0.15" % [ns2.law_ledger[SURTAX]["channels"].get("bloc_offset", {})])
	if ns2.law_ledger[SURTAX].get("months", []) != ns.law_ledger[SURTAX]["months"]:
		_fail("round-trip lost the month stamps: %s vs %s" % [ns2.law_ledger[SURTAX].get("months"), ns.law_ledger[SURTAX]["months"]])
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
