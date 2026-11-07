extends SceneTree

## V5.3 b, band B3 (docs/design/v5.3-ab.md 4.2): a poll on any measure. Headless.
##
##   - THE PRICE lands on the debt, the fee and nothing else; three tiers, once each.
##   - ANY MEASURE: a law, an ownership bill, a draft, a live process, a tax change.
##   - THE DELAY: nothing printed before its day; read and fixed on it.
##   - THE BAND: the printed range brackets the true support per bloc in 100 % of reads,
##     narrower for the dearer tier, at every level of support.
##
## The band's numbers are written here as literals, never read from the constants.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const MeasurePolls = preload("res://src/sim/measure_polls.gd")
const Address = preload("res://src/sim/address.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Bills = preload("res://src/sim/bills.gd")
const Processes = preload("res://src/sim/processes.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Referendum = preload("res://src/sim/referendum.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")

const PLAYER := "FRA"
const TIERS := {"quick": [0.01, 6.0, 14], "standard": [0.03, 3.0, 28], "deep": [0.06, 1.5, 42]}

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_a_new_game_has_no_poll()
	_check_the_price_and_nothing_else_moves()
	_check_a_poll_is_refused_with_no_effect()
	_check_any_measure_can_be_polled()
	_check_nothing_is_printed_before_its_day()
	_check_a_printed_poll_is_fixed()
	_check_the_range_at_every_level_of_support()
	_check_the_band_on_real_measures()
	_check_each_bloc_is_its_own_fieldwork()
	_check_support_reads_an_address_on_that_measure()
	_check_the_game_month_delivers()
	_check_a_poll_survives_a_save()
	_check_the_address_fade_leaves_the_polls()

	if _failures.is_empty():
		print("test_measure_polls: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


func _new_state(nation_id := PLAYER):
	var state = GameState.new_game(_loader, nation_id)
	state.year = 2026
	state.month = 3
	state.day = 10
	return state


func _open_bill(state):
	for law in Legislature.available(state.player(), _loader.laws):
		if not law.constitutional:
			return law
	_fail("no open ordinary bill")
	return null


func _polled(ns, key: String, tier: String) -> Dictionary:
	return ((ns.measure_opinion.get("polls", {}) as Dictionary).get(key, {}) as Dictionary).get(tier, {})


func _check_a_new_game_has_no_poll() -> void:
	var state = _new_state()
	if not state.player().measure_opinion.is_empty():
		_fail("a new game has a poll: %s" % [state.player().measure_opinion])
	if not MeasurePolls.deliver_due(state, 31).is_empty():
		_fail("a new game delivered a poll")


## A twin of the same game: the whole nation dictionary differs in the debt and the register,
## through the commission and through the delivery. The fee is the debt's move, to the euro.
func _check_the_price_and_nothing_else_moves() -> void:
	for tier in TIERS:
		var bought = _new_state()
		var twin = _new_state()
		var law = _open_bill(bought)
		var before := float(bought.player().debt_eur_bn)
		var result: Dictionary = MeasurePolls.commission(bought, _loader, law.id, tier)
		if not bool(result.get("ok", false)) or bool(result.get("refused", true)):
			_fail("%s was refused: %s" % [tier, result])
			continue
		if float(result["cost_eur_bn"]) != float(TIERS[tier][0]):
			_fail("%s costs %.5f" % [tier, result["cost_eur_bn"]])
		if not is_equal_approx(float(bought.player().debt_eur_bn) - before, float(TIERS[tier][0])):
			_fail("%s moved the debt by %.5f" % [tier, float(bought.player().debt_eur_bn) - before])
		_only_the_debt_and_register_differ(bought.player(), twin.player(), "%s, commissioned" % tier)
		bought.day = 28
		MeasurePolls.deliver_due(bought, 31)
		bought.month = 6
		MeasurePolls.deliver_due(bought, 1)
		_only_the_debt_and_register_differ(bought.player(), twin.player(), "%s, delivered" % tier)


func _only_the_debt_and_register_differ(a, b, label: String) -> void:
	var left: Dictionary = a.to_dict()
	var right: Dictionary = b.to_dict()
	for key in ["debt_eur_bn", "measure_opinion"]:
		left.erase(key)
		right.erase(key)
	if str(left) != str(right):
		for key in left:
			if str(left[key]) != str(right.get(key)):
				_fail("%s also moved %s" % [label, key])


func _check_a_poll_is_refused_with_no_effect() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _open_bill(state)
	var debt := float(ns.debt_eur_bn)
	for bad in [[law.id, "no_such_tier"], ["", "quick"], ["no_such_measure", "quick"], ["tax:vat:sideways", "quick"], ["tax:no_such_tax:up", "quick"]]:
		var result: Dictionary = MeasurePolls.commission(state, _loader, bad[0], bad[1])
		if bool(result.get("ok", true)) or not bool(result.get("refused", false)) or String(result.get("refusal", "")) == "" or float(result.get("cost_eur_bn", 1.0)) != 0.0:
			_fail("%s took: %s" % [bad, result])
	if float(ns.debt_eur_bn) != debt or not ns.measure_opinion.is_empty():
		_fail("a refused poll left a mark: %s" % [ns.measure_opinion])
	if not bool(MeasurePolls.commission(state, _loader, law.id, "quick")["ok"]):
		_fail("a first poll was refused")
	var charged := float(ns.debt_eur_bn)
	var again: Dictionary = MeasurePolls.commission(state, _loader, law.id, "quick")
	if bool(again["ok"]) or float(ns.debt_eur_bn) != charged:
		_fail("a second commission of one tier was a reroll: %s" % [again])
	if not bool(MeasurePolls.commission(state, _loader, law.id, "deep")["ok"]):
		_fail("another tier on the same measure was refused")


## One of each key kind, and a verb content gives no position to is refused.
func _check_any_measure_can_be_polled() -> void:
	var state = _new_state()
	var ns = state.player()
	var measures: Array[String] = [_open_bill(state).id, "tax:vat:up", "tax:income:down"]
	var ownership: Array = Bills.open(state, ns, _loader).filter(func(bill) -> bool: return String(bill.id).begins_with(Bills.OWNERSHIP_PREFIX))
	if ownership.is_empty():
		_fail("no ownership bill open")
	else:
		measures.append(String(ownership[0].id))
	ns.draft_bills["draft_probe"] = {"name": "probe", "position": {"economic": 0.3, "social": -0.2}, "months_left": 3}
	measures.append("draft_probe")
	var action = _action_with_bill()
	ns.processes.append({"id": "process_probe", "action_id": String(action.id), "company_id": "firm", "status": Processes.OPEN})
	measures.append("process_probe")
	for key in measures:
		var read: Dictionary = MeasurePolls.support(ns, _loader, key)
		if read.size() != OpinionK.BLOC_KEYS.size():
			_fail("%s reads no support: %s" % [key, read])
		if not bool(MeasurePolls.commission(state, _loader, key, "quick").get("ok", false)):
			_fail("%s could not be polled" % key)
	# A tax up and the same tax down are opposite measures: the business bloc says so.
	if not Referendum.bloc_yes(ns, "business", MeasurePolls.position_of(ns, _loader, "tax:vat:down")) > Referendum.bloc_yes(ns, "business", MeasurePolls.position_of(ns, _loader, "tax:vat:up")):
		_fail("business likes a tax rise as a tax cut")
	# A process that has ended is no longer a measure.
	ns.processes.append({"id": "process_over", "action_id": String(action.id), "company_id": "firm", "status": "settled"})
	if not MeasurePolls.position_of(ns, _loader, "process_over").is_empty():
		_fail("a closed process took a poll")
	var stake = _action_without_bill()
	ns.processes.append({"id": "process_stake", "action_id": String(stake.id), "company_id": "firm", "status": Processes.OPEN})
	if bool(MeasurePolls.commission(state, _loader, "process_stake", "quick").get("ok", true)):
		_fail("a verb content gives no position took a poll")


func _action_with_bill():
	for action in _loader.company_actions:
		if not action.bill.is_empty():
			return action
	_fail("no company action with a bill")
	return null


func _action_without_bill():
	for action in _loader.company_actions:
		if action.bill.is_empty():
			return action
	_fail("no company action without a bill")
	return null


## Two, four, six weeks from the purchase, to the day, across a month's end.
func _check_nothing_is_printed_before_its_day() -> void:
	for tier in TIERS:
		var state = _new_state()
		var ns = state.player()
		var law = _open_bill(state)
		MeasurePolls.commission(state, _loader, law.id, tier)
		if not MeasurePolls.result(ns, law.id, tier).is_empty():
			_fail("%s printed on the day it was bought" % tier)
		var when := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 3, "day": 10, "hour": 0, "minute": 0, "second": 0})) + 86400 * int(TIERS[tier][2]))
		var eve := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_datetime_dict(when)) - 86400)
		state.year = int(eve["year"])
		state.month = int(eve["month"])
		if not MeasurePolls.deliver_due(state, int(eve["day"])).is_empty():
			_fail("%s printed the day before %s" % [tier, when])
		state.year = int(when["year"])
		state.month = int(when["month"])
		var arrived: Array = MeasurePolls.deliver_due(state, int(when["day"]))
		if arrived.size() != 1 or String(arrived[0]["key"]) != law.id or String(arrived[0]["tier"]) != tier or (arrived[0]["ranges"] as Dictionary).size() != OpinionK.BLOC_KEYS.size():
			_fail("%s did not arrive on its day: %s" % [tier, arrived])
		if not MeasurePolls.deliver_due(state, int(when["day"])).is_empty():
			_fail("%s arrived twice" % tier)
		if str(MeasurePolls.result(ns, law.id, tier)) != str(arrived[0]["ranges"]):
			_fail("%s reads other than it arrived" % tier)


