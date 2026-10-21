extends SceneTree

## V4.1 Task 4. The programme credit CHANNEL: the pulse Opinion reads, the
## bounded stock it maintains, the price it pays, and the tick ordering the
## same-month guarantee rests on. The register machine's own contract is
## tests/test_programme.gd; this file is the opinion side of
## docs/programme-model.md §3, plus the one property a unit test cannot see --
## that the game's month concludes the register IMMEDIATELY before Opinion reads it,
## with Elections (the only writer of terms_served/months_in_term) after both.
##
## PROGRAMME_SPAN is deliberately not pinned here -- the Task 4 sweep owns it,
## and every expected figure below is computed FROM the shipped constant.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Programme = preload("res://src/sim/programme.gd")
const PK = preload("res://src/sim/programme_constants.gd")
const K = preload("res://src/sim/opinion_constants.gd")

## Fires prog_industrial_renewal's `complete` (growth_annual_pct >= 2.0) with
## no authored immediate and no on_* effects, so a delta between the pair is
## the channel ALONE -- and, never written, the same entry is the
## chosen-but-never-delivers arm of the first test.
const COMPLETE_ENTRY := "prog_industrial_renewal"
const WRITE_MONTH := 3
const WRITE_GROWTH := 2.5

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_the_channel_is_inert_until_a_conclusion()
	_test_a_completion_pays_one_month_of_inertia()
	_test_the_stock_is_bounded_even_under_an_illegal_cadence()
	_test_the_decay_half_life_lands_inside_the_band()
	_test_the_guarantee_is_pinned_in_main()
	_finish()


## P3 at unit scale: an idle nation and a nation that CHOSE but never
## delivered -- the goal is simply never met, no write anywhere -- are
## bit-identical in approval for eight months. Choosing prices nothing; the
## pulse is the only input the channel has.
func _test_the_channel_is_inert_until_a_conclusion() -> void:
	var pair := _new_pair(COMPLETE_ENTRY)
	for m in range(8):
		_advance_pair(pair, false)
		var a: Dictionary = pair["a"]
		var b: Dictionary = pair["b"]
		if float(b["ns"].programme_stock) != 0.0:
			_fail("month %d: a chosen-but-unconcluded register moved the stock" % (m + 1))
		for bloc in K.BLOC_KEYS:
			if float(b["ns"].bloc_approval[bloc]) != float(a["ns"].bloc_approval[bloc]):
				_fail("month %d: bloc '%s' diverged with no conclusion on the register" % [m + 1, bloc])


## The channel's fingerprint: a conclusion in month 3 puts the stock at exactly
## 1.0, pays the credit into every bloc's target, and moves each bloc's
## approval by exactly INERTIA_RATE x credit in that month's update -- the
## one-month-of-inertia shape the sweep's slope is made of. Next month the
## pulse is gone (the stamp matched once) and the stock has decayed one step.
func _test_a_completion_pays_one_month_of_inertia() -> void:
	var pair := _new_pair(COMPLETE_ENTRY)
	_advance_pair(pair, false)
	_advance_pair(pair, false)
	_advance_pair(pair, true)  # month 3: the write fires the complete trigger.

	var b = pair["b"]["ns"]
	var a = pair["a"]["ns"]
	if not is_equal_approx(float(pair["last_pulse"]), 1.0):
		_fail("the completion month did not pay the unit pulse (%s)" % str(pair["last_pulse"]))
	if not is_equal_approx(float(b.programme_stock), 1.0):
		_fail("the completion month did not leave the stock at 1.0 (%s)" % str(b.programme_stock))
	var credit: float = Opinion.programme_credit(b)
	if not is_equal_approx(credit, PK.PROGRAMME_SPAN * 1.0):
		_fail("programme_credit is not SPAN x stock (%s vs %s)" % [str(credit), str(PK.PROGRAMME_SPAN)])
	for bloc in K.BLOC_KEYS:
		var moved: float = float(b.bloc_approval[bloc]) - float(a.bloc_approval[bloc])
		if absf(moved - K.INERTIA_RATE * credit) > 1e-9:
			_fail("bloc '%s' moved %s, not one month of inertia on the credit" % [bloc, str(moved)])
	var headline: float = float(b.overall_approval_pct) - float(a.overall_approval_pct)
	if absf(headline - K.INERTIA_RATE * credit) > 1e-9:
		_fail("the headline moved %s, not one month of inertia on the credit" % [str(headline)])

	_advance_pair(pair, false)  # month 4: the pulse is a step, not a rate.
	if not is_equal_approx(float(pair["last_pulse"]), 0.0):
		_fail("the pulse paid twice -- the stamp is matching outside its month")
	if not is_equal_approx(float(b.programme_stock), 1.0 * (1.0 - PK.PROGRAMME_DECAY_RATE)):
		_fail("the stock did not decay one step in its first pulse-free month")


