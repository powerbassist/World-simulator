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
const Economy = preload("res://src/sim/economy.gd")

## The stages whose ask is a price, and of them the state's purchases.
const PRICE_STAGES := ["negotiation", "offer", "sale"]
const PURCHASE_STAGES := ["negotiation", "offer"]
## The verbs whose deals can be negotiated, by the side the state deals with: a seller
## on a purchase, the buyers on a sale (side_of(); a walk holds its own side's, holds()).
const PURCHASE_VERBS := ["minority_stake", "full_nationalisation"]
const SALE_VERBS := ["privatisation"]
const SELLER_WALKED := "The seller walked away from a deal on this firm and will not talk again yet."
const BUYERS_WALKED := "The buyers walked away from the sale of this firm and will not bid again yet."


## The other side's true chance of accepting a counter of `counter` (a share of the
## price) when its strength is `leverage`, from -1 (weakest: a seller in a downturn)
## to 1 (strongest: a closing plant's buyer). Falls with both, inside the bounds, so
## no counter is a certain win or a certain loss.
static func odds(counter: float, leverage: float) -> float:
	var p := K.NEGOTIATE_ODDS.x - K.NEGOTIATE_ODDS.y * counter - K.NEGOTIATE_LEVERAGE * clampf(leverage, -1.0, 1.0)
	return clampf(p, K.NEGOTIATE_ODDS_BOUNDS.x, K.NEGOTIATE_ODDS_BOUNDS.y)


## The range the strip shows for true odds `odds_true`: NEGOTIATE_FOG either side
## wide, the truth seeded inside it on the deal's key in month `now`. The window slides
## over every place that holds the truth inside [0, 1] (the #280 RECORD: clamped, a
## truth above 1 - 2 x FOG sat in the top window on most seeds and the fog said where
## it was); in the middle that is the window it always was, on the same seed.
static func shown(odds_true: float, key: String, now: int) -> Vector2:
	var u := Cycle.unit("%s|odds" % key, now)
	var width := 2.0 * K.NEGOTIATE_FOG
	var top := minf(odds_true, 1.0 - width)
	var lo := top - (top - maxf(odds_true - width, 0.0)) * u
	return Vector2(lo, lo + width)


## The other side's answer at the ask's due month: "accepted" at its odds, else
## "walked" for NEGOTIATE_WALK of the refusals and "back" for the rest.
static func draw(odds_true: float, key: String, now: int) -> String:
	if Cycle.unit("%s|answer" % key, now) < odds_true:
		return "accepted"
	return "walked" if Cycle.unit("%s|walk" % key, now) < K.NEGOTIATE_WALK else "back"


## The other side's strength on a price ask at `stage`, -1..1: on a purchase the
## seller's, from the cycle -- strong in a boom, weak in a downturn, at full strength a
## gap of PROCESS_DISCOUNT_GAP_PCT either way (the sale discount's own read); on a sale
## none (the parent's call 2: the discount already carries the cycle).
static func leverage(ns, stage: String) -> float:
	if not PURCHASE_STAGES.has(stage):
		return 0.0
	return clampf(Economy.output_gap_pct(ns) / K.PROCESS_DISCOUNT_GAP_PCT, -1.0, 1.0)


## The three counters' answers on `row`'s price ask, posted in month `now`. `price` is
## the deal's own answer's debt (accept or pay; a sale's is negative, a receipt) and
## `rest` its bloc move. Each: the price moved by the counter (less to pay, more to
## receive), the true odds at the cycle's leverage now (`odds`: the draw's, NEVER shown
## -- the break-up's row["odds"] precedent) inside the range the strip shows
## (odds_lo..odds_hi), the share of refusals that walk, and the old price the deal lands
## at if the other side comes back.
static func answers(ns, row: Dictionary, price: float, rest: Dictionary, now: int) -> Array:
	var out: Array = []
	var stage := String(row["stage"])
	var more := stage == "sale"
	for c in K.NEGOTIATE_COUNTERS:
		var id := "negotiate_%d" % roundi(100.0 * float(c))
		var p := odds(float(c), leverage(ns, stage))
		var band := shown(p, key(row, id), now)
		out.append({"id": id, "counter": float(c), "debt_eur_bn": price * (1.0 + float(c) if more else 1.0 - float(c)),
			"bloc_offset": rest.duplicate(), "odds": p, "odds_lo": band.x, "odds_hi": band.y,
			"walk": K.NEGOTIATE_WALK, "back_debt_eur_bn": price})
	return out


## The seed key of one counter on one deal: the range shown and the answer drawn.
static func key(row: Dictionary, answer_id: String) -> String:
	return "%s|%s" % [String(row["id"]), answer_id]


## The side the state deals with on `action_id`'s deal: "seller" on a purchase,
## "buyers" on a sale, "" for a verb that is not negotiated.
static func side_of(action_id: String) -> String:
	if PURCHASE_VERBS.has(action_id):
		return "seller"
	return "buyers" if SALE_VERBS.has(action_id) else ""


## Whether the walk on `row` still holds the verbs of `side` ("seller" or "buyers",
## side_of) in month `now` (the parent's call 1, per side by its ruling on #280): after
## a seller walks away from a purchase, the firm's purchases -- a new stake, a
## nationalisation bill -- wait NEGOTIATE_WALK_COOLDOWN_MONTHS; after the buyers walk
## away from a sale, its sales do. The other side's verbs stay open: a walked stake does
## not hold a sale of the share the state already owns. Processes.refusal() reads it in
## its one scan of the register and names who walked (walked_line()).
static func holds(row: Dictionary, side: String, now: int) -> bool:
	return side != "" and String(row["status"]) == "walked" and side_of(String(row["action_id"])) == side \
			and now - int(row["closed"]) < K.NEGOTIATE_WALK_COOLDOWN_MONTHS


## The refusal that names who walked away: the seller, or the buyers.
static func walked_line(side: String) -> String:
	return SELLER_WALKED if side == "seller" else BUYERS_WALKED
