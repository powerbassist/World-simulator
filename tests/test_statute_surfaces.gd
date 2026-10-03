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

const Law = preload("res://src/core/law.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const LawPanelUi = preload("res://src/ui/law_panel.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const Statute = preload("res://src/sim/statute.gd")
const StatuteK = preload("res://src/sim/statute_constants.gd")
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
		_fail("the composed key's slider is not capped at the birth-gate ceiling")
	ns.custom_taxes.erase("carbon")
	ns.tax_rates_pct.erase("carbon")
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
	ns.assembly_bills.erase("pmb_surfaces")


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
