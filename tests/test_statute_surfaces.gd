extends SceneTree

## Headless test: godot --headless --script res://tests/test_statute_surfaces.gd
## Non-zero exit on any failure.
##
## V4.2 T5's UI surfaces, pinned the test_industry_surfaces way -- the real
## main.tscn, driven a frame at a time, read through LIVE controls (queue_free
## is deferred; a refresh's reaped children still carry their text on the same
## frame). Every leg here can fail silently, which is the class this file
## exists for:
##
##   (a) the Tax Code window on KEY_X, one row per live key off the
##       ns.tax_rates_pct REGISTER -- a composed key appears when it exists,
##       and no hand-written roster decides what the player can move;
##   (b) "Propose a tax" opening the birth flow, the draft landing in the
##       in-tray, and the briefing carrying its drafting months;
##   (c) the briefing on Propose naming channels, direction, magnitude and
##       the LANDED price's offended blocs;
##   (d) both paid polls: bought once per bill, cost to the purchase register
##       AND to the debt stock, a second commission refused;
##   (e) the bought assembly poll firming the forecast to ABSTAIN_BAND for
##       THAT bill alone;
##   (f) the bought popular poll narrowing the bloc read to +-1.0;
##   (g) purchases riding save/load; absence meaning none bought;
##   (h) the single-writer pin: no src/sim file reads `poll_purchases`
##       except statute.gd's buy_poll -- the register remembers money, not
##       display, and the surfaces reach it directly;
##   (i) the law panel's ASSEMBLY BILLS section: a staged in-tray entry
##       (hand-written in the machine's own shape, the way this file stages
##       firms) shows its row and its Endorse button, the press calls
##       endorse() (the entry's bonus moves), and the spent verb is replaced
##       by the endorsed line -- the verb was player-unreachable before the
##       section existed, which is why the leg can fail silently and lives
##       here.
##   (j) the division card's memory keys the DIVISION'S OWN MONTH -- the
##       machine's assembly_division_month stamp -- so a quiet month cannot
##       re-announce a division (driven on the real announcer, twice);
##   (k) the load path clears the bill-id memories and SEEDS the two month
##       memories from the loaded result's own stamp, so the first month
##       elapsed after a save+load cannot re-announce the loaded division or
##       release (driven through the REAL _on_load_requested);
##   (l) the reversal preview's dual company shape: effect_lines() reads both
##       the {sector, burden} effects shape and the ledger's {sector: delta},
##       or a regulation repeal's "It reverses" drops its one line; and the
##       bloc reversal rides the same walk under include_bloc (the default
##       walk stays silent -- the price section prints the price already);
##   (n) the result summary resolves composed laws -- a staged register entry
##       renders its NAME, never the raw draft_NNNN id;
##   (o) the briefing detaches on the real load path: hidden, and no reference
##       to the discarded GameState survives (the V2.8 drift class).

