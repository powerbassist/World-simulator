extends SceneTree

## V1.7a. The campaign phase: the window, the mobilisation register, the turnout it
## produces, the computed bill and the verb. Model: docs/campaign-model.md.
##
## The load-bearing assertions here are the ones about what does NOT happen, and each
## is a property this session's shape rests on:
##
##   - Campaign.turnout_of() returns election_constants.BLOC_TURNOUT BIT-FOR-BIT with
##     no campaign -- not approximately, exactly -- which is what lets the whole layer
##     go live with the balance harness bit-identical across every existing regime and
##     with tests/test_elections.gd's two invariants untouched;
##   - src/sim/campaign.gd writes NOTHING on ns.framing_gain or ns.press_freedom. The
##     row's "messaging" clause is V1.5d's machine, which V1.5d CUT the campaign-time
##     twin of; this file reads the source and fails if either name appears in it, so
##     the refusal is a check and not a paragraph;
##   - the window opens and closes on a LEVEL READ of the clock, so the register clears
##     itself with no hook in elections.gd and no flag anywhere. A save reloaded inside
##     a run-up is inside it;
##   - the bill STOPS, and on a date the player cannot move;
##   - turnout is bounded strictly inside (0, 1) BY CONSTRUCTION, at any mobilisation,
##     so there is no clamp on it to get wrong;
##   - the nine never campaign, so the verb is the player's -- V1.3g's, V1.6e's and
##     V1.6f's honest limitation, pinned rather than described.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const K = preload("res://src/sim/campaign_constants.gd")
const Elections = preload("res://src/sim/elections.gd")
const ElectionK = preload("res://src/sim/election_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")

const PLAYER := "FRA"
## The cheapest effort in the shipped ladder, so a run fits comfortably inside a test.
## Named rather than derived, because a test that picks its own subject silently
## changes what it measures when the content moves.
const EFFORT := "ground_game"
const EFFORT_START := "start_ground_game"
const EFFORT_STOP := "stop_ground_game"
const OTHER_START := "start_digital_push"
## The one effort in the shipped ladder whose authored bloc_offset is POSITIVE
## (rural +0.03), which is what made the restart farm below worth anything. Named
## rather than derived for EFFORT's reason, and the test asserts the sign so a
## content edit that removed it turns this red rather than making it vacuous.
const REWARD_START := "start_town_halls"
const REWARD_STOP := "stop_town_halls"

var _failures: Array[String] = []
var _loader