func _check_a_printed_poll_is_fixed() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _open_bill(state)
	MeasurePolls.commission(state, _loader, law.id, "quick")
	state.month = 4
	MeasurePolls.deliver_due(state, 1)
	var printed: String = str(MeasurePolls.result(ns, law.id, "quick"))
	if printed == "{  }":
		_fail("nothing printed")
	for bloc in OpinionK.BLOC_KEYS:
		ns.bloc_approval[bloc] = 90.0
	state.month = 9
	MeasurePolls.deliver_due(state, 1)
	if str(MeasurePolls.result(ns, law.id, "quick")) != printed:
		_fail("a printed poll moved with the country")
	var other = _new_state()
	var other_law = _open_bill(other)
	for bloc in OpinionK.BLOC_KEYS:
		other.player().bloc_approval[bloc] = 90.0
	MeasurePolls.commission(other, _loader, other_law.id, "quick")
	other.month = 4
	MeasurePolls.deliver_due(other, 1)
	if str(MeasurePolls.result(other.player(), other_law.id, "quick")) == printed:
		_fail("the fieldwork did not read the country: a poll bought in a better month prints the same")


## The range by hand, at the edges and the noise's two ends: always the truth inside, always
## the full width, inside 0 to 100.
func _check_the_range_at_every_level_of_support() -> void:
	for margin in [6.0, 3.0, 1.5]:
		for truth in [0.0, 0.5, 1.0, 4.0, 50.0, 96.0, 99.5, 100.0]:
			for u in [0.0, 0.25, 0.5, 0.999]:
				var r: Array = MeasurePolls.printed_range(truth, margin, u)
				if float(r[0]) > truth or float(r[1]) < truth:
					_fail("truth %.1f outside %s at margin %.1f, draw %.3f" % [truth, r, margin, u])
				if float(r[0]) < 0.0 or float(r[1]) > 100.0:
					_fail("%s leaves 0 to 100" % [r])
				var width: float = float(r[1]) - float(r[0])
				if width < 2.0 * margin - 0.001 or width > 2.0 * margin + 0.2 + 0.001:
					_fail("truth %.1f, margin %.1f, draw %.3f: width %.2f" % [truth, margin, u, width])


