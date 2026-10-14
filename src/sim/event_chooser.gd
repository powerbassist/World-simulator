extends RefCounted

## The AI chooser, split out of events.gd (which was past the size the
## architecture rules allow). Behaviour is unchanged; Events._choose became
## EventChooser.choose and Events._score_choice EventChooser.score_choice.

const K = preload("res://src/sim/events_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")


## The AI's desk is the same tick it announced in: score every choice against the
## nation's own position and take the best. Minimal by events-model §5's closure
## note -- approval-seeking on the size-weighted bloc response, a fiscal term
## that prefers balance when the deficit is high, a cleanliness term when
## corruption is high, a concession term when unrest is high -- and the terms
## TRADE, which is the point: a deficit-running government in unrest would prefer the
## concession a balanced one refuses. Deterministic; ties go to content order.
##
## THE BOUND, stated where the chooser is described: EventChooser.choose runs only for AI
## nations, and an AI nation's unrest_pct never ticks (Unrest.tick_month skips a
## nation without has_budget) and its deficit_pct_gdp stays at its authored start (AI
## answers skip the fiscal channels since pass 23, so no event answer recomputes it
## either). So the unrest term is reachable only by a nation whose
## unrest ticks -- for today's AI nations it reads its start value -- and the fiscal
## term reads starting data. The trade-off above is a property of a budgeted nation
## the day AI nations get a budget tick, with no edit here. See docs/someday.md, "The
## AI nations' unrest and deficit registers never tick".
static func choose(ns, ev) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	for choice in ev.choices:
		var score := score_choice(ns, choice)
		if score > best_score:
			best_score = score
			best = choice
	return best


static func score_choice(ns, choice: Dictionary) -> float:
	var effects: Dictionary = choice.get("effects", {})
	var score := 0.0

	var blocs: Dictionary = effects.get("bloc_offset", {})
	var weighted := 0.0
	var weight_sum := 0.0
	for bloc in blocs:
		var size: float = float(OpinionK.BLOC_SIZE.get(bloc, 0.0))
		weighted += size * float(blocs[bloc])
		weight_sum += size
	if weight_sum > 0.0:
		score += weighted / weight_sum

	# Fiscal: a sign-and-size heuristic, not an accounting identity. A tax delta is
	# points of a RATE and a spending delta is a share of GDP, so the two are in
	# different units and the sum below is only a rough "does this push the balance
	# the right way, and how hard" score. The sign is the register's own (a
	# shortfall is POSITIVE -- E0's finding): revenue-raising adds, spending subtracts.
	if float(ns.deficit_pct_gdp) > K.CHOOSER_DEFICIT_FLOOR:
		var balance_delta := 0.0
		for tax_key in effects.get("tax_rates_pct", {}):
			balance_delta += float(effects["tax_rates_pct"][tax_key])
		for spend_key in effects.get("spending_pct_gdp", {}):
			balance_delta -= float(effects["spending_pct_gdp"][spend_key])
		score += balance_delta * K.CHOOSER_FISCAL_WEIGHT

	if float(ns.corruption) > K.CHOOSER_CORRUPTION_FLOOR:
		# Corruption's better direction is unambiguous (E3's fourth axis), so a
		# dirty government still prefers to clean up when the voters can see it.
		score -= float(effects.get("society", {}).get("corruption", 0.0)) * K.CHOOSER_CORRUPTION_WEIGHT

	if float(ns.unrest_pct) > K.CHOOSER_UNREST_FLOOR:
		# A concession is new spending; settlement_stance has no better
		# direction by design (E3's own argument), so the money is the honest
		# proxy for what an unrestful country's government reaches for.
		for spend_key in effects.get("spending_pct_gdp", {}):
			score += float(effects["spending_pct_gdp"][spend_key]) * K.CHOOSER_UNREST_WEIGHT

	return score
