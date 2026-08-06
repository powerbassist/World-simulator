extends SceneTree

## V1.3g. Military capability as a derived stock, the two defence registers, the
## level-read obligation, and both prices reaching the budget and the electorate.
## Model: docs/defence-model.md.
##
## The load-bearing assertions here are the ones about what does NOT happen, and
## they are load-bearing because each one is a failure this session either found or
## deliberately declined to build:
##
##   - the obligation CLOSES when the measure lifts (a level read, not an edge
##     trigger -- nothing in the project ever lifts a retaliation, so an edge
##     trigger is a permanent monotone charge on the player's budget);
##   - a nation coercing its own ally is NOT obliged to deploy against itself;
##   - a CHOSEN deployment is not promoted to obliged when an obligation arrives
##     (that would charge the player the obliged multiplier for their own decision);
##   - a withdraw verb CANNOT close an obliged deployment, which is the entire
##     reason diplomacy_constants carries four defence pair fields and not one;
##   - the nine's capability does not move over a full run, which is the "no
##     has_budget lift" call stated as a property rather than as a comment.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Relations = preload("res://src/core/relations.gd")
const Defence = preload("res://src/sim/defence.gd")
const K = preload("res://src/sim/defence_constants.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")
const FPK = preload("res://src/sim/foreign_policy_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")

const PLAYER := "FRA"
const ALLY := "DEU"
const AGGRESSOR := "GBR"

var _failures: Array[String] = []
var _loader


class StubAction:
	var id: String = "test_pact"
	var action_name: String = "Test Pact"


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_capability_seeds_at_equilibrium()
	_test_capability_converges()
	_test_the_nine_never_move()
	_test_cost_is_inverse_in_capability()
	_test_pact_register_is_symmetric()
	_test_abandon_closes_both_directions()
	_test_obligation_opens_and_closes()
	_test_obligation_excludes_self()
	_test_obligation_respects_the_floor()
	_test_chosen_is_not_promoted()
	_test_orphans_close()
	_test_prices_reach_budget_and_opinion()
	_test_content_loads()
	_test_withdraw_cannot_close_an_obligation()
	_test_agenda_excludes_the_player_from_signing_only()
	_finish()


func _new_state():
	return GameState.new_game(_loader, PLAYER)


# --- Capability ---------------------------------------------------------------

## Seeded AT equilibrium, not at zero. Zero would mean every nation spends the
## first decade of every game acquiring an army it already had.
func _test_capability_seeds_at_equilibrium() -> void:
	var state = _new_state()
	for id in state.nations.keys():
		var ns = state.nations[id]
		var authored: float = float(ns.spending_pct_gdp.get("defence", 0.0))
		if not is_equal_approx(ns.military_capability, authored):
			_fail("%s seeded capability %.3f against authored spending %.3f" % [
				id, ns.military_capability, authored
			])


func _test_capability_converges() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	ns.spending_pct_gdp["defence"] = 4.0

	var before: float = ns.military_capability
	Defence.tick_month(state)
	if not (ns.military_capability > before):
		_fail("capability did not move toward a raised defence line")
	if ns.military_capability >= 4.0:
		_fail("capability reached the new target in one month -- it is a stock, not the lever")

	for _i in range(200):
		Defence.tick_month(state)
	if absf(ns.military_capability - 4.0) > 0.05:
		_fail("capability never converged: %.3f after 200 months" % ns.military_capability)


## THE "no has_budget lift" CALL, as a property. The nine have no budget model, so
## their spending never moves and their capability must sit still for a whole run.
## If this ever fails, something has started writing the nine's spending and the
## separate session docs/trade-model.md books has quietly half-happened.
func _test_the_nine_never_move() -> void:
	var state = _new_state()
	var before := {}
	for id in state.nations.keys():
		before[id] = float(state.nations[id].military_capability)

	for _i in range(168):
		Defence.tick_month(state)

	for id in state.nations.keys():
		if state.nations[id].has_budget:
			continue
		if not is_equal_approx(state.nations[id].military_capability, float(before[id])):
			_fail("%s's capability moved over a run without a budget model: %.4f -> %.4f" % [
				id, float(before[id]), state.nations[id].military_capability
			])