## The region the tests hold their meetings in: the first of the player's own in
## authored order, which the importer writes descending by population -- so the tests
## campaign in Ile-de-France, the capital. Taken off the loader rather than hard-coded,
## because the register is content and a hard-coded NUTS id would outlive it.
func _site(ns) -> String:
	return Campaign.region_ids(ns, _loader)[0]


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_content_loads()
	_test_every_effort_can_be_stopped()
	_test_register_seeds_empty()
	_test_turnout_is_bit_identical_with_no_campaign()
	_test_turnout_is_bounded_by_construction()
	_test_low_turnout_blocs_have_more_room()
	_test_the_window_is_a_level_read()
	_test_the_verb_is_refused_outside_the_window()
	_test_an_effort_accrues_every_month()
	_test_the_accumulator_is_clamped()
	_test_the_bill_reaches_the_budget()
	_test_the_register_clears_when_the_window_closes()
	_test_stopping_keeps_what_it_bought()
	_test_an_effort_cannot_be_restarted()
	_test_mobilisation_moves_the_vote()
	_test_no_framing_machine()
	_test_campaign_is_a_leaf()
	_test_the_site_is_required_and_must_be_ones_own()
	_test_the_fresh_factor_is_mean_one()
	_test_the_factor_varies_and_saturation_bites()
	_test_the_tour_leaves_the_capital()
	_test_the_nine_never_campaign()
	_test_the_register_carries_no_content()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("test_campaign: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _new_state():
	return GameState.new_game(_loader, PLAYER)


func _action(id: String):
	for a in _loader.campaign_actions:
		if a.id == id:
			return a
	return null


## Winds the clock forward to `months` before the executive election, ticking nothing:
## the tests below drive the register directly and only need the date to be right.
func _wind_to(state, months: int) -> void:
	var ns = state.player()
	var target: int = (ns.next_executive_year * 12 + ns.next_executive_month) - months
	state.year = int(target / 12)
	state.month = target - state.year * 12
	if state.month <= 0:
		state.month += 12
		state.year -= 1


func _test_content_loads() -> void:
	if _loader.campaign_actions.is_empty():
		_fail("data/campaign-actions/ loaded no actions")
		return
	for a in _loader.campaign_actions:
		if not a.effects.has("campaign"):
			_fail("%s has no effects.campaign" % a.id)


## Every effort that can be started can be stopped, which is what stops the bill being
## a permanent monotone charge inside the window -- docs/defence-model.md's named
## failure, avoided by content here rather than by a constant.
func _test_every_effort_can_be_stopped() -> void:
	var starts := {}
	var stops := {}
	for a in _loader.campaign_actions:
		var t: Dictionary = a.effects.get("campaign", {})
		match String(t.get("op", "")):
			"start": starts[String(t.get("effort_id", ""))] = a.id
			"stop": stops[String(t.get("effort_id", ""))] = a.id
	for eid in starts:
		if not stops.has(eid):
			_fail("effort '%s' can be started and never stopped" % eid)


func _test_register_seeds_empty() -> void:
	var ns = _new_state().player()
	if not ns.campaign_running.is_empty():
		_fail("a new game starts with efforts in the field")
	if not ns.campaign_mobilisation.is_empty():
		_fail("a new game starts with somebody mobilised")
	if ns.campaign_bill_pct_gdp != 0.0:
		_fail("a new game starts with a campaign bill of %f" % ns.campaign_bill_pct_gdp)
	if not ns.campaign_sites.is_empty():
		_fail("a new game starts with a site already chosen")
	if not ns.campaign_saturation.is_empty():
		_fail("a new game starts with somebody already spoken to")


## THE PROPERTY THE WHOLE SESSION RESTS ON. Exact equality, not is_equal_approx: the
## nine non-playing nations and every test written before V1.7a must run the model they
## ran before, and "close enough" is not that.
func _test_turnout_is_bit_identical_with_no_campaign() -> void:
	var ns = _new_state().player()
	for bloc in OpinionK.BLOC_KEYS:
		if Campaign.turnout_of(ns, bloc) != float(ElectionK.BLOC_TURNOUT[bloc]):
			_fail("turnout_of(%s) is not bit-identical to BLOC_TURNOUT with no campaign" % bloc)
	if Campaign.turnout_spread(ns) != 0.0:
		_fail("turnout_spread is not exactly 0.0 with no campaign")


## Bounded strictly inside (0, 1) BY CONSTRUCTION rather than by a clamp, which is why
## campaign_constants.gd ships no turnout bound. Tested well past anything the content
## can reach, because the guarantee is about the arithmetic and not about the ladder.
##
## THE RANGE IS +-10 AND NOT +-50, AND THE REASON IS THE FLOAT AND NOT THE MODEL. The
## first version swept to +-50 and failed on all six blocs: exp(50) puts the odds at
## 5e21, and `odds / (1 + odds)` rounds to exactly 1.0 in a double somewhere above a
## shift of about 36. The mathematical bound is exact at every finite shift; the
## REPRESENTATION saturates. +-10 is eleven times campaign_constants.MOBILISATION_MAX
## and far outside anything the ladder can reach, so it tests the construction rather
## than the library -- and the limit is recorded here rather than quietly dropped,
## because a later session widening this sweep should find the reason and not the
## failure.
func _test_turnout_is_bounded_by_construction() -> void:
	var ns = _new_state().player()
	for shift in [-10.0, -5.0, -1.0, 1.0, 5.0, 10.0]:
		for bloc in OpinionK.BLOC_KEYS:
			ns.campaign_mobilisation[bloc] = shift
			var t: float = Campaign.turnout_of(ns, bloc)
			if t <= 0.0 or t >= 1.0 or not is_finite(t):
				_fail("turnout_of(%s) = %f at shift %f -- outside (0, 1)" % [bloc, t, shift])
	ns.campaign_mobilisation = {}


## The property nobody authored: the same shift is worth more to a bloc with more room.
## Students turn out least and gain most; pensioners turn out most and gain least.
func _test_low_turnout_blocs_have_more_room() -> void:
	var ns = _new_state().player()
	for bloc in OpinionK.BLOC_KEYS:
		ns.campaign_mobilisation[bloc] = 0.40
	var students: float = Campaign.turnout_of(ns, "students") - float(ElectionK.BLOC_TURNOUT["students"])
	var pensioners: float = Campaign.turnout_of(ns, "pensioners") - float(ElectionK.BLOC_TURNOUT["pensioners"])
	if students <= pensioners:
		_fail("the same shift moved pensioners (%f) at least as far as students (%f)" % [pensioners, students])
	ns.campaign_mobilisation = {}


func _test_the_window_is_a_level_read() -> void:
	var state = _new_state()
	var ns = state.player()

	_wind_to(state, K.CAMPAIGN_WINDOW_MONTHS + 1)
	if Campaign.is_open(state, ns):
		_fail("the window is open one month before it should be")

	_wind_to(state, K.CAMPAIGN_WINDOW_MONTHS)
	if not Campaign.is_open(state, ns):
		_fail("the window is shut at exactly CAMPAIGN_WINDOW_MONTHS")

	# INCLUSIVE OF THE MONTH OF THE VOTE, which is what makes the last month of effort
	# count -- Campaign.tick_month() runs before Elections.tick_month() in main.gd.
	_wind_to(state, 0)
	if not Campaign.is_open(state, ns):
		_fail("the window is shut in the month of the vote")


func _test_the_verb_is_refused_outside_the_window() -> void:
	var state = _new_state()
	var ns = state.player()
	_wind_to(state, K.CAMPAIGN_WINDOW_MONTHS + 3)

	if not Campaign.available(state, ns, _loader.campaign_actions).is_empty():
		_fail("actions are available outside the run-up")

	var result := Campaign.execute(state, ns, _loader.campaign_actions, _action(EFFORT_START))
	if result.get("applied", false):
		_fail("execute() applied an effort outside the run-up")
	if not ns.campaign_running.is_empty():
		_fail("a refused execute() still wrote the register")


func _test_an_effort_accrues_every_month() -> void:
	var state = _new_state()
	var ns = state.player()
	_wind_to(state, K.CAMPAIGN_WINDOW_MONTHS)
	Campaign.execute(state, ns, _loader.campaign_actions, _action(EFFORT_START), _site(ns))

	# V2.6b2: the accrual runs at the site's factor, and the site saturates under the
	# meeting it holds every month -- so month 1 is the full fresh rate, month 2 runs
	# at fresh x (1 - the half-life's first month of decay), and months 2 and 3 MATCH
	# because a camping effort re-speaks its region to the clamp every month. The
	# formula is the spec, not a re-implementation: the same three numbers
	# campaign_constants.gd's comment records.
	var rate: float = float(Campaign.terms_of(_loader, EFFORT)["mobilisation"]["workers"])
	var fresh: float = Campaign.fresh_factor(ns, _loader, _site(ns))
	var faded: float = 1.0 - pow(0.5, 1.0 / K.SATURATION_HALF_LIFE_MONTHS)
	for i in range(3):
		Campaign.tick_month(state, _loader)
		var want: float = rate * fresh * (1.0 if i == 0 else 1.0 + faded * float(i))
		var got: float = float(ns.campaign_mobilisation.get("workers", 0.0))
		if not is_equal_approx(got, want):
			_fail("after %d months the accrual is %f, expected %f" % [i + 1, got, want])
	if float(ns.campaign_saturation.get(_site(ns), 0.0)) <= 0.0:
		_fail("three meeting months left no saturation behind")


func _test_the_accumulator_is_clamped() -> void:
	var state = _new_state()
	var ns = state.player()
	_wind_to(state, K.CAMPAIGN_WINDOW_MONTHS)
	Campaign.execute(state, ns, _loader.campaign_actions, _action(EFFORT_START))
	ns.campaign_mobilisation["workers"] = K.MOBILISATION_MAX
	Campaign.tick_month(state, _loader)
	if float(ns.campaign_mobilisation["workers"]) > K.MOBILISATION_MAX:
		_fail("the accumulator passed MOBILISATION_MAX")


func _test_the_bill_reaches_the_budget() -> void:
	var state = _new_state()
	var ns = state.player()
	_wind_to(state, K.CAMPAIGN_WINDOW_MONTHS)

	var quiet: float = ns.total_spending_pct_gdp
	Campaign.execute(state, ns, _loader.campaign_actions, _action(EFFORT_START), _site(ns))
	Campaign.tick_month(state, _loader)

	var cost: float = float(Campaign.terms_of(_loader, EFFORT)["cost_pct_gdp"])
	if not is_equal_approx(ns.campaign_bill_pct_gdp, cost):
		_fail("the bill reads %f, expected the authored %f" % [ns.campaign_bill_pct_gdp, cost])

	Budget.recompute(state, ns)
	if ns.total_spending_pct_gdp <= quiet:
		_fail("the campaign bill did not reach total_spending_pct_gdp")


## The bill STOPS, the mobilisation is spent, and the efforts leave the field -- all
## three on a level read, with no hook in elections.gd and no flag to lift.
func _test_the_register_clears_when_the_window_closes() -> void:
	var state = _new_state()
	var ns = state.player()
	_wind_to(state, K.CAMPAIGN_WINDOW_MONTHS)
	Campaign.execute(state, ns, _loader.campaign_actions, _action(EFFORT_START), _site(ns))
	Campaign.tick_month(state, _loader)
	if ns.campaign_bill_pct_gdp == 0.0:
		_fail("the bill is zero inside the window with an effort running")

	# What Elections.tick_month() does to a re-elected president: the next vote moves a
	# full term out, so the window closes on the level read alone.
	ns.next_executive_year += 5
	Campaign.tick_month(state, _loader)

	if not ns.campaign_running.is_empty():
		_fail("efforts survived the window closing")
	if not ns.campaign_mobilisation.is_empty():
		_fail("mobilisation survived the window closing")
	if ns.campaign_bill_pct_gdp != 0.0:
		_fail("the bill survived the window closing")
	if not ns.campaign_sites.is_empty():
		_fail("a site survived the window closing")
	if ns.campaign_saturation.is_empty():
		_fail("the saturation register was cleared with the campaign -- attention persists")


## src/sim/investment.gd's `withdraw` rather than src/sim/projects.gd's `abandon`, and
## the difference is the model: half a motorway is worth nothing and half a campaign is
## worth half a campaign.
func _test_stopping_keeps_what_it_bought() -> void:
	var state = _new_state()
	var ns = state.player()
	_wind_to(state, K.CAMPAIGN_WINDOW_MONTHS)
	Campaign.execute(state, ns, _loader.campaign_actions, _action(EFFORT_START), _site(ns))
	Campaign.tick_month(state, _loader)
	Campaign.tick_month(state, _loader)
	var bought: float = float(ns.campaign_mobilisation.get("workers", 0.0))

	Campaign.execute(state, ns, _loader.campaign_actions, _action(EFFORT_STOP))
	Campaign.tick_month(state, _loader)

	if not is_equal_approx(float(ns.campaign_mobilisation.get("workers", 0.0)), bought):
		_fail("stopping an effort took back what it had already bought")
	if ns.campaign_bill_pct_gdp != 0.0:
		_fail("a stopped effort is still billing")


## AN EFFORT GETS ONE RUN PER WINDOW, and this is the assertion that makes the one
## above safe. `bloc_offset` is a PERMANENT accumulator paid at the moment of the
## press, and the bill is charged over the running set once a month -- so before
## `campaign_started` existed, start/stop/start inside a single month re-paid the
## offset every cycle for no bill and no elapsed time. On start_town_halls, the only
## effort whose offset is positive, that farmed rural approval to
## legislature_constants.BLOC_OFFSET_MAX in about thirty presses.
##
## Fixed by making the restart illegal rather than by making the offset accrue: the
## offset accruing monthly is a different model, and V1.7a's constants were selected
## against this one. Found by external review, not by this file.
func _test_an_effort_cannot_be_restarted() -> void:
	var state = _new_state()
	var ns = state.player()
	_wind_to(state, K.CAMPAIGN_WINDOW_MONTHS)

	var reward: Dictionary = _action(REWARD_START).effects.get("bloc_offset", {})
	if float(reward.get("rural", 0.0)) <= 0.0:
		_fail("%s no longer carries a positive bloc_offset, so this check measures nothing" % REWARD_START)
		return

	Campaign.execute(state, ns, _loader.campaign_actions, _action(REWARD_START), _site(ns))
	var paid_once: float = float(ns.bloc_offset.get("rural", 0.0))

	Campaign.execute(state, ns, _loader.campaign_actions, _action(REWARD_STOP))
	var again: Dictionary = Campaign.execute(state, ns, _loader.campaign_actions, _action(REWARD_START))

	if again.get("applied", false):
		_fail("an effort was restarted inside its own window")
	if not is_equal_approx(float(ns.bloc_offset.get("rural", 0.0)), paid_once):
		_fail("restarting an effort paid its bloc_offset a second time")
	if Campaign.available(state, ns, _loader.campaign_actions).has(_action(REWARD_START)):
		_fail("a spent effort is still offered as available, so the panel would show a dead button")

	# And the ledger clears with everything else, so the NEXT run-up is a clean slate.
	_wind_to(state, K.CAMPAIGN_WINDOW_MONTHS + 2)
	Campaign.tick_month(state, _loader)
	if not ns.campaign_started.is_empty():
		_fail("the spent-effort register survived the window closing")


## The whole point: the register reaches Elections.vote_share(). Measured against a
## control run from the same state, so the assertion is about the campaign and not
## about the month.
func _test_mobilisation_moves_the_vote() -> void:
	var state = _new_state()
	var ns = state.player()
	var party_list: Array = _loader.parties.get(PLAYER, [])
	var before := Elections.vote_share(ns, party_list, ns.incumbent_party_id)

	for bloc in OpinionK.BLOC_KEYS:
		ns.campaign_mobilisation[bloc] = 0.0
	var flat := Elections.vote_share(ns, party_list, ns.incumbent_party_id)
	for pid in before:
		if float(flat[pid]) != float(before[pid]):
			_fail("an all-zero mobilisation moved %s's share" % pid)

	ns.campaign_mobilisation["students"] = 0.40
	var after := Elections.vote_share(ns, party_list, ns.incumbent_party_id)
	var moved := false
	for pid in before:
		if not is_equal_approx(float(after[pid]), float(before[pid])):
			moved = true
	if not moved:
		_fail("mobilising a bloc moved nobody's vote share")

	var total := 0.0
	for pid in after:
		total += float(after[pid])
	if not is_equal_approx(total, 1.0):
		_fail("vote shares sum to %f under a campaign, not 1.0" % total)


## docs/media-model.md section 2 CUT government messaging, and section 7's bullet says
## this session READS that machine rather than rebuilding it. Checked by reading the
## source, so the refusal survives a later session adding a line rather than a file.
func _test_no_framing_machine() -> void:
	var path := "res://src/sim/campaign.gd"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("could not read %s" % path)
		return
	var text := file.get_as_text()
	file.close()
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		for banned in ["framing_gain", "press_freedom"]:
			if trimmed.contains(banned):
				_fail("campaign.gd writes '%s' -- V1.5d cut the campaign-time twin of that machine" % banned)


## Preloads its own constants, opinion's and elections' -- three constant files and no
## SYSTEM. src/sim/elections.gd reads this file; a reverse edge would be a cycle.
func _test_campaign_is_a_leaf() -> void:
	var path := "res://src/sim/campaign.gd"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("could not read %s" % path)
		return
	var text := file.get_as_text()
	file.close()
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("const ") or not trimmed.contains("preload("):
			continue
		if trimmed.contains("_constants.gd"):
			continue
		# V5.1-0d (G1): the capital rule is a src/core reader shared with the map
		# and the diary, not a system -- it preloads nothing and holds no state.
		if trimmed.contains("res://src/core/capital.gd"):
			continue
		_fail("campaign.gd preloads a system: `%s`" % trimmed)


## V2.6b2's verb change, asserted at both halves: a start without a region is refused
## (the panel's disabled button made loud), and a region that is not the acting
## nation's own is refused -- validated against the live V2.6a register, so no second
## roster exists to drift.
func _test_the_site_is_required_and_must_be_ones_own() -> void:
	var state = _new_state()
	var ns = state.player()
	_wind_to(state, K.CAMPAIGN_WINDOW_MONTHS)

	var result: Dictionary = Campaign.execute(state, ns, _loader.campaign_actions, _action(EFFORT_START))
	if result.get("applied", false):
		_fail("a start without a region was applied")
	if result.get("reason", "") == "":
		_fail("a place-less start was refused without a reason")
	if not ns.campaign_running.is_empty():
		_fail("a refused start still wrote the running register")

	# Any id that is not a key of the acting nation's own register must be refused --
	# taken from ANOTHER nation's register so the negative case is real and not a typo.
	var deu_state = GameState.new_game(_loader, "DEU")
	var foreign: String = Campaign.region_ids(deu_state.player(), _loader)[0]
	if ns.region_pop_share.has(foreign):
		_fail("test bug: %s is in FRA's register after all" % foreign)
	var other: Dictionary = Campaign.execute(state, ns, _loader.campaign_actions, _action(EFFORT_START), foreign)
	if other.get("applied", false):
		_fail("a start in another nation's region was applied")

	var ok: Dictionary = Campaign.execute(state, ns, _loader.campaign_actions, _action(EFFORT_START), _site(ns))
	if not ok.get("applied", false):
		_fail("a start at the nation's own region was refused: %s" % str(ok))
	if String(ns.campaign_sites.get(EFFORT, "")) != _site(ns):
		_fail("the applied start did not record its site")


## The fresh factor is mean-one in UNIFORM weights over the nation's regions,
## EXACTLY, so the average choice delivers the authored rate. 1e-12 is the tolerance
## docs/siting-model.md section 4 measured V2.6b1's at. The population-weighted form
## was measured and refused -- it empties V1.7a's calibration band -- and the reason
## lives in Campaign.fresh_factor()'s doc, so a session re-deriving the idiom finds
## the measurement before the failure.
func _test_the_fresh_factor_is_mean_one() -> void:
	var ns = _new_state().player()
	var total := 0.0
	var count := 0.0
	for region in _loader.regions.get(PLAYER, []):
		total += Campaign.fresh_factor(ns, _loader, String(region.id))
		count += 1.0
	if absf(total / count - 1.0) > 1e-12:
		_fail("the fresh factor's uniform mean is %.15f, not 1.0" % (total / count))


## The choice varies, and the second meeting in the same place is worth less: the
## factor differs across regions, and factor_of() sits strictly under fresh_factor()
## once the region has been spoken to. The clamp is asserted rather than assumed.
func _test_the_factor_varies_and_saturation_bites() -> void:
	var ns = _new_state().player()
	var ids: Array = Campaign.region_ids(ns, _loader)
	var best := -1.0
	var worst := INF
	for rid in ids:
		best = maxf(best, Campaign.fresh_factor(ns, _loader, String(rid)))
		worst = minf(worst, Campaign.fresh_factor(ns, _loader, String(rid)))
	if best <= worst:
		_fail("the fresh factor does not vary across the nation's regions")

	var rid := _site(ns)
	ns.campaign_saturation[rid] = 1.0
	if Campaign.factor_of(ns, _loader, rid) != 0.0:
		_fail("a fully spoken-to region still offers reach")
	ns.campaign_saturation[rid] = 0.5
	var half: float = Campaign.factor_of(ns, _loader, rid)
	if not is_equal_approx(half, Campaign.fresh_factor(ns, _loader, rid) * 0.5):
		_fail("the discount is not (1 - spoken): %f" % half)
	if Campaign.factor_of(ns, _loader, rid) >= Campaign.fresh_factor(ns, _loader, rid):
		_fail("saturation did not discount the site")


## THE TOUR, IN THE REAL MODEL. The capital camps, the register saturates, and after
## two meeting months the best fresh OTHER region out-offers the capital's discounted
## factor -- the reorder tools/tour_probe.gd measured at the register scale, asserted
## here so a constant drift turns it red. Travel pricing is asserted alongside: the
## capital's own journey is one day and the farthest region costs more.
func _test_the_tour_leaves_the_capital() -> void:
	var state = _new_state()
	var ns = state.player()
	_wind_to(state, K.CAMPAIGN_WINDOW_MONTHS)
	var home := _site(ns)
	if Campaign.travel_days_to(ns, _loader, home) != 1:
		_fail("the capital's own journey is not one day")
	var farthest := ""
	var farthest_days := 0
	for rid in Campaign.region_ids(ns, _loader):
		var days := Campaign.travel_days_to(ns, _loader, String(rid))
		if days > farthest_days:
			farthest_days = days
			farthest = String(rid)
	if farthest_days <= 1:
		_fail("no region is more than one day from the capital")

	Campaign.execute(state, ns, _loader.campaign_actions, _action(EFFORT_START), home)
	Campaign.tick_month(state, _loader)
	Campaign.tick_month(state, _loader)

	var camped: float = Campaign.factor_of(ns, _loader, home)
	var best_other := 0.0
	for rid in Campaign.region_ids(ns, _loader):
		if String(rid) == home:
			continue
		best_other = maxf(best_other, Campaign.factor_of(ns, _loader, String(rid)))
	if best_other <= camped:
		_fail("after two meeting months at the capital no other region out-offers it (%f vs %f)" % [best_other, camped])


## The nine never campaign, because nothing ever executes an action for them. V1.3g's,
## V1.6e's and V1.6f's honest limitation, pinned rather than described.
func _test_the_nine_never_campaign() -> void:
	var state = _new_state()
	for i in range(24):
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		Economy.tick_month(state)
		Budget.tick_month(state)
		Campaign.tick_month(state, _loader)
	for id in state.nations:
		if String(id) == PLAYER:
			continue
		var ns = state.nations[id]
		if not ns.campaign_running.is_empty():
			_fail("%s put an effort in the field with no player command" % id)
		if ns.campaign_bill_pct_gdp != 0.0:
			_fail("%s is paying a campaign bill of %f" % [id, ns.campaign_bill_pct_gdp])
		if not ns.campaign_saturation.is_empty():
			_fail("%s has spoken-to regions with no campaign verb" % id)


## The cost and the reach are AUTHORED, so caching either on NationState would put
## content in the save file. V1.4a's, V1.6e's and V1.6f's property in a fifth register.
func _test_the_register_carries_no_content() -> void:
	var state = _new_state()
	var ns = state.player()
	_wind_to(state, K.CAMPAIGN_WINDOW_MONTHS)
	Campaign.execute(state, ns, _loader.campaign_actions, _action(EFFORT_START), _site(ns))
	Campaign.execute(state, ns, _loader.campaign_actions, _action(OTHER_START), _site(ns))
	Campaign.tick_month(state, _loader)

	for entry in ns.campaign_running:
		if typeof(entry) != TYPE_STRING:
			_fail("the running register holds a %s, not an effort id" % typeof(entry))
	for bloc in ns.campaign_mobilisation:
		if not OpinionK.BLOC_KEYS.has(String(bloc)):
			_fail("the mobilisation register holds '%s', which is not a bloc" % bloc)
		if typeof(ns.campaign_mobilisation[bloc]) != TYPE_FLOAT:
			_fail("the mobilisation register holds a non-float for '%s'" % bloc)
	for eid in ns.campaign_sites:
		if typeof(ns.campaign_sites[eid]) != TYPE_STRING:
			_fail("the site register holds a non-string for '%s'" % eid)
		if not ns.region_pop_share.has(String(ns.campaign_sites[eid])):
			_fail("the site register names '%s', which is not one of the nation's regions" % ns.campaign_sites[eid])
	for rid in ns.campaign_saturation:
		if typeof(ns.campaign_saturation[rid]) != TYPE_FLOAT:
			_fail("the saturation register holds a non-float for '%s'" % rid)
