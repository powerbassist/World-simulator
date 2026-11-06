extends SceneTree

## V5.3 b, the author's idea ("On doit pouvoir negocier le prix avec l'acheteur
## non ?"), the parent's mechanic: ONE Negotiate answer on every price ask. These
## are its pure parts (src/sim/negotiation.gd): the other side's true chance of
## accepting a counter, the range the strip shows (the #244 fog: a fixed width with
## the truth seeded inside it), and the seeded draw -- accepted, back next month at
## the old price, or walked away.

const Negotiation = preload("res://src/sim/negotiation.gd")
const K = preload("res://src/sim/companies_constants.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_odds_fall_with_the_counter_and_the_other_sides_leverage()
	_test_the_shown_range_brackets_the_truth()
	_test_the_draw_lands_at_its_odds()
	_test_the_draw_is_seeded()
	_finish()


## A bigger counter is harder to win, and so is one against a strong other side;
## every counter keeps a chance either way (no certain win, no certain loss).
func _test_odds_fall_with_the_counter_and_the_other_sides_leverage() -> void:
	var counters: Array = K.NEGOTIATE_COUNTERS
	if counters.size() != 3:
		_fail("the counters are %s, not the three the strip offers" % [counters])
		return
	for leverage in [-1.0, 0.0, 1.0]:
		var last := 2.0
		for c in counters:
			var p := Negotiation.odds(float(c), leverage)
			if not (p < last) or p <= 0.0 or p >= 1.0:
				_fail("a %d %% counter at leverage %.1f reads %.3f after %.3f" % [roundi(100.0 * float(c)), leverage, p, last])
			last = p
	for c in counters:
		if not (Negotiation.odds(float(c), 1.0) < Negotiation.odds(float(c), 0.0)
				and Negotiation.odds(float(c), 0.0) < Negotiation.odds(float(c), -1.0)):
			_fail("a %d %% counter's odds do not fall as the other side grows stronger" % roundi(100.0 * float(c)))


## The strip's range is NEGOTIATE_FOG either side wide and holds the truth, on
## every seed, without its midpoint giving the truth away.
func _test_the_shown_range_brackets_the_truth() -> void:
	var off_centre := 0
	for i in 400:
		var p := Negotiation.odds(float(K.NEGOTIATE_COUNTERS[i % 3]), -1.0 + 2.0 * float(i % 7) / 6.0)
		var r: Vector2 = Negotiation.shown(p, "negotiation|test|%d" % i, 100 + i)
		if r.x > p + 1e-12 or r.y < p - 1e-12 or not is_equal_approx(r.y - r.x, 2.0 * K.NEGOTIATE_FOG):
			_fail("seed %d shows %s for a true %.3f" % [i, r, p])
			return
		if absf((r.x + r.y) / 2.0 - p) > 0.02:
			off_centre += 1
	if off_centre < 200:
		_fail("only %d of 400 ranges sit off their truth: the midpoint gives it away" % off_centre)


## Over many deals the other side accepts at its odds, and of the refusals the
## NEGOTIATE_WALK share walk away; the rest come back.
func _test_the_draw_lands_at_its_odds() -> void:
	var p := 0.55
	var n := 4000
	var tally := {"accepted": 0, "back": 0, "walked": 0}
	for i in n:
		var outcome := Negotiation.draw(p, "deal|%d" % i, 300)
		tally[outcome] = int(tally.get(outcome, 0)) + 1
	if tally.size() != 3:
		_fail("the draw returned outcomes %s" % [tally.keys()])
		return
	var accepted := float(tally["accepted"]) / float(n)
	var refused := float(n - int(tally["accepted"]))
	var walked := float(tally["walked"]) / refused
	if absf(accepted - p) > 0.03 or absf(walked - K.NEGOTIATE_WALK) > 0.04:
		_fail("4000 deals at odds %.2f: %.3f accepted, %.3f of the refusals walked (want %.2f)" % [p, accepted, walked, K.NEGOTIATE_WALK])


func _test_the_draw_is_seeded() -> void:
	for i in 50:
		if Negotiation.draw(0.5, "same|%d" % i, 42) != Negotiation.draw(0.5, "same|%d" % i, 42):
			_fail("the same deal in the same month drew two outcomes")
			return


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_negotiation")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)