## THE BAND, on real measures of all four playable nations, three game seeds, the game's own
## support at delivery: every bloc's truth inside its range, and each dearer tier narrower.
func _check_the_band_on_real_measures() -> void:
	var reads := 0
	for nation_id in ["FRA", "DEU", "GBR", "POL"]:
		for draw in 3:
			var state = _new_state(nation_id)
			var ns = state.player()
			ns.draw_seed = draw
			var keys: Array[String] = ["tax:vat:up", "tax:income:down"]
			var count := 0
			for law in Legislature.available(ns, _loader.laws):
				if not law.constitutional and count < 12:
					keys.append(String(law.id))
					count += 1
			for key in keys:
				for tier in TIERS:
					MeasurePolls.commission(state, _loader, key, tier)
			state.year = 2026
			state.month = 8
			MeasurePolls.deliver_due(state, 1)
			for key in keys:
				var truth: Dictionary = MeasurePolls.support(ns, _loader, key)
				var widths := []
				for tier in TIERS:
					var ranges: Dictionary = MeasurePolls.result(ns, key, tier)
					if ranges.is_empty():
						_fail("%s %s printed nothing" % [key, tier])
						continue
					var widest := 0.0
					for bloc in truth:
						reads += 1
						if float(ranges[bloc][0]) > float(truth[bloc]) or float(ranges[bloc][1]) < float(truth[bloc]):
							_fail("%s %s %s: truth %.2f outside %s" % [nation_id, key, bloc, truth[bloc], ranges[bloc]])
						widest = maxf(widest, float(ranges[bloc][1]) - float(ranges[bloc][0]))
					widths.append(widest)
				if widths.size() == 3 and not (float(widths[0]) > float(widths[1]) and float(widths[1]) > float(widths[2])):
					_fail("%s %s: widths %s are not narrower for the dearer tier" % [nation_id, key, widths])
	if reads < 1000:
		_fail("the band read only %d" % reads)


