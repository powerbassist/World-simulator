extends SceneTree

## V1.7b. Campaign promises: the ladder, the window they may be made in, the level read
## that judges them, the accrued price and the verb. Model: docs/pledge-model.md.
##
## The load-bearing assertions here are the ones about what does NOT happen:
##
##   - a nation that has promised nothing has its ns.bloc_offset BIT-FOR-BIT unchanged
##     after a full term, which is what lets the whole layer go live with the balance
##     harness bit-identical across every existing regime;
##   - a promise charges NOTHING before the term it binds begins and NOTHING after it
##     ends, both on a level read of the clock, so there is no flag anywhere and
##     elections.gd does not know this file exists;
##   - it is NOT judged once at the end. tests below run a promise broken early and
##     repaired late, and require it to have been charged -- which is the whole of
##     instance forty-two, pinned rather than argued;
##   - `inflation_pct` is NOT promisable. tools/pledge_probe.gd table (c0) deleted it
##     for measuring 0.114 of luck and 0.045 of choice, both under the resolution of
##     the model that produces it, and this file fails if it comes back;
##   - the register carries no CONTENT, so a save round-trips the decision and never
##     the ladder;
##   - the nine never promise anything, so the verb is the player's;
##   - and the two BALANCE HARNESSES both call Pledges.tick_month(). V1.5d shipped with
##     neither of them calling Media.tick_month(), so both ran the pre-session model and
##     their agreement about a bit-identical re-run was about nothing. That check is
##     here rather than in a comment.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const K = preload("res://src/sim/pledges_constants.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const CampaignK = preload("res://src/sim/campaign_constants.gd")
const EconomyK = preload("res://src/sim/economy_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const LegislatureK = preload("res://src/sim/legislature_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")

const PLAYER := "FRA"
## A rate promise, so a test can break it by committing a budget rather than by waiting
## for the world. Named rather than derived, because a test that picks its own subject
## silently changes what it measures when the content moves.
const RATE_PLEDGE := "pledge_no_new_taxes"
const RATE_PLEDGE_ID := "tax_lock"
const OTHER_PLEDGE := "pledge_protect_health"
const THIRD_PLEDGE := "pledge_growth"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_content_loads()
	_test_rate_fields_mirror_the_economy_keys()
	_test_inflation_is_not_promisable()
	_test_register_seeds_empty()
	_test_no_promise_leaves_bloc_offset_bit_identical()
	_test_window_gates_the_verb()
	_test_a_termed_out_incumbent_cannot_promise()
	_test_the_same_promise_cannot_be_made_twice()
	_test_execute_pays_the_reward_and_freezes_the_dates()
	_test_nothing_is_charged_before_the_term_begins()
	_test_a_broken_promise_is_charged_every_month()
	_test_repairing_it_stops_the_charge()
	_test_it_retires_on_a_level_read()
	_test_the_register_carries_no_content()
	_test_the_nine_never_promise()
	_test_preloads_are_a_short_list()
	_test_elections_does_not_know_this_file_exists()
	_test_both_balance_harnesses_tick_it()

	_finish()


# --- Content -------------------------------------------------------------------------

func _test_content_loads() -> void:
	if _loader.pledges.is_empty():
		_fail("data/pledges/ loaded no promises")
		return
	var ids := {}
	for a in _loader.pledges:
		var terms: Dictionary = a.effects.get("pledge", {})
		if terms.is_empty():
			_fail("%s has no effects.pledge" % a.id)
			continue
		if not K.PLEDGE_FIELDS.has(String(terms.get("field", ""))):
			_fail("%s promises '%s', which is not a promisable field" % [a.id, terms.get("field", "")])
		if not K.PLEDGE_OPS.has(String(terms.get("op", ""))):
			_fail("%s uses op '%s', which is not a bound" % [a.id, terms.get("op", "")])
		var pid := String(terms.get("pledge_id", ""))
		if ids.has(pid):
			_fail("pledge_id '%s' is defined twice" % pid)
		ids[pid] = true
		# Authored as a magnitude, charged as a subtraction. A negative would be a
		# promise that paid for being broken.
		for bloc in terms.get("breach_offset", {}):
			var v: float = float(terms["breach_offset"][bloc])
			if v < 0.0:
				_fail("%s: breach_offset.%s is negative" % [a.id, bloc])
			if v > K.MAX_BREACH_OFFSET_PER_MONTH:
				_fail("%s: breach_offset.%s exceeds the ceiling" % [a.id, bloc])
		if String(terms.get("pledge_name", "")) == "":
			_fail("%s has no pledge_name -- the ledger needs the noun" % a.id)


## pledges_constants.gd writes its rate fields out because a `const` cannot loop. This
## is the check that keeps the two lists honest, and it runs BOTH ways -- so a sixth
## tax added at some later session turns this red rather than becoming silently
## unpromisable, and a field left here after its key is deleted turns it red too.
func _test_rate_fields_mirror_the_economy_keys() -> void:
	var expected: Array = []
	for key in EconomyK.TAX_KEYS:
		expected.append("tax_%s_pct" % key)
	for key in EconomyK.SPENDING_KEYS:
		expected.append("spending_%s_pct_gdp" % key)

	for f in expected:
		if not K.PLEDGE_RATE_FIELDS.has(f):
			_fail("PLEDGE_RATE_FIELDS is missing '%s' -- a rate the player sets that nobody may promise" % f)
	for f in K.PLEDGE_RATE_FIELDS:
		if not expected.has(String(f)):
			_fail("PLEDGE_RATE_FIELDS carries '%s', which no TAX_KEYS or SPENDING_KEYS entry produces" % f)


## The probe deleted it and this is where that stays deleted. Table (c0) measures
## inflation_pct at 0.114 of luck and 0.045 of choice over a full term, both under the
## resolution of docs/inflation-model.md's own model, so any authored threshold is a
## constant verdict -- kept in all sixty months or broken in all sixty, with nothing
## the player does moving it.
func _test_inflation_is_not_promisable() -> void:
	if K.PLEDGE_FIELDS.has("inflation_pct"):
		_fail("inflation_pct is promisable again -- see pledges_constants.gd, it was deleted by measurement")


# --- The register ---------------------------------------------------------------------

func _test_register_seeds_empty() -> void:
	var state = _new_state()
	for ns in state.nations.values():
		if not ns.pledges.is_empty():
			_fail("%s starts with promises on the books" % ns.id)


## The property the whole layer's bit-identity rests on: a nation that never promises
## anything has bloc_offset EXACTLY unchanged, not approximately. Asserted with `!=`
## rather than is_equal_approx for V1.4a's reason.
func _test_no_promise_leaves_bloc_offset_bit_identical() -> void:
	var state = _new_state()
	var ns = state.player()
	var before: Dictionary = ns.bloc_offset.duplicate(true)
	for m in range(72):
		_advance(state)
		Economy.tick_month(state)
		Budget.tick_month(state)
		Pledges.tick_month(state, _loader)
	for bloc in before:
		if float(ns.bloc_offset.get(bloc, 0.0)) != float(before[bloc]):
			_fail("bloc_offset['%s'] moved without a promise: %.17f -> %.17f" % [
				bloc, float(before[bloc]), float(ns.bloc_offset.get(bloc, 0.0))])


# --- The verb -------------------------------------------------------------------------

func _test_window_gates_the_verb() -> void:
	var state = _new_state()
	var ns = state.player()

	_wind_to(state, CampaignK.CAMPAIGN_WINDOW_MONTHS + 3)
	if not Pledges.available(state, ns, _loader.pledges).is_empty():
		_fail("promises are available outside the run-up")

	_wind_to(state, CampaignK.CAMPAIGN_WINDOW_MONTHS)
	if Pledges.available(state, ns, _loader.pledges).is_empty():
		_fail("no promise is available at the moment the run-up opens")

	# Refused rather than half-applied, so a stale button cannot produce the effect the
	# window exists to prevent.
	_wind_to(state, CampaignK.CAMPAIGN_WINDOW_MONTHS + 3)
	var result: Dictionary = Pledges.execute(state, ns, _loader.pledges, _action(RATE_PLEDGE))
	if bool(result.get("applied", false)) or not bool(result.get("refused", false)):
		_fail("a promise was made outside the run-up")
	if not ns.pledges.is_empty():
		_fail("a refused promise still reached the register")


## Found by the probe rather than by the design. Table (a0) prints three run-ups over
## fourteen years and the third opens against a `termed_out` notice: Campaign.is_open()
## is a pure clock read with no term-limit branch, so the window opens for a president
## who cannot stand. A promise about a term you are barred from serving binds nobody.
func _test_a_termed_out_incumbent_cannot_promise() -> void:
	var state = _new_state()
	var ns = state.player()
	_wind_to(state, CampaignK.CAMPAIGN_WINDOW_MONTHS)
	if ns.term_limit <= 0:
		return
	ns.terms_served = ns.term_limit
	if not Pledges.available(state, ns, _loader.pledges).is_empty():
		_fail("a termed-out incumbent can still make promises about a term they cannot serve")


func _test_the_same_promise_cannot_be_made_twice() -> void:
	var state = _new_state()
	var ns = state.player()
	_wind_to(state, CampaignK.CAMPAIGN_WINDOW_MONTHS)
	Pledges.execute(state, ns, _loader.pledges, _action(RATE_PLEDGE))
	for a in Pledges.available(state, ns, _loader.pledges):
		if a.id == RATE_PLEDGE:
			_fail("the same promise is offered twice")
	if Pledges.pledge_count(ns) != 1:
		_fail("expected one promise on the books, found %d" % Pledges.pledge_count(ns))

	# `pledge_count <= 1` is authored on every promise, so a second is legal and a
	# third is not. The gate is CONTENT and this is what pins that it works.
	Pledges.execute(state, ns, _loader.pledges, _action(OTHER_PLEDGE))
	if Pledges.pledge_count(ns) != 2:
		_fail("the second promise was refused")
	var third: Dictionary = Pledges.execute(state, ns, _loader.pledges, _action(THIRD_PLEDGE))
	if bool(third.get("applied", false)):
		_fail("a third promise was allowed past the `pledge_count <= 1` gate")


func _test_execute_pays_the_reward_and_freezes_the_dates() -> void:
	var state = _new_state()
	var ns = state.player()
	_wind_to(state, CampaignK.CAMPAIGN_WINDOW_MONTHS)
	var before: Dictionary = ns.bloc_offset.duplicate(true)
	var action = _action(RATE_PLEDGE)
	Pledges.execute(state, ns, _loader.pledges, action)

	for bloc in action.effects.get("bloc_offset", {}):
		var moved: float = float(ns.bloc_offset.get(bloc, 0.0)) - float(before.get(bloc, 0.0))
		if not is_equal_approx(moved, float(action.effects["bloc_offset"][bloc])):
			_fail("the reward for '%s' did not reach bloc_offset['%s']" % [RATE_PLEDGE, bloc])

	var entry: Dictionary = ns.pledges[0]
	if int(entry["from_year"]) != int(ns.next_executive_year) or int(entry["from_month"]) != int(ns.next_executive_month):
		_fail("the promise does not bind from the vote it was made for")

	# FROZEN, not derived. Elections.tick_month() pushes next_executive_* a full term
	# forward the moment the incumbent wins, so a promise deriving its deadline from
	# that field would move its own goalposts on the night it was won.
	var expected_until: int = int(ns.next_executive_year) * 12 + (int(ns.next_executive_month) - 1) + int(ns.term_months)
	var actual_until: int = int(entry["until_year"]) * 12 + (int(entry["until_month"]) - 1)
	if actual_until != expected_until:
		_fail("the promise binds until %d, expected %d" % [actual_until, expected_until])

	ns.next_executive_year += 5
	if int(entry["until_year"]) * 12 + (int(entry["until_month"]) - 1) != expected_until:
		_fail("the deadline moved when the schedule did -- it is derived, not frozen")


# --- The judgement --------------------------------------------------------------------

## A promise is not broken before it is owed. The run-up is the last months of the
## PREVIOUS term, so a president in breach on the day they promise pays nothing for it.
func _test_nothing_is_charged_before_the_term_begins() -> void:
	var state = _new_state()
	var ns = state.player()
	_wind_to(state, CampaignK.CAMPAIGN_WINDOW_MONTHS)
	Pledges.execute(state, ns, _loader.pledges, _action(RATE_PLEDGE))
	_break_the_rate_pledge(state, ns)

	var before: Dictionary = ns.bloc_offset.duplicate(true)
	for m in range(CampaignK.CAMPAIGN_WINDOW_MONTHS):
		Pledges.tick_month(state, _loader)
		_advance(state)
	for bloc in before:
		if float(ns.bloc_offset.get(bloc, 0.0)) != float(before[bloc]):
			_fail("a promise was charged before the term it binds began")
	if int(ns.pledges[0]["breach_months"]) != 0:
		_fail("breach months accrued before the term began")


## INSTANCE FORTY-TWO, pinned. The row said the triple is read at the END of the term;
## a single read there is strictly dominated by last-minute compliance, so it is read
## every month and the price is the integral.
func _test_a_broken_promise_is_charged_every_month() -> void:
	var state = _new_state()
	var ns = state.player()
	var entry := _standing_promise(state, ns)
	_break_the_rate_pledge(state, ns)

	var charged: Array = []
	# Seeded at the CURRENT value and not at zero: the promise has already paid its
	# reward onto this very bloc, so a zero baseline measures the reward in the first
	# row and reports it as a month that charged nothing.
	var last: float = float(ns.bloc_offset.get("business", 0.0))
	for m in range(6):
		Pledges.tick_month(state, _loader)
		var now: float = float(ns.bloc_offset.get("business", 0.0))
		charged.append(now - last)
		last = now
		_advance(state)

	if int(ns.pledges[0]["breach_months"]) != 6:
		_fail("six broken months counted as %d" % int(ns.pledges[0]["breach_months"]))
	# Every month charges, and every month charges the SAME -- linear in months, which
	# is what makes breaking it early and repairing it late cost more than the reverse.
	for d in charged:
		if float(d) >= 0.0:
			_fail("a broken promise charged nothing in one of its months")


## The off switch is called governing. This is why pledges_constants.gd ships no
## `renounce` op: the player already holds it.
func _test_repairing_it_stops_the_charge() -> void:
	var state = _new_state()
	var ns = state.player()
	_standing_promise(state, ns)
	_break_the_rate_pledge(state, ns)
	for m in range(3):
		Pledges.tick_month(state, _loader)
		_advance(state)

	_repair_the_rate_pledge(state, ns)
	var before: Dictionary = ns.bloc_offset.duplicate(true)
	var months_at_repair: int = int(ns.pledges[0]["breach_months"])
	for m in range(6):
		Pledges.tick_month(state, _loader)
		_advance(state)

	for bloc in before:
		if float(ns.bloc_offset.get(bloc, 0.0)) != float(before[bloc]):
			_fail("a repaired promise kept charging bloc_offset['%s']" % bloc)
	if int(ns.pledges[0]["breach_months"]) != months_at_repair:
		_fail("a repaired promise kept counting broken months")


## Retired by the clock and by nothing else, so there is no hook in elections.gd and no
## flag that could disagree with the date. What it charged stays charged: bloc_offset is
## an accumulator, so a term of broken promises outlives the term.
func _test_it_retires_on_a_level_read() -> void:
	var state = _new_state()
	var ns = state.player()
	var entry := _standing_promise(state, ns)
	_break_the_rate_pledge(state, ns)
	Pledges.tick_month(state, _loader)
	var charged: Dictionary = ns.bloc_offset.duplicate(true)

	# One month past the deadline the register carries. Converted through the same
	# arithmetic Pledges._absolute_month() uses -- the first version of this used
	# _wind_to()'s conversion, which is one-based where that one is zero-based, and
	# landed the clock exactly ON the deadline instead of past it.
	var past: int = int(entry["until_year"]) * 12 + (int(entry["until_month"]) - 1) + 1
	state.year = int(past / 12)
	state.month = (past % 12) + 1
	Pledges.tick_month(state, _loader)

	if not ns.pledges.is_empty():
		_fail("a promise outlived the term it bound")
	for bloc in charged:
		if float(ns.bloc_offset.get(bloc, 0.0)) != float(charged[bloc]):
			_fail("retiring a promise gave back what it charged")


# --- The properties --------------------------------------------------------------------

## The breach rates and the display name are AUTHORED, so caching either on NationState
## would put content in the save file. V1.4a's, V1.6e's, V1.6f's and V1.7a's property in
## a sixth register.
func _test_the_register_carries_no_content() -> void:
	var state = _new_state()
	var ns = state.player()
	_standing_promise(state, ns)
	var allowed := [
		"pledge_id", "field", "op", "value",
		"from_year", "from_month", "until_year", "until_month",
		"breach_months", "months_live",
	]
	for entry in ns.pledges:
		for key in entry.keys():
			if not allowed.has(String(key)):
				_fail("the register carries '%s', which is not one of its ten keys" % key)
		for key in allowed:
			if not entry.has(key):
				_fail("the register is missing '%s'" % key)
		if entry.has("breach_offset") or entry.has("pledge_name"):
			_fail("the register cached content -- the ladder must round-trip through data/pledges/")


## The nine never promise anything, so the verb is the player's. V1.3g's, V1.6e's,
## V1.6f's and V1.7a's honest limitation, pinned rather than described: nothing in
## src/sim/ calls Pledges.execute(), so there is no AI agenda term for this verb.
func _test_the_nine_never_promise() -> void:
	var dir := DirAccess.open("res://src/sim")
	if dir == null:
		_fail("could not open src/sim to check for an AI pledge agenda")
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".gd") and name != "pledges.gd":
			var text := FileAccess.get_file_as_string("res://src/sim/%s" % name)
			if text.contains("Pledges.execute"):
				_fail("src/sim/%s executes a promise -- the nine are supposed to be inert" % name)
		name = dir.get_next()
	dir.list_dir_end()