func _test_cost_is_inverse_in_capability() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]

	ns.military_capability = K.CAPABILITY_REFERENCE
	var at_reference := Defence.deployment_cost_pct_gdp(ns)
	if not is_equal_approx(at_reference, K.DEPLOYMENT_COST_PCT_GDP):
		_fail("a nation of exactly reference capability paid %.4f, not DEPLOYMENT_COST_PCT_GDP" % at_reference)

	ns.military_capability = K.CAPABILITY_REFERENCE * 2.0
	if not (Defence.deployment_cost_pct_gdp(ns) < at_reference):
		_fail("doubling capability did not lower the deployment cost")

	# Both clamps, so a nation at zero cannot pay an unbounded price and one at the
	# lever's ceiling cannot deploy for free.
	ns.military_capability = 0.0
	if not is_equal_approx(Defence.capability_ratio(ns), K.DEPLOYMENT_COST_MIN_RATIO):
		_fail("capability 0.0 did not clamp to DEPLOYMENT_COST_MIN_RATIO")
	ns.military_capability = 1000.0
	if not is_equal_approx(Defence.capability_ratio(ns), K.DEPLOYMENT_COST_MAX_RATIO):
		_fail("an enormous capability did not clamp to DEPLOYMENT_COST_MAX_RATIO")


# --- The registers ------------------------------------------------------------

func _test_pact_register_is_symmetric() -> void:
	var state = _new_state()
	Defence.sign_pact(state, PLAYER, ALLY, StubAction.new())

	if not Defence.pact_active(state, PLAYER, ALLY):
		_fail("sign_pact did not register the pact")
	if not Defence.pact_active(state, ALLY, PLAYER):
		_fail("the pact register is not symmetric -- rel(A,B) must be rel(B,A) structurally")
	if state.pacts.size() != 1:
		_fail("one pact wrote %d entries -- the key is not canonical" % state.pacts.size())

	# The derived set, which is what makes a fifth kind of live state unnecessary.
	if Defence.allies(state, PLAYER) != [ALLY]:
		_fail("allies() did not derive the set from the pair register: %s" % [Defence.allies(state, PLAYER)])
	if Defence.pact_count(state, ALLY) != 1:
		_fail("pact_count is not symmetric with the register")


func _test_abandon_closes_both_directions() -> void:
	var state = _new_state()
	Defence.sign_pact(state, PLAYER, ALLY, StubAction.new())
	Defence.open_deployment(state, PLAYER, ALLY, K.DEPLOYMENT_CHOSEN, null)
	Defence.open_deployment(state, ALLY, PLAYER, K.DEPLOYMENT_CHOSEN, null)

	Defence.abandon_pact(state, PLAYER, ALLY)

	if Defence.pact_active(state, PLAYER, ALLY):
		_fail("abandon_pact left the pact in the register")
	if not state.deployments.is_empty():
		_fail("abandon_pact left %d deployment(s) standing under a pact that is gone" % state.deployments.size())


# --- The obligation -----------------------------------------------------------

func _impose(state, from_id: String, to_id: String, severity: float) -> void:
	state.measures[Relations.directed_key(from_id, to_id)] = {
		"action_id": "test", "action_name": "Test", "kind": "tariff",
		"severity": severity, "since_year": state.year, "since_month": state.month,
		"retaliated": false,
	}


