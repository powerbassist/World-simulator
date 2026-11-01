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

## stage -> [the ask's kind, its default answer].
const STAGE_ASK := {
	"negotiation": ["price", "accept"], "offer": ["offer", "pay"],
	"investigation": ["contest", "press_on"], "sale": ["bid", "accept"],
}


## Post the stage's ask on `row` (the stage's last month). The break-up's finding
## is drawn here, with the odds its strip showed; the sale's bid is priced here, at
## the discount the cycle gives now, and that is the price the sale then books.
static func post(ns, loader, row: Dictionary, action, now: int) -> void:
	var stage := String(row["stage"])
	if not STAGE_ASK.has(stage):
		return
	var base := float(row["base_eur_bn"])
	var offsets: Dictionary = action.effects.get("bloc_offset", {})
	var rest := scaled(offsets, 1.0 - K.PROCESS_BLOC_AT_START)
	var answers: Array = []
	match stage:
		"negotiation":
			answers = [_answer("accept", base * (1.0 + float(row["rate"])), rest), _answer("walk", 0.0, uturn(action))]
		"offer":
			answers = [_answer("pay", base * (1.0 + float(row["rate"])), rest),
				_answer("stop", K.PROCESS_BREAK_FEE * base * float(row["rate"]), uturn(action))]
		"investigation":
			row["ruled"] = Cycle.unit("%s|ruling" % String(row["id"]), now) < float(row["odds"])
			if not bool(row["ruled"]):
				return
			var value := Companies.value_eur_bn(ns, _company(ns, loader, String(row["company_id"])))
			answers = [_answer("press_on", 0.0, offsets),
				_answer("settle", -K.PROCESS_SETTLEMENT_FINE * value, scaled(offsets, K.PROCESS_SETTLEMENT_BLOC))]
		"sale":
			row["rate"] = discount(ns)
			# One hold only (pass 1 on #248): the new bid is priced and asks nothing,
			# so the sale ends inside the months its strip showed (A3).
			if bool(row.get("held", false)):
				return
			answers =[_answer("accept", -base * (1.0 - float(row["rate"])), rest), _answer("hold", 0.0, {})]
	row["ask"] = {"kind": String(STAGE_ASK[stage][0]), "posted": now, "due": now + 1,
		"default": String(STAGE_ASK[stage][1]), "answers": answers}


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


## The U-turn: every bloc the verb pleased loses PROCESS_UTURN_SHARE of its offset.
static func uturn(action) -> Dictionary:
	var out := {}
	var offsets: Dictionary = action.effects.get("bloc_offset", {}) if action != null else {}
	for bloc in offsets:
		if float(offsets[bloc]) > 0.0:
			out[bloc] = -K.PROCESS_UTURN_SHARE * float(offsets[bloc])
	return out


static func scaled(offsets: Dictionary, share: float) -> Dictionary:
	var out := {}
	for bloc in offsets:
		out[bloc] = share * float(offsets[bloc])
	return out


static func _answer(id: String, debt_eur_bn: float, bloc_offset: Dictionary) -> Dictionary:
	return {"id": id, "debt_eur_bn": debt_eur_bn, "bloc_offset": bloc_offset}


static func _company(ns, loader, company_id: String):
	for company in Companies.firms_of(loader, ns.id):
		if String(company.id) == company_id:
			return company
	return null