## Read from the source, the idiom test_unrest.gd, test_projects.gd, test_calendar.gd
## and test_people.gd all use. campaign.gd is the ONE system this file may reach, which
## is (b) reading (a); anything else would be a machine this session did not build.
func _test_preloads_are_a_short_list() -> void:
	var text := FileAccess.get_file_as_string("res://src/sim/pledges.gd")
	var allowed := [
		"res://src/sim/pledges_constants.gd",
		"res://src/sim/campaign.gd",
		"res://src/sim/legislature_constants.gd",
	]
	for line in text.split("\n"):
		var trimmed := String(line).strip_edges()
		if not trimmed.begins_with("const ") or not trimmed.contains("preload("):
			continue
		var path := trimmed.get_slice("preload(\"", 1).get_slice("\"", 0)
		if not allowed.has(path):
			_fail("src/sim/pledges.gd preloads '%s', which is not on its short list" % path)


## The window opens and the deadline closes on a level read, so nothing in elections.gd
## needs to know this file exists. If that changes, the level-read property has been
## traded for an edge trigger and somebody has to come and say why.
func _test_elections_does_not_know_this_file_exists() -> void:
	var text := FileAccess.get_file_as_string("res://src/sim/elections.gd")
	if text.contains("Pledges") or text.contains("pledges.gd"):
		_fail("elections.gd names Pledges -- the judgement is supposed to be a level read")