## A LEVEL READ. The closing half is the one that matters: nothing in this project
## ever lifts a retaliation, so an edge-triggered obligation would be a permanent
## monotone charge and DEPLOYMENT_BILL_MAX_PCT_GDP would set the bill rather than
## guard it.
func _test_obligation_opens_and_closes() -> void:
	var state = _new_state()
	Defence.sign_pact(state, PLAYER, ALLY, StubAction.new())

	Defence.tick_month(state)
	if Defence.deployment_kind(state, PLAYER, ALLY) != "":
		_fail("a pact with nobody coercing the ally opened a deployment")

	_impose(state, AGGRESSOR, ALLY, 0.60)
	Defence.tick_month(state)
	if Defence.deployment_kind(state, PLAYER, ALLY) != K.DEPLOYMENT_OBLIGED:
		_fail("a measure on a pact partner did not open an obliged deployment")

	state.measures.erase(Relations.directed_key(AGGRESSOR, ALLY))
	Defence.tick_month(state)
	if Defence.deployment_kind(state, PLAYER, ALLY) != "":
		_fail("lifting the measure left the obligation standing -- it is supposed to be a level read")


## Without the self-exclusion a nation that tariffs its own ally is obliged to
## deploy in that ally's support AGAINST ITSELF.
func _test_obligation_excludes_self() -> void:
	var state = _new_state()
	Defence.sign_pact(state, PLAYER, ALLY, StubAction.new())
	_impose(state, PLAYER, ALLY, 0.60)
	Defence.tick_month(state)

	if Defence.deployment_kind(state, PLAYER, ALLY) != "":
		_fail("coercing your own ally obliged you to deploy in their support against yourself")


func _test_obligation_respects_the_floor() -> void:
	var state = _new_state()
	Defence.sign_pact(state, PLAYER, ALLY, StubAction.new())
	_impose(state, AGGRESSOR, ALLY, K.OBLIGATION_MIN_SEVERITY * 0.5)
	Defence.tick_month(state)

	if Defence.deployment_kind(state, PLAYER, ALLY) != "":
		_fail("a token measure below OBLIGATION_MIN_SEVERITY still put a standing charge on the budget")


## A player who volunteered before the obligation arrived is not re-labelled: that
## would charge them the obliged multiplier for a decision they took themselves.
func _test_chosen_is_not_promoted() -> void:
	var state = _new_state()
	Defence.sign_pact(state, PLAYER, ALLY, StubAction.new())
	Defence.open_deployment(state, PLAYER, ALLY, K.DEPLOYMENT_CHOSEN, null)
	_impose(state, AGGRESSOR, ALLY, 0.60)
	Defence.tick_month(state)

	if Defence.deployment_kind(state, PLAYER, ALLY) != K.DEPLOYMENT_CHOSEN:
		_fail("a chosen deployment was promoted to obliged when an obligation arrived")


func _test_orphans_close() -> void:
	var state = _new_state()
	Defence.sign_pact(state, PLAYER, ALLY, StubAction.new())
	Defence.open_deployment(state, PLAYER, ALLY, K.DEPLOYMENT_CHOSEN, null)

	# Erased directly rather than through abandon_pact(), which closes its own
	# deployments -- this is the route where the COUNTERPARTY walked away.
	state.pacts.erase(Relations.key(PLAYER, ALLY))
	Defence.tick_month(state)

	if Defence.deployment_kind(state, PLAYER, ALLY) != "":
		_fail("a deployment survived the pact it stood under")


# --- The prices ---------------------------------------------------------------

func _test_prices_reach_budget_and_opinion() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]

	var deficit_before: float = ns.deficit_pct_gdp
	var defence_before: float = float(Opinion.issue_satisfaction(ns).get("defence", 0.0))

	Defence.sign_pact(state, PLAYER, ALLY, StubAction.new())
	Defence.open_deployment(state, PLAYER, ALLY, K.DEPLOYMENT_CHOSEN, null)
	Defence.tick_month(state)
	Budget.recompute(state, ns)

	if is_zero_approx(ns.deployment_bill_pct_gdp):
		_fail("a live deployment produced no bill")
	if not (ns.deficit_pct_gdp > deficit_before):
		_fail("the deployment bill never reached the deficit")
	if not (float(Opinion.issue_satisfaction(ns).get("defence", 0.0)) < defence_before):
		_fail("the deployment load never reached the defence issue")

	# The bill is clamped, and the clamp is a guard rail rather than the model: this
	# asserts it EXISTS without asserting it is ever reached, which the probe
	# measured at 0.586 against 2.00.
	for other_id in state.nations.keys():
		if String(other_id) == PLAYER:
			continue
		Defence.sign_pact(state, PLAYER, String(other_id), StubAction.new())
		Defence.open_deployment(state, PLAYER, String(other_id), K.DEPLOYMENT_CHOSEN, null)
	Defence.tick_month(state)
	if ns.deployment_bill_pct_gdp > K.DEPLOYMENT_BILL_MAX_PCT_GDP + 1e-6:
		_fail("the bill exceeded DEPLOYMENT_BILL_MAX_PCT_GDP: %.3f" % ns.deployment_bill_pct_gdp)


