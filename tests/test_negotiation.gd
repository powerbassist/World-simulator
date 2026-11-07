extends SceneTree

## V5.3 b, the author's idea ("On doit pouvoir negocier le prix avec l'acheteur
## non ?"), the parent's mechanic: ONE Negotiate answer on every price ask. These
## are its pure parts (src/sim/negotiation.gd): the other side's true chance of
## accepting a counter, the range the strip shows (the #244 fog: a fixed width with
## the truth seeded inside it), and the seeded draw -- accepted, back next month at
## the old price, or walked away.

const Negotiation = preload("res://src/sim/negotiation.gd")
const K = preload("res://src/sim/companies_constants.gd")
const Cycle = preload("res://src/sim/cycle.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_odds_fall_with_the_counter_and_the_other_sides_leverage()
	_test_the_shown_range_brackets_the_truth()
	_test_the_range_keeps_its_fog_at_the_edges()
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


## The #280 RECORD the parent routed to PR 2: the range was clamped at the edges, so
## true odds above 1 - 2 x FOG (a 5 % counter against a weak seller) sat in the top
## window on most seeds, and below 2 x FOG in the bottom one: the fog said where the
## truth was. The window now slides over every place that holds the truth inside
## [0, 1], so at the edges it is rarely pinned; in the middle it is the window it was,
## on the same seed.
func _test_the_range_keeps_its_fog_at_the_edges() -> void:
	var w := 2.0 * K.NEGOTIATE_FOG
	for p in [K.NEGOTIATE_ODDS_BOUNDS.x, K.NEGOTIATE_ODDS_BOUNDS.y]:
		var pinned := 0
		for i in 200:
			var r: Vector2 = Negotiation.shown(p, "edge|%d" % i, 50 + i)
			if r.x > p + 1e-12 or r.y < p - 1e-12 or r.x < -1e-12 or r.y > 1.0 + 1e-12 or not is_equal_approx(r.y - r.x, w):
				_fail("seed %d shows %s for a true %.2f" % [i, r, p])
				return
			if is_equal_approx(r.x, 0.0) or is_equal_approx(r.y, 1.0):
				pinned += 1
		if pinned > 20:
			_fail("%d of 200 ranges for a true %.2f sit pinned at the edge: the fog gives it away" % [pinned, p])
	for i in 200:
		var p := w + (1.0 - 2.0 * w) * float(i) / 199.0
		var key := "mid|%d" % i
		var u := Cycle.unit("%s|odds" % key, 70 + i)
		if not is_equal_approx(Negotiation.shown(p, key, 70 + i).x, p - w * u):
			_fail("a true %.3f in the middle moved its window: %s, was %.4f" % [p, Negotiation.shown(p, key, 70 + i), p - w * u])
			return


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