## Each bloc's error is its own, and another game's seed draws another: one shared draw
## would let a player read every bloc's truth off the first one they could check.
func _check_each_bloc_is_its_own_fieldwork() -> void:
	var offsets := {}
	var printed := []
	for draw in 2:
		var state = _new_state()
		var ns = state.player()
		ns.draw_seed = draw
		MeasurePolls.commission(state, _loader, "tax:vat:up", "quick")
		state.month = 4
		MeasurePolls.deliver_due(state, 1)
		var truth: Dictionary = MeasurePolls.support(ns, _loader, "tax:vat:up")
		var ranges: Dictionary = MeasurePolls.result(ns, "tax:vat:up", "quick")
		printed.append(str(ranges))
		if draw == 0:
			for bloc in truth:
				offsets[snappedf((float(ranges[bloc][0]) + float(ranges[bloc][1])) / 2.0 - float(truth[bloc]), 0.1)] = true
	if offsets.size() < 3:
		_fail("the blocs share a draw: offsets %s" % [offsets.keys()])
	if printed[0] == printed[1]:
		_fail("another game's seed printed the same poll")


## An address on a measure is in its truth, on that measure, within 0 to 100.
func _check_support_reads_an_address_on_that_measure() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _open_bill(state)
	var other: String = "tax:vat:up"
	var before: Dictionary = MeasurePolls.support(ns, _loader, law.id)
	var before_other: String = str(MeasurePolls.support(ns, _loader, other))
	var shifts: Dictionary = Address.give(state, _loader, law.id)["shifts"]
	var after: Dictionary = MeasurePolls.support(ns, _loader, law.id)
	for bloc in shifts:
		var want := clampf(float(before[bloc]) + float(shifts[bloc]), 0.0, 100.0)
		if not is_equal_approx(float(after[bloc]), want):
			_fail("%s reads %.3f after the address, want %.3f" % [bloc, after[bloc], want])
	if str(MeasurePolls.support(ns, _loader, other)) != before_other:
		_fail("an address on one measure moved another")
	for bloc in OpinionK.BLOC_KEYS:
		ns.measure_opinion["measures"][law.id]["shifts"][bloc] = 500.0
	if float(MeasurePolls.support(ns, _loader, law.id)[OpinionK.BLOC_KEYS[0]]) != 100.0:
		_fail("support past 100")


## The month's close delivers what falls due inside the month, whatever day the clock reads.
func _check_the_game_month_delivers() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _open_bill(state)
	state.day = 1
	MeasurePolls.commission(state, _loader, law.id, "quick")
	MeasurePolls.commission(state, _loader, law.id, "deep")
	if not WorldMonth.STEPS.has("Polls"):
		_fail("no Polls step in the month")
		return
	var report: Dictionary = WorldMonth.tick_month(state, _loader)
	var arrived: Array = report.get("polls", [])
	if arrived.size() != 1 or String(arrived[0]["tier"]) != "quick":
		_fail("the close delivered %s" % [arrived])
	if not MeasurePolls.result(ns, law.id, "deep").is_empty():
		_fail("a six-week poll printed at the first close")


func _check_a_poll_survives_a_save() -> void:
	var state = _new_state()
	var law = _open_bill(state)
	MeasurePolls.commission(state, _loader, law.id, "quick")
	MeasurePolls.commission(state, _loader, law.id, "deep")
	state.month = 4
	MeasurePolls.deliver_due(state, 1)
	var back = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	if str(MeasurePolls.result(back.player(), law.id, "quick")) != str(JSON.parse_string(JSON.stringify(MeasurePolls.result(state.player(), law.id, "quick")))):
		_fail("a printed poll did not survive a save")
	if not MeasurePolls.result(back.player(), law.id, "deep").is_empty():
		_fail("a pending poll printed across a save")
	back.month = 5
	var arrived: Array = MeasurePolls.deliver_due(back, 1)
	if arrived.size() != 1 or String(arrived[0]["tier"]) != "deep":
		_fail("a pending poll did not arrive after a save: %s" % [arrived])
	if bool(MeasurePolls.commission(back, _loader, law.id, "quick").get("ok", true)):
		_fail("a save forgot a purchase: a reroll")


## The two share a field, and the fade empties its own keys only.
func _check_the_address_fade_leaves_the_polls() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _open_bill(state)
	Address.give(state, _loader, law.id)
	MeasurePolls.commission(state, _loader, law.id, "quick")
	for i in 8:
		Address.tick_month(state)
		state.month = 3 + i + 1
	if _polled(ns, law.id, "quick").is_empty():
		_fail("the fade wiped a poll: %s" % [ns.measure_opinion])
	if ns.measure_opinion.has("measures") or ns.measure_opinion.has("given"):
		_fail("the fade left its own keys behind: %s" % [ns.measure_opinion])