## V1.5d shipped with neither tools/balance_probe.gd nor tests/test_balance.gd calling
## Media.tick_month(), so both harnesses ran the pre-session model and their agreement
## about a bit-identical re-run was about nothing. A bit-identical re-run is the
## REASSURING outcome, so nothing about it invites suspicion -- which is exactly why
## this check is a test and not a habit.
##
## Both run src/sim/world_month.gd's month now (tests/test_world_month.gd holds them
## to it), so the month is what is read.
func _test_both_balance_harnesses_tick_it() -> void:
	for path in ["res://src/sim/world_month.gd"]:
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			_fail("%s could not be read" % path)
			continue
		if not text.contains("Pledges.tick_month"):
			_fail("%s never calls Pledges.tick_month() -- it is running the pre-session model" % path)


# --- Harness --------------------------------------------------------------------------

func _new_state():
	return GameState.new_game(_loader, PLAYER)


func _action(id: String):
	for a in _loader.pledges:
		if a.id == id:
			return a
	return null


## Make the rate promise and move the clock into the term it binds, so the next
## Pledges.tick_month() is a month that counts.
func _standing_promise(state, ns) -> Dictionary:
	_wind_to(state, CampaignK.CAMPAIGN_WINDOW_MONTHS)
	Pledges.execute(state, ns, _loader.pledges, _action(RATE_PLEDGE))
	var entry: Dictionary = ns.pledges[0]
	state.year = int(entry["from_year"])
	state.month = int(entry["from_month"])
	_advance(state)
	return entry


func _break_the_rate_pledge(state, ns) -> void:
	var pending := {
		"tax_rates_pct": ns.tax_rates_pct.duplicate(),
		"spending_pct_gdp": ns.spending_pct_gdp.duplicate(),
	}
	pending["tax_rates_pct"]["income"] = float(pending["tax_rates_pct"]["income"]) + 4.0
	Budget.commit(state, pending)


func _repair_the_rate_pledge(state, ns) -> void:
	var pending := {
		"tax_rates_pct": ns.tax_rates_pct.duplicate(),
		"spending_pct_gdp": ns.spending_pct_gdp.duplicate(),
	}
	pending["tax_rates_pct"]["income"] = float(pending["tax_rates_pct"]["income"]) - 4.0
	Budget.commit(state, pending)


func _wind_to(state, months: int) -> void:
	var ns = state.player()
	var target: int = (ns.next_executive_year * 12 + ns.next_executive_month) - months
	state.year = int(target / 12)
	state.month = target - state.year * 12
	if state.month <= 0:
		state.month += 12
		state.year -= 1


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


func _finish() -> void:
	if _failures.is_empty():
		print("test_pledges: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