## The clamp is the point of the form (the bound is what makes PROGRAMME_SPAN
## the whole price), so it must hold under a cadence no legal content can
## reach -- one concluded completion stamped every month, forever. The stock
## saturates at exactly 1.0 and never steps past it.
func _test_the_stock_is_bounded_even_under_an_illegal_cadence() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	Programme.choose(state, ns, COMPLETE_ENTRY, _loader)
	for m in range(30):
		ns.programme.append({
			"entry_id": "spam_%d" % m,
			"chosen_term": int(ns.terms_served),
			"months_live": 1,
			"status": PK.STATUS_COMPLETE,
			"concluded_term": int(ns.terms_served),
			"concluded_term_month": int(ns.months_in_term),
		})
		Programme.tick_month(state, _loader)
		Opinion.tick_month(state)
		_advance_clock(state)
		if float(ns.programme_stock) > PK.STOCK_MAX + 1e-12:
			_fail("month %d: the stock escaped its bound (%s)" % [m + 1, str(ns.programme_stock)])
	if not is_equal_approx(float(ns.programme_stock), PK.STOCK_MAX):
		_fail("a saturated cadence did not sit at the bound (%s)" % str(ns.programme_stock))


## P5's band: the stock halves within ln(2)/DECAY_RATE months of the pulse,
## +-1 for the discrete tick. The credit follows the stock, so the stock is
## the honest read.
func _test_the_decay_half_life_lands_inside_the_band() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	Programme.choose(state, ns, COMPLETE_ENTRY, _loader)
	var peak := 0.0
	var half_life := -1
	for m in range(24):
		if m + 1 == WRITE_MONTH:
			ns.growth_annual_pct = WRITE_GROWTH
		Programme.tick_month(state, _loader)
		Opinion.tick_month(state)
		_advance_clock(state)
		if m + 1 == WRITE_MONTH:
			peak = float(ns.programme_stock)
		elif half_life < 0 and peak != 0.0 and absf(float(ns.programme_stock)) <= 0.5 * absf(peak):
			half_life = (m + 1) - WRITE_MONTH
	var nominal := log(2.0) / PK.PROGRAMME_DECAY_RATE
	if half_life < 0:
		_fail("the stock never halved inside 24 months")
	elif absf(float(half_life) - nominal) > 1.0:
		_fail("the half-life measured %d months against a nominal %.2f, past the +-1 band"
			% [half_life, nominal])


