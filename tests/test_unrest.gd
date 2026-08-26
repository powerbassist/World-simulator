extends SceneTree

## V1.5c. The grievance stock, the acting agent, and the declared inequality stopgap.
## Model: docs/unrest-model.md.
##
## The load-bearing assertions here are the ones about what does NOT happen, and each
## one is a property this session either found, deliberately declined, or inherited:
##
##   - the stock reads EXACTLY 0.0 at new game for all ten, exact equality and not
##     is_zero_approx, which is V1.4a's standard and what lets a channel that writes a
##     growth impulse ship without moving a figure anywhere;
##   - UNREST_BLOCS does NOT contain `business`, because a business owner is not who
##     strikes -- QUALITY_KEYS' refusal-is-the-design shape;
##   - the hardship term is NOT the national roll-up, asserted by moving an issue only
##     `business` weights and showing the grievance does not notice. That is what keeps
##     it a different quantity from Discipline.unpopularity() rather than a slower copy;
##   - the INEQUALITY READ IS A STOPGAP, asserted by mutating the three distributional
##     instruments the model actually has -- the corporate rate, a state holding and a
##     sector burden -- and requiring the index not to move. §6 turns this red;
##   - src/sim/ never reads GameState.unrest_acts back, so the stock stays the only
##     memory, which is V1.3e's *no grievance ledger* property in the one session that
##     could have built the ledger literally;
##   - an `unrest_pct` precondition may only ever be `>=`, because available() only
##     OPENS laws and a `<=` would make unrest an uncontestable gate -- ROADMAP.md's
##     call 4, and §1's judiciary is the other one;
##   - the nine never move, the has_budget gate stated as a property the way
##     tests/test_society.gd and tests/test_defence.gd state theirs.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const K = preload("res://src/sim/unrest_constants.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Society = preload("res://src/sim/society.gd")
const Demography = preload("res://src/sim/demography.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LK = preload("res://src/sim/legislature_constants.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_registry_excludes_the_bloc_that_does_not_strike()
	_test_starts_at_exactly_zero()
	_test_the_nine_never_move()
	_test_hardship_is_not_the_national_roll_up()
	_test_grievance_rises_under_hardship()
	_test_settlement_closes_what_hardship_opens()
	_test_the_stance_has_one_writer()
	_test_inequality_is_a_declared_stopgap()
	_test_inequality_has_no_writer_here()
	_test_the_act_is_deterministic_and_gated()
	_test_the_impulse_decays()
	_test_the_label_is_display_only()
	_test_every_label_is_reachable_in_principle()
	_test_precondition_is_open_only()
	_test_opinion_load_is_silent_when_calm()
	_test_unrest_preloads_are_exactly_these()
	_test_content_loads()
	_finish()


func _new_state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	return state


func _step(state, months_in: int) -> void:
	state.year = 2026 + int(months_in / 12)
	state.month = (months_in % 12) + 1
	Economy.tick_month(state)
	Budget.tick_month(state)
	Opinion.tick_month(state)
	Demography.tick_month(state)
	Society.tick_month(state)
	Unrest.tick_month(state)


## A budget bad enough to provoke: balance_probe's `austerity` deltas.
func _commit_austerity(state) -> void:
	var ns = state.player()
	var lines := {}
	for pair in [["health", -2.5], ["education", -2.0], ["defence", -1.0], ["pensions", -3.5], ["infrastructure", -2.0]]:
		lines[pair[0]] = maxf(float(ns.start_spending_pct_gdp.get(pair[0], 0.0)) + float(pair[1]), 0.0)
	Budget.commit(state, {
		"spending_pct_gdp": lines,
		"tax_rates_pct": {
			"income": float(ns.start_tax_rates_pct["income"]) + 6.0,
			"corporate": float(ns.start_tax_rates_pct["corporate"]) + 5.0,
			"vat": float(ns.start_tax_rates_pct["vat"]) + 4.0,
		},
	})


# --- The registry -------------------------------------------------------------

## THE REFUSAL IS THE DESIGN, society_constants.QUALITY_KEYS' shape. `business` is the
## bloc that cannot be in this list: a business owner is not who strikes, and the row's
## own noun is "trade unions". `pensioners` is out for a weaker reason and is not
## asserted, so a later session may add it without arguing with a test.
func _test_registry_excludes_the_bloc_that_does_not_strike() -> void:
	if K.UNREST_BLOCS.has("business"):
		_fail("UNREST_BLOCS contains `business` -- a business owner is not who strikes, and a grievance weighted by the people it is aimed at is not a grievance")
	if K.UNREST_BLOCS.is_empty():
		_fail("UNREST_BLOCS is empty, so the hardship term reads nobody")
	for bloc in K.UNREST_BLOCS:
		if not OK.BLOC_KEYS.has(bloc):
			_fail("UNREST_BLOCS names %s, which is not a bloc" % bloc)


# --- The stock ------------------------------------------------------------------

## EXACT equality, not is_zero_approx. Every term of the target is a deviation against
## the nation's own start, so a fresh game is exactly quiet -- and that exactness is
## what lets a channel writing into economy.gd's growth sum go live with the balance
## harness untouched wherever no act fires.
func _test_starts_at_exactly_zero() -> void:
	var state = _new_state()
	for id in state.nations:
		var ns = state.nations[id]
		if ns.unrest_pct != 0.0:
			_fail("%s starts at unrest %s rather than exactly 0.0" % [id, str(ns.unrest_pct)])
		if ns.unrest_impulse_pct != 0.0:
			_fail("%s starts with a live unrest impulse" % id)
		if ns.unrest_opinion_load != 0.0:
			_fail("%s starts with a live unrest opinion load" % id)
	if not state.unrest_acts.is_empty():
		_fail("a new game already has industrial action on the record")

	# The target itself, not just the stock: a stock seeded at zero over a target that
	# is not zero would step on frame one, which is defence.gd's authored-transient
	# failure arriving through the back door.
	if Unrest.unrest_target(state.player()) != 0.0:
		_fail("the grievance target is %s at new game rather than exactly 0.0" % str(Unrest.unrest_target(state.player())))


## The has_budget gate stated as a property. The nine have no opinion model, so a
## grievance built out of Opinion.issue_satisfaction() would be a number with no
## meaning -- and an output impulse on a nation nobody governs would reach the player
## through the trade weight, moving figures V1.3b measured.
func _test_the_nine_never_move() -> void:
	var state = _new_state()
	_commit_austerity(state)
	for i in range(120):
		_step(state, i)
	for id in state.nations:
		var ns = state.nations[id]
		if ns.has_budget:
			continue
		if ns.unrest_pct != 0.0:
			_fail("%s has no budget and still reached unrest %s" % [id, str(ns.unrest_pct)])
		if ns.unrest_impulse_pct != 0.0:
			_fail("%s has no budget and still took an output hit" % id)
	for act in state.unrest_acts:
		if String(act["nation_id"]) != PLAYER:
			_fail("%s acted, and only the player's nation has a grievance model" % act["nation_id"])


## THE ASSERTION THAT KEEPS THIS A DIFFERENT QUANTITY. Discipline.unpopularity() is
## already a [0, 1] anger index over the whole electorate, read by three systems, so a
## grievance target built the same way would be that number with a lag -- the
## military_capability / potential_shift_pct failure a fifth time.
##
## `tax_corporate` is weighted by `business` at 0.25 and by nobody in UNREST_BLOCS, so
## moving it is the cleanest available separation: national approval must notice and
## the grievance must not.
func _test_hardship_is_not_the_national_roll_up() -> void:
	var state = _new_state()
	var ns = state.player()
	var before := Unrest.hardship(Opinion.issue_satisfaction(ns))
	ns.tax_rates_pct["corporate"] = float(ns.start_tax_rates_pct["corporate"]) + 20.0
	var sat: Dictionary = Opinion.issue_satisfaction(ns)
	if is_equal_approx(float(sat["tax_corporate"]), 0.0):
		_fail("a 20-point corporate rate rise did not move the tax_corporate issue, so this test proves nothing")
	if not is_equal_approx(Unrest.hardship(sat), before):
		_fail("the grievance noticed a corporate tax rise -- the hardship term is reading blocs outside UNREST_BLOCS, which makes it Discipline.unpopularity() with a lag")


func _test_grievance_rises_under_hardship() -> void:
	var state = _new_state()
	_commit_austerity(state)
	for i in range(60):
		_step(state, i)
	if state.player().unrest_pct <= 0.0:
		_fail("five years of austerity produced no grievance at all")
	if state.player().unrest_pct >= K.UNREST_MAX:
		_fail("austerity pinned the grievance at the clamp, so the clamp is setting the number rather than guarding it")


## Without this the layer is the permanent monotone charge docs/defence-model.md names:
## a rising cost with no verb able to close it. Asserted rather than left to the probe,
## because the probe is not run by tools/run_tests.sh.
func _test_settlement_closes_what_hardship_opens() -> void:
	var loud = _new_state()
	_commit_austerity(loud)
	var calm = _new_state()
	_commit_austerity(calm)
	for i in range(60):
		calm.player().settlement_stance = K.SETTLEMENT_STANCE_MAX
		_step(loud, i)
		_step(calm, i)
	if calm.player().unrest_pct >= loud.player().unrest_pct:
		_fail("a saturated settlement did not lower the grievance")
	if calm.player().unrest_pct >= K.UNREST_THRESHOLD_PCT:
		_fail("a saturated settlement left the grievance above the threshold, so nothing in the game can stop a strike")

	# SIGNED BOTH WAYS. An imposed settlement is the negative direction on the same
	# accumulator, and without it every settlement law is inert on a calm state --
	# V1.3f's property that nothing on the law list does nothing.
	var harsh = _new_state()
	_commit_austerity(harsh)
	for i in range(60):
		harsh.player().settlement_stance = -K.SETTLEMENT_STANCE_MAX
		_step(harsh, i)
	if harsh.player().unrest_pct <= loud.player().unrest_pct:
		_fail("an imposed settlement did not raise the grievance, so the stance is one-directional")


## src/sim/unrest.gd may READ ns.settlement_stance and must never write it: the channel's
## single writer is Legislature.apply(). The read-the-file idiom test_society.gd,
## test_demography.gd, test_people.gd and test_calendar.gd all use.
func _test_the_stance_has_one_writer() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/unrest.gd")
	if src == "":
		_fail("could not read src/sim/unrest.gd")
		return
	for line in src.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.contains("settlement_stance =") or stripped.contains("settlement_stance +="):
			_fail("unrest.gd writes ns.settlement_stance -- the channel's single writer is Legislature.apply(), and this is the second")


# --- The declared stopgap -------------------------------------------------------

## WHAT MAKES "DECLARED STOPGAP" MECHANICAL RATHER THAN PROSE. docs/tiers/v1.md §6 owns
## the distributional instruments, and the three the model actually has today are the
## corporate rate, a state holding and a sector burden. The index must be blind to all
## three -- and this test is written to FAIL the day §6 makes it live, which is the
## point of it: the stopgap is discharged by a visible test change, not silently.
func _test_inequality_is_a_declared_stopgap() -> void:
	var base = _new_state()
	var mutated = _new_state()
	var ns = mutated.player()

	ns.tax_rates_pct["corporate"] = 60.0
	for firm_id in ns.companies:
		(ns.companies[firm_id] as Dictionary)["state_share"] = 1.0
	for sector in ns.regulation_burden:
		ns.regulation_burden[sector] = 1.0

	for i in range(168):
		_step(base, i)
		_step(mutated, i)

	if Unrest.inequality_deviation(mutated.player()) != Unrest.inequality_deviation(base.player()):
		_fail("the inequality index moved when the corporate rate, every state holding and every sector burden did -- it is no longer a stopgap, and §6's row has to say so")

	# And it is not inert: the measured drift must actually reach the deviation, or the
	# insensitivity above is true for the boring reason.
	if is_equal_approx(Unrest.inequality_deviation(base.player()), 0.0):
		_fail("the inequality deviation is still 0.0 after fourteen years, so the drift never reached it")


## No stored index anywhere in this file. The drift lives on Demography, the base is
## content, and the deviation is a subtraction -- Defence.allies()' shape, which is what
## keeps the stopgap out of the save format entirely.
func _test_inequality_has_no_writer_here() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/unrest.gd")
	if src == "":
		_fail("could not read src/sim/unrest.gd")
		return
	for line in src.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		# Matched as an ASSIGNMENT rather than as "a line mentioning gini", which the
		# first version did -- it skipped any line containing `float(`, so
		# `ns.gini_index = float(x)` walked straight through the check written to catch
		# exactly that. Same shape as the settlement_stance assertion above, and it is
		# the shape because that one is right.
		if (
			stripped.contains("gini_index =") or stripped.contains("gini_index +=")
			or stripped.contains("gini_index -=") or stripped.contains("gini_index_per_yr =")
		):
			_fail("unrest.gd assigns a gini field -- the drift's single writer is Demography.tick_month(), and this is the second: %s" % stripped)


# --- The agent ------------------------------------------------------------------

func _test_the_act_is_deterministic_and_gated() -> void:
	var state = _new_state()
	var ns = state.player()

	ns.unrest_pct = K.UNREST_THRESHOLD_PCT - 0.01
	if Unrest.would_act(ns):
		_fail("the unions acted below the threshold")
	ns.unrest_pct = K.UNREST_THRESHOLD_PCT
	if not Unrest.would_act(ns):
		# A LEVEL READ, not an edge trigger: a government inheriting a country already
		# over the line must face what is already there. defence.gd's obligation call.
		_fail("the unions did not act at exactly the threshold -- this is a level read, not an edge trigger")
	ns.unrest_cooldown_months = 1
	if Unrest.would_act(ns):
		_fail("the unions acted during the cooldown")

	# Two identical states act identically. No randomness anywhere, which is what the
	# balance harness's whole value rests on.
	var a = _new_state()
	var b = _new_state()
	_commit_austerity(a)
	_commit_austerity(b)
	for i in range(96):
		_step(a, i)
		_step(b, i)
	if a.player().unrest_pct != b.player().unrest_pct:
		_fail("two identical runs produced different grievances -- something here is not deterministic")
	if a.unrest_acts.size() != b.unrest_acts.size():
		_fail("two identical runs produced different numbers of acts")
	if a.unrest_acts.is_empty():
		_fail("eight years of austerity produced no industrial action, so the agent is unreachable")


## Decaying and not sustained, which is the distinction economy.gd's own comment draws
## between this addend and the two beside it. Decayed by Unrest so the field keeps one
## writer, and asserted here because a sustained impulse wearing a decaying comment
## would be invisible everywhere else.
func _test_the_impulse_decays() -> void:
	var state = _new_state()
	var ns = state.player()
	ns.unrest_pct = K.UNREST_MAX
	ns.unrest_cooldown_months = 0
	Unrest.tick_month(state)
	var struck := float(ns.unrest_impulse_pct)
	if struck >= 0.0:
		_fail("an act at maximum grievance produced no negative output impulse")
	ns.unrest_pct = 0.0
	for _i in range(24):
		Unrest.tick_month(state)
	if absf(float(ns.unrest_impulse_pct)) >= absf(struck) * 0.5:
		_fail("the output impulse did not decay -- a strike is a shock, and a sustained one would be coercion_impulse_pct's shape rather than demand_impulse_pct's")
	if absf(float(ns.unrest_impulse_pct)) > K.UNREST_IMPULSE_MAX_PCT:
		_fail("the impulse escaped its clamp")


## V1.3f's foreign_acts property, and here it is the one that keeps the session honest:
## the grievance number IS the memory, so the moment a decision reads the act list back
## the model has two memories that can disagree. Checked over the whole directory rather
## than over unrest.gd, because the failure is a LATER file reading it.
func _test_the_label_is_display_only() -> void:
	var dir := DirAccess.open("res://src/sim")
	if dir == null:
		_fail("could not open res://src/sim")
		return
	for name in dir.get_files():
		if not name.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string("res://src/sim/%s" % name)
		for line in src.split("\n"):
			var stripped: String = line.strip_edges()
			if stripped.begins_with("#"):
				continue
			if not stripped.contains("unrest_acts"):
				continue
			# The writer is allowed to append and to trim. Anything else is a read.
			if name == "unrest.gd" and (stripped.contains("append(") or stripped.contains("remove_at(") or stripped.contains("size()")):
				continue
			_fail("src/sim/%s reads GameState.unrest_acts: %s" % [name, stripped])


## A label the model cannot reach is a figure computed and displayed nowhere --
## docs/trade-model.md's `refused_by_partner` failure, which this project has hit five
## times. The probe measures reachability against the real regimes; this asserts the
## weaker structural half, that every label owns a non-empty slice of the span.
func _test_every_label_is_reachable_in_principle() -> void:
	var seen := {}
	var span: float = K.UNREST_MAX - K.UNREST_THRESHOLD_PCT
	for step in range(0, 1001):
		var value: float = K.UNREST_THRESHOLD_PCT + span * float(step) / 1000.0
		seen[Unrest.act_label(value)] = true
	for label in K.ACT_LABELS:
		if not seen.has(label):
			_fail("no grievance between the threshold and the ceiling is called `%s`" % label)


## `unrest_pct` may only ever be tested with `>=`. available() only OPENS laws, so a
## `>=` precondition is a lever unrest hands the player -- while a `<=` one would take a
## lever away, which makes unrest an uncontestable gate on player action. ROADMAP.md's
## call 4 says two of those is one machine claimed twice, and docs/tiers/v1.md §1's
## judiciary is the other.
func _test_precondition_is_open_only() -> void:
	if not LK.PRECONDITION_FIELDS.has("unrest_pct"):
		_fail("unrest_pct is not a precondition field, so nothing in the game can respond to a strike")
	for law in _loader.laws:
		for pre in law.preconditions:
			if String(pre.get("field", "")) != "unrest_pct":
				continue
			if String(pre.get("op", "")) != ">=":
				_fail("%s gates on unrest_pct with `%s` -- only `>=` is allowed, because a law that CLOSES as the country gets angrier is a gate rather than a lever" % [law.id, pre.get("op", "")])


func _test_opinion_load_is_silent_when_calm() -> void:
	var state = _new_state()
	if Unrest.opinion_load(state.player()) != 0.0:
		_fail("a calm country still takes an approval load")
	state.player().unrest_pct = K.UNREST_MAX
	if Unrest.opinion_load(state.player()) <= 0.0:
		_fail("maximum grievance costs no approval at all -- the session's price is missing")

	# Read off the STOCK and not off the act, which is what makes it the statistic's
	# price rather than the strike's: a country at grievance 44 has not struck and is
	# still angry.
	state.player().unrest_pct = K.UNREST_THRESHOLD_PCT - 1.0
	if Unrest.opinion_load(state.player()) <= 0.0:
		_fail("a country angry but not yet striking pays nothing, so the price is on the act rather than on the statistic")


## Not a leaf -- this file preloads opinion.gd for issue_satisfaction() -- but the set
## is closed and the one preload that must NOT appear is economy.gd: this file writes an
## impulse Economy reads next month, and a reverse edge would make that lag a convention
## instead of a fact. opinion.gd must not appear on the other side either, and it does
## not: opinion.gd reads ns.unrest_opinion_load off NationState.
func _test_unrest_preloads_are_exactly_these() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/unrest.gd")
	if src == "":
		_fail("could not read src/sim/unrest.gd")
		return
	var allowed := [
		"res://src/sim/unrest_constants.gd",
		"res://src/sim/opinion.gd",
		"res://src/sim/opinion_constants.gd",
		"res://src/sim/economy_constants.gd",
		# V1.6d, and it is the first addition to this list since V1.5c wrote it. tax.gd
		# is what makes the player's own budget reach inequality_deviation(), and it is
		# admitted rather than routed around because the alternative -- reading the
		# offset off a field somebody else wrote -- is the second writer the whole
		# discharge exists to avoid.
		"res://src/sim/tax.gd",
		# V1.1e, the SECOND addition, and it is admitted on V1.6d's reason above rather
		# than on a new one: judiciary.gd is what makes a captured court reach
		# unrest_target(), and reading the load off a field somebody else wrote would be
		# the second writer the whole discharge exists to avoid. It is also a LEAF -- it
		# preloads nothing but its own constants -- so the edge runs one way and adds no
		# ordering question, which is exactly what tax.gd's note says about tax.gd.
		"res://src/sim/judiciary.gd",
	]
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("const"):
			continue
		if not line.contains("preload("):
			continue
		var ok := false
		for path in allowed:
			if line.contains(path):
				ok = true
		if not ok:
			_fail("unrest.gd preloads something outside its allowed set: %s" % line.strip_edges())

	var opinion_src := FileAccess.get_file_as_string("res://src/sim/opinion.gd")
	if opinion_src.contains("res://src/sim/unrest.gd"):
		_fail("opinion.gd preloads unrest.gd, and unrest.gd preloads opinion.gd -- that is the cycle ns.unrest_opinion_load exists to avoid")

	# V1.6d. Admitting tax.gd above is only safe while tax.gd is a LEAF, so that is
	# checked here rather than assumed: this file's whole preload argument is about
	# edges, and an edge to a module that itself preloads systems would smuggle the
	# graph back in one hop further out. tests/test_tax.gd owns the statelessness of
	# that file; this owns its position in the graph.
	var tax_src := FileAccess.get_file_as_string("res://src/sim/tax.gd")
	if tax_src == "":
		_fail("could not read src/sim/tax.gd")
		return
	for line in tax_src.split("
"):
		var stripped: String = line.strip_edges()
		if not stripped.begins_with("const") or not stripped.contains("preload("):
			continue
		if not stripped.contains("_constants.gd"):
			_fail("tax.gd preloads something that is not a constants file, so it is no longer a leaf and unrest.gd's preload set is no longer closed: %s" % stripped)


func _test_content_loads() -> void:
	var with_settlement: Array = []
	var positive := false
	var negative := false
	var gated := false
	for law in _loader.laws:
		var society: Dictionary = law.effects.get("society", {})
		if not society.has("settlement"):
			continue
		with_settlement.append(law.id)
		if float(society["settlement"]) > 0.0:
			positive = true
		else:
			negative = true
		for pre in law.preconditions:
			if String(pre.get("field", "")) == "unrest_pct":
				gated = true

	if with_settlement.is_empty():
		_fail("no law carries effects.society.settlement, so the third term on the channel is unreachable")
	# Both directions reachable IN PLAY, not merely representable -- test_society.gd's
	# argument for corruption, and the same reason: a probe sweeping a saturated stance
	# in a direction no law can produce is measuring a state the game cannot reach.
	if not positive:
		_fail("no law settles WITH the unions, so the calming half of the stance is unreachable")
	if not negative:
		_fail("no law imposes a settlement, so the inflaming half of the stance is unreachable")
	if not gated:
		_fail("no law gates on unrest_pct, so `protests forcing a response` is a sentence with no content behind it")

	# The ten nations all carry the imported inequality block, or the stopgap has no
	# per-nation content and every nation drifts identically -- the clustered
	# `coalition_position` failure the measured import exists to avoid.
	var slopes := {}
	for id in _loader.nations:
		var nation = _loader.nations[id]
		if not nation.inequality.has("gini_index_per_yr"):
			_fail("%s has no imported.inequality block" % id)
			continue
		slopes[id] = float(nation.inequality["gini_index_per_yr"])
	var rising := 0
	var falling := 0
	for id in slopes:
		if float(slopes[id]) > 0.0:
			rising += 1
		elif float(slopes[id]) < 0.0:
			falling += 1
	if rising == 0 or falling == 0:
		_fail("every nation's Gini moves the same way -- a one-signed roster is the authored-pyramid risk V1.5b measured its way out of")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_unrest: all checks passed")
		quit(0)
		return
	for message in _failures:
		printerr(message)
	quit(1)