const Law = preload("res://src/core/law.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const BriefingUi = preload("res://src/ui/briefing.gd")
const LawPanelUi = preload("res://src/ui/law_panel.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const Statute = preload("res://src/sim/statute.gd")
const StatuteK = preload("res://src/sim/statute_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const C = preload("res://src/sim/economy_constants.gd")

const POLL_SLOT := "__test_poll_surfaces__"

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let _ready() run
	_run()
	_finish()
	return false


func _run() -> void:
	if _main._state == null:
		_fail("main scene did not build a GameState")
		return
	var state = _main._state
	var loader = _main._loader
	var ns = state.player()
	var panel = _main._tax_panel
	var briefing = _main._briefing
	var law_panel = _main._law_panel

	# --- (a) The Tax Code window: KEY_X, rows off the register -------------
	if _main._windows.shortcut("tax") != KEY_X:
		_fail("the tax panel is not registered on KEY_X")
	panel.setup(state, loader)
	panel._on_revert()
	panel._refresh()
	var base_rows: int = ns.tax_rates_pct.size() + 1  # the brackets lever
	if _slider_count(panel) != base_rows:
		_fail("expected %d lever rows off the register + brackets, found %d" % [base_rows, _slider_count(panel)])
	# THE RATE AS A NUMBER: every row prints a figure that parses as one.
	for key in panel._lever_keys():
		var text := String(panel._lever_values[key].text)
		if text.contains("—") or not text.is_valid_float():
			_fail("the rate row for '%s' prints '%s', which is not a number" % [key, text])
	if float(panel._sliders["income"].max_value) != 70.0:
		_fail("the income slider lost its authored ceiling")
	if not is_equal_approx(float(panel._sliders["wealth"].max_value), C.WEALTH_RATE_MAX_PCT):
		_fail("the wealth slider must read the model bound, not a copied number")

	# A composed key appears when it exists -- staged exactly as apply()
	# writes it (params + rate), and never by an edit to the panel.
	ns.custom_taxes["carbon"] = {
		"name": "The Carbon Levy", "base_share": 0.06, "erosion": 0.7, "ref_pct": 25.0}
	ns.tax_rates_pct["carbon"] = 25.0
	panel.mark_dirty()
	panel._refresh()
	if _slider_count(panel) != base_rows + 1:
		_fail("a staged composed key built no row -- the scan is not off the register")
	if not _live_text_has(panel, "The Carbon Levy"):
		_fail("the composed key's row is not named off the params register")
	if float(panel._sliders["carbon"].max_value) != StatuteK.NEW_TAX_RATE_MAX:
		_fail("a low-base born key (0.06) lost its full rate range -- the max is matched to the BASE (12.0 / 0.06 = 200), so minf keeps NEW_TAX_RATE_MAX the cap")
	# THE OTHER SIDE OF THAT RULE (the ultra pass-6 finding): a HIGH base pulls
	# the max DOWN to its own yield bound. The old fallback offered 100 points
	# on every born key, so a base-4.0 key was one drag from a 400-of-GDP
	# yield the ceiling's own rationale declares unpriceable -- the slider must
	# top at 12.0 / 4.0 = 3.0.
	ns.custom_taxes["heavy"] = {
		"name": "The Stock Levy", "base_share": 4.0, "erosion": 0.8, "ref_pct": 3.0}
	ns.tax_rates_pct["heavy"] = 3.0
	panel.mark_dirty()
	panel._refresh()
	if not is_equal_approx(float(panel._sliders["heavy"].max_value),
			StatuteK.NEW_TAX_YIELD_CEILING / 4.0):
		_fail("a base-4.0 born key's slider tops at %s, expected 3.0 -- the product gate" % panel._sliders["heavy"].max_value)
	# THE COMMIT GATE is sim-side, because the panel is not the only writer: a
	# rate the slider can no longer produce is still REFUSED at Budget.commit
	# (push_error + skip, never a silent clamp), and the register keeps the
	# birth rate.
	var heavy_rate: float = float(ns.tax_rates_pct["heavy"])
	## expects-error: budget: base .* rate for 'heavy' refused
	Budget.commit(state, {"tax_rates_pct": {"heavy": 100.0}})
	if not is_equal_approx(float(ns.tax_rates_pct["heavy"]), heavy_rate):
		_fail("an over-ceiling commit applied the rate -- it must refuse, not clamp")
	# Strictly >, like the birth gate: the anchor product (4.0 x 3.0 = 12.0)
	# commits, so the gate bounds the product and not the act of committing.
	Budget.commit(state, {"tax_rates_pct": {"heavy": 3.0}})
	if not is_equal_approx(float(ns.tax_rates_pct["heavy"]), 3.0):
		_fail("a rate AT the product ceiling must still commit, got %s" % ns.tax_rates_pct["heavy"])
	ns.custom_taxes.erase("heavy")
	ns.tax_rates_pct.erase("heavy")
	panel.mark_dirty()
	panel._refresh()

	# --- (b) "Propose a tax" opens the birth flow and drafts ---------------
	_press(_find_button(panel, "Propose a tax"))
	if not panel._compose_box.visible:
		_fail("Propose a tax did not open the composition flow")
	panel._draft_name.text = "The Digital Levy"
	panel._draft_key.text = "digital"
	panel._base_slider.value = 0.3
	panel._erosion_slider.value = 0.5
	panel._rate_slider.value = 12.0
	var debt_before_draft: float = ns.debt_eur_bn
	panel._on_draft()
	if ns.draft_bills.is_empty():
		_fail("the draft button drafted nothing")
	if not briefing.visible:
		_fail("an accepted draft did not open the briefing")
	# A pure birth names no channel: zero drafting size, two base months.
	if not _live_text_has(briefing, "In drafting: 2 months"):
		_fail("the draft briefing does not carry the drafting months")
	if not _live_text_has(briefing, "no bloc directly"):
		_fail("a zero-price bill's briefing does not say so")
	if absf(ns.debt_eur_bn - debt_before_draft) > 1e-9:
		_fail("drafting a bill moved money -- only a passed poll or act may")
	# The refusal is the panel's to show, verbatim from the machine.
	panel._draft_key.text = "income"
	panel._on_draft()
	if not panel._refusal.visible:
		_fail("a refused draft showed no refusal line")

	# --- (c) The briefing on Propose: channels, price, offended blocs ------
	var surtax = _law_by_id(loader, "high_earner_surtax")
	law_panel._on_propose(surtax)
	if not briefing.visible:
		_fail("Propose did not open the briefing")
	# One effects walk serves rows and attribution: the line the walk builds.
	if not _live_text_has(briefing, "Raises the income tax rate by 5.0 points."):
		_fail("the briefing does not name the channel, direction and magnitude")
	if not _live_text_has(briefing, "Business") or not _live_text_has(briefing, "It offends: Business."):
		_fail("the briefing does not name the price's offended bloc")
	# THE LANDED PRICE, not the quote: T3's recorded bound lets the derived
	# price quote past the clamp; the display must show what the applier
	# writes. An authored bill sits inside the bound, so the numbers agree
	# here -- the clamp branch itself is pinned below on a composed bill.
	var landed_seen := false
	for bloc in surtax.effects.get("bloc_offset", {}):
		var landed: float = clampf(float(surtax.effects["bloc_offset"][bloc]), LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX)
		if _live_text_has(briefing, "%+.2f" % landed):
			landed_seen = true
	if not landed_seen:
		_fail("the briefing shows no landed price figure")

	# The clamp note, on a price that really does quote past the bound: a
	# deep infrastructure cut prices urban at -0.45 per point (the machine's
	# own table), so -3.0 quotes -1.35 against the +-1.0 clamp.
	var spec := {
		"name": "The Overwhelming Bill",
		"position": {"economic": 0.5, "social": 0.5},
		"channels": {"spending_pct_gdp": {"infrastructure": -3.0}},
	}
	var quoted: Dictionary = Statute.draft(state, ns, loader, spec)
	if not bool(quoted.get("ok", false)):
		_fail("the clamp leg's spec refused: %s" % quoted.get("refusal", ""))
	else:
		var entry: Dictionary = ns.draft_bills[String(quoted["draft_id"])]
		var quote: float = float(entry["price"].get("urban", 0.0))
		briefing.open_for_draft(entry, String(quoted["draft_id"]), state, loader)
		if absf(quote) <= LK.BLOC_OFFSET_MAX:
			_fail("the clamp leg's spec no longer quotes past the bound (urban %.2f) -- rewrite it, do not drop the pin" % quote)
		elif not _live_text_has(briefing, "%+.2f" % clampf(quote, LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX)):
			_fail("a clamped price is not shown at its landed value")
		elif not _live_text_has(briefing, "lands clamped"):
			_fail("a quote past the bound is not marked as clamped")

	# --- (d) The two paid polls ---------------------------------------------
	# Back on the authored bill: the clamp leg left the briefing on a draft,
	# and the purchase must land on the law id the forecast reads.
	briefing.open_for_law(surtax, state, loader)
	var debt_before: float = ns.debt_eur_bn
	var assembly_btn := _find_button(briefing, "assembly poll")
	if assembly_btn == null:
		_fail("the briefing built no assembly poll button")
	else:
		_press(assembly_btn)
	var poll_cost: float = ns.debt_eur_bn - debt_before
	var expected_cost: float = float(ns.gdp_eur_bn) * float(StatuteK.POLL_COSTS["assembly"]) / 100.0
	if absf(poll_cost - expected_cost) > 1e-9:
		_fail("the assembly poll charged %.4f, expected %.4f (%%GDP through the level)" % [poll_cost, expected_cost])
	var bought: Dictionary = ns.poll_purchases.get("high_earner_surtax", {})
	if not bought.has("assembly"):
		_fail("the assembly purchase is not on the register")
	var second: Dictionary = Statute.buy_poll(state, ns, "high_earner_surtax", "assembly")
	if bool(second.get("ok", true)) or not bool(second.get("refused", false)):
		_fail("a second assembly commission was not refused -- the fixed-forecast rule")
	if absf(ns.debt_eur_bn - (debt_before + expected_cost)) > 1e-9:
		_fail("a refused commission charged money")

	# The popular poll, on another bill -- each kind once per bill.
	var carbon = _law_by_id(loader, "carbon_levy")
	if carbon != null:
		law_panel._on_propose(carbon)
		var debt2: float = ns.debt_eur_bn
		var popular_btn := _find_button(briefing, "popular poll")
		if popular_btn == null:
			_fail("the briefing built no popular poll button")
		else:
			# The ultra pass-3 finding: the label read "Commission an popular
			# poll". Pinned on the rendered button because the substring find
			# above matches inside the wrong label too -- the exact silent
			# class this file exists for.
			if not String(popular_btn.text).contains("Commission a popular poll"):
				_fail("the popular poll button's article is wrong: '%s'" % popular_btn.text)
			_press(popular_btn)
		var expected2: float = float(ns.gdp_eur_bn) * float(StatuteK.POLL_COSTS["popular"]) / 100.0
		if absf(ns.debt_eur_bn - (debt2 + expected2)) > 1e-9:
			_fail("the popular poll charged the wrong one-off")
		if not ns.poll_purchases.get("carbon_levy", {}).has("popular"):
			_fail("the popular purchase is not on the register")
		# (f) the bought popular poll narrows the bloc read to +-1.0, and the
		# rows are exactly the precise hash the function publishes.
		var id := PollNoise.poll_id(int(state.year), int(state.month))
		for bloc in K.BLOC_KEYS:
			var truth: float = float(ns.bloc_approval.get(bloc, 0.0))
			var shown: float = PollNoise.displayed_precise(id, "carbon_levy|%s" % bloc, truth)
			if absf(shown - truth) > PollNoise.PRECISE_MAX_PCT + 1e-9:
				_fail("displayed_precise left its own band for %s" % bloc)
			if not _live_text_has(briefing, "%.1f" % shown):
				_fail("the briefing's bloc read for %s is not the precise figure" % bloc)
		if not _live_text_has(briefing, "Commissioned poll"):
			_fail("the bought popular poll's margin line is missing")
		# And the narrowing is real: the ordinary band DOES exceed one point
		# for some (id, key), so +-1.0 is a purchase and not the world.
		var widened := false
		for i in range(40):
			for bloc in K.BLOC_KEYS:
				if absf(PollNoise.offset(id + i, "carbon_levy|%s" % bloc)) > PollNoise.PRECISE_MAX_PCT:
					widened = true
		if not widened:
			_fail("no ordinary offset exceeds the precise band -- the narrowing proves nothing")

	# The bought button is dead -- the fixed-forecast rule, made visible.
	law_panel._on_propose(surtax)
	var bought_btn := _find_button(briefing, "assembly poll")
	if bought_btn != null and not bought_btn.disabled:
		_fail("a bought poll's commission button is still live")

	# --- (e) The forecast firms for THAT bill alone -------------------------
	if not is_equal_approx(LawPanelUi.forecast_band(ns, "high_earner_surtax"), LK.ABSTAIN_BAND):
		_fail("the bought assembly poll did not firm the forecast band")
	if not is_equal_approx(LawPanelUi.forecast_band(ns, "carbon_levy"), 0.15):
		_fail("an unbilled bill's forecast must stay blurred at 0.15")
	_run_forecast_walk(ns, loader)

	# --- (g) Purchases ride save/load; absence is none bought ---------------
	var err: String = SaveManager.save_game(state, _main._clock, POLL_SLOT)
	if err != "":
		_fail("save failed: %s" % err)
	var result: Dictionary = SaveManager.load_game(POLL_SLOT, loader)
	if not bool(result.get("ok", false)):
		_fail("load failed: %s" % result.get("error", ""))
	else:
		var reloaded = result["state"].player()
		if reloaded.poll_purchases.size() != ns.poll_purchases.size():
			_fail("the purchase register did not survive the round trip")
		for bill_key in ns.poll_purchases:
			for kind in ns.poll_purchases[bill_key]:
				var rec: Dictionary = reloaded.poll_purchases.get(bill_key, {}).get(kind, {})
				if rec.is_empty():
					_fail("a purchase is missing after load (%s %s)" % [bill_key, kind])
				elif int(rec["month"]) != int(ns.poll_purchases[bill_key][kind]["month"]):
					_fail("a purchase's month moved across the round trip")
	SaveManager.delete_slot(POLL_SLOT)
	# A projection's copy is its own: the deep-copy discipline, one register on.
	var dup = state.duplicate_state()
	dup.player().poll_purchases["solo"] = {"assembly": {"month": 1, "cost": 1.0}}
	if ns.poll_purchases.has("solo"):
		_fail("duplicate_state aliased the purchase register")
	# And a new game is nobody having bought anything.
	Legislature.init_nation(ns)
	if not ns.poll_purchases.is_empty():
		_fail("init_nation left purchases behind")

	# --- (h) The single-writer pin ------------------------------------------
	# The WRITE-side reset lives in legislature.init_nation (where law_ledger
	# resets), so a raw name scan over src/sim would flag it. The scan is the
	# house read/write-shape idiom pointed the other way: statute.gd is the
	# one reader-writer; every other sim line that touches the register and is
	# not a bare `= {}` reset is a read the register's contract forbids.
	var readers := _sim_reads_purchases()
	if not readers.is_empty():
		_fail("src/sim reads poll_purchases outside the writer: %s" % ", ".join(readers))
	# The UI half of the pin: the surfaces DO read it -- a pin that cannot
	# fail when the reader disappears is decoration.
	for path in ["res://src/ui/briefing.gd", "res://src/ui/law_panel.gd"]:
		if not FileAccess.get_file_as_string(path).contains("poll_purchases"):
			_fail("%s no longer reads the purchase register -- the pins outlived the feature" % path)

	# display_precise's additive contract, at the function: the ordinary
	# displayed() is untouched.
	if absf(PollNoise.offset(1234, "x")) > PollNoise.NOISE_MAX_PCT + 1e-9:
		_fail("the ordinary poll noise moved")
	if StatuteK.POLL_COSTS.size() != 2:
		_fail("the price list grew without a commission button to match")

	# --- (i) The assembly-bills section: the endorse verb is reachable ------
	# Staged exactly as _table_bill writes the in-tray entry -- the machine's
	# own five-key shape, the way this file stages firms -- with the assembly
	# test's fixture law and chief. The card has said all along that the
	# stand is the president's to take; this leg pins the surface that
	# finally offers it.
	ns.assembly_bills["pmb_surfaces"] = {
		"law_id": "retirement_age_reform",
		"months_left": StatuteK.PMB_MONTHS_TO_VOTE,
		"backer_firm": "FRA_aurignac",
		"backer_chief": "FRA_chief_aurignac",
		"endorse_bonus": 0.0,
	}
	law_panel.mark_dirty()
	law_panel._refresh()
	var staged_law = _law_by_id(loader, "retirement_age_reform")
	var bill_label: String = staged_law.law_name if staged_law != null else "retirement_age_reform"
	if not _live_text_has(law_panel, bill_label):
		_fail("the staged assembly bill built no row on the law panel")
	if not _live_text_has(law_panel, loader.firm_name(ns.id, "FRA_aurignac")):
		_fail("the lobbied bill's row does not name its backer firm")
	if not _live_text_has(law_panel, loader.person_name("FRA_chief_aurignac")):
		_fail("the lobbied bill's row does not name the backer chief")
	var endorse_btn := _find_button(law_panel, "Endorse")
	if endorse_btn == null:
		_fail("the staged bill offers no Endorse button -- the stand is unreachable again")
	else:
		_press(endorse_btn)
	if float(ns.assembly_bills.get("pmb_surfaces", {}).get("endorse_bonus", 0.0)) <= 0.0:
		_fail("pressing Endorse left the in-tray bonus at zero -- endorse() never ran")
	# One stand per bill: the spent verb is REPLACED by the record, the
	# companies panel's shape -- a live button here could only ever refuse.
	law_panel.mark_dirty()
	law_panel._refresh()
	if _find_button(law_panel, "Endorse") != null:
		_fail("an endorsed bill still offers Endorse -- one stand per bill")
	if not _live_text_has(law_panel, "Endorsed"):
		_fail("the endorsed bill shows no endorsed line")
	# THE STALE PRESS: the bill resolved between the click and the refresh --
	# the one reachable refusal, endorse() refusing a bill no longer in the
	# in-tray. The handler is driven directly (the pin is the DISPLAY, not
	# the press) and the refusal must survive INTO the refresh that shows it:
	# round 2's dead-display pair was the refresh erasing what it should
	# print, and the section's empty early-return swallowing it after that.
	ns.assembly_bills.erase("pmb_surfaces")
	law_panel._on_endorse("pmb_surfaces")
	law_panel.mark_dirty()
	law_panel._refresh()
	if not _live_text_has(law_panel, "There is no such bill before the assembly."):
		_fail("a refused endorse printed no refusal line -- the display is dead as wired")
	law_panel._endorse_refusal = ""

	# --- (j) The division card keys the DIVISION'S OWN MONTH ----------------
	# The review's finding: the guard used to compare the memory against the
	# CURRENT month, so every quiet month re-announced the last division until
	# a new law event overwrote it. Driven on the real announcer: push once,
	# advance the clock, call again, and the card count must not move.
	var cards_before: int = _main._hud.message_stack._cards.size()
	var stamp: int = int(state.year) * 12 + int(state.month)
	# The FULL division shape resolve_vote() writes -- the law panel's result
	# summary reads the tally and party_votes off this same dictionary on the
	# next frame, so a thinner fixture would be a script error, not a pin.
	ns.last_law_result = {
		"assembly_bill": true, "bill_id": "pmb_card", "law_id": "retirement_age_reform",
		"passed": false, "majority": "simple",
		"yes_seats": 115, "no_seats": 307, "abstain_seats": 0, "seats_total": 577,
		"party_votes": {}, "party_support": {}, "party_rebels": {},
		"assembly_division_month": stamp,
	}
	_main._assembly_news.announce()
	if int(_main._assembly_news._assembly_result_month) != stamp:
		_fail("the card memory did not take the division's own month stamp")
	var after_first: int = _main._hud.message_stack._cards.size()
	if after_first != cards_before + 1:
		_fail("the division card did not push exactly once (%d -> %d)" % [cards_before, after_first])
	state.month = int(state.month) + 1
	if int(state.month) > 12:
		state.month = 1
		state.year = int(state.year) + 1
	_main._assembly_news.announce()
	if _main._hud.message_stack._cards.size() != after_first:
		_fail("a quiet month re-announced the division -- the memory must key the stamp, not the clock")

	# --- (k) The load boundary honours the stamp, not a reset ---------------
	# The ultra pass-7 finding, reproduced live: the handler reset both month
	# memories to -1 while the LOADED register keeps leg (j)'s division stamp,
	# so the first month elapsed after a save+load re-announced the loaded
	# division as news -- evicting a live card behind it (MAX_CARDS 6, oldest
	# dropped). The bill-id maps still belong to the discarded game; the two
	# month memories are seeded FROM the loaded result instead. Driven through
	# the REAL handler, the same reason leg (g) drives the real save/load pair.
	var err2: String = SaveManager.save_game(state, _main._clock, POLL_SLOT)
	if err2 != "":
		_fail("the load leg's save failed: %s" % err2)
	else:
		_main._assembly_news._announced_assembly_bills["ghost_bill"] = true
		_main._assembly_news._assembly_cards["ghost_bill"] = "card_ghost"
		_main._assembly_news._assembly_result_month = 42
		_main._assembly_news._assembly_release_month = 43
		_main._on_load_requested(POLL_SLOT)
		SaveManager.delete_slot(POLL_SLOT)
		# The load drops the discarded game's whole stack (V5.1-a2), so the count the
		# first month must NOT move is the one the load itself left, not the count
		# before it.
		var cards_after_load: int = _main._hud.message_stack._cards.size()
		if not _main._assembly_news._announced_assembly_bills.is_empty() or not _main._assembly_news._assembly_cards.is_empty():
			_fail("the load path left the bill-id memories behind -- they belong to the discarded game")
		# THE SEED: the saved register carries leg (j)'s division fixture, so
		# the division memory must land on ITS stamp and the release memory on
		# none -- a reset to -1 here is the stale re-announce below.
		var reloaded_ns = _main._state.player()
		var loaded_stamp := int(reloaded_ns.last_law_result.get("assembly_division_month", -1))
		if loaded_stamp < 0 or int(_main._assembly_news._assembly_result_month) != loaded_stamp:
			_fail("the load path did not seed the division memory from the loaded stamp (memory %s, register %s) -- the next month re-announces it" % [
				_main._assembly_news._assembly_result_month, loaded_stamp])
		if int(_main._assembly_news._assembly_release_month) != -1:
			_fail("a loaded DIVISION seeded the release memory (%s)" % _main._assembly_news._assembly_release_month)
		# The live-repro month: one month elapsed on the loaded game, and the
		# stale card must NOT fire. The announcer is driven directly, the
		# collision leg's quiet-month precedent -- a full _on_month_elapsed
		# would let the assembly table a NEW bill, whose tabling card would
		# legitimately move the count and spoil the pin.
		reloaded_ns.assembly_bills.clear()
		var y := int(_main._state.year)
		var m := int(_main._state.month) + 1
		if m > 12:
			m = 1
			y += 1
		_main._state.year = y
		_main._state.month = m
		_main._assembly_news.announce()
		if _main._hud.message_stack._cards.size() != cards_after_load:
			_fail("the first month after load re-announced the loaded division -- the load boundary must honour the stamp")
		# THE RELEASE VARIANT, by symmetry: the release stamp rides the same
		# register (legislature.gd writes it there), so a loaded RELEASE seeds
		# the release slot and never the division's -- a swap would silently
		# re-arm the wrong once-only memory.
		reloaded_ns.last_law_result = {
			"assembly_bill": true, "law_id": "retirement_age_reform",
			"passed": true, "released": true, "majority": "simple",
			"yes_seats": 0, "no_seats": 0, "abstain_seats": 0, "seats_total": 577,
			"party_votes": {}, "party_support": {}, "party_rebels": {},
			"upper_chamber": String(reloaded_ns.upper_chamber_name),
			"assembly_division_month": loaded_stamp,
		}
		var err3: String = SaveManager.save_game(_main._state, _main._clock, POLL_SLOT)
		if err3 != "":
			_fail("the load leg's release save failed: %s" % err3)
		else:
			_main._on_load_requested(POLL_SLOT)
			SaveManager.delete_slot(POLL_SLOT)
			if int(_main._assembly_news._assembly_release_month) != loaded_stamp:
				_fail("the load path did not seed the release memory from the loaded release (memory %s, register %s)" % [
					_main._assembly_news._assembly_release_month, loaded_stamp])
			if int(_main._assembly_news._assembly_result_month) != -1:
				_fail("a loaded RELEASE seeded the division memory (%s)" % _main._assembly_news._assembly_result_month)

	# --- (l) The reversal preview's dual company shape ----------------------
	# A negated ledger keys the burden channel BY SECTOR ({sector: delta},
	# legislature.gd's ledger shape) where a bill's effects carry {sector,
	# burden}. Without the second reading a regulation repeal's "It reverses"
	# preview printed its heading over zero lines -- silent, misleading by
	# omission, on the statute book's headline verb.
	var ledger_lines: Array[String] = BriefingUi.effect_lines({"company": {"industry": -0.3}}, ns)
	var lifted := false
	for line in ledger_lines:
		if line == "Lifts a burden of 0.30 on the Industry sector.":
			lifted = true
	if not lifted:
		_fail("a negated sector burden produced no reversal line: %s" % [ledger_lines])
	var effects_lines: Array[String] = BriefingUi.effect_lines(
		{"company": {"sector": "industry", "burden": 0.3}}, ns)
	var imposed := false
	for line in effects_lines:
		if line == "Imposes a burden of 0.30 on the Industry sector.":
			imposed = true
	if not imposed:
		_fail("the effects-shape burden line regressed: %s" % [effects_lines])

	# (m) The reversal walk renders the BLOC reversal too -- the ultra pass-2
	# finding: a negated ledger carries the bloc deltas the repeal re-applies,
	# and effect_lines() dropped them, so the preview named every channel but
	# the one a political-price-bearing repeal most moves. Default stays OFF:
	# the price section's own walk must not print the price rows a second time.
	var bloc_lines: Array[String] = BriefingUi.effect_lines(
		{"bloc_offset": {"business": -0.15}}, ns, true)
	var bloc_moved := false
	for line in bloc_lines:
		if line == "Moves the Business bloc's approval price by -0.15.":
			bloc_moved = true
	if not bloc_moved:
		_fail("a negated bloc delta produced no reversal line: %s" % [bloc_lines])
	if not BriefingUi.effect_lines({"bloc_offset": {"business": -0.15}}, ns).is_empty():
		_fail("bloc_offset leaked into the default walk -- the price section would print its rows twice")

	# (n) The result summary resolves composed laws -- the ultra pass-2 finding:
	# _find_law scanned the loader only, so every composed division, held bill
	# and referendum printed the raw draft_NNNN id on the panel that lists the
	# laws. Staged in the register's own to_save_dict shape (the machine's).
	# The LIVE state: leg (k)'s load rebounded every panel to the loaded game.
	var live_state = _main._state
	var live_loader = _main._loader
	var live_ns = live_state.player()
	live_ns.custom_laws["draft_424242"] = {
		"id": "draft_424242", "name": "The Composed Namesake Act",
		"theme": "labour", "summary": "",
		"position": {"economic": 0.0, "social": 0.0},
		"majority": "simple", "cooldown_months": 24, "once": false,
		"effects": {"other_revenue_pct_gdp": 0.2}, "new_tax": {},
		"repeals": "", "composed": true, "origin": "player",
	}
	live_ns.last_law_result = {
		"law_id": "draft_424242", "passed": false, "majority": "simple",
		"yes_seats": 115, "no_seats": 307, "abstain_seats": 0, "seats_total": 577,
		"party_votes": {}, "party_support": {}, "party_rebels": {},
	}
	law_panel.mark_dirty()
	law_panel._refresh()
	if not _live_text_has(law_panel, "The Composed Namesake Act — FAILED"):
		_fail("the result summary printed a raw draft id instead of the composed name")
	live_ns.custom_laws.erase("draft_424242")
	live_ns.last_law_result = {}

	# (p) The held-bill blocks promise the override price only where it is
	# charged -- the ultra pass-3 finding: the clause rode unconditioned on
	# both the held list and the division record, while an assembly-origin
	# hold releases free (nobody insisted on a PMB). Both origins rendered,
	# the cost sentence asserted on the player's side alone.
	live_ns.held_bills["carbon_levy"] = {"months": 5, "origin": "player"}
	law_panel.mark_dirty()
	law_panel._refresh()
	if not _live_text_has(law_panel, "overriding them costs"):
		_fail("a held government bill's block lost the override clause")
	live_ns.held_bills["carbon_levy"]["origin"] = "assembly"
	law_panel.mark_dirty()
	law_panel._refresh()
	if _live_text_has(law_panel, "overriding them costs"):
		_fail("a held assembly bill's block still promises the override price")
	if not _live_text_has(law_panel, "comes into force"):
		_fail("a held assembly bill's block lost the coming-into-force sentence")
	live_ns.held_bills.erase("carbon_levy")
	# The division record's own held line, same branch keyed on the result's
	# assembly marker (the record carries no origin -- the marker is what the
	# machine stamps assembly divisions with).
	live_ns.last_law_result = {
		"law_id": "carbon_levy", "passed": false, "majority": "simple",
		"yes_seats": 318, "no_seats": 259, "abstain_seats": 0, "seats_total": 577,
		"party_votes": {}, "party_support": {}, "party_rebels": {},
		"upper_chamber": live_ns.upper_chamber_name,
		"upper_power": "suspensive", "upper_passed": false,
		"upper_yes_seats": 100, "upper_no_seats": 200, "upper_abstain_seats": 48,
		"upper_seats_total": 348,
		"held_by_upper": true, "held_months": 9,
	}
	law_panel.mark_dirty()
	law_panel._refresh()
	if not _live_text_has(law_panel, "overriding them costs"):
		_fail("a held government division's record lost the override clause")
	live_ns.last_law_result["assembly_bill"] = true
	law_panel.mark_dirty()
	law_panel._refresh()
	if _live_text_has(law_panel, "overriding them costs"):
		_fail("a held assembly division's record still promises the override price")
	if not _live_text_has(law_panel, "comes into force"):
		_fail("a held assembly division's record lost the coming-into-force sentence")
	live_ns.last_law_result = {}

	# (o) The briefing does not hold the dead state across a load -- the ultra
	# pass-2 finding, the V2.8 drift class one panel deeper: the briefing is
	# not in the registry, so the load path's setup() sweep never rebinds it,
	# and an open briefing kept the discarded GameState (its poll verb wrote
	# the dead run's books). Driven through the REAL load handler, leg (k)'s
	# reason: a detach the handler skips is exactly the defect.
	law_panel._on_propose(_law_by_id(live_loader, "high_earner_surtax"))
	if not briefing.visible:
		_fail("setup: the briefing did not open for the detach leg")
	var err3: String = SaveManager.save_game(live_state, _main._clock, POLL_SLOT)
	if err3 != "":
		_fail("the detach leg's save failed: %s" % err3)
	else:
		_main._on_load_requested(POLL_SLOT)
		SaveManager.delete_slot(POLL_SLOT)
		if briefing.visible:
			_fail("the briefing stayed open across a load -- a dead popup still answers clicks")
		if briefing._state != null:
			_fail("the briefing kept the discarded GameState across a load")
		if briefing._ns != null:
			_fail("the briefing kept the discarded nation across a load")


## The forecast walk, on a synthetic bill positioned so one party's support
## sits strictly inside (ABSTAIN_BAND, FORECAST_UNCERTAIN_BAND): blurred, its
## seats read undecided; firmed, they read yes or no. This is what the
## purchase buys, on the bill it was bought for.
func _run_forecast_walk(ns, loader) -> void:
	var party_list: Array = loader.parties.get(ns.id, [])
	var target = null
	for party in party_list:
		if not ns.coalition_party_ids.has(party.id) and int(ns.seats_by_party.get(party.id, 0)) > 0:
			target = party
	if target == null:
		_fail("no opposition party to aim the forecast pin at")
		return
	var pos: Dictionary = load("res://src/sim/election_constants.gd").SLOT_POSITION.get(target.ideology_slot, {"economic": 0.0, "social": 0.0})
	var law = Law.new()
	law.id = "forecast_probe"
	law.law_name = "Forecast Probe"
	law.majority = "simple"
	var econ: float = float(pos["economic"])
	var found := false
	# Both directions off the party's own position, and clamped repeats
	# skipped: a party parked near an axis edge has only one way out, and the
	# support window is a fixed band of DISTANCE, so one clean sweep of
	# hundredths must cross it.
	for dir_to in [-1.0, 1.0]:
		if found:
			break
		var last_x := econ
		for step in range(1, 220):
			var x := clampf(econ + dir_to * 0.01 * step, -1.0, 1.0)
			if is_equal_approx(x, last_x):
				continue
			last_x = x
			law.position = {"economic": x, "social": float(pos["social"])}
			var s: float = Legislature.spatial_support(ns, target, law)
			if s > LK.ABSTAIN_BAND and s <= 0.15:
				found = true
				break
	if not found:
		_fail("no position put the target party inside the undecided window -- the pin cannot run")
		return
	var seats: int = int(ns.seats_by_party.get(target.id, 0))
	var blurred := LawPanelUi.forecast_text(ns, party_list, law, 0.15)
	var firm := LawPanelUi.forecast_text(ns, party_list, law, LK.ABSTAIN_BAND)
	var u_blurred := _undecided(blurred)
	var u_firm := _undecided(firm)
	if u_blurred < seats:
		_fail("the blurred forecast should hold the target party's %d seats as undecided, got %s" % [seats, blurred])
	if u_firm >= u_blurred:
		_fail("firming the band did not move seats out of undecided: '%s' vs '%s'" % [firm, blurred])


func _undecided(forecast: String) -> int:
	# "N for · M against · K undecided" -- the third integer is the read.
	var parts := forecast.split("·")
	if parts.size() < 3:
		return -1
	return int(String(parts[2]).strip_edges().trim_suffix(" undecided").split(" ")[0])


func _law_by_id(loader, id: String):
	for law in loader.laws:
		if String(law.id) == id:
			return law
	return null


func _slider_count(panel) -> int:
	return panel._sliders.size()


## The pin's shape, the test_characters/test_commodities scan idiom pointed at
## READS: statute.gd is the register's one sim touch (buy_poll writes and
## validates), legislature.gd's bare `= {}` reset is the init that walks beside
## law_ledger, and any other sim line that names the register in CODE is a
## reader the contract forbids. Comments do not count -- _code_only strips
## them, the same correction test_geography's register scan records.
func _sim_reads_purchases() -> Array[String]:
	var bad: Array[String] = []
	var da := DirAccess.open("res://src/sim")
	if da == null:
		return bad
	for f in da.get_files():
		if not f.ends_with(".gd") or f == "statute.gd":
			continue
		var src := FileAccess.get_file_as_string("res://src/sim/" + f)
		for raw_line in _code_only(src).split("\n"):
			var line := String(raw_line)
			if not line.contains("poll_purchases"):
				continue
			if line.contains("[") or line.contains(".get(") \
					or line.contains(".has(") or line.contains(".erase(") \
					or not line.contains("= {}"):
				bad.append("%s: %s" % [f, line.strip_edges()])
	return bad


func _code_only(src: String) -> String:
	var out := ""
	for raw_line in src.split("\n"):
		var line := String(raw_line)
		var hash_at := line.find("#")
		if hash_at != -1:
			line = line.substr(0, hash_at)
		out += line + "\n"
	return out


func _press(button: Button) -> void:
	if button == null:
		_fail("nothing to press")
		return
	button.pressed.emit()


func _find_button(node: Node, fragment: String) -> Button:
	if node.is_queued_for_deletion():
		return null
	if node is Button and String(node.text).contains(fragment):
		return node
	for child in node.get_children():
		var found := _find_button(child, fragment)
		if found != null:
			return found
	return null


func _live_text_has(node: Node, fragment: String) -> bool:
	if node.is_queued_for_deletion():
		return false
	if node is Label and String(node.text).contains(fragment):
		return true
	if node is LineEdit and String(node.text).contains(fragment):
		return true
	for child in node.get_children():
		if _live_text_has(child, fragment):
			return true
	return false


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_statute_surfaces: all checks passed")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: " + f)
		print("test_statute_surfaces: %d failures" % _failures.size())
		quit(1)