## The same-month guarantee, read from the source the way test_inflation pins
## the Media call: Programme.tick_month must be IMMEDIATELY before
## Opinion.tick_month in the game's month, src/sim/world_month.gd (nothing between
## them but comments and the step hook's own two calls), and Elections.tick_month
## -- the only writer of the stamp pair -- must come after both. Elections between
## the pair would reset months_in_term in a won election month between stamp and
## read, and the pulse would go silently unpaid; the wiring comment in
## world_month.gd says the same thing.
##
## The hook is the one seam a caller can reach between the pair, so main.gd -- the
## caller with the most hooks -- is read too: it must hook neither the end of
## Programme nor the start of Opinion.
func _test_the_guarantee_is_pinned_in_main() -> void:
	var lines := FileAccess.get_file_as_string("res://src/sim/world_month.gd").split("\n")
	var programme_at := -1
	var opinion_at := -1
	var elections_at := -1
	for i in range(lines.size()):
		var stripped := String(lines[i]).strip_edges()
		if stripped.begins_with("#"):
			continue
		if programme_at < 0 and stripped == "Programme.tick_month(state, loader)":
			programme_at = i
		elif programme_at >= 0 and opinion_at < 0 and stripped == "Opinion.tick_month(state)":
			opinion_at = i
		elif opinion_at >= 0 and elections_at < 0 and stripped.contains("Elections.tick_month("):
			elections_at = i
	if programme_at < 0 or opinion_at < 0 or elections_at < 0:
		_fail("world_month.gd is missing the Programme/Opinion/Elections sequence")
		return
	for j in range(programme_at + 1, opinion_at):
		var stripped := String(lines[j]).strip_edges()
		if stripped == "" or stripped.begins_with("#"):
			continue
		if stripped == '_after(on_step, "Programme", report)' or stripped == '_before(on_step, "Opinion", report)':
			continue
		# V5.1-0a: the month is a cursor, one match arm per step, so the seam
		# between the pair is Opinion's arm label -- and between two frames,
		# month_runner.gd defers every input, so nothing runs there either.
		if stripped == '"Opinion":':
			continue
		_fail("world_month.gd runs '%s' between Programme.tick_month and Opinion.tick_month -- the same-month guarantee is broken" % stripped)
	if elections_at < opinion_at:
		_fail("world_month.gd runs Elections before the Programme/Opinion pair -- a won election month would drop the pulse")

	# main.gd's hook: arms of its before-branch sit three tabs in, its after-branch's
	# two. Neither may be the seam between the pair.
	for line in FileAccess.get_file_as_string("res://src/ui/main.gd").split("\n"):
		if line.strip_edges() == '"Programme":' or line == '\t\t\t"Opinion":':
			_fail("main.gd hooks the seam between Programme and Opinion ('%s') -- the same-month guarantee holds only while nothing runs there" % line.strip_edges())


# --- Harness --------------------------------------------------------------------------

## A pair of states grown month by month: `a` idle, `b` having chosen
## `entry_id` at term start. Both share the write when it fires, so every
## difference between them is the register's and nothing else.
func _new_pair(entry_id: String) -> Dictionary:
	var a = GameState.new_game(_loader, "FRA")
	var b = GameState.new_game(_loader, "FRA")
	if entry_id != "":
		var result: Dictionary = Programme.choose(b, b.player(), entry_id, _loader)
		if not bool(result.get("applied", false)):
			_fail("the pair's choice was refused: %s" % str(result.get("reason", "")))
	return {"a": {"state": a, "ns": a.player()}, "b": {"state": b, "ns": b.player()}, "last_pulse": 0.0}


## One month of both states in main.gd's relevant order: Programme concludes,
## then Opinion prices, then the clock step that stands in for Elections'
## months_in_term increment (Elections runs last in the real loop; this mirror
## puts the increment in the same place, which is what makes a stamp match for
## exactly one month).
func _advance_pair(pair: Dictionary, write: bool) -> void:
	for half in ["a", "b"]:
		var state = pair[half]["state"]
		var ns = pair[half]["ns"]
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		if write:
			ns.growth_annual_pct = WRITE_GROWTH
		Programme.tick_month(state, _loader)
		if half == "b":
			pair["last_pulse"] = Programme.programme_pulse(ns)
		Opinion.tick_month(state)
		_advance_clock(state)


## Elections._tick_nation increments months_in_term for a nation in government;
## a harness that does not run Elections must do it in the same month position
## or every stamp matches forever. test_programme.gd's own conclusion test
## moves the counter by hand for the same reason.
func _advance_clock(state) -> void:
	var ns = state.player()
	if ns.in_government:
		ns.months_in_term += 1


func _finish() -> void:
	if _failures.is_empty():
		print("test_programme_channel: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
