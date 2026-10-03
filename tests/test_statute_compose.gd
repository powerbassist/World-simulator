extends SceneTree

## V4.2 T2: the composition machine and the drafting budget.
##
## The load-bearing pins:
##   - REFUSALS: an empty channel set, an unknown channel (bloc_offset and
##     institutional alike -- the price is the machine's, the settings are
##     authored content's), a position outside [-1, 1], an over-budget size,
##     and a new_tax key colliding with the authored five (T4 wires the real
##     tax params; the refusal lands now, and so does refusing a VALID
##     new_tax -- an accepted-but-unwired param would be silently dropped at
##     passage, the half-applied state this project refuses);
##   - THE BUDGET IS ARITHMETIC: size sums CHANNEL_COST over the spec's
##     magnitudes, months = DRAFT_MONTHS_BASE + size x DRAFT_MONTHS_PER_SIZE
##     (rounded up), and the derived price is NON-EMPTY -- the all-upside
##     guard, priced per the authored laws the table mirrors;
##   - COMPOSITION: the parked draft counts down in tick_month() and at 0
##     becomes a Law in custom_laws (origin "player", composed, once=false,
##     cooldown DRAFT_COOLDOWN_MONTHS, effects = channels + derived price).
##     Entries stay parked at months_left 0 -- the id scheme reads
##     draft_bills.size(), so an erased entry could hand a later draft a used
##     id;
##   - THE LEGALITY SCAN FINDS COMPOSED LAWS: propose() must accept a custom
##     law, or the player's own bill would be refused as unavailable;
##   - A REPEAL DRAFT records the negated ledger it was shown, and the
##     composed bill carries `repeals` WITHOUT freezing the negation into its
##     effects -- T1's subtraction is live-at-passage, and an effects copy
##     would subtract twice. The task leg says "effects carry the negated
##     ledger"; the ledger is carried on the draft (the panel's preview) and
##     the subtraction fires through T1's machinery, which is the reading
##     that does not double-apply;
##   - DETERMINISM, ROUND-TRIP (no aliasing), ABSENCE (empty, no error).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Law = preload("res://src/core/law.gd")
const Statute = preload("res://src/sim/statute.gd")
const SK = preload("res://src/sim/statute_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

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
		_test_refusals()
		_test_one_channel_spec()
		_test_countdown_composes()
		_test_propose_accepts_custom_law()
		_test_repeal_draft()
		_test_determinism()
		_test_roundtrip_absence_and_duplicate()
		_test_init_resets()
		_test_price_table_blocs()
	_finish()


func _law_by_id(law_id: String):
	for law in _loader.laws:
		if law.id == law_id:
			return law
	return null


func _fresh():
	var gs = GameState.new_game(_loader, PLAYER)
	return [gs, gs.player()]


func _one_channel_spec() -> Dictionary:
	return {
		"name": "Middle Income Rate Adjustment",
		"position": {"economic": -0.4, "social": 0.0},
		"channels": {"tax_rates_pct": {"income": 2.0}},
	}


func _test_refusals() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var base := {"name": "Test Bill", "position": {"economic": 0.0, "social": 0.0}}

	var r: Dictionary = Statute.draft(gs, ns, _loader,
		{"name": "Empty Bill", "position": {"economic": 0.0, "social": 0.0}, "channels": {}})
	if bool(r.get("ok", true)):
		_fail("an empty channel set with no repeal target must be refused")

	var unknown := base.duplicate()
	unknown["channels"] = {"bloc_offset": {"business": -0.1}}
	r = Statute.draft(gs, ns, _loader, unknown)
	if bool(r.get("ok", true)):
		_fail("bloc_offset is the machine's own derived price, never a spec channel")

	var institutional := base.duplicate()
	institutional["channels"] = {"institutional": {"election_system": "pr_national"}}
	r = Statute.draft(gs, ns, _loader, institutional)
	if bool(r.get("ok", true)):
		_fail("institutional must be refused -- T1's contract: a composed law is never authored with a setting, or it is unrepealable at birth")

	var outside := base.duplicate()
	outside["channels"] = {"tax_rates_pct": {"income": 1.0}}
	outside["position"] = {"economic": 1.5, "social": 0.0}
	r = Statute.draft(gs, ns, _loader, outside)
	if bool(r.get("ok", true)):
		_fail("a position outside [-1, 1] must be refused")

	var over := base.duplicate()
	over["channels"] = {"tax_rates_pct": {"income": 40.0}}
	r = Statute.draft(gs, ns, _loader, over)
	if bool(r.get("ok", true)):
		_fail("an over-budget size (40 points x 0.2 = 8.0 of 6.0) must be refused")

	var colliding := base.duplicate()
	colliding["channels"] = {"tax_rates_pct": {"income": 1.0}}
	colliding["new_tax"] = {"key": "vat", "base_share": 0.05, "erosion": 0.7, "rate": 10.0}
	r = Statute.draft(gs, ns, _loader, colliding)
	if bool(r.get("ok", true)):
		_fail("a new_tax key colliding with the authored five must be refused")
	if String(r.get("refusal", "")).find("already exists") == -1:
		_fail("the collision refusal must name the collision, not a generic refusal: '%s'" % r.get("refusal", ""))

	var unwired := base.duplicate()
	unwired["channels"] = {"tax_rates_pct": {"income": 1.0}}
	unwired["new_tax"] = {"key": "carbon", "base_share": 0.06, "erosion": 0.7, "rate": 25.0}
	r = Statute.draft(gs, ns, _loader, unwired)
	if bool(r.get("ok", true)):
		_fail("a VALID new_tax must be refused at T2 -- accepted but unwired it would be silently dropped at passage")

	if not ns.draft_bills.is_empty():
		_fail("a refused draft must not park anything")


func _test_one_channel_spec() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var r: Dictionary = Statute.draft(gs, ns, _loader, _one_channel_spec())
	if not bool(r.get("ok", false)):
		_fail("a one-channel spec inside the budget must draft: %s" % r.get("refusal", ""))
		return
	var size := float(r.get("size", -1.0))
	if not is_equal_approx(size, 0.4):
		_fail("size %s, expected 0.4 (2.0 points x CHANNEL_COST 0.2)" % size)
	if size >= SK.DRAFT_SIZE_MAX:
		_fail("a one-channel spec must sit below DRAFT_SIZE_MAX")
	var months := int(r.get("months", -1))
	if months != SK.DRAFT_MONTHS_BASE + int(ceil(size * SK.DRAFT_MONTHS_PER_SIZE)):
		_fail("months %d, expected %d (base + size x per-size, rounded up)"
			% [months, SK.DRAFT_MONTHS_BASE + int(ceil(size * SK.DRAFT_MONTHS_PER_SIZE))])
	var price: Dictionary = r.get("price", {})
	if price.is_empty():
		_fail("the derived price must be NON-EMPTY -- the all-upside guard")
	if not is_equal_approx(float(price.get("business", 0.0)), -0.06):
		_fail("business price %s, expected -0.06 (the surtax anchor row: -0.03 per point)"
			% price.get("business", 0.0))
	if not is_equal_approx(float(price.get("workers", 0.0)), 0.02):
		_fail("workers price %s, expected +0.02 (the anchor row: +0.01 per point)"
			% price.get("workers", 0.0))
	var draft_id := String(r.get("draft_id", ""))
	if draft_id == "" or not ns.draft_bills.has(draft_id):
		_fail("an accepted draft must be parked under its id")
		return
	if int(ns.draft_bills[draft_id]["months_left"]) != months:
		_fail("the parked entry must carry the full countdown")


func _test_countdown_composes() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var r: Dictionary = Statute.draft(gs, ns, _loader, _one_channel_spec())
	var draft_id := String(r["draft_id"])
	var months := int(r["months"])
	if Statute.drafts(ns).size() != 1:
		_fail("the in-tray read must show a parked draft")
	for i in range(months - 1):
		Statute.tick_month(gs, _loader)
	if not ns.custom_laws.is_empty():
		_fail("the law must not exist before the countdown reaches 0")
	if int(ns.draft_bills[draft_id]["months_left"]) != 1:
		_fail("countdown %d after %d ticks, expected 1"
			% [int(ns.draft_bills[draft_id]["months_left"]), months - 1])
	Statute.tick_month(gs, _loader)
	if ns.custom_laws.is_empty():
		_fail("the countdown reached 0 and composed nothing")
	var laws: Array = Statute.custom_laws(ns)
	if laws.size() != 1:
		_fail("expected exactly one composed law, got %d" % laws.size())
		return
	var law = laws[0]
	if not law.composed:
		_fail("the composed law must carry composed=true")
	if law.origin != "player":
		_fail("origin '%s', expected 'player'" % law.origin)
	if law.once:
		_fail("a composed law is re-proposable: once must be false")
	if law.cooldown_months != SK.DRAFT_COOLDOWN_MONTHS:
		_fail("cooldown %d, expected DRAFT_COOLDOWN_MONTHS %d"
			% [law.cooldown_months, SK.DRAFT_COOLDOWN_MONTHS])
	if not is_equal_approx(float(law.effects["tax_rates_pct"]["income"]), 2.0):
		_fail("the composed effects must carry the spec's channel")
	if not law.effects.has("bloc_offset"):
		_fail("the composed effects must carry the derived price")
	if not is_equal_approx(float(law.effects["bloc_offset"].get("business", 0.0)), -0.06):
		_fail("the composed bloc price drifted from the derived one")
	if int(ns.draft_bills[draft_id]["months_left"]) != 0:
		_fail("the parked entry stays at months_left 0 -- never erased, the id scheme reads size()")
	if not Statute.drafts(ns).is_empty():
		_fail("the in-tray read must filter settled drafts out")
	# A settled draft is inert: the tick composes nothing twice.
	Statute.tick_month(gs, _loader)
	if ns.custom_laws.size() != 1:
		_fail("a settled draft composed again")


func _test_propose_accepts_custom_law() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	Statute.draft(gs, ns, _loader, _one_channel_spec())
	for i in range(int(ns.draft_bills.values()[0]["months_left"])):
		Statute.tick_month(gs, _loader)
	var law = Statute.custom_laws(ns)[0]
	var result: Dictionary = Legislature.propose(gs, _loader, law)
	if bool(result.get("unavailable", false)):
		_fail("propose() must accept a custom law -- the legality scan must find it in the concat")


func _test_repeal_draft() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var income_before: float = float(ns.tax_rates_pct.get("income", 0.0))
	Legislature.apply(gs, ns, _law_by_id(SURTAX), _loader)
	if not ns.law_ledger.has(SURTAX):
		_fail("the repeal-draft leg needs a ledger entry")
		return
	var r: Dictionary = Statute.draft(gs, ns, _loader, {
		"name": "Repeal of the High-Earner Surtax",
		"position": {"economic": 0.6, "social": 0.0},
		"channels": {},
		"repeals": SURTAX,
	})
	if not bool(r.get("ok", false)):
		_fail("a repeal of a recorded, non-institutional law must draft: %s" % r.get("refusal", ""))
		return
	# The draft records the negated ledger the player was shown.
	var negated: Dictionary = ns.draft_bills[String(r["draft_id"])].get("negated", {})
	if not is_equal_approx(float(negated.get("tax_rates_pct", {}).get("income", 0.0)), -5.0):
		_fail("the draft's negated preview must carry the target's ledger, negated")
	# An unknown target has no record and drafts nothing.
	var r2: Dictionary = Statute.draft(gs, ns, _loader, {
		"name": "Ghost Repeal", "position": {"economic": 0.0, "social": 0.0},
		"channels": {}, "repeals": "law_that_never_passed",
	})
	if bool(r2.get("ok", true)):
		_fail("a law with no ledger entry must not draft as a repeal")
	# An institutional law with a ledger entry is still refused -- the setting
	# has no inverse delta, so the repeal would be a half-removed act. This leg
	# is why draft() needs the loader: the target lookup cannot run without it.
	Legislature.apply(gs, ns, _law_by_id("proportional_representation_act"), _loader)
	var r3: Dictionary = Statute.draft(gs, ns, _loader, {
		"name": "Repeal of the PR Act", "position": {"economic": 0.0, "social": 0.0},
		"channels": {}, "repeals": "proportional_representation_act",
	})
	if bool(r3.get("ok", true)):
		_fail("an institutional law must not draft as a repeal -- the setting has no inverse delta")
	# Compose and pass; T1's subtraction fires on the LIVE ledger.
	for i in range(int(r["months"])):
		Statute.tick_month(gs, _loader)
	var laws: Array = Statute.custom_laws(ns)
	if laws.is_empty():
		_fail("the repeal draft composed nothing")
		return
	var law = laws[0]
	if law.repeals != SURTAX:
		_fail("the composed bill must carry repeals='%s', got '%s'" % [SURTAX, law.repeals])
	if law.effects.has("tax_rates_pct"):
		_fail("a composed repeal must NOT freeze the negated ledger into its effects -- T1 subtracts live at passage, and an effects copy would subtract twice")
	Legislature.apply(gs, ns, law, _loader)
	if not is_equal_approx(float(ns.tax_rates_pct.get("income", 0.0)), income_before):
		_fail("passage left income at %s, expected the pre-law %s -- T1's subtraction did not fire"
			% [ns.tax_rates_pct.get("income"), income_before])
	if ns.law_ledger.has(SURTAX):
		_fail("passage did not erase the target's ledger entry")
	if not ns.law_cooldown_months.has(SURTAX):
		_fail("passage did not write the target's cooldown")


func _test_determinism() -> void:
	var a = _fresh()
	var b = _fresh()
	var spec := _one_channel_spec()
	var ra: Dictionary = Statute.draft(a[0], a[1], _loader, spec)
	var rb: Dictionary = Statute.draft(b[0], b[1], _loader, spec)
	if String(ra["draft_id"]) != String(rb["draft_id"]):
		_fail("identical states must draw identical draft ids: %s vs %s"
			% [ra["draft_id"], rb["draft_id"]])
	var entry_a: Dictionary = a[1].draft_bills[String(ra["draft_id"])]
	var entry_b: Dictionary = b[1].draft_bills[String(rb["draft_id"])]
	if entry_a != entry_b:
		_fail("identical states must park identical draft entries")
	if ra.get("price", {}) != rb.get("price", {}):
		_fail("identical specs must derive identical prices")


func _test_roundtrip_absence_and_duplicate() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	Statute.draft(gs, ns, _loader, _one_channel_spec())
	for i in range(int(ns.draft_bills.values()[0]["months_left"])):
		Statute.tick_month(gs, _loader)
	Statute.draft(gs, ns, _loader, {
		"name": "Still Parked Bill", "position": {"economic": 0.3, "social": -0.2},
		"channels": {"spending_pct_gdp": {"health": 0.5}},
	})

	var d: Dictionary = ns.to_dict()
	var ns2 = NationState.from_dict(d)
	if ns2.draft_bills != ns.draft_bills:
		_fail("draft_bills did not survive to_dict/from_dict")
	var laws: Array = Statute.custom_laws(ns2)
	if laws.size() != 1:
		_fail("custom_laws did not survive to_dict/from_dict")
		return
	var law2 = laws[0]
	if not is_equal_approx(float(law2.effects["tax_rates_pct"]["income"]), 2.0):
		_fail("the round-tripped law lost its channel")
	if not is_equal_approx(float(law2.effects["bloc_offset"]["business"]), -0.06):
		_fail("the round-tripped law lost its derived price")
	if law2.cooldown_months != SK.DRAFT_COOLDOWN_MONTHS or law2.origin != "player" or not law2.composed:
		_fail("the round-tripped law lost its composition marks")

	# No aliasing: the loaded register must not share a dictionary with the live one.
	ns2.custom_laws.values()[0]["effects"]["tax_rates_pct"]["income"] = -9.0
	if is_equal_approx(float(Statute.custom_laws(ns)[0].effects["tax_rates_pct"]["income"]), -9.0):
		_fail("from_dict shared the custom_laws payload -- the save would mutate with the run")

	var s = ns.duplicate_state()
	s.draft_bills.values()[0]["months_left"] = 99
	if int(ns.draft_bills.values()[0]["months_left"]) == 99:
		_fail("duplicate_state shared draft_bills -- a projection would tick the live in-tray")
	s.custom_laws.values()[0]["cooldown_months"] = 7
	if int(ns.custom_laws.values()[0]["cooldown_months"]) == 7:
		_fail("duplicate_state shared custom_laws")

	var d2: Dictionary = ns.to_dict()
	d2.erase("draft_bills")
	d2.erase("custom_laws")
	var ns3 = NationState.from_dict(d2)
	if not ns3.draft_bills.is_empty() or not ns3.custom_laws.is_empty():
		_fail("absence must read empty with no error")


func _test_init_resets() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	Statute.draft(gs, ns, _loader, _one_channel_spec())
	for i in range(int(ns.draft_bills.values()[0]["months_left"])):
		Statute.tick_month(gs, _loader)
	Legislature.init_nation(ns)
	if not ns.draft_bills.is_empty() or not ns.custom_laws.is_empty():
		_fail("init_nation did not reset the composition registers -- whatever WRITES a field resets it")


## The price table is hand-authored, so its bloc vocabulary can drift from the
## one the opinion model actually reads -- a misspelled bloc would sit in the
## derived price as a dead key nobody prices. Read as data, the house
## source-scan idiom.
func _test_price_table_blocs() -> void:
	for bloc in _table_blocs(SK.CHANNEL_PRICE["tax_rates_pct"]):
		if not OpinionK.BLOC_KEYS.has(bloc):
			_fail("CHANNEL_PRICE tax row names '%s', which is not a BLOC_KEYS member" % bloc)
	for key in SK.CHANNEL_PRICE["spending_pct_gdp"]:
		for direction in ["rise", "cut"]:
			var row: Dictionary = SK.CHANNEL_PRICE["spending_pct_gdp"][key].get(direction, {})
			if row.is_empty():
				_fail("spending row '%s' is missing its '%s' price -- a cut and a rise differ" % [key, direction])
			for bloc in row:
				if not OpinionK.BLOC_KEYS.has(bloc):
					_fail("CHANNEL_PRICE spending row '%s' names '%s', which is not a BLOC_KEYS member" % [key, bloc])
	for scalar in ["structural_unemployment_pct", "potential_growth_pct", "other_revenue_pct_gdp", "company"]:
		for bloc in SK.CHANNEL_PRICE[scalar]:
			if not OpinionK.BLOC_KEYS.has(bloc):
				_fail("CHANNEL_PRICE %s names '%s', which is not a BLOC_KEYS member" % [scalar, bloc])
	for term in SK.CHANNEL_PRICE["society"]:
		for bloc in SK.CHANNEL_PRICE["society"][term]:
			if not OpinionK.BLOC_KEYS.has(bloc):
				_fail("CHANNEL_PRICE society '%s' names '%s', which is not a BLOC_KEYS member" % [term, bloc])


func _table_blocs(tax_table: Dictionary) -> Array:
	var out: Array = []
	for key in tax_table:
		for bloc in tax_table[key]:
			out.append(bloc)
	return out


func _fail(message: String) -> void:
	_failures.append(message)
	print("FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("OK: all statute compose checks passed")
		quit(0)
	else:
		print("%d failures" % _failures.size())
		quit(1)