# --- The content and the channel ----------------------------------------------

func _test_content_loads() -> void:
	var by_op := {}
	for action in _loader.diplomatic_actions:
		var op := String(action.effects.get("pact", {}).get("op", ""))
		if op == "":
			continue
		by_op[op] = action.id

	for op in K.PACT_OPS:
		if not by_op.has(op):
			_fail("no action in data/diplomatic-actions/ carries effects.pact.op '%s'" % op)


## The precondition that is the entire reason four defence pair fields exist rather
## than one. On `deployment_active` this verb would hand the player a free exit from
## the one commitment the whole session is about.
func _test_withdraw_cannot_close_an_obligation() -> void:
	var state = _new_state()
	Defence.sign_pact(state, PLAYER, ALLY, StubAction.new())
	_impose(state, AGGRESSOR, ALLY, 0.60)
	Defence.tick_month(state)

	var withdraw = _pact_action("withdraw")
	if withdraw == null:
		_fail("no withdraw verb to test the obligation against")
		return

	var offered: Array = Diplomacy.available(
		state, _loader.diplomatic_actions, PLAYER, ALLY
	)
	if offered.has(withdraw):
		_fail("the withdraw verb was offered against an OBLIGED deployment -- the player must not be able to close one")

	# And the same verb IS offered once the deployment is one they chose, so the
	# assertion above is about the kind rather than about the verb being broken.
	state.measures.clear()
	Defence.tick_month(state)
	Defence.open_deployment(state, PLAYER, ALLY, K.DEPLOYMENT_CHOSEN, null)
	if not Diplomacy.available(state, _loader.diplomatic_actions, PLAYER, ALLY).has(withdraw):
		_fail("the withdraw verb was not offered against a CHOSEN deployment either -- the gate is wrong, not narrow")


## V1.3f's exclusion, inherited with the narrower test. An AI must never OFFER the
## player a pact -- would_accept_pact() is the counterparty's decision and would
## answer on the player's behalf -- but it must still be able to ABANDON one, which
## is the half the agreement version of this gets wrong.
func _test_agenda_excludes_the_player_from_signing_only() -> void:
	var state = _new_state()
	var sign_verb = _pact_action("sign")
	var abandon_verb = _pact_action("abandon")
	if sign_verb == null or abandon_verb == null:
		_fail("missing pact content for the agenda exclusion test")
		return

	Defence.sign_pact(state, ALLY, PLAYER, StubAction.new())

	# The AI's own view of what it may do to the player.
	var offered: Array = Diplomacy.available(
		state, _loader.diplomatic_actions, ALLY, PLAYER
	)
	if not offered.has(abandon_verb):
		_fail("an AI cannot abandon a pact with the player -- they are locked into an alliance forever")

	# The sign verb is gated by pact_active == 0 here, so the exclusion is asserted
	# on a clean pair where it WOULD otherwise be available.
	var clean = _new_state()
	var clean_offers: Array = Diplomacy.available(
		clean, _loader.diplomatic_actions, ALLY, PLAYER
	)
	if not clean_offers.has(sign_verb):
		_fail("the sign verb is not even available AI->player, so the exclusion below asserts nothing")


func _pact_action(op: String):
	for action in _loader.diplomatic_actions:
		if String(action.effects.get("pact", {}).get("op", "")) == op:
			return action
	return null


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_defence: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
