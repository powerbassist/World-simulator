extends RefCounted

## V5.3 b, the author's idea ("On doit pouvoir negocier le prix avec l'acheteur
## non ?"), the parent's mechanic: ONE Negotiate answer on every price ask (the
## stake's final price, the nationalisation's offer, the sale's best bid, the closing
## plant buyer's sweetener). The player counters by one of NEGOTIATE_COUNTERS -- less
## to pay or more to receive -- and the other side answers at the ask's due month:
##
##   accepted   the deal lands at the countered price;
##   back       it comes back the next month at the OLD price, once per deal;
##   walked     the other side walks away and the deal ends.
##
## These are the pure parts, shared by every ask: the true odds, the range the strip
## shows (the #244 fog: a fixed width with the truth seeded inside, so the midpoint
## does not give it away) and the seeded draw. Each draw is Cycle.unit() on its own
## key and month -- keyed and stateless, so computing a range or a draw consumes no
## stream and a game that never negotiates draws exactly what it drew before.
## Main-thread reads only (process ticks, the player's verbs).

const K = preload("res://src/sim/companies_constants.gd")
const Cycle = preload("res://src/sim/cycle.gd")


## The other side's true chance of accepting a counter of `counter` (a share of the
## price) when its strength is `leverage`, from -1 (weakest: a seller in a downturn)
## to 1 (strongest: a closing plant's buyer). Falls with both, inside the bounds, so
## no counter is a certain win or a certain loss.
static func odds(counter: float, leverage: float) -> float:
	var p := K.NEGOTIATE_ODDS.x - K.NEGOTIATE_ODDS.y * counter - K.NEGOTIATE_LEVERAGE * clampf(leverage, -1.0, 1.0)
	return clampf(p, K.NEGOTIATE_ODDS_BOUNDS.x, K.NEGOTIATE_ODDS_BOUNDS.y)


## The range the strip shows for true odds `odds_true`: NEGOTIATE_FOG either side
## wide, the truth seeded inside it on the deal's key in month `now`.
static func shown(odds_true: float, key: String, now: int) -> Vector2:
	var u := Cycle.unit("%s|odds" % key, now)
	var lo := clampf(odds_true - 2.0 * K.NEGOTIATE_FOG * u, 0.0, 1.0 - 2.0 * K.NEGOTIATE_FOG)
	return Vector2(lo, lo + 2.0 * K.NEGOTIATE_FOG)


## The other side's answer at the ask's due month: "accepted" at its odds, else
## "walked" for NEGOTIATE_WALK of the refusals and "back" for the rest.
static func draw(odds_true: float, key: String, now: int) -> String:
	if Cycle.unit("%s|answer" % key, now) < odds_true:
		return "accepted"
	return "walked" if Cycle.unit("%s|walk" % key, now) < K.NEGOTIATE_WALK else "back"
