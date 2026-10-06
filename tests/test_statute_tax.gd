extends SceneTree

## V4.2 T4: custom tax keys through the params register.
##
## The load-bearing pins:
##   - BIRTH: a draft with `new_tax` composes into a law that, on passage,
##     writes BOTH the rate (into tax_rates_pct, through the ONE applier's
##     ordinary channel) AND the params (base_share, erosion, and the birth
##     rate as the erosion reference, into ns.custom_taxes). Registration
##     happens in apply() BEFORE the rate moves -- commit() refuses a pending
##     rate with no params behind it, so a birth that applied its rate first
##     would be refused by its own applier;
##   - ZERO-REFERENCE BY CONSTRUCTION: start_tax_rates_pct has no entry for a
##     key that did not exist at new-game, so the curve's reference is the
##     rate the key was BORN at -- docs/tax-model.md section 2's zero-
##     reference finding working as designed, not a bug;
##   - ONE CURVE: the shared _erosion() runs the custom key -- its own
##     coefficient, the same clamps, no second implementation;
##   - OPINION AT THE DEFAULT SCALE: the custom key prices at TAX_SCALE_PP
##     (16.0) and never at a TAX_SCALE_PP_BY_KEY entry -- per-key overrides
##     are authored constants' privilege;
##   - THE AUTHORED FIVE ARE BIT-IDENTICAL: their revenue lines do not move
##     by one last bit when a custom key exists;
##   - ONE KEY, ONE BIRTH: a second bill proposing the same key is refused;
##   - ONE ACT, MANY PASSAGES (ultra pass 4): the same composed birth law
##     passing twice is ordinary play -- the apply-time re-registration is a
##     quiet no-op (existing params entry wins, the rate re-adds);
##   - REPEAL REMOVES THE RATE, NOT THE TAX: the params entry survives, the
##     way an authored tax nobody charges does;
##   - ROUND-TRIP: rate + params survive save/load and duplicate_state();
##     absence reads empty with no error.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Law = preload("res://src/core/law.gd")
const Statute = preload("res://src/sim/statute.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const C = preload("res://src/sim/economy_constants.gd")

const PLAYER := "FRA"
const KEY := "carbon"
## The brief's own spec: base 0.06 of GDP, erosion 0.7, born at 25 points.
const BIRTH_SPEC := {
	"name": "The Carbon Levy",
	"position": {"economic": -0.5, "social": 0.2},
	"new_tax": {"key": KEY, "name": "The Carbon Levy", "base_share": 0.06, "erosion": 0.7, "rate": 25.0},
}

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
	else:
		_test_birth_writes_rate_and_params()
		_test_revenue_and_the_one_curve()
		_test_opinion_prices_at_the_default_scale()
		_test_authored_five_bit_identical()
		_test_commit_sees_custom_keys()
		_test_one_key_one_birth()
		_test_second_passage_is_a_quiet_noop()
		_test_repeal_keeps_the_params()
		_test_roundtrip_absence_and_duplicate()
		_test_init_resets()
		_test_birth_yield_ceiling()
		_test_reserved_line_names()
		_test_yield_cap_gates_the_reoffer()
		_test_reserved_names_derive_from_the_writer()
		_test_commit_yield_gate()
		_test_negative_params_refused()
		_test_nameless_key_refused()
		_test_tax_key_charset()
	_finish()


## Review fix 1: the birth gate capped base_share and rate INDEPENDENTLY, so
## base 4.0 x rate 100 = 400 % of GDP could be born -- a product nothing else
## brakes. The ceiling anchors at wealth's own max yield (4.0 x 3.0 = 12.0).
func _test_birth_yield_ceiling() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var over := BIRTH_SPEC.duplicate(true)
	over["new_tax"]["key"] = "windfall"
	over["new_tax"]["name"] = "The Windfall Duty"
	over["new_tax"]["base_share"] = 4.0
	over["new_tax"]["rate"] = 100.0
	var r: Dictionary = Statute.draft(gs, ns, _loader, over)
	if bool(r.get("ok", true)):
		_fail("base 4.0 x rate 100 = 400 of GDP must be refused -- the yield ceiling")
	if String(r.get("refusal", "")).find("12.0") == -1:
		_fail("the yield-ceiling refusal must name the product and the anchor: '%s'" % r.get("refusal", ""))
	# Wealth's own shape still passes the gate: 4.0 x 3.0 = 12.0, the anchor.
	var at_anchor := BIRTH_SPEC.duplicate(true)
	at_anchor["new_tax"]["key"] = "windfall"
	at_anchor["new_tax"]["name"] = "The Windfall Duty"
	at_anchor["new_tax"]["base_share"] = 4.0
	at_anchor["new_tax"]["erosion"] = 0.8
	at_anchor["new_tax"]["rate"] = 3.0
	r = Statute.draft(gs, ns, _loader, at_anchor)
	if not bool(r.get("ok", false)):
		_fail("wealth's own shape (4.0 x 3.0 = 12.0) must still draft: %s" % r.get("refusal", ""))


## The ultra pass-6 finding, the SIM half: the birth gate bounds the product at
## draft time only, and commit() applied any pending custom rate unchecked --
## the reviewer's live repro birthed the anchor shape and then cranked the
## register to 4.0 x 100 through the one writer every rate change routes
## through. The gate REFUSES there (loudly, per key), never clamps: a clamp
## would silently re-price the schedule the caller was shown.
func _test_commit_yield_gate() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	# The anchor birth, landed whole: base 4.0, born at 3.0 -- the product AT
	# the ceiling, which is legal (strictly > is the refusal).
	var spec: Dictionary = BIRTH_SPEC.duplicate(true)
	spec["new_tax"]["key"] = "windfall"
	spec["new_tax"]["name"] = "The Windfall Duty"
	spec["new_tax"]["base_share"] = 4.0
	spec["new_tax"]["erosion"] = 0.8
	spec["new_tax"]["rate"] = 3.0
	var r: Dictionary = Statute.draft(gs, ns, _loader, spec)
	if not bool(r.get("ok", false)):
		_fail("setup: the anchor birth must draft: %s" % r.get("refusal", ""))
		return
	var draft_id := String(r["draft_id"])
	for i in range(int(ns.draft_bills[draft_id]["months_left"])):
		Statute.tick_month(gs, _loader)
	Legislature.apply(gs, ns, Law.composed_from_dict(ns.custom_laws[draft_id]), _loader)
	if not is_equal_approx(float(ns.tax_rates_pct.get("windfall", -1.0)), 3.0):
		_fail("setup: the anchor birth must land at 3.0, got %s" % ns.tax_rates_pct.get("windfall"))
		return
	# The crank: 100 points on a 4.0 base is 400 of GDP. Refused, and the
	# register keeps the birth rate -- the rate the books actually price.
	Budget.commit(gs, {"tax_rates_pct": {"windfall": 100.0}})
	if not is_equal_approx(float(ns.tax_rates_pct.get("windfall", -1.0)), 3.0):
		_fail("an over-ceiling commit applied the rate -- refuse, never clamp, got %s" % ns.tax_rates_pct.get("windfall"))
	# The boundary holds in both directions: the anchor itself commits ...
	Budget.commit(gs, {"tax_rates_pct": {"windfall": 3.0}})
	if not is_equal_approx(float(ns.tax_rates_pct.get("windfall", -1.0)), 3.0):
		_fail("a rate AT the product ceiling must still commit, got %s" % ns.tax_rates_pct.get("windfall"))
	# ... and an ordinary under-ceiling move is nobody's business.
	Budget.commit(gs, {"tax_rates_pct": {"windfall": 2.0}})
	if not is_equal_approx(float(ns.tax_rates_pct.get("windfall", -1.0)), 2.0):
		_fail("a rate under the product ceiling (4.0 x 2.0 = 8.0) must commit, got %s" % ns.tax_rates_pct.get("windfall"))


## Review fix 2: `_numeric_nonzero` alone let negative params draft.
func _test_negative_params_refused() -> void:
	for field in ["base_share", "erosion", "rate"]:
		var pair = _fresh()
		var gs = pair[0]
		var spec: Dictionary = BIRTH_SPEC.duplicate(true)
		spec["new_tax"][field] = -1.0
		var r: Dictionary = Statute.draft(gs, pair[1], _loader, spec)
		if bool(r.get("ok", true)):
			_fail("a negative %s must be refused" % field)


## Review fix 3: a nameless new_tax spec birthed a key whose panel label
## read empty -- the params name comes from the spec, not the bill.
func _test_nameless_key_refused() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var spec: Dictionary = BIRTH_SPEC.duplicate(true)
	spec["new_tax"].erase("name")
	var r: Dictionary = Statute.draft(gs, pair[1], _loader, spec)
	if bool(r.get("ok", true)):
		_fail("a nameless new_tax spec must be refused -- a tax needs a name to be argued about")
	if String(r.get("refusal", "")).find("name") == -1:
		_fail("the nameless refusal must say so: '%s'" % r.get("refusal", ""))


## The ultra pass-2 pipe gate: the ledger encodes a tax channel as "tax|<key>"
## and splits on "|", so a key carrying "|" corrupts the record (a birth keyed
## "carbon|tax" became permanently un-repealable while its repeal reported
## carried; "vat|one" mis-split onto an AUTHORED lever). The draft gate refuses
## anything outside [a-z0-9_], length 2..24, and names the rule.
func _test_tax_key_charset() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	for bad in ["carbon|tax", "Carbon", "carbon-tax", "a", "x".repeat(25)]:
		var spec: Dictionary = BIRTH_SPEC.duplicate(true)
		spec["new_tax"]["key"] = bad
		spec["new_tax"]["name"] = "The Pipe Levy"
		var r: Dictionary = Statute.draft(gs, ns, _loader, spec)
		if bool(r.get("ok", true)):
			_fail("tax key '%s' must be refused by the charset gate" % bad)
		if String(r.get("refusal", "")).find("lowercase") == -1:
			_fail("the charset refusal must name the rule: '%s'" % r.get("refusal", ""))
	# The legal form still drafts: digits and underscores, length 2..24.
	var good: Dictionary = BIRTH_SPEC.duplicate(true)
	good["new_tax"]["key"] = "carbon_tax_2"
	good["new_tax"]["name"] = "The Second Carbon Levy"
	var ok: Dictionary = Statute.draft(gs, ns, _loader, good)
	if not bool(ok.get("ok", false)):
		_fail("carbon_tax_2 must pass the charset gate: %s" % ok.get("refusal", ""))


func _fresh():
	var gs = GameState.new_game(_loader, PLAYER)
	return [gs, gs.player()]


## Draft -> countdown -> compose -> apply. Returns the draft id (== the law
## id), or "" after failing.
func _birth_and_pass(gs, ns) -> String:
	var r: Dictionary = Statute.draft(gs, ns, _loader, BIRTH_SPEC.duplicate(true))
	if not bool(r.get("ok", false)):
		_fail("the birth spec must draft: %s" % r.get("refusal", ""))
		return ""
	var draft_id := String(r.get("draft_id", ""))
	for i in range(int(ns.draft_bills[draft_id]["months_left"])):
		Statute.tick_month(gs, _loader)
	if not ns.custom_laws.has(draft_id):
		_fail("the birth did not compose at countdown 0")
		return ""
	var law = Law.composed_from_dict(ns.custom_laws[draft_id])
	if law.new_tax.is_empty():
		_fail("the composed law must carry the params -- apply() has nothing to register otherwise")
		return ""
	if String(law.theme) != "tax":
		_fail("a birth bill must read tax, not '%s'" % law.theme)
	Legislature.apply(gs, ns, law, _loader)
	return draft_id


func _test_birth_writes_rate_and_params() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var draft_id := _birth_and_pass(gs, ns)
	if draft_id == "":
		return
	if not is_equal_approx(float(ns.tax_rates_pct.get(KEY, -1.0)), 25.0):
		_fail("on passage the key must sit in tax_rates_pct at its rate, got %s" % ns.tax_rates_pct.get(KEY))
	if not ns.custom_taxes.has(KEY):
		_fail("on passage the key must have params on the register")
		return
	var params: Dictionary = ns.custom_taxes[KEY]
	if String(params.get("name", "")) != "The Carbon Levy":
		_fail("params name '%s', expected the spec's own name" % params.get("name"))
	if not is_equal_approx(float(params.get("base_share", -1.0)), 0.06):
		_fail("params base_share %s, expected 0.06" % params.get("base_share"))
	if not is_equal_approx(float(params.get("erosion", -1.0)), 0.7):
		_fail("params erosion %s, expected 0.7" % params.get("erosion"))
	if not is_equal_approx(float(params.get("ref_pct", -1.0)), 25.0):
		_fail("params ref_pct %s, expected the birth rate 25.0" % params.get("ref_pct"))


func _test_revenue_and_the_one_curve() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	if ns.start_tax_rates_pct.has(KEY):
		_fail("a fresh game must carry NO start rate for a custom key -- the zero-reference is by construction")
		return
	_birth_and_pass(gs, ns)
	var rates: Dictionary = ns.tax_rates_pct
	var custom: Dictionary = ns.custom_taxes

	# At birth, rate == ref, so the curve reads exactly 1.0 and the yield is
	# base x rate -- the closed form, not a table lookup.
	var at_birth: Dictionary = Budget.revenue_lines(rates, ns.start_tax_rates_pct, 1.0, custom)
	if not is_equal_approx(float(at_birth[KEY]), 0.06 * 25.0):
		_fail("birth yield %s, expected 0.06 x 25.0 x 1.0 (rate == ref -> erosion exactly 1.0)" % at_birth.get(KEY))

	# Zero-reference: an EMPTY reference table gives the identical number --
	# start has no entry, so ref reads 0.0 either way and the curve runs on
	# the birth rate.
	var no_ref: Dictionary = Budget.revenue_lines(rates, {}, 1.0, custom)
	if float(no_ref[KEY]) != float(at_birth[KEY]):
		_fail("the yield must not depend on a start entry that does not exist: %s vs %s" % [no_ref.get(KEY), at_birth.get(KEY)])

	# Raising the rate puts the shared curve's diminishing returns to work:
	# clamp(1.0 - 0.7 x (30 - 25) / 25) -- the ONE _erosion() expression, its
	# coefficient from the spec and its reference from the register.
	ns.tax_rates_pct[KEY] = 30.0
	var raised: Dictionary = Budget.revenue_lines(ns.tax_rates_pct, ns.start_tax_rates_pct, 1.0, custom)
	var expected_curve := clampf(1.0 - 0.7 * (30.0 - 25.0) / 25.0, C.EROSION_MIN, C.EROSION_MAX)
	if float(raised[KEY]) != 0.06 * 30.0 * expected_curve:
		_fail("raised yield %s, expected 0.06 x 30 x %s -- the shared curve, no second implementation"
			% [raised.get(KEY), expected_curve])
	if not is_equal_approx(Budget._erosion(KEY, 30.0, ns.start_tax_rates_pct, custom), expected_curve):
		_fail("_erosion on the custom key must BE the shared curve")

	# The clamps bind as they do for the authored five: a rate far above the
	# reference floors the curve at EROSION_MIN -- a finite, signed number.
	var clamped: Dictionary = Budget.revenue_lines(
		{KEY: 100.0}, ns.start_tax_rates_pct, 1.0, custom)
	if not is_equal_approx(float(clamped[KEY]), 0.06 * 100.0 * C.EROSION_MIN):
		_fail("ceiling yield %s, expected the EROSION_MIN floor" % clamped.get(KEY))


func _test_opinion_prices_at_the_default_scale() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	_birth_and_pass(gs, ns)
	# 8 points over the start reads -8/16 = -0.5 on the SHARED scale; income's
	# own override (24.0) would read -1/3. The default is what a custom key
	# gets -- per-key overrides are authored constants' privilege.
	ns.tax_rates_pct[KEY] = 8.0
	var sat: Dictionary = Opinion.issue_satisfaction(ns)
	if not sat.has("tax_%s" % KEY):
		_fail("opinion must price the custom key")
		return
	if not is_equal_approx(float(sat["tax_%s" % KEY]), -0.5):
		_fail("custom key satisfaction %s, expected -8.0/TAX_SCALE_PP(16.0) = -0.5" % sat["tax_%s" % KEY])
	if is_equal_approx(float(sat["tax_%s" % KEY]), -8.0 / 24.0):
		_fail("the custom key must NOT read a per-key override scale")


func _test_authored_five_bit_identical() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	Budget.recompute(gs, ns)
	var before := {}
	for key in C.TAX_KEYS:
		before[key] = ns.revenue_pct_gdp[key]
	_birth_and_pass(gs, ns)
	Budget.recompute(gs, ns)
	for key in C.TAX_KEYS:
		# Exact float equality: the authored loop, its order and its two
		# tables are untouched, so anything but bit-identity is a defect.
		if ns.revenue_pct_gdp[key] != before[key]:
			_fail("authored line '%s' moved: %s vs %s -- the five must be bit-identical"
				% [key, ns.revenue_pct_gdp[key], before[key]])
	if not is_equal_approx(float(ns.revenue_pct_gdp[KEY]), 1.5):
		_fail("the custom line itself %s, expected 1.5 at the birth rate" % ns.revenue_pct_gdp.get(KEY))


## THE KNOWN GAP T1's report recorded, now closed and pinned: commit() read
## pending rates off the authored five only, so a CUSTOM key in pending was
## silently dropped. The params register is the authorising record -- a key
## with nothing behind it is refused loudly, not applied as a rate that
## yields nothing.
func _test_commit_sees_custom_keys() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	_birth_and_pass(gs, ns)
	Budget.commit(gs, {"tax_rates_pct": {KEY: 30.0}})
	if not is_equal_approx(float(ns.tax_rates_pct.get(KEY, -1.0)), 30.0):
		_fail("commit must apply a pending CUSTOM rate, got %s" % ns.tax_rates_pct.get(KEY))
	Budget.commit(gs, {"tax_rates_pct": {"not_a_tax": 5.0}})
	if ns.tax_rates_pct.has("not_a_tax"):
		_fail("a pending rate with no params on the register must be refused -- the silent half-tax")


func _test_one_key_one_birth() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	_birth_and_pass(gs, ns)
	var second: Dictionary = Statute.draft(gs, ns, _loader, BIRTH_SPEC.duplicate(true))
	if bool(second.get("ok", true)):
		_fail("a second bill proposing the SAME key must be refused -- one key, one birth")
	if String(second.get("refusal", "")).find("already") == -1:
		_fail("the one-birth refusal must name the existing key: '%s'" % second.get("refusal", ""))

	# The ultra pass-3 finding: the gate read only the LANDED register, so two
	# PARKED drafts could carry the key at once -- both accepted, both composing,
	# and the second passage firing _register_new_tax's "impossible" error while
	# its rate still landed. A draft still counting down must refuse. (The
	# error half of that hazard went quiet at pass 4 -- a second passage is a
	# quiet no-op now, see _test_second_passage_is_a_quiet_noop -- but two
	# parked drafts are still refused: the second would be a phantom bill.)
	var parked_pair = _fresh()
	var parked_ns = parked_pair[1]
	var first: Dictionary = Statute.draft(parked_pair[0], parked_ns, _loader, BIRTH_SPEC.duplicate(true))
	if not bool(first.get("ok", false)):
		_fail("the parked-key leg's first draft refused: %s" % first.get("refusal", ""))
		return
	var twin: Dictionary = Statute.draft(parked_pair[0], parked_ns, _loader, BIRTH_SPEC.duplicate(true))
	if bool(twin.get("ok", true)):
		_fail("a second PARKED draft carrying the key must be refused -- the drafted window")
	if String(twin.get("refusal", "")).find("drafted or enacted") == -1:
		_fail("the parked-key refusal must name the window: '%s'" % twin.get("refusal", ""))

	# The composed-but-unproposed window: countdown to completion lands the law
	# on ns.custom_laws WITHOUT registering the key (that happens at passage),
	# and that window is unbounded -- a player can sit on a finished bill for a
	# whole term. A birth key a composed law carries must refuse.
	var composed_pair = _fresh()
	var composed_gs = composed_pair[0]
	var composed_ns = composed_pair[1]
	var queued: Dictionary = Statute.draft(composed_gs, composed_ns, _loader, BIRTH_SPEC.duplicate(true))
	if not bool(queued.get("ok", false)):
		_fail("the composed-window leg's draft refused: %s" % queued.get("refusal", ""))
		return
	var draft_id := String(queued["draft_id"])
	for i in range(int(composed_ns.draft_bills[draft_id]["months_left"])):
		Statute.tick_month(composed_gs, _loader)
	if not composed_ns.custom_laws.has(draft_id):
		_fail("test setup: the draft did not compose -- the leg measures nothing")
		return
	if composed_ns.custom_taxes.has(KEY):
		_fail("test setup: composing registered the key -- the unproposed window no longer exists")
		return
	var after: Dictionary = Statute.draft(composed_gs, composed_ns, _loader, BIRTH_SPEC.duplicate(true))
	if bool(after.get("ok", true)):
		_fail("a key a COMPOSED law carries must be refused -- the enacted window")
	if String(after.get("refusal", "")).find("drafted or enacted") == -1:
		_fail("the composed-window refusal must name the window: '%s'" % after.get("refusal", ""))


## ONE ACT, MANY PASSAGES, the ultra pass-4 finding: composed birth laws are
## once:false by design (statute.gd's _compose), so a second passage of the
## SAME act is ordinary play -- the panel lists every open law with a Propose
## button, and nothing writes a cooldown on a carried birth. The apply-time
## guard is therefore a QUIET no-op: the existing params entry wins and the
## rate re-adds through apply_effects like any repeatable tax law. Only an
## UNNAMED key is refused loudly. (The DRAFT-time gates above stay loud: they
## are what keeps a NEW bill from re-birthing a live key -- this leg re-passes
## the same act, which no draft gate can see.)
func _test_second_passage_is_a_quiet_noop() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var draft_id := _birth_and_pass(gs, ns)
	if draft_id == "":
		return
	var params_before: Dictionary = ns.custom_taxes[KEY]
	var law = Law.composed_from_dict(ns.custom_laws[draft_id])
	Legislature.apply(gs, ns, law, _loader)
	if not is_equal_approx(float(ns.tax_rates_pct.get(KEY, -1.0)), 50.0):
		_fail("the second passage must re-add the rate (25 -> 50), got %s" % ns.tax_rates_pct.get(KEY))
	if ns.custom_taxes[KEY] != params_before:
		_fail("the second passage re-priced the params entry: %s vs %s -- the existing entry wins"
			% [ns.custom_taxes[KEY], params_before])


func _test_repeal_keeps_the_params() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var birth_id := _birth_and_pass(gs, ns)
	if birth_id == "":
		return
	if not Legislature.repeal_target_legal(ns, _loader, birth_id):
		_fail("the bill that created the key must be a legal repeal target")
		return
	var params_before: Dictionary = ns.custom_taxes[KEY]
	var repeal = Law.new()
	repeal.id = "repeal_of_the_carbon_levy"
	repeal.law_name = "Repeal of the Carbon Levy"
	repeal.theme = "tax"
	repeal.summary = "Test repeal."
	repeal.position = {"economic": 0.5, "social": 0.0}
	repeal.majority = "simple"
	repeal.repeals = birth_id
	Legislature.apply(gs, ns, repeal, _loader)
	if not is_equal_approx(float(ns.tax_rates_pct.get(KEY, -1.0)), 0.0):
		_fail("repeal must subtract the rate back to 0, got %s" % ns.tax_rates_pct.get(KEY))
	if not ns.custom_taxes.has(KEY):
		_fail("repeal removes the RATE, not the tax -- the params entry must survive")
		return
	if ns.custom_taxes[KEY] != params_before:
		_fail("the surviving params must be untouched: %s vs %s" % [ns.custom_taxes[KEY], params_before])
	# The tax exists at rate 0, the way an authored tax nobody charges does:
	# a key on the books yielding exactly nothing.
	var lines: Dictionary = Budget.revenue_lines(ns.tax_rates_pct, ns.start_tax_rates_pct, 1.0, ns.custom_taxes)
	if float(lines[KEY]) != 0.0:
		_fail("a rate-0 custom tax yields %s, expected exactly 0.0" % lines.get(KEY))


func _test_roundtrip_absence_and_duplicate() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	_birth_and_pass(gs, ns)
	var d: Dictionary = ns.to_dict()
	var ns2 = NationState.from_dict(d)
	if not ns2.custom_taxes.has(KEY):
		_fail("params did not survive to_dict/from_dict")
		return
	if ns2.custom_taxes[KEY] != ns.custom_taxes[KEY]:
		_fail("round-tripped params differ: %s vs %s" % [ns2.custom_taxes[KEY], ns.custom_taxes[KEY]])
	if not is_equal_approx(float(ns2.tax_rates_pct.get(KEY, -1.0)), 25.0):
		_fail("the rate must survive beside the params -- a silent half-tax otherwise")
	var laws: Array = Statute.custom_laws(ns2)
	if laws.is_empty() or laws[0].new_tax.is_empty():
		_fail("the composed birth law must round-trip its params carrier")
	var d2: Dictionary = ns.to_dict()
	d2.erase("custom_taxes")
	var ns3 = NationState.from_dict(d2)
	if not ns3.custom_taxes.is_empty():
		_fail("a payload without custom_taxes must read empty -- absence is the pre-38 truth")
	var s = ns.duplicate_state()
	s.custom_taxes[KEY]["base_share"] = 9.99
	if is_equal_approx(float(ns.custom_taxes[KEY]["base_share"]), 9.99):
		_fail("duplicate_state shared the params register -- a projection would re-price the real books")


func _test_init_resets() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	_birth_and_pass(gs, ns)
	Legislature.init_nation(ns)
	if not ns.custom_taxes.is_empty():
		_fail("init_nation did not reset the params register -- whatever WRITES a field resets it")


## The ultra pass-17 finding: a birth act is repeatable, but a re-passage
## whose pending product would exceed the yield ceiling changes nothing the
## model can price -- so available() does not offer it. The anchor birth
## (4.0 x 3.0 = 12.0 at birth) is never re-offered; a small birth is.
func _test_yield_cap_gates_the_reoffer() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	# The anchor birth: at the ceiling from its first passage.
	var anchor := BIRTH_SPEC.duplicate(true)
	anchor["new_tax"]["key"] = "windfall"
	anchor["new_tax"]["name"] = "The Windfall Duty"
	anchor["new_tax"]["base_share"] = 4.0
	anchor["new_tax"]["erosion"] = 0.8
	anchor["new_tax"]["rate"] = 3.0
	var r: Dictionary = Statute.draft(gs, ns, _loader, anchor)
	if not bool(r.get("ok", false)):
		_fail("yield-cap fixture: the anchor birth was refused")
		return
	# Compose it the machine's way (tick the draft to completion).
	for i in range(4):
		gs.month = int(gs.month) + 1
		Statute.tick_month(gs, _loader)
	var anchor_law = null
	for composed in Law.composed_register(ns):
		if String(composed.id) == String(r["draft_id"]):
			anchor_law = composed
			break
	if anchor_law == null:
		_fail("yield-cap fixture: the anchor birth did not compose")
		return
	Legislature.apply(gs, ns, anchor_law, _loader)
	# Re-passage would land 6.0 on a 4.0 base -- 24 of GDP. Not offered.
	var offered := false
	for open_law in Legislature.available(ns, _loader.laws + Law.composed_register(ns)):
		if open_law.id == anchor_law.id:
			offered = true
			break
	if offered:
		_fail("the anchor birth's re-passage was offered -- it would price 24 of GDP")
	# The commit backstop still holds: a direct crank is refused, the live
	# birth rate kept.
	Budget.commit(gs, {"tax_rates_pct": {"windfall": 100.0}})
	if not is_equal_approx(float(ns.tax_rates_pct.get("windfall", -1.0)), 3.0):
		_fail("the yield backstop no longer keeps the birth rate")


func _test_reserved_line_names() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	# The ultra pass-15 finding: "other", "tariffs" and "dividends" are the
	# COMPUTED revenue lines Budget.recompute() writes over the modelled dict
	# -- a tax born under one would price approval and demand and collect
	# nothing. All three are refused at draft.
	for reserved in ["other", "tariffs", "dividends"]:
		var spec: Dictionary = BIRTH_SPEC.duplicate(true)
		spec["new_tax"]["key"] = reserved
		var r: Dictionary = Statute.draft(gs, ns, _loader, spec)
		if bool(r.get("ok", false)):
			_fail("a reserved revenue-line name '%s' drafted clean" % reserved)


## The re-deriving pin (the ultra pass-19 finding): the reserved names the
## birth gate refuses are exactly the computed lines Budget.recompute()
## writes over the modelled dict. This file re-derives the set from
## budget.gd's SOURCE so the gate cannot silently drift from the writer --
## a fourth computed line added without growing COMPUTED_REVENUE_LINES
## turns this red.
func _test_reserved_names_derive_from_the_writer() -> void:
	var source := FileAccess.get_file_as_string("res://src/sim/budget.gd")
	var regex := RegEx.new()
	regex.compile('ns[.]revenue_pct_gdp[[]"([a-z_]+)"] *=')
	var derived := {}
	for match_ in regex.search_all(source):
		derived[match_.get_string(1)] = true
	for reserved in Budget.COMPUTED_REVENUE_LINES:
		if not derived.has(reserved):
			_fail("COMPUTED_REVENUE_LINES carries '%s', which budget.gd no longer writes" % reserved)
	for written in derived:
		if not Budget.COMPUTED_REVENUE_LINES.has(written):
			_fail("budget.gd writes computed line '%s' that COMPUTED_REVENUE_LINES does not reserve" % written)


func _fail(message: String) -> void:
	_failures.append(message)
	print("FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("OK: all statute tax checks passed")
		quit(0)
	else:
		print("%d failures" % _failures.size())
		quit(1)
