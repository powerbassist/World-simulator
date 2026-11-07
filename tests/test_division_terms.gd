extends SceneTree

## V5.3 b, band B4 (docs/design/v5.3-ab.md 4.4) with the parent's two rulings: a division
## reads a bill's size, and a person's pledge. Headless.
##
##   - NO MAGNITUDE, NO PLEDGE, SCALE 1: the same division, byte for byte.
##   - THE GRADE multiplies the budget effects and the magnitude on a copy, and below 1 the
##     law's other effects too, and travels the real road: tabled, forecast, divided, applied,
##     held, saved.
##   - THE SIZE TERM moves support away from zero in the direction the party already
##     leans, and charges a party that weighs the deficit for the cost.
##   - THE PLEDGE moves seats on one bill, the forecast sees it, and the vote judges it
##     into a mark the deal can read.
##   - THE PEEL takes seats off a whipped yes line as a bill grows, by discipline, and a
##     pledged seat is never counted as peeled too.
##
## The band's numbers are written here as literals, never read from the constants.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Division = preload("res://src/sim/division.gd")
const DivisionTerms = preload("res://src/sim/division_terms.gd")
const LawMagnitude = preload("res://src/core/law_magnitude.gd")
const PoliticsLoader = preload("res://src/core/loaders/politics_loader.gd")
const Levers = preload("res://src/sim/levers.gd")
const Chambers = preload("res://src/sim/chambers.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")
const President = preload("res://src/sim/president.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_no_row_ships_a_magnitude_yet()
	_check_nothing_moves_at_scale_one()
	_check_the_scale_reads_budget_effects_only()
	_check_a_bill_graded_down_brings_less_of_everything()
	_check_a_bill_graded_down_on_the_real_road()
	_check_the_loader_reads_a_magnitude()
	_check_a_row_carries_its_magnitude_through_the_loader()
	_check_the_size_term_moves_away_from_zero()
	_check_the_deficit_is_charged_to_the_right()
	_check_the_grade_on_the_real_road()
	_check_a_grade_is_refused_where_it_means_nothing()
	_check_a_forced_bill_keeps_its_grade()
	_check_a_hold_writes_its_grade()
	_check_a_held_bill_keeps_its_grade()
	_check_a_held_grade_survives_a_save()
	_check_size_is_not_a_whips_strain()
	_check_a_grade_survives_a_save()
	_check_a_pledge_moves_seats_on_one_bill()
	_check_one_person_pledges_a_bill_once()
	_check_a_pledge_takes_no_before_abstain_and_caps()
	_check_only_a_whipped_yes_line_peels()
	_check_pledged_and_peeled_seats_do_not_double_count()
	_check_the_share_that_peels()
	_check_the_peel_on_a_real_division()
	_check_the_vote_judges_a_pledge()
	_check_a_pledge_is_broken_with_no_seat()
	_check_a_pledge_names_the_party_the_person_is_in()
	_check_the_verdict_is_this_bill_and_the_latest()
	_check_a_pledge_with_no_vote_is_void_at_no_price()
	_check_a_pledge_survives_a_save()

	if _failures.is_empty():
		print("test_division_terms: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _new_state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 3
	return state


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _parties() -> Array:
	return _loader.parties[PLAYER]


func _term(ns, party, law) -> float:
	return DivisionTerms.of(Legislature.spatial_support(ns, party, law), party, law)


## A law with a spending effect and an ordinary road, graded by hand: no row is tagged yet.
func _graded(value := 40.0, reference := 40.0):
	for law in _loader.laws:
		if law.effects.has("spending_pct_gdp") and not law.constitutional and law.majority == "simple":
			var copy = LawMagnitude.copy(law)
			copy.magnitude = {"value": value, "reference": reference, "unit": "lycees"}
			return copy
	_fail("no ordinary law with a spending effect")
	return null


func _party_by_slot(slot: String):
	for party in _parties():
		if party.ideology_slot == slot:
			return party
	_fail("no %s party in %s" % [slot, PLAYER])
	return null


func _check_no_row_ships_a_magnitude_yet() -> void:
	for law in _loader.laws:
		if not law.magnitude.is_empty():
			# Content tags rows after this PR: this pin then becomes the rows' own band.
			_fail("%s ships a magnitude: the balance prediction assumed none" % law.id)


func _check_nothing_moves_at_scale_one() -> void:
	var ns = _new_state().player()
	var plain = _graded()
	plain.magnitude = {}
	var at_reference = _graded()
	if LawMagnitude.scaled(plain, 2.0) != plain:
		_fail("a row with no size took a saved grade")
	if LawMagnitude.scaled(at_reference, 1.0) != at_reference:
		_fail("scale 1 made a copy: an ungraded road should not pay for one")
	for party in _parties():
		if Legislature.support(ns, party, plain) != Legislature.support(ns, party, at_reference):
			_fail("%s reads a law at its reference size differently from one with no magnitude" % party.id)
	if str(Legislature.resolve_vote(ns, _parties(), plain)) != str(Legislature.resolve_vote(ns, _parties(), at_reference)):
		_fail("a division moved at scale 1")
	if _term(ns, _parties()[0], plain) != 0.0:
		_fail("a law with no magnitude has a term")


func _check_the_scale_reads_budget_effects_only() -> void:
	var law = _graded()
	var before: Dictionary = law.effects.duplicate(true)
	var big = LawMagnitude.scaled(law, 10.0)
	if big == law or str(law.effects) != str(before) or float(law.magnitude["value"]) != 40.0:
		_fail("scaling touched the original law: %s" % [law.effects])
	if float(big.magnitude["value"]) != 400.0 or float(big.magnitude["reference"]) != 40.0:
		_fail("the magnitude did not scale: %s" % [big.magnitude])
	for line in before["spending_pct_gdp"]:
		if not is_equal_approx(float(big.effects["spending_pct_gdp"][line]), 10.0 * float(before["spending_pct_gdp"][line])):
			_fail("spending line %s did not scale" % line)
	if str(big.effects.get("bloc_offset", {})) != str(before.get("bloc_offset", {})):
		_fail("the ruling keeps other effects unscaled, and bloc_offset moved")
	var t = LawMagnitude.copy(law)
	t.effects = {"tax_rates_pct": {"income": 5.0}, "other_revenue_pct_gdp": 0.5, "bloc_offset": {"business": -0.1}}
	var d = LawMagnitude.scaled(t, 2.0)
	if float(d.effects["tax_rates_pct"]["income"]) != 10.0 or float(d.effects["other_revenue_pct_gdp"]) != 1.0 \
			or float(d.effects["bloc_offset"]["business"]) != -0.1:
		_fail("a tax rate and other revenue scale, a bloc offset does not: %s" % [d.effects])


## The parent's ruling, correcting the first: a tenth of the cost must not keep the whole of
## the rest, or grading down is a dominant line. Linear below 1; a law's institutional terms
## are set values, not quantities, and stay.
func _check_a_bill_graded_down_brings_less_of_everything() -> void:
	var law = _graded()
	law.effects = {"spending_pct_gdp": {"health": 0.5}, "tax_rates_pct": {"income": 2.0}, "other_revenue_pct_gdp": 0.4,
		"structural_unemployment_pct": -0.2, "potential_growth_pct": 0.1,
		"bloc_offset": {"workers": 0.3, "business": -0.2}, "society": {"corruption": -0.04},
		"company": {"sector": "energy", "burden": 0.06}, "institutional": {"election_threshold_pct": 5.0}}
	var before: String = str(law.effects)
	var half = LawMagnitude.scaled(law, 0.5)
	var want := {"structural_unemployment_pct": -0.1, "potential_growth_pct": 0.05, "other_revenue_pct_gdp": 0.2}
	for key in want:
		if not is_equal_approx(float(half.effects[key]), float(want[key])):
			_fail("%s at half a bill reads %.4f" % [key, half.effects[key]])
	if not is_equal_approx(float(half.effects["bloc_offset"]["workers"]), 0.15) or not is_equal_approx(float(half.effects["bloc_offset"]["business"]), -0.1):
		_fail("a bloc's offset at half a bill: %s" % [half.effects["bloc_offset"]])
	if not is_equal_approx(float(half.effects["society"]["corruption"]), -0.02):
		_fail("society at half a bill: %s" % [half.effects["society"]])
	if not is_equal_approx(float(half.effects["company"]["burden"]), 0.03) or String(half.effects["company"]["sector"]) != "energy":
		_fail("a company's burden at half a bill: %s" % [half.effects["company"]])
	if not is_equal_approx(float(half.effects["spending_pct_gdp"]["health"]), 0.25) or not is_equal_approx(float(half.effects["tax_rates_pct"]["income"]), 1.0):
		_fail("the budget at half a bill: %s" % [half.effects])
	if float(half.effects["institutional"]["election_threshold_pct"]) != 5.0:
		_fail("a set value scaled: %s" % [half.effects["institutional"]])
	if str(law.effects) != before:
		_fail("grading down touched the original law: %s" % [law.effects])
	var big = LawMagnitude.scaled(law, 10.0)
	if float(big.effects["potential_growth_pct"]) != 0.1 or float(big.effects["bloc_offset"]["workers"]) != 0.3 \
			or float(big.effects["society"]["corruption"]) != -0.04 or float(big.effects["company"]["burden"]) != 0.06:
		_fail("a bigger bill multiplied its other effects: %s" % [big.effects])
	if LawMagnitude.scaled(law, 1.0) != law:
		_fail("scale 1 made a copy")


## Twins of one game, at reference and at half, on what the game realised.
func _check_a_bill_graded_down_on_the_real_road() -> void:
	var one = _new_state()
	var half = _new_state()
	var law = _open_graded_passing(one)
	if law == null:
		return
	if not (law.effects.get("bloc_offset", {}) as Dictionary).size() > 0:
		_fail("premise: %s has no bloc offset" % law.id)
	Legislature.propose(one, _loader, law)
	Legislature.propose(half, _loader, law, false, false, 0.5)
	if not bool(Division.divide(one, _loader).get("passed", false)) or not bool(Division.divide(half, _loader).get("passed", false)):
		_fail("premise: %s did not pass at both grades" % law.id)
	else:
		var offsets_one: Dictionary = (one.player().law_ledger.get(law.id, {}) as Dictionary).get("channels", {}).get("bloc_offset", {})
		var offsets_half: Dictionary = (half.player().law_ledger.get(law.id, {}) as Dictionary).get("channels", {}).get("bloc_offset", {})
		if offsets_one.is_empty():
			_fail("the ledger read no bloc offset on %s" % law.id)
		for bloc in offsets_one:
			if not is_equal_approx(float(offsets_half.get(bloc, 0.0)), 0.5 * float(offsets_one[bloc])):
				_fail("%s realised %.4f at half a bill, %.4f at one" % [bloc, offsets_half.get(bloc, 0.0), offsets_one[bloc]])
	law.magnitude = {}


func _check_the_loader_reads_a_magnitude() -> void:
	var errors: Array[String] = []
	var good := LawMagnitude.parse({"id": "x", "magnitude": {"value": 40, "reference": 40, "unit": "lycees"}}, "x", false, "t.json", errors)
	if not errors.is_empty() or float(good.get("value", 0.0)) != 40.0:
		_fail("a good magnitude was refused: %s" % [errors])
	if not LawMagnitude.parse({"id": "x"}, "x", false, "t.json", errors).is_empty() or not errors.is_empty():
		_fail("an absent magnitude does not read empty")
	for bad in [{"value": 0, "reference": 40, "unit": "u"}, {"value": 40, "reference": -1, "unit": "u"}, {"value": 40, "unit": "u"},
			{"value": 40, "reference": 40}, {"value": "40", "reference": 40, "unit": "u"}, {"value": 40, "reference": 40, "unit": "u", "extra": 1}]:
		var e: Array[String] = []
		LawMagnitude.parse({"id": "x", "magnitude": bad}, "x", false, "t.json", e)
		if e.is_empty():
			_fail("the loader took magnitude %s" % [bad])
	var c: Array[String] = []
	LawMagnitude.parse({"id": "x", "magnitude": {"value": 40, "reference": 40, "unit": "u"}}, "x", true, "t.json", c)
	if c.is_empty():
		_fail("a constitutional law took a size: it has no road for a grade")


## The wire, not the parser: a row on disk reaches a Law with its size, through the function
## the game loads with, and a bad size is the loader's error.
func _check_a_row_carries_its_magnitude_through_the_loader() -> void:
	var dir := "user://test_division_terms_laws"
	DirAccess.make_dir_recursive_absolute(dir)
	var row: Dictionary = {"id": "sized_bill", "name": "Sized bill", "theme": "social", "summary": "A row for this test.",
		"position": {"economic": 0.0, "social": 0.0}, "majority": "simple", "cooldown_months": 12, "once": false,
		"effects": {"bloc_offset": {"workers": 0.01}}, "magnitude": {"value": 40, "reference": 40, "unit": "lycees"}}
	var file := FileAccess.open(dir.path_join("laws.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"laws": [row]}))
	file.close()
	var fresh = DataLoader.new()
	PoliticsLoader.load_laws(fresh, dir)
	if not fresh.errors.is_empty():
		_fail("the test's row did not load: %s" % [fresh.errors])
	if fresh.laws.size() != 1 or float(fresh.laws[0].magnitude.get("value", 0.0)) != 40.0 or String(fresh.laws[0].magnitude.get("unit", "")) != "lycees":
		_fail("the loader dropped a row's magnitude: %s" % [fresh.laws])
	row["magnitude"] = {"value": 0, "reference": 40, "unit": "lycees"}
	file = FileAccess.open(dir.path_join("laws.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"laws": [row]}))
	file.close()
	var bad = DataLoader.new()
	PoliticsLoader.load_laws(bad, dir)
	if bad.errors.is_empty():
		_fail("the loader took a magnitude of nothing")
	DirAccess.remove_absolute(dir.path_join("laws.json"))
	DirAccess.remove_absolute(dir)


## The party's own lean, read with the spatial term alone so the whip does not hide it.
func _check_the_size_term_moves_away_from_zero() -> void:
	var ns = _new_state().player()
	var law = _graded()
	var big = LawMagnitude.scaled(law, 10.0)
	big.effects = {}  # size alone: the cost term is the next check's
	var small = LawMagnitude.scaled(law, 0.1)
	small.effects = {}
	var likes := 0
	var dislikes := 0
	for party in _parties():
		var lean: float = Legislature.spatial_support(ns, party, law)
		var up: float = _term(ns, party, big)
		var down: float = _term(ns, party, small)
		if lean > 0.0:
			likes += 1
		elif lean < 0.0:
			dislikes += 1
		if signf(up) != signf(lean) or up == 0.0:
			_fail("%s leans %.3f and ten times the size moves it %.3f" % [party.id, lean, up])
		if signf(down) == signf(lean) and down != 0.0:
			_fail("%s leans %.3f and a tenth of the size moves it %.3f, away from zero" % [party.id, lean, down])
		if absf(down) > absf(lean) + 0.000001:
			_fail("%s leans %.3f and a tenth of the size crossed zero: %.3f" % [party.id, lean, down])
	if likes == 0 or dislikes == 0:
		_fail("the law read %d likers and %d dislikers: the check proved nothing" % [likes, dislikes])


## The cost charged grows with the bn, to a party that weighs the deficit: a right-of-centre
## party pays, a left one does not, and a revenue-raising bill charges nobody.
func _check_the_deficit_is_charged_to_the_right() -> void:
	var ns = _new_state().player()
	var law = _graded()
	var nocost = LawMagnitude.copy(law)
	nocost.effects = {}
	var free = LawMagnitude.scaled(nocost, 10.0)
	var dear = LawMagnitude.scaled(law, 10.0)
	var dearer = LawMagnitude.scaled(_cost_of(law, 2.0), 10.0)
	var right = _party_by_slot("centre_right")
	var left = _party_by_slot("left_populist")
	if not _term(ns, right, dear) < _term(ns, right, free):
		_fail("a right party pays nothing for the bn: %.3f against %.3f" % [_term(ns, right, dear), _term(ns, right, free)])
	if not _term(ns, right, dearer) < _term(ns, right, dear):
		_fail("twice the bn did not cost a right party more")
	if _term(ns, left, dear) != _term(ns, left, free):
		_fail("a left party pays for the bn: it does not weigh the deficit")
	var raises = LawMagnitude.copy(law)
	raises.effects = {"other_revenue_pct_gdp": 0.5}
	if _term(ns, right, LawMagnitude.scaled(raises, 10.0)) != _term(ns, right, free):
		_fail("a bill that raises revenue charged the deficit")
	var paid_for = LawMagnitude.copy(law)
	paid_for.effects = {"spending_pct_gdp": {"health": 0.5}, "other_revenue_pct_gdp": 0.5}
	if _term(ns, right, LawMagnitude.scaled(paid_for, 10.0)) != _term(ns, right, free):
		_fail("a bill its own revenue pays for charged the deficit")


## The members read a bill's size as the line does, so only the whip is strain: an
## opposition party has no whip on it and does not rebel at any size.
func _check_size_is_not_a_whips_strain() -> void:
	var ns = _new_state().player()
	var read := 0
	for law in _loader.laws:
		if law.constitutional or not law.effects.has("spending_pct_gdp"):
			continue
		var graded = LawMagnitude.copy(law)
		graded.magnitude = {"value": 1.0, "reference": 1.0, "unit": "u"}
		var rebels: Dictionary = Legislature.resolve_vote(ns, _parties(), LawMagnitude.scaled(graded, 10.0))["party_rebels"]
		for party in _parties():
			if not ns.coalition_party_ids.has(party.id):
				read += 1
				if rebels.has(party.id):
					_fail("%s is in opposition and %d of its seats rebel on %s at ten times" % [party.id, rebels[party.id], law.id])
	if read == 0:
		_fail("no opposition party read")


func _cost_of(law, times: float):
	var out = LawMagnitude.copy(law)
	for line in out.effects["spending_pct_gdp"]:
		out.effects["spending_pct_gdp"][line] = float(out.effects["spending_pct_gdp"][line]) * times
	return out


## A law of the bills open now, graded on the loader's own object for the real road.
func _open_graded(state):
	for law in Legislature.available(state.player(), _loader.laws):
		if law.effects.has("spending_pct_gdp") and not law.constitutional:
			law.magnitude = {"value": 40.0, "reference": 40.0, "unit": "lycees"}
			return law
	_fail("no open law with a spending effect")
	return null


## Tabled at ten times, the forecast and the division read ten times, and what lands is
## ten times the budget effect: twins of one game, one proposed at each scale, on a law
## that passes at both, read from the ledger of what was realised.
func _check_the_grade_on_the_real_road() -> void:
	var one = _new_state()
	var ten = _new_state()
	var law = _open_graded_passing(one)
	if law == null:
		return
	var tabled_one: Dictionary = Legislature.propose(one, _loader, law)
	Legislature.propose(ten, _loader, law, false, false, 10.0)
	if tabled_one.has("scale") or one.player().tabled_bill.has("scale"):
		_fail("an ungraded tabling wrote a scale: %s" % [tabled_one])
	if float(ten.player().tabled_bill.get("scale", 0.0)) != 10.0:
		_fail("the tabling did not keep the grade: %s" % [ten.player().tabled_bill])
	var forecast: Dictionary = Division.forecast(ten, ten.player(), _loader)
	var want: Dictionary = Legislature.resolve_vote(ten.player(), _parties(), LawMagnitude.scaled(law, 10.0))
	if str(forecast) != str(want):
		_fail("the forecast did not read the grade: %s against %s" % [forecast.get("party_support"), want.get("party_support")])
	var ones: Dictionary = Division.divide(one, _loader)
	var tens: Dictionary = Division.divide(ten, _loader)
	if not bool(ones.get("passed", false)) or not bool(tens.get("passed", false)):
		_fail("premise: %s did not pass at both scales: %s, %s" % [law.id, ones, tens])
	else:
		var line_one := _ledger_spending(one.player(), law)
		var line_ten := _ledger_spending(ten.player(), law)
		if line_one <= 0.0 or not is_equal_approx(line_ten, 10.0 * line_one):
			_fail("%s realised %.4f at ten times and %.4f at one: %s" % [law.id, line_ten, line_one, ten.player().law_ledger.get(law.id, {})])
		if float(law.effects["spending_pct_gdp"].values()[0]) != float(_loader_effect(law)):
			_fail("the road scaled the loader's own row")
	law.magnitude = {}


func _loader_effect(law) -> float:
	for row in _loader.laws:
		if row.id == law.id:
			return float(row.effects["spending_pct_gdp"].values()[0])
	return NAN


## The first open law with a spending effect that passes at reference size and at ten times.
func _open_graded_passing(state):
	var ns = state.player()
	for law in Legislature.available(ns, _loader.laws):
		if law.effects.has("spending_pct_gdp") and not law.constitutional and float(law.effects["spending_pct_gdp"].values()[0]) > 0.0:
			law.magnitude = {"value": 40.0, "reference": 40.0, "unit": "lycees"}
			if bool(Legislature.resolve_vote(ns, _parties(), law)["passed"]) and bool(Legislature.resolve_vote(ns, _parties(), LawMagnitude.scaled(law, 10.0))["passed"]):
				return law
			law.magnitude = {}
	_fail("no open spending law passes at both scales")
	return null


## The first spending line the ledger realised for this law.
func _ledger_spending(ns, law) -> float:
	var ledger: Dictionary = (ns.law_ledger.get(law.id, {}) as Dictionary).get("channels", {})
	var spending: Dictionary = ledger.get("spending_pct_gdp", {})
	return 0.0 if spending.is_empty() else float(spending.values()[0])


func _check_a_grade_is_refused_where_it_means_nothing() -> void:
	var state = _new_state()
	var plain
	for law in Legislature.available(state.player(), _loader.laws):
		if not law.constitutional:
			plain = law
			break
	if bool(Legislature.propose(state, _loader, plain, false, false, 10.0).get("tabled", false)):
		_fail("a law with no magnitude took a grade")
	plain.magnitude = {"value": 40.0, "reference": 40.0, "unit": "lycees"}
	for bad in [0.0, -1.0, 0.05, 11.0]:
		if bool(Legislature.propose(state, _loader, plain, false, false, bad).get("tabled", false)):
			_fail("a grade of %.2f was taken" % bad)
	if bool(Legislature.propose(state, _loader, plain, false, true, 10.0).get("tabled", false)):
		_fail("a grade took the referendum road")
	# may_grade itself: the proposal above is refused earlier for a law with no such road.
	if LawMagnitude.may_grade(plain, 2.0, true) or not LawMagnitude.may_grade(plain, 2.0, false):
		_fail("may_grade reads the referendum road wrongly")
	if not state.player().tabled_bill.is_empty():
		_fail("a refused grade left a tabled bill: %s" % [state.player().tabled_bill])
	plain.magnitude = {}


## Article 49.3 skips the division and not the grade: twins of one game forced at each scale,
## read from what was realised, and a law with no size is refused on this road too.
func _check_a_forced_bill_keeps_its_grade() -> void:
	var one = _new_state()
	var ten = _new_state()
	var law = _open_graded(one)
	if law == null:
		return
	var at_one: Dictionary = Legislature.propose(one, _loader, law, true)
	var at_ten: Dictionary = Legislature.propose(ten, _loader, law, true, false, 10.0)
	if not bool(at_one.get("forced", false)) or not bool(at_ten.get("forced", false)) or bool(at_one.get("refused", false)) or bool(at_ten.get("refused", false)):
		_fail("premise: the forced road was not taken: %s, %s" % [at_one, at_ten])
	var line_one := _ledger_spending(one.player(), law)
	var line_ten := _ledger_spending(ten.player(), law)
	if line_one <= 0.0 or not is_equal_approx(line_ten, 10.0 * line_one):
		_fail("%s forced at ten times realised %.4f, at one %.4f" % [law.id, line_ten, line_one])
	law.magnitude = {}
	var plain = _new_state()
	var cooldown := int(plain.player().force_cooldown_months)
	var refused: Dictionary = Legislature.propose(plain, _loader, law, true, false, 10.0)
	if not bool(refused.get("refused", false)) or _ledger_spending(plain.player(), law) != 0.0 or int(plain.player().force_cooldown_months) != cooldown:
		_fail("a law with no magnitude was forced at a grade: %s" % [refused])


## The division that holds a graded bill writes its grade on the hold, or the release above
## would apply one times the bill: a chamber that says no, on the first nation whose upper
## house only holds, its seats against the bill by hand. A row at half its reference, so a
## grade of 2 cannot be mistaken for the ratio of 1.
func _check_a_hold_writes_its_grade() -> void:
	for nation_id in _loader.nations:
		if not _loader.nations[nation_id].playable:
			continue
		var state = GameState.new_game(_loader, nation_id)
		state.year = 2026
		state.month = 3
		var ns = state.player()
		for law in Legislature.available(ns, _loader.laws):
			if law.constitutional or not law.effects.has("spending_pct_gdp"):
				continue
			if Chambers.power_over(ns, law) != ChambersK.VERDICT_SUSPENSIVE:
				continue
			law.magnitude = {"value": 20.0, "reference": 40.0, "unit": "lycees"}
			var big = LawMagnitude.scaled(law, 2.0)
			var parties: Array = _loader.parties[nation_id]
			if bool(Legislature.resolve_vote(ns, parties, big)["passed"]) and not bool(Legislature.resolve_upper(ns, parties, big)["passed"]):
				Legislature.propose(state, _loader, law, false, false, 2.0)
				Division.divide(state, _loader)
				var hold: Dictionary = ns.held_bills.get(law.id, {})
				law.magnitude = {}
				if float(hold.get("scale", 0.0)) != 2.0:
					_fail("a held graded bill kept %s on its hold" % [hold])
				return
			law.magnitude = {}
	_fail("no playable nation holds a graded bill: the write went unread")


## Held by the upper chamber, a graded bill comes back at its grade (tick_month's release).
func _check_a_held_bill_keeps_its_grade() -> void:
	var one = _new_state()
	var law = _open_graded(one)
	if law == null:
		return
	var ten = _new_state()
	for pair in [[one, {}], [ten, {"scale": 10.0}]]:
		var entry := {"months": 1, "origin": "bill"}
		entry.merge(pair[1])
		pair[0].player().held_bills[law.id] = entry
	Legislature.tick_month(one, _loader)
	Legislature.tick_month(ten, _loader)
	if one.player().held_bills.has(law.id) or ten.player().held_bills.has(law.id):
		_fail("premise: the hold did not run out")
	var line_one := _ledger_spending(one.player(), law)
	var line_ten := _ledger_spending(ten.player(), law)
	if line_one == 0.0 or not is_equal_approx(line_ten, 10.0 * line_one):
		_fail("a held bill at ten times released %.4f, at one %.4f" % [line_ten, line_one])
	law.magnitude = {}


## held_bills goes through a reader that names its keys, unlike tabled_bill: a hold saved and
## loaded releases at its grade, and an ungraded hold reads as it always did.
func _check_a_held_grade_survives_a_save() -> void:
	var state = _new_state()
	var law = _open_graded(state)
	if law == null:
		return
	var plain = _new_state()
	state.player().held_bills[law.id] = {"months": 1, "origin": "player", "scale": 10.0}
	plain.player().held_bills[law.id] = {"months": 1, "origin": "player"}
	var back = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	var plain_back = GameState.from_dict(JSON.parse_string(JSON.stringify(plain.to_dict())))
	if float(back.player().held_bills.get(law.id, {}).get("scale", 0.0)) != 10.0:
		_fail("a held grade did not survive a save: %s" % [back.player().held_bills])
	if plain_back.player().held_bills.get(law.id, {}).has("scale"):
		_fail("an ungraded hold came back with a grade: %s" % [plain_back.player().held_bills])
	Legislature.tick_month(back, _loader)
	Legislature.tick_month(plain_back, _loader)
	var line_ten := _ledger_spending(back.player(), law)
	var line_one := _ledger_spending(plain_back.player(), law)
	if line_one == 0.0 or not is_equal_approx(line_ten, 10.0 * line_one):
		_fail("a hold released after a load realised %.4f at ten times, %.4f at one" % [line_ten, line_one])
	law.magnitude = {}


func _check_a_grade_survives_a_save() -> void:
	var state = _new_state()
	var law = _open_graded(state)
	if law == null:
		return
	Legislature.propose(state, _loader, law, false, false, 2.5)
	var back = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	if float(back.player().tabled_bill.get("scale", 0.0)) != 2.5:
		_fail("a tabled grade did not survive a save: %s" % [back.player().tabled_bill])
	law.magnitude = {}


## A party whose line on the bill is no, and one of its people with a standing.
func _no_party_and_person(ns, law) -> Array:
	var verdict: Dictionary = Legislature.resolve_vote(ns, _parties(), law)
	for party in _parties():
		if String(verdict["party_votes"][party.id]) == "no" and int(ns.seats_by_party.get(party.id, 0)) > 20:
			for person in _loader.people[PLAYER]:
				if String(person.party_id) == party.id:
					return [party, String(person.id)]
	_fail("no party votes no on %s" % law.id)
	return []


func _check_a_pledge_moves_seats_on_one_bill() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _graded()
	var other
	for candidate in _loader.laws:
		if candidate.id != law.id:
			other = candidate
			break
	var found := _no_party_and_person(ns, law)
	if found.is_empty():
		return
	var party = found[0]
	var pid: String = found[1]
	var before: Dictionary = Legislature.resolve_vote(ns, _parties(), law)
	var before_other := str(Legislature.resolve_vote(ns, _parties(), other))
	var seats := int(ns.seats_by_party[party.id])
	ns.person_standing[pid] = 0.8
	if not President.pledge(state, ns, _loader, pid, law.id, _now(state) + 3):
		_fail("the pledge was not written")
		return
	var after: Dictionary = Legislature.resolve_vote(ns, _parties(), law)
	var want := roundi(float(seats) * 0.8 * 0.25)
	if int(after["yes_seats"]) - int(before["yes_seats"]) != want or int(before["no_seats"]) - int(after["no_seats"]) != want:
		_fail("a pledge of %d seats moved yes %d -> %d, no %d -> %d" % [want, before["yes_seats"], after["yes_seats"], before["no_seats"], after["no_seats"]])
	if int((after.get("party_pledged", {}) as Dictionary).get(party.id, 0)) != want:
		_fail("the result does not say who was pledged: %s" % [after.get("party_pledged")])
	if String(after["party_votes"][party.id]) != "no":
		_fail("a pledge moved the party's line: seats, not the line, is the ruling")
	if str(Legislature.resolve_vote(ns, _parties(), other)) != before_other:
		_fail("a pledge on one bill moved another")
	# A backbencher with no standing still brings their own seat.
	ns.person_standing[pid] = 0.0
	var own: Dictionary = Legislature.resolve_vote(ns, _parties(), law)
	if int(own["yes_seats"]) - int(before["yes_seats"]) != 1:
		_fail("a person of no standing brought %d seats, not their own" % (int(own["yes_seats"]) - int(before["yes_seats"])))
	# Many hands cap at the party's seats, in the result as in the tally.
	var hands: Array[String] = ["hand_0", "hand_1", "hand_2", "hand_3", "hand_4"]
	for hand in hands:
		ns.person_standing[hand] = 1.0
		ns.commitments.append({"kind": "pledge", "person_id": hand, "object": "law:%s" % law.id, "made_month": _now(state), "due_month": _now(state) + 3, "party_id": party.id})
	if int(Legislature.resolve_vote(ns, _parties(), law)["party_pledged"][party.id]) != seats:
		_fail("pledges past the party's %d seats read %s" % [seats, Legislature.resolve_vote(ns, _parties(), law)["party_pledged"]])
	for hand in hands:
		President.withdraw_commitment(ns, "pledge", hand, "law:%s" % law.id)
	ns.person_standing[pid] = 0.0
	# A party's leader has no party_id: the party names them, and they pledge for it.
	var leader := String(party.leader_person_id)
	if not President.pledge(state, ns, _loader, leader, other.id, _now(state) + 3) or String(President.pledges_on(ns, other.id)[0].get("party_id", "")) != party.id:
		_fail("a party's leader could not pledge for the party they lead: %s" % [President.pledges_on(ns, other.id)])
	President.withdraw_commitment(ns, "pledge", leader, "law:%s" % other.id)
	# Their party left: the row delivers nothing, and is a broken pledge at the vote.
	ns.person_party_override[pid] = ""
	if str(Legislature.resolve_vote(ns, _parties(), law)) != str(before):
		_fail("a person who left the party still delivered its seats")


func _check_a_pledge_takes_no_before_abstain_and_caps() -> void:
	if DivisionTerms.seats_of("no", "no", 100, 0, 30, 0.0, 0.0) != [30, 70, 0]:
		_fail("a pledge on a no line: %s" % [DivisionTerms.seats_of("no", "no", 100, 0, 30, 0.0, 0.0)])
	if DivisionTerms.seats_of("abstain", "abstain", 100, 0, 30, 0.0, 0.0) != [30, 0, 70]:
		_fail("a pledge on an abstaining line: %s" % [DivisionTerms.seats_of("abstain", "abstain", 100, 0, 30, 0.0, 0.0)])
	if DivisionTerms.seats_of("yes", "yes", 100, 0, 30, 0.0, 0.0) != [100, 0, 0]:
		_fail("a pledge on a yes line added seats: %s" % [DivisionTerms.seats_of("yes", "yes", 100, 0, 30, 0.0, 0.0)])
	if DivisionTerms.seats_of("no", "abstain", 100, 10, 95, 0.0, 0.0) != [95, 0, 5]:
		_fail("a pledge takes no before abstain: %s" % [DivisionTerms.seats_of("no", "abstain", 100, 10, 95, 0.0, 0.0)])
	if DivisionTerms.seats_of("yes", "no", 100, 10, 5, 0.0, 0.0) != [95, 5, 0]:
		_fail("a pledge comes from the rebels of a yes line: %s" % [DivisionTerms.seats_of("yes", "no", 100, 10, 5, 0.0, 0.0)])
	if DivisionTerms.seats_of("no", "no", 100, 0, 500, 0.0, 0.0) != [100, 0, 0]:
		_fail("a pledge past the party's seats: %s" % [DivisionTerms.seats_of("no", "no", 100, 0, 500, 0.0, 0.0)])
	if DivisionTerms.seats_of("no", "yes", 100, 10, 0, 0.0, 0.0) != [10, 90, 0]:
		_fail("no pledge changed the split: %s" % [DivisionTerms.seats_of("no", "yes", 100, 10, 0, 0.0, 0.0)])


## A peel reads the seats a whip holds on yes: not a no line, not an abstaining one, not
## rebels voting yes against their line, and a rebel leaving a yes line is not peeled again.
func _check_only_a_whipped_yes_line_peels() -> void:
	var table := [
		[["yes", "yes", 100, 0, 0, 0.2], [80, 0, 20], "a yes line"],
		[["no", "no", 100, 0, 0, 0.2], [0, 100, 0], "a no line"],
		[["abstain", "abstain", 100, 0, 0, 0.2], [0, 0, 100], "an abstaining line"],
		[["no", "yes", 100, 10, 0, 0.2], [10, 90, 0], "rebels voting yes against a no line"],
		[["yes", "no", 100, 10, 0, 0.2], [72, 10, 18], "the whipped seats of a yes line, its rebels out"],
		[["yes", "abstain", 100, 10, 0, 0.2], [72, 0, 28], "rebels abstaining beside what peeled"],
		[["yes", "no", 100, 10, 5, 0.0], [95, 5, 0], "no peel at all"],
	]
	_read_seats(table)


## Exactly the pledged number of seats is bound. The numbers tell apart the wrong orders:
## with 100 seats, 10 rebels against, 15 pledged and 20 % peeling, leaving the pledge out of
## the peel's base reads 82, peeling first and drawing the pledge back out of it reads 87,
## and holding the whole pledge on the line besides drawing the rebels reads 85.
func _check_pledged_and_peeled_seats_do_not_double_count() -> void:
	var table := [
		[["yes", "yes", 100, 0, 30, 0.2], [86, 0, 14], "a pledge holds seats on a yes line"],
		[["yes", "no", 100, 10, 15, 0.2], [83, 0, 17], "a pledge brings the rebels, then holds"],
		[["yes", "no", 100, 10, 10, 0.2], [82, 0, 18], "a pledge spent on the rebels holds nothing"],
		[["yes", "abstain", 100, 10, 5, 0.2], [77, 0, 23], "a pledge draws no seat that peeled"],
		[["yes", "yes", 100, 0, 100, 0.5], [100, 0, 0], "a whole party pledged: nothing peels"],
		[["no", "no", 100, 0, 30, 0.2], [30, 70, 0], "a pledge across a no line peels nothing"],
	]
	_read_seats(table)
	for row in table:
		var got: Array = DivisionTerms.seats_of(row[0][0], row[0][1], row[0][2], row[0][3], row[0][4], row[0][5], 0.0)
		if int(got[0]) + int(got[1]) + int(got[2]) != int(row[0][2]):
			_fail("%s: %s does not add up to the party's seats" % [row[2], got])


func _read_seats(table: Array) -> void:
	for row in table:
		var a: Array = row[0]
		var got: Array = DivisionTerms.seats_of(a[0], a[1], a[2], a[3], a[4], a[5], 0.0)
		if got != row[1]:
			_fail("%s: %s, want %s" % [row[2], got, row[1]])


## 85 % per tenfold at no discipline at all, by the live discipline, and nothing at or below
## the reference. The number is written here, never read from the constant.
func _check_the_share_that_peels() -> void:
	var ns = _new_state().player()
	var party = _parties()[0]
	var table := [
		[0.85, 400.0, 0.1275], [0.5, 400.0, 0.425], [0.0, 400.0, 0.85], [0.5, 4000.0, 0.85],
		[0.5, 40.0, 0.0], [0.5, 4.0, 0.0],
	]
	for row in table:
		ns.party_discipline[party.id] = float(row[0])
		var share := DivisionTerms.peel_share(ns, party, _graded(float(row[1]), 40.0))
		if not is_equal_approx(share, float(row[2])) and not (float(row[2]) == 0.0 and share == 0.0):
			_fail("discipline %.2f at %.0f of 40 peels %.4f, want %.4f" % [row[0], row[1], share, row[2]])
	var plain = _graded()
	plain.magnitude = {}
	if DivisionTerms.peel_share(ns, party, plain) != 0.0:
		_fail("a law with no magnitude peels")
	ns.party_discipline[party.id] = 0.0
	if DivisionTerms.peel_share(ns, party, _graded(4.0e20, 40.0)) != 1.0:
		_fail("a row of any ratio must not peel past the whole line: %.3f" % DivisionTerms.peel_share(ns, party, _graded(4.0e20, 40.0)))


## An opposition party on a yes line, so no whip moves when its discipline does. Through
## resolve_vote: the seats go from yes to abstain, by its discipline, and it is no rebellion.
func _check_the_peel_on_a_real_division() -> void:
	var ns = _new_state().player()
	var found := _opposition_on_yes(ns)
	if found.is_empty():
		_fail("no opposition party on a yes line at both sizes")
		return
	var party = found["party"]
	var seats := int(ns.seats_by_party[party.id])
	var law = found["law"]
	var big = LawMagnitude.scaled(law, 10.0)
	ns.party_discipline[party.id] = 1.0
	var whole: Dictionary = Legislature.resolve_vote(ns, _parties(), big)
	ns.party_discipline[party.id] = 0.0
	var loose: Dictionary = Legislature.resolve_vote(ns, _parties(), big)
	var want := roundi(float(seats) * 0.85)
	if want == 0:
		_fail("premise: %s is too small to read a peel" % party.id)
	if int(whole["yes_seats"]) - int(loose["yes_seats"]) != want or int(loose["abstain_seats"]) - int(whole["abstain_seats"]) != want:
		_fail("%s of %d seats peeled %d yes, %d abstain, want %d" % [party.id, seats,
			int(whole["yes_seats"]) - int(loose["yes_seats"]), int(loose["abstain_seats"]) - int(whole["abstain_seats"]), want])
	if int(whole["no_seats"]) != int(loose["no_seats"]):
		_fail("a peel moved a no")
	if loose["party_rebels"].has(party.id):
		_fail("a peel is not a rebellion, and it would be charged as one: %s" % [loose["party_rebels"]])
	if String(loose["party_votes"][party.id]) != "yes":
		_fail("a peel moved the party's line")
	var reference: Dictionary = Legislature.resolve_vote(ns, _parties(), law)
	ns.party_discipline[party.id] = 1.0
	if str(reference) != str(Legislature.resolve_vote(ns, _parties(), law)):
		_fail("a bill at its reference size reads discipline through the peel")


func _opposition_on_yes(ns) -> Dictionary:
	for law in _loader.laws:
		if law.constitutional or not law.effects.has("spending_pct_gdp"):
			continue
		var graded = LawMagnitude.copy(law)
		graded.magnitude = {"value": 40.0, "reference": 40.0, "unit": "u"}
		var big = LawMagnitude.scaled(graded, 10.0)
		for party in _parties():
			if ns.coalition_party_ids.has(party.id) or int(ns.seats_by_party.get(party.id, 0)) < 20:
				continue
			if Legislature.vote_of(Legislature.support(ns, party, graded)) == "yes" and Legislature.vote_of(Legislature.support(ns, party, big)) == "yes":
				return {"party": party, "law": graded}
	return {}


## pledged_seats() sums the rows, so a second word on one bill must not write a second row.
func _check_one_person_pledges_a_bill_once() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _graded()
	var found := _no_party_and_person(ns, law)
	if found.is_empty():
		return
	var pid: String = found[1]
	var due: int = _now(state) + 3
	if not President.pledge(state, ns, _loader, pid, law.id, due):
		_fail("premise: %s could not pledge" % pid)
	var once := DivisionTerms.pledged_seats(ns, found[0], law)
	if President.pledge(state, ns, _loader, pid, law.id, due):
		_fail("%s pledged %s twice" % [pid, law.id])
	if DivisionTerms.pledged_seats(ns, found[0], law) != once or President.pledges_on(ns, law.id).size() != 1:
		_fail("a second pledge moved the seats: %d against %d" % [DivisionTerms.pledged_seats(ns, found[0], law), once])
	if not President.pledge(state, ns, _loader, pid, "another_bill", due):
		_fail("a pledge on one bill refused one on another")
	var second := false
	for other_id in _loader.person_by_id:
		if String(other_id).begins_with("%s_" % PLAYER) and other_id != pid and President.pledge(state, ns, _loader, other_id, law.id, due):
			second = true
			break
	if not second:
		_fail("one person's pledge refused everybody else's on that bill")


## The mark the deal reads: kept when it delivered, broken when the person left the party,
## off the live register either way, and the president is not charged here.
func _check_the_vote_judges_a_pledge() -> void:
	for leg in ["kept", "broken"]:
		var state = _new_state()
		var ns = state.player()
		var law = _open_graded(state)
		if law == null:
			return
		var found := _no_party_and_person(ns, law)
		if found.is_empty():
			return
		var pid: String = found[1]
		if not President.pledge(state, ns, _loader, pid, law.id, _now(state) + 3):
			_fail("the pledge was not written")
		var rapport := President.rapport(ns, pid)
		var grudge := float(ns.person_grudges.get(pid, 0.0))
		if President.pledge_verdict(ns, pid, law.id) != "":
			_fail("a pledge has a verdict before its vote")
		if leg == "broken":
			ns.person_party_override[pid] = ""
		Legislature.propose(state, _loader, law)
		Division.divide(state, _loader)
		if President.pledge_verdict(ns, pid, law.id) != leg:
			_fail("a %s pledge reads '%s' after the vote: %s" % [leg, President.pledge_verdict(ns, pid, law.id), ns.commitments_judged])
		if not ns.commitments.is_empty():
			_fail("a judged pledge is still live: %s" % [ns.commitments])
		if President.rapport(ns, pid) != rapport or float(ns.person_grudges.get(pid, 0.0)) != grudge:
			_fail("the vote charged a %s pledge: the deal prices it, not the division" % leg)
		law.magnitude = {}


## The person did not leave, the party holds no seat: nothing was delivered.
func _check_a_pledge_is_broken_with_no_seat() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _graded()
	var found := _no_party_and_person(ns, law)
	if found.is_empty():
		return
	var pid: String = found[1]
	President.pledge(state, ns, _loader, pid, law.id, _now(state) + 3)
	ns.seats_by_party[found[0].id] = 0
	DivisionTerms.judge_pledges(ns, law, _now(state))
	if President.pledge_verdict(ns, pid, law.id) != "broken":
		_fail("a pledge from a party with no seat reads '%s'" % President.pledge_verdict(ns, pid, law.id))


## A defector pledges for the party they joined, and someone sitting alone cannot pledge.
func _check_a_pledge_names_the_party_the_person_is_in() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _graded()
	var found := _no_party_and_person(ns, law)
	if found.is_empty():
		return
	var pid: String = found[1]
	var other := ""
	for party in _parties():
		if party.id != found[0].id:
			other = String(party.id)
			break
	ns.person_party_override[pid] = other
	if not President.pledge(state, ns, _loader, pid, law.id, _now(state) + 3):
		_fail("a defector's pledge was refused")
	var rows: Array = President.pledges_on(ns, law.id)
	if rows.size() != 1 or String(rows[0]["party_id"]) != other:
		_fail("a defector's pledge names %s, want %s" % [rows, other])
	President.withdraw_commitment(ns, "pledge", pid, "law:%s" % law.id)
	ns.person_party_override[pid] = ""
	if President.pledge(state, ns, _loader, pid, law.id, _now(state) + 3):
		_fail("someone sitting alone pledged seats they do not have")


## Judged twice over a game: the read is this bill's, and the later of its two marks.
func _check_the_verdict_is_this_bill_and_the_latest() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _graded()
	var found := _no_party_and_person(ns, law)
	if found.is_empty():
		return
	var pid: String = found[1]
	var due: int = _now(state) + 3
	President.pledge(state, ns, _loader, pid, law.id, due)
	DivisionTerms.judge_pledges(ns, law, _now(state))
	if President.pledge_verdict(ns, pid, law.id) != "kept":
		_fail("premise: the first pledge reads '%s'" % President.pledge_verdict(ns, pid, law.id))
	if President.pledge_verdict(ns, pid, "another_bill") != "":
		_fail("a mark on one bill reads on another: '%s'" % President.pledge_verdict(ns, pid, "another_bill"))
	President.pledge(state, ns, _loader, pid, law.id, due)
	ns.person_party_override[pid] = ""
	DivisionTerms.judge_pledges(ns, law, _now(state))
	if President.pledge_verdict(ns, pid, law.id) != "broken":
		_fail("the later mark is 'broken', and the read says '%s'" % President.pledge_verdict(ns, pid, law.id))


func _check_a_pledge_with_no_vote_is_void_at_no_price() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _graded()
	var found := _no_party_and_person(ns, law)
	if found.is_empty():
		return
	var pid: String = found[1]
	President.pledge(state, ns, _loader, pid, law.id, _now(state) + 1)
	var rapport := President.rapport(ns, pid)
	state.month += 2
	var out: Dictionary = Levers.tick_month(state, _loader, {})
	if President.pledge_verdict(ns, pid, law.id) != "void" or not (out["void"] as Array).size() == 1:
		_fail("a pledge whose bill never came reads '%s': %s" % [President.pledge_verdict(ns, pid, law.id), out])
	if President.rapport(ns, pid) != rapport:
		_fail("a void pledge charged rapport")


func _check_a_pledge_survives_a_save() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _graded()
	var found := _no_party_and_person(ns, law)
	if found.is_empty():
		return
	President.pledge(state, ns, _loader, found[1], law.id, _now(state) + 3)
	var back = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	if str(Legislature.resolve_vote(back.player(), _parties(), law)["party_pledged"]) != str(Legislature.resolve_vote(ns, _parties(), law)["party_pledged"]):
		_fail("a pledge moved other seats after a save")


func _fail(message: String) -> void:
	_failures.append(message)
