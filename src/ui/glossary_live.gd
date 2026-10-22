extends RefCounted

## The closed table of live values a glossary entry may name -- V5.1-c, rule L1
## of docs/design/glossary-tooltips.md: a live value is a figure the UI already
## shows (a strip reading, the Economy tab's line, the legislature's cooldown),
## never a NationState field the fog hides. A name outside NAMES is a load error
## (glossary.gd); a name inside it with no reader yet shows no line.
##
## c reads the figures already on screen (the parent's call Q2). The six that need
## a context -- a partner, a firm, a budget line, a tax, a portfolio, a bloc -- and
## the rest wait for V5.1-d, where the 309 prose sites arrive with their context.
##
## dissolution_months_left, not the data's first dissolution_lockout_months: that
## is NationState's CONFIG field (12), and what the player is shown is the months
## LEFT (Dissolution.refusal_reason).

const StripReadings = preload("res://src/ui/strip_readings.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const Credit = preload("res://src/sim/credit.gd")
const Government = preload("res://src/sim/government.gd")
const Num = preload("res://src/ui/num.gd")
const Strings = preload("res://src/ui/strings.gd")

const NAMES: PackedStringArray = [
	"agreements_in_force", "amendment_threshold", "article_49_3_available", "bloc_poll",
	"coalition", "coalition_seats", "corruption_readout", "credit_rating", "credit_yield",
	"debt_pct", "deficit_pct", "dissolution_months_left", "events_waiting",
	"firm_state_share", "gdp", "growth_and_trend", "headline_poll", "held_bill",
	"inflation", "judicial_independence", "measures_in_force", "next_booking",
	"next_division", "office_holders", "open_ious", "open_pledges", "pending_referendum",
	"plants", "portfolio_minister", "press_freedom", "programme_progress",
	"relations_with_partner", "spending_share", "subsidy_bill", "tax_rate",
	"terms_served", "unemployment", "unrest",
]

## The strip reading that already prints the figure: the tooltip shows the same
## text, so the two can never disagree.
const _STRIP := {
	"headline_poll": "approval", "deficit_pct": "deficit", "gdp": "gdp",
	"unemployment": "unemployment", "inflation": "inflation", "unrest": "unrest",
	"programme_progress": "programme", "events_waiting": "desk",
}


## The shown figure for `live`, "" when there is none to show (no reader yet, no
## game, a verb with nothing to say).
static func value(live: String, state, loader) -> String:
	if live.is_empty() or state == null or state.player() == null:
		return ""
	if _STRIP.has(live):
		# A dash is the strip saying "nothing yet" (no programme on a term's first
		# day): on a plate it would read as a value, so the line is left out.
		var text := String(StripReadings.read(_STRIP[live], state, loader)["text"])
		return "" if text == StripReadings.NOTHING else text
	var ns = state.player()
	match live:
		"debt_pct":
			return Strings.t("%s%% of GDP") % Num.f(ns.debt_to_gdp_pct(), 1)
		"credit_yield":
			return "%s%%" % Num.f(Credit.yield_pct(ns), 2)
		"credit_rating":
			return Credit.rating(ns)
		"growth_and_trend":
			return Strings.t("%s%% a year, against a trend of %s%%") % [
				Num.fs(ns.growth_annual_pct, 2), Num.fs(ns.trend_annual_pct, 2)]
		"article_49_3_available":
			# law_panel's force button: the cooldown when there is one, else whether
			# the verb is open at all.
			if ns.force_cooldown_months > 0:
				return Strings.tn("available again in %d month", "available again in %d months",
					ns.force_cooldown_months) % ns.force_cooldown_months
			return Strings.t("available now") if Government.can_force(ns) else ""
		"dissolution_months_left":
			if ns.dissolution_lockout_remaining <= 0:
				return ""
			return Strings.tn("%d month of lockout left", "%d months of lockout left",
				ns.dissolution_lockout_remaining) % ns.dissolution_lockout_remaining
	return ""


## Where the figure comes from, when the fog makes that matter: a poll is not the
## truth ("fog is shown, never silent").
static func source(live: String) -> String:
	if live == "headline_poll" or live == "bloc_poll":
		return Strings.t("a poll, ±%d points") % int(PollNoise.NOISE_MAX_PCT)
	return ""
