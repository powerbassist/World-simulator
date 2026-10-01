extends SceneTree

## Headless test: godot --headless --script res://tests/test_industry_surfaces.gd
## Non-zero exit on any failure.
##
## V4.7b's UI surfaces, pinned at the pass-5 fleet's find: the pending mark,
## the announce memory and the panel's autonomy sections could all fail
## silently and the suite would stay green -- the exact class AGENTS.md's
## "new UI behaviour that can fail silently needs a test" rule exists for,
## and the announce memory had already shipped one silent-class draft defect
## inside this very block (caught by review, not by test).
##
## The state is staged EXACTLY as the machine writes it -- the bid's three
## scalars as _bids writes them, the failure as _failures commits them -- the
## same discipline the screenshot flags and test_industry's forced mechanics
## use. The announce memory is asserted through main's own memory dicts (the
## state under test) rather than through message-stack card counts, which the
## stack's own aging makes unstable; one card-count delta pins the first
## push, and the panel is read through LIVE controls only -- queue_free is
## deferred, and a refresh's reaped children still carry their text on the
## same frame.

const Companies = preload("res://src/sim/companies.gd")
const IndustryK = preload("res://src/sim/industry_constants.gd")
const Pending = preload("res://src/ui/pending.gd")

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
	var panel = _main._companies_panel
	var stack = _main._hud.message_stack

	var majors := Companies.majors_of(loader, ns.id)
	var major = majors[0]
	var second = majors[1]
	var third = majors[2]

	# --- The pending mark: absent on a clean register -----------------------
	if Pending.window_ids(state, loader).has("companies"):
		_fail("companies pending mark standing on a clean register")

	# --- The bid: card, mark, memory, panel row ------------------------------
	_stage_bid(ns, major)
	var before_bid: int = stack.card_count()
	_main._announce_industry_events()
	if stack.card_count() <= before_bid:
		_fail("a staged foreign bid announced no card")
	if not _main._announced_bids.has(major.id):
		_fail("the bid announce left no memory entry")
	if not Pending.window_ids(state, loader).has("companies"):
		_fail("no companies pending mark with a bid standing")
	panel._dirty = true
	panel._refresh()
	if _count_live_buttons(panel._body, ["Block the Takeover", "Allow the Takeover"]) < 2:
		_fail("the bid built no live takeover buttons (the bid row, or the firm row co-offering it)")

	# --- The answered bid: memory clears, so the NEXT bid re-announces ------
	_answer_bid(ns, major)
	_main._announce_industry_events()
	if not _main._announced_bids.is_empty():
		_fail("the bid memory did not clear when the event ended")
	if Pending.window_ids(state, loader).has("companies"):
		_fail("companies mark standing with no bid and no failure")
	_stage_bid(ns, major)
	_main._announce_industry_events()
	if not _main._announced_bids.has(major.id):
		_fail("a second bid on the same firm announced no memory entry -- the write-once class")

	# --- The failure: memory, mark, rescue row -------------------------------
	_stage_failure(ns, major)
	_stage_failure(ns, second)
	_main._announce_industry_events()
	if not (_main._announced_failures.has(major.id) and _main._announced_failures.has(second.id)):
		_fail("the failure announce missed a memory entry")
	if not Pending.window_ids(state, loader).has("companies"):
		_fail("no companies pending mark with failures standing")
	panel._dirty = true
	panel._refresh()
	if _count_live_buttons(panel._body, ["Strategic Rescue Package"]) < 1:
		_fail("the failing-firms rows built no live rescue button")

	# --- The per-firm memory: a rescued firm RE-failing re-announces ---------
	var rescue = null
	for a in loader.company_actions:
		if String(a.id) == "strategic_rescue":
			rescue = a
			break
	var rescue_result: Dictionary = Companies.execute(state, ns, loader.company_actions, rescue, major.id, loader)
	if not bool(rescue_result.get("applied", false)):
		_fail("the rescue itself was refused: %s" % str(rescue_result))
	_main._announce_industry_events()
	if _main._announced_failures.has(major.id):
		_fail("the rescued firm's memory entry survived -- the per-firm clear did not run")
	_stage_failure(ns, major)
	_main._announce_industry_events()
	if not _main._announced_failures.has(major.id):
		_fail("a re-failed firm inside another window was card-silent -- the write-once class")

	# --- The corpse: the gate holds, and the refusal is shown ----------------
	_ensure_entry(ns, third)
	var corpse: Dictionary = ns.companies[third.id]
	corpse["failed"] = true
	corpse["rescue_months_left"] = 0
	corpse["share"] = 0.0
	# A stale bid no machine path can now produce (failure and break-up clear
	# it) -- hand-staged to prove the panel's defence-in-depth gate holds if
	# one ever coexists: available() answers one door on a failed firm, and
	# the door is shut at window 0.
	if not Companies.available(state, ns, loader.company_actions, third.id, loader).is_empty():
		_fail("available() offered actions on a committed corpse")
	var block = null
	for a in loader.company_actions:
		if String(a.id) == "block_takeover":
			block = a
			break
	panel._on_act(ns, third, block)
	panel._dirty = true
	panel._refresh()
	if not _live_text_has(panel._body, "refused"):
		_fail("a refused click left no refusal line in the body")


## The bid's three scalars, exactly as industry.gd::_bids writes them.
func _stage_bid(ns, company) -> void:
	_ensure_entry(ns, company)
	var entry: Dictionary = ns.companies[company.id]
	entry["bid_bidder"] = "DEU|foreign_rival"
	entry["bid_price_eur_bn"] = 12.0
	entry["bid_months_left"] = IndustryK.BID_WINDOW_MONTHS


## The answered bid, as block_bid clears it (the scalars plus the courtship).
func _answer_bid(ns, company) -> void:
	var entry: Dictionary = ns.companies[company.id]
	entry["bid_bidder"] = ""
	entry["bid_price_eur_bn"] = 0.0
	entry["bid_months_left"] = 0
	entry["courted"] = 0.0


## The failure, exactly as industry.gd::_failures commits it.
func _stage_failure(ns, company) -> void:
	_ensure_entry(ns, company)
	var entry: Dictionary = ns.companies[company.id]
	entry["failed"] = true
	entry["share"] = 0.0
	entry["subsidy"] = 0.0
	entry["rescue_months_left"] = IndustryK.RESCUE_WINDOW_MONTHS


## The register entry every staged write needs -- the seed's own shape, since
## this test runs before the first tick would seed one.
func _ensure_entry(ns, company) -> void:
	if not ns.companies.has(company.id):
		ns.companies[company.id] = {"share": company.share, "subsidy": 0.0, "state_share": 0.0}


## Buttons under the node whose text matches any of the names, counting LIVE
## controls only: queue_free is deferred, so a refresh's reaped children are
## still in the tree on the same frame.
func _count_live_buttons(node: Node, names: Array) -> int:
	var n := 0
	if node is Button and not node.is_queued_for_deletion() and names.has(node.text):
		n += 1
	for child in node.get_children():
		n += _count_live_buttons(child, names)
	return n


func _live_text_has(node: Node, fragment: String) -> bool:
	if node.is_queued_for_deletion():
		return false
	if node is Label and String(node.text).contains(fragment):
		return true
	if node is RichTextLabel and String(node.get_parsed_text()).contains(fragment):
		return true
	for child in node.get_children():
		if _live_text_has(child, fragment):
			return true
	return false


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_industry_surfaces: all checks passed")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: " + f)
		print("test_industry_surfaces: %d failures" % _failures.size())
		quit(1)
