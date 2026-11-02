extends RefCounted

## V5.3 a, the author's call on #244 ("each stage asks you something"): the one
## question each process puts to the player at its key stage. The ask is posted in
## the stage's last month and is due when the stage ends, so a player who never
## answers gets the default and the process keeps its timetable (src/sim/processes.gd
## posts it and resolves it; this file builds it). Each answer carries its strip's
## figures -- the debt it books once and the bloc offsets it moves -- so the ask is a
## B7 decision arrival (tools/decision_surfaces_probe.gd --density) and the card the
## UI draws reads the sim's numbers, never a copy.
##
##   negotiation    the stake's final price       accept (default) / walk away
##   offer          the nationalisation's price   pay (default) / stop, the break fee
##   investigation  a ruling FOR the break-up,    press on (default) / settle: a fine
##                  contested by the firm         the firm pays, half the bloc move,
##                                                the firm intact; a firm the
##                                                authority clears is asked nothing
##   sale           the best bid                  accept (default) / hold for a new
##                                                bid in PROCESS_HOLD_MONTHS, once
##
## Walking away and stopping are the stop verb (Processes.stop: a U-turn, and the
## break fee after a vote); the other answers land at the stage's end.

const Companies = preload("res://src/sim/companies.gd")
const K = preload("res://src/sim/companies_constants.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const Economy = preload("res://src/sim/economy.gd")
const Negotiation = preload("res://src/sim/negotiation.gd")

## stage -> [the ask's kind, its default answer].
const STAGE_ASK := {
	"negotiation": ["price", "accept"], "offer": ["offer", "pay"],
	"investigation": ["contest", "press_on"], "sale": ["bid", "accept"],
}


## Post the stage's ask on `row` (the stage's last month). The break-up's finding
## is drawn here, with the odds its strip showed; the sale's bid is priced here, at
## the discount the cycle gives now, and that is the price the sale then books.
## `company` is the firm, from the caller's own lookup (Processes._company), for
## the settlement's fine. A price ask also offers Negotiate's three counters
## (negotiation.gd), once per deal; `reprice` false keeps the sale's bid at its old
## price when a counter comes back (resolve_negotiation()).
static func post(ns, row: Dictionary, action, now: int, company, reprice := true) -> void:
	var stage := String(row["stage"])
	if not STAGE_ASK.has(stage):
		return
	var base := float(row["base_eur_bn"])
	var offsets: Dictionary = action.effects.get("bloc_offset", {})
	var rest := scaled(moved(action, row), 1.0 - K.PROCESS_BLOC_AT_START)
	var answers: Array = []
	match stage:
		"negotiation":
			answers = [_answer("accept", base * (1.0 + float(row["rate"])), rest), _answer("walk", 0.0, uturn(action, row))]
		"offer":
			answers = [_answer("pay", base * (1.0 + float(row["rate"])), rest),
				_answer("stop", K.PROCESS_BREAK_FEE * base * float(row["rate"]), uturn(action, row))]
		"investigation":
			row["ruled"] = rule(row, now)
			if not bool(row["ruled"]):
				return
			var value := Companies.value_eur_bn(ns, company)
			answers = [_answer("press_on", 0.0, offsets),
				_answer("settle", -K.PROCESS_SETTLEMENT_FINE * value, scaled(offsets, K.PROCESS_SETTLEMENT_BLOC))]
		"sale":
			if reprice:
				row["rate"] = discount(ns)
			# One hold only (pass 1 on #248): the new bid is priced and asks nothing,
			# so the sale ends inside the months its strip showed (A3).
			if bool(row.get("held", false)):
				return
			answers = [_answer("accept", -base * (1.0 - float(row["rate"])), rest), _answer("hold", 0.0, {})]
	if Negotiation.PRICE_STAGES.has(stage) and not row.has("negotiated"):
		answers.append_array(Negotiation.answers(ns, row, float(answers[0]["debt_eur_bn"]), answers[0]["bloc_offset"], now))
	row["ask"] = {"kind": String(STAGE_ASK[stage][0]), "posted": now, "due": now + 1,
		"default": String(STAGE_ASK[stage][1]), "answers": answers}


## A counter's answer at its ask's due month `now` (negotiation.gd), before the stage
## lands (Processes._tick_row): true when the stage does not land this month.
##   accepted  the price moves by the counter (base_eur_bn, which every landing reads)
##             and the stage lands as its default would: false.
##   back      one more month at the old price, asked again without the counters
##             (once per deal; a new arrival): true.
##   walked    the deal ends: nothing paid, no U-turn (the other side left), the
##             start's half of the bloc move stays, and Negotiation.cooldown() holds
##             the firm's negotiable verbs: true.
static func resolve_negotiation(ns, row: Dictionary, action, now: int) -> bool:
	var pick := chosen(row)
	if not pick.begins_with("negotiate_"):
		return false
	var a := answer_of(row, pick)
	var outcome := Negotiation.draw(float(a["odds"]), Negotiation.key(row, pick), now)
	row["negotiated"] = true
	row["negotiation"] = {"answer": pick, "outcome": outcome, "month": now}
	match outcome:
		"accepted":
			var c := float(a["counter"])
			row["countered"] = c
			row["base_eur_bn"] = float(row["base_eur_bn"]) * (1.0 + c if String(row["stage"]) == "sale" else 1.0 - c)
			return false
		"back":
			row.erase("answer")
			row["months_left"] = 1
			post(ns, row, action, now, null, false)
			return true
	row["status"] = "walked"
	row["closed"] = now
	return true


## The authority's finding on a referral (true: the break-up is ordered), drawn on
## the row's own seed in month `now` with the odds its strip showed. One copy, so a
## referral saved before the asks and ruled at its stage's end (processes.gd) draws
## from the same stream as one ruled here.
static func rule(row: Dictionary, now: int) -> bool:
	return Cycle.unit("%s|ruling" % String(row["id"]), now) < float(row["odds"])


## The answer the stage resolves with: the player's, else the ask's default ("" with
## no ask posted).
static func chosen(row: Dictionary) -> String:
	var ask: Dictionary = row.get("ask", {})
	return String(row.get("answer", ask.get("default", "")))


## One answer of the ask, by id ({} when the ask does not offer it).
static func answer_of(row: Dictionary, answer_id: String) -> Dictionary:
	for a in (row.get("ask", {}) as Dictionary).get("answers", []):
		if String(a["id"]) == answer_id:
			return a
	return {}


## The sale's discount, from the cycle: none at or above potential, the whole range
## at a gap of PROCESS_DISCOUNT_GAP_PCT below it.
static func discount(ns) -> float:
	var depth := clampf(-Economy.output_gap_pct(ns) / K.PROCESS_DISCOUNT_GAP_PCT, 0.0, 1.0)
	return lerpf(K.PROCESS_PRIVATISE_DISCOUNT.x, K.PROCESS_PRIVATISE_DISCOUNT.y, depth)


## The U-turn: every bloc the verb pleased loses PROCESS_UTURN_SHARE of its offset
## (of the move this row makes, `moved`).
static func uturn(action, row: Dictionary) -> Dictionary:
	var out := {}
	var offsets := moved(action, row)
	for bloc in offsets:
		if float(offsets[bloc]) > 0.0:
			out[bloc] = -K.PROCESS_UTURN_SHARE * float(offsets[bloc])
	return out


## The bloc move this row's verb makes: a buying verb's scales with the share it
## buys, so buying the last 60 % of a part-held firm moves 0.6 x what buying a
## private one does (the parent's call on #275). A row saved before the share was
## recorded reads as bought from nothing, the whole move.
static func moved(action, row: Dictionary) -> Dictionary:
	var offsets: Dictionary = action.effects.get("bloc_offset", {}) if action != null else {}
	if action == null or String(action.id) not in ["minority_stake", "full_nationalisation"]:
		return offsets
	var stake := float((action.effects.get("company", {}) as Dictionary).get("stake", 1.0))
	return scaled(offsets, (stake - float(row.get("state_share_at_start", 0.0))) / stake)


static func scaled(offsets: Dictionary, share: float) -> Dictionary:
	var out := {}
	for bloc in offsets:
		out[bloc] = share * float(offsets[bloc])
	return out


static func _answer(id: String, debt_eur_bn: float, bloc_offset: Dictionary) -> Dictionary:
	return {"id": id, "debt_eur_bn": debt_eur_bn, "bloc_offset": bloc_offset}

